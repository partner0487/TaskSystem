import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';

/// 完成紀錄：最近 90 天完成、放棄、未完成的任務，依日期分組。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.store});

  final QuestStore store;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

/// 篩選：null = 全部
typedef _Filter = HistoryKind?;

class _HistoryPageState extends State<HistoryPage> {
  _Filter _filter;

  static const _missedColor = Color(0xFFE0A86B);

  static String _kindLabel(HistoryKind k) => switch (k) {
        HistoryKind.done => '完成',
        HistoryKind.abandoned => '放棄',
        HistoryKind.missed => '未完成',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final all = widget.store.history;
        final shown = all.where((e) => _filter == null || e.kind == _filter).toList()
          ..sort((a, b) => b.at.compareTo(a.at)); // 新 → 舊
        return Scaffold(
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
                  _buildTitle(context),
                  _buildFilters(all),
                  Expanded(child: shown.isEmpty ? _buildEmpty() : _buildList(shown)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 20, 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: GColors.text),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
            const Text('完成紀錄',
                style: TextStyle(
                    color: GColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
            const Spacer(),
            const Text('最近 $historyKeepDays 天',
                style: TextStyle(color: GColors.sub, fontSize: 12)),
          ],
        ),
      );

  Widget _buildFilters(List<HistoryEntry> all) {
    int count(HistoryKind? k) => k == null ? all.length : all.where((e) => e.kind == k).length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (final k in <HistoryKind?>[null, ...HistoryKind.values])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${k == null ? '全部' : _kindLabel(k)}  ${count(k)}'),
                selected: _filter == k,
                onSelected: (_) => setState(() => _filter = k),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _filter == null
                ? '還沒有紀錄\n\n完成、放棄任務，或任務到期還沒完成時，\n都會記在這裡（保留 $historyKeepDays 天）'
                : '沒有「${_kindLabel(_filter!)}」的紀錄',
            textAlign: TextAlign.center,
            style: const TextStyle(color: GColors.sub, height: 1.6),
          ),
        ),
      );

  Widget _buildList(List<HistoryEntry> entries) {
    final now = DateTime.now();
    final children = <Widget>[];
    String? lastDay;
    for (final e in entries) {
      final day = dayKey(gameDay(e.at));
      if (day != lastDay) {
        lastDay = day;
        children.add(_dayHeader(gameDay(e.at), gameDay(now)));
      }
      children.add(_entryTile(e));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 32), children: children);
  }

  /// 「今天」「昨天」「11/23（日）」
  Widget _dayHeader(DateTime day, DateTime today) {
    DateTime utc(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    final diff = utc(today).difference(utc(day)).inDays;
    final label = switch (diff) {
      0 => '今天',
      1 => '昨天',
      _ => '${day.month}/${day.day}（${weekNames[day.weekday - 1]}）',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(color: GColors.gold, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: Colors.white12)),
        ],
      ),
    );
  }

  Widget _entryTile(HistoryEntry e) {
    final (icon, color) = switch (e.kind) {
      HistoryKind.done => (Icons.check, GColors.gold),
      HistoryKind.abandoned => (Icons.close, GColors.overdue),
      HistoryKind.missed => (Icons.priority_high, _missedColor),
    };
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(e.at.hour)}:${two(e.at.minute)}';
    // 右邊的說明：完成 / 放棄的時間；未完成 = 截止時間或「每日結算」
    final when = switch (e.kind) {
      HistoryKind.missed => e.type.recurring
          ? (e.type == QuestType.daily ? '每日結算' : '每週結算')
          : '截止 $time',
      _ => time,
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: GColors.card,
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    style: const TextStyle(
                        color: GColors.text, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${e.type.label}・${e.questTitle}',
                    style: const TextStyle(color: GColors.sub, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_kindLabel(e.kind), style: TextStyle(color: color, fontSize: 13)),
              const SizedBox(height: 2),
              Text(when, style: const TextStyle(color: GColors.sub, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
