import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';

class PrinterConfigService {
  final ApiService _api = ApiService();

  static const String _defaultBusinessName = 'TERRA CART';

  /// Get printer config for current user's cart.
  Future<Map<String, dynamic>> getPrinterConfig() async {
    try {
      final response = await _api.get(ApiConfig.printerConfig);
      final data = response['data'] ?? response;
      final rawAuthority =
          data['printAuthority']?.toString().trim().toUpperCase();
      final printAuthority = (rawAuthority == 'APP' || rawAuthority == 'AGENT')
          ? rawAuthority
          : 'APP';

      return {
        'printerIp': data['printerIp'] ?? '',
        'printerPort': (data['printerPort'] ?? 9100) as int,
        'businessName':
            data['businessName']?.toString().trim().isNotEmpty == true
                ? data['businessName'].toString().trim()
                : _defaultBusinessName,
        'kotHeaderText': data['kotHeaderText']?.toString() ?? '',
        'billHeaderText': data['billHeaderText']?.toString() ?? '',
        'centerAlign': data['centerAlign'] != false,
        'printAuthority': printAuthority,
      };
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Failed to get printer config: ${e.toString()}',
      );
    }
  }

  /// Save printer config.
  Future<Map<String, dynamic>> savePrinterConfig({
    required String printerIp,
    int printerPort = 9100,
    String businessName = _defaultBusinessName,
    String kotHeaderText = '',
    String billHeaderText = '',
    bool centerAlign = true,
  }) async {
    try {
      final response = await _api.put(
        ApiConfig.printerConfig,
        body: {
          'printerIp': printerIp.trim(),
          'printerPort': printerPort,
          'businessName': businessName.trim().isEmpty
              ? _defaultBusinessName
              : businessName.trim(),
          'kotHeaderText': kotHeaderText.trim(),
          'billHeaderText': billHeaderText.trim(),
          'centerAlign': centerAlign,
        },
      );
      final data = response['data'] ?? response;
      return {
        'printerIp': data['printerIp'] ?? printerIp,
        'printerPort': (data['printerPort'] ?? printerPort) as int,
        'businessName':
            data['businessName']?.toString().trim().isNotEmpty == true
                ? data['businessName'].toString().trim()
                : (businessName.trim().isEmpty
                    ? _defaultBusinessName
                    : businessName.trim()),
        'kotHeaderText':
            data['kotHeaderText']?.toString() ?? kotHeaderText.trim(),
        'billHeaderText':
            data['billHeaderText']?.toString() ?? billHeaderText.trim(),
        'centerAlign': data['centerAlign'] is bool
            ? data['centerAlign'] as bool
            : centerAlign,
      };
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Failed to save printer config: ${e.toString()}',
      );
    }
  }
}
