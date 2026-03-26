import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';

class ScheduleService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> getMySchedule() async {
    try {
      final response = await _api.get('/employee-schedule/my-schedule');

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
        return Map<String, dynamic>.from(data);
      }
      if (response['weeklySchedule'] != null) {
        return Map<String, dynamic>.from(response);
      }

      throw ApiException(message: 'Failed to get schedule');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get schedule: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> updateMySchedule({
    required String employeeId,
    required List<Map<String, dynamic>> weeklySchedule,
  }) async {
    try {
      final response = await _api.post(
        '/employee-schedule',
        body: {
          'employeeId': employeeId,
          'weeklySchedule': weeklySchedule,
        },
      );

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
        return Map<String, dynamic>.from(data);
      }
      if (response['weeklySchedule'] != null) {
        return Map<String, dynamic>.from(response);
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to update schedule');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to update schedule: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getEmployeeSchedule(String employeeId) async {
    try {
      final response =
          await _api.get('/employee-schedule/employee/$employeeId');

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
        return Map<String, dynamic>.from(data);
      }
      if (response['weeklySchedule'] != null) {
        return Map<String, dynamic>.from(response);
      }

      throw ApiException(message: 'Failed to get employee schedule');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to get employee schedule: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> updateTodayState({
    required String employeeId,
    required String todayState,
  }) async {
    try {
      final response = await _api.put(
        '/employee-schedule/employee/$employeeId/today-state',
        body: {'todayState': todayState},
      );

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
        return Map<String, dynamic>.from(data);
      }
      if (response['employeeId'] != null) {
        return Map<String, dynamic>.from(response);
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to update today state');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to update today state: ${e.toString()}');
    }
  }
}
