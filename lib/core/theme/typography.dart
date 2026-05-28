import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class DefendraType {
  // negative tracking formula: -0.02 * fontSize
  static double _track(double size) => -0.02 * size;

  static TextStyle get display => GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w500,
        color: DefendraColors.text,
        letterSpacing: _track(32),
        height: 1.1,
      );

  static TextStyle get title => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: DefendraColors.text,
        letterSpacing: _track(20),
        height: 1.2,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: DefendraColors.text,
        letterSpacing: 0,
        height: 1.5,
      );

  static TextStyle get label => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: DefendraColors.muted,
        letterSpacing: 0,
        height: 1.4,
      );

  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: DefendraColors.text,
        letterSpacing: 0,
        height: 1.5,
      );

  static TextStyle get monoSmall => GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: DefendraColors.muted,
        letterSpacing: 0,
        height: 1.4,
      );
}
