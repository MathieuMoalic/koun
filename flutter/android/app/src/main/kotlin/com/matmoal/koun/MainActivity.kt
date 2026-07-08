package com.matmoal.koun

import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "Audio path is missing", null)
                        return@setMethodCallHandler
                    }
                    playFile(path)
                    result.success(null)
                }
                "stop" -> {
                    stopAudio()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }

    private fun playFile(path: String) {
        stopAudio()
        mediaPlayer = MediaPlayer().apply {
            setDataSource(path)
            setOnCompletionListener {
                stopAudio()
            }
            prepare()
            start()
        }
    }

    private fun stopAudio() {
        mediaPlayer?.runCatching {
            stop()
            release()
        }
        mediaPlayer = null
    }

    companion object {
        private const val CHANNEL = "koun/audio"
    }
}