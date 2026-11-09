import 'package:flutter/foundation.dart';

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

  int openStepCount(QuestType type) => quests
      .where((q) => q.type == type)
      .expand((q) => q.steps)
      .where((s) => !s.done)
      .length;

  /// 從存檔重新讀取（App 啟動、回到前景、通知欄按了完成之後都會呼叫）。
  Future<void> reload() async {
    _data = await Storage.read();
    _applyDailyReset();
    loaded = true;
    await _commit();
  }

  /// 每分鐘檢查一次，跨過凌晨 4 點就重置每日委託。
  Future<void> checkDailyReset() async {
    if (_applyDailyReset()) await _commit();
  }

  bool _applyDailyReset() {
    final key = resetDayKey(DateTime.now());
    if (_data.lastReset == key) return false;
    if (_data.lastReset != null) {
      for (final q in quests.where((q) => q.type == QuestType.daily)) {
        for (final s in q.steps) {
          s.done = false;
        }
      }
    }
    _data.lastReset = key;
    return true;
  }

  Future<void> _commit() async {
    notifyListeners();
    await Storage.write(_data);
    await Notifier.sync(_data);
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

  Future<void> deleteQuest(Quest q) {
    quests.remove(q);
    return _commit();
  }

  // ---------- 細項 ----------

  Future<void> addStep(Quest q,
      {required String title, String note = '', DateTime? deadline}) {
    q.steps.add(QuestStep(
        id: _data.newId(), title: title, note: note, deadline: deadline));
    return _commit();
  }

  Future<void> updateStep(QuestStep s,
      {required String title, required String note, DateTime? deadline}) {
    s
      ..title = title
      ..note = note
      ..deadline = deadline;
    return _commit();
  }

  Future<void> deleteStep(Quest q, QuestStep s) {
    q.steps.remove(s);
    return _commit();
  }

  Future<void> toggleStep(QuestStep s) {
    s.done = !s.done;
    return _commit();
  }
}
