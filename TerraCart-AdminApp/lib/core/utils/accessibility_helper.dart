import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_colors.dart';

/// Helper for accessibility-aware notifications (vibration, visual alerts).
/// Use when showing snackbars to respect user's deaf/hard-of-hearing settings.
class AccessibilityHelper {
  /// Shows a snackbar with optional vibration when [vibrationEnabled] is enabled.
  static void showSnackBar(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.vibrationEnabled) {
      HapticFeedback.mediumImpact();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? AppColors.primary,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Triggers a brief vibration for important alerts (e.g. new order, KOT).
  static void triggerAlert(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.vibrationEnabled) {
      HapticFeedback.heavyImpact();
    }
  }
}
