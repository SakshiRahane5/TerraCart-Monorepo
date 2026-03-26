import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';
import '../core/constants/preference_keys.dart';
import '../models/order_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrderService {
  final ApiService _api = ApiService();

  String _buildIdempotencyKey(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$now';
  }

  Future<String?> _getCurrentCartId() async {
    final prefs = await SharedPreferences.getInstance();
    final cartId = prefs.getString(PreferenceKeys.userCartId)?.trim();
    if (cartId == null || cartId.isEmpty) {
      return null;
    }
    return cartId;
  }

  Future<List<OrderModel>> getOrders({
    String? status,
    int page = 1,
    int limit = 500, // Increased default limit to get more orders
    bool includeHistory = false,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
        if (includeHistory) 'includeHistory': 'true',
      };

      final response =
          await _api.get(ApiConfig.orders, queryParams: queryParams);

      if (response['success'] == true || response['success'] == null) {
        final data = response['data'] ?? response;
        if (data is List) {
          final orders = data
              .whereType<Map>()
              .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          final currentCartId = await _getCurrentCartId();
          // If local cart binding is unavailable, trust backend scoping.
          if (currentCartId == null || currentCartId.isEmpty) {
            return orders;
          }
          return orders
              .where((order) => (order.cartId ?? '').trim() == currentCartId)
              .toList();
        }
        return [];
      }

      throw ApiException(message: 'Failed to get orders');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get orders: ${e.toString()}');
    }
  }

  Future<OrderModel> getOrderById(String id) async {
    try {
      final response = await _api.get(ApiConfig.orderById(id));
      final orderData = response['data'] ?? response;

      if ((response['success'] == true || response['success'] == null) &&
          orderData is Map) {
        return OrderModel.fromJson(Map<String, dynamic>.from(orderData));
      }

      throw ApiException(message: 'Failed to get order');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get order: ${e.toString()}');
    }
  }

  Future<void> createOrder(Map<String, dynamic> orderData) async {
    try {
      final payload = Map<String, dynamic>.from(orderData);
      final existingKey = payload['idempotencyKey']?.toString().trim() ?? '';
      if (existingKey.isEmpty) {
        payload['idempotencyKey'] = _buildIdempotencyKey('app-order');
      }

      final response = await _api.post(ApiConfig.orders, body: payload);

      if (response['success'] == true || response['success'] == null) {
        // Order created successfully
        // Don't try to parse response if data is null - order will be loaded via socket/list
        return;
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to create order');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to create order: ${e.toString()}');
    }
  }

  /// Accept takeaway order (first-come-first-serve). Backend: waiter, captain, manager.
  Future<OrderModel> acceptOrder(String id) async {
    try {
      final response = await _api.patch(ApiConfig.acceptOrder(id));
      final orderData = response['data'] ?? response;
      if (response['success'] == true ||
          (orderData is Map &&
              (orderData['_id'] != null || orderData['id'] != null))) {
        return OrderModel.fromJson(Map<String, dynamic>.from(orderData));
      }
      throw ApiException(
          message: response['message'] ?? 'Failed to accept order');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to accept order: ${e.toString()}');
    }
  }

  Future<OrderModel> updateOrderStatus(
    String id,
    String status, {
    String? paymentStatus,
  }) async {
    try {
      final payload = <String, dynamic>{'status': status};
      if (paymentStatus != null && paymentStatus.trim().isNotEmpty) {
        payload['paymentStatus'] = paymentStatus.trim().toUpperCase();
      }
      final response = await _api.patch(
        ApiConfig.updateOrderStatus(id),
        body: payload,
      );

      // Backend returns order directly, API service wraps it with success: true
      // The order data is either in response['data'] or at the top level
      final orderData = response['data'] ?? response;

      // If response has success flag, use data field, otherwise use response itself
      if (response['success'] == true || response['success'] == null) {
        // Check if orderData has order fields (like _id, status, etc.)
        if (orderData is Map &&
            (orderData['_id'] != null || orderData['id'] != null)) {
          return OrderModel.fromJson(Map<String, dynamic>.from(orderData));
        }
        // If data field doesn't have order, try response itself
        if (response['_id'] != null || response['id'] != null) {
          return OrderModel.fromJson(Map<String, dynamic>.from(response));
        }
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to update order status');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to update status: ${e.toString()}');
    }
  }

  Future<OrderModel> addKOT(
    String orderId,
    List<Map<String, dynamic>> items, {
    String? specialInstructions,
  }) async {
    try {
      final body = <String, dynamic>{'items': items};
      body['idempotencyKey'] = _buildIdempotencyKey('app-kot');
      if (specialInstructions != null &&
          specialInstructions.trim().isNotEmpty) {
        body['specialInstructions'] = specialInstructions.trim();
      }
      final response = await _api.post(
        ApiConfig.addKOT(orderId),
        body: body,
      );

      if (response['success'] == true) {
        return OrderModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Failed to add KOT');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to add KOT: ${e.toString()}');
    }
  }

  /// Add items to existing order. Backend: admin, franchise_admin, super_admin only.
  Future<OrderModel> addItemsToOrder(
      String orderId, List<Map<String, dynamic>> items) async {
    try {
      final response = await _api.post(
        ApiConfig.addItemsToOrder(orderId),
        body: {'items': items},
      );
      final orderData = response['data'] ?? response;
      if (response['success'] == true ||
          (orderData is Map &&
              (orderData['_id'] != null || orderData['id'] != null))) {
        return OrderModel.fromJson(Map<String, dynamic>.from(orderData));
      }
      throw ApiException(message: response['message'] ?? 'Failed to add items');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to add items: ${e.toString()}');
    }
  }

  /// Return selected items. Backend: admin, franchise_admin, super_admin only.
  /// itemIds: [{ kotIndex: int, itemIndex: int }, ...]
  Future<OrderModel> returnItems(
      String orderId, List<Map<String, dynamic>> itemIds) async {
    try {
      final response = await _api.patch(
        ApiConfig.returnItems(orderId),
        body: {'itemIds': itemIds},
      );
      final orderData = response['data'] ?? response;
      if (response['success'] == true ||
          (orderData is Map &&
              (orderData['_id'] != null || orderData['id'] != null))) {
        return OrderModel.fromJson(Map<String, dynamic>.from(orderData));
      }
      throw ApiException(
          message: response['message'] ?? 'Failed to return items');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to return items: ${e.toString()}');
    }
  }

  /// Convert DINE_IN order to takeaway. Backend: admin, franchise_admin, super_admin only.
  Future<OrderModel> convertToTakeaway(String orderId,
      {List<Map<String, dynamic>>? itemIds}) async {
    try {
      final response = await _api.patch(
        ApiConfig.convertToTakeaway(orderId),
        body: itemIds != null ? {'itemIds': itemIds} : {},
      );
      final orderData = response['data'] ?? response;
      if (response['success'] == true ||
          (orderData is Map &&
              (orderData['_id'] != null || orderData['id'] != null))) {
        return OrderModel.fromJson(Map<String, dynamic>.from(orderData));
      }
      throw ApiException(message: response['message'] ?? 'Failed to convert');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to convert: ${e.toString()}');
    }
  }

  /// Delete order. Backend: admin, franchise_admin, super_admin only.
  Future<void> deleteOrder(String orderId) async {
    try {
      await _api.delete(ApiConfig.deleteOrder(orderId));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to delete order: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getPendingKotPrintJobs() async {
    try {
      final response = await _api.get(ApiConfig.pendingKotPrintJobs);
      final data = response['pendingKots'];
      if (data is List) {
        return data.whereType<Map>().map((e) {
          return Map<String, dynamic>.from(e);
        }).toList();
      }
      return const <Map<String, dynamic>>[];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Failed to fetch pending KOT print jobs: ${e.toString()}',
      );
    }
  }

  /// Update print status after successful print. Backend: admin, manager, waiter, captain.
  Future<void> updatePrintStatus(
    String orderId, {
    bool? kotPrinted,
    bool? billPrinted,
    int? lastPrintedKotIndex,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (kotPrinted == true) body['kotPrinted'] = true;
      if (billPrinted == true) body['billPrinted'] = true;
      if (lastPrintedKotIndex != null && lastPrintedKotIndex >= 0) {
        body['lastPrintedKotIndex'] = lastPrintedKotIndex;
      }
      if (body.isEmpty) return;
      await _api.patch(ApiConfig.updatePrintStatus(orderId), body: body);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Failed to update print status: ${e.toString()}',
      );
    }
  }

  /// Claim an auto-print job in backend (idempotent).
  /// Returns true only for the first claimant; duplicate claims return false.
  /// For KOT pass type: 'kot', kotIndex, printKey, and deviceId.
  Future<Map<String, dynamic>> claimPrintJob(
    String orderId, {
    required String docType,
    String printerId = 'default',
    int? kotIndex,
    int? kotNumber,
    String? orderVersion,
    String? printKey,
    String? deviceId,
  }) async {
    try {
      // Backend per-KOT claim path requires type=kot + kotIndex + printKey + deviceId.
      // Only send type: 'kot' when we have printKey and deviceId; otherwise backend uses legacy PrintJob path.
      final pk = printKey?.trim() ?? '';
      final devId = deviceId?.trim() ?? '';
      final hasKotLineClaim =
          docType.toUpperCase() == 'KOT' && pk.isNotEmpty && devId.isNotEmpty;
      final body = <String, dynamic>{
        'docType': docType,
        if (hasKotLineClaim) 'type': 'kot',
        'printerId': printerId,
        if (kotIndex != null && kotIndex >= 0) 'kotIndex': kotIndex,
        if (kotNumber != null && kotNumber > 0) 'kotNumber': kotNumber,
        if (orderVersion != null && orderVersion.trim().isNotEmpty)
          'orderVersion': orderVersion.trim(),
        if (printKey != null && printKey.trim().isNotEmpty)
          'printKey': printKey.trim(),
        if (deviceId != null && deviceId.trim().isNotEmpty)
          'deviceId': deviceId.trim(),
      };
      final response = await _api.patch(
        ApiConfig.claimPrintJob(orderId),
        body: body,
      );
      final data = response['data'] ?? response;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return const {'claimed': false};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to claim print job: ${e.toString()}');
    }
  }

  /// Mark an auto-print job as completed/failed in backend.
  /// For KOT pass type: 'kot', kotIndex, deviceId, and status: 'printed' or 'failed'.
  Future<void> completePrintJob(
    String orderId, {
    required String printKey,
    required String docType,
    bool success = true,
    String? errorMessage,
    int? kotIndex,
    String? deviceId,
    String? status,
  }) async {
    try {
      final body = <String, dynamic>{
        'printKey': printKey,
        'docType': docType,
        'success': success,
        if (errorMessage != null && errorMessage.trim().isNotEmpty)
          'errorMessage': errorMessage.trim(),
        if (docType.toUpperCase() == 'KOT') 'type': 'kot',
        if (kotIndex != null && kotIndex >= 0) 'kotIndex': kotIndex,
        if (deviceId != null && deviceId.trim().isNotEmpty)
          'deviceId': deviceId.trim(),
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      };
      await _api.patch(
        ApiConfig.completePrintJob(orderId),
        body: body,
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Failed to complete print job: ${e.toString()}',
      );
    }
  }

  /// Fetch backend-owned compact KOT template (single source of truth).
  Future<Map<String, dynamic>> getKotPrintTemplate(
    String orderId, {
    int? kotIndex,
    String paperWidth = '58mm',
    String printerId = 'kitchen-primary',
  }) async {
    try {
      final query = <String, String>{
        'paperWidth': paperWidth.trim().isEmpty ? '58mm' : paperWidth.trim(),
        'printerId':
            printerId.trim().isEmpty ? 'kitchen-primary' : printerId.trim(),
        if (kotIndex != null && kotIndex >= 0) 'kotIndex': kotIndex.toString(),
      };

      final response = await _api.get(
        ApiConfig.kotPrintTemplate(orderId),
        queryParams: query,
      );
      final data = response['data'] ?? response;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return const <String, dynamic>{};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Failed to fetch KOT print template: ${e.toString()}',
      );
    }
  }

  /// Finalize order. Backend: admin only.
  Future<OrderModel> finalizeOrder(String orderId) async {
    try {
      final response = await _api.post(ApiConfig.finalizeOrder(orderId));
      final orderData = response['data'] ?? response;
      if (response['success'] == true ||
          (orderData is Map &&
              (orderData['_id'] != null || orderData['id'] != null))) {
        return OrderModel.fromJson(Map<String, dynamic>.from(orderData));
      }
      throw ApiException(message: response['message'] ?? 'Failed to finalize');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to finalize: ${e.toString()}');
    }
  }
}
