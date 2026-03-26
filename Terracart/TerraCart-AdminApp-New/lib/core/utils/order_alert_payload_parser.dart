import 'dart:convert';

class OrderAlertPayloadParser {
  OrderAlertPayloadParser._();

  static const Set<String> socketAlertEvents = <String>{
    'order:created',
    'kot:created',
    'request:created',
  };

  static const Set<String> dataAlertEventNames = <String>{
    'order:created',
    'order_created',
    'new_order',
    'order:status:updated',
    'order_status_updated',
    'kot:created',
    'kot_created',
    'request:created',
    'request_created',
    'customer_request_created',
    'assistant_request_created',
    'request_assistant',
    'payment:created',
    'payment_created',
    'paymentcreated',
    'payment:updated',
    'payment_updated',
    'paymentupdated',
    'payment_request',
    'payment_request_created',
    'cart_broadcast',
  };

  static const List<String> _cartIdKeys = <String>[
    'cartId',
    'cafeId',
    'cart_id',
    'cafe_id',
  ];

  static const List<String> _entityIdKeys = <String>[
    'eventId',
    'event_id',
    'orderId',
    'requestId',
    'kotId',
    'paymentId',
    'payment_id',
    '_id',
    'id',
  ];

  static const List<String> _eventNameKeys = <String>[
    'event',
    'eventName',
    'type',
    'notificationType',
    'alertType',
  ];

  static const List<String> _idFallbackKeys = <String>[
    '_id',
    'id',
    'orderId',
    'requestId',
    'kotId',
    'paymentId',
    'cartId',
    'cafeId',
  ];

  static bool isSocketAlertEvent(String eventName) {
    final normalized = eventName.trim().toLowerCase();
    return socketAlertEvents.contains(normalized);
  }

  static String normalizeEventName(String eventName) {
    return eventName.trim().toLowerCase().replaceAll(' ', '_');
  }

  static Map<String, dynamic> normalizeDataPayload(
      Map<String, dynamic> rawData) {
    final normalized = <String, dynamic>{};
    for (final entry in rawData.entries) {
      normalized[entry.key] = _decodeJsonIfNeeded(entry.value);
    }

    const nestedKeys = <String>[
      'payload',
      'eventPayload',
      'data',
      'order',
      'request',
      'kot',
    ];
    for (final key in nestedKeys) {
      final nestedMap = _toMap(normalized[key]);
      if (nestedMap == null) {
        continue;
      }
      normalized[key] = nestedMap;
      for (final nestedEntry in nestedMap.entries) {
        normalized.putIfAbsent(nestedEntry.key, () => nestedEntry.value);
      }
    }

    return normalized;
  }

  static bool isOperationalAlertData(Map<String, dynamic> payload) {
    final normalized = normalizeDataPayload(payload);
    final eventName = extractEventName(normalized);
    if (eventName != null && dataAlertEventNames.contains(eventName)) {
      return true;
    }

    final eventHint = eventName ?? '';
    if (eventHint.contains('order') ||
        eventHint.contains('kot') ||
        eventHint.contains('request') ||
        eventHint.contains('assistant') ||
        eventHint.contains('payment')) {
      return true;
    }

    return extractEntityId(normalized) != null &&
        (normalized.containsKey('orderId') ||
            normalized.containsKey('requestId') ||
            normalized.containsKey('kotId') ||
            normalized.containsKey('paymentId'));
  }

  static bool isOrderAlertData(Map<String, dynamic> payload) {
    return isOperationalAlertData(payload);
  }

  static String? extractEventName(Map<String, dynamic> payload) {
    for (final key in _eventNameKeys) {
      final value = payload[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim().toLowerCase();
      if (text.isNotEmpty) {
        return normalizeEventName(text);
      }
    }
    return null;
  }

  static String? extractCartId(dynamic payload) {
    return _extractByKeys(payload, _cartIdKeys);
  }

  static String? extractEntityId(dynamic payload) {
    final direct = _extractByKeys(payload, _entityIdKeys);
    if (direct != null) {
      return direct;
    }

    final map = _toMap(payload);
    if (map == null) {
      return null;
    }

    for (final key in const <String>['order', 'request', 'kot']) {
      final nested = _extractByKeys(map[key], _entityIdKeys);
      if (nested != null) {
        return nested;
      }
    }

    return null;
  }

  static bool cartMatches({
    required String? currentCartId,
    required dynamic payload,
    bool allowMissingIncomingCart = false,
  }) {
    final current = currentCartId?.trim();
    if (current == null || current.isEmpty) {
      return false;
    }

    final incoming = extractCartId(payload)?.trim();
    if (incoming == null || incoming.isEmpty) {
      return allowMissingIncomingCart;
    }

    return incoming == current;
  }

  static String buildDedupeKey({
    required String eventName,
    required dynamic payload,
  }) {
    final entityId = extractEntityId(payload);
    if (entityId != null && entityId.isNotEmpty) {
      return 'entity:$entityId';
    }

    final cartId = extractCartId(payload);
    if (cartId != null && cartId.isNotEmpty) {
      return '${normalizeEventName(eventName)}:$cartId';
    }

    return normalizeEventName(eventName);
  }

  static String? _extractByKeys(
    dynamic payload,
    List<String> keys, {
    int depth = 0,
  }) {
    if (payload == null || depth > 7) {
      return null;
    }

    final map = _toMap(payload);
    if (map != null) {
      for (final key in keys) {
        final value = _stringifyIdentifier(map[key]);
        if (value != null) {
          return value;
        }
      }

      for (final value in map.values) {
        final nested = _extractByKeys(value, keys, depth: depth + 1);
        if (nested != null) {
          return nested;
        }
      }
      return null;
    }

    if (payload is List) {
      for (final item in payload) {
        final nested = _extractByKeys(item, keys, depth: depth + 1);
        if (nested != null) {
          return nested;
        }
      }
    }

    return null;
  }

  static String? _stringifyIdentifier(dynamic value) {
    if (value == null) {
      return null;
    }

    final decoded = _decodeJsonIfNeeded(value);
    if (decoded == null) {
      return null;
    }

    if (decoded is String) {
      final trimmed = decoded.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    if (decoded is num || decoded is bool) {
      return decoded.toString();
    }

    final nestedMap = _toMap(decoded);
    if (nestedMap != null) {
      for (final key in _idFallbackKeys) {
        final nestedValue = _stringifyIdentifier(nestedMap[key]);
        if (nestedValue != null) {
          return nestedValue;
        }
      }
    }

    return null;
  }

  static Map<String, dynamic>? _toMap(dynamic value) {
    if (value == null) {
      return null;
    }

    final decoded = _decodeJsonIfNeeded(value);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return null;
  }

  static dynamic _decodeJsonIfNeeded(dynamic value) {
    if (value is! String) {
      return value;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return value;
    }

    final looksLikeJsonObject =
        trimmed.startsWith('{') && trimmed.endsWith('}');
    final looksLikeJsonArray = trimmed.startsWith('[') && trimmed.endsWith(']');
    if (!looksLikeJsonObject && !looksLikeJsonArray) {
      return value;
    }

    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return value;
    }
  }
}
