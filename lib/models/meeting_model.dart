import 'package:cloud_firestore/cloud_firestore.dart';

class Meeting {
  final String id;
  final String houseId;
  final String title;
  final DateTime date;
  final int duration;
  final List<String> participants;
  final List<String> participantNames;
  final String agendaTopic;
  final List<String> problemsIdentified;
  final List<String> decisionsAndRules;
  final DateTime createdAt;
  final String createdBy;

  Meeting({
    required this.id,
    required this.houseId,
    required this.title,
    required this.date,
    required this.duration,
    required this.participants,
    required this.participantNames,
    required this.agendaTopic,
    required this.problemsIdentified,
    required this.decisionsAndRules,
    required this.createdAt,
    required this.createdBy,
  });

  factory Meeting.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return Meeting(
      id: doc.id,
      houseId: data['houseId'] ?? '',
      title: data['title'] ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      duration: data['duration'] ?? 0,
      participants: List<String>.from(data['participants'] ?? []),
      participantNames: List<String>.from(data['participantNames'] ?? []),
      agendaTopic: data['agendaTopic'] ?? '',
      problemsIdentified: List<String>.from(data['problemsIdentified'] ?? []),
      decisionsAndRules: List<String>.from(data['decisionsAndRules'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'houseId': houseId,
      'title': title,
      'date': Timestamp.fromDate(date),
      'duration': duration,
      'participants': participants,
      'participantNames': participantNames,
      'agendaTopic': agendaTopic,
      'problemsIdentified': problemsIdentified,
      'decisionsAndRules': decisionsAndRules,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
    };
  }
}
