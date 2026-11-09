import 'package:flutter/material.dart';
import 'duration_wheels.dart';

class RelativeAlarmEditor extends StatefulWidget {
  const RelativeAlarmEditor({super.key, required this.onAdd});
  final Future<void> Function(String label, int minutes) onAdd;
  @override
  State<RelativeAlarmEditor> createState() => _RelativeAlarmEditorState();
}

class _RelativeAlarmEditorState extends State<RelativeAlarmEditor> {
  final label = TextEditingController();
  int minutes = 60;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    label.dispose();
    super.dispose();
  }

  Future<void> save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onAdd(
          label.text.trim().isEmpty ? 'Timer' : label.text.trim(), minutes);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not reserve the timer. Try again.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => DurationAlarmCard(
      label: label,
      hint: 'Timer',
      addTooltip: 'Add timer',
      minutes: minutes,
      onChanged: (n) => setState(() => minutes = n),
      onAdd: save,
      enabled: !saving,
      error: error);
}
