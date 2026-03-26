import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';
import '../models/task_model.dart';

class TaskService {
  final ApiService _api = ApiService();

  Future<List<TaskModel>> getTasks({
    String? status,
    String? category,
    String? priority,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
        if (category != null) 'category': category,
        if (priority != null) 'priority': priority,
      };

      final response =
          await _api.get(ApiConfig.tasks, queryParams: queryParams);

      // API service wraps list responses into { success: true, data: [...] }.
      // Keep extra fallbacks for backward compatibility.
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => TaskModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
        if (data is Map) {
          return [TaskModel.fromJson(Map<String, dynamic>.from(data))];
        }
      }

      if (response['data'] is List) {
        return (response['data'] as List)
            .whereType<Map>()
            .map((e) => TaskModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      if (response['_id'] != null || response['id'] != null) {
        return [TaskModel.fromJson(response)];
      }

      return [];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get tasks: ${e.toString()}');
    }
  }

  Future<List<TaskModel>> getTodayTasks() async {
    try {
      final response = await _api.get(ApiConfig.todayTasks);

      // Handle response format: backend may return array directly or wrapped in { success, data }
      List<dynamic> taskList = [];

      // API service always returns a Map, but backend may return array in data field
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          taskList = data;
        } else {
          // Single task object
          taskList = [data];
        }
      } else if (response.containsKey('data') && response['data'] is List) {
        taskList = response['data'] as List;
      } else if (response.containsKey('_id')) {
        // Single task object at root level
        taskList = [response];
      } else {
        // If no tasks, return empty list instead of throwing error
        return [];
      }

      final parsedTasks = taskList
          .whereType<Map>()
          .map((e) => TaskModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Backend already applies IST-aware "today" rules; avoid client re-filter
      // to prevent date/timezone mismatches.
      return parsedTasks;
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get tasks: ${e.toString()}');
    }
  }

  Future<TaskModel> createTask(Map<String, dynamic> taskData) async {
    try {
      final response = await _api.post(ApiConfig.tasks, body: taskData);

      // Handle both formats: { success: true, data: {...} } or direct object
      if (response['success'] == true && response['data'] != null) {
        return TaskModel.fromJson(response['data']);
      } else if (response['_id'] != null || response['id'] != null) {
        // Direct task object response
        return TaskModel.fromJson(response);
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to create task');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to create task: ${e.toString()}');
    }
  }

  Future<TaskModel> updateTask(String id, Map<String, dynamic> taskData) async {
    try {
      final response = await _api.put(ApiConfig.taskById(id), body: taskData);

      // Handle both formats: { success: true, data: {...} } or direct object
      if (response['success'] == true && response['data'] != null) {
        return TaskModel.fromJson(response['data']);
      } else if (response['_id'] != null || response['id'] != null) {
        // Direct task object response
        return TaskModel.fromJson(response);
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to update task');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to update task: ${e.toString()}');
    }
  }

  Future<TaskModel> completeTask(String id) async {
    try {
      final response = await _api.post(ApiConfig.completeTask(id));

      // Handle both formats: { success: true, data: {...} } or direct object
      if (response['success'] == true && response['data'] != null) {
        return TaskModel.fromJson(response['data']);
      } else if (response['_id'] != null || response['id'] != null) {
        // Direct task object response
        return TaskModel.fromJson(response);
      }

      throw ApiException(
          message: response['message'] ?? 'Failed to complete task');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to complete task: ${e.toString()}');
    }
  }
}
