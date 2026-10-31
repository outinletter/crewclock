import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

typedef SaveReminder = Future<void> Function(
    String label, int? minutes, String? date, String? time);

class HoursMinutesFields extends StatelessWidget {
  const HoursMinutesFields(
      {super.key,
      required this.hours,
      required this.minutes,
      this.enabled = true,
      this.onChanged});
  final TextEditingController hours, minutes;
  final bool enabled;
  final VoidCallback? onChanged;
  static int read(TextEditingController hours, TextEditingController minutes,
      {int minimum = 0}) {
    final h = int.tryParse(hours.text), m = int.tryParse(minutes.text);
    if (h == null ||
        m == null ||
        h < 0 ||
        h > 168 ||
        m < 0 ||
        m > 59 ||
        h * 60 + m < minimum ||
        h * 60 + m > 10080) {
      throw FormatException(minimum == 0
          ? 'Use 0–168 hours and 0–59 minutes, up to 168 hours total.'
          : 'Enter at least 1 minute, up to 168 hours total.');
    }
    return h * 60 + m;
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: TextField(
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                controller: hours,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => onChanged?.call(),
                decoration: InputDecoration(
                    labelText: 'Hours',
                    suffixText: 'h',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none)))),
        const SizedBox(width: 12),
        Expanded(
            child: TextField(
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                controller: minutes,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => onChanged?.call(),
                decoration: InputDecoration(
                    labelText: 'Minutes',
                    suffixText: 'min',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none)))),
      ]);
}

class InlineReminderEditor extends StatefulWidget {
  const InlineReminderEditor(
      {super.key,
      required this.label,
      required this.onSave,
      this.minutesBefore,
      this.date,
      this.time,
      this.zone,
      this.heading,
      this.status,
      this.enabled,
      this.busy = false,
      this.repeat = false,
      this.compact = false,
      this.summary = false,
      this.saveLabel = 'Save changes',
      this.onToggle,
      this.onDelete,
      this.onCancel});
  final String label;
  final String saveLabel;
  final int? minutesBefore;
  final String? date, time, zone, heading, status;
  final bool? enabled;
  final bool busy, repeat, compact, summary;
  final SaveReminder onSave;
  final Future<void> Function(bool)? onToggle;
  final Future<void> Function()? onDelete;
  final VoidCallback? onCancel;
  @override
  State<InlineReminderEditor> createState() => _InlineReminderEditorState();
}

class _InlineReminderEditorState extends State<InlineReminderEditor> {
  late final TextEditingController label, hours, minutes, date, time;
  bool dirty = false, saving = false;
  String? error;
  bool saved = false, expanded = false;
  @override
  void initState() {
    super.initState();
    label = TextEditingController();
    hours = TextEditingController();
    minutes = TextEditingController();
    date = TextEditingController();
    time = TextEditingController();
    _sync();
  }

  void _sync() {
    label.text = widget.label;
    hours.text = '${(widget.minutesBefore ?? 0) ~/ 60}';
    minutes.text = '${(widget.minutesBefore ?? 0) % 60}';
    date.text = widget.date ?? '';
    time.text = widget.time ?? '';
  }

  @override
  void didUpdateWidget(covariant InlineReminderEditor old) {
    super.didUpdateWidget(old);
    if (!dirty && !saving) _sync();
  }

  @override
  void dispose() {
    for (final c in [label, hours, minutes, date, time]) {
      c.dispose();
    }
    super.dispose();
  }

  void changed() => setState(() {
        dirty = true;
        saved = false;
        error = null;
      });
  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    try {
      final entered = label.text.trim();
      final text =
          widget.repeat && entered.isEmpty ? 'Repeating reminder' : entered;
      if (text.isEmpty || text.length > 100) {
        throw const FormatException('Enter a label within 100 characters.');
      }
      final total = widget.minutesBefore == null
          ? null
          : HoursMinutesFields.read(hours, minutes,
              minimum: widget.repeat ? 1 : 0);
      setState(() => saving = true);
      await widget.onSave(text, total, date.text, time.text);
      if (mounted) {
        setState(() {
          dirty = false;
          saved = true;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() => saving = true);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _number(TextEditingController controller, String text, String unit,
          bool disabled) =>
      SizedBox(
        width: 44,
        height: 48,
        child: TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: controller,
            enabled: !disabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => changed(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
                isDense: true,
                labelText: text,
                floatingLabelStyle: const TextStyle(fontSize: 10),
                suffixText: unit,
                suffixStyle: const TextStyle(fontSize: 11),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 3, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)))),
      );
  Widget _compact(bool disabled) => Card.outlined(
        margin: const EdgeInsets.only(top: 4),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.summary)
                    Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                            tooltip: 'Close editor',
                            onPressed: disabled
                                ? null
                                : () => setState(() => expanded = false),
                            icon: const Icon(Icons.keyboard_arrow_up))),
                  if (widget.heading != null || widget.status != null)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(spacing: 8, runSpacing: 2, children: [
                          if (widget.heading != null)
                            Text(widget.heading!,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.primary)),
                          if (widget.status != null)
                            Text(widget.status!,
                                style: Theme.of(context).textTheme.bodySmall),
                        ])),
                  Row(children: [
                    Expanded(
                        child: Tooltip(
                            message: label.text,
                            child: TextField(
                                onTapOutside: (_) => FocusManager
                                    .instance.primaryFocus
                                    ?.unfocus(),
                                controller: label,
                                enabled: !disabled,
                                onChanged: (_) => changed(),
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Reminder label',
                                    floatingLabelStyle: TextStyle(fontSize: 11),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 12),
                                    border: InputBorder.none)))),
                    _number(hours, 'Hours', 'h', disabled),
                    const SizedBox(width: 3),
                    _number(minutes, 'Minutes', 'm', disabled),
                    if (widget.onToggle != null)
                      SizedBox(
                          width: 44,
                          height: 48,
                          child: Tooltip(
                              message: 'Enable reminder',
                              child: Checkbox(
                                  value: widget.enabled ?? true,
                                  onChanged: disabled
                                      ? null
                                      : (v) => _perform(
                                          () => widget.onToggle!(v == true))))),
                    SizedBox(
                        width: 44,
                        height: 48,
                        child: IconButton(
                            tooltip: saved ? 'Saved' : 'Save',
                            onPressed:
                                disabled || (!dirty && widget.label.isNotEmpty)
                                    ? null
                                    : _save,
                            icon: Icon(
                                saved ? Icons.check : Icons.save_outlined,
                                color: dirty
                                    ? Theme.of(context).colorScheme.primary
                                    : null))),
                    if (widget.onDelete != null)
                      SizedBox(
                          width: 44,
                          height: 48,
                          child: IconButton(
                              tooltip: 'Delete reminder',
                              onPressed: disabled
                                  ? null
                                  : () => _perform(widget.onDelete!),
                              icon:
                                  const Icon(Icons.delete_outline, size: 20))),
                    if (widget.onCancel != null)
                      SizedBox(
                          width: 44,
                          height: 48,
                          child: IconButton(
                              tooltip: 'Cancel',
                              onPressed: disabled ? null : widget.onCancel,
                              icon: const Icon(Icons.close))),
                  ]),
                  if (error != null)
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12)),
                ])),
      );

  @override
  Widget build(BuildContext context) {
    final disabled = widget.busy || saving;
    if (widget.summary && !expanded) {
      final total = widget.minutesBefore ?? 0;
      return Card.outlined(
          margin: const EdgeInsets.only(top: 8),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: Text(widget.heading ?? '',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800)),
            title: Text(widget.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${total ~/ 60}h ${total % 60}m before departure'),
            onTap: disabled ? null : () => setState(() => expanded = true),
          ));
    }

    if (widget.compact &&
        widget.minutesBefore != null &&
        MediaQuery.sizeOf(context).width >= 350 &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
      return _compact(disabled);
    }
    return Card.outlined(
        margin: const EdgeInsets.only(top: 6),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.heading != null)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(widget.heading!,
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary))),
                  TextField(
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      controller: label,
                      enabled: !disabled,
                      onChanged: (_) => changed(),
                      decoration: InputDecoration(
                          labelText: widget.repeat
                              ? 'Reminder label (optional)'
                              : 'Reminder label',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none))),
                  const SizedBox(height: 8),
                  if (widget.minutesBefore != null) ...[
                    Text(widget.repeat ? 'Repeat every' : 'Before departure',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    HoursMinutesFields(
                        hours: hours,
                        minutes: minutes,
                        enabled: !disabled,
                        onChanged: changed),
                  ] else ...[
                    SizedBox(
                        height: MediaQuery.textScalerOf(context).scale(1) > 1.3
                            ? 144
                            : 120,
                        child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.dateAndTime,
                          itemExtent:
                              MediaQuery.textScalerOf(context).scale(1) > 1.3
                                  ? 36
                                  : 28,
                          use24hFormat: true,
                          initialDateTime:
                              DateTime.tryParse('${date.text}T${time.text}') ??
                                  DateTime.now(),
                          onDateTimeChanged: (value) {
                            date.text =
                                '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
                            time.text =
                                '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
                            changed();
                          },
                        )),
                    if (widget.zone != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(widget.zone!,
                              style: Theme.of(context).textTheme.bodySmall)),
                  ],
                  if (widget.status != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(widget.status!,
                            style: Theme.of(context).textTheme.bodySmall)),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 14),
                  Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (widget.onToggle != null)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Switch.adaptive(
                                value: widget.enabled ?? true,
                                onChanged: disabled
                                    ? null
                                    : (v) =>
                                        _perform(() => widget.onToggle!(v))),
                            Text(widget.enabled == true ? 'On' : 'Off')
                          ]),
                        if (widget.onCancel != null)
                          TextButton(
                              onPressed: disabled ? null : widget.onCancel,
                              child: const Text('Cancel')),
                        if (widget.onDelete != null)
                          IconButton(
                              tooltip: 'Delete reminder',
                              onPressed: disabled
                                  ? null
                                  : () => _perform(widget.onDelete!),
                              icon: const Icon(Icons.delete_outline)),
                        FilledButton.tonalIcon(
                            onPressed:
                                disabled || (!dirty && widget.label.isNotEmpty)
                                    ? null
                                    : _save,
                            icon: Icon(
                                saved ? Icons.check : Icons.save_outlined,
                                size: 18),
                            label: Text(saving
                                ? 'Saving…'
                                : saved
                                    ? 'Saved'
                                    : widget.saveLabel)),
                      ]),
                ])));
  }
}

/// Settings-only row: valid changes save automatically; deletion is by swipe.
class PreparationPresetRow extends StatefulWidget {
  const PreparationPresetRow(
      {super.key,
      required this.label,
      required this.minutesBefore,
      required this.onSave,
      required this.onDelete});
  final String label;
  final int minutesBefore;
  final SaveReminder onSave;
  final Future<void> Function() onDelete;
  @override
  State<PreparationPresetRow> createState() => _PreparationPresetRowState();
}

class _PreparationPresetRowState extends State<PreparationPresetRow> {
  late final TextEditingController label, hours, minutes;
  Timer? timer, savedTimer;
  String? error;
  bool dirty = false, saving = false, deleting = false, saved = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    label = TextEditingController(text: widget.label);
    hours = TextEditingController(text: '${widget.minutesBefore ~/ 60}');
    minutes = TextEditingController(text: '${widget.minutesBefore % 60}');
  }

  @override
  void dispose() {
    timer?.cancel();
    savedTimer?.cancel();
    // Flush valid edits when leaving this screen before the debounce expires.
    if (dirty && !deleting) {
      try {
        final text = label.text.trim();
        final total = HoursMinutesFields.read(hours, minutes);
        if (text.isNotEmpty && text.length <= 100) {
          widget
              .onSave(text, total, null, null)
              .catchError((Object error, StackTrace stack) {
            FlutterError.reportError(FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'CrewClock',
                context: ErrorDescription(
                    'saving preparation settings while leaving the screen')));
          });
        }
      } on FormatException {/* Invalid input is never persisted. */}
    }
    label.dispose();
    hours.dispose();
    minutes.dispose();
    super.dispose();
  }

  void changed(String _) {
    revision++;
    dirty = true;
    setState(() {
      error = null;
      saved = false;
    });
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 650), save);
  }

  Future<void> save() async {
    timer?.cancel();
    if (!dirty || deleting) return;
    if (saving) {
      timer = Timer(const Duration(milliseconds: 150), save);
      return;
    }
    final version = revision;
    try {
      final text = label.text.trim();
      if (text.isEmpty || text.length > 100) {
        throw const FormatException('Enter a reminder name.');
      }
      final total = HoursMinutesFields.read(hours, minutes);
      saving = true;
      await widget.onSave(text, total, null, null);
      if (mounted && version == revision) {
        setState(() {
          dirty = false;
          saved = true;
          error = null;
        });
        savedTimer?.cancel();
        savedTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => saved = false);
        });
      }
    } catch (e) {
      if (mounted && version == revision) setState(() => error = '$e');
    } finally {
      saving = false;
    }
  }

  Widget field(TextEditingController controller, String hint,
          {bool numeric = false}) =>
      TextField(
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        controller: controller,
        onChanged: changed,
        onEditingComplete: () {
          save();
          FocusScope.of(context).unfocus();
        },
        textAlign: numeric ? TextAlign.center : TextAlign.start,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        inputFormatters:
            numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
            labelText: hint,
            filled: true,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            suffixText: numeric ? (hint == 'Hours' ? 'h' : 'm') : null,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
      );
  @override
  Widget build(BuildContext context) => Dismissible(
        key: ValueKey('swipe-${widget.key}'),
        direction: DismissDirection.endToStart,
        background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.delete_outline)),
        confirmDismiss: (_) async {
          timer?.cancel();
          deleting = true;
          try {
            // Finish any queued edit before deleting, so it cannot restore the row.
            while (saving) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            await widget.onDelete();
          } catch (e) {
            deleting = false;
            if (mounted) setState(() => error = '$e');
          }
          return false;
        },
        child: Card.outlined(
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (MediaQuery.textScalerOf(context).scale(1) > 1.3) ...[
                        field(label, 'Reminder'),
                        Row(children: [
                          Expanded(child: field(hours, 'Hours', numeric: true)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: field(minutes, 'Minutes', numeric: true))
                        ]),
                      ] else
                        Row(children: [
                          Expanded(flex: 5, child: field(label, 'Reminder')),
                          const SizedBox(width: 8),
                          Expanded(
                              flex: 2,
                              child: field(hours, 'Hours', numeric: true)),
                          const SizedBox(width: 8),
                          Expanded(
                              flex: 2,
                              child: field(minutes, 'Minutes', numeric: true)),
                        ]),
                      if (saved)
                        const Align(
                            alignment: Alignment.centerRight,
                            child:
                                Text('Saved', style: TextStyle(fontSize: 11))),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                    ]))),
      );
}
