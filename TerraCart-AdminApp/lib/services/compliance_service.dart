import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';

class ComplianceService {
  final ApiService _apiService = ApiService();

  /// Get all compliance documents
  Future<List<Map<String, dynamic>>> getAllCompliance({
    String? type,
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (type != null) queryParams['type'] = type;
      if (status != null) queryParams['status'] = status;

      final response = await _apiService.get(
        ApiConfig.compliance,
        queryParams: queryParams,
      );

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
        return [];
      }
      return [];
    } catch (e) {
      throw ApiException(
        message: e.toString(),
      );
    }
  }

  /// Get expiring compliance documents
  Future<List<Map<String, dynamic>>> getExpiringCompliance({
    int days = 30,
  }) async {
    try {
      final response = await _apiService.get(
        ApiConfig.expiringCompliance,
        queryParams: {'days': days.toString()},
      );

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
        return [];
      }
      return [];
    } catch (e) {
      throw ApiException(
        message: e.toString(),
      );
    }
  }

  /// Get compliance statistics
  Future<Map<String, dynamic>> getComplianceStats() async {
    try {
      final response = await _apiService.get(ApiConfig.complianceStats);

      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data']);
      }
      return {
        'total': 0,
        'valid': 0,
        'expiringSoon': 0,
        'expired': 0,
        'renewalPending': 0,
      };
    } catch (e) {
      throw ApiException(
        message: e.toString(),
      );
    }
  }

  /// Get compliance document by ID
  Future<Map<String, dynamic>> getComplianceById(String id) async {
    try {
      final response = await _apiService.get(ApiConfig.complianceById(id));

      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data']);
      }
      throw ApiException(
        message: 'Compliance document not found',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: e.toString(),
      );
    }
  }
}
