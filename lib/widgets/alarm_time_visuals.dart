import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AlarmTimeDial extends StatefulWidget {
  const AlarmTimeDial(
      {super.key,
      required this.times,
      this.armedTimes,
      this.date,
      this.caption = 'Next alarm',
      this.hourCycle = 24,
      this.emphasizeNumbers = false});
  final DateTime? date;
  final String caption;
  final int hourCycle;
  final bool emphasizeNumbers;
  final List<DateTime> times;
  final List<DateTime>? armedTimes;

  @override
  State<AlarmTimeDial> createState() => _AlarmTimeDialState();
}

class _AlarmTimeDialState extends State<AlarmTimeDial> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    if (widget.emphasizeNumbers) {
      _clock =
          Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final roster = widget.emphasizeNumbers;
    final ordered = [...widget.times]..sort();
    final next = roster
        ? ordered
            .where((time) =>
                time.isAfter(now) &&
                (widget.armedTimes?.contains(time) ?? true))
            .firstOrNull
        : ordered.firstOrNull;
    if (next != null) {
      ordered.remove(next);
      ordered.insert(0, next);
    }
    if (next == null && !roster) return const SizedBox.shrink();
    final nextTime =
        next == null ? null : '${_two(next.hour)}:${_two(next.minute)}';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final localDate =
        '${_two(now.month)}/${_two(now.day)} ${weekdays[now.weekday - 1]}';
    final localTime = '${_two(now.hour)}:${_two(now.minute)}';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [
        Semantics(
            label: nextTime == null
                ? 'No upcoming flight alarm'
                : 'Alarm times. Next: $nextTime',
            child: SizedBox.square(
                dimension: 200,
                child: CustomPaint(
                    painter: _AlarmDialPainter(
                        ordered,
                        theme.colorScheme,
                        widget.hourCycle,
                        roster,
                        next != null,
                        widget.date,
                        theme.textTheme.bodyMedium?.fontFamily)))),
        if (roster) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(localDate,
                  style: theme.textTheme.bodySmall,
                  semanticsLabel: 'Current local date $localDate'),
              const SizedBox(width: 8),
              Text('$localTime (L)',
                  maxLines: 1,
                  semanticsLabel: 'Current local time $localTime',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(
            nextTime == null
                ? 'No upcoming flight alarms on this day'
                : '${widget.hourCycle}h · ${widget.caption} · $nextTime',
            style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

class _AlarmDialPainter extends CustomPainter {
  _AlarmDialPainter(this.times, this.colors, this.hourCycle,
      this.emphasizeNumbers, this.hasNext, this.date, this.fontFamily);
  final int hourCycle;
  final bool emphasizeNumbers;
  final bool hasNext;
  final String? fontFamily;
  final DateTime? date;
  final List<DateTime> times;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2;
    if (emphasizeNumbers) {
      _paintRoster(canvas, center, radius);
      return;
    }
    canvas.drawCircle(center, radius - 1, Paint()..color = colors.surface);
    if (emphasizeNumbers) {
      canvas.drawCircle(
          center,
          radius - 1.5,
          Paint()
            ..color = colors.outlineVariant
            ..style = PaintingStyle.stroke);
    }
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
                  fontSize: emphasizeNumbers ? 13 : (hourCycle == 12 ? 12 : 10),
                  fontWeight:
                      emphasizeNumbers ? FontWeight.w800 : FontWeight.w600)),
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
      final isNext = hasNext && i == 0;
      final paint = Paint()
        ..color = colors.primary.withValues(alpha: isNext ? 1 : .35)
        ..strokeWidth = isNext ? 3.5 : 2
        ..strokeCap = StrokeCap.round;
      for (final hand in [
        (time.hour % hourCycle + time.minute / 60) * math.pi * 2 / hourCycle,
        .0 + time.minute * math.pi / 30
      ].indexed) {
        final angle = hand.$2 - math.pi / 2;
        final tip = center +
            Offset(math.cos(angle), math.sin(angle)) *
                radius *
                (hand.$1 == 0 ? .42 : .66);
        if (emphasizeNumbers && isNext) {
          final width = hand.$1 == 0 ? 5.0 : 3.5;
          const shadowOffset = Offset(1, 2);
          canvas.drawLine(
              center + shadowOffset,
              tip + shadowOffset,
              Paint()
                ..color = colors.shadow.withValues(alpha: .25)
                ..strokeWidth = width
                ..strokeCap = StrokeCap.round
                ..maskFilter =
                    const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.5));
          paint
            ..strokeWidth = width
            ..shader = ui.Gradient.linear(center, tip, [
              colors.primary,
              Color.lerp(colors.primary, colors.onPrimary, .34)!,
            ]);
        }
        canvas.drawLine(center, tip, paint);
      }
    }
    canvas.drawCircle(center, 4, Paint()..color = colors.primary);
    if (emphasizeNumbers && times.isNotEmpty) {
      canvas.drawCircle(center, 1.5, Paint()..color = colors.onPrimary);
    }
  }

  void _paintRoster(Canvas canvas, Offset center, double radius) {
    const navy = Color(0xff101e2b);
    const blue = Color(0xff20a7f3);
    final faceRadius = radius - 4;
    final face = Rect.fromCircle(center: center, radius: faceRadius);
    canvas.drawShadow(Path()..addOval(face), const Color(0xff07101c), 3, true);
    canvas.drawCircle(
        center,
        radius - 1,
        Paint()
          ..shader = ui.Gradient.linear(face.topLeft, face.bottomRight, [
            const Color(0xffc9d1d9),
            const Color(0xff34424f),
            const Color(0xffa5b1bc)
          ], const [
            0,
            .5,
            1
          ]));
    canvas.drawCircle(
        center, radius - 3, Paint()..color = const Color(0xff080f17));
    canvas.drawCircle(
        center,
        faceRadius,
        Paint()
          ..shader = ui.Gradient.radial(
              center - Offset(radius * .25, radius * .35),
              radius * 1.6,
              [const Color(0xff24394a), navy, const Color(0xff0b141e)],
              const [0, .55, 1]));

    for (var tick = 0; tick < 60; tick++) {
      final angle = tick * math.pi / 30 - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final major = tick % 5 == 0;
      canvas.drawLine(
          center + direction * (radius - (major ? 17 : 12)),
          center + direction * (radius - 7),
          Paint()
            ..color = major ? const Color(0xffedf3f8) : const Color(0xff8599aa)
            ..strokeWidth = major ? 2.4 : 1
            ..strokeCap = StrokeCap.round);
    }

    void label(String value, Offset position, double size, Color color,
        FontWeight weight) {
      final text = TextPainter(
          text: TextSpan(
              text: value,
              style: TextStyle(
                  fontSize: size,
                  fontFamily: fontFamily,
                  color: color,
                  fontWeight: weight,
                  height: 1,
                  shadows: const [
                    Shadow(
                        color: Color(0xff000811),
                        offset: Offset(0, 1),
                        blurRadius: 2)
                  ])),
          textDirection: TextDirection.ltr)
        ..layout();
      text.paint(canvas, position - Offset(text.width / 2, text.height / 2));
      text.dispose();
    }

    for (var hour = 1; hour <= 12; hour++) {
      final angle = hour * math.pi / 6 - math.pi / 2;
      label(
          '$hour',
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 29),
          14,
          const Color(0xfff0f5fa),
          FontWeight.w600);
    }
    final plane = TextPainter(
        text: TextSpan(
            text: String.fromCharCode(CupertinoIcons.airplane.codePoint),
            style: TextStyle(
                fontSize: 24,
                color: const Color(0xffe8f2fa),
                fontFamily: CupertinoIcons.airplane.fontFamily,
                package: CupertinoIcons.airplane.fontPackage)),
        textDirection: TextDirection.ltr)
      ..layout();
    plane.paint(canvas, center + Offset(-plane.width / 2, -radius * .54));
    plane.dispose();
    label('CrewClock', center + Offset(0, -radius * .23), 8.5,
        const Color(0xffb1c4d4), FontWeight.w500);

    final selectedDate = date;
    if (selectedDate != null) {
      const months = [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC'
      ];
      final window = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: center + Offset(0, radius * .39), width: 54, height: 22),
          const Radius.circular(7));
      canvas.drawRRect(window, Paint()..color = const Color(0xff070e17));
      canvas.drawRRect(
          window,
          Paint()
            ..color = const Color(0xff28618b)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      label(
          '${months[selectedDate.month - 1]} ${selectedDate.day}',
          window.outerRect.center,
          10,
          const Color(0xffedf4fa),
          FontWeight.w700);
    }

    // Retain every selected-day alarm and draw the next active alarm on top.
    for (var i = times.length - 1; i >= 0; i--) {
      final time = times[i];
      final next = hasNext && i == 0;
      for (var hand = 0; hand < 2; hand++) {
        final angle = (hand == 0
                ? (time.hour % 12 + time.minute / 60) * math.pi / 6
                : time.minute * math.pi / 30) -
            math.pi / 2;
        final direction = Offset(math.cos(angle), math.sin(angle));
        final tip = center + direction * radius * (hand == 0 ? .52 : .75);
        final color = hand == 0 ? const Color(0xffeff6fc) : blue;
        final width = next ? (hand == 0 ? 4.5 : 4.0) : 1.4;
        if (next) {
          canvas.drawLine(
              center + const Offset(1, 2),
              tip + const Offset(1, 2),
              Paint()
                ..color = const Color(0xcc000711)
                ..strokeWidth = width + 1
                ..strokeCap = StrokeCap.round
                ..maskFilter =
                    const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.4));
        }
        canvas.drawLine(
            center,
            tip,
            Paint()
              ..strokeWidth = width
              ..strokeCap = StrokeCap.round
              ..shader = ui.Gradient.linear(center, tip, [
                color.withValues(alpha: next ? 1 : .32),
                Color.lerp(color, Colors.white, .25)!
                    .withValues(alpha: next ? 1 : .48),
              ]));
        if (next) {
          canvas.drawLine(
              center + Offset(-direction.dy, direction.dx) * .7,
              tip,
              Paint()
                ..color = Colors.white.withValues(alpha: .35)
                ..strokeWidth = .7
                ..strokeCap = StrokeCap.round);
        }
      }
      final angle = time.minute * math.pi / 30 - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
          center + direction * (radius - 15),
          center + direction * (radius - 7),
          Paint()
            ..color = const Color(0xffffd879).withValues(alpha: .8)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round);
    }
    canvas.drawCircle(
        center,
        4,
        Paint()
          ..shader = ui.Gradient.linear(
              center - const Offset(3, 3),
              center + const Offset(3, 3),
              [const Color(0xff9ce3ff), blue, const Color(0xff08649f)],
              const [0, .5, 1]));
    canvas.drawCircle(center - const Offset(1, 1), 1.2,
        Paint()..color = const Color(0xffe4f7ff));
  }

  @override
  bool shouldRepaint(covariant _AlarmDialPainter old) =>
      old.fontFamily != fontFamily ||
      old.date != date ||
      old.hourCycle != hourCycle ||
      old.emphasizeNumbers != emphasizeNumbers ||
      old.hasNext != hasNext ||
      old.colors != colors ||
      old.times.length != times.length ||
      old.times.indexed.any((entry) => entry.$2 != times[entry.$1]);
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
