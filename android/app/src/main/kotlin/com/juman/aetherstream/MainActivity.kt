package com.juman.aetherstream

import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    // §pipPhone — Canal MAISON (voir platform_pip.dart pour le pourquoi : le
    // PiP du paquet vendore exige `isFullScreen`, jamais vrai ici). Garde en
    // champ pour qu'onUserLeaveHint / onPictureInPictureModeChanged puissent
    // emettre vers Dart en dehors de configureFlutterEngine.
    private var pipChannel: MethodChannel? = null
    private var autoPipEnabled = false
    private var autoPipWidth = 16
    private var autoPipHeight = 9

    // §dlNotif — Meme raisonnement que pipChannel : garde en champ pour que
    // le BroadcastReceiver d'annulation (qui vit independamment de
    // configureFlutterEngine) puisse emettre vers Dart.
    private var transferChannel: MethodChannel? = null

    // §dlNotif — Le bouton "Annuler" d'une notification de telechargement
    // passe par un Intent (PendingIntent.getBroadcast), pas par un appel Dart
    // direct : la notification doit pouvoir agir meme si MainActivity n'a
    // jamais ete au premier plan depuis le dernier demarrage du processus.
    // ⚠️ Enregistre dynamiquement (RECEIVER_NOT_EXPORTED) : l'action porte le
    // package en `setPackage`, aucune autre app ne peut la declencher.
    private val cancelDownloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val taskId = intent?.getStringExtra(AetherDownloadService.EXTRA_TASK_ID) ?: return
            transferChannel?.invokeMethod(
                "onDownloadAction",
                mapOf("action" to "cancel", "taskId" to taskId)
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Canal pour lancer l'installation d'un APK via FileProvider (Android 7+)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aetherstream/install_apk"
        ).setMethodCallHandler { call, result ->
            if (call.method == "install") {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("NO_PATH", "Le chemin de l'APK est requis", null)
                    return@setMethodCallHandler
                }
                try {
                    val file = File(path)
                    val uri = FileProvider.getUriForFile(
                        this,
                        "${packageName}.fileprovider",
                        file
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("INSTALL_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        // Canal de détection plateforme TV (§3c-1).
        // Retourne true si on est sur Android TV (UiModeManager) OU sur Fire TV
        // (feature flag Amazon spécifique).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aetherstream/tv_detection"
        ).setMethodCallHandler { call, result ->
            if (call.method == "isTv") {
                try {
                    val uiManager =
                        getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    val isAndroidTv =
                        uiManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                    val isFireTv =
                        packageManager.hasSystemFeature("amazon.hardware.fire_tv")
                    result.success(isAndroidTv || isFireTv)
                } catch (e: Exception) {
                    result.error("TV_DETECT_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        // §pipPhone — Picture-in-Picture. `isSupported` : feature + API >= 26
        // (PictureInPictureParams n'existe pas avant). `enter` : bouton manuel
        // du lecteur. `setAutoEnter` : arme/desarme le PiP au geste Accueil —
        // rappele a CHAQUE changement d'eligibilite (verrou, erreur, TV),
        // jamais une seule fois au demarrage.
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aetherstream/pip"
        )
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(supported)
                }
                "enter" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val w = call.argument<Int>("width") ?: 16
                    val h = call.argument<Int>("height") ?: 9
                    try {
                        val entered = enterPictureInPictureMode(
                            PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(w, h))
                                .build()
                        )
                        result.success(entered)
                    } catch (e: Exception) {
                        // Appareil sans le feature, ou activite pas eligible
                        // (multi-fenetre deja actif, etc.) : jamais une exception
                        // cote Dart, juste "non entre".
                        result.success(false)
                    }
                }
                "setAutoEnter" -> {
                    autoPipEnabled = call.argument<Boolean>("enabled") ?: false
                    autoPipWidth = call.argument<Int>("width") ?: 16
                    autoPipHeight = call.argument<Int>("height") ?: 9
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            setPictureInPictureParams(buildAutoPipParams())
                        } catch (e: Exception) {
                            // Fenetre pas encore attachee : sans effet, geree
                            // par onUserLeaveHint le moment venu.
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // §dlNotif — Notification de téléchargement, portée par
        // `AetherDownloadService` (foreground service `dataSync` : sans lui, le
        // transfert — Dio dans l'isolate principal, aucun WorkManager — meurt
        // avec le processus dès qu'Android récupère la mémoire).
        transferChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aetherstream/transfer_notif"
        )
        transferChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startOrUpdate" -> {
                    val title = call.argument<String>("title") ?: "Téléchargement"
                    val text = call.argument<String>("text") ?: ""
                    val progress = call.argument<Int>("progress") ?: -1
                    val indeterminate = call.argument<Boolean>("indeterminate") ?: false
                    val cancelTaskId = call.argument<String>("cancelTaskId")
                    AetherDownloadService.start(
                        this, title, text, progress, indeterminate, cancelTaskId
                    )
                    result.success(null)
                }
                "stopOngoing" -> {
                    AetherDownloadService.stop(this)
                    result.success(null)
                }
                "postFinished" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val title = call.argument<String>("title") ?: "Téléchargement"
                    val success = call.argument<Boolean>("success") ?: false
                    AetherDownloadService.postFinished(this, id, title, success)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun buildAutoPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(autoPipWidth, autoPipHeight))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoPipEnabled)
        }
        return builder.build()
    }

    // §pipPhone — Geste Accueil : c'est le SEUL chemin qui fonctionne a partir
    // de l'API 26 (setAutoEnterEnabled n'existe que depuis l'API 31, et ne
    // couvre de toute facon pas tous les constructeurs). Idiome standard
    // Android pour le PiP manuel.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPipEnabled &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !isInPictureInPictureMode
        ) {
            try {
                enterPictureInPictureMode(buildAutoPipParams())
            } catch (e: Exception) {
                // Silencieux : rien a faire cote app si le systeme refuse.
            }
        }
    }

    // §pipPhone — L'EVENEMENT exact (contre le sondage a 150 ms du paquet
    // vendore, qui n'a pas acces a l'Activity et doit deviner). `dismissed`
    // distingue « ferme depuis la fenetre PiP » (croix) de « restaure en plein
    // ecran » : dans le premier cas, PlayerPage met la lecture en pause plutot
    // que de laisser un son sans image derriere une activite qui se termine.
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        val dismissed = !isInPictureInPictureMode && (isFinishing || isDestroyed)
        pipChannel?.invokeMethod(
            "onPipChanged",
            mapOf("active" to isInPictureInPictureMode, "dismissed" to dismissed)
        )
    }

    // §dlNotif — Enregistre en `onCreate`/`onDestroy`, PAS en `onStart`/
    // `onStop` : le bouton "Annuler" doit rester actionnable tant que le
    // PROCESSUS vit, précisément quand l'app est en arrière-plan (backgroundée,
    // pas détruite) — c'est le cas normal pour qui regarde une notification
    // de téléchargement. Un enregistrement borné à `onStart`/`onStop` le
    // désarmerait exactement quand il sert le plus.
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(AetherDownloadService.ACTION_CANCEL)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(cancelDownloadReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(cancelDownloadReceiver, filter)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(cancelDownloadReceiver)
        } catch (e: IllegalArgumentException) {
            // Jamais enregistré (onCreate n'a pas eu le temps de s'exécuter) :
            // rien à faire.
        }
        super.onDestroy()
    }
}
