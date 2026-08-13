import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium dark trading terminal palette.
abstract final class AppColors {
  static const bg = Color(0xFF0A0D12);
  static const surface = Color(0xFF141A24);
  static const surfaceHigh = Color(0xFF1C2433);
  static const border = Color(0xFF2A3447);
  static const accent = Color(0xFF00E5C3);
  static const accentDim = Color(0xFF00B89A);
  static const profit = Color(0xFF3DDC97);
  static const loss = Color(0xFFFF6B6B);
  static const warn = Color(0xFFFFB347);
  static const textPrimary = Color(0xFFF4F7FB);
  static const textMuted = Color(0xFF8B97AB);
  static const take = Color(0xFF1B4332);
  static const takeBorder = Color(0xFF3DDC97);
  static const noTrade = Color(0xFF3D2C1E);
  static const noTradeBorder = Color(0xFFFFB347);
  static const sitOut = Color(0xFF252A33);
  static const sitOutBorder = Color(0xFF6B7280);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accentDim,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.loss,
    ),
  );

  final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.accent : AppColors.textMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.accent : AppColors.textMuted,
          size: 24,
        );
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceHigh,
      selectedColor: AppColors.accent.withValues(alpha: 0.2),
      labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.textMuted),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Color decisionAccent(String decision) => switch (decision) {
      'TAKE' => AppColors.profit,
      'SIT_OUT' => AppColors.textMuted,
      _ => AppColors.warn,
    };

Color decisionSurface(String decision) => switch (decision) {
      'TAKE' => AppColors.take,
      'SIT_OUT' => AppColors.sitOut,
      _ => AppColors.noTrade,
    };

Color decisionBorder(String decision) => switch (decision) {
      'TAKE' => AppColors.takeBorder,
      'SIT_OUT' => AppColors.sitOutBorder,
      _ => AppColors.noTradeBorder,
    };

String formatInr(num value) {
  final sign = value < 0 ? '-' : '';
  final abs = value.abs();
  if (abs >= 100000) return '$sign₹${(abs / 100000).toStringAsFixed(2)}L';
  if (abs >= 1000) return '$sign₹${(abs / 1000).toStringAsFixed(1)}k';
  return '$sign₹${abs.toStringAsFixed(0)}';
}
