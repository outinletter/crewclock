import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'crewclock_theme.dart';

class CrewClockHeader extends StatelessWidget implements PreferredSizeWidget {
  const CrewClockHeader({super.key, this.pageTitle, this.actions = const []});
  final String? pageTitle;
  final List<Widget> actions;
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DecoratedBox(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [CrewClockTheme.navy, Color(0xff114e87)])),
          child: SafeArea(
              bottom: false,
              child: SizedBox(
                  height: 64,
                  child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 12),
                      child: Semantics(
                          header: true,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                    child: Text('CrewClock',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textScaler:
                                            MediaQuery.textScalerOf(context)
                                                .clamp(maxScaleFactor: 1.2),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -.6))),
                                IconButtonTheme(
                                    data: IconButtonThemeData(
                                        style: IconButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            disabledForegroundColor:
                                                Colors.white38)),
                                    child: IconTheme(
                                        data: const IconThemeData(
                                            color: Colors.white, size: 22),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: actions))),
                              ])))))));
}
