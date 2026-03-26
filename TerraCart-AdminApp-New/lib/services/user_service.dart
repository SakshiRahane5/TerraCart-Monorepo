import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';

class UserService {
  final ApiService _api = ApiService();

  Map<String, dynamic> _normalizeEmergencyContact(Map<String, dynamic> source) {
    return {
      'name': source['name']?.toString() ?? '',
      'phone': source['phone']?.toString() ?? '',
      'relation': source['relation']?.toString() ?? '',
      'relationship': source['relationship']?.toString() ??
          source['relation']?.toString() ??
          '',
      'notes': source['notes']?.toString() ?? '',
      'email': source['email']?.toString() ?? '',
      'isPrimary': source['isPrimary'] == true,
    };
  }

  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    try {
      final response = await _api.get('/users/emergency-contacts');
      final data = response['data'] ?? response;
      final contacts = data is Map ? data['emergencyContacts'] : null;
      if (contacts is! List) {
        return const <Map<String, dynamic>>[];
      }

      return contacts
          .whereType<Map>()
          .map((c) => _normalizeEmergencyContact(Map<String, dynamic>.from(c)))
          .toList();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to get emergency contacts: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> updateEmergencyContacts(
      List<Map<String, dynamic>> contacts) async {
    try {
      final payloadContacts = contacts.map((contact) {
        final normalized = Map<String, dynamic>.from(contact);
        return {
          'name': normalized['name']?.toString() ?? '',
          'phone': normalized['phone']?.toString() ?? '',
          'relation': normalized['relation']?.toString() ??
              normalized['relationship']?.toString() ??
              '',
          'notes': normalized['notes']?.toString() ?? '',
          'isPrimary': normalized['isPrimary'] == true,
        };
      }).toList();

      final response = await _api.put(
        '/users/emergency-contacts',
        body: {'emergencyContacts': payloadContacts},
      );

      final data = response['data'] ?? response;
      final updatedContacts = data is Map ? data['emergencyContacts'] : null;
      if (updatedContacts is! List) {
        return payloadContacts
            .map((entry) => _normalizeEmergencyContact(entry))
            .toList();
      }

      return updatedContacts
          .whereType<Map>()
          .map((entry) =>
              _normalizeEmergencyContact(Map<String, dynamic>.from(entry)))
          .toList();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to update emergency contacts: ${e.toString()}');
    }
  }

  /// Fetch user/cart/cafe details by ID
  /// Returns address, location, and other details
  Future<Map<String, dynamic>> getUserById(String userId) async {
    try {
      print('[USER_SERVICE] Fetching user by ID: $userId');
      final response = await _api.get('/users/$userId');

      print('[USER_SERVICE] Response received: ${response.toString()}');

      // Handle both wrapped and direct response formats
      Map<String, dynamic> userData;
      if (response['success'] == true) {
        userData = response['data'] ?? response['user'] ?? response;
      } else if (response['_id'] != null || response['id'] != null) {
        // Direct user object response
        userData = response;
      } else {
        userData = {};
      }

      print(
          '[USER_SERVICE] Extracted user data - address: ${userData['address']}, location: ${userData['location']}');

      return userData;
    } catch (e) {
      print('[USER_SERVICE] Error fetching user: $e');
      if (e is ApiException) rethrow;
      throw ApiException(
          message: 'Failed to get user details: ${e.toString()}');
    }
  }
}
