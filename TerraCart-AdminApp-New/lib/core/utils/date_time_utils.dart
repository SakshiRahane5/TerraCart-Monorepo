import 'package:intl/intl.dart';

/// Centralized date/time utilities for TerraAdmin app.
/// All displayed times are converted to Indian Standard Time (IST, UTC+5:30).
class DateTimeUtils {
  static const Duration _istOffset = Duration(hours: 5, minutes: 30);

  /// Converts any [DateTime] to Indian Standard Time (IST).
  /// Works correctly for both UTC and local DateTime values.
  static DateTime toIST(DateTime dateTime) {
    final utc = dateTime.toUtc();
    return utc.add(_istOffset);
  }

  /// Parses an ISO8601 or date string and returns IST DateTime.
  static DateTime parseToIST(String dateTimeStr) {
    final parsed = DateTime.parse(dateTimeStr);
    return toIST(parsed);
  }

  /// Formats a DateTime for display in IST (e.g. "hh:mm a").
  static String formatTimeIST(DateTime dateTime) {
    return DateFormat('hh:mm a').format(toIST(dateTime));
  }

  /// Formats a DateTime for display in IST (e.g. "dd MMM yyyy, hh:mm a").
  static String formatDateTimeIST(DateTime dateTime, [String pattern = 'dd MMM yyyy, hh:mm a']) {
    return DateFormat(pattern).format(toIST(dateTime));
  }

  /// Formats a DateTime for short display (e.g. "dd MMM, hh:mm a").
  static String formatShortDateTimeIST(DateTime dateTime) {
    return DateFormat('dd MMM, hh:mm a').format(toIST(dateTime));
  }

  /// Formats a DateTime for date-only display (e.g. "dd MMM yyyy").
  static String formatDateIST(DateTime dateTime) {
    return DateFormat('dd MMM yyyy').format(toIST(dateTime));
  }

  /// Returns current time in IST.
  static DateTime nowIST() {
    return toIST(DateTime.now());
  }

  /// Returns "time ago" string (e.g. "2 min ago") using IST for comparison.
  static String getTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().toUtc().difference(dateTime.toUtc());
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return formatDateIST(dateTime);
  }
}
