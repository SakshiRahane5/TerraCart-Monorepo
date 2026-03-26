import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../services/table_service.dart';
import '../../services/order_service.dart';
import '../../models/order_model.dart';
import '../../core/utils/order_status_utils.dart';
import '../../core/exceptions/api_exception.dart';
import '../orders/order_details_screen.dart';

class TableDashboardScreen extends StatefulWidget {
  const TableDashboardScreen({super.key});

  @override
  State<TableDashboardScreen> createState() => _TableDashboardScreenState();
}

class _TableDashboardScreenState extends State<TableDashboardScreen> {
  final TableService _tableService = TableService();
  final OrderService _orderService = OrderService();
  List<Map<String, dynamic>> _tables = [];
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
      final tables = await _tableService.getTableOccupancyDashboard();
      if (mounted) {
        setState(() {
          _tables = tables;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ApiException ? e.message : 'Failed to load tables';
          _isLoading = false;
        });
      }
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
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

  Future<void> _onTableTap(BuildContext context, Map<String, dynamic> table) async {
    final status = table['status']?.toString() ?? 'AVAILABLE';
    final isOccupied = status == 'OCCUPIED' || status == 'RESERVED';
    if (!isOccupied) return;

    OrderModel? order;
    final currentOrder = table['currentOrder'];
    if (currentOrder != null && currentOrder is Map) {
      try {
        order = OrderModel.fromJson(Map<String, dynamic>.from(currentOrder));
      } catch (_) {}
    }
    if (order == null) {
      final currentOrderId = table['currentOrder'] is Map
          ? (table['currentOrder'] as Map)['_id']?.toString() ?? (table['currentOrder'] as Map)['id']?.toString()
          : table['currentOrder']?.toString();
      final tableId = table['id']?.toString() ?? table['_id']?.toString();
      if (currentOrderId != null && currentOrderId.isNotEmpty) {
        try {
          order = await _orderService.getOrderById(currentOrderId);
        } catch (_) {}
      }
      if (order == null && tableId != null) {
        try {
          final orders = await _orderService.getOrders(limit: 100);
          final active = orders.where((o) {
            final tid = o.tableId?.toString() ?? '';
            return tid == tableId &&
                OrderStatusUtils.shouldShowForEmployees(
                  status: o.status,
                  paymentStatus: o.paymentStatus,
                  isPaid: o.isPaid,
                  paymentMode: o.paymentMode,
                  officePaymentMode: o.officePaymentMode,
                  paymentRequiredBeforeProceeding:
                      o.paymentRequiredBeforeProceeding,
                  sourceQrType: o.sourceQrType,
                  serviceType: o.serviceType,
                  orderType: o.orderType,
                );
          }).toList();
          if (active.isNotEmpty) order = active.first;
        } catch (_) {}
      }
    }
    if (order != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderDetailsScreen(order: order!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Table Occupancy'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _isLoading ? null : _loadTables),
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
                        Icon(Icons.error_outline, size: 48, color: AppColors.error),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(_errorMessage!, textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadTables, child: const Text('Retry')),
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
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.9,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _tables.length,
                          itemBuilder: (context, i) {
                            final table = _tables[i];
                            final status = table['status']?.toString() ?? 'AVAILABLE';
                            final number = table['number'] ?? table['name'] ?? '${i + 1}';
                            final isMerged = table['isMerged'] == true;
                            final capacity = table['totalCapacity'] ?? table['capacity'] ?? 0;
                            return Card(
                              color: _getStatusColor(status).withValues(alpha: 0.1),
                              child: InkWell(
                                onTap: () => _onTableTap(context, table),
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
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      if (isMerged)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('Merged', style: TextStyle(fontSize: 10, color: Colors.purple.withValues(alpha: 0.9))),
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


