import 'package:flutter/material.dart';

abstract final class CrewClockTheme {
  static const navy = Color(0xff0b1b2e);
  static const blue = Color(0xff3a7bd5);

  /// Corner radius for cards and for controls inside them.
  static const cardRadius = 22.0, innerRadius = 14.0;

  // Role colours: [colors].primary is flight and primary actions; these
  // cover the other three meanings used across the timeline, rest planner
  // and alarm lists.
  /// Preparation and other time on the ground.
  static Color ground({required bool dark}) =>
      dark ? const Color(0xff5f7893) : const Color(0xff9db4d6);

  /// In-flight rest.
  static Color rest({required bool dark}) =>
      dark ? const Color(0xff2bb8a3) : const Color(0xff2f9e8a);

  /// WOCL and anything that needs attention without being an error.
  static Color caution({required bool dark}) =>
      dark ? const Color(0xfff2b544) : const Color(0xff8b6000);

  /// The one prominent clock time on a card, and supporting times.
  static const timeLarge = TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()]),
      timeSmall = TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()]);
  static ColorScheme colors({required bool dark}) => ColorScheme.fromSeed(
              seedColor: blue,
              brightness: dark ? Brightness.dark : Brightness.light)
          .copyWith(
        primary: dark ? const Color(0xff4da3ff) : blue,
        onPrimary: dark ? navy : Colors.white,
        onSurface: dark ? const Color(0xffe4edf7) : const Color(0xff1c2b45),
        onSurfaceVariant:
            dark ? const Color(0xff9fb2c8) : const Color(0xff5c6c7c),
        primaryContainer:
            dark ? const Color(0xff1a3a5e) : const Color(0xffdcebff),
        onPrimaryContainer: dark ? const Color(0xffd8ebff) : navy,
        secondaryContainer:
            dark ? const Color(0xff1a3a5e) : const Color(0xffe6f0ff),
        onSecondaryContainer: dark ? const Color(0xffd8ebff) : navy,
        surface: dark ? const Color(0xff122a44) : Colors.white,
        outlineVariant:
            dark ? const Color(0xff24405f) : const Color(0xffe1e8f5),
      );
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
      return caution(dark: dark);
    }
    return dark ? const Color(0xffb7c6d8) : const Color(0xff526174);
  }

  static ThemeData data({required bool dark}) => ThemeData(
        colorScheme: colors(dark: dark),
        useMaterial3: true,
        platform: TargetPlatform.iOS,
        scaffoldBackgroundColor: dark ? navy : const Color(0xfff4f7fd),
        inputDecorationTheme: InputDecorationTheme(
          floatingLabelBehavior: FloatingLabelBehavior.never,
          filled: true,
          fillColor: dark ? const Color(0xff18324f) : const Color(0xffeaf0fb),
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
              borderSide:
                  BorderSide(color: colors(dark: dark).primary, width: 1.5)),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: dark ? const Color(0xff122a44) : Colors.white,
          // Flat cards on the tinted page; no outline, as in iOS grouped lists.
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(cardRadius)),
        ),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44))),
        visualDensity: VisualDensity.compact,
      );
}
