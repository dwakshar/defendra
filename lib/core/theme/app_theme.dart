import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'colors.dart';
import 'typography.dart';

class AppTheme {
  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: DefendraColors.canvas,
        cardColor: DefendraColors.card,
        dividerColor: DefendraColors.border,
        colorScheme: const ColorScheme.dark(
          surface: DefendraColors.surface,
          onSurface: DefendraColors.text,
          primary: DefendraColors.text,
          onPrimary: DefendraColors.canvas,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: DefendraColors.surface,
          foregroundColor: DefendraColors.text,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          titleTextStyle: DefendraType.mono.copyWith(
            fontSize: 13,
            letterSpacing: 0.08,
          ),
          shape: const Border(
            bottom: BorderSide(color: DefendraColors.border, width: 0.5),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: DefendraColors.surface,
          selectedItemColor: DefendraColors.text,
          unselectedItemColor: DefendraColors.muted,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          showUnselectedLabels: true,
        ),
        textTheme: TextTheme(
          displayLarge: DefendraType.display,
          titleMedium: DefendraType.title,
          bodyMedium: DefendraType.body,
          labelSmall: DefendraType.label,
        ),
        dividerTheme: const DividerThemeData(
          color: DefendraColors.border,
          thickness: 0.5,
          space: 0,
        ),
      );

  static ThemeData get lightTheme => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: DefendraColors.canvasLight,
        cardColor: DefendraColors.cardLight,
        dividerColor: DefendraColors.borderLight,
        colorScheme: const ColorScheme.light(
          surface: DefendraColors.surfaceLight,
          onSurface: DefendraColors.textLight,
          primary: DefendraColors.textLight,
          onPrimary: DefendraColors.canvasLight,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: DefendraColors.surfaceLight,
          foregroundColor: DefendraColors.textLight,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          titleTextStyle: DefendraType.mono.copyWith(
            fontSize: 13,
            letterSpacing: 0.08,
            color: DefendraColors.textLight,
          ),
          shape: const Border(
            bottom: BorderSide(color: DefendraColors.borderLight, width: 0.5),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: DefendraColors.surfaceLight,
          selectedItemColor: DefendraColors.textLight,
          unselectedItemColor: DefendraColors.mutedLight,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          showUnselectedLabels: true,
        ),
        textTheme: TextTheme(
          displayLarge: DefendraType.display.copyWith(color: DefendraColors.textLight),
          titleMedium: DefendraType.title.copyWith(color: DefendraColors.textLight),
          bodyMedium: DefendraType.body.copyWith(color: DefendraColors.textLight),
          labelSmall: DefendraType.label.copyWith(color: DefendraColors.mutedLight),
        ),
        dividerTheme: const DividerThemeData(
          color: DefendraColors.borderLight,
          thickness: 0.5,
          space: 0,
        ),
      );
}
