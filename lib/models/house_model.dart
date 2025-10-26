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
    Map<String, dynamic> info = {};

    // Handle info as either Map or other types from Firestore
    if (data['info'] is Map<String, dynamic>) {
      info = data['info'] as Map<String, dynamic>;
    } else if (data['info'] is Map) {
      info = Map<String, dynamic>.from(data['info'] as Map);
    }

    // Handle members as either Map or List from Firestore
    Map<String, HouseMember> parsedMembers = {};
    final membersData = data['members'];

    if (membersData is Map) {
      // If members is a Map, convert it
      parsedMembers = (membersData as Map<String, dynamic>).map((key, value) =>
        MapEntry(key, HouseMember.fromMap(value as Map<String, dynamic>)));
    } else if (membersData is List) {
      // If members is a List, convert it to a Map using index as key or member name
      for (var i = 0; i < membersData.length; i++) {
        if (membersData[i] is Map<String, dynamic>) {
          final memberMap = membersData[i] as Map<String, dynamic>;
          final memberName = memberMap['name'] ?? 'Member$i';
          parsedMembers[memberName] = HouseMember.fromMap(memberMap);
        }
      }
    }

    return House(
      id: doc.id,
      name: info['name'] ?? 'The Lab',
      bedrooms: info['bedrooms'] ?? 0,
      bathrooms: info['bathrooms'] ?? 0,
      createdAt: (info['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: info['createdBy'] ?? '',
      members: parsedMembers,
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
