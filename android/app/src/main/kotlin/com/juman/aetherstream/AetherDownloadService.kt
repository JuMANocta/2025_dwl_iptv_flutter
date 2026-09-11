package com.juman.aetherstream

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * §dlNotif — Service de premier plan qui garde le PROCESSUS vivant pendant un
 * téléchargement, et affiche sa progression.
 *
 * **Pourquoi il existe** : le transfert (`DownloadManagerService`, Dio dans
 * l'isolate principal) ne passe par AUCUN `WorkManager` ni wakelock — il
 * dépend entièrement de la survie du processus. Sans ce service, Android le
 * tue dès qu'il récupère de la mémoire, et une notification de progression
 * affichée sans lui mentirait : elle continuerait d'annoncer un pourcentage
 * qui ne bouge plus.
 *
 * ⚠️ **Type `dataSync`, plafonné à 6h/24h depuis Android 15** — [onTimeout]
 * doit arrêter le service, sinon ANR. La reprise par en-tête `Range` (déjà en
 * place côté Dart) encaisse la coupure : ce n'est pas traité comme une panne.
 *
 * ⚠️ **`onTaskRemoved`** : l'utilisateur qui balaie l'app hors des Récents
 * détruit l'`Activity` et son moteur Flutter — le transfert s'arrête avec.
 * Continuer d'afficher « en cours » serait le même mensonge. On s'arrête ;
 * `_reconcileTasksOnStartup` (Dart) rattrape la tâche en `failed` au
 * prochain lancement.
 */
class AetherDownloadService : Service() {

    companion object {
        private const val TAG = "AetherDownloadService"
        private const val CHANNEL_ID = "aether_download"
        private const val ONGOING_NOTIFICATION_ID = 2001
        const val ACTION_CANCEL = "com.juman.aetherstream.action.CANCEL_DOWNLOAD"
        const val EXTRA_TASK_ID = "taskId"

        // Revue 2026-09-11, D2B-10 — Le drapeau `isRunning` était écrit
        // (`onStartCommand`, `onDestroy`) mais JAMAIS lu : son commentaire
        // promettait « éviter de relancer un démarrage à chaque mise à jour »,
        // alors que `start()` appelle `startService` sans condition (un
        // aller-retour IPC par mise à jour, sans danger depuis §fgsSafeStart :
        // la promotion n'a lieu qu'une fois, dans `onCreate`). Retiré.

        fun start(
            context: Context,
            title: String,
            text: String,
            progress: Int,
            indeterminate: Boolean,
            cancelTaskId: String?,
            cancelLabel: String? = null
        ) {
            val intent = Intent(context, AetherDownloadService::class.java).apply {
                putExtra("title", title)
                putExtra("text", text)
                putExtra("progress", progress)
                putExtra("indeterminate", indeterminate)
                putExtra("cancelTaskId", cancelTaskId)
                // Revue 2026-09-11, D3L-02 — libellé du bouton, traduit par Dart.
                putExtra("cancelLabel", cancelLabel)
            }
            try {
                // §fgsSafeStart (2026-09-10) — ⚠️ **`startService`, PAS
                // `startForegroundService`.** Ce dernier arme un compte à
                // rebours de 5 s : si le service n'est pas créé ET promu dans
                // ce délai, Android **tue le processus**
                // (`ForegroundServiceDidNotStartInTimeException`).
                //
                // Le paquet vendoré a payé exactement ce plantage sur Galaxy
                // S25 le 2026-09-05 — son patch 13 le documente — mais le
                // correctif n'avait jamais été reporté ici. La fenêtre est
                // étroite (un transfert qui se termine ou est annulé dans la
                // seconde de son démarrage détruit le service avant sa
                // promotion) et §dlWatchdog la traverse en plein.
                //
                // ⚠️ Il était en plus RÉ-ÉMIS à chaque mise à jour (1×/s) :
                // chacune ré-armait le minuteur alors que le service tournait
                // déjà. La promotion se fait désormais dans `onCreate`, donc
                // dès que l'instance existe.
                @Suppress("DEPRECATION")
                context.startService(intent)
            } catch (e: Exception) {
                // Démarrage refusé depuis l'arrière-plan : le transfert
                // continue, il perd seulement sa notification. C'était déjà le
                // comportement avant — mais par plantage rattrapé, pas par
                // choix.
                AetherLog.w(TAG, "démarrage du service refusé (${e.javaClass.simpleName})")
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AetherDownloadService::class.java))
        }

        /**
         * Notification NON persistante, pour l'annonce ponctuelle de fin de
         * transfert. ⚠️ Fonction de COMPAGNON, pas de méthode d'instance :
         * elle doit pouvoir poster même si le service de premier plan vient
         * de s'arrêter (le dernier téléchargement actif vient de se
         * terminer) — un `NotificationManager` seul suffit, pas besoin de
         * relancer un service pour ça.
         */
        fun postFinished(
            context: Context,
            id: Int,
            title: String,
            success: Boolean,
            text: String? = null
        ) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Revue 2026-09-11, D2B-17 — (re)créé à chaque fois : sur un
                // canal existant, Android met à jour son NOM, qui suit donc la
                // langue de l'appareil (l'importance, elle, ne bouge pas).
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        context.getString(R.string.notif_channel_downloads),
                        NotificationManager.IMPORTANCE_LOW
                    )
                )
            }
            val contentIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val contentPending = PendingIntent.getActivity(
                context, id, contentIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            // D3L-02 — le texte vient de Dart (L10n) ; la ressource n'est que
            // le repli, jamais une notification vide.
            val body = text?.takeIf { it.isNotBlank() }
                ?: context.getString(
                    if (success) R.string.notif_download_finished else R.string.notif_download_failed
                )
            val iconRes = context.resources.getIdentifier("ic_notification", "drawable", context.packageName)
                .let { if (it != 0) it else context.applicationInfo.icon }
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(iconRes)
                .setAutoCancel(true)
                .setContentIntent(contentPending)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()
            nm.notify(id, notification)
        }
    }

    private lateinit var notificationManager: NotificationManager

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannel()
        // §fgsSafeStart — ⚠️ On se déclare dès la CRÉATION, avec une
        // notification de repli s'il le faut. Attendre `onStartCommand`
        // laissait une fenêtre où un `stopService()` détruisait l'instance
        // avant toute promotion : personne n'appelait `startForeground()` et le
        // système tuait le processus.
        promoteToForeground(
            buildNotification(getString(R.string.notif_download_title), "", -1, true, null, null)
        )
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    /// Déclare le service en premier plan. ⚠️ Ne lève jamais : Android 12+ peut
    /// refuser la promotion depuis l'arrière-plan, et on ne doit pas planter
    /// pour ça — le téléchargement continue sans notification.
    private fun promoteToForeground(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    ONGOING_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(ONGOING_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            AetherLog.w(TAG, "startForeground refusé (${e.javaClass.simpleName})")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: getString(R.string.notif_download_title)
        val text = intent?.getStringExtra("text") ?: ""
        val progress = intent?.getIntExtra("progress", -1) ?: -1
        val indeterminate = intent?.getBooleanExtra("indeterminate", false) ?: false
        val cancelTaskId = intent?.getStringExtra("cancelTaskId")
        val cancelLabel = intent?.getStringExtra("cancelLabel")

        val notification =
            buildNotification(title, text, progress, indeterminate, cancelTaskId, cancelLabel)
        // §fgsSafeStart — Déjà promu dans `onCreate` : ici on ne fait que
        // remplacer la notification de repli par la vraie.
        // ⛔ Plus de `stopSelf()` en rattrapage d'échec : se retirer sans
        // s'être déclaré est PRÉCISÉMENT ce qui tue le processus.
        promoteToForeground(notification)
        return START_NOT_STICKY
    }

    // API 35+ (Android 15) : le système retire le droit `dataSync` après 6h
    // cumulées sur 24h et appelle ce callback. On DOIT s'arrêter — l'ignorer
    // produit un ANR, pas une simple perte de notification.
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf(startId)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // Revue 2026-09-11, D2B-17 — plus de retour anticipé si le canal
        // existe : le recréer met à jour son NOM (langue de l'appareil).
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notif_channel_downloads),
            NotificationManager.IMPORTANCE_LOW
        )
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildNotification(
        title: String,
        text: String,
        progress: Int,
        indeterminate: Boolean,
        cancelTaskId: String?,
        cancelLabel: String?
    ): Notification {
        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val contentPending = PendingIntent.getActivity(
            this, 0, contentIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(resolveSmallIconRes())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentPending)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        if (progress in 0..100 || indeterminate) {
            builder.setProgress(100, progress.coerceIn(0, 100), indeterminate)
        }

        // §dlNotif — Un seul bouton, UNIQUEMENT quand il désigne une tâche
        // précise (une seule active) : « Annuler » sur l'agrégat de plusieurs
        // téléchargements n'aurait pas de sens univoque.
        if (cancelTaskId != null) {
            val cancelIntent = Intent(ACTION_CANCEL).apply {
                setPackage(packageName)
                putExtra(EXTRA_TASK_ID, cancelTaskId)
            }
            val cancelPending = PendingIntent.getBroadcast(
                this, cancelTaskId.hashCode(), cancelIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            // D3L-02 — libellé traduit par Dart, repli sur la ressource.
            val label = cancelLabel?.takeIf { it.isNotBlank() }
                ?: getString(R.string.notif_cancel)
            builder.addAction(0, label, cancelPending)
        }

        return builder.build()
    }

    private fun resolveSmallIconRes(): Int {
        val byName = resources.getIdentifier("ic_notification", "drawable", packageName)
        return if (byName != 0) byName else applicationInfo.icon
    }
}
