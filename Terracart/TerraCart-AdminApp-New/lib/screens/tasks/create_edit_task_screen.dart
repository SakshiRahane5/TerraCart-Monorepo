import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/task_service.dart';
import '../../services/employee_service.dart';
import '../../services/schedule_service.dart';
import '../../models/task_model.dart';
import '../../providers/app_provider.dart';
import '../../core/exceptions/api_exception.dart';

class CreateEditTaskScreen extends StatefulWidget {
  final TaskModel? task;

  const CreateEditTaskScreen({super.key, this.task});

  @override
  State<CreateEditTaskScreen> createState() => _CreateEditTaskScreenState();
}

class _CreateEditTaskScreenState extends State<CreateEditTaskScreen> {
  final TaskService _taskService = TaskService();
  final EmployeeService _employeeService = EmployeeService();
  final ScheduleService _scheduleService = ScheduleService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String _selectedPriority = 'medium';
  String _selectedCategory = 'cleaning';
  String? _selectedEmployeeId;
  DateTime _selectedDueDate = DateTime.now();
  List<String> _selectedFrequency = []; // Days of week
  bool _assignToSelf = false;

  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = false;
  bool _isLoadingEmployees = false;
  bool _isLoadingSchedule = false;
  String? _currentEmployeeId;
  Set<String> _disabledDays = {}; // Days that are off (not working)

  // More specific task categories
  final List<Map<String, dynamic>> _categories = [
    {
      'value': 'cleaning',
      'label': 'Cleaning',
      'icon': Icons.cleaning_services,
      'subcategories': [
        'Floor Cleaning',
        'Table Cleaning',
        'Kitchen Cleaning',
        'Bathroom Cleaning',
        'Equipment Cleaning',
        'Window Cleaning',
      ],
    },
    {
      'value': 'maintenance',
      'label': 'Maintenance',
      'icon': Icons.build,
      'subcategories': [
        'Equipment Repair',
        'Preventive Maintenance',
        'Safety Check',
        'Electrical',
        'Plumbing',
        'HVAC',
      ],
    },
    {
      'value': 'inventory',
      'label': 'Inventory',
      'icon': Icons.inventory_2,
      'subcategories': [
        'Stock Check',
        'Restocking',
        'Expiry Check',
        'Order Placement',
        'Receiving',
        'Waste Management',
      ],
    },
    {
      'value': 'service',
      'label': 'Service',
      'icon': Icons.room_service,
      'subcategories': [
        'Customer Service',
        'Table Setup',
        'Order Taking',
        'Food Delivery',
        'Payment Processing',
        'Complaint Handling',
      ],
    },
    {
      'value': 'food_preparation',
      'label': 'Food Preparation',
      'icon': Icons.restaurant,
      'subcategories': [
        'Cooking',
        'Prepping',
        'Quality Check',
        'Food Safety',
        'Recipe Follow-up',
        'Presentation',
      ],
    },
    {
      'value': 'safety',
      'label': 'Safety & Compliance',
      'icon': Icons.security,
      'subcategories': [
        'Safety Inspection',
        'Fire Safety',
        'Health Check',
        'Compliance Audit',
        'Training',
        'Documentation',
      ],
    },
    {
      'value': 'other',
      'label': 'Other',
      'icon': Icons.more_horiz,
      'subcategories': [
        'General Task',
        'Administrative',
        'Training',
        'Meeting',
        'Special Event',
        'Custom',
      ],
    },
  ];

  final List<Map<String, dynamic>> _daysOfWeek = [
    {'day': 'monday', 'label': 'Mon', 'fullLabel': 'Monday'},
    {'day': 'tuesday', 'label': 'Tue', 'fullLabel': 'Tuesday'},
    {'day': 'wednesday', 'label': 'Wed', 'fullLabel': 'Wednesday'},
    {'day': 'thursday', 'label': 'Thu', 'fullLabel': 'Thursday'},
    {'day': 'friday', 'label': 'Fri', 'fullLabel': 'Friday'},
    {'day': 'saturday', 'label': 'Sat', 'fullLabel': 'Saturday'},
    {'day': 'sunday', 'label': 'Sun', 'fullLabel': 'Sunday'},
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    // Get current user's employee ID for self-assignment
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.currentUser?.employeeId != null) {
      _currentEmployeeId = appProvider.currentUser!.employeeId;
    }

    if (widget.task != null) {
      _titleController.text = widget.task!.title;
      _descriptionController.text = widget.task!.description;
      _notesController.text = widget.task!.notes ?? '';
      _selectedPriority = widget.task!.priority;
      _selectedCategory = widget.task!.category;
      _selectedEmployeeId = widget.task!.assignedToId;
      _selectedDueDate = widget.task!.dueDate;
      _selectedFrequency = List.from(widget.task!.frequency ?? []);
      _assignToSelf = _selectedEmployeeId == _currentEmployeeId;
    } else {
      // Default due date: tomorrow
      _selectedDueDate = DateTime.now().add(const Duration(days: 1));
      // Default to self-assignment for new tasks
      if (_currentEmployeeId != null) {
        _assignToSelf = true;
        _selectedEmployeeId = _currentEmployeeId;
      }
    }
    await _loadEmployees();
    // Load schedule for the selected employee (for both new and existing tasks)
    if (_selectedEmployeeId != null) {
      await _loadEmployeeSchedule(_selectedEmployeeId!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoadingEmployees = true);
    try {
      final employees = await _employeeService.getEmployees();
      if (mounted) {
        setState(() {
          _employees = employees
              .map((e) => {
                    'id': e['_id']?.toString() ?? e['id']?.toString(),
                    'name': e['name'] ?? '',
                    'role': e['employeeRole'] ?? '',
                  })
              .toList();
          _isLoadingEmployees = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingEmployees = false);
      }
    }
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      final TimeOfDay? timePicked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDueDate),
      );

      if (timePicked != null) {
        setState(() {
          _selectedDueDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            timePicked.hour,
            timePicked.minute,
          );
        });
      }
    }
  }

  void _toggleFrequency(String day) {
    // If no employee is selected, don't allow selection
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an employee first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Prevent selecting disabled days
    if (_disabledDays.contains(day)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This day is off for the selected employee and cannot be selected'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    setState(() {
      if (_selectedFrequency.contains(day)) {
        _selectedFrequency.remove(day);
      } else {
        // Final check before adding - should never reach here if disabled
        if (!_disabledDays.contains(day)) {
          _selectedFrequency.add(day);
        } else {
          // This should not happen, but just in case
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('This day is off for the selected employee'),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  void _handleSelfAssignment(bool value) {
    setState(() {
      _assignToSelf = value;
      if (value && _currentEmployeeId != null) {
        _selectedEmployeeId = _currentEmployeeId;
        _loadEmployeeSchedule(_currentEmployeeId!);
      } else if (!value) {
        _selectedEmployeeId = null;
        _disabledDays.clear();
      }
    });
  }

  Future<void> _loadEmployeeSchedule(String employeeId) async {
    setState(() {
      _isLoadingSchedule = true;
      _disabledDays.clear();
    });

    try {
      final schedule = await _scheduleService.getEmployeeSchedule(employeeId);
      if (mounted) {
        // Extract disabled days (days that are off)
        final weeklySchedule = schedule['weeklySchedule'] as List<dynamic>? ?? [];
        final disabledDaysSet = weeklySchedule
            .where((day) => day['isWorking'] == false)
            .map((day) => day['day'] as String)
            .toSet();
        
        setState(() {
          _isLoadingSchedule = false;
          _disabledDays = disabledDaysSet;
          
          // Remove any selected frequency days that are now disabled
          _selectedFrequency.removeWhere((day) => _disabledDays.contains(day));
        });
        
        // Debug print to verify schedule loading
        print('[CreateEditTaskScreen] Loaded schedule for employee: $employeeId');
        print('[CreateEditTaskScreen] Disabled days: $_disabledDays');
        print('[CreateEditTaskScreen] Weekly schedule: $weeklySchedule');
      }
    } catch (e) {
      print('[CreateEditTaskScreen] Error loading schedule: $e');
      if (mounted) {
        setState(() {
          _isLoadingSchedule = false;
          // If schedule not found or error, allow all days but show warning
          _disabledDays.clear();
        });
        
        // Show error message if schedule couldn't be loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not load employee schedule. All days will be available.'),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final taskData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'category': _selectedCategory,
        'priority': _selectedPriority,
        'dueDate': _selectedDueDate.toIso8601String(),
        'notes': _notesController.text.trim(),
        if (_selectedEmployeeId != null) 'assignedTo': _selectedEmployeeId,
        if (_selectedFrequency.isNotEmpty) 'frequency': _selectedFrequency,
      };

      if (widget.task != null) {
        // Update existing task
        await _taskService.updateTask(widget.task!.id, taskData);
      } else {
        // Create new task
        await _taskService.createTask(taskData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.task != null
                ? '✅ Task updated successfully'
                : '✅ Task created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException
                  ? e.message
                  : 'Failed to ${widget.task != null ? 'update' : 'create'} task',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task != null ? 'Edit Task' : 'Create Task'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Frequency (Days Selection) - Moved before category
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
                      Icon(Icons.repeat, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Frequency (Days)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedEmployeeId == null
                        ? 'Select an employee first to see available working days'
                        : 'Select days for recurring tasks (only working days are available)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  if (_selectedEmployeeId != null && _disabledDays.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Days marked with ⊗ are off days and cannot be selected',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.warning,
                            fontSize: 11,
                          ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Circular day selection
                  _isLoadingSchedule
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: _daysOfWeek.map((dayInfo) {
                            final day = dayInfo['day'] as String;
                            final isSelected =
                                _selectedFrequency.contains(day);
                            final isDisabled = _disabledDays.contains(day);
                            final isEnabled = _selectedEmployeeId != null && !isDisabled;
                            
                            return AbsorbPointer(
                              absorbing: !isEnabled,
                              child: GestureDetector(
                                onTap: () => _toggleFrequency(day),
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? AppColors.primary
                                        : isDisabled
                                            ? Colors.grey.withValues(alpha: 0.2)
                                            : AppColors.primary.withValues(alpha: 0.1),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : isDisabled
                                              ? Colors.grey.withValues(alpha: 0.5)
                                              : AppColors.primary.withValues(alpha: 0.3),
                                      width: isSelected ? 3 : 1,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        dayInfo['label'] as String,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? Colors.white
                                              : isDisabled
                                                  ? Colors.grey
                                                  : AppColors.primary,
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check,
                                            size: 16, color: Colors.white),
                                      if (isDisabled && !isSelected)
                                        Icon(Icons.block,
                                            size: 12, color: Colors.grey.withValues(alpha: 0.7)),
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

            // Category with subcategories
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Category *',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                // Category selection grid
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.map((category) {
                    final isSelected = _selectedCategory == category['value'];
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = category['value'] as String;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.3),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              category['icon'] as IconData,
                              size: 20,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              category['label'] as String,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Priority
            DropdownButtonFormField<String>(
              value: _selectedPriority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flag),
              ),
              items: ['low', 'medium', 'high', 'urgent']
                  .map((priority) => DropdownMenuItem(
                        value: priority,
                        child: Text(priority.toUpperCase()),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedPriority = value);
                }
              },
            ),
            const SizedBox(height: 16),

            // Self Assignment Toggle
            if (_currentEmployeeId != null)
              Card(
                color: AppColors.primary.withValues(alpha: 0.05),
                child: SwitchListTile(
                  title: const Text('Assign to Self'),
                  subtitle: const Text('Create task for yourself'),
                  value: _assignToSelf,
                  onChanged: _handleSelfAssignment,
                  secondary: Icon(
                    Icons.person,
                    color: _assignToSelf ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),

            // Assigned To (if not self-assigning)
            if (!_assignToSelf) ...[
              DropdownButtonFormField<String>(
                value: _selectedEmployeeId,
                decoration: InputDecoration(
                  labelText: 'Assign To',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                  suffixIcon: _isLoadingEmployees
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  ..._employees.map((employee) => DropdownMenuItem(
                        value: employee['id'],
                        child: Text(
                          '${employee['name']} (${employee['role']})',
                        ),
                      )),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedEmployeeId = value;
                    // Clear selected frequency when employee changes
                    _selectedFrequency.clear();
                    _disabledDays.clear();
                  });
                  // Load schedule for the new employee
                  if (value != null) {
                    _loadEmployeeSchedule(value);
                  }
                },
              ),
              const SizedBox(height: 16),
            ],

            // Due Date
            InkWell(
              onTap: _selectDueDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Due Date & Time *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  '${_selectedDueDate.day}/${_selectedDueDate.month}/${_selectedDueDate.year} '
                  '${_selectedDueDate.hour.toString().padLeft(2, '0')}:'
                  '${_selectedDueDate.minute.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        widget.task != null ? 'Update Task' : 'Create Task',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
