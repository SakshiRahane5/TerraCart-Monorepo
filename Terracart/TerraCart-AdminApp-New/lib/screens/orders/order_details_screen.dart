import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_time_utils.dart';
import '../../core/exceptions/api_exception.dart';
import '../../models/order_model.dart';
import '../../providers/app_provider.dart';
import '../../services/print_service.dart';
import '../../services/order_service.dart';

class OrderDetailsScreen extends StatefulWidget {
  final OrderModel order;

  const OrderDetailsScreen({
    super.key,
    required this.order,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  // ignore: unused_field
  final OrderService _orderService = OrderService();
  late OrderModel _order;
  // ignore: unused_field
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return AppColors.warning;
      case 'preparing':
        return AppColors.info;
      case 'ready':
        return AppColors.success;
      case 'served':
        return AppColors.primary;
      case 'paid':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatDateTime(DateTime dateTime) =>
      DateTimeUtils.formatDateTimeIST(dateTime);

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final role = appProvider.userRole;
    final isReadOnlyLocked = appProvider.isReadOnlyAfterCheckout;
    final canPrint = role == 'manager' || role == 'waiter' || role == 'captain';
    /*
    final canAcceptTakeaway = !isReadOnlyLocked &&
        (role == 'waiter' || role == 'captain' || role == 'manager') &&
        _order.acceptedBy?.employeeId == null &&
        !['paid', 'cancelled', 'returned']
            .contains(_order.status.toLowerCase());
    */
    // Accept-order assignment flow disabled.
    // final canAcceptTakeaway = false;

    final items = _order.activeItems;
    final addons = _order.selectedAddons
        .where((addon) => addon.quantity > 0)
        .toList(growable: false);
    final subtotal = _order.subtotalAmount;
    final total = _order.totalAmount;

    // Extract table number safely
    String tableNumber = 'N/A';
    if (_order.tableNumber != null && _order.tableNumber!.isNotEmpty) {
      tableNumber = _order.tableNumber!;
    } else if (_order.tableId != null) {
      if (_order.tableId is Map) {
        final tableMap = _order.tableId as Map;
        final num = tableMap['tableNumber'] ?? tableMap['number'];
        if (num != null) {
          tableNumber = num.toString();
        }
      }
    }

    final serviceType = (_order.serviceType).toUpperCase();
    final orderType = (_order.orderType ?? '').toUpperCase();
    final isOfficeOrder =
        (_order.sourceQrType ?? '').toUpperCase() == 'OFFICE' ||
            (_order.officeName ?? '').trim().isNotEmpty;
    final isTakeawayLike = serviceType == 'TAKEAWAY' ||
        serviceType == 'PICKUP' ||
        serviceType == 'DELIVERY' ||
        (serviceType.isEmpty &&
            (orderType == 'PICKUP' || orderType == 'DELIVERY'));
    final serviceLabel = serviceType == 'DINE_IN'
        ? 'Dine-In'
        : serviceType == 'DELIVERY' || orderType == 'DELIVERY'
            ? (isOfficeOrder ? 'Office' : 'Delivery')
            : serviceType == 'PICKUP' || orderType == 'PICKUP'
                ? 'Pickup'
                : isOfficeOrder
                    ? 'Office'
                    : isTakeawayLike
                        ? 'Takeaway'
                        : 'Dine-In';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isReadOnlyLocked) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
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
            ],
            // Order Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order #${_order.id}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDateTime(_order.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _order.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Order Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.cardBorder.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    context,
                    'Service Type',
                    serviceLabel,
                    icon: isTakeawayLike
                        ? Icons.shopping_bag
                        : Icons.table_restaurant,
                  ),
                  if (!isTakeawayLike) ...[
                    const Divider(height: 24),
                    _buildInfoRow(
                      context,
                      'Table',
                      tableNumber,
                      icon: Icons.table_restaurant,
                    ),
                  ],
                  if (_order.takeawayToken != null) ...[
                    const Divider(height: 24),
                    _buildInfoRow(
                      context,
                      'Token',
                      _order.takeawayToken.toString(),
                      icon: Icons.confirmation_number_outlined,
                      valueColor: AppColors.warning,
                    ),
                  ],
                  const Divider(height: 24),
                  _buildInfoRow(
                    context,
                    'Status',
                    _order.status,
                    icon: Icons.info_outline,
                    valueColor: _getStatusColor(_order.status),
                  ),
                  if (_order.assignedStaff?.name != null) ...[
                    const Divider(height: 24),
                    _buildInfoRow(
                      context,
                      'Assigned To',
                      _order.assignedStaff!.name!,
                      icon: Icons.person,
                      valueColor: AppColors.success,
                    ),
                    if (_order.assignedStaff!.disability != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _buildInfoRow(
                          context,
                          'Disability Support',
                          _order.assignedStaff!.disability!,
                          icon: Icons.accessibility_new,
                        ),
                      ),
                  ],
                  if (_order.specialInstructions.trim().isNotEmpty) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Icon(
                          Icons.sticky_note_2_outlined,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'KOT Note',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _order.specialInstructions.trim(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Accept-order assignment flow disabled.
            /*
            if (canAcceptTakeaway) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAccepting ? null : () => _acceptTakeawayOrder(),
                  icon: _isAccepting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_isAccepting ? 'Accepting...' : 'Accept Order'),
                ),
              ),
            ],
            */

            const SizedBox(height: 20),

            // Order Items
            Text(
              'Order Items',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            if (items.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.cardBorder.withValues(alpha: 0.3),
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final itemPrice = item.unitPrice;
                    final lineTotal = item.lineTotal;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Qty: ${item.quantity} x \u20B9${itemPrice.toStringAsFixed(2)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                                if (item.extras.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  for (final extra in item.extras)
                                    Text(
                                      '+ ${extra.name} (\u20B9${extra.price.toStringAsFixed(2)})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                ],
                                if (item.addOns.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  for (final addOn in item.addOns)
                                    Text(
                                      '(+) ${addOn.name} (\u20B9${addOn.price.toStringAsFixed(2)})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                    ),
                                ],
                                if (item.note.trim().isNotEmpty ||
                                    item.specialInstructions.trim().isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(top: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.warning
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.note.trim().isNotEmpty
                                          ? 'Note: ${item.note.trim()}'
                                          : 'Note: ${item.specialInstructions.trim()}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.warning,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '\u20B9${lineTotal.toStringAsFixed(2)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.cardBorder.withValues(alpha: 0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    'No items in this order',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ),

            if (addons.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Add-ons',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.cardBorder.withValues(alpha: 0.3),
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: addons.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final addon = addons[index];
                    final lineTotal = addon.lineTotal;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '(+) ${addon.name}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Qty: ${addon.quantity} x \u20B9${addon.price.toStringAsFixed(2)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '\u20B9${lineTotal.toStringAsFixed(2)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Bill Summary
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.warmGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Bill Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildBillRow(
                    context,
                    'Subtotal',
                    '\u20B9${subtotal.toStringAsFixed(2)}',
                  ),
                  // GST removed for now:
                  // _buildBillRow(context, 'GST (5%)', '\u20B9${gst.toStringAsFixed(2)}'),
                  const Divider(
                    color: Colors.white,
                    thickness: 1,
                    height: 24,
                  ),
                  _buildBillRow(
                    context,
                    'Total',
                    '\u20B9${total.toStringAsFixed(2)}',
                    isTotal: true,
                  ),
                ],
              ),
            ),

            // Reprint (Manager, Waiter, Captain)
            if (canPrint && _order.kotLines.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Reprint',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reprint(context, isKot: true),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Reprint KOT'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reprint(context, isKot: false),
                      icon: const Icon(Icons.receipt),
                      label: const Text('Reprint Bill'),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _reprint(BuildContext context, {required bool isKot}) async {
    final orderMap = _order.toJson();
    orderMap['_id'] = _order.id;
    orderMap['printStatus'] = {
      'kotPrinted': _order.kotPrinted,
      'billPrinted': _order.billPrinted,
    };
    orderMap['takeawayToken'] = _order.takeawayToken;
    orderMap['customerName'] = _order.customerName;
    orderMap['customerMobile'] = _order.customerMobile;

    try {
      if (isKot) {
        await PrintService().reprintKot(orderMap);
      } else {
        await PrintService().reprintBill(orderMap);
      }
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
            content: Text(e is ApiException ? e.message : 'Print failed'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ignore: unused_element
  Future<void> _acceptTakeawayOrder() async {
    // Accept-order assignment flow disabled.
    /*
    if (_isAccepting) return;

    setState(() {
      _isAccepting = true;
    });

    try {
      final acceptedOrder = await _orderService.acceptOrder(_order.id);
      if (!mounted) return;
      setState(() {
        _order = acceptedOrder;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order accepted by you'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Failed to accept order';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
        });
      }
    }
    */
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    IconData? icon,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
        ),
      ],
    );
  }

  Widget _buildBillRow(
    BuildContext context,
    String label,
    String value, {
    bool isTotal = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            color: Colors.white,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
