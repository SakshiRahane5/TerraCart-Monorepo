import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/utils/order_status_utils.dart';
import '../../services/print_service.dart';
import '../../services/table_service.dart';
import '../../services/order_service.dart';
import '../../services/menu_service.dart';
import '../../services/addon_service.dart';
import '../../services/socket_service.dart';
import '../../models/table_model.dart';
import '../../models/order_model.dart';
import '../../models/menu_model.dart';
import '../../models/addon_model.dart';
import '../../providers/app_provider.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/config/api_config.dart';
import 'qr_scanner_screen.dart';

class OrdersScreen extends StatefulWidget {
  final bool? showBackButton;

  /// When true, shows only the table layout (for waiter's Tables bottom bar tab).
  final bool showTablesOnly;
  final int initialTabIndex;

  const OrdersScreen(
      {super.key,
      this.showBackButton,
      this.showTablesOnly = false,
      this.initialTabIndex = 0});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Employee app should not surface final/closed orders.
  static const Set<String> _hiddenEmployeeStatuses =
      OrderStatusUtils.employeeHiddenStatuses;

  // Legacy takeaway status handled as closed in mobile app.
  // ignore: unused_field
  static const Set<String> _hiddenTakeawayStatuses =
      OrderStatusUtils.hiddenTakeawayStatuses;

  late TabController _tabController;
  final TableService _tableService = TableService();
  final OrderService _orderService = OrderService();
  final MenuService _menuService = MenuService();
  final SocketService _socketService = SocketService();

  List<TableModel> _tables = [];
  // Map of tableId -> sessionToken (populated when scanning QR / looking up table)
  final Map<String, String?> _tableSessionTokens = {};
  List<OrderModel> _activeOrders = [];
  List<OrderModel> _previousOrders = [];
  List<MenuCategory> _menuCategories = [];
  List<MenuItem> _allMenuItems = [];
  int _selectedTable = 0;
  bool _isLoading = true;
  String? _errorMessage;
  // Selected tables for merging (stores table IDs)
  final Set<String> _selectedTablesForMerge = {};
  final List<Map<String, dynamic>> _newOrderPopupQueue = [];
  final Set<String> _queuedPopupOrderIds = {};
  bool _isOrderPopupVisible = false;
  bool _isOrderPopupClosing = false;
  String? _activeOrderPopupId;
  BuildContext? _activeOrderPopupContext;
  String _orderSearchQuery = '';
  String _orderDateRange = 'today';
  String _previousOrderDateRange = 'today';
  Timer? _socketFallbackPollTimer;
  static const Duration _socketFallbackPollInterval = Duration(seconds: 4);
  int _socketFallbackPollTick = 0;
  final Set<String> _statusUpdateInFlightOrderIds = <String>{};
  final Map<String, int> _queuedStatusAdvances = <String, int>{};

  bool get _isWaiter =>
      Provider.of<AppProvider>(context, listen: false).userRole == 'waiter';
  bool get _isReadOnlyLocked =>
      Provider.of<AppProvider>(context, listen: false).isReadOnlyAfterCheckout;
  /*
  bool get _canHandleRealtimeOrderAcceptance {
    final role =
        Provider.of<AppProvider>(context, listen: false).userRole.toLowerCase();
    return !_isReadOnlyLocked &&
        (role == 'waiter' || role == 'captain' || role == 'manager');
  }

  bool get _canHandleRealtimeOrderPopups =>
      !widget.showTablesOnly &&
      !_isReadOnlyLocked &&
      _canHandleRealtimeOrderAcceptance;
  */
  // Accept-order assignment flow disabled: process orders directly by status flow.
  // ignore: unused_element
  bool get _canHandleRealtimeOrderAcceptance => false;
  bool get _canHandleRealtimeOrderPopups => false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final maxTabIndex = _isWaiter ? 1 : 2;
    final safeInitialTabIndex = widget.initialTabIndex < 0
        ? 0
        : (widget.initialTabIndex > maxTabIndex
            ? maxTabIndex
            : widget.initialTabIndex);
    _tabController = TabController(
      length: _isWaiter ? 2 : 3,
      vsync: this,
      initialIndex: safeInitialTabIndex,
    );
    _tabController.addListener(() {
      if (!mounted || _tabController.indexIsChanging) return;
      setState(() {});
    });
    _loadData();
    _setupSocketListeners();
  }

  String? _getCurrentCartId() {
    return Provider.of<AppProvider>(context, listen: false)
        .currentUser
        ?.cartId
        ?.trim();
  }

  void _upsertRealtimeOrderFromPayload(dynamic data) {
    if (!mounted || data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    final realtimeOrderId =
        (map['_id'] ?? map['id'] ?? map['orderId'])?.toString().trim();
    if (realtimeOrderId == null || realtimeOrderId.isEmpty) return;

    try {
      // Some events send the order under payload.order.
      final sourceMap = map['order'] is Map
          ? Map<String, dynamic>.from(map['order'] as Map)
          : map;
      sourceMap['_id'] = sourceMap['_id'] ?? realtimeOrderId;
      final idx = _activeOrders.indexWhere((o) => o.id == realtimeOrderId);
      final hasRichOrderShape = sourceMap['kotLines'] is List ||
          sourceMap['table'] != null ||
          sourceMap['createdAt'] != null ||
          sourceMap['customerName'] != null;

      if (idx == -1 && !hasRichOrderShape) {
        // Status-only payload for unknown order: trigger source-of-truth refresh.
        _loadOrders(showLoading: false);
        return;
      }

      final mergedPayload = idx != -1
          ? Map<String, dynamic>.from(_activeOrders[idx].toJson())
          : <String, dynamic>{};
      mergedPayload.addAll(sourceMap);
      mergedPayload['_id'] = realtimeOrderId;
      mergedPayload['updatedAt'] =
          sourceMap['updatedAt'] ?? mergedPayload['updatedAt'];
      mergedPayload['status'] = sourceMap['status'] ?? mergedPayload['status'];
      mergedPayload['paymentStatus'] =
          sourceMap['paymentStatus'] ?? mergedPayload['paymentStatus'];
      mergedPayload['isPaid'] =
          (sourceMap['paymentStatus']?.toString().toUpperCase() == 'PAID') ||
              sourceMap['isPaid'] == true ||
              mergedPayload['isPaid'] == true;
      mergedPayload['createdAt'] =
          mergedPayload['createdAt'] ?? DateTime.now().toIso8601String();

      final order = OrderModel.fromJson(mergedPayload);

      final currentCartId = _getCurrentCartId();
      final orderCartId = (order.cartId ?? '').trim();
      if (currentCartId != null &&
          currentCartId.isNotEmpty &&
          orderCartId.isNotEmpty &&
          orderCartId != currentCartId) {
        return;
      }

      if (!_shouldShowOrderForEmployees(order)) {
        final idx = _activeOrders.indexWhere((o) => o.id == order.id);
        if (idx != -1) {
          setState(() {
            _activeOrders.removeAt(idx);
          });
        }
        return;
      }

      setState(() {
        if (idx == -1) {
          _activeOrders.add(order);
        } else {
          _activeOrders[idx] = order;
        }
        _activeOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    } catch (_) {
      // Best effort UI update; API reload below keeps source of truth.
    }
  }

  void _removeRealtimeOrderFromPayload(dynamic data) {
    if (!mounted || data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    final id = (map['id'] ?? map['_id'] ?? map['orderId'])?.toString().trim();
    if (id == null || id.isEmpty) return;
    final idx = _activeOrders.indexWhere((o) => o.id == id);
    if (idx == -1) return;
    setState(() {
      _activeOrders.removeAt(idx);
    });
  }

  void _onOrderCreated(dynamic data) {
    if (!mounted) return;
    _upsertRealtimeOrderFromPayload(data);
    PrintService().triggerPendingKotRecovery();
    _loadOrders(showLoading: false);
  }

  void _onOrderUpdated(dynamic data) {
    if (!mounted) return;
    if (data is Map) {
      final payload = Map<String, dynamic>.from(data);
      print(
          '[SOCKET_DEBUG][orders_screen] recv order_status_updated orderId=${payload['orderId'] ?? payload['_id'] ?? payload['id']} status=${payload['status']} paymentStatus=${payload['paymentStatus']} updatedAt=${payload['updatedAt']}');
    }
    _upsertRealtimeOrderFromPayload(data);
    PrintService().triggerPendingKotRecovery();
    _loadOrders(showLoading: false);
  }

  void _onOrderDeleted(dynamic data) {
    if (!mounted) return;
    _removeRealtimeOrderFromPayload(data);
    _loadOrders(showLoading: false);
  }

  void _onOrderUpsert(dynamic data) {
    if (!mounted) return;
    _upsertRealtimeOrderFromPayload(data);
    PrintService().triggerPendingKotRecovery();
    _loadOrders(showLoading: false);
  }

  void _onSocketConnected(dynamic _) {
    if (!mounted) return;
    _stopSocketFallbackPolling();
    PrintService().triggerPendingKotRecovery();
    _loadOrders(showLoading: false);
  }

  void _onSocketDisconnected(dynamic _) {
    if (!mounted) return;
    _startSocketFallbackPolling();
  }

  void _onTableStatusUpdated(dynamic _) {
    if (mounted) _loadTables();
  }

  void _onTableMerged(dynamic _) {
    if (mounted) {
      _loadTables();
      _loadOrders(showLoading: false);
    }
  }

  void _onTableUnmerged(dynamic _) {
    if (mounted) {
      _loadTables();
      _loadOrders(showLoading: false);
    }
  }

  void _onMenuUpdated(dynamic _) {
    if (mounted) _loadMenu();
  }

  void _setupSocketListeners() {
    _socketService.on('order:created', _onOrderCreated,
        debounce: true, delay: const Duration(milliseconds: 300));
    _socketService.on('order:upsert', _onOrderUpsert,
        debounce: true, delay: const Duration(milliseconds: 300));
    _socketService.on('order_status_updated', _onOrderUpdated,
        debounce: true, delay: const Duration(milliseconds: 300));
    _socketService.on('order.cancelled', _onOrderUpdated,
        debounce: true, delay: const Duration(milliseconds: 300));
    _socketService.on('order:deleted', _onOrderDeleted,
        debounce: true, delay: const Duration(milliseconds: 300));
    _socketService.on('orderDeleted', _onOrderDeleted,
        debounce: true, delay: const Duration(milliseconds: 300));

    // Accept-order popup flow disabled.
    /*
    _socketService.on('NEW_ORDER_AVAILABLE', (data) {
      if (!mounted) return;
      _handleNewOrderAvailableEvent(data);
    });

    _socketService.on('ORDER_ACCEPTED', (data) {
      if (!mounted) return;
      _handleOrderAcceptedEvent(data);
    });
    */

    _socketService.on('table:status:updated', _onTableStatusUpdated,
        debounce: true);

    _socketService.on('table:merged', _onTableMerged, debounce: true);

    _socketService.on('table:unmerged', _onTableUnmerged, debounce: true);

    _socketService.on('menu:updated', _onMenuUpdated, debounce: true);

    _socketService.on('connect', _onSocketConnected);
    _socketService.on('reconnect', _onSocketConnected);
    _socketService.on('disconnect', _onSocketDisconnected);
    _socketService.on('connect_error', _onSocketDisconnected);

    if (_socketService.isConnected) {
      _stopSocketFallbackPolling();
    } else {
      _startSocketFallbackPolling();
    }
  }

  void _removeSocketListeners() {
    _socketService.off('order:created', _onOrderCreated);
    _socketService.off('order:upsert', _onOrderUpsert);
    _socketService.off('order_status_updated', _onOrderUpdated);
    _socketService.off('order.cancelled', _onOrderUpdated);
    _socketService.off('order:deleted', _onOrderDeleted);
    _socketService.off('orderDeleted', _onOrderDeleted);
    _socketService.off('table:status:updated', _onTableStatusUpdated);
    _socketService.off('table:merged', _onTableMerged);
    _socketService.off('table:unmerged', _onTableUnmerged);
    _socketService.off('menu:updated', _onMenuUpdated);
    _socketService.off('connect', _onSocketConnected);
    _socketService.off('reconnect', _onSocketConnected);
    _socketService.off('disconnect', _onSocketDisconnected);
    _socketService.off('connect_error', _onSocketDisconnected);
  }

  void _startSocketFallbackPolling() {
    if (_socketFallbackPollTimer != null) return;
    _socketFallbackPollTick = 0;
    _socketFallbackPollTimer = Timer.periodic(_socketFallbackPollInterval, (_) {
      if (!mounted) return;
      if (_socketService.isConnected) {
        _stopSocketFallbackPolling();
        return;
      }
      _socketFallbackPollTick += 1;
      _loadOrders(showLoading: false);
      // Keep table polling much less frequent to reduce noisy refresh loops.
      if (_socketFallbackPollTick % 5 == 0) {
        _loadTables();
      }
      PrintService().triggerPendingKotRecovery();
    });
  }

  void _stopSocketFallbackPolling() {
    _socketFallbackPollTimer?.cancel();
    _socketFallbackPollTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      PrintService().triggerPendingKotRecovery();
      _loadOrders(showLoading: false);
      _loadTables();
      if (_socketService.isConnected) {
        _stopSocketFallbackPolling();
      } else {
        _startSocketFallbackPolling();
      }
    }
  }

  // Helper method to safely show snackbars
  void _showSnackBar(String message,
      {Color? backgroundColor, Duration? duration}) {
    if (!mounted) return;
    _showSnackBarWithContext(context, message,
        backgroundColor: backgroundColor, duration: duration);
  }

  // Helper method to show snackbars with a specific context (for modals)
  void _showSnackBarWithContext(BuildContext ctx, String message,
      {Color? backgroundColor, Duration? duration}) {
    try {
      final scaffoldMessenger = ScaffoldMessenger.maybeOf(ctx);
      if (scaffoldMessenger != null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor ?? AppColors.primary,
            duration: duration ?? const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Silently fail if context is invalid
      print('[OrdersScreen] Failed to show snackbar: $e');
    }
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      await Future.wait([_loadTables(), _loadOrders(), _loadMenu()]);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMenu() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final cartId = appProvider.currentUser?.cartId;

      if (cartId == null) {
        if (mounted) {
          setState(() {
            _menuCategories = [];
            _allMenuItems = [];
          });
        }
        return;
      }

      final categories = await _menuService.getMenu(cartId: cartId);
      if (mounted) {
        setState(() {
          _menuCategories = categories;
          // Flatten all items for search
          _allMenuItems = categories.expand((cat) => cat.items).toList();
        });
      }
    } catch (e) {
      print('[OrdersScreen] Failed to load menu: $e');
      if (mounted) {
        setState(() {
          _menuCategories = [];
          _allMenuItems = [];
        });
      }
    }
  }

  Future<void> _loadTables() async {
    try {
      print('[OrdersScreen] Loading tables...');
      final tables = await _tableService.getTables();
      print('[OrdersScreen] Loaded ${tables.length} tables');

      if (mounted) {
        final currentCartId = _getCurrentCartId()?.trim();
        final modernTables = tables.where((table) {
          final hasQrSlug = (table.qrSlug ?? '').trim().isNotEmpty;
          if (!hasQrSlug) return false;

          final qrContextType =
              (table.qrContextType ?? '').trim().toUpperCase();
          if (qrContextType != 'TABLE' && qrContextType != 'OFFICE') {
            return false;
          }

          return true;
        }).toList();

        // Keep cart filter best-effort only. If current user cart is stale locally,
        // don't drop all server-scoped tables.
        List<TableModel> cartScopedTables = modernTables;
        if (currentCartId != null && currentCartId.isNotEmpty) {
          final matches = modernTables.where((table) {
            final tableCartId = (table.cartId ?? '').trim();
            return tableCartId.isNotEmpty && tableCartId == currentCartId;
          }).toList();
          if (matches.isNotEmpty) {
            cartScopedTables = matches;
          }
        }

        // Deduplicate by logical table key (cart + number).
        // Keep the first entry (backend already sorts and deduplicates by freshness).
        final Map<String, TableModel> deduplicatedByNumber = {};
        for (final table in cartScopedTables) {
          final cartId = (table.cartId ?? 'unknown').trim();
          final key = '$cartId-${table.number}';
          if (!deduplicatedByNumber.containsKey(key)) {
            deduplicatedByNumber[key] = table;
          }
        }

        final uniqueTables = deduplicatedByNumber.values.toList()
          ..sort((a, b) => a.number.compareTo(b.number));
        print(
            '[OrdersScreen] After deduplication: ${uniqueTables.length} unique tables');

        setState(() {
          _tables = uniqueTables;
          // Initialize known session tokens from backend (for occupied tables)
          for (final t in uniqueTables) {
            if (t.sessionToken != null && t.sessionToken!.isNotEmpty) {
              _tableSessionTokens[t.id] = t.sessionToken;
            }
          }
          // Clear error message on successful load
          _errorMessage = null;
        });
      }
    } catch (e) {
      print('[OrdersScreen] Error loading tables: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e is ApiException
              ? e.message
              : 'Failed to load tables: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _loadOrders({bool showLoading = false}) async {
    try {
      final orders = await _orderService.getOrders(
        status: null, // Get all orders
        limit: 500, // Increased limit significantly to get all orders
        includeHistory: !_isWaiter,
      );
      if (mounted) {
        setState(() {
          final currentCartId = Provider.of<AppProvider>(
            context,
            listen: false,
          ).currentUser?.cartId?.trim();

          // Defense in depth: keep only orders from current user's cart.
          final cartScopedOrders = (currentCartId != null &&
                  currentCartId.isNotEmpty)
              ? orders
                  .where(
                    (order) =>
                        (order.cartId ?? '').toString().trim() == currentCartId,
                  )
                  .toList()
              // If local cart binding is unavailable, trust backend scoping.
              : orders;

          // Keep only employee-visible active orders.
          final filteredOrders =
              cartScopedOrders.where(_shouldShowOrderForEmployees).toList();
          final previousOrders =
              cartScopedOrders.where(_isPreviousOrder).toList();

          // Sort by creation date descending (newest first)
          filteredOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          previousOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          _activeOrders = filteredOrders;
          _previousOrders = previousOrders;

          // Clear error message on successful load
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e is ApiException ? e.message : 'Failed to load orders';
          // Don't clear existing orders on error - keep showing them
        });
      }
    }
  }

  String _normalizeStatus(String status) => status.trim().toLowerCase();

  bool _isDineInServiceType(String? serviceType) {
    return (serviceType ?? '').trim().toUpperCase() == 'DINE_IN';
  }

  bool _isTakeawayLikeServiceType(String? serviceType) {
    final normalized = (serviceType ?? '').trim().toUpperCase();
    return normalized == 'TAKEAWAY' ||
        normalized == 'PICKUP' ||
        normalized == 'DELIVERY';
  }

  bool _isOfficeOrder(OrderModel order) {
    final sourceQrType = (order.sourceQrType ?? '').trim().toUpperCase();
    if (sourceQrType == 'OFFICE') return true;
    return (order.officeName ?? '').trim().isNotEmpty;
  }

  bool _isTakeawayLikeOrder(OrderModel order) {
    final serviceType = (order.serviceType).trim().toUpperCase();
    if (serviceType == 'DINE_IN') {
      // Service type is canonical for modern records. Ignore stale orderType.
      return false;
    }
    if (_isTakeawayLikeServiceType(serviceType)) {
      return true;
    }
    // Backward compatibility for older payloads where serviceType may be absent.
    return _isTakeawayLikeServiceType(order.orderType);
  }

  String _serviceTypeLabel(OrderModel order) {
    final serviceType = (order.serviceType).trim().toUpperCase();
    final orderType = (order.orderType ?? '').trim().toUpperCase();
    if (serviceType == 'DINE_IN') return 'Dine-In';
    if (serviceType == 'DELIVERY' || orderType == 'DELIVERY') {
      return _isOfficeOrder(order) ? 'Office' : 'Delivery';
    }
    if (serviceType == 'PICKUP' || orderType == 'PICKUP') return 'Pickup';
    if (_isOfficeOrder(order)) return 'Office';
    if (_isTakeawayLikeOrder(order)) return 'Takeaway';
    return 'Dine-In';
  }

  bool _matchesOrderServiceTab(OrderModel order, String tabServiceType) {
    if (tabServiceType == 'DINE_IN') {
      return _isDineInServiceType(order.serviceType);
    }
    if (tabServiceType == 'TAKEAWAY') {
      return _isTakeawayLikeOrder(order);
    }
    return false;
  }

  List<OrderModel> _applyOrderSearch(List<OrderModel> orders) {
    final query = _orderSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return orders;

    return orders.where((order) {
      final itemNames =
          order.activeItems.map((e) => e.name).join(' ').toLowerCase();
      final addonNames =
          order.selectedAddons.map((e) => e.name).join(' ').toLowerCase();

      return order.id.toLowerCase().contains(query) ||
          (order.tableNumber ?? '').toLowerCase().contains(query) ||
          (order.customerName ?? '').toLowerCase().contains(query) ||
          (order.customerMobile ?? '').toLowerCase().contains(query) ||
          order.status.toLowerCase().contains(query) ||
          _serviceTypeLabel(order).toLowerCase().contains(query) ||
          (order.takeawayToken?.toString() ?? '').contains(query) ||
          itemNames.contains(query) ||
          addonNames.contains(query);
    }).toList();
  }

  DateTime _normalizeIstDateOnly(DateTime value) {
    final ist = DateTimeUtils.toIST(value);
    return DateTime(ist.year, ist.month, ist.day);
  }

  List<OrderModel> _applyOrderDateRange(
    List<OrderModel> orders, {
    String? selectedRange,
  }) {
    final range = (selectedRange ?? _orderDateRange).trim().toLowerCase();
    if (range == 'all') return orders;

    final now = DateTime.now();
    final today = _normalizeIstDateOnly(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final currentMonth = DateTime(today.year, today.month, 1);
    final weeklyStart = today.subtract(const Duration(days: 6));

    return orders.where((order) {
      final createdDay = _normalizeIstDateOnly(order.createdAt);
      if (range == 'today') {
        return createdDay == today;
      }
      if (range == 'yesterday') {
        return createdDay == yesterday;
      }
      if (range == 'weekly') {
        return !createdDay.isBefore(weeklyStart) && !createdDay.isAfter(today);
      }
      if (range == 'monthly') {
        return createdDay.year == currentMonth.year &&
            createdDay.month == currentMonth.month;
      }
      return true;
    }).toList();
  }

  Widget _buildOrderDateRangeChip(
    String value,
    String label, {
    required String selectedValue,
    required ValueChanged<String> onChanged,
  }) {
    final isSelected = selectedValue == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          onChanged(value);
        });
      },
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      backgroundColor: Theme.of(context).cardColor,
      side: BorderSide(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.6)
            : AppColors.cardBorder,
      ),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  bool _isHiddenForEmployees(String status) {
    return _hiddenEmployeeStatuses.contains(_normalizeStatus(status));
  }

  bool _shouldShowOrderForEmployees(OrderModel order) {
    return OrderStatusUtils.shouldShowForEmployees(
      status: order.status,
      paymentStatus: order.paymentStatus,
      isPaid: order.isPaid,
      paymentMode: order.paymentMode,
      officePaymentMode: order.officePaymentMode,
      paymentRequiredBeforeProceeding: order.paymentRequiredBeforeProceeding,
      sourceQrType: order.sourceQrType,
      serviceType: order.serviceType,
      orderType: order.orderType,
    );
  }

  bool _isOrderSettled(OrderModel order) {
    return OrderStatusUtils.isSettled(
      status: order.status,
      paymentStatus: order.paymentStatus,
      isPaid: order.isPaid,
    );
  }

  bool _isPreviousOrder(OrderModel order) {
    return _isOrderSettled(order);
  }

  Map<String, dynamic>? _normalizeNewOrderPayload(dynamic data,
      {bool fromLegacyOrderCreated = false}) {
    if (data is! Map) return null;

    final map = Map<String, dynamic>.from(data);
    final orderId = (map['orderId'] ?? map['_id'] ?? map['id'])?.toString();
    if (orderId == null || orderId.isEmpty) return null;
    final assignedStaff = map['assignedStaff'];
    final assignedStaffId =
        assignedStaff is Map ? assignedStaff['id']?.toString() : null;
    final isAssigned = map['isAssigned'] == true ||
        (assignedStaffId != null && assignedStaffId.isNotEmpty);

    final serviceType = ((map['serviceType'] ?? '').toString()).toUpperCase();
    final orderType =
        ((map['orderType'] ?? serviceType).toString()).toUpperCase();
    final status = ((map['status'] ?? '').toString()).toLowerCase();

    List<dynamic> orderSummary = [];
    if (map['orderSummary'] is List) {
      orderSummary = List<dynamic>.from(map['orderSummary'] as List);
    } else if (fromLegacyOrderCreated) {
      final kotLinesRaw = map['kotLines'];
      if (kotLinesRaw is List && kotLinesRaw.isNotEmpty) {
        final latestKot = kotLinesRaw.last;
        if (latestKot is Map && latestKot['items'] is List) {
          orderSummary = List<dynamic>.from(latestKot['items'] as List);
        }
      }
    }

    return {
      'orderId': orderId,
      'serviceType': serviceType,
      'orderType': orderType,
      'status': status,
      'isAssigned': isAssigned,
      'tableNo': map['tableNo'] ?? map['tableNumber'],
      'createdAt': map['createdAt'],
      'orderSummary': orderSummary,
    };
  }

  String _buildOrderSummaryText(dynamic summaryRaw) {
    if (summaryRaw is! List || summaryRaw.isEmpty) {
      return 'A new order is waiting for acceptance.';
    }

    final parts = <String>[];
    for (final entry in summaryRaw.take(3)) {
      if (entry is Map) {
        final map = Map<String, dynamic>.from(entry);
        final name = map['name']?.toString();
        final qty = map['quantity']?.toString();
        if (name != null && name.isNotEmpty) {
          parts.add('${qty ?? '1'} x $name');
        }
      }
    }

    if (parts.isEmpty) {
      return 'A new order is waiting for acceptance.';
    }

    final hiddenCount = summaryRaw.length - parts.length;
    return hiddenCount > 0
        ? '${parts.join(', ')} +$hiddenCount more'
        : parts.join(', ');
  }

  // ignore: unused_element
  void _handleNewOrderAvailableEvent(dynamic data,
      {bool fromLegacyOrderCreated = false}) {
    if (!_canHandleRealtimeOrderPopups) return;

    final payload = _normalizeNewOrderPayload(
      data,
      fromLegacyOrderCreated: fromLegacyOrderCreated,
    );
    if (payload == null) return;

    final orderId = payload['orderId']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    if (payload['isAssigned'] == true) {
      return;
    }

    final status = payload['status']?.toString().toLowerCase() ?? '';
    if (_isHiddenForEmployees(status)) {
      return;
    }

    if (_queuedPopupOrderIds.contains(orderId)) return;

    _queuedPopupOrderIds.add(orderId);
    _newOrderPopupQueue.add(payload);
    _loadOrders(showLoading: false);
    _tryShowNextOrderPopup();
  }

  // ignore: unused_element
  bool _canAcceptAssignment(OrderModel order) {
    // Accept-order assignment flow disabled.
    /*
    if (_isReadOnlyLocked) return false;
    if (!_canHandleRealtimeOrderAcceptance) return false;
    if (order.acceptedBy?.employeeId != null) return false;
    if (_isHiddenForEmployees(order.status)) return false;
    if (_isTakeawayLikeOrder(order) &&
        _hiddenTakeawayStatuses.contains(_normalizeStatus(order.status))) {
      return false;
    }
    return true;
    */
    return false;
  }

  void _closeActiveOrderPopupSafely(String result) {
    if (_isOrderPopupClosing) return;
    final popupCtx = _activeOrderPopupContext;
    if (popupCtx == null || !popupCtx.mounted) return;

    _isOrderPopupClosing = true;
    // Detach immediately so concurrent socket callbacks cannot trigger another pop.
    _activeOrderPopupContext = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !popupCtx.mounted) {
        _isOrderPopupClosing = false;
        return;
      }

      try {
        final navigator = Navigator.maybeOf(
          popupCtx,
          rootNavigator: true,
        );
        if (navigator != null && navigator.canPop()) {
          navigator.pop(result);
          return;
        }
      } catch (e) {
        debugPrint('[ORDERS_SCREEN] Popup close failed: $e');
      }

      if (mounted) {
        _isOrderPopupClosing = false;
      }
    });
  }

  // ignore: unused_element
  void _handleOrderAcceptedEvent(dynamic data) {
    if (!_canHandleRealtimeOrderPopups) return;
    if (data is! Map) return;

    final payload = Map<String, dynamic>.from(data);
    final orderId =
        (payload['orderId'] ?? payload['order']?['_id'])?.toString();
    if (orderId == null || orderId.isEmpty) return;

    final assignedStaffRaw = payload['assignedStaff'];
    String? assignedName;
    String? assignedId;
    if (assignedStaffRaw is Map) {
      final assignedStaff = Map<String, dynamic>.from(assignedStaffRaw);
      assignedName = assignedStaff['name']?.toString();
      assignedId = assignedStaff['id']?.toString();
    }

    final currentEmployeeId = Provider.of<AppProvider>(context, listen: false)
        .currentUser
        ?.employeeId
        ?.toString();
    final acceptedByCurrentUser = assignedId != null &&
        currentEmployeeId != null &&
        assignedId == currentEmployeeId;
    final wasTrackedByPopup = _activeOrderPopupId == orderId ||
        _queuedPopupOrderIds.contains(orderId);
    final isPopupOpenForOrder =
        _activeOrderPopupId == orderId && _activeOrderPopupContext != null;

    _newOrderPopupQueue.removeWhere((entry) => entry['orderId'] == orderId);
    _queuedPopupOrderIds.remove(orderId);

    if (_activeOrderPopupId == orderId && _activeOrderPopupContext != null) {
      _closeActiveOrderPopupSafely(
        acceptedByCurrentUser ? 'accepted' : 'already_accepted',
      );
    }

    if (!acceptedByCurrentUser && wasTrackedByPopup && !isPopupOpenForOrder) {
      _showSnackBar(
        assignedName != null && assignedName.isNotEmpty
            ? 'Order already accepted by $assignedName'
            : 'Order already accepted',
        backgroundColor: AppColors.warning,
      );
    }

    _loadOrders(showLoading: false);
  }

  void _focusAcceptedOrder(String orderId) {
    if (!mounted) return;
    final index = _activeOrders.indexWhere((o) => o.id == orderId);
    if (index == -1) return;

    if (_tabController.length > 1) {
      final order = _activeOrders[index];
      final targetTabIndex =
          _isWaiter ? (_isTakeawayLikeOrder(order) ? 1 : 0) : 1;
      if (_tabController.index != targetTabIndex) {
        _tabController.animateTo(targetTabIndex);
      }
    }

    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final latestIndex = _activeOrders.indexWhere((o) => o.id == orderId);
      if (latestIndex != -1) {
        _showOrderDetailsModal(_activeOrders[latestIndex]);
      }
    });
  }

  void _tryShowNextOrderPopup() {
    if (!mounted || _isOrderPopupVisible || _newOrderPopupQueue.isEmpty) return;

    final payload = _newOrderPopupQueue.first;
    final orderId = payload['orderId']?.toString();
    if (orderId == null || orderId.isEmpty) {
      _newOrderPopupQueue.removeAt(0);
      _tryShowNextOrderPopup();
      return;
    }

    _isOrderPopupVisible = true;
    _activeOrderPopupId = orderId;

    final orderType =
        payload['orderType']?.toString().toUpperCase() ?? 'TAKEAWAY';
    final tableNo = payload['tableNo']?.toString();
    final summaryText = _buildOrderSummaryText(payload['orderSummary']);

    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _activeOrderPopupContext = dialogContext;
        bool isAccepting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.notifications_active, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(child: Text('New Order Available')),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order Type: $orderType',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (tableNo != null && tableNo.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Table / Token: $tableNo'),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    summaryText,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isAccepting
                      ? null
                      : () => _closeActiveOrderPopupSafely('ignored'),
                  child: const Text('Ignore'),
                ),
                ElevatedButton(
                  onPressed: isAccepting
                      ? null
                      : () async {
                          setDialogState(() {
                            isAccepting = true;
                          });

                          try {
                            await _orderService.acceptOrder(orderId);
                            _closeActiveOrderPopupSafely('accepted');
                          } catch (e) {
                            final message = e is ApiException
                                ? e.message
                                : 'Failed to accept order';
                            final lower = message.toLowerCase();
                            if (lower.contains('already accepted')) {
                              _closeActiveOrderPopupSafely('already_accepted');
                              return;
                            }
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isAccepting = false;
                              });
                            }
                            _showSnackBar(
                              message,
                              backgroundColor: AppColors.error,
                            );
                          }
                        },
                  child: isAccepting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept Order'),
                ),
              ],
            );
          },
        );
      },
    ).then((result) async {
      _isOrderPopupClosing = false;
      _activeOrderPopupContext = null;
      _activeOrderPopupId = null;
      _isOrderPopupVisible = false;
      _newOrderPopupQueue.removeWhere((entry) => entry['orderId'] == orderId);
      _queuedPopupOrderIds.remove(orderId);

      if (!mounted) return;

      if (result == 'accepted') {
        _showSnackBar(
          'Order accepted by you',
          backgroundColor: AppColors.success,
        );
        await _loadOrders(showLoading: false);
        _focusAcceptedOrder(orderId);
      } else if (result == 'already_accepted') {
        _showSnackBar(
          'Order already accepted',
          backgroundColor: AppColors.warning,
        );
        await _loadOrders(showLoading: false);
      }

      _tryShowNextOrderPopup();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSocketFallbackPolling();
    _removeSocketListeners();
    _statusUpdateInFlightOrderIds.clear();
    _queuedStatusAdvances.clear();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReadOnlyLocked = _isReadOnlyLocked;
    final isTablesOnly = widget.showTablesOnly;
    final isPreviousOrdersTab =
        !isTablesOnly && !_isWaiter && _tabController.index == 2;
    final showOrderSearch =
        !isTablesOnly && (_isWaiter || _tabController.index >= 1);
    final showOrderDateRange = showOrderSearch;
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Order Management'),
          automaticallyImplyLeading: widget.showBackButton ?? false,
          leading: (widget.showBackButton ?? false)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded),
                  onPressed: () => Navigator.pop(context),
                )
              : null,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isTablesOnly ? 'Tables' : 'Order Management'),
        automaticallyImplyLeading: widget.showBackButton ?? false,
        leading: (widget.showBackButton ?? false)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: isReadOnlyLocked ? null : () => _openQRScanner(),
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
        bottom: isTablesOnly
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: AppColors.textLight,
                labelColor: AppColors.textLight,
                unselectedLabelColor:
                    AppColors.textLight.withValues(alpha: 0.7),
                labelStyle: TextStyle(fontWeight: FontWeight.w600),
                unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal),
                tabs: _isWaiter
                    ? const [
                        Tab(text: 'Dine In'),
                        Tab(text: 'Takeaway'),
                      ]
                    : const [
                        Tab(text: 'Tables'),
                        Tab(text: 'Active Orders'),
                        Tab(text: 'Previous Orders'),
                      ],
              ),
      ),
      body: Column(
        children: [
          if (isReadOnlyLocked)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You have checked out for today. Read-only mode active.',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (showOrderSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search order ID, table, token, customer, items...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _orderSearchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            setState(() {
                              _orderSearchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
                onChanged: (value) {
                  setState(() {
                    _orderSearchQuery = value;
                  });
                },
              ),
            ),
          if (showOrderDateRange)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 8,
                  children: isPreviousOrdersTab
                      ? [
                          _buildOrderDateRangeChip(
                            'today',
                            'Today',
                            selectedValue: _previousOrderDateRange,
                            onChanged: (value) {
                              _previousOrderDateRange = value;
                            },
                          ),
                          _buildOrderDateRangeChip(
                            'yesterday',
                            'Yesterday',
                            selectedValue: _previousOrderDateRange,
                            onChanged: (value) {
                              _previousOrderDateRange = value;
                            },
                          ),
                          _buildOrderDateRangeChip(
                            'weekly',
                            'Weekly',
                            selectedValue: _previousOrderDateRange,
                            onChanged: (value) {
                              _previousOrderDateRange = value;
                            },
                          ),
                          _buildOrderDateRangeChip(
                            'all',
                            'All',
                            selectedValue: _previousOrderDateRange,
                            onChanged: (value) {
                              _previousOrderDateRange = value;
                            },
                          ),
                        ]
                      : [
                          _buildOrderDateRangeChip(
                            'today',
                            'Today',
                            selectedValue: _orderDateRange,
                            onChanged: (value) {
                              _orderDateRange = value;
                            },
                          ),
                          _buildOrderDateRangeChip(
                            'weekly',
                            'Weekly',
                            selectedValue: _orderDateRange,
                            onChanged: (value) {
                              _orderDateRange = value;
                            },
                          ),
                          _buildOrderDateRangeChip(
                            'monthly',
                            'Monthly',
                            selectedValue: _orderDateRange,
                            onChanged: (value) {
                              _orderDateRange = value;
                            },
                          ),
                          _buildOrderDateRangeChip(
                            'all',
                            'All',
                            selectedValue: _orderDateRange,
                            onChanged: (value) {
                              _orderDateRange = value;
                            },
                          ),
                        ],
                ),
              ),
            ),
          Expanded(
            child: _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 64, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text(_errorMessage!),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: isTablesOnly
                        ? _buildTablesView()
                        : TabBarView(
                            controller: _tabController,
                            children: _isWaiter
                                ? [
                                    _buildFilteredOrdersView('DINE_IN'),
                                    _buildFilteredOrdersView('TAKEAWAY'),
                                  ]
                                : [
                                    _buildTablesView(),
                                    _buildActiveOrdersView(),
                                    _buildPreviousOrdersView(),
                                  ],
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: isTablesOnly
          ? null
          : FloatingActionButton.extended(
              heroTag: 'orders_fab',
              onPressed: () {
                if (_isWaiter) {
                  final isTakeaway = _tabController.index == 1;
                  _showNewOrderSheet(
                      initialServiceType: isTakeaway ? 'TAKEAWAY' : 'DINE_IN');
                } else {
                  _showNewOrderSheet();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Order'),
            ),
    );
  }

  List<TableModel> _tableGridTables() {
    return _tables.where((table) {
      final qrContextType = (table.qrContextType ?? '').trim().toUpperCase();
      return qrContextType == 'TABLE';
    }).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  Widget _buildTablesView() {
    final displayTables = _tableGridTables();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend and Total Seats
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildLegendItem('Available', AppColors.success),
                  _buildLegendItem('Occupied', AppColors.warning),
                  _buildLegendItem('Selected', AppColors.primary),
                  _buildLegendItem('Merged', AppColors.info),
                  if (_selectedTablesForMerge.isNotEmpty)
                    _buildLegendItem('Merge', AppColors.primary),
                ],
              ),
              const SizedBox(height: 12),
              // Total seats available
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.event_seat,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    Text(
                      'Total Available Seats:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${displayTables.where((table) => !table.isMerged).fold<int>(0, (sum, table) => sum + table.availableSeats)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      '(${displayTables.where((table) => !table.isMerged).length} tables)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedTablesForMerge.isNotEmpty) ...[
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.merge_type,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Long press to select tables for merging (${_selectedTablesForMerge.length}/3)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedTablesForMerge.clear();
                          });
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                        ),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ).animate().fadeIn(),

          const SizedBox(height: 24),

          // Tables Grid
          displayTables.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'No tables available',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: displayTables.length,
                  itemBuilder: (context, index) {
                    final table = displayTables[index];
                    final isSelected = _selectedTable == table.number;
                    final isOccupied = table.isOccupied;
                    final isSelectedForMerge =
                        _selectedTablesForMerge.contains(table.id);
                    final isMerged = table.isMerged;
                    final hasMergedTables = table.hasMergedTables;

                    // Count orders for this table (including merged tables)
                    final tableOrders = _activeOrders.where((o) {
                      if (o.tableNumber == table.number.toString() ||
                          o.tableId == table.id) {
                        return true;
                      }
                      // Also count orders from merged tables
                      if (hasMergedTables && table.mergedTables != null) {
                        final mergedTableNumbers =
                            table.mergedTables!.map((mergedId) {
                          final mergedTable = displayTables.firstWhere(
                            (t) => t.id == mergedId,
                            orElse: () => table,
                          );
                          return mergedTable.number.toString();
                        }).toList();
                        return mergedTableNumbers.contains(o.tableNumber) ||
                            table.mergedTables!.contains(o.tableId);
                      }
                      return false;
                    }).length;

                    return GestureDetector(
                      onTap: () {
                        // If in merge mode, toggle selection
                        if (_selectedTablesForMerge.isNotEmpty) {
                          setState(() {
                            if (isSelectedForMerge) {
                              _selectedTablesForMerge.remove(table.id);
                            } else if (_selectedTablesForMerge.length < 3) {
                              _selectedTablesForMerge.add(table.id);
                              // Show merge dialog when 2 or 3 tables are selected (with delay for animation)
                              if (_selectedTablesForMerge.length >= 2) {
                                Future.delayed(
                                    const Duration(milliseconds: 300), () {
                                  if (mounted) {
                                    _showMergeConfirmationDialog();
                                  }
                                });
                              }
                            }
                          });
                        } else {
                          // Normal tap behavior
                          setState(() => _selectedTable = table.number);
                          // If table is merged or has merged tables, show unmerge modal
                          if (isMerged || hasMergedTables) {
                            _showUnmergeConfirmationDialog(table);
                          } else if (isOccupied) {
                            _showTableDetails(table);
                          }
                        }
                      },
                      onLongPress: () {
                        setState(() {
                          if (isSelectedForMerge) {
                            _selectedTablesForMerge.remove(table.id);
                          } else if (_selectedTablesForMerge.length < 3) {
                            _selectedTablesForMerge.add(table.id);
                            // Show merge dialog when 2 or 3 tables are selected (with delay for animation)
                            if (_selectedTablesForMerge.length >= 2) {
                              Future.delayed(const Duration(milliseconds: 500),
                                  () {
                                if (mounted) {
                                  _showMergeConfirmationDialog();
                                }
                              });
                            }
                          } else {
                            _showSnackBar(
                              'You can only merge up to 3 tables at a time',
                              backgroundColor: AppColors.warning,
                            );
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          color: isSelectedForMerge
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : isMerged
                                  ? AppColors.info.withValues(alpha: 0.2)
                                  : isSelected
                                      ? AppColors.primary
                                      : isOccupied
                                          ? AppColors.warning
                                              .withValues(alpha: 0.2)
                                          : AppColors.success
                                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelectedForMerge
                                ? AppColors.primary
                                : isMerged
                                    ? AppColors.info
                                    : isSelected
                                        ? AppColors.primary
                                        : isOccupied
                                            ? AppColors.warning
                                            : AppColors.success,
                            width:
                                isSelectedForMerge ? 3 : (isMerged ? 2.5 : 2),
                          ),
                          boxShadow: isSelectedForMerge || isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.4),
                                    blurRadius: isSelectedForMerge ? 15 : 10,
                                    spreadRadius: isSelectedForMerge ? 2 : 0,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isCompactTile =
                                  constraints.maxHeight < 82 ||
                                      constraints.maxWidth < 72;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    children: [
                                      AnimatedScale(
                                        scale: isSelectedForMerge ? 1.2 : 1.0,
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                        child: Icon(
                                          Icons.table_restaurant,
                                          color: isSelectedForMerge
                                              ? AppColors.primary
                                              : isMerged
                                                  ? AppColors.info
                                                  : isSelected
                                                      ? AppColors.textLight
                                                      : isOccupied
                                                          ? AppColors.warning
                                                          : AppColors.success,
                                          size: 24,
                                        ),
                                      ),
                                      if (isSelectedForMerge)
                                        Positioned(
                                          right: -2,
                                          top: -2,
                                          child: TweenAnimationBuilder<double>(
                                            key: ValueKey(
                                                'badge_${table.id}_${_selectedTablesForMerge.length}'),
                                            tween: Tween(begin: 0.0, end: 1.0),
                                            duration: const Duration(
                                                milliseconds: 400),
                                            curve: Curves.elasticOut,
                                            builder: (context, value, child) {
                                              return Transform.scale(
                                                scale: value,
                                                child: Container(
                                                  width: 18,
                                                  height: 18,
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color:
                                                          AppColors.textLight,
                                                      width: 1.5,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: AppColors.primary
                                                            .withValues(
                                                                alpha: 0.6),
                                                        blurRadius: 6,
                                                        spreadRadius: 1,
                                                      ),
                                                    ],
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      '${_selectedTablesForMerge.toList().indexOf(table.id) + 1}',
                                                      style: const TextStyle(
                                                        color:
                                                            AppColors.textLight,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: isCompactTile ? 1 : 2),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 300),
                                    style: TextStyle(
                                      fontSize: isCompactTile ? 11 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelectedForMerge
                                          ? AppColors.primary
                                          : isMerged
                                              ? AppColors.info
                                              : isSelected
                                                  ? AppColors.textLight
                                                  : Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.color,
                                    ),
                                    child: Text(
                                      'T${table.number}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // Status indicators in one line
                                  if (!isCompactTile) ...[
                                    const SizedBox(height: 3),
                                    Wrap(
                                      spacing: 3,
                                      runSpacing: 3,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        // Show merged indicator
                                        if (isMerged)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.info
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: AppColors.info
                                                    .withValues(alpha: 0.3),
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.merge_type,
                                                  size: 9,
                                                  color: AppColors.info,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  'Merged',
                                                  style: TextStyle(
                                                    fontSize: 8,
                                                    color: AppColors.info,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        // Show merged tables info for primary table (compact)
                                        if (hasMergedTables &&
                                            table.mergedTables != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.3),
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.merge_type,
                                                  size: 9,
                                                  color: AppColors.primary,
                                                ),
                                                const SizedBox(width: 2),
                                                ...table.mergedTables!
                                                    .take(2)
                                                    .map((mergedId) {
                                                  final mergedTable =
                                                      displayTables.firstWhere(
                                                    (t) => t.id == mergedId,
                                                    orElse: () => table,
                                                  );
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 2),
                                                    child: Text(
                                                      'T${mergedTable.number}',
                                                      style: TextStyle(
                                                        fontSize: 8,
                                                        color:
                                                            AppColors.primary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  );
                                                }),
                                                if (table.mergedTables!.length >
                                                    2)
                                                  Text(
                                                    '+${table.mergedTables!.length - 2}',
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                      color: AppColors.primary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        // Show available seats (only on primary tables, not on merged secondary tables)
                                        if (!isMerged)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: (isOccupied
                                                      ? AppColors.warning
                                                      : AppColors.success)
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: (isOccupied
                                                        ? AppColors.warning
                                                        : AppColors.success)
                                                    .withValues(alpha: 0.3),
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.event_seat,
                                                  size: 9,
                                                  color: isOccupied
                                                      ? AppColors.warning
                                                      : AppColors.success,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '${table.availableSeats}',
                                                  style: TextStyle(
                                                    fontSize: 8,
                                                    color: isOccupied
                                                        ? AppColors.warning
                                                        : AppColors.success,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        // Show orders count
                                        if (isOccupied && tableOrders > 0)
                                          AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 300),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelectedForMerge
                                                  ? AppColors.primary
                                                      .withValues(alpha: 0.2)
                                                  : isSelected
                                                      ? AppColors.textLight
                                                          .withValues(
                                                              alpha: 0.3)
                                                      : AppColors.primary
                                                          .withValues(
                                                              alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.3),
                                                width: 0.5,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.shopping_cart,
                                                  size: 9,
                                                  color: isSelectedForMerge
                                                      ? AppColors.primary
                                                      : isSelected
                                                          ? AppColors.textLight
                                                          : AppColors.primary,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '$tableOrders',
                                                  style: TextStyle(
                                                    fontSize: 8,
                                                    color: isSelectedForMerge
                                                        ? AppColors.primary
                                                        : isSelected
                                                            ? AppColors
                                                                .textLight
                                                            : AppColors.primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 2),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isMerged
                                            ? AppColors.info
                                            : isOccupied
                                                ? AppColors.warning
                                                : AppColors.success,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.textLight
                                              .withValues(alpha: 0.5),
                                          width: 0.8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: 50 * index));
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildFilteredOrdersView(String serviceType) {
    final serviceFiltered = _activeOrders
        .where((o) => _matchesOrderServiceTab(o, serviceType))
        .toList();
    final dateFiltered = _applyOrderDateRange(serviceFiltered);
    final filtered = _applyOrderSearch(dateFiltered);
    if (filtered.isEmpty) {
      final isSearching = _orderSearchQuery.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                serviceType == 'TAKEAWAY'
                    ? Icons.takeout_dining
                    : Icons.restaurant,
                size: 64,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                isSearching
                    ? 'No matching orders found'
                    : 'No ${serviceType == 'TAKEAWAY' ? 'takeaway' : 'dine-in'} orders',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                isSearching
                    ? 'Try a different keyword'
                    : 'Tap Create Order to add one',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final order = filtered[index];
        return _buildOrderCard(order)
            .animate()
            .fadeIn(delay: Duration(milliseconds: 100 * index))
            .slideX(begin: 0.1);
      },
    );
  }

  Widget _buildActiveOrdersView() {
    final filtered = _applyOrderSearch(_applyOrderDateRange(_activeOrders));

    if (filtered.isEmpty) {
      final isSearching = _orderSearchQuery.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long,
                  size: 64, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              Text(
                isSearching ? 'No matching orders found' : 'No active orders',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (isSearching) ...[
                const SizedBox(height: 8),
                Text(
                  'Try a different keyword',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final order = filtered[index];
        return _buildOrderCard(order)
            .animate()
            .fadeIn(delay: Duration(milliseconds: 100 * index))
            .slideX(begin: 0.1);
      },
    );
  }

  Widget _buildPreviousOrdersView() {
    final filtered = _applyOrderSearch(
      _applyOrderDateRange(
        _previousOrders,
        selectedRange: _previousOrderDateRange,
      ),
    );

    if (filtered.isEmpty) {
      final isSearching = _orderSearchQuery.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history_outlined,
                size: 64,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                isSearching ? 'No matching orders found' : 'No previous orders',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                isSearching
                    ? 'Try a different keyword'
                    : 'Completed and paid orders will appear here',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final order = filtered[index];
        return _buildOrderCard(order, isHistoryView: true)
            .animate()
            .fadeIn(delay: Duration(milliseconds: 100 * index))
            .slideX(begin: 0.1);
      },
    );
  }

  Widget _buildOrderCard(OrderModel order, {bool isHistoryView = false}) {
    final status = OrderStatusUtils.normalizeStatus(order.status);
    final paymentStatus = OrderStatusUtils.normalizePaymentStatus(
      order.paymentStatus,
      status: order.status,
      isPaid: order.isPaid,
    );
    final paymentTypeLabel =
        paymentStatus == OrderStatusUtils.paymentPaid ? 'PAID' : 'CASH';
    final isSettled = _isOrderSettled(order);

    Color statusColor;
    switch (status) {
      case OrderStatusUtils.statusNew:
        statusColor = AppColors.info;
        break;
      case OrderStatusUtils.statusPreparing:
        statusColor = AppColors.warning;
        break;
      case OrderStatusUtils.statusReady:
        statusColor = AppColors.success;
        break;
      case OrderStatusUtils.statusServed:
        statusColor = isSettled ? AppColors.textSecondary : AppColors.primary;
        break;
      default:
        statusColor = AppColors.textSecondary;
    }
    final statusLabel = status == OrderStatusUtils.statusServed
        ? (paymentStatus == OrderStatusUtils.paymentPaid
            ? 'SERVED - PAID'
            : 'SERVED - PENDING PAYMENT')
        : status;

    final itemNames = <String>[
      ...order.activeItems.map((item) => item.name),
      ...order.selectedAddons.map((addon) => '(+) ${addon.name}'),
    ];
    final itemPreviewCount = itemNames.length > 2 ? 2 : itemNames.length;
    final previewItems = itemNames.take(itemPreviewCount).join(', ');
    final remainingItems = itemNames.length - itemPreviewCount;
    final timeAgo = _getTimeAgo(order.createdAt);
    final isTakeawayLike = _isTakeawayLikeOrder(order);
    final serviceLabel = _serviceTypeLabel(order);
    final shortOrderId = order.id.length > 8
        ? order.id.substring(order.id.length - 8)
        : order.id;
    final totalItemsCount = order.activeItems.fold<int>(
          0,
          (sum, item) => sum + item.quantity,
        ) +
        order.selectedAddons.fold<int>(
          0,
          (sum, addon) => sum + addon.quantity,
        );

    IconData serviceIcon = Icons.table_restaurant;
    Color serviceColor = AppColors.primary;
    if (serviceLabel == 'Delivery') {
      serviceIcon = Icons.delivery_dining;
      serviceColor = AppColors.info;
    } else if (serviceLabel == 'Takeaway' || serviceLabel == 'Pickup') {
      serviceIcon = Icons.takeout_dining;
      serviceColor = AppColors.warning;
    }
    final paymentChipColor = paymentStatus == OrderStatusUtils.paymentPaid
        ? AppColors.success
        : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.pureBlack.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Order #$shortOrderId',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: serviceColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            serviceIcon,
                            size: 14,
                            color: serviceColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            serviceLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: serviceColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isTakeawayLike &&
                        order.tableNumber != null &&
                        order.tableNumber!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Table ${order.tableNumber}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    if (order.takeawayToken != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Token ${order.takeawayToken}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: paymentChipColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        paymentTypeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: paymentChipColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (order.customerName?.isNotEmpty == true ||
                    order.customerMobile?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${order.customerName ?? ''} ${order.customerMobile ?? ''}'
                        .trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
                if (order.assignedStaff?.name != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Assigned to ${order.assignedStaff!.name}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  itemNames.isEmpty
                      ? 'No items added yet'
                      : remainingItems > 0
                          ? '$previewItems +$remainingItems more'
                          : previewItems,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$timeAgo • $totalItemsCount item${totalItemsCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    Text(
                      '\u20B9${order.totalAmount.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Builder(
              builder: (context) {
                if (isHistoryView) {
                  return Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _showOrderDetailsModal(order);
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                          ),
                          child: const Text('View Details'),
                        ),
                      ),
                    ],
                  );
                }

                final appProvider =
                    Provider.of<AppProvider>(context, listen: false);
                final canAdminOrders = [
                  'admin',
                  'franchise_admin',
                  'super_admin'
                ].contains(appProvider.userRole);
                final canAdvanceStatus =
                    _nextCanonicalStatus(order) != null || _canMarkPaid(order);
                return Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _showOrderDetailsModal(order);
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        child: const Text('View Details'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: canAdvanceStatus
                            ? () => _queueOrderStatusAdvance(order.id)
                            : null,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          backgroundColor: AppColors.primary,
                        ),
                        child: Text(
                          _getNextStatusButtonText(order),
                        ),
                      ),
                    ),
                    if (canAdminOrders) ...[
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        padding: EdgeInsets.zero,
                        onSelected: (value) =>
                            _handleAdminOrderAction(order, value, context),
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                              value: 'add_items', child: Text('Add Items')),
                          const PopupMenuItem(
                              value: 'return_items',
                              child: Text('Return Items')),
                          if (_isDineInServiceType(order.serviceType))
                            const PopupMenuItem(
                                value: 'convert_takeaway',
                                child: Text('Convert to Takeaway')),
                          if (OrderStatusUtils.normalizeStatus(order.status) !=
                                  OrderStatusUtils.statusServed ||
                              !OrderStatusUtils.isSettled(
                                status: order.status,
                                paymentStatus: order.paymentStatus,
                                isPaid: order.isPaid,
                              ))
                            const PopupMenuItem(
                                value: 'finalize', child: Text('Finalize')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) => DateTimeUtils.getTimeAgo(dateTime);

  void _queueOrderStatusAdvance(String orderId) {
    if (orderId.trim().isEmpty) return;
    final pending = _queuedStatusAdvances[orderId] ?? 0;
    // Keep a small queue so rapid taps are handled, but avoid overshooting.
    _queuedStatusAdvances[orderId] = pending >= 3 ? 3 : pending + 1;
    _processQueuedStatusAdvances(orderId);
  }

  OrderModel _buildOptimisticStatusOrder({
    required OrderModel source,
    required String newStatus,
    required bool markPaid,
  }) {
    final nextPaymentStatus =
        markPaid ? OrderStatusUtils.paymentPaid : source.paymentStatus;
    final payload = source.toJson();
    payload['status'] = newStatus;
    payload['rawStatus'] = newStatus;
    payload['lifecycleStatus'] = newStatus;
    payload['paymentStatus'] = nextPaymentStatus;
    payload['isPaid'] = markPaid || source.isPaid;
    payload['updatedAt'] = DateTime.now().toIso8601String();
    if (markPaid) {
      payload['paidAt'] = DateTime.now().toIso8601String();
    }
    return OrderModel.fromJson(payload);
  }

  Future<void> _processQueuedStatusAdvances(String orderId) async {
    if (_statusUpdateInFlightOrderIds.contains(orderId)) return;
    _statusUpdateInFlightOrderIds.add(orderId);

    try {
      while (mounted && (_queuedStatusAdvances[orderId] ?? 0) > 0) {
        _queuedStatusAdvances[orderId] =
            (_queuedStatusAdvances[orderId] ?? 1) - 1;

        final orderIndex = _activeOrders.indexWhere((o) => o.id == orderId);
        if (orderIndex < 0 || orderIndex >= _activeOrders.length) {
          _queuedStatusAdvances.remove(orderId);
          break;
        }

        final currentOrder = _activeOrders[orderIndex];
        final shouldMarkPaid = _canMarkPaid(currentOrder);
        final newStatus = _nextCanonicalStatus(currentOrder) ??
            (shouldMarkPaid ? OrderStatusUtils.statusServed : null);

        if (newStatus == null) {
          // Nothing else to advance for this order.
          _queuedStatusAdvances.remove(orderId);
          break;
        }

        final optimisticOrder = _buildOptimisticStatusOrder(
          source: currentOrder,
          newStatus: newStatus,
          markPaid: shouldMarkPaid,
        );

        if (mounted) {
          setState(() {
            if (orderIndex >= 0 && orderIndex < _activeOrders.length) {
              _activeOrders[orderIndex] = optimisticOrder;
            }
          });
        }

        try {
          await _orderService.updateOrderStatus(
            currentOrder.id,
            newStatus,
            paymentStatus: shouldMarkPaid ? OrderStatusUtils.paymentPaid : null,
          );
        } catch (e) {
          if (mounted) {
            final revertIndex =
                _activeOrders.indexWhere((o) => o.id == orderId);
            setState(() {
              if (revertIndex >= 0 && revertIndex < _activeOrders.length) {
                _activeOrders[revertIndex] = currentOrder;
              }
            });
            _showSnackBar(
              e is ApiException
                  ? e.message
                  : 'Failed to update order: ${e.toString()}',
              backgroundColor: AppColors.error,
            );
          }
          _queuedStatusAdvances.remove(orderId);
          break;
        }
      }
    } finally {
      _statusUpdateInFlightOrderIds.remove(orderId);
      if ((_queuedStatusAdvances[orderId] ?? 0) <= 0) {
        _queuedStatusAdvances.remove(orderId);
      }
      if (mounted) {
        _loadOrders(showLoading: false);
      }
    }
  }

  String? _nextCanonicalStatus(OrderModel order) {
    final currentStatus = OrderStatusUtils.normalizeStatus(order.status);
    switch (currentStatus) {
      case OrderStatusUtils.statusNew:
        return OrderStatusUtils.statusPreparing;
      case OrderStatusUtils.statusPreparing:
        return OrderStatusUtils.statusReady;
      case OrderStatusUtils.statusReady:
        return OrderStatusUtils.statusServed;
      default:
        return null;
    }
  }

  bool _canMarkPaid(OrderModel order) {
    final currentStatus = OrderStatusUtils.normalizeStatus(order.status);
    if (currentStatus != OrderStatusUtils.statusServed) return false;
    final paymentStatus = OrderStatusUtils.normalizePaymentStatus(
      order.paymentStatus,
      status: order.status,
      isPaid: order.isPaid,
    );
    return paymentStatus != OrderStatusUtils.paymentPaid;
  }

  String _getNextStatusButtonText(OrderModel order) {
    final currentStatus = OrderStatusUtils.normalizeStatus(order.status);
    final paymentStatus = OrderStatusUtils.normalizePaymentStatus(
      order.paymentStatus,
      status: order.status,
      isPaid: order.isPaid,
    );
    // Accept-order assignment flow disabled.
    /*
    if (_canAcceptAssignment(order)) {
      return 'Accept Order';
    }
    */

    switch (currentStatus) {
      case OrderStatusUtils.statusNew:
        return 'Start Preparing';
      case OrderStatusUtils.statusPreparing:
        return 'Mark Ready';
      case OrderStatusUtils.statusReady:
        return 'Mark Served';
      case OrderStatusUtils.statusServed:
        if (paymentStatus == OrderStatusUtils.paymentPaid) {
          return 'Paid';
        }
        return 'Mark Paid';
      default:
        return 'Update';
    }
  }

  void _showBillForTable(TableModel table) {
    // Find all active orders for this table
    final ordersForTable = _activeOrders.where((o) {
      return o.tableNumber == table.number.toString() || o.tableId == table.id;
    }).toList();

    if (ordersForTable.isEmpty) {
      _showSnackBar(
        'No active orders for this table yet.',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    // Aggregate all item/add-on lines using the same invoice structure as web.
    final Map<String, Map<String, dynamic>> aggregatedItems = {};

    void addLine({
      required String name,
      required int quantity,
      required double unitPriceRupees,
    }) {
      if (quantity <= 0 || unitPriceRupees < 0) {
        return;
      }
      final key = name.trim();
      if (key.isEmpty) {
        return;
      }

      final amount = unitPriceRupees * quantity;
      final existing = aggregatedItems[key];
      if (existing == null) {
        aggregatedItems[key] = {
          'name': key,
          'quantity': quantity,
          'unitPrice': unitPriceRupees,
          'pricePaise': unitPriceRupees * 100,
          'amount': amount,
        };
        return;
      }

      existing['quantity'] = (existing['quantity'] as int) + quantity;
      existing['amount'] = (existing['amount'] as double) + amount;
    }

    for (final order in ordersForTable) {
      for (final item in order.activeItems) {
        addLine(
          name: item.name,
          quantity: item.quantity,
          unitPriceRupees: item.unitPrice,
        );
      }
      for (final addon in order.selectedAddons) {
        addLine(
          name: '(+) ${addon.name}',
          quantity: addon.quantity,
          unitPriceRupees: addon.price,
        );
      }
    }

    final itemsList = aggregatedItems.values.toList(growable: false);
    final subtotal = itemsList.fold<double>(
      0.0,
      (sum, item) => sum + (item['amount'] as double? ?? 0.0),
    );
    final total = subtotal;
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final role = appProvider.userRole;
    final canPrint = role == 'manager' || role == 'waiter' || role == 'captain';
    final OrderModel? orderForPrint = () {
      final withKot =
          ordersForTable.where((o) => o.kotLines.isNotEmpty).toList();
      if (withKot.isNotEmpty) return withKot.last;
      if (ordersForTable.isNotEmpty) return ordersForTable.last;
      return null;
    }();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Bill - Table ${table.number}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ordersForTable.length} active order(s)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 16),

                // Items list
                if (itemsList.isNotEmpty)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: ListView.separated(
                      itemCount: itemsList.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 12, thickness: 0.5),
                      itemBuilder: (context, index) {
                        final item = itemsList[index];
                        final name = item['name'] as String;
                        final quantity = item['quantity'] as int;
                        final unitPrice = item['unitPrice'] as double? ?? 0.0;
                        final lineTotal =
                            item['amount'] as double? ?? (unitPrice * quantity);

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '$name x$quantity',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '\u20B9${lineTotal.toStringAsFixed(2)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        );
                      },
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No items found for this bill.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),

                const SizedBox(height: 16),
                const Divider(thickness: 0.8),
                const SizedBox(height: 8),

                // Summary
                if (subtotal > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal'),
                      Text('\u20B9${subtotal.toStringAsFixed(2)}'),
                    ],
                  ),
                  // GST removed for now:
                  // Row(
                  //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  //   children: [const Text('GST'), Text('\u20B9${gst.toStringAsFixed(2)}')],
                  // ),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '\u20B9${total.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                    ),
                  ],
                ),
                if (canPrint &&
                    (orderForPrint != null ||
                        (ordersForTable.length > 1 &&
                            itemsList.isNotEmpty))) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text('Print Bill'),
                    onPressed: () async {
                      try {
                        await _printBillForOrder(
                          ordersForTable.length > 1 ? null : orderForPrint,
                          table: table,
                          ordersForTable: ordersForTable,
                          aggregatedItems: ordersForTable.length > 1
                              ? {
                                  'items': itemsList,
                                  'subtotal': subtotal,
                                  'total': total,
                                }
                              : null,
                        );
                        if (mounted) {
                          Navigator.pop(context);
                          _showSnackBar(
                            'Bill sent to printer',
                            backgroundColor: AppColors.success,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          _showSnackBar(
                            e is ApiException
                                ? e.message
                                : 'Failed to print bill',
                            backgroundColor: AppColors.error,
                          );
                        }
                      }
                    },
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _printBillForOrder(
    OrderModel? order, {
    TableModel? table,
    List<OrderModel>? ordersForTable,
    Map<String, dynamic>? aggregatedItems,
  }) async {
    Map<String, dynamic> orderMap;
    if (aggregatedItems != null &&
        ordersForTable != null &&
        ordersForTable.isNotEmpty) {
      final first = ordersForTable.first;
      final items = (aggregatedItems['items'] as List)
          .map<Map<String, dynamic>>((i) => {
                'name': i['name'],
                'quantity': i['quantity'],
                // ESC/POS formatter expects item price in paise.
                'price': i['pricePaise'] ?? 0,
                'returned': false,
              })
          .toList();
      orderMap = {
        '_id': first.id,
        'cartId': first.cartId,
        'tableNumber':
            (table != null ? table.number : first.tableNumber)?.toString() ??
                'N/A',
        'serviceType': first.serviceType,
        'takeawayToken': first.takeawayToken,
        'customerName': first.customerName,
        'customerMobile': first.customerMobile,
        'kotLines': [
          {
            'items': items,
            'subtotal': aggregatedItems['subtotal'],
            // GST removed for now.
            'gst': 0,
            'totalAmount': aggregatedItems['total'],
          },
        ],
      };
    } else if (order != null) {
      orderMap = order.toJson();
      orderMap['_id'] = order.id;
      orderMap['printStatus'] = {
        'kotPrinted': order.kotPrinted,
        'billPrinted': order.billPrinted,
      };
      orderMap['takeawayToken'] = order.takeawayToken;
      orderMap['customerName'] = order.customerName;
      orderMap['customerMobile'] = order.customerMobile;
    } else {
      throw ApiException(message: 'No order to print');
    }
    await PrintService().reprintBill(orderMap);
  }

  void _showOrderDetailsModal(OrderModel order) {
    final items = order.activeItems;
    final addons = order.selectedAddons
        .where((addon) => addon.quantity > 0)
        .toList(growable: false);
    final subtotal = order.subtotalAmount;
    final total = order.totalAmount;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Details',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: AppColors.textLight,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Order #${order.id}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color:
                                    AppColors.textLight.withValues(alpha: 0.9),
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.textLight),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order Info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isTakeawayLikeOrder(order)
                                    ? ((order.orderType ?? '').toUpperCase() ==
                                            'DELIVERY'
                                        ? Icons.delivery_dining
                                        : Icons.shopping_bag)
                                    : Icons.table_restaurant,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_serviceTypeLabel(order)} Order',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Status:',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColorForModal(order.status)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  order.status,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        _getStatusColorForModal(order.status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!_isTakeawayLikeOrder(order) &&
                              order.tableNumber != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Table:',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                Text(
                                  order.tableNumber!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ],
                          if (order.takeawayToken != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Token:',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                Text(
                                  order.takeawayToken.toString(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.warning,
                                      ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Order Time:',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                _formatDateTimeForModal(order.createdAt),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Items List
                    Text(
                      'Order Items',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (items.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final itemPrice = item.unitPrice;
                            final lineTotal = item.lineTotal;

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Qty: ${item.quantity} x \u20B9${itemPrice.toStringAsFixed(2)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.textSecondary,
                                              ),
                                        ),
                                        if (item.extras.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          for (final extra in item.extras)
                                            Text(
                                              '+ ${extra.name} (\u20B9${extra.price.toStringAsFixed(2)})',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        AppColors.textSecondary,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                            ),
                                        ],
                                        if (item.returned)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.error
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Returned',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: AppColors.error,
                                                      fontSize: 10,
                                                    ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '\u20B9${lineTotal.toStringAsFixed(2)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No items in this order',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ),
                    if (addons.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Add-ons',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: addons.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final addon = addons[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '(+) ${addon.name} x${addon.quantity}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    '\u20B9${addon.lineTotal.toStringAsFixed(2)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Bill Summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Bill Summary',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Subtotal:',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                '\u20B9${subtotal.toStringAsFixed(2)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                          // GST removed for now:
                          // Row(
                          //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          //   children: [
                          //     Text('GST:', style: Theme.of(context).textTheme.bodyMedium),
                          //     Text('\u20B9${gst.toStringAsFixed(2)}'),
                          //   ],
                          // ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Amount:',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                '\u20B9${total.toStringAsFixed(2)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColorForModal(String status) {
    final normalized = OrderStatusUtils.normalizeStatus(status);
    switch (normalized) {
      case OrderStatusUtils.statusNew:
        return AppColors.info;
      case OrderStatusUtils.statusPreparing:
        return AppColors.warning;
      case OrderStatusUtils.statusReady:
        return AppColors.success;
      case OrderStatusUtils.statusServed:
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatDateTimeForModal(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return DateTimeUtils.formatDateTimeIST(dateTime, 'dd/MM/yyyy hh:mm a');
  }

  Future<void> _handleAdminOrderAction(
      OrderModel order, String action, BuildContext context) async {
    try {
      switch (action) {
        case 'delete':
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Order'),
              content: Text(
                  'Delete order #${order.id.substring(0, 8)}? This cannot be undone.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete',
                        style: TextStyle(color: AppColors.error))),
              ],
            ),
          );
          if (confirm == true && mounted) {
            await _orderService.deleteOrder(order.id);
            await _loadOrders();
            _showSnackBar('Order deleted', backgroundColor: AppColors.success);
          }
          break;
        case 'finalize':
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Finalize Order'),
              content: const Text('Finalize this order? (Admin only)'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Finalize')),
              ],
            ),
          );
          if (confirm == true && mounted) {
            await _orderService.finalizeOrder(order.id);
            await _loadOrders();
            _showSnackBar('Order finalized',
                backgroundColor: AppColors.success);
          }
          break;
        case 'convert_takeaway':
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Convert to Takeaway'),
              content: const Text('Convert this dine-in order to takeaway?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Convert')),
              ],
            ),
          );
          if (confirm == true && mounted) {
            await _orderService.convertToTakeaway(order.id);
            await _loadOrders();
            _showSnackBar('Order converted to takeaway',
                backgroundColor: AppColors.success);
          }
          break;
        case 'add_items':
          _showAddItemsModal(order, context);
          break;
        case 'return_items':
          _showReturnItemsModal(order, context);
          break;
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(e is ApiException ? e.message : 'Failed: ${e.toString()}',
            backgroundColor: AppColors.error);
      }
    }
  }

  void _showAddItemsModal(OrderModel order, BuildContext parentContext) {
    final selectedItems = <Map<String, dynamic>>[];
    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Add Items',
                            style: Theme.of(context).textTheme.titleLarge),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: _allMenuItems.length,
                      itemBuilder: (context, i) {
                        final item = _allMenuItems[i];
                        final qty = selectedItems
                            .where((s) => s['name'] == item.name)
                            .fold<int>(
                                0, (sum, s) => sum + (s['quantity'] as int));
                        return ListTile(
                          title: Text(item.name),
                          subtitle: Text(
                              '\u20B9${(item.price / 100).toStringAsFixed(0)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: qty > 0
                                    ? () {
                                        final idx = selectedItems.indexWhere(
                                            (s) => s['name'] == item.name);
                                        if (idx >= 0) {
                                          selectedItems[idx]['quantity'] =
                                              (selectedItems[idx]['quantity']
                                                      as int) -
                                                  1;
                                          if (selectedItems[idx]['quantity'] <=
                                              0) selectedItems.removeAt(idx);
                                          setModalState(() {});
                                        }
                                      }
                                    : null,
                              ),
                              Text('${qty > 0 ? qty : 0}'),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () {
                                  final idx = selectedItems.indexWhere(
                                      (s) => s['name'] == item.name);
                                  if (idx >= 0) {
                                    selectedItems[idx]['quantity'] =
                                        (selectedItems[idx]['quantity']
                                                as int) +
                                            1;
                                  } else {
                                    selectedItems.add({
                                      'name': item.name,
                                      'quantity': 1,
                                      'price': item.price.toDouble()
                                    });
                                  }
                                  setModalState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: selectedItems.isEmpty
                          ? null
                          : () async {
                              final items = selectedItems
                                  .where((s) => (s['quantity'] as int) > 0)
                                  .map((s) => {
                                        'name': s['name'],
                                        'quantity': s['quantity'],
                                        'price': (s['price'] as num).toDouble(),
                                      })
                                  .toList();
                              if (items.isEmpty) return;
                              Navigator.pop(ctx);
                              try {
                                await _orderService.addItemsToOrder(
                                    order.id, items);
                                await _loadOrders();
                                if (mounted)
                                  _showSnackBar('Items added',
                                      backgroundColor: AppColors.success);
                              } catch (e) {
                                if (mounted)
                                  _showSnackBar(
                                      e is ApiException ? e.message : 'Failed',
                                      backgroundColor: AppColors.error);
                              }
                            },
                      child: Text(
                          'Add ${selectedItems.fold<int>(0, (s, i) => s + (i['quantity'] as int))} items'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showReturnItemsModal(OrderModel order, BuildContext parentContext) {
    final selected = <Map<String, dynamic>>[];
    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Return Items',
                            style: Theme.of(context).textTheme.titleLarge),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: order.kotLines.length,
                      itemBuilder: (context, kotIdx) {
                        final kot = order.kotLines[kotIdx];
                        final kotDisplayNumber =
                            (kot.kotNumber != null && kot.kotNumber! > 0)
                                ? kot.kotNumber!
                                : kotIdx + 1;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                  'KOT #${kotDisplayNumber.toString().padLeft(2, '0')}',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                            ),
                            ...kot.items.asMap().entries.map((e) {
                              final itemIdx = e.key;
                              final item = e.value;
                              final isSelected = selected.any((s) =>
                                  s['kotIndex'] == kotIdx &&
                                  s['itemIndex'] == itemIdx);
                              return CheckboxListTile(
                                title: Text('${item.name} x${item.quantity}'),
                                value: isSelected,
                                onChanged: (v) {
                                  if (v == true) {
                                    selected.add({
                                      'kotIndex': kotIdx,
                                      'itemIndex': itemIdx
                                    });
                                  } else {
                                    selected.removeWhere((s) =>
                                        s['kotIndex'] == kotIdx &&
                                        s['itemIndex'] == itemIdx);
                                  }
                                  setModalState(() {});
                                },
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              try {
                                await _orderService.returnItems(
                                    order.id, selected);
                                await _loadOrders();
                                if (mounted)
                                  _showSnackBar('Items returned',
                                      backgroundColor: AppColors.success);
                              } catch (e) {
                                if (mounted)
                                  _showSnackBar(
                                      e is ApiException ? e.message : 'Failed',
                                      backgroundColor: AppColors.error);
                              }
                            },
                      child: Text('Return ${selected.length} item(s)'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showStatusUpdateModal(OrderModel order) {
    // Canonical flow: NEW -> PREPARING -> READY -> SERVED
    final currentStatus = OrderStatusUtils.normalizeStatus(order.status);

    print(
        '[ORDERS_SCREEN] Status update modal - Order: ${order.id}, ServiceType: ${order.serviceType}, CurrentStatus: $currentStatus');

    // Get available next statuses based on current status
    List<String> availableStatuses;
    switch (currentStatus) {
      case OrderStatusUtils.statusNew:
        availableStatuses = [OrderStatusUtils.statusPreparing];
        break;
      case OrderStatusUtils.statusPreparing:
        availableStatuses = [OrderStatusUtils.statusReady];
        break;
      case OrderStatusUtils.statusReady:
        availableStatuses = [OrderStatusUtils.statusServed];
        break;
      default:
        availableStatuses = <String>[];
        break;
    }

    print('[ORDERS_SCREEN] Available statuses: $availableStatuses');

    if (availableStatuses.isEmpty) {
      _showSnackBar(
        'No status updates available for ${currentStatus} status',
      );
      return;
    }

    // Capture parent context before showing modal
    final parentContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.transparent,
      isScrollControlled: true,
      builder: (modalContext) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(modalContext).size.height * 0.75,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(modalContext).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Update Order Status',
                    style:
                        Theme.of(modalContext).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(modalContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Order #${order.id.substring(0, 8)}',
                style: Theme.of(modalContext).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusColorForModal(currentStatus)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Current Status:',
                      style: Theme.of(modalContext).textTheme.bodyMedium,
                    ),
                    Text(
                      currentStatus,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColorForModal(currentStatus),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Select New Status:',
                style: Theme.of(modalContext).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              ...availableStatuses.map((status) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(modalContext); // Close modal first

                        try {
                          await _orderService.updateOrderStatus(
                              order.id, status);

                          // Wait a bit to ensure modal is fully closed before using context
                          await Future.delayed(
                              const Duration(milliseconds: 100));

                          await _loadOrders();

                          // Use parent context for snackbar (not modal context)
                          _showSnackBarWithContext(
                            parentContext,
                            'Order status updated to $status',
                            backgroundColor: AppColors.success,
                          );
                        } catch (e) {
                          // Use parent context for snackbar (not modal context)
                          _showSnackBarWithContext(
                            parentContext,
                            e is ApiException
                                ? e.message
                                : 'Failed to update order: ${e.toString()}',
                            backgroundColor: AppColors.error,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        backgroundColor: _getStatusColorForModal(status)
                            .withValues(alpha: 0.1),
                        foregroundColor: _getStatusColorForModal(status),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            status,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward,
                            size: 18,
                            color: _getStatusColorForModal(status),
                          ),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showTableDetails(TableModel table) {
    final parentContext = context;

    showModalBottomSheet(
      context: parentContext,
      backgroundColor: AppColors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Table ${table.number}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_activeOrders.where((o) => o.tableNumber == table.number.toString() || o.tableId == table.id).length} active orders',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Close the details sheet
                      Navigator.pop(context);

                      // Ensure we are still mounted before updating state or opening new sheet
                      if (!mounted) return;

                      // Select this table in the parent state
                      setState(() {
                        _selectedTable = table.number;
                      });

                      // Store session token if available (used for dine-in orders)
                      if (table.sessionToken != null &&
                          table.sessionToken!.isNotEmpty) {
                        _tableSessionTokens[table.id] = table.sessionToken;
                      }

                      // Open the New Order sheet for this table
                      await _showNewOrderSheet();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Order'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Close the details sheet
                      Navigator.pop(context);

                      if (!mounted) return;

                      // Show the bill for this table with ordered items & amount
                      _showBillForTable(table);
                    },
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('View Bill'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _openQRScanner() async {
    try {
      await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => QRScannerScreen(
            onScanComplete: (slug) {
              // Process the scan result after the scanner closes
              _processScannedSlug(slug);
            },
          ),
        ),
      );
    } catch (e) {
      _showSnackBar(
        'Failed to open QR scanner: ${e.toString()}',
        backgroundColor: AppColors.error,
      );
    }
  }

  Future<void> _processScannedSlug(String slug) async {
    // Look up the table by slug
    try {
      final table = await _tableService.lookupTableBySlug(slug);

      if (table != null && mounted) {
        // Find the table in our list
        final foundTable = _tables.firstWhere(
          (t) => t.id == table.id || t.qrSlug == slug,
          orElse: () => table,
        );

        // Store sessionToken for this table (required for dine-in orders)
        _tableSessionTokens[foundTable.id] = table.sessionToken;

        // Select the table
        setState(() {
          _selectedTable = foundTable.number;
        });

        // Switch to Tables tab if not already there
        if (_tabController.index != 0) {
          _tabController.animateTo(0);
        }

        // Show success message
        _showSnackBar(
          'Table ${foundTable.number} selected',
          backgroundColor: AppColors.success,
        );

        // Wait a moment for UI to update and tab switch
        await Future.delayed(const Duration(milliseconds: 400));

        // Automatically open the new order menu for this table
        if (mounted) {
          await _showNewOrderSheet();
        }
      } else {
        _showSnackBar(
          'Table not found. Please try scanning again.',
          backgroundColor: AppColors.error,
        );
      }
    } catch (e) {
      _showSnackBar(
        e is ApiException
            ? e.message
            : 'Failed to lookup table. Please try again.',
        backgroundColor: AppColors.error,
      );
    }
  }

  Future<void> _showNewOrderSheet({String? initialServiceType}) async {
    // Ensure menu is loaded for the current cart before opening
    if (_allMenuItems.isEmpty || _menuCategories.isEmpty) {
      await _loadMenu();
    }

    // Find initially selected table (from tap or QR scan)
    TableModel? initialTable;
    if (_selectedTable != 0) {
      try {
        initialTable = _tables.firstWhere((t) => t.number == _selectedTable);
      } catch (_) {
        // Ignore if not found
      }
    }

    final created = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.transparent,
      isScrollControlled: true,
      builder: (context) => NewOrderSheet(
        tables: _tables,
        menuItems: _allMenuItems,
        menuCategories: _menuCategories,
        initialTableId: initialTable?.id,
        tableSessionTokens: _tableSessionTokens,
        initialServiceType: initialServiceType,
        onOrderCreated: () async {
          // Reload orders and tables without clearing existing data
          await Future.wait([
            _loadOrders(),
            _loadTables(),
          ]);
        },
      ),
    );

    if (created == true && mounted) {
      _showSnackBar(
        'Order created successfully!',
        backgroundColor: AppColors.success,
      );
    }
  }

  Future<void> _showMergeConfirmationDialog() async {
    if (_selectedTablesForMerge.length < 2) return;

    final selectedTables =
        _tables.where((t) => _selectedTablesForMerge.contains(t.id)).toList();

    if (selectedTables.length < 2) return;

    // The first selected table will be the primary table
    final primaryTable = selectedTables.first;
    final secondaryTables = selectedTables.sublist(1);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.merge_type, color: AppColors.primary, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Merge Tables',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Do you want to merge these tables?',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Primary',
                          style: TextStyle(
                            color: AppColors.textLight,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Table T${primaryTable.number}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Secondary',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tables ${secondaryTables.map((t) => 'T${t.number}').join(', ')}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All orders from secondary tables will be moved to the primary table.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textLight,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Merge',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _mergeTables(primaryTable, secondaryTables);
    }
  }

  Future<void> _mergeTables(
    TableModel primaryTable,
    List<TableModel> secondaryTables,
  ) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final secondaryTableIds = secondaryTables.map((t) => t.id).toList();

      await _tableService.mergeTables(
        primaryTableId: primaryTable.id,
        secondaryTableIds: secondaryTableIds,
      );

      if (mounted) {
        // Clear merge selection
        setState(() {
          _selectedTablesForMerge.clear();
        });

        // Reload tables and orders
        await Future.wait([
          _loadTables(),
          _loadOrders(),
        ]);

        _showSnackBar(
          'Tables merged successfully!',
          backgroundColor: AppColors.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedTablesForMerge.clear();
        });
        _showSnackBar(
          e is ApiException
              ? e.message
              : 'Failed to merge tables. Please try again.',
          backgroundColor: AppColors.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showUnmergeConfirmationDialog(TableModel table) async {
    final isPrimary = table.hasMergedTables;
    final mergedTableNumbers = isPrimary && table.mergedTables != null
        ? table.mergedTables!.map((mergedId) {
            final mergedTable = _tables.firstWhere(
              (t) => t.id == mergedId,
              orElse: () => table,
            );
            return 'T${mergedTable.number}';
          }).join(', ')
        : '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.call_split, color: AppColors.error, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Unmerge Tables',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPrimary
                  ? 'Do you want to unmerge Table T${table.number} and its merged tables?'
                  : 'Do you want to unmerge this table from the merged group?',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            if (isPrimary && mergedTableNumbers.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Primary',
                            style: TextStyle(
                              color: AppColors.textLight,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Table T${table.number}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.error,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Merged',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            mergedTableNumbers,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isPrimary
                          ? 'All tables will be separated and orders will remain on their original tables.'
                          : 'This table will be separated from the merged group.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.textLight,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Unmerge',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _unmergeTable(table);
    }
  }

  Future<void> _unmergeTable(TableModel table) async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _tableService.unmergeTable(table.id);

      if (mounted) {
        // Reload tables and orders
        await Future.wait([
          _loadTables(),
          _loadOrders(),
        ]);

        _showSnackBar(
          'Table unmerged successfully!',
          backgroundColor: AppColors.success,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          e is ApiException
              ? e.message
              : 'Failed to unmerge table. Please try again.',
          backgroundColor: AppColors.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

/// Public widget for creating new orders. Used by OrdersScreen.
class NewOrderSheet extends StatefulWidget {
  final List<TableModel> tables;
  final List<MenuItem> menuItems;
  final List<MenuCategory> menuCategories;
  final Future<void> Function() onOrderCreated;
  final String? initialTableId;
  final Map<String, String?> tableSessionTokens;
  final String? initialServiceType;

  const NewOrderSheet({
    required this.tables,
    required this.menuItems,
    required this.menuCategories,
    required this.onOrderCreated,
    this.initialTableId,
    required this.tableSessionTokens,
    this.initialServiceType,
  });

  @override
  State<NewOrderSheet> createState() => _NewOrderSheetState();
}

class _NewOrderSheetState extends State<NewOrderSheet> {
  final OrderService _orderService = OrderService();
  final AddonService _addonService = AddonService();
  final TextEditingController _searchController = TextEditingController();

  String? _selectedTableId;
  String? _selectedOfficeTableId;
  String _searchQuery = '';
  String _selectedCategoryId = 'all';
  final Map<String, int> _selectedItems = {}; // itemId -> quantity
  String _cartNote = '';
  List<AddonModel> _availableAddons = [];
  List<String> _selectedAddonIds = []; // Repeat IDs to represent quantity
  bool _isLoadingAddons = false;
  bool _isCreating = false;
  bool _isTakeaway = false;
  String _takeawayMode = 'COUNTER'; // COUNTER | OFFICE

  static const Map<String, String> _spiceLevelLabels = {
    'MILD': 'Mild',
    'MEDIUM': 'Medium',
    'HOT': 'Hot',
    'EXTREME': 'Extreme',
  };

  bool _isSelectableTableStatus(TableModel table) {
    return table.status == 'AVAILABLE' || table.status == 'OCCUPIED';
  }

  bool _isOfficeTable(TableModel table) {
    final qrContextType = (table.qrContextType ?? '').trim().toUpperCase();
    if (qrContextType == 'OFFICE') {
      return true;
    }
    return (table.officeName ?? '').trim().isNotEmpty;
  }

  List<TableModel> _dineInTables() {
    return widget.tables
        .where((t) => _isSelectableTableStatus(t) && !_isOfficeTable(t))
        .toList();
  }

  List<TableModel> _officeTables() {
    return widget.tables
        .where((t) => _isSelectableTableStatus(t) && _isOfficeTable(t))
        .toList();
  }

  bool get _isOfficeTakeaway => _isTakeaway && _takeawayMode == 'OFFICE';

  @override
  void initState() {
    super.initState();
    // Pre-select table if provided
    _selectedTableId = widget.initialTableId;
    TableModel? initiallySelectedTable;
    if (widget.initialTableId != null && widget.initialTableId!.isNotEmpty) {
      for (final table in widget.tables) {
        if (table.id == widget.initialTableId) {
          initiallySelectedTable = table;
          break;
        }
      }
      if (initiallySelectedTable != null &&
          _isOfficeTable(initiallySelectedTable)) {
        _selectedOfficeTableId = initiallySelectedTable.id;
        _selectedTableId = null;
      }
    }
    // Pre-select service type if provided (from Dine In / Takeaway tab)
    if (widget.initialServiceType == 'TAKEAWAY') {
      _isTakeaway = true;
    } else if (widget.initialServiceType == 'DINE_IN') {
      _isTakeaway = false;
    } else {
      // Default to takeaway when no tables available
      if (_dineInTables().isEmpty) {
        _isTakeaway = true;
      }
    }

    if (_selectedOfficeTableId != null &&
        _selectedOfficeTableId!.isNotEmpty &&
        widget.initialServiceType != 'DINE_IN') {
      _isTakeaway = true;
      _takeawayMode = 'OFFICE';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAddons();
    });
  }

  @override
  void didUpdateWidget(covariant NewOrderSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedCategoryId != 'all') {
      final isCategoryStillAvailable =
          widget.menuCategories.any((cat) => cat.id == _selectedCategoryId);
      if (!isCategoryStillAvailable) {
        _selectedCategoryId = 'all';
      }
    }

    if (_selectedTableId != null &&
        _selectedTableId!.isNotEmpty &&
        !_dineInTables().any((t) => t.id == _selectedTableId)) {
      _selectedTableId = null;
    }
    if (_selectedOfficeTableId != null &&
        _selectedOfficeTableId!.isNotEmpty &&
        !_officeTables().any((t) => t.id == _selectedOfficeTableId)) {
      _selectedOfficeTableId = null;
    }
    if (_takeawayMode == 'OFFICE' && _officeTables().isEmpty) {
      _takeawayMode = 'COUNTER';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Helper method to safely show snackbars
  void _showSnackBar(String message,
      {Color? backgroundColor, Duration? duration}) {
    if (!mounted) return;

    try {
      final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
      if (scaffoldMessenger != null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor ?? AppColors.primary,
            duration: duration ?? const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Silently fail if context is invalid
      print('[NewOrderSheet] Failed to show snackbar: $e');
    }
  }

  List<MenuItem> get _filteredItems {
    final selectedCategoryId = _selectedCategoryId;
    final queryLower = _searchQuery.toLowerCase();
    return widget.menuItems.where((item) {
      if (!item.isAvailable) return false;
      if (selectedCategoryId != 'all' &&
          item.categoryId != selectedCategoryId) {
        return false;
      }
      if (_searchQuery.isEmpty) return true;
      final inName = item.name.toLowerCase().contains(queryLower);
      final inDescription =
          (item.description ?? '').toLowerCase().contains(queryLower);
      final inTags = item.tags.any(
        (tag) => tag.toLowerCase().contains(queryLower),
      );
      final inSpice = _getSpiceLevelLabel(item.spiceLevel)
          .toLowerCase()
          .contains(queryLower);
      return inName || inDescription || inTags || inSpice;
    }).toList();
  }

  List<MenuCategory> get _availableMenuCategories {
    final availableCategoryIds = widget.menuItems
        .where((item) => item.isAvailable && item.categoryId.isNotEmpty)
        .map((item) => item.categoryId)
        .toSet();
    final categories = widget.menuCategories
        .where((category) => availableCategoryIds.contains(category.id))
        .toList();
    categories.sort((a, b) {
      final orderA = a.sortOrder ?? 0;
      final orderB = b.sortOrder ?? 0;
      if (orderA != orderB) return orderA.compareTo(orderB);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return categories;
  }

  String? _activeContextTableIdForAddons() {
    if (_isOfficeTakeaway) {
      return _selectedOfficeTableId;
    }
    if (!_isTakeaway) {
      return _selectedTableId;
    }
    return null;
  }

  String? _resolveCartIdForAddons() {
    final selectedContextTableId = _activeContextTableIdForAddons();
    // For add-ons, prefer cart inferred from selected table/office (same as customer flow).
    if (selectedContextTableId != null && selectedContextTableId.isNotEmpty) {
      for (final table in widget.tables) {
        if (table.id == selectedContextTableId) {
          final tableCartId = table.cartId?.trim();
          if (tableCartId != null && tableCartId.isNotEmpty) {
            return tableCartId;
          }
          break;
        }
      }
    }

    // If no table is selected, still prefer any known table cart before user cart.
    for (final table in widget.tables) {
      final tableCartId = table.cartId?.trim();
      if (tableCartId != null && tableCartId.isNotEmpty) {
        return tableCartId;
      }
    }

    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final userCartId = appProvider.currentUser?.cartId?.trim();
    if (userCartId != null && userCartId.isNotEmpty) {
      return userCartId;
    }

    return null;
  }

  Future<void> _loadAddons({String? tableId}) async {
    final cartId = _resolveCartIdForAddons();
    final selectedOrProvidedTableId =
        (tableId ?? _activeContextTableIdForAddons())?.trim();
    final fallbackCandidates = _isOfficeTakeaway
        ? _officeTables()
        : !_isTakeaway
            ? _dineInTables()
            : widget.tables;
    final fallbackTableId = fallbackCandidates
        .map((t) => t.id.trim())
        .firstWhere((id) => id.isNotEmpty, orElse: () => '');
    final effectiveTableId = (selectedOrProvidedTableId != null &&
            selectedOrProvidedTableId.isNotEmpty)
        ? selectedOrProvidedTableId
        : (fallbackTableId.isNotEmpty ? fallbackTableId : null);
    if ((cartId == null || cartId.isEmpty) &&
        (effectiveTableId == null || effectiveTableId.isEmpty)) {
      if (!mounted) return;
      setState(() {
        _availableAddons = [];
        _selectedAddonIds = [];
      });
      return;
    }

    if (mounted) {
      setState(() => _isLoadingAddons = true);
    }

    try {
      List<AddonModel> addons = await _addonService.getPublicAddons(
        cartId: cartId,
        tableId: effectiveTableId,
      );

      if (addons.isEmpty && widget.tables.isNotEmpty) {
        final idsToTry = <String>{
          if (effectiveTableId != null && effectiveTableId.isNotEmpty)
            effectiveTableId,
          ...widget.tables.map((t) => t.id.trim()).where((id) => id.isNotEmpty),
        };

        for (final candidateTableId in idsToTry) {
          addons =
              await _addonService.getPublicAddons(tableId: candidateTableId);
          if (addons.isNotEmpty) {
            break;
          }
        }
      }

      if (!mounted) return;

      final visibleAddons = addons.where((a) => a.isAvailable).toList()
        ..sort((a, b) {
          final byOrder = a.sortOrder.compareTo(b.sortOrder);
          if (byOrder != 0) return byOrder;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      final availableAddonIds = visibleAddons.map((a) => a.id).toSet();

      setState(() {
        _availableAddons = visibleAddons;
        _selectedAddonIds =
            _selectedAddonIds.where(availableAddonIds.contains).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _availableAddons = [];
        _selectedAddonIds = [];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingAddons = false);
      }
    }
  }

  AddonModel? _findAddonById(String addonId) {
    for (final addon in _availableAddons) {
      if (addon.id == addonId) {
        return addon;
      }
    }
    return null;
  }

  int _getAddonQuantity(String addonId) =>
      _selectedAddonIds.where((id) => id == addonId).length;

  void _addAddon(String addonId) {
    if (!mounted) return;
    setState(() => _selectedAddonIds.add(addonId));
  }

  void _removeAddon(String addonId) {
    if (!mounted) return;
    final index = _selectedAddonIds.indexOf(addonId);
    if (index == -1) return;
    setState(() => _selectedAddonIds.removeAt(index));
  }

  List<Map<String, dynamic>> get _selectedAddonsPayload {
    return _selectedAddonIds
        .map((addonId) {
          final addon = _findAddonById(addonId);
          if (addon == null) return null;
          final data = <String, dynamic>{
            'name': addon.name,
            'price': addon.price,
          };
          // Backend expects ObjectId for addonId; keep optional for fallback/static add-ons.
          if (_isLikelyObjectId(addon.id)) {
            data['addonId'] = addon.id;
          }
          return data;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  bool _isLikelyObjectId(String value) =>
      RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(value);

  TableModel? _selectedTableModel() {
    final selectedId = _selectedTableId;
    if (selectedId == null || selectedId.isEmpty) return null;
    for (final table in widget.tables) {
      if (table.id == selectedId) {
        return table;
      }
    }
    return null;
  }

  TableModel? _selectedOfficeTableModel() {
    final selectedId = _selectedOfficeTableId;
    if (selectedId == null || selectedId.isEmpty) return null;
    for (final table in widget.tables) {
      if (table.id == selectedId) {
        return table;
      }
    }
    return null;
  }

  String? _selectedContextBadgeText() {
    if (_isOfficeTakeaway) {
      final office = _selectedOfficeTableModel();
      if (office == null) return null;
      final officeName = (office.officeName ?? '').trim();
      if (officeName.isNotEmpty) {
        return officeName;
      }
      return 'Office #${office.number}';
    }

    final table = _selectedTableModel();
    if (table == null) return null;
    return 'Table T${table.number}';
  }

  bool get _hasSelectedTable => (_selectedTableId ?? '').trim().isNotEmpty;
  bool get _hasSelectedOffice =>
      (_selectedOfficeTableId ?? '').trim().isNotEmpty;

  Future<void> _createOrder() async {
    final selectedDineInTable = _selectedTableModel();
    final selectedOfficeTable = _selectedOfficeTableModel();

    if (!_isTakeaway &&
        (!_hasSelectedTable ||
            selectedDineInTable == null ||
            _isOfficeTable(selectedDineInTable))) {
      _showSnackBar(
        'Please select a dine-in table to create an order',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    if (_isOfficeTakeaway &&
        (!_hasSelectedOffice ||
            selectedOfficeTable == null ||
            !_isOfficeTable(selectedOfficeTable))) {
      _showSnackBar(
        'Please select an office to create this order',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    if (_selectedItems.isEmpty) {
      _showSnackBar(
        'Please select at least one item',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final officeCartId = selectedOfficeTable?.cartId?.trim();
    final userCartId = appProvider.currentUser?.cartId?.trim();
    final resolvedCartId = (_isOfficeTakeaway &&
            officeCartId != null &&
            officeCartId.isNotEmpty)
        ? officeCartId
        : ((userCartId != null && userCartId.isNotEmpty) ? userCartId : null);

    if (_isTakeaway && !_isOfficeTakeaway && resolvedCartId == null) {
      _showSnackBar(
        'Cart/cafe not configured. Please contact admin.',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      // Build order items from selected menu items
      final orderItems = _selectedItems.entries.map((entry) {
        final item = widget.menuItems.firstWhere((i) => i.id == entry.key);
        return {
          'name': item.name,
          'quantity': entry.value,
          'price': item.price,
          'returned': false,
        };
      }).toList();

      final selectedAddons = _selectedAddonsPayload;
      final Map<String, dynamic> orderData = {
        'items': orderItems,
        'serviceType': _isTakeaway ? 'TAKEAWAY' : 'DINE_IN',
        if (_cartNote.trim().isNotEmpty)
          'specialInstructions': _cartNote.trim(),
        if (resolvedCartId != null) 'cartId': resolvedCartId,
        if (selectedAddons.isNotEmpty) 'selectedAddons': selectedAddons,
      };

      if (_isOfficeTakeaway) {
        final officeName = (selectedOfficeTable?.officeName ?? '').trim();
        final officePhone = (selectedOfficeTable?.officePhone ?? '').trim();
        final officeAddress = (selectedOfficeTable?.officeAddress ?? '').trim();
        final officePaymentMode =
            (selectedOfficeTable?.officePaymentMode ?? '').trim().toUpperCase();
        final officeDeliveryCharge =
            selectedOfficeTable?.officeDeliveryCharge ?? 0;

        orderData['tableId'] = _selectedOfficeTableId;
        orderData['tableNumber'] =
            (selectedOfficeTable?.number ?? 'TAKEAWAY').toString();
        orderData['sourceQrType'] = 'OFFICE';
        if (officeName.isNotEmpty) {
          orderData['officeName'] = officeName;
          orderData['customerName'] = officeName;
        }
        if (officePhone.isNotEmpty) {
          orderData['customerMobile'] = officePhone;
        }
        if (officeAddress.isNotEmpty) {
          orderData['customerLocation'] = {
            'latitude': null,
            'longitude': null,
            'address': officeAddress,
          };
        }
        if (officePaymentMode == 'ONLINE' ||
            officePaymentMode == 'COD' ||
            officePaymentMode == 'BOTH') {
          orderData['officePaymentMode'] = officePaymentMode;
        }
        if (officeDeliveryCharge > 0) {
          orderData['officeDeliveryCharge'] =
              double.parse(officeDeliveryCharge.toStringAsFixed(2));
        }
      } else if (_isTakeaway) {
        // Counter takeaway: no table or session token needed.
      } else {
        // Dine-in: resolve session token
        String? sessionToken = widget.tableSessionTokens[_selectedTableId];
        if (sessionToken == null || sessionToken.isEmpty) {
          final tableToken = selectedDineInTable?.sessionToken?.trim();
          if (tableToken != null && tableToken.isNotEmpty) {
            sessionToken = tableToken;
          }
        }
        if (sessionToken == null || sessionToken.isEmpty) {
          sessionToken =
              'WAITER_${_selectedTableId}_${DateTime.now().millisecondsSinceEpoch}';
          widget.tableSessionTokens[_selectedTableId!] = sessionToken;
        }
        orderData['tableId'] = _selectedTableId;
        orderData['sessionToken'] = sessionToken;
      }

      await _orderService.createOrder(orderData);

      // Refresh parent data first, then close sheet with a success result.
      await widget.onOrderCreated();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showSnackBar(
        e is ApiException ? e.message : 'Failed to create order',
        backgroundColor: AppColors.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _updateItemQuantity(String itemId, int delta) {
    if (!mounted) return; // Prevent updates if widget is disposed

    setState(() {
      final current = _selectedItems[itemId] ?? 0;
      final newQuantity = current + delta;
      if (newQuantity <= 0) {
        _selectedItems.remove(itemId);
      } else {
        _selectedItems[itemId] = newQuantity;
      }
    });
  }

  String _getSpiceLevelLabel(String level) {
    return _spiceLevelLabels[level] ?? '';
  }

  bool _hasSpiceLevel(MenuItem item) {
    return _spiceLevelLabels.containsKey(item.spiceLevel);
  }

  Color _spiceBadgeBackground(String level) {
    switch (level) {
      case 'MILD':
        return const Color(0xFFC6F6D5);
      case 'MEDIUM':
        return const Color(0xFFFDE68A);
      case 'HOT':
        return const Color(0xFFFDBA74);
      case 'EXTREME':
        return const Color(0xFFFCA5A5);
      default:
        return AppColors.cardBorder.withValues(alpha: 0.2);
    }
  }

  Color _spiceBadgeBorder(String level) {
    switch (level) {
      case 'MILD':
        return const Color(0xFF4ADE80);
      case 'MEDIUM':
        return const Color(0xFFF59E0B);
      case 'HOT':
        return const Color(0xFFF97316);
      case 'EXTREME':
        return const Color(0xFFEF4444);
      default:
        return AppColors.cardBorder.withValues(alpha: 0.4);
    }
  }

  Color _spiceBadgeText(String level) {
    switch (level) {
      case 'MILD':
        return const Color(0xFF166534);
      case 'MEDIUM':
        return const Color(0xFF78350F);
      case 'HOT':
        return const Color(0xFF7C2D12);
      case 'EXTREME':
        return const Color(0xFF7F1D1D);
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _showCartNoteDialog() async {
    final currentNote = _cartNote.trim();
    String draftNote = currentNote;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('KOT Note'),
          content: TextFormField(
            initialValue: currentNote,
            maxLines: 4,
            minLines: 2,
            maxLength: 220,
            onChanged: (value) {
              draftNote = value;
            },
            decoration: const InputDecoration(
              hintText: 'Any preparation note for kitchen?',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, currentNote),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('Clear'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, draftNote.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    setState(() {
      _cartNote = result.trim();
    });
  }

  int get _selectedUnitsCount =>
      _selectedItems.values.fold(0, (sum, qty) => sum + qty);

  double get _itemsTotalAmount {
    return _selectedItems.entries.fold(0.0, (sum, entry) {
      final item = widget.menuItems.firstWhere(
        (i) => i.id == entry.key,
        orElse: () => MenuItem(
          id: entry.key,
          name: 'Unknown',
          price: 0,
          isAvailable: false,
          categoryId: '',
        ),
      );
      return sum + (item.price * entry.value);
    });
  }

  double get _addonsTotalAmount {
    return _selectedAddonIds.fold(0.0, (sum, addonId) {
      final addon = _findAddonById(addonId);
      return sum + (addon?.price ?? 0.0);
    });
  }

  double get _totalAmount => _itemsTotalAmount + _addonsTotalAmount;

  int _menuGridCrossAxisCount(double width) {
    if (width < 900) return 2;
    if (width < 1200) return 3;
    return 4;
  }

  double _menuGridMainAxisExtent(double width) {
    if (width < 600) return 232;
    if (width < 900) return 238;
    if (width < 1200) return 244;
    return 248;
  }

  String get _floatingCartSummaryText {
    final itemLabel = _selectedUnitsCount == 1 ? 'Item' : 'Items';
    return '🛒 $_selectedUnitsCount $itemLabel | \u20B9${_totalAmount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final dineInTables = _dineInTables();
    final officeTables = _officeTables();

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Create New Order',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          if (!_isTakeaway || _isOfficeTakeaway) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isOfficeTakeaway
                        ? Icons.business_outlined
                        : Icons.table_restaurant,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedContextBadgeText() ??
                          (_isOfficeTakeaway
                              ? 'Office not selected'
                              : 'Table not selected'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _isOfficeTakeaway
                                ? (!_hasSelectedOffice
                                    ? AppColors.warning
                                    : AppColors.primary)
                                : (!_hasSelectedTable
                                    ? AppColors.warning
                                    : AppColors.primary),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Order type: Dine-in vs Takeaway
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isTakeaway = false;
                        _takeawayMode = 'COUNTER';
                        if (_selectedTableId == null &&
                            _dineInTables().isNotEmpty) {
                          _selectedTableId = _dineInTables().first.id;
                        }
                      });
                      _loadAddons(tableId: _selectedTableId);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_isTakeaway
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: !_isTakeaway
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.table_restaurant,
                            size: 20,
                            color: !_isTakeaway
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Dine-in',
                            style: TextStyle(
                              fontWeight: !_isTakeaway
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: !_isTakeaway
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isTakeaway = true;
                        if (_takeawayMode == 'OFFICE' && officeTables.isEmpty) {
                          _takeawayMode = 'COUNTER';
                        }
                      });
                      _loadAddons();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isTakeaway
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isTakeaway
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.takeout_dining,
                            size: 20,
                            color: _isTakeaway
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Takeaway',
                            style: TextStyle(
                              fontWeight: _isTakeaway
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _isTakeaway
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_isTakeaway && officeTables.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Counter'),
                  selected: _takeawayMode == 'COUNTER',
                  onSelected: (_) {
                    setState(() {
                      _takeawayMode = 'COUNTER';
                    });
                    _loadAddons();
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.18),
                  side: BorderSide(
                    color: _takeawayMode == 'COUNTER'
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.cardBorder,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Office'),
                  selected: _takeawayMode == 'OFFICE',
                  onSelected: (_) {
                    if (officeTables.isEmpty) return;
                    setState(() {
                      _takeawayMode = 'OFFICE';
                      if (_selectedOfficeTableId == null ||
                          !officeTables.any(
                              (table) => table.id == _selectedOfficeTableId)) {
                        _selectedOfficeTableId = officeTables.first.id;
                      }
                    });
                    _loadAddons(tableId: _selectedOfficeTableId);
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.18),
                  side: BorderSide(
                    color: _takeawayMode == 'OFFICE'
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.cardBorder,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Selection + Search
          if (!_isTakeaway || _isOfficeTakeaway)
            LayoutBuilder(
              builder: (context, constraints) {
                final showOfficePicker = _isOfficeTakeaway;
                final selectionPool =
                    showOfficePicker ? officeTables : dineInTables;
                final currentSelectionId = showOfficePicker
                    ? _selectedOfficeTableId
                    : _selectedTableId;
                final hasCurrentSelection = selectionPool
                    .any((table) => table.id == currentSelectionId);
                final isNarrow = constraints.maxWidth < 760;

                final selector = DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: showOfficePicker ? 'Office *' : 'Table *',
                    prefixIcon: Icon(showOfficePicker
                        ? Icons.business_outlined
                        : Icons.table_restaurant),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  value: hasCurrentSelection ? currentSelectionId : null,
                  items: selectionPool.map((table) {
                    final isOccupied = table.status == 'OCCUPIED';
                    final officeName = (table.officeName ?? '').trim();
                    final officeLabel = officeName.isNotEmpty
                        ? officeName
                        : 'Office #${table.number}';
                    final label = showOfficePicker
                        ? officeLabel
                        : (isOccupied
                            ? 'T${table.number} (Occ)'
                            : 'T${table.number}');
                    return DropdownMenuItem(
                      value: table.id,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: selectionPool.isEmpty
                      ? null
                      : (value) {
                          setState(() {
                            if (showOfficePicker) {
                              _selectedOfficeTableId = value;
                            } else {
                              _selectedTableId = value;
                            }
                          });
                          _loadAddons(tableId: value);
                        },
                );

                final searchBox = TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search Menu Items',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      selector,
                      const SizedBox(height: 12),
                      searchBox,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 2, child: selector),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: searchBox),
                  ],
                );
              },
            )
          else
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search Menu Items',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),

          const SizedBox(height: 24),

          // Menu Items Section
          Text(
            _searchQuery.isEmpty ? 'Menu Items' : 'Search Results',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (_availableMenuCategories.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildCategoryChip(
                    categoryId: 'all',
                    label: 'All',
                  ),
                  ..._availableMenuCategories.map(
                    (category) => _buildCategoryChip(
                      categoryId: category.id,
                      label: category.name,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Menu Items Grid
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = _menuGridCrossAxisCount(width);
                final mainAxisExtent = _menuGridMainAxisExtent(width);

                Widget content;
                if (_filteredItems.isEmpty) {
                  content = Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          size: 64,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No menu items available'
                              : 'No items found',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  );
                } else {
                  content = GridView.builder(
                    key: const PageStorageKey('menu_items_grid'),
                    padding: EdgeInsets.only(
                      bottom: _selectedItems.isNotEmpty ? 84 : 16,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: mainAxisExtent,
                    ),
                    itemCount: _filteredItems.length,
                    cacheExtent: 360,
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final quantity = _selectedItems[item.id] ?? 0;
                      return _buildMenuItemCard(item, quantity);
                    },
                  );
                }

                return Stack(
                  children: [
                    Positioned.fill(child: content),
                    if (_selectedItems.isNotEmpty)
                      Positioned(
                        right: 2,
                        bottom: 8,
                        child: Material(
                          color: AppColors.primary,
                          elevation: 3,
                          borderRadius: BorderRadius.circular(24),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: _showCartBottomSheet,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Text(
                                _floatingCartSummaryText,
                                style: const TextStyle(
                                  color: AppColors.textLight,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _createOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shadowColor: AppColors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isCreating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.textLight),
                        ),
                      )
                    : Text(
                        () {
                          final hasContextSelection = _isOfficeTakeaway
                              ? _hasSelectedOffice
                              : (!_isTakeaway && _hasSelectedTable);
                          final contextText = hasContextSelection
                              ? ' | ${_selectedContextBadgeText()}'
                              : '';
                          if (_selectedItems.isEmpty) {
                            return 'Create Order$contextText';
                          }
                          return 'Create Order$contextText | \u20B9${_totalAmount.toStringAsFixed(2)}';
                        }(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  MenuItem _findMenuItemById(String id) {
    return widget.menuItems.firstWhere(
      (i) => i.id == id,
      orElse: () => MenuItem(
        id: id,
        name: 'Unknown Item',
        price: 0,
        isAvailable: false,
        categoryId: '',
      ),
    );
  }

  Widget _buildCategoryChip({
    required String categoryId,
    required String label,
  }) {
    final isSelected = _selectedCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            _selectedCategoryId = categoryId;
          });
        },
        selectedColor: AppColors.primary.withValues(alpha: 0.18),
        backgroundColor: Theme.of(context).cardColor,
        side: BorderSide(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.6)
              : AppColors.cardBorder.withValues(alpha: 0.6),
        ),
        labelStyle: TextStyle(
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildQuantityActionButton({
    required IconData icon,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  void _showCartBottomSheet() {
    if (_selectedItems.isEmpty) {
      _showSnackBar(
        'Cart is empty. Add items to continue.',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final entries = _selectedItems.entries.toList();
            entries.sort((a, b) => _findMenuItemById(a.key)
                .name
                .compareTo(_findMenuItemById(b.key).name));

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.cardBorder,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            Icons.shopping_cart_rounded,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Your Cart',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            _selectedAddonIds.isEmpty
                                ? '$_selectedUnitsCount item${_selectedUnitsCount > 1 ? 's' : ''}'
                                : '$_selectedUnitsCount item${_selectedUnitsCount > 1 ? 's' : ''} + ${_selectedAddonIds.length} add-on${_selectedAddonIds.length > 1 ? 's' : ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => Divider(
                          color: AppColors.cardBorder.withValues(alpha: 0.5),
                          height: 12,
                        ),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final item = _findMenuItemById(entry.key);
                          final lineTotal = item.price * entry.value;

                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final itemInfo = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  Text(
                                    '\u20B9${item.price.toStringAsFixed(2)} each',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ],
                              );

                              final quantityControls = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      _updateItemQuantity(entry.key, -1);
                                      setModalState(() {});
                                      if (_selectedItems.isEmpty &&
                                          sheetContext.mounted) {
                                        Navigator.pop(sheetContext);
                                      }
                                    },
                                    icon:
                                        const Icon(Icons.remove_circle_outline),
                                    iconSize: 18,
                                    color: AppColors.primary,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Text(
                                    '${entry.value}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      _updateItemQuantity(entry.key, 1);
                                      setModalState(() {});
                                    },
                                    icon: const Icon(Icons.add_circle_outline),
                                    iconSize: 18,
                                    color: AppColors.primary,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              );

                              final lineTotalText = SizedBox(
                                width: 84,
                                child: Text(
                                  '\u20B9${lineTotal.toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              );

                              final isCompact = constraints.maxWidth < 360;
                              if (isCompact) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: itemInfo),
                                        lineTotalText,
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: quantityControls,
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: itemInfo),
                                  quantityControls,
                                  lineTotalText,
                                ],
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.cardBorder.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.sticky_note_2_outlined,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'KOT Note',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () async {
                                    await _showCartNoteDialog();
                                    setModalState(() {});
                                  },
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(42, 30),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                  ),
                                  child: Text(
                                    _cartNote.trim().isEmpty ? 'Add' : 'Edit',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _cartNote.trim().isEmpty
                                  ? 'No note added for this order.'
                                  : _cartNote.trim(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: _cartNote.trim().isEmpty
                                        ? AppColors.textSecondary
                                        : AppColors.primary,
                                    fontStyle: _cartNote.trim().isEmpty
                                        ? FontStyle.normal
                                        : FontStyle.italic,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Customizations & Extras',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_isLoadingAddons)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Loading add-ons...',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      else if (_availableAddons.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  AppColors.cardBorder.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            'No add-ons available',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _availableAddons.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final addon = _availableAddons[index];
                            final qty = _getAddonQuantity(addon.id);
                            final lineTotal = addon.price * qty;

                            return Container(
                              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                              decoration: BoxDecoration(
                                color: qty > 0
                                    ? AppColors.primary.withValues(alpha: 0.08)
                                    : Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: qty > 0
                                      ? AppColors.primary
                                          .withValues(alpha: 0.35)
                                      : AppColors.cardBorder.withValues(
                                          alpha: 0.4,
                                        ),
                                ),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final addonInfo = Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        addon.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      if ((addon.description ?? '').isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            addon.description!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          addon.price > 0
                                              ? '+\u20B9${addon.price.toStringAsFixed(2)} each'
                                              : 'Free',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.textSecondary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  );

                                  final addonControls = Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: qty > 0
                                            ? () {
                                                _removeAddon(addon.id);
                                                setModalState(() {});
                                              }
                                            : null,
                                        icon: Icon(
                                          qty == 1
                                              ? Icons.delete_outline
                                              : Icons.remove_circle_outline,
                                        ),
                                        iconSize: 18,
                                        color: AppColors.primary,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Text(
                                        '$qty',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          _addAddon(addon.id);
                                          setModalState(() {});
                                        },
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                        iconSize: 18,
                                        color: AppColors.primary,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  );

                                  final addonTotal = SizedBox(
                                    width: 76,
                                    child: Text(
                                      qty > 0
                                          ? '\u20B9${lineTotal.toStringAsFixed(2)}'
                                          : '',
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: qty > 0
                                                ? AppColors.primary
                                                : AppColors.textSecondary,
                                          ),
                                    ),
                                  );

                                  final isCompact = constraints.maxWidth < 360;
                                  if (isCompact) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(child: addonInfo),
                                            addonTotal,
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: addonControls,
                                        ),
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(child: addonInfo),
                                      addonControls,
                                      addonTotal,
                                    ],
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            'Items',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const Spacer(),
                          Text(
                            '\u20B9${_itemsTotalAmount.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      if (_selectedAddonIds.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              'Add-ons',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const Spacer(),
                            Text(
                              '\u20B9${_addonsTotalAmount.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Divider(
                        color: AppColors.cardBorder.withValues(alpha: 0.6),
                        height: 1,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Total',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            '\u20B9${_totalAmount.toStringAsFixed(2)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                          },
                          icon: const Icon(Icons.done),
                          label: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return '';
    // If it's already a full URL, return as is
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    // Otherwise, construct full URL from base URL
    // Extract base URL from ApiConfig (remove /api suffix)
    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    // Handle both absolute paths (starting with /) and relative paths
    if (imagePath.startsWith('/')) {
      return '$baseUrl$imagePath';
    }
    // If it's just a filename, assume it's in /uploads/
    return '$baseUrl/uploads/$imagePath';
  }

  Widget _buildMenuItemCard(MenuItem item, int quantity) {
    final imageUrl = _getImageUrl(item.image);
    final hasImage = imageUrl.isNotEmpty;
    final hasSpice = _hasSpiceLevel(item);
    final spiceLabel = _getSpiceLevelLabel(item.spiceLevel);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _updateItemQuantity(item.id, 1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          key: ValueKey('menu_item_${item.id}_$quantity'),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: quantity > 0
                  ? AppColors.primary
                  : AppColors.cardBorder.withValues(alpha: 0.5),
              width: quantity > 0 ? 1.8 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.pureBlack.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 108,
                      width: double.infinity,
                      child: hasImage
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.low,
                              gaplessPlayback: true,
                              cacheWidth: 360,
                              cacheHeight: 240,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: AppColors.cardBorder
                                      .withValues(alpha: 0.22),
                                  child: const Icon(
                                    Icons.restaurant_menu,
                                    size: 36,
                                    color: AppColors.textSecondary,
                                  ),
                                );
                              },
                            )
                          : Container(
                              color:
                                  AppColors.cardBorder.withValues(alpha: 0.22),
                              child: const Icon(
                                Icons.restaurant_menu,
                                size: 36,
                                color: AppColors.textSecondary,
                              ),
                            ),
                    ),
                    if (quantity > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '$quantity',
                            style: const TextStyle(
                              color: AppColors.textLight,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '\u20B9${item.price.toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                            ),
                          ),
                          if (hasSpice)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _spiceBadgeBackground(item.spiceLevel),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _spiceBadgeBorder(item.spiceLevel),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                spiceLabel,
                                style: TextStyle(
                                  color: _spiceBadgeText(item.spiceLevel),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildQuantityActionButton(
                              icon: Icons.remove,
                              onTap: quantity > 0
                                  ? () => _updateItemQuantity(item.id, -1)
                                  : null,
                              color: quantity > 0
                                  ? AppColors.primary
                                  : AppColors.textSecondary
                                      .withValues(alpha: 0.45),
                            ),
                            Expanded(
                              child: Text(
                                '$quantity',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: quantity > 0
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                    ),
                              ),
                            ),
                            _buildQuantityActionButton(
                              icon: Icons.add,
                              onTap: () => _updateItemQuantity(item.id, 1),
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
