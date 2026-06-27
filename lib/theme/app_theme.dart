import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Colour tokens ────────────────────────────────────────────────────────────

class AppColors {
  // Original tokens
  static const Color primaryGreen = Color(0xFF1D9E75);
  static const Color backgroundGreenTint = Color(0xFFE1F5EE);
  static const Color infoBlue = Color(0xFF378ADD);
  static const Color backgroundBlueTint = Color(0xFFE6F1FB);
  static const Color purple = Color(0xFF534AB7);
  static const Color backgroundPurpleTint = Color(0xFFEEEDFE);
  static const Color amber = Color(0xFFEF9F27);
  static const Color panicRed = Color(0xFFE24B4A);
  static const Color panicBackground = Color(0xFF0A0F1A);
  static const Color panicText = Color(0xFF8B9BB4);
  static const Color panicAccent = Color(0xFF2D4A6B);

  // Home-screen warm palette
  static const Color backgroundCream = Color(0xFFF5EAD3);
  static const Color textDark = Color(0xFF3D2E1F);
  static const Color greenModuleBg = Color(0xFFC4D9B4);
  static const Color greenAccent = Color(0xFF3A6B3A);
  static const Color blueModuleBg = Color(0xFFB8CFE0);
  static const Color blueAccent = Color(0xFF2E5577);
  static const Color purpleModuleBg = Color(0xFFC8BBD9);
  static const Color purpleAccent = Color(0xFF5B4985);
  static const Color coralModuleBg = Color(0xFFE8A89A);
  static const Color coralAccent = Color(0xFF9B4137);

  // Neutral
  static const Color white = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8F9FA);
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
}

// ─── Typography helpers ───────────────────────────────────────────────────────

/// Caveat — handwritten display font.
TextStyle displayStyle({
  double fontSize = 24,
  FontWeight fontWeight = FontWeight.w600,
  Color color = AppColors.textDark,
}) =>
    GoogleFonts.caveat(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );

/// Nunito — rounded soft body font.
TextStyle bodyStyle({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w400,
  Color color = AppColors.textDark,
}) =>
    GoogleFonts.nunito(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );

// ─── ThemeData ────────────────────────────────────────────────────────────────

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryGreen,
        primary: AppColors.primaryGreen,
        surface: AppColors.backgroundCream,
        onSurface: AppColors.textDark,
      ),
      scaffoldBackgroundColor: AppColors.backgroundCream,
      textTheme: GoogleFonts.nunitoTextTheme().copyWith(
        displayLarge: GoogleFonts.caveat(
          fontSize: 36,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
        displayMedium: GoogleFonts.caveat(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
        titleLarge: GoogleFonts.caveat(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
        titleMedium: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
        bodyLarge: GoogleFonts.nunito(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColors.textDark,
        ),
        bodyMedium: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textDark,
        ),
        bodySmall: GoogleFonts.nunito(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
        labelMedium: GoogleFonts.nunito(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundCream,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.caveat(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.backgroundCream,
        selectedItemColor: AppColors.textDark,
        unselectedItemColor: AppColors.textSecondary,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.panicRed,
        foregroundColor: AppColors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
      cardTheme: CardThemeData(
        color: AppColors.backgroundCream,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}
