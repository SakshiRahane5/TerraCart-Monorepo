import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../exceptions/api_exception.dart';
import 'cache_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;
  bool get _isLoopbackOrigin {
    final host = Uri.tryParse(ApiConfig.origin)?.host.toLowerCase();
    return host == '127.0.0.1' || host == 'localhost';
  }

  String get _loopbackOriginHint {
    if (!_isLoopbackOrigin) {
      return '';
    }
    return '\n4. API_ORIGIN uses 127.0.0.1, so enable USB reverse before debug run: scripts/enable-terra-admin-usb-local-backend.ps1';
  }

  final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Connection': 'keep-alive', // Enable HTTP keep-alive
  };

  // Reusable HTTP client with connection pooling
  final http.Client _httpClient = http.Client();

  // Dispose HTTP client when done
  void dispose() {
    _httpClient.close();
  }

  // Initialize token from storage
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token');
      if (_token != null) {
        _headers['Authorization'] = 'Bearer $_token';
      }
    } catch (e) {
      _token = null;
      _headers.remove('Authorization');
      debugPrint('[API INIT ERROR] Failed to load auth token: $e');
    }
  }

  // Set authentication token
  Future<void> setToken(String? token) async {
    _token = token;
    if (token != null) {
      _headers['Authorization'] = 'Bearer $token';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
    } else {
      _headers.remove('Authorization');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    }
  }

  // Get current token
  String? get token => _token;

  // GET request with optional caching
  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? queryParams,
    bool useCache = false,
    Duration? cacheTtl,
  }) async {
    try {
      // Check cache first if enabled
      if (useCache) {
        final cacheKey = CacheService.getCacheKey(endpoint, queryParams);
        final cached = CacheService().get<Map<String, dynamic>>(cacheKey);
        if (cached != null) {
          return cached;
        }
      }

      final response = await _sendWithLoopbackFallback(
        endpoint: endpoint,
        queryParams: queryParams,
        request: (uri) => _httpClient
            .get(uri, headers: _headers)
            .timeout(ApiConfig.receiveTimeout),
      );

      final result = _handleResponse(response);

      // Cache result if enabled
      if (useCache) {
        final cacheKey = CacheService.getCacheKey(endpoint, queryParams);
        CacheService().set(cacheKey, result, ttl: cacheTtl);
      }

      return result;
    } catch (e) {
      if (e is TimeoutException) {
        throw ApiException.networkError(
          'Request timeout. Please check your connection and ensure the backend server is running at ${ApiConfig.baseUrl}',
        );
      } else if (e is http.ClientException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable') ||
          e.toString().contains('No route to host')) {
        throw ApiException.networkError(
          'Cannot connect to server (host unreachable). Please check:\n1. Backend server is running\n2. API URL is correct: ${ApiConfig.baseUrl}\n3. Your device/emulator can reach the server${_loopbackOriginHint}',
        );
      }
      rethrow;
    }
  }

  // POST request
  Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? customHeaders,
    bool includeAuth = true,
  }) async {
    try {
      // Merge custom headers with default headers
      final headers = {..._headers, ...?customHeaders};
      if (!includeAuth) {
        headers.remove('Authorization');
      }
      final response = await _sendWithLoopbackFallback(
        endpoint: endpoint,
        request: (uri) => _httpClient
            .post(
              uri,
              headers: headers,
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(ApiConfig.receiveTimeout),
      );

      return _handleResponse(response);
    } catch (e) {
      // Log detailed error for debugging
      debugPrint('[API POST ERROR] Type: ${e.runtimeType}');
      debugPrint('[API POST ERROR] Message: ${e.toString()}');
      debugPrint(
        '[API POST ERROR] Attempted URL: ${ApiConfig.baseUrl}$endpoint',
      );

      if (e is TimeoutException) {
        throw ApiException.networkError(
          'Request timeout. Please check your connection and ensure the backend server is running at ${ApiConfig.baseUrl}',
        );
      } else if (e is http.ClientException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable') ||
          e.toString().contains('No route to host')) {
        throw ApiException.networkError(
          'Cannot connect to server (host unreachable). Please check:\n1. Backend server is running\n2. API URL is correct: ${ApiConfig.baseUrl}\n3. Your device/emulator can reach the server\n4. Windows Firewall allows port 5001 (see FIX_FIREWALL_NOW.md)${_isLoopbackOrigin ? '\n5. API_ORIGIN uses 127.0.0.1, so enable USB reverse before debug run: scripts/enable-terra-admin-usb-local-backend.ps1' : ''}',
        );
      }
      rethrow;
    }
  }

  // PATCH request
  Future<Map<String, dynamic>> patch(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _sendWithLoopbackFallback(
        endpoint: endpoint,
        request: (uri) => _httpClient
            .patch(
              uri,
              headers: _headers,
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(ApiConfig.receiveTimeout),
      );

      return _handleResponse(response);
    } catch (e) {
      if (e is TimeoutException) {
        throw ApiException.networkError(
          'Request timeout. Please check your connection and ensure the backend server is running.',
        );
      } else if (e is http.ClientException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('No route to host')) {
        throw ApiException.networkError(
          'Cannot connect to server. Please check your connection and ensure the backend server is running at ${ApiConfig.baseUrl}${_loopbackOriginHint}',
        );
      }
      rethrow;
    }
  }

  // PUT request
  Future<Map<String, dynamic>> put(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _sendWithLoopbackFallback(
        endpoint: endpoint,
        request: (uri) => _httpClient
            .put(
              uri,
              headers: _headers,
              body: body != null ? jsonEncode(body) : null,
            )
            .timeout(ApiConfig.receiveTimeout),
      );

      return _handleResponse(response);
    } catch (e) {
      if (e is TimeoutException) {
        throw ApiException.networkError(
          'Request timeout. Please check your connection and ensure the backend server is running.',
        );
      } else if (e is http.ClientException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('No route to host')) {
        throw ApiException.networkError(
          'Cannot connect to server. Please check your connection and ensure the backend server is running at ${ApiConfig.baseUrl}${_loopbackOriginHint}',
        );
      }
      rethrow;
    }
  }

  // DELETE request
  Future<Map<String, dynamic>> delete(String endpoint) async {
    try {
      final response = await _sendWithLoopbackFallback(
        endpoint: endpoint,
        request: (uri) => _httpClient
            .delete(uri, headers: _headers)
            .timeout(ApiConfig.receiveTimeout),
      );

      return _handleResponse(response);
    } catch (e) {
      if (e is TimeoutException) {
        throw ApiException.networkError(
          'Request timeout. Please check your connection and ensure the backend server is running.',
        );
      } else if (e is http.ClientException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('No route to host')) {
        throw ApiException.networkError(
          'Cannot connect to server. Please check your connection and ensure the backend server is running at ${ApiConfig.baseUrl}${_loopbackOriginHint}',
        );
      }
      rethrow;
    }
  }

  bool get _canTryAndroidLoopbackFallback =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      ApiConfig.isLoopbackOrigin;

  bool _isLikelyConnectionFailure(Object error) {
    if (error is TimeoutException) return true;
    if (error is http.ClientException) return true;

    final text = error.toString();
    return text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection refused') ||
        text.contains('Network is unreachable') ||
        text.contains('No route to host');
  }

  Uri _buildUri(
    String baseUrl,
    String endpoint, {
    Map<String, String>? queryParams,
  }) {
    var uri = Uri.parse('$baseUrl$endpoint');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }
    return uri;
  }

  Future<http.Response> _sendWithLoopbackFallback({
    required String endpoint,
    Map<String, String>? queryParams,
    required Future<http.Response> Function(Uri uri) request,
  }) async {
    final primaryUri =
        _buildUri(ApiConfig.baseUrl, endpoint, queryParams: queryParams);

    try {
      return await request(primaryUri);
    } catch (primaryError) {
      if (!_canTryAndroidLoopbackFallback ||
          !_isLikelyConnectionFailure(primaryError)) {
        rethrow;
      }

      Object? lastError;
      final fallbackBaseUrls = ApiConfig.localOriginFallbacks
          .map((origin) => '$origin/api')
          .toList(growable: false);

      for (final fallbackBaseUrl in fallbackBaseUrls) {
        final fallbackUri = _buildUri(
          fallbackBaseUrl,
          endpoint,
          queryParams: queryParams,
        );
        try {
          debugPrint(
            '[API FALLBACK] Primary $primaryUri failed, retrying $fallbackUri',
          );
          return await request(fallbackUri);
        } catch (fallbackError) {
          lastError = fallbackError;
        }
      }

      if (lastError != null) {
        throw lastError;
      }
      rethrow;
    }
  }

  // Handle HTTP response
  Map<String, dynamic> _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    Map<String, dynamic>? jsonResponse;

    try {
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          // Normal object response
          jsonResponse = decoded;
        } else if (decoded is List) {
          // Some backend endpoints return a bare array (e.g. inventory, tables, etc.)
          // Wrap it in a standard envelope so callers can always use response['data']
          jsonResponse = {
            'success': true,
            'data': decoded,
          };
        } else {
          // Fallback: store raw decoded value
          jsonResponse = {
            'data': decoded,
          };
        }
      }
    } catch (e) {
      // If response is not JSON, create a simple response
      jsonResponse = {'message': response.body};
    }

    if (statusCode >= 200 && statusCode < 300) {
      // Always ensure a success flag for happy-path responses
      return jsonResponse != null
          ? {
              'success': jsonResponse['success'] ?? true,
              ...jsonResponse,
            }
          : {
              'success': true,
            };
    } else if (statusCode == 401) {
      // Clear token on unauthorized
      setToken(null);
      final message = jsonResponse?['message'] ?? 'Unauthorized access';
      throw ApiException(message: message, statusCode: 401);
    } else if (statusCode == 403) {
      final message = jsonResponse?['message'] ?? 'Access forbidden';
      throw ApiException(message: message, statusCode: 403);
    } else if (statusCode == 404) {
      // Use the actual error message from backend if available
      final message = jsonResponse?['message'] ?? 'Resource not found';
      throw ApiException(message: message, statusCode: 404);
    } else if (statusCode >= 500) {
      throw ApiException.serverError();
    } else {
      // Handle other errors
      final message = jsonResponse?['message'] ?? 'An error occurred';
      throw ApiException.fromResponse({
        'message': message,
        'statusCode': statusCode,
        'code': jsonResponse?['code'],
        'data': jsonResponse,
      });
    }
  }
}
