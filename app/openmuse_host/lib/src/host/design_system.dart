import 'package:flutter/material.dart';

abstract final class OpenMuseTokens {
  static const sidebarWidth = 232.0;
  static const assistantWidth = 354.0;
  static double sidebarWidthFor(double windowWidth) =>
      (windowWidth * 0.19).clamp(sidebarWidth, 290.0).toDouble();
  static double assistantWidthFor(double windowWidth) =>
      (windowWidth * 0.43).clamp(assistantWidth, 660.0).toDouble();
  static const topBarHeight = 42.0;
  static const itemHeight = 32.0;
  static const dialogRadius = 12.0;
  static const canvas = Color(0xffffffff);
  static const sidebar = Color(0xfff7f8fb);
  static const sidebarSelected = Color(0xffe8e9ee);
  static const sidebarHover = Color(0xffeff0f4);
  static const border = Color(0xffececf0);
  static const text = Color(0xff29292d);
  static const textMuted = Color(0xff77777e);
  static const accent = Color(0xff4c63d9);
  static const cyan = Color(0xff18aee5);
  static const scrim = Color(0x76000000);
  static const compactText = TextStyle(
    fontSize: 14,
    height: 1.25,
    color: text,
    fontWeight: FontWeight.w400,
  );
}

ThemeData buildOpenMuseTheme({Brightness brightness = Brightness.light}) =>
    ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? OpenMuseTokens.canvas
          : const Color(0xff191b20),
      colorScheme: ColorScheme.fromSeed(
        seedColor: OpenMuseTokens.accent,
        brightness: brightness,
      ),
      fontFamily: 'SF Pro Text',
      textTheme: TextTheme(
        bodyMedium: OpenMuseTokens.compactText.copyWith(
          color: brightness == Brightness.light
              ? OpenMuseTokens.text
              : const Color(0xffe5e7ec),
        ),
      ),
      dividerColor: brightness == Brightness.light
          ? OpenMuseTokens.border
          : const Color(0xff383b43),
      dialogTheme: DialogThemeData(
        backgroundColor: brightness == Brightness.light
            ? Colors.white
            : const Color(0xff24262c),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OpenMuseTokens.dialogRadius),
        ),
      ),
      splashFactory: NoSplash.splashFactory,
      hoverColor: brightness == Brightness.light
          ? const Color(0x0a000000)
          : const Color(0x1affffff),
    );
