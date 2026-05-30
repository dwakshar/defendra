import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

double _track(double size) => -0.02 * size;

/// Static dark-palette styles — used in ThemeData definitions only.
/// In widgets, use the DefendraTypeX context extension instead.
class DefendraType {
  static TextStyle get display => GoogleFonts.inter(
        fontSize: 32, fontWeight: FontWeight.w500,
        color: DefendraColors.text, letterSpacing: _track(32), height: 1.1,
      );

  static TextStyle get title => GoogleFonts.inter(
        fontSize: 20, fontWeight: FontWeight.w500,
        color: DefendraColors.text, letterSpacing: _track(20), height: 1.2,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400,
        color: DefendraColors.text, letterSpacing: 0, height: 1.5,
      );

  static TextStyle get label => GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w400,
        color: DefendraColors.muted, letterSpacing: 0, height: 1.4,
      );

  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 14, fontWeight: FontWeight.w400,
        color: DefendraColors.text, letterSpacing: 0, height: 1.5,
      );

  static TextStyle get monoSmall => GoogleFonts.jetBrainsMono(
        fontSize: 12, fontWeight: FontWeight.w400,
        color: DefendraColors.muted, letterSpacing: 0, height: 1.4,
      );
}

/// Theme-adaptive text style accessors. Reads dText/dMuted from DefendraThemeX.
extension DefendraTypeX on BuildContext {
  TextStyle get dtDisplay => GoogleFonts.inter(
        fontSize: 32, fontWeight: FontWeight.w500,
        color: dText, letterSpacing: _track(32), height: 1.1,
      );

  TextStyle get dtTitle => GoogleFonts.inter(
        fontSize: 20, fontWeight: FontWeight.w500,
        color: dText, letterSpacing: _track(20), height: 1.2,
      );

  TextStyle get dtBody => GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400,
        color: dText, letterSpacing: 0, height: 1.5,
      );

  TextStyle get dtLabel => GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w400,
        color: dMuted, letterSpacing: 0, height: 1.4,
      );

  TextStyle get dtMono => GoogleFonts.jetBrainsMono(
        fontSize: 14, fontWeight: FontWeight.w400,
        color: dText, letterSpacing: 0, height: 1.5,
      );

  TextStyle get dtMonoSmall => GoogleFonts.jetBrainsMono(
        fontSize: 12, fontWeight: FontWeight.w400,
        color: dMuted, letterSpacing: 0, height: 1.4,
      );
}
