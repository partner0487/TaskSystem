package com.partner0487.task_system

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 手機重開機（或 App 更新）後，通知欄會被清空、鬧鐘也會被清掉。
 * 這裡重新排好遊戲模式的自動關閉，並在背景執行 Dart 的 bootSync()，把未完成任務的通知補回來。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON" -> Unit
            else -> return
        }
        GameMode.refresh(context)

        // goAsync：讓 BroadcastReceiver 多活一下（系統上限約 10 秒）等 Dart 做完
        val pending = goAsync()
        HeadlessDart.run(context, "bootSync") { pending.finish() }
    }
}
