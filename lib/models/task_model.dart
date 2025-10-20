import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  final String houseId;
  final String title;
  final String description;
  final String assignedTo;
  final String assignedToName;
  final String status;
  final DateTime? dueDate;
  final DateTime createdAt;
  final String createdBy;
  final String? confirmedBy;
  final DateTime? completedAt;

  Task({
    required this.id,
    required this.houseId,
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.assignedToName,
    required this.status,
    this.dueDate,
    required this.createdAt,
    required this.createdBy,
    this.confirmedBy,
    this.completedAt,
  });

  factory Task.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return Task(
      id: doc.id,
      houseId: data['houseId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      assignedTo: data['assignedTo'] ?? '',
      assignedToName: data['assignedToName'] ?? '',
      status: data['status'] ?? 'pending',
      dueDate: data['dueDate'] != null ? (data['dueDate'] as Timestamp).toDate() : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      confirmedBy: data['confirmedBy'],
      completedAt: data['completedAt'] != null ? (data['completedAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'houseId': houseId,
      'title': title,
      'description': description,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'status': status,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'confirmedBy': confirmedBy,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    };
  }
}
