package com.huddlecommunity.better_native_video_player

import android.util.Log

/**
 * Logging gate for the plugin.
 *
 * Debug/warning logs are skipped entirely unless [enabled] is set (done once
 * in [NativeVideoPlayerPlugin.onAttachedToEngine] based on the consuming
 * app's debuggable flag), so per-event/per-tick log calls cost a single
 * boolean check in release builds instead of a synchronous logd write.
 * Errors always log.
 */
object NpLog {
    @Volatile
    var enabled = false

    fun d(tag: String, msg: String) {
        if (enabled) Log.d(tag, msg)
    }

    fun w(tag: String, msg: String) {
        if (enabled) Log.w(tag, msg)
    }

    /**
     * patch 19 (revue 2026-09-11, D2B-16) — Les erreurs restent journalisées,
     * mais la PILE complète seulement sur un build débogable : en release,
     * le message seul.
     */
    fun e(tag: String, msg: String, tr: Throwable? = null) {
        Log.e(tag, msg, if (enabled) tr else null)
    }
}
