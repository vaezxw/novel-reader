import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(
        brightness: Brightness.light,
        paper: AppColors.paper,
        ink: AppColors.ink,
        muted: AppColors.inkMuted,
        rule: AppColors.rule,
        lamp: AppColors.lamp,
        onLamp: AppColors.onLamp,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        paper: AppColors.nightPaper,
        ink: AppColors.nightInk,
        muted: AppColors.nightMuted,
        rule: AppColors.nightRule,
        lamp: AppColors.nightLamp,
        onLamp: AppColors.onNightLamp,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color paper,
    required Color ink,
    required Color muted,
    required Color rule,
    required Color lamp,
    required Color onLamp,
  }) {
    final uiText = GoogleFonts.notoSansScTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(bodyColor: ink, displayColor: ink);

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: lamp,
      onPrimary: onLamp,
      secondary: ink,
      onSecondary: paper,
      surface: paper,
      onSurface: ink,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      outline: rule,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: paper,
      textTheme: uiText,
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.notoSansSc(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: ink,
          letterSpacing: -0.3,
        ),
      ),
      dividerTheme: DividerThemeData(color: rule, thickness: 1, space: 1),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: lamp,
        foregroundColor: onLamp,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: lamp.withValues(alpha: 0.14),
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.notoSansSc(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? lamp : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(size: 24, color: selected ? lamp : muted);
        }),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: GoogleFonts.notoSansSc(color: paper, fontSize: 14),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Long-form reading face — use on reader pages only.
  static TextStyle readingBody({
    required Color color,
    double fontSize = 19,
    double height = 1.78,
  }) {
    return GoogleFonts.notoSerifSc(
      color: color,
      fontSize: fontSize,
      height: height,
      fontWeight: FontWeight.w400,
    );
  }
}
