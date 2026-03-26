import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_provider.dart';
import '../../services/task_service.dart';
import '../../services/socket_service.dart';
import '../../models/task_model.dart';
import '../../core/exceptions/api_exception.dart';
import 'create_edit_task_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final TaskService _taskService = TaskService();
  final SocketService _socketService = SocketService();

  List<TaskModel> _tasks = [];
  List<TaskModel> _filteredTasks = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'all'; // all, pending, in_progress, completed

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _removeSocketListeners();
    super.dispose();
  }

  void _setupSocketListeners() {
    // Use debouncing for faster updates
    _socketService.on('task:created', (_) {
      if (mounted) _loadTasks(showLoading: false);
    }, debounce: true, delay: const Duration(milliseconds: 300));

    _socketService.on('task:updated', (_) {
      if (mounted) _loadTasks(showLoading: false);
    }, debounce: true, delay: const Duration(milliseconds: 300));

    _socketService.on('task:completed', (_) {
      if (mounted) _loadTasks(showLoading: false);
    }, debounce: true, delay: const Duration(milliseconds: 300));

    _socketService.on('task:deleted', (_) {
      if (mounted) _loadTasks(showLoading: false);
    }, debounce: true, delay: const Duration(milliseconds: 300));

    // Listen for schedule updates to refresh tasks
    _socketService.on('schedule:updated', (_) {
      if (mounted) _loadTasks(showLoading: false);
    }, debounce: true, delay: const Duration(milliseconds: 500));
  }

  void _removeSocketListeners() {
    _socketService.off('task:created');
    _socketService.off('task:updated');
    _socketService.off('task:completed');
    _socketService.off('task:deleted');
    _socketService.off('schedule:updated');
  }

  Future<void> _loadTasks({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final tasks = await _taskService.getTodayTasks();
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e is ApiException ? e.message : 'Failed to load tasks';
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilter() {
    switch (_selectedFilter) {
      case 'pending':
        _filteredTasks = _tasks.where((t) => t.status == 'pending').toList();
        break;
      case 'in_progress':
        _filteredTasks =
            _tasks.where((t) => t.status == 'in_progress').toList();
        break;
      case 'completed':
        _filteredTasks = _tasks.where((t) => t.status == 'completed').toList();
        break;
      case 'late':
        _filteredTasks = _tasks.where((t) => t.status == 'late').toList();
        break;
      default:
        _filteredTasks = List.from(_tasks);
    }
    // Sort by priority and due date
    _filteredTasks.sort((a, b) {
      final priorityOrder = {'urgent': 0, 'high': 1, 'medium': 2, 'low': 3};
      final priorityDiff =
          (priorityOrder[a.priority] ?? 2) - (priorityOrder[b.priority] ?? 2);
      if (priorityDiff != 0) return priorityDiff;
      return a.dueDate.compareTo(b.dueDate);
    });
  }

  // Calculate completion percentage
  double _getCompletionPercentage() {
    if (_tasks.isEmpty) return 0.0;
    final completed = _tasks.where((t) => t.status == 'completed').length;
    return (completed / _tasks.length) * 100;
  }

  // Get stats for each status
  Map<String, int> _getStatusStats() {
    return {
      'pending': _tasks.where((t) => t.status == 'pending').length,
      'in_progress': _tasks.where((t) => t.status == 'in_progress').length,
      'completed': _tasks.where((t) => t.status == 'completed').length,
      'late': _tasks.where((t) => t.status == 'late').length,
      'half_day': _tasks.where((t) => t.status == 'half_day').length,
      'total': _tasks.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final isReadOnlyLocked = appProvider.isReadOnlyAfterCheckout;
    final stats = _getStatusStats();
    final completionPercentage = _getCompletionPercentage();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: isReadOnlyLocked
                ? null
                : () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateEditTaskScreen(),
                      ),
                    );
                    if (result == true && mounted) {
                      _loadTasks();
                    }
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          if (isReadOnlyLocked)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
          // Progress Card with Circular Progress
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Circular Progress Indicator
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Background circle
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: 1.0,
                          strokeWidth: 10,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      // Progress circle
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: completionPercentage / 100,
                          strokeWidth: 10,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                      // Percentage text inside
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${completionPercentage.toInt()}%',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Complete',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                // Stats
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatRow('Total Tasks', stats['total']!, Icons.list),
                      const SizedBox(height: 8),
                      _buildStatRow(
                        'Pending',
                        stats['pending']!,
                        Icons.pending,
                        color: AppColors.warning,
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow(
                        'In Progress',
                        stats['in_progress']!,
                        Icons.hourglass_empty,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow(
                        'Completed',
                        stats['completed']!,
                        Icons.check_circle,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Filter chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All', Icons.list, stats['total']!),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'pending',
                    'Pending',
                    Icons.pending,
                    stats['pending']!,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'in_progress',
                    'In Progress',
                    Icons.hourglass_empty,
                    stats['in_progress']!,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'completed',
                    'Completed',
                    Icons.check_circle,
                    stats['completed']!,
                  ),
                  if (stats['late']! > 0) ...[
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'late',
                      'Late',
                      Icons.schedule,
                      stats['late']!,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Tasks list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 64, color: AppColors.error),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () => _loadTasks(),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredTasks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.task_alt,
                                    size: 64, color: AppColors.textSecondary),
                                const SizedBox(height: 16),
                                Text(
                                  'No tasks found',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap + to create a new task',
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
                            onRefresh: () => _loadTasks(),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredTasks.length,
                              itemBuilder: (context, index) {
                                return _buildTaskCard(
                                  _filteredTasks[index],
                                  isReadOnlyLocked: isReadOnlyLocked,
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int count, IconData icon, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? Colors.white),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 14,
          ),
        ),
        Text(
          count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(
      String value, String label, IconData icon, int count) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white
                  : AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.primary : Colors.white,
              ),
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
          _applyFilter();
        });
      },
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      checkmarkColor: AppColors.primary,
    );
  }

  Widget _buildTaskCard(
    TaskModel task, {
    required bool isReadOnlyLocked,
  }) {
    final priorityColors = {
      'urgent': AppColors.error,
      'high': Colors.orange,
      'medium': AppColors.warning,
      'low': AppColors.textSecondary,
    };

    final statusColors = {
      'pending': AppColors.warning,
      'in_progress': AppColors.primary,
      'completed': AppColors.success,
      'cancelled': AppColors.textSecondary,
      'late': AppColors.error,
      'half_day': Colors.orange,
    };

    final statusIcons = {
      'pending': Icons.pending,
      'in_progress': Icons.hourglass_bottom,
      'completed': Icons.check_circle,
      'cancelled': Icons.cancel,
      'late': Icons.schedule,
      'half_day': Icons.access_time,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: task.isOverdue
            ? BorderSide(color: AppColors.error, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: isReadOnlyLocked
            ? null
            : () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateEditTaskScreen(task: task),
                  ),
                );
                if (result == true && mounted) {
                  _loadTasks();
                }
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Status Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColors[task.status]?.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      statusIcons[task.status] ?? Icons.task,
                      color: statusColors[task.status],
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        if (task.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            task.description,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          priorityColors[task.priority]?.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      task.priority.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: priorityColors[task.priority],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Status Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColors[task.status]?.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          statusIcons[task.status] ?? Icons.task,
                          size: 12,
                          color: statusColors[task.status],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task.status.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColors[task.status],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Category Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.category,
                            size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          task.category.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Assigned To
                  if (task.assignedToName != null &&
                      task.assignedToName!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person,
                              size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            task.assignedToName!,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Recurring Badge
                  if (task.frequency != null && task.frequency!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.repeat,
                              size: 12, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Recurring',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(task.dueDate),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: task.isOverdue
                              ? AppColors.error
                              : AppColors.textSecondary,
                          fontWeight: task.isOverdue
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                  ),
                  if (task.isOverdue) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'OVERDUE',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn().slideX();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDate = DateTime(date.year, date.month, date.day);

    if (taskDate == today) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (taskDate == today.add(const Duration(days: 1))) {
      return 'Tomorrow ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (taskDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }
}
