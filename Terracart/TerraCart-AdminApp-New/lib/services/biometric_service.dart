import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Check if device supports biometric authentication
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  // Check if biometrics are available (enrolled and ready)
  Future<bool> isBiometricsAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  // Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  // Authenticate using biometrics
  Future<bool> authenticate({
    String reason = 'Authenticate to login to TeraCard Staff App',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) async {
    try {
      final isAvailable = await isBiometricsAvailable();
      if (!isAvailable) {
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          useErrorDialogs: useErrorDialogs,
          stickyAuth: stickyAuth,
          biometricOnly: true, // Only use biometrics, not device PIN/pattern
        ),
      );
    } catch (e) {
      return false;
    }
  }

  // Store credentials securely
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    try {
      await _secureStorage.write(
        key: 'biometric_email',
        value: email,
      );
      await _secureStorage.write(
        key: 'biometric_password',
        value: password,
      );
      await _secureStorage.write(
        key: 'biometric_enabled',
        value: 'true',
      );
    } catch (e) {
      // Handle error silently
    }
  }

  // Get stored credentials
  Future<Map<String, String?>> getStoredCredentials() async {
    try {
      final email = await _secureStorage.read(key: 'biometric_email');
      final password = await _secureStorage.read(key: 'biometric_password');
      return {
        'email': email,
        'password': password,
      };
    } catch (e) {
      return {'email': null, 'password': null};
    }
  }

  // Check if biometric login is enabled
  Future<bool> isBiometricEnabled() async {
    try {
      final enabled = await _secureStorage.read(key: 'biometric_enabled');
      return enabled == 'true';
    } catch (e) {
      return false;
    }
  }

  // Clear stored credentials
  Future<void> clearCredentials() async {
    try {
      await _secureStorage.delete(key: 'biometric_email');
      await _secureStorage.delete(key: 'biometric_password');
      await _secureStorage.delete(key: 'biometric_enabled');
    } catch (e) {
      // Handle error silently
    }
  }

  // Disable biometric login (keep credentials but mark as disabled)
  Future<void> disableBiometric() async {
    try {
      await _secureStorage.delete(key: 'biometric_enabled');
    } catch (e) {
      // Handle error silently
    }
  }
}

