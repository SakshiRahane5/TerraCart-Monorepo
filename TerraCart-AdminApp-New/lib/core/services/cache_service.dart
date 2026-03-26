/// Cache service for storing and retrieving frequently accessed data
/// Reduces API calls and improves real-time performance
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final Map<String, CacheEntry> _memoryCache = {};
  static const Duration _defaultTtl = Duration(minutes: 5);

  /// Get cached data if available and not expired
  T? get<T>(String key) {
    final entry = _memoryCache[key];
    if (entry == null || entry.isExpired) {
      _memoryCache.remove(key);
      return null;
    }
    return entry.data as T?;
  }

  /// Set cache with optional TTL
  void set(String key, dynamic data, {Duration? ttl}) {
    _memoryCache[key] = CacheEntry(data, ttl ?? _defaultTtl);
  }

  /// Remove specific cache entry
  void remove(String key) {
    _memoryCache.remove(key);
  }

  /// Clear all cache
  void clear() {
    _memoryCache.clear();
  }

  /// Clear expired entries
  void clearExpired() {
    _memoryCache.removeWhere((key, entry) => entry.isExpired);
  }

  /// Invalidate cache for a pattern (e.g., 'dashboard:*')
  void invalidatePattern(String pattern) {
    if (pattern.endsWith('*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      _memoryCache.removeWhere((key, _) => key.startsWith(prefix));
    } else {
      _memoryCache.remove(pattern);
    }
  }

  /// Cache keys
  static const String dashboardStats = 'dashboard:stats';
  static const String todayAttendance = 'attendance:today';
  static const String orders = 'orders:list';
  static const String tasks = 'tasks:today';
  static const String inventory = 'inventory:list';

  /// Get cache key with parameters
  static String getCacheKey(String base, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return base;
    final sortedParams = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final paramString = sortedParams
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return '$base?$paramString';
  }
}

/// Cache entry with timestamp
class CacheEntry {
  final dynamic data;
  final DateTime timestamp;
  final Duration ttl;

  CacheEntry(this.data, this.ttl) : timestamp = DateTime.now();

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}
