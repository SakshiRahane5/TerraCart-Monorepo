import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../providers/app_provider.dart';
import '../../services/customer_request_service.dart';
import '../../services/socket_service.dart';
import '../../core/exceptions/api_exception.dart';
import 'customer_request_logs_screen.dart';

class CustomerRequestsScreen extends StatefulWidget {
  /// When false, no back button is shown (e.g. when used as a tab)
  final bool showBackButton;

  const CustomerRequestsScreen({super.key, this.showBackButton = false});

  @override
  State<CustomerRequestsScreen> createState() => _CustomerRequestsScreenState();
}

class _CustomerRequestsScreenState extends State<CustomerRequestsScreen> {
  final CustomerRequestService _requestService = CustomerRequestService();
  final SocketService _socketService = SocketService();
  List<Map<String, dynamic>> _requests = [];
  Map<String, List<Map<String, dynamic>>> _requestsByTable = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _selectedTableFilter; // null = all tables

  @override
  void initState() {
    super.initState();
    _loadRequests();
    // Setup socket listeners after a short delay to ensure socket is connected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSocketListeners();
    });
  }

  @override
  void dispose() {
    _removeSocketListeners();
    super.dispose();
  }

  void _setupSocketListeners() {
    // Check if socket is connected before setting up listeners
    if (!_socketService.isConnected) {
      print(
          '[CustomerRequestsScreen] Socket not connected, listeners will be set up when socket connects');
      // Try again after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _socketService.isConnected) {
          _setupSocketListeners();
        }
      });
      return;
    }

    print(
        '[CustomerRequestsScreen] Setting up socket listeners for real-time request updates');

    // Listen to all request-related socket events for real-time updates with debouncing
    _socketService.on('request:created', (data) {
      print('[CustomerRequestsScreen] 🔔 Socket event: request:created');
      if (mounted) {
        // Show a brief notification that a new request arrived
        _showSnackBar(
          '📢 New customer request received',
          backgroundColor: AppColors.info,
          duration: const Duration(seconds: 2),
        );
        _loadRequests();
      }
    }, debounce: true, delay: const Duration(milliseconds: 500));

    _socketService.on('request:updated', (data) {
      print('[CustomerRequestsScreen] 🔔 Socket event: request:updated');
      if (mounted) _loadRequests();
    }, debounce: true);

    _socketService.on('request:acknowledged', (data) {
      print('[CustomerRequestsScreen] 🔔 Socket event: request:acknowledged');
      if (mounted) _loadRequests();
    }, debounce: true);

    _socketService.on('request:resolved', (data) {
      print('[CustomerRequestsScreen] 🔔 Socket event: request:resolved');
      if (mounted) {
        // Request resolved - remove from list immediately
        _loadRequests();
      }
    }, debounce: true);

    // Also listen to order events as requests might be tied to orders
    _socketService.on('order:created', (data) {
      print(
          '[CustomerRequestsScreen] 🔔 Socket event: order:created (may affect requests)');
      if (mounted) _loadRequests();
    }, debounce: true);

    _socketService.on('order_status_updated', (data) {
      print(
          '[CustomerRequestsScreen] 🔔 Socket event: order_status_updated (may affect requests)');
      if (mounted) _loadRequests();
    }, debounce: true);
  }

  void _removeSocketListeners() {
    print('[CustomerRequestsScreen] Removing socket listeners');
    _socketService.off('request:created');
    _socketService.off('request:updated');
    _socketService.off('request:acknowledged');
    _socketService.off('request:resolved');
    _socketService.off('order:created');
    _socketService.off('order_status_updated');
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch all requests (not just pending) to show complete status
      // The backend should return requests sorted by status and time
      final requests = await _requestService.getRequests(
        status: null, // Get all requests
        limit: 100, // Increased limit to get all requests
      );

      if (mounted) {
        setState(() {
          // Convert to list and filter out resolved/completed requests
          final allRequests = (requests as List)
              .map((r) => r as Map<String, dynamic>)
              .where((r) {
            final status = (r['status'] ?? 'pending').toString().toLowerCase();
            // Only show non-resolved requests on main page
            return status != 'resolved' && status != 'completed';
          }).toList()
            ..sort((a, b) {
              final statusA =
                  (a['status'] ?? 'pending').toString().toLowerCase();
              final statusB =
                  (b['status'] ?? 'pending').toString().toLowerCase();

              // Priority: pending > acknowledged/in_progress
              final priorityA = statusA == 'pending' ? 0 : 1;
              final priorityB = statusB == 'pending' ? 0 : 1;

              if (priorityA != priorityB) {
                return priorityA.compareTo(priorityB);
              }

              // If same priority, sort by time (newest first)
              final timeA = a['createdAt'] ?? a['timestamp'] ?? '';
              final timeB = b['createdAt'] ?? b['timestamp'] ?? '';
              if (timeA.isNotEmpty && timeB.isNotEmpty) {
                try {
                  final dateA = DateTime.parse(timeA);
                  final dateB = DateTime.parse(timeB);
                  return dateB.compareTo(dateA);
                } catch (_) {}
              }
              return 0;
            });

          // Group requests by table (only active requests)
          _requestsByTable.clear();
          for (final request in allRequests) {
            final tableNumber = _getTableNumber(request);
            final tableKey =
                tableNumber != 'N/A' ? 'Table $tableNumber' : 'No Table';

            if (!_requestsByTable.containsKey(tableKey)) {
              _requestsByTable[tableKey] = [];
            }
            _requestsByTable[tableKey]!.add(request);
          }

          // Apply table filter if selected
          if (_selectedTableFilter != null) {
            _requests = _requestsByTable[_selectedTableFilter] ?? [];
          } else {
            _requests = allRequests;
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e is ApiException ? e.message : 'Failed to load requests';
          _isLoading = false;
        });
      }
    }
  }

  // Helper method to safely show snackbars
  void _showSnackBar(String message,
      {Color? backgroundColor, Duration? duration}) {
    if (!mounted) return;

    try {
      final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
      if (scaffoldMessenger != null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor ?? AppColors.primary,
            duration: duration ?? const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Silently fail if context is invalid
      print('[CustomerRequestsScreen] Failed to show snackbar: $e');
    }
  }

  Future<void> _acknowledgeRequest(String id) async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.isReadOnlyAfterCheckout) {
      _showSnackBar(
        'You have checked out for today. Read-only mode active.',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    try {
      await _requestService.acknowledgeRequest(id);
      // Reload requests to get updated status
      await _loadRequests();
      _showSnackBar(
        '✅ Request acknowledged',
        backgroundColor: AppColors.success,
      );
    } catch (e) {
      _showSnackBar(
        e is ApiException ? e.message : 'Failed to acknowledge request',
        backgroundColor: AppColors.error,
      );
    }
  }

  Future<void> _resolveRequest(String id) async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    if (appProvider.isReadOnlyAfterCheckout) {
      _showSnackBar(
        'You have checked out for today. Read-only mode active.',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    try {
      await _requestService.resolveRequest(id);
      // Reload requests to get updated status
      await _loadRequests();
      _showSnackBar(
        '✅ Request resolved',
        backgroundColor: AppColors.success,
      );
    } catch (e) {
      _showSnackBar(
        e is ApiException ? e.message : 'Failed to resolve request',
        backgroundColor: AppColors.error,
      );
    }
  }

  String _formatTimeAgo(String? dateTimeStr) {
    if (dateTimeStr == null) return 'Just now';
    try {
      return DateTimeUtils.getTimeAgo(DateTime.parse(dateTimeStr));
    } catch (e) {
      return 'Just now';
    }
  }

  String _getTableNumber(Map<String, dynamic> request) {
    // Try multiple ways to get table number
    if (request['tableId'] != null) {
      if (request['tableId'] is Map) {
        return request['tableId']['number']?.toString() ??
            request['tableId']['tableNumber']?.toString() ??
            'N/A';
      } else if (request['tableId'] is String) {
        // If it's a string ID, try to get from table object
        return request['table']?['number']?.toString() ??
            request['table']?['tableNumber']?.toString() ??
            'N/A';
      }
    }
    // Also check table object directly
    if (request['table'] != null && request['table'] is Map) {
      return request['table']['number']?.toString() ??
          request['table']['tableNumber']?.toString() ??
          'N/A';
    }
    return 'N/A';
  }

  String _getOrderId(Map<String, dynamic> request) {
    // Extract full order ID from request
    if (request['orderId'] != null) {
      if (request['orderId'] is Map) {
        return request['orderId']['_id']?.toString() ??
            request['orderId']['id']?.toString() ??
            'N/A';
      }
      return request['orderId'].toString();
    }
    if (request['order'] != null) {
      if (request['order'] is Map) {
        return request['order']['_id']?.toString() ??
            request['order']['id']?.toString() ??
            'N/A';
      } else {
        return request['order'].toString();
      }
    }
    return 'N/A';
  }

  String _getCustomerName(Map<String, dynamic> request) {
    // Try to get customer name from order
    if (request['orderId'] != null && request['orderId'] is Map) {
      final order = request['orderId'] as Map<String, dynamic>;
      if (order['customerName'] != null &&
          order['customerName'].toString().trim().isNotEmpty) {
        return order['customerName'].toString().trim();
      }
    }
    if (request['order'] != null && request['order'] is Map) {
      final order = request['order'] as Map<String, dynamic>;
      if (order['customerName'] != null &&
          order['customerName'].toString().trim().isNotEmpty) {
        return order['customerName'].toString().trim();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final isReadOnlyLocked = appProvider.isReadOnlyAfterCheckout;
    final pendingCount =
        _requests.where((r) => r['status'] == 'pending').length;
    final tableKeys = _requestsByTable.keys.toList()..sort();

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Customer Requests'),
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
          title: const Text('Customer Requests'),
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
                onPressed: _loadRequests,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Requests'),
        automaticallyImplyLeading: widget.showBackButton,
        leading: widget.showBackButton
            ? IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_rounded),
              )
            : null,
        actions: [
          // Socket connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              _socketService.isConnected ? Icons.wifi : Icons.wifi_off,
              size: 20,
              color: _socketService.isConnected
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
          ),
          // View logs button
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CustomerRequestLogsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history),
            tooltip: 'View request logs',
          ),
          Stack(
            children: [
              IconButton(
                onPressed: _loadRequests,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh requests',
              ),
              if (pendingCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        pendingCount > 9 ? '9+' : pendingCount.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
          // Table Filter
          if (_requestsByTable.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.cardBorder.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Filter by Table:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _selectedTableFilter,
                      isExpanded: true,
                      hint: const Text('All Tables'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('All Tables'),
                        ),
                        ...tableKeys.map((tableKey) => DropdownMenuItem<String>(
                              value: tableKey,
                              child: Text(tableKey),
                            )),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedTableFilter = value;
                          // Update filtered requests
                          if (value != null) {
                            _requests = _requestsByTable[value] ?? [];
                          } else {
                            // Show all requests
                            _requests = _requestsByTable.values
                                .expand((list) => list)
                                .toList()
                              ..sort((a, b) {
                                final statusA = (a['status'] ?? 'pending')
                                    .toString()
                                    .toLowerCase();
                                final statusB = (b['status'] ?? 'pending')
                                    .toString()
                                    .toLowerCase();
                                final priorityA = statusA == 'pending'
                                    ? 0
                                    : (statusA == 'acknowledged' ||
                                            statusA == 'in_progress')
                                        ? 1
                                        : 2;
                                final priorityB = statusB == 'pending'
                                    ? 0
                                    : (statusB == 'acknowledged' ||
                                            statusB == 'in_progress')
                                        ? 1
                                        : 2;
                                if (priorityA != priorityB) {
                                  return priorityA.compareTo(priorityB);
                                }
                                final timeA =
                                    a['createdAt'] ?? a['timestamp'] ?? '';
                                final timeB =
                                    b['createdAt'] ?? b['timestamp'] ?? '';
                                if (timeA.isNotEmpty && timeB.isNotEmpty) {
                                  try {
                                    final dateA = DateTime.parse(timeA);
                                    final dateB = DateTime.parse(timeB);
                                    return dateB.compareTo(dateA);
                                  } catch (_) {}
                                }
                                return 0;
                              });
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          // Requests List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadRequests,
              child: _requests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.support_agent,
                            size: 64,
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _selectedTableFilter != null
                                ? 'No requests for $_selectedTableFilter'
                                : 'No pending requests',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        final request = _requests[index];
                        return _buildRequestCard(
                          request,
                          isReadOnlyLocked: isReadOnlyLocked,
                        )
                            .animate()
                            .fadeIn(
                                delay:
                                    Duration(milliseconds: 100 + (index * 50)))
                            .slideX(begin: 0.05);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(
    Map<String, dynamic> request, {
    required bool isReadOnlyLocked,
  }) {
    final priority = request['priority'] ?? 'medium';
    final requestType = request['requestType'] ?? 'service';
    final status = request['status'] ?? 'pending';
    final tableNumber = _getTableNumber(request);
    final createdAt = request['createdAt'] ?? request['timestamp'];
    final description =
        request['description'] ?? request['customerNotes'] ?? '';

    Color priorityColor;
    switch (priority) {
      case 'high':
      case 'urgent':
        priorityColor = AppColors.error;
        break;
      case 'medium':
        priorityColor = AppColors.warning;
        break;
      default:
        priorityColor = AppColors.success;
    }

    IconData typeIcon;
    switch (requestType) {
      case 'service':
        typeIcon = Icons.room_service;
        break;
      case 'water':
        typeIcon = Icons.water_drop;
        break;
      case 'bill':
        typeIcon = Icons.receipt_long;
        break;
      case 'complaint':
        typeIcon = Icons.warning_amber;
        break;
      case 'assistance':
        typeIcon = Icons.help_outline;
        break;
      case 'menu':
        typeIcon = Icons.menu_book;
        break;
      case 'cutlery':
        typeIcon = Icons.restaurant;
        break;
      default:
        typeIcon = Icons.help_outline;
    }

    final isPending = status == 'pending';
    final isAcknowledged = status == 'acknowledged' || status == 'in_progress';
    final isResolved = status == 'resolved';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(
            color: priorityColor,
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(typeIcon, color: priorityColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                requestType.toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
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
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: priorityColor),
                                ),
                                child: Text(
                                  priority.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: priorityColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Table $tableNumber • ${_formatTimeAgo(createdAt)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                              ),
                              if (_getCustomerName(request).isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 12,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _getCustomerName(request),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                              if (_getOrderId(request) != 'N/A') ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Order: ${_getOrderId(request)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isResolved)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: AppColors.success,
                          size: 20,
                        ),
                      ),
                  ],
                ),
                if (description.isNotEmpty ||
                    (request['customerNotes'] != null &&
                        request['customerNotes']
                            .toString()
                            .trim()
                            .isNotEmpty)) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.message_outlined,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            description.isNotEmpty
                                ? description
                                : (request['customerNotes']
                                        ?.toString()
                                        .trim() ??
                                    ''),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action Buttons
          if (!isResolved)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardBorder.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  if (isPending) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isReadOnlyLocked
                            ? null
                            : () => _acknowledgeRequest(
                                  request['_id'] ?? request['id'],
                                ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text(
                          'Acknowledge',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isReadOnlyLocked
                            ? null
                            : () => _resolveRequest(
                                  request['_id'] ?? request['id'],
                                ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text(
                          'Resolve',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ] else if (isAcknowledged) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isReadOnlyLocked
                            ? null
                            : () => _resolveRequest(
                                  request['_id'] ?? request['id'],
                                ),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text(
                          'Mark Complete',
                          style: TextStyle(fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}



