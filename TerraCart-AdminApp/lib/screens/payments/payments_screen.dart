import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/order_alert_payload_parser.dart';
import '../../core/utils/date_time_utils.dart';
import '../../providers/app_provider.dart';
import '../../services/payment_service.dart';
import '../../services/order_service.dart';
import '../../services/print_service.dart';
import '../../services/socket_service.dart';
import '../../core/exceptions/api_exception.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final PaymentService _paymentService = PaymentService();
  final OrderService _orderService = OrderService();
  final SocketService _socketService = SocketService();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _filterStatus = 'ALL';
  String? _busyId;
  bool _isRealtimeSyncInFlight = false;
  String? _lastNotifiedPaymentId;
  DateTime? _lastPaymentRequestAt;
  Timer? _realtimeFallbackTimer;

  @override
  void initState() {
    super.initState();
    _loadPayments();
    _setupSocketListeners();
    _startRealtimeFallbackPoll();
  }

  @override
  void dispose() {
    _realtimeFallbackTimer?.cancel();
    _removeSocketListeners();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPayments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final payments = await _paymentService.getPayments();
      if (mounted) {
        setState(() {
          _payments = payments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              e is ApiException ? e.message : 'Failed to load payments';
          _isLoading = false;
        });
      }
    }
  }

  void _setupSocketListeners() {
    _socketService.on('paymentCreated', _onPaymentCreated,
        debounce: true, delay: const Duration(milliseconds: 300));
    _socketService.on('paymentUpdated', _onPaymentUpdated,
        debounce: true, delay: const Duration(milliseconds: 300));
    _socketService.on('connect', _onSocketConnected);
    _socketService.on('reconnect', _onSocketConnected);
  }

  void _removeSocketListeners() {
    _socketService.off('paymentCreated', _onPaymentCreated);
    _socketService.off('paymentUpdated', _onPaymentUpdated);
    _socketService.off('connect', _onSocketConnected);
    _socketService.off('reconnect', _onSocketConnected);
  }

  void _onSocketConnected(dynamic _) {
    _refreshPaymentsFromSocket();
  }

  void _onPaymentCreated(dynamic data) {
    if (!_isSocketPayloadForCurrentCart(data)) return;
    _refreshPaymentsFromSocket();
    _showPaymentRequestNotificationIfNeeded(data);
  }

  void _onPaymentUpdated(dynamic data) {
    if (!_isSocketPayloadForCurrentCart(data)) return;
    _refreshPaymentsFromSocket();
  }

  bool _isSocketPayloadForCurrentCart(dynamic payload) {
    final currentCartId =
        Provider.of<AppProvider>(context, listen: false).currentCartId?.trim();
    if (currentCartId == null || currentCartId.isEmpty) {
      return true;
    }

    final incomingCartId = OrderAlertPayloadParser.extractCartId(payload)?.trim();
    if (incomingCartId == null || incomingCartId.isEmpty) {
      // Keep backward compatibility for legacy socket payloads without cartId.
      return true;
    }

    return incomingCartId == currentCartId;
  }

  void _startRealtimeFallbackPoll() {
    _realtimeFallbackTimer?.cancel();
    _realtimeFallbackTimer =
        Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || _isRealtimeSyncInFlight) {
        return;
      }
      _refreshPaymentsFromSocket();
    });
  }

  Future<void> _refreshPaymentsFromSocket() async {
    if (!mounted || _isRealtimeSyncInFlight) return;
    _isRealtimeSyncInFlight = true;
    try {
      final payments = await _paymentService.getPayments();
      if (!mounted) return;
      setState(() {
        _payments = payments;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (_) {
      // Silent fail for socket refresh; manual refresh remains available.
    } finally {
      _isRealtimeSyncInFlight = false;
    }
  }

  void _showPaymentRequestNotificationIfNeeded(dynamic payload) {
    if (!mounted || payload is! Map) return;
    final map = Map<String, dynamic>.from(payload);
    final method = (map['method'] ?? '').toString().trim().toUpperCase();
    final status = (map['status'] ?? '').toString().trim().toUpperCase();
    if (method != 'ONLINE' || !(status == 'PENDING' || status == 'PROCESSING')) {
      return;
    }

    final paymentId =
        (map['id'] ?? map['_id'] ?? map['paymentId'] ?? '').toString().trim();
    final now = DateTime.now();
    if (paymentId.isNotEmpty &&
        _lastNotifiedPaymentId == paymentId &&
        _lastPaymentRequestAt != null &&
        now.difference(_lastPaymentRequestAt!) < const Duration(seconds: 3)) {
      return;
    }

    _lastNotifiedPaymentId = paymentId.isEmpty ? _lastNotifiedPaymentId : paymentId;
    _lastPaymentRequestAt = now;

    final message = (map['body'] ?? '').toString().trim().isNotEmpty
        ? (map['body'] ?? '').toString().trim()
        : 'New online payment request received';

    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    scaffoldMessenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.info,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _matchesSearch(Map<String, dynamic> p, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();
    final id = (p['id'] ?? p['_id'] ?? '').toString().toLowerCase();
    final orderId = (p['orderId'] ?? '').toString().toLowerCase();
    final amount = (p['amount'] ?? 0).toString();
    final description = (p['description'] ?? '').toString().toLowerCase();
    final method = (p['method'] ?? '').toString().toLowerCase();
    final status = (p['status'] ?? '').toString().toLowerCase();
    String dateStr = '';
    if (p['createdAt'] != null) {
      try {
        dateStr = DateTimeUtils.formatDateTimeIST(
                DateTime.parse(p['createdAt'].toString()), 'dd MMM yyyy HH:mm')
            .toLowerCase();
      } catch (_) {}
    }
    return id.contains(q) ||
        orderId.contains(q) ||
        amount.contains(q) ||
        description.contains(q) ||
        method.contains(q) ||
        status.contains(q) ||
        dateStr.contains(q);
  }

  List<Map<String, dynamic>> get _filteredPayments {
    var filtered = _payments;
    switch (_filterStatus) {
      case 'ACTIVE':
        filtered = filtered
            .where((p) =>
                ['PENDING', 'PROCESSING', 'CASH_PENDING'].contains(p['status']))
            .toList();
        break;
      case 'PAID':
        filtered = filtered.where((p) => p['status'] == 'PAID').toList();
        break;
      case 'CANCELLED':
        filtered = filtered
            .where((p) => ['CANCELLED', 'FAILED'].contains(p['status']))
            .toList();
        break;
    }
    final query = _searchController.text;
    if (query.isNotEmpty) {
      filtered = filtered.where((p) => _matchesSearch(p, query)).toList();
    }
    return filtered;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'PENDING':
      case 'PROCESSING':
      case 'CASH_PENDING':
        return AppColors.warning;
      case 'PAID':
        return AppColors.success;
      case 'CANCELLED':
      case 'FAILED':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _markPaid(Map<String, dynamic> payment) async {
    final id = payment['id']?.toString() ?? payment['_id']?.toString();
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Paid'),
        content: Text(
            'Mark payment ${id.length > 8 ? id.substring(0, 8) : id} as paid?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mark Paid')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busyId = id);
    try {
      await _paymentService.markPaymentPaid(id);
      await _loadPayments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Payment marked as paid'),
              backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is ApiException ? e.message : 'Failed'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _cancelPayment(Map<String, dynamic> payment) async {
    final id = payment['id']?.toString() ?? payment['_id']?.toString();
    if (id == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: 'Cancelled by admin');
        return AlertDialog(
          title: const Text('Cancel Payment'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
            maxLines: 2,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Cancel Payment')),
          ],
        );
      },
    );
    if (reason == null) return;
    setState(() => _busyId = id);
    try {
      await _paymentService.cancelPayment(id,
          reason: reason.isEmpty ? null : reason);
      await _loadPayments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Payment cancelled'),
              backgroundColor: AppColors.warning),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is ApiException ? e.message : 'Failed'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _syncPaid() async {
    try {
      await _paymentService.syncPaidPayments();
      await _loadPayments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Synced paid orders'),
              backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e is ApiException ? e.message : 'Failed'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _getOrderIdFromPayment(Map<String, dynamic> payment) {
    final o = payment['orderId'];
    if (o == null) return '';
    if (o is Map && (o['_id'] != null || o['id'] != null)) {
      return (o['_id'] ?? o['id']).toString();
    }
    return o.toString();
  }

  String _getTokenNumberFromPayment(Map<String, dynamic> payment) {
    final directToken = payment['tokenNumber'] ?? payment['takeawayToken'];
    if (directToken != null) {
      final token = directToken.toString().trim();
      if (token.isNotEmpty && token != 'null') return token;
    }

    final metadata = payment['metadata'];
    if (metadata is Map) {
      final metadataMap = Map<String, dynamic>.from(metadata);
      final metaToken =
          metadataMap['takeawayToken'] ?? metadataMap['tokenNumber'];
      if (metaToken != null) {
        final token = metaToken.toString().trim();
        if (token.isNotEmpty && token != 'null') return token;
      }
    }

    return '';
  }

  Future<void> _printBillForPayment(
      BuildContext context, String orderIdStr) async {
    if (orderIdStr.isEmpty || orderIdStr == '-') return;
    try {
      final order = await _orderService.getOrderById(orderIdStr);
      final orderMap = order.toJson();
      orderMap['_id'] = order.id;
      orderMap['printStatus'] = {
        'kotPrinted': order.kotPrinted,
        'billPrinted': order.billPrinted,
      };
      orderMap['takeawayToken'] = order.takeawayToken;
      orderMap['customerName'] = order.customerName;
      orderMap['customerMobile'] = order.customerMobile;
      await PrintService().reprintBill(orderMap);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Print sent to printer'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(e is ApiException ? e.message : 'Failed to load order'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showPaymentDetails(Map<String, dynamic> payment) {
    final id = payment['id']?.toString() ?? payment['_id']?.toString() ?? '';
    final orderId = _getOrderIdFromPayment(payment);
    final tokenNumber = _getTokenNumberFromPayment(payment);
    final amount = (payment['amount'] ?? 0).toDouble();
    final method = payment['method']?.toString() ?? '-';
    final status = payment['status']?.toString() ?? '-';
    final description = payment['description']?.toString() ?? '-';
    String createdAt = '-';
    if (payment['createdAt'] != null) {
      try {
        createdAt = DateTimeUtils.formatDateTimeIST(
            DateTime.parse(payment['createdAt'].toString()));
      } catch (_) {}
    }
    String paidAt = '-';
    if (payment['paidAt'] != null) {
      try {
        paidAt = DateTimeUtils.formatDateTimeIST(
            DateTime.parse(payment['paidAt'].toString()));
      } catch (_) {}
    }
    String cancelledAt = '-';
    if (payment['cancelledAt'] != null) {
      try {
        cancelledAt = DateTimeUtils.formatDateTimeIST(
            DateTime.parse(payment['cancelledAt'].toString()));
      } catch (_) {}
    }
    final cancellationReason = payment['cancellationReason']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 24,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.receipt_long,
                        color: _getStatusColor(status), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\u20B9${amount.toStringAsFixed(0)}',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                _getStatusColor(status).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(status),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailRow('Payment ID',
                  id.length > 12 ? '${id.substring(0, 12)}...' : id),
              _buildDetailRow('Order ID', orderId),
              if (tokenNumber.isNotEmpty)
                _buildDetailRow('Token No', tokenNumber),
              _buildDetailRow('Amount', '\u20B9${amount.toStringAsFixed(2)}'),
              _buildDetailRow('Method', method),
              if (description.isNotEmpty)
                _buildDetailRow('Description', description),
              _buildDetailRow('Created', createdAt),
              if (status == 'PAID') _buildDetailRow('Paid At', paidAt),
              if (['CANCELLED', 'FAILED'].contains(status)) ...[
                _buildDetailRow('Cancelled At', cancelledAt),
                if (cancellationReason.isNotEmpty)
                  _buildDetailRow('Reason', cancellationReason),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  if (['PENDING', 'PROCESSING', 'CASH_PENDING']
                      .contains(status)) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _markPaid(payment);
                        },
                        icon: const Icon(Icons.check_circle, size: 20),
                        label: const Text('Mark Paid'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.success,
                          side: const BorderSide(color: AppColors.success),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _cancelPayment(payment);
                        },
                        icon: const Icon(Icons.cancel, size: 20),
                        label: const Text('Cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                      ),
                    ),
                  ] else ...[
                    if (orderId.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await _printBillForPayment(context, orderId);
                          },
                          icon: const Icon(Icons.print, size: 20),
                          label: const Text('Print Bill'),
                        ),
                      ),
                    if (orderId.isNotEmpty) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadPayments),
          IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _isLoading ? null : _syncPaid),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPayments,
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
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _loadPayments,
                            child: const Text('Retry')),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Search by date, name, ID, amount...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _filterStatus,
                              decoration: InputDecoration(
                                labelText: 'Status',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'ALL', child: Text('All')),
                                DropdownMenuItem(
                                    value: 'ACTIVE', child: Text('Active')),
                                DropdownMenuItem(
                                    value: 'PAID', child: Text('Paid')),
                                DropdownMenuItem(
                                    value: 'CANCELLED',
                                    child: Text('Cancelled/Failed')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _filterStatus = v ?? 'ALL'),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${_filteredPayments.length} payment(s)',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredPayments.length,
                          itemBuilder: (context, index) {
                            final p = _filteredPayments[index];
                            final id = p['id']?.toString() ??
                                p['_id']?.toString() ??
                                '';
                            final status = p['status']?.toString() ?? '';
                            final amount = (p['amount'] ?? 0).toDouble();
                            final method = p['method']?.toString() ?? '';
                            final orderId = p['orderId']?.toString() ?? '';
                            final tokenNumber = _getTokenNumberFromPayment(p);
                            final createdAt = p['createdAt'] != null
                                ? DateTimeUtils.formatShortDateTimeIST(
                                    DateTime.parse(p['createdAt'].toString()))
                                : '';
                            final isBusy = _busyId == id;
                            final canMarkPaid = [
                              'PENDING',
                              'PROCESSING',
                              'CASH_PENDING'
                            ].contains(status);
                            final canCancel = [
                              'PENDING',
                              'PROCESSING',
                              'CASH_PENDING'
                            ].contains(status);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                onTap: () => _showPaymentDetails(p),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.06),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: _getStatusColor(status)
                                          .withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(status)
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              method == 'CASH'
                                                  ? Icons.payments
                                                  : Icons.credit_card,
                                              color: _getStatusColor(status),
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Order ${orderId.length > 10 ? orderId.substring(0, 10) : orderId}',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (tokenNumber.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Token $tokenNumber',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color:
                                                              AppColors.primary,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                  ),
                                                ],
                                                const SizedBox(height: 4),
                                                Text(
                                                  createdAt,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: AppColors
                                                            .textSecondary,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '\u20B9${amount.toStringAsFixed(0)}',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _getStatusColor(status)
                                                      .withValues(alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  status,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        _getStatusColor(status),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Text(
                                            method,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                          ),
                                          const Spacer(),
                                          if (canMarkPaid)
                                            IconButton(
                                              icon: isBusy
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                              strokeWidth: 2),
                                                    )
                                                  : const Icon(
                                                      Icons.check_circle,
                                                      color: AppColors.success,
                                                      size: 22),
                                              onPressed: isBusy
                                                  ? null
                                                  : () => _markPaid(p),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                          if (canCancel) ...[
                                            if (canMarkPaid)
                                              const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.cancel,
                                                  color: AppColors.error,
                                                  size: 22),
                                              onPressed: isBusy
                                                  ? null
                                                  : () => _cancelPayment(p),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                                .animate()
                                .fadeIn(
                                    duration: 200.ms, delay: (index * 40).ms)
                                .slideY(begin: 0.05, end: 0, duration: 200.ms);
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
