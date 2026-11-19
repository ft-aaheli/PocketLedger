package com.pocketledger.pocketledger

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val credentialRequest = 4107
    private var pendingCredential: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pocketledger/device_lock")
            .setMethodCallHandler { call, result ->
                if (call.method == "confirm") {
                    confirmCredential(result)
                } else {
                    result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun confirmCredential(result: MethodChannel.Result) {
        if (pendingCredential != null) {
            result.error("in_progress", "Device confirmation is already open.", null)
            return
        }
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (keyguard == null || !keyguard.isDeviceSecure) {
            result.error("no_screen_lock", "Set a screen lock in Android Settings.", null)
            return
        }
        val intent = keyguard.createConfirmDeviceCredentialIntent(
            "PocketLedger",
            "Confirm your screen lock to continue.",
        )
        if (intent == null) {
            result.error("unavailable", "Android could not open device confirmation.", null)
            return
        }
        pendingCredential = result
        try {
            // Device credential confirmation is available on Android 8.1.
            startActivityForResult(intent, credentialRequest)
        } catch (error: RuntimeException) {
            pendingCredential = null
            result.error("unavailable", "Android could not open device confirmation.", null)
        }
    }

    @Deprecated("Uses device credential confirmation on supported Android versions.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == credentialRequest) {
            val callback = pendingCredential
            pendingCredential = null
            callback?.success(resultCode == Activity.RESULT_OK)
        }
    }
}
