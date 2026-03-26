import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/preference_keys.dart';
import '../core/services/api_service.dart';
import '../core/services/cache_service.dart';
import '../core/utils/order_alert_payload_parser.dart';
import '../services/auth_service.dart';
import '../services/attendance_service.dart';
import '../services/in_app_notification_service.dart';
import '../services/notification_service.dart';
import '../services/schedule_service.dart';
import '../services/socket_service.dart';
import '../services/print_service.dart';
import '../models/user_model.dart';
import '../core/exceptions/api_exception.dart';
import '../l10n/app_localizations.dart';

class AppProvider extends ChangeNotifier with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final AttendanceService _attendanceService = AttendanceService();
  final ScheduleService _scheduleService = ScheduleService();
  final SocketService _socketService = SocketService();
  final ApiService _apiService = ApiService();

  // Theme settings
  bool _isDarkMode = false;
  bool _largeText = false;
  bool _highContrast = false;
  bool _dyslexiaFont = false;
  bool _voiceCommands = false;
  bool _vibrationEnabled = true;
  bool _smartwatchSync = false;
  bool _morseCodeSupport = false;
  String _languageCode = 'en';
  // Deaf/Hard of Hearing accessibility
  bool _visualAlerts = false;
  bool _visualFlash = false;
  bool _deafMode = false;

  // User state
  bool _isLoggedIn = false;
  String _userName = '';
  String _userRole = 'waiter'; // waiter, cook, manager, captain
  String _userAvatar = '';
  String _userEmail = '';
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _socketListenersAttached = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  String _persistedUserCartId = '';

  static const Duration _vibrationDebounceWindow = Duration(seconds: 3);
  final Map<String, DateTime> _recentAlertVibrations = <String, DateTime>{};

  // Getters
  bool get isDarkMode => _isDarkMode;
  bool get largeText => _largeText;
  bool get highContrast => _highContrast;
  bool get dyslexiaFont => _dyslexiaFont;
  bool get voiceCommands => _voiceCommands;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get vibrationAlerts => _vibrationEnabled;
  bool get smartwatchSync => _smartwatchSync;
  bool get morseCodeSupport => _morseCodeSupport;
  String get languageCode => _languageCode;
  bool get visualAlerts => _visualAlerts;
  bool get visualFlash => _visualFlash;
  bool get deafMode => _deafMode;
  bool get isLoggedIn => _isLoggedIn;
  String get userName => _userName;
  String get userRole => _userRole;
  String get userAvatar => _userAvatar;
  String get userEmail => _userEmail;
  UserModel? get currentUser => _currentUser;
  String? get currentCartId {
    final liveCartId = _currentUser?.cartId?.trim() ?? '';
    if (liveCartId.isNotEmpty) {
      return liveCartId;
    }
    final persistedCartId = _persistedUserCartId.trim();
    if (persistedCartId.isNotEmpty) {
      return persistedCartId;
    }
    return null;
  }
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  bool _isDisposed = false;
  bool _initScheduled = false;
  final Completer<void> _bootstrapCompleter = Completer<void>();

  AppProvider() {
    WidgetsBinding.instance.addObserver(this);
    _scheduleInitialization();
  }

  void _scheduleInitialization() {
    if (_initScheduled) return;
    _initScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed) return;
      _initialize();
    });
  }

  Future<void> _initialize() async {
    try {
      await _loadPreferences();
      await _apiService.init();

      // Check if user is already logged in
      if (_isLoggedIn && _apiService.token != null) {
        try {
          // Verify token is still valid by fetching user data
          await _loadUserData();
          _connectSocket();
          print('[APP_PROVIDER] Auto-login successful for ${_userEmail}');
        } catch (e) {
          // On startup failure, clear local session without making extra API calls.
          print('[APP_PROVIDER] Auto-login failed (token expired/invalid): $e');
          await _clearSessionLocally(notify: false);
        }
      } else {
        // No stored login state, ensure clean state
        _isLoggedIn = false;
        _currentUser = null;
      }
    } catch (e) {
      print('[APP_PROVIDER] Initialization error: $e');
      // Ensure clean state on any error
      _isLoggedIn = false;
      _currentUser = null;
    } finally {
      _isInitialized = true;
      if (!_bootstrapCompleter.isCompleted) {
        _bootstrapCompleter.complete();
      }
      notifyListeners();
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _largeText = prefs.getBool('largeText') ?? false;
    _highContrast = prefs.getBool('highContrast') ?? false;
    _dyslexiaFont = prefs.getBool('dyslexia_mode') ??
        prefs.getBool('dyslexiaFont') ??
        false;
    _voiceCommands = prefs.getBool('voiceCommands') ?? false;
    _vibrationEnabled =
        prefs.getBool(PreferenceKeys.accessibilityVibrationEnabled) ??
            prefs.getBool(PreferenceKeys.legacyVibrationAlerts) ??
            true;
    _smartwatchSync = prefs.getBool('smartwatchSync') ?? false;
    _morseCodeSupport = prefs.getBool('morseCodeSupport') ?? false;
    _languageCode = AppLocalizations.normalizeLanguageCode(
      prefs.getString(PreferenceKeys.appLanguageCode),
    );
    _visualAlerts = prefs.getBool('visualAlerts') ?? false;
    _visualFlash = prefs.getBool('visualFlash') ?? false;
    _deafMode = prefs.getBool('deafMode') ?? false;
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    _userName = prefs.getString('userName') ?? '';
    _userRole = prefs.getString('userRole') ?? 'waiter';
    _userAvatar = prefs.getString('userAvatar') ?? '';
    _userEmail = prefs.getString('userEmail') ?? '';
    _persistedUserCartId = prefs.getString(PreferenceKeys.userCartId) ?? '';
  }

  Future<void> _savePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  // Theme Setters
  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    _savePreference('isDarkMode', _isDarkMode);
    notifyListeners();
  }

  void toggleLargeText() {
    _largeText = !_largeText;
    _savePreference('largeText', _largeText);
    notifyListeners();
  }

  void toggleHighContrast() {
    _highContrast = !_highContrast;
    _savePreference('highContrast', _highContrast);
    notifyListeners();
  }

  void toggleDyslexiaFont() {
    _dyslexiaFont = !_dyslexiaFont;
    _savePreference('dyslexia_mode', _dyslexiaFont);
    _savePreference('dyslexiaFont', _dyslexiaFont);
    notifyListeners();
  }

  void toggleVoiceCommands() {
    _voiceCommands = !_voiceCommands;
    _savePreference('voiceCommands', _voiceCommands);
    notifyListeners();
  }

  void toggleVibrationEnabled() {
    _vibrationEnabled = !_vibrationEnabled;
    _persistVibrationPreference(_vibrationEnabled);
    notifyListeners();
  }

  void toggleVibrationAlerts() {
    toggleVibrationEnabled();
  }

  void toggleSmartwatchSync() {
    _smartwatchSync = !_smartwatchSync;
    _savePreference('smartwatchSync', _smartwatchSync);
    notifyListeners();
  }

  void toggleMorseCodeSupport() {
    _morseCodeSupport = !_morseCodeSupport;
    _savePreference('morseCodeSupport', _morseCodeSupport);
    notifyListeners();
  }

  Future<void> setLanguageCode(String code) async {
    final normalized = AppLocalizations.normalizeLanguageCode(code);
    if (_languageCode == normalized) return;
    _languageCode = normalized;
    await _savePreference(PreferenceKeys.appLanguageCode, normalized);
    notifyListeners();
  }

  void toggleVisualAlerts() {
    _visualAlerts = !_visualAlerts;
    _savePreference('visualAlerts', _visualAlerts);
    notifyListeners();
  }

  void toggleVisualFlash() {
    _visualFlash = !_visualFlash;
    _savePreference('visualFlash', _visualFlash);
    notifyListeners();
  }

  void toggleDeafMode() {
    _deafMode = !_deafMode;
    if (_deafMode) {
      _vibrationEnabled = true;
      _visualAlerts = true;
      _visualFlash = true;
      _persistVibrationPreference(true);
      _savePreference('visualAlerts', true);
      _savePreference('visualFlash', true);
    }
    _savePreference('deafMode', _deafMode);
    notifyListeners();
  }

  void _persistVibrationPreference(bool value) {
    _savePreference(PreferenceKeys.accessibilityVibrationEnabled, value);
    _savePreference(PreferenceKeys.legacyVibrationAlerts, value);
  }

  // User Setters
  Future<void> login({
    required String email,
    required String password,
  }) async {
    try {
      // Avoid race with startup auto-login state restoration.
      if (!_bootstrapCompleter.isCompleted) {
        await _bootstrapCompleter.future;
      }

      _isLoading = true;
      _errorMessage = null;
      _isLoggedIn = false;
      _currentUser = null;
      _userName = '';
      _userEmail = '';
      _userAvatar = '';
      _userRole = 'waiter';
      notifyListeners();

      // Prevent stale identity bleed-over between login attempts.
      await _apiService.setToken(null);
      await _savePreference('isLoggedIn', false);
      await _savePreference('userName', '');
      await _savePreference('userRole', 'waiter');
      await _savePreference('userEmail', '');

      final result = await _authService.login(
        email: email.trim().toLowerCase(),
        password: password,
      );

      if (result['success'] == true) {
        final user = result['user'] as UserModel;
        _currentUser = user;
        _userName = user.name;
        _userRole = _mapBackendRoleToAppRole(user.role);
        _userAvatar = '';
        // Always update email for the logged-in user
        _userEmail = user.email;

        // Check if role is restricted
        if (_userRole == 'restricted') {
          _isLoading = false;
          _isLoggedIn = false;
          _errorMessage =
              'Access denied. Mobile app login is only available for waiter, cook, captain, and manager roles.';
          notifyListeners();
          // Don't save login state for restricted roles
          return;
        }

        _isLoggedIn = true;
        await _persistUserCartId();
        // Canonicalize user details from backend source-of-truth.
        await _loadUserData();

        // Save login state and user data to cache for auto-login on next app start
        await _savePreference('isLoggedIn', true);
        await _savePreference('userName', user.name);
        await _savePreference('userRole', _userRole);
        await _savePreference('userEmail', user.email);

        // Token is already saved by AuthService.login() -> ApiService.setToken()

        // Refresh schedule/day status + attendance (non-blocking for login UX)
        _refreshTodayScheduleStatus().catchError((e) {
          print('[APP_PROVIDER] Failed to fetch schedule status: $e');
        });

        // Fetch today's attendance (auto-created on login for mobile users)
        _fetchTodayAttendance().then((_) {
          // If no attendance found and user is mobile role, try to check in
          if (_todayAttendance == null &&
              !_isTodayOffDay &&
              ["waiter", "cook", "captain", "manager"].contains(_userRole)) {
            _attendanceService
                .checkIn(location: 'Mobile App Auto Check-in')
                .then((_) {
              _fetchTodayAttendance(); // Refresh after check-in
              print('[APP_PROVIDER] Auto checked in on login.');
            }).catchError((checkInError) {
              print('[APP_PROVIDER] Auto check-in failed: $checkInError');
            });
          }
        }).catchError((e) {
          // Attendance fetch failure shouldn't block login
          print('[APP_PROVIDER] Failed to fetch attendance: $e');
        });

        // Connect to socket
        _connectSocket();

        _isLoading = false;
        notifyListeners();
      } else {
        throw ApiException(message: 'Login failed');
      }
    } catch (e) {
      _isLoading = false;
      if (e is ApiException) {
        _errorMessage = e.message;
      } else if (e.toString().contains('SocketException') ||
          e.toString().contains('Network') ||
          e.toString().contains('Failed host lookup')) {
        _errorMessage =
            'Network error. Please check your connection and ensure the backend server is running.';
      } else {
        _errorMessage = 'Login failed. Please try again.';
      }
      _isLoggedIn = false;
      notifyListeners();
      // Don't rethrow - error is already handled and displayed to user
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _authService.getCurrentUser();
      _currentUser = user;
      _userName = user.name;
      _userRole = _mapBackendRoleToAppRole(user.role);
      // Keep email in sync when loading user from backend
      _userEmail = user.email;
      await _persistUserCartId();
      await _registerNotificationToken(user);

      // Save updated user data to cache
      await _savePreference('userName', user.name);
      await _savePreference('userRole', _userRole);
      await _savePreference('userEmail', user.email);

      // Fetch today's attendance (non-blocking)
      _fetchTodayAttendance().catchError((e) {
        print('[APP_PROVIDER] Failed to fetch attendance: $e');
      });
      _refreshTodayScheduleStatus().catchError((e) {
        print('[APP_PROVIDER] Failed to fetch schedule status: $e');
      });

      notifyListeners();
    } catch (e) {
      // If token is invalid/expired, clear stored login state
      if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        print('[APP_PROVIDER] Token expired or invalid, clearing login state');
        _isLoggedIn = false;
        await _savePreference('isLoggedIn', false);
      }
      rethrow;
    }
  }

  Future<void> _fetchTodayAttendance() async {
    try {
      final attendanceList = await _attendanceService.getTodayAttendance();
      if (attendanceList.isNotEmpty) {
        // For manager/captain: filter by employeeId when multiple records (they see all cart attendance)
        Map<String, dynamic>? myRecord;
        final currentEmployeeId = _currentUser?.employeeId;
        if (currentEmployeeId != null && attendanceList.length > 1) {
          myRecord = attendanceList.cast<Map<String, dynamic>>().where((a) {
            final empId = a['employeeId'];
            final empIdStr =
                empId is Map ? empId['_id']?.toString() : empId?.toString();
            return empIdStr == currentEmployeeId;
          }).firstOrNull;
        }
        _todayAttendance = myRecord ?? attendanceList.first;
      } else {
        _todayAttendance = null;
      }
      _updateReadOnlyModeFromAttendance(_todayAttendance);
      notifyListeners();
    } catch (e) {
      // Silently fail - attendance might not exist yet
      print('[APP_PROVIDER] Attendance fetch error: $e');
      _todayAttendance = null;
      _isReadOnlyAfterCheckout = false;
      notifyListeners();
    }
  }

  void _updateReadOnlyModeFromAttendance(Map<String, dynamic>? attendance) {
    if (attendance == null) {
      _isReadOnlyAfterCheckout = false;
      return;
    }

    bool toBool(dynamic value) {
      if (value is bool) return value;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        return normalized == 'true' || normalized == '1' || normalized == 'yes';
      }
      if (value is num) return value != 0;
      return false;
    }

    String? extractDateTimeString(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value.toIso8601String();
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      if (value is Map) {
        for (final key in const ['time', 'timestamp', 'date', 'at', 'value']) {
          final nested = extractDateTimeString(value[key]);
          if (nested != null) return nested;
        }
        return null;
      }
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    String? firstTime(List<dynamic> candidates) {
      for (final candidate in candidates) {
        final value = extractDateTimeString(candidate);
        if (value != null) return value;
      }
      return null;
    }

    final attendanceStatus =
        attendance['attendanceStatus']?.toString().toLowerCase();
    final checkInStatus = attendance['checkInStatus']?.toString().toLowerCase();
    final status = attendance['status']?.toString().toLowerCase();
    final explicitCheckedOut = toBool(attendance['isCheckedOut']) ||
        toBool(attendance['checkedOut']) ||
        toBool(attendance['isCheckout']);
    final hasCheckOutTime = firstTime([
          attendance['checkOut'],
          attendance['checkout'],
          attendance['checkOutTime'],
          attendance['checkoutTime'],
          attendance['checkedOutAt'],
          attendance['checkOutAt'],
          attendance['checkoutAt'],
        ]) !=
        null;

    _isReadOnlyAfterCheckout = explicitCheckedOut ||
        attendanceStatus == 'checked_out' ||
        attendanceStatus == 'checkedout' ||
        checkInStatus == 'checked_out' ||
        checkInStatus == 'checkedout' ||
        status == 'checked_out' ||
        status == 'checkedout' ||
        hasCheckOutTime;
  }

  Future<void> _refreshTodayScheduleStatus() async {
    try {
      if (!["waiter", "cook", "captain", "manager", "employee"]
          .contains(_currentUser?.role)) {
        _isTodayOffDay = false;
        _todayScheduleMessage = null;
        notifyListeners();
        return;
      }

      final schedule = await _scheduleService.getMySchedule();
      final weeklySchedule = schedule['weeklySchedule'] as List<dynamic>? ?? [];
      if (weeklySchedule.isEmpty) {
        _isTodayOffDay = false;
        _todayScheduleMessage = null;
        notifyListeners();
        return;
      }

      const dayMap = {
        1: 'monday',
        2: 'tuesday',
        3: 'wednesday',
        4: 'thursday',
        5: 'friday',
        6: 'saturday',
        7: 'sunday',
      };
      final todayKey = dayMap[DateTime.now().weekday];
      final todayEntry = weeklySchedule.firstWhere(
        (entry) => entry is Map && entry['day']?.toString() == todayKey,
        orElse: () => null,
      );

      if (todayEntry is Map && todayEntry['isWorking'] == false) {
        _isTodayOffDay = true;
        _todayScheduleMessage = 'Today is your off day.';
      } else {
        _isTodayOffDay = false;
        _todayScheduleMessage = null;
      }
      notifyListeners();
    } catch (e) {
      _isTodayOffDay = false;
      _todayScheduleMessage = null;
      notifyListeners();
    }
  }

  // Attendance state
  Map<String, dynamic>? _todayAttendance;
  Map<String, dynamic>? get todayAttendance => _todayAttendance;
  bool _isReadOnlyAfterCheckout = false;
  bool get isReadOnlyAfterCheckout => _isReadOnlyAfterCheckout;
  bool _isTodayOffDay = false;
  bool get isTodayOffDay => _isTodayOffDay;
  String? _todayScheduleMessage;
  String? get todayScheduleMessage => _todayScheduleMessage;

  // Refresh attendance data
  Future<void> refreshAttendance() async {
    await _fetchTodayAttendance();
  }

  // Sync provider attendance state from a screen-level fresh snapshot.
  void syncTodayAttendanceSnapshot(Map<String, dynamic>? attendance) {
    _todayAttendance =
        attendance == null ? null : Map<String, dynamic>.from(attendance);
    _updateReadOnlyModeFromAttendance(_todayAttendance);
    notifyListeners();
  }

  // Refresh user data (public method)
  Future<void> refreshUserData() async {
    await _loadUserData();
  }

  String _mapBackendRoleToAppRole(String backendRole) {
    // Map backend roles to app roles for mobile app
    // Only 4 roles are allowed: waiter, cook, captain, manager
    if (backendRole == 'waiter') {
      return 'waiter';
    } else if (backendRole == 'cook') {
      return 'cook';
    } else if (backendRole == 'captain') {
      return 'captain';
    } else if (backendRole == 'manager') {
      return 'manager';
    }
    // All other roles are restricted
    return 'restricted';
  }

  void _connectSocket() {
    if (_currentUser != null && _apiService.token != null) {
      final socketCartId = currentCartId;
      _socketService.connect(
        token: _apiService.token,
        role: _currentUser!.role,
        cartId: socketCartId,
        franchiseId: _currentUser!.franchiseId,
      );

      // Set up real-time listeners
      _setupSocketListeners();

      // Start auto-print for all staff roles. Claim/complete deduplication
      // prevents duplicate prints even when multiple devices are online.
      if (['manager', 'captain', 'waiter', 'cook'].contains(_userRole)) {
        PrintService().start();
      }
    }
  }

  void _setupSocketListeners() {
    if (_socketListenersAttached) {
      return;
    }
    _socketListenersAttached = true;

    // Order events
    _socketService.on('order:created', (data) {
      _handleRealtimeVibration('order:created', data);
      notifyListeners();
    }, persistent: true);
    _socketService.on('order:upsert', (data) {
      notifyListeners();
    }, persistent: true);

    _socketService.on('order_status_updated', (data) {
      debugPrint(
          '[SOCKET_DEBUG][app_provider] recv order_status_updated orderId=${data is Map ? (data['orderId'] ?? data['_id'] ?? data['id']) : null} status=${data is Map ? data['status'] : null} paymentStatus=${data is Map ? data['paymentStatus'] : null}');
      _handleRealtimeVibration('order:status:updated', data);
      notifyListeners();
    }, persistent: true);
    _socketService.on('order.cancelled', (data) {
      _handleRealtimeVibration('order.cancelled', data);
      notifyListeners();
    }, persistent: true);

    // Payment events
    _socketService.on('paymentCreated', (data) {
      _handleRealtimeVibration('payment:created', data);
      notifyListeners();
    }, persistent: true);
    _socketService.on('paymentUpdated', (data) {
      _handleRealtimeVibration('payment:updated', data);
      notifyListeners();
    }, persistent: true);
    _socketService.on('payment_received', (data) {
      _handleRealtimeVibration('payment:received', data);
      notifyListeners();
    }, persistent: true);

    // Table events
    _socketService.on('table:status:updated', (data) {
      notifyListeners();
    }, persistent: true);

    // KOT events
    _socketService.on('kot:created', (data) {
      _handleRealtimeVibration('kot:created', data);
      notifyListeners();
    }, persistent: true);

    _socketService.on('kot:status:updated', (data) {
      notifyListeners();
    }, persistent: true);

    // Request events
    _socketService.on('request:created', (data) {
      _handleRealtimeVibration('request:created', data);
      notifyListeners();
    }, persistent: true);

    _socketService.on('request:resolved', (data) {
      notifyListeners();
    }, persistent: true);

    // Task events
    _socketService.on('task:created', (data) {
      notifyListeners();
    }, persistent: true);

    _socketService.on('task:completed', (data) {
      notifyListeners();
    }, persistent: true);
  }

  Future<void> logout() async {
    await _clearSessionLocally();

    // Server-side logout should never block local logout UX.
    unawaited(
      _authService
          .logout()
          .timeout(const Duration(seconds: 4))
          .catchError((e) {
        print('[APP_PROVIDER] Background logout API call failed: $e');
      }),
    );
  }

  Future<void> _clearSessionLocally({bool notify = true}) async {
    NotificationService.instance.clearRegisteredUserContext();
    InAppNotificationService.instance.clearAll();
    _socketListenersAttached = false;
    _recentAlertVibrations.clear();
    _socketService.disconnect();
    PrintService().stop();
    _isLoggedIn = false;
    _userName = '';
    _userRole = 'waiter';
    _userAvatar = '';
    _userEmail = '';
    _currentUser = null;
    _errorMessage = null;
    _todayAttendance = null;
    _isReadOnlyAfterCheckout = false;
    _isTodayOffDay = false;
    _todayScheduleMessage = null;
    _persistedUserCartId = '';

    try {
      await _apiService.setToken(null);
    } catch (e) {
      debugPrint('[APP_PROVIDER] Failed to clear auth token: $e');
    }

    // Clear all cached authentication data
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isLoggedIn');
      await prefs.remove('userName');
      await prefs.remove('userRole');
      await prefs.remove('userEmail');
      await prefs.remove('userAvatar');
      await prefs.remove(PreferenceKeys.userCartId);
      CacheService().clear();
    } catch (e) {
      debugPrint('[APP_PROVIDER] Failed to clear cached session: $e');
    }

    if (notify) {
      notifyListeners();
    }
  }

  void setUserRole(String role) {
    _userRole = role;
    _savePreference('userRole', role);
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _persistUserCartId() async {
    final prefs = await SharedPreferences.getInstance();
    final cartId = _currentUser?.cartId?.trim();
    if (cartId == null || cartId.isEmpty) {
      _persistedUserCartId = '';
      await prefs.remove(PreferenceKeys.userCartId);
      return;
    }
    _persistedUserCartId = cartId;
    await prefs.setString(PreferenceKeys.userCartId, cartId);
  }

  Future<void> _registerNotificationToken(UserModel user) async {
    if (user.id.trim().isEmpty) {
      return;
    }

    if (!['waiter', 'cook', 'captain', 'manager'].contains(_userRole)) {
      return;
    }

    try {
      await NotificationService.instance.registerUserForNotifications(
        userId: user.id,
        role: _userRole,
        cartId: user.cartId,
      );
    } catch (error) {
      debugPrint('[APP_PROVIDER] Failed to register FCM token: $error');
    }
  }

  void _handleRealtimeVibration(String eventName, dynamic payload) {
    if (!_vibrationEnabled) {
      if (kDebugMode) {
        debugPrint('[VIBRATION] Skipped ($eventName): setting disabled');
      }
      return;
    }

    if (!_shouldNotifyCurrentRoleForEvent(eventName)) {
      if (kDebugMode) {
        debugPrint('[VIBRATION] Skipped ($eventName): role=$_userRole');
      }
      return;
    }

    final cartMatches = _isRealtimePayloadForCurrentCart(payload);
    if (!cartMatches) {
      if (kDebugMode) {
        debugPrint('[VIBRATION] Skipped ($eventName): cart mismatch');
      }
      return;
    }

    final dedupeKey = OrderAlertPayloadParser.buildDedupeKey(
      eventName: eventName,
      payload: payload,
    );
    if (!_shouldTriggerVibration(dedupeKey)) {
      if (kDebugMode) {
        debugPrint('[VIBRATION] Skipped ($eventName): deduped');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
          '[VIBRATION] Triggering ($eventName) in state=$_appLifecycleState');
    }

    if (_appLifecycleState == AppLifecycleState.resumed) {
      _triggerForegroundInAppAlert(eventName, payload);
      return;
    }

    _triggerBackgroundSocketAlert(eventName, payload);
  }

  bool _shouldNotifyCurrentRoleForEvent(String eventName) {
    final role = _userRole.trim().toLowerCase();
    final normalizedEvent = eventName.trim().toLowerCase();

    final isOrderEvent = normalizedEvent.contains('order');
    final isKotEvent = normalizedEvent.contains('kot');
    final isPaymentEvent = normalizedEvent.contains('payment');
    final isRequestEvent = normalizedEvent.contains('request') ||
        normalizedEvent.contains('assistant');

    if (role == 'cook') {
      return isOrderEvent || isKotEvent;
    }

    if (role == 'waiter' || role == 'captain' || role == 'manager') {
      return isOrderEvent || isKotEvent || isPaymentEvent || isRequestEvent;
    }

    return true;
  }

  bool _shouldTriggerVibration(String dedupeKey) {
    final now = DateTime.now();
    _recentAlertVibrations.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _vibrationDebounceWindow,
    );

    final lastTriggeredAt = _recentAlertVibrations[dedupeKey];
    if (lastTriggeredAt != null &&
        now.difference(lastTriggeredAt) <= _vibrationDebounceWindow) {
      return false;
    }

    _recentAlertVibrations[dedupeKey] = now;
    return true;
  }

  void _triggerForegroundInAppAlert(String eventName, dynamic payload) {
    final rawPayload = payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
    rawPayload.putIfAbsent('event', () => eventName);
    final normalizedPayload =
        OrderAlertPayloadParser.normalizeDataPayload(rawPayload);
    final type = InAppNotificationService.instance.resolveType(
      eventName: eventName,
      payload: normalizedPayload,
    );
    final title = _resolveRealtimeAlertTitle(eventName, normalizedPayload);
    final body = _resolveRealtimeAlertBody(eventName, normalizedPayload);

    InAppNotificationService.instance.enqueue(
      type: type,
      title: title,
      body: body,
      payload: normalizedPayload,
      enableVibration: _vibrationEnabled,
      orderId: OrderAlertPayloadParser.extractEntityId(normalizedPayload),
    );
  }

  String _resolveRealtimeAlertTitle(
    String eventName,
    Map<String, dynamic> payload,
  ) {
    final title = payload['title']?.toString().trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }

    final normalizedEvent = eventName.toLowerCase();
    if (normalizedEvent.contains('assistant')) {
      return 'Urgent Assistant Request';
    }
    if (normalizedEvent.contains('request')) {
      return 'Customer Request';
    }
    if (normalizedEvent.contains('payment')) {
      if (normalizedEvent.contains('received') ||
          normalizedEvent.contains('paid')) {
        return 'Payment Received';
      }
      return 'Payment Request';
    }
    if (normalizedEvent.contains('cancel')) {
      return 'Order Cancelled';
    }
    if (normalizedEvent.contains('ready')) {
      return 'Order Ready';
    }
    return 'New Order';
  }

  String _resolveRealtimeAlertBody(
    String eventName,
    Map<String, dynamic> payload,
  ) {
    final body = payload['body']?.toString().trim();
    if (body != null && body.isNotEmpty) {
      return body;
    }
    final message = payload['message']?.toString().trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }

    final normalizedEvent = eventName.toLowerCase();
    if (normalizedEvent.contains('assistant')) {
      return 'Immediate support has been requested by a customer.';
    }
    if (normalizedEvent.contains('request')) {
      return 'A new customer request needs attention.';
    }
    if (normalizedEvent.contains('payment')) {
      if (normalizedEvent.contains('received') ||
          normalizedEvent.contains('paid')) {
        return 'Payment has been completed for an order.';
      }
      return 'A payment action is pending.';
    }
    if (normalizedEvent.contains('cancel')) {
      return 'An order has been cancelled.';
    }
    if (normalizedEvent.contains('ready')) {
      return 'An order is ready for next action.';
    }
    return 'A new order event was received.';
  }

  Future<void> _triggerBackgroundSocketAlert(
    String eventName,
    dynamic payload,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await NotificationService.instance.showSocketAlertNotification(
      eventName: eventName,
      payload: payload,
      vibrationEnabled: _vibrationEnabled,
    );
  }

  bool _isRealtimePayloadForCurrentCart(dynamic payload) {
    final currentCartId = _currentCartIdOrEmpty();

    if (currentCartId.isEmpty) {
      // Socket subscriptions are already room scoped.
      // If the local cart context is temporarily unavailable, avoid dropping
      // legitimate realtime events such as online payment requests.
      return true;
    }

    final incomingCartId =
        OrderAlertPayloadParser.extractCartId(payload)?.trim();
    if (incomingCartId == null || incomingCartId.isEmpty) {
      // Socket events are room-scoped; if cart id is omitted in payload, treat as match.
      return true;
    }

    return incomingCartId == currentCartId;
  }

  String _currentCartIdOrEmpty() {
    return (currentCartId ?? '').trim();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
