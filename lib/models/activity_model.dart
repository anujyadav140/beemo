import 'package:cloud_firestore/cloud_firestore.dart';

class Activity {
  final String id;
  final String houseId;
  final String type;
  final String title;
  final String description;
  final DateTime createdAt;
  final String createdBy;
  final Map<String, dynamic> metadata;

  Activity({
    required this.id,
    required this.houseId,
    required this.type,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.createdBy,
    required this.metadata,
  });

  factory Activity.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return Activity(
      id: doc.id,
      houseId: data['houseId'] ?? '',
      type: data['type'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      metadata: Map<String, dynamic>.from(data['metadata'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'houseId': houseId,
      'type': type,
      'title': title,
      'description': description,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'metadata': metadata,
    };
  }
}
