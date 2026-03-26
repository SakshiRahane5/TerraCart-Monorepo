import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/utils/order_status_utils.dart';
import '../../providers/app_provider.dart';
import '../../services/dashboard_service.dart';
import '../../services/attendance_service.dart';
import '../../services/order_service.dart';
import '../../services/socket_service.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/services/cache_service.dart';
import '../../models/order_model.dart';
import '../orders/orders_screen.dart';
import '../orders/order_details_screen.dart';
import '../attendance/attendance_screen.dart';
import '../checklists/checklists_screen.dart';
import '../customer_requests/customer_requests_screen.dart';
import 'package:intl/intl.dart';

class CaptainDashboard extends StatefulWidget {
  const CaptainDashboard({super.key});

  @override
  State<CaptainDashboard> createState() => _CaptainDashboardState();
}

class _CaptainDashboardState extends State<CaptainDashboard> {
  final DashboardService _dashboardService = DashboardService();
  final AttendanceService _attendanceService = AttendanceService();
  final OrderService _orderService = OrderService();
  final SocketService _socketService = SocketService();

  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _todayAttendance;
  List<OrderModel> _currentOrders = [];
  List<OrderModel> _recentOrders = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadOrders();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _removeSocketListeners();
    super.dispose();
  }

  void _setupSocketListeners() {
    void refreshOrders(dynamic _) {
      if (!mounted) return;
      _dashboardService.invalidateCache();
      CacheService().remove(CacheService.orders);
      _loadDashboardData(showLoading: false);
      _loadOrders();
    }

    // Real-time updates for captain dashboard stats with debouncing
    _socketService.on('order:created', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        CacheService().remove(CacheService.orders);
        _loadDashboardData(showLoading: false);
        _loadOrders();
      }
    }, debounce: true, delay: const Duration(milliseconds: 500));
    _socketService.on('order:upsert', refreshOrders,
        debounce: true, delay: const Duration(milliseconds: 500));

    _socketService.on('order_status_updated', refreshOrders,
        debounce: true, delay: const Duration(milliseconds: 500));
    _socketService.on('order.cancelled', refreshOrders,
        debounce: true, delay: const Duration(milliseconds: 500));
    _socketService.on('kot:created', refreshOrders,
        debounce: true, delay: const Duration(milliseconds: 500));

    _socketService.on('table:status:updated', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    _socketService.on('task:created', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    _socketService.on('task:completed', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    _socketService.on('request:created', (_) {
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

    _socketService.on('attendance:checked_in', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    _socketService.on('attendance:checked_out', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);
  }

  void _removeSocketListeners() {
    _socketService.off('order:created');
    _socketService.off('order:upsert');
    _socketService.off('order_status_updated');
    _socketService.off('order.cancelled');
    _socketService.off('kot:created');
    _socketService.off('table:status:updated');
    _socketService.off('task:created');
    _socketService.off('task:completed');
    _socketService.off('request:created');
    _socketService.off('request:resolved');
    _socketService.off('attendance:checked_in');
    _socketService.off('attendance:checked_out');
  }

  Future<void> _loadDashboardData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final [stats, todayAttendance] = await Future.wait([
        _dashboardService.getDashboardStats(useCache: true),
        _attendanceService
            .getTodayAttendance()
            .catchError((e) => <Map<String, dynamic>>[]),
      ]);

      if (mounted) {
        setState(() {
          _stats = stats as Map<String, dynamic>;
          final attendanceList = todayAttendance as List<Map<String, dynamic>>;
          // For captain: filter by employeeId when multiple records (captain sees all cart attendance)
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

  Future<void> _loadOrders() async {
    try {
      final orders = await _orderService.getOrders(limit: 20);
      if (mounted) {
        setState(() {
          // Current orders: exclude employee-hidden terminal statuses.
          _currentOrders = orders
              .where((o) => OrderStatusUtils.shouldShowForEmployees(
                    status: o.status,
                    paymentStatus: o.paymentStatus,
                    isPaid: o.isPaid,
                    paymentMode: o.paymentMode,
                    officePaymentMode: o.officePaymentMode,
                    paymentRequiredBeforeProceeding:
                        o.paymentRequiredBeforeProceeding,
                    sourceQrType: o.sourceQrType,
                    serviceType: o.serviceType,
                    orderType: o.orderType,
                  ))
              .toList();
          // Recent settled orders: COMPLETED + PAID
          _recentOrders = orders
              .where((o) => OrderStatusUtils.isSettled(
                    status: o.status,
                    paymentStatus: o.paymentStatus,
                    isPaid: o.isPaid,
                  ))
              .take(5)
              .toList();
        });
      }
    } catch (e) {
      // Silently fail - orders are not critical for dashboard
      if (mounted) {
        setState(() {
          _currentOrders = [];
          _recentOrders = [];
        });
      }
    }
  }

  String _formatTime(DateTime dateTime) =>
      DateTimeUtils.formatTimeIST(dateTime);

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final userName =
        appProvider.userName.isNotEmpty ? appProvider.userName : 'Captain';
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

    final activeOrders = _currentOrders.length;
    final pendingTasks = _stats['pendingTasks'] ?? 0;
    final pendingRequests = _stats['pendingRequests'] ?? 0;

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
                          'Captain Dashboard',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                      Icons.supervisor_account,
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
                                  showBackButton: true, initialTabIndex: 1))),
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
                      'Pending Requests',
                      pendingRequests.toString(),
                      Icons.support_agent,
                      AppColors.warning,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CustomerRequestsScreen(
                                  showBackButton: true))),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Current Orders Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Current Orders',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OrdersScreen(
                            showBackButton: true,
                            initialTabIndex: 1,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_currentOrders.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.cardBorder.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No active orders',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...List.generate(
                  _currentOrders.length > 5 ? 5 : _currentOrders.length,
                  (index) => _buildOrderCard(_currentOrders[index], true),
                ),

              const SizedBox(height: 24),

              // Recent Orders Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Orders',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OrdersScreen(
                            showBackButton: true,
                            initialTabIndex: 1,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_recentOrders.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.cardBorder.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.history_outlined,
                          size: 48,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No recent orders',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...List.generate(
                  _recentOrders.length,
                  (index) => _buildOrderCard(_recentOrders[index], false),
                ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _buildAttendanceCard(BuildContext context) {
    final checkInTimeStr = _todayAttendance?['checkIn']?['time'];
    final checkOutTimeStr = _todayAttendance?['checkOut']?['time'];

    DateTime? checkInTime;
    DateTime? checkOutTime;

    if (checkInTimeStr != null) {
      try {
        final parsed = checkInTimeStr is DateTime
            ? checkInTimeStr
            : DateTime.parse(checkInTimeStr.toString());
        // Convert to local time if it's UTC (backend sends UTC)
        checkInTime = parsed.isUtc ? parsed.toLocal() : parsed;
      } catch (e) {
        checkInTime = null;
      }
    }

    if (checkOutTimeStr != null) {
      try {
        final parsed = checkOutTimeStr is DateTime
            ? checkOutTimeStr
            : DateTime.parse(checkOutTimeStr.toString());
        checkOutTime = parsed.isUtc ? parsed.toLocal() : parsed;
      } catch (e) {
        checkOutTime = null;
      }
    }

    final isCheckedIn = checkInTime != null && checkOutTime == null;

    String statusText = 'Not Checked In';
    if (isCheckedIn) {
      statusText = 'Checked In at ${_formatTime(checkInTime)}';
    } else if (checkOutTime != null) {
      statusText = 'Checked Out at ${_formatTime(checkOutTime)}';
    }

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
                    () {
                      if (checkInTime == null) return 'Not Started';
                      final checkIn = checkInTime;
                      final checkOut = checkOutTime;
                      return '${_formatTime(checkIn)} - ${checkOut != null ? _formatTime(checkOut) : "Ongoing"}';
                    }(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                      mainAxisSize: MainAxisSize.min,
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
                        Text(
                          statusText,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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

  Widget _buildOrderCard(OrderModel order, bool isCurrent) {
    Color statusColor;
    switch (order.status.toLowerCase()) {
      case 'pending':
        statusColor = AppColors.warning;
        break;
      case 'preparing':
      case 'in_progress':
        statusColor = AppColors.info;
        break;
      case 'ready':
        statusColor = AppColors.success;
        break;
      case 'paid':
        statusColor = AppColors.success;
        break;
      case 'cancelled':
        statusColor = AppColors.error;
        break;
      default:
        statusColor = AppColors.textSecondary;
    }

    // Extract table number safely - prefer tableNumber field, fallback to extraction
    String tableNumber = 'N/A';
    if (order.tableNumber != null && order.tableNumber!.isNotEmpty) {
      // Use the tableNumber field directly if available
      tableNumber = order.tableNumber!;
    } else if (order.tableId != null) {
      // Try to extract from tableId if it's a Map
      if (order.tableId is Map) {
        final tableMap = order.tableId as Map;
        final num = tableMap['tableNumber'] ?? tableMap['number'];
        if (num != null) {
          tableNumber = num.toString();
        }
      } else {
        // If tableId is a string, try to parse it or use a safe fallback
        final tableIdStr = order.tableId.toString();
        // If it looks like an object string, don't use it
        if (!tableIdStr.startsWith('{') && !tableIdStr.contains('_id:')) {
          tableNumber = tableIdStr;
        }
      }
    }

    final orderTime = DateFormat('hh:mm a').format(order.createdAt);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailsScreen(order: order),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent
                ? statusColor.withValues(alpha: 0.3)
                : AppColors.cardBorder.withValues(alpha: 0.3),
            width: isCurrent ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.receipt_long,
                color: statusColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Order #${order.id}',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          order.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.table_restaurant,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Text(
                              'Table $tableNumber',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: Text(
                              orderTime,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\u20B9${order.totalAmount.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
