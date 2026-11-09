import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialLocalizations, Theme;

class CenteredDateTimePicker extends StatefulWidget {
  const CenteredDateTimePicker(
      {super.key,
      required this.initialDateTime,
      required this.onDateTimeChanged,
      this.itemExtent = 20});
  final DateTime initialDateTime;
  final ValueChanged<DateTime> onDateTimeChanged;
  final double itemExtent;
  @override
  State<CenteredDateTimePicker> createState() => _CenteredDateTimePickerState();
}

class _CenteredDateTimePickerState extends State<CenteredDateTimePicker> {
  late final FixedExtentScrollController dates, hours, minutes;
  late DateTime day;
  late int hour, minute;
  @override
  void initState() {
    super.initState();
    final at = widget.initialDateTime;
    day = DateTime.utc(at.year, at.month, at.day);
    hour = at.hour;
    minute = at.minute;
    dates = FixedExtentScrollController(
        initialItem: day.difference(DateTime.utc(1)).inDays);
    hours = FixedExtentScrollController(initialItem: hour);
    minutes = FixedExtentScrollController(initialItem: minute);
  }

  @override
  void dispose() {
    dates.dispose();
    hours.dispose();
    minutes.dispose();
    super.dispose();
  }

  void changed() => widget
      .onDateTimeChanged(DateTime(day.year, day.month, day.day, hour, minute));
  Widget text(String value) => Center(
      child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurface))));
  Widget numberWheel(FixedExtentScrollController controller, int count,
          String label, ValueChanged<int> selected) =>
      Expanded(
          flex: 2,
          child: Semantics(
              label: label,
              child: CupertinoPicker(
                  scrollController: controller,
                  itemExtent: widget.itemExtent,
                  looping: true,
                  onSelectedItemChanged: selected,
                  children: List.generate(
                      count, (i) => text(i.toString().padLeft(2, '0'))))));
  @override
  Widget build(BuildContext context) => Center(
      child: SizedBox(
          width: 280,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                flex: 4,
                child: Semantics(
                    label: 'Date',
                    child: CupertinoPicker.builder(
                        scrollController: dates,
                        itemExtent: widget.itemExtent,
                        onSelectedItemChanged: (index) {
                          day = DateTime.utc(1, 1, index + 1);
                          changed();
                        },
                        itemBuilder: (context, index) {
                          final date = DateTime.utc(1, 1, index + 1);
                          return text(MaterialLocalizations.of(context)
                              .formatShortDate(date));
                        }))),
            numberWheel(hours, 24, 'Hours', (index) {
              hour = index % 24;
              changed();
            }),
            numberWheel(minutes, 60, 'Minutes', (index) {
              minute = index % 60;
              changed();
            }),
          ])));
}
