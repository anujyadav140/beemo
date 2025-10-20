import 'package:cloud_firestore/cloud_firestore.dart';

class House {
  final String id;
  final String name;
  final int bedrooms;
  final int bathrooms;
  final DateTime createdAt;
  final String createdBy;
  final Map<String, HouseMember> members;
  final String inviteCode;

  House({
    required this.id,
    required this.name,
    required this.bedrooms,
    required this.bathrooms,
    required this.createdAt,
    required this.createdBy,
    required this.members,
    required this.inviteCode,
  });

  factory House.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    Map<String, dynamic> info = data['info'] ?? {};
    Map<String, dynamic> membersData = data['members'] ?? {};

    return House(
      id: doc.id,
      name: info['name'] ?? 'The Lab',
      bedrooms: info['bedrooms'] ?? 0,
      bathrooms: info['bathrooms'] ?? 0,
      createdAt: (info['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: info['createdBy'] ?? '',
      members: membersData.map((key, value) =>
        MapEntry(key, HouseMember.fromMap(value as Map<String, dynamic>))),
      inviteCode: data['inviteCode'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'info': {
        'name': name,
        'bedrooms': bedrooms,
        'bathrooms': bathrooms,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdBy': createdBy,
      },
      'members': members.map((key, value) => MapEntry(key, value.toMap())),
      'inviteCode': inviteCode,
    };
  }
}

class HouseMember {
  final String name;
  final String role;
  final DateTime joinedAt;

  HouseMember({
    required this.name,
    required this.role,
    required this.joinedAt,
  });

  factory HouseMember.fromMap(Map<String, dynamic> data) {
    return HouseMember(
      name: data['name'] ?? '',
      role: data['role'] ?? 'member',
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'role': role,
      'joinedAt': Timestamp.fromDate(joinedAt),
    };
  }
}
