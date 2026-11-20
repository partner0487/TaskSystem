package com.partner0487.task_system

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 快速設定裡的「遊戲模式」開關（拉下通知欄，跟 Wi-Fi、藍牙同一排）。
 * - 關閉中按下 → 打開 App，跳出時間選擇（30 分鐘 / 1 小時 / 2 小時 / 直到手動關閉）
 * - 開啟中按下 → 立刻關閉，任務回到通知欄
 */
class GameModeTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        if (GameMode.isActive(this)) {
            GameMode.turnOff(this)
            GameMode.refresh(this)
            updateTile()
            HeadlessDart.run(this, "syncNotificationsOnly")
        } else {
            val intent = Intent(this, MainActivity::class.java)
                .putExtra(MainActivity.EXTRA_ACTION, MainActivity.ACTION_GAME_MODE_PICKER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(
                        this, 1, intent,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        }
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val active = GameMode.isActive(this)
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= 29) {
            val end = GameMode.until(this)
            tile.subtitle = when {
                !active -> null
                end == GameMode.MANUAL -> "手動關閉"
                else -> "到 " + SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(end))
            }
        }
        tile.updateTile()
    }
}
