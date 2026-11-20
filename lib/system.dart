import 'package:flutter/services.dart';

/// 呼叫 Android 原生的小功能（實作在 MainActivity.kt）。
class SystemInfo {
  static const _channel = MethodChannel('task_system/system');

  /// 電池是否「不受限制」。不受限制時，通知欄的「完成」、「滑掉彈回」等背景功能才會穩定運作。
  static Future<bool> isBatteryUnrestricted() async =>
      await _channel.invokeMethod<bool>('isBatteryUnrestricted') ?? true;

  /// 打開這個 App 的系統設定頁（可以在裡面設定電池、通知）。
  static Future<void> openAppSettings() => _channel.invokeMethod('openAppSettings');

  /// 「1.0.0 (1)」
  static Future<String> appVersion() async =>
      await _channel.invokeMethod<String>('appVersion') ?? '?';

  static Future<void> openUrl(String url) => _channel.invokeMethod('openUrl', url);

  /// 開關遊戲模式之後呼叫：原生端排好自動關閉的鬧鐘、更新快速設定開關。
  static Future<void> gameModeChanged() => _channel.invokeMethod('gameModeChanged');

  /// 拿走一次性的動作，例如從快速設定開關打開 App → 'game_mode_picker'。沒有就是 null。
  static Future<String?> takeLaunchAction() => _channel.invokeMethod<String>('takeLaunchAction');
}
