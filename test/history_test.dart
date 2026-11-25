import 'package:flutter_test/flutter_test.dart';
import 'package:task_system/models.dart';

// 2026-11-23 是週一
void main() {
  List<String> log(AppData d) =>
      d.history.map((e) => '${e.kind.name} ${e.title} ${e.at.month}/${e.at.day}').toList();

  group('完成 / 放棄', () {
    test('打勾記一筆「完成」；取消打勾就拿掉', () {
      final q = Quest(id: 1, title: '專題', type: QuestType.main, steps: [QuestStep(id: 2, title: '報告')]);
      final d = AppData(nextId: 10, quests: [q]);
      final now = DateTime(2026, 11, 23, 10);

      d.setStepState(q, q.steps.first, done: true, abandoned: false, now: now);
      expect(log(d), ['done 報告 11/23']);
      expect(d.history.single.questTitle, '專題');

      d.setStepState(q, q.steps.first, done: false, abandoned: false, now: now);
      expect(d.history, isEmpty);
    });

    test('放棄記一筆「放棄」；放棄後改成完成 → 放棄那筆拿掉、記完成', () {
      final q = Quest(id: 1, title: '專題', type: QuestType.main, steps: [QuestStep(id: 2, title: '報告')]);
      final d = AppData(nextId: 10, quests: [q]);
      final now = DateTime(2026, 11, 23, 10);

      d.setStepState(q, q.steps.first, done: false, abandoned: true, now: now);
      expect(log(d), ['abandoned 報告 11/23']);
      d.setStepState(q, q.steps.first, done: true, abandoned: false, now: now);
      expect(log(d), ['done 報告 11/23']);
    });
  });

  group('主線 / 支線：截止時間到了還沒完成 → 錯過', () {
    AppData withReport({bool done = false}) => AppData(nextId: 10, lastReset: '2026-11-23', quests: [
          Quest(id: 1, title: '專題', type: QuestType.main, steps: [
            QuestStep(id: 2, title: '報告', deadline: DateTime(2026, 11, 23, 18), done: done),
          ]),
        ]);

    test('截止前不記，截止後記一筆（時間是截止時間），而且只記一次', () {
      final d = withReport();
      expect(d.applyResets(DateTime(2026, 11, 23, 17, 59)), isFalse);
      expect(d.history, isEmpty);

      expect(d.applyResets(DateTime(2026, 11, 23, 18, 30)), isTrue); // 有變動 → 會存檔
      expect(log(d), ['missed 報告 11/23']);
      expect(d.history.single.at, DateTime(2026, 11, 23, 18));

      d.applyResets(DateTime(2026, 11, 23, 20));
      expect(d.history, hasLength(1));
    });

    test('截止前就完成了 → 不記錯過', () {
      final d = withReport(done: true);
      d.applyResets(DateTime(2026, 11, 24, 9));
      expect(d.history, isEmpty);
    });

    test('逾期後才完成 → 錯過和完成兩筆都留著', () {
      final d = withReport();
      d.applyResets(DateTime(2026, 11, 23, 19));
      final q = d.quests.first;
      d.setStepState(q, q.steps.first, done: true, abandoned: false, now: DateTime(2026, 11, 23, 21));
      expect(log(d), ['missed 報告 11/23', 'done 報告 11/23']);
    });

    test('沒有截止時間的不會有錯過', () {
      final d = AppData(nextId: 10, lastReset: '2026-11-23', quests: [
        Quest(id: 1, title: '購物', type: QuestType.side, steps: [QuestStep(id: 2, title: '牛奶')]),
      ]);
      d.applyResets(DateTime(2026, 12, 1));
      expect(d.history, isEmpty);
    });
  });

  group('每日 / 每週：每日結算沒做 → 錯過', () {
    AppData daily({required String lastReset, bool done = false}) =>
        AppData(nextId: 10, lastReset: lastReset, quests: [
          Quest(id: 1, title: '生病', type: QuestType.daily, steps: [
            QuestStep(id: 2, title: '吃藥', done: done),
          ]),
        ]);

    test('今天沒做，隔天結算記一筆（記在今天）', () {
      final d = daily(lastReset: '2026-11-23');
      d.applyResets(DateTime(2026, 11, 24, 9));
      expect(log(d), ['missed 吃藥 11/23']);
    });

    test('有做就不記', () {
      final d = daily(lastReset: '2026-11-23', done: true);
      d.applyResets(DateTime(2026, 11, 24, 9));
      expect(d.history, isEmpty);
    });

    test('好幾天沒打開 App：中間每一天都算沒做', () {
      final d = daily(lastReset: '2026-11-23', done: true); // 週一有做
      d.applyResets(DateTime(2026, 11, 26, 9)); // 週四才打開
      expect(log(d), ['missed 吃藥 11/24', 'missed 吃藥 11/25']);
    });

    test('凌晨 3 點還算前一天，不會提早結算', () {
      final d = daily(lastReset: '2026-11-23');
      d.applyResets(DateTime(2026, 11, 24, 3));
      expect(d.history, isEmpty);
    });

    test('每週一、三：只有輪到的日子才記', () {
      final d = AppData(nextId: 10, lastReset: '2026-11-23', quests: [
        Quest(id: 1, title: '運動', type: QuestType.weekly, steps: [
          QuestStep(id: 2, title: '跑步', weekdays: const [DateTime.monday, DateTime.wednesday]),
        ]),
      ]);
      d.applyResets(DateTime(2026, 11, 27, 9)); // 週五
      expect(log(d), ['missed 跑步 11/23', 'missed 跑步 11/25']);
    });

    test('沒選星期幾的每週任務：週日結算一次', () {
      AppData weekly({bool done = false}) => AppData(nextId: 10, lastReset: '2026-11-20', quests: [
            Quest(id: 1, title: '家事', type: QuestType.weekly, steps: [
              QuestStep(id: 2, title: '打掃', done: done),
            ]),
          ]);
      final notDone = weekly()..applyResets(DateTime(2026, 11, 24, 9)); // 週五 → 下週二
      expect(log(notDone), ['missed 打掃 11/22']);
      final done = weekly(done: true)..applyResets(DateTime(2026, 11, 24, 9));
      expect(done.history, isEmpty);
    });

    test('放棄的不算錯過（已經記過放棄了）', () {
      final d = AppData(nextId: 10, lastReset: '2026-11-23', quests: [
        Quest(id: 1, title: '生病', type: QuestType.daily, steps: [
          QuestStep(id: 2, title: '吃藥', abandoned: true),
        ]),
      ]);
      d.applyResets(DateTime(2026, 11, 24, 9));
      expect(d.history, isEmpty);
    });
  });

  test('超過 90 天的紀錄會自動刪掉', () {
    final d = AppData(nextId: 10, lastReset: '2026-11-23', history: [
      HistoryEntry(stepId: 1, title: '舊的', questTitle: 'q', type: QuestType.main,
          kind: HistoryKind.done, at: DateTime(2026, 8, 1)),
      HistoryEntry(stepId: 2, title: '新的', questTitle: 'q', type: QuestType.main,
          kind: HistoryKind.done, at: DateTime(2026, 11, 1)),
    ]);
    d.applyResets(DateTime(2026, 11, 23, 12));
    expect(d.history.map((e) => e.title), ['新的']);
  });

  test('紀錄會跟著存檔 / 備份；舊存檔沒有紀錄也讀得進來', () {
    final d = AppData(nextId: 10, history: [
      HistoryEntry(stepId: 1, title: '報告', questTitle: '專題', type: QuestType.side,
          kind: HistoryKind.abandoned, at: DateTime(2026, 11, 23, 14, 5)),
    ]);
    final back = AppData.fromJson(d.toJson());
    expect(back.history.single.toJson(), d.history.single.toJson());
    expect(AppData.fromJson({'nextId': 1, 'quests': []}).history, isEmpty);
  });
}
