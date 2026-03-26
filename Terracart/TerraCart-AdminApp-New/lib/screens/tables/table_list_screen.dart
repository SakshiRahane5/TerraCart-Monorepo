import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/table_model.dart';
import '../../services/table_service.dart';
import '../../core/exceptions/api_exception.dart';

/// Table list screen for waiter - uses GET /tables (waiter has access).
/// Table dashboard (occupancy) is manager-only.
class TableListScreen extends StatefulWidget {
  const TableListScreen({super.key});

  @override
  State<TableListScreen> createState() => _TableListScreenState();
}

class _TableListScreenState extends State<TableListScreen> {
  final TableService _tableService = TableService();
  List<TableModel> _tables = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final tables = await _tableService.getTables();
      final modernTables = tables.where((table) {
        final hasQrSlug = (table.qrSlug ?? '').trim().isNotEmpty;
        final qrType = (table.qrContextType ?? '').trim().toUpperCase();
        return hasQrSlug && qrType == 'TABLE';
      }).toList();

      final Map<String, TableModel> dedupedByNumber = {};
      for (final table in modernTables) {
        final cartId = (table.cartId ?? 'unknown').trim();
        final key = '$cartId-${table.number}';
        if (!dedupedByNumber.containsKey(key)) {
          dedupedByNumber[key] = table;
          continue;
        }

        final existing = dedupedByNumber[key]!;
        if (table.isOccupied && !existing.isOccupied) {
          dedupedByNumber[key] = table;
        }
      }

      final scopedTables = dedupedByNumber.values.toList()
        ..sort((a, b) => a.number.compareTo(b.number));

      if (mounted) {
        setState(() {
          _tables = scopedTables;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e is ApiException ? e.message : 'Failed to load tables';
          _isLoading = false;
        });
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'AVAILABLE':
        return AppColors.success;
      case 'OCCUPIED':
      case 'RESERVED':
        return AppColors.error;
      case 'CLEANING':
        return AppColors.textSecondary;
      case 'MERGED':
        return Colors.purple;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tables'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadTables,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTables,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: AppColors.error),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child:
                              Text(_errorMessage!, textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadTables,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_tables.length} table(s)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 16),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.9,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _tables.length,
                          itemBuilder: (context, i) {
                            final table = _tables[i];
                            final status = table.status;
                            final number = table.number;
                            final isMerged = table.isMerged;
                            final capacity =
                                table.totalCapacity ?? table.capacity;
                            return Card(
                              color: _getStatusColor(status)
                                  .withValues(alpha: 0.1),
                              child: InkWell(
                                onTap: () {},
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'T$number',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: _getStatusColor(status),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _getStatusColor(status),
                                        ),
                                      ),
                                      if (capacity > 0)
                                        Text(
                                          'Seats: $capacity',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      if (isMerged)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.purple
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Merged',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.purple
                                                  .withValues(alpha: 0.9),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
