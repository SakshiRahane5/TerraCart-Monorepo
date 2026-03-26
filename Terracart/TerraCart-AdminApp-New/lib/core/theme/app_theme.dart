import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData lightTheme({
    bool largeText = false,
    bool highContrast = false,
    bool dyslexiaFont = false,
  }) {
    final baseTextSize = largeText ? 18.0 : 14.0;
    final colorScheme = highContrast
        ? const ColorScheme.highContrastLight(
            primary: AppColors.highContrastPrimary,
            onPrimary: AppColors.highContrastSecondary,
            secondary: AppColors.highContrastAccent,
            onSecondary: AppColors.highContrastPrimary,
            surface: AppColors.highContrastSecondary,
            onSurface: AppColors.highContrastPrimary,
            error: AppColors.error,
            onError: AppColors.highContrastSecondary,
          )
        : const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: AppColors.textLight,
            secondary: AppColors.secondary,
            onSecondary: AppColors.textPrimary,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
            error: AppColors.error,
            onError: AppColors.textLight,
          );

    return _buildTheme(
      brightness: Brightness.light,
      baseTextSize: baseTextSize,
      dyslexiaFont: dyslexiaFont,
      highContrast: highContrast,
      colorScheme: colorScheme,
      scaffoldColor:
          highContrast ? AppColors.highContrastSecondary : AppColors.background,
      cardColor: highContrast
          ? AppColors.highContrastSecondary
          : AppColors.cardBackground,
      inputFillColor:
          highContrast ? AppColors.highContrastSecondary : AppColors.surface,
      shadowColor: highContrast ? Colors.transparent : AppColors.shadowLight,
    );
  }

  static ThemeData darkTheme({
    bool largeText = false,
    bool highContrast = false,
    bool dyslexiaFont = false,
  }) {
    final baseTextSize = largeText ? 18.0 : 14.0;
    final colorScheme = highContrast
        ? const ColorScheme.highContrastDark(
            primary: AppColors.highContrastAccent,
            onPrimary: AppColors.highContrastPrimary,
            secondary: AppColors.highContrastSecondary,
            onSecondary: AppColors.highContrastPrimary,
            surface: AppColors.highContrastPrimary,
            onSurface: AppColors.highContrastSecondary,
            error: AppColors.error,
            onError: AppColors.highContrastPrimary,
          )
        : const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.textLight,
            secondary: AppColors.secondary,
            onSecondary: AppColors.textPrimary,
            surface: AppColors.surfaceDark,
            onSurface: AppColors.textLight,
            error: AppColors.error,
            onError: AppColors.textLight,
          );

    return _buildTheme(
      brightness: Brightness.dark,
      baseTextSize: baseTextSize,
      dyslexiaFont: dyslexiaFont,
      highContrast: highContrast,
      colorScheme: colorScheme,
      scaffoldColor: highContrast
          ? AppColors.highContrastPrimary
          : AppColors.backgroundDark,
      cardColor: highContrast
          ? AppColors.highContrastPrimary
          : AppColors.cardBackgroundDark,
      inputFillColor:
          highContrast ? AppColors.highContrastPrimary : AppColors.surfaceDark,
      shadowColor: highContrast ? Colors.transparent : AppColors.shadowDark,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required double baseTextSize,
    required bool dyslexiaFont,
    required bool highContrast,
    required ColorScheme colorScheme,
    required Color scaffoldColor,
    required Color cardColor,
    required Color inputFillColor,
    required Color shadowColor,
  }) {
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = highContrast
        ? onSurface
        : onSurface.withValues(
            alpha: brightness == Brightness.dark ? 0.82 : 0.72);
    final borderColor = highContrast
        ? onSurface
        : (brightness == Brightness.dark
            ? AppColors.neutral700
            : AppColors.cardBorder);
    final appBarBackground = brightness == Brightness.light && !highContrast
        ? colorScheme.primary
        : colorScheme.surface;
    final appBarForeground = brightness == Brightness.light && !highContrast
        ? colorScheme.onPrimary
        : colorScheme.onSurface;
    final cardBorderSide = highContrast
        ? BorderSide(color: colorScheme.onSurface, width: 2)
        : BorderSide.none;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: colorScheme.primary,
      scaffoldBackgroundColor: scaffoldColor,
      canvasColor: scaffoldColor,
      cardColor: cardColor,
      colorScheme: colorScheme,
      fontFamily: dyslexiaFont ? 'OpenDyslexic' : null,
      disabledColor: onSurfaceVariant.withValues(alpha: 0.45),
      dividerColor: borderColor.withValues(alpha: highContrast ? 0.95 : 0.55),
      shadowColor: shadowColor,
      textTheme: _buildTextTheme(
        baseTextSize,
        dyslexiaFont,
        highContrast,
        brightness,
        colorScheme,
      ),
      iconTheme: IconThemeData(color: onSurfaceVariant),
      listTileTheme: ListTileThemeData(
        iconColor: onSurfaceVariant,
        textColor: onSurface,
        tileColor: Colors.transparent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackground,
        foregroundColor: appBarForeground,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: appBarForeground),
        actionsIconTheme: IconThemeData(color: appBarForeground),
        titleTextStyle: _themedTextStyle(
          dyslexiaFont: dyslexiaFont,
          fontSize: baseTextSize + 4,
          fontWeight: FontWeight.w600,
          color: appBarForeground,
        ),
      ),
      cardTheme: CardTheme(
        color: cardColor,
        elevation: highContrast ? 0 : 2,
        shadowColor: shadowColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: cardBorderSide,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(double.infinity, 56),
          elevation: highContrast ? 0 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: highContrast
                ? BorderSide(color: colorScheme.onPrimary, width: 1.5)
                : BorderSide.none,
          ),
          textStyle: _themedTextStyle(
            dyslexiaFont: dyslexiaFont,
            fontSize: baseTextSize + 2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(double.infinity, 56),
          side: BorderSide(
            color: colorScheme.primary,
            width: highContrast ? 2.4 : 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: _themedTextStyle(
            dyslexiaFont: dyslexiaFont,
            fontSize: baseTextSize + 2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return onSurfaceVariant.withValues(alpha: 0.55);
          }
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return highContrast ? colorScheme.onSurface : colorScheme.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return onSurfaceVariant.withValues(alpha: 0.25);
          }
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary
                .withValues(alpha: highContrast ? 0.7 : 0.4);
          }
          return onSurfaceVariant.withValues(alpha: highContrast ? 0.5 : 0.28);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: borderColor,
            width: highContrast ? 2 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: highContrast ? 3 : 2,
          ),
        ),
        labelStyle: _themedTextStyle(
          dyslexiaFont: dyslexiaFont,
          fontSize: baseTextSize,
          color: onSurfaceVariant,
        ),
        floatingLabelStyle: _themedTextStyle(
          dyslexiaFont: dyslexiaFont,
          fontSize: baseTextSize,
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: _themedTextStyle(
          dyslexiaFont: dyslexiaFont,
          fontSize: baseTextSize,
          color: onSurfaceVariant.withValues(alpha: 0.92),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.32),
        selectionHandleColor: colorScheme.primary,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: highContrast ? 0 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: highContrast
              ? BorderSide(color: colorScheme.onPrimary, width: 1.5)
              : BorderSide.none,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: _themedTextStyle(
          dyslexiaFont: dyslexiaFont,
          fontSize: baseTextSize - 2,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        ),
        unselectedLabelStyle: _themedTextStyle(
          dyslexiaFont: dyslexiaFont,
          fontSize: baseTextSize - 2,
          color: onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: borderColor.withValues(alpha: highContrast ? 0.95 : 0.5),
        thickness: highContrast ? 1.5 : 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: highContrast
            ? colorScheme.surface
            : colorScheme.secondary.withValues(alpha: 0.16),
        selectedColor:
            colorScheme.primary.withValues(alpha: highContrast ? 0.25 : 0.2),
        disabledColor: onSurfaceVariant.withValues(alpha: 0.2),
        labelStyle: _themedTextStyle(
          dyslexiaFont: dyslexiaFont,
          fontSize: baseTextSize - 2,
          color: onSurface,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: highContrast
              ? BorderSide(color: colorScheme.onSurface, width: 1.4)
              : BorderSide.none,
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: highContrast
              ? BorderSide(color: colorScheme.onSurface, width: 1.5)
              : BorderSide.none,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? AppColors.neutral200
            : AppColors.neutral900,
        contentTextStyle: _themedTextStyle(
          dyslexiaFont: dyslexiaFont,
          fontSize: baseTextSize,
          color: brightness == Brightness.dark
              ? AppColors.neutral900
              : AppColors.neutral200,
        ),
        actionTextColor: colorScheme.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: onSurfaceVariant.withValues(alpha: 0.25),
        linearTrackColor: onSurfaceVariant.withValues(alpha: 0.25),
      ),
    );
  }

  static TextTheme _buildTextTheme(
    double baseSize,
    bool dyslexiaFont,
    bool highContrast,
    Brightness brightness,
    ColorScheme colorScheme,
  ) {
    final primaryTextColor = colorScheme.onSurface;
    final secondaryTextColor = highContrast
        ? colorScheme.onSurface
        : colorScheme.onSurface
            .withValues(alpha: brightness == Brightness.dark ? 0.82 : 0.72);

    return TextTheme(
      displayLarge: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize + 22,
        fontWeight: FontWeight.bold,
        color: primaryTextColor,
      ),
      displayMedium: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize + 16,
        fontWeight: FontWeight.bold,
        color: primaryTextColor,
      ),
      displaySmall: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize + 12,
        fontWeight: FontWeight.w600,
        color: primaryTextColor,
      ),
      headlineLarge: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize + 10,
        fontWeight: FontWeight.w600,
        color: primaryTextColor,
      ),
      headlineMedium: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize + 6,
        fontWeight: FontWeight.w600,
        color: primaryTextColor,
      ),
      headlineSmall: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize + 4,
        fontWeight: FontWeight.w600,
        color: primaryTextColor,
      ),
      titleLarge: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize + 4,
        fontWeight: FontWeight.w500,
        color: primaryTextColor,
      ),
      titleMedium: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize + 2,
        fontWeight: FontWeight.w500,
        color: primaryTextColor,
      ),
      titleSmall: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize,
        fontWeight: FontWeight.w500,
        color: primaryTextColor,
      ),
      bodyLarge: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize + 2,
        fontWeight: FontWeight.normal,
        color: primaryTextColor,
      ),
      bodyMedium: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize,
        fontWeight: FontWeight.normal,
        color: primaryTextColor,
      ),
      bodySmall: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize - 2,
        fontWeight: FontWeight.normal,
        color: secondaryTextColor,
      ),
      labelLarge: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize,
        fontWeight: FontWeight.w600,
        color: primaryTextColor,
      ),
      labelMedium: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize - 2,
        fontWeight: FontWeight.w500,
        color: secondaryTextColor,
      ),
      labelSmall: _themedTextStyle(
        dyslexiaFont: dyslexiaFont,
        fontSize: baseSize - 4,
        fontWeight: FontWeight.w500,
        color: secondaryTextColor,
      ),
    );
  }

  static TextStyle _themedTextStyle({
    required bool dyslexiaFont,
    required double fontSize,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
  }) {
    if (dyslexiaFont) {
      return TextStyle(
        fontFamily: 'OpenDyslexic',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );
    }

    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }
}
