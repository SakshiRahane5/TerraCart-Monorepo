import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../services/kot_service.dart';
import '../../services/socket_service.dart';
import '../../core/exceptions/api_exception.dart';
import '../../providers/app_provider.dart';
import 'package:provider/provider.dart';

class KotScreen extends StatefulWidget {
  const KotScreen({super.key});

  @override
  State<KotScreen> createState() => _KotScreenState();
}

class _KotScreenState extends State<KotScreen> {
  final KotService _kotService = KotService();
  final SocketService _socketService = SocketService();

  List<Map<String, dynamic>> _kotItems = [];
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'pending', 'preparing', 'ready'];
  bool _isLoading = true;
  String? _errorMessage;

  String _statusKey(String rawStatus) =>
      rawStatus.toLowerCase().trim().replaceAll('_', ' ');

  @override
  void initState() {
    super.initState();
    _loadKOTs();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    // Clean up socket listeners to prevent crashes when navigating back
    _socketService.off('kot:created');
    _socketService.off('kot:status:updated');
    _socketService.off('order:created');
    _socketService.off('order_status_updated');
    _socketService.off('order.cancelled');
    super.dispose();
  }

  void _setupSocketListeners() {
    void refreshKots(dynamic _) {
      if (mounted) {
        _loadKOTs();
      }
    }

    // Listen for KOT-specific events
    _socketService.on('kot:created', refreshKots);
    _socketService.on('kot:status:updated', refreshKots);

    // Listen for order events to sync with takeaway and dine-in orders
    _socketService.on('order:created', refreshKots);
    _socketService.on('order_status_updated', refreshKots);
    _socketService.on('order.cancelled', refreshKots);
  }

  Future<void> _loadKOTs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final kots = await _kotService
          .getPendingKOTs()
          .catchError((e) => <Map<String, dynamic>>[]);

      if (mounted) {
        setState(() {
          _kotItems = List<Map<String, dynamic>>.from(kots);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ApiException ? e.message : 'Failed to load KOTs';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_selectedFilter == 'All') return _kotItems;
    return _kotItems.where((item) {
      final rawStatus =
          (item['orderStatus'] ?? item['status'] ?? '').toString();
      return _statusKey(rawStatus) == _selectedFilter.toLowerCase();
    }).toList();
  }

  int _getStatusCount(String status) {
    return _kotItems.where((item) {
      final rawStatus =
          (item['orderStatus'] ?? item['status'] ?? '').toString();
      return _statusKey(rawStatus) == status.toLowerCase();
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Kitchen Orders (KOT)'),
          leading: IconButton(
            onPressed: () {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_ios_rounded),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Kitchen Orders (KOT)'),
          leading: IconButton(
            onPressed: () {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_ios_rounded),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(_errorMessage!),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadKOTs,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Orders (KOT)'),
        leading: IconButton(
          onPressed: () {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          IconButton(
            onPressed: _loadKOTs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadKOTs,
        child: Column(
          children: [
            // Stats Bar
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.warmGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('Pending', '${_getStatusCount('pending')}',
                      Icons.access_time),
                  _buildDivider(),
                  _buildStatItem('Preparing', '${_getStatusCount('preparing')}',
                      Icons.restaurant_menu),
                  _buildDivider(),
                  _buildStatItem('Ready', '${_getStatusCount('ready')}',
                      Icons.check_circle),
                ],
              ),
            ).animate().fadeIn(),

            // Professional Filter Chips
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.map((filter) {
                    final isSelected = _selectedFilter == filter;
                    final displayLabel = _getFilterLabel(filter);
                    final filterIcon = _getFilterIcon(filter);
                    final filterColor = _getFilterColor(filter);

                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(
                          filterIcon,
                          size: 18,
                          color: isSelected ? Colors.white : filterColor,
                        ),
                        label: Text(
                          displayLabel,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (_) =>
                            setState(() => _selectedFilter = filter),
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.cardBackground,
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.cardBorder,
                          width: isSelected ? 2 : 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        checkmarkColor: Colors.white,
                        elevation: isSelected ? 2 : 0,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 16),

            // KOT List
            Expanded(
              child: _filteredItems.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.restaurant_menu,
                                size: 64, color: AppColors.textSecondary),
                            const SizedBox(height: 16),
                            Text(
                              'No KOTs available',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final kot = _filteredItems[index];
                        return _buildKotCard(kot)
                            .animate()
                            .fadeIn(
                                delay:
                                    Duration(milliseconds: 150 + (index * 50)))
                            .slideX(begin: 0.05);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 50,
      color: Colors.white.withValues(alpha: 0.3),
    );
  }

  // Helper functions for professional filter display
  String _getFilterLabel(String filter) {
    switch (filter.toLowerCase()) {
      case 'all':
        return 'All';
      case 'pending':
        return 'Pending';
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready';
      default:
        return filter;
    }
  }

  IconData _getFilterIcon(String filter) {
    switch (filter.toLowerCase()) {
      case 'all':
        return Icons.list_alt;
      case 'pending':
        return Icons.access_time;
      case 'preparing':
        return Icons.restaurant_menu;
      case 'ready':
        return Icons.check_circle;
      default:
        return Icons.filter_list;
    }
  }

  Color _getFilterColor(String filter) {
    switch (filter.toLowerCase()) {
      case 'all':
        return AppColors.primary;
      case 'pending':
        return AppColors.info;
      case 'preparing':
        return AppColors.warning;
      case 'ready':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildKotCard(Map<String, dynamic> kot) {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final userRole = appProvider.userRole.toLowerCase();
    final isCook = userRole == 'cook';

    final rawStatus = (kot['orderStatus'] ?? kot['status'] ?? '').toString();
    final status = _statusKey(rawStatus);
    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (status) {
      case 'pending':
        statusColor = AppColors.info;
        statusIcon = Icons.access_time;
        statusLabel = 'PENDING';
        break;
      case 'preparing':
        statusColor = AppColors.warning;
        statusIcon = Icons.restaurant_menu;
        statusLabel = 'PREPARING';
        break;
      case 'ready':
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        statusLabel = 'READY';
        break;
      case 'served':
        statusColor = AppColors.info;
        statusIcon = Icons.restaurant;
        statusLabel = 'SERVED';
        break;
      default:
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.help_outline;
        statusLabel =
            rawStatus.isNotEmpty ? rawStatus.toUpperCase() : 'UNKNOWN';
    }

    final items = kot['items'] ?? kot['orderItems'] ?? [];
    final tableNumber = kot['tableNumber'] ?? kot['table'] ?? 'N/A';
    final serviceType = kot['serviceType'] ?? 'DINE_IN';
    final isTakeaway = serviceType == 'TAKEAWAY';
    final createdAt = kot['createdAt'] ?? kot['timestamp'];
    final timeAgo = createdAt != null
        ? DateTimeUtils.getTimeAgo(DateTime.parse(createdAt))
        : 'Recently';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              kot['orderId']?.toString().isNotEmpty == true
                                  ? 'Order ${kot['orderId']}'
                                  : (kot['_id']?.toString() ??
                                      kot['id']?.toString() ??
                                      'KOT'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            isTakeaway
                                ? Icons.shopping_bag
                                : Icons.table_restaurant,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isTakeaway ? 'Takeaway' : 'Table $tableNumber',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeAgo,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Items
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: (items as List).map((item) {
                final itemName = item['name'] ?? item['itemName'] ?? 'Unknown';
                final quantity = item['quantity'] ?? item['qty'] ?? 1;
                final note = item['note'] ?? item['specialInstructions'] ?? '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${quantity}x',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              itemName,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            if (note.toString().isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Note: $note',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Action Buttons (cook-only, backend-driven transitions)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBorder.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
            ),
            child: _buildActionButtons(kot, status, isCook),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
      Map<String, dynamic> kot, String status, bool isCook) {
    // Get orderId from kot - backend returns orderId field directly
    final orderId = kot['orderId']?.toString() ?? '';
    if (orderId.isEmpty) {
      // Fallback: try to extract from _id if orderId is not present
      final kotId = kot['_id']?.toString() ?? kot['id']?.toString() ?? '';
      if (kotId.contains('-kot-')) {
        final parts = kotId.split('-kot-');
        if (parts.isNotEmpty) {
          final actualOrderId = parts[0];
          return _buildButtonsForOrder(actualOrderId, status, isCook);
        }
      }
      return const SizedBox.shrink();
    }

    return _buildButtonsForOrder(orderId, status, isCook);
  }

  Widget _buildButtonsForOrder(String orderId, String status, bool isCook) {
    if (!isCook) return const SizedBox.shrink();

    if (status == 'pending') {
      return ElevatedButton(
        onPressed: () => _updateStatus(orderId, 'Preparing'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.warning,
          minimumSize: const Size(double.infinity, 48),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_menu, color: Colors.white),
            SizedBox(width: 8),
            Text('Start Preparing'),
          ],
        ),
      );
    }

    if (status == 'preparing') {
      return ElevatedButton(
        onPressed: () => _updateStatus(orderId, 'Ready'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          minimumSize: const Size(double.infinity, 48),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Mark Ready'),
          ],
        ),
      );
    }

    if (status == 'ready') {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            'Ready for waiter service',
            style: TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _updateStatus(String orderId, String newStatus) async {
    try {
      // Use orderId directly (the KOT route accepts both orderId and orderId-kot-index)
      await _kotService.updateKOTStatus(orderId, newStatus);
      await _loadKOTs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('KOT updated to ${newStatus.toUpperCase()}'),
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
              e is ApiException ? e.message : 'Failed to update KOT status',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
