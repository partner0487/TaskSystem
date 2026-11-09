import 'package:flutter/material.dart';

/// 任務分類，對應原神的「主線 / 支線 / 每週 / 每日」。
/// 宣告順序就是畫面上方分頁的順序。
/// 沒有期限的任務不另外分類：任何分類的細項都可以不設期限。
enum QuestType { main, side, weekly, daily }

extension QuestTypeInfo on QuestType {
  String get label => switch (this) {
        QuestType.main => '主線任務',
        QuestType.side => '支線任務',
        QuestType.weekly => '每週任務',
        QuestType.daily => '每日委託',
      };

  IconData get icon => switch (this) {
        QuestType.main => Icons.auto_awesome,
        QuestType.side => Icons.explore_outlined,
        QuestType.weekly => Icons.event_repeat,
        QuestType.daily => Icons.wb_sunny_outlined,
      };

  /// 每日 / 每週會定期自動重置。
  bool get recurring => this == QuestType.daily || this == QuestType.weekly;

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
    List<int>? weekdays,
    this.remindBefore,
  }) : weekdays = weekdays ?? [];

  final int id;
  String title;
  String note;
  DateTime? deadline; // null 表示沒有時間限制
  bool done;

  /// 每週任務在星期幾重置（1 = 週一 … 7 = 週日）。空的 = 每週一重置一次。
  List<int> weekdays;

  /// 截止前幾分鐘震動提醒，null = 不提醒。只有設定期限時才有作用。
  int? remindBefore;

  /// 每週任務實際的重置日。
  List<int> get resetWeekdays => weekdays.isEmpty ? const [DateTime.monday] : weekdays;

  /// 震動提醒的時間，沒有就回傳 null。
  DateTime? get remindAt {
    final d = deadline, m = remindBefore;
    if (d == null || m == null) return null;
    return d.subtract(Duration(minutes: m));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'deadline': deadline?.toIso8601String(),
        'done': done,
        'weekdays': weekdays,
        'remindBefore': remindBefore,
      };

  factory QuestStep.fromJson(Map<String, dynamic> j) => QuestStep(
        id: j['id'] as int,
        title: j['title'] as String,
        note: (j['note'] as String?) ?? '',
        deadline: j['deadline'] == null
            ? null
            : DateTime.parse(j['deadline'] as String),
        done: (j['done'] as bool?) ?? false,
        weekdays: ((j['weekdays'] as List?) ?? const []).cast<int>().toList(),
        remindBefore: j['remindBefore'] as int?,
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

  /// 跨過凌晨 4 點時重置：每日委託全部改回未完成；
  /// 每週任務只有「經過了它的重置日」才改回未完成。有變動時回傳 true。
  /// App 畫面、通知欄的背景處理、開機補發都會呼叫，所以放在資料層。
  bool applyResets(DateTime now) {
    final today = gameDay(now);
    final key = dayKey(today);
    if (lastReset == key) return false;

    final last = parseDayKey(lastReset);
    if (last != null) {
      // 上次重置之後（不含）到今天（含）經過了哪些星期幾。超過 7 天就是全部。
      final passed = <int>{};
      for (var i = 0; i < 7; i++) {
        final d = DateTime(today.year, today.month, today.day - i);
        if (!d.isAfter(last)) break;
        passed.add(d.weekday);
      }
      for (final q in quests) {
        for (final s in q.steps) {
          if (q.type == QuestType.daily && passed.isNotEmpty ||
              q.type == QuestType.weekly && s.resetWeekdays.any(passed.contains)) {
            s.done = false;
          }
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
    QuestStep step(String t,
            {String note = '', DateTime? deadline, bool done = false, List<int>? weekdays}) =>
        QuestStep(
            id: d.newId(), title: t, note: note, deadline: deadline, done: done, weekdays: weekdays);

    d.quests.addAll([
      Quest(id: d.newId(), title: '每日委託', type: QuestType.daily, steps: [
        step('喝水 2000cc'),
      ]),
      Quest(id: d.newId(), title: '健身', type: QuestType.weekly, steps: [
        step('運動 30 分鐘', weekdays: [DateTime.monday, DateTime.wednesday, DateTime.friday]),
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

const weekNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 「遊戲日」：以凌晨 4 點為一天的分界（跟原神一樣），凌晨 3 點還算前一天。
DateTime gameDay(DateTime now) {
  final d = now.subtract(const Duration(hours: 4));
  return DateTime(d.year, d.month, d.day);
}

String dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

String resetDayKey(DateTime now) => dayKey(gameDay(now));

DateTime? parseDayKey(String? key) {
  final parts = key?.split('-').map(int.tryParse).toList();
  if (parts == null || parts.length != 3 || parts.contains(null)) return null;
  return DateTime(parts[0]!, parts[1]!, parts[2]!);
}

/// 下一次每日重置的時間（凌晨 4:00）。
DateTime nextResetTime(DateTime now) {
  final today4 = DateTime(now.year, now.month, now.day, 4);
  return now.isBefore(today4) ? today4 : DateTime(now.year, now.month, now.day + 1, 4);
}

/// 今天（以凌晨 4 點為分界）這個細項該不該出現。
/// 有勾星期幾的每週任務只在那幾天出現；其它都是每天出現（直到完成）。
bool isActiveOn(QuestType type, QuestStep s, DateTime now) =>
    type != QuestType.weekly || s.weekdays.isEmpty || s.weekdays.contains(gameDay(now).weekday);

/// 這個細項下一次被重置（重新出現）的時間；主線 / 支線不會重置，回傳 null。
DateTime? nextResetFor(QuestType type, QuestStep s, DateTime now) {
  final first = nextResetTime(now);
  switch (type) {
    case QuestType.daily:
      return first;
    case QuestType.weekly:
      for (var i = 0; i < 7; i++) {
        final t = DateTime(first.year, first.month, first.day + i, 4);
        if (s.resetWeekdays.contains(t.weekday)) return t;
      }
      return null;
    case QuestType.main:
    case QuestType.side:
      return null;
  }
}

/// 「明天」或「週三」：已完成的每日 / 每週任務什麼時候會重新出現。
String nextResetLabel(DateTime resetAt, DateTime now) {
  // 用 UTC 日期相減，避開日光節約時間造成的 23 / 25 小時
  DateTime utc(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  final days = utc(gameDay(resetAt)).difference(utc(gameDay(now))).inDays;
  return days == 1 ? '明天' : '週${weekNames[resetAt.weekday - 1]}';
}

/// 「每週一、三、五」
String weekdaysText(QuestStep s) =>
    '每週${(s.resetWeekdays.toList()..sort()).map((d) => weekNames[d - 1]).join('、')}';

/// 沒設期限時顯示的文字。
String _noDeadlineText(QuestStep s, QuestType type) => switch (type) {
      QuestType.daily => '每日 04:00 重置',
      QuestType.weekly => s.weekdays.isEmpty ? '每週一 04:00 重置' : weekdaysText(s),
      _ => '無期限',
    };

/// 「1 小時」、「10 分鐘」、「1 天」
String durationText(int minutes) {
  if (minutes % 1440 == 0) return '${minutes ~/ 1440} 天';
  if (minutes % 60 == 0) return '${minutes ~/ 60} 小時';
  return '$minutes 分鐘';
}

/// 震動提醒的選項（分鐘），null = 不提醒。
const remindOptions = <int?>[null, 10, 60, 1440];

/// 通知欄用的期限文字。通知發出後 App 不一定會再更新它，
/// 所以用固定的截止時間（「截止 11/12（三）18:00」），不用會過時的「剩幾小時」。
String notificationDeadlineText(QuestStep s, QuestType type, DateTime now) {
  final d = s.deadline;
  if (d == null) return _noDeadlineText(s, type);
  String two(int n) => n.toString().padLeft(2, '0');
  final text = '${d.month}/${d.day}（${weekNames[d.weekday - 1]}）${two(d.hour)}:${two(d.minute)}';
  return d.isBefore(now) ? '已逾期・$text' : '截止 $text';
}

/// 「剩 2 天 5 小時」、「無期限」、「已逾期」之類的文字。
String deadlineText(QuestStep s, QuestType type, DateTime now) {
  final d = s.deadline;
  if (d == null) return _noDeadlineText(s, type);
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
