import '../core/config/api_config.dart';
import '../core/exceptions/api_exception.dart';
import '../core/services/api_service.dart';

class VoiceInventoryService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> parseVoiceInventory({
    required String text,
  }) async {
    final transcript = text.trim();
    if (transcript.isEmpty) {
      throw ApiException(message: 'Voice transcript is empty.');
    }

    try {
      final response = await _api.post(
        ApiConfig.voiceInventoryParse,
        body: {
          'text': transcript,
        },
      );

      final detectedRaw = response['detected'];
      final itemsRaw = response['items'];
      if (detectedRaw is Map) {
        final parsedItems = <Map<String, dynamic>>[];
        if (itemsRaw is List) {
          for (final entry in itemsRaw) {
            if (entry is Map) {
              parsedItems.add(Map<String, dynamic>.from(entry));
            }
          }
        }

        return {
          'success': response['success'] == true,
          'originalText': (response['originalText'] ?? text).toString(),
          'language': response['language']?.toString().trim(),
          'ttsLocale': response['ttsLocale']?.toString().trim(),
          'action': response['action']?.toString(),
          'assistantReply': (response['assistantReply'] ?? '').toString(),
          'detected': Map<String, dynamic>.from(detectedRaw),
          'items': parsedItems,
          'warnings': response['warnings'],
          'requiresConfirmation': response['requiresConfirmation'] == true,
        };
      }

      throw ApiException(
        message: response['message']?.toString() ??
            'Unable to parse inventory voice command.',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Voice inventory parsing failed: ${e.toString()}',
      );
    }
  }
}
