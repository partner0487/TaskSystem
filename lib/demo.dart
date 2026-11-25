import 'models.dart';

/// 截圖 / 展示用模式：`flutter run --dart-define=DEMO=true`。
/// 使用另一份獨立的存檔，不會動到真實資料；資料內容盡量讓各種狀態都出現在畫面上。
const demoMode = bool.fromEnvironment('DEMO');

AppData demoData() {
  final d = AppData(nextId: 1);
  final now = DateTime.now();
  QuestStep step(
    String t, {
    String note = '',
    Duration? due,
    bool done = false,
    List<int>? weekdays,
    int? remind,
  }) => QuestStep(
    id: d.newId(),
    title: t,
    note: note,
    deadline: due == null ? null : now.add(due),
    done: done,
    weekdays: weekdays,
    remindBefore: remind,
  );

  d.quests.addAll([
    Quest(
      id: d.newId(),
      title: '期末專題',
      type: QuestType.main,
      steps: [
        step('上台報告', due: const Duration(minutes: 42, seconds: 30), remind: 10),
        step(
          '完成系統架構圖',
          note: '用 draw.io 畫，放進簡報第 3 頁',
          due: const Duration(days: 2, hours: 5),
          remind: 60,
        ),
        step('補上單元測試'),
        step('整理參考資料', done: true),
      ],
    ),
    Quest(
      id: d.newId(),
      title: '搬家',
      type: QuestType.main,
      steps: [
        step('打包書櫃', due: const Duration(days: 5, hours: 3), remind: 1440),
        step('預約搬家公司')..tracked = false, // 取消追蹤（🔕，大事件的 📌 變空心）
      ],
    ),
    Quest(
      id: d.newId(),
      title: '購物清單',
      type: QuestType.side,
      steps: [
        step('牛奶'),
        step('三號電池'),
        step('洗衣精', done: true),
        step('搶限量球鞋')..abandoned = true, // 已放棄（紅字）
      ],
    ),
    Quest(
      id: d.newId(),
      title: '圖書館',
      type: QuestType.side,
      steps: [step('歸還《演算法導論》', due: const Duration(days: -1, hours: -3))],
    ),
    Quest(
      id: d.newId(),
      title: '運動',
      type: QuestType.weekly,
      steps: [
        step(
          '跑步 5 公里',
          weekdays: [DateTime.tuesday, DateTime.thursday, DateTime.saturday],
          remind: 60,
        ),
        step('打掃房間'),
        step('籃球', weekdays: [DateTime.saturday, DateTime.sunday]),
      ],
    ),
    Quest(
      id: d.newId(),
      title: '感冒吃藥',
      type: QuestType.daily,
      steps: [
        // 早上截圖時：早餐那次「時間到」，午餐、晚餐還沒到（展示兩種狀態）
        _timed(d, '早餐後吃藥', 8 * 60),
        _timed(d, '午餐後吃藥', 12 * 60),
        _timed(d, '晚餐後吃藥', 18 * 60),
      ],
    ),
    Quest(
      id: d.newId(),
      title: '每日任務',
      type: QuestType.daily,
      steps: [step('喝水 2000cc'), step('整理桌面'), step('背 20 個英文單字', done: true)],
    ),
  ]);
  // 完成紀錄的展示資料（今天、昨天、前天）
  HistoryEntry h(String t, String q, QuestType type, HistoryKind k, DateTime at) =>
      HistoryEntry(stepId: 0, title: t, questTitle: q, type: type, kind: k, at: at);
  final today = gameDay(now);
  DateTime at(int daysAgo, int hour, [int minute = 0]) =>
      DateTime(today.year, today.month, today.day - daysAgo, hour, minute);
  d.history.addAll([
    h('喝水 2000cc', '每日任務', QuestType.daily, HistoryKind.missed, at(2, 23, 59)),
    h('交讀書心得', '期末專題', QuestType.main, HistoryKind.missed, at(2, 18)),
    h('早餐後吃藥', '感冒吃藥', QuestType.daily, HistoryKind.done, at(1, 8, 20)),
    h('搶限量球鞋', '購物清單', QuestType.side, HistoryKind.abandoned, at(1, 12, 3)),
    h('午餐後吃藥', '感冒吃藥', QuestType.daily, HistoryKind.done, at(1, 12, 45)),
    h('晚餐後吃藥', '感冒吃藥', QuestType.daily, HistoryKind.missed, at(1, 23, 59)),
    h('整理參考資料', '期末專題', QuestType.main, HistoryKind.done, at(0, 9, 10)),
    h('洗衣精', '購物清單', QuestType.side, HistoryKind.done, at(0, 10, 32)),
    h('背 20 個英文單字', '每日任務', QuestType.daily, HistoryKind.done, at(0, 11, 5)),
  ]);
  d.lastReset = resetDayKey(now); // 已經是今天，不要被重置掉展示用的「已完成」
  return d;
}

/// 展示用：固定時間的每日任務（[minutes] = 從午夜起算的分鐘），準時提醒。
QuestStep _timed(AppData d, String title, int minutes) =>
    QuestStep(id: d.newId(), title: title, timeOfDay: minutes, remindBefore: 0);
