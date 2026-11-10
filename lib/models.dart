import 'package:flutter/material.dart';

/// 任務分類：主線 / 支線 / 每週 / 每日。
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
        QuestType.side => Icons.new_releases_outlined, // 突發任務的「!」
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

/// 大事件，例如「期末報告」，底下有多個細項。
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

  /// 跨過凌晨 4 點時重置。有變動時回傳 true。
  /// - 每日委託、有選星期幾的每週任務：每天都改回未完成
  ///   （例如一三五的任務週一做完，週二會顯示「未完成、還沒輪到」，週三再出現）
  /// - 沒選星期幾的每週任務：經過週一才改回未完成（一週做一次）
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
          final perDay = q.type == QuestType.daily ||
              q.type == QuestType.weekly && s.weekdays.isNotEmpty;
          if (perDay && passed.isNotEmpty ||
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

    // 給第一次使用的人的教學：照著做一遍就會操作。
    d.quests.addAll([
      Quest(id: d.newId(), title: '新手教學', type: QuestType.main, steps: [
        step('點一下這張卡片',
            note: '選中的卡片會展開備註。\n長按卡片可以編輯，往左滑可以刪除。'),
        step('按右邊的 ✓ 完成這一項', note: '完成後，通知欄裡的這一則也會消失。'),
        step('拉下通知欄看看',
            note: '每個未完成的細項都會常駐在通知欄，\n展開通知可以直接按「✓ 完成」，不用打開 App。',
            deadline: now.add(const Duration(days: 3))),
        step('用右下角的 ＋ 新增自己的任務',
            note: '主線、支線可以設期限和震動提醒；\n教學做完可以從標題右邊的 ⋮ 刪除整個「新手教學」。'),
      ]),
      Quest(id: d.newId(), title: '購物清單', type: QuestType.side, steps: [
        step('牛奶'),
        step('電池'),
      ]),
      Quest(id: d.newId(), title: '健身', type: QuestType.weekly, steps: [
        step('運動 30 分鐘',
            note: '每週任務可以選星期幾，只在那幾天出現。',
            weekdays: [DateTime.monday, DateTime.wednesday, DateTime.friday]),
      ]),
      Quest(id: d.newId(), title: '每日委託', type: QuestType.daily, steps: [
        step('喝水 2000cc', note: '每日委託每天凌晨 4 點重新出現。'),
      ]),
    ]);
    return d;
  }
}

const weekNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 「任務日」：以凌晨 4 點為一天的分界，凌晨 3 點還算前一天（熬夜時任務不會被提早重置）。
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

/// 現在這個細項該不該出現（不管完成與否）。
/// - 每週任務：只在選的星期幾出現；過了自動期限（晚上 12 點）就結束，等下次再出現
/// - 其它：一直都在（直到完成）
bool isActiveOn(QuestType type, QuestStep s, DateTime now) {
  if (type != QuestType.weekly) return true;
  if (s.weekdays.isNotEmpty && !s.weekdays.contains(gameDay(now).weekday)) return false;
  final d = effectiveDeadline(type, s, now);
  return d == null || now.isBefore(d);
}

/// 細項的顯示順序：今天要做的 → 還沒輪到的（每週任務的休息日）→ 已完成。
/// 同一組裡維持使用者排好的順序。
List<QuestStep> displaySteps(QuestType type, List<QuestStep> steps, DateTime now) {
  bool active(QuestStep s) => isActiveOn(type, s, now);
  return [
    ...steps.where((s) => !s.done && active(s)),
    ...steps.where((s) => !s.done && !active(s)),
    ...steps.where((s) => s.done),
  ];
}

/// 大事件標題右邊的進度，只算「現在該做的」細項：「1/2」；全部都還沒輪到就是「休息中」。
String questProgress(QuestType type, Quest q, DateTime now) {
  if (q.done) return '已完成';
  final active = q.steps.where((s) => isActiveOn(type, s, now)).toList();
  if (q.steps.isNotEmpty && active.isEmpty) return '休息中';
  return '${active.where((s) => s.done).length}/${active.length}';
}

/// 下一次震動提醒的時間（沒有就回傳 null）：
/// - 主線 / 支線：截止時間往前推（已完成就不提醒）
/// - 每週任務：當次的截止時間（當天 / 週日 24:00）往前推；
///   當次已完成或提醒時間已過，就算下一次出現的那天
/// - 每日委託：不提醒
DateTime? nextReminderTime(QuestType type, QuestStep s, DateTime now) {
  final m = s.remindBefore;
  if (m == null) return null;
  if (!type.recurring) {
    final at = s.remindAt;
    return !s.done && at != null && at.isAfter(now) ? at : null;
  }
  if (type != QuestType.weekly) return null;

  DateTime? remindFor(DateTime when) =>
      effectiveDeadline(type, s, when)?.subtract(Duration(minutes: m));

  // 這一次（今天輪到、還沒做）
  if (!s.done && isActiveOn(type, s, now)) {
    final at = remindFor(now);
    if (at != null && at.isAfter(now)) return at;
  }
  // 下一次出現的那天
  final next = nextResetFor(type, s, now);
  if (next == null) return null;
  final at = remindFor(next);
  return at != null && at.isAfter(now) ? at : null;
}

/// 主線 / 支線逾期多久後從通知欄移除（App 裡仍保留）。
const overdueHideAfter = Duration(days: 7);

/// 主線 / 支線從通知欄移除的時間；沒有期限或每日 / 每週任務回傳 null。
DateTime? notificationHideAt(QuestType type, QuestStep s) {
  final d = s.deadline;
  if (type.recurring || d == null) return null;
  return d.add(overdueHideAfter);
}

/// 已逾期太久，不再顯示在通知欄。
bool isStale(QuestType type, QuestStep s, DateTime now) {
  final t = notificationHideAt(type, s);
  return t != null && !now.isBefore(t);
}

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
  final d = effectiveDeadline(type, s, now);
  if (d == null) return _noDeadlineText(s, type);
  final text = formatDateTime(d, withWeekday: true);
  return d.isBefore(now) ? '已逾期・$text' : '截止 $text';
}

/// 實際用來倒數的截止時間：
/// - 主線 / 支線 → 自己設定的期限（可以沒有）
/// - 每日 → 沒有期限（每天 04:00 重置）
/// - 每週、有選星期幾 → 當天晚上 12 點
/// - 每週、沒選星期幾 → 這週日晚上 12 點
/// 每日 / 每週有自動規則，會忽略手動設定的期限。
DateTime? effectiveDeadline(QuestType type, QuestStep s, DateTime now) {
  if (!type.recurring) return s.deadline;
  if (type != QuestType.weekly) return null;
  final day = gameDay(now);
  if (s.weekdays.isNotEmpty) {
    if (!s.weekdays.contains(day.weekday)) return null; // 今天不是它的日子
    return DateTime(day.year, day.month, day.day + 1); // 當天 24:00
  }
  return DateTime(day.year, day.month, day.day + (DateTime.sunday - day.weekday) + 1); // 週日 24:00
}

/// 倒數文字：
/// - 1 天以上：「剩 2 天 5 小時」
/// - 1 天以內：「剩 5 小時 30 分」
/// - 1 小時以內：「剩 12 分 30 秒」
String remainingText(Duration left) {
  if (left.inDays >= 1) return '剩 ${left.inDays} 天 ${left.inHours % 24} 小時';
  if (left.inHours >= 1) return '剩 ${left.inHours} 小時 ${left.inMinutes % 60} 分';
  return '剩 ${left.inMinutes} 分 ${left.inSeconds % 60} 秒';
}

/// 「剩 2 天 5 小時」、「無期限」、「已逾期」之類的文字。
String deadlineText(QuestStep s, QuestType type, DateTime now) {
  final d = effectiveDeadline(type, s, now);
  if (d == null) return _noDeadlineText(s, type);
  final left = d.difference(now);
  if (left.isNegative) return '已逾期・${formatDateTime(d)}';
  return remainingText(left);
}

/// 「11/15 18:00」；午夜顯示成前一天的「24:00」，比較符合「當天晚上 12 點前」的直覺。
/// [withWeekday] 時加上星期：「11/15（日）24:00」。
String formatDateTime(DateTime d, {bool withWeekday = false}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final midnight = d.hour == 0 && d.minute == 0;
  final day = midnight ? DateTime(d.year, d.month, d.day - 1) : d;
  final week = withWeekday ? '（${weekNames[day.weekday - 1]}）' : ' ';
  final time = midnight ? '24:00' : '${two(d.hour)}:${two(d.minute)}';
  return '${day.month}/${day.day}$week$time';
}
