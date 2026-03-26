import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../services/compliance_service.dart';
import '../../services/socket_service.dart';
import '../../core/exceptions/api_exception.dart';

class ComplianceScreen extends StatefulWidget {
  const ComplianceScreen({super.key});

  @override
  State<ComplianceScreen> createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> {
  final ComplianceService _complianceService = ComplianceService();
  final SocketService _socketService = SocketService();

  List<Map<String, dynamic>> _documents = [];
  Map<String, dynamic> _stats = {
    'valid': 0,
    'expiringSoon': 0,
    'expired': 0,
  };
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadComplianceData();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _removeSocketListeners();
    super.dispose();
  }

  void _setupSocketListeners() {
    _socketService.on('compliance:created', (_) => _loadComplianceData());
    _socketService.on('compliance:updated', (_) => _loadComplianceData());
    _socketService.on('compliance:deleted', (_) => _loadComplianceData());
  }

  void _removeSocketListeners() {
    _socketService.off('compliance:created');
    _socketService.off('compliance:updated');
    _socketService.off('compliance:deleted');
  }

  Future<void> _loadComplianceData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait([
        _complianceService.getAllCompliance(limit: 100),
        _complianceService.getComplianceStats(),
      ]);

      if (mounted) {
        setState(() {
          _documents = List<Map<String, dynamic>>.from(results[0] as List);
          _stats = Map<String, dynamic>.from(results[1] as Map);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e is ApiException ? e.message : 'Failed to load compliance data';
          _isLoading = false;
        });
      }
    }
  }

  IconData _getIconForType(String? type) {
    switch (type?.toLowerCase()) {
      case 'fssai':
      case 'license':
        return Icons.verified;
      case 'health':
      case 'health_certificate':
        return Icons.health_and_safety;
      case 'trade':
      case 'trade_license':
        return Icons.business;
      case 'fire':
      case 'fire_noc':
        return Icons.local_fire_department;
      case 'gst':
      case 'gst_registration':
        return Icons.receipt_long;
      default:
        return Icons.description;
    }
  }

  String _getStatusFromDocument(Map<String, dynamic> doc) {
    final status = doc['status']?.toString().toLowerCase() ?? '';
    if (status == 'expired') return 'Expired';
    if (status == 'expiring_soon' || status == 'expiring') return 'Expiring';
    return 'Valid';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Valid':
        return AppColors.success;
      case 'Expiring':
        return AppColors.warning;
      case 'Expired':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Compliance Documents'),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Compliance Documents'),
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
                onPressed: _loadComplianceData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final expiredCount = _stats['expired'] ?? 0;
    final expiringCount = _stats['expiringSoon'] ?? 0;
    final hasAlerts = expiredCount > 0 || expiringCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compliance Documents'),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
        actions: [
          IconButton(
            onPressed: _loadComplianceData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadComplianceData,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        context,
                        'Valid',
                        (_stats['valid'] ?? 0).toString(),
                        AppColors.success,
                        Icons.check_circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        context,
                        'Expiring',
                        expiringCount.toString(),
                        AppColors.warning,
                        Icons.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        context,
                        'Expired',
                        expiredCount.toString(),
                        AppColors.error,
                        Icons.error,
                      ),
                    ),
                  ],
                ).animate().fadeIn(),

                if (hasAlerts) ...[
                  const SizedBox(height: 24),
                  // Alert Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.warning_amber,
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Action Required',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.error,
                                ),
                              ),
                              Text(
                                '$expiredCount document${expiredCount != 1 ? 's' : ''} expired, $expiringCount expiring soon',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms),
                ],

                const SizedBox(height: 24),

                // Documents List
                Text(
                  'All Documents',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),

                if (_documents.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 64,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No compliance documents found',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                    itemCount: _documents.length,
                    itemBuilder: (context, index) {
                      final doc = _documents[index];
                      return _buildDocumentCard(context, doc)
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: 200 + (index * 50)));
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'compliance_fab',
        onPressed: () {
          // TODO: Navigate to add document screen
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add document feature coming soon')),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Document'),
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String label,
    String count,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            count,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(BuildContext context, Map<String, dynamic> doc) {
    final status = _getStatusFromDocument(doc);
    final statusColor = _getStatusColor(status);
    IconData statusIcon;

    switch (status) {
      case 'Valid':
        statusIcon = Icons.check_circle;
        break;
      case 'Expiring':
        statusIcon = Icons.warning;
        break;
      case 'Expired':
        statusIcon = Icons.error;
        break;
      default:
        statusIcon = Icons.help_outline;
    }

    DateTime? expiryDate;
    if (doc['expiryDate'] != null) {
      if (doc['expiryDate'] is String) {
        expiryDate = DateTime.tryParse(doc['expiryDate']);
      } else if (doc['expiryDate'] is DateTime) {
        expiryDate = doc['expiryDate'] as DateTime;
      }
    }
    String expiryText = 'No expiry';
    if (expiryDate != null) {
      final daysLeft = expiryDate.difference(DateTime.now()).inDays;
      if (daysLeft < 0) {
        expiryText = 'Expired ${-daysLeft} days ago';
      } else if (daysLeft == 0) {
        expiryText = 'Expires today';
      } else {
        expiryText = 'Expires in $daysLeft days';
      }
    }

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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getIconForType(doc['type']),
                        color: statusColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc['title'] ?? doc['name'] ?? 'Untitled',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (doc['type'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              doc['type'].toString().toUpperCase(),
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            status,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.cardBorder.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Expiry Date',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              expiryDate != null
                                  ? DateFormat('dd MMM yyyy').format(expiryDate)
                                  : 'N/A',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Status',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              expiryText,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (status != 'Valid')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.visibility),
                      label: const Text('View'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.refresh),
                      label: const Text('Renew'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: statusColor,
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


