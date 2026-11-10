package com.partner0487.task_system

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Dart 端（lib/system.dart）用的幾個 Android 原生小功能：
 * 電池是否不受限制、打開 App 設定頁、讀版本號、用瀏覽器開網址。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "task_system/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 已經不受電池最佳化限制（Samsung 的「不受限制」）
                    "isBatteryUnrestricted" -> {
                        val pm = getSystemService(PowerManager::class.java)
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }

                    // App 資訊頁：使用者可以在這裡點「電池」→「不受限制」
                    "openAppSettings" -> {
                        start(Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ))
                        result.success(null)
                    }

                    "appVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
                        else @Suppress("DEPRECATION") info.versionCode.toLong()
                        result.success("${info.versionName} (${code})")
                    }

                    "openUrl" -> {
                        start(Intent(Intent.ACTION_VIEW, Uri.parse(call.arguments as String)))
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun start(intent: Intent) {
        try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            // 極少數手機沒有對應的設定頁 / 瀏覽器，忽略即可
        }
    }
}
