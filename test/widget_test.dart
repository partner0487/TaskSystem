import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_system/backup.dart';
import 'package:task_system/models.dart';

void main() {
  group('備份', () {
    test('匯出再匯入，內容完全一樣', () {
      final data = AppData.sample();
      final back = decodeBackup(encodeBackup(data, DateTime(2026, 11, 10)));
      expect(back.toJson(), data.toJson());
      expect(backupSummary(back), '4 個大事件、8 個細項');
    });

    test('不是備份檔的內容會被拒絕，並給出看得懂的訊息', () {
      expect(() => decodeBackup('hello'), throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', '這個檔案不是任務系統的備份檔')));
      expect(() => decodeBackup('{"a": 1}'), throwsFormatException);
      expect(() => decodeBackup('[1, 2]'), throwsFormatException);
    });

    test('較新版本的備份會要求先更新 App', () {
      final text = jsonEncode({'format': 'task_system_backup', 'version': 99, 'data': {}});
      expect(() => decodeBackup(text), throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', contains('較新版本'))));
    });

    test('內容損毀時給出看得懂的訊息', () {
      final text = jsonEncode({'format': 'task_system_backup', 'version': 1, 'data': {'quests': 'x'}});
      expect(() => decodeBackup(text), throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', contains('損毀'))));
    });

    test('nextId 太小時自動修正，避免新任務跟舊的撞 id', () {
      final data = AppData(nextId: 1, quests: [
        Quest(id: 5, title: 'q', type: QuestType.main, steps: [QuestStep(id: 9, title: 's')]),
      ]);
      expect(decodeBackup(encodeBackup(data, DateTime(2026))).nextId, 10);
    });
  });

  test('存檔轉成 JSON 再讀回來，內容不變', () {
    final data = AppData.sample();
    final back = AppData.fromJson(data.toJson());
    expect(back.toJson(), data.toJson());
  });

  test('每日重置以凌晨 4 點為分界', () {
    expect(resetDayKey(DateTime(2026, 11, 9, 3, 59)), '2026-11-8');
    expect(resetDayKey(DateTime(2026, 11, 9, 4, 0)), '2026-11-9');
  });

  test('沒有期限的任務顯示「無期限」', () {
    final s = QuestStep(id: 1, title: '牛奶');
    expect(deadlineText(s, QuestType.side, DateTime.now()), '無期限');
    expect(deadlineText(s, QuestType.daily, DateTime.now()), '每日 04:00 重置');
  });

  test('下次重置時間：4 點前是今天 4 點，4 點後是明天 4 點', () {
    expect(nextResetTime(DateTime(2026, 11, 9, 3, 30)), DateTime(2026, 11, 9, 4));
    expect(nextResetTime(DateTime(2026, 11, 9, 4, 0)), DateTime(2026, 11, 10, 4));
    expect(nextResetTime(DateTime(2026, 11, 30, 23, 0)), DateTime(2026, 12, 1, 4));
  });

  test('跨過 4 點時，每日委託變回未完成，其它分類不受影響', () {
    final data = AppData(nextId: 10, lastReset: '2026-11-8', quests: [
      Quest(id: 1, title: '每日', type: QuestType.daily,
          steps: [QuestStep(id: 2, title: '喝水', done: true)]),
      Quest(id: 3, title: '主線', type: QuestType.main,
          steps: [QuestStep(id: 4, title: '讀書', done: true)]),
    ]);
    expect(data.applyResets(DateTime(2026, 11, 9, 3, 59)), isFalse);
    expect(data.applyResets(DateTime(2026, 11, 9, 4, 1)), isTrue);
    expect(data.quests[0].steps[0].done, isFalse);
    expect(data.quests[1].steps[0].done, isTrue);
  });

  // 2026-11-09 是週一
  AppData weekly(String lastReset, {List<int>? days}) => AppData(nextId: 10, lastReset: lastReset, quests: [
        Quest(id: 1, title: '健身', type: QuestType.weekly,
            steps: [QuestStep(id: 2, title: '運動', done: true, weekdays: days)]),
      ]);

  test('每週一三五：週一做完，週二顯示未完成但還沒輪到、週三再出現', () {
    const mwf = [DateTime.monday, DateTime.wednesday, DateTime.friday];
    final tue = weekly('2026-11-9', days: mwf)..applyResets(DateTime(2026, 11, 10, 8));
    final step = tue.quests[0].steps[0];
    expect(step.done, isFalse); // 週二早上：變回未完成
    expect(isActiveOn(QuestType.weekly, step, DateTime(2026, 11, 10, 8)), isFalse); // 但還沒輪到（不能打勾）
    expect(questProgress(QuestType.weekly, tue.quests[0], DateTime(2026, 11, 10, 8)), '休息中');
    expect(isActiveOn(QuestType.weekly, step, DateTime(2026, 11, 11, 8)), isTrue); // 週三出現
  });

  test('標題進度只算現在該做的細項', () {
    const sat = [DateTime.saturday];
    final q = Quest(id: 1, title: '運動', type: QuestType.weekly, steps: [
      QuestStep(id: 2, title: '跑步', done: true), // 沒選星期幾：整週都在
      QuestStep(id: 3, title: '籃球', weekdays: sat), // 週六才輪到
    ]);
    expect(questProgress(QuestType.weekly, q, DateTime(2026, 11, 10, 12)), '1/1');
    expect(questProgress(QuestType.weekly, q, DateTime(2026, 11, 14, 12)), '1/2');
  });

  test('細項顯示順序：要做的 → 還沒輪到的 → 已完成', () {
    final steps = [
      QuestStep(id: 1, title: '完成的', done: true),
      QuestStep(id: 2, title: '週六的', weekdays: const [DateTime.saturday]),
      QuestStep(id: 3, title: '今天的'),
    ];
    final order = displaySteps(QuestType.weekly, steps, DateTime(2026, 11, 10, 12)).map((s) => s.id);
    expect(order, [3, 2, 1]);
  });

  test('每週任務的震動提醒', () {
    final ball = QuestStep(
        id: 1, title: '籃球', weekdays: const [DateTime.saturday], remindBefore: 120);
    // 週二：提醒排在週六晚上 10 點（24:00 前 2 小時）
    expect(nextReminderTime(QuestType.weekly, ball, DateTime(2026, 11, 10, 12)),
        DateTime(2026, 11, 14, 22));
    // 週六晚上 11 點、還沒做：今天的提醒已經過了 → 排下週六
    expect(nextReminderTime(QuestType.weekly, ball, DateTime(2026, 11, 14, 23)),
        DateTime(2026, 11, 21, 22));
    // 週六下午做完 → 也是排下週六
    ball.done = true;
    expect(nextReminderTime(QuestType.weekly, ball, DateTime(2026, 11, 14, 15)),
        DateTime(2026, 11, 21, 22));
    // 每日委託不提醒；主線已完成不提醒
    expect(nextReminderTime(QuestType.daily, ball, DateTime(2026, 11, 10)), isNull);
    final report = QuestStep(
        id: 2, title: '報告', deadline: DateTime(2026, 11, 12, 18), remindBefore: 60, done: true);
    expect(nextReminderTime(QuestType.main, report, DateTime(2026, 11, 10)), isNull);
  });

  test('好幾天沒開 App，中間經過了重置日也會重置', () {
    // 上次是週二，下一次打開是週四：中間經過週三
    final d = weekly('2026-11-10', days: const [DateTime.wednesday])
      ..applyResets(DateTime(2026, 11, 12, 9));
    expect(d.quests[0].steps[0].done, isFalse);
  });

  test('每週沒選星期幾 = 每週一重置', () {
    final sun = weekly('2026-11-14')..applyResets(DateTime(2026, 11, 15, 9));
    expect(sun.quests[0].steps[0].done, isTrue);
    final mon = weekly('2026-11-15')..applyResets(DateTime(2026, 11, 16, 9));
    expect(mon.quests[0].steps[0].done, isFalse);
  });

  test('週六日籃球：週一不出現，週六、週日出現', () {
    final s = QuestStep(id: 1, title: '籃球', weekdays: const [DateTime.saturday, DateTime.sunday]);
    expect(isActiveOn(QuestType.weekly, s, DateTime(2026, 11, 9, 23)), isFalse); // 週一
    expect(isActiveOn(QuestType.weekly, s, DateTime(2026, 11, 14, 9)), isTrue); // 週六
    expect(isActiveOn(QuestType.weekly, s, DateTime(2026, 11, 15, 23, 59)), isTrue); // 週日晚上
    // 過了週日晚上 12 點：本次已結束（不是「已逾期」），直接消失
    expect(isActiveOn(QuestType.weekly, s, DateTime(2026, 11, 16, 0, 0)), isFalse);
    expect(isActiveOn(QuestType.weekly, s, DateTime(2026, 11, 16, 3)), isFalse);
    expect(isActiveOn(QuestType.weekly, s, DateTime(2026, 11, 16, 4)), isFalse); // 週一 4 點過後
    // 週六晚上 12 點後結束，週日凌晨 4 點再出現
    expect(isActiveOn(QuestType.weekly, s, DateTime(2026, 11, 15, 1)), isFalse);
    expect(nextResetFor(QuestType.weekly, s, DateTime(2026, 11, 15, 1)), DateTime(2026, 11, 15, 4));
    expect(isActiveOn(QuestType.weekly, s, DateTime(2026, 11, 15, 4)), isTrue);
    // 週一新增的籃球，下次在週六凌晨 4 點出現
    expect(nextResetFor(QuestType.weekly, s, DateTime(2026, 11, 9, 23)), DateTime(2026, 11, 14, 4));
    // 沒勾星期幾的每週任務、其它分類：每天都出現
    expect(isActiveOn(QuestType.weekly, QuestStep(id: 2, title: 'x'), DateTime(2026, 11, 9, 12)), isTrue);
    // 沒選星期幾：週日 24:00 截止 → 週一 00:00～04:00 本次已結束
    expect(isActiveOn(QuestType.weekly, QuestStep(id: 2, title: 'x'), DateTime(2026, 11, 9, 1)), isFalse);
    expect(isActiveOn(QuestType.daily, s, DateTime(2026, 11, 9)), isTrue);
  });

  test('每週任務的自動期限：有選星期幾 = 當天 24:00；沒選 = 週日 24:00', () {
    final ball = QuestStep(id: 1, title: '籃球', weekdays: const [DateTime.saturday, DateTime.sunday]);
    final sat = DateTime(2026, 11, 14, 20); // 週六晚上 8 點
    expect(effectiveDeadline(QuestType.weekly, ball, sat), DateTime(2026, 11, 15));
    expect(deadlineText(ball, QuestType.weekly, sat), '剩 4 小時 0 分');
    expect(notificationDeadlineText(ball, QuestType.weekly, sat), '截止 11/14（六）24:00');
    expect(effectiveDeadline(QuestType.weekly, ball, DateTime(2026, 11, 9, 12)), isNull); // 週一休息

    final anyDay = QuestStep(id: 2, title: '打掃');
    final mon = DateTime(2026, 11, 9, 12); // 週一中午
    expect(effectiveDeadline(QuestType.weekly, anyDay, mon), DateTime(2026, 11, 16));
    expect(deadlineText(anyDay, QuestType.weekly, mon), '剩 6 天 12 小時');

    // 主線用自己設的期限；每週 / 每日忽略手動期限，用自動規則
    final custom = QuestStep(id: 3, title: 'x', deadline: DateTime(2026, 11, 10, 9));
    expect(effectiveDeadline(QuestType.main, custom, mon), DateTime(2026, 11, 10, 9));
    expect(effectiveDeadline(QuestType.weekly, custom, mon), DateTime(2026, 11, 16));
    expect(effectiveDeadline(QuestType.daily, custom, mon), isNull);
    expect(effectiveDeadline(QuestType.main, anyDay, mon), isNull);
  });

  test('主線 / 支線逾期 7 天後移出通知欄，每週 / 每日不會', () {
    final s = QuestStep(id: 1, title: '交報告', deadline: DateTime(2026, 11, 1, 18));
    expect(notificationHideAt(QuestType.side, s), DateTime(2026, 11, 8, 18));
    expect(isStale(QuestType.side, s, DateTime(2026, 11, 8, 17, 59)), isFalse);
    expect(isStale(QuestType.side, s, DateTime(2026, 11, 8, 18)), isTrue);
    expect(isStale(QuestType.weekly, s, DateTime(2026, 12, 1)), isFalse);
    expect(isStale(QuestType.main, QuestStep(id: 2, title: '無期限'), DateTime(2030)), isFalse);
  });

  test('倒數文字的三種格式', () {
    expect(remainingText(const Duration(days: 2, hours: 5, minutes: 9)), '剩 2 天 5 小時');
    expect(remainingText(const Duration(hours: 5, minutes: 30, seconds: 9)), '剩 5 小時 30 分');
    expect(remainingText(const Duration(minutes: 12, seconds: 30)), '剩 12 分 30 秒');
    expect(remainingText(const Duration(seconds: 7)), '剩 0 分 7 秒');
  });

  test('午夜顯示成前一天的 24:00', () {
    expect(formatDateTime(DateTime(2026, 11, 16)), '11/15 24:00');
    expect(formatDateTime(DateTime(2026, 11, 16), withWeekday: true), '11/15（日）24:00');
    expect(formatDateTime(DateTime(2026, 11, 16, 9, 5)), '11/16 09:05');
  });

  test('下次重新出現的時間與文字', () {
    final s = QuestStep(id: 1, title: '運動', weekdays: const [1, 3, 5]);
    final mon = DateTime(2026, 11, 9, 20); // 週一晚上
    expect(nextResetFor(QuestType.weekly, s, mon), DateTime(2026, 11, 11, 4));
    expect(nextResetLabel(DateTime(2026, 11, 11, 4), mon), '週三');
    expect(nextResetFor(QuestType.daily, s, mon), DateTime(2026, 11, 10, 4));
    expect(nextResetLabel(DateTime(2026, 11, 10, 4), mon), '明天');
    expect(nextResetFor(QuestType.main, s, mon), isNull);
    expect(weekdaysText(s), '每週一、三、五');
  });

  test('提醒時間與文字', () {
    final s = QuestStep(id: 1, title: 'x', deadline: DateTime(2026, 11, 9, 18), remindBefore: 60);
    expect(s.remindAt, DateTime(2026, 11, 9, 17));
    expect(durationText(10), '10 分鐘');
    expect(durationText(60), '1 小時');
    expect(durationText(1440), '1 天');
  });

  test('通知用固定的截止時間', () {
    final now = DateTime(2026, 11, 9, 12);
    final s = QuestStep(id: 1, title: 'x', deadline: DateTime(2026, 11, 11, 18, 5));
    expect(notificationDeadlineText(s, QuestType.main, now), '截止 11/11（三）18:05');
    s.deadline = DateTime(2026, 11, 8, 9, 0);
    expect(notificationDeadlineText(s, QuestType.main, now), '已逾期・11/8（日）09:00');
  });

  test('分頁順序是主線、支線、每週、每日', () {
    expect(QuestType.values,
        [QuestType.main, QuestType.side, QuestType.weekly, QuestType.daily]);
  });

  test('舊存檔裡的「記事」讀進來會歸到支線', () {
    final q = Quest.fromJson({'id': 1, 'title': '購物清單', 'type': 'memo', 'steps': []});
    expect(q.type, QuestType.side);
  });
}
