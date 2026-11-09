import 'package:flutter/material.dart';

/// 任務分類，對應原神的「主線 / 支線 / 每日」。
/// 宣告順序就是畫面上方分頁的順序。
/// 沒有期限的任務不另外分類：任何分類的細項都可以不設期限。
enum QuestType { main, side, daily }

extension QuestTypeInfo on QuestType {
  String get label => switch (this) {
        QuestType.main => '主線任務',
        QuestType.side => '支線任務',
        QuestType.daily => '每日委託',
      };

  IconData get icon => switch (this) {
        QuestType.main => Icons.auto_awesome,
        QuestType.side => Icons.explore_outlined,
        QuestType.daily => Icons.wb_sunny_outlined,
      };

  /// 從存檔讀分類。舊版的「記事」(memo) 已移除，讀到時歸到支線。
  static QuestType parse(String name) =>
      QuestType.values.asNameMap()[name] ?? QuestType.side;
}

/// 大事件底下的一個細項。每個未完成的細項會在通知欄顯示一則通知，
/// 通知 id 就是細項的 id。
class QuestStep {
  QuestStep({
    required this.id,
    required this.title,
    this.note = '',
    this.deadline,
    this.done = false,
  });

  final int id;
  String title;
  String note;
  DateTime? deadline; // null 表示沒有時間限制
  bool done;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'deadline': deadline?.toIso8601String(),
        'done': done,
      };

  factory QuestStep.fromJson(Map<String, dynamic> j) => QuestStep(
        id: j['id'] as int,
        title: j['title'] as String,
        note: (j['note'] as String?) ?? '',
        deadline: j['deadline'] == null
            ? null
            : DateTime.parse(j['deadline'] as String),
        done: (j['done'] as bool?) ?? false,
      );
}

/// 大事件，例如「異象」，底下有多個細項。
class Quest {
  Quest({
    required this.id,
    required this.title,
    required this.type,
    List<QuestStep>? steps,
  }) : steps = steps ?? [];

  final int id;
  String title;
  QuestType type;
  final List<QuestStep> steps;

  bool get done => steps.isNotEmpty && steps.every((s) => s.done);
  int get doneCount => steps.where((s) => s.done).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.name,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory Quest.fromJson(Map<String, dynamic> j) => Quest(
        id: j['id'] as int,
        title: j['title'] as String,
        type: QuestTypeInfo.parse(j['type'] as String),
        steps: (j['steps'] as List)
            .map((s) => QuestStep.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

/// 整個 App 存檔的內容。
class AppData {
  AppData({required this.nextId, this.lastReset, List<Quest>? quests})
      : quests = quests ?? [];

  int nextId;
  String? lastReset; // 上次每日重置的日期（以凌晨 4 點為分界）
  final List<Quest> quests;

  int newId() => nextId++;

  /// 跨過凌晨 4 點就把每日委託改回未完成。有變動時回傳 true。
  /// App 畫面、通知欄的背景處理、開機補發都會呼叫，所以放在資料層。
  bool applyDailyReset(DateTime now) {
    final key = resetDayKey(now);
    if (lastReset == key) return false;
    if (lastReset != null) {
      for (final q in quests.where((q) => q.type == QuestType.daily)) {
        for (final s in q.steps) {
          s.done = false;
        }
      }
    }
    lastReset = key;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'nextId': nextId,
        'lastReset': lastReset,
        'quests': quests.map((q) => q.toJson()).toList(),
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        nextId: j['nextId'] as int,
        lastReset: j['lastReset'] as String?,
        quests: (j['quests'] as List)
            .map((q) => Quest.fromJson(q as Map<String, dynamic>))
            .toList(),
      );

  /// 第一次開啟時的範例資料。
  factory AppData.sample() {
    final d = AppData(nextId: 1);
    final now = DateTime.now();
    QuestStep step(String t, {String note = '', DateTime? deadline, bool done = false}) =>
        QuestStep(id: d.newId(), title: t, note: note, deadline: deadline, done: done);

    d.quests.addAll([
      Quest(id: d.newId(), title: '每日委託', type: QuestType.daily, steps: [
        step('喝水 2000cc'),
        step('運動 30 分鐘'),
      ]),
      Quest(id: d.newId(), title: '踏上 Flutter 之旅', type: QuestType.main, steps: [
        step('安裝開發環境', done: true),
        step('做出第一個畫面',
            note: '試著改改看 lib/ui/home_page.dart',
            deadline: now.add(const Duration(days: 3))),
      ]),
      Quest(id: d.newId(), title: '整理房間', type: QuestType.side, steps: [
        step('洗衣服', deadline: now.add(const Duration(hours: 20))),
      ]),
      Quest(id: d.newId(), title: '購物清單', type: QuestType.side, steps: [
        step('牛奶'),
        step('電池'),
      ]),
    ]);
    return d;
  }
}

/// 每日重置以凌晨 4 點為分界（跟原神一樣）。
String resetDayKey(DateTime now) {
  final d = now.subtract(const Duration(hours: 4));
  return '${d.year}-${d.month}-${d.day}';
}

/// 下一次每日重置的時間（凌晨 4:00）。
DateTime nextResetTime(DateTime now) {
  final today4 = DateTime(now.year, now.month, now.day, 4);
  return now.isBefore(today4) ? today4 : DateTime(now.year, now.month, now.day + 1, 4);
}

/// 通知欄用的期限文字。通知發出後 App 不一定會再更新它，
/// 所以用固定的截止時間（「截止 11/12（三）18:00」），不用會過時的「剩幾小時」。
String notificationDeadlineText(QuestStep s, QuestType type, DateTime now) {
  final d = s.deadline;
  if (d == null) return type == QuestType.daily ? '每日 04:00 重置' : '無期限';
  const week = ['一', '二', '三', '四', '五', '六', '日'];
  String two(int n) => n.toString().padLeft(2, '0');
  final text = '${d.month}/${d.day}（${week[d.weekday - 1]}）${two(d.hour)}:${two(d.minute)}';
  return d.isBefore(now) ? '已逾期・$text' : '截止 $text';
}

/// 「剩 2 天 5 小時」、「無期限」、「已逾期」之類的文字。
String deadlineText(QuestStep s, QuestType type, DateTime now) {
  final d = s.deadline;
  if (d == null) {
    return type == QuestType.daily ? '每日 04:00 重置' : '無期限';
  }
  final diff = d.difference(now);
  if (diff.isNegative) return '已逾期・${formatDateTime(d)}';
  if (diff.inDays >= 1) return '剩 ${diff.inDays} 天 ${diff.inHours % 24} 小時';
  if (diff.inHours >= 1) return '剩 ${diff.inHours} 小時 ${diff.inMinutes % 60} 分';
  return '剩 ${diff.inMinutes} 分鐘';
}

String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.month}/${d.day} ${two(d.hour)}:${two(d.minute)}';
}
