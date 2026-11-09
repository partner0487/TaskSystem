import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

typedef QuestInput = ({String title, QuestType type, String? firstStep});
typedef StepInput = ({String title, String note, DateTime? deadline});

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

/// 新增 / 編輯細項。
Future<StepInput?> showStepSheet(BuildContext context, {QuestStep? step}) {
  return _sheet<StepInput>(context, _StepForm(step: step));
}

class _StepForm extends StatefulWidget {
  const _StepForm({this.step});
  final QuestStep? step;

  @override
  State<_StepForm> createState() => _StepFormState();
}

class _StepFormState extends State<_StepForm> {
  late final _title = TextEditingController(text: widget.step?.title ?? '');
  late final _note = TextEditingController(text: widget.step?.note ?? '');
  late DateTime? _deadline = widget.step?.deadline;

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
    Navigator.pop<StepInput>(
        context, (title: title, note: _note.text.trim(), deadline: _deadline));
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
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('設定期限'),
          subtitle: Text(_deadline == null ? '無期限（像記事本一樣）' : formatDateTime(_deadline!)),
          value: _deadline != null,
          onChanged: (on) {
            if (on) {
              _pickDeadline();
            } else {
              setState(() => _deadline = null);
            }
          },
        ),
        if (_deadline != null)
          TextButton.icon(
            onPressed: _pickDeadline,
            icon: const Icon(Icons.edit_calendar),
            label: const Text('更改期限'),
          ),
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
