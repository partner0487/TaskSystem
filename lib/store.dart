import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'auto_backup.dart';
import 'backup.dart';
import 'demo.dart';
import 'models.dart';
import 'notifications.dart';
import 'storage.dart';

/// App 的狀態中心：所有新增 / 修改 / 刪除都經過這裡，
/// 改完會存檔、通知畫面更新，並同步通知欄。
class QuestStore extends ChangeNotifier {
  /// 預設用手機上的存檔與通知欄；測試時可以換成假的。
  QuestStore({
    Future<AppData> Function()? read,
    Future<void> Function(AppData)? write,
    Future<void> Function(AppData)? syncNotifications,
    Future<void> Function(AppData)? dailyBackup,
  })  : _read = read ?? Storage.read,
        _write = write ?? Storage.write,
        _sync = syncNotifications ?? Notifier.sync,
        _dailyBackup = dailyBackup ??
            (demoMode ? (_) async {} : (d) => AutoBackup.runDaily(d, DateTime.now()));

  final Future<AppData> Function() _read;
  final Future<void> Function(AppData) _write;
  final Future<void> Function(AppData) _sync;
  final Future<void> Function(AppData) _dailyBackup;

  AppData _data = AppData(nextId: 1);
  bool loaded = false;

  List<Quest> get quests => _data.quests;

  /// 某個分類的大事件：未完成的排前面，已完成的沉到下面。
  List<Quest> questsOf(QuestType type) {
    final list = quests.where((q) => q.type == type).toList();
    final open = list.where((q) => !q.done);
    final closed = list.where((q) => q.done);
    return [...open, ...closed];
  }

  /// 分頁上的數字：今天該做、還沒做的細項數。
  int openStepCount(QuestType type) {
    final now = DateTime.now();
    return quests
        .where((q) => q.type == type)
        .expand((q) => q.steps)
        .where((s) => !s.closed && isActiveOn(type, s, now))
        .length;
  }

  // ---------- 依序執行 ----------

  /// 讀取 / 修改排隊依序執行，避免「回到前景重新讀取」剛好跟「按下新增」同時發生而互相蓋掉。
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  // ---------- 用 id 找「目前的」物件 ----------
  // 重新讀取存檔後，清單裡會是全新的物件；畫面（例如還開著的新增表單）手上可能還拿著舊的。
  // 所以修改時一律用 id 找出現在清單裡的那一筆，不直接改傳進來的物件。

  Quest? _quest(int id) {
    for (final q in quests) {
      if (q.id == id) return q;
    }
    return null;
  }

  (Quest, QuestStep)? _step(int id) {
    for (final q in quests) {
      for (final s in q.steps) {
        if (s.id == id) return (q, s);
      }
    }
    return null;
  }

  /// 從存檔重新讀取（App 啟動、回到前景、通知欄按了完成之後都會呼叫）。
  /// 只有真的有變動（跨過凌晨 4 點重置）才寫回存檔：
  /// 不然剛讀到的舊資料寫回去，可能會蓋掉背景同時寫入的修改。
  Future<void> reload() => _serial(() async {
        _data = await _read();
        final changed = _data.applyResets(DateTime.now());
        loaded = true;
        notifyListeners();
        if (changed) await _write(_data);
        await _sync(_data);
        // 每天第一次打開（或回到前景）時自動備份一次；失敗也不影響 App
        try {
          await _dailyBackup(_data);
        } catch (_) {}
      });

  /// 只重新同步通知欄（例如遊戲模式開關之後）。
  Future<void> resync() => _serial(() => _sync(_data));

  /// 從自動備份還原（可以復原）。
  Future<void> restoreAutoBackup(AppData data) => importBackup(data);

  /// App 開著時，通知欄的「完成」「放棄」「滑掉」由背景轉交到這裡，跟其它修改一起依序處理。
  Future<void> handleNotificationAction(String action, int stepId) => _serial(() async {
        _data.applyResets(DateTime.now());
        applyNotificationAction(
          _data,
          completeStepId: action == Notifier.actionComplete ? stepId : null,
          abandonStepId: action == Notifier.actionAbandon ? stepId : null,
        );
        await _commit(); // 「滑掉」也會同步，被滑掉的通知就補回來
      });

  /// App 開著的時候定時檢查，跨過凌晨 4 點就重置每日 / 每週任務。
  Future<void> checkDailyReset() => _serial(() async {
        if (_data.applyResets(DateTime.now())) await _commit();
      });

  Future<void> _commit() async {
    notifyListeners();
    await _write(_data);
    await _sync(_data);
  }

  // ---------- 復原 ----------

  /// 上一個可以復原的操作之前的資料快照（只保留一步）。
  String? _undoSnapshot;

  /// 在刪除 / 打勾 / 匯入之前呼叫，記下操作前的樣子。
  void _snapshot() => _undoSnapshot = jsonEncode(_data.toJson());

  /// 把資料還原成上一個操作之前的樣子。
  Future<void> undo() => _serial(() async {
        final snap = _undoSnapshot;
        if (snap == null) return;
        _undoSnapshot = null;
        _data = AppData.fromJson(jsonDecode(snap) as Map<String, dynamic>);
        await _commit();
      });

  // ---------- 備份 ----------

  String exportBackup() => encodeBackup(_data, DateTime.now());

  /// 用備份取代目前所有資料（可以復原）。[data] 來自 [decodeBackup]。
  Future<void> importBackup(AppData data) => _serial(() async {
        _snapshot();
        _data = data..applyResets(DateTime.now());
        await _commit();
      });

  // ---------- 大事件 ----------

  Future<void> addQuest(String title, QuestType type, {String? firstStep}) => _serial(() {
        final q = Quest(id: _data.newId(), title: title, type: type);
        if (firstStep != null && firstStep.trim().isNotEmpty) {
          q.steps.add(QuestStep(id: _data.newId(), title: firstStep.trim()));
        }
        quests.add(q);
        return _commit();
      });

  /// 回傳 false = 這個大事件已經不存在（例如被刪掉了）。
  Future<bool> updateQuest(Quest quest, {required String title, required QuestType type}) =>
      _serial(() async {
        final q = _quest(quest.id);
        if (q == null) return false;
        q
          ..title = title
          ..type = type;
        await _commit();
        return true;
      });

  /// 拖曳排序大事件。[oldIndex] / [newIndex] 是在這個分頁畫面上的位置（[questsOf] 的順序）。
  Future<void> reorderQuests(QuestType type, int oldIndex, int newIndex) => _serial(() {
        final visible = questsOf(type);
        if (oldIndex >= visible.length || newIndex >= visible.length) return Future.value();
        final moved = visible.removeAt(oldIndex);
        visible.insert(newIndex, moved);
        // 其它分類的位置不動，只把這個分類的「格子」依新順序填回去
        var i = 0;
        for (var k = 0; k < quests.length; k++) {
          if (quests[k].type == type) quests[k] = visible[i++];
        }
        return _commit();
      });

  /// 拖曳排序細項。[shown] 是畫面上的順序（[displaySteps]），index 是在它裡面的位置。
  Future<void> reorderSteps(Quest quest, List<QuestStep> shown, int oldIndex, int newIndex) =>
      _serial(() {
        final q = _quest(quest.id);
        if (q == null) return Future.value();
        // 依畫面上的順序（id）重新排列「目前的」細項
        final ids = shown.map((s) => s.id).toList();
        final moved = ids.removeAt(oldIndex);
        ids.insert(newIndex, moved);
        final byId = {for (final s in q.steps) s.id: s};
        final ordered = [
          for (final id in ids)
            if (byId.containsKey(id)) byId.remove(id)!
        ];
        q.steps
          ..clear()
          ..addAll(ordered)
          ..addAll(byId.values); // 畫面上沒有的（不太可能）放到最後，不會弄丟
        return _commit();
      });

  /// 清除主線 / 支線裡已完成、已放棄的細項（可以復原）。回傳清掉幾個細項。
  /// 大事件一律保留，就算底下清空了也留著，之後可以繼續新增細項。
  Future<int> clearCompleted() => _serial(() async {
        var count = 0;
        final targets = quests.where((q) => !q.type.recurring).toList();
        if (!targets.any((q) => q.steps.any((s) => s.closed))) return 0;
        _snapshot();
        for (final q in targets) {
          count += q.steps.where((s) => s.closed).length;
          q.steps.removeWhere((s) => s.closed);
        }
        await _commit();
        return count;
      });

  Future<void> deleteQuest(Quest quest) => _serial(() async {
        final q = _quest(quest.id);
        if (q == null) return;
        _snapshot();
        quests.remove(q);
        await _commit();
      });

  // ---------- 細項 ----------

  /// 回傳 false = 這個大事件已經不存在（例如被刪掉了）。
  Future<bool> addStep(Quest quest,
          {required String title,
          String note = '',
          DateTime? deadline,
          List<int>? weekdays,
          int? remindBefore,
          int? timeOfDay}) =>
      _serial(() async {
        final q = _quest(quest.id);
        if (q == null) return false;
        q.steps.add(QuestStep(
            id: _data.newId(),
            title: title,
            note: note,
            deadline: deadline,
            weekdays: weekdays,
            remindBefore: remindBefore,
            timeOfDay: timeOfDay));
        await _commit();
        return true;
      });

  /// 回傳 false = 這個細項已經不存在（例如被刪掉了）。
  Future<bool> updateStep(QuestStep step,
          {required String title,
          required String note,
          DateTime? deadline,
          required List<int> weekdays,
          int? remindBefore,
          int? timeOfDay}) =>
      _serial(() async {
        final found = _step(step.id);
        if (found == null) return false;
        found.$2
          ..title = title
          ..note = note
          ..deadline = deadline
          ..weekdays = weekdays
          ..remindBefore = remindBefore
          ..timeOfDay = timeOfDay;
        await _commit();
        return true;
      });

  Future<void> deleteStep(Quest quest, QuestStep step) => _serial(() async {
        final found = _step(step.id);
        if (found == null) return;
        _snapshot();
        found.$1.steps.remove(found.$2);
        await _commit();
      });

  // ---------- 追蹤 ----------

  /// 大事件的 📌：底下全部都在追蹤 → 全部取消追蹤；只要有一個沒追蹤 → 全部追蹤。
  /// 回傳之後的狀態（true = 全部追蹤）；不存在時回傳 null。
  Future<bool?> toggleQuestTracked(Quest quest) => _serial(() async {
        final q = _quest(quest.id);
        if (q == null) return null;
        final target = !q.allTracked;
        for (final s in q.steps) {
          s.tracked = target;
        }
        await _commit();
        return target;
      });

  /// 切換細項的追蹤。回傳切換後的狀態（true = 追蹤中）；不存在時回傳 null。
  Future<bool?> toggleStepTracked(QuestStep step) => _serial(() async {
        final found = _step(step.id);
        if (found == null) return null;
        final s = found.$2..tracked = !found.$2.tracked;
        await _commit();
        return s.tracked;
      });

  /// 回傳打勾之後的狀態（true = 已完成）；細項不存在時回傳 null。
  Future<bool?> toggleStep(QuestStep step) => _serial(() async {
        final found = _step(step.id);
        if (found == null) return null;
        _snapshot();
        final s = found.$2;
        if (s.abandoned) {
          // 已放棄的按 ✓ → 改成完成
          s
            ..abandoned = false
            ..done = true;
        } else {
          s.done = !s.done;
        }
        await _commit();
        return s.done;
      });

  /// 放棄 / 取消放棄。回傳之後的狀態（true = 已放棄）；細項不存在時回傳 null。
  Future<bool?> toggleAbandon(QuestStep step) => _serial(() async {
        final found = _step(step.id);
        if (found == null) return null;
        _snapshot();
        final s = found.$2;
        s
          ..abandoned = !s.abandoned
          ..done = false;
        await _commit();
        return s.abandoned;
      });
}
