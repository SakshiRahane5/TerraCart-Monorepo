import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

import '../core/config/api_config.dart';
import '../core/services/api_service.dart';

class AppUpdateDecision {
  final bool updateRequired;
  final bool updateAvailable;
  final bool forceUpdate;
  final String currentVersion;
  final String latestVersion;
  final String minimumSupportedVersion;
  final String releaseNotes;
  final String apkUrl;
  final String updateUrl;
  final String sha256;

  const AppUpdateDecision({
    required this.updateRequired,
    required this.updateAvailable,
    required this.forceUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.minimumSupportedVersion,
    required this.releaseNotes,
    required this.apkUrl,
    required this.updateUrl,
    required this.sha256,
  });

  bool get shouldPrompt => updateRequired || updateAvailable;

  String? get preferredUpdateUrl {
    final apk = apkUrl.trim();
    if (apk.isNotEmpty) return apk;

    final fallback = updateUrl.trim();
    if (fallback.isNotEmpty) return fallback;

    return null;
  }
}

class AppUpdateService {
  final ApiService _api = ApiService();

  Future<AppUpdateDecision?> checkForMandatoryUpdate({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      return await _checkForMandatoryUpdate().timeout(
        timeout,
        onTimeout: () => null,
      );
    } catch (_) {
      // Fail open: app should continue normally if update check cannot complete.
      return null;
    }
  }

  Future<AppUpdateDecision?> _checkForMandatoryUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();
    if (currentVersion.isEmpty) return null;

    final response = await _api.get(ApiConfig.appVersion);
    final rawData = _extractPayload(response);
    if (rawData == null) return null;

    final latestVersion = _readString(rawData['latestVersion']);
    if (latestVersion.isEmpty) return null;

    final minimumSupportedVersion = _readString(
      rawData['minimumSupportedVersion'],
      fallback: latestVersion,
    );
    final forceUpdate = _toBool(rawData['forceUpdate']);
    final releaseNotes = _readString(rawData['releaseNotes']);
    final apkUrl = _readString(rawData['apkUrl']);
    final updateUrl = _readString(rawData['updateUrl']);
    final sha256 = _readString(rawData['sha256']);

    final belowMinimum =
        compareVersions(currentVersion, minimumSupportedVersion) < 0;
    final updateAvailable = compareVersions(currentVersion, latestVersion) < 0;
    final updateRequired = forceUpdate || belowMinimum;

    return AppUpdateDecision(
      updateRequired: updateRequired,
      updateAvailable: updateAvailable,
      forceUpdate: forceUpdate,
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
      releaseNotes: releaseNotes,
      apkUrl: apkUrl,
      updateUrl: updateUrl,
      sha256: sha256,
    );
  }

  Map<String, dynamic>? _extractPayload(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (response.containsKey('latestVersion')) {
      return Map<String, dynamic>.from(response);
    }
    return null;
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'on';
    }
    return false;
  }

  String _readString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static int compareVersions(String current, String target) {
    final currentParts = _extractNumericVersionParts(current);
    final targetParts = _extractNumericVersionParts(target);
    final maxLen =
        currentParts.length > targetParts.length ? currentParts.length : targetParts.length;

    for (var i = 0; i < maxLen; i++) {
      final left = i < currentParts.length ? currentParts[i] : 0;
      final right = i < targetParts.length ? targetParts[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }

  static List<int> _extractNumericVersionParts(String version) {
    final normalized =
        version.trim().split('+').first.split('-').first;
    if (normalized.isEmpty) return const [0];

    final parts = normalized.split('.');
    final result = <int>[];
    final pattern = RegExp(r'\d+');
    for (final part in parts) {
      final match = pattern.firstMatch(part);
      result.add(int.tryParse(match?.group(0) ?? '0') ?? 0);
    }
    return result;
  }
}
