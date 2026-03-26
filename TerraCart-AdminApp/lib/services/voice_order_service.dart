import '../core/config/api_config.dart';
import '../core/exceptions/api_exception.dart';
import '../core/services/api_service.dart';

class VoiceOrderService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> parseTapToOrder({
    required String transcript,
    required List<String> menuItems,
    required String locale,
  }) async {
    final normalizedTranscript = transcript.trim();
    if (normalizedTranscript.isEmpty) {
      throw ApiException(message: 'Voice transcript is empty.');
    }

    final cleanedMenuItems = menuItems
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (cleanedMenuItems.isEmpty) {
      throw ApiException(message: 'Menu is not loaded for voice ordering.');
    }

    try {
      final response = await _api.post(
        ApiConfig.voiceOrderTapToOrder,
        body: {
          'transcript': normalizedTranscript,
          'menuItems': cleanedMenuItems,
          'locale': locale.trim().isEmpty ? 'en-IN' : locale.trim(),
        },
      );

      final itemsRaw = response['items'];
      final parsedItems = <Map<String, dynamic>>[];
      if (itemsRaw is List) {
        for (final entry in itemsRaw) {
          if (entry is Map) {
            parsedItems.add(Map<String, dynamic>.from(entry));
          }
        }
      }

      final notFoundRaw = response['notFound'];
      final notFound = <String>[];
      if (notFoundRaw is List) {
        for (final entry in notFoundRaw) {
          final text = entry.toString().trim();
          if (text.isNotEmpty) notFound.add(text);
        }
      }

      return {
        'originalText':
            (response['originalText'] ?? normalizedTranscript).toString(),
        'language': response['language']?.toString().trim().toLowerCase(),
        'ttsLocale': response['ttsLocale']?.toString().trim(),
        'parsedCommand': response['parsedCommand'],
        'action':
            (response['action'] ?? 'NONE').toString().trim().toUpperCase(),
        'assistantReply': (response['assistantReply'] ?? '').toString().trim(),
        'items': parsedItems,
        'notFound': notFound,
      };
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Voice order parsing failed: ${e.toString()}');
    }
  }
}
