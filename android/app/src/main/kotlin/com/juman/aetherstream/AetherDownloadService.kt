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
        private const val CHANNEL_ID = "aether_download"
        private const val ONGOING_NOTIFICATION_ID = 2001
        const val ACTION_CANCEL = "com.juman.aetherstream.action.CANCEL_DOWNLOAD"
        const val EXTRA_TASK_ID = "taskId"

        fun start(
            context: Context,
            title: String,
            text: String,
            progress: Int,
            indeterminate: Boolean,
            cancelTaskId: String?
        ) {
            val intent = Intent(context, AetherDownloadService::class.java).apply {
                putExtra("title", title)
                putExtra("text", text)
                putExtra("progress", progress)
                putExtra("indeterminate", indeterminate)
                putExtra("cancelTaskId", cancelTaskId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
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
        fun postFinished(context: Context, id: Int, title: String, success: Boolean) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                nm.getNotificationChannel(CHANNEL_ID) == null
            ) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Téléchargements", NotificationManager.IMPORTANCE_LOW)
                )
            }
            val contentIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            }
            val contentPending = PendingIntent.getActivity(
                context, id, contentIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val text = if (success) "Téléchargement terminé — appuyer pour ouvrir" else "Échec du téléchargement"
            val iconRes = context.resources.getIdentifier("ic_notification", "drawable", context.packageName)
                .let { if (it != 0) it else context.applicationInfo.icon }
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
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
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Téléchargement"
        val text = intent?.getStringExtra("text") ?: ""
        val progress = intent?.getIntExtra("progress", -1) ?: -1
        val indeterminate = intent?.getBooleanExtra("indeterminate", false) ?: false
        val cancelTaskId = intent?.getStringExtra("cancelTaskId")

        val notification = buildNotification(title, text, progress, indeterminate, cancelTaskId)
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
            // Android 12+ : ForegroundServiceStartNotAllowedException si l'app
            // était déjà en arrière-plan au moment du DÉMARRAGE du service (le
            // watchdog §dlWatchdog relance un transfert pendant que l'app est
            // en fond, par exemple). Rien à récupérer côté service : la
            // notification ne s'affiche pas cette fois, le téléchargement lui-
            // même continue tant que le processus n'est pas tué.
            stopSelf()
        }
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
        if (notificationManager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Téléchargements",
            NotificationManager.IMPORTANCE_LOW
        )
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildNotification(
        title: String,
        text: String,
        progress: Int,
        indeterminate: Boolean,
        cancelTaskId: String?
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
            builder.addAction(0, "Annuler", cancelPending)
        }

        return builder.build()
    }

    private fun resolveSmallIconRes(): Int {
        val byName = resources.getIdentifier("ic_notification", "drawable", packageName)
        return if (byName != 0) byName else applicationInfo.icon
    }
}
