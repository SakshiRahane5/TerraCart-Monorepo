import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/attendance_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../services/attendance_service.dart';
import '../../services/user_service.dart';
import '../../services/employee_service.dart';
import '../../services/socket_service.dart';
import '../../providers/app_provider.dart';
import '../../core/exceptions/api_exception.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final UserService _userService = UserService();
  final EmployeeService _employeeService = EmployeeService();
  final SocketService _socketService = SocketService();

  Map<String, dynamic>? _todayAttendance;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _pastAttendance = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;
  Timer? _timer;
  String? _locationAddress;
  bool _didInitialDependencyLoad = false;
  bool _socketListenersAttached = false;
  bool _isAttendanceLoadInProgress = false;
  DateTime? _lastAttendanceLoadAt;
  static const Duration _minAttendanceReloadGap = Duration(milliseconds: 400);
  static const List<String> _attendanceSocketEvents = <String>[
    'attendance:checked_in',
    'attendance:checked_out',
    'attendance:updated',
    'attendance:break_started',
    'attendance:break_ended',
  ];

  @override
  void initState() {
    super.initState();
    _loadAttendanceData(force: true);
    _fetchLocationAddress();
    // Setup socket listeners after a short delay to ensure socket is connected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSocketListeners();
    });
    // Update UI every second for real-time timers
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      // Rebuild live timers only while actively checked in/on break.
      if (_isCheckedOut || (!_isCheckedIn && !_isOnBreak)) return;

      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Avoid repeated reload loops caused by inherited widget updates.
    if (_didInitialDependencyLoad) return;
    _didInitialDependencyLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadAttendanceData(force: true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _removeSocketListeners();
    super.dispose();
  }

  void _setupSocketListeners() {
    if (_socketListenersAttached) return;
    if (!_socketService.isConnected) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _setupSocketListeners();
      });
      return;
    }

    _socketListenersAttached = true;
    for (final event in _attendanceSocketEvents) {
      _socketService.on(event, _handleAttendanceSocketEvent);
    }
  }

  void _removeSocketListeners() {
    if (!_socketListenersAttached) return;
    _socketListenersAttached = false;
    for (final event in _attendanceSocketEvents) {
      _socketService.off(event);
    }
  }

  void _handleAttendanceSocketEvent(dynamic data) {
    if (!mounted) return;

    if (data is! Map) {
      _loadAttendanceData();
      return;
    }

    final payload = data.map((key, value) => MapEntry(key.toString(), value));
    if (!_isCurrentUserAttendancePayload(payload)) return;

    final attendanceId = payload['_id']?.toString();
    final currentAttendanceId = _todayAttendance?['_id']?.toString();
    final canApplyImmediately = attendanceId != null &&
        (attendanceId == currentAttendanceId || _todayAttendance == null);

    if (canApplyImmediately) {
      setState(() {
        _todayAttendance = Map<String, dynamic>.from(payload);
        _isLoading = false;
      });
    }

    _loadAttendanceData();
  }

  bool _isCurrentUserAttendancePayload(Map<String, dynamic> payload) {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final currentEmployeeId = appProvider.currentUser?.employeeId?.toString();
    if (currentEmployeeId == null || currentEmployeeId.isEmpty) return true;

    final payloadEmployee = payload['employeeId'];
    String? payloadEmployeeId;
    if (payloadEmployee is Map) {
      payloadEmployeeId = payloadEmployee['_id']?.toString() ??
          payloadEmployee['id']?.toString();
    } else if (payloadEmployee is String) {
      payloadEmployeeId = payloadEmployee;
    } else {
      payloadEmployeeId = payloadEmployee?.toString();
    }

    if (payloadEmployeeId == null || payloadEmployeeId.isEmpty) return true;
    return payloadEmployeeId == currentEmployeeId;
  }

  Future<void> _loadAttendanceData({bool force = false}) async {
    final now = DateTime.now();
    if (!force) {
      if (_isAttendanceLoadInProgress) return;
      if (_lastAttendanceLoadAt != null &&
          now.difference(_lastAttendanceLoadAt!) < _minAttendanceReloadGap) {
        return;
      }
    }

    _isAttendanceLoadInProgress = true;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final [todayAttendance, stats, pastAttendance] = await Future.wait([
        _attendanceService
            .getTodayAttendance()
            .catchError((e) => <Map<String, dynamic>>[]),
        _attendanceService
            .getAttendanceStats()
            .catchError((e) => <String, dynamic>{}),
        _attendanceService
            .getPastAttendance()
            .catchError((e) => <Map<String, dynamic>>[]),
      ]);

      if (mounted) {
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        final currentUser = appProvider.currentUser;
        final currentEmployeeId = currentUser?.employeeId;

        final attendanceList = todayAttendance as List<Map<String, dynamic>>;

        // Filter attendance to only get the current user's record
        Map<String, dynamic>? userAttendance;
        if (currentEmployeeId != null && attendanceList.isNotEmpty) {
          userAttendance = attendanceList.firstWhere(
            (record) {
              final recordEmployeeId = record['employeeId'];
              // Handle different employeeId formats
              String? recordId;
              if (recordEmployeeId is Map) {
                recordId = recordEmployeeId['_id']?.toString();
              } else if (recordEmployeeId is String) {
                recordId = recordEmployeeId;
              }
              return recordId?.toString() == currentEmployeeId.toString();
            },
            orElse: () => <String, dynamic>{},
          );

          // If no match found, check if it's an empty map
          if (userAttendance.isEmpty) {
            userAttendance = null;
          }
        } else if (attendanceList.isNotEmpty && currentEmployeeId == null) {
          // Fallback: if no employeeId, take first record.
          userAttendance = attendanceList.first;
        }

        setState(() {
          _todayAttendance = userAttendance;
          _stats = stats as Map<String, dynamic>?;
          _pastAttendance = pastAttendance as List<Map<String, dynamic>>;
          _isLoading = false;
        });

        appProvider.syncTodayAttendanceSnapshot(userAttendance);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e is ApiException ? e.message : 'Failed to load attendance data';
          _isLoading = false;
        });
      }
    } finally {
      _lastAttendanceLoadAt = DateTime.now();
      _isAttendanceLoadInProgress = false;
    }
  }

  Future<void> _fetchLocationAddress() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      String? cartId = appProvider.currentUser?.cartId;

      // If cartId is not in user object, try to get it from employee record
      if ((cartId == null || cartId.isEmpty) &&
          appProvider.currentUser?.employeeId != null) {
        try {
          final employeeId = appProvider.currentUser!.employeeId!;
          final employeeData =
              await _employeeService.getEmployeeById(employeeId);
          cartId = employeeData['cartId']?.toString() ??
              employeeData['cafeId']
                  ?.toString(); // Support both for backward compatibility
        } catch (_) {}
      }

      if (cartId != null && cartId.isNotEmpty) {
        final cafeData = await _userService.getUserById(cartId);

        // Prefer address, fallback to location
        final address = cafeData['address'] ?? cafeData['location'];

        if (mounted) {
          setState(() {
            _locationAddress = address ?? 'Location not specified';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _locationAddress = 'Location not specified';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationAddress = 'Location not available';
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

  String? _readCheckInTimeRaw() {
    if (_todayAttendance == null) return null;
    return _firstNonEmptyDateTimeString([
      _todayAttendance!['checkIn'],
      _todayAttendance!['checkin'],
      _todayAttendance!['checkInTime'],
      _todayAttendance!['checkinTime'],
      _todayAttendance!['checkInTimestamp'],
      _todayAttendance!['checkedInAt'],
      _todayAttendance!['checkInAt'],
      _todayAttendance!['createdAt'],
    ]);
  }

  String? _readCheckOutTimeRaw() {
    if (_todayAttendance == null) return null;
    return _firstNonEmptyDateTimeString([
      _todayAttendance!['checkOut'],
      _todayAttendance!['checkout'],
      _todayAttendance!['checkOutTime'],
      _todayAttendance!['checkoutTime'],
      _todayAttendance!['checkedOutAt'],
      _todayAttendance!['checkOutAt'],
      _todayAttendance!['checkoutAt'],
    ]);
  }

  String? _readBreakStartRaw() {
    if (_todayAttendance == null) return null;
    return _firstNonEmptyDateTimeString([
      _todayAttendance!['breakStart'],
      _todayAttendance!['breakStartedAt'],
      _todayAttendance!['currentBreak'] is Map
          ? _todayAttendance!['currentBreak']['breakStart']
          : null,
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

    final isCheckedIn = checkInTime != null &&
        checkInTime.isNotEmpty &&
        (checkOutTime == null || checkOutTime.isEmpty);

    return isCheckedIn;
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
        attendanceStatus == 'checked-out' ||
        checkInStatus == 'checked_out' ||
        checkInStatus == 'checkedout' ||
        checkInStatus == 'checked-out' ||
        status == 'checked_out' ||
        status == 'checkedout' ||
        status == 'checked-out' ||
        hasCheckOutTime;
  }

  bool get _isOnBreak {
    if (_isCheckedOut) return false;

    // Check both isOnBreak field and breakStart to determine if on break
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
    if (_todayAttendance == null) return null;

    // Try multiple formats for checkIn time
    String? checkInTimeStr;
    final checkIn = _todayAttendance!['checkIn'];

    // Format 1: checkIn is an object with 'time' property
    if (checkIn is Map) {
      checkInTimeStr = checkIn['time']?.toString();
      // Also try 'timestamp' or 'date' fields
      if (checkInTimeStr == null) {
        checkInTimeStr =
            checkIn['timestamp']?.toString() ?? checkIn['date']?.toString();
      }
    } else if (checkIn is String) {
      // Format 2: checkIn is directly a string
      checkInTimeStr = checkIn;
    }

    // Also check for direct time fields at root level
    if (checkInTimeStr == null) {
      checkInTimeStr = _todayAttendance!['checkInTime']?.toString() ??
          _todayAttendance!['checkInTimestamp']?.toString() ??
          _todayAttendance!['createdAt']?.toString();
    }

    if (checkInTimeStr != null && checkInTimeStr.isNotEmpty) {
      try {
        final parsed = DateTime.parse(checkInTimeStr);
        // Convert UTC to local time (IST)
        final localTime = parsed.isUtc ? parsed.toLocal() : parsed;
        return localTime;
      } catch (e) {
        // Try to use createdAt as fallback if checkIn parsing fails
        final createdAt = _todayAttendance!['createdAt']?.toString();
        if (createdAt != null && createdAt.isNotEmpty) {
          try {
            final parsed = DateTime.parse(createdAt);
            return parsed.isUtc ? parsed.toLocal() : parsed;
          } catch (_) {}
        }
        return null;
      }
    }
    return null;
  }

  DateTime? get _checkOutTime {
    final checkOutTimeStr = _readCheckOutTimeRaw();
    if (checkOutTimeStr != null) {
      try {
        final parsed = DateTime.parse(checkOutTimeStr);
        // Convert UTC to local time (IST)
        return parsed.isUtc ? parsed.toLocal() : parsed;
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
        final parsed = DateTime.parse(breakStartStr);
        // Convert UTC to local time (IST)
        return parsed.isUtc ? parsed.toLocal() : parsed;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Future<void> _handleCheckIn() async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.isTodayOffDay) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                appProvider.todayScheduleMessage ?? 'Today is your off day.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    if (appProvider.isReadOnlyAfterCheckout || _isCheckedOut) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('You have checked out for today. Read-only mode active.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    // Always reload data first to get latest state
    await _loadAttendanceData(force: true);

    // If already checked in, just show message and return
    if (_isCheckedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ℹ️ Already checked in. Timer is running.'),
            backgroundColor: AppColors.info,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final result = await _attendanceService.checkIn(
        location: _locationAddress ?? 'Location not available',
      );

      if (mounted) {
        // Update UI from API response immediately, then refetch for confirmation
        setState(() {
          _todayAttendance = Map<String, dynamic>.from(result);
          _isLoading = false;
        });
        await _loadAttendanceData(force: true);
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Checked in successfully! Timer started.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMessage =
            e is ApiException ? e.message : 'Failed to check in';
        // Check if error is about already checked in
        if (errorMessage.toLowerCase().contains('already') ||
            errorMessage.toLowerCase().contains('checked in')) {
          // Use attendance from 409 response so UI shows immediately
          final responseData = e is ApiException ? e.data : null;
          if (responseData is Map && responseData['attendance'] != null) {
            setState(() {
              _todayAttendance =
                  Map<String, dynamic>.from(responseData['attendance'] as Map);
              _isLoading = false;
            });
          }
          await _loadAttendanceData(force: true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ℹ️ $errorMessage. Timer is running.'),
              backgroundColor: AppColors.info,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleStartBreak() async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.isReadOnlyAfterCheckout || _isCheckedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('You have checked out for today. Read-only mode active.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final attendanceId = _todayAttendance?['_id']?.toString();
    if (attendanceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '⚠️ Attendance record not found. Please check in first.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_isOnBreak) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ You are already on break.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await _attendanceService.startBreak(attendanceId);
      if (mounted) {
        // Reload full data to get updated attendance from backend
        await _loadAttendanceData(force: true);

        // Verify break was started
        if (_todayAttendance != null &&
            (_todayAttendance!['isOnBreak'] == true ||
                _todayAttendance!['breakStart'] != null)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Break started'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          // Break didn't start properly, show error
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('⚠️ Break may not have started. Please refresh.'),
              backgroundColor: AppColors.warning,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Failed to start break',
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleEndBreak() async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.isReadOnlyAfterCheckout || _isCheckedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('You have checked out for today. Read-only mode active.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final attendanceId = _todayAttendance?['_id']?.toString();
    if (attendanceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '⚠️ Attendance record not found. Please check in first.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (!_isOnBreak) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ You are not currently on break.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final result = await _attendanceService.endBreak(attendanceId);
      if (mounted) {
        // Reload full data to get updated attendance from backend
        await _loadAttendanceData(force: true);

        // Show success message with break duration if available
        final breakDuration = result['breakDuration'] ??
            result['data']?['breakDuration'] ??
            result['attendance']?['breakDuration'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(breakDuration != null
                ? '✅ Break ended. Duration: $breakDuration minutes'
                : '✅ Break ended. Back to work!'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Failed to end break',
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleCheckOut() async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.isReadOnlyAfterCheckout || _isCheckedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('You have checked out for today. Read-only mode active.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final attendanceId = _todayAttendance?['_id']?.toString();
    if (attendanceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '⚠️ Attendance record not found. Please check in first.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_isOnBreak) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '⚠️ Cannot checkout while on break. Please end break first.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final location = _locationAddress ?? 'Location not available';
      final result = await _attendanceService.checkout(
        attendanceId,
        location: location,
      );

      if (mounted) {
        // Update UI from API response immediately, then refetch for confirmation
        final att = result['attendance'] ?? result['data'] ?? result;
        if (att is Map<String, dynamic> && att.isNotEmpty) {
          setState(() {
            _todayAttendance = Map<String, dynamic>.from(att);
            _isLoading = false;
          });
        }
        await _loadAttendanceData(force: true);

        // Show success message with working hours and break details
        final totalMinutes = result['totalWorkingMinutes'] ??
            result['data']?['totalWorkingMinutes'];
        final overtime = result['overtime'] ?? result['data']?['overtime'];
        final breakMins = result['breakMinutes'] ??
            result['data']?['breakMinutes'] ??
            _todayAttendance?['breakMinutes'] ??
            0;
        final breaks = result['breaks'] ??
            result['data']?['breaks'] ??
            _todayAttendance?['breaks'] ??
            [];
        final breakCountFinal = breaks is List ? breaks.length : 0;

        String message = '✅ Checked out successfully!';
        if (totalMinutes != null) {
          final hours = (totalMinutes / 60).floor();
          final minutes = totalMinutes % 60;
          message = '✅ Checked out!\nWorking time: ${hours}h ${minutes}m';

          if (breakCountFinal > 0) {
            final breakHours = (breakMins / 60).floor();
            final breakMinsRemainder = breakMins % 60;
            if (breakHours > 0) {
              message +=
                  '\nBreaks: $breakCountFinal (Total: ${breakHours}h ${breakMinsRemainder}m)';
            } else {
              message += '\nBreaks: $breakCountFinal (Total: ${breakMins}m)';
            }
          }

          if (overtime != null && overtime > 0) {
            final overtimeHours = (overtime / 60).floor();
            final overtimeMins = overtime % 60;
            if (overtimeHours > 0) {
              message += '\nOvertime: ${overtimeHours}h ${overtimeMins}m';
            } else {
              message += '\nOvertime: ${overtime}m';
            }
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Failed to check out',
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final isReadOnlyLocked =
        appProvider.isReadOnlyAfterCheckout || _isCheckedOut;
    final isTodayOffDay = appProvider.isTodayOffDay;
    final offDayMessage =
        appProvider.todayScheduleMessage ?? 'Today is your off day.';

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Attendance'),
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
          title: const Text('Attendance'),
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
                onPressed: () => _loadAttendanceData(force: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          // Socket connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              _socketService.isConnected ? Icons.wifi : Icons.wifi_off,
              size: 20,
              color: _socketService.isConnected
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
          ),
          IconButton(
            onPressed: () => _loadAttendanceData(force: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh attendance',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive padding based on screen size
          final padding = constraints.maxWidth > 600
              ? const EdgeInsets.symmetric(horizontal: 40, vertical: 20)
              : const EdgeInsets.all(20);

          return SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth > 600 ? 800 : double.infinity,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  if (isTodayOffDay) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.info.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_busy, color: AppColors.info),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              offDayMessage,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Today's Status Card with Break Controls
                  _buildAttendanceControlsCard(
                    isReadOnlyLocked: isReadOnlyLocked,
                    isTodayOffDay: isTodayOffDay,
                    offDayMessage: offDayMessage,
                  ),

                  const SizedBox(height: 24),

                  // Location Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.info.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: AppColors.info,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Work Location',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _locationAddress ?? 'Loading location...',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms),

                  const SizedBox(height: 24),

                  // Monthly Summary
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'Working Days',
                          '${_stats?['workingDays'] ?? 0}',
                          Icons.work,
                          AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryCard(
                          'Leave Taken',
                          '${_stats?['leaveDays'] ?? 0}',
                          Icons.beach_access,
                          AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSummaryCard(
                          'Overtime',
                          '${_formatHours(_stats?['totalOvertime'] ?? 0)}',
                          Icons.schedule,
                          AppColors.info,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 200.ms),

                  const SizedBox(height: 24),

                  // History (Past Attendance - excluding today)
                  Text(
                    'Recent Attendance',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),

                  if (_pastAttendance.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'No past attendance records',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _pastAttendance.length,
                      itemBuilder: (context, index) {
                        final record = _pastAttendance[index];
                        return _buildHistoryItem(record).animate().fadeIn(
                            delay: Duration(milliseconds: 300 + (index * 50)));
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttendanceControlsCard({
    required bool isReadOnlyLocked,
    required bool isTodayOffDay,
    required String offDayMessage,
  }) {
    final checkInTime = _checkInTime;
    final checkOutTime = _checkOutTime;
    final breakStartTime = _breakStartTime;
    final isOnBreak = _isOnBreak;
    final isCheckedIn = _isCheckedIn;
    final isCheckedOut = _isCheckedOut;
    final attendanceId = _todayAttendance?['_id']?.toString();

    final breakMinutes = (_todayAttendance?['breakDuration'] ??
        _todayAttendance?['breakMinutes'] ??
        0) as num;
    final totalWorkingMinutes = _todayAttendance?['totalWorkingMinutes'] ?? 0;
    // Get break list from attendance data (if available, otherwise use breakDuration)
    final breaksList = _todayAttendance?['breaks'] ?? [];
    final completedBreaks = breaksList is List
        ? breaksList
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList()
        : <Map<String, dynamic>>[];
    final breakCount = completedBreaks.length + (isOnBreak ? 1 : 0);

    // Calculate live working hours (real-time with seconds)
    // When on break, the working timer should PAUSE (freeze at the time break started)
    int currentWorkingSeconds = 0;
    if (isCheckedIn && !isCheckedOut) {
      if (checkInTime != null) {
        final now = DateTime.now();

        // Calculate total elapsed time since check-in
        final totalElapsedSeconds = now.difference(checkInTime).inSeconds;

        if (isOnBreak && breakStartTime != null) {
          // PAUSED: Working timer is frozen at the moment break started
          // Calculate working time from checkIn to breakStart, minus only completed breaks
          final workingTimeUntilBreak =
              breakStartTime.difference(checkInTime).inSeconds;

          // Get only completed breaks (exclude current break)
          // breakDuration doesn't include the current break, so use it directly
          int completedBreakSeconds = (breakMinutes * 60).toInt();

          currentWorkingSeconds =
              (workingTimeUntilBreak - completedBreakSeconds).toInt();
          if (currentWorkingSeconds < 0) currentWorkingSeconds = 0;
        } else {
          // ACTIVE: Working timer is running
          // Calculate total time minus completed break time
          // breakDuration contains all completed breaks
          int completedBreakSeconds = (breakMinutes * 60).toInt();

          // Calculate working seconds: total elapsed minus completed breaks
          currentWorkingSeconds =
              (totalElapsedSeconds - completedBreakSeconds).toInt();
          if (currentWorkingSeconds < 0) currentWorkingSeconds = 0;

          // Ensure we have at least some time if checked in (minimum 1 second)
          if (currentWorkingSeconds == 0 && totalElapsedSeconds > 0) {
            // If no breaks were deducted, use the full elapsed time
            currentWorkingSeconds = totalElapsedSeconds.toInt();
          }
        }
      } else {
        // Fallback: use backend calculated value if available
        if (totalWorkingMinutes > 0) {
          currentWorkingSeconds = (totalWorkingMinutes * 60).toInt();
        }
      }
    } else if (isCheckedOut) {
      currentWorkingSeconds = (totalWorkingMinutes * 60)
          .toInt(); // Convert to seconds for consistency
    }

    final workingHours = currentWorkingSeconds ~/ 3600;
    final workingMins = (currentWorkingSeconds % 3600) ~/ 60;
    final workingSecs = currentWorkingSeconds % 60;

    // Calculate live break timer (real-time with seconds)
    // Shows active break time when on break, or total break time when not on break
    int currentBreakTimerSeconds = 0;
    if (isOnBreak && breakStartTime != null) {
      // ACTIVE BREAK: Show live timer counting up from break start (current break only)
      final now = DateTime.now();
      final currentBreakDuration = now.difference(breakStartTime).inSeconds;
      // Show current active break time + previous completed breaks
      currentBreakTimerSeconds =
          (currentBreakDuration + (breakMinutes * 60)).toInt();
    } else if (breakMinutes > 0) {
      // NO ACTIVE BREAK: Show total accumulated break time
      currentBreakTimerSeconds =
          (breakMinutes * 60).toInt(); // Convert to seconds
    }
    final breakTimerHours = currentBreakTimerSeconds ~/ 3600;
    final breakTimerMins = (currentBreakTimerSeconds % 3600) ~/ 60;
    final breakTimerSecs = currentBreakTimerSeconds % 60;

    // Status text and color
    String statusText = 'Not Checked In';
    Color statusColor = AppColors.error;
    IconData statusIcon = Icons.logout;

    if (isCheckedIn && !isCheckedOut) {
      final checkedInAt =
          checkInTime != null ? _formatTime(checkInTime) : 'Now';
      if (isOnBreak) {
        statusText = 'Checked In at $checkedInAt';
        statusColor = AppColors.warning;
        statusIcon = Icons.coffee;
      } else {
        statusText = 'Checked In at $checkedInAt';
        statusColor = AppColors.success;
        statusIcon = Icons.work;
      }
    } else if (isCheckedOut) {
      statusText = checkOutTime != null
          ? 'Checked Out at ${_formatTime(checkOutTime)}'
          : 'Checked Out';
      statusColor = AppColors.info;
      statusIcon = Icons.check_circle;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.warmGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date and Status
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, d MMMM').format(DateTime.now()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  statusIcon,
                  color: Colors.white,
                  size: 35,
                ),
              ),
            ],
          ),

          // Check-in/Check-out times (Real-time)
          if (checkInTime != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.login,
                    color: Colors.white.withValues(alpha: 0.8), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Checked In: ${_formatTime(checkInTime)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                      if (isCheckedIn && !isCheckedOut) ...[
                        const SizedBox(height: 2),
                        Text(
                          isOnBreak
                              ? 'On Break'
                              : 'Current Time: ${_formatTime(DateTime.now())}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (checkOutTime != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.logout,
                    color: Colors.white.withValues(alpha: 0.8), size: 16),
                const SizedBox(width: 8),
                Text(
                  'Checked Out: ${_formatTime(checkOutTime)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
          if (isOnBreak && breakStartTime != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.coffee,
                    color: Colors.white.withValues(alpha: 0.8), size: 16),
                const SizedBox(width: 8),
                Text(
                  'Break Started: ${_formatTime(breakStartTime)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // Working Hours and Break Timer (Real-time)
          Row(
            children: [
              Expanded(
                child: _buildInfoChip(
                  isOnBreak ? 'Working Hours (Paused)' : 'Working Hours',
                  isCheckedIn && !isCheckedOut
                      ? '${workingHours.toString().padLeft(2, '0')}h ${workingMins.toString().padLeft(2, '0')}m ${workingSecs.toString().padLeft(2, '0')}s'
                      : '${workingHours.toString().padLeft(2, '0')}h ${workingMins.toString().padLeft(2, '0')}m',
                  isOnBreak ? Icons.pause_circle_outline : Icons.work,
                  isOnBreak
                      ? Colors.white.withValues(alpha: 0.7)
                      : Colors.white,
                ),
              ),
              if (isOnBreak || breakMinutes > 0) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoChip(
                    isOnBreak ? 'Break Time (Active)' : 'Total Break Time',
                    isOnBreak
                        ? '${breakTimerHours.toString().padLeft(2, '0')}h ${breakTimerMins.toString().padLeft(2, '0')}m ${breakTimerSecs.toString().padLeft(2, '0')}s'
                        : '${breakTimerHours.toString().padLeft(2, '0')}h ${breakTimerMins.toString().padLeft(2, '0')}m',
                    Icons.coffee,
                    isOnBreak ? Colors.orange.shade200 : Colors.white,
                  ),
                ),
              ],
            ],
          ),

          // Break Count and Details
          if (breakCount > 0 || isOnBreak) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's Breaks ($breakCount)",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (completedBreaks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...List.generate(completedBreaks.length, (index) {
                      final breakEntry = completedBreaks[index];
                      final start = breakEntry['breakStart']?.toString();
                      final end = breakEntry['breakEnd']?.toString();
                      final durationMinutes =
                          (breakEntry['durationMinutes'] ?? 0) as num;
                      DateTime? startDate;
                      DateTime? endDate;
                      try {
                        if (start != null && start.isNotEmpty) {
                          startDate = DateTime.parse(start).toLocal();
                        }
                        if (end != null && end.isNotEmpty) {
                          endDate = DateTime.parse(end).toLocal();
                        }
                      } catch (_) {}

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Break ${index + 1}  ${startDate != null ? _formatTime(startDate) : "--"} - ${endDate != null ? _formatTime(endDate) : "--"}  Duration: ${durationMinutes.toInt()} min',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                          ),
                        ),
                      );
                    }),
                  ],
                  if (isOnBreak && breakStartTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Break $breakCount  ${_formatTime(breakStartTime)} - Running  Duration: ${breakTimerMins} min',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Action Buttons
          if (!isCheckedIn) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isProcessing || isReadOnlyLocked || isTodayOffDay)
                    ? null
                    : _handleCheckIn,
                icon: const Icon(Icons.login, size: 18),
                label: Text(isTodayOffDay ? offDayMessage : 'Check In'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ] else if (!isCheckedOut) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                if (!isOnBreak)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ||
                              attendanceId == null ||
                              isReadOnlyLocked
                          ? null
                          : _handleStartBreak,
                      icon: const Icon(Icons.coffee, size: 18),
                      label: const Text('Start Break'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ||
                              attendanceId == null ||
                              isReadOnlyLocked
                          ? null
                          : _handleEndBreak,
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
                    onPressed: _isProcessing ||
                            attendanceId == null ||
                            isOnBreak ||
                            isReadOnlyLocked
                        ? null
                        : () => _showCheckoutConfirmation(),
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
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }

  Widget _buildInfoChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatHours(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
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
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
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

  Widget _buildHistoryItem(Map<String, dynamic> record) {
    final date = record['date'] != null
        ? DateTime.parse(record['date'])
        : DateTime.now();
    final checkInTime = record['checkIn']?['time'];
    final checkOutTime = record['checkOut']?['time'];
    final status = record['status'] ?? 'present';
    final totalWorkingMinutes =
        record['totalWorkingMinutes'] ?? record['workingHours'] ?? 0;

    // Use global attendance colors
    final statusColor = AttendanceColors.getStatusColor(status);

    String checkInStr = '-';
    String checkOutStr = '-';
    String hoursStr = '-';

    if (checkInTime != null) {
      try {
        checkInStr = _formatTime(DateTime.parse(checkInTime));
      } catch (e) {
        checkInStr = '-';
      }
    }

    if (checkOutTime != null) {
      try {
        checkOutStr = _formatTime(DateTime.parse(checkOutTime));
      } catch (e) {
        checkOutStr = '-';
      }
    }

    if (totalWorkingMinutes > 0) {
      hoursStr = _formatHours(totalWorkingMinutes);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('dd').format(date),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(date),
                  style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE').format(date),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: _buildTimeChip('In: $checkInStr'),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: _buildTimeChip('Out: $checkOutStr'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hoursStr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: AppColors.primary,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  void _showCheckoutConfirmation() {
    final isOnBreak = _isOnBreak;

    if (isOnBreak) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '⚠️ Cannot checkout while on break. Please resume work first.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Check Out'),
        content: Text(
          'You will be checked out at ${_formatTime(DateTime.now())}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isProcessing
                ? null
                : () {
                    Navigator.pop(context);
                    _handleCheckOut();
                  },
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Check Out'),
          ),
        ],
      ),
    );
  }
}
