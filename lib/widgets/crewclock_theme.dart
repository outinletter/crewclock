import 'package:flutter/material.dart';

abstract final class CrewClockTheme {
  static const navy = Color(0xff08213f);
  static const blue = Color(0xff1676c8);
  static ColorScheme colors({required bool dark}) => ColorScheme.fromSeed(
          seedColor: blue,
          brightness: dark ? Brightness.dark : Brightness.light)
      .copyWith(surface: dark ? const Color(0xff10253d) : Colors.white);
  static Color statusColor(String label, {required bool dark}) {
    final s = label.toLowerCase();
    if (s == 'scheduled' || s == 'done') {
      return dark ? const Color(0xff8ad7a3) : const Color(0xff237849);
    }
    if (s.contains('failed') ||
        s.contains('permission') ||
        s.contains('not scheduled')) {
      return dark ? const Color(0xffffaaa2) : const Color(0xffb63232);
    }
    if (s.contains('ringing') ||
        s.contains('notification') ||
        s.contains('waiting') ||
        s.contains('missed')) {
      return dark ? const Color(0xffffd17c) : const Color(0xff8b6000);
    }
    return dark ? const Color(0xffb7c6d8) : const Color(0xff526174);
  }

  static ThemeData data({required bool dark}) => ThemeData(
        colorScheme: colors(dark: dark),
        useMaterial3: true,
        platform: TargetPlatform.iOS,
        scaffoldBackgroundColor:
            dark ? const Color(0xff07182c) : const Color(0xfff4f6f9),
        inputDecorationTheme: InputDecorationTheme(
          floatingLabelBehavior: FloatingLabelBehavior.never,
          filled: true,
          fillColor: dark ? const Color(0xff142b44) : const Color(0xffedf1f6),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: blue, width: 1.5)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: dark ? const Color(0xff10253d) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                  color: dark
                      ? const Color(0xff28425f)
                      : const Color(0xffdce5ef))),
        ),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 50))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48))),
        visualDensity: VisualDensity.compact,
      );
}
