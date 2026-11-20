package com.partner0487.task_system

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * 啟動一個沒有畫面的 Flutter 引擎，執行 lib/main.dart 裡的某個 Dart 函式（要有 @pragma('vm:entry-point')）。
 * 用在：開機補發通知、遊戲模式開關、遊戲模式時間到自動關閉。要在主執行緒呼叫。
 */
object HeadlessDart {
    /** 執行 [entrypoint]；Dart 通常 1 秒內做完，8 秒後關掉引擎釋放記憶體，再呼叫 [onDone]。 */
    fun run(context: Context, entrypoint: String, onDone: () -> Unit = {}) {
        val appContext = context.applicationContext
        val handler = Handler(Looper.getMainLooper())
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(appContext)
        loader.ensureInitializationCompleteAsync(appContext, null, handler) {
            val engine = FlutterEngine(appContext) // 會自動註冊所有 plugin
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), entrypoint)
            )
            handler.postDelayed({
                engine.destroy()
                onDone()
            }, 8000)
        }
    }
}
