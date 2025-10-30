import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String houseId;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String senderColor;
  final String message;
  final String messageType;
  final DateTime timestamp;
  final bool isBeemo;
  final List<PollOption>? pollOptions;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    required this.id,
    required this.houseId,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.senderColor,
    required this.message,
    required this.messageType,
    required this.timestamp,
    required this.isBeemo,
    this.pollOptions,
    this.metadata,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return ChatMessage(
      id: doc.id,
      houseId: data['houseId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderAvatar: data['senderAvatar'] ?? '',
      senderColor: data['senderColor'] ?? '#000000',
      message: data['message'] ?? '',
      messageType: data['messageType'] ?? 'text',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isBeemo: data['isBeemo'] ?? false,
      pollOptions: data['pollOptions'] != null
          ? (data['pollOptions'] as List).map((opt) => PollOption.fromMap(opt as Map<String, dynamic>)).toList()
          : null,
      metadata: data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'houseId': houseId,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'senderColor': senderColor,
      'message': message,
      'messageType': messageType,
      'timestamp': Timestamp.fromDate(timestamp),
      'isBeemo': isBeemo,
      'pollOptions': pollOptions?.map((opt) => opt.toMap()).toList(),
      'metadata': metadata,
    };
  }
}

class PollOption {
  final String option;
  final List<String> votes;

  PollOption({
    required this.option,
    required this.votes,
  });

  factory PollOption.fromMap(Map<String, dynamic> data) {
    return PollOption(
      option: data['option'] ?? '',
      votes: List<String>.from(data['votes'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'option': option,
      'votes': votes,
    };
  }
}
