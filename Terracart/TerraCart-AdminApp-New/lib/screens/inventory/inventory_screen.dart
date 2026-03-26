import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/exceptions/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_provider.dart';
import '../../services/inventory_service.dart';
import '../../services/socket_service.dart';

class _UnitConversionRule {
  const _UnitConversionRule({
    required this.base,
    required this.factor,
  });

  final String base;
  final double factor;
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  final InventoryService _inventoryService = InventoryService();
  final SocketService _socketService = SocketService();
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;

  List<Map<String, dynamic>> _inventoryItems = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoadingInventory = true;
  bool _isLoadingTransactions = false;
  bool _transactionsLoaded = false;
  bool _isRefreshing = false;
  String? _inventoryError;
  String? _transactionsError;

  static const List<String> _uomOptions = <String>[
    'kg',
    'g',
    'l',
    'ml',
    'pcs',
    'pack',
    'box',
    'bottle',
    'dozen',
  ];
  static const List<String> _categoryOptions = <String>[
    'Vegetables',
    'Dairy',
    'Meat & Poultry',
    'Grains & Staples',
    'Spices & Seasoning',
    'Cooking Oils & Ghee',
    'Bread, Buns & Rotis',
    'Snacks Ingredients',
    'Packaged Items',
    'Beverages',
    'Cleaning Supplies',
    'Packaging Materials',
    'Disposable Items',
    'Prepared Items',
    'Pre-mixes',
    'Other',
  ];
  static const List<String> _storageOptions = <String>[
    'Dry Storage',
    'Cold Storage',
    'Frozen Storage',
    'Vegetables Section',
    'Packaging Supplies',
    'Cleaning Supplies',
    'Other',
  ];
  static const List<String> _wasteReasonOptions = <String>[
    'Spoilage',
    'Expired',
    'Overproduction',
    'Quality Issue',
    'Damage',
    'Other',
  ];

  static const List<String> _consumeRefTypes = <String>[
    'manual',
    'recipe',
    'waste',
    'adjustment',
  ];

  static const List<String> _refreshEvents = <String>[
    'inventory:created',
    'inventory:updated',
    'inventory:deleted',
    'inventory:stock_updated',
    'ingredient:created',
    'ingredient:updated',
    'purchase:received',
    'waste:recorded',
    'inventory:consumed',
    'inventory:returned',
    'order:finalized',
  ];

  static const Map<String, _UnitConversionRule> _unitConversions =
      <String, _UnitConversionRule>{
    'kg': _UnitConversionRule(base: 'g', factor: 1000),
    'g': _UnitConversionRule(base: 'g', factor: 1),
    'l': _UnitConversionRule(base: 'ml', factor: 1000),
    'ml': _UnitConversionRule(base: 'ml', factor: 1),
    'pcs': _UnitConversionRule(base: 'pcs', factor: 1),
    'pack': _UnitConversionRule(base: 'pack', factor: 1),
    'box': _UnitConversionRule(base: 'box', factor: 1),
    'bottle': _UnitConversionRule(base: 'bottle', factor: 1),
    'dozen': _UnitConversionRule(base: 'pcs', factor: 12),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _loadInventory(showLoading: true);
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _removeSocketListeners();
    _searchController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1 &&
        !_tabController.indexIsChanging &&
        !_transactionsLoaded) {
      _loadTransactions(showLoading: true);
    }
  }

  void _setupSocketListeners() {
    for (final event in _refreshEvents) {
      _socketService.on(
        event,
        (_) {
          if (mounted) {
            _refreshFromBackend(includeTransactions: _transactionsLoaded);
          }
        },
        debounce: true,
        delay: const Duration(milliseconds: 400),
      );
    }

    _socketService.on(
      'order_status_updated',
      _onOrderStatusUpdated,
      debounce: true,
      delay: const Duration(milliseconds: 400),
    );
  }

  void _removeSocketListeners() {
    for (final event in _refreshEvents) {
      _socketService.off(event);
    }
    _socketService.off('order_status_updated');
  }

  void _onOrderStatusUpdated(dynamic data) {
    final payload = _asMap(data);
    final statusRaw =
        payload?['status'] ?? payload?['newStatus'] ?? payload?['orderStatus'];
    final status = statusRaw?.toString().trim().toUpperCase();

    // Refresh on PREPARING transitions; fallback refresh when payload shape is unknown.
    if (status == null || status.isEmpty || status == 'PREPARING') {
      if (mounted) {
        _refreshFromBackend(includeTransactions: _transactionsLoaded);
      }
    }
  }

  Future<void> _loadInventory({required bool showLoading}) async {
    if (showLoading) {
      setState(() {
        _isLoadingInventory = true;
        _inventoryError = null;
      });
    }

    try {
      final items = await _inventoryService.getInventoryItems();
      if (!mounted) return;
      setState(() {
        _inventoryItems = items;
        _inventoryError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inventoryError = _extractErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInventory = false;
        });
      }
    }
  }

  Future<void> _loadTransactions({required bool showLoading}) async {
    if (showLoading) {
      setState(() {
        _isLoadingTransactions = true;
        _transactionsError = null;
      });
    }

    try {
      final txns = await _inventoryService.getInventoryTransactions();
      if (!mounted) return;
      setState(() {
        _transactions = txns;
        _transactionsLoaded = true;
        _transactionsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _transactionsLoaded = true;
        _transactionsError = _extractErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTransactions = false;
        });
      }
    }
  }

  Future<void> _refreshFromBackend({required bool includeTransactions}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await _loadInventory(showLoading: false);
      if (includeTransactions) {
        await _loadTransactions(showLoading: false);
      }
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _refreshAfterMutation() async {
    await _loadInventory(showLoading: false);
    if (_transactionsLoaded || _tabController.index == 1) {
      await _loadTransactions(showLoading: false);
    }
  }

  String _extractErrorMessage(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return error.toString();
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  dynamic _pick(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value != null) return value;
    }
    return null;
  }

  bool _isBlankLikeToken(String text) {
    final normalized = text.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'null' ||
        normalized == 'nil' ||
        normalized == 'undefined' ||
        normalized == 'nan';
  }

  double? _parseNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final raw = value.toString().trim();
    if (_isBlankLikeToken(raw)) return null;
    final cleaned = raw.replaceAll(',', '');
    return double.tryParse(cleaned);
  }

  String? _normalizedUnit(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim().toLowerCase();
    if (_isBlankLikeToken(text)) return null;
    return text;
  }

  double? _convertUnit(double qty, String fromUom, String toUom) {
    final from = _unitConversions[fromUom.toLowerCase()];
    final to = _unitConversions[toUom.toLowerCase()];
    if (from == null || to == null) return null;
    if (from.base != to.base) return null;
    return (qty * from.factor) / to.factor;
  }

  String _baseUnitFromUom(String uom) {
    final normalized = uom.trim().toLowerCase();
    if (normalized == 'kg' || normalized == 'g') return 'g';
    if (normalized == 'l' || normalized == 'ml') return 'ml';
    return 'pcs';
  }

  String _formatQty(double qty) {
    return qty.toStringAsFixed(2);
  }

  String? _pickNonEmptyString(Map<String, dynamic> item, List<String> keys) {
    final value = _pick(item, keys);
    if (value == null) return null;
    final text = value.toString().trim();
    if (_isBlankLikeToken(text)) return null;
    return text;
  }

  String _textOrDash(dynamic value) {
    if (value == null) return '--';
    final text = value.toString().trim();
    return _isBlankLikeToken(text) ? '--' : text;
  }

  String _inventoryItemName(Map<String, dynamic> item) {
    final ingredient = _asMap(item['ingredient']);
    return _textOrDash(
      ingredient?['name'] ?? item['ingredientName'] ?? item['name'],
    );
  }

  String _inventoryStorage(Map<String, dynamic> item) {
    return _textOrDash(
      item['storageType'] ?? item['storageLocation'] ?? item['location'],
    );
  }

  String _inventoryUom(Map<String, dynamic> item) {
    return _textOrDash(item['uom'] ?? item['unit']);
  }

  String _stockText(Map<String, dynamic> item, String displayUomText) {
    final qty = _parseNumber(_pick(item, ['qtyOnHand', 'quantity']));
    if (qty == null) return '--';

    if (displayUomText == '--') {
      return _formatQty(qty);
    }

    final displayUom = _normalizedUnit(displayUomText);
    final baseUnit = _normalizedUnit(item['baseUnit']) ?? displayUom;

    double displayQty = qty;
    if (displayUom != null && baseUnit != null && baseUnit != displayUom) {
      final converted = _convertUnit(qty, baseUnit, displayUom);
      if (converted != null) {
        // Match web: rounded quantity in the ingredient display unit.
        displayQty = converted.roundToDouble();
      }
    } else {
      displayQty = qty.roundToDouble();
    }

    return '${_formatQty(displayQty)} $displayUomText';
  }

  String _quantityWithUom(dynamic qty, String uom) {
    final qtyText = _textOrDash(qty);
    if (qtyText == '--') return '--';
    if (uom == '--') return qtyText;
    return '$qtyText $uom';
  }

  String _currencySymbol(Map<String, dynamic> item) {
    final symbol = _pickNonEmptyString(item, ['currencySymbol', 'currency']);
    return symbol ?? '\u20B9';
  }

  String _weightedAvgCostText(Map<String, dynamic> item, String uom) {
    final displayReady = _pickNonEmptyString(item, [
      'weightedAvgCostDisplay',
      'weightedAvgCostFormatted',
      'weightedAvgCostText',
    ]);
    if (displayReady != null) {
      return displayReady;
    }

    final qtyOnHand = _parseNumber(_pick(item, ['qtyOnHand', 'quantity'])) ?? 0;
    final baseCost = _parseNumber(
            _pick(item, ['weightedAvgCost', 'currentCostPerBaseUnit'])) ??
        0;
    final symbol = _currencySymbol(item);
    final displayUom = _normalizedUnit(uom);

    if (displayUom == null || uom == '--') {
      if (baseCost <= 0) return '${symbol}0';
      return '$symbol${baseCost.toStringAsFixed(2)}';
    }

    // Match web behavior: if stock is zero, show zero cost in display uom.
    if (qtyOnHand <= 0 || baseCost <= 0) {
      return '${symbol}0 / $uom';
    }

    final baseUnit = _normalizedUnit(item['baseUnit']) ?? displayUom;
    final baseUnitsPerDisplayUnit = _convertUnit(1, displayUom, baseUnit);

    double unitPrice = 0;
    if (baseUnitsPerDisplayUnit != null) {
      unitPrice = baseCost * baseUnitsPerDisplayUnit;
    }

    if (unitPrice.isNaN || unitPrice.isInfinite || unitPrice < 0) {
      unitPrice = 0;
    }

    return '$symbol${unitPrice.toStringAsFixed(2)} / $uom';
  }

  String _totalValueText(Map<String, dynamic> item) {
    final displayReady = _pickNonEmptyString(item, [
      'totalValueDisplay',
      'totalValueFormatted',
      'totalValueText',
    ]);
    if (displayReady != null) {
      return displayReady;
    }

    double? totalValue =
        _parseNumber(_pick(item, ['totalValue', 'stockValue']));
    if (totalValue == null) {
      final qty = _parseNumber(_pick(item, ['qtyOnHand', 'quantity'])) ?? 0;
      final cost = _parseNumber(
              _pick(item, ['weightedAvgCost', 'currentCostPerBaseUnit'])) ??
          0;
      totalValue = qty > 0 && cost > 0 ? qty * cost : 0;
    }

    if (totalValue.isNaN || totalValue.isInfinite) {
      return '--';
    }

    final symbol = _currencySymbol(item);
    // Match web table display: integer rounded currency value.
    return '$symbol${totalValue.round()}';
  }

  String _shelfLifeText(Map<String, dynamic> item) {
    final shelfDisplay = _pickNonEmptyString(item, [
      'shelfLifeDisplay',
      'shelfLifeText',
    ]);
    if (shelfDisplay != null) return shelfDisplay;

    final shelfDays =
        _parseNumber(_pick(item, ['shelfLifeDays', 'shelfTimeDays']))?.toInt();
    if (shelfDays == null) return '--';

    final startDateRaw = _pickNonEmptyString(item, ['lastReceivedAt']);
    if (startDateRaw != null) {
      final startDate = DateTime.tryParse(startDateRaw)?.toLocal();
      if (startDate != null) {
        final start = DateTime(startDate.year, startDate.month, startDate.day);
        final expiry = start.add(Duration(days: shelfDays));
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final daysRemaining = expiry.difference(today).inDays;
        if (daysRemaining < 0) return 'Expired';
        if (daysRemaining == 0) return 'Expires today';
        return '$daysRemaining day${daysRemaining == 1 ? '' : 's'} left';
      }
    }

    return 'Shelf: $shelfDays day${shelfDays == 1 ? '' : 's'}';
  }

  String _statusText(Map<String, dynamic> item) {
    final status = _pickNonEmptyString(item, ['status']);
    if (status != null) return status;

    final isActive = item['isActive'];
    if (isActive is bool) {
      return isActive ? 'Active' : 'Inactive';
    }

    return 'Active';
  }

  Color _statusBackground(String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'active') {
      return const Color(0xFFE8F5E9);
    }
    return const Color(0xFFF5F5F5);
  }

  Color _statusForeground(String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'active') {
      return const Color(0xFF2E7D32);
    }
    return const Color(0xFF616161);
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    FontWeight? valueWeight,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: valueWeight ?? FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _transactionTypeBackground(String type) {
    final normalized = type.trim().toUpperCase();
    switch (normalized) {
      case 'IN':
        return const Color(0xFFE8F5E9);
      case 'OUT':
        return const Color(0xFFFFEBEE);
      case 'RETURN':
        return const Color(0xFFE3F2FD);
      case 'WASTE':
        return const Color(0xFFFFF8E1);
      default:
        return const Color(0xFFF5F5F5);
    }
  }

  Color _transactionTypeForeground(String type) {
    final normalized = type.trim().toUpperCase();
    switch (normalized) {
      case 'IN':
        return const Color(0xFF2E7D32);
      case 'OUT':
        return const Color(0xFFC62828);
      case 'RETURN':
        return const Color(0xFF1565C0);
      case 'WASTE':
        return const Color(0xFFEF6C00);
      default:
        return const Color(0xFF616161);
    }
  }

  Widget _buildTransactionTypeChip(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _transactionTypeBackground(type),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        type,
        style: TextStyle(
          color: _transactionTypeForeground(type),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String _transactionDateText(dynamic value) {
    if (value == null) return '--';
    final raw = value.toString().trim();
    if (raw.isEmpty) return '--';

    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;

    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  String _transactionItemName(Map<String, dynamic> txn) {
    final ingredient = _asMap(txn['ingredientId']);
    return _textOrDash(ingredient?['name'] ?? txn['itemName']);
  }

  String _transactionType(Map<String, dynamic> txn) {
    return _textOrDash(txn['type']);
  }

  String _transactionQuantity(Map<String, dynamic> txn) {
    final uom = _textOrDash(txn['uom']);
    return _quantityWithUom(txn['qty'], uom);
  }

  String _transactionCost(Map<String, dynamic> txn) {
    final displayReady = _pickNonEmptyString(txn, [
      'costAllocatedDisplay',
      'costAllocatedFormatted',
      'costAllocatedText',
    ]);
    if (displayReady != null) return displayReady;

    final rawCost = txn['costAllocated'];
    if (rawCost == null) return '--';
    final text = rawCost.toString().trim();
    if (text.isEmpty) return '--';
    if (text.contains('Rs') || text.contains('INR') || text.contains(r'$')) {
      return text;
    }

    final symbol = _currencySymbol(txn);
    return symbol.isEmpty ? text : '$symbol $text';
  }

  String? _transactionIngredientId(Map<String, dynamic> txn) {
    final ingredient = _asMap(txn['ingredientId']) ?? _asMap(txn['ingredient']);
    final rawId = ingredient?['_id'] ??
        ingredient?['id'] ??
        (txn['ingredientId'] is String ? txn['ingredientId'] : null) ??
        (txn['ingredient'] is String ? txn['ingredient'] : null);
    if (rawId == null) return null;
    final id = rawId.toString().trim();
    return id.isEmpty ? null : id;
  }

  String? _extractSupplierFromText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (_isBlankLikeToken(text)) return null;

    final bracketMatch = RegExp(
      r'\(Supplier:\s*([^)]+)\)',
      caseSensitive: false,
    ).firstMatch(text);
    if (bracketMatch != null) {
      final candidate = bracketMatch.group(1)?.trim();
      if (candidate != null &&
          candidate.isNotEmpty &&
          candidate.toLowerCase() != 'n/a') {
        return candidate;
      }
    }

    final directMatch = RegExp(
      r'Direct Purchase from\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (directMatch != null) {
      final candidate = directMatch.group(1)?.trim();
      if (candidate != null &&
          candidate.isNotEmpty &&
          candidate.toLowerCase() != 'n/a') {
        return candidate;
      }
    }

    return null;
  }

  String? _latestSupplierForIngredient(String ingredientId) {
    if (ingredientId.trim().isEmpty) return null;

    for (final txn in _transactions) {
      final txnIngredientId = _transactionIngredientId(txn);
      if (txnIngredientId != ingredientId) continue;

      final fromNotes = _extractSupplierFromText(txn['notes']) ??
          _extractSupplierFromText(txn['remarks']);
      if (fromNotes != null) return fromNotes;

      final fromFields = _pickNonEmptyString(
        txn,
        ['supplier', 'supplierName', 'vendor', 'vendorName'],
      );
      if (fromFields != null) return fromFields;
    }

    return null;
  }

  List<Map<String, dynamic>> get _filteredInventoryItems {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _inventoryItems;

    return _inventoryItems.where((item) {
      final name = _inventoryItemName(item).toLowerCase();
      final storage = _inventoryStorage(item).toLowerCase();
      return name.contains(query) || storage.contains(query);
    }).toList();
  }

  Map<String, dynamic>? _findInventoryItemById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final item in _inventoryItems) {
      final itemId = item['_id']?.toString();
      if (itemId == id) return item;
    }
    return null;
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _showConsumeDialog() async {
    String? ingredientId;
    String qty = '';
    String uom = 'kg';
    String refType = 'manual';
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Consume Inventory'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: ingredientId,
                      decoration: const InputDecoration(
                        labelText: 'Item *',
                        border: OutlineInputBorder(),
                      ),
                      items: _inventoryItems
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['_id']?.toString() ?? '',
                              child: Text(
                                _inventoryItemName(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .where((option) => (option.value ?? '').isNotEmpty)
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          ingredientId = value;
                          final selected = _findInventoryItemById(value);
                          final backendUom = _inventoryUom(selected ?? {});
                          if (backendUom != '--') {
                            uom = backendUom;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Quantity *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        qty = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                          _uomOptions.contains(uom) ? uom : _uomOptions.first,
                      decoration: const InputDecoration(
                        labelText: 'UOM *',
                        border: OutlineInputBorder(),
                      ),
                      items: _uomOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          uom = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: refType,
                      decoration: const InputDecoration(
                        labelText: 'Reference Type',
                        border: OutlineInputBorder(),
                      ),
                      items: _consumeRefTypes
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          refType = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final parsedQty = double.tryParse(qty.trim()) ?? 0;
                          if (ingredientId == null ||
                              ingredientId!.isEmpty ||
                              parsedQty <= 0) {
                            _showSnackBar(
                              'Please select an item and enter a valid quantity.',
                              isError: true,
                            );
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            await _inventoryService.consumeInventory(
                              ingredientId: ingredientId!,
                              qty: parsedQty,
                              uom: uom,
                              refType: refType,
                            );

                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                            _showSnackBar(
                              'Inventory consumed successfully.',
                              isError: false,
                            );
                            await _refreshAfterMutation();
                          } catch (e) {
                            _showSnackBar(
                              _extractErrorMessage(e),
                              isError: true,
                            );
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Consume'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showReturnDialog() async {
    String? ingredientId;
    String qty = '';
    String uom = 'kg';
    String notes = '';
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Return to Inventory'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: ingredientId,
                      decoration: const InputDecoration(
                        labelText: 'Item *',
                        border: OutlineInputBorder(),
                      ),
                      items: _inventoryItems
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['_id']?.toString() ?? '',
                              child: Text(
                                _inventoryItemName(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .where((option) => (option.value ?? '').isNotEmpty)
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          ingredientId = value;
                          final selected = _findInventoryItemById(value);
                          final backendUom = _inventoryUom(selected ?? {});
                          if (backendUom != '--') {
                            uom = backendUom;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Return Quantity *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        qty = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                          _uomOptions.contains(uom) ? uom : _uomOptions.first,
                      decoration: const InputDecoration(
                        labelText: 'UOM *',
                        border: OutlineInputBorder(),
                      ),
                      items: _uomOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          uom = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Reason/Notes',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        notes = value;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final parsedQty = double.tryParse(qty.trim()) ?? 0;
                          if (ingredientId == null ||
                              ingredientId!.isEmpty ||
                              parsedQty <= 0) {
                            _showSnackBar(
                              'Please select an item and enter a valid quantity.',
                              isError: true,
                            );
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            await _inventoryService.returnToInventory(
                              ingredientId: ingredientId!,
                              qty: parsedQty,
                              uom: uom,
                              refType: 'return',
                              notes: notes.trim().isEmpty
                                  ? 'Unused ingredients returned to inventory'
                                  : notes.trim(),
                            );

                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                            _showSnackBar(
                              'Inventory returned successfully.',
                              isError: false,
                            );
                            await _refreshAfterMutation();
                          } catch (e) {
                            _showSnackBar(
                              _extractErrorMessage(e),
                              isError: true,
                            );
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Return'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddItemDialog() async {
    String name = '';
    String category = 'Other';
    String storageLocation = 'Dry Storage';
    String uom = 'kg';
    String reorderLevel = '0';
    String shelfTimeDays = '7';
    bool isActive = true;
    bool isSubmitting = false;
    final currentCartId =
        context.read<AppProvider>().currentUser?.cartId?.trim();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Inventory Item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Item Name *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        name = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: category,
                      decoration: const InputDecoration(
                        labelText: 'Category *',
                        border: OutlineInputBorder(),
                      ),
                      items: _categoryOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          category = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: storageLocation,
                      decoration: const InputDecoration(
                        labelText: 'Storage Location *',
                        border: OutlineInputBorder(),
                      ),
                      items: _storageOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          storageLocation = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: uom,
                      decoration: const InputDecoration(
                        labelText: 'UOM *',
                        border: OutlineInputBorder(),
                      ),
                      items: _uomOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          uom = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: reorderLevel,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Reorder Level',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        reorderLevel = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: shelfTimeDays,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Shelf Time (Days)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        shelfTimeDays = value;
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() {
                          isActive = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final trimmedName = name.trim();
                          if (trimmedName.isEmpty) {
                            _showSnackBar(
                              'Please enter item name.',
                              isError: true,
                            );
                            return;
                          }

                          final parsedReorder = double.tryParse(
                            reorderLevel.trim().isEmpty
                                ? '0'
                                : reorderLevel.trim(),
                          );
                          if (parsedReorder == null || parsedReorder < 0) {
                            _showSnackBar(
                              'Please enter a valid reorder level.',
                              isError: true,
                            );
                            return;
                          }

                          final parsedShelf = int.tryParse(
                            shelfTimeDays.trim().isEmpty
                                ? '0'
                                : shelfTimeDays.trim(),
                          );
                          if (parsedShelf == null || parsedShelf < 0) {
                            _showSnackBar(
                              'Please enter valid shelf time in days.',
                              isError: true,
                            );
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            final createdItem =
                                await _inventoryService.createInventoryItem({
                              'name': trimmedName,
                              'category': category,
                              'storageLocation': storageLocation,
                              'uom': uom,
                              'baseUnit': _baseUnitFromUom(uom),
                              'reorderLevel': parsedReorder,
                              'shelfTimeDays': parsedShelf,
                              'isActive': isActive,
                              if (currentCartId != null &&
                                  currentCartId.isNotEmpty)
                                'cartId': currentCartId,
                            });

                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                            final serverMessage =
                                createdItem['message']?.toString().trim() ?? '';
                            _showSnackBar(
                              serverMessage.isNotEmpty
                                  ? serverMessage
                                  : 'Inventory item added successfully.',
                              isError: false,
                            );
                            await _refreshFromBackend(
                              includeTransactions: _transactionsLoaded ||
                                  _tabController.index == 1,
                            );
                          } catch (e) {
                            _showSnackBar(
                              _extractErrorMessage(e),
                              isError: true,
                            );
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showDirectPurchaseDialog() async {
    if (!_transactionsLoaded) {
      await _loadTransactions(showLoading: false);
    }
    if (!mounted) return;

    String? ingredientId;
    String qty = '';
    String uom = 'kg';
    String unitPrice = '';
    String supplier = '';
    String notes = '';
    bool isSubmitting = false;
    final currentCartId =
        context.read<AppProvider>().currentUser?.cartId?.trim();
    final supplierController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Purchase Stock'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: ingredientId,
                      decoration: const InputDecoration(
                        labelText: 'Item *',
                        border: OutlineInputBorder(),
                      ),
                      items: _inventoryItems
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['_id']?.toString() ?? '',
                              child: Text(
                                _inventoryItemName(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .where((option) => (option.value ?? '').isNotEmpty)
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          ingredientId = value;
                          final selected = _findInventoryItemById(value);
                          final backendUom = _inventoryUom(selected ?? {});
                          if (backendUom != '--' &&
                              _uomOptions.contains(backendUom)) {
                            uom = backendUom;
                          }
                          final latestSupplier = value == null
                              ? null
                              : _latestSupplierForIngredient(value);
                          supplier = latestSupplier ?? '';
                          supplierController.text = supplier;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Quantity *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        qty = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                          _uomOptions.contains(uom) ? uom : _uomOptions.first,
                      decoration: const InputDecoration(
                        labelText: 'UOM *',
                        border: OutlineInputBorder(),
                      ),
                      items: _uomOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          uom = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Unit Price *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        unitPrice = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: supplierController,
                      decoration: const InputDecoration(
                        labelText: 'Supplier',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        supplier = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        notes = value;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final parsedQty = double.tryParse(qty.trim()) ?? 0;
                          final parsedUnitPrice =
                              double.tryParse(unitPrice.trim());
                          if (ingredientId == null ||
                              ingredientId!.isEmpty ||
                              parsedQty <= 0 ||
                              parsedUnitPrice == null ||
                              parsedUnitPrice < 0) {
                            _showSnackBar(
                              'Please select item and enter valid quantity and price.',
                              isError: true,
                            );
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            await _inventoryService.directPurchase(
                              ingredientId: ingredientId!,
                              qty: parsedQty,
                              uom: uom,
                              unitPrice: parsedUnitPrice,
                              supplier: supplierController.text.trim().isEmpty
                                  ? null
                                  : supplierController.text.trim(),
                              notes: notes.trim().isEmpty ? null : notes.trim(),
                              cartId: (currentCartId == null ||
                                      currentCartId.isEmpty)
                                  ? null
                                  : currentCartId,
                            );

                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                            _showSnackBar(
                              'Stock added successfully.',
                              isError: false,
                            );
                            await _refreshAfterMutation();
                          } catch (e) {
                            _showSnackBar(
                              _extractErrorMessage(e),
                              isError: true,
                            );
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Add Stock'),
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        supplierController.dispose();
      });
    } else {
      supplierController.dispose();
    }
  }

  Future<void> _showWasteDialog() async {
    String? ingredientId;
    String qty = '';
    String uom = 'kg';
    String reason = _wasteReasonOptions.first;
    String reasonDetails = '';
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Record Waste'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: ingredientId,
                      decoration: const InputDecoration(
                        labelText: 'Item *',
                        border: OutlineInputBorder(),
                      ),
                      items: _inventoryItems
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['_id']?.toString() ?? '',
                              child: Text(
                                _inventoryItemName(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .where((option) => (option.value ?? '').isNotEmpty)
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          ingredientId = value;
                          final selected = _findInventoryItemById(value);
                          final backendUom = _inventoryUom(selected ?? {});
                          if (backendUom != '--' &&
                              _uomOptions.contains(backendUom)) {
                            uom = backendUom;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Waste Quantity *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        qty = value;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value:
                          _uomOptions.contains(uom) ? uom : _uomOptions.first,
                      decoration: const InputDecoration(
                        labelText: 'UOM *',
                        border: OutlineInputBorder(),
                      ),
                      items: _uomOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          uom = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: reason,
                      decoration: const InputDecoration(
                        labelText: 'Reason *',
                        border: OutlineInputBorder(),
                      ),
                      items: _wasteReasonOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          reason = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Details (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        reasonDetails = value;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final parsedQty = double.tryParse(qty.trim()) ?? 0;
                          if (ingredientId == null ||
                              ingredientId!.isEmpty ||
                              parsedQty <= 0) {
                            _showSnackBar(
                              'Please select item and enter valid waste quantity.',
                              isError: true,
                            );
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            await _inventoryService.recordWaste(
                              ingredientId: ingredientId!,
                              qty: parsedQty,
                              uom: uom,
                              reason: reason,
                              reasonDetails: reasonDetails.trim().isEmpty
                                  ? null
                                  : reasonDetails.trim(),
                            );

                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                            _showSnackBar(
                              'Waste recorded successfully.',
                              isError: false,
                            );
                            await _refreshAfterMutation();
                          } catch (e) {
                            _showSnackBar(
                              _extractErrorMessage(e),
                              isError: true,
                            );
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Record'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditItemDialog(Map<String, dynamic> item) async {
    final ingredientId = (item['_id'] ?? item['ingredientId'])?.toString();
    if (ingredientId == null || ingredientId.isEmpty) {
      _showSnackBar('Unable to edit this item.', isError: true);
      return;
    }

    final existingStorageRaw = _inventoryStorage(item);
    final existingStorage =
        existingStorageRaw == '--' ? '' : existingStorageRaw;
    final existingReorderRaw =
        item['reorderLevel'] ?? item['minStockLevel'] ?? item['minStock'];
    final existingReorder =
        existingReorderRaw == null ? '' : existingReorderRaw.toString();
    final existingIsActive = item['isActive'] is bool
        ? item['isActive'] as bool
        : _statusText(item).toLowerCase() == 'active';

    final storageController = TextEditingController(text: existingStorage);
    final reorderController = TextEditingController(text: existingReorder);
    bool isActive = existingIsActive;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Inventory Item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: _inventoryItemName(item),
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Item',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: storageController,
                      decoration: const InputDecoration(
                        labelText: 'Storage',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reorderController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Reorder Level (${_inventoryUom(item)})',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() {
                          isActive = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final payload = <String, dynamic>{};
                          final storage = storageController.text.trim();
                          final reorder = reorderController.text.trim();

                          if (storage != existingStorage) {
                            payload['storageLocation'] = storage;
                          }

                          if (reorder != existingReorder) {
                            if (reorder.isEmpty) {
                              payload['reorderLevel'] = 0;
                            } else {
                              final parsedReorder = double.tryParse(reorder);
                              if (parsedReorder == null || parsedReorder < 0) {
                                _showSnackBar(
                                  'Please enter a valid reorder level.',
                                  isError: true,
                                );
                                return;
                              }
                              payload['reorderLevel'] = parsedReorder;
                            }
                          }

                          if (isActive != existingIsActive) {
                            payload['isActive'] = isActive;
                          }

                          if (payload.isEmpty) {
                            Navigator.of(dialogContext).pop();
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            await _inventoryService.updateIngredient(
                              ingredientId,
                              payload,
                            );

                            if (!mounted) return;
                            Navigator.of(this.context).pop();
                            _showSnackBar(
                              'Inventory item updated successfully.',
                              isError: false,
                            );
                            await _refreshFromBackend(
                              includeTransactions: _transactionsLoaded ||
                                  _tabController.index == 1,
                            );
                          } catch (e) {
                            _showSnackBar(
                              _extractErrorMessage(e),
                              isError: true,
                            );
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    storageController.dispose();
    reorderController.dispose();
  }

  Widget _buildAccessDeniedView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Management'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Inventory is only accessible to cooks and managers.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryTab({required bool canMutateInventory}) {
    if (_isLoadingInventory && _inventoryItems.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_inventoryError != null && _inventoryItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_inventoryError!),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _loadInventory(showLoading: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final items = _filteredInventoryItems;
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _refreshFromBackend(includeTransactions: false),
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No inventory items found')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refreshFromBackend(includeTransactions: false),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${items.length} items',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Text(
                    'Pull down to refresh',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          final item = items[index - 1];
          final uom = _inventoryUom(item);
          final status = _statusText(item);
          final stockText = _stockText(item, uom);
          final reorderText = _quantityWithUom(
            item['reorderLevel'] ?? item['minStockLevel'] ?? item['minStock'],
            uom,
          );

          return Card(
            margin: EdgeInsets.zero,
            elevation: 1.5,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _inventoryItemName(item),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _statusBackground(status),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: _statusForeground(status),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildMetaChip(
                        icon: Icons.warehouse_outlined,
                        label: _inventoryStorage(item),
                      ),
                      _buildMetaChip(
                        icon: Icons.straighten_outlined,
                        label: 'UOM: $uom',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    icon: Icons.inventory_outlined,
                    label: 'Stock',
                    value: stockText,
                  ),
                  _buildInfoRow(
                    icon: Icons.warning_amber_outlined,
                    label: 'Reorder Level',
                    value: reorderText,
                  ),
                  _buildInfoRow(
                    icon: Icons.paid_outlined,
                    label: 'Weighted Avg Cost',
                    value: _weightedAvgCostText(item, uom),
                  ),
                  _buildInfoRow(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Total Value',
                    value: _totalValueText(item),
                  ),
                  _buildInfoRow(
                    icon: Icons.event_note_outlined,
                    label: 'Shelf Life',
                    value: _shelfLifeText(item),
                  ),
                  if (canMutateInventory) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () => _showEditItemDialog(item),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit Item'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTransactionsTab() {
    if (_isLoadingTransactions && !_transactionsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_transactionsError != null && _transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _transactionsError!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _loadTransactions(showLoading: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_transactions.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadTransactions(showLoading: false),
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No transactions found')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadTransactions(showLoading: false),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _transactions.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_transactions.length} transactions',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Text(
                    'Latest first',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          final txn = _transactions[index - 1];
          final type = _transactionType(txn);

          return Card(
            margin: EdgeInsets.zero,
            elevation: 1.5,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTransactionTypeChip(type),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _transactionItemName(txn),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Date',
                    value: _transactionDateText(txn['date']),
                  ),
                  _buildInfoRow(
                    icon: Icons.scale_outlined,
                    label: 'Quantity',
                    value: _transactionQuantity(txn),
                  ),
                  _buildInfoRow(
                    icon: Icons.payments_outlined,
                    label: 'Cost Allocated',
                    value: _transactionCost(txn),
                  ),
                  _buildInfoRow(
                    icon: Icons.link_outlined,
                    label: 'Reference',
                    value: _textOrDash(txn['refType']),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, appProvider, _) {
        final canViewInventory =
            appProvider.userRole == 'manager' || appProvider.userRole == 'cook';
        final canMutateInventory = appProvider.userRole == 'manager';

        if (!canViewInventory) {
          return _buildAccessDeniedView();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Inventory Management'),
            actions: [
              IconButton(
                onPressed: () {
                  _refreshFromBackend(
                    includeTransactions:
                        _transactionsLoaded || _tabController.index == 1,
                  );
                },
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
              if (canMutateInventory)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'add_item') {
                      _showAddItemDialog();
                      return;
                    }
                    if (value == 'direct_purchase') {
                      if (_inventoryItems.isEmpty) {
                        _showSnackBar(
                          'Add an inventory item first.',
                          isError: true,
                        );
                        return;
                      }
                      _showDirectPurchaseDialog();
                      return;
                    }
                    if (value == 'waste') {
                      if (_inventoryItems.isEmpty) {
                        _showSnackBar(
                          'Add an inventory item first.',
                          isError: true,
                        );
                        return;
                      }
                      _showWasteDialog();
                      return;
                    }
                    if (value == 'consume') {
                      if (_inventoryItems.isEmpty) {
                        _showSnackBar(
                          'Add an inventory item first.',
                          isError: true,
                        );
                        return;
                      }
                      _showConsumeDialog();
                      return;
                    }
                    if (value == 'return') {
                      if (_inventoryItems.isEmpty) {
                        _showSnackBar(
                          'Add an inventory item first.',
                          isError: true,
                        );
                        return;
                      }
                      _showReturnDialog();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'add_item',
                      child: Text('Add Inventory Item'),
                    ),
                    PopupMenuItem<String>(
                      value: 'direct_purchase',
                      child: Text('Add Purchase Stock'),
                    ),
                    PopupMenuItem<String>(
                      value: 'waste',
                      child: Text('Record Waste'),
                    ),
                    PopupMenuItem<String>(
                      value: 'consume',
                      child: Text('Consume Inventory'),
                    ),
                    PopupMenuItem<String>(
                      value: 'return',
                      child: Text('Return to Inventory'),
                    ),
                  ],
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(
                  icon: Icon(Icons.inventory_2_outlined),
                  text: 'Stock',
                ),
                Tab(
                  icon: Icon(Icons.receipt_long_outlined),
                  text: 'Transactions',
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search item or storage',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () => _searchController.clear(),
                            icon: const Icon(Icons.close),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (canMutateInventory)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Actions menu: Add Item, Add Purchase Stock, Record Waste, Consume, Return.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildInventoryTab(
                      canMutateInventory: canMutateInventory,
                    ),
                    _buildTransactionsTab(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
