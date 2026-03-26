import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';
import '../core/constants/preference_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PaymentService {
  final ApiService _api = ApiService();

  Future<String?> _getCurrentCartId() async {
    final prefs = await SharedPreferences.getInstance();
    final cartId = prefs.getString(PreferenceKeys.userCartId)?.trim();
    if (cartId == null || cartId.isEmpty) {
      return null;
    }
    return cartId;
  }

  Future<List<Map<String, dynamic>>> getPayments() async {
    try {
      final currentCartId = await _getCurrentCartId();
      final response = await _api.get(
        ApiConfig.payments,
        queryParams: <String, String>{
          if (currentCartId != null && currentCartId.isNotEmpty)
            'cartId': currentCartId,
        },
      );
      final data = response['data'] ?? response;
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get payments: ${e.toString()}');
    }
  }

  /// Get latest payment for an order (for bill printing - payment method).
  Future<Map<String, dynamic>?> getLatestPaymentForOrder(String orderId) async {
    try {
      final response = await _api.get(
        ApiConfig.latestPaymentForOrder(orderId),
      );
      final data = response['data'] ?? response;
      if (data == null) return null;
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    } catch (e) {
      if (e is ApiException) rethrow;
      return null; // No payment yet is valid
    }
  }

  Future<Map<String, dynamic>> getPaymentById(String id) async {
    try {
      final response = await _api.get(ApiConfig.paymentById(id));
      final data = response['data'] ?? response;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      throw ApiException(message: 'Invalid payment response');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get payment: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> markPaymentPaid(String id) async {
    try {
      final response = await _api.post(ApiConfig.markPaymentPaid(id));
      final data = response['data'] ?? response;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return {};
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to mark payment as paid: ${e.toString()}');
    }
  }

  Future<void> cancelPayment(String id, {String? reason}) async {
    try {
      await _api.post(ApiConfig.cancelPayment(id),
          body: reason != null ? {'reason': reason} : {});
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to cancel payment: ${e.toString()}');
    }
  }

  Future<void> syncPaidPayments() async {
    try {
      await _api.post(ApiConfig.syncPaidPayments);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to sync paid payments: ${e.toString()}');
    }
  }
}
