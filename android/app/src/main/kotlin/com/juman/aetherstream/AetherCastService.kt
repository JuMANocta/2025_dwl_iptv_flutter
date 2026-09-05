package com.juman.aetherstream

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import java.net.HttpURLConnection
import java.net.URL

/**
 * §castSend — Service de premier plan qui garde le PROCESSUS vivant pendant une
 * diffusion Chromecast, et affiche « Diffusion sur <appareil> » avec
 * Pause / Lecture et Arrêter.
 *
 * **Pourquoi il existe** : la session Cast (`CastSession`, Dart pur) est un
 * socket TLS tenu depuis l'isolate principal, avec un battement de cœur toutes
 * les 5 s. Le téléviseur continuerait de lire si Android tuait le processus,
 * mais l'utilisateur perdrait toute commande — et une notification affichée
 * sans service mentirait. Même modèle qu'[AetherDownloadService].
 *
 * **Type `mediaPlayback`** (pas `dataSync`) : c'est une commande de lecture à
 * distance, pas un transfert — et ce type n'est pas plafonné à 6 h/24 h.
 * La permission `FOREGROUND_SERVICE_MEDIA_PLAYBACK` vient du manifeste du
 * paquet vendoré (fusionné), redéclarée explicitement dans le nôtre.
 *
 * ⚠️ **`onTaskRemoved`** : balayer l'app hors des Récents détruit le moteur
 * Flutter et la session avec — le téléviseur continue seul, la notification
 * doit disparaître plutôt que d'annoncer une commande qui n'existe plus.
 *
 * **§castAwake — un service de premier plan ne garde PAS le CPU éveillé.** Il
 * garde le processus : Android ne le tue pas pour récupérer la mémoire. Mais
 * écran éteint, sans verrou, le noyau suspend le téléphone dès que plus rien
 * ne le retient — et avec lui la conversion Media3, le serveur local qui sert
 * le film au téléviseur, et le battement de cœur (5 s) de la session Cast.
 * Constaté le 2026-09-05 : l'écran s'éteint, la diffusion meurt. C'est
 * exactement ce contre quoi ExoPlayer tient `WAKE_MODE_NETWORK` pendant une
 * lecture audio en arrière-plan ; ici la lecture est sur la télé, mais le
 * téléphone est le tuyau. D'où un `PARTIAL_WAKE_LOCK` + un `WifiLock`, pris
 * quand le service démarre et rendus quand il meurt — la durée de vie du
 * service EST celle de la diffusion (`CastNotificationBridge` le suit).
 * Un service de premier plan est justement ce qui rend ces verrous honorés
 * pendant le mode Sommeil (Doze) : ils sont ignorés pour tout processus
 * moins prioritaire.
 */
class AetherCastService : Service() {

    companion object {
        private const val CHANNEL_ID = "aether_cast"
        private const val ONGOING_NOTIFICATION_ID = 2002
        const val ACTION_TOGGLE = "com.juman.aetherstream.action.CAST_TOGGLE"
        const val ACTION_STOP = "com.juman.aetherstream.action.CAST_STOP"

        fun start(
            context: Context,
            title: String,
            text: String,
            playing: Boolean,
            image: String? = null,
            lowBattery: Boolean = false,
        ) {
            val intent = Intent(context, AetherCastService::class.java).apply {
                putExtra("title", title)
                putExtra("text", text)
                putExtra("playing", playing)
                putExtra("image", image)
                putExtra("lowBattery", lowBattery)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AetherCastService::class.java))
        }
    }

    private lateinit var notificationManager: NotificationManager

    /// §castSend — L'affiche du film dans la notification. Chargée une seule
    /// fois par URL, sur un thread, jamais bloquante : sans elle la
    /// notification reste correcte, juste sans image.
    // ⚠️ Écrits par le thread de téléchargement, lus sur le thread principal :
    // sans `@Volatile`, la visibilité n'est pas garantie.
    @Volatile
    private var posterUrl: String? = null

    @Volatile
    private var poster: Bitmap? = null

    /// ⚠️ **Le garde-fou contre une notification que plus rien ne peut
    /// retirer.** `downloadBitmap` attend jusqu'à 8 s ; si la diffusion
    /// s'arrête pendant ce temps, le service est détruit et Android retire
    /// sa notification — puis le thread se réveillait et la REPOSAIT, sans
    /// service pour la porter. Même famille de panne que §dlNotif.
    @Volatile
    private var destroyed = false

    /// §castBattery — Sous 15 %, la notification passe en ROUGE : le
    /// téléphone porte la diffusion, s'il s'éteint tout s'arrête.
    private var lowBattery: Boolean = false

    /// §castAwake — Verrou CPU : sans lui, écran éteint, le téléphone se
    /// suspend et la diffusion avec. Non compté par référence : un seul
    /// `acquire` quel que soit le nombre de mises à jour de la notification,
    /// un seul `release` à la mort du service.
    private var wakeLock: PowerManager.WakeLock? = null

    /// §castAwake — Verrou WiFi. ⚠️ Depuis Android 14, `HIGH_PERF` vaut
    /// `LOW_LATENCY`, qui n'agit qu'app au premier plan et écran allumé : il
    /// ne garantit donc rien écran éteint sur un appareil récent. On le tient
    /// quand même — c'est gratuit, et il aide sur les versions antérieures,
    /// où la radio pouvait ralentir écran éteint. Le verrou qui compte
    /// vraiment est celui du CPU.
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "AetherStream"
        val text = intent?.getStringExtra("text") ?: "Diffusion en cours"
        val playing = intent?.getBooleanExtra("playing", true) ?: true
        val image = intent?.getStringExtra("image")
        lowBattery = intent?.getBooleanExtra("lowBattery", false) ?: false
        maybeLoadPoster(image, title, text, playing)

        val notification = buildNotification(title, text, playing)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    ONGOING_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(ONGOING_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Android 12+ : ForegroundServiceStartNotAllowedException si l'app
            // est en arrière-plan au DÉMARRAGE du service. La diffusion démarre
            // toujours depuis le lecteur (au premier plan) : ce cas ne devrait
            // pas se produire ; s'il arrive, la diffusion continue sans
            // notification, comme §dlNotif.
            stopSelf()
            return START_NOT_STICKY
        }
        // §castAwake — APRÈS `startForeground` : c'est le statut de premier
        // plan qui rend le verrou honoré en mode Sommeil. Idempotent : chaque
        // mise à jour de la notification repasse ici.
        acquireLocks()
        return START_NOT_STICKY
    }

    // ── §castAwake ────────────────────────────────────────────────────────

    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "AetherStream:cast"
                ).apply { setReferenceCounted(false) }
            }
            // ⚠️ Sans délai : une diffusion dure un film entier, et le verrou
            // est rendu par `onDestroy`, dont l'appel est garanti par
            // `stopService` (le pont Dart) comme par `onTaskRemoved`.
            wakeLock?.takeIf { !it.isHeld }?.acquire()
        } catch (e: Exception) {
            // Sans permission ou sans PowerManager : la diffusion tourne quand
            // même, écran allumé. Jamais une exception jusqu'à Dart.
            wakeLock = null
        }
        try {
            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(mode, "AetherStream:cast")
                    .apply { setReferenceCounted(false) }
            }
            wifiLock?.takeIf { !it.isHeld }?.acquire()
        } catch (e: Exception) {
            wifiLock = null
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            // Déjà rendu : rien à faire.
        }
        wakeLock = null
        try {
            wifiLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            // Idem.
        }
        wifiLock = null
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf(startId)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        destroyed = true
        // §castAwake — Le verrou meurt avec le service : diffusion arrêtée,
        // le téléphone a le droit de dormir.
        releaseLocks()
        // Filet : si un thread d'affiche a reposé la notification juste
        // avant, elle n'appartient plus à personne — on l'enlève.
        notificationManager.cancel(ONGOING_NOTIFICATION_ID)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (notificationManager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Diffusion Chromecast",
            NotificationManager.IMPORTANCE_LOW
        )
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, text: String, playing: Boolean): Notification {
        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val contentPending = PendingIntent.getActivity(
            this, 0, contentIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val togglePending = PendingIntent.getBroadcast(
            this, 1,
            Intent(ACTION_TOGGLE).apply { setPackage(packageName) },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stopPending = PendingIntent.getBroadcast(
            this, 2,
            Intent(ACTION_STOP).apply { setPackage(packageName) },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(resolveSmallIconRes())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setContentIntent(contentPending)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, if (playing) "Pause" else "Lecture", togglePending)
            .addAction(0, "Arrêter", stopPending)
        if (lowBattery) {
            // Fond coloré (autorisé pour un service de premier plan média) :
            // l'alerte se voit sans lire le texte.
            builder.setColor(0xFFD32F2F.toInt())
            builder.setColorized(true)
        }
        poster?.let { bmp ->
            builder.setLargeIcon(bmp)
            // Notification dépliée : l'affiche en grand, sans répéter la
            // vignette (`bigLargeIcon(null)`), comme un lecteur média.
            builder.setStyle(
                NotificationCompat.BigPictureStyle()
                    .bigPicture(bmp)
                    .bigLargeIcon(null as Bitmap?)
            )
        }
        return builder.build()
    }

    /// Télécharge l'affiche si son URL a changé, puis repose la notification
    /// avec l'image. Tout échec est silencieux (réseau, format) : la
    /// diffusion n'en dépend pas.
    private fun maybeLoadPoster(
        url: String?,
        title: String,
        text: String,
        playing: Boolean,
    ) {
        if (url.isNullOrBlank()) {
            posterUrl = null
            poster = null
            return
        }
        if (url == posterUrl && poster != null) return
        posterUrl = url
        Thread {
            val bmp = downloadBitmap(url) ?: return@Thread
            // Service détruit pendant le téléchargement, ou nouvelle
            // diffusion entre-temps : on ne repose RIEN.
            if (destroyed || url != posterUrl) return@Thread
            poster = bmp
            try {
                notificationManager.notify(
                    ONGOING_NOTIFICATION_ID,
                    buildNotification(title, text, playing),
                )
            } catch (e: Exception) {
                // Service peut-être déjà arrêté : sans conséquence.
            }
        }.apply { isDaemon = true }.start()
    }

    private fun downloadBitmap(url: String): Bitmap? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000
                readTimeout = 8000
                instanceFollowRedirects = true
            }
            conn.inputStream.use { BitmapFactory.decodeStream(it) }
        } catch (e: Exception) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun resolveSmallIconRes(): Int {
        val byName = resources.getIdentifier("ic_notification", "drawable", packageName)
        return if (byName != 0) byName else applicationInfo.icon
    }
}
