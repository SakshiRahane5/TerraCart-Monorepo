import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import '../core/config/api_config.dart';
import '../core/utils/debouncer.dart';

class _SocketEndpoint {
  final String origin;
  final String path;

  const _SocketEndpoint({
    required this.origin,
    required this.path,
  });
}

class _SocketListenerEntry {
  final Function(dynamic) original;
  final Function(dynamic) wrapped;
  final bool persistent;
  final Debouncer? debouncer;
  final Throttler? throttler;

  _SocketListenerEntry({
    required this.original,
    required this.wrapped,
    required this.persistent,
    this.debouncer,
    this.throttler,
  });

  void disposeRateLimiter() {
    debouncer?.dispose();
    throttler?.dispose();
  }
}

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  String? _role;
  String? _cartId;
  String? _franchiseId;
  List<_SocketEndpoint> _candidateEndpoints = const <_SocketEndpoint>[];
  int _candidateEndpointIndex = 0;
  String? _authToken;
  bool _isSwitchingEndpoint = false;

  final Map<String, List<_SocketListenerEntry>> _listeners = {};

  bool get isConnected => _isConnected;

  void connect({
    String? token,
    String? role,
    String? cartId,
    String? franchiseId,
  }) {
    _role = role;
    _cartId = cartId;
    _franchiseId = franchiseId;
    _authToken = token;
    _candidateEndpoints = _buildCandidateEndpoints();
    _candidateEndpointIndex = 0;

    if (_socket != null && _isConnected) return;

    if (_socket != null && !_isConnected) {
      _socket?.dispose();
      _socket = null;
    }

    _connectToCurrentEndpoint();
  }

  List<_SocketEndpoint> _buildCandidateEndpoints() {
    final origins = <String>{ApiConfig.socketUrl};
    final canUseLoopbackFallback = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        ApiConfig.isLoopbackOrigin;

    if (canUseLoopbackFallback) {
      origins.addAll(ApiConfig.localOriginFallbacks);
    }

    const paths = <String>[
      '/socket.io',
      '/api/socket.io',
    ];

    final endpoints = <_SocketEndpoint>[];
    final seen = <String>{};
    for (final origin in origins) {
      final normalizedOrigin = origin.trim();
      if (normalizedOrigin.isEmpty) continue;
      for (final path in paths) {
        final normalizedPath = path.trim();
        if (normalizedPath.isEmpty) continue;
        final key = '$normalizedOrigin|$normalizedPath';
        if (seen.contains(key)) continue;
        seen.add(key);
        endpoints.add(_SocketEndpoint(
          origin: normalizedOrigin,
          path: normalizedPath,
        ));
      }
    }

    return endpoints.toList(growable: false);
  }

  void _connectToCurrentEndpoint() {
    if (_candidateEndpoints.isEmpty) {
      _candidateEndpoints = <_SocketEndpoint>[
        _SocketEndpoint(
          origin: ApiConfig.socketUrl,
          path: '/socket.io',
        ),
      ];
      _candidateEndpointIndex = 0;
    }

    final currentEndpoint = _candidateEndpoints[_candidateEndpointIndex];
    print(
        '[SOCKET] Connecting to ${currentEndpoint.origin} (path=${currentEndpoint.path})');

    _socket = IO.io(
      currentEndpoint.origin,
      IO.OptionBuilder()
          // Keep polling enabled for restrictive networks; upgrade to websocket when available.
          .setTransports(['polling', 'websocket'])
          .setPath(currentEndpoint.path)
          .enableReconnection()
          // Use socket.io default reconnection attempt policy (unbounded) instead of hard stop.
          // .setReconnectionAttempts(25)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(15000)
          .setTimeout(30000)
          // Send token via auth payload for websocket/polling parity.
          .setAuth({
            if (_authToken != null) 'token': 'Bearer $_authToken',
          })
          .enableAutoConnect()
          .build(),
    );

    _reattachListeners();

    _socket!.onConnect((_) {
      _isConnected = true;
      print(
          '[SOCKET] Connected on ${currentEndpoint.origin} (path=${currentEndpoint.path})');
      _joinRooms();
    });

    _socket!.on('reconnect', (_) {
      _isConnected = true;
      print('[SOCKET] Reconnected');
      _joinRooms();
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      print('[SOCKET] Disconnected');
    });

    _socket!.onConnectError((error) {
      _isConnected = false;
      print('[SOCKET] Connect error: $error');
      _tryNextEndpoint();
    });

    _socket!.onError((error) {
      _isConnected = false;
      print('[SOCKET] Error: $error');
    });
  }

  void _tryNextEndpoint() {
    if (_isSwitchingEndpoint) return;
    if (_candidateEndpointIndex + 1 >= _candidateEndpoints.length) return;

    _isSwitchingEndpoint = true;
    try {
      _candidateEndpointIndex += 1;
      final nextEndpoint = _candidateEndpoints[_candidateEndpointIndex];
      print(
          '[SOCKET] Retrying with fallback endpoint: ${nextEndpoint.origin} (path=${nextEndpoint.path})');
      _socket?.dispose();
      _socket = null;
      _connectToCurrentEndpoint();
    } finally {
      _isSwitchingEndpoint = false;
    }
  }

  void _reattachListeners() {
    if (_socket == null) return;
    _listeners.forEach((event, callbacks) {
      for (final entry in callbacks) {
        _socket!.on(event, entry.wrapped);
      }
    });
  }

  void _joinRooms() {
    if (_socket == null) return;
    if (_role != null && _role!.isNotEmpty) {
      _socket!.emit('join:role', _role);
    }
    if (_cartId != null && _cartId!.isNotEmpty) {
      _socket!.emit('join:cafe', _cartId);
      _socket!.emit('join:cart', _cartId);
    }
    if (_franchiseId != null && _franchiseId!.isNotEmpty) {
      _socket!.emit('join:franchise', _franchiseId);
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    dispose();
  }

  void on(
    String event,
    Function(dynamic) callback, {
    bool debounce = false,
    bool throttle = false,
    Duration? delay,
    bool persistent = false,
  }) {
    final Debouncer? eventDebouncer = debounce
        ? Debouncer(delay: delay ?? const Duration(milliseconds: 500))
        : null;
    final Throttler? eventThrottler = throttle
        ? Throttler(delay: delay ?? const Duration(milliseconds: 300))
        : null;

    final wrappedCallback = (dynamic data) {
      if (eventDebouncer != null) {
        eventDebouncer.call(() => callback(data));
      } else if (eventThrottler != null) {
        eventThrottler.call(() => callback(data));
      } else {
        callback(data);
      }
    };

    _listeners.putIfAbsent(event, () => []).add(
          _SocketListenerEntry(
            original: callback,
            wrapped: wrappedCallback,
            persistent: persistent,
            debouncer: eventDebouncer,
            throttler: eventThrottler,
          ),
        );
    _socket?.on(event, wrappedCallback);
  }

  void off(String event, [Function(dynamic)? callback]) {
    final listeners = _listeners[event];
    if (listeners == null || listeners.isEmpty) return;

    if (callback != null) {
      final toRemove = listeners
          .where(
            (entry) =>
                identical(entry.original, callback) ||
                identical(entry.wrapped, callback),
          )
          .toList();
      for (final entry in toRemove) {
        _socket?.off(event, entry.wrapped);
        entry.disposeRateLimiter();
        listeners.remove(entry);
      }
    } else {
      final toRemove = listeners.where((entry) => !entry.persistent).toList();
      for (final entry in toRemove) {
        _socket?.off(event, entry.wrapped);
        entry.disposeRateLimiter();
        listeners.remove(entry);
      }
    }

    if (listeners.isEmpty) {
      _listeners.remove(event);
    }
  }

  void dispose() {
    _listeners.forEach((event, callbacks) {
      for (final entry in callbacks) {
        _socket?.off(event, entry.wrapped);
        entry.disposeRateLimiter();
      }
    });
    _listeners.clear();
  }

  void emit(String event, [dynamic data]) {
    _socket?.emit(event, data);
  }
}
