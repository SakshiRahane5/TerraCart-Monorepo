import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/api_config.dart';
import '../core/constants/preference_keys.dart';
import '../core/services/api_service.dart';
import '../core/utils/order_alert_payload_parser.dart';
import 'in_app_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.instance.handleBackgroundMessage(message);
}

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String ordersChannelId = 'orders_high_priority_v2';
  static const String ordersChannelName = 'Orders & Alerts (Vibration)';
  static const String ordersChannelDescription =
      'High-priority order, KOT, and customer request alerts with vibration.';

  static const String ordersSilentChannelId = 'orders_high_priority_silent_v1';
  static const String ordersSilentChannelName = 'Orders & Alerts (Silent)';
  static const String ordersSilentChannelDescription =
      'High-priority order, KOT, and customer request alerts without vibration.';

  static final Int64List _androidVibrationPattern =
      Int64List.fromList(<int>[0, 400, 200, 400, 200, 600]);
  static final AndroidNotificationChannel _ordersHighPriorityChannel =
      AndroidNotificationChannel(
    ordersChannelId,
    ordersChannelName,
    description: ordersChannelDescription,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    vibrationPattern: _androidVibrationPattern,
  );
  static final AndroidNotificationChannel _ordersSilentChannel =
      AndroidNotificationChannel(
    ordersSilentChannelId,
    ordersSilentChannelName,
    description: ordersSilentChannelDescription,
    importance: Importance.max,
    playSound: true,
    enableVibration: false,
  );

  static const Duration _dedupeWindow = Duration(seconds: 3);
  static final Map<String, DateTime> _recentBackgroundAlerts =
      <String, DateTime>{};

  static const Set<String> _staffOperationalRoles = <String>{
    'waiter',
    'captain',
    'manager',
    'cook',
  };

  final ApiService _apiService = ApiService();
  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _foregroundListenerAttached = false;
  String? _activeUserId;
  String? _activeUserRole;
  String? _activeUserCartId;
  String? _lastSyncedFcmToken;
  bool _isTokenSyncInProgress = false;

  static bool _localNotificationsInitialized = false;
  static bool _firebaseInitialized = false;

  bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isApplePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> initialize() async {
    try {
      await _initializeLocalNotifications();
      await _requestLocalNotificationPermissions();
      await _initializeFirebase();

      if (!_firebaseInitialized) {
        debugPrint('[NotificationService] Firebase init skipped.');
        return;
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _requestPermissions();
      _attachForegroundListener();
      _attachTokenRefreshListener();
    } catch (error) {
      debugPrint('[NotificationService] initialize failed: $error');
    }
  }

  Future<void> registerUserForNotifications({
    required String userId,
    required String role,
    String? cartId,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return;
    }

    final normalizedRole = role.trim().toLowerCase();
    if (!_staffOperationalRoles.contains(normalizedRole)) {
      debugPrint(
        '[NotificationService] Skipping FCM registration for unsupported role: $normalizedRole',
      );
      return;
    }

    _activeUserId = normalizedUserId;
    _activeUserRole = normalizedRole;
    _activeUserCartId = cartId?.trim();

    await initialize();
    await _syncCurrentFcmToken(force: true);
    _attachTokenRefreshListener();
  }

  void clearRegisteredUserContext() {
    _activeUserId = null;
    _activeUserRole = null;
    _activeUserCartId = null;
    _lastSyncedFcmToken = null;
  }

  Future<void> handleBackgroundMessage(RemoteMessage message) async {
    try {
      await _initializeLocalNotifications();
      await _initializeFirebase();

      if (!_firebaseInitialized) {
        return;
      }

      final normalizedData =
          OrderAlertPayloadParser.normalizeDataPayload(message.data);
      if (!OrderAlertPayloadParser.isOperationalAlertData(normalizedData)) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final userRole = _resolveCurrentUserRole(prefs);
      final userCartId = _resolveCurrentCartId(prefs);

      final eventName =
          OrderAlertPayloadParser.extractEventName(normalizedData) ??
              _inferEventName(normalizedData);
      if (!_shouldNotifyRoleForEvent(eventName, userRole)) {
        return;
      }

      final vibrationEnabled =
          prefs.getBool(PreferenceKeys.accessibilityVibrationEnabled) ??
              prefs.getBool(PreferenceKeys.legacyVibrationAlerts) ??
              true;

      final cartMatches = OrderAlertPayloadParser.cartMatches(
        currentCartId: userCartId,
        payload: normalizedData,
        allowMissingIncomingCart: true,
      );
      if (!cartMatches) {
        return;
      }

      final dedupeKey = OrderAlertPayloadParser.buildDedupeKey(
        eventName: eventName,
        payload: normalizedData,
      );
      if (!_shouldProcessBackgroundAlert(dedupeKey)) {
        return;
      }

      final title = _resolveTitle(message, normalizedData, eventName);
      final body = _resolveBody(normalizedData, eventName);
      await _showLocalAlertNotification(
        title: title,
        body: body,
        payload: normalizedData,
        vibrationEnabled: vibrationEnabled,
      );
    } catch (error) {
      debugPrint(
          '[NotificationService] handleBackgroundMessage failed: $error');
    }
  }

  Future<void> _initializeFirebase() async {
    if (_firebaseInitialized) {
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _messaging = FirebaseMessaging.instance;
      _firebaseInitialized = true;
    } catch (error) {
      _messaging = null;
      _firebaseInitialized = false;
      debugPrint('[NotificationService] Firebase initialize failed: $error');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) {
      return;
    }

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();
      const initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotificationsPlugin.initialize(initializationSettings);

      final androidPlugin =
          _localNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin
          ?.createNotificationChannel(_ordersHighPriorityChannel);
      await androidPlugin?.createNotificationChannel(_ordersSilentChannel);
      _localNotificationsInitialized = true;
    } catch (error) {
      _localNotificationsInitialized = false;
      debugPrint(
          '[NotificationService] Local notifications initialize failed: $error');
    }
  }

  Future<void> _requestPermissions() async {
    final messaging = _messaging;
    if (messaging == null) {
      return;
    }

    try {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (_isApplePlatform) {
        // Use custom in-app banners for foreground events; suppress iOS system
        // foreground alerts to avoid duplicate notification surfaces.
        await messaging.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
      }
    } catch (error) {
      debugPrint('[NotificationService] Permission request failed: $error');
    }
  }

  Future<void> _requestLocalNotificationPermissions() async {
    if (_isAndroidPlatform) {
      final androidPlugin =
          _localNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }

    if (_isApplePlatform) {
      final iosPlugin =
          _localNotificationsPlugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      final macOsPlugin =
          _localNotificationsPlugin.resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>();
      await macOsPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  void _attachForegroundListener() {
    if (_foregroundListenerAttached) {
      return;
    }
    _foregroundListenerAttached = true;

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      try {
        await _initializeLocalNotifications();
        final prefs = await SharedPreferences.getInstance();

        final normalizedData =
            OrderAlertPayloadParser.normalizeDataPayload(message.data);
        final eventName =
            OrderAlertPayloadParser.extractEventName(normalizedData) ??
                _inferEventName(normalizedData);

        if (!OrderAlertPayloadParser.isOperationalAlertData(normalizedData)) {
          // Still allow explicit notification payloads without structured data.
          if (message.notification == null) {
            return;
          }
        }

        final role = _resolveCurrentUserRole(prefs);
        if (!_shouldNotifyRoleForEvent(eventName, role)) {
          return;
        }

        final userCartId = _resolveCurrentCartId(prefs);
        final cartMatches = OrderAlertPayloadParser.cartMatches(
          currentCartId: userCartId,
          payload: normalizedData,
          allowMissingIncomingCart: true,
        );
        if (!cartMatches) {
          return;
        }

        final dedupeKey = OrderAlertPayloadParser.buildDedupeKey(
          eventName: eventName,
          payload: normalizedData,
        );
        if (!_shouldProcessBackgroundAlert('fcm:$dedupeKey')) {
          return;
        }

        final vibrationEnabled =
            prefs.getBool(PreferenceKeys.accessibilityVibrationEnabled) ??
                prefs.getBool(PreferenceKeys.legacyVibrationAlerts) ??
                true;

        final title = _resolveTitle(message, normalizedData, eventName);
        final body = _resolveBody(normalizedData, eventName);
        final type = InAppNotificationService.instance.resolveType(
          eventName: eventName,
          payload: normalizedData,
        );
        InAppNotificationService.instance.enqueue(
          type: type,
          title: title,
          body: body,
          payload: normalizedData,
          enableVibration: vibrationEnabled,
          orderId: OrderAlertPayloadParser.extractEntityId(normalizedData),
        );
      } catch (error) {
        debugPrint(
          '[NotificationService] Foreground message handling failed: $error',
        );
      }
    });
  }

  void _attachTokenRefreshListener() {
    if (_tokenRefreshSubscription != null) {
      return;
    }

    _tokenRefreshSubscription =
        FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final normalizedToken = token.trim();
      if (normalizedToken.isEmpty) {
        return;
      }
      await _syncTokenToBackend(normalizedToken, force: true);
    }, onError: (error) {
      debugPrint('[NotificationService] onTokenRefresh failed: $error');
    });
  }

  Future<void> _syncCurrentFcmToken({bool force = false}) async {
    if (!_firebaseInitialized) {
      return;
    }

    final messaging = _messaging;
    if (messaging == null) {
      return;
    }

    String? token;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        token = await messaging.getToken();
      } catch (error) {
        debugPrint(
          '[NotificationService] getToken attempt ${attempt + 1} failed: $error',
        );
      }

      if (token != null && token.trim().isNotEmpty) {
        break;
      }

      await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }

    final normalizedToken = token?.trim();
    if (normalizedToken == null || normalizedToken.isEmpty) {
      debugPrint(
        '[NotificationService] FCM token unavailable. Ensure notification permission is granted.',
      );
      return;
    }

    await _syncTokenToBackend(normalizedToken, force: force);
  }

  Future<void> _syncTokenToBackend(
    String token, {
    bool force = false,
  }) async {
    if (_isTokenSyncInProgress) {
      return;
    }

    final userId = _activeUserId?.trim();
    if (userId == null || userId.isEmpty) {
      return;
    }

    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      return;
    }

    if (!force && _lastSyncedFcmToken == normalizedToken) {
      return;
    }

    _isTokenSyncInProgress = true;
    try {
      await _apiService.post(
        ApiConfig.saveFcmToken,
        body: {
          'userId': userId,
          'firebaseToken': normalizedToken,
          'platform': _resolvePlatform(),
        },
      );
      _lastSyncedFcmToken = normalizedToken;
      debugPrint('[NotificationService] Synced FCM token for user $userId');
    } catch (error) {
      debugPrint('[NotificationService] Failed to sync FCM token: $error');
    } finally {
      _isTokenSyncInProgress = false;
    }
  }

  String _resolvePlatform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return 'ios';
      default:
        return 'unknown';
    }
  }

  String _resolveCurrentUserRole(SharedPreferences prefs) {
    final persistedRole =
        prefs.getString('userRole')?.trim().toLowerCase() ?? '';
    final activeRole = _activeUserRole?.trim().toLowerCase() ?? '';
    if (activeRole.isNotEmpty) {
      return activeRole;
    }
    return persistedRole;
  }

  String? _resolveCurrentCartId(SharedPreferences prefs) {
    final persistedCartId = prefs.getString(PreferenceKeys.userCartId)?.trim();
    final activeCartId = _activeUserCartId?.trim();
    if (activeCartId != null && activeCartId.isNotEmpty) {
      return activeCartId;
    }
    return persistedCartId;
  }

  bool _shouldNotifyRoleForEvent(String eventName, String role) {
    final normalizedRole = role.trim().toLowerCase();
    if (normalizedRole.isEmpty) {
      return false;
    }

    final normalizedEvent = eventName.trim().toLowerCase();
    final isOrderEvent = normalizedEvent.contains('order');
    final isKotEvent = normalizedEvent.contains('kot');
    final isPaymentEvent = normalizedEvent.contains('payment');
    final isRequestEvent = normalizedEvent.contains('request') ||
        normalizedEvent.contains('assistant');
    final isBroadcastEvent = normalizedEvent.contains('broadcast') ||
        normalizedEvent.contains('maintenance') ||
        normalizedEvent.contains('test');

    if (normalizedRole == 'cook') {
      return isOrderEvent || isKotEvent || isBroadcastEvent;
    }

    if (normalizedRole == 'waiter' ||
        normalizedRole == 'captain' ||
        normalizedRole == 'manager') {
      return isOrderEvent ||
          isKotEvent ||
          isPaymentEvent ||
          isRequestEvent ||
          isBroadcastEvent;
    }

    return true;
  }

  String _inferEventName(Map<String, dynamic> data) {
    final notificationType = data['notificationType']?.toString().trim();
    if (notificationType != null && notificationType.isNotEmpty) {
      return notificationType.toLowerCase();
    }
    if (data.containsKey('paymentId') || data.containsKey('payment_id')) {
      return 'payment:updated';
    }
    if (data.containsKey('kotId')) {
      return 'kot:created';
    }
    if (data.containsKey('requestId')) {
      return 'request:created';
    }
    if (data.containsKey('orderId')) {
      return 'order:created';
    }
    return 'order:created';
  }

  static bool _shouldProcessBackgroundAlert(String dedupeKey) {
    final now = DateTime.now();
    _recentBackgroundAlerts.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _dedupeWindow,
    );

    final lastTimestamp = _recentBackgroundAlerts[dedupeKey];
    if (lastTimestamp != null &&
        now.difference(lastTimestamp) <= _dedupeWindow) {
      return false;
    }

    _recentBackgroundAlerts[dedupeKey] = now;
    return true;
  }

  Future<void> showSocketAlertNotification({
    required String eventName,
    required dynamic payload,
    required bool vibrationEnabled,
  }) async {
    try {
      if (!_isAndroidPlatform) {
        return;
      }

      await _initializeLocalNotifications();

      final rawPayload = payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{};
      rawPayload.putIfAbsent('event', () => eventName);
      final normalizedPayload =
          OrderAlertPayloadParser.normalizeDataPayload(rawPayload);
      final prefs = await SharedPreferences.getInstance();
      final role = _resolveCurrentUserRole(prefs);
      if (!_shouldNotifyRoleForEvent(eventName, role)) {
        return;
      }

      final dedupeKey = OrderAlertPayloadParser.buildDedupeKey(
        eventName: eventName,
        payload: normalizedPayload,
      );
      if (!_shouldProcessBackgroundAlert('socket:$dedupeKey')) {
        return;
      }

      final title = _resolveTitleFromData(normalizedPayload, eventName);
      final body = _resolveBody(normalizedPayload, eventName);
      await _showLocalAlertNotification(
        title: title,
        body: body,
        payload: normalizedPayload,
        vibrationEnabled: vibrationEnabled,
      );
    } catch (error) {
      debugPrint(
          '[NotificationService] showSocketAlertNotification failed: $error');
    }
  }

  Future<void> _showLocalAlertNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    required bool vibrationEnabled,
  }) async {
    if (!_isAndroidPlatform) {
      return;
    }

    final channel =
        vibrationEnabled ? _ordersHighPriorityChannel : _ordersSilentChannel;
    final notificationId = _notificationIdForPayload(payload);
    final safePayload = _safeJsonEncode(payload);

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: vibrationEnabled,
      vibrationPattern: vibrationEnabled ? _androidVibrationPattern : null,
      icon: '@mipmap/ic_launcher',
    );

    await _localNotificationsPlugin.show(
      notificationId,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: safePayload,
    );
  }

  int _notificationIdForPayload(Map<String, dynamic> payload) {
    final entityId =
        OrderAlertPayloadParser.extractEntityId(payload) ?? '${DateTime.now()}';
    return entityId.hashCode & 0x7fffffff;
  }

  String _resolveTitle(
    RemoteMessage message,
    Map<String, dynamic> data,
    String eventName,
  ) {
    return _resolveTitleFromData(
      data,
      eventName,
      fallbackTitle: message.notification?.title,
    );
  }

  String _resolveTitleFromData(
    Map<String, dynamic> data,
    String eventName, {
    String? fallbackTitle,
  }) {
    final explicitTitle = data['title']?.toString().trim();
    if (explicitTitle != null && explicitTitle.isNotEmpty) {
      return explicitTitle;
    }

    final notificationTitle = fallbackTitle?.trim();
    if (notificationTitle != null && notificationTitle.isNotEmpty) {
      return notificationTitle;
    }

    if (eventName.contains('assistant')) {
      return 'Assistant Request';
    }
    if (eventName.contains('request')) {
      return 'New Customer Request';
    }
    if (eventName.contains('payment')) {
      if (eventName.contains('received') || eventName.contains('paid')) {
        return 'Payment Received';
      }
      return 'Payment Request';
    }
    if (eventName.contains('kot')) {
      return 'New KOT';
    }
    return 'New Order';
  }

  String _resolveBody(Map<String, dynamic> data, String eventName) {
    final explicitBody = data['body']?.toString().trim();
    if (explicitBody != null && explicitBody.isNotEmpty) {
      return explicitBody;
    }

    final message = data['message']?.toString().trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }

    if (eventName.contains('assistant')) {
      return 'A customer requested staff assistance.';
    }
    if (eventName.contains('request')) {
      return 'A customer has raised a new request.';
    }
    if (eventName.contains('payment')) {
      if (eventName.contains('received') || eventName.contains('paid')) {
        return 'Payment has been completed for an order.';
      }
      return 'Payment action is required for an order.';
    }
    if (eventName.contains('kot')) {
      return 'A new kitchen order ticket is ready.';
    }
    return 'A new order has arrived.';
  }

  String _safeJsonEncode(Map<String, dynamic> data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      return '{}';
    }
  }
}
