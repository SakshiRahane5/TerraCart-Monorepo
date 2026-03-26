import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/api_config.dart';

typedef UpdateDownloadProgress = void Function(
  int downloadedBytes,
  int? totalBytes,
);

class InAppUpdateInstaller {
  final http.Client _client;

  InAppUpdateInstaller({http.Client? client}) : _client = client ?? http.Client();

  Uri _resolveTargetUri(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) {
      throw Exception('Update URL is empty.');
    }

    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      throw Exception('Invalid update URL.');
    }

    if (parsed.hasScheme) return parsed;

    final originUri = Uri.parse(ApiConfig.origin);
    final normalizedPath = value.startsWith('/') ? value : '/$value';
    return originUri.resolve(normalizedPath);
  }

  Future<void> downloadAndOpenInstaller({
    required String url,
    required String version,
    UpdateDownloadProgress? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw Exception('In-app APK installation is supported on Android only.');
    }

    final uri = _resolveTargetUri(url);
    final request = http.Request('GET', uri);
    final response = await _client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to download update (HTTP ${response.statusCode}).',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final safeVersion = version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final apkPath =
        '${tempDir.path}${Platform.pathSeparator}terracart_update_$safeVersion.apk';
    final apkFile = File(apkPath);
    if (apkFile.existsSync()) {
      await apkFile.delete();
    }

    final sink = apkFile.openWrite();
    final contentLength = response.contentLength;
    var received = 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, contentLength);
    }

    await sink.flush();
    await sink.close();
    onProgress?.call(received, contentLength);

    final openResult = await OpenFilex.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );

    if (openResult.type != ResultType.done) {
      final message = openResult.message.toString().trim();
      throw Exception(
        message.isNotEmpty
            ? message
            : 'Could not open Android package installer.',
      );
    }
  }
}
