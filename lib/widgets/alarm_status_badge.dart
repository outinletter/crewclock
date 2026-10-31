import 'package:flutter/material.dart';
import 'crewclock_theme.dart';

class AlarmStatusBadge extends StatelessWidget {
  const AlarmStatusBadge({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final color = CrewClockTheme.statusColor(label,
        dark: Theme.of(context).brightness == Brightness.dark);
    final success = label == 'Scheduled' || label == 'Done';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(success ? Icons.check_circle_outline : Icons.info_outline,
            size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
            child: Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
