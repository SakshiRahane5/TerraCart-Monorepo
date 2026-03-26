class TableModel {
  final String id;
  final int number;
  final String? name;
  final int capacity;
  final int? totalCapacity; // Total capacity including merged tables
  final String status;
  final String? qrSlug;
  final String? sessionToken;
  final String? currentOrderId;
  final DateTime? lastAssignedAt;
  final String? cartId;
  final String? franchiseId;
  final String? qrContextType;
  final String? officeName;
  final String? officeAddress;
  final String? officePhone;
  final double officeDeliveryCharge;
  final String? officePaymentMode;
  final String?
      mergedWith; // ID of table this is merged with (for secondary tables)
  final List<String>?
      mergedTables; // IDs of tables merged into this one (for primary tables)

  TableModel({
    required this.id,
    required this.number,
    this.name,
    this.capacity = 2,
    this.totalCapacity,
    this.status = 'AVAILABLE',
    this.qrSlug,
    this.sessionToken,
    this.currentOrderId,
    this.lastAssignedAt,
    this.cartId,
    this.franchiseId,
    this.qrContextType,
    this.officeName,
    this.officeAddress,
    this.officePhone,
    this.officeDeliveryCharge = 0,
    this.officePaymentMode,
    this.mergedWith,
    this.mergedTables,
  });

  factory TableModel.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value, int fallback) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    double parseDouble(dynamic value, double fallback) {
      if (value == null) return fallback;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    String? extractId(dynamic value) {
      if (value == null) return null;
      if (value is String && value.isNotEmpty) return value;
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        final nested =
            map['_id'] ?? map['id'] ?? map['cartId'] ?? map['cafeId'];
        return nested?.toString();
      }
      final parsed = value.toString();
      return parsed.isEmpty ? null : parsed;
    }

    // Parse mergedTables - can be array of IDs or array of objects with number
    List<String>? mergedTablesList;
    if (json['mergedTables'] != null) {
      if (json['mergedTables'] is List) {
        final list = (json['mergedTables'] as List)
            .map((item) {
              if (item is Map) {
                return item['_id']?.toString() ?? item['id']?.toString() ?? '';
              }
              return item.toString();
            })
            .where((id) => id.isNotEmpty)
            .toList();
        mergedTablesList = list.isNotEmpty ? list : null;
      }
    }

    return TableModel(
      id: extractId(json['_id'] ?? json['id']) ?? '',
      number: parseInt(json['number'] ?? json['tableNumber'], 0),
      name: json['name'],
      capacity: parseInt(json['capacity'], 2),
      totalCapacity: json['totalCapacity'] != null
          ? parseInt(json['totalCapacity'], parseInt(json['capacity'], 2))
          : null,
      status: json['status'] ?? 'AVAILABLE',
      qrSlug: json['qrSlug'],
      sessionToken: json['sessionToken']?.toString(),
      currentOrderId: extractId(json['currentOrder']),
      lastAssignedAt: json['lastAssignedAt'] != null
          ? DateTime.tryParse(json['lastAssignedAt'].toString())
          : null,
      cartId: extractId(json['cartId']) ??
          extractId(json['cafeId']), // Support both for backward compatibility
      franchiseId: extractId(json['franchiseId']),
      qrContextType: json['qrContextType']?.toString(),
      officeName: json['officeName']?.toString(),
      officeAddress: json['officeAddress']?.toString(),
      officePhone: json['officePhone']?.toString(),
      officeDeliveryCharge: parseDouble(json['officeDeliveryCharge'], 0),
      officePaymentMode: json['officePaymentMode']?.toString(),
      mergedWith: json['mergedWith']?.toString(),
      mergedTables: mergedTablesList,
    );
  }

  bool get isOccupied => status == 'OCCUPIED';
  bool get isAvailable => status == 'AVAILABLE';
  bool get isMerged => status == 'MERGED' || mergedWith != null;
  bool get hasMergedTables => mergedTables != null && mergedTables!.isNotEmpty;

  // Calculate available seats (capacity - occupied seats)
  // For merged tables, use totalCapacity if available
  int get availableSeats {
    final totalCap = totalCapacity ?? capacity;
    // If table is occupied, assume some seats are taken
    // For simplicity, we'll show full capacity as available if not occupied
    // In a real scenario, you'd track actual seat usage
    return isOccupied ? 0 : totalCap;
  }
}
