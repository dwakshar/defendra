import 'package:flutter/material.dart';

class DefendraColors {
  // dark palette
  static const canvas     = Color(0xFF000000);
  static const surface    = Color(0xFF0A0A0A);
  static const card       = Color(0xFF171717);
  static const border     = Color(0xFF2A2A2A);
  static const muted      = Color(0xFF888888);
  static const text       = Color(0xFFEDEDED);

  // light palette — mirror
  static const canvasLight  = Color(0xFFFFFFFF);
  static const surfaceLight = Color(0xFFFAFAFA);
  static const cardLight    = Color(0xFFF4F4F4);
  static const borderLight  = Color(0xFFE5E5E5);
  static const mutedLight   = Color(0xFF666666);
  static const textLight    = Color(0xFF0A0A0A);

  // verdict accents — same across themes
  static const safe       = Color(0xFF00D26A);
  static const suspicious = Color(0xFFF5A623);
  static const scam       = Color(0xFFFF4D4D);
}

/// Theme-adaptive color accessors. Import colors.dart and call context.dCanvas etc.
extension DefendraThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get dCanvas  => isDark ? DefendraColors.canvas  : DefendraColors.canvasLight;
  Color get dSurface => isDark ? DefendraColors.surface : DefendraColors.surfaceLight;
  Color get dCard    => isDark ? DefendraColors.card    : DefendraColors.cardLight;
  Color get dBorder  => isDark ? DefendraColors.border  : DefendraColors.borderLight;
  Color get dMuted   => isDark ? DefendraColors.muted   : DefendraColors.mutedLight;
  Color get dText    => isDark ? DefendraColors.text    : DefendraColors.textLight;
}
