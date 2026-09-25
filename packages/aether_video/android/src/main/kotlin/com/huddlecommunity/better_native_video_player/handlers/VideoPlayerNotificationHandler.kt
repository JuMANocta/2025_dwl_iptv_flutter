package com.huddlecommunity.better_native_video_player.handlers

import com.huddlecommunity.better_native_video_player.NpLog
import com.huddlecommunity.better_native_video_player.VideoPlayerMediaSessionService

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import androidx.media3.common.MediaMetadata
// §engineVendor patch 10 — style media OFFICIEL de Media3 (cf. buildNotification).
import androidx.media3.session.MediaStyleNotificationHelper
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionToken
// AetherStream patch 29 (§notifAudit P8) — boutons ±30 s et épisode suivant.
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionCommands
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL

/**
 * Handles MediaSession and notification controls for lock screen and notification area
 * Equivalent to iOS VideoPlayerNowPlayingHandler
 */
class VideoPlayerNotificationHandler(
    private val context: Context,
    private val player: ExoPlayer,
    private var eventHandler: VideoPlayerEventHandler
) {
    companion object {
        private const val TAG = "VideoPlayerNotification"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "video_player_channel"
        private var sessionCounter = 0

        /** Patch 18 — délai de connexion ET de lecture de l'affiche. */
        private const val ARTWORK_TIMEOUT_MS = 8000

        /** Patch 18 — côté visé au décodage : une icône, pas un poster. */
        private const val ARTWORK_TARGET_PX = 512

        /** Patch 30 (§notifAudit P10) — redirections suivies à la main (HTTP
         *  ↔ HTTPS compris, que `HttpURLConnection` refuse de franchir seul). */
        private const val ARTWORK_MAX_REDIRECTS = 4

        // ── AetherStream patch 29 (§notifAudit P8) ───────────────────────────
        /** Boutons signalés à Dart (événement `mediaAction`) : l'APP décide
         *  (diffusion en cours, épisode suivant, amnistie des blocages). */
        const val ACTION_SEEK_BACK = "seekBack"
        const val ACTION_SEEK_FORWARD = "seekForward"
        const val ACTION_PLAY_PAUSE = "playPause"
        const val ACTION_NEXT = "next"
        private val ACTIONS = listOf(ACTION_SEEK_BACK, ACTION_PLAY_PAUSE, ACTION_SEEK_FORWARD, ACTION_NEXT)

        /** Commandes de session : lecteur média du système et écran
         *  verrouillé (Android 13+, qui ne lisent plus les boutons de la
         *  notification mais l'état de la session). */
        private const val CUSTOM_SEEK_BACK = "aether.media.SEEK_BACK"
        private const val CUSTOM_SEEK_FORWARD = "aether.media.SEEK_FORWARD"
        private const val CUSTOM_NEXT = "aether.media.NEXT"

        /** Clés des libellés envoyés par Dart (`setMediaActions`). */
        private const val LABEL_SEEK_BACK = "seekBack"
        private const val LABEL_SEEK_FORWARD = "seekForward"
        private const val LABEL_NEXT = "next"
        private const val LABEL_PLAY = "play"
        private const val LABEL_PAUSE = "pause"

        /**
         * Clé de connexion par laquelle Media3 reconnaît le contrôleur de SA
         * notification (`MediaNotificationManager.KEY_MEDIA_NOTIFICATION_MANAGER`,
         * privée). ⚠️ C'est ce contrôleur, et lui seul, qui fixe les commandes
         * que la session du SYSTÈME expose : sans lui, les boutons de session
         * n'apparaissent nulle part (vérifié dans le code de media3-session
         * 1.5.0, `MediaSessionImpl.onConnectOnHandler`). À revérifier à chaque
         * montée de version de Media3.
         */
        private const val KEY_MEDIA_NOTIFICATION_MANAGER =
            "androidx.media3.session.MediaNotificationManager"

        /** Diffusions des boutons de la NOTIFICATION (avant Android 13). */
        private const val BROADCAST_INFIX = ".aether_media."
    }

    /**
     * Patch 29 — Ce que l'app demande en plus de lecture/pause : les sauts
     * (montrés seulement si le flux se laisse parcourir) et l'épisode suivant,
     * avec leurs libellés dans la langue de l'app. ⚠️ Gardé à la libération
     * de la session : c'est une intention de l'app, pas un état de lecture —
     * une vue recréée pour le même contrôleur retrouve les mêmes boutons.
     */
    private data class MediaActions(
        val seek: Boolean = false,
        val next: Boolean = false,
        // AetherStream patch 31 — touches « suivant / précédent » d'un casque,
        // d'une montre ou d'une voiture = ±30 s (décision utilisateur).
        val seekKeys: Boolean = false,
        val labels: Map<String, String> = emptyMap()
    )

    private var mediaActions = MediaActions()

    /** Patch 29 — contrôleur « de notification » (cf. KEY_MEDIA_NOTIFICATION_MANAGER). */
    private var notificationControllerFuture: ListenableFuture<MediaController>? = null

    /** Patch 29 — récepteur des boutons de la notification. */
    private var actionReceiver: BroadcastReceiver? = null

    /** Patch 29 — la notification est-elle affichée (pour la reposer quand
     *  les boutons changent, sans jamais la faire réapparaître) ? */
    private var notificationPosted = false

    /** Patch 29 — dernier état « parcourable » vu, pour ne rafraîchir les
     *  boutons que quand il change. */
    private var lastSeekable: Boolean? = null

    /**
     * Patch 29 — Rappels de la session. Les commandes maison (±30 s, épisode
     * suivant) sont ouvertes à tous les contrôleurs ; le contrôleur de
     * notification reçoit en plus les boutons et les commandes du lecteur que
     * le système doit afficher.
     */
    private val sessionCallback = object : MediaSession.Callback {
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            val builder = MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                .setAvailableSessionCommands(sessionCommands())
            if (session.isMediaNotificationController(controller)) {
                builder.setAvailablePlayerCommands(platformPlayerCommands())
                    .setMediaButtonPreferences(mediaButtons())
            }
            return builder.build()
        }

        // Connecté : l'état de la session du système est reposé TOUT DE SUITE
        // (Media3 ne le fait qu'au prochain événement du lecteur).
        override fun onPostConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ) {
            if (session.isMediaNotificationController(controller)) refreshMediaButtons()
        }

        /**
         * AetherStream patch 31 — Touches « suivant / précédent » d'un casque,
         * d'une montre, d'un autoradio (événements `MEDIA_BUTTON` remis à la
         * session) : ±30 s, signalés à l'app comme les boutons de la
         * notification. Décision utilisateur (2026-09-25) : partout sauf en
         * direct — c'est l'app qui en décide (`seekKeys`).
         *
         * ⚠️ Sans ce rappel, depuis le patch 29, Media3 les confie au
         * contrôleur de notification (`MediaSessionImpl.applyMediaButtonKeyEvent`),
         * à qui « précédent / suivant » d'ExoPlayer sont retirés : elles ne
         * faisaient plus rien. Les rendre à ExoPlayer ramènerait « précédent »
         * = retour au début du film.
         *
         * Media3 ne passe ici que les appuis (`ACTION_DOWN`) ; une répétition
         * (touche maintenue) est absorbée sans relancer un saut.
         */
        override fun onMediaButtonEvent(
            session: MediaSession,
            controllerInfo: MediaSession.ControllerInfo,
            intent: Intent
        ): Boolean {
            if (!mediaActions.seekKeys) return false
            val event = mediaKeyEventOf(intent) ?: return false
            val action = seekActionForKey(event.keyCode) ?: return false
            if (event.repeatCount == 0) dispatchMediaAction(action)
            return true
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle
        ): ListenableFuture<SessionResult> {
            val action = when (customCommand.customAction) {
                CUSTOM_SEEK_BACK -> ACTION_SEEK_BACK
                CUSTOM_SEEK_FORWARD -> ACTION_SEEK_FORWARD
                CUSTOM_NEXT -> ACTION_NEXT
                else -> null
            } ?: return Futures.immediateFuture(
                SessionResult(SessionResult.RESULT_ERROR_NOT_SUPPORTED)
            )
            dispatchMediaAction(action)
            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
        }
    }

    /** Patch 18 — téléchargement d'affiche en cours, annulable. */
    private var artworkJob: Job? = null

    /**
     * The status-bar small icon must be a flat, alpha-only drawable — Android tints it, so a
     * full-color launcher icon renders as a solid white square. Prefer a dedicated
     * notification icon from the host app and only fall back to the launcher icon when none
     * is provided:
     * 1. a drawable named `ic_notification` in the host app,
     * 2. the FCM default notification icon meta-data (most apps with push already set it),
     * 3. the launcher icon (previous behavior).
     */
    private fun resolveSmallIconRes(): Int {
        val byName = context.resources.getIdentifier("ic_notification", "drawable", context.packageName)
        if (byName != 0) {
            return byName
        }

        try {
            val appInfo = context.packageManager.getApplicationInfo(
                context.packageName,
                PackageManager.GET_META_DATA
            )
            val fcmIcon = appInfo.metaData
                ?.getInt("com.google.firebase.messaging.default_notification_icon", 0) ?: 0
            if (fcmIcon != 0) {
                return fcmIcon
            }
        } catch (e: Exception) {
            NpLog.w(TAG, "Could not read notification icon meta-data: ${e.message}")
        }

        return context.applicationInfo.icon
    }

    private var mediaSession: MediaSession? = null
    private val handler = Handler(Looper.getMainLooper())
    private val notificationManager: NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private var currentArtwork: Bitmap? = null
    private var currentArtworkUrl: String? = null // Track which artwork we're currently loading

    // Store current metadata separately to avoid reading stale data from player
    private var currentTitle: String = "Video"
    private var currentSubtitle: String = ""

    init {
        createNotificationChannel()
    }

    private val playerListener = object : Player.Listener {
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (playWhenReady) {
                // showNotification() promotes playback to a foreground service so
                // the OS keeps the app's network alive for background streaming.
                showNotification()
                eventHandler.sendEvent("play")
            } else {
                // Pause: drop foreground status (we're no longer streaming) but
                // keep the notification posted so the user can resume.
                VideoPlayerMediaSessionService.stop(context, removeNotification = false)
                updateNotification()
                eventHandler.sendEvent("pause")
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_ENDED, Player.STATE_IDLE -> {
                    VideoPlayerMediaSessionService.stop(context, removeNotification = true)
                    hideNotification()
                }
                Player.STATE_READY -> if (player.playWhenReady) showNotification()
            }
        }

        // Patch 29 — un flux devenu (non) parcourable : les sauts suivent. Un
        // direct n'a jamais ±30 s, même si l'app les demande.
        override fun onAvailableCommandsChanged(availableCommands: Player.Commands) {
            val seekable = availableCommands.contains(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)
            if (seekable == lastSeekable) return
            lastSeekable = seekable
            if (!mediaActions.seek) return
            refreshMediaButtons()
            repostNotification()
        }
    }

    /**
     * Creates notification channel for Android O+
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // AetherStream patch 21 (revue 2026-09-11, D2B-17) — nom et
            // description du canal lus dans les ressources de l'APP, PAR LEUR
            // NOM (la brique ne connaît pas la classe R de l'app), traduits
            // fr/en. Repli sur les libellés d'origine si la ressource manque.
            val nameId = context.resources.getIdentifier(
                "notif_channel_playback", "string", context.packageName)
            val descId = context.resources.getIdentifier(
                "notif_channel_playback_desc", "string", context.packageName)
            val channel = NotificationChannel(
                CHANNEL_ID,
                if (nameId != 0) context.getString(nameId) else "Video Player",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description =
                    if (descId != 0) context.getString(descId) else "Media playback controls"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
            NpLog.d(TAG, "Notification channel created")
        }
    }

    /**
     * Updates the event handler (needed when shared NotificationHandler is reused by new VideoPlayerView)
     */
    fun updateEventHandler(newEventHandler: VideoPlayerEventHandler) {
        eventHandler = newEventHandler
        NpLog.d(TAG, "Event handler updated for shared notification handler")
    }

    /**
     * Updates the player's current MediaItem metadata (title, artist, album)
     * This is essential for MediaSession to display correct info in notification
     */
    private fun updatePlayerMediaItemMetadata(mediaInfo: Map<String, Any>?) {
        if (mediaInfo == null) return

        val currentItem = player.currentMediaItem ?: return

        // Build new metadata from mediaInfo
        val metadataBuilder = MediaMetadata.Builder()
        (mediaInfo["title"] as? String)?.let { metadataBuilder.setTitle(it) }
        (mediaInfo["subtitle"] as? String)?.let { metadataBuilder.setArtist(it) }
        (mediaInfo["album"] as? String)?.let { metadataBuilder.setAlbumTitle(it) }

        // Create updated MediaItem with new metadata
        val updatedItem = currentItem.buildUpon()
            .setMediaMetadata(metadataBuilder.build())
            .build()

        // Replace the MediaItem without interrupting playback
        val wasPlaying = player.isPlaying
        val position = player.currentPosition
        player.replaceMediaItem(player.currentMediaItemIndex, updatedItem)
        player.seekTo(position)
        if (wasPlaying) player.play()

        NpLog.d(TAG, "Updated player MediaItem metadata - title: ${mediaInfo["title"]}, subtitle: ${mediaInfo["subtitle"]}")
    }

    /**
     * Sets up MediaSession with metadata (title, subtitle, artwork)
     * Similar to iOS MPNowPlayingInfoCenter - shows on lock screen when playing
     * MediaSession automatically provides lock screen controls and system media notification
     */
    fun setupMediaSession(mediaInfo: Map<String, Any>?) {
        // Extract metadata from the provided info
        val newTitle = (mediaInfo?.get("title") as? String) ?: "Video"
        val newSubtitle = (mediaInfo?.get("subtitle") as? String) ?: ""

        // Check if media info has actually changed to avoid unnecessary updates
        val mediaInfoChanged = (newTitle != currentTitle || newSubtitle != currentSubtitle)

        // Store the new metadata
        currentTitle = newTitle
        currentSubtitle = newSubtitle
        NpLog.d(TAG, "📱 Media info - title: $currentTitle, subtitle: $currentSubtitle, changed: $mediaInfoChanged")

        // If MediaSession already exists, only update if media info changed
        if (mediaSession != null) {
            // Only update MediaItem if the info actually changed to avoid playback interruptions
            if (mediaInfoChanged) {
                NpLog.d(TAG, "📱 MediaSession exists - media info changed, updating metadata")
                currentArtwork = null // Clear old artwork
                currentArtworkUrl = null // Clear artwork URL to ignore pending loads

                // Update the player's MediaItem with the new metadata
                updatePlayerMediaItemMetadata(mediaInfo)

                // Load new artwork asynchronously
                mediaInfo?.let { info ->
                    updateMediaMetadata(info)
                }

                // Update notification with new info
                handler.post {
                    if (player.playWhenReady) {
                        updateNotification()
                        NpLog.d(TAG, "✅ Notification updated with new media info")
                    }
                }
            } else {
                NpLog.d(TAG, "📱 MediaSession exists - media info unchanged, skipping update to avoid interruption")
            }
            return
        }

        // Create pending intent to launch app when notification is clicked
        val packageManager = context.packageManager
        val intent = packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        } ?: Intent()
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Create MediaSession with unique session ID and activity (opens app when notification is tapped)
        val sessionId = "huddle_video_player_${++sessionCounter}"
        val session = MediaSession.Builder(context, player)
            .setId(sessionId)
            .setSessionActivity(pendingIntent)
            // Patch 29 — ±30 s et épisode suivant.
            .setCallback(sessionCallback)
            .build()
        mediaSession = session

        // Add listener to track play/pause events
        player.addListener(playerListener)

        // Patch 29 — le contrôleur qui fait apparaître les boutons de session,
        // et le récepteur des boutons de la notification.
        lastSeekable = player.isCommandAvailable(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)
        connectNotificationController(session)
        registerActionReceiver()

        NpLog.d(TAG, "MediaSession created - lock screen and notification controls active")

        // Set metadata on the player's MediaItem first (for MediaSession to use)
        mediaInfo?.let { info ->
            updatePlayerMediaItemMetadata(info)
            NpLog.d(TAG, "Initial MediaItem metadata set for new MediaSession")
        }

        // Load artwork asynchronously if provided
        mediaInfo?.let { info ->
            updateMediaMetadata(info)
        }
        // Patch 20 (revue 2026-09-11, D2B-09) — plus de « mise à jour de
        // position » périodique : son Runnable ne faisait que se re-poster
        // chaque seconde (MediaSession publie la position d'ExoPlayer seule),
        // soit un réveil du looper principal par seconde pour rien.
    }

    /**
     * Shows or updates the media notification
     */
    private fun showNotification() {
        try {
            val notification = buildNotification()
            if (player.playWhenReady) {
                // While playing, the notification must back a foreground service
                // so the OS keeps network access for background streaming. The
                // service refreshes the same NOTIFICATION_ID, so appearance and
                // later notify()-based updates (artwork) are unchanged.
                VideoPlayerMediaSessionService.start(context, notification)
            } else {
                notificationManager.notify(NOTIFICATION_ID, notification)
            }
            notificationPosted = true // patch 29
            NpLog.d(TAG, "Notification shown/updated (playing=${player.playWhenReady})")
        } catch (e: Exception) {
            NpLog.e(TAG, "Error showing notification: ${e.message}", e)
        }
    }

    /**
     * Updates the existing notification
     */
    private fun updateNotification() {
        showNotification()
    }

    /**
     * Hides the notification
     */
    private fun hideNotification() {
        notificationPosted = false // patch 29
        notificationManager.cancel(NOTIFICATION_ID)
        NpLog.d(TAG, "Notification hidden")
    }

    /**
     * Builds the media notification
     */
    private fun buildNotification(): Notification {
        val session = mediaSession ?: throw IllegalStateException("MediaSession not initialized")

        // Read metadata from the player's current MediaItem (source of truth for MediaSession)
        // This ensures the notification always shows what the MediaSession is actually playing
        val mediaMetadata = player.currentMediaItem?.mediaMetadata
        val title = mediaMetadata?.title?.toString() ?: currentTitle
        val artist = mediaMetadata?.artist?.toString() ?: currentSubtitle

        // Create pending intent for the notification
        val packageManager = context.packageManager
        val intent = packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        } ?: Intent()
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        NpLog.d(TAG, "Building notification - title: $title, subtitle: $artist (from player: ${mediaMetadata != null})")

        val iconResId = resolveSmallIconRes()

        // §engineVendor patch 10 — Le jeton de session ne se convertit PLUS par
        // reflexion. Amont : `getSessionCompatToken()` invoque par reflexion, puis
        // `as? android.support.v4.media.session.MediaSessionCompat.Token`. Or
        // depuis Media3 1.4 la methode rend un
        // `androidx.media3.session.legacy.MediaSessionCompat.Token` : le cast
        // rendait `null` SANS exception, le repli « notification sans jeton »
        // etait pris en silence, et la notification n'avait AUCUN bouton ni
        // aucune commande depuis l'ecran verrouille. Mesure sur l'AVD
        // telephone : `dumpsys notification` sans extra `android.mediaSession`,
        // `dumpsys media_session` avec « Media button session is null ».
        // La voie officielle prend la MediaSession Media3 directement.

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(artist)
            .setSmallIcon(iconResId)
            .setLargeIcon(currentArtwork)
            .setContentIntent(contentIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)

        // §engineVendor patch 10 — Style media relie a la session : c'est lui qui
        // donne les boutons (lecture/pause) et fait apparaitre la notification
        // dans le lecteur media du systeme et sur l'ecran verrouille.
        val style = MediaStyleNotificationHelper.MediaStyle(session)

        // AetherStream patch 29 (§notifAudit P8) — Boutons de la NOTIFICATION.
        // Android 13+ les ignore pour une notification média (il lit ceux de
        // la session, cf. mediaButtons) ; avant, ce sont les SEULS : la
        // notification n'en avait aucun, pas même lecture/pause. Ordre :
        // −30 s · lecture/pause · +30 s (vue compacte), puis épisode suivant.
        val compact = ArrayList<Int>(3)
        val seek = seekOffered()
        if (seek) {
            builder.addAction(
                CommandButton.getIconResIdForIconConstant(CommandButton.ICON_SKIP_BACK_30),
                label(LABEL_SEEK_BACK), actionIntent(ACTION_SEEK_BACK, 2901)
            )
            compact.add(compact.size)
        }
        val playing = player.playWhenReady
        builder.addAction(
            CommandButton.getIconResIdForIconConstant(
                if (playing) CommandButton.ICON_PAUSE else CommandButton.ICON_PLAY
            ),
            label(if (playing) LABEL_PAUSE else LABEL_PLAY),
            actionIntent(ACTION_PLAY_PAUSE, 2902)
        )
        compact.add(compact.size)
        if (seek) {
            builder.addAction(
                CommandButton.getIconResIdForIconConstant(CommandButton.ICON_SKIP_FORWARD_30),
                label(LABEL_SEEK_FORWARD), actionIntent(ACTION_SEEK_FORWARD, 2903)
            )
            compact.add(compact.size)
        }
        if (mediaActions.next) {
            builder.addAction(
                CommandButton.getIconResIdForIconConstant(CommandButton.ICON_NEXT),
                label(LABEL_NEXT), actionIntent(ACTION_NEXT, 2904)
            )
        }
        style.setShowActionsInCompactView(*compact.toIntArray())
        builder.setStyle(style)

        return builder.build()
    }

    /**
     * AetherStream patch 29 (§notifAudit P8) — L'app (Dart) demande les
     * boutons en plus de lecture/pause : [seek] (±30 s) et [next] (épisode
     * suivant), avec leurs libellés. Appliqué tout de suite à la session et à
     * la notification si elles existent, sinon à leur création.
     */
    fun setMediaActions(
        seek: Boolean,
        next: Boolean,
        labels: Map<String, String>,
        seekKeys: Boolean = false
    ) {
        val updated = MediaActions(seek, next, seekKeys, labels)
        if (updated == mediaActions) return
        mediaActions = updated
        NpLog.d(TAG, "Boutons de notification : sauts=$seek, suivant=$next, touches=$seekKeys")
        refreshMediaButtons()
        repostNotification()
    }

    /** Patch 31 — L'événement clavier d'un `MEDIA_BUTTON`, s'il y en a un. */
    private fun mediaKeyEventOf(intent: Intent): KeyEvent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
        }

    /** Patch 31 — « suivant » = +30 s, « précédent » = −30 s ; le reste
     *  (lecture/pause, avance rapide…) garde le traitement de Media3. */
    private fun seekActionForKey(keyCode: Int): String? = when (keyCode) {
        KeyEvent.KEYCODE_MEDIA_NEXT, KeyEvent.KEYCODE_MEDIA_SKIP_FORWARD -> ACTION_SEEK_FORWARD
        KeyEvent.KEYCODE_MEDIA_PREVIOUS, KeyEvent.KEYCODE_MEDIA_SKIP_BACKWARD -> ACTION_SEEK_BACK
        else -> null
    }

    /** Patch 29 — Les sauts : demandés par l'app ET permis par le flux. */
    private fun seekOffered(): Boolean =
        mediaActions.seek && player.isCommandAvailable(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)

    /** Patch 29 — Commandes maison ouvertes aux contrôleurs de la session. */
    private fun sessionCommands(): SessionCommands =
        MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()
            .add(SessionCommand(CUSTOM_SEEK_BACK, Bundle.EMPTY))
            .add(SessionCommand(CUSTOM_SEEK_FORWARD, Bundle.EMPTY))
            .add(SessionCommand(CUSTOM_NEXT, Bundle.EMPTY))
            .build()

    /**
     * Patch 29 — Commandes du lecteur que le SYSTÈME affiche. Quand nos
     * boutons sont là, « précédent / suivant » d'ExoPlayer sont retirés :
     * sinon le système leur donne les deux places principales, et « précédent »
     * sur un film seul… le relance depuis le début d'un appui. Les ±30 s
     * prennent ces places. Sans nos boutons (direct), rien ne change.
     */
    private fun platformPlayerCommands(): Player.Commands {
        val defaults = MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS
        if (!seekOffered() && !mediaActions.next) return defaults
        return defaults.buildUpon()
            .removeAll(
                Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_NEXT,
                Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM
            )
            .build()
    }

    /** Patch 29 — Boutons de session, dans l'ordre où le système les place
     *  (le 1er à gauche de lecture/pause, le 2e à droite, puis le reste). */
    private fun mediaButtons(): List<CommandButton> {
        val buttons = ArrayList<CommandButton>(3)
        if (seekOffered()) {
            buttons.add(
                commandButton(
                    CommandButton.ICON_SKIP_BACK_30, CUSTOM_SEEK_BACK,
                    label(LABEL_SEEK_BACK), CommandButton.SLOT_BACK
                )
            )
            buttons.add(
                commandButton(
                    CommandButton.ICON_SKIP_FORWARD_30, CUSTOM_SEEK_FORWARD,
                    label(LABEL_SEEK_FORWARD), CommandButton.SLOT_FORWARD
                )
            )
        }
        if (mediaActions.next) {
            buttons.add(
                commandButton(
                    CommandButton.ICON_NEXT, CUSTOM_NEXT,
                    label(LABEL_NEXT), CommandButton.SLOT_FORWARD_SECONDARY
                )
            )
        }
        return buttons
    }

    private fun commandButton(icon: Int, action: String, name: CharSequence, slot: Int): CommandButton =
        CommandButton.Builder(icon)
            .setSessionCommand(SessionCommand(action, Bundle.EMPTY))
            .setDisplayName(name)
            .setSlots(slot)
            .build()

    /** Patch 29 — Pousse boutons et commandes vers la session du système
     *  (via le contrôleur de notification ; pas encore connecté : il les
     *  recevra dans `onConnect`). */
    private fun refreshMediaButtons() {
        val session = mediaSession ?: return
        val controller = session.mediaNotificationControllerInfo ?: return
        session.setAvailableCommands(controller, sessionCommands(), platformPlayerCommands())
        // Pose aussi l'état de la session du système (PlaybackState).
        session.setMediaButtonPreferences(controller, mediaButtons())
    }

    /** Patch 29 — Repose la notification DÉJÀ affichée avec ses nouveaux
     *  boutons. Jamais de service démarré ici, jamais de réapparition. */
    private fun repostNotification() {
        if (mediaSession == null || !notificationPosted) return
        try {
            notificationManager.notify(NOTIFICATION_ID, buildNotification())
        } catch (e: Exception) {
            NpLog.w(TAG, "Notification non reposee (${e.javaClass.simpleName})")
        }
    }

    /**
     * Patch 29 — Libellé d'un bouton : celui de l'app (Dart, langue de
     * l'écran, §l10nAll) ; à défaut, la ressource de l'app par son NOM
     * (méthode du patch 21 : `notif_play` et `notif_pause` existent déjà) ;
     * à défaut, celle de Media3, traduite. Jamais de texte écrit ici.
     */
    private fun label(key: String): String {
        mediaActions.labels[key]?.takeIf { it.isNotBlank() }?.let { return it }
        val names = when (key) {
            LABEL_SEEK_BACK -> arrayOf("notif_seek_back", "media3_controls_seek_back_description")
            LABEL_SEEK_FORWARD -> arrayOf("notif_seek_forward", "media3_controls_seek_forward_description")
            LABEL_NEXT -> arrayOf("notif_next_episode", "media3_controls_seek_to_next_description")
            LABEL_PLAY -> arrayOf("notif_play", "media3_controls_play_description")
            else -> arrayOf("notif_pause", "media3_controls_pause_description")
        }
        for (name in names) {
            val id = context.resources.getIdentifier(name, "string", context.packageName)
            if (id != 0) return context.getString(id)
        }
        return ""
    }

    /** Patch 29 — Action de diffusion d'un bouton, propre à l'app. */
    private fun broadcastAction(action: String): String =
        context.packageName + BROADCAST_INFIX + action

    private fun actionIntent(action: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(broadcastAction(action)).setPackage(context.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

    /** Patch 29 — Signale un bouton à Dart ; c'est l'app qui l'exécute. */
    private fun dispatchMediaAction(action: String) {
        NpLog.d(TAG, "Bouton de notification : $action")
        eventHandler.sendEvent("mediaAction", mapOf("action" to action))
    }

    /**
     * Patch 29 — Se connecte à la session comme SON contrôleur de
     * notification : c'est ce qui fait apparaître ±30 s et « épisode
     * suivant » dans le lecteur média du système (Android 13+).
     */
    private fun connectNotificationController(session: MediaSession) {
        if (notificationControllerFuture != null) return
        try {
            val hints = Bundle().apply { putBoolean(KEY_MEDIA_NOTIFICATION_MANAGER, true) }
            notificationControllerFuture =
                MediaController.Builder(context.applicationContext, session.token)
                    .setConnectionHints(hints)
                    .setApplicationLooper(Looper.getMainLooper())
                    .buildAsync()
        } catch (e: Exception) {
            NpLog.w(TAG, "Controleur de notification refuse (${e.javaClass.simpleName})")
        }
    }

    /** Patch 29 — Même cycle que la session ; même garde que les récepteurs
     *  de `MainActivity` (non exporté à partir d'Android 13). */
    private fun registerActionReceiver() {
        if (actionReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val received = intent.action ?: return
                val action = ACTIONS.firstOrNull { broadcastAction(it) == received } ?: return
                dispatchMediaAction(action)
            }
        }
        val filter = IntentFilter().apply {
            for (action in ACTIONS) addAction(broadcastAction(action))
        }
        val app = context.applicationContext
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                app.registerReceiver(receiver, filter)
            }
            actionReceiver = receiver
        } catch (e: Exception) {
            NpLog.w(TAG, "Recepteur des boutons refuse (${e.javaClass.simpleName})")
        }
    }

    private fun unregisterActionReceiver() {
        val receiver = actionReceiver ?: return
        actionReceiver = null
        try {
            context.applicationContext.unregisterReceiver(receiver)
        } catch (e: Exception) {
            // Déjà retiré : sans objet.
        }
    }

    /**
     * Updates media metadata (title, artist, artwork)
     * This is called after the MediaItem is already set, so we just load artwork
     * The base metadata was already set when creating the MediaItem
     */
    fun updateMediaMetadata(mediaInfo: Map<String, Any>) {
        // Load artwork asynchronously if present and update the notification
        val artworkUrl = mediaInfo["artworkUrl"] as? String
        // AetherStream patch 30 (§notifAudit P10) — en-têtes de l'app pour
        // cette requête (l'agent IPTV, §iptvUaCompat).
        val artworkHeaders = (mediaInfo["artworkHeaders"] as? Map<*, *>)
            ?.mapNotNull { (k, v) -> if (k is String && v is String) k to v else null }
            ?.toMap()
            ?: emptyMap()
        if (artworkUrl != null) {
            currentArtworkUrl = artworkUrl // Track the current artwork URL
            loadArtwork(artworkUrl, artworkHeaders) { bitmap ->
                // Only use this artwork if it's still the current one (prevent race conditions)
                // Patch 30 — jamais l'URL au journal (§tvLogs).
                if (artworkUrl != currentArtworkUrl) {
                    NpLog.d(TAG, "Ignoring outdated artwork")
                    return@loadArtwork
                }

                bitmap?.let {
                    currentArtwork = it

                    // Update notification directly with the new artwork
                    // DO NOT call replaceMediaItem here as it can interrupt playback
                    // The notification will use currentArtwork automatically
                    if (player.playWhenReady) {
                        handler.post {
                            updateNotification()
                            NpLog.d(TAG, "Artwork loaded and notification updated")
                        }
                    } else {
                        NpLog.d(TAG, "Artwork loaded but player not ready, will show on next play")
                    }
                }
            }
        }

        NpLog.d(TAG, "Media metadata setup complete")
    }

    /**
     * Loads artwork from URL
     *
     * §engineVendor patch 18 (AetherStream, revue 2026-09-11, D2B-07) — même
     * patron que `AetherCastService.downloadBitmap` côté app. Amont : aucun
     * délai (0 = infini), flux jamais fermé, image décodée en PLEINE
     * résolution pour une icône, coroutine jamais annulée. Une affiche sur un
     * hôte muet bloquait un thread IO indéfiniment en retenant ce
     * gestionnaire ; une affiche TMDB « original » de plusieurs Mpx était
     * décodée en entier.
     * - délais de connexion et de lecture bornés ([ARTWORK_TIMEOUT_MS]) ;
     * - flux fermé (`use`) et connexion rendue (`disconnect`) ;
     * - décodage sous-échantillonné vers ~[ARTWORK_TARGET_PX] px ;
     * - tâche gardée : annulée par [release] et par une affiche plus récente.
     */
    private fun loadArtwork(
        url: String,
        headers: Map<String, String>,
        callback: (Bitmap?) -> Unit
    ) {
        artworkJob?.cancel()
        artworkJob = CoroutineScope(Dispatchers.IO).launch {
            val bitmap = try {
                downloadArtwork(url, headers)
            } catch (e: Exception) {
                // Patch 30 (§notifAudit P10) — le NOM de l'exception seul :
                // le message d'une `FileNotFoundException` (404, 500 d'un
                // panel) EST l'URL, et `NpLog.e` écrit même en release.
                NpLog.w(TAG, "Artwork unavailable (${e.javaClass.simpleName})")
                null
            }
            // Annulée pendant le téléchargement (release, autre affiche) :
            // `withContext` lève et le rappel n'a pas lieu.
            withContext(Dispatchers.Main) {
                callback(bitmap)
            }
        }
    }

    /**
     * Patch 18 — téléchargement borné + décodage sous-échantillonné.
     *
     * AetherStream patch 30 (§notifAudit P10) — Pas de vignette pour les
     * chaînes : la requête partait avec l'agent par défaut d'Android
     * (« Dalvik/… ») et SANS suivre une redirection HTTP → HTTPS (que
     * `HttpURLConnection` refuse de franchir seul). Désormais : en-têtes de
     * l'app ([headers], l'agent IPTV de §iptvUaCompat), redirections suivies
     * à la main jusqu'à [ARTWORK_MAX_REDIRECTS], code HTTP vérifié.
     */
    private fun downloadArtwork(url: String, headers: Map<String, String>): Bitmap? {
        var current = URL(url)
        var redirects = 0
        while (true) {
            val connection = current.openConnection()
            val http = connection as? HttpURLConnection
            try {
                connection.connectTimeout = ARTWORK_TIMEOUT_MS
                connection.readTimeout = ARTWORK_TIMEOUT_MS
                for ((name, value) in headers) connection.setRequestProperty(name, value)
                if (http != null) {
                    http.instanceFollowRedirects = false
                    val code = http.responseCode
                    if (code in 300..399) {
                        val location = http.getHeaderField("Location") ?: return null
                        if (++redirects > ARTWORK_MAX_REDIRECTS) return null
                        val next = URL(current, location)
                        if (next.protocol != "http" && next.protocol != "https") return null
                        current = next
                        continue
                    }
                    if (code !in 200..299) {
                        NpLog.w(TAG, "Artwork refused (HTTP $code)")
                        return null
                    }
                }
                val bytes = connection.getInputStream().use { it.readBytes() }
                return decodeArtwork(bytes)
            } finally {
                http?.disconnect()
            }
        }
    }

    /** Patch 18 — décodage sous-échantillonné vers ~[ARTWORK_TARGET_PX] px. */
    private fun decodeArtwork(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= ARTWORK_TARGET_PX &&
            bounds.outHeight / (sample * 2) >= ARTWORK_TARGET_PX
        ) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }

    /**
     * Releases MediaSession and hides notification
     */
    fun release() {
        // Patch 18 — plus aucune affiche ne doit arriver après la libération.
        artworkJob?.cancel()
        artworkJob = null
        // Patch 29 — contrôleur de notification et récepteur, AVANT la session.
        notificationControllerFuture?.let { MediaController.releaseFuture(it) }
        notificationControllerFuture = null
        unregisterActionReceiver()
        lastSeekable = null
        player.removeListener(playerListener)
        VideoPlayerMediaSessionService.stop(context, removeNotification = true)
        hideNotification()

        mediaSession?.release()
        mediaSession = null
        currentArtwork = null
        currentArtworkUrl = null
        currentTitle = "Video"
        currentSubtitle = ""
        NpLog.d(TAG, "MediaSession released")
    }
}
