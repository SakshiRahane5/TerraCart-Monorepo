import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import '../core/notifications/in_app_notification_models.dart';
import '../screens/customer_requests/customer_requests_screen.dart';
import '../screens/orders/orders_screen.dart';
import '../screens/payments/payments_screen.dart';

class InAppNotificationService {
  InAppNotificationService._();

  static final InAppNotificationService instance = InAppNotificationService._();

  final Queue<InAppNotificationItem> _queue = Queue<InAppNotificationItem>();
  final Map<String, DateTime> _recentOrderEvents = <String, DateTime>{};
  final ValueNotifier<InAppNotificationItem?> currentNotification =
      ValueNotifier<InAppNotificationItem?>(null);

  static const Duration _orderMergeWindow = Duration(seconds: 5);

  Timer? _dismissTimer;
  GlobalKey<NavigatorState>? _navigatorKey;

  void attachNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }

  void enqueue({
    required InAppNotificationType type,
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    required bool enableVibration,
    String? orderId,
  }) {
    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty && trimmedBody.isEmpty) {
      return;
    }

    final now = DateTime.now();
    _pruneOrderMergeCache(now);

    final normalizedOrderId = orderId?.trim();
    if (normalizedOrderId != null && normalizedOrderId.isNotEmpty) {
      final lastEventAt = _recentOrderEvents[normalizedOrderId];
      final withinMergeWindow = lastEventAt != null &&
          now.difference(lastEventAt) <= _orderMergeWindow;

      _recentOrderEvents[normalizedOrderId] = now;

      if (withinMergeWindow) {
        final merged = _mergeWithActiveOrQueued(
          type: type,
          title: trimmedTitle,
          body: trimmedBody,
          payload: payload,
          orderId: normalizedOrderId,
          enableVibration: enableVibration,
          now: now,
        );
        if (merged) {
          return;
        }
      }
    }

    final item = InAppNotificationItem(
      id: '${now.microsecondsSinceEpoch}_${type.name}',
      type: type,
      title: trimmedTitle,
      body: trimmedBody,
      payload: Map<String, dynamic>.from(payload),
      createdAt: now,
      enableVibration: enableVibration,
      orderId: normalizedOrderId,
    );

    _queue.add(item);
    _pumpQueue();
  }

  void dismissCurrent() {
    _dismissTimer?.cancel();
    _dismissTimer = null;

    if (currentNotification.value == null) {
      return;
    }

    currentNotification.value = null;
    _pumpQueue();
  }

  void clearAll() {
    _queue.clear();
    _dismissTimer?.cancel();
    _dismissTimer = null;
    currentNotification.value = null;
    _recentOrderEvents.clear();
  }

  void handleNotificationTap(InAppNotificationItem item) {
    dismissCurrent();

    final navigatorState = _navigatorKey?.currentState;
    if (navigatorState == null) {
      return;
    }

    final route = _buildRoute(item);
    if (route == null) {
      return;
    }

    navigatorState.push(route);
  }

  InAppNotificationType resolveType({
    required String eventName,
    required Map<String, dynamic> payload,
  }) {
    final normalizedEvent = eventName.trim().toLowerCase();
    final status = (payload['status'] ?? payload['orderStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final notificationType =
        (payload['notificationType'] ?? payload['type'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    if (normalizedEvent.contains('cancel') ||
        notificationType.contains('cancel') ||
        status.contains('cancel')) {
      return InAppNotificationType.orderCancelled;
    }

    if (normalizedEvent.contains('assistant') ||
        normalizedEvent.contains('request') ||
        notificationType.contains('urgent') ||
        payload['urgent'] == true) {
      return InAppNotificationType.urgentRequest;
    }

    if (normalizedEvent.contains('payment') ||
        notificationType.contains('payment')) {
      return InAppNotificationType.payment;
    }

    final isReadyStatus = status == 'completed' ||
        status == 'ready' ||
        status == 'served' ||
        status == 'delivered';
    if (isReadyStatus || normalizedEvent.contains('ready')) {
      return InAppNotificationType.orderReady;
    }

    return InAppNotificationType.newOrder;
  }

  bool _mergeWithActiveOrQueued({
    required InAppNotificationType type,
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    required String orderId,
    required bool enableVibration,
    required DateTime now,
  }) {
    final active = currentNotification.value;
    if (active != null && active.orderId == orderId) {
      final mergedItem = active.copyWith(
        type: type,
        title: title,
        body: body,
        payload: Map<String, dynamic>.from(payload),
        createdAt: now,
        enableVibration: enableVibration,
        mergedCount: active.mergedCount + 1,
      );
      currentNotification.value = mergedItem;
      _scheduleAutoDismiss(mergedItem);
      return true;
    }

    if (_queue.isEmpty) {
      return false;
    }

    bool merged = false;
    final updatedQueue = <InAppNotificationItem>[];
    for (final item in _queue) {
      if (!merged && item.orderId == orderId) {
        merged = true;
        updatedQueue.add(
          item.copyWith(
            type: type,
            title: title,
            body: body,
            payload: Map<String, dynamic>.from(payload),
            createdAt: now,
            enableVibration: enableVibration,
            mergedCount: item.mergedCount + 1,
          ),
        );
      } else {
        updatedQueue.add(item);
      }
    }

    if (!merged) {
      return false;
    }

    _queue
      ..clear()
      ..addAll(updatedQueue);
    return true;
  }

  void _pumpQueue() {
    if (currentNotification.value != null || _queue.isEmpty) {
      return;
    }

    final next = _queue.removeFirst();
    currentNotification.value = next;
    _scheduleAutoDismiss(next);
    unawaited(_triggerVibration(next));
  }

  void _scheduleAutoDismiss(InAppNotificationItem item) {
    _dismissTimer?.cancel();
    _dismissTimer = null;

    final duration = item.type.autoDismissDuration;
    if (duration == null) {
      return;
    }

    _dismissTimer = Timer(duration, () {
      if (currentNotification.value?.id != item.id) {
        return;
      }
      dismissCurrent();
    });
  }

  Future<void> _triggerVibration(InAppNotificationItem item) async {
    if (!item.enableVibration || kIsWeb) {
      return;
    }

    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        await Vibration.vibrate(pattern: item.type.vibrationPattern);
        return;
      }

      await HapticFeedback.heavyImpact();
      await HapticFeedback.vibrate();
    } catch (_) {
      await HapticFeedback.heavyImpact();
      await HapticFeedback.vibrate();
    }
  }

  void _pruneOrderMergeCache(DateTime now) {
    _recentOrderEvents.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _orderMergeWindow,
    );
  }

  Route<dynamic>? _buildRoute(InAppNotificationItem item) {
    switch (item.type) {
      case InAppNotificationType.newOrder:
      case InAppNotificationType.orderReady:
      case InAppNotificationType.orderCancelled:
        return MaterialPageRoute<void>(
          builder: (_) => const OrdersScreen(
            showBackButton: true,
            initialTabIndex: 1,
          ),
        );
      case InAppNotificationType.payment:
        return MaterialPageRoute<void>(
          builder: (_) => const PaymentsScreen(),
        );
      case InAppNotificationType.urgentRequest:
        return MaterialPageRoute<void>(
          builder: (_) => const CustomerRequestsScreen(showBackButton: true),
        );
    }
  }
}
