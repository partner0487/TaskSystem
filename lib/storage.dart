import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 讀寫存檔。用 SharedPreferencesAsync（沒有快取），
/// 這樣通知欄按「完成」時在背景改的資料，App 這邊讀得到最新的。
class Storage {
  static const _key = 'quest_data_v1';
  static final _prefs = SharedPreferencesAsync();

  static Future<AppData> read() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return AppData.sample();
    return AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<void> write(AppData data) =>
      _prefs.setString(_key, jsonEncode(data.toJson()));

  /// 「電池設定提示」使用者按過「不再提醒」。
  static Future<bool> batteryTipDismissed() async =>
      await _prefs.getBool('battery_tip_dismissed') ?? false;

  static Future<void> dismissBatteryTip() => _prefs.setBool('battery_tip_dismissed', true);
}
