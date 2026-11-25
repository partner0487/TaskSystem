import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auto_backup.dart';
import '../backup.dart';
import '../demo.dart';
import '../game_mode.dart';
import '../models.dart';
import '../notifications.dart';
import '../storage.dart';
import '../store.dart';
import '../system.dart';
import '../theme.dart';
import 'edit_sheets.dart';
import 'history_page.dart';
import 'tour.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store, this.showTourOnStart = false});

  final QuestStore store;

  /// 第一次安裝打開時：資料讀好之後顯示新手指引
  final bool showTourOnStart;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  QuestType _tab = QuestType.main;
  int? _selectedStep;
  final Set<int> _collapsed = {}; // 被收合的大事件 id
  late final Timer _ticker;
  DateTime _now = DateTime.now();

  // 手機設定檢查（頂端提示用）。預設 true = 檢查完之前不顯示提示
  bool _notificationsOn = true;
  bool _batteryOk = true;
  bool _batteryTipDismissed = true;

  QuestStore get store => widget.store;

  /// 檢查通知權限與電池設定；App 開啟、回到前景時都會做（從設定頁回來就會更新）。
  Future<void> _checkSetup() async {
    if (demoMode) return; // 展示 / 截圖時不顯示設定提示
    final results = await Future.wait([
      Notifier.areEnabled(),
      SystemInfo.isBatteryUnrestricted(),
      Storage.batteryTipDismissed(),
    ]);
    if (!mounted) return;
    setState(() {
      _notificationsOn = results[0];
      _batteryOk = results[1];
      _batteryTipDismissed = results[2];
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSetup();
    _checkGameMode();
    store.addListener(_checkGameMode); // 背景改了遊戲模式（快速設定、時間到）→ App 重新讀取時更新提示
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleLaunchAction());
    if (widget.showTourOnStart) store.addListener(_maybeStartTour);
    // 倒數文字的更新：有任務剩不到 1 小時（顯示到秒）就每秒重畫，
    // 否則每分鐘重畫一次就夠了（比較省電）。換分鐘時順便檢查是否跨過每日重置時間。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final newMinute = now.minute != _now.minute;
      if (newMinute || _showsSeconds(now)) setState(() => _now = now);
      if (newMinute) {
        store.checkDailyReset();
        _checkGameMode(); // 遊戲模式時間到 → 提示消失
      }
    });
  }

  /// 目前有沒有任務剩不到 1 小時（倒數會顯示秒數）。
  bool _showsSeconds(DateTime now) => store.quests.any(
    (q) => q.steps.any((s) {
      if (s.closed) return false;
      final d = countdownTarget(q.type, s, now);
      if (d == null) return false;
      final left = d.difference(now);
      return left > const Duration(seconds: -1) &&
          left < const Duration(hours: 1);
    }),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_checkGameMode);
    store.removeListener(_maybeStartTour);
    _listScroll.dispose();
    _ticker.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到 App 時重新讀取：可能在通知欄按過「完成」，或已經過了每日重置
    if (state == AppLifecycleState.resumed) {
      _now = DateTime.now();
      store.reload();
      _checkSetup();
      _checkGameMode();
      _handleLaunchAction();
    }
  }

  // ---------- 新手指引 ----------

  /// 指引進行中才把 key 掛到元件上（拖曳排序時元件會被複製，平常掛 GlobalKey 會衝突）
  bool _touring = false;

  /// 指引進行時暫時放在主線最上面的範例大事件（不存檔、不進通知欄，指引結束就消失）。
  /// 這樣不管使用者的任務是空的、沒有細項、或列表捲到下面，指引都指得到同樣的東西。
  Quest? _tourExample;

  /// 主列表的捲動位置（指引開始時跳回最上面）
  final _listScroll = ScrollController();
  final _tourTabs = GlobalKey();
  final _tourQuest = GlobalKey();
  final _tourStep = GlobalKey();
  final _tourCheck = GlobalKey();
  final _tourPin = GlobalKey();
  final _tourFab = GlobalKey();
  final _tourGame = GlobalKey();
  final _tourMenu = GlobalKey();

  GlobalKey? _tk(GlobalKey k) => _touring ? k : null;

  /// 第一次打開：等資料讀好（通知權限也問完了）再開始
  void _maybeStartTour() {
    if (!store.loaded) return;
    store.removeListener(_maybeStartTour);
    _startTour();
  }

  Future<void> _startTour() async {
    if (_touring || !mounted) return;
    // 從主線分頁開始，第一個大事件要展開、細項不要選中，畫面才對得上說明
    setState(() {
      _touring = true;
      _tab = QuestType.main;
      _selectedStep = null;
      _collapsed.clear();
      final now = DateTime.now();
      _tourExample = Quest(id: -1, title: '範例：期末報告', type: QuestType.main, steps: [
        QuestStep(
          id: -2,
          title: '完成簡報',
          note: '這是指引用的範例，指引結束就會消失。',
          deadline: now.add(const Duration(days: 2, hours: 5)),
          remindBefore: 60,
        ),
        QuestStep(id: -3, title: '整理參考資料'),
      ]);
    });
    // 列表直接跳回最上面（不用捲動動畫）
    if (_listScroll.hasClients) _listScroll.jumpTo(0);
    await Future<void>.delayed(const Duration(milliseconds: 400)); // 等畫面排好
    if (!mounted) return;
    await showTour(context, [
      const TourStep(null, '歡迎使用任務系統',
          '把待辦事項變成任務清單，\n還沒做的任務會常駐在通知欄。\n\n跟著幾個步驟認識一下吧！'),
      TourStep(_tourTabs, '四種任務',
          '主線、支線：重要的事和零碎的事，可以設期限。\n每週、每日：固定要做的事，會自動重新出現。'),
      TourStep(_tourQuest, '大事件',
          '一件事可以拆成好幾個細項。\n點標題展開或收合；長按可以拖曳排序。'),
      TourStep(_tourStep, '細項',
          '點一下可以看備註，還有編輯、追蹤、放棄的按鈕。\n往左滑可以刪除。'),
      TourStep(_tourCheck, '完成',
          '做完按這裡打勾，通知欄的那一則也會消失。\n按錯了，下方可以「復原」。'),
      TourStep(_tourPin, '追蹤',
          '取消追蹤的任務不會出現在通知欄，也不會提醒。\n標題上的圖釘可以一次切換整組。'),
      TourStep(_tourFab, '新增', '按這裡新增大事件，再到底下加細項。'),
      TourStep(_tourGame, '遊戲模式', '打遊戲、開會時按一下，\n暫時隱藏所有任務通知和提醒。'),
      TourStep(_tourMenu, '更多功能',
          '完成紀錄、備份、背景執行設定都在這裡。\n想再看一次新手指引，也在這裡。'),
      const TourStep(null, '最後：拉下通知欄看看',
          '還沒做的任務都在通知欄。\n展開通知，可以直接按「✓ 完成」或「✕ 放棄」，\n不用打開 App。'),
    ]);
    if (mounted) {
      setState(() {
        _touring = false;
        _tourExample = null;
      });
    }
  }

  // ---------- 遊戲模式 ----------

  static const _gameModeColor = Color(0xFFA48BE8);

  /// 目前的遊戲模式（null = 沒開；until == null = 直到手動關閉）
  ({DateTime? until})? _gameMode;

  Future<void> _checkGameMode() async {
    if (demoMode) return;
    final g = await GameMode.read();
    if (mounted && g != _gameMode) setState(() => _gameMode = g);
  }

  /// 從快速設定的「遊戲模式」打開 App 時，跳出時間選擇。
  Future<void> _handleLaunchAction() async {
    if (demoMode) return;
    final action = await SystemInfo.takeLaunchAction();
    if (action == 'game_mode_picker' && mounted) await _pickGameMode();
  }

  Future<void> _pickGameMode() async {
    final picked = await showDialog<({Duration? d})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: GColors.header,
        title: const Text('遊戲模式'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              '暫時清空通知欄、停掉所有提醒。要開多久？',
              style: TextStyle(color: GColors.sub, fontSize: 13),
            ),
          ),
          for (final d in gameModeDurations)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, (d: d)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  gameModeDurationText(d),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await GameMode.turnOn(picked.d);
    await _afterGameModeChanged();
    final g = _gameMode;
    _toast(
      g == null
          ? '遊戲模式已開啟'
          : g.until == null
          ? '遊戲模式已開啟，直到手動關閉'
          : '遊戲模式已開啟，到 ${timeText(g.until!.hour * 60 + g.until!.minute)} 自動關閉',
    );
  }

  Future<void> _turnOffGameMode() async {
    await GameMode.turnOff();
    await _afterGameModeChanged();
    _toast('遊戲模式已關閉，任務回到通知欄');
  }

  /// 開關之後：原生端排鬧鐘 / 更新快速設定開關、通知欄重新同步、畫面提示更新。
  Future<void> _afterGameModeChanged() async {
    await SystemInfo.gameModeChanged();
    await store.resync();
    await _checkGameMode();
  }

  // ---------- 動作 ----------

  Future<void> _addQuest() async {
    final r = await showQuestSheet(context, initialType: _tab);
    if (r == null) return;
    await store.addQuest(r.title, r.type, firstStep: r.firstStep);
    setState(() => _tab = r.type);
  }

  Future<void> _questMenu(Quest q, String action) async {
    switch (action) {
      case 'add':
        await _addStep(q);
      case 'edit':
        final r = await showQuestSheet(context, quest: q, initialType: q.type);
        if (r != null &&
            !await store.updateQuest(q, title: r.title, type: r.type)) {
          _toast('「${q.title}」已經不存在，可能被刪除了');
        }
      case 'delete':
        if (await confirmDelete(context, q.title)) {
          await store.deleteQuest(q);
          _showUndo('已刪除「${q.title}」');
        }
    }
  }

  /// 還原每天自動做的那一份備份（今天第一次打開 App 時的樣子）。
  Future<void> _restoreAutoBackup() async {
    final backup = await AutoBackup.read();
    if (!mounted) return;
    if (backup == null) {
      _toast('還沒有自動備份（每天第一次打開 App 時會自動備份）');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.header,
        title: const Text('還原自動備份？'),
        content: Text(
          '備份時間：${formatDateTime(backup.savedAt, withWeekday: true)}\n'
          '備份內容：${backupSummary(backup.data)}\n\n'
          '目前所有任務會被這份備份取代。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('還原'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.restoreAutoBackup(backup.data);
    _showUndo('已還原自動備份');
  }

  /// 清除主線 / 支線裡已完成的細項（每日 / 每週會自己重置，不清）。
  Future<void> _clearCompleted() async {
    final n = await store.clearCompleted();
    if (n == 0) {
      _toast('主線／支線沒有已完成的任務');
    } else {
      _showUndo('已清除 $n 個已完成的細項');
    }
  }

  Future<void> _deleteStep(Quest q, QuestStep s) async {
    await store.deleteStep(q, s);
    _showUndo('已刪除「${s.title}」');
  }

  Future<void> _toggleStep(Quest q, QuestStep s) async {
    // 還沒輪到的每週任務不能打勾（例如週一的「週六日籃球」）
    if (!isActiveOn(q.type, s, _now)) {
      final next = nextResetFor(q.type, s, _now);
      _toast(
        next == null
            ? '「${s.title}」現在不能打勾'
            : '「${s.title}」${nextResetLabel(next, _now)}才能打勾',
      );
      return;
    }
    // 用回傳值判斷（畫面上的 s 在重新讀取後可能是舊的物件）
    if (await store.toggleStep(s) == true) _showUndo('已完成「${s.title}」');
  }

  // ---------- 放棄 ----------

  Future<void> _toggleAbandon(Quest q, QuestStep s) async {
    // 還沒輪到的每週任務（例如週一的「週六日籃球」）沒有東西可以放棄
    if (!s.abandoned && !isActiveOn(q.type, s, _now)) {
      _toast('「${s.title}」還沒輪到，不用放棄');
      return;
    }
    final abandoned = await store.toggleAbandon(s);
    if (abandoned == true) {
      _showUndo(q.type.recurring ? '已放棄「${s.title}」這一次' : '已放棄「${s.title}」');
    } else if (abandoned == false) {
      _toast('已取消放棄「${s.title}」');
    }
  }

  // ---------- 追蹤 ----------

  Future<void> _toggleQuestTracked(Quest q) async {
    final tracked = await store.toggleQuestTracked(q);
    if (tracked == null) return;
    _toast(
      tracked
          ? '「${q.title}」已全部追蹤，會出現在通知欄'
          : '「${q.title}」已全部取消追蹤，不會出現在通知欄，也不會提醒',
    );
  }

  Future<void> _toggleStepTracked(QuestStep s) async {
    final tracked = await store.toggleStepTracked(s);
    if (tracked == null) return;
    _toast(tracked ? '已追蹤「${s.title}」' : '已取消追蹤「${s.title}」，不會出現在通知欄，也不會提醒');
  }

  /// 下方跳出「…・復原」的提示，幾秒後自動消失。
  void _showUndo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: '復原', onPressed: store.undo),
        ),
      );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // ---------- 備份 ----------

  /// 匯出：跳出 Android 的「儲存到…」畫面（下載、雲端硬碟…），存成 JSON 檔。
  Future<void> _export() async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = '任務系統備份_${now.year}-${two(now.month)}-${two(now.day)}.json';
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: '匯出備份',
        fileName: name,
        bytes: utf8.encode(store.exportBackup()),
        mimeType: 'application/json',
      );
      if (uri != null) _toast('已匯出備份：$name');
    } catch (e) {
      _toast('匯出失敗：$e');
    }
  }

  /// 匯入：選備份檔 → 顯示內容摘要確認 → 取代目前資料（可以復原）。
  Future<void> _import() async {
    try {
      final files = await FilePicker.pickFiles(dialogTitle: '選擇備份檔');
      if (files.isEmpty) return;
      final data = decodeBackup(await files.first.xFile.readAsString());
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: GColors.header,
          title: const Text('匯入備份？'),
          content: Text('備份內容：${backupSummary(data)}\n\n目前所有任務會被這份備份取代。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('匯入'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await store.importBackup(data);
      _showUndo('已匯入備份');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('匯入失敗：$e');
    }
  }

  Future<void> _addStep(Quest q) async {
    final r = await showStepSheet(context, type: q.type);
    if (r == null) return;
    final ok = await store.addStep(
      q,
      title: r.title,
      note: r.note,
      deadline: r.deadline,
      weekdays: r.weekdays,
      remindBefore: r.remindBefore,
      timeOfDay: r.timeOfDay,
    );
    if (!ok) {
      _toast('「${q.title}」已經不存在，可能被刪除了');
      return;
    }
    _collapsed.remove(q.id);
  }

  Future<void> _editStep(Quest q, QuestStep s) async {
    final r = await showStepSheet(
      context,
      type: q.type,
      step: s,
      onDelete: () => _deleteStep(q, s),
    );
    if (r == null) return;
    final ok = await store.updateStep(
      s,
      title: r.title,
      note: r.note,
      deadline: r.deadline,
      weekdays: r.weekdays,
      remindBefore: r.remindBefore,
      timeOfDay: r.timeOfDay,
    );
    if (!ok) _toast('「${s.title}」已經不存在，可能被刪除了');
  }

  // ---------- 畫面 ----------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        floatingActionButton: FloatingActionButton(
          key: _tk(_tourFab),
          backgroundColor: GColors.cardSelected,
          foregroundColor: GColors.textDark,
          shape: const CircleBorder(
            side: BorderSide(color: GColors.gold, width: 2),
          ),
          onPressed: _addQuest,
          child: const Icon(Icons.add, size: 30),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GColors.bgTop, GColors.bgBottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildTitle(),
                _buildSetupBanner(),
                _buildTabs(),
                Expanded(child: store.loaded ? _buildList() : const SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          const DiamondIcon(size: 16, filled: true),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '任務系統',
              style: TextStyle(
                color: GColors.text,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
          ),
          // 遊戲模式：關閉中 = 灰色（按下選時間）；開啟中 = 紫色實心（按下立刻關閉）
          // （展示模式只顯示、不動作：遊戲模式的設定跟真實資料共用）
          IconButton(
            key: _tk(_tourGame),
            tooltip: _gameMode == null ? '遊戲模式' : '關閉遊戲模式',
            onPressed: demoMode
                ? () {}
                : (_gameMode == null ? _pickGameMode : _turnOffGameMode),
            icon: Icon(
              _gameMode == null
                  ? Icons.sports_esports_outlined
                  : Icons.sports_esports,
              color: _gameMode == null ? GColors.sub : _gameModeColor,
            ),
          ),
          PopupMenuButton<String>(
            key: _tk(_tourMenu),
            icon: const Icon(Icons.more_vert, color: GColors.sub),
            color: GColors.card,
            onSelected: (v) => switch (v) {
              'history' => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => HistoryPage(store: store))),
              'export' => _export(),
              'import' => _import(),
              'battery' => SystemInfo.openAppSettings(),
              'restore' => _restoreAutoBackup(),
              'tour' => _startTour(),
              'clear' => _clearCompleted(),
              _ => _showAbout(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'history',
                // 打勾清單（跟「還原自動備份」的時鐘箭頭區分）
                child: ListTile(leading: Icon(Icons.fact_check_outlined), title: Text('完成紀錄')),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.upload_file),
                  title: Text('匯出備份'),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('匯入備份'),
                ),
              ),
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  leading: Icon(Icons.restore),
                  title: Text('還原自動備份'),
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.cleaning_services_outlined),
                  title: Text('清除已完成'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'battery',
                child: ListTile(
                  leading: Icon(Icons.battery_charging_full),
                  title: Text('背景執行設定'),
                ),
              ),
              PopupMenuItem(
                value: 'tour',
                child: ListTile(
                  leading: Icon(Icons.tips_and_updates_outlined),
                  title: Text('新手指引'),
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('關於'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 頂端的設定提示：通知沒開（最重要，不能關掉）> 電池有限制（可以「不再提醒」）。
  Widget _buildSetupBanner() {
    final g = _gameMode;
    if (g != null) {
      final until = g.until;
      return _Banner(
        color: _gameModeColor,
        icon: Icons.sports_esports_outlined,
        text: until == null
            ? '遊戲模式中・直到手動關閉\n任務通知和提醒已暫停'
            : '遊戲模式中・到 ${timeText(until.hour * 60 + until.minute)}\n任務通知和提醒已暫停',
        action: '關閉',
        onAction: _turnOffGameMode,
      );
    }
    if (!_notificationsOn) {
      return _Banner(
        color: GColors.overdue,
        icon: Icons.notifications_off_outlined,
        text: '通知未開啟，任務不會出現在通知欄',
        action: '開啟',
        onAction: Notifier.openSettings,
      );
    }
    if (!_batteryOk && !_batteryTipDismissed) {
      return _Banner(
        color: GColors.gold,
        icon: Icons.battery_alert_outlined,
        text: '建議把電池設為「不受限制」，通知欄的「完成」才能穩定運作\n（App 資訊 → 電池 → 不受限制）',
        action: '前往設定',
        onAction: SystemInfo.openAppSettings,
        onClose: () async {
          await Storage.dismissBatteryTip();
          setState(() => _batteryTipDismissed = true);
        },
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _showAbout() async {
    final version = await SystemInfo.appVersion();
    if (!mounted) return;
    const repo = 'https://github.com/partner0487/TaskSystem';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GColors.header,
        title: const Row(
          children: [
            DiamondIcon(size: 16, filled: true),
            SizedBox(width: 10),
            Text('任務系統'),
          ],
        ),
        content: Text(
          '版本 $version\n\n把待辦事項變成任務清單，\n未完成的任務會常駐在通知欄。',
          style: const TextStyle(color: GColors.text, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => SystemInfo.openUrl('$repo/releases'),
            child: const Text('檢查更新'),
          ),
          TextButton(
            onPressed: () => SystemInfo.openUrl(repo),
            child: const Text('GitHub'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      key: _tk(_tourTabs),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          for (final t in QuestType.values)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _tab = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: _tab == t ? GColors.gold : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Badge(
                        isLabelVisible: store.openStepCount(t) > 0,
                        label: Text('${store.openStepCount(t)}'),
                        backgroundColor: GColors.accent,
                        child: Icon(
                          t.icon,
                          color: _tab == t ? GColors.gold : GColors.sub,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: _tab == t ? GColors.gold : GColors.sub,
                          fontWeight: _tab == t
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final example = _tab == QuestType.main ? _tourExample : null;
    final quests = [?example, ...store.questsOf(_tab)];
    if (quests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DiamondIcon(size: 28, color: GColors.sub),
            const SizedBox(height: 12),
            Text(
              '這裡還沒有${_tab.label}',
              style: const TextStyle(color: GColors.sub),
            ),
            const SizedBox(height: 4),
            const Text(
              '點右下角的 ＋ 新增',
              style: TextStyle(color: GColors.sub, fontSize: 12),
            ),
          ],
        ),
      );
    }
    // 長按大事件標題可以拖曳排序
    return ReorderableListView.builder(
      scrollController: _listScroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      buildDefaultDragHandles: false,
      proxyDecorator: _dragProxy,
      itemCount: quests.length,
      // 指引中（有範例大事件）不排序；平常照常
      onReorderItem: (from, to) {
        if (example == null) store.reorderQuests(_tab, from, to);
      },
      itemBuilder: (context, i) => KeyedSubtree(
        key: ValueKey('quest-${quests[i].id}'),
        child: _buildQuest(quests[i], i),
      ),
    );
  }

  /// 拖曳中的項目：浮起來加陰影。
  Widget _dragProxy(Widget child, int index, Animation<double> animation) =>
      Material(
        color: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black,
        child: child,
      );

  Widget _buildQuest(Quest q, int index) {
    // 已完成的大事件預設收合
    final expanded = q.done
        ? _collapsed.contains(-q.id)
        : !_collapsed.contains(q.id);
    void toggle() => setState(() {
      final key = q.done ? -q.id : q.id;
      _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key);
    });

    final steps = displaySteps(q.type, q.steps, _now);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: QuestHeader(
              key: index == 0 ? _tk(_tourQuest) : null,
              pinKey: index == 0 ? _tk(_tourPin) : null,
              quest: q,
              progress: questProgress(q.type, q, _now),
              expanded: expanded,
              onTap: toggle,
              onMenu: (a) => _questMenu(q, a),
              onToggleTrack: () => _toggleQuestTracked(q),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: !expanded
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(left: 10, right: 2),
                  padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
                  color: Colors.white.withValues(alpha: 0.05),
                  child: Column(
                    children: [
                      // 長按細項可以在大事件裡拖曳排序
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        proxyDecorator: _dragProxy,
                        itemCount: steps.length,
                        onReorderItem: (from, to) =>
                            store.reorderSteps(q, steps, from, to),
                        itemBuilder: (context, j) =>
                            ReorderableDelayedDragStartListener(
                              key: ValueKey('step-${steps[j].id}'),
                              index: j,
                              child: _buildStep(q, steps[j], first: index == 0 && j == 0),
                            ),
                      ),
                      AddStepButton(onTap: () => _addStep(q)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// [first]：第一個大事件的第一個細項（新手指引會指到它和它的 ✓）
  Widget _buildStep(Quest q, QuestStep s, {bool first = false}) {
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: GColors.overdue.withValues(alpha: 0.6),
        child: const Icon(Icons.delete_outline),
      ),
      // 先問「確定要刪除嗎？」；按取消卡片會彈回原位。刪除後下方仍會出現「復原」
      confirmDismiss: (_) => confirmDelete(context, s.title),
      onDismissed: (_) => _deleteStep(q, s),
      child: StepCard(
        key: first ? _tk(_tourStep) : null,
        checkKey: first ? _tk(_tourCheck) : null,
        step: s,
        type: q.type,
        now: _now,
        selected: _selectedStep == s.id,
        onTap: () =>
            setState(() => _selectedStep = _selectedStep == s.id ? null : s.id),
        onEdit: () => _editStep(q, s),
        onToggle: () => _toggleStep(q, s),
        onToggleTrack: () => _toggleStepTracked(s),
        onAbandon: () => _toggleAbandon(q, s),
      ),
    );
  }
}

/// 頂端的提示條（通知沒開、電池有限制…）。
class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
    this.onClose,
  });

  final Color color;
  final IconData icon;
  final String text;
  final String action;
  final Future<void> Function() onAction;

  /// 有提供才顯示「×」（可以不再提醒）。
  final Future<void> Function()? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: GColors.text, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: color),
            child: Text(action),
          ),
          if (onClose != null)
            IconButton(
              tooltip: '不再提醒',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18, color: GColors.sub),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
