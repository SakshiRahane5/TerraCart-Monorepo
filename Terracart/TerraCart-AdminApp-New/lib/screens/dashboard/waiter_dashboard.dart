import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/utils/order_status_utils.dart';
import '../../providers/app_provider.dart';
import '../../services/dashboard_service.dart';
import '../../services/attendance_service.dart';
import '../../services/task_service.dart';
import '../../services/order_service.dart';
import '../../services/socket_service.dart';
import '../../models/task_model.dart';
import '../../models/order_model.dart';
import '../../core/exceptions/api_exception.dart';
import '../../core/services/cache_service.dart';
import '../orders/orders_screen.dart';
import '../orders/order_details_screen.dart';
import '../attendance/attendance_screen.dart';
import '../checklists/checklists_screen.dart';
import '../customer_requests/customer_requests_screen.dart';

class WaiterDashboard extends StatefulWidget {
  const WaiterDashboard({super.key});

  @override
  State<WaiterDashboard> createState() => _WaiterDashboardState();
}

class _WaiterDashboardState extends State<WaiterDashboard> {
  final DashboardService _dashboardService = DashboardService();
  final AttendanceService _attendanceService = AttendanceService();
  final TaskService _taskService = TaskService();
  final OrderService _orderService = OrderService();
  final SocketService _socketService = SocketService();

  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _todayAttendance;
  List<TaskModel> _todayTasks = [];
  List<OrderModel> _activeOrders = [];
  int _activeOrdersCount = 0;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _attendanceTimer;

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

  void _setupSocketListeners() {
    void refreshOrders(dynamic _) {
      if (!mounted) return;
      _dashboardService.invalidateCache();
      CacheService().remove(CacheService.orders);
      _loadDashboardData(showLoading: false);
    }

    // Order events with debouncing
    _socketService.on('order:created', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        CacheService().remove(CacheService.orders);
        _loadDashboardData(showLoading: false);
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

    // Table events
    _socketService.on('table:status:updated', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    // Task events
    _socketService.on('task:created', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        CacheService().remove(CacheService.tasks);
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    _socketService.on('task:completed', (_) {
      if (mounted) {
        _dashboardService.invalidateCache();
        CacheService().remove(CacheService.tasks);
        _loadDashboardData(showLoading: false);
      }
    }, debounce: true);

    // Request events
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
  }

  void _startAttendanceTimer() {
    // Update attendance display every second for real-time timers
    _attendanceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _todayAttendance == null) return;

      final isCheckedOut = _isAttendanceCheckedOut(_todayAttendance);
      final isOnBreak =
          _isAttendanceOnBreak(_todayAttendance, isCheckedOut: isCheckedOut);
      final isCheckedIn =
          _readCheckInTimeRaw(_todayAttendance) != null && !isCheckedOut;
      if (!isCheckedIn && !isOnBreak) return;

      setState(() {});
    });
  }

  Future<void> _loadDashboardData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait([
        _dashboardService
            .getDashboardStats(useCache: true)
            .catchError((e) => <String, dynamic>{}),
        _attendanceService
            .getTodayAttendance()
            .catchError((e) => <Map<String, dynamic>>[]),
        _taskService.getTodayTasks().catchError((e) => <TaskModel>[]),
        _orderService
            .getOrders(status: null, limit: 50)
            .catchError((e) => <OrderModel>[]),
      ]);

      if (mounted) {
        setState(() {
          _stats = results[0] as Map<String, dynamic>;
          final attendanceList = results[1] as List<Map<String, dynamic>>;
          _todayAttendance =
              attendanceList.isNotEmpty ? attendanceList.first : null;
          _todayTasks = results[2] as List<TaskModel>;
          final allOrders = results[3] as List<OrderModel>;
          final activeOrderPool = allOrders
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
              .toList(growable: false);

          _activeOrdersCount = activeOrderPool.length;
          _activeOrders = activeOrderPool
              .where((o) => o.serviceType == 'DINE_IN')
              .take(5)
              .toList(growable: false);
          _isLoading = false;
        });

        // Also update provider's attendance
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

  String _formatTime(DateTime dateTime) =>
      DateTimeUtils.formatTimeIST(dateTime);

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

  String? _readCheckInTimeRaw(Map<String, dynamic>? attendance) {
    if (attendance == null) return null;
    return _firstNonEmptyDateTimeString([
      attendance['checkIn'],
      attendance['checkin'],
      attendance['checkInTime'],
      attendance['checkinTime'],
      attendance['checkInTimestamp'],
      attendance['checkedInAt'],
      attendance['checkInAt'],
      attendance['createdAt'],
    ]);
  }

  String? _readCheckOutTimeRaw(Map<String, dynamic>? attendance) {
    if (attendance == null) return null;
    return _firstNonEmptyDateTimeString([
      attendance['checkOut'],
      attendance['checkout'],
      attendance['checkOutTime'],
      attendance['checkoutTime'],
      attendance['checkedOutAt'],
      attendance['checkOutAt'],
      attendance['checkoutAt'],
    ]);
  }

  String? _readBreakStartRaw(Map<String, dynamic>? attendance) {
    if (attendance == null) return null;
    return _firstNonEmptyDateTimeString([
      attendance['breakStart'],
      attendance['breakStartedAt'],
      attendance['currentBreak'] is Map
          ? attendance['currentBreak']['breakStart']
          : null,
    ]);
  }

  DateTime? _parseLocalDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final parsed = DateTime.parse(raw);
      return parsed.isUtc ? parsed.toLocal() : parsed;
    } catch (_) {
      return null;
    }
  }

  bool _isAttendanceCheckedOut(Map<String, dynamic>? attendance) {
    if (attendance == null) return false;
    final attendanceStatus =
        attendance['attendanceStatus']?.toString().toLowerCase();
    final checkInStatus = attendance['checkInStatus']?.toString().toLowerCase();
    final status = attendance['status']?.toString().toLowerCase();
    final explicitCheckedOut = _toBool(attendance['isCheckedOut']) ||
        _toBool(attendance['checkedOut']) ||
        _toBool(attendance['isCheckout']);
    final hasCheckOutTime = _readCheckOutTimeRaw(attendance) != null;
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

  bool _isAttendanceOnBreak(
    Map<String, dynamic>? attendance, {
    required bool isCheckedOut,
  }) {
    if (attendance == null || isCheckedOut) return false;

    final attendanceStatus =
        attendance['attendanceStatus']?.toString().toLowerCase();
    final checkInStatus = attendance['checkInStatus']?.toString().toLowerCase();
    final status = attendance['status']?.toString().toLowerCase();
    final isOnBreakField =
        _toBool(attendance['isOnBreak']) || _toBool(attendance['onBreak']);
    final hasBreakStart = _readBreakStartRaw(attendance) != null;
    return attendanceStatus == 'on_break' ||
        checkInStatus == 'on_break' ||
        status == 'on_break' ||
        isOnBreakField ||
        hasBreakStart;
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final userName =
        appProvider.userName.isNotEmpty ? appProvider.userName : 'Waiter';

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

    final activeOrders = _activeOrdersCount;
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
                            'Waiter Dashboard',
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
                        Icons.restaurant_menu,
                        color: Colors.white,
                        size: 24,
                      ),
                    ).animate().scale(delay: 200.ms),
                  ],
                ),

                const SizedBox(height: 24),

                // Attendance Widget with Break Controls
                _buildAttendanceWidget(context),

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
                                builder: (_) =>
                                    const OrdersScreen(showBackButton: true))),
                      ),
                    ),
                    const SizedBox(width: 12),
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

                // Daily Tasks Section
                _buildTasksSection(context),

                const SizedBox(height: 24),

                // Active Orders Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Active Orders',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const OrdersScreen(showBackButton: true)),
                        );
                      },
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildOrdersSection(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceWidget(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final isReadOnlyLocked = appProvider.isReadOnlyAfterCheckout;
    final checkInTimeStr = _readCheckInTimeRaw(_todayAttendance);
    final breakStartStr = _readBreakStartRaw(_todayAttendance);
    final isCheckedOut = _isAttendanceCheckedOut(_todayAttendance);
    final isOnBreak =
        _isAttendanceOnBreak(_todayAttendance, isCheckedOut: isCheckedOut);
    final breakMinutes = _todayAttendance?['breakMinutes'] ?? 0;
    final totalWorkingMinutes = _todayAttendance?['totalWorkingMinutes'] ?? 0;
    final attendanceId = _todayAttendance?['_id']?.toString();

    final checkInTime = _parseLocalDateTime(checkInTimeStr);
    final breakStart = _parseLocalDateTime(breakStartStr);

    final isCheckedIn = checkInTime != null && !isCheckedOut;

    // Calculate live working hours with seconds (real-time)
    String workingHoursText = '0h 0m 0s';
    int currentWorkingSeconds = 0;

    if (isCheckedIn && !isCheckedOut) {
      final now = DateTime.now();
      final totalSeconds = now.difference(checkInTime).inSeconds;

      // Subtract break time
      int currentBreakSeconds =
          breakMinutes * 60; // Convert break minutes to seconds
      if (isOnBreak && breakStart != null) {
        // Add current break duration in seconds
        currentBreakSeconds += now.difference(breakStart).inSeconds;
      }

      currentWorkingSeconds = totalSeconds - currentBreakSeconds;
      if (currentWorkingSeconds < 0) currentWorkingSeconds = 0;

      final hours = currentWorkingSeconds ~/ 3600;
      final minutes = (currentWorkingSeconds % 3600) ~/ 60;
      final seconds = currentWorkingSeconds % 60;
      workingHoursText =
          '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
    } else if (isCheckedOut) {
      // Use stored total working minutes (no seconds needed for completed)
      final hours = totalWorkingMinutes ~/ 60;
      final minutes = totalWorkingMinutes % 60;
      workingHoursText = '${hours}h ${minutes}m';
    }

    // Calculate break duration if on break (with seconds for real-time)
    String breakDurationText = '';
    if (isOnBreak && breakStart != null) {
      final now = DateTime.now();
      final breakDurationSeconds = now.difference(breakStart).inSeconds;
      final breakHours = breakDurationSeconds ~/ 3600;
      final breakMins = (breakDurationSeconds % 3600) ~/ 60;
      final breakSecs = breakDurationSeconds % 60;
      breakDurationText =
          '${breakHours.toString().padLeft(2, '0')}h ${breakMins.toString().padLeft(2, '0')}m ${breakSecs.toString().padLeft(2, '0')}s';
    } else if (breakMinutes > 0) {
      final breakHours = breakMinutes ~/ 60;
      final breakMins = breakMinutes % 60;
      breakDurationText = '${breakHours}h ${breakMins}m';
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isReadOnlyLocked) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Read-only mode active (checked out)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isCheckedIn && !isCheckedOut
                            ? (isOnBreak
                                ? AppColors.warning
                                : AppColors.success)
                            : AppColors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCheckedIn && !isCheckedOut
                          ? (isOnBreak ? 'On Break' : 'Working')
                          : isCheckedOut
                              ? 'Checked Out'
                              : 'Not Checked In',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (isCheckedIn && !isCheckedOut)
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AttendanceScreen()),
                      );
                    },
                    child: Text(
                      'View Details',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (checkInTime != null) ...[
              Row(
                children: [
                  Icon(Icons.login,
                      color: Colors.white.withValues(alpha: 0.8), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Checked In: ${_formatTime(checkInTime)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Working Hours',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      workingHoursText,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (isOnBreak || breakDurationText.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Break Time',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        breakDurationText,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (isCheckedIn && !isCheckedOut) ...[
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final id = attendanceId;
                  return Row(
                    children: [
                      if (!isOnBreak)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: id != null && !isReadOnlyLocked
                                ? () => _handleStartBreak(context, id)
                                : null,
                            icon: const Icon(Icons.coffee, size: 18),
                            label: const Text('Start Break'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.2),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: id != null && !isReadOnlyLocked
                                ? () => _handleEndBreak(context, id)
                                : null,
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Resume Work'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              id != null && !isOnBreak && !isReadOnlyLocked
                                  ? () => _handleCheckout(context, id)
                                  : null,
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text('Check Out'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleStartBreak(
      BuildContext context, String attendanceId) async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.isReadOnlyAfterCheckout) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('You have checked out for today. Read-only mode active.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    try {
      await _attendanceService.startBreak(attendanceId);
      await _loadDashboardData();
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Break started'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Failed to start break',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleEndBreak(
      BuildContext context, String attendanceId) async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.isReadOnlyAfterCheckout) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('You have checked out for today. Read-only mode active.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    try {
      await _attendanceService.endBreak(attendanceId);
      await _loadDashboardData();
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Break ended. Back to work!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Failed to end break',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleCheckout(
      BuildContext context, String attendanceId) async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.isReadOnlyAfterCheckout) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('You have checked out for today. Read-only mode active.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Check Out'),
        content: const Text('Are you sure you want to check out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Check Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _attendanceService.checkout(attendanceId);
      await _loadDashboardData();
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Checked out successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Failed to checkout',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
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

  Widget _buildTasksSection(BuildContext context) {
    final completedCount = _todayTasks
        .where((t) => t.status == 'completed' || t.status == 'complete')
        .length;
    final totalCount = _todayTasks.length;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const ChecklistsScreen(showBackButton: true)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.checklist,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Daily Tasks',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.textSecondary,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$completedCount/$totalCount Completed',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 8,
              ),
            ),
            if (_todayTasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...(_todayTasks
                  .take(3)
                  .map((task) => _buildTaskItem(context, task))),
              if (_todayTasks.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '+${_todayTasks.length - 3} more tasks',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: AppColors.primary,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.task_alt,
                        size: 32,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No tasks for today',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
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

  Widget _buildTaskItem(BuildContext context, TaskModel task) {
    final isCompleted = task.status == 'completed' || task.status == 'complete';
    Color priorityColor;
    switch (task.priority) {
      case 'high':
        priorityColor = AppColors.error;
        break;
      case 'medium':
        priorityColor = AppColors.warning;
        break;
      default:
        priorityColor = AppColors.info;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCompleted
            ? AppColors.success.withValues(alpha: 0.1)
            : priorityColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: isCompleted
            ? null
            : Border.all(color: priorityColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isCompleted ? AppColors.success : Colors.transparent,
              shape: BoxShape.circle,
              border: isCompleted
                  ? null
                  : Border.all(color: priorityColor, width: 2),
            ),
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              task.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                    color: isCompleted ? AppColors.textSecondary : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersSection(BuildContext context) {
    if (_activeOrders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long,
                  size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                'No active orders',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _activeOrders
          .map((order) => _buildOrderItem(context, order))
          .toList(),
    );
  }

  Widget _buildOrderItem(BuildContext context, OrderModel order) {
    Color statusColor;
    switch (order.status) {
      case 'Preparing':
        statusColor = AppColors.warning;
        break;
      case 'Ready':
        statusColor = AppColors.success;
        break;
      case 'Served':
        statusColor = AppColors.info;
        break;
      default:
        statusColor = AppColors.textSecondary;
    }

    final timeAgo = _getTimeAgo(order.createdAt);

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
          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
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
              width: 48,
              height: 48,
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        order.tableNumber != null
                            ? 'Table ${order.tableNumber}'
                            : 'Order #${order.id.substring(0, 6)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          order.status,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\u20B9${order.totalAmount.toStringAsFixed(2)} | $timeAgo',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) => DateTimeUtils.getTimeAgo(dateTime);
}
