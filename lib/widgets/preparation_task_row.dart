import 'dart:async';
import 'package:flutter/material.dart';

class PreparationTaskRow extends StatefulWidget {
  const PreparationTaskRow({super.key, required this.label, required this.checked, required this.editing, required this.onRename, required this.onToggle, required this.onDelete, this.checkedText});
  final String label;
  final String? checkedText;
  final bool checked, editing;
  final Future<bool> Function(String) onRename;
  final VoidCallback? onToggle, onDelete;
  @override
  State<PreparationTaskRow> createState() => _PreparationTaskRowState();
}
class _PreparationTaskRowState extends State<PreparationTaskRow> {
  late final TextEditingController controller;
  Timer? pending;
  @override
  void initState() { super.initState(); controller = TextEditingController(text: widget.label); }
  @override
  void didUpdateWidget(covariant PreparationTaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label && controller.text == oldWidget.label) controller.text = widget.label;
    if (oldWidget.editing && !widget.editing) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) save(); });
  }
  Future<void> save() async {
    pending?.cancel();
    final text = controller.text.trim();
    if (text.isEmpty) { controller.text = widget.label; return; }
    if (text != widget.label) await widget.onRename(text);
  }
  @override
  void dispose() { pending?.cancel(); controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: SizedBox(
    height: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 64 : 44,
    child: Row(children: [
      Tooltip(message: widget.checkedText == null ? 'Preparation complete' : 'Checked ${widget.checkedText}', child: Checkbox(value: widget.checked, onChanged: widget.onToggle == null ? null : (_) => widget.onToggle!())),
      Expanded(child: widget.editing ? TextField(controller: controller, maxLength: 100, textAlignVertical: TextAlignVertical.center, onChanged: (_) { pending?.cancel(); pending = Timer(const Duration(milliseconds: 650), save); }, onSubmitted: (_) => save(), onTapOutside: (_) { FocusManager.instance.primaryFocus?.unfocus(); save(); }, decoration: const InputDecoration(isDense: true, counterText: '', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8))) : Tooltip(message: widget.label, child: Text(widget.label, maxLines: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 2 : 1, overflow: TextOverflow.ellipsis))),
      if (widget.editing) ...[
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Semantics(label: 'Hold to reorder', child: const Icon(Icons.drag_handle, size: 20))),
        IconButton(tooltip: 'Delete preparation item', onPressed: widget.onDelete, icon: const Icon(Icons.remove_circle_outline, size: 20)),
      ],
    ]),
  ));
}
