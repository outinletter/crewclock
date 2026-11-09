import 'package:flutter/material.dart';

class FlightScheduleSummary extends StatelessWidget {
  const FlightScheduleSummary(
      {super.key,
      required this.date,
      required this.departure,
      required this.arrival,
      required this.number,
      required this.route,
      this.timeSuffix = 'L'});
  final String date, departure, arrival, number, route;
  final String timeSuffix;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
        key: const ValueKey('flight-summary-background'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, constraints) {
            final accessible = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final compact = constraints.maxWidth < 340;
            final clockStyle = TextStyle(
                fontSize: compact ? 18 : 20,
                letterSpacing: -.4,
                fontWeight: FontWeight.w800,
                color: colors.primary,
                fontFeatures: const [FontFeature.tabularFigures()]);
            final dateBadge = Tooltip(
                message: date,
                child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: compact ? 6 : 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(date,
                        maxLines: accessible ? null : 1,
                        style: TextStyle(
                            fontSize: compact ? 12 : 14,
                            letterSpacing: -.3,
                            color: colors.onPrimary,
                            fontWeight: FontWeight.w700))));
            final routeText = Text('$number  $route',
                maxLines: accessible ? null : 1,
                style: TextStyle(
                    fontSize: compact ? 14 : 16,
                    letterSpacing: -.4,
                    fontWeight: FontWeight.w700));
            if (accessible) {
              return Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    dateBadge,
                    Text(departure, style: clockStyle),
                    routeText,
                    if (arrival.isNotEmpty) Text(arrival, style: clockStyle)
                  ]);
            }
            return Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    dateBadge,
                    const SizedBox(width: 8),
                    Text(departure, style: clockStyle),
                    const SizedBox(width: 8),
                    routeText,
                    if (arrival.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(arrival, style: clockStyle)
                    ],
                  ]),
                ));
          }),
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Departure ${route.split('→').first.trim()} ($timeSuffix) · Arrival ${route.split('→').last.trim()} ($timeSuffix)',
                  style:
                      TextStyle(fontSize: 10, color: colors.onSurfaceVariant))),
        ]));
  }
}
