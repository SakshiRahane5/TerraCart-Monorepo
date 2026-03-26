import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../providers/app_provider.dart';
import '../../services/dashboard_service.dart';
import '../../services/attendance_service.dart';
import '../../services/customer_request_service.dart';
import '../../services/socket_service.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/services/cache_service.dart';
import '../orders/orders_screen.dart';
import '../inventory/inventory_screen.dart';
import '../checklists/checklists_screen.dart';
import '../attendance/attendance_screen.dart';
import '../attendance/manager_employee_attendance_screen.dart';
import '../kot/kot_screen.dart';
import '../payments/payments_screen.dart';
import '../compliance/compliance_screen.dart';
import '../customer_requests/customer_requests_screen.dart';

class ManagerDashboard extends StatefulWidget {
  const ManagerDashboard({super.key});

  @override
  State<ManagerDashboard> createState() => _ManagerDashboardState();
}

class _ManagerDashboardState extends State<ManagerDashboard> {
  final DashboardService _dashboardService = DashboardService();
  final AttendanceService _attendanceService = AttendanceService();
  final CustomerRequestService _customerRequestService =
      CustomerRequestService();
  final SocketService _socketService = SocketService();

  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _todayAttendance;
  int _pendingRequestCount = 0;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _attendanceTimer;
  DateTime _currentTime = DateTime.now();
  String _lastActionRequiredSignature = '';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startAttendanceTimer();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _attendanceTimer?.cancel();
    _removeSocketListeners();
    super.dispose();
  }

  void _startAttendanceTimer() {
    // Update attendance display every second for real-time timers
    _attendanceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  void _setupSocketListeners() {
    void refreshOrders(dynamic _) {
      if (!mounted) return;
      _dashboardService.invalidateCache();
      _loadDashboardData(showLoading: false);
    }

    // Real-time order/KOT events for dashboard stats.
    const orderEvents = <String>[
      'order:created',
      'order:upsert',
      'order_status_updated',
      'order.cancelled',
      'order:deleted',
      'kot:created',
      'kot:status:updated',
      'paymentCreated',
      'paymentUpdated',
    ];
    for (final event in orderEvents) {
      _socketService.on(
        event,
        refreshOrders,
        debounce: true,
        delay: const Duration(milliseconds: 500),
      );
    }

    _socketService.on('table:status:updated', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('task:created', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('task:completed', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('inventory:low_stock', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('attendance:checked_in', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('attendance:checked_out', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('attendance:updated', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('attendance:break_started', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('attendance:break_ended', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('compliance:created', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('compliance:updated', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('compliance:deleted', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData();
      }
    }, debounce: true);

    _socketService.on('request:created', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    _socketService.on('request:updated', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    _socketService.on('request:resolved', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    _socketService.on('request:acknowledged', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    _socketService.on('request:deleted', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);
  }

  void _removeSocketListeners() {
    _socketService.off('order:created');
    _socketService.off('order:upsert');
    _socketService.off('order_status_updated');
    _socketService.off('order.cancelled');
    _socketService.off('order:deleted');
    _socketService.off('paymentCreated');
    _socketService.off('paymentUpdated');
    _socketService.off('table:status:updated');
    _socketService.off('task:created');
    _socketService.off('task:completed');
    _socketService.off('inventory:low_stock');
    _socketService.off('kot:created');
    _socketService.off('kot:status:updated');
    _socketService.off('attendance:checked_in');
    _socketService.off('attendance:checked_out');
    _socketService.off('attendance:updated');
    _socketService.off('attendance:break_started');
    _socketService.off('attendance:break_ended');
    _socketService.off('compliance:created');
    _socketService.off('compliance:updated');
    _socketService.off('compliance:deleted');
    _socketService.off('request:created');
    _socketService.off('request:updated');
    _socketService.off('request:resolved');
    _socketService.off('request:acknowledged');
    _socketService.off('request:deleted');
  }

  Future<void> _loadDashboardData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // Load data in parallel with caching
      final [stats, todayAttendance, pendingRequests] = await Future.wait([
        _dashboardService.getDashboardStats(useCache: true),
        _attendanceService
            .getTodayAttendance()
            .catchError((e) => <Map<String, dynamic>>[]),
        _customerRequestService
            .getPendingRequests()
            .catchError((e) => <Map<String, dynamic>>[]),
      ]);

      if (mounted) {
        setState(() {
          _stats = stats as Map<String, dynamic>;
          final attendanceList = todayAttendance as List<Map<String, dynamic>>;
          final pendingRequestList =
              pendingRequests as List<Map<String, dynamic>>;
          _pendingRequestCount = pendingRequestList.length;
          // For manager: filter by employeeId when multiple records (manager sees all cart attendance)
          Map<String, dynamic>? myAttendance;
          if (attendanceList.isNotEmpty) {
            final appProvider =
                Provider.of<AppProvider>(context, listen: false);
            final currentEmployeeId = appProvider.currentUser?.employeeId;
            if (currentEmployeeId != null && attendanceList.length > 1) {
              myAttendance = attendanceList.where((a) {
                final empId = a['employeeId'];
                final empIdStr =
                    empId is Map ? empId['_id']?.toString() : empId?.toString();
                return empIdStr == currentEmployeeId;
              }).firstOrNull;
            }
            _todayAttendance = myAttendance ?? attendanceList.first;
          } else {
            _todayAttendance = null;
          }
          _isLoading = false;
        });
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        appProvider.refreshAttendance();
        _maybeShowActionRequiredNotification();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e is ApiException ? e.message : 'Failed to load dashboard data';
          _isLoading = false;
        });
      }
    }
  }

  String _formatTime(DateTime dateTime) =>
      DateTimeUtils.formatTimeIST(dateTime);

  List<Map<String, dynamic>> _getActionRequiredItems() {
    final pendingKOTs = (_stats['pendingKOTs'] ?? 0) as num;
    final preparingKOTs = (_stats['preparingKOTs'] ?? 0) as num;
    final readyKOTs = (_stats['readyKOTs'] ?? 0) as num;
    final activeKOTs = pendingKOTs + preparingKOTs + readyKOTs;
    final pendingTasks = (_stats['pendingTasks'] ?? 0) as num;
    final lowStockItems = (_stats['lowStockItems'] ?? 0) as num;

    final items = <Map<String, dynamic>>[];
    if (_pendingRequestCount > 0) {
      items.add({
        'label': 'Customer Requests',
        'count': _pendingRequestCount,
        'icon': Icons.support_agent,
        'color': AppColors.error,
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const CustomerRequestsScreen(showBackButton: true),
              ),
            ),
      });
    }
    if (activeKOTs > 0) {
      items.add({
        'label': 'Active KOTs',
        'count': activeKOTs.toInt(),
        'icon': Icons.restaurant_menu,
        'color': AppColors.warning,
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const KotScreen()),
            ),
      });
    }
    if (pendingTasks > 0) {
      items.add({
        'label': 'Pending Tasks',
        'count': pendingTasks.toInt(),
        'icon': Icons.checklist,
        'color': AppColors.info,
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ChecklistsScreen(showBackButton: true),
              ),
            ),
      });
    }
    if (lowStockItems > 0) {
      items.add({
        'label': 'Low Stock Items',
        'count': lowStockItems.toInt(),
        'icon': Icons.inventory_2,
        'color': AppColors.warning,
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InventoryScreen()),
            ),
      });
    }
    return items;
  }

  void _maybeShowActionRequiredNotification() {
    if (!mounted) return;
    final items = _getActionRequiredItems();
    final signature = items.map((i) => '${i['label']}:${i['count']}').join('|');
    if (signature.isEmpty || signature == _lastActionRequiredSignature) return;
    _lastActionRequiredSignature = signature;

    final totalCount = items.fold<int>(
      0,
      (sum, item) => sum + ((item['count'] as int?) ?? 0),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Action Required: $totalCount pending alerts'),
          action: items.isNotEmpty
              ? SnackBarAction(
                  label: 'View',
                  onPressed: () => (items.first['onTap'] as VoidCallback)(),
                )
              : null,
        ),
      );
    });
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    if (value is num) return value != 0;
    return false;
  }

  String? _extractDateTimeString(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toIso8601String();
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is Map) {
      for (final key in const ['time', 'timestamp', 'date', 'at', 'value']) {
        final nested = _extractDateTimeString(value[key]);
        if (nested != null) return nested;
      }
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _firstNonEmptyDateTimeString(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final parsed = _extractDateTimeString(candidate);
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool _isAttendanceCheckedOut() {
    final attendance = _todayAttendance;
    if (attendance == null) return false;
    final attendanceStatus =
        attendance['attendanceStatus']?.toString().toLowerCase();
    final checkInStatus = attendance['checkInStatus']?.toString().toLowerCase();
    final status = attendance['status']?.toString().toLowerCase();
    final explicitCheckedOut = _toBool(attendance['isCheckedOut']) ||
        _toBool(attendance['checkedOut']) ||
        _toBool(attendance['isCheckout']);
    final hasCheckOutTime = _firstNonEmptyDateTimeString([
          attendance['checkOut'],
          attendance['checkout'],
          attendance['checkOutTime'],
          attendance['checkoutTime'],
          attendance['checkedOutAt'],
          attendance['checkOutAt'],
          attendance['checkoutAt'],
        ]) !=
        null;
    return explicitCheckedOut ||
        attendanceStatus == 'checked_out' ||
        attendanceStatus == 'checkedout' ||
        attendanceStatus == 'checked-out' ||
        checkInStatus == 'checked_out' ||
        checkInStatus == 'checkedout' ||
        checkInStatus == 'checked-out' ||
        status == 'checked_out' ||
        status == 'checkedout' ||
        status == 'checked-out' ||
        hasCheckOutTime;
  }

  bool _isAttendanceOnBreak() {
    final attendance = _todayAttendance;
    if (attendance == null || _isAttendanceCheckedOut()) return false;
    final currentBreak = attendance['currentBreak'];

    final attendanceStatus =
        attendance['attendanceStatus']?.toString().toLowerCase();
    final checkInStatus = attendance['checkInStatus']?.toString().toLowerCase();
    final status = attendance['status']?.toString().toLowerCase();
    final isOnBreakField =
        _toBool(attendance['isOnBreak']) || _toBool(attendance['onBreak']);
    final hasBreakStart = _firstNonEmptyDateTimeString([
          attendance['breakStart'],
          attendance['breakStartedAt'],
          currentBreak is Map ? currentBreak['breakStart'] : null,
        ]) !=
        null;
    return attendanceStatus == 'on_break' ||
        checkInStatus == 'on_break' ||
        status == 'on_break' ||
        isOnBreakField ||
        hasBreakStart;
  }

  String _calculateRealTimeHours() {
    final checkInTime = _getCheckInTime();
    if (checkInTime == null) return '0h 0m 0s';

    final checkOutTime = _getCheckOutTime();
    if (checkOutTime != null) {
      // Already checked out - use stored total
      final totalMinutes = _todayAttendance?['totalWorkingMinutes'] ?? 0;
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      return '${hours}h ${minutes}m';
    }

    // Currently checked in - calculate real-time
    final now = _currentTime;
    final totalSeconds = now.difference(checkInTime).inSeconds;

    // Subtract break time
    final breakMinutes = _todayAttendance?['breakMinutes'] ?? 0;
    int currentBreakSeconds = breakMinutes * 60;

    final breakStart = _getBreakStartTime();
    final isOnBreak = _isAttendanceOnBreak();

    if (isOnBreak && breakStart != null) {
      currentBreakSeconds += now.difference(breakStart).inSeconds;
    }

    int currentWorkingSeconds = totalSeconds - currentBreakSeconds;
    if (currentWorkingSeconds < 0) currentWorkingSeconds = 0;

    final hours = currentWorkingSeconds ~/ 3600;
    final minutes = (currentWorkingSeconds % 3600) ~/ 60;
    final seconds = currentWorkingSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  DateTime? _getCheckInTime() {
    final checkIn = _firstNonEmptyDateTimeString([
      _todayAttendance?['checkIn'],
      _todayAttendance?['checkin'],
      _todayAttendance?['checkInTime'],
      _todayAttendance?['checkinTime'],
      _todayAttendance?['checkInTimestamp'],
      _todayAttendance?['checkedInAt'],
      _todayAttendance?['checkInAt'],
      _todayAttendance?['createdAt'],
    ]);
    if (checkIn == null) return null;
    try {
      final dateTime = DateTime.parse(checkIn);
      // Convert to local time if it's UTC
      return dateTime.isUtc ? dateTime.toLocal() : dateTime;
    } catch (e) {
      return null;
    }
  }

  DateTime? _getCheckOutTime() {
    final checkOut = _firstNonEmptyDateTimeString([
      _todayAttendance?['checkOut'],
      _todayAttendance?['checkout'],
      _todayAttendance?['checkOutTime'],
      _todayAttendance?['checkoutTime'],
      _todayAttendance?['checkedOutAt'],
      _todayAttendance?['checkOutAt'],
      _todayAttendance?['checkoutAt'],
    ]);
    if (checkOut == null) return null;
    try {
      final dateTime = DateTime.parse(checkOut);
      return dateTime.isUtc ? dateTime.toLocal() : dateTime;
    } catch (e) {
      return null;
    }
  }

  DateTime? _getBreakStartTime() {
    final currentBreak = _todayAttendance?['currentBreak'];
    final breakStart = _firstNonEmptyDateTimeString([
      _todayAttendance?['breakStart'],
      _todayAttendance?['breakStartedAt'],
      currentBreak is Map ? currentBreak['breakStart'] : null,
    ]);
    if (breakStart == null) return null;
    try {
      final dateTime = DateTime.parse(breakStart);
      return dateTime.isUtc ? dateTime.toLocal() : dateTime;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final userName =
        appProvider.userName.isNotEmpty ? appProvider.userName : 'Manager';
    final isReadOnlyLocked = appProvider.isReadOnlyAfterCheckout;

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadDashboardData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final activeOrders = _stats['activeOrders'] ?? 0;
    final todayRevenue = _stats['todayRevenue'] ?? 0.0;
    final pendingTasks = _stats['pendingTasks'] ?? 0;
    final pendingKOTs = _stats['pendingKOTs'] ?? 0;
    final preparingKOTs = _stats['preparingKOTs'] ?? 0;
    final readyKOTs = _stats['readyKOTs'] ?? 0;
    final completedUnpaid = _stats['completedUnpaid'] ?? 0;
    final activeKOTs = pendingKOTs + preparingKOTs + readyKOTs;
    final lowStockItems = _stats['lowStockItems'] ?? 0;
    final todayAttendance = _stats['todayAttendance'] ?? 0;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboardData,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, $userName!',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ).animate().fadeIn().slideX(begin: -0.1),
                          const SizedBox(height: 4),
                          Text(
                            'Manager Dashboard',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                          ).animate().fadeIn(delay: 100.ms),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.dashboard,
                        color: Colors.white,
                        size: 24,
                      ),
                    ).animate().scale(delay: 200.ms),
                  ],
                ),

                const SizedBox(height: 24),

                if (isReadOnlyLocked) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
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
                ],

                // Attendance Card
                _buildAttendanceCard(context),

                const SizedBox(height: 24),

                // Revenue Card - clickable
                GestureDetector(
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PaymentsScreen())),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Today's Revenue",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '\u20B9${todayRevenue.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.currency_rupee,
                          color: Colors.white,
                          size: 40,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Stats Grid - clickable cards
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        context,
                        'Active Orders',
                        activeOrders.toString(),
                        Icons.receipt_long,
                        AppColors.primary,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const OrdersScreen(
                                      showBackButton: true,
                                      initialTabIndex: 1,
                                    ))),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        context,
                        'Served Unpaid',
                        completedUnpaid.toString(),
                        Icons.payments_outlined,
                        AppColors.warning,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const OrdersScreen(
                                      showBackButton: true,
                                      initialTabIndex: 1,
                                    ))),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        context,
                        'Active KOTs',
                        activeKOTs.toString(),
                        Icons.restaurant_menu,
                        AppColors.error,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const KotScreen())),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        context,
                        'Pending Tasks',
                        pendingTasks.toString(),
                        Icons.checklist,
                        AppColors.info,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ChecklistsScreen(
                                    showBackButton: true))),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        context,
                        'Low Stock',
                        lowStockItems.toString(),
                        Icons.inventory_2,
                        AppColors.warning,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const InventoryScreen())),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        context,
                        'Attendance',
                        todayAttendance.toString(),
                        Icons.people,
                        AppColors.success,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const ManagerEmployeeAttendanceScreen(
                                        showBackButton: true))),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                Builder(
                  builder: (context) {
                    final actionItems = _getActionRequiredItems();
                    if (actionItems.isEmpty) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.error_outline, color: AppColors.error),
                              SizedBox(width: 8),
                              Text(
                                'Action Required',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: actionItems.map((item) {
                              final color = item['color'] as Color;
                              return ActionChip(
                                avatar: Icon(
                                  item['icon'] as IconData,
                                  size: 18,
                                  color: color,
                                ),
                                label: Text(
                                  '${item['label']} (${item['count']})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onPressed: item['onTap'] as VoidCallback,
                                side: BorderSide(
                                  color: color.withValues(alpha: 0.4),
                                ),
                                backgroundColor: Colors.white,
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Quick Actions
                Text(
                  'Quick Actions',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),

                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.3,
                  children: [
                    _buildActionCard(
                      context,
                      'Attendance',
                      'Check In/Out',
                      Icons.access_time,
                      AppColors.info,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AttendanceScreen()),
                      ),
                    ),
                    _buildActionCard(
                      context,
                      'Employees',
                      'View All Attendance',
                      Icons.people,
                      AppColors.primary,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ManagerEmployeeAttendanceScreen(
                              showBackButton: true),
                        ),
                      ),
                    ),
                    _buildActionCard(
                      context,
                      'Payments',
                      'View Payments',
                      Icons.payment,
                      AppColors.success,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PaymentsScreen()),
                      ),
                    ),
                    _buildActionCard(
                      context,
                      'Compliance',
                      'Manage Compliance',
                      Icons.verified_user,
                      AppColors.warning,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ComplianceScreen()),
                      ),
                    ),
                    _buildActionCard(
                      context,
                      'Requests',
                      'Customer Requests',
                      Icons.support_agent,
                      AppColors.error,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CustomerRequestsScreen(
                                showBackButton: true)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceCard(BuildContext context) {
    final checkInTime = _getCheckInTime();
    final checkOutTime = _getCheckOutTime();
    final isCheckedOut = _isAttendanceCheckedOut();
    final isCheckedIn = checkInTime != null && !isCheckedOut;
    final isOnBreak = _isAttendanceOnBreak();

    String statusText = 'Not Checked In';
    if (isCheckedIn) {
      statusText = 'Checked In at ${_formatTime(checkInTime)}';
      if (isOnBreak) {
        statusText += ' | On Break';
      }
    } else if (isCheckedOut) {
      final safeCheckOutTime = checkOutTime ?? _currentTime;
      statusText = 'Checked Out at ${_formatTime(safeCheckOutTime)}';
    }

    final workingHoursText = _calculateRealTimeHours();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.warmGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's Shift",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    workingHoursText,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (checkInTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Check In: ${_formatTime(checkInTime)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                  if (checkOutTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Check Out: ${_formatTime(checkOutTime)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isCheckedIn
                                ? AppColors.success
                                : AppColors.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.access_time_filled,
                color: Colors.white,
                size: 35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                if (onTap != null)
                  Icon(Icons.arrow_forward_ios,
                      color: color.withValues(alpha: 0.5), size: 14),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
