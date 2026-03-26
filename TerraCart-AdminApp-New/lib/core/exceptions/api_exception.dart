class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final dynamic data;

  ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.data,
  });

  @override
  String toString() => message;

  factory ApiException.fromResponse(Map<String, dynamic> response) {
    return ApiException(
      message: response['message'] ?? 'An error occurred',
      statusCode: response['statusCode'],
      code: response['code'],
      data: response['data'],
    );
  }

  factory ApiException.networkError(String message) {
    return ApiException(
      message: message,
      code: 'NETWORK_ERROR',
    );
  }

  factory ApiException.unauthorized() {
    return ApiException(
      message: 'Unauthorized. Please login again.',
      statusCode: 401,
      code: 'UNAUTHORIZED',
    );
  }

  factory ApiException.forbidden() {
    return ApiException(
      message: 'Access denied. You don\'t have permission.',
      statusCode: 403,
      code: 'FORBIDDEN',
    );
  }

  factory ApiException.notFound() {
    return ApiException(
      message: 'Resource not found',
      statusCode: 404,
      code: 'NOT_FOUND',
    );
  }

  factory ApiException.serverError() {
    return ApiException(
      message: 'Server error. Please try again later.',
      statusCode: 500,
      code: 'SERVER_ERROR',
    );
  }
}

