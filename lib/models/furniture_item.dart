class FurnitureItem {
  final String id;
  final String name;
  final String type; // 'couch', 'table', 'plant', etc.
  final String? imageUrl;
  final String emoji; // fallback if no image
  final double width;
  final double height;
  final String category; // Category: 'furniture', 'decor', 'paintings', 'electronics'

  FurnitureItem({
    required this.id,
    required this.name,
    required this.type,
    this.imageUrl,
    required this.emoji,
    this.width = 80,
    this.height = 60,
    required this.category,
  });
}

class PlacedFurniture {
  final String furnitureId;
  final String furnitureType;
  final double x;
  final double y;
  final String placedId;

  PlacedFurniture({
    required this.furnitureId,
    required this.furnitureType,
    required this.x,
    required this.y,
    required this.placedId,
  });

  Map<String, dynamic> toMap() {
    return {
      'furnitureId': furnitureId,
      'furnitureType': furnitureType,
      'x': x,
      'y': y,
      'placedId': placedId,
    };
  }

  factory PlacedFurniture.fromMap(Map<String, dynamic> map) {
    return PlacedFurniture(
      furnitureId: map['furnitureId'] ?? '',
      furnitureType: map['furnitureType'] ?? '',
      x: (map['x'] ?? 0).toDouble(),
      y: (map['y'] ?? 0).toDouble(),
      placedId: map['placedId'] ?? '',
    );
  }
}
