import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// 原神任務標題左邊那個菱形圖示。
class DiamondIcon extends StatelessWidget {
  const DiamondIcon({super.key, this.size = 14, this.color = GColors.gold, this.filled = false});

  final double size;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.5,
      height: size * 1.5,
      child: Center(
        child: Transform.rotate(
          angle: pi / 4,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: filled ? color : null,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Container(
                width: size * 0.35,
                height: size * 0.35,
                color: filled ? GColors.header : color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 大事件的標題列（例如「異象」），點一下展開 / 收合。
class QuestHeader extends StatelessWidget {
  const QuestHeader({
    super.key,
    required this.quest,
    required this.expanded,
    required this.onTap,
    required this.onMenu,
  });

  final Quest quest;
  final bool expanded;
  final VoidCallback onTap;
  final void Function(String action) onMenu;

  @override
  Widget build(BuildContext context) {
    final done = quest.done;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
        decoration: BoxDecoration(
          color: GColors.header,
          border: Border.all(
            color: expanded ? GColors.text.withValues(alpha: 0.85) : Colors.white12,
            width: expanded ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: DiamondIcon(color: done ? GColors.sub : GColors.gold),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                quest.title,
                style: TextStyle(
                  color: done ? GColors.sub : GColors.gold,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            Text(
              done ? '已完成' : '${quest.doneCount}/${quest.steps.length}',
              style: const TextStyle(color: GColors.sub, fontSize: 13),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: GColors.sub),
              color: GColors.card,
              onSelected: onMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('新增細項')),
                PopupMenuItem(value: 'edit', child: Text('編輯大事件')),
                PopupMenuItem(value: 'delete', child: Text('刪除大事件')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 細項卡片（例如「異象・至冬」）。選中時變成米白底 + 金框，跟原神一樣。
class StepCard extends StatelessWidget {
  const StepCard({
    super.key,
    required this.step,
    required this.type,
    required this.selected,
    required this.now,
    required this.onTap,
    required this.onLongPress,
    required this.onToggle,
  });

  final QuestStep step;
  final QuestType type;
  final bool selected;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggle;

  /// 未完成：期限；已完成的每日 / 每週：什麼時候重新出現。
  String _subtitle() {
    if (!step.done) return deadlineText(step, type, now);
    final next = nextResetFor(type, step, now);
    return next == null ? '已完成' : '已完成・${nextResetLabel(next, now)}重新出現';
  }

  @override
  Widget build(BuildContext context) {
    final overdue =!step.done && step.deadline != null && step.deadline!.isBefore(now);
    final urgent = !step.done &&
        step.deadline != null &&
        step.deadline!.difference(now) < const Duration(hours: 24);
    final titleColor = selected ? GColors.textDark : (step.done ? GColors.sub : GColors.text);
    final subColor = overdue
        ? GColors.overdue
        : (selected ? GColors.textDark.withValues(alpha: 0.75) : GColors.sub);

    return Row(
      children: [
        // 選中時左邊的白色小箭頭
        SizedBox(
          width: 14,
          child: selected
              ? const Icon(Icons.play_arrow, size: 14, color: Colors.white)
              : null,
        ),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: selected ? GColors.cardSelected : GColors.card,
                border: Border.all(
                  color: selected ? GColors.goldBright : Colors.white10,
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [BoxShadow(color: GColors.gold.withValues(alpha: 0.35), blurRadius: 10)]
                    : null,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 快到期（24 小時內）時左邊的藍色條
                    Container(width: 5, color: urgent ? GColors.accent : Colors.transparent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.title,
                              style: TextStyle(
                                color: titleColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                decoration: step.done ? TextDecoration.lineThrough : null,
                                decorationColor: titleColor,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _subtitle(),
                                    style: TextStyle(color: subColor, fontSize: 13),
                                  ),
                                ),
                                if (!step.done && step.remindAt != null) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.vibration, size: 14, color: subColor),
                                ],
                              ],
                            ),
                            if (selected && step.note.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                step.note,
                                style: const TextStyle(color: GColors.textDark, fontSize: 14),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Center(child: CheckButton(done: step.done, selected: selected, onTap: onToggle)),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 右側的圓形勾選按鈕。
class CheckButton extends StatelessWidget {
  const CheckButton({super.key, required this.done, required this.selected, required this.onTap});

  final bool done;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = selected ? GColors.gold : GColors.gold.withValues(alpha: 0.55);
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? GColors.gold : Colors.black.withValues(alpha: 0.15),
          border: Border.all(color: ring, width: 1.5),
        ),
        child: Icon(
          Icons.check,
          size: 22,
          color: done ? GColors.textDark : ring.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// 「＋ 新增細項」按鈕。
class AddStepButton extends StatelessWidget {
  const AddStepButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: GColors.gold.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: GColors.gold),
              SizedBox(width: 6),
              Text('新增細項', style: TextStyle(color: GColors.gold)),
            ],
          ),
        ),
      ),
    );
  }
}
