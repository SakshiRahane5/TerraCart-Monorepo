import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';
import '../core/constants/preference_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KotService {
  final ApiService _api = ApiService();
  static const String _cookKotClearBeforeKey = 'cook_kot_clear_before_ms';

  Future<String> _cookKotClearKey() async {
    final cartId = await _getCurrentCartId();
    if (cartId == null || cartId.isEmpty) return _cookKotClearBeforeKey;
    return '${_cookKotClearBeforeKey}_$cartId';
  }

  String _statusKey(String status) =>
      status.toLowerCase().trim().replaceAll('_', ' ');
  static const Set<String> _terminalStatuses = {
    'paid',
    'cancelled',
    'returned',
    'rejected',
    'closed',
    'exit',
    'completed',
    'finalized',
    'served',
  };
  static const Set<String> _pendingWorkflowStatuses = {
    'new',
    'pending',
    'confirmed',
    'accept',
    'accepted',
  };
  static const Set<String> _preparingWorkflowStatuses = {
    'preparing',
    'being prepared',
    'beingprepared',
  };
  static const Set<String> _readyWorkflowStatuses = {
    'ready',
  };

  Future<String?> _getCurrentCartId() async {
    final prefs = await SharedPreferences.getInstance();
    final cartId = prefs.getString(PreferenceKeys.userCartId)?.trim();
    if (cartId == null || cartId.isEmpty) {
      return null;
    }
    return cartId;
  }

  // ignore: unused_element
  Future<String> _getCurrentUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('userRole') ?? '').trim().toLowerCase();
  }

  // ignore: unused_element
  bool _isCookOrManagerRole(String role) => role == 'cook' || role == 'manager';

  // ignore: unused_element
  bool _hasAssignedStaff(Map<String, dynamic> kot) {
    final isAssigned = kot['isAssigned'] == true;
    if (isAssigned) return true;
    final acceptedByRaw = kot['acceptedBy'];
    if (acceptedByRaw is! Map) return false;
    final acceptedBy = Map<String, dynamic>.from(acceptedByRaw);
    final employeeId = acceptedBy['employeeId']?.toString().trim() ?? '';
    final employeeName = acceptedBy['employeeName']?.toString().trim() ?? '';
    return employeeId.isNotEmpty || employeeName.isNotEmpty;
  }

  String? _resolveWorkflowStatus(String rawStatus) {
    final status = _statusKey(rawStatus);
    if (_terminalStatuses.contains(status)) {
      return null;
    }
    if (_pendingWorkflowStatuses.contains(status)) {
      return 'pending';
    }
    if (_preparingWorkflowStatuses.contains(status)) {
      return 'preparing';
    }
    if (_readyWorkflowStatuses.contains(status)) {
      return 'ready';
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getKOTs({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
      };

      final response = await _api.get(ApiConfig.kot, queryParams: queryParams);

      if (response['success'] == true) {
        final kots = List<Map<String, dynamic>>.from(response['data'] ?? []);
        final currentCartId = await _getCurrentCartId();
        // If local cart binding is unavailable, trust backend scoping.
        if (currentCartId == null || currentCartId.isEmpty) {
          return kots;
        }
        return kots.where((kot) {
          final kotCartId =
              (kot['cartId'] ?? kot['cafeId'] ?? '').toString().trim();
          return kotCartId.isNotEmpty && kotCartId == currentCartId;
        }).toList();
      }

      throw ApiException(message: 'Failed to get KOTs');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get KOTs: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getPendingKOTs() async {
    try {
      // Use the main KOT endpoint to get all KOTs (includes both takeaway and dine-in orders)
      // The backend filters by cartId automatically, so we get all relevant KOTs
      final response = await _api.get(ApiConfig.kot);

      // Handle both response formats: { success: true, data: [...] } or direct array
      List<Map<String, dynamic>> kots = [];
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          kots = List<Map<String, dynamic>>.from(data);
        }
      } else if (response.containsKey('data')) {
        final data = response['data'];
        if (data is List) {
          kots = List<Map<String, dynamic>>.from(data);
        }
      }

      // Defense in depth: keep only KOTs for current user's cart.
      final currentCartId = await _getCurrentCartId();
      if (currentCartId != null && currentCartId.isNotEmpty) {
        kots = kots.where((kot) {
          final kotCartId =
              (kot['cartId'] ?? kot['cafeId'] ?? '').toString().trim();
          if (kotCartId.isEmpty) {
            // Fail closed to avoid cross-cart leakage when cart metadata is missing.
            return false;
          }
          return kotCartId == currentCartId;
        }).toList();
      }

      /*
      final role = await _getCurrentUserRole();
      final requireAccepted = _isCookOrManagerRole(role);
      */
      // Accept-order assignment flow disabled: show pending KOTs without assignment gating.
      // final requireAccepted = false;

      final normalizedKots = <Map<String, dynamic>>[];
      for (final kot in kots) {
        final rawStatus =
            (kot['status'] ?? kot['orderStatus'] ?? '').toString();
        final workflowStatus = _resolveWorkflowStatus(rawStatus);
        if (workflowStatus == null) {
          continue;
        }
        /*
        final hasAssignmentMetadata =
            kot.containsKey('isAssigned') || kot.containsKey('acceptedBy');
        if (requireAccepted &&
            hasAssignmentMetadata &&
            !_hasAssignedStaff(kot)) {
          continue;
        }
        */

        final normalizedKot = Map<String, dynamic>.from(kot);
        normalizedKot['rawOrderStatus'] = rawStatus;
        normalizedKot['status'] = workflowStatus;
        normalizedKot['orderStatus'] = workflowStatus;
        normalizedKots.add(normalizedKot);
      }

      return normalizedKots;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get KOTs: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> updateKOTStatus(String id, String status) async {
    try {
      final response = await _api.patch(
        ApiConfig.updateKOTStatus(id),
        body: {'status': status},
      );

      if (response['success'] == true) {
        return response['data'] ?? {};
      }

      throw ApiException(message: 'Failed to update KOT status');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to update status: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getKOTStats() async {
    try {
      final response = await _api.get(ApiConfig.kotStats);

      if (response['success'] == true) {
        return response['data'] ?? {};
      }

      throw ApiException(message: 'Failed to get KOT stats');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get stats: ${e.toString()}');
    }
  }

  Future<void> clearCookKotHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _cookKotClearKey();
    await prefs.setInt(
      key,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<int?> getCookKotClearBeforeMs() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _cookKotClearKey();
    return prefs.getInt(key);
  }
}
