import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class AlarmTimeDial extends StatelessWidget {
  const AlarmTimeDial(
      {super.key,
      required this.times,
      this.caption = 'Next alarm',
      this.hourCycle = 24,
      this.emphasizeNumbers = false});
  final String caption;
  final int hourCycle;
  final bool emphasizeNumbers;
  final List<DateTime> times;
  @override
  Widget build(BuildContext context) {
    final ordered = [...times]..sort();
    if (ordered.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [
        Semantics(
            label:
                'Alarm times. Next: ${ordered.first.hour}:${ordered.first.minute.toString().padLeft(2, '0')}',
            child: SizedBox.square(
                dimension: 200,
                child: CustomPaint(
                    painter: _AlarmDialPainter(
                        ordered,
                        Theme.of(context).colorScheme,
                        hourCycle,
                        emphasizeNumbers)))),
        const SizedBox(height: 6),
        Text(
            '${hourCycle}h · $caption · ${ordered.first.hour.toString().padLeft(2, '0')}:${ordered.first.minute.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class _AlarmDialPainter extends CustomPainter {
  _AlarmDialPainter(
      this.times, this.colors, this.hourCycle, this.emphasizeNumbers);
  final int hourCycle;
  final bool emphasizeNumbers;
  final List<DateTime> times;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius - 1, Paint()..color = colors.surface);
    for (var i = 0; i < 60; i++) {
      final angle = i * math.pi / 30 - math.pi / 2;
      final major = i % 5 == 0;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
          center + direction * (radius - (major ? 12 : 7)),
          center + direction * (radius - 3),
          Paint()
            ..color = colors.onSurfaceVariant.withValues(alpha: major ? .8 : .3)
            ..strokeWidth = major ? 2 : 1);
    }
    for (var hour = 1; hour <= hourCycle; hour++) {
      final angle = hour * math.pi * 2 / hourCycle - math.pi / 2;
      final text = TextPainter(
          text: TextSpan(
              text: '$hour',
              style: TextStyle(
                  color: colors.onSurface,
                  fontSize: hourCycle == 12 ? 12 : 10,
                  fontWeight:
                      emphasizeNumbers ? FontWeight.w700 : FontWeight.w600)),
          textDirection: TextDirection.ltr)
        ..layout();
      final direction = Offset(math.cos(angle), math.sin(angle));
      text.paint(
          canvas,
          center +
              direction * (radius - 25) -
              Offset(text.width / 2, text.height / 2));
      text.dispose();
    }
    // Paint the next occurrence last, so its hands remain clearly visible.
    for (var i = times.length - 1; i >= 0; i--) {
      final time = times[i];
      final paint = Paint()
        ..color = colors.primary.withValues(alpha: i == 0 ? 1 : .22)
        ..strokeWidth = i == 0 ? 3.5 : 2
        ..strokeCap = StrokeCap.round;
      for (final hand in [
        (time.hour % hourCycle + time.minute / 60) * math.pi * 2 / hourCycle,
        .0 + time.minute * math.pi / 30
      ].indexed) {
        final angle = hand.$2 - math.pi / 2;
        canvas.drawLine(
            center,
            center +
                Offset(math.cos(angle), math.sin(angle)) *
                    radius *
                    (hand.$1 == 0 ? .42 : .66),
            paint);
      }
    }
    canvas.drawCircle(center, 4, Paint()..color = colors.primary);
  }

  @override
  bool shouldRepaint(covariant _AlarmDialPainter old) =>
      old.hourCycle != hourCycle ||
      old.emphasizeNumbers != emphasizeNumbers ||
      old.colors != colors ||
      old.times.toString() != times.toString();
}

class IntervalCountdown extends StatefulWidget {
  const IntervalCountdown(
      {super.key,
      required this.next,
      required this.minutes,
      required this.enabled});
  final DateTime? next;
  final int minutes;
  final bool enabled;
  @override
  State<IntervalCountdown> createState() => _IntervalCountdownState();
}

class _IntervalCountdownState extends State<IntervalCountdown> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.next == null) {
      // Keep the reserved progress area stable when the toggle changes.
      return const SizedBox(height: 41);
    }
    final seconds = widget.next!.difference(DateTime.now()).inSeconds;
    final remaining = seconds.clamp(0, widget.minutes * 60);
    final fraction = (remaining / (widget.minutes * 60)).clamp(0.0, 1.0);
    return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 4),
          SizedBox(
              height: 22,
              child: Text(
                  seconds <= 0
                      ? 'Due now'
                      : '${remaining ~/ 3600}h ${(remaining % 3600) ~/ 60}m ${remaining % 60}s remaining',
                  style: Theme.of(context).textTheme.labelSmall)),
        ]));
  }
}
