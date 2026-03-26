import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/services/cache_service.dart';
import '../core/exceptions/api_exception.dart';

class AttendanceService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> checkIn({
    String? employeeId,
    String? location,
    String? notes,
  }) async {
    try {
      final response = await _api.post(
        ApiConfig.checkIn,
        body: {
          if (employeeId != null) 'employeeId': employeeId,
          if (location != null) 'location': location,
          if (notes != null) 'notes': notes,
        },
      );

      // Backend returns {message, attendance}, {alreadyCheckedIn: true, attendance}, or {success, data}
      if (response['attendance'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['attendance'] as Map<String, dynamic>;
      }
      if (response['success'] == true && response['data'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['data'] as Map<String, dynamic>;
      }
      if (response['alreadyCheckedIn'] == true && response['attendance'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['attendance'] as Map<String, dynamic>;
      }

      throw ApiException(message: response['message'] ?? 'Check-in failed');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Check-in failed: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> checkOut({
    String? employeeId,
    String? location,
    String? notes,
    bool managerOverride = false,
    String? managerOverrideReason,
  }) async {
    try {
      final response = await _api.post(
        ApiConfig.checkOut,
        body: {
          if (employeeId != null) 'employeeId': employeeId,
          if (location != null) 'location': location,
          if (notes != null) 'notes': notes,
          if (managerOverride) 'managerOverride': true,
          if (managerOverrideReason != null && managerOverrideReason.isNotEmpty)
            'managerOverrideReason': managerOverrideReason,
        },
      );

      // Backend returns {message, attendance} or {success, data}
      if (response['attendance'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['attendance'] as Map<String, dynamic>;
      }
      if (response['success'] == true && response['data'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['data'] as Map<String, dynamic>;
      }

      throw ApiException(message: response['message'] ?? 'Check-out failed');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Check-out failed: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getTodayAttendance(
      {bool useCache = false}) async {
    try {
      // Always fetch fresh attendance for reliable check-in/check-out visibility.
      CacheService().remove(CacheService.todayAttendance);

      final dynamic response = await _api.get(
        ApiConfig.todayAttendance,
        useCache: false,
      );

      if (response is List) {
        return response
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      if (response is Map && response['success'] == true) {
        final data = response['data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }

      if (response is Map && response['data'] is List) {
        return (response['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      throw ApiException(message: 'Failed to get today\'s attendance');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get attendance: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getPastAttendance() async {
    try {
      final response = await _api.get(ApiConfig.pastAttendance);

      if (response['success'] == true) {
        return List<Map<String, dynamic>>.from(response['data'] ?? []);
      }

      throw ApiException(message: 'Failed to get past attendance');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to get past attendance: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getAttendanceStats() async {
    try {
      final response = await _api.get(ApiConfig.attendanceStats);

      // Backend returns {success: true, data: {...}} or direct stats object
      if (response['success'] == true && response['data'] != null) {
        return response['data'] as Map<String, dynamic>;
      }

      // Fallback: if response is already the stats object (backward compatibility)
      if (response['totalDays'] != null || response['workingDays'] != null) {
        return response;
      }

      throw ApiException(message: 'Failed to get attendance stats');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get stats: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> startBreak(String attendanceId) async {
    try {
      final response = await _api.patch(ApiConfig.startBreak(attendanceId));

      // Backend returns {message, attendance} or {success, data}
      if (response['attendance'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['attendance'] as Map<String, dynamic>;
      }
      if (response['success'] == true && response['data'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['data'] as Map<String, dynamic>;
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to start break');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to start break: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> endBreak(String attendanceId) async {
    try {
      final response = await _api.patch(ApiConfig.endBreak(attendanceId));

      // Backend returns {message, attendance} or {success, data}
      if (response['attendance'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['attendance'] as Map<String, dynamic>;
      }
      if (response['success'] == true && response['data'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['data'] as Map<String, dynamic>;
      }

      throw ApiException(message: response['message'] ?? 'Failed to end break');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to end break: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getAllAttendance({
    String? employeeId,
    String? startDate,
    String? endDate,
    String? status,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (employeeId != null) queryParams['employeeId'] = employeeId;
      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;
      if (status != null) queryParams['status'] = status;

      final response = await _api.get(
        ApiConfig.attendance,
        queryParams: queryParams.isEmpty ? null : queryParams,
      );

      if (response['success'] == true) {
        final data = response['data'];
        if (data is List) {
          return data.map((e) {
            if (e is Map) {
              return Map<String, dynamic>.from(e);
            }
            return <String, dynamic>{};
          }).toList();
        }
        if (data is Map) {
          // If data is a single object, wrap it in a list
          return [Map<String, dynamic>.from(data)];
        }
        return [];
      }
      if (response is List) {
        return (response as List).map((e) {
          if (e is Map) {
            return Map<String, dynamic>.from(e);
          }
          return <String, dynamic>{};
        }).toList();
      }

      throw ApiException(message: 'Failed to get attendance records');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get attendance: ${e.toString()}');
    }
  }

  Future<void> deleteAttendance(String attendanceId) async {
    try {
      await _api.delete(ApiConfig.deleteAttendance(attendanceId));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to delete attendance: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> updateAttendanceStatus(String attendanceId,
      {String? status, String? notes}) async {
    try {
      final response = await _api.put(
        ApiConfig.updateAttendanceStatus(attendanceId),
        body: {
          if (status != null) 'status': status,
          if (notes != null) 'notes': notes,
        },
      );
      if (response['attendance'] != null) {
        return response['attendance'] as Map<String, dynamic>;
      }
      if (response['success'] == true && response['data'] != null) {
        return response['data'] as Map<String, dynamic>;
      }
      if (response['_id'] != null) {
        return Map<String, dynamic>.from(response);
      }
      throw ApiException(
          message: response['message'] ?? 'Failed to update attendance');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to update attendance: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> checkout(String attendanceId,
      {String? location,
      String? notes,
      bool managerOverride = false,
      String? managerOverrideReason}) async {
    try {
      final response = await _api.patch(
        ApiConfig.checkout(attendanceId),
        body: {
          if (location != null) 'location': location,
          if (notes != null) 'notes': notes,
          if (managerOverride) 'managerOverride': true,
          if (managerOverrideReason != null && managerOverrideReason.isNotEmpty)
            'managerOverrideReason': managerOverrideReason,
        },
      );

      // Backend returns {message, attendance} or {success, data}
      if (response['attendance'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['attendance'] as Map<String, dynamic>;
      }
      if (response['success'] == true && response['data'] != null) {
        CacheService().remove(CacheService.todayAttendance);
        return response['data'] as Map<String, dynamic>;
      }

      throw ApiException(message: response['message'] ?? 'Failed to checkout');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to checkout: ${e.toString()}');
    }
  }
}
