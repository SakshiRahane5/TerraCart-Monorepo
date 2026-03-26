import 'package:http/http.dart' as http;
import '../core/config/api_config.dart';

class ConnectionTest {
  static List<Uri> _candidateUrisForPath(String path) {
    final primary = Uri.parse('${ApiConfig.origin}$path');
    final all = <Uri>[primary];
    for (final fallbackOrigin in ApiConfig.localOriginFallbacks) {
      all.add(Uri.parse('$fallbackOrigin$path'));
    }

    final unique = <String>{};
    final results = <Uri>[];
    for (final uri in all) {
      final key = uri.toString();
      if (unique.add(key)) {
        results.add(uri);
      }
    }
    return results;
  }

  static String get _loopbackDebugHint {
    final host = Uri.tryParse(ApiConfig.origin)?.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost') {
      return '\nHint: API_ORIGIN is 127.0.0.1. For physical Android device, run scripts/enable-terra-admin-usb-local-backend.ps1 before debugging. For Android emulator, 10.0.2.2 is used as automatic fallback.';
    }
    return '';
  }

  /// Test if the backend server is reachable
  static Future<Map<String, dynamic>> testConnection() async {
    Object? lastError;
    try {
      final candidates = _candidateUrisForPath('/health');

      for (final uri in candidates) {
        try {
          print('[CONNECTION TEST] Testing: $uri');

          final response =
              await http.get(uri).timeout(const Duration(seconds: 15));

          print('[CONNECTION TEST] Status: ${response.statusCode}');
          print('[CONNECTION TEST] Body: ${response.body}');

          if (response.statusCode == 200) {
            return {
              'success': true,
              'message': 'Server is reachable',
              'statusCode': response.statusCode,
              'url': uri.toString(),
            };
          } else {
            return {
              'success': false,
              'message': 'Server responded with status ${response.statusCode}',
              'statusCode': response.statusCode,
              'url': uri.toString(),
            };
          }
        } catch (e) {
          lastError = e;
          print('[CONNECTION TEST] Error: $e');
        }
      }
    } catch (e) {
      lastError = e;
    }

    return {
      'success': false,
      'message':
          'Cannot reach server: ${lastError?.toString() ?? 'Unknown error'}${_loopbackDebugHint}',
      'error': lastError?.toString(),
    };
  }

  static List<Uri> _candidateLoginUris() {
    final primary = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.login}');
    final all = <Uri>[primary];
    for (final fallbackOrigin in ApiConfig.localOriginFallbacks) {
      all.add(Uri.parse('$fallbackOrigin/api${ApiConfig.login}'));
    }

    final unique = <String>{};
    final results = <Uri>[];
    for (final uri in all) {
      final key = uri.toString();
      if (unique.add(key)) {
        results.add(uri);
      }
    }
    return results;
  }

  /// Test login endpoint specifically
  static Future<Map<String, dynamic>> testLoginEndpoint() async {
    Object? lastError;
    try {
      final candidates = _candidateLoginUris();

      for (final uri in candidates) {
        try {
          print('[LOGIN TEST] Testing endpoint: $uri');

          // Test with invalid credentials to see if endpoint is reachable
          final response = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'x-app-login': 'mobile',
                },
                body: '{"email":"test@test.com","password":"test"}',
              )
              .timeout(const Duration(seconds: 15));

          print('[LOGIN TEST] Status: ${response.statusCode}');
          print('[LOGIN TEST] Body: ${response.body}');

          // Even if login fails, if we get a 401/400, the endpoint is reachable
          if (response.statusCode == 401 || response.statusCode == 400) {
            return {
              'success': true,
              'message': 'Login endpoint is reachable',
              'statusCode': response.statusCode,
              'url': uri.toString(),
            };
          } else if (response.statusCode == 200) {
            return {
              'success': true,
              'message': 'Login endpoint is reachable and working',
              'statusCode': response.statusCode,
              'url': uri.toString(),
            };
          } else {
            return {
              'success': false,
              'message': 'Unexpected status: ${response.statusCode}',
              'statusCode': response.statusCode,
              'url': uri.toString(),
            };
          }
        } catch (e) {
          lastError = e;
          print('[LOGIN TEST] Error: $e');
        }
      }
    } catch (e) {
      lastError = e;
    }

    return {
      'success': false,
      'message':
          'Cannot reach login endpoint: ${lastError?.toString() ?? 'Unknown error'}${_loopbackDebugHint}',
      'error': lastError?.toString(),
    };
  }
}
