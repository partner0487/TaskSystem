import 'package:flutter_test/flutter_test.dart';
import 'package:task_system/models.dart';

void main() {
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

  test('每週一三五：週二早上不重置，週三早上重置', () {
    const mwf = [DateTime.monday, DateTime.wednesday, DateTime.friday];
    final tue = weekly('2026-11-9', days: mwf)..applyResets(DateTime(2026, 11, 10, 8));
    expect(tue.quests[0].steps[0].done, isTrue);
    final wed = weekly('2026-11-10', days: mwf)..applyResets(DateTime(2026, 11, 11, 8));
    expect(wed.quests[0].steps[0].done, isFalse);
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
