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
    expect(data.applyDailyReset(DateTime(2026, 11, 9, 3, 59)), isFalse);
    expect(data.applyDailyReset(DateTime(2026, 11, 9, 4, 1)), isTrue);
    expect(data.quests[0].steps[0].done, isFalse);
    expect(data.quests[1].steps[0].done, isTrue);
  });

  test('通知用固定的截止時間', () {
    final now = DateTime(2026, 11, 9, 12);
    final s = QuestStep(id: 1, title: 'x', deadline: DateTime(2026, 11, 11, 18, 5));
    expect(notificationDeadlineText(s, QuestType.main, now), '截止 11/11（三）18:05');
    s.deadline = DateTime(2026, 11, 8, 9, 0);
    expect(notificationDeadlineText(s, QuestType.main, now), '已逾期・11/8（日）09:00');
  });

  test('分頁順序是主線、支線、每日', () {
    expect(QuestType.values, [QuestType.main, QuestType.side, QuestType.daily]);
  });

  test('舊存檔裡的「記事」讀進來會歸到支線', () {
    final q = Quest.fromJson({'id': 1, 'title': '購物清單', 'type': 'memo', 'steps': []});
    expect(q.type, QuestType.side);
  });
}
