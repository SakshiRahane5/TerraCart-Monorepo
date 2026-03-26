class AddonModel {
  final String id;
  final String name;
  final String? description;
  final double price;
  final String? icon;
  final bool isAvailable;
  final int sortOrder;

  const AddonModel({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.icon,
    this.isAvailable = true,
    this.sortOrder = 0,
  });

  factory AddonModel.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    final parsedPrice = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;

    final rawSortOrder = json['sortOrder'];
    final parsedSortOrder = rawSortOrder is num
        ? rawSortOrder.toInt()
        : int.tryParse(rawSortOrder?.toString() ?? '') ?? 0;

    return AddonModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      price: parsedPrice,
      icon: json['icon']?.toString(),
      isAvailable: json['isAvailable'] != false,
      sortOrder: parsedSortOrder,
    );
  }
}
