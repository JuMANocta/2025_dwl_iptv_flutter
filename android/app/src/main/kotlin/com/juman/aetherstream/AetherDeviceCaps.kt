package com.juman.aetherstream

import android.app.ActivityManager
import android.content.Context
import android.hardware.display.DisplayManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.os.Build
import android.view.Display

/**
 * §deviceCaps (2026-09-06) — Ce que l'appareil SAIT FAIRE, mesuré, pas deviné.
 *
 * Trois questions, trois sources Android :
 *  - « peut-il DÉCODER de la 4K ? » → [MediaCodecList] : par codec (H.264, HEVC,
 *    AV1, VP9), le meilleur décodeur, matériel ou logiciel, sa taille maximale et
 *    la cadence supportée en 1080p et 2160p.
 *  - « peut-il l'AFFICHER ? » → [Display] : définition physique du mode courant,
 *    fréquences, capacités HDR. ⚠️ Décoder n'est pas afficher (§video4k a mesuré
 *    une image sur trois perdue à la SORTIE, pas à la source) : les deux
 *    comptent, séparément.
 *  - « a-t-il la mémoire ? » → [ActivityManager] : RAM totale, classe mémoire,
 *    drapeau « appareil à faible mémoire ».
 *
 * Tout est rendu brut dans une carte ; l'interprétation vit côté Dart, testée.
 */
object AetherDeviceCaps {

    private val MIMES = mapOf(
        "avc" to "video/avc",
        "hevc" to "video/hevc",
        "av1" to "video/av01",
        "vp9" to "video/x-vnd.on2.vp9",
    )

    fun probe(context: Context): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["model"] = Build.MODEL
        out["manufacturer"] = Build.MANUFACTURER
        out["sdk"] = Build.VERSION.SDK_INT
        out["abis"] = Build.SUPPORTED_ABIS.toList()
        out["cores"] = Runtime.getRuntime().availableProcessors()
        out["memory"] = probeMemory(context)
        out["display"] = probeDisplay(context)
        out["decoders"] = probeDecoders()
        return out
    }

    private fun probeMemory(context: Context): Map<String, Any?> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        am.getMemoryInfo(info)
        return mapOf(
            "totalMb" to (info.totalMem / (1024L * 1024L)),
            "availMb" to (info.availMem / (1024L * 1024L)),
            "lowRamDevice" to am.isLowRamDevice,
            "memoryClassMb" to am.memoryClass,
            "largeMemoryClassMb" to am.largeMemoryClass,
        )
    }

    private fun probeDisplay(context: Context): Map<String, Any?> {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val display: Display = dm.getDisplay(Display.DEFAULT_DISPLAY)
            ?: return mapOf("error" to "no default display")
        val mode = display.mode
        val modes = display.supportedModes.map {
            mapOf(
                "width" to it.physicalWidth,
                "height" to it.physicalHeight,
                "refreshHz" to it.refreshRate,
            )
        }
        val hdr = try {
            display.hdrCapabilities?.supportedHdrTypes?.toList() ?: emptyList<Int>()
        } catch (_: Exception) {
            emptyList<Int>()
        }
        val hdrNames = hdr.map {
            when (it) {
                Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "DOLBY_VISION"
                Display.HdrCapabilities.HDR_TYPE_HDR10 -> "HDR10"
                Display.HdrCapabilities.HDR_TYPE_HLG -> "HLG"
                Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "HDR10_PLUS"
                else -> "HDR_$it"
            }
        }
        return mapOf(
            "width" to mode.physicalWidth,
            "height" to mode.physicalHeight,
            "refreshHz" to mode.refreshRate,
            "modes" to modes,
            "hdr" to hdrNames,
        )
    }

    /**
     * Pour chaque codec vidéo : le décodeur retenu (matériel d'abord), sa taille
     * maximale et la cadence supportée en 1080p et en 2160p (0 = taille non
     * supportée).
     */
    private fun probeDecoders(): Map<String, Any?> {
        val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        val result = HashMap<String, Any?>()
        for ((key, mime) in MIMES) {
            var best: MediaCodecInfo? = null
            var bestHw = false
            for (info in list.codecInfos) {
                if (info.isEncoder) continue
                if (!info.supportedTypes.any { it.equals(mime, ignoreCase = true) }) continue
                val hw = isHardware(info)
                // Un décodeur matériel gagne toujours sur un logiciel.
                if (best == null || (hw && !bestHw)) {
                    best = info
                    bestHw = hw
                }
            }
            if (best == null) {
                result[key] = null
                continue
            }
            val caps = try { best.getCapabilitiesForType(mime) } catch (_: Exception) { null }
            val video = caps?.videoCapabilities
            val profiles = caps?.profileLevels?.map { it.profile } ?: emptyList()
            result[key] = mapOf(
                "name" to best.name,
                "hardware" to bestHw,
                "maxWidth" to (video?.supportedWidths?.upper ?: 0),
                "maxHeight" to (video?.supportedHeights?.upper ?: 0),
                "fps1080" to fpsFor(video, 1920, 1080),
                "fps2160" to fpsFor(video, 3840, 2160),
                "profiles" to profiles,
            )
        }
        return result
    }

    private fun fpsFor(video: MediaCodecInfo.VideoCapabilities?, w: Int, h: Int): Double {
        if (video == null) return 0.0
        return try {
            if (!video.isSizeSupported(w, h)) 0.0
            else video.getSupportedFrameRatesFor(w, h).upper
        } catch (_: Exception) {
            0.0
        }
    }

    private fun isHardware(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return info.isHardwareAccelerated
        // Avant Android 10 : les décodeurs logiciels d'AOSP portent ces préfixes.
        val n = info.name.lowercase()
        return !(n.startsWith("omx.google.") || n.startsWith("c2.android.") || n.contains(".sw."))
    }
}
