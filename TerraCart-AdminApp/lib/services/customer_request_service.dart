import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';

class CustomerRequestService {
  final ApiService _api = ApiService();

  Future<List<Map<String, dynamic>>> getRequests({
    String? status,
    String? tableId,
    int page = 1,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
        if (tableId != null) 'tableId': tableId,
      };

      final response = await _api.get(ApiConfig.customerRequests, queryParams: queryParams);
      
      // ApiService wraps arrays in {success: true, data: []}
      List<Map<String, dynamic>> result = [];
      
      final data = response['data'];
      if (data != null && data is List) {
        for (var item in data) {
          if (item is Map) {
            result.add(Map<String, dynamic>.from(item));
          }
        }
        return result;
      }

      throw ApiException(message: 'Failed to get requests');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get requests: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    try {
      final response = await _api.get(ApiConfig.pendingRequests);
      
      // ApiService wraps arrays in {success: true, data: []}
      List<Map<String, dynamic>> result = [];
      
      final data = response['data'];
      if (data != null && data is List) {
        for (var item in data) {
          if (item is Map) {
            result.add(Map<String, dynamic>.from(item));
          }
        }
        return result;
      }

      throw ApiException(message: 'Failed to get pending requests');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get requests: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> requestData) async {
    try {
      final response = await _api.post(ApiConfig.customerRequests, body: requestData);
      
      if (response['success'] == true) {
        return response['data'] ?? {};
      }

      throw ApiException(message: response['message'] ?? 'Failed to create request');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to create request: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> acknowledgeRequest(String id) async {
    try {
      // Backend uses POST for acknowledge, not PATCH
      final response = await _api.post(ApiConfig.acknowledgeRequest(id));
      
      // Handle both direct object response and wrapped response
      if (response['data'] != null) {
        return Map<String, dynamic>.from(response['data']);
      } else if (response['success'] == true) {
        return Map<String, dynamic>.from(response['data'] ?? response);
      } else if (response['_id'] != null) {
        // Direct object response
        return Map<String, dynamic>.from(response);
      }

      throw ApiException(message: 'Failed to acknowledge request');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to acknowledge: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> resolveRequest(String id, {String? notes}) async {
    try {
      final body = notes != null ? {'notes': notes} : <String, dynamic>{};
      // Backend uses POST for resolve, not PATCH
      final response = await _api.post(
        ApiConfig.resolveRequest(id),
        body: body,
      );
      
      // Handle both direct object response and wrapped response
      if (response['data'] != null) {
        return Map<String, dynamic>.from(response['data']);
      } else if (response['success'] == true) {
        return Map<String, dynamic>.from(response['data'] ?? response);
      } else if (response['_id'] != null) {
        // Direct object response
        return Map<String, dynamic>.from(response);
      }

      throw ApiException(message: 'Failed to resolve request');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to resolve: ${e.toString()}');
    }
  }
}

