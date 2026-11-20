package com.partner0487.task_system

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService

/**
 * 遊戲模式的狀態（原生端）。跟 lib/game_mode.dart 讀寫同一個設定檔、同一個 key：
 * game_mode_until = 0 → 關閉；-1 → 直到手動關閉；其它 → 結束時間（毫秒）。
 */
object GameMode {
    private const val FILE = "task_system_flags"
    private const val KEY = "game_mode_until"
    const val MANUAL = -1L

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun until(context: Context): Long = prefs(context).getLong(KEY, 0L)

    fun isActive(context: Context): Boolean {
        val v = until(context)
        return v == MANUAL || v > System.currentTimeMillis()
    }

    fun turnOff(context: Context) {
        prefs(context).edit().putLong(KEY, 0L).commit()
    }

    /** 依照目前狀態：排好（或取消）時間到自動關閉的鬧鐘，並更新快速設定開關的樣子。 */
    fun refresh(context: Context) {
        val app = context.applicationContext
        val alarms = app.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(
            app, 0, Intent(app, GameModeReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        alarms.cancel(pending)
        val end = until(app)
        if (end > System.currentTimeMillis()) {
            // 要準時：用精確鬧鐘（USE_EXACT_ALARM）；系統不允許時退回不精確的
            if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, end, pending)
            } else {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, end, pending)
            }
        }
        TileService.requestListeningState(app, ComponentName(app, GameModeTileService::class.java))
    }
}
