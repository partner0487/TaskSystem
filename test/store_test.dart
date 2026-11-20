import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_system/models.dart';
import 'package:task_system/notifications.dart';
import 'package:task_system/store.dart';

/// 假的存檔：像手機上的一樣存成 JSON 字串，每次讀取都產生全新的物件。
class FakeStorage {
  String json = jsonEncode(AppData(nextId: 10, quests: [
    Quest(id: 1, title: '生病', type: QuestType.daily, steps: [QuestStep(id: 2, title: '午餐後吃藥')]),
  ]).toJson());

  /// 讓讀取變慢，模擬「回到前景重新讀取」還在進行中。
  Duration readDelay = Duration.zero;

  Future<AppData> read() async {
    final snapshot = json;
    await Future<void>.delayed(readDelay);
    return AppData.fromJson(jsonDecode(snapshot) as Map<String, dynamic>);
  }

  Future<void> write(AppData d) async => json = jsonEncode(d.toJson());

  AppData get saved => AppData.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

void main() {
  late FakeStorage storage;
  late QuestStore store;

  setUp(() async {
    storage = FakeStorage();
    store = QuestStore(read: storage.read, write: storage.write, syncNotifications: (_) async {});
    await store.reload();
  });

  test('新增表單開著時 App 回到前景（重新讀取），按下新增仍然會存進去', () async {
    final staleQuest = store.quests.first; // 表單打開時拿到的大事件
    await store.reload(); // 切到別的 App / 拉下通知欄再回來

    expect(identical(staleQuest, store.quests.first), isFalse); // 已經是新的物件了
    final ok = await store.addStep(staleQuest, title: '晚餐後吃藥');

    expect(ok, isTrue);
    expect(store.quests.first.steps.map((s) => s.title), ['午餐後吃藥', '晚餐後吃藥']);
    expect(storage.saved.quests.first.steps.map((s) => s.title), contains('晚餐後吃藥'));
  });

  test('編輯、打勾、刪除用的是舊物件，也會改到目前的資料', () async {
    final staleStep = store.quests.first.steps.first;
    await store.reload();

    expect(await store.updateStep(staleStep, title: '午餐後吃藥（飯後 30 分）', note: '', weekdays: const []),
        isTrue);
    expect(storage.saved.quests.first.steps.first.title, '午餐後吃藥（飯後 30 分）');

    expect(await store.toggleStep(staleStep), isTrue);
    expect(storage.saved.quests.first.steps.first.done, isTrue);

    await store.deleteStep(store.quests.first, staleStep);
    expect(storage.saved.quests.first.steps, isEmpty);
  });

  test('重新讀取還在進行時按下新增，兩件事依序執行，不會互相蓋掉', () async {
    final quest = store.quests.first;
    storage.readDelay = const Duration(milliseconds: 50);

    final reloading = store.reload(); // 讀取中（還沒讀完）
    final adding = store.addStep(quest, title: '晚餐後吃藥'); // 同時按下新增
    await Future.wait([reloading, adding]);

    expect(await adding, isTrue);
    expect(storage.saved.quests.first.steps.map((s) => s.title), contains('晚餐後吃藥'));
  });

  group('追蹤', () {
    setUp(() async {
      storage.json = jsonEncode(AppData(nextId: 10, quests: [
        Quest(id: 1, title: '生病', type: QuestType.daily, steps: [
          QuestStep(id: 2, title: '午餐後吃藥'),
          QuestStep(id: 3, title: '晚餐後吃藥'),
        ]),
      ]).toJson());
      await store.reload();
    });

    List<bool> trackedOf() => store.quests.first.steps.map((s) => s.tracked).toList();

    test('細項：單純切換追蹤 / 取消追蹤，取消後就不會出現在通知欄', () async {
      final now = DateTime(2026, 11, 20, 12);
      final s = store.quests.first.steps.first;
      expect(showsInNotificationBar(store.quests.first, s, now), isTrue);

      expect(await store.toggleStepTracked(s), isFalse);
      expect(showsInNotificationBar(store.quests.first, store.quests.first.steps.first, now), isFalse);
      expect(storage.saved.quests.first.steps.first.tracked, isFalse); // 有存檔

      expect(await store.toggleStepTracked(s), isTrue);
      expect(showsInNotificationBar(store.quests.first, store.quests.first.steps.first, now), isTrue);
    });

    test('大事件：全部追蹤中 → 按下全部取消追蹤', () async {
      expect(store.quests.first.allTracked, isTrue);
      expect(await store.toggleQuestTracked(store.quests.first), isFalse);
      expect(trackedOf(), [false, false]);
    });

    test('大事件：只要有一個沒追蹤 → 按下全部追蹤', () async {
      await store.toggleStepTracked(store.quests.first.steps.first); // 只取消一個
      expect(store.quests.first.allTracked, isFalse);
      expect(await store.toggleQuestTracked(store.quests.first), isTrue);
      expect(trackedOf(), [true, true]);
    });

    test('大事件：全部取消後再按一次 → 全部追蹤', () async {
      await store.toggleQuestTracked(store.quests.first);
      expect(trackedOf(), [false, false]);
      await store.toggleQuestTracked(store.quests.first);
      expect(trackedOf(), [true, true]);
    });
  });

  group('通知欄的按鈕', () {
    test('按「放棄」：細項變成已放棄並存檔（之前的 bug：放棄沒有被寫進去）', () async {
      final id = store.quests.first.steps.first.id;
      await store.handleNotificationAction(Notifier.actionAbandon, id);
      expect(store.quests.first.steps.first.abandoned, isTrue);
      expect(storage.saved.quests.first.steps.first.abandoned, isTrue);
    });

    test('按「完成」：細項變成已完成並存檔', () async {
      final id = store.quests.first.steps.first.id;
      await store.handleNotificationAction(Notifier.actionComplete, id);
      expect(storage.saved.quests.first.steps.first.done, isTrue);
    });

    test('背景直接改資料時，「放棄」也會套用（App 沒開的情況）', () {
      final data = storage.saved;
      applyNotificationAction(data, abandonStepId: data.quests.first.steps.first.id);
      expect(data.quests.first.steps.first.abandoned, isTrue);
    });

    test('回到前景重新讀取：沒有變動就不寫回存檔，不會蓋掉背景剛寫入的修改', () async {
      var writes = 0;
      final counting = QuestStore(
        read: storage.read,
        write: (d) async {
          writes++;
          await storage.write(d);
        },
        syncNotifications: (_) async {},
      );
      await counting.reload(); // 第一次讀：lastReset 是空的 → 會設定並寫入
      writes = 0;
      await counting.reload();
      expect(writes, 0);
    });
  });

  test('清除已完成：只清細項，大事件就算清空了也保留', () async {
    storage.json = jsonEncode(AppData(nextId: 10, quests: [
      Quest(id: 1, title: '全部做完的', type: QuestType.main, steps: [
        QuestStep(id: 2, title: 'a', done: true),
        QuestStep(id: 3, title: 'b', abandoned: true),
      ]),
      Quest(id: 4, title: '還有要做的', type: QuestType.side, steps: [
        QuestStep(id: 5, title: 'c', done: true),
        QuestStep(id: 6, title: 'd'),
      ]),
      Quest(id: 7, title: '每日', type: QuestType.daily, steps: [
        QuestStep(id: 8, title: 'e', done: true), // 每日 / 每週會自己重置，不清
      ]),
    ]).toJson());
    await store.reload();

    expect(await store.clearCompleted(), 3);
    expect(store.quests.map((q) => q.title), ['全部做完的', '還有要做的', '每日']);
    expect(store.quests[0].steps, isEmpty);
    expect(store.quests[1].steps.map((s) => s.title), ['d']);
    expect(store.quests[2].steps.single.done, isTrue);
  });

  group('放棄', () {
    final noon = DateTime(2026, 11, 20, 12);

    test('放棄後不出現在通知欄、不提醒，可以復原', () async {
      final s = store.quests.first.steps.first;
      expect(await store.toggleAbandon(s), isTrue);
      final now = store.quests.first.steps.first;
      expect(now.abandoned, isTrue);
      expect(now.closed, isTrue);
      expect(showsInNotificationBar(store.quests.first, now, noon), isFalse);

      await store.undo();
      expect(store.quests.first.steps.first.abandoned, isFalse);
    });

    test('取消放棄 → 回到未完成；已放棄的按 ✓ → 改成完成', () async {
      final s = store.quests.first.steps.first;
      await store.toggleAbandon(s);
      expect(await store.toggleAbandon(s), isFalse);
      expect(store.quests.first.steps.first.closed, isFalse);

      await store.toggleAbandon(s);
      expect(await store.toggleStep(s), isTrue);
      final after = store.quests.first.steps.first;
      expect([after.done, after.abandoned], [true, false]);
    });

    test('每日任務只放棄這一次：跨過凌晨 4 點就重新出現', () {
      final data = AppData(nextId: 10, lastReset: '2026-11-19', quests: [
        Quest(id: 1, title: '生病', type: QuestType.daily,
            steps: [QuestStep(id: 2, title: '吃藥', abandoned: true)]),
      ]);
      data.applyResets(DateTime(2026, 11, 20, 8));
      expect(data.quests.first.steps.first.abandoned, isFalse);
    });

    test('有放棄的細項時，提醒不再排', () {
      final s = QuestStep(
          id: 1, title: '報告', deadline: DateTime(2026, 11, 21, 18), remindBefore: 60, abandoned: true);
      expect(nextReminderTime(QuestType.main, s, noon), isNull);
    });

    test('清除已完成也會清掉已放棄的主線 / 支線', () async {
      storage.json = jsonEncode(AppData(nextId: 10, quests: [
        Quest(id: 1, title: '專題', type: QuestType.main, steps: [
          QuestStep(id: 2, title: '放棄的', abandoned: true),
          QuestStep(id: 3, title: '還要做的'),
        ]),
      ]).toJson());
      await store.reload();
      expect(await store.clearCompleted(), 1);
      expect(store.quests.first.steps.map((s) => s.title), ['還要做的']);
    });

    test('全部完成或放棄 = 大事件已完成', () {
      final q = Quest(id: 1, title: 'x', type: QuestType.main, steps: [
        QuestStep(id: 2, title: 'a', done: true),
        QuestStep(id: 3, title: 'b', abandoned: true),
      ]);
      expect(q.done, isTrue);
    });
  });

  test('舊存檔沒有放棄欄位 = 沒放棄', () {
    expect(QuestStep.fromJson({'id': 1, 'title': 's'}).abandoned, isFalse);
  });

  test('舊存檔沒有追蹤欄位 = 追蹤中', () {
    final q = Quest.fromJson({
      'id': 1, 'title': '舊', 'type': 'main',
      'steps': [{'id': 2, 'title': 's'}],
    });
    expect(q.steps.first.tracked, isTrue);
  });

  test('舊版把取消追蹤記在大事件上：讀取時改成底下細項都取消追蹤', () {
    final q = Quest.fromJson({
      'id': 1, 'title': '舊', 'type': 'main', 'tracked': false,
      'steps': [{'id': 2, 'title': 'a'}, {'id': 3, 'title': 'b'}],
    });
    expect(q.steps.map((s) => s.tracked), [false, false]);
    expect(q.toJson().containsKey('tracked'), isFalse);
  });

  test('大事件已經被刪掉時，新增會回報失敗（畫面會跳出提示）', () async {
    final quest = store.quests.first;
    await store.deleteQuest(quest);
    expect(await store.addStep(quest, title: '晚餐後吃藥'), isFalse);
  });
}
