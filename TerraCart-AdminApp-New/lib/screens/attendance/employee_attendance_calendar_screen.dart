import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/attendance_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../services/attendance_service.dart';
import '../../services/schedule_service.dart';
import '../../core/exceptions/api_exception.dart';

class EmployeeAttendanceCalendarScreen extends StatefulWidget {
  final Map<String, dynamic> employee;

  const EmployeeAttendanceCalendarScreen({
    super.key,
    required this.employee,
  });

  @override
  State<EmployeeAttendanceCalendarScreen> createState() =>
      _EmployeeAttendanceCalendarScreenState();
}

class _EmployeeAttendanceCalendarScreenState
    extends State<EmployeeAttendanceCalendarScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final ScheduleService _scheduleService = ScheduleService();
  static const Duration _istOffset = Duration(hours: 5, minutes: 30);
  static const Color _offDayColor = Color(0xFF64748B);

  List<Map<String, dynamic>> _attendanceRecords = [];
  final Map<String, bool> _workingDaysByName = <String, bool>{};
  bool _isLoading = true;
  String? _errorMessage;
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAttendanceData();
  }

  Future<void> _loadAttendanceData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final employeeId = widget.employee['_id']?.toString();
      if (employeeId == null) {
        throw ApiException(message: 'Invalid employee ID');
      }

      // Get start and end of selected month
      final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final endDate =
          DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

      final results = await Future.wait<dynamic>([
        _attendanceService.getAllAttendance(
          employeeId: employeeId,
          startDate: startDate.toIso8601String().split('T')[0],
          endDate: endDate.toIso8601String().split('T')[0],
        ),
        _scheduleService
            .getEmployeeSchedule(employeeId)
            .catchError((_) => <String, dynamic>{}),
      ]);

      final attendance = (results[0] as List<dynamic>)
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final schedule =
          (results[1] is Map) ? Map<String, dynamic>.from(results[1]) : {};
      final weeklySchedule = schedule['weeklySchedule'];

      final workingDayMap = <String, bool>{};
      if (weeklySchedule is List) {
        for (final dayEntry in weeklySchedule.whereType<Map>()) {
          final rawDay = dayEntry['day']?.toString().toLowerCase().trim();
          if (rawDay == null || rawDay.isEmpty) continue;
          workingDayMap[rawDay] = dayEntry['isWorking'] == true;
        }
      }

      if (mounted) {
        setState(() {
          _attendanceRecords = attendance;
          _workingDaysByName
            ..clear()
            ..addAll(workingDayMap);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e is ApiException ? e.message : 'Failed to load attendance';
          _isLoading = false;
        });
      }
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    _loadAttendanceData();
  }

  String _toIstDateKey(DateTime date) {
    final istDate = date.toUtc().add(_istOffset);
    final year = istDate.year.toString().padLeft(4, '0');
    final month = istDate.month.toString().padLeft(2, '0');
    final day = istDate.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _normalizeDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'monday';
      case DateTime.tuesday:
        return 'tuesday';
      case DateTime.wednesday:
        return 'wednesday';
      case DateTime.thursday:
        return 'thursday';
      case DateTime.friday:
        return 'friday';
      case DateTime.saturday:
        return 'saturday';
      case DateTime.sunday:
        return 'sunday';
      default:
        return '';
    }
  }

  bool _isOffDay(DateTime date) {
    final dayName = _normalizeDayName(date.weekday);
    if (dayName.isEmpty) return false;
    if (_workingDaysByName.isEmpty) return false;
    return _workingDaysByName[dayName] == false;
  }

  Map<String, dynamic> _getAttendanceForDate(DateTime date) {
    final dateStr = _toIstDateKey(date);
    return _attendanceRecords.firstWhere(
      (att) {
        final attDate = att['date'];
        if (attDate == null) return false;
        final parsedDate = attDate is DateTime
            ? attDate
            : DateTime.tryParse(attDate.toString());
        if (parsedDate == null) return false;
        final attDateStr = _toIstDateKey(parsedDate);
        return attDateStr == dateStr;
      },
      orElse: () => <String, dynamic>{},
    );
  }

  Color _getDateColor(DateTime date, Map<String, dynamic>? attendance) {
    if (attendance == null || attendance.isEmpty) {
      if (_isOffDay(date)) return _offDayColor;
      return Colors.transparent;
    }

    // Use global attendance colors
    return AttendanceColors.getColorFromRecord(attendance);
  }

  String _getDateStatusLabel(DateTime date, Map<String, dynamic>? attendance) {
    if (attendance != null && attendance.isNotEmpty) {
      return AttendanceColors.getStatusText(attendance['status']?.toString());
    }
    if (_isOffDay(date)) return 'Off Day';
    return 'No Record';
  }

  Widget _buildCalendar() {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final firstDayOfWeek = firstDay.weekday % 7; // 0 = Sunday, 1 = Monday, etc.
    final daysInMonth = lastDay.day;

    final weekDays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      children: [
        // Month Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Text(
                DateFormat('MMMM yyyy').format(_selectedMonth),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
        ),

        // Week Days Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
          ),
          child: Row(
            children: weekDays.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Calendar Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: firstDayOfWeek + daysInMonth,
            itemBuilder: (context, index) {
              if (index < firstDayOfWeek) {
                return const SizedBox.shrink();
              }

              final day = index - firstDayOfWeek + 1;
              final date =
                  DateTime(_selectedMonth.year, _selectedMonth.month, day);
              final attendance = _getAttendanceForDate(date);
              final hasAttendance = attendance.isNotEmpty;
              final isOffDay = _isOffDay(date);
              final dateColor = _getDateColor(date, attendance);
              final isToday = date.year == DateTime.now().year &&
                  date.month == DateTime.now().month &&
                  date.day == DateTime.now().day;

              return GestureDetector(
                onTap: hasAttendance || isOffDay
                    ? () => _showAttendanceDetails(
                          date,
                          hasAttendance ? attendance : <String, dynamic>{},
                        )
                    : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: dateColor != Colors.transparent
                        ? dateColor.withValues(alpha: 0.2)
                        : Colors.transparent,
                    border: Border.all(
                      color: isToday
                          ? AppColors.primary
                          : dateColor != Colors.transparent
                              ? dateColor
                              : Colors.grey.withValues(alpha: 0.2),
                      width: isToday ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day.toString(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.normal,
                          color: isToday
                              ? AppColors.primary
                              : dateColor != Colors.transparent
                                  ? dateColor
                                  : AppColors.textSecondary,
                        ),
                      ),
                      if (hasAttendance || isOffDay) ...[
                        const SizedBox(height: 2),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: dateColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAttendanceDetails(DateTime date, Map<String, dynamic> attendance) {
    final isOffDay = attendance.isEmpty && _isOffDay(date);
    final checkIn = attendance['checkIn']?['time'];
    final checkOut = attendance['checkOut']?['time'];
    final statusLabel = _getDateStatusLabel(date, attendance);
    final totalWorkingMinutes = attendance['totalWorkingMinutes'] ?? 0;
    final breakMinutes = attendance['breakMinutes'] ?? 0;
    final isOnBreak = attendance['isOnBreak'] == true;

    String formatTime(String? timeStr) {
      if (timeStr == null) return 'N/A';
      try {
        return DateTimeUtils.formatTimeIST(DateTime.parse(timeStr));
      } catch (e) {
        return 'N/A';
      }
    }

    String formatDuration(int minutes) {
      if (minutes < 60) return '${minutes}m';
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                DateFormat('EEEE, MMMM d').format(date),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Status', statusLabel.toUpperCase()),
              if (!isOffDay && attendance.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Check In', formatTime(checkIn)),
                const SizedBox(height: 8),
                _buildDetailRow('Check Out', formatTime(checkOut)),
                if (totalWorkingMinutes > 0) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(
                      'Working Hours', formatDuration(totalWorkingMinutes)),
                ],
                if (breakMinutes > 0) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow('Break Time', formatDuration(breakMinutes)),
                ],
                if (isOnBreak) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.coffee, color: AppColors.warning, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Currently on break',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  isOffDay
                      ? 'This is marked as a non-working day in the weekly schedule.'
                      : 'No attendance record found for this date.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final employeeName = widget.employee['name'] ?? 'Unknown';
    final employeeRole = widget.employee['employeeRole'] ?? 'N/A';

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(employeeName),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(employeeName),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded),
          ),
        ),
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
                onPressed: _loadAttendanceData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(employeeName),
            Text(
              employeeRole.toUpperCase(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
            ),
          ],
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          IconButton(
            onPressed: _loadAttendanceData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Legend
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem(AttendanceColors.present, 'Present'),
                _buildLegendItem(AttendanceColors.halfDay, 'Half Day'),
                _buildLegendItem(AttendanceColors.late, 'Late'),
                _buildLegendItem(AttendanceColors.absent, 'Absent'),
                _buildLegendItem(_offDayColor, 'Off Day'),
              ],
            ),
          ),

          // Calendar
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _buildCalendar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
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
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}


