class TaskModel {
  final String id;
  final String title;
  final String description;
  final String category;
  final String? assignedToId;
  final String? assignedToName;
  final String status;
  final DateTime dueDate;
  final String priority;
  final DateTime? completedAt;
  final String? notes;
  final DateTime createdAt;
  final List<String>? frequency; // Days of week: monday, tuesday, etc.
  final DateTime? originalDueDate;
  bool isSelected;

  TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    this.category = 'daily',
    this.assignedToId,
    this.assignedToName,
    this.status = 'pending',
    required this.dueDate,
    this.priority = 'medium',
    this.completedAt,
    this.notes,
    required this.createdAt,
    this.frequency,
    this.originalDueDate,
    this.isSelected = false,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? 'daily',
      assignedToId: json['assignedTo']?['_id']?.toString() ??
          json['assignedTo']?.toString(),
      assignedToName: json['assignedTo']?['name'] ?? '',
      status: json['status'] ?? 'pending',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'])
          : DateTime.now(),
      priority: json['priority'] ?? 'medium',
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
      notes: json['notes'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      frequency: json['frequency'] != null
          ? List<String>.from(json['frequency'])
          : null,
      originalDueDate: json['originalDueDate'] != null
          ? DateTime.parse(json['originalDueDate'])
          : null,
      isSelected: json['isSelected'] ?? false,
    );
  }

  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    String? assignedToId,
    String? assignedToName,
    String? status,
    DateTime? dueDate,
    String? priority,
    DateTime? completedAt,
    String? notes,
    DateTime? createdAt,
    List<String>? frequency,
    DateTime? originalDueDate,
    bool? isSelected,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      assignedToId: assignedToId ?? this.assignedToId,
      assignedToName: assignedToName ?? this.assignedToName,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      completedAt: completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      frequency: frequency ?? this.frequency,
      originalDueDate: originalDueDate ?? this.originalDueDate,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'title': title,
      'description': description,
      'category': category,
      'assignedTo': {
        '_id': assignedToId,
        'name': assignedToName,
      },
      'status': status,
      'dueDate': dueDate.toIso8601String(),
      'priority': priority,
      'completedAt': completedAt?.toIso8601String(),
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'frequency': frequency,
      'originalDueDate': originalDueDate?.toIso8601String(),
    };
  }

  bool get isOverdue {
    if (status == 'completed' || status == 'complete' || status == 'cancelled')
      return false;
    return dueDate.isBefore(DateTime.now());
  }

  bool get isDueToday {
    final today = DateTime.now();
    return dueDate.year == today.year &&
        dueDate.month == today.month &&
        dueDate.day == today.day;
  }
}
