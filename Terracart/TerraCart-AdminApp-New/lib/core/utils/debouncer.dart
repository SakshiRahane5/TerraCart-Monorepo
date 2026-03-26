import 'dart:async';

/// Debouncer utility to limit the rate of function calls
/// Useful for preventing rapid socket event triggers
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 500)});

  void call(void Function() callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Throttler utility to limit function calls to at most once per duration
/// Useful for rate-limiting socket event handlers
class Throttler {
  final Duration delay;
  DateTime? _lastCall;
  Timer? _pendingTimer;
  void Function()? _pendingCallback;

  Throttler({this.delay = const Duration(milliseconds: 300)});

  void call(void Function() callback) {
    final now = DateTime.now();
    
    if (_lastCall == null || now.difference(_lastCall!) >= delay) {
      // Execute immediately
      _lastCall = now;
      callback();
    } else {
      // Schedule for later
      _pendingCallback = callback;
      _pendingTimer?.cancel();
      final remaining = delay - now.difference(_lastCall!);
      _pendingTimer = Timer(remaining, () {
        _lastCall = DateTime.now();
        final cb = _pendingCallback;
        _pendingCallback = null;
        cb?.call();
      });
    }
  }

  void dispose() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingCallback = null;
  }
}

