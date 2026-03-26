import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../providers/app_provider.dart';
import '../../services/dashboard_service.dart';
import '../../services/attendance_service.dart';
import '../../core/exceptions/api_exception.dart';
import '../checklists/checklists_screen.dart';
import '../customer_requests/customer_requests_screen.dart';
import '../kot/kot_screen.dart';
import '../compliance/compliance_screen.dart';
import '../accessibility/accessibility_screen.dart';
import '../attendance/attendance_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _dashboardService = DashboardService();
  final AttendanceService _attendanceService = AttendanceService();

  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _todayAttendance;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final [stats, todayAttendance] = await Future.wait([
        _dashboardService.getDashboardStats(),
        _attendanceService
            .getTodayAttendance()
            .catchError((e) => <Map<String, dynamic>>[]),
      ]);

      if (mounted) {
        setState(() {
          _stats = stats as Map<String, dynamic>;
          final attendanceList = todayAttendance as List<Map<String, dynamic>>;
          _todayAttendance =
              attendanceList.isNotEmpty ? attendanceList.first : null;
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
    final userRole = appProvider.userRole;
    final userName = appProvider.userName.isNotEmpty
        ? appProvider.userName
        : _getDefaultRoleName(userRole);

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

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getGreeting(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userName,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Notification Badge
                      Stack(
                        children: [
                          IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.notifications_outlined,
                                size: 28),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '3',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Accessibility Button
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AccessibilityScreen(),
                            ),
                          );
                        },
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.accessibility_new_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ).animate().fadeIn().slideY(begin: -0.1),

              const SizedBox(height: 24),

              // Today's Attendance Card
              _buildAttendanceCard(context),

              const SizedBox(height: 24),

              // Performance Overview
              _buildPerformanceSection(context, userRole),

              const SizedBox(height: 24),

              // Quick Actions Title
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 16),

              // Role-Based Action Cards
              _buildActionCards(context, userRole),

              const SizedBox(height: 24),

              // Recent Activity
              _buildRecentActivity(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceCard(BuildContext context) {
    final checkInTime = _todayAttendance?['checkIn']?['time'];
    final checkOutTime = _todayAttendance?['checkOut']?['time'];
    final isCheckedIn = checkInTime != null;

    String statusText = 'Not Checked In';
    if (isCheckedIn && checkOutTime == null) {
      final checkIn = DateTime.parse(checkInTime);
      statusText = 'Checked In at ${_formatTime(checkIn)}';
    } else if (checkOutTime != null) {
      final checkOut = DateTime.parse(checkOutTime);
      statusText = 'Checked Out at ${_formatTime(checkOut)}';
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
                    _todayAttendance != null
                        ? '${_formatTime(DateTime.parse(_todayAttendance!['checkIn']?['time'] ?? DateTime.now().toIso8601String()))} - ${checkOutTime != null ? _formatTime(DateTime.parse(checkOutTime)) : "Ongoing"}'
                        : 'Not Started',
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
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1);
  }

  String _formatTime(DateTime dateTime) =>
      DateTimeUtils.formatTimeIST(dateTime);

  Widget _buildPerformanceSection(BuildContext context, String userRole) {
    // Get stats based on role
    String tasksValue = '0';
    String ordersValue = '0';
    String ratingValue = '4.5★';

    if (userRole == 'waiter') {
      tasksValue = '${_stats['myTasks'] ?? 0}';
      ordersValue = '${_stats['todayOrders'] ?? 0}';
    } else if (userRole == 'cook') {
      tasksValue = '${_stats['pendingKOTs'] ?? 0}';
      ordersValue = '${_stats['preparingKOTs'] ?? 0}';
    } else if (userRole == 'captain') {
      tasksValue = '${_stats['myTasks'] ?? _stats['totalTasks'] ?? 0}';
      ordersValue = '${_stats['todayOrders'] ?? 0}';
    } else if (userRole == 'manager') {
      final completedTasks = _stats['completedTasks'] ?? 0;
      final totalTasks = _stats['totalTasks'] ?? 0;
      tasksValue = totalTasks > 0 ? '$completedTasks/$totalTasks' : '0';
      ordersValue = '${_stats['todayOrders'] ?? 0}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance Overview',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                userRole == 'cook'
                    ? 'Pending KOTs'
                    : userRole == 'captain'
                        ? 'Team Tasks'
                        : 'Tasks',
                tasksValue,
                userRole == 'cook'
                    ? Icons.restaurant_menu
                    : userRole == 'captain'
                        ? Icons.groups
                        : Icons.task_alt,
                AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                'Orders',
                ordersValue,
                Icons.receipt_long,
                AppColors.info,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                userRole == 'manager'
                    ? 'Revenue'
                    : userRole == 'captain'
                        ? 'Team Rating'
                        : 'Rating',
                userRole == 'manager'
                    ? '\u20B9${(_stats['todayRevenue'] ?? 0).toStringAsFixed(0)}'
                    : ratingValue,
                userRole == 'manager'
                    ? Icons.currency_rupee
                    : userRole == 'captain'
                        ? Icons.star_border
                        : Icons.star,
                AppColors.warning,
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning ☀️';
    if (hour < 17) return 'Good Afternoon 🌤️';
    return 'Good Evening 🌙';
  }

  String _getDefaultRoleName(String role) {
    switch (role) {
      case 'waiter':
        return 'Waiter';
      case 'cook':
        return 'Cook';
      case 'captain':
        return 'Captain';
      case 'manager':
        return 'Manager';
      default:
        return 'Staff Member';
    }
  }

  Widget _buildActionCards(BuildContext context, String role) {
    final pendingTasks = _stats['myTasks'] ?? _stats['totalTasks'] ?? 0;
    final pendingRequests = _stats['pendingRequests'] ?? 0;
    final pendingKOTs = _stats['pendingKOTs'] ?? 0;
    final expiringCompliance = _stats['expiringCompliance'] ?? 0;

    final actions = <Map<String, dynamic>>[
      {
        'title': 'Tasks',
        'subtitle': '$pendingTasks pending',
        'icon': Icons.checklist_rounded,
        'color': AppColors.info,
        'badge': pendingTasks > 0 ? pendingTasks.toString() : null,
        'onTap': () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ChecklistsScreen(showBackButton: true)),
            ),
      },
      if (role != 'cook')
        {
          'title': 'Requests',
          'subtitle': '$pendingRequests new',
          'icon': Icons.support_agent_rounded,
          'color': AppColors.warning,
          'badge': pendingRequests > 0 ? pendingRequests.toString() : null,
          'onTap': () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const CustomerRequestsScreen(showBackButton: true)),
              ),
        },
      if (role == 'cook' || role == 'manager')
        {
          'title': 'KOT',
          'subtitle': '$pendingKOTs active',
          'icon': Icons.restaurant_menu,
          'color': AppColors.error,
          'badge': pendingKOTs > 0 ? pendingKOTs.toString() : null,
          'onTap': () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const KotScreen()),
              ),
        },
      if (role == 'captain')
        {
          'title': 'Team Tasks',
          'subtitle': 'Monitor team',
          'icon': Icons.groups,
          'color': AppColors.info,
          'badge': null,
          'onTap': () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const ChecklistsScreen(showBackButton: true)),
              ),
        },
      if (role == 'manager')
        {
          'title': 'Compliance',
          'subtitle': '$expiringCompliance expiring',
          'icon': Icons.verified_user,
          'color': AppColors.success,
          'badge': expiringCompliance > 0 ? '!' : null,
          'onTap': () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ComplianceScreen()),
              ),
        },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return _buildActionCard(
          context,
          action['title'],
          action['subtitle'],
          action['icon'],
          action['color'],
          action['badge'],
          action['onTap'],
        ).animate().fadeIn(delay: Duration(milliseconds: 400 + (index * 100)));
      },
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    String? badge,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dashboardService.getRecentActivity(limit: 5),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final activities = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (activities.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'No recent activity',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              )
            else
              ...activities.take(3).map((activity) {
                final icon = _getActivityIcon(activity['type']);
                final color = _getActivityColor(activity['type']);
                final timeAgo = _getTimeAgo(activity['timestamp']);

                return _buildActivityItem(
                  context,
                  activity['message'] ?? 'Activity',
                  timeAgo,
                  icon,
                  color,
                );
              }),
          ],
        ).animate().fadeIn(delay: 600.ms);
      },
    );
  }

  IconData _getActivityIcon(String? type) {
    switch (type) {
      case 'order':
        return Icons.receipt_long;
      case 'request':
        return Icons.support_agent;
      case 'task':
        return Icons.task_alt;
      default:
        return Icons.notifications;
    }
  }

  Color _getActivityColor(String? type) {
    switch (type) {
      case 'order':
        return AppColors.success;
      case 'request':
        return AppColors.warning;
      case 'task':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'Just now';
    try {
      final dateTime = timestamp is String
          ? DateTime.parse(timestamp)
          : DateTime.fromMillisecondsSinceEpoch(timestamp);
      return DateTimeUtils.getTimeAgo(dateTime);
    } catch (e) {
      return 'Recently';
    }
  }

  Widget _buildActivityItem(
    BuildContext context,
    String title,
    String time,
    IconData icon,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.cardBorder.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                Text(
                  time,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
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
    );
  }
}
