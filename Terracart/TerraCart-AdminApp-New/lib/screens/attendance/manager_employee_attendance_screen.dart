import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/attendance_colors.dart';
import '../../core/services/cache_service.dart';
import '../../providers/app_provider.dart';
import '../../services/employee_service.dart';
import '../../services/attendance_service.dart';
import '../../services/socket_service.dart';
import '../../core/exceptions/api_exception.dart';
import 'employee_attendance_calendar_screen.dart';

class ManagerEmployeeAttendanceScreen extends StatefulWidget {
  /// When false, no back button is shown (e.g. when used as a tab)
  final bool showBackButton;

  const ManagerEmployeeAttendanceScreen(
      {super.key, this.showBackButton = true});

  @override
  State<ManagerEmployeeAttendanceScreen> createState() =>
      _ManagerEmployeeAttendanceScreenState();
}

class _ManagerEmployeeAttendanceScreenState
    extends State<ManagerEmployeeAttendanceScreen> {
  final EmployeeService _employeeService = EmployeeService();
  final AttendanceService _attendanceService = AttendanceService();
  final SocketService _socketService = SocketService();

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmployees = [];
  Map<String, List<Map<String, dynamic>>> _todayAttendanceMap = {};
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedRoleFilter = 'All';

  final List<String> _roleFilters = [
    'All',
    'manager',
    'captain',
    'waiter',
    'cook'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _removeSocketListeners();
    super.dispose();
  }

  void _setupSocketListeners() {
    _socketService.on('attendance:checked_in', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadData();
      }
    }, debounce: true, delay: const Duration(milliseconds: 500));
    _socketService.on('attendance:checked_out', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadData();
      }
    }, debounce: true, delay: const Duration(milliseconds: 500));
    _socketService.on('attendance:updated', (_) {
      if (mounted) {
        CacheService().remove(CacheService.todayAttendance);
        _loadData();
      }
    }, debounce: true, delay: const Duration(milliseconds: 500));
  }

  void _removeSocketListeners() {
    _socketService.off('attendance:checked_in');
    _socketService.off('attendance:checked_out');
    _socketService.off('attendance:updated');
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final [employees, todayAttendance] = await Future.wait([
        _employeeService
            .getEmployees()
            .catchError((e) => <Map<String, dynamic>>[]),
        _attendanceService
            .getTodayAttendance()
            .catchError((e) => <Map<String, dynamic>>[]),
      ]);

      if (mounted) {
        setState(() {
          // Remove duplicate employees based on their _id
          final seenIds = <String>{};
          _employees = employees.where((emp) {
            final empId = emp['_id']?.toString();
            // Skip duplicates and malformed entries.
            if (empId == null || seenIds.contains(empId)) {
              return false;
            }

            seenIds.add(empId);
            return true;
          }).toList();

          // Create a map of employeeId -> attendance records
          final attendanceList = todayAttendance;
          _todayAttendanceMap = {};
          for (var att in attendanceList) {
            final employeeId = att['employeeId'];
            if (employeeId != null) {
              final empId = employeeId is Map
                  ? employeeId['_id']?.toString()
                  : employeeId.toString();
              if (empId != null) {
                if (!_todayAttendanceMap.containsKey(empId)) {
                  _todayAttendanceMap[empId] = [];
                }
                _todayAttendanceMap[empId]!.add(att);
              }
            }
          }

          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ApiException ? e.message : 'Failed to load data';
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilter() {
    if (_selectedRoleFilter == 'All') {
      _filteredEmployees = List.from(_employees);
    } else {
      _filteredEmployees = _employees
          .where((emp) =>
              emp['employeeRole']?.toString().toLowerCase() ==
              _selectedRoleFilter.toLowerCase())
          .toList();
    }
  }

  void _onRoleFilterChanged(String? role) {
    if (role != null) {
      setState(() {
        _selectedRoleFilter = role;
        _applyFilter();
      });
    }
  }

  Map<String, dynamic>? _getTodayAttendance(String employeeId) {
    final attendanceList = _todayAttendanceMap[employeeId];
    if (attendanceList != null && attendanceList.isNotEmpty) {
      return attendanceList.first;
    }
    return null;
  }

  String _getStatusText(Map<String, dynamic>? attendance) {
    if (attendance == null) return 'Not Checked In';
    final checkIn = attendance['checkIn']?['time'];
    final checkOut = attendance['checkOut']?['time'];
    final status = attendance['status'] ?? 'present';

    if (checkOut != null) return 'Checked Out';
    if (attendance['isOnBreak'] == true) return 'On Break';
    if (checkIn != null) return 'Checked In';
    return status.toString().toUpperCase();
  }

  bool _hasCheckedIn(Map<String, dynamic>? attendance) {
    if (attendance == null) return false;
    final checkIn = attendance['checkIn']?['time'];
    final status = attendance['attendanceStatus']?.toString().toLowerCase();
    return checkIn != null || status == 'checked_in' || status == 'on_break';
  }

  bool _isCheckedOut(Map<String, dynamic>? attendance) {
    if (attendance == null) return false;
    final checkOut = attendance['checkOut']?['time'];
    final status = attendance['attendanceStatus']?.toString().toLowerCase();
    return checkOut != null ||
        attendance['isCheckedOut'] == true ||
        status == 'checked_out';
  }

  bool _isOnBreak(Map<String, dynamic>? attendance) {
    if (attendance == null) return false;
    final status = attendance['attendanceStatus']?.toString().toLowerCase();
    return attendance['isOnBreak'] == true || status == 'on_break';
  }

  Color _getStatusColor(Map<String, dynamic>? attendance) {
    // Use global attendance colors
    return AttendanceColors.getColorFromRecord(attendance);
  }

  void _showEditAttendanceDialog(BuildContext context,
      Map<String, dynamic> attendance, String employeeName) {
    final notesController = TextEditingController(
      text: attendance['checkIn']?['notes'] ??
          attendance['checkOut']?['notes'] ??
          '',
    );
    final attId = attendance['_id']?.toString() ?? attendance['id']?.toString();
    if (attId == null) return;
    final validStatuses = [
      'present',
      'absent',
      'late',
      'half_day',
      'on_leave',
      'sick',
      'completed'
    ];
    final initialStatus = attendance['status']?.toString() ?? 'present';
    String selectedStatus =
        validStatuses.contains(initialStatus) ? initialStatus : 'present';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Edit: $employeeName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: validStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedStatus = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (c) => AlertDialog(
                          title: const Text('Delete Record?'),
                          content: const Text(
                            'This will remove this attendance record. This action cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: AppColors.error),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        try {
                          await _attendanceService.deleteAttendance(attId);
                          if (mounted) {
                            Navigator.pop(ctx);
                            CacheService().remove(CacheService.todayAttendance);
                            _loadData();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Record deleted'),
                                  backgroundColor: AppColors.success),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e is ApiException
                                    ? e.message
                                    : 'Delete failed'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete Record'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _attendanceService.updateAttendanceStatus(
                      attId,
                      status: selectedStatus,
                      notes: notesController.text.trim().isEmpty
                          ? null
                          : notesController.text.trim(),
                    );
                    if (mounted) {
                      Navigator.pop(ctx);
                      CacheService().remove(CacheService.todayAttendance);
                      _loadData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Attendance updated'),
                            backgroundColor: AppColors.success),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              e is ApiException ? e.message : 'Update failed'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showManualCheckInDialog() {
    final notCheckedIn = _filteredEmployees
        .where((e) => _getTodayAttendance(e['_id']?.toString() ?? '') == null)
        .toList();
    if (notCheckedIn.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All employees have already checked in today'),
          backgroundColor: AppColors.info,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual Check-in'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: notCheckedIn
                .map((emp) => ListTile(
                      title: Text(emp['name'] ?? 'Unknown'),
                      subtitle: Text(
                          emp['employeeRole']?.toString().toUpperCase() ?? ''),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final empId = emp['_id']?.toString();
                        if (empId == null) return;
                        try {
                          await _attendanceService.checkIn(employeeId: empId);
                          if (mounted) {
                            CacheService().remove(CacheService.todayAttendance);
                            _loadData();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '${emp['name'] ?? 'Employee'} checked in'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e is ApiException
                                    ? e.message
                                    : 'Check-in failed'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showManualCheckOutDialog() {
    final checkedInEmployees = _filteredEmployees.where((e) {
      final attendance = _getTodayAttendance(e['_id']?.toString() ?? '');
      return _hasCheckedIn(attendance) &&
          !_isCheckedOut(attendance) &&
          !_isOnBreak(attendance);
    }).toList();

    if (checkedInEmployees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No checked-in employees available for checkout'),
          backgroundColor: AppColors.info,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual Check-out'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: checkedInEmployees
                .map((emp) => ListTile(
                      title: Text(emp['name'] ?? 'Unknown'),
                      subtitle: Text(
                          emp['employeeRole']?.toString().toUpperCase() ?? ''),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final empId = emp['_id']?.toString();
                        if (empId == null) return;
                        try {
                          await _attendanceService.checkOut(employeeId: empId);
                          if (mounted) {
                            CacheService().remove(CacheService.todayAttendance);
                            _loadData();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '${emp['name'] ?? 'Employee'} checked out'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e is ApiException
                                    ? e.message
                                    : 'Check-out failed'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _openEmployeeCalendar(Map<String, dynamic> employee) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeAttendanceCalendarScreen(
          employee: employee,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Employee Attendance'),
          leading: widget.showBackButton
              ? IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_rounded),
                )
              : null,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Employee Attendance'),
          leading: widget.showBackButton
              ? IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_rounded),
                )
              : null,
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
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Attendance'),
        leading: widget.showBackButton
            ? IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_rounded),
              )
            : null,
        actions: [
          if (Provider.of<AppProvider>(context, listen: false).userRole ==
              'manager')
            IconButton(
              onPressed: _showManualCheckInDialog,
              icon: const Icon(Icons.person_add),
              tooltip: 'Manual Check-in',
            ),
          if (Provider.of<AppProvider>(context, listen: false).userRole ==
              'manager')
            IconButton(
              onPressed: _showManualCheckOutDialog,
              icon: const Icon(Icons.person_remove),
              tooltip: 'Manual Check-out',
            ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Role Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              children: [
                const Icon(Icons.filter_list, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(
                  'Filter by Role:',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedRoleFilter,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _roleFilters.map((role) {
                      return DropdownMenuItem<String>(
                        value: role,
                        child: Text(
                          role == 'All' ? 'All Roles' : role.toUpperCase(),
                          style: TextStyle(
                            fontWeight: _selectedRoleFilter == role
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _selectedRoleFilter == role
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: _onRoleFilterChanged,
                  ),
                ),
              ],
            ),
          ),

          // Employee List
          Expanded(
            child: _filteredEmployees.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No employees found',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                        if (_selectedRoleFilter != 'All')
                          Text(
                            'for role: ${_selectedRoleFilter.toUpperCase()}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                          ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredEmployees.length,
                      itemBuilder: (context, index) {
                        final employee = _filteredEmployees[index];
                        final employeeId = employee['_id']?.toString() ?? '';
                        final employeeName = employee['name'] ?? 'Unknown';
                        final employeeRole = employee['employeeRole'] ?? 'N/A';
                        final mobile = employee['mobile'] ?? '';
                        final todayAttendance = _getTodayAttendance(employeeId);
                        final statusText = _getStatusText(todayAttendance);
                        final statusColor = _getStatusColor(todayAttendance);

                        return GestureDetector(
                          onTap: () => _openEmployeeCalendar(employee),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.3),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Avatar
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      employeeName.isNotEmpty
                                          ? employeeName[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // Employee Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        employeeName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              employeeRole.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                          if (mobile.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Icon(
                                              Icons.phone,
                                              size: 14,
                                              color: AppColors.textSecondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                mobile,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: AppColors
                                                          .textSecondary,
                                                    ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: statusColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            statusText,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Edit (Manager only, when attendance exists)
                                if (Provider.of<AppProvider>(context,
                                                listen: false)
                                            .userRole ==
                                        'manager' &&
                                    todayAttendance != null) ...[
                                  IconButton(
                                    onPressed: () => _showEditAttendanceDialog(
                                        context, todayAttendance, employeeName),
                                    icon: const Icon(Icons.edit, size: 20),
                                    color: AppColors.primary,
                                  ),
                                ],
                                // Arrow Icon
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                          ).animate().fadeIn(
                              delay: Duration(milliseconds: index * 50)),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
