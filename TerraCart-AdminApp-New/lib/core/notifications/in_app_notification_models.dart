import 'package:flutter/material.dart';

enum InAppNotificationType {
  newOrder,
  orderReady,
  payment,
  urgentRequest,
  orderCancelled,
}

class InAppNotificationItem {
  const InAppNotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    required this.createdAt,
    required this.enableVibration,
    this.orderId,
    this.mergedCount = 1,
  });

  final String id;
  final InAppNotificationType type;
  final String title;
  final String body;
  final String? orderId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final bool enableVibration;
  final int mergedCount;

  InAppNotificationItem copyWith({
    String? id,
    InAppNotificationType? type,
    String? title,
    String? body,
    String? orderId,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    bool? enableVibration,
    int? mergedCount,
  }) {
    return InAppNotificationItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      orderId: orderId ?? this.orderId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      enableVibration: enableVibration ?? this.enableVibration,
      mergedCount: mergedCount ?? this.mergedCount,
    );
  }
}

extension InAppNotificationTypeStyle on InAppNotificationType {
  Color get backgroundColor {
    switch (this) {
      case InAppNotificationType.newOrder:
        return const Color(0xFF0B57D0);
      case InAppNotificationType.orderReady:
        return const Color(0xFF2E7D32);
      case InAppNotificationType.payment:
        return const Color(0xFFF9A825);
      case InAppNotificationType.urgentRequest:
        return const Color(0xFFD32F2F);
      case InAppNotificationType.orderCancelled:
        return const Color(0xFF6D4C41);
    }
  }

  IconData get icon {
    switch (this) {
      case InAppNotificationType.newOrder:
        return Icons.receipt_long;
      case InAppNotificationType.orderReady:
        return Icons.task_alt;
      case InAppNotificationType.payment:
        return Icons.payments;
      case InAppNotificationType.urgentRequest:
        return Icons.priority_high;
      case InAppNotificationType.orderCancelled:
        return Icons.cancel;
    }
  }

  List<int> get vibrationPattern {
    switch (this) {
      case InAppNotificationType.newOrder:
        return const <int>[0, 180, 110, 180];
      case InAppNotificationType.orderReady:
        return const <int>[0, 120, 80, 120, 80, 120];
      case InAppNotificationType.payment:
        return const <int>[0, 250, 150, 250];
      case InAppNotificationType.urgentRequest:
        return const <int>[0, 400, 120, 400, 120, 400];
      case InAppNotificationType.orderCancelled:
        return const <int>[0, 80, 60, 80, 60, 200];
    }
  }

  Duration? get autoDismissDuration {
    switch (this) {
      case InAppNotificationType.urgentRequest:
        return null;
      case InAppNotificationType.newOrder:
        return const Duration(seconds: 4);
      case InAppNotificationType.orderReady:
        return const Duration(seconds: 5);
      case InAppNotificationType.payment:
        return const Duration(seconds: 6);
      case InAppNotificationType.orderCancelled:
        return const Duration(seconds: 5);
    }
  }
}
