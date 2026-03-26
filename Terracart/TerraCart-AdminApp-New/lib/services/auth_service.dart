import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';
import '../models/user_model.dart';

class AuthService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? role,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      print('[AUTH] Attempting login for: $email');
      print('[AUTH] API Base URL: ${ApiConfig.baseUrl}');
      print('[AUTH] Login Endpoint: ${ApiConfig.login}');

      // Always perform login without carrying over any previous auth header.
      await _api.setToken(null);

      // Send mobile header for mobile app login
      final response = await _api.post(
        ApiConfig.login,
        body: {
          'email': normalizedEmail,
          'password': password,
          if (role != null) 'role': role,
        },
        customHeaders: {
          'x-app-login': 'mobile', // Identify this as mobile app login
        },
        includeAuth: false,
      );

      print('[AUTH] Login response received: ${response.toString()}');

      // Backend can return success or just token directly
      final hasSuccess = response['success'] == true;
      final hasToken = response['token'] != null;

      if (hasToken || hasSuccess) {
        final token = response['token'];
        if (token == null) {
          print('[AUTH] ERROR: No token in response');
          throw ApiException(message: 'Invalid response: missing token');
        }

        // Parse user data - backend returns user object nested or at root level
        Map<String, dynamic>? userData = response['user'] ?? response['data'];

        // If no nested user, check if response itself has user fields
        if (userData == null && response['_id'] != null) {
          userData = {
            '_id': response['_id'],
            'name': response['name'],
            'email': response['email'],
            'role': response['role'],
            'cartId': response['user']?['cartId'] ??
                response['cartId'] ??
                response['user']?['cafeId'] ??
                response['cafeId'], // Support both for backward compatibility
            'franchiseId':
                response['user']?['franchiseId'] ?? response['franchiseId'],
          };
        }

        if (userData == null) {
          print('[AUTH] ERROR: No user data in response');
          print('[AUTH] Full response: $response');
          throw ApiException(message: 'Invalid response: missing user data');
        }

        final responseEmail =
            (userData['email'] ?? '').toString().trim().toLowerCase();
        if (responseEmail.isNotEmpty && responseEmail != normalizedEmail) {
          print(
            '[AUTH] ERROR: Email mismatch. requested=$normalizedEmail response=$responseEmail',
          );
          throw ApiException(
            message:
                'Login identity mismatch detected. Please try again. If this persists, contact admin.',
          );
        }

        print('[AUTH] User data: $userData');
        final user = UserModel.fromJson(userData);
        await _api.setToken(token.toString());

        return {
          'success': true,
          'user': user,
          'token': token,
        };
      }

      final errorMsg = response['message'] ?? 'Login failed';
      print('[AUTH] Login failed: $errorMsg');
      throw ApiException(message: errorMsg);
    } catch (e) {
      print('[AUTH] Login exception: ${e.toString()}');
      await _api.setToken(null);
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Login failed: ${e.toString()}');
    }
  }

  Future<UserModel> getCurrentUser() async {
    try {
      final response = await _api.get(ApiConfig.me);

      // Handle both response formats: { success: true, user: {...} } or direct user object
      Map<String, dynamic>? userData;

      if (response['success'] == true) {
        userData = response['user'] ?? response['data'];
      } else if (response['_id'] != null || response['id'] != null) {
        // Direct user object (legacy format)
        userData = response;
      }

      if (userData == null) {
        throw ApiException(message: 'Invalid response: missing user data');
      }

      return UserModel.fromJson(userData);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get user: ${e.toString()}');
    }
  }

  Future<void> logout() async {
    try {
      await _api.post(ApiConfig.logout);
    } catch (e) {
      // Even if logout fails on server, clear local token
    } finally {
      await _api.setToken(null);
    }
  }

  Future<Map<String, dynamic>> signup({
    required String name,
    required String email,
    required String password,
    required String cartName,
    required String location,
    String? phone,
    String? role,
    String? franchiseId,
    String? address,
  }) async {
    try {
      final response = await _api.post(
        ApiConfig.signup,
        body: {
          'name': name,
          'email': email,
          'password': password,
          'cartName': cartName,
          'location': location,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (role != null) 'role': role,
          if (franchiseId != null && franchiseId.isNotEmpty)
            'franchiseId': franchiseId,
          if (address != null && address.isNotEmpty) 'address': address,
        },
        includeAuth: false,
      );

      if (response['success'] == true) {
        // If signup returns a token, store it
        if (response['token'] != null) {
          await _api.setToken(response['token']);
        }

        // Parse user data if available
        UserModel? user;
        if (response['user'] != null || response['data'] != null) {
          final userData = response['user'] ?? response['data'];
          user = UserModel.fromJson(userData);
        }

        return {
          'success': true,
          'user': user,
          'token': response['token'],
          'message': response['message'] ?? 'Signup successful',
        };
      }

      throw ApiException(
        message: response['message'] ?? 'Signup failed',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Signup failed: ${e.toString()}');
    }
  }

  bool get isAuthenticated => _api.token != null;
}
