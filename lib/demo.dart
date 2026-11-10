import 'models.dart';

/// 截圖 / 展示用模式：`flutter run --dart-define=DEMO=true`。
/// 使用另一份獨立的存檔，不會動到真實資料；資料內容盡量讓各種狀態都出現在畫面上。
const demoMode = bool.fromEnvironment('DEMO');

AppData demoData() {
  final d = AppData(nextId: 1);
  final now = DateTime.now();
  QuestStep step(String t,
          {String note = '',
          Duration? due,
          bool done = false,
          List<int>? weekdays,
          int? remind}) =>
      QuestStep(
        id: d.newId(),
        title: t,
        note: note,
        deadline: due == null ? null : now.add(due),
        done: done,
        weekdays: weekdays,
        remindBefore: remind,
      );

  d.quests.addAll([
    Quest(id: d.newId(), title: '期末專題', type: QuestType.main, steps: [
      step('上台報告', due: const Duration(minutes: 42, seconds: 30), remind: 10),
      step('完成系統架構圖',
          note: '用 draw.io 畫，放進簡報第 3 頁',
          due: const Duration(days: 2, hours: 5),
          remind: 60),
      step('補上單元測試'),
      step('整理參考資料', done: true),
    ]),
    Quest(id: d.newId(), title: '搬家', type: QuestType.main, steps: [
      step('打包書櫃', due: const Duration(days: 5, hours: 3), remind: 1440),
      step('預約搬家公司'),
    ]),
    Quest(id: d.newId(), title: '購物清單', type: QuestType.side, steps: [
      step('牛奶'),
      step('三號電池'),
      step('洗衣精', done: true),
    ]),
    Quest(id: d.newId(), title: '圖書館', type: QuestType.side, steps: [
      step('歸還《演算法導論》', due: const Duration(days: -1, hours: -3)),
    ]),
    Quest(id: d.newId(), title: '運動', type: QuestType.weekly, steps: [
      step('跑步 5 公里',
          weekdays: [DateTime.tuesday, DateTime.thursday, DateTime.saturday], remind: 60),
      step('打掃房間'),
      step('籃球', weekdays: [DateTime.saturday, DateTime.sunday]),
    ]),
    Quest(id: d.newId(), title: '每日委託', type: QuestType.daily, steps: [
      step('喝水 2000cc'),
      step('整理桌面'),
      step('背 20 個英文單字', done: true),
    ]),
  ]);
  d.lastReset = resetDayKey(now); // 已經是今天，不要被重置掉展示用的「已完成」
  return d;
}
