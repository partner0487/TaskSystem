import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

/// 遊戲模式：暫時清空通知欄、停掉所有提醒，時間到（或手動關閉）後恢復。
///
/// 狀態存在 Android 的一般設定檔（task_system_flags），
/// 這樣快速設定開關、自動關閉的鬧鐘（原生 Kotlin）和 Dart 都讀得到同一份。
/// 原生端的讀寫在 GameMode.kt，key 和數值的意思要兩邊一致。
class GameMode {
  static const fileName = 'task_system_flags';
  static const _key = 'game_mode_until';

  /// 存的值：0 / 沒有 = 關閉；-1 = 直到手動關閉；其它 = 結束時間（毫秒）
  static const _manual = -1;

  static final _prefs = SharedPreferencesAsync(
    options: const SharedPreferencesAsyncAndroidOptions(
      backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
      originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(fileName: fileName),
    ),
  );

  /// 目前狀態。null = 沒開；`until == null` = 直到手動關閉。
  static Future<({DateTime? until})?> read([DateTime? now]) async {
    final v = await _prefs.getInt(_key) ?? 0;
    if (v == _manual) return (until: null);
    if (v <= 0) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(v);
    return until.isAfter(now ?? DateTime.now()) ? (until: until) : null;
  }

  static Future<bool> isActive([DateTime? now]) async => await read(now) != null;

  /// 開啟遊戲模式。[duration] 為 null = 直到手動關閉。
  static Future<void> turnOn(Duration? duration) => _prefs.setInt(
      _key, duration == null ? _manual : DateTime.now().add(duration).millisecondsSinceEpoch);

  static Future<void> turnOff() => _prefs.setInt(_key, 0);
}

/// 開啟時可以選的時間（null = 直到手動關閉）。
const gameModeDurations = <Duration?>[
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  null,
];

String gameModeDurationText(Duration? d) {
  if (d == null) return '直到手動關閉';
  if (d.inMinutes < 60) return '${d.inMinutes} 分鐘';
  return '${d.inHours} 小時';
}
