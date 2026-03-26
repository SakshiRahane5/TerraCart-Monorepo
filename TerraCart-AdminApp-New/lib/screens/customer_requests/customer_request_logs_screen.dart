import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../services/customer_request_service.dart';
import '../../services/socket_service.dart';
import '../../core/exceptions/api_exception.dart';

class CustomerRequestLogsScreen extends StatefulWidget {
  const CustomerRequestLogsScreen({super.key});

  @override
  State<CustomerRequestLogsScreen> createState() => _CustomerRequestLogsScreenState();
}

class _CustomerRequestLogsScreenState extends State<CustomerRequestLogsScreen> {
  final CustomerRequestService _requestService = CustomerRequestService();
  final SocketService _socketService = SocketService();
  Map<String, List<Map<String, dynamic>>> _requestsByDate = {};
  List<String> _dateKeys = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRequestLogs();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _removeSocketListeners();
    super.dispose();
  }

  void _setupSocketListeners() {
    // Listen to request events to refresh logs
    _socketService.on('request:created', (_) {
      if (mounted) _loadRequestLogs(showLoading: false);
    }, debounce: true);
    
    _socketService.on('request:resolved', (_) {
      if (mounted) _loadRequestLogs(showLoading: false);
    }, debounce: true);
    
    _socketService.on('request:acknowledged', (_) {
      if (mounted) _loadRequestLogs(showLoading: false);
    }, debounce: true);
  }

  void _removeSocketListeners() {
    _socketService.off('request:created');
    _socketService.off('request:resolved');
    _socketService.off('request:acknowledged');
  }

  Future<void> _loadRequestLogs({bool showLoading = true}) async {
    if (!mounted) return;
    
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // Fetch all requests including resolved ones
      final requests = await _requestService.getRequests(
        status: null, // Get all requests
        limit: 500, // Get more requests for logs
      );
      
      if (mounted) {
        setState(() {
          // Convert to list
          final allRequests = (requests as List)
              .map((r) => r as Map<String, dynamic>)
              .toList();

          // Group requests by date
          _requestsByDate.clear();
          for (final request in allRequests) {
            final createdAt = request['createdAt'] ?? request['timestamp'];
            if (createdAt == null) continue;

            try {
              final dateTime = DateTime.parse(createdAt.toString());
              final dateKey = DateFormat('yyyy-MM-dd').format(dateTime);
              
              if (!_requestsByDate.containsKey(dateKey)) {
                _requestsByDate[dateKey] = [];
              }
              _requestsByDate[dateKey]!.add(request);
            } catch (e) {
              // Skip invalid dates
              continue;
            }
          }

          // Sort requests within each date (newest first)
          _requestsByDate.forEach((dateKey, requests) {
            requests.sort((a, b) {
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
          });

          // Sort date keys (newest first)
          _dateKeys = _requestsByDate.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is ApiException ? e.message : 'Failed to load request logs';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(String dateKey) {
    try {
      final date = DateTime.parse(dateKey);
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      
      if (date.year == today.year && 
          date.month == today.month && 
          date.day == today.day) {
        return 'Today';
      } else if (date.year == yesterday.year && 
                 date.month == yesterday.month && 
                 date.day == yesterday.day) {
        return 'Yesterday';
      } else {
        return DateFormat('MMM dd, yyyy').format(date);
      }
    } catch (e) {
      return dateKey;
    }
  }

  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      return DateTimeUtils.formatTimeIST(DateTime.parse(dateTimeStr));
    } catch (e) {
      return '';
    }
  }

  String _getTableNumber(Map<String, dynamic> request) {
    if (request['tableId'] != null) {
      if (request['tableId'] is Map) {
        return request['tableId']['number']?.toString() ?? 
               request['tableId']['tableNumber']?.toString() ?? 'N/A';
      }
    }
    if (request['table'] != null && request['table'] is Map) {
      return request['table']['number']?.toString() ?? 
             request['table']['tableNumber']?.toString() ?? 'N/A';
    }
    return 'N/A';
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppColors.warning;
      case 'acknowledged':
      case 'in_progress':
        return AppColors.info;
      case 'resolved':
      case 'completed':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending;
      case 'acknowledged':
      case 'in_progress':
        return Icons.hourglass_empty;
      case 'resolved':
      case 'completed':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Request Logs'),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Request Logs'),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded),
          ),
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
                onPressed: () => _loadRequestLogs(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Logs'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          IconButton(
            onPressed: () => _loadRequestLogs(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh logs',
          ),
        ],
      ),
      body: _requestsByDate.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No request logs found',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _loadRequestLogs(),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _dateKeys.length,
                itemBuilder: (context, dateIndex) {
                  final dateKey = _dateKeys[dateIndex];
                  final requests = _requestsByDate[dateKey] ?? [];
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date Header
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 20,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatDate(dateKey),
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${requests.length} ${requests.length == 1 ? 'request' : 'requests'}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Requests for this date
                      ...requests.map((request) => _buildLogCard(request))
                          .toList(),
                      if (dateIndex < _dateKeys.length - 1)
                        const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> request) {
    final status = (request['status'] ?? 'pending').toString();
    final requestType = (request['requestType'] ?? 'service').toString();
    final tableNumber = _getTableNumber(request);
    final createdAt = request['createdAt'] ?? request['timestamp'];
    final resolvedAt = request['resolvedAt'] ?? request['completedAt'];
    final description = request['description'] ?? request['customerNotes'] ?? '';
    final isResolved = status == 'resolved' || status == 'completed';
    final statusColor = _getStatusColor(status);

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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(typeIcon, color: statusColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              requestType.toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getStatusIcon(status),
                                  size: 12,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Table $tableNumber • ${_formatTime(createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      if (isResolved && resolvedAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Resolved at ${_formatTime(resolvedAt)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardBorder.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.message_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn().slideX(begin: 0.05);
  }
}



