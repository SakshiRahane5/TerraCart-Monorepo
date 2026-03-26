import 'package:flutter/material.dart';

class AppColors {
  // Unified palette
  static const Color primary = Color(0xFFFF7043);
  static const Color secondary = Color(0xFFFFAB91);
  static const Color accent = Color(0xFFE64A19);
  static const Color background = Color(0xFFFFF8E1);
  static const Color backgroundDark = Color(0xFF1A1A1A);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF2C2C2C);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF2196F3);

  // Neutral + utility tokens
  static const Color neutral900 = Color(0xFF2C2C2C);
  static const Color neutral700 = Color(0xFF616161);
  static const Color neutral600 = Color(0xFF757575);
  static const Color neutral300 = Color(0xFFE0E0E0);
  static const Color neutral200 = Color(0xFFEEEEEE);
  static const Color pureBlack = Color(0xFF000000);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color transparent = Color(0x00000000);

  // Common shadow tokens
  static const Color shadowLight = Color(0x1F000000);
  static const Color shadowDark = Color(0x42000000);

  // Backward-compatible aliases
  static const Color primaryLight = secondary;
  static const Color primaryDark = accent;
  static const Color textPrimary = neutral900;
  static const Color textSecondary = neutral600;
  static const Color textLight = pureWhite;
  static const Color textDark = neutral300;
  static const Color cardBackground = surface;
  static const Color cardBackgroundDark = surfaceDark;
  static const Color cardBorder = neutral300;

  // Accessibility high-contrast colors
  static const Color highContrastPrimary = pureBlack;
  static const Color highContrastSecondary = pureWhite;
  static const Color highContrastAccent = Color(0xFFFFD700);

  // Urgency colors (color-blind safe)
  static const Color urgencyHigh = Color(0xFFE53935);
  static const Color urgencyMedium = Color(0xFFFF9800);
  static const Color urgencyLow = Color(0xFF4CAF50);

  // Gradient colors
  static const Color warmStart = Color(0xFFFF8A65);
  static const Color warmEnd = Color(0xFFFF5722);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accent],
  );

  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [warmStart, warmEnd],
  );

  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, warmEnd, accent],
  );
}
