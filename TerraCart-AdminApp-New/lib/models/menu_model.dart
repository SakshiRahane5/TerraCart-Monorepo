class MenuCategory {
  final String id;
  final String name;
  final String? description;
  final int? sortOrder;
  final List<MenuItem> items;

  MenuCategory({
    required this.id,
    required this.name,
    this.description,
    this.sortOrder,
    this.items = const [],
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) {
    return MenuCategory(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      sortOrder: json['sortOrder'],
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => MenuItem.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class MenuItem {
  final String id;
  final String name;
  final String? description;
  final double price;
  final String? image;
  final bool isAvailable;
  final bool isFeatured;
  final String spiceLevel;
  final int? sortOrder;
  final List<String> tags;
  final String categoryId;

  MenuItem({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.image,
    this.isAvailable = true,
    this.isFeatured = false,
    this.spiceLevel = 'NONE',
    this.sortOrder,
    this.tags = const [],
    required this.categoryId,
  });

  static String _normalizeSpiceLevel(dynamic rawValue) {
    final level = rawValue?.toString().trim().toUpperCase() ?? '';
    const allowed = {'NONE', 'MILD', 'MEDIUM', 'HOT', 'EXTREME'};
    return allowed.contains(level) ? level : 'NONE';
  }

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    // Handle price conversion - use backend value as-is in rupees
    double price = 0.0;
    if (json['price'] != null) {
      final dynamic raw = json['price'];
      if (raw is num) {
        // Treat numeric price from backend as rupees directly
        price = raw.toDouble();
      } else if (raw is String) {
        price = double.tryParse(raw) ?? 0.0;
      }
    }

    return MenuItem(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      price: price,
      image: json['image'],
      isAvailable: json['isAvailable'] ?? true,
      isFeatured: json['isFeatured'] == true,
      spiceLevel: _normalizeSpiceLevel(json['spiceLevel']),
      sortOrder: json['sortOrder'],
      tags: (json['tags'] as List<dynamic>?)
              ?.map((tag) => tag.toString().trim())
              .where((tag) => tag.isNotEmpty)
              .toList() ??
          const [],
      categoryId: json['category']?.toString() ?? '',
    );
  }
}
