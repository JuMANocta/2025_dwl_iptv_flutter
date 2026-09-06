package com.huddlecommunity.better_native_video_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service that backs background video playback.
 *
 * Streaming (live + VOD) needs the app to keep network access while the screen
 * is off. A plain posted notification does NOT grant that — only a *running
 * foreground service* exempts the app from Android's Doze / app-standby
 * background-network restrictions. Without it the OS cuts the app's network
 * after a few minutes in the background and ExoPlayer fails with
 * `UnknownHostException (no network)`.
 *
 * The service runs (showing the media notification) only while the player is
 * actually playing, and is stopped on pause/stop. [VideoPlayerNotificationHandler]
 * drives [start]/[stop]; the notification itself is built there so its
 * appearance is unchanged.
 *
 * NOTE: this was previously a (never-started, never-given-a-session) Media3
 * MediaSessionService. It is now a plain foreground Service. The lock-screen
 * MediaSession lives independently in [VideoPlayerNotificationHandler].
 */
class VideoPlayerMediaSessionService : Service() {

    companion object {
        private const val TAG = "VideoPlayerMSS"

        // Must match VideoPlayerNotificationHandler.NOTIFICATION_ID so the
        // foreground notification and the handler's notify()/cancel() updates
        // operate on a single notification entry.
        const val NOTIFICATION_ID = 1001

        // Doit correspondre au canal de VideoPlayerNotificationHandler.
        private const val CHANNEL_ID = "video_player_channel"

        // The notification to promote to foreground with. Set just before the
        // service is started; same process, so a static handoff is safe.
        @Volatile
        private var pendingNotification: Notification? = null

        // false on pause (detach: keep the notification so the user can resume);
        // true on stop/idle/dispose (remove it).
        @Volatile
        private var removeNotificationOnStop: Boolean = true

        @Volatile
        private var isRunning: Boolean = false

        /**
         * Promotes playback to a foreground service showing [notification].
         * Safe to call repeatedly: while already running it just refreshes the
         * notification (e.g. when artwork finishes loading) instead of re-issuing
         * startForegroundService — which Android 12+ forbids from the background.
         */
        fun start(context: Context, notification: Notification) {
            pendingNotification = notification
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (isRunning) {
                nm.notify(NOTIFICATION_ID, notification)
                return
            }
            val intent = Intent(context, VideoPlayerMediaSessionService::class.java)
            try {
                // ⚠️ **`startService`, PAS `startForegroundService`.** Ce dernier
                // arme un compte à rebours de 5 s : si le service n'est pas créé
                // ET promu dans ce délai, Android **tue le processus**. Mesuré
                // sur Galaxy S25 le 2026-09-05 pendant une conversion Cast : le
                // service mettait **4,95 s** à être créé — le téléphone était
                // occupé à convertir un film — et l'app mourait sur
                // `ForegroundServiceDidNotStartInTimeException`, alors même
                // qu'elle appelait bien `startForeground()`.
                //
                // `startService` n'impose aucun délai ; la promotion en premier
                // plan se fait quand même dans `onCreate`. Contrepartie assumée :
                // Android 8+ le refuse depuis l'arrière-plan — on retombe alors
                // sur la notification simple, exactement comme avant.
                @Suppress("DEPRECATION")
                context.startService(intent)
            } catch (e: Exception) {
                // Démarrage refusé depuis l'arrière-plan (Android 8+ pour
                // `startService`, 12+ pour les services de premier plan) : on
                // retombe sur une notification simple plutôt que de planter. Le
                // réseau en arrière-plan peut rester bridé jusqu'à la prochaine
                // lecture au premier plan, mais la lecture en cours garde sa
                // notification.
                NpLog.w(TAG, "FGS start refused (${e.javaClass.simpleName}); posting notification only")
                nm.notify(NOTIFICATION_ID, notification)
            }
        }

        /**
         * Stops the foreground service. [removeNotification] = false detaches the
         * notification (keeps it visible, for resume on pause); true removes it.
         */
        fun stop(context: Context, removeNotification: Boolean) {
            removeNotificationOnStop = removeNotification
            context.stopService(Intent(context, VideoPlayerMediaSessionService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * §engineVendor patch 13 — ⚠️ **On se déclare dès la CRÉATION, pas à la
     * première commande.** Android arme son compte à rebours de 5 s au moment
     * du `startForegroundService()` ; entre cet instant et la première
     * `onStartCommand`, le service peut être détruit par un `stopService()`
     * (l'utilisateur quitte le lecteur et en relance un). Personne n'appelle
     * alors `startForeground()` et le système **tue le processus**.
     *
     * Constaté sur Galaxy S25 (Android 16) le 2026-09-05 : le service traçait
     * pourtant « started » puis « stopped » — la déclaration existait, mais
     * pour une AUTRE demande que celle dont le minuteur expirait. Se déclarer
     * dans `onCreate` referme la fenêtre : dès que l'instance existe, le
     * contrat est honoré.
     */
    override fun onCreate() {
        super.onCreate()
        promoteToForeground(pendingNotification ?: placeholderNotification())
    }

    private fun promoteToForeground(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Android 12+ peut refuser la promotion depuis l'arrière-plan. On
            // ne relance pas : la lecture continue, sans service.
            NpLog.w(TAG, "startForeground refusé (${e.javaClass.simpleName})")
        }
    }

    /**
     * §engineVendor patch 13 — ⚠️ **`stopSelf()` NE SATISFAIT PAS le contrat de
     * `startForegroundService()`.** L'ancien code sortait par `stopSelf()` quand
     * il n'avait pas de notification à montrer, en pensant « sortir proprement ».
     * Android exige que `startForeground()` soit appelé dans les ~5 s, sinon il
     * TUE LE PROCESSUS — ce qui s'est produit le 2026-09-05 : quitter le lecteur
     * puis en relancer un provoquait
     * `ForegroundServiceDidNotStartInTimeException`, plantage complet de l'app,
     * exactement 5 s après le démarrage du service.
     *
     * On se déclare donc TOUJOURS d'abord, quitte à utiliser une notification
     * de repli, et on ne se retire qu'après. La même règle couvre la course
     * `stop()` arrivant avant `onStartCommand`.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val pending = pendingNotification
        // Déjà promu dans `onCreate` ; ici on ne fait que rafraîchir avec la
        // vraie notification si elle est arrivée entre-temps.
        promoteToForeground(pending ?: placeholderNotification())

        if (pending == null) {
            // Rien à afficher : on s'est déclaré (obligatoire), on se retire
            // aussitôt et on efface la notification de repli.
            NpLog.w(TAG, "onStartCommand sans notification ; arrêt après déclaration")
            removeNotificationOnStop = true
            stopSelf()
            return START_NOT_STICKY
        }

        isRunning = true
        NpLog.d(TAG, "Foreground service started (playback)")
        // Not sticky: a system-killed service should not auto-restart with a
        // stale notification; playback recreation is driven from Dart.
        return START_NOT_STICKY
    }

    /**
     * Notification minimale, jamais vue par l'utilisateur : elle n'existe que
     * pour honorer le contrat d'Android le temps de se retirer.
     */
    private fun placeholderNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            nm.getNotificationChannel(CHANNEL_ID) == null
        ) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Video Player",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
        val icon = resources.getIdentifier("ic_notification", "drawable", packageName)
            .takeIf { it != 0 } ?: applicationInfo.icon
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder.setSmallIcon(icon).build()
    }

    override fun onDestroy() {
        val flags = if (removeNotificationOnStop) {
            Service.STOP_FOREGROUND_REMOVE
        } else {
            Service.STOP_FOREGROUND_DETACH
        }
        stopForeground(flags)
        isRunning = false
        NpLog.d(TAG, "Foreground service stopped (removeNotification=$removeNotificationOnStop)")
        super.onDestroy()
    }
}
