import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backup.dart';
import '../demo.dart';
import '../models.dart';
import '../notifications.dart';
import '../storage.dart';
import '../store.dart';
import '../system.dart';
import '../theme.dart';
import 'edit_sheets.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final QuestStore store;

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
    // 倒數文字的更新：有任務剩不到 1 小時（顯示到秒）就每秒重畫，
    // 否則每分鐘重畫一次就夠了（比較省電）。換分鐘時順便檢查是否跨過每日重置時間。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final newMinute = now.minute != _now.minute;
      if (newMinute || _showsSeconds(now)) setState(() => _now = now);
      if (newMinute) store.checkDailyReset();
    });
  }

  /// 目前有沒有任務剩不到 1 小時（倒數會顯示秒數）。
  bool _showsSeconds(DateTime now) => store.quests.any((q) => q.steps.any((s) {
        if (s.done) return false;
        final d = countdownTarget(q.type, s, now);
        if (d == null) return false;
        final left = d.difference(now);
        return left > const Duration(seconds: -1) && left < const Duration(hours: 1);
      }));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    }
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
        if (r != null) await store.updateQuest(q, title: r.title, type: r.type);
      case 'delete':
        if (await confirmDelete(context, q.title)) {
          await store.deleteQuest(q);
          _showUndo('已刪除「${q.title}」');
        }
    }
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
      _toast(next == null
          ? '「${s.title}」現在不能打勾'
          : '「${s.title}」${nextResetLabel(next, _now)}才能打勾');
      return;
    }
    await store.toggleStep(s);
    if (s.done) _showUndo('已完成「${s.title}」');
  }

  /// 下方跳出「…・復原」的提示，幾秒後自動消失。
  void _showUndo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: '復原', onPressed: store.undo),
      ));
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('匯入')),
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
    await store.addStep(q,
        title: r.title,
        note: r.note,
        deadline: r.deadline,
        weekdays: r.weekdays,
        remindBefore: r.remindBefore,
        timeOfDay: r.timeOfDay);
    _collapsed.remove(q.id);
  }

  Future<void> _editStep(Quest q, QuestStep s) async {
    final r = await showStepSheet(context, type: q.type, step: s);
    if (r == null) return;
    await store.updateStep(s,
        title: r.title,
        note: r.note,
        deadline: r.deadline,
        weekdays: r.weekdays,
        remindBefore: r.remindBefore,
        timeOfDay: r.timeOfDay);
  }

  // ---------- 畫面 ----------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        floatingActionButton: FloatingActionButton(
          backgroundColor: GColors.cardSelected,
          foregroundColor: GColors.textDark,
          shape: const CircleBorder(side: BorderSide(color: GColors.gold, width: 2)),
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
            child: Text('任務系統',
                style: TextStyle(
                    color: GColors.text, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4)),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: GColors.sub),
            color: GColors.card,
            onSelected: (v) => switch (v) {
              'export' => _export(),
              'import' => _import(),
              'battery' => SystemInfo.openAppSettings(),
              'clear' => _clearCompleted(),
              _ => _showAbout(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: ListTile(leading: Icon(Icons.upload_file), title: Text('匯出備份')),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(leading: Icon(Icons.download), title: Text('匯入備份')),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(leading: Icon(Icons.cleaning_services_outlined), title: Text('清除已完成')),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'battery',
                child: ListTile(leading: Icon(Icons.battery_charging_full), title: Text('背景執行設定')),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(leading: Icon(Icons.info_outline), title: Text('關於')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 頂端的設定提示：通知沒開（最重要，不能關掉）> 電池有限制（可以「不再提醒」）。
  Widget _buildSetupBanner() {
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
        content: Text('版本 $version\n\n把待辦事項變成任務清單，\n未完成的任務會常駐在通知欄。',
            style: const TextStyle(color: GColors.text, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => SystemInfo.openUrl('$repo/releases'),
            child: const Text('檢查更新'),
          ),
          TextButton(onPressed: () => SystemInfo.openUrl(repo), child: const Text('GitHub')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
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
                        child: Icon(t.icon, color: _tab == t ? GColors.gold : GColors.sub),
                      ),
                      const SizedBox(height: 4),
                      Text(t.label,
                          style: TextStyle(
                            fontSize: 13,
                            color: _tab == t ? GColors.gold : GColors.sub,
                            fontWeight: _tab == t ? FontWeight.bold : FontWeight.normal,
                          )),
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
    final quests = store.questsOf(_tab);
    if (quests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DiamondIcon(size: 28, color: GColors.sub),
            const SizedBox(height: 12),
            Text('這裡還沒有${_tab.label}', style: const TextStyle(color: GColors.sub)),
            const SizedBox(height: 4),
            const Text('點右下角的 ＋ 新增', style: TextStyle(color: GColors.sub, fontSize: 12)),
          ],
        ),
      );
    }
    // 長按大事件標題可以拖曳排序
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      buildDefaultDragHandles: false,
      proxyDecorator: _dragProxy,
      itemCount: quests.length,
      onReorderItem: (from, to) => store.reorderQuests(_tab, from, to),
      itemBuilder: (context, i) => KeyedSubtree(
        key: ValueKey('quest-${quests[i].id}'),
        child: _buildQuest(quests[i], i),
      ),
    );
  }

  /// 拖曳中的項目：浮起來加陰影。
  Widget _dragProxy(Widget child, int index, Animation<double> animation) => Material(
        color: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black,
        child: child,
      );

  Widget _buildQuest(Quest q, int index) {
    // 已完成的大事件預設收合
    final expanded = q.done ? _collapsed.contains(-q.id) : !_collapsed.contains(q.id);
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
              quest: q,
              progress: questProgress(q.type, q, _now),
              expanded: expanded,
              onTap: toggle,
              onMenu: (a) => _questMenu(q, a),
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
                        onReorderItem: (from, to) => store.reorderSteps(q, steps, from, to),
                        itemBuilder: (context, j) => ReorderableDelayedDragStartListener(
                          key: ValueKey('step-${steps[j].id}'),
                          index: j,
                          child: _buildStep(q, steps[j]),
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

  Widget _buildStep(Quest q, QuestStep s) {
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: GColors.overdue.withValues(alpha: 0.6),
        child: const Icon(Icons.delete_outline),
      ),
      // 不用確認視窗：刪除後下方會出現「復原」
      onDismissed: (_) => _deleteStep(q, s),
      child: StepCard(
        step: s,
        type: q.type,
        now: _now,
        selected: _selectedStep == s.id,
        onTap: () => setState(() => _selectedStep = _selectedStep == s.id ? null : s.id),
        onEdit: () => _editStep(q, s),
        onToggle: () => _toggleStep(q, s),
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
            child: Text(text, style: const TextStyle(color: GColors.text, fontSize: 13)),
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
