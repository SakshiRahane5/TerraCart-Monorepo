import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/services/cache_service.dart';
import '../core/exceptions/api_exception.dart';
import '../core/constants/preference_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardService {
  final ApiService _api = ApiService();

  Future<String?> _getCurrentCartId() async {
    final prefs = await SharedPreferences.getInstance();
    final cartId = prefs.getString(PreferenceKeys.userCartId)?.trim();
    if (cartId == null || cartId.isEmpty) {
      return null;
    }
    return cartId;
  }

  Future<String> _dashboardCacheKey() async {
    final prefs = await SharedPreferences.getInstance();
    final cartId = prefs.getString(PreferenceKeys.userCartId)?.trim();
    final role = prefs.getString('userRole')?.trim();
    return CacheService.getCacheKey(
      CacheService.dashboardStats,
      <String, dynamic>{
        'cartId': (cartId == null || cartId.isEmpty) ? '__none__' : cartId,
        'role': (role == null || role.isEmpty) ? '__unknown__' : role,
      },
    );
  }

  Future<Map<String, dynamic>> getDashboardStats({bool useCache = true}) async {
    try {
      final cacheKey = await _dashboardCacheKey();
      final currentCartId = await _getCurrentCartId();
      var queryParams = <String, String>{
        if (currentCartId != null && currentCartId.isNotEmpty)
          'cartId': currentCartId,
      };

      // Check cache first
      if (useCache) {
        final cached = CacheService().get<Map<String, dynamic>>(cacheKey);
        if (cached != null) {
          // Return cached data immediately, then refresh in background
          _refreshDashboardStatsInBackground(cacheKey, queryParams);
          return cached;
        }
      }

      Map<String, dynamic> response;
      try {
        response = await _api.get(
          ApiConfig.dashboardStats,
          queryParams: queryParams,
          useCache: false, // Don't cache here, we handle it manually
        );
      } on ApiException catch (e) {
        // If local cart binding is stale, retry once without cartId and trust
        // backend auth scoping.
        if (e.statusCode == 403 && queryParams.containsKey('cartId')) {
          queryParams = <String, String>{};
          response = await _api.get(
            ApiConfig.dashboardStats,
            queryParams: queryParams,
            useCache: false,
          );
        } else {
          rethrow;
        }
      }

      if (response['success'] == true) {
        final data = response['data'] ?? {};
        // Cache the result
        if (useCache) {
          CacheService().set(cacheKey, data, ttl: const Duration(seconds: 30));
        }
        return data;
      }

      throw ApiException(message: 'Failed to get dashboard stats');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get stats: ${e.toString()}');
    }
  }

  // Refresh stats in background without blocking
  void _refreshDashboardStatsInBackground(
    String cacheKey,
    Map<String, String> queryParams,
  ) {
    _api
        .get(
      ApiConfig.dashboardStats,
      queryParams: queryParams,
      useCache: false,
    )
        .then((response) {
      if (response['success'] == true) {
        CacheService().set(cacheKey, response['data'] ?? {},
            ttl: const Duration(seconds: 30));
      }
    }).catchError((_) {
      // Silently fail background refresh
    });
  }

  // Invalidate dashboard cache
  void invalidateCache() {
    CacheService().invalidatePattern('${CacheService.dashboardStats}*');
    CacheService().remove(CacheService.dashboardStats);
  }

  Future<List<Map<String, dynamic>>> getRecentActivity({int limit = 20}) async {
    try {
      final response = await _api.get(
        ApiConfig.recentActivity,
        queryParams: {'limit': limit.toString()},
      );

      if (response['success'] == true) {
        return List<Map<String, dynamic>>.from(response['data'] ?? []);
      }

      throw ApiException(message: 'Failed to get recent activity');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get activity: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getPerformanceMetrics() async {
    try {
      final response = await _api.get(ApiConfig.performance);

      if (response['success'] == true) {
        return response['data'] ?? {};
      }

      throw ApiException(message: 'Failed to get performance metrics');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get metrics: ${e.toString()}');
    }
  }
}
