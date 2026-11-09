import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Shared inline duration control for timers, repeating reminders and presets.
class DurationWheels extends StatefulWidget {
  const DurationWheels(
      {super.key,
      required this.minutes,
      required this.onChanged,
      this.enabled = true,
      this.onScrollingChanged});
  final int minutes;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final ValueChanged<bool>? onScrollingChanged;
  @override
  State<DurationWheels> createState() => _DurationWheelsState();
}

const int maxDurationHours = 24;

class _DurationWheelsState extends State<DurationWheels> {
  late final FixedExtentScrollController hours, minutes;
  late int h, m;
  int scrolls = 0;
  @override
  void initState() {
    super.initState();
    h = (widget.minutes ~/ 60).clamp(0, maxDurationHours);
    m = widget.minutes % 60;
    hours = FixedExtentScrollController(initialItem: h);
    minutes = FixedExtentScrollController(initialItem: m);
  }

  @override
  void didUpdateWidget(covariant DurationWheels old) {
    super.didUpdateWidget(old);
    if (old.minutes != widget.minutes && widget.minutes != h * 60 + m) {
      h = (widget.minutes ~/ 60).clamp(0, maxDurationHours);
      m = widget.minutes % 60;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (hours.hasClients) hours.jumpToItem(h);
        if (minutes.hasClients) minutes.jumpToItem(m);
      });
    }
  }

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    super.dispose();
  }

  void changed() {
    if (h == maxDurationHours && m != 0) {
      m = 0;
      if (minutes.hasClients) minutes.jumpToItem(0);
    }
    widget.onChanged(h * 60 + m);
  }

  Widget wheel(FixedExtentScrollController controller, int count, String unit,
          ValueChanged<int> select) =>
      Expanded(
          child: Row(children: [
        Expanded(
            child: Semantics(
                label: unit == 'h' ? 'Hours' : 'Minutes',
                child: CupertinoPicker(
                    scrollController: controller,
                    itemExtent: 20,
                    onSelectedItemChanged: select,
                    children: List.generate(
                        count,
                        (i) => Center(
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('$i',
                                    style: TextStyle(
                                        fontSize: 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface)))))))),
        SizedBox(
            width: 12,
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child:
                    Text(unit, style: Theme.of(context).textTheme.labelSmall))),
      ]));
  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification) {
              scrolls++;
              widget.onScrollingChanged?.call(true);
            }
            if (notification is ScrollEndNotification) {
              scrolls = (scrolls - 1).clamp(0, 10);
              widget.onScrollingChanged?.call(scrolls > 0);
            }
            return false;
          },
          child: IgnorePointer(
              ignoring: !widget.enabled,
              child: Opacity(
                  opacity: widget.enabled ? 1 : .45,
                  child: SizedBox(
                      width: 140,
                      height: 32,
                      child: Row(children: [
                        wheel(hours, maxDurationHours + 1, 'h', (n) {
                          h = n;
                          changed();
                        }),
                        const SizedBox(width: 4),
                        wheel(minutes, 60, 'm', (n) {
                          m = n;
                          changed();
                        })
                      ])))));
}

class DurationAlarmCard extends StatelessWidget {
  const DurationAlarmCard(
      {super.key,
      required this.label,
      required this.hint,
      required this.minutes,
      required this.onChanged,
      required this.onAdd,
      this.enabled = true,
      this.error,
      this.onLabelChanged,
      this.showAddButton = true,
      this.addTooltip,
      this.actionIcon = Icons.add,
      this.onScrollingChanged});
  final TextEditingController label;
  final String hint;
  final int minutes;
  final ValueChanged<int> onChanged;
  final VoidCallback? onAdd;
  final ValueChanged<String>? onLabelChanged;
  final bool enabled;
  final bool showAddButton;
  final String? addTooltip;
  final IconData actionIcon;
  final ValueChanged<bool>? onScrollingChanged;
  final String? error;
  @override
  Widget build(BuildContext context) => Card.outlined(
      color: Color.alphaBlend(const Color(0xff9293cd).withValues(alpha: .065),
          Theme.of(context).colorScheme.surface),
      child: Padding(
          padding: const EdgeInsets.all(8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: label,
                      style: const TextStyle(fontSize: 15, height: 1.2),
                      enabled: enabled,
                      maxLength: 100,
                      onChanged: onLabelChanged,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                          hintText: hint,
                          counterText: '',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 12)))),
              const SizedBox(width: 6),
              DurationWheels(
                  minutes: minutes,
                  enabled: enabled,
                  onChanged: onChanged,
                  onScrollingChanged: onScrollingChanged),
              if (showAddButton) const SizedBox(width: 4),
              if (showAddButton)
                IconButton.filledTonal(
                    tooltip: addTooltip ?? 'Add $hint',
                    onPressed: enabled ? onAdd : null,
                    icon: Icon(actionIcon))
            ]),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))
          ])));
}
