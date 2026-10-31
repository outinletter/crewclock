import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'crewclock_theme.dart';

class CrewClockHeader extends StatelessWidget implements PreferredSizeWidget {
  const CrewClockHeader({super.key});
  @override
  Size get preferredSize => const Size.fromHeight(76);
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DecoratedBox(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [CrewClockTheme.navy, Color(0xff114e87)])),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Semantics(
                    header: true,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset('assets/icon/app_icon.png',
                                  width: 44,
                                  height: 44,
                                  cacheWidth: 132,
                                  excludeFromSemantics: true)),
                          const SizedBox(width: 12),
                          const Flexible(
                              child: Text('CrewClock',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -.8))),
                        ])),
              ))));
}
