class OrderModel {
  final String id;
  final String? tableNumber;
  final String? tableId;
  final String serviceType;
  final String? orderType;
  final List<KOTLine> kotLines;
  final String status;
  final String rawStatus;
  final String lifecycleStatus;
  final String paymentStatus;
  final String? paymentMode;
  final String? officePaymentMode;
  final bool paymentRequiredBeforeProceeding;
  final bool isPaid;
  final bool isCancelled;
  final String? cancelledReason;
  final bool requiresManagerApproval;
  final DateTime? managerApprovedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? paidAt;
  final String? cartId;
  final String? franchiseId;
  final bool kotPrinted;
  final bool billPrinted;
  final int lastPrintedKotIndex;
  final int? takeawayToken;
  final String? customerName;
  final String? customerMobile;
  final String? sourceQrType;
  final String? officeName;
  final String specialInstructions;
  final Map<String, dynamic>? pickupLocation;
  final AssignedStaff? assignedStaff;
  final AcceptedBy? acceptedBy;
  final List<OrderAddon> selectedAddons;

  OrderModel({
    required this.id,
    this.tableNumber,
    this.tableId,
    this.serviceType = 'DINE_IN',
    this.orderType,
    this.kotLines = const [],
    this.status = 'NEW',
    this.rawStatus = 'NEW',
    this.lifecycleStatus = 'NEW',
    this.paymentStatus = 'PENDING',
    this.paymentMode,
    this.officePaymentMode,
    this.paymentRequiredBeforeProceeding = false,
    this.isPaid = false,
    this.isCancelled = false,
    this.cancelledReason,
    this.requiresManagerApproval = false,
    this.managerApprovedAt,
    required this.createdAt,
    this.updatedAt,
    this.paidAt,
    this.cartId,
    this.franchiseId,
    this.kotPrinted = false,
    this.billPrinted = false,
    this.lastPrintedKotIndex = -1,
    this.takeawayToken,
    this.customerName,
    this.customerMobile,
    this.sourceQrType,
    this.officeName,
    this.specialInstructions = '',
    this.pickupLocation,
    this.assignedStaff,
    this.acceptedBy,
    this.selectedAddons = const [],
  });

  static int _parseInt(dynamic v, int def) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }

  static double _parseDouble(dynamic v, [double def = 0.0]) {
    if (v == null) return def;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? def;
    return def;
  }

  static String? _coerceMeaningfulString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final normalized = text.toLowerCase();
    if (normalized == 'null' ||
        normalized == 'none' ||
        normalized == 'undefined') {
      return null;
    }
    return text;
  }

  static String? _extractId(dynamic value) {
    if (value == null) return null;
    if (value is String) return _coerceMeaningfulString(value);
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final nested = map['_id'] ?? map['id'] ?? map['cartId'] ?? map['cafeId'];
      return _coerceMeaningfulString(nested);
    }
    return _coerceMeaningfulString(value);
  }

  static int? _parseOptionalInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool _parseBool(dynamic value, [bool defaultValue = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final token = value.trim().toLowerCase();
      if (token == 'true' || token == '1' || token == 'yes') return true;
      if (token == 'false' || token == '0' || token == 'no') return false;
    }
    return defaultValue;
  }

  static String _canonicalStatus(dynamic value) {
    final token = value
        ?.toString()
        .trim()
        .toUpperCase()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (token == null || token.isEmpty) return 'NEW';
    if (token == 'NEW' ||
        token == 'PENDING' ||
        token == 'CONFIRMED' ||
        token == 'ACCEPT' ||
        token == 'ACCEPTED') {
      return 'NEW';
    }
    if (token == 'PREPARING' ||
        token == 'BEING PREPARED' ||
        token == 'BEINGPREPARED') {
      return 'PREPARING';
    }
    if (token == 'READY') return 'READY';
    if (token == 'COMPLETED' ||
        token == 'SERVED' ||
        token == 'FINALIZED' ||
        token == 'PAID' ||
        token == 'CANCELLED' ||
        token == 'CANCELED' ||
        token == 'RETURNED' ||
        token == 'EXIT' ||
        token == 'CLOSED' ||
        token == 'REJECTED') {
      return 'SERVED';
    }
    return 'NEW';
  }

  static String _canonicalPaymentStatus(
    dynamic paymentStatus,
    dynamic status,
    dynamic isPaid,
  ) {
    final paymentToken =
        paymentStatus?.toString().trim().toUpperCase().replaceAll('_', ' ');
    if (paymentToken == 'PAID') return 'PAID';
    if (isPaid == true) return 'PAID';
    final rawStatus = status?.toString().trim().toUpperCase();
    if (rawStatus == 'PAID') return 'PAID';
    return 'PENDING';
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final printStatus = json['printStatus'];
    final ps = printStatus is Map ? printStatus : null;
    final tableData = json['table'];
    final tableMap =
        tableData is Map ? Map<String, dynamic>.from(tableData) : null;

    final resolvedTableNumber = _coerceMeaningfulString(json['tableNumber']) ??
        _coerceMeaningfulString(json['tableNo']) ??
        _coerceMeaningfulString(tableMap?['number']) ??
        _coerceMeaningfulString(tableMap?['tableNumber']) ??
        _coerceMeaningfulString(tableMap?['name']);

    final resolvedTableId = _extractId(tableMap?['_id']) ??
        _extractId(tableMap?['id']) ??
        _extractId(json['tableId']) ??
        (tableData is String ? _coerceMeaningfulString(tableData) : null);

    final resolvedCartId = _extractId(json['cartId']) ??
        _extractId(json['cafeId']) ??
        _extractId(tableMap?['cartId']) ??
        _extractId(tableMap?['cafeId']);

    final resolvedTakeawayToken = _parseOptionalInt(json['takeawayToken']) ??
        _parseOptionalInt(json['token']) ??
        _parseOptionalInt(json['takeaway_token']) ??
        _parseOptionalInt(json['deliveryToken']) ??
        _parseOptionalInt(json['delivery_token']);

    final canonicalStatus = _canonicalStatus(json['status']);
    final canonicalPaymentStatus = _canonicalPaymentStatus(
      json['paymentStatus'],
      json['status'],
      json['isPaid'],
    );
    final canonicalPaymentMode =
        _coerceMeaningfulString(json['paymentMode'])?.toUpperCase();
    final canonicalOfficePaymentMode =
        _coerceMeaningfulString(json['officePaymentMode'])?.toUpperCase();

    return OrderModel(
      id: json['_id'] ?? json['id'] ?? '',
      tableNumber: resolvedTableNumber,
      tableId: resolvedTableId,
      serviceType: (json['serviceType'] ?? json['orderType'] ?? 'DINE_IN')
          .toString()
          .trim()
          .toUpperCase(),
      orderType: json['orderType']?.toString().trim().toUpperCase(),
      kotLines: (json['kotLines'] as List<dynamic>?)
              ?.map((e) => KOTLine.fromJson(e))
              .toList() ??
          [],
      status: canonicalStatus,
      rawStatus:
          json['rawStatus']?.toString() ?? json['status']?.toString() ?? 'NEW',
      lifecycleStatus: json['lifecycleStatus']?.toString() ?? canonicalStatus,
      paymentStatus: canonicalPaymentStatus,
      paymentMode: canonicalPaymentMode,
      officePaymentMode: canonicalOfficePaymentMode,
      paymentRequiredBeforeProceeding:
          _parseBool(json['paymentRequiredBeforeProceeding']),
      isPaid: canonicalPaymentStatus == 'PAID',
      isCancelled: json['isCancelled'] == true,
      cancelledReason: json['cancelledReason']?.toString().isNotEmpty == true
          ? json['cancelledReason']?.toString()
          : (json['cancellationReason']?.toString().isNotEmpty == true
              ? json['cancellationReason']?.toString()
              : null),
      requiresManagerApproval: json['requiresManagerApproval'] == true,
      managerApprovedAt: json['managerApprovedAt'] != null
          ? DateTime.tryParse(json['managerApprovedAt'].toString())
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      paidAt: json['paidAt'] != null ? DateTime.parse(json['paidAt']) : null,
      cartId: resolvedCartId,
      franchiseId: _extractId(json['franchiseId']),
      kotPrinted: ps?['kotPrinted'] ?? false,
      billPrinted: ps?['billPrinted'] ?? false,
      lastPrintedKotIndex: _parseInt(ps?['lastPrintedKotIndex'], -1),
      takeawayToken: resolvedTakeawayToken,
      customerName: json['customerName'],
      customerMobile: json['customerMobile'],
      sourceQrType: _coerceMeaningfulString(json['sourceQrType']),
      officeName: _coerceMeaningfulString(json['officeName']),
      specialInstructions: json['specialInstructions']?.toString() ??
          json['specialInstruction']?.toString() ??
          json['orderNote']?.toString() ??
          json['note']?.toString() ??
          json['notes']?.toString() ??
          '',
      pickupLocation: json['pickupLocation'] is Map
          ? Map<String, dynamic>.from(json['pickupLocation'] as Map)
          : null,
      assignedStaff: json['assignedStaff'] is Map
          ? AssignedStaff.fromJson(
              Map<String, dynamic>.from(json['assignedStaff'] as Map),
            )
          : null,
      acceptedBy: json['acceptedBy'] != null
          ? AcceptedBy.fromJson(
              Map<String, dynamic>.from(json['acceptedBy'] as Map))
          : null,
      selectedAddons: (json['selectedAddons'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => OrderAddon.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const <OrderAddon>[],
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'tableNumber': tableNumber,
        'tableId': tableId,
        'serviceType': serviceType,
        if (orderType != null) 'orderType': orderType,
        'kotLines': kotLines.map((e) => e.toJson()).toList(),
        'status': status,
        'rawStatus': rawStatus,
        'lifecycleStatus': lifecycleStatus,
        'paymentStatus': paymentStatus,
        if (paymentMode != null) 'paymentMode': paymentMode,
        if (officePaymentMode != null) 'officePaymentMode': officePaymentMode,
        'paymentRequiredBeforeProceeding': paymentRequiredBeforeProceeding,
        'isPaid': isPaid,
        'isCancelled': isCancelled,
        if (cancelledReason != null) 'cancelledReason': cancelledReason,
        'requiresManagerApproval': requiresManagerApproval,
        if (managerApprovedAt != null)
          'managerApprovedAt': managerApprovedAt!.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        'paidAt': paidAt?.toIso8601String(),
        'cartId': cartId,
        'franchiseId': franchiseId,
        'printStatus': {
          'kotPrinted': kotPrinted,
          'billPrinted': billPrinted,
          'lastPrintedKotIndex': lastPrintedKotIndex,
        },
        'takeawayToken': takeawayToken,
        'customerName': customerName,
        'customerMobile': customerMobile,
        if (sourceQrType != null) 'sourceQrType': sourceQrType,
        if (officeName != null) 'officeName': officeName,
        if (specialInstructions.trim().isNotEmpty)
          'specialInstructions': specialInstructions.trim(),
        if (pickupLocation != null) 'pickupLocation': pickupLocation!,
        if (assignedStaff != null) 'assignedStaff': assignedStaff!.toJson(),
        if (acceptedBy != null) 'acceptedBy': acceptedBy!.toJson(),
        if (selectedAddons.isNotEmpty)
          'selectedAddons': selectedAddons.map((e) => e.toJson()).toList(),
      };
}

class AssignedStaff {
  final String? id;
  final String? name;
  final String? role;
  final String? disability;
  final DateTime? acceptedAt;

  AssignedStaff({
    this.id,
    this.name,
    this.role,
    this.disability,
    this.acceptedAt,
  });

  factory AssignedStaff.fromJson(Map<String, dynamic> json) {
    final acceptedAtRaw = json['acceptedAt'];
    return AssignedStaff(
      id: OrderModel._coerceMeaningfulString(json['id']),
      name: OrderModel._coerceMeaningfulString(json['name']),
      role: OrderModel._coerceMeaningfulString(json['role']),
      disability: OrderModel._coerceMeaningfulString(json['disability']),
      acceptedAt: acceptedAtRaw != null
          ? DateTime.tryParse(acceptedAtRaw.toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (name != null) 'name': name,
        if (role != null) 'role': role,
        if (disability != null) 'disability': disability,
        if (acceptedAt != null) 'acceptedAt': acceptedAt!.toIso8601String(),
      };
}

class AcceptedBy {
  final String? employeeId;
  final String? employeeName;
  final String? employeeRole;
  final bool hasDisability;
  final String? disabilityType;

  AcceptedBy({
    this.employeeId,
    this.employeeName,
    this.employeeRole,
    this.hasDisability = false,
    this.disabilityType,
  });

  factory AcceptedBy.fromJson(Map<String, dynamic> json) {
    final disability = json['disability'];
    final d = disability is Map ? disability : null;
    return AcceptedBy(
      employeeId: json['employeeId']?.toString(),
      employeeName: json['employeeName'],
      employeeRole: json['employeeRole']?.toString(),
      hasDisability: d?['hasDisability'] ?? false,
      disabilityType: d?['type'],
    );
  }

  Map<String, dynamic> toJson() => {
        if (employeeId != null) 'employeeId': employeeId,
        if (employeeName != null) 'employeeName': employeeName,
        if (employeeRole != null) 'employeeRole': employeeRole,
        'disability': {
          'hasDisability': hasDisability,
          if (disabilityType != null) 'type': disabilityType,
        },
      };
}

extension OrderModelTotal on OrderModel {
  List<OrderItem> get allItems =>
      kotLines.expand((kotLine) => kotLine.items).toList();

  List<OrderItem> get activeItems =>
      allItems.where((item) => !item.returned).toList();

  double get itemsSubtotal => activeItems.fold<double>(
        0.0,
        (sum, item) => sum + item.lineTotal,
      );

  double get addonsSubtotal => selectedAddons.fold<double>(
        0.0,
        (sum, addon) => sum + addon.lineTotal,
      );

  double get subtotalAmount =>
      double.parse((itemsSubtotal + addonsSubtotal).toStringAsFixed(2));

  double get gstAmount => 0.0;

  double get totalAmount => subtotalAmount;
}

class KOTLine {
  final int? kotNumber;
  final List<OrderItem> items;
  final double subtotal;
  final double gst;
  final double totalAmount;
  final DateTime createdAt;

  /// Set by backend for KOT print claim/complete flow; required for agent print.
  final String? printKey;
  final String? printStatus;

  KOTLine({
    this.kotNumber,
    required this.items,
    required this.subtotal,
    required this.gst,
    required this.totalAmount,
    required this.createdAt,
    this.printKey,
    this.printStatus,
  });

  factory KOTLine.fromJson(Map<String, dynamic> json) {
    return KOTLine(
      kotNumber: OrderModel._parseOptionalInt(json['kotNumber']),
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => OrderItem.fromJson(e))
              .toList() ??
          [],
      subtotal: OrderModel._parseDouble(json['subtotal']),
      gst: OrderModel._parseDouble(json['gst']),
      totalAmount: OrderModel._parseDouble(
        json['totalAmount'] ?? json['total'],
      ),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      printKey: OrderModel._coerceMeaningfulString(json['printKey']),
      printStatus: OrderModel._coerceMeaningfulString(json['printStatus']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (kotNumber != null) 'kotNumber': kotNumber,
        'items': items.map((e) => e.toJson()).toList(),
        'subtotal': subtotal,
        'gst': gst,
        'totalAmount': totalAmount,
        'createdAt': createdAt.toIso8601String(),
        if (printKey != null && printKey!.isNotEmpty) 'printKey': printKey,
        if (printStatus != null && printStatus!.isNotEmpty)
          'printStatus': printStatus,
      };
}

class OrderItem {
  final String name;
  final int quantity;
  final double price;
  final bool returned;
  final String note;
  final String specialInstructions;
  final List<OrderItemExtra> extras;
  final List<OrderItemExtra> addOns;

  OrderItem({
    required this.name,
    required this.quantity,
    required this.price,
    this.returned = false,
    this.note = '',
    this.specialInstructions = '',
    this.extras = const <OrderItemExtra>[],
    this.addOns = const <OrderItemExtra>[],
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      name: json['name'] ?? '',
      quantity: OrderModel._parseInt(json['quantity'], 0),
      price: OrderModel._parseDouble(json['price']),
      returned: json['returned'] ?? false,
      note: json['note']?.toString() ?? '',
      specialInstructions: json['specialInstructions']?.toString() ?? '',
      extras: (json['extras'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (e) => OrderItemExtra.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          const <OrderItemExtra>[],
      addOns: (json['addOns'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (e) => OrderItemExtra.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          const <OrderItemExtra>[],
    );
  }

  double get unitPrice => price / 100;
  double get lineTotal => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'price': price,
        'returned': returned,
        if (note.isNotEmpty) 'note': note,
        if (specialInstructions.isNotEmpty)
          'specialInstructions': specialInstructions,
        if (extras.isNotEmpty) 'extras': extras.map((e) => e.toJson()).toList(),
        if (addOns.isNotEmpty) 'addOns': addOns.map((e) => e.toJson()).toList(),
      };
}

class OrderItemExtra {
  final String name;
  final double price;

  const OrderItemExtra({
    required this.name,
    required this.price,
  });

  factory OrderItemExtra.fromJson(Map<String, dynamic> json) {
    return OrderItemExtra(
      name: json['name']?.toString() ?? '',
      price: OrderModel._parseDouble(json['price']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
      };
}

class OrderAddon {
  final String? addonId;
  final String name;
  final double price;
  final int quantity;

  const OrderAddon({
    this.addonId,
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  factory OrderAddon.fromJson(Map<String, dynamic> json) {
    final dynamic addonRef = json['addonId'];
    final Map<String, dynamic>? addonRefMap =
        addonRef is Map ? Map<String, dynamic>.from(addonRef) : null;
    final resolvedName = json['name']?.toString() ??
        json['addonName']?.toString() ??
        addonRefMap?['name']?.toString() ??
        'Add-on';
    final resolvedPrice = OrderModel._parseDouble(
      json['price'] ?? json['amount'] ?? addonRefMap?['price'],
    );
    final resolvedQuantity = OrderModel._parseInt(
      json['quantity'] ?? json['qty'],
      1,
    ).clamp(1, 9999);

    return OrderAddon(
      addonId: json['addonId']?.toString() ??
          addonRefMap?['_id']?.toString() ??
          json['_id']?.toString() ??
          json['id']?.toString(),
      name: resolvedName,
      price: resolvedPrice,
      quantity: resolvedQuantity,
    );
  }

  double get lineTotal => price * quantity;

  Map<String, dynamic> toJson() => {
        if (addonId != null) 'addonId': addonId,
        'name': name,
        'price': price,
        'quantity': quantity,
      };
}
