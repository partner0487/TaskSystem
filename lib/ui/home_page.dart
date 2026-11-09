import 'dart:async';

import 'package:flutter/material.dart';

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
        if (await confirmDelete(context, q.title)) await store.deleteQuest(q);
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          DiamondIcon(size: 16, filled: true),
          SizedBox(width: 10),
          Text('任務系統',
              style: TextStyle(
                  color: GColors.text, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4)),
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
                        confirmDismiss: (_) => confirmDelete(context, s.title),
                        onDismissed: (_) => store.deleteStep(q, s),
                        child: StepCard(
                          step: s,
                          type: q.type,
                          now: _now,
                          selected: _selectedStep == s.id,
                          onTap: () => setState(
                              () => _selectedStep = _selectedStep == s.id ? null : s.id),
                          onLongPress: () => _editStep(q, s),
                          onToggle: () => store.toggleStep(s),
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
