import 'dart:async';

class VoiceCommandTarget {
  static const String orders = 'orders';
  static const String inventory = 'inventory';
}

class VoiceCommandEvent {
  VoiceCommandEvent({
    required this.target,
    required this.transcript,
    this.localeId,
    this.autoPlace = false,
  });

  final String target;
  final String transcript;
  final String? localeId;
  final bool autoPlace;
}

class VoiceCommandBus {
  VoiceCommandBus._internal();
  static final VoiceCommandBus _instance = VoiceCommandBus._internal();
  factory VoiceCommandBus() => _instance;

  final StreamController<VoiceCommandEvent> _controller =
      StreamController<VoiceCommandEvent>.broadcast();

  Stream<VoiceCommandEvent> get stream => _controller.stream;

  void emit(VoiceCommandEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }
}
