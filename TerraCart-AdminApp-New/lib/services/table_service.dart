import '../core/config/api_config.dart';
import '../core/services/api_service.dart';
import '../core/exceptions/api_exception.dart';
import '../models/table_model.dart';

class TableService {
  final ApiService _api = ApiService();

  Future<List<TableModel>> getTables() async {
    try {
      final response = await _api.get(ApiConfig.tables);
      
      // Handle response format: { success: true, data: [...] }
      // or legacy: { data: [...] }
      List<dynamic> tablesList = [];
      
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          tablesList = data;
        }
      } else if (response['data'] != null) {
        final data = response['data'];
        if (data is List) {
          tablesList = data;
        }
      }
      
      return tablesList.map((e) => TableModel.fromJson(e)).toList();
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get tables: ${e.toString()}');
    }
  }

  Future<List<TableModel>> getAvailableTables() async {
    try {
      final response = await _api.get(ApiConfig.availableTables);
      
      if (response['success'] == true) {
        final data = response['data'] ?? [];
        return (data as List).map((e) => TableModel.fromJson(e)).toList();
      }

      throw ApiException(message: 'Failed to get available tables');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get tables: ${e.toString()}');
    }
  }

  Future<TableModel> getTableById(String id) async {
    try {
      final response = await _api.get(ApiConfig.tableById(id));
      
      if (response['success'] == true) {
        return TableModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Failed to get table');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get table: ${e.toString()}');
    }
  }

  Future<TableModel> occupyTable(String id) async {
    try {
      final response = await _api.post(ApiConfig.occupyTable(id));
      
      if (response['success'] == true) {
        return TableModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Failed to occupy table');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to occupy table: ${e.toString()}');
    }
  }

  Future<TableModel?> lookupTableBySlug(String slug) async {
    try {
      final response = await _api.get('/tables/lookup/$slug');
      
      // Backend returns table in different formats:
      // 1. { table: {...} }
      // 2. { success: true, data: {...} }
      // 3. Direct table object
      Map<String, dynamic>? tableData;
      
      if (response['table'] != null) {
        final table = response['table'];
        if (table is Map<String, dynamic>) {
          tableData = table;
        }
      } else if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        if (data is Map<String, dynamic>) {
          tableData = data;
        }
      } else if (response['_id'] != null || response['number'] != null) {
        // Direct table object
        tableData = response;
      }
      
      if (tableData != null) {
        return TableModel.fromJson(tableData);
      }

      return null;
    } catch (e) {
      if (e is ApiException) {
        // If it's a 404, table not found - return null
        if (e.message.contains('not found') || e.message.contains('404')) {
          return null;
        }
        rethrow;
      }
      return null;
    }
  }

  Future<Map<String, dynamic>> mergeTables({
    required String primaryTableId,
    required List<String> secondaryTableIds,
  }) async {
    try {
      final response = await _api.post(
        '/tables/merge',
        body: {
          'primaryTableId': primaryTableId,
          'secondaryTableIds': secondaryTableIds,
        },
      );

      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data']);
      }
      if (response['message'] != null) {
        return response;
      }

      throw ApiException(message: 'Failed to merge tables');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to merge tables: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getTableOccupancyDashboard() async {
    try {
      final response = await _api.get(ApiConfig.tableDashboard);
      final data = response['data'] ?? response;
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to get table occupancy: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> unmergeTable(String tableId) async {
    try {
      final response = await _api.post(
        '/tables/$tableId/unmerge',
      );

      if (response['success'] == true && response['data'] != null) {
        return Map<String, dynamic>.from(response['data']);
      }
      if (response['message'] != null) {
        return response;
      }

      throw ApiException(message: 'Failed to unmerge table');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Failed to unmerge table: ${e.toString()}');
    }
  }
}
