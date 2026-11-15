import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// One entry of an [IosMenuButton] action sheet.
class IosMenuItem<T> {
  const IosMenuItem(this.value, this.label, {this.destructive = false});
  final T value;
  final String label;
  final bool destructive;
}

/// Opens an iOS action sheet and reports the chosen value. Shows an ellipsis
/// button unless [child] is given.
class IosMenuButton<T> extends StatelessWidget {
  const IosMenuButton(
      {super.key,
      required this.tooltip,
      required this.items,
      required this.onSelected,
      this.title,
      this.child,
      this.enabled = true});
  final String tooltip;
  final String? title;
  final List<IosMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final Widget? child;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final chosen = await showCupertinoModalPopup<IosMenuItem<T>>(
        context: context,
        builder: (c) => CupertinoActionSheet(
            title: title == null ? null : Text(title!),
            actions: [
              for (final item in items)
                CupertinoActionSheetAction(
                    isDestructiveAction: item.destructive,
                    onPressed: () => Navigator.pop(c, item),
                    child: Text(item.label))
            ],
            cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel'))));
    if (chosen != null) onSelected(chosen.value);
  }

  @override
  Widget build(BuildContext context) => child == null
      ? IconButton(
          tooltip: tooltip,
          onPressed: enabled ? () => _open(context) : null,
          icon: const Icon(CupertinoIcons.ellipsis_circle))
      : Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => _open(context) : null,
              child: child));
}

/// Wheel date or time picker in a bottom sheet with a Done button. Returns
/// null when dismissed without confirming.
Future<DateTime?> showIosDatePicker(BuildContext context,
    {required DateTime initial,
    CupertinoDatePickerMode mode = CupertinoDatePickerMode.date}) {
  var value = initial;
  return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (c) => Container(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Cancel')),
                      CupertinoButton(
                          onPressed: () => Navigator.pop(c, value),
                          child: const Text('Done',
                              style: TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                SizedBox(
                    height: 216,
                    child: CupertinoTheme(
                        data: CupertinoThemeData(
                            brightness: Theme.of(context).brightness),
                        child: CupertinoDatePicker(
                            mode: mode,
                            use24hFormat: true,
                            initialDateTime: initial,
                            minimumYear: 2000,
                            maximumYear: 2100,
                            onDateTimeChanged: (v) => value = v))),
              ]))));
}

/// iOS confirmation alert; resolves to true only when confirmed.
Future<bool> confirmIos(BuildContext context,
    {required String title,
    required String message,
    required String confirm,
    bool destructive = false}) async {
  final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel')),
                CupertinoDialogAction(
                    isDestructiveAction: destructive,
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(confirm)),
              ]));
  return result == true;
}
