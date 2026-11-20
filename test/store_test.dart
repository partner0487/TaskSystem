import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_system/models.dart';
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
