package com.partner0487.task_system

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * 手機重開機（或 App 更新）後，通知欄會被清空。
 * 這裡啟動一個沒有畫面的 Flutter 引擎，執行 Dart 的 bootSync()，把未完成任務的通知補回來。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON" -> Unit
            else -> return
        }

        // goAsync：讓 BroadcastReceiver 多活一下（系統上限約 10 秒）等 Dart 做完
        val pending = goAsync()
        val appContext = context.applicationContext
        val handler = Handler(Looper.getMainLooper())
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(appContext)
        loader.ensureInitializationCompleteAsync(appContext, null, handler) {
            val engine = FlutterEngine(appContext) // 會自動註冊所有 plugin
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "bootSync")
            )
            // bootSync 通常 1 秒內就完成；給它 8 秒後關掉引擎，釋放記憶體
            handler.postDelayed({
                engine.destroy()
                pending.finish()
            }, 8000)
        }
    }
}
