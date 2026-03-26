import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/api_config.dart';
import '../core/exceptions/api_exception.dart';
import '../models/menu_model.dart';

class MenuService {
  /// Get menu items for a specific cart (cartId)
  /// This fetches the menu from the cart's menu items
  /// Uses direct HTTP call to handle array responses from backend
  Future<List<MenuCategory>> getMenu({String? cartId}) async {
    try {
      // Build URL with query params
      Uri uri = Uri.parse('${ApiConfig.baseUrl}/menu/public');
      if (cartId != null) {
        uri = uri.replace(queryParameters: {'cartId': cartId});
      }

      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      // Make request
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .get(uri, headers: headers)
          .timeout(ApiConfig.receiveTimeout);

      // Handle response
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Backend returns array directly
        final decoded = jsonDecode(response.body);
        
        if (decoded is List) {
          return decoded
              .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
              .toList();
        } else if (decoded is Map<String, dynamic>) {
          // Check if it's an error response
          if (decoded.containsKey('message')) {
            throw ApiException(
              message: decoded['message'] ?? 'Failed to get menu',
              statusCode: response.statusCode,
            );
          }
          // If it's a map but not an error, try to extract data
          if (decoded.containsKey('data') && decoded['data'] is List) {
            return (decoded['data'] as List)
                .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
        
        // Return empty list if no valid data
        return [];
      } else {
        // Handle error response
        Map<String, dynamic>? errorJson;
        try {
          errorJson = jsonDecode(response.body) as Map<String, dynamic>?;
        } catch (_) {}
        
        final message = errorJson?['message'] ?? 
            'Failed to get menu (${response.statusCode})';
        throw ApiException(
          message: message,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      if (e is http.ClientException || 
          e.toString().contains('SocketException') ||
          e.toString().contains('TimeoutException')) {
        throw ApiException.networkError(
          'Cannot connect to server. Please check your connection.',
        );
      }
      throw ApiException(message: 'Failed to get menu: ${e.toString()}');
    }
  }
}

