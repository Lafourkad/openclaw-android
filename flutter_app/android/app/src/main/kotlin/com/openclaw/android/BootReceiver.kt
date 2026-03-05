package com.openclaw.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.util.Log

/**
 * Starts the gateway automatically on device boot if auto-start is enabled.
 * User controls this from the app settings.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
        private const val PREF_NAME = "openclaw_prefs"
        private const val KEY_AUTOSTART = "gateway_autostart"

        fun isAutoStartEnabled(context: Context): Boolean {
            return context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_AUTOSTART, false)
        }

        fun setAutoStartEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_AUTOSTART, enabled)
                .apply()
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON") {
            return
        }

        Log.i(TAG, "Boot completed, checking auto-start...")

        if (!isAutoStartEnabled(context)) {
            Log.i(TAG, "Auto-start disabled, skipping")
            return
        }

        // Check if config exists
        val configFile = java.io.File(context.filesDir, ".openclaw/openclaw.json")
        if (!configFile.exists()) {
            Log.w(TAG, "No config file found, skipping auto-start")
            return
        }

        // Check if bootstrap is complete
        val nodeFile = java.io.File(context.filesDir, "node/bin/node")
        if (!nodeFile.exists()) {
            Log.w(TAG, "Node not installed, skipping auto-start")
            return
        }

        Log.i(TAG, "Starting gateway service on boot")
        try {
            GatewayService.start(context)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start gateway on boot", e)
        }
    }
}
