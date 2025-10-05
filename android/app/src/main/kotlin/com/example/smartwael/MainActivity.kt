package com.example.smartwael

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "scanFile" -> {
                    val filePath = call.argument<String>("path")
                    if (filePath != null) {
                        scanFile(filePath, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "File path is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun scanFile(filePath: String, result: MethodChannel.Result) {
        try {
            val file = File(filePath)
            if (file.exists()) {
                MediaScannerConnection.scanFile(
                    this,
                    arrayOf(filePath),
                    null
                ) { _, uri ->
                    runOnUiThread {
                        result.success("File scanned successfully: $uri")
                    }
                }
            } else {
                result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
            }
        } catch (e: Exception) {
            result.error("SCAN_ERROR", "Failed to scan file: ${e.message}", null)
        }
    }
}