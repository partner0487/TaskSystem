import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'backup.dart';
import 'models.dart';
import 'notifications.dart';
import 'storage.dart';

/// App 的狀態中心：所有新增 / 修改 / 刪除都經過這裡，
/// 改完會存檔、通知畫面更新，並同步通知欄。
class QuestStore extends ChangeNotifier {
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
        .where((s) => !s.done && isActiveOn(type, s, now))
        .length;
  }

  /// 從存檔重新讀取（App 啟動、回到前景、通知欄按了完成之後都會呼叫）。
  Future<void> reload() async {
    _data = await Storage.read();
    _data.applyResets(DateTime.now());
    loaded = true;
    await _commit();
  }

  /// App 開著的時候定時檢查，跨過凌晨 4 點就重置每日 / 每週任務。
  Future<void> checkDailyReset() async {
    if (_data.applyResets(DateTime.now())) await _commit();
  }

  Future<void> _commit() async {
    notifyListeners();
    await Storage.write(_data);
    await Notifier.sync(_data);
  }

  // ---------- 復原 ----------

  /// 上一個可以復原的操作之前的資料快照（只保留一步）。
  String? _undoSnapshot;

  /// 在刪除 / 打勾 / 匯入之前呼叫，記下操作前的樣子。
  void _snapshot() => _undoSnapshot = jsonEncode(_data.toJson());

  /// 把資料還原成上一個操作之前的樣子。
  Future<void> undo() async {
    final snap = _undoSnapshot;
    if (snap == null) return;
    _undoSnapshot = null;
    _data = AppData.fromJson(jsonDecode(snap) as Map<String, dynamic>);
    await _commit();
  }

  // ---------- 備份 ----------

  String exportBackup() => encodeBackup(_data, DateTime.now());

  /// 用備份取代目前所有資料（可以復原）。[data] 來自 [decodeBackup]。
  Future<void> importBackup(AppData data) async {
    _snapshot();
    _data = data..applyResets(DateTime.now());
    await _commit();
  }

  // ---------- 大事件 ----------

  Future<void> addQuest(String title, QuestType type, {String? firstStep}) {
    final q = Quest(id: _data.newId(), title: title, type: type);
    if (firstStep != null && firstStep.trim().isNotEmpty) {
      q.steps.add(QuestStep(id: _data.newId(), title: firstStep.trim()));
    }
    quests.add(q);
    return _commit();
  }

  Future<void> updateQuest(Quest q, {required String title, required QuestType type}) {
    q.title = title;
    q.type = type;
    return _commit();
  }

  /// 拖曳排序大事件。[oldIndex] / [newIndex] 是在這個分頁畫面上的位置（[questsOf] 的順序）。
  Future<void> reorderQuests(QuestType type, int oldIndex, int newIndex) {
    final visible = questsOf(type);
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex, moved);
    // 其它分類的位置不動，只把這個分類的「格子」依新順序填回去
    var i = 0;
    for (var k = 0; k < quests.length; k++) {
      if (quests[k].type == type) quests[k] = visible[i++];
    }
    return _commit();
  }

  /// 拖曳排序細項。[shown] 是畫面上的順序（[displaySteps]），index 是在它裡面的位置。
  Future<void> reorderSteps(Quest q, List<QuestStep> shown, int oldIndex, int newIndex) {
    final list = [...shown];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    q.steps
      ..clear()
      ..addAll(list);
    return _commit();
  }

  /// 清除主線 / 支線裡已完成的細項；整個做完的大事件一起刪掉（可以復原）。回傳清掉幾個細項。
  Future<int> clearCompleted() async {
    var count = 0;
    final targets = quests.where((q) => !q.type.recurring).toList();
    if (!targets.any((q) => q.steps.any((s) => s.done))) return 0;
    _snapshot();
    for (final q in targets) {
      final hadSteps = q.steps.isNotEmpty;
      count += q.steps.where((s) => s.done).length;
      q.steps.removeWhere((s) => s.done);
      if (hadSteps && q.steps.isEmpty) quests.remove(q);
    }
    await _commit();
    return count;
  }

  Future<void> deleteQuest(Quest q) {
    _snapshot();
    quests.remove(q);
    return _commit();
  }

  // ---------- 細項 ----------

  Future<void> addStep(Quest q,
      {required String title,
      String note = '',
      DateTime? deadline,
      List<int>? weekdays,
      int? remindBefore,
      int? timeOfDay}) {
    q.steps.add(QuestStep(
        id: _data.newId(),
        title: title,
        note: note,
        deadline: deadline,
        weekdays: weekdays,
        remindBefore: remindBefore,
        timeOfDay: timeOfDay));
    return _commit();
  }

  Future<void> updateStep(QuestStep s,
      {required String title,
      required String note,
      DateTime? deadline,
      required List<int> weekdays,
      int? remindBefore,
      int? timeOfDay}) {
    s
      ..title = title
      ..note = note
      ..deadline = deadline
      ..weekdays = weekdays
      ..remindBefore = remindBefore
      ..timeOfDay = timeOfDay;
    return _commit();
  }

  Future<void> deleteStep(Quest q, QuestStep s) {
    _snapshot();
    q.steps.remove(s);
    return _commit();
  }

  Future<void> toggleStep(QuestStep s) {
    _snapshot();
    s.done = !s.done;
    return _commit();
  }
}
