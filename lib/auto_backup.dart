import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'backup.dart';
import 'models.dart';

/// 每天自動備份一次，只保留一份，存在 App 自己的資料夾（使用者看不到，刪掉 App 會一起刪掉）。
/// 用來救「資料壞掉、按錯」；換手機請用手動的「匯出備份」。
class AutoBackup {
  static const _fileName = 'auto_backup.json';

  /// 備份放在哪個資料夾（測試時可以換成暫存資料夾）。
  static Future<Directory> Function() directory = getApplicationSupportDirectory;

  static Future<File> _file() async => File('${(await directory()).path}/$_fileName');

  /// 今天（以凌晨 4 點為分界）還沒備份過，就備份一次。回傳這次有沒有備份。
  /// 在 App 打開、還沒做任何修改之前呼叫：備份的是「今天一打開時」的樣子。
  static Future<bool> runDaily(AppData data, DateTime now) async {
    final file = await _file();
    if (await file.exists() && resetDayKey(await file.lastModified()) == resetDayKey(now)) {
      return false;
    }
    // 先寫到暫存檔，成功後再取代：寫到一半當機也不會弄壞唯一那份備份
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encodeBackup(data, now), flush: true);
    await tmp.rename(file.path);
    return true;
  }

  /// 讀出自動備份：備份時間與內容；沒有備份或讀不出來時回傳 null。
  static Future<({DateTime savedAt, AppData data})?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final data = decodeBackup(await file.readAsString());
      return (savedAt: await file.lastModified(), data: data);
    } on FormatException {
      return null;
    }
  }
}
