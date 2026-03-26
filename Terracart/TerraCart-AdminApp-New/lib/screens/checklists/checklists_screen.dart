import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_provider.dart';
import '../../services/task_service.dart';
import '../../services/socket_service.dart';
import '../../models/task_model.dart';
import '../../core/exceptions/api_exception.dart';

class ChecklistsScreen extends StatefulWidget {
  /// When false (default), no back button is shown - use when screen is a top-level tab.
  /// When true, show back button - use when screen is pushed onto the navigation stack.
  final bool showBackButton;

  const ChecklistsScreen({super.key, this.showBackButton = false});

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  final TaskService _taskService = TaskService();
  final SocketService _socketService = SocketService();
  List<TaskModel> _tasks = [];
  bool _showCompletedTasks = true;
  bool _isLoading = true;
  String? _errorMessage;

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
    _socketService.on('task:created', (_) => _loadTasks());
    _socketService.on('task:completed', (_) => _loadTasks());
  }

  void _removeSocketListeners() {
    _socketService.off('task:created');
    _socketService.off('task:completed');
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tasks = await _taskService.getTodayTasks();
      if (mounted) {
        setState(() {
          _tasks = tasks;
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

  Future<void> _toggleTask(TaskModel task) async {
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

    if (task.status == 'completed' || task.status == 'complete') return;

    try {
      await _taskService.completeTask(task.id);
      await _loadTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Task completed!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'Failed to update task',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _createTask() async {
    if (!mounted) return;
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

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _CreateTaskDialog(),
    );

    if (result != null && mounted) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        await _taskService.createTask(result);
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          await _loadTasks();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Task created!'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is ApiException ? e.message : 'Failed to create task',
              ),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  int get _completedCount => _tasks
      .where((t) => t.status == 'completed' || t.status == 'complete')
      .length;
  int get _totalCount => _tasks.length;
  double get _progress => _totalCount > 0 ? _completedCount / _totalCount : 0;
  List<TaskModel> get _visibleTasks {
    if (_showCompletedTasks) return _tasks;
    return _tasks
        .where((t) => t.status != 'completed' && t.status != 'complete')
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final isVoiceEnabled = appProvider.voiceCommands;
    final isReadOnlyLocked = appProvider.isReadOnlyAfterCheckout;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Daily Checklists'),
          automaticallyImplyLeading: widget.showBackButton,
          leading: widget.showBackButton
              ? IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_rounded),
                )
              : null,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Daily Checklists'),
          automaticallyImplyLeading: widget.showBackButton,
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
                onPressed: _loadTasks,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Checklists'),
        automaticallyImplyLeading: widget.showBackButton,
        leading: widget.showBackButton
            ? IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_rounded),
              )
            : null,
        actions: [
          if (isVoiceEnabled)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic, size: 16, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'Voice',
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
      body: RefreshIndicator(
        onRefresh: _loadTasks,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
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
              // Progress Card
              Container(
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
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Today's Progress",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$_completedCount of $_totalCount',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'tasks completed',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Circular Progress Indicator - Aligned to middle right
                        SizedBox(
                          width: 110,
                          height: 110,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Background circle
                              SizedBox(
                                width: 110,
                                height: 110,
                                child: CircularProgressIndicator(
                                  value: 1.0,
                                  strokeWidth: 12,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.2),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.transparent),
                                ),
                              ),
                              // Progress circle
                              SizedBox(
                                width: 110,
                                height: 110,
                                child: CircularProgressIndicator(
                                  value: _progress,
                                  strokeWidth: 12,
                                  backgroundColor: Colors.transparent,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                  strokeCap: StrokeCap.round,
                                ),
                              ),
                              // Percentage text centered inside
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${(_progress * 100).toInt()}%',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      height: 1.0,
                                    ),
                                  ),
                                  if (_totalCount > 0)
                                    Text(
                                      'Done',
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.1),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loadTasks,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showCompletedTasks = !_showCompletedTasks;
                        });
                      },
                      icon: Icon(
                        _showCompletedTasks
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                      ),
                      label: Text(
                        _showCompletedTasks ? 'Hide Done' : 'Show All',
                      ),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 16),

              // Task List
              if (_visibleTasks.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.task_alt,
                          size: 64,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _tasks.isEmpty
                              ? 'No tasks for today'
                              : 'No pending tasks',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _visibleTasks.length,
                  itemBuilder: (context, index) {
                    final task = _visibleTasks[index];
                    return _buildTaskItem(
                      task,
                      isReadOnlyLocked: isReadOnlyLocked,
                    ).animate().fadeIn(
                        delay: Duration(milliseconds: 150 + (index * 50)));
                  },
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'checklists_fab',
        onPressed: isReadOnlyLocked ? null : _createTask,
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
    );
  }

  // Helper function to format category name for display
  String _formatCategoryName(String category) {
    switch (category.toLowerCase()) {
      case 'cleaning':
        return 'Cleaning';
      case 'maintenance':
        return 'Maintenance';
      case 'inventory':
        return 'Inventory';
      case 'service':
        return 'Service';
      case 'food_preparation':
        return 'Food Prep';
      case 'safety':
        return 'Safety';
      case 'other':
        return 'Other';
      default:
        return category.toUpperCase();
    }
  }

  Widget _buildTaskItem(
    TaskModel task, {
    required bool isReadOnlyLocked,
  }) {
    final isCompleted = task.status == 'completed' || task.status == 'complete';

    Color priorityColor;
    switch (task.priority.toLowerCase()) {
      case 'urgent':
        priorityColor = AppColors.error;
        break;
      case 'high':
        priorityColor = Colors.orange;
        break;
      case 'medium':
        priorityColor = AppColors.warning;
        break;
      case 'low':
        priorityColor = AppColors.textSecondary;
        break;
      default:
        priorityColor = AppColors.info;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: isCompleted
            ? null
            : Border.all(
                color: priorityColor.withValues(alpha: 0.3),
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: GestureDetector(
          onTap: isReadOnlyLocked ? null : () => _toggleTask(task),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppColors.success
                  : priorityColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: isCompleted
                  ? null
                  : Border.all(color: priorityColor, width: 2),
            ),
            child: Icon(
              isCompleted ? Icons.check : Icons.circle_outlined,
              color: isCompleted ? Colors.white : priorityColor,
              size: 24,
            ),
          ),
        ),
        title: Text(
          task.title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                decoration: isCompleted ? TextDecoration.lineThrough : null,
                color: isCompleted ? AppColors.textSecondary : null,
              ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatCategoryName(task.category),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.priority.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: priorityColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(
            Icons.more_vert,
            color: AppColors.textSecondary,
          ),
          onSelected: (value) {
            if (!isReadOnlyLocked && value == 'complete' && !isCompleted) {
              _toggleTask(task);
            }
          },
          itemBuilder: (context) => [
            if (!isCompleted)
              const PopupMenuItem(
                value: 'complete',
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: AppColors.success, size: 20),
                    SizedBox(width: 8),
                    Text('Mark as Completed'),
                  ],
                ),
              ),
            if (isCompleted)
              PopupMenuItem(
                value: 'info',
                enabled: false,
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: AppColors.success, size: 20),
                    SizedBox(width: 8),
                    Text('Task Completed',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CreateTaskDialog extends StatefulWidget {
  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = 'other';
  String _priority = 'medium';
  List<String> _selectedFrequency = []; // Days of week

  final List<Map<String, dynamic>> _daysOfWeek = [
    {'day': 'monday', 'label': 'Mon', 'fullLabel': 'Monday'},
    {'day': 'tuesday', 'label': 'Tue', 'fullLabel': 'Tuesday'},
    {'day': 'wednesday', 'label': 'Wed', 'fullLabel': 'Wednesday'},
    {'day': 'thursday', 'label': 'Thu', 'fullLabel': 'Thursday'},
    {'day': 'friday', 'label': 'Fri', 'fullLabel': 'Friday'},
    {'day': 'saturday', 'label': 'Sat', 'fullLabel': 'Saturday'},
    {'day': 'sunday', 'label': 'Sun', 'fullLabel': 'Sunday'},
  ];

  void _toggleFrequency(String day) {
    setState(() {
      if (_selectedFrequency.contains(day)) {
        _selectedFrequency.remove(day);
      } else {
        _selectedFrequency.add(day);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Create New Task',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title *',
                    border: OutlineInputBorder(),
                    hintText: 'Enter task title',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a task title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                    hintText: 'Enter task description',
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                // Frequency (Days Selection)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.repeat,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Frequency (Days)',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select days for recurring tasks (leave empty for one-time task)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 16),
                      // Circular day selection - in one line
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: _daysOfWeek.map((dayInfo) {
                          final isSelected =
                              _selectedFrequency.contains(dayInfo['day']);
                          return Flexible(
                            child: GestureDetector(
                              onTap: () =>
                                  _toggleFrequency(dayInfo['day'] as String),
                              child: Container(
                                width: 36,
                                height: 36,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.primary
                                          .withValues(alpha: 0.1),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.primary
                                            .withValues(alpha: 0.3),
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.3),
                                            blurRadius: 6,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      dayInfo['label'] as String,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.primary,
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(Icons.check,
                                          size: 11, color: Colors.white),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_selectedFrequency.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Task will recur on: ${_selectedFrequency.map((d) => _daysOfWeek.firstWhere((dw) => dw['day'] == d)['fullLabel']).join(', ')}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    {'value': 'cleaning', 'label': 'Cleaning'},
                    {'value': 'maintenance', 'label': 'Maintenance'},
                    {'value': 'inventory', 'label': 'Inventory'},
                    {'value': 'service', 'label': 'Service'},
                    {'value': 'food_preparation', 'label': 'Food Preparation'},
                    {'value': 'safety', 'label': 'Safety'},
                    {'value': 'other', 'label': 'Other'},
                  ]
                      .map((cat) => DropdownMenuItem(
                            value: cat['value'] as String,
                            child: Text(cat['label'] as String),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _priority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    {'value': 'low', 'label': 'Low'},
                    {'value': 'medium', 'label': 'Medium'},
                    {'value': 'high', 'label': 'High'},
                    {'value': 'urgent', 'label': 'Urgent'},
                  ]
                      .map((pri) => DropdownMenuItem(
                            value: pri['value'] as String,
                            child: Text(pri['label'] as String),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _priority = value);
                  },
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            // Use current date (backend will handle IST conversion)
                            final now = DateTime.now();
                            final Map<String, dynamic> result = {
                              'title': _titleController.text.trim(),
                              'description': _descriptionController.text.trim(),
                              'category': _category,
                              'priority': _priority,
                              'dueDate': now.toIso8601String(),
                            };
                            // Add frequency if days are selected
                            if (_selectedFrequency.isNotEmpty) {
                              result['frequency'] = _selectedFrequency;
                            }
                            Navigator.pop(context, result);
                          }
                        },
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
