class UserModel {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? cartId;
  final String? franchiseId;
  final String? franchiseCode;
  final String? cartCode;
  final String? franchiseName;
  final String? cartName;
  final bool isActive;
  final bool isApproved;
  final String? employeeId;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.cartId,
    this.franchiseId,
    this.franchiseCode,
    this.cartCode,
    this.franchiseName,
    this.cartName,
    this.isActive = true,
    this.isApproved = true,
    this.employeeId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
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

    return UserModel(
      id: extractId(json['_id'] ?? json['id']) ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      cartId: extractId(json['cartId']) ??
          extractId(json['cafeId']), // Support both for backward compatibility
      franchiseId: extractId(json['franchiseId']),
      franchiseCode: json['franchiseCode']?.toString(),
      cartCode: json['cartCode']?.toString(),
      franchiseName: json['franchiseName']?.toString(),
      cartName: json['cartName']?.toString(),
      isActive: json['isActive'] ?? true,
      isApproved: json['isApproved'] ?? true,
      employeeId: extractId(json['employeeId']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'cartId': cartId,
      'franchiseId': franchiseId,
      'franchiseCode': franchiseCode,
      'cartCode': cartCode,
      'franchiseName': franchiseName,
      'cartName': cartName,
      'isActive': isActive,
      'isApproved': isApproved,
      'employeeId': employeeId,
    };
  }
}
