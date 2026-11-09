import 'dart:convert';

import 'models.dart';

/// 備份檔的識別標記：匯入時用來確認選到的真的是任務系統的備份，不是別的 JSON。
const _format = 'task_system_backup';
const _version = 1;

/// 把全部資料轉成備份檔內容（排版過的 JSON，人也看得懂）。
String encodeBackup(AppData data, DateTime now) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': _format,
      'version': _version,
      'exportedAt': now.toIso8601String(),
      'data': data.toJson(),
    });

/// 讀備份檔。格式不對時丟出 [FormatException]，訊息可以直接顯示給使用者看。
AppData decodeBackup(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const FormatException('這個檔案不是任務系統的備份檔');
  }
  if (json is! Map<String, dynamic> || json['format'] != _format) {
    throw const FormatException('這個檔案不是任務系統的備份檔');
  }
  if ((json['version'] as int? ?? 0) > _version) {
    throw const FormatException('這個備份檔來自較新版本的 App，請先更新 App');
  }
  try {
    final data = AppData.fromJson(json['data'] as Map<String, dynamic>);
    // 保險：確保之後新增的 id 不會跟備份裡的重複
    final maxId = data.quests
        .expand((q) => [q.id, ...q.steps.map((s) => s.id)])
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (data.nextId <= maxId) data.nextId = maxId + 1;
    return data;
  } catch (_) {
    throw const FormatException('備份檔內容已損毀，無法讀取');
  }
}

/// 「3 個大事件、12 個細項」：匯入前讓使用者確認。
String backupSummary(AppData data) =>
    '${data.quests.length} 個大事件、${data.quests.fold<int>(0, (n, q) => n + q.steps.length)} 個細項';
