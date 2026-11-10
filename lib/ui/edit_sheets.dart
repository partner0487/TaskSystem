import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

typedef QuestInput = ({String title, QuestType type, String? firstStep});
typedef StepInput = ({
  String title,
  String note,
  DateTime? deadline,
  List<int> weekdays,
  int? remindBefore,
});

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GColors.header,
    shape: const RoundedRectangleBorder(),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: child,
      ),
    ),
  );
}

Widget _sheetTitle(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(text,
          style: const TextStyle(
              color: GColors.gold, fontSize: 20, fontWeight: FontWeight.bold)),
    );

Widget _buttons(BuildContext context, VoidCallback onOk) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: GColors.cardSelected, foregroundColor: GColors.textDark),
            onPressed: onOk,
            child: const Text('確定'),
          ),
        ],
      ),
    );

/// 新增 / 編輯大事件。
Future<QuestInput?> showQuestSheet(BuildContext context,
    {Quest? quest, required QuestType initialType}) {
  return _sheet<QuestInput>(context, _QuestForm(quest: quest, initialType: initialType));
}

class _QuestForm extends StatefulWidget {
  const _QuestForm({this.quest, required this.initialType});
  final Quest? quest;
  final QuestType initialType;

  @override
  State<_QuestForm> createState() => _QuestFormState();
}

class _QuestFormState extends State<_QuestForm> {
  late final _title = TextEditingController(text: widget.quest?.title ?? '');
  final _first = TextEditingController();
  late QuestType _type = widget.quest?.type ?? widget.initialType;

  @override
  void dispose() {
    _title.dispose();
    _first.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop<QuestInput>(context, (title: title, type: _type, firstStep: _first.text));
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.quest == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetTitle(isNew ? '新增大事件' : '編輯大事件'),
        TextField(
          controller: _title,
          autofocus: isNew,
          decoration: const InputDecoration(labelText: '名稱（例如：期末考、購物清單）'),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final t in QuestType.values)
              ChoiceChip(
                label: Text(t.label),
                avatar: Icon(t.icon, size: 16),
                selected: _type == t,
                onSelected: (_) => setState(() => _type = t),
              ),
          ],
        ),
        if (isNew) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _first,
            decoration: const InputDecoration(labelText: '第一個細項（可留空）'),
            onSubmitted: (_) => _submit(),
          ),
        ],
        _buttons(context, _submit),
      ],
    );
  }
}

/// 新增 / 編輯細項。[type] 是所屬大事件的分類（每週任務才會顯示星期幾）。
Future<StepInput?> showStepSheet(BuildContext context,
    {required QuestType type, QuestStep? step}) {
  return _sheet<StepInput>(context, _StepForm(type: type, step: step));
}

class _StepForm extends StatefulWidget {
  const _StepForm({required this.type, this.step});
  final QuestType type;
  final QuestStep? step;

  @override
  State<_StepForm> createState() => _StepFormState();
}

class _StepFormState extends State<_StepForm> {
  late final _title = TextEditingController(text: widget.step?.title ?? '');
  late final _note = TextEditingController(text: widget.step?.note ?? '');
  late DateTime? _deadline = widget.step?.deadline;
  late final Set<int> _weekdays = {...?widget.step?.weekdays};
  // 新的主線 / 支線細項預設「1 小時前」震動提醒；每週任務預設不提醒
  late int? _remind = widget.step != null
      ? widget.step!.remindBefore
      : (widget.type.recurring ? null : 60);

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final init = _deadline ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
    );
    if (time == null) return;
    setState(() => _deadline =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final recurring = widget.type.recurring;
    Navigator.pop<StepInput>(context, (
      title: title,
      note: _note.text.trim(),
      // 每日 / 每週不使用手動期限，存檔時清掉，避免日後改分類時冒出舊期限
      deadline: recurring ? null : _deadline,
      weekdays: _weekdays.toList()..sort(),
      // 每日委託沒有期限，不提醒；每週任務可以
      remindBefore: widget.type == QuestType.daily ? null : _remind,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.step == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sheetTitle(isNew ? '新增細項' : '編輯細項'),
        TextField(
          controller: _title,
          autofocus: isNew,
          decoration: const InputDecoration(labelText: '細項名稱'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '備註（可留空）'),
        ),
        if (widget.type == QuestType.daily)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('每天凌晨 04:00 重新出現', style: TextStyle(color: GColors.sub)),
          ),
        if (widget.type == QuestType.weekly) ...[
          const SizedBox(height: 16),
          Text(
            _weekdays.isEmpty
                ? '沒選星期幾：整週都在，週日 24:00 截止，週一 04:00 重新出現'
                : '${weekdaysText(QuestStep(id: 0, title: '', weekdays: _weekdays.toList()))}出現，當天 24:00 截止',
            style: const TextStyle(color: GColors.sub),
          ),
          const SizedBox(height: 6),
          // 一～日 平均分成七格，任何螢幕寬度都排得下一行
          Row(
            children: [
              for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _DayToggle(
                      label: weekNames[d - 1],
                      selected: _weekdays.contains(d),
                      onTap: () => setState(
                          () => _weekdays.contains(d) ? _weekdays.remove(d) : _weekdays.add(d)),
                    ),
                  ),
                ),
            ],
          ),
        ],
        // 期限與提醒只給主線 / 支線；每日 / 每週有自動的時間規則
        if (!widget.type.recurring) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('設定期限'),
            subtitle: Text(_deadline == null
                ? '無期限'
                : '${formatDateTime(_deadline!)}（逾期 ${overdueHideAfter.inDays} 天後移出通知欄）'),
            value: _deadline != null,
            onChanged: (on) {
              if (on) {
                _pickDeadline();
              } else {
                setState(() => _deadline = null);
              }
            },
          ),
        ],
        if (!widget.type.recurring && _deadline != null)
          TextButton.icon(
            onPressed: _pickDeadline,
            icon: const Icon(Icons.edit_calendar),
            label: const Text('更改期限'),
          ),
        // 震動提醒：主線 / 支線要先設期限；每週任務用自動期限（當天 / 週日 24:00）
        if (!widget.type.recurring && _deadline != null || widget.type == QuestType.weekly) ...[
          const SizedBox(height: 8),
          Text(
            widget.type == QuestType.weekly ? '震動提醒（截止 24:00 前，不響鈴）' : '震動提醒（不響鈴）',
            style: const TextStyle(color: GColors.sub),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final m in remindOptions)
                ChoiceChip(
                  label: Text(m == null ? '不提醒' : '${durationText(m)}前'),
                  avatar: m == null ? null : const Icon(Icons.vibration, size: 16),
                  selected: _remind == m,
                  onSelected: (_) => setState(() => _remind = m),
                ),
            ],
          ),
        ],
        _buttons(context, _submit),
      ],
    );
  }
}

Future<bool> confirmDelete(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: GColors.header,
      title: const Text('確定刪除？'),
      content: Text('「$name」將被刪除，無法復原。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('刪除', style: TextStyle(color: GColors.overdue)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 星期幾的選擇格（選中 = 金色底）。
class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? GColors.gold.withValues(alpha: 0.35) : Colors.transparent,
          border: Border.all(color: selected ? GColors.gold : Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? GColors.goldBright : GColors.text,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
