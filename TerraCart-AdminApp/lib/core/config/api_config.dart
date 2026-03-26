import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // Runtime .env override:
  // API_ORIGIN=http://192.168.x.x:5001
  //
  // Build-time fallback (if .env is missing):
  // --dart-define=DEV_PHYSICAL_DEVICE_BASE_URL=http://192.168.x.x:5001
  static const String devPhysicalDeviceBaseUrl = String.fromEnvironment(
    'DEV_PHYSICAL_DEVICE_BASE_URL',
    defaultValue: 'http://127.0.0.1:5001',
  );
  static const bool useProductionApi = bool.fromEnvironment(
    'USE_PROD_API',
    defaultValue: false,
  );
  static const String productionOrigin = 'https://api.terracart.in';

  static String get origin {
    final envOrigin =
        dotenv.isInitialized ? dotenv.env['API_ORIGIN']?.trim() : null;
    if (envOrigin != null && envOrigin.isNotEmpty) {
      return _trimTrailingSlash(envOrigin);
    }
    return _trimTrailingSlash(
      useProductionApi ? productionOrigin : devPhysicalDeviceBaseUrl,
    );
  }

  static String get baseUrl => '$origin/api';
  static String get socketUrl => origin;
  static String get healthUrl => '$origin/health';

  static bool get isLoopbackOrigin {
    final host = Uri.tryParse(origin)?.host.toLowerCase();
    return host == '127.0.0.1' || host == 'localhost';
  }

  static List<String> get localOriginFallbacks {
    if (!isLoopbackOrigin) return const <String>[];

    final current = Uri.tryParse(origin);
    if (current == null) return const <String>[];

    final fallbacks = <String>{};
    for (final host in const <String>['10.0.2.2', '10.0.3.2']) {
      final replaced = current.replace(host: host).toString();
      fallbacks.add(_trimTrailingSlash(replaced));
    }
    return fallbacks.toList(growable: false);
  }

  static String _trimTrailingSlash(String value) {
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  // Timeouts - Increased for mobile network connections
  static const Duration connectTimeout = Duration(seconds: 60);
  static const Duration receiveTimeout = Duration(seconds: 60);

  // API Endpoints
  // Mobile login endpoint (supports x-app-login: mobile header)
  static const String login = '/users/login';
  static const String signup = '/users/register-cafe-admin-public';
  static const String me = '/users/me';
  static const String logout = '/users/logout';
  static const String saveFcmToken = '/save-token';

  // Orders
  static const String orders = '/orders';
  static String orderById(String id) => '/orders/$id';
  static String updateOrderStatus(String id) => '/orders/$id/status';
  static String acceptOrder(String id) => '/orders/$id/accept';
  static String updatePrintStatus(String id) => '/orders/$id/print-status';
  static String claimPrintJob(String id) => '/orders/$id/print-claim';
  static String completePrintJob(String id) => '/orders/$id/print-complete';
  static String kotPrintTemplate(String id) => '/orders/$id/kot-print';
  static String addKOT(String id) => '/orders/$id/kot';
  static String addItemsToOrder(String id) => '/orders/$id/add-items';
  static String returnItems(String id) => '/orders/$id/return-items';
  static String convertToTakeaway(String id) =>
      '/orders/$id/convert-to-takeaway';
  static String deleteOrder(String id) => '/orders/$id';
  static String finalizeOrder(String id) => '/orders/$id/finalize';

  // Add-ons
  static const String publicAddons = '/addons/public';

  // Tables
  static const String tables = '/tables';
  static const String availableTables = '/tables/available';
  static String tableById(String id) => '/tables/$id';
  static String occupyTable(String id) => '/tables/$id/occupy';
  static const String tableDashboard = '/tables/dashboard/occupancy';

  // Inventory - costing-v2 only (manager-only in mobile app)
  static const String inventory = '/costing-v2/inventory';
  static const String inventoryConsume = '/costing-v2/inventory/consume';
  static const String inventoryReturn = '/costing-v2/inventory/return';
  static const String inventoryTransactions =
      '/costing-v2/inventory/transactions';
  static const String inventoryDirectPurchase =
      '/costing-v2/inventory/direct-purchase';
  static const String costingIngredients = '/costing-v2/ingredients';
  static const String costingWaste = '/costing-v2/waste';
  static const String costingSuppliers = '/costing-v2/suppliers';
  static const String costingPurchases = '/costing-v2/purchases';
  static const String inventoryStats = '/inventory/stats';
  static const String availableIngredients = '/inventory/available-ingredients';
  static String inventoryItem(String id) => '/inventory/$id';
  static String updateStock(String id) => '/inventory/$id/stock';
  static String costingIngredient(String id) => '/costing-v2/ingredients/$id';

  // Attendance
  static const String attendance = '/attendance';
  static const String todayAttendance = '/attendance/today';
  static const String pastAttendance = '/attendance/past';
  static const String checkIn = '/attendance/checkin';
  static const String checkOut = '/attendance/checkout';
  static const String attendanceStats = '/attendance/stats';
  static String startBreak(String id) => '/attendance/$id/start-break';
  static String endBreak(String id) => '/attendance/$id/end-break';
  static String checkout(String id) => '/attendance/$id/checkout';
  static String updateAttendanceStatus(String id) => '/attendance/$id/status';
  static String deleteAttendance(String id) => '/attendance/$id';

  // Employee Schedule
  static const String mySchedule = '/employee-schedule/my-schedule';

  // Leave Requests
  static const String leaveRequests = '/leave-requests';
  static const String myLeaveRequests = '/leave-requests/my';
  static String updateLeaveRequestStatus(String id) =>
      '/leave-requests/$id/status';

  // Tasks
  static const String tasks = '/tasks';
  static const String todayTasks = '/tasks/today';
  static const String taskStats = '/tasks/stats';
  static String taskById(String id) => '/tasks/$id';
  static String completeTask(String id) => '/tasks/$id/complete';

  // Customer Requests
  static const String customerRequests = '/customer-requests';
  static const String pendingRequests = '/customer-requests/pending';
  static String requestById(String id) => '/customer-requests/$id';
  static String acknowledgeRequest(String id) =>
      '/customer-requests/$id/acknowledge';
  static String resolveRequest(String id) => '/customer-requests/$id/resolve';

  // Compliance
  static const String compliance = '/compliance';
  static const String expiringCompliance = '/compliance/expiring';
  static const String complianceStats = '/compliance/stats';
  static String complianceById(String id) => '/compliance/$id';

  // KOT
  static const String kot = '/kot';
  static const String pendingKOTs = '/kot/pending';
  static const String kotStats = '/kot/stats';
  static String kotById(String id) => '/kot/$id';
  static String updateKOTStatus(String id) => '/kot/$id/status';

  // Dashboard
  static const String dashboardStats = '/dashboard/stats';
  static const String recentActivity = '/dashboard/recent-activity';
  static const String performance = '/dashboard/performance';

  // App update
  static const String appVersion = '/app/version';
  static String appApk(String version) => '/app/apk/$version';

  // Voice
  static const String voiceOrderTapToOrder = '/voice-order/tap-to-order';
  static const String voiceInventoryParse = '/voice-inventory/parse';
  static const String voiceCommandIntent = '/voice-command/intent';

  // Print recovery
  static const String pendingKotPrintJobs = '/print/pending-kots';

  // Payments (admin, franchise_admin, super_admin, manager)
  static const String payments = '/payments';
  static String paymentById(String id) => '/payments/$id';
  static String latestPaymentForOrder(String orderId) =>
      '/payments/order/$orderId/latest';
  static String markPaymentPaid(String id) => '/payments/$id/mark-paid';
  static String cancelPayment(String id) => '/payments/$id/cancel';
  static const String syncPaidPayments = '/payments/sync-paid';

  // Printer Config (manager only)
  static const String printerConfig = '/printer-config';

  // Employees
  static const String employees = '/employees';
  static String employeeById(String id) => '/employees/$id';
  static String employeeSchedule(String id) =>
      '/employee-schedule/employee/$id';
}
