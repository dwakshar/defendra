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

        // app bar: surface bg, no elevation, mono uppercase labels
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

        // bottom nav: surface bg, 0.5px top hairline
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
}
