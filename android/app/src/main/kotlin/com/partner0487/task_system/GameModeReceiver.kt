package com.partner0487.task_system

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 遊戲模式時間到：關閉遊戲模式，並在背景把任務補回通知欄（App 沒開也一樣）。 */
class GameModeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val end = GameMode.until(context)
        // 只關掉「已經到時間」的；如果使用者剛好又重新開啟（新的結束時間），就不要動
        if (end > 0 && end <= System.currentTimeMillis() + 1000) GameMode.turnOff(context)
        GameMode.refresh(context)

        val pending = goAsync()
        HeadlessDart.run(context, "syncNotificationsOnly") { pending.finish() }
    }
}
