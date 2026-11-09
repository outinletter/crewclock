import 'package:flutter/material.dart';

/// Keeps ordinary headings on one line without restricting accessibility text.
class WidthAwareTitle extends StatelessWidget {
  const WidthAwareTitle(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Text(text, style: style);
    }
    return Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(text, maxLines: 1, style: style)));
  }
}
