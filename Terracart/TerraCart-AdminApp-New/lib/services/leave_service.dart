import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';

class LeaveService {
  final ApiService _api = ApiService();

  String _toIsoDate(DateTime value) {
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>> applyLeave({
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? employeeId,
  }) async {
    try {
      final payload = {
        'startDate': _toIsoDate(startDate),
        'endDate': _toIsoDate(endDate),
        'reason': reason.trim(),
        if (employeeId != null && employeeId.isNotEmpty) 'employeeId': employeeId,
      };

      final response = await _api.post('/leave-requests', body: payload);
      final data = response['data'];
      if (response['success'] == true && data is Map) {
        return Map<String, dynamic>.from(data);
      }
      if (response is Map<String, dynamic> && response['_id'] != null) {
        return response;
      }
      throw ApiException(message: response['message'] ?? 'Failed to apply leave');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to apply leave: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getMyLeaveRequests() async {
    try {
      final response = await _api.get('/leave-requests/my');
      final data = response['data'] ?? response;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
      }
      return const <Map<String, dynamic>>[];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Failed to load leave requests: ${e.toString()}',
      );
    }
  }
}
