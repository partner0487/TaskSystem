import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backup.dart';
import '../models.dart';
import '../store.dart';
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

  QuestStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        final d = effectiveDeadline(q.type, s, now);
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

  Future<void> _deleteStep(Quest q, QuestStep s) async {
    await store.deleteStep(q, s);
    _showUndo('已刪除「${s.title}」');
  }

  Future<void> _toggleStep(QuestStep s) async {
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
        remindBefore: r.remindBefore);
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
        remindBefore: r.remindBefore);
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
            onSelected: (v) => v == 'export' ? _export() : _import(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: ListTile(leading: Icon(Icons.upload_file), title: Text('匯出備份')),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(leading: Icon(Icons.download), title: Text('匯入備份')),
              ),
            ],
          ),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      children: [
        for (final q in quests) ..._buildQuest(q),
      ],
    );
  }

  List<Widget> _buildQuest(Quest q) {
    // 已完成的大事件預設收合
    final expanded = q.done ? _collapsed.contains(-q.id) : !_collapsed.contains(q.id);
    void toggle() => setState(() {
          final key = q.done ? -q.id : q.id;
          _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key);
        });

    // 排序：今天要做的 → 今天休息的（每週任務的非指定日）→ 已完成
    bool active(QuestStep s) => isActiveOn(q.type, s, _now);
    final steps = [
      ...q.steps.where((s) => !s.done && active(s)),
      ...q.steps.where((s) => !s.done && !active(s)),
      ...q.steps.where((s) => s.done),
    ];

    return [
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: QuestHeader(
          quest: q,
          expanded: expanded,
          onTap: toggle,
          onMenu: (a) => _questMenu(q, a),
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
                    for (final s in steps)
                      Dismissible(
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
                          onTap: () => setState(
                              () => _selectedStep = _selectedStep == s.id ? null : s.id),
                          onLongPress: () => _editStep(q, s),
                          onToggle: () => _toggleStep(s),
                        ),
                      ),
                    AddStepButton(onTap: () => _addStep(q)),
                  ],
                ),
              ),
      ),
    ];
  }
}
