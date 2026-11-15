import 'package:flutter/material.dart';
import 'crewclock_theme.dart';

/// Horizontal duty timeline for one departure: preparation, flight, the
/// home-base WOCL window and one clock row per relevant time zone.
/// [data] comes from `CrewClockStore.dutyRibbon`.
class DutyRibbon extends StatelessWidget {
  const DutyRibbon({super.key, required this.data, required this.dark});
  final Map data;
  final bool dark;

  static String _duration(int minutes) =>
      '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

  Color get _wocl => CrewClockTheme.caution(dark: dark);

  Widget _legend(Color color, String text, Color textColor) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Flexible(
            child:
                Text(text, style: TextStyle(fontSize: 12, color: textColor))),
      ]);

  @override
  Widget build(BuildContext context) {
    final colors = CrewClockTheme.colors(dark: dark);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final axes = data['axes'] as List;
    final block = data['blockMinutes'] as int?;
    final overlap = data['woclFlightMinutes'] as int?;
    final row = scaler.scale(18);
    final summary = [
      block == null
          ? 'Arrival time not in roster'
          : 'Block ${_duration(block)}',
      if (overlap != null)
        overlap == 0
            ? 'No WOCL in flight'
            : 'WOCL in flight ${_duration(overlap)}'
    ];
    return Container(
        key: const ValueKey('duty-ribbon'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(CrewClockTheme.cardRadius)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, children: [
            Text(summary.first,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface)),
            if (summary.length > 1)
              Text(summary[1],
                  key: const ValueKey('duty-ribbon-wocl'),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: overlap == 0 ? colors.onSurfaceVariant : _wocl)),
          ]),
          const SizedBox(height: 8),
          Semantics(
              label: 'Duty timeline. ${summary.join('. ')}. '
                  'Clock rows: ${axes.map((a) => a['label']).join(', ')}.',
              child: ExcludeSemantics(
                  child: SizedBox(
                      height: 40 + row * axes.length,
                      child: CustomPaint(
                          painter: _RibbonPainter(
                              data: data,
                              colors: colors,
                              wocl: _wocl,
                              ground: CrewClockTheme.ground(dark: dark),
                              row: row,
                              scaler: scaler))))),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _legend(CrewClockTheme.ground(dark: dark), 'Preparation',
                colors.onSurfaceVariant),
            _legend(colors.primary, 'Flight', colors.onSurfaceVariant),
            _legend(_wocl.withValues(alpha: .45),
                'WOCL · ${data['home']} 02–06', colors.onSurfaceVariant),
          ]),
          const SizedBox(height: 4),
          Text('Home-base body-clock low, for reference only.',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        ]));
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(
      {required this.data,
      required this.colors,
      required this.wocl,
      required this.ground,
      required this.row,
      required this.scaler});
  final Map data;
  final ColorScheme colors;
  final Color wocl, ground;
  final double row;
  final TextScaler scaler;

  static const _gutter = 38.0;

  TextPainter _text(String text, Color color,
          {FontWeight weight = FontWeight.w500, double size = 11}) =>
      TextPainter(
          text: TextSpan(
              text: text,
              style: TextStyle(
                  color: color,
                  fontSize: size,
                  fontWeight: weight,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1)
        ..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width - _gutter;
    double x(num fraction) => _gutter + width * fraction;
    const barTop = 14.0, barBottom = 32.0, axisTop = 40.0;

    for (final band in data['wocl'] as List) {
      final rect = Rect.fromLTRB(x(band[0]), 0, x(band[1]), size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          Paint()..color = wocl.withValues(alpha: .2));
      final label = _text('WOCL', wocl, weight: FontWeight.w700, size: 9);
      if (rect.width > label.width + 4) {
        label.paint(canvas, Offset(rect.center.dx - label.width / 2, 1));
      }
    }

    RRect bar(double from, double to) =>
        RRect.fromLTRBR(from, barTop, to, barBottom, const Radius.circular(6));
    canvas.drawRRect(
        bar(_gutter, size.width), Paint()..color = colors.outlineVariant);
    final dep = x(data['dep'] as num);
    canvas.drawRRect(bar(x(data['prep'] as num), dep), Paint()..color = ground);
    final arr = data['arr'] as num?;
    final flight = Rect.fromLTRB(
        dep, barTop, arr == null ? size.width : x(arr), barBottom);
    canvas.drawRRect(
        RRect.fromRectAndRadius(flight, const Radius.circular(6)),
        Paint()
          ..shader = arr != null
              ? null
              : LinearGradient(colors: [
                  colors.primary,
                  colors.primary.withValues(alpha: 0)
                ]).createShader(flight)
          ..color = colors.primary);

    for (final step in data['steps'] as List) {
      final center = Offset(x(step as num), (barTop + barBottom) / 2);
      canvas.drawCircle(center, 4, Paint()..color = colors.surface);
      canvas.drawCircle(
          center,
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = colors.primary);
    }

    final axes = data['axes'] as List;
    for (var i = 0; i < axes.length; i++) {
      final top = axisTop + row * i;
      _text('${axes[i]['label']}', colors.onSurfaceVariant,
              weight: FontWeight.w700)
          .paint(canvas, Offset(0, top + 2));
      var lastRight = _gutter - 4;
      for (final tick in axes[i]['ticks'] as List) {
        final label = _text('${tick['text']}', colors.onSurface);
        final left = (x(tick['x'] as num) - label.width / 2)
            .clamp(_gutter, size.width - label.width);
        if (left < lastRight + 4) continue;
        label.paint(canvas, Offset(left, top + 2));
        lastRight = left + label.width;
      }
    }
    for (final axis in axes.take(1)) {
      for (final tick in axis['ticks'] as List) {
        final at = x(tick['x'] as num);
        canvas.drawLine(Offset(at, barBottom + 1), Offset(at, barBottom + 5),
            Paint()..color = colors.outline);
      }
    }

    final now = data['now'] as num?;
    if (now != null) {
      canvas.drawLine(
          Offset(x(now), 8),
          Offset(x(now), size.height),
          Paint()
            ..strokeWidth = 1.5
            ..color = colors.error);
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.data != data || old.colors != colors || old.row != row;
}
