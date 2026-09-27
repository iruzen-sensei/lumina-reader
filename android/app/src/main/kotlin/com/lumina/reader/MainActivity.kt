package com.lumina.reader

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pipChannel: MethodChannel? = null

    /// Set by the anime player while a video is actively playing: when the
    /// user leaves the app (home / recents), the activity shrinks into
    /// Picture-in-Picture instead of pausing — the Netflix behaviour.
    private var autoPipOnUserLeave = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lumina/pip").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "enter" -> {
                        enterPip()
                        result.success(true)
                    }
                    "setAutoOnLeave" -> {
                        autoPipOnUserLeave = call.argument<Boolean>("enabled") ?: false
                        result.success(true)
                    }
                    "isInPip" -> result.success(isInPictureInPictureMode)
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val aspect = Rational(16, 9)
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(aspect)
                    .build()
                enterPictureInPictureMode(params)
            } catch (_: Exception) {
                // Some OEMs forbid PiP (policy / multi-window off) —
                // the video simply keeps playing fullscreen.
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPipOnUserLeave && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val aspect = Rational(16, 9)
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(aspect)
                    .build()
                enterPictureInPictureMode(params)
            } catch (_: Exception) {
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Tell Dart so the player can hide its controls overlay in PiP.
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
