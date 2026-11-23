import 'package:flutter/material.dart';

class MamPetColors {
  // Cozy 2D Game UI palette matching MamPet's thick-brown-line illustrations & sky-blue egg logo
  static const Color creamBg = Color(0xFFFFFBF3);
  static const Color warmSurface = Color(0xFFFFFFFF);
  static const Color warmSurfaceAlt = Color(0xFFF9F1E4);
  static const Color warmOutline = Color(0xFFE0CEBA);

  static const Color espresso = Color(0xFF2D201B);
  static const Color cocoaMuted = Color(0xFF6B584F);

  static const Color coralPrimary = Color(0xFFFF6B35);
  static const Color coralDeep = Color(0xFFC94A1A);
  static const Color coralSoft = Color(0xFFFFEFE6);
  static const Color honeySecondary = Color(0xFFF5A623);
  static const Color honeySoft = Color(0xFFFFF6DE);
  static const Color skyAccent = Color(0xFF0EA5E9);
  static const Color skySoft = Color(0xFFE3F5FF);
  static const Color sageAccent = Color(0xFF22A06B);
  static const Color sageSoft = Color(0xFFE8FAF0);
  static const Color silhouetteDark = Color(0xFF17202B);

  // Dark warm palette
  static const Color darkBg = Color(0xFF181312);
  static const Color darkSurface = Color(0xFF241C1A);
  static const Color darkSurfaceAlt = Color(0xFF302522);
  static const Color darkOutline = Color(0xFF4B3D37);

  static List<BoxShadow> softCardShadow({Color? tint}) => [
        BoxShadow(
          color: (tint ?? espresso).withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: (tint ?? espresso).withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];
}

class MamPetTheme {
  static TextTheme _buildGameTextTheme(TextTheme base, Color textColor) {
    return base
        .apply(
          fontFamily: 'Nunito',
          bodyColor: textColor,
          displayColor: textColor,
        )
        .copyWith(
          headlineLarge: base.headlineLarge?.copyWith(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: MamPetColors.coralPrimary,
      brightness: Brightness.light,
      primary: MamPetColors.coralPrimary,
      onPrimary: Colors.white,
      secondary: MamPetColors.honeySecondary,
      onSecondary: MamPetColors.espresso,
      tertiary: MamPetColors.sageAccent,
      surface: MamPetColors.warmSurface,
      onSurface: MamPetColors.espresso,
      surfaceContainerLowest: MamPetColors.creamBg,
      surfaceContainerLow: MamPetColors.warmSurfaceAlt,
      outline: MamPetColors.warmOutline,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Nunito',
    );

    return base.copyWith(
      scaffoldBackgroundColor: MamPetColors.creamBg,
      textTheme: _buildGameTextTheme(base.textTheme, MamPetColors.espresso),
      appBarTheme: const AppBarTheme(
        backgroundColor: MamPetColors.creamBg,
        foregroundColor: MamPetColors.espresso,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Fredoka',
          color: MamPetColors.espresso,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: MamPetColors.warmSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: MamPetColors.warmOutline, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          side: const BorderSide(color: MamPetColors.warmOutline, width: 1.8),
          textStyle: const TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MamPetColors.warmSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: MamPetColors.warmOutline, width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: MamPetColors.warmOutline, width: 1.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: MamPetColors.coralPrimary, width: 2.2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: MamPetColors.warmOutline, width: 1.4),
        selectedColor: MamPetColors.coralSoft,
        labelStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: MamPetColors.espresso,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MamPetColors.espresso,
        contentTextStyle: const TextStyle(
          fontFamily: 'Nunito',
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dividerTheme: const DividerThemeData(
        color: MamPetColors.warmOutline,
        thickness: 1.2,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: MamPetColors.coralPrimary,
      brightness: Brightness.dark,
      primary: const Color(0xFFFF8652),
      secondary: MamPetColors.honeySecondary,
      tertiary: const Color(0xFF4ADE80),
      surface: MamPetColors.darkSurface,
      outline: MamPetColors.darkOutline,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Nunito',
    );

    return base.copyWith(
      scaffoldBackgroundColor: MamPetColors.darkBg,
      textTheme: _buildGameTextTheme(base.textTheme, const Color(0xFFFFF5EB)),
      appBarTheme: const AppBarTheme(
        backgroundColor: MamPetColors.darkBg,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Fredoka',
          color: Color(0xFFFFF5EB),
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: MamPetColors.darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: MamPetColors.darkOutline, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MamPetColors.darkSurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: MamPetColors.darkOutline, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: MamPetColors.darkOutline, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
