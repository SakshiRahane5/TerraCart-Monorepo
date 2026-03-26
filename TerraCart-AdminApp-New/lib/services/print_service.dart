import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/preference_keys.dart';
import '../core/exceptions/api_exception.dart';
import '../core/utils/order_status_utils.dart';
import '../utils/esc_pos_formatter.dart';
import 'order_service.dart';
import 'payment_service.dart';
import 'printer_config_service.dart';
import 'socket_service.dart';
import 'user_service.dart';

/// Auto KOT and BILL printing service.
/// Runs on manager session only to avoid duplicate device prints.
/// KOT prints on order creation; BILL prints when order is paid/closed.
class PrintService {
  static final PrintService _instance = PrintService._internal();
  factory PrintService() => _instance;
  PrintService._internal();

  final SocketService _socket = SocketService();
  final OrderService _orderService = OrderService();
  final PaymentService _paymentService = PaymentService();
  final PrinterConfigService _printerConfig = PrinterConfigService();
  final UserService _userService = UserService();

  bool _isRunning = false;

  /// When false (printAuthority == AGENT), do not attempt KOT print; Local Print Bridge is the authority.
  /// Defaults to true (APP) so KOT printing works until overridden by explicit AGENT config.
  bool _kotPrintAuthorityApp = true;
  Map<String, dynamic>? _cachedPrinterConfig;
  static const List<int> _retryDelays = [2000, 4000, 8000]; // ms
  static const Duration _pendingKotRecoveryInterval = Duration(seconds: 4);

  /// Tracks KOT print jobs by "orderId:kotIndex" so duplicate events don't print twice.
  final Set<String> _kotPrintInProgress = {};
  final Set<String> _billPrintInProgress = {};
  static const String _autoPrinterId = 'kitchen-primary';
  Timer? _pendingKotRecoveryTimer;
  bool _isRecoveringPendingKots = false;

  // Stored references so we can unregister exactly these callbacks on stop().
  late final Function(dynamic) _boundPrinterKotPending =
      _onPrinterKotPendingEvent;
  late final Function(dynamic) _boundOrderCreatedForKot = _onOrderCreatedForKot;
  late final Function(dynamic) _boundOrderStatusEvent = _onOrderStatusEvent;
  late final Function(dynamic) _boundPaymentUpdated = _onPaymentUpdated;

  bool get isRunning => _isRunning;

  /// Stable device id for claim/complete so only one device prints when multiple are online.
  Future<String> _getOrCreatePrintDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(PreferenceKeys.printDeviceId)?.trim();
    if (id != null && id.isNotEmpty) return id;
    id = const Uuid().v4();
    await prefs.setString(PreferenceKeys.printDeviceId, id);
    return id;
  }

  /// Start listening and auto-printing.
  /// Primary KOT trigger: printer:kot:pending. Fallback: order:created / kot:created.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _cachedPrinterConfig = null;
    _kotPrintAuthorityApp = true;

    _socket.on('printer:kot:pending', _boundPrinterKotPending);
    _socket.on('order:created', _boundOrderCreatedForKot);
    _socket.on('order:upsert', _boundOrderCreatedForKot);
    _socket.on('kot:created', _boundOrderCreatedForKot);
    _socket.on('order_status_updated', _boundOrderStatusEvent);
    _socket.on('paymentUpdated', _boundPaymentUpdated);

    _refreshPrintAuthority();
    _startPendingKotRecovery();
    print(
        '[PRINT] PrintService started (KOT via printer:kot:pending + order:created/order:upsert/kot:created fallback)');
  }

  /// Stop listening. Call on logout.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _socket.off('printer:kot:pending', _boundPrinterKotPending);
    _socket.off('order:created', _boundOrderCreatedForKot);
    _socket.off('order:upsert', _boundOrderCreatedForKot);
    _socket.off('kot:created', _boundOrderCreatedForKot);
    _socket.off('order_status_updated', _boundOrderStatusEvent);
    _socket.off('paymentUpdated', _boundPaymentUpdated);
    _cachedPrinterConfig = null;
    _kotPrintInProgress.clear();
    _billPrintInProgress.clear();
    _pendingKotRecoveryTimer?.cancel();
    _pendingKotRecoveryTimer = null;
    _isRecoveringPendingKots = false;
    print('[PRINT] PrintService stopped');
  }

  Future<void> _refreshPrintAuthority() async {
    try {
      _cachedPrinterConfig = null;
      final config = await _printerConfig.getPrinterConfig();
      final authority =
          config['printAuthority']?.toString().trim().toUpperCase();
      _kotPrintAuthorityApp = authority != 'AGENT';
      if (!_kotPrintAuthorityApp) {
        print(
            '[PRINT] printAuthority is AGENT - KOT printing handled by Local Print Bridge only');
      } else {
        print(
            '[PRINT] printAuthority is APP - Flutter app will handle KOT printing');
      }
    } catch (e) {
      _kotPrintAuthorityApp = true;
      print('[PRINT] Could not load printAuthority (defaulting to APP): $e');
    }
  }

  void _startPendingKotRecovery() {
    _pendingKotRecoveryTimer?.cancel();
    _pendingKotRecoveryTimer = Timer.periodic(_pendingKotRecoveryInterval, (_) {
      _recoverPendingKotJobs();
    });
    // Run one recovery shortly after startup to catch missed events.
    Future.delayed(const Duration(seconds: 1), _recoverPendingKotJobs);
  }

  /// Trigger an immediate pending KOT recovery pass (best-effort).
  void triggerPendingKotRecovery() {
    if (!_isRunning || !_kotPrintAuthorityApp) return;
    _recoverPendingKotJobs();
  }

  Future<void> _recoverPendingKotJobs() async {
    if (!_isRunning || !_kotPrintAuthorityApp) return;
    if (_isRecoveringPendingKots) return;

    _isRecoveringPendingKots = true;
    try {
      final pendingJobs = await _orderService.getPendingKotPrintJobs();
      if (pendingJobs.isEmpty) return;

      for (final job in pendingJobs) {
        final orderId = job['orderId']?.toString().trim() ?? '';
        final printKey = job['printKey']?.toString().trim() ?? '';
        final rawKotIndex = job['kotIndex'];
        final kotIndex = rawKotIndex is int
            ? rawKotIndex
            : int.tryParse(rawKotIndex?.toString() ?? '');

        if (orderId.isEmpty || printKey.isEmpty || kotIndex == null) {
          continue;
        }
        _maybePrintSingleKot(orderId, kotIndex, printKey);
      }
    } catch (e) {
      // Keep this silent-ish; recovery should be best-effort.
      print('[PRINT] Pending KOT recovery failed: $e');
    } finally {
      _isRecoveringPendingKots = false;
    }
  }

  /// Primary KOT trigger from printer:kot:pending. Payload: orderId, kotIndex, cartId, printKey.
  void _onPrinterKotPendingEvent(dynamic data) {
    if (!_isRunning || !_kotPrintAuthorityApp) return;
    if (data is! Map) return;
    final m = Map<String, dynamic>.from(data);
    final orderId =
        m['orderId']?.toString().trim() ?? m['_id']?.toString().trim();
    final kotIndexRaw = m['kotIndex'];
    final kotIndex = kotIndexRaw is int
        ? kotIndexRaw
        : int.tryParse(kotIndexRaw?.toString() ?? '');
    final printKey = m['printKey']?.toString().trim();
    if (orderId == null ||
        orderId.isEmpty ||
        kotIndex == null ||
        kotIndex < 0 ||
        printKey == null ||
        printKey.isEmpty) {
      return;
    }
    print(
        '[PRINT] printer:kot:pending received for $orderId KOT #${kotIndex + 1}');
    _orderCartIdMatchesCurrentUser(m).then((matches) {
      if (_isRunning && matches) {
        _maybePrintSingleKot(orderId, kotIndex, printKey);
      }
    });
  }

  /// Fallback KOT trigger from order:created / kot:created events.
  /// Fetches the order and prints any pending KOT lines via the claim flow.
  void _onOrderCreatedForKot(dynamic data) {
    if (!_isRunning || !_kotPrintAuthorityApp) return;
    final orderMap = _toOrderMap(data);
    final orderId = (orderMap?['_id'] ?? orderMap?['orderId'])?.toString();
    if (orderId == null || orderId.isEmpty) return;

    _orderCartIdMatchesCurrentUser(orderMap).then((matches) {
      if (_isRunning && matches) {
        _maybePrintAllPendingKots(orderId);
      }
    });
  }

  /// Fetch order and print ALL pending KOT lines (fallback path from order:created/kot:created).
  void _maybePrintAllPendingKots(String orderId) {
    if (orderId.isEmpty) return;
    // Wait briefly so the primary printer:kot:pending path claims first.
    Future.delayed(const Duration(milliseconds: 800), () async {
      if (!_isRunning || !_kotPrintAuthorityApp) return;
      try {
        final order = await _fetchOrderForPrint(orderId);
        if (order == null) return;
        final status = (order['status']?.toString() ?? '').trim().toUpperCase();
        final kotStatuses = {'NEW', 'PREPARING'};
        if (!kotStatuses.contains(status) || !_hasKotLines(order)) return;

        final kotLines = order['kotLines'] as List<dynamic>? ?? [];
        final pendingIndices = _pendingKotIndices(order);
        // Skip any KOT indices already being handled by the primary path.
        final toProcess = pendingIndices
            .where((i) => !_kotPrintInProgress.contains('$orderId:$i'))
            .toList();
        if (toProcess.isEmpty) return;

        for (final i in toProcess) {
          final key = '$orderId:$i';
          if (_kotPrintInProgress.contains(key)) continue;
          _kotPrintInProgress.add(key);
          try {
            final kot = kotLines[i] is Map
                ? Map<String, dynamic>.from(kotLines[i] as Map)
                : <String, dynamic>{};
            final linePrintKey = kot['printKey']?.toString().trim();
            if (linePrintKey != null && linePrintKey.isNotEmpty) {
              await _printSingleKot(order, i, linePrintKey);
            }
          } finally {
            Future.delayed(const Duration(seconds: 5), () {
              _kotPrintInProgress.remove(key);
            });
          }
        }
      } catch (e) {
        print('[PRINT] Fallback KOT print error for $orderId: $e');
      }
    });
  }

  /// Returns true if order's cartId matches current user's cartId, or if either is missing (allow).
  Future<bool> _orderCartIdMatchesCurrentUser(
      Map<String, dynamic>? orderMap) async {
    if (orderMap == null) return true;
    final orderCartId = _extractCartId(orderMap['cartId']);
    if (orderCartId == null || orderCartId.isEmpty) return true;

    final prefs = await SharedPreferences.getInstance();
    final userCartId = prefs.getString(PreferenceKeys.userCartId)?.trim();
    if (userCartId == null || userCartId.isEmpty) return true;

    final match = orderCartId == userCartId;
    if (!match) {
      print(
          '[PRINT] Skipping KOT print - order cartId ($orderCartId) does not match user cartId ($userCartId)');
    }
    return match;
  }

  String? _extractCartId(dynamic cartIdValue) {
    if (cartIdValue == null) return null;
    if (cartIdValue is String) return cartIdValue.trim();
    if (cartIdValue is Map) {
      final id = cartIdValue['_id'] ?? cartIdValue['id'];
      return id?.toString().trim();
    }
    return cartIdValue.toString().trim();
  }

  void _onOrderStatusEvent(dynamic data) {
    if (!_isRunning) return;
    final orderMap = _toOrderMap(data);
    final orderId = orderMap?['_id']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    _maybePrintBill(orderId);
  }

  void _onPaymentUpdated(dynamic data) {
    if (!_isRunning) return;
    final payment = data is Map ? Map<String, dynamic>.from(data) : null;
    if (payment == null) return;
    if (payment['status'] != 'PAID') return;

    final orderId = payment['orderId']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    _fetchAndPrintBill(orderId);
  }

  Map<String, dynamic>? _toOrderMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Map<String, dynamic>?> _getPrinterConfig() async {
    if (_cachedPrinterConfig != null) {
      final ip = _cachedPrinterConfig!['printerIp']?.toString() ?? '';
      if (ip.isNotEmpty) return _cachedPrinterConfig;
    }
    try {
      _cachedPrinterConfig = await _printerConfig.getPrinterConfig();
      final ip = _cachedPrinterConfig!['printerIp']?.toString() ?? '';
      if (ip.isEmpty) {
        print('[PRINT] No printer config - manager must set IP in Settings');
        return null;
      }
      return _cachedPrinterConfig;
    } catch (e) {
      print('[PRINT] Failed to get printer config: $e');
      return null;
    }
  }

  /// Fetch latest order from API to avoid duplicate prints when multiple roles receive same event.
  Future<Map<String, dynamic>?> _fetchOrderForPrint(String orderId) async {
    try {
      final order = await _orderService.getOrderById(orderId);
      final m = order.toJson();
      m['_id'] = order.id;
      m['status'] = order.status;
      m['printStatus'] = {
        'kotPrinted': order.kotPrinted,
        'billPrinted': order.billPrinted,
        'lastPrintedKotIndex': order.lastPrintedKotIndex,
      };
      return m;
    } catch (_) {
      return null;
    }
  }

  /// Single KOT print from printer:kot:pending payload (orderId, kotIndex, printKey).
  void _maybePrintSingleKot(String orderId, int kotIndex, String printKey) {
    if (orderId.isEmpty || printKey.isEmpty) return;
    final progressKey = '$orderId:$kotIndex';
    if (_kotPrintInProgress.contains(progressKey)) return;

    _kotPrintInProgress.add(progressKey);
    () async {
      try {
        final order = await _fetchOrderForPrint(orderId);
        if (order == null) return;
        await _printSingleKot(order, kotIndex, printKey);
      } finally {
        Future.delayed(const Duration(seconds: 5), () {
          _kotPrintInProgress.remove(progressKey);
        });
      }
    }();
  }

  void _maybePrintBill(String orderId) {
    if (orderId.isEmpty) return;
    if (_billPrintInProgress.contains(orderId)) return;

    _billPrintInProgress.add(orderId);
    () async {
      try {
        final order = await _fetchOrderForPrint(orderId);
        if (order == null) return;
        final status = (order['status']?.toString() ?? '').trim().toUpperCase();
        final paymentStatus = order['paymentStatus']?.toString() ?? '';
        final billPrinted = _getBool(order, 'printStatus', 'billPrinted');
        final paymentConfirmed = paymentStatus.toUpperCase() == 'PAID' ||
            order['isPaid'] == true;
        final isSettled =
            OrderStatusUtils.normalizeStatus(status) ==
                OrderStatusUtils.statusServed &&
            paymentConfirmed;
        if (isSettled &&
            paymentConfirmed &&
            !billPrinted &&
            _hasKotLines(order)) {
          await _printBill(order, updateStatus: true);
        }
      } finally {
        _billPrintInProgress.remove(orderId);
      }
    }();
  }

  Future<void> _fetchAndPrintBill(String orderId) async {
    if (_billPrintInProgress.contains(orderId)) return;
    try {
      final order = await _orderService.getOrderById(orderId);
      final status = order.status.trim().toUpperCase();
      final paymentConfirmed =
          order.paymentStatus.trim().toUpperCase() == 'PAID' || order.isPaid;
      final isSettled =
          OrderStatusUtils.normalizeStatus(status) ==
              OrderStatusUtils.statusServed &&
          paymentConfirmed;
      if (!isSettled ||
          !paymentConfirmed ||
          order.billPrinted ||
          order.kotLines.isEmpty) {
        return;
      }
      _billPrintInProgress.add(orderId);
      final orderMap = order.toJson();
      orderMap['_id'] = order.id;
      orderMap['printStatus'] = {
        'kotPrinted': order.kotPrinted,
        'billPrinted': order.billPrinted,
      };
      try {
        await _printBill(orderMap, updateStatus: true);
      } finally {
        _billPrintInProgress.remove(orderId);
      }
    } catch (e) {
      _billPrintInProgress.remove(orderId);
      print('[PRINT] Failed to fetch order for bill: $e');
    }
  }

  bool _getBool(Map<String, dynamic> m, String key1, String key2) {
    final inner = m[key1];
    if (inner is Map && inner[key2] == true) return true;
    return false;
  }

  int _getLastPrintedKotIndex(Map<String, dynamic> order) {
    final inner = order['printStatus'];
    if (inner is! Map) return -1;
    final v = inner['lastPrintedKotIndex'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return -1;
  }

  bool _hasKotLines(Map<String, dynamic> order) {
    final lines = order['kotLines'];
    return lines is List && lines.isNotEmpty;
  }

  int _resolveKotNumber(Map<String, dynamic> kot, int kotIndex) {
    final rawKotNumber = kot['kotNumber'];
    final parsedKotNumber = rawKotNumber is num
        ? rawKotNumber.toInt()
        : int.tryParse(rawKotNumber?.toString() ?? '');
    if (parsedKotNumber != null && parsedKotNumber > 0) {
      return parsedKotNumber;
    }
    return kotIndex + 1;
  }

  bool _readPrinterConfigBool(
    Map<String, dynamic>? config,
    String key, {
    bool fallback = true,
  }) {
    final raw = config?[key];
    if (raw is bool) return raw;
    if (raw is String) {
      final value = raw.trim().toLowerCase();
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return fallback;
  }

  List<int> _applyKotAlignmentCommand(
    List<int> bytes,
    Map<String, dynamic> printerConfig,
  ) {
    final centerAlign =
        _readPrinterConfigBool(printerConfig, 'centerAlign', fallback: true);
    final alignCommand = <int>[0x1B, 0x61, centerAlign ? 0x01 : 0x00];

    if (bytes.length >= 2 && bytes[0] == 0x1B && bytes[1] == 0x40) {
      return <int>[bytes[0], bytes[1], ...alignCommand, ...bytes.sublist(2)];
    }
    return <int>[...alignCommand, ...bytes];
  }

  List<int> _applyBillAlignmentCommand(
    List<int> bytes,
    Map<String, dynamic> printerConfig,
  ) {
    final centerAlign =
        _readPrinterConfigBool(printerConfig, 'centerAlign', fallback: true);
    final alignCommand = <int>[0x1B, 0x61, centerAlign ? 0x01 : 0x00];

    if (bytes.length >= 2 && bytes[0] == 0x1B && bytes[1] == 0x40) {
      return <int>[bytes[0], bytes[1], ...alignCommand, ...bytes.sublist(2)];
    }
    return <int>[...alignCommand, ...bytes];
  }

  /// Returns map with claimed (bool), printKey (String?), reason (String? when claimed is false).
  Future<Map<String, dynamic>> _claimAutoPrintJob({
    required String orderId,
    required String docType,
    int? kotIndex,
    int? kotNumber,
    String? orderVersion,
    String? printKey,
    String? deviceId,
  }) async {
    try {
      final claim = await _orderService.claimPrintJob(
        orderId,
        docType: docType,
        printerId: _autoPrinterId,
        kotIndex: kotIndex,
        kotNumber: kotNumber,
        orderVersion: orderVersion,
        printKey: printKey,
        deviceId: deviceId,
      );
      final claimed = claim['claimed'] == true;
      final key =
          claim['printKey']?.toString().trim() ?? printKey?.trim() ?? '';
      final reason = claim['reason']?.toString().trim();
      return {
        'claimed': claimed,
        'printKey': key.isNotEmpty ? key : null,
        'reason': reason,
      };
    } catch (e) {
      final msg = e.toString();
      print('[PRINT] Failed to claim $docType print job for $orderId: $msg');
      return {'claimed': false, 'printKey': null, 'reason': msg};
    }
  }

  Future<void> _completeAutoPrintJob({
    required String orderId,
    required String docType,
    required String printKey,
    required bool success,
    String? errorMessage,
    int? kotIndex,
    String? deviceId,
  }) async {
    try {
      await _orderService.completePrintJob(
        orderId,
        printKey: printKey,
        docType: docType,
        success: success,
        errorMessage: errorMessage,
        kotIndex: kotIndex,
        deviceId: deviceId,
        status: success ? 'printed' : 'failed',
      );
    } catch (e) {
      print('[PRINT] Failed to complete $docType print job for $orderId: $e');
    }
  }

  Future<bool> _sendToPrinter(
    List<int> bytes,
    Map<String, dynamic> config,
  ) async {
    final ip = config['printerIp']?.toString() ?? '';
    final port = (config['printerPort'] ?? 9100) as int;
    if (ip.isEmpty) return false;

    for (var i = 0; i < _retryDelays.length; i++) {
      try {
        final socket =
            await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
        socket.add(bytes);
        await socket.flush();
        await socket.close();
        return true;
      } catch (e) {
        print('[PRINT] Attempt ${i + 1} failed: $e');
        if (i < _retryDelays.length - 1) {
          await Future.delayed(Duration(milliseconds: _retryDelays[i]));
        }
      }
    }
    print('[PRINT] Failed to send to printer at $ip:$port');
    return false;
  }

  Future<List<int>> _buildKotBytes({
    required String orderId,
    required int kotIndex,
    required Map<String, dynamic> printerConfig,
  }) async {
    try {
      final template = await _orderService.getKotPrintTemplate(
        orderId,
        kotIndex: kotIndex,
        paperWidth: '58mm',
        printerId: _autoPrinterId,
      );

      final linesRaw = template['lines'];
      if (linesRaw is List && linesRaw.isNotEmpty) {
        final paperWidth = template['paperWidth']?.toString() ?? '58mm';
        return EscPosFormatter.generateKotBytesFromTemplateLines(
          linesRaw,
          printerConfig: printerConfig,
          paperWidth: paperWidth,
        );
      }
      print(
          '[PRINT] Backend KOT template for $orderId (kotIndex=$kotIndex) returned no printable lines.');
    } catch (e) {
      print(
          '[PRINT] Backend KOT template fetch failed for $orderId (kotIndex=$kotIndex): $e');
    }

    // Strict backend source of truth: do not render a separate local KOT template.
    return const <int>[];
  }

  /// Pending KOT indices: printStatus != "printed" (or missing for legacy). New flow requires printKey on line.
  List<int> _pendingKotIndices(Map<String, dynamic> order) {
    final kotLines = order['kotLines'] as List<dynamic>? ?? [];
    if (kotLines.isEmpty) return [];
    final indices = <int>[];
    for (var i = 0; i < kotLines.length; i++) {
      final line = kotLines[i] is Map
          ? Map<String, dynamic>.from(kotLines[i] as Map)
          : <String, dynamic>{};
      final status = line['printStatus']?.toString();
      if (status != 'printed') indices.add(i);
    }
    return indices.isNotEmpty
        ? indices
        : _getLastPrintedKotIndex(order) < kotLines.length - 1
            ? [
                for (var j = _getLastPrintedKotIndex(order) + 1;
                    j < kotLines.length;
                    j++)
                  j
              ]
            : [];
  }

  /// Print a single KOT from printer:kot:pending (claim with printKey → build → send → complete).
  Future<void> _printSingleKot(
      Map<String, dynamic> order, int kotIndex, String printKey) async {
    final config = await _getPrinterConfig();
    if (config == null) return;

    final orderId = order['_id']?.toString() ?? '';
    if (orderId.isEmpty) return;

    final deviceId = await _getOrCreatePrintDeviceId();
    final claimResult = await _claimAutoPrintJob(
      orderId: orderId,
      docType: 'KOT',
      kotIndex: kotIndex,
      printKey: printKey,
      deviceId: deviceId,
    );
    if (claimResult['claimed'] != true) {
      final reason = claimResult['reason']?.toString() ?? 'unknown';
      print(
          '[PRINT] Skipping single KOT for $orderId (KOT #${kotIndex + 1}): $reason');
      return;
    }
    final claimedPrintKey = claimResult['printKey']?.toString();
    if (claimedPrintKey == null || claimedPrintKey.isEmpty) return;

    final bytes = await _buildKotBytes(
      orderId: orderId,
      kotIndex: kotIndex,
      printerConfig: config,
    );
    if (bytes.isEmpty) {
      await _completeAutoPrintJob(
        orderId: orderId,
        docType: 'KOT',
        printKey: claimedPrintKey,
        success: false,
        errorMessage: 'Backend KOT template unavailable',
        kotIndex: kotIndex,
        deviceId: deviceId,
      );
      return;
    }
    final alignedKotBytes = _applyKotAlignmentCommand(bytes, config);
    final ok = await _sendToPrinter(alignedKotBytes, config);
    await _completeAutoPrintJob(
      orderId: orderId,
      docType: 'KOT',
      printKey: claimedPrintKey,
      success: ok,
      errorMessage: ok ? null : 'Failed to send data to printer',
      kotIndex: kotIndex,
      deviceId: deviceId,
    );
    if (ok) {
      print('[PRINT] KOT printed for order $orderId (KOT #${kotIndex + 1})');
    }
  }

  Future<bool> _printKot(Map<String, dynamic> order,
      {bool updateStatus = false}) async {
    final config = await _getPrinterConfig();
    if (config == null) return false;

    final kotLines = order['kotLines'] as List<dynamic>? ?? [];
    if (kotLines.isEmpty) return false;

    final orderId = order['_id']?.toString() ?? '';
    if (orderId.isEmpty) return false;

    final pendingIndices = updateStatus
        ? _pendingKotIndices(order)
        : List.generate(kotLines.length, (i) => i);
    if (pendingIndices.isEmpty) return false;

    String? deviceId;
    if (updateStatus) {
      deviceId = await _getOrCreatePrintDeviceId();
    }

    var lastOk = false;
    for (var idx = 0; idx < pendingIndices.length; idx++) {
      final i = pendingIndices[idx];
      final kot = kotLines[i] is Map
          ? Map<String, dynamic>.from(kotLines[i] as Map)
          : <String, dynamic>{};
      final linePrintKey = kot['printKey']?.toString().trim();
      final useNewFlow = updateStatus &&
          linePrintKey != null &&
          linePrintKey.isNotEmpty &&
          deviceId != null;

      String? claimedPrintKey;
      if (updateStatus) {
        Map<String, dynamic> claimResult;
        if (useNewFlow) {
          claimResult = await _claimAutoPrintJob(
            orderId: orderId,
            docType: 'KOT',
            kotIndex: i,
            printKey: linePrintKey,
            deviceId: deviceId,
          );
        } else {
          final kotNumber = _resolveKotNumber(kot, i);
          claimResult = await _claimAutoPrintJob(
            orderId: orderId,
            docType: 'KOT',
            kotIndex: i,
            kotNumber: kotNumber,
            orderVersion: order['updatedAt']?.toString(),
          );
        }
        if (claimResult['claimed'] != true) {
          final reason = claimResult['reason']?.toString() ?? 'unknown';
          print('[PRINT] Skipping KOT print for $orderId: $reason');
          continue;
        }
        claimedPrintKey = claimResult['printKey']?.toString();
        if (claimedPrintKey == null || claimedPrintKey.isEmpty) continue;
      }

      final bytes = await _buildKotBytes(
        orderId: orderId,
        kotIndex: i,
        printerConfig: config,
      );
      if (bytes.isEmpty) {
        lastOk = false;
        if (updateStatus && claimedPrintKey != null) {
          await _completeAutoPrintJob(
            orderId: orderId,
            docType: 'KOT',
            printKey: claimedPrintKey,
            success: false,
            errorMessage: 'Backend KOT template unavailable',
            kotIndex: useNewFlow ? i : null,
            deviceId: useNewFlow ? deviceId : null,
          );
        }
        continue;
      }
      final alignedKotBytes = _applyKotAlignmentCommand(bytes, config);
      lastOk = await _sendToPrinter(alignedKotBytes, config);

      if (updateStatus && claimedPrintKey != null) {
        await _completeAutoPrintJob(
          orderId: orderId,
          docType: 'KOT',
          printKey: claimedPrintKey,
          success: lastOk,
          errorMessage: lastOk ? null : 'Failed to send data to printer',
          kotIndex: useNewFlow ? i : null,
          deviceId: useNewFlow ? deviceId : null,
        );
      }

      if (lastOk && updateStatus && !useNewFlow) {
        try {
          final isLast = i == kotLines.length - 1;
          await _orderService.updatePrintStatus(
            orderId,
            lastPrintedKotIndex: i,
            kotPrinted: isLast,
          );
          print('[PRINT] KOT printed for order $orderId');
        } catch (e) {
          print('[PRINT] Failed to update KOT print status: $e');
        }
      } else if (lastOk && updateStatus && useNewFlow) {
        print('[PRINT] KOT printed for order $orderId (agent print-complete)');
      }
    }
    return lastOk;
  }

  Future<bool> _printBill(Map<String, dynamic> order,
      {bool updateStatus = false}) async {
    final config = await _getPrinterConfig();
    if (config == null) return false;

    final orderId = order['_id']?.toString() ?? '';
    if (orderId.isEmpty) return false;

    String? claimedPrintKey;
    if (updateStatus) {
      final claimResult = await _claimAutoPrintJob(
        orderId: orderId,
        docType: 'BILL',
        orderVersion: order['updatedAt']?.toString(),
      );
      if (claimResult['claimed'] != true) {
        final reason = claimResult['reason']?.toString() ?? 'unknown';
        print('[PRINT] Skipping BILL print for $orderId: $reason');
        return true;
      }
      claimedPrintKey = claimResult['printKey']?.toString();
      if (claimedPrintKey == null || claimedPrintKey.isEmpty) return true;
    }

    String? paymentMethod;
    try {
      final payment = await _paymentService.getLatestPaymentForOrder(orderId);
      paymentMethod = payment?['method']?.toString();
    } catch (_) {}

    Map<String, dynamic>? cartData;
    final cartId = order['cartId']?.toString();
    if (cartId != null && cartId.isNotEmpty) {
      try {
        cartData = await _userService.getUserById(cartId);
      } catch (_) {}
    }

    List<int> bytes;
    try {
      bytes = await EscPosFormatter.generateBillBytes(
        order,
        paymentMethod,
        cartData: cartData,
        printerConfig: config,
      );
    } catch (e) {
      print('[PRINT] Bill generation failed: $e');
      throw ApiException(
        message: 'Failed to generate bill: ${e.toString()}',
      );
    }
    final alignedBillBytes = _applyBillAlignmentCommand(bytes, config);
    final ok = await _sendToPrinter(alignedBillBytes, config);
    if (updateStatus && claimedPrintKey != null) {
      await _completeAutoPrintJob(
        orderId: orderId,
        docType: 'BILL',
        printKey: claimedPrintKey,
        success: ok,
        errorMessage: ok ? null : 'Failed to send data to printer',
      );
    }
    if (ok && updateStatus) {
      try {
        await _orderService.updatePrintStatus(
          orderId,
          billPrinted: true,
        );
        print('[PRINT] Bill printed for order $orderId');
      } catch (e) {
        print('[PRINT] Failed to update BILL print status: $e');
      }
    }
    return ok;
  }

  /// Reprint KOT. Throws ApiException if printer not configured or print fails.
  Future<bool> reprintKot(Map<String, dynamic> order) async {
    if (!_hasKotLines(order)) {
      throw ApiException(message: 'Order has no items to print');
    }
    final config = await _getPrinterConfig();
    if (config == null) {
      print('[PRINT] No printer config - manager must set IP in Settings');
      throw ApiException(
        message:
            'Printer not configured. Manager must set printer IP in Settings.',
      );
    }
    final ok = await _printKot(order, updateStatus: false);
    if (!ok) {
      throw ApiException(
        message: 'Print failed. Check printer connection and Settings.',
      );
    }
    print('[PRINT] KOT printed for order ${order['_id']}');
    return true;
  }

  /// Reprint Bill. Throws ApiException if printer not configured or print fails.
  Future<bool> reprintBill(Map<String, dynamic> order) async {
    if (!_hasKotLines(order)) {
      throw ApiException(message: 'Order has no items to print');
    }
    final config = await _getPrinterConfig();
    if (config == null) {
      print('[PRINT] No printer config - manager must set IP in Settings');
      throw ApiException(
        message:
            'Printer not configured. Manager must set printer IP in Settings.',
      );
    }
    final ok = await _printBill(order, updateStatus: false);
    if (!ok) {
      throw ApiException(
        message: 'Print failed. Check printer connection and Settings.',
      );
    }
    print('[PRINT] Bill printed for order ${order['_id']}');
    return true;
  }

  /// Invalidate cached printer config (e.g. after saving new config).
  void invalidatePrinterConfig() {
    _cachedPrinterConfig = null;
  }
}
