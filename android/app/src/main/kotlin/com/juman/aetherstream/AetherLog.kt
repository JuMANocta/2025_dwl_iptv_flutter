package com.juman.aetherstream

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log

/**
 * Mode production — revue 2026-09-11, D2B-16 — Journal natif de l'APP, filtré
 * comme `NpLog` l'est dans le paquet vendoré.
 *
 * **Le défaut réparé.** Le relais Cast (`Log.i` à chaque piste, en fin de
 * conversion, `Log.w` avec le message brut de l'exception) et nos deux
 * services de premier plan écrivaient dans logcat EN RELEASE, alors que le
 * paquet vendoré, lui, se tait sur un APK non débogable. Côté Dart, §tourFix
 * coupe déjà logcat en release ; le natif était resté bavard.
 *
 * Info et avertissements : seulement sur un build DÉBOGABLE (debug, le S25 de
 * recette). Rien ici n'est une erreur à garder en production.
 *
 * ⚠️ [init] est appelé par `MainActivity.onCreate`, avant tout le reste. Un
 * service relancé seul par le système (processus recréé sans activité) reste
 * muet — c'est le côté sûr.
 */
object AetherLog {
    @Volatile
    var enabled = false
        private set

    fun init(context: Context) {
        enabled = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    fun i(tag: String, msg: String) {
        if (enabled) Log.i(tag, msg)
    }

    fun w(tag: String, msg: String) {
        if (enabled) Log.w(tag, msg)
    }
}
