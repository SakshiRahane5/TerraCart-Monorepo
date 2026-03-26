import '../core/config/api_config.dart';
import '../core/exceptions/api_exception.dart';
import '../core/services/api_service.dart';
import '../models/addon_model.dart';

class AddonService {
  final ApiService _api = ApiService();
  static const List<AddonModel> _fallbackAddons = [
    AddonModel(
      id: 'extraCheese',
      name: 'Extra Cheese',
      price: 20,
      icon: null,
      isAvailable: true,
      sortOrder: 1,
    ),
    AddonModel(
      id: 'extraSauce',
      name: 'Extra Sauce',
      price: 10,
      icon: null,
      isAvailable: true,
      sortOrder: 2,
    ),
    AddonModel(
      id: 'oregano',
      name: 'Oregano & Chilli Flakes',
      price: 0,
      icon: null,
      isAvailable: true,
      sortOrder: 3,
    ),
    AddonModel(
      id: 'tissues',
      name: 'Tissue Paper',
      price: 0,
      icon: null,
      isAvailable: true,
      sortOrder: 4,
    ),
    AddonModel(
      id: 'cutlery',
      name: 'Disposable Cutlery',
      price: 0,
      icon: null,
      isAvailable: true,
      sortOrder: 5,
    ),
  ];

  Future<List<AddonModel>> _fetchPublicAddons(
    Map<String, String> queryParams,
  ) async {
    final response = await _api.get(
      ApiConfig.publicAddons,
      queryParams: queryParams,
    );

    final dynamic rawData = response['data'] ?? response;
    if (rawData is! List) return [];

    return rawData
        .whereType<Map>()
        .map(
          (e) => AddonModel.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList();
  }

  Future<String?> _resolveCartIdFromTable(String tableId) async {
    final response = await _api.get('/tables/public-cart-id/$tableId');
    final dynamic rawCartId = response['cartId'] ?? response['data']?['cartId'];
    final cartId = rawCartId?.toString().trim();
    return (cartId == null || cartId.isEmpty) ? null : cartId;
  }

  Future<List<AddonModel>> getPublicAddons({
    String? cartId,
    String? tableId,
  }) async {
    final safeCartId = cartId?.trim() ?? '';
    final safeTableId = tableId?.trim() ?? '';

    if (safeCartId.isEmpty && safeTableId.isEmpty) {
      return _fallbackAddons;
    }

    final attempts = <Map<String, String>>[
      if (safeCartId.isNotEmpty && safeTableId.isNotEmpty)
        {'cartId': safeCartId, 'tableId': safeTableId},
      if (safeTableId.isNotEmpty) {'tableId': safeTableId},
      if (safeCartId.isNotEmpty) {'cartId': safeCartId},
    ];

    final seenAttemptKeys = <String>{};
    List<AddonModel> lastSuccess = [];

    for (final params in attempts) {
      final key = params.entries.map((e) => '${e.key}:${e.value}').toList()
        ..sort();
      final attemptKey = key.join('|');
      if (seenAttemptKeys.contains(attemptKey)) continue;
      seenAttemptKeys.add(attemptKey);

      try {
        final addons = await _fetchPublicAddons(params);
        if (addons.isNotEmpty) return addons;
        lastSuccess = addons;
      } catch (_) {
        // Try next fallback attempt.
      }
    }

    // Match customer web fallback: if cartId was wrong/missing, resolve from tableId.
    if (safeTableId.isNotEmpty) {
      try {
        final resolvedCartId = await _resolveCartIdFromTable(safeTableId);
        if (resolvedCartId != null && resolvedCartId.isNotEmpty) {
          final addons = await _fetchPublicAddons({'cartId': resolvedCartId});
          if (addons.isNotEmpty) return addons;
          lastSuccess = addons;
        }
      } catch (_) {
        // Keep graceful empty response.
      }
    }

    if (lastSuccess.isNotEmpty) {
      return lastSuccess;
    }

    try {
      final finalAttempt = await _fetchPublicAddons({
        if (safeTableId.isNotEmpty) 'tableId': safeTableId,
        if (safeCartId.isNotEmpty) 'cartId': safeCartId,
      });
      return finalAttempt.isNotEmpty ? finalAttempt : _fallbackAddons;
    } catch (e) {
      if (e is ApiException) {
        return _fallbackAddons;
      }
      return _fallbackAddons;
    }
  }
}
