import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';

class EmployeeService {
  final ApiService _api = ApiService();

  /// Get all employees under the manager's cart/kiosk/cafe
  /// The backend automatically filters by the manager's cartId
  Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final response = await _api.get(ApiConfig.employees);
      
      // Backend now returns: { success: true, data: [...] }
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
        return [];
      }
      
      // Fallback: check if response is directly a list (legacy format)
      if (response is List) {
        return (response as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      // If no data, return empty list (user might not have a cartId)
      if (response['success'] == true) {
        return [];
      }

      throw ApiException(message: response['message'] ?? 'Failed to get employees');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get employees: ${e.toString()}');
    }
  }

  /// Get employee by ID
  Future<Map<String, dynamic>> getEmployeeById(String employeeId) async {
    try {
      final response = await _api.get(ApiConfig.employeeById(employeeId));
      
      if (response['success'] == true) {
        return response['data'] ?? response;
      }

      throw ApiException(message: response['message'] ?? 'Failed to get employee');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get employee: ${e.toString()}');
    }
  }
}

