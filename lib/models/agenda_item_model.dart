import 'package:cloud_firestore/cloud_firestore.dart';

class AgendaItem {
  final String id;
  final String houseId;
  final String title;
  final String details;
  final String priority;
  final String status;
  final DateTime createdAt;
  final String createdBy;
  final DateTime? scheduledFor;
  final DateTime? resolvedAt;

  AgendaItem({
    required this.id,
    required this.houseId,
    required this.title,
    required this.details,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    this.scheduledFor,
    this.resolvedAt,
  });

  factory AgendaItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return AgendaItem(
      id: doc.id,
      houseId: data['houseId'] ?? '',
      title: data['title'] ?? '',
      details: data['details'] ?? '',
      priority: data['priority'] ?? 'flexible',
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      scheduledFor: data['scheduledFor'] != null ? (data['scheduledFor'] as Timestamp).toDate() : null,
      resolvedAt: data['resolvedAt'] != null ? (data['resolvedAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'houseId': houseId,
      'title': title,
      'details': details,
      'priority': priority,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'scheduledFor': scheduledFor != null ? Timestamp.fromDate(scheduledFor!) : null,
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
    };
  }
}
