import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';

class InventoryService {
  final ApiService _api = ApiService();

  Future<List<Map<String, dynamic>>> getInventoryItems({
    String? category,
    int page = 1,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (category != null) 'category': category,
      };

      final response =
          await _api.get(ApiConfig.inventory, queryParams: queryParams);

      List<dynamic> itemsList = [];
      if (response['success'] == true &&
          response['data'] != null &&
          response['data'] is List) {
        itemsList = response['data'] as List;
      } else if (response.containsKey('data') && response['data'] is List) {
        itemsList = response['data'] as List;
      }

      final result = <Map<String, dynamic>>[];
      for (final e in itemsList) {
        if (e is Map) {
          result.add(Map<String, dynamic>.from(e));
        }
      }
      return result;
    } catch (e) {
      // ignore: avoid_print
      print('[INVENTORY] Error: $e');
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get inventory: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getInventoryStats() async {
    try {
      final response = await _api.get(ApiConfig.inventoryStats);

      if (response['success'] == true) {
        return response['data'] ?? {};
      }

      throw ApiException(message: 'Failed to get inventory stats');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get stats: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getInventoryTransactions({
    String? ingredientId,
    String? type,
    String? from,
    String? to,
    String? cartId,
  }) async {
    try {
      final queryParams = <String, String>{
        if (ingredientId != null && ingredientId.isNotEmpty)
          'ingredientId': ingredientId,
        if (type != null && type.isNotEmpty) 'type': type,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (cartId != null && cartId.isNotEmpty) 'cartId': cartId,
      };

      final response = await _api.get(
        ApiConfig.inventoryTransactions,
        queryParams: queryParams.isEmpty ? null : queryParams,
      );

      final data = response['data'];
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to get inventory transactions: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> createInventoryItem(
      Map<String, dynamic> itemData) async {
    try {
      final response =
          await _api.post(ApiConfig.costingIngredients, body: itemData);

      if (response['success'] == true && response['data'] != null) {
        final result = Map<String, dynamic>.from(response['data'] as Map);
        if (response['message'] != null) {
          result['message'] = response['message'];
        }
        if (response['warning'] != null) {
          result['warning'] = response['warning'];
        }
        if (response['isExisting'] != null) {
          result['isExisting'] = response['isExisting'];
        }
        return result;
      }

      if (response.containsKey('_id') || response.containsKey('name')) {
        // Backward-compatible fallback for raw object response
        return Map<String, dynamic>.from(response);
      }

      if (response['success'] == true) {
        // Some backend success responses may only include warning/message.
        return Map<String, dynamic>.from(response);
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to create inventory item');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to create inventory item: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> updateStock(String id, double quantity) async {
    try {
      final response = await _api.patch(
        ApiConfig.updateStock(id),
        body: {
          'quantity': quantity,
          'operation': 'set', // Backend requires 'add', 'subtract', or 'set'
        },
      );

      // Backend returns either wrapped {success: true, data: {...}} or raw object
      if (response.containsKey('message') &&
          !response.containsKey('_id') &&
          !response.containsKey('quantity')) {
        // Error response
        throw ApiException(
            message: response['message'] ?? 'Failed to update stock');
      }

      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data'] as Map);
      } else if (response.containsKey('_id') ||
          response.containsKey('quantity')) {
        // Raw object response (direct from backend - stock updated successfully)
        return Map<String, dynamic>.from(response);
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to update stock');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to update stock: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableIngredients() async {
    try {
      final response = await _api.get(ApiConfig.availableIngredients);

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          return data.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }

      throw ApiException(message: 'Failed to get available ingredients');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get ingredients: ${e.toString()}');
    }
  }

  /// Consume (subtract) inventory - costing-v2. Manager only.
  Future<Map<String, dynamic>> consumeInventory({
    required String ingredientId,
    required double qty,
    required String uom,
    String refType = 'manual',
    String? refId,
    String? cartId,
  }) async {
    try {
      final response = await _api.post(ApiConfig.inventoryConsume, body: {
        'ingredientId': ingredientId,
        'qty': qty,
        'uom': uom,
        'refType': refType,
        if (refId != null && refId.isNotEmpty) 'refId': refId,
        if (cartId != null && cartId.isNotEmpty) 'cartId': cartId,
      });
      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
      throw ApiException(
          message: response['message'] ?? 'Failed to consume inventory');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to consume inventory: ${e.toString()}');
    }
  }

  /// Return (add) inventory - costing-v2. Manager only.
  Future<Map<String, dynamic>> returnToInventory({
    required String ingredientId,
    required double qty,
    required String uom,
    String refType = 'return',
    String? refId,
    String? originalTransactionId,
    String? notes,
    String? cartId,
  }) async {
    try {
      final response = await _api.post(ApiConfig.inventoryReturn, body: {
        'ingredientId': ingredientId,
        'qty': qty,
        'uom': uom,
        'refType': refType,
        if (refId != null && refId.isNotEmpty) 'refId': refId,
        if (originalTransactionId != null && originalTransactionId.isNotEmpty)
          'originalTransactionId': originalTransactionId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (cartId != null && cartId.isNotEmpty) 'cartId': cartId,
      });
      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
      throw ApiException(
          message: response['message'] ?? 'Failed to return to inventory');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to return to inventory: ${e.toString()}');
    }
  }

  /// Direct Purchase (add stock with price) - costing-v2. Manager only.
  Future<Map<String, dynamic>> directPurchase({
    required String ingredientId,
    required double qty,
    required String uom,
    required double unitPrice,
    String? supplier,
    String? notes,
    String? cartId,
  }) async {
    try {
      final response =
          await _api.post(ApiConfig.inventoryDirectPurchase, body: {
        'ingredientId': ingredientId,
        'qty': qty,
        'uom': uom,
        'unitPrice': unitPrice,
        if (supplier != null) 'supplier': supplier,
        if (notes != null) 'notes': notes,
        if (cartId != null && cartId.isNotEmpty) 'cartId': cartId,
      });
      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
      throw ApiException(
          message: response['message'] ?? 'Failed to add direct purchase');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to add direct purchase: ${e.toString()}');
    }
  }

  /// Update ingredient (reorderLevel, storageLocation, etc.) - costing-v2. Manager only.
  Future<Map<String, dynamic>> updateIngredient(
      String id, Map<String, dynamic> data) async {
    try {
      final response =
          await _api.put(ApiConfig.costingIngredient(id), body: data);
      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data'] as Map);
      } else if (response.containsKey('_id') || response.containsKey('name')) {
        return Map<String, dynamic>.from(response);
      }
      throw ApiException(
          message: response['message'] ?? 'Failed to update ingredient');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to update ingredient: ${e.toString()}');
    }
  }

  /// Record waste transaction - costing-v2. Manager only.
  Future<Map<String, dynamic>> recordWaste({
    required String ingredientId,
    required double qty,
    required String uom,
    required String reason,
    String? reasonDetails,
    String? cartId,
  }) async {
    try {
      final response = await _api.post(ApiConfig.costingWaste, body: {
        'ingredientId': ingredientId,
        'qty': qty,
        'uom': uom,
        'reason': reason,
        if (reasonDetails != null && reasonDetails.trim().isNotEmpty)
          'reasonDetails': reasonDetails.trim(),
        if (cartId != null && cartId.isNotEmpty) 'cartId': cartId,
      });
      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
      throw ApiException(
          message: response['message'] ?? 'Failed to record waste');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to record waste: ${e.toString()}');
    }
  }
}
