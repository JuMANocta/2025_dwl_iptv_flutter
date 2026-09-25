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

        /**
         * §notifAudit P5 — Canal SÉPARÉ pour la fin de transfert.
         *
         * La notification de fin partageait le canal de progression, en
         * `IMPORTANCE_LOW` : elle arrivait donc muette, sans bandeau, et se
         * perdait dans le tiroir. Or c'est le seul moment où l'utilisateur a
         * quelque chose à apprendre. Un canal à part lui rend un son — et
         * laisse la progression, elle, rester discrète.
         *
         * ⚠️ L'importance d'un canal ne se change QU'À SA CRÉATION : un canal
         * existant garde la sienne (seul son nom se met à jour). D'où un
         * identifiant neuf, et non une importance relevée sur l'ancien.
         */
        private const val DONE_CHANNEL_ID = "aether_download_done"
        private const val ONGOING_NOTIFICATION_ID = 2001
        const val ACTION_CANCEL = "com.juman.aetherstream.action.CANCEL_DOWNLOAD"

        /**
         * §notifAudit P6 — « Relancer » depuis la notification d'échec.
         *
         * ⚠️ Exige d'être reçu côté `MainActivity` (même récepteur que
         * [ACTION_CANCEL], `IntentFilter` à compléter) : sans cela le bouton
         * ne fait rien.
         */
        const val ACTION_RESTART = "com.juman.aetherstream.action.RESTART_DOWNLOAD"
        const val EXTRA_TASK_ID = "taskId"

        /**
         * §notifAudit P5 — Extra posé sur l'`Intent` de lancement : « appuyer
         * pour ouvrir » doit tomber sur l'onglet Téléchargements, pas sur
         * l'accueil. Relayé à Dart par `MainActivity` (`takeOpenRoute` au
         * démarrage à froid, `openRoute` app ouverte), avec [EXTRA_TASK_ID]
         * quand la notification désigne une tâche.
         */
        const val EXTRA_OPEN_ROUTE = "aether_open_route"
        const val ROUTE_DOWNLOADS = "downloads"

        /**
         * R13 — L'instance vivante, s'il y en a une.
         *
         * **Le défaut payé** : [start] appelait `startService` à CHAQUE mise à
         * jour de progression — un aller-retour IPC par seconde et par
         * transfert, plus un `onStartCommand` complet, pour ne changer qu'un
         * texte. Quand le service tourne déjà, `notify()` sur le même
         * identifiant suffit et ne coûte rien.
         *
         * ⚠️ §fgsSafeStart intact : la promotion en premier plan reste dans
         * `onCreate`, ce chemin ne fait que REMPLACER la notification d'un
         * service déjà promu.
         */
        @Volatile
        private var live: AetherDownloadService? = null

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
            // R13 — Service déjà vivant : on remplace la notification sur
            // place, sans repasser par le système.
            live?.let { svc ->
                svc.refresh(title, text, progress, indeterminate, cancelTaskId, cancelLabel)
                return
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
            text: String? = null,
            restartTaskId: String? = null,
            restartLabel: String? = null,
            doneChannelName: String? = null,
            openTaskId: String? = null
        ) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Revue 2026-09-11, D2B-17 — (re)créé à chaque fois : sur un
                // canal existant, Android met à jour son NOM, qui suit donc la
                // langue de l'appareil (l'importance, elle, ne bouge pas).
                // §notifAudit P5 — Canal PROPRE à la fin de transfert, en
                // importance par défaut : c'est le seul moment qui mérite un son.
                nm.createNotificationChannel(
                    NotificationChannel(
                        DONE_CHANNEL_ID,
                        doneChannelName?.takeIf { it.isNotBlank() }
                            ?: context.getString(R.string.notif_channel_downloads),
                        NotificationManager.IMPORTANCE_DEFAULT
                    )
                )
            }
            // §notifAudit P5 — « Appuyer pour ouvrir » visait l'accueil : on
            // demande l'onglet Téléchargements. L'extra est lu par
            // `MainActivity` (cf. EXTRA_OPEN_ROUTE) ; sans lui, l'app s'ouvre
            // simplement comme avant.
            val contentIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra(EXTRA_OPEN_ROUTE, ROUTE_DOWNLOADS)
                // §notifAudit P5 (second volet) — la tâche à montrer.
                openTaskId?.let { putExtra(EXTRA_TASK_ID, it) }
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
            val builder = NotificationCompat.Builder(context, DONE_CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(body)
                // Le nom d'un fichier et la raison d'un échec dépassent une
                // ligne : sans ça, l'essentiel finissait en trois points.
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setSmallIcon(iconRes)
                .setAutoCancel(true)
                .setContentIntent(contentPending)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // §notifAudit P6 — « Relancer », seulement sur un échec et
            // seulement quand la tâche est désignée.
            if (!success && restartTaskId != null && restartLabel != null) {
                val restartIntent = Intent(ACTION_RESTART).apply {
                    setPackage(context.packageName)
                    putExtra(EXTRA_TASK_ID, restartTaskId)
                }
                val restartPending = PendingIntent.getBroadcast(
                    context, restartTaskId.hashCode(), restartIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                builder.addAction(0, restartLabel, restartPending)
            }
            nm.notify(id, builder.build())
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
        // R13 — Publié EN DERNIER : tant que `notificationManager` n'est pas
        // posé et le service pas promu, `refresh()` n'aurait rien sur quoi
        // écrire. Une mise à jour arrivée avant passe par `startService`,
        // comme avant.
        live = this
    }

    override fun onDestroy() {
        // R13 — L'instance meurt : la prochaine mise a jour devra repasser par
        // `startService`, sinon elle ecrirait dans le vide.
        if (live === this) live = null
        super.onDestroy()
    }

    /**
     * R13 — Remplace la notification d'un service DEJA promu, sans IPC.
     *
     * ⚠️ Ne promeut rien et n'arrete rien : §fgsSafeStart veut que la
     * promotion reste dans `onCreate` et qu'aucun chemin ne se retire avant
     * elle. Si la permission de notification est refusee, `notify` ne montre
     * rien — et le service continue de tourner (§notifAudit P3).
     */
    fun refresh(
        title: String,
        text: String,
        progress: Int,
        indeterminate: Boolean,
        cancelTaskId: String?,
        cancelLabel: String?
    ) {
        try {
            notificationManager.notify(
                ONGOING_NOTIFICATION_ID,
                buildNotification(title, text, progress, indeterminate, cancelTaskId, cancelLabel)
            )
        } catch (e: Exception) {
            AetherLog.w(TAG, "mise a jour de la notification refusee (" + e.javaClass.simpleName + ")")
        }
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
        // §notifAudit P5 — un transfert en cours s'ouvre lui aussi sur l'onglet
        // Téléchargements.
        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra(EXTRA_OPEN_ROUTE, ROUTE_DOWNLOADS)
        }
        // ⚠️ Code de requête PROPRE (pas 0) : les extras ne comptent pas dans
        // l'identité d'un `PendingIntent`. Sur le code 0, partagé avec les
        // notifications de lecture et de diffusion (même Intent de
        // lancement), `FLAG_UPDATE_CURRENT` leur aurait collé la route : les
        // toucher aurait ouvert l'onglet Téléchargements.
        val contentPending = PendingIntent.getActivity(
            this, ONGOING_NOTIFICATION_ID, contentIntent,
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
