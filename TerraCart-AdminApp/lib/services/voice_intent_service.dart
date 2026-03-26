import '../core/config/api_config.dart';
import '../core/exceptions/api_exception.dart';
import '../core/services/api_service.dart';

class VoiceIntentService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> detectIntent({
    required String transcript,
    String? role,
    String? currentPage,
  }) async {
    final text = transcript.trim();
    if (text.isEmpty) {
      throw ApiException(message: 'Voice transcript is empty.');
    }

    try {
      final response = await _api.post(
        ApiConfig.voiceCommandIntent,
        body: {
          'text': text,
          if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
          if (currentPage != null && currentPage.trim().isNotEmpty)
            'currentPage': currentPage.trim(),
        },
      );

      if (response['success'] == true) {
        return Map<String, dynamic>.from(response);
      }

      throw ApiException(
        message: response['message']?.toString() ??
            'Unable to detect voice command intent.',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Voice command intent detection failed: ${e.toString()}',
      );
    }
  }
}
