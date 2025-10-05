package com.example.smartwael

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "scanFile") {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            val file = File(path)
                            val uri = Uri.fromFile(file)

                            // 🔹 إعلام النظام بأن هناك ملفًا جديدًا ليظهر في تطبيق الملفات
                            val intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, uri)
                            sendBroadcast(intent)

                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SCAN_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "Path is null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
>>>>>>> temp-fixes
