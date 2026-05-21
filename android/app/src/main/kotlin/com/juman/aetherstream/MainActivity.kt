package com.juman.aetherstream

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

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
    }
}
