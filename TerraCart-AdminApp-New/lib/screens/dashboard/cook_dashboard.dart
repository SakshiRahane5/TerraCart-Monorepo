import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../providers/app_provider.dart';
import '../../services/dashboard_service.dart';
import '../../services/attendance_service.dart';
import '../../services/socket_service.dart';
import '../../core/exceptions/api_exception.dart';
import '../kot/kot_screen.dart';
import '../attendance/attendance_screen.dart';
import '../inventory/inventory_screen.dart';

class CookDashboard extends StatefulWidget {
  const CookDashboard({super.key});

  @override
  State<CookDashboard> createState() => _CookDashboardState();
}

class _CookDashboardState extends State<CookDashboard> {
  final DashboardService _dashboardService = DashboardService();
  final AttendanceService _attendanceService = AttendanceService();
  final SocketService _socketService = SocketService();

  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String? _errorMessage;

  // Attendance state
  Map<String, dynamic>? _todayAttendance;
  bool _isAttendanceLoading = false;
  Timer? _attendanceTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadAttendanceData();
    _setupDashboardSocketListeners();
    _setupAttendanceSocketListeners();
    // Update attendance UI every second for real-time timer
    _attendanceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _todayAttendance != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _attendanceTimer?.cancel();
    _removeDashboardSocketListeners();
    _removeAttendanceSocketListeners();
    super.dispose();
  }

  void _setupDashboardSocketListeners() {
    void refreshDashboard(dynamic _) {
      if (!mounted) return;
      _dashboardService.invalidateCache();
      _loadDashboardData(showLoading: false);
    }

    _socketService.on('order:created', refreshDashboard,
        debounce: true, delay: const Duration(milliseconds: 500));
    _socketService.on('order_status_updated', refreshDashboard,
        debounce: true, delay: const Duration(milliseconds: 500));
    _socketService.on('order.cancelled', refreshDashboard,
        debounce: true, delay: const Duration(milliseconds: 500));
    _socketService.on('kot:created', refreshDashboard, debounce: true);
    _socketService.on('kot:status:updated', refreshDashboard, debounce: true);
  }

  void _removeDashboardSocketListeners() {
    _socketService.off('order:created');
    _socketService.off('order_status_updated');
    _socketService.off('order.cancelled');
    _socketService.off('kot:created');
    _socketService.off('kot:status:updated');
  }

  Future<void> _loadAttendanceData() async {
    if (_isAttendanceLoading) return;

    setState(() => _isAttendanceLoading = true);
    try {
      final attendanceList = await _attendanceService.getTodayAttendance();
      if (mounted) {
        setState(() {
          if (attendanceList.isNotEmpty) {
            _todayAttendance = attendanceList[0];
          } else {
            _todayAttendance = null;
          }
          _isAttendanceLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _todayAttendance = null;
          _isAttendanceLoading = false;
        });
      }
    }
  }

  void _setupAttendanceSocketListeners() {
    // Listen for socket connection and set up listeners when connected
    _socketService.on('connect', (_) {
      print(
          '[CookDashboard] Socket connected, setting up attendance listeners');
      _setupAttendanceEventListeners();
    });

    // If already connected, set up listeners immediately
    if (_socketService.isConnected) {
      print(
          '[CookDashboard] Socket already connected, setting up attendance listeners');
      _setupAttendanceEventListeners();
    } else {
      print(
          '[CookDashboard] Socket not connected yet, will set up listeners when connected');
      // Try again after a delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _socketService.isConnected) {
          _setupAttendanceEventListeners();
        }
      });
    }
  }

  void _setupAttendanceEventListeners() {
    print('[CookDashboard] Setting up attendance event listeners');

    _socketService.on('attendance:checked_in', (data) {
      print('[CookDashboard] 🔔 Socket event: attendance:checked_in');
      if (mounted) {
        _loadAttendanceData();
      }
    });

    _socketService.on('attendance:checked_out', (data) {
      print('[CookDashboard] 🔔 Socket event: attendance:checked_out');
      if (mounted) {
        _loadAttendanceData();
      }
    });

    _socketService.on('attendance:updated', (data) {
      print('[CookDashboard] 🔔 Socket event: attendance:updated');
      if (mounted) {
        _loadAttendanceData();
      }
    });

    _socketService.on('attendance:break_started', (data) {
      print('[CookDashboard] 🔔 Socket event: attendance:break_started');
      if (mounted) {
        _loadAttendanceData();
      }
    });

    _socketService.on('attendance:break_ended', (data) {
      print('[CookDashboard] 🔔 Socket event: attendance:break_ended');
      if (mounted) {
        _loadAttendanceData();
      }
    });
  }

  void _removeAttendanceSocketListeners() {
    _socketService.off('connect');
    _socketService.off('attendance:checked_in');
    _socketService.off('attendance:checked_out');
    _socketService.off('attendance:updated');
    _socketService.off('attendance:break_started');
    _socketService.off('attendance:break_ended');
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

  String? _readCheckInTimeRaw() {
    return _firstNonEmptyDateTimeString([
      _todayAttendance?['checkIn'],
      _todayAttendance?['checkin'],
      _todayAttendance?['checkInTime'],
      _todayAttendance?['checkinTime'],
      _todayAttendance?['checkInTimestamp'],
      _todayAttendance?['checkedInAt'],
      _todayAttendance?['checkInAt'],
      _todayAttendance?['createdAt'],
    ]);
  }

  String? _readCheckOutTimeRaw() {
    return _firstNonEmptyDateTimeString([
      _todayAttendance?['checkOut'],
      _todayAttendance?['checkout'],
      _todayAttendance?['checkOutTime'],
      _todayAttendance?['checkoutTime'],
      _todayAttendance?['checkedOutAt'],
      _todayAttendance?['checkOutAt'],
      _todayAttendance?['checkoutAt'],
    ]);
  }

  String? _readBreakStartRaw() {
    final currentBreak = _todayAttendance?['currentBreak'];
    return _firstNonEmptyDateTimeString([
      _todayAttendance?['breakStart'],
      _todayAttendance?['breakStartedAt'],
      currentBreak is Map ? currentBreak['breakStart'] : null,
    ]);
  }

  bool get _isCheckedIn {
    if (_todayAttendance == null) return false;
    if (_isCheckedOut) return false;

    final attendanceStatus =
        _todayAttendance!['attendanceStatus']?.toString().toLowerCase();
    final checkInStatus =
        _todayAttendance!['checkInStatus']?.toString().toLowerCase();
    if (attendanceStatus == 'checked_in' ||
        attendanceStatus == 'on_break' ||
        checkInStatus == 'checked_in') {
      return true;
    }

    final checkInTime = _readCheckInTimeRaw();
    final checkOutTime = _readCheckOutTimeRaw();
    return checkInTime != null &&
        checkInTime.isNotEmpty &&
        (checkOutTime == null || checkOutTime.isEmpty);
  }

  bool get _isCheckedOut {
    final attendanceStatus =
        _todayAttendance?['attendanceStatus']?.toString().toLowerCase();
    final checkInStatus =
        _todayAttendance?['checkInStatus']?.toString().toLowerCase();
    final status = _todayAttendance?['status']?.toString().toLowerCase();
    final explicitCheckedOut = _toBool(_todayAttendance?['isCheckedOut']) ||
        _toBool(_todayAttendance?['checkedOut']) ||
        _toBool(_todayAttendance?['isCheckout']);
    final hasCheckOutTime = _readCheckOutTimeRaw() != null;
    return explicitCheckedOut ||
        attendanceStatus == 'checked_out' ||
        attendanceStatus == 'checkedout' ||
        checkInStatus == 'checked_out' ||
        checkInStatus == 'checkedout' ||
        status == 'checked_out' ||
        status == 'checkedout' ||
        hasCheckOutTime;
  }

  bool get _isOnBreak {
    if (_isCheckedOut) return false;

    final attendanceStatus =
        _todayAttendance?['attendanceStatus']?.toString().toLowerCase();
    final checkInStatus =
        _todayAttendance?['checkInStatus']?.toString().toLowerCase();
    final status = _todayAttendance?['status']?.toString().toLowerCase();
    final isOnBreakField = _toBool(_todayAttendance?['isOnBreak']) ||
        _toBool(_todayAttendance?['onBreak']);
    final hasBreakStart = _readBreakStartRaw() != null;
    return attendanceStatus == 'on_break' ||
        checkInStatus == 'on_break' ||
        status == 'on_break' ||
        isOnBreakField ||
        hasBreakStart;
  }

  DateTime? get _checkInTime {
    final checkInTimeStr = _readCheckInTimeRaw();
    if (checkInTimeStr != null) {
      try {
        final parsed = DateTime.parse(checkInTimeStr);
        return parsed; // Keep raw moment for duration; use formatTimeIST for display
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  DateTime? get _breakStartTime {
    final breakStartStr = _readBreakStartRaw();
    if (breakStartStr != null) {
      try {
        return DateTime.parse(breakStartStr); // Keep raw moment for duration
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  String _formatTime(DateTime dateTime) =>
      DateTimeUtils.formatTimeIST(dateTime);

  String _formatBreakTime() {
    final breakMinutes = _todayAttendance?['breakDuration'] ?? 0;
    final breakStartTime = _breakStartTime;
    final isOnBreak = _isOnBreak;

    int breakSeconds = 0;
    if (isOnBreak && breakStartTime != null) {
      final now = DateTime.now();
      final currentBreakDuration = now.difference(breakStartTime).inSeconds;
      breakSeconds = (breakMinutes * 60) + currentBreakDuration;
    } else if (breakMinutes > 0) {
      breakSeconds = breakMinutes * 60;
    }

    final breakHours = breakSeconds ~/ 3600;
    final breakMins = (breakSeconds % 3600) ~/ 60;
    final breakSecs = breakSeconds % 60;

    if (isOnBreak && breakStartTime != null) {
      return '${breakHours.toString().padLeft(2, '0')}h ${breakMins.toString().padLeft(2, '0')}m ${breakSecs.toString().padLeft(2, '0')}s';
    } else {
      return '${breakHours.toString().padLeft(2, '0')}h ${breakMins.toString().padLeft(2, '0')}m';
    }
  }

  Future<void> _loadDashboardData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final stats = await _dashboardService.getDashboardStats();

      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
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

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final userName =
        appProvider.userName.isNotEmpty ? appProvider.userName : 'Cook';

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

    final pendingKOTs = _stats['pendingKOTs'] ?? 0;
    final preparingKOTs = _stats['preparingKOTs'] ?? 0;
    final readyKOTs = _stats['readyKOTs'] ?? 0;

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
                                ?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ).animate().fadeIn().slideX(begin: -0.1),
                          const SizedBox(height: 4),
                          Text(
                            'Cook Dashboard',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
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
                        Icons.restaurant,
                        color: Colors.white,
                        size: 24,
                      ),
                    ).animate().scale(delay: 200.ms),
                  ],
                ),

                const SizedBox(height: 24),

                // Attendance Widget
                _buildAttendanceWidget(),

                const SizedBox(height: 24),

                // KOT Stats Grid - clickable cards
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        context,
                        'Pending KOTs',
                        pendingKOTs.toString(),
                        Icons.pending_actions,
                        AppColors.warning,
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
                        'Preparing',
                        preparingKOTs.toString(),
                        Icons.restaurant_menu,
                        AppColors.info,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const KotScreen())),
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
                        'Ready',
                        readyKOTs.toString(),
                        Icons.check_circle,
                        AppColors.success,
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
                        'Total KOTs',
                        (pendingKOTs + preparingKOTs + readyKOTs).toString(),
                        Icons.receipt_long,
                        AppColors.primary,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const KotScreen())),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Quick Actions
                Text(
                  'Quick Actions',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
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
                      'Inventory',
                      'Real-time Stock View',
                      Icons.inventory_2,
                      AppColors.info,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const InventoryScreen()),
                      ),
                    ),
                    _buildActionCard(
                      context,
                      'Attendance',
                      'Check In/Out',
                      Icons.access_time,
                      AppColors.success,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AttendanceScreen()),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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

  Widget _buildAttendanceWidget() {
    final checkInTime = _checkInTime;
    final breakStartTime = _breakStartTime;
    final isCheckedIn = _isCheckedIn;
    final isCheckedOut = _isCheckedOut;
    final isOnBreak = _isOnBreak;
    final attendanceId = _todayAttendance?['_id']?.toString();
    final breakMinutes = _todayAttendance?['breakDuration'] ?? 0;

    // Calculate working hours
    int currentWorkingSeconds = 0;
    if (isCheckedIn && !isCheckedOut && checkInTime != null) {
      final now = DateTime.now();
      final totalElapsedSeconds = now.difference(checkInTime).inSeconds;
      if (isOnBreak && breakStartTime != null) {
        final workingTimeUntilBreak =
            breakStartTime.difference(checkInTime).inSeconds;
        int completedBreakSeconds = (breakMinutes * 60).toInt();
        currentWorkingSeconds =
            (workingTimeUntilBreak - completedBreakSeconds).toInt();
        if (currentWorkingSeconds < 0) currentWorkingSeconds = 0;
      } else {
        int completedBreakSeconds = (breakMinutes * 60).toInt();
        currentWorkingSeconds =
            (totalElapsedSeconds - completedBreakSeconds).toInt();
        if (currentWorkingSeconds < 0) currentWorkingSeconds = 0;
      }
    } else if (isCheckedOut) {
      final totalWorkingMinutes = _todayAttendance?['totalWorkingMinutes'] ?? 0;
      currentWorkingSeconds = (totalWorkingMinutes * 60).toInt();
    }

    final workingHours = currentWorkingSeconds ~/ 3600;
    final workingMins = (currentWorkingSeconds % 3600) ~/ 60;
    final workingSecs = currentWorkingSeconds % 60;

    // Status
    String statusText = 'Not Checked In';
    Color statusColor = AppColors.error;
    IconData statusIcon = Icons.logout;

    if (isCheckedIn && !isCheckedOut) {
      if (isOnBreak) {
        statusText = 'On Break';
        statusColor = AppColors.warning;
        statusIcon = Icons.coffee;
      } else {
        statusText = 'Working';
        statusColor = AppColors.success;
        statusIcon = Icons.work;
      }
    } else if (isCheckedOut) {
      statusText = 'Checked Out';
      statusColor = AppColors.info;
      statusIcon = Icons.check_circle;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
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
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Attendance',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(statusIcon, color: Colors.white, size: 20),
                  ],
                ),
              ],
            ),
            if (checkInTime != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.login,
                      color: Colors.white.withValues(alpha: 0.8), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Checked In: ${_formatTime(checkInTime)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            if (isCheckedIn && !isCheckedOut) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOnBreak ? 'Working Hours (Paused)' : 'Working Hours',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${workingHours.toString().padLeft(2, '0')}h ${workingMins.toString().padLeft(2, '0')}m ${workingSecs.toString().padLeft(2, '0')}s',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (isOnBreak || breakMinutes > 0) ...[
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
                          _formatBreakTime(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ] else if (isCheckedIn && isCheckedOut) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Working Hours',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${workingHours.toString().padLeft(2, '0')}h ${workingMins.toString().padLeft(2, '0')}m',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!isCheckedIn)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await _attendanceService.checkIn(
                              location: 'Dashboard');
                          _loadAttendanceData();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e is ApiException
                                    ? e.message
                                    : 'Failed to check in'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('Check In'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  )
                else if (!isCheckedOut) ...[
                  if (!isOnBreak)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: attendanceId == null
                            ? null
                            : () async {
                                try {
                                  await _attendanceService
                                      .startBreak(attendanceId);
                                  _loadAttendanceData();
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(e is ApiException
                                            ? e.message
                                            : 'Failed to start break'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: const Icon(Icons.coffee, size: 16),
                        label: const Text('Break'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: attendanceId == null
                            ? null
                            : () async {
                                try {
                                  await _attendanceService
                                      .endBreak(attendanceId);
                                  _loadAttendanceData();
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(e is ApiException
                                            ? e.message
                                            : 'Failed to end break'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Resume'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: attendanceId == null || isOnBreak
                          ? null
                          : () async {
                              try {
                                await _attendanceService.checkout(attendanceId,
                                    location: 'Dashboard');
                                _loadAttendanceData();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e is ApiException
                                          ? e.message
                                          : 'Failed to check out'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Check Out'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AttendanceScreen()),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward,
                      color: Colors.white, size: 20),
                  tooltip: 'View Details',
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }
}
