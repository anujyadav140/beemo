import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../models/task_model.dart';
import '../models/chat_message_model.dart';
import '../models/meeting_model.dart';
import '../models/agenda_item_model.dart';
import '../models/house_model.dart';
import '../models/activity_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  // ============ HOUSE METHODS ============

  // Get user's house ID
  Future<String?> getUserHouseId(String userId) async {
    // Check if user is a member of any house
    QuerySnapshot housesQuery = await _firestore
        .collection('houses')
        .where('members.$userId', isNotEqualTo: null)
        .limit(1)
        .get();

    if (housesQuery.docs.isNotEmpty) {
      return housesQuery.docs.first.id;
    }

    return null;
  }

  Future<String> createHouse({
    required String name,
    required int bedrooms,
    required int bathrooms,
    required String userName,
  }) async {
    String userId = _auth.currentUser!.uid;
    String inviteCode = _generateInviteCode();

    DocumentReference houseRef = await _firestore.collection('houses').add({
      'info': {
        'name': name,
        'bedrooms': bedrooms,
        'bathrooms': bathrooms,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': userId,
      },
      'members': {
        userId: {
          'name': userName,
          'role': 'admin',
          'joinedAt': FieldValue.serverTimestamp(),
        }
      },
      'inviteCode': inviteCode,
    });

    return houseRef.id;
  }

  Future<void> joinHouse(String inviteCode, String userName) async {
    String userId = _auth.currentUser!.uid;

    QuerySnapshot houseQuery = await _firestore
        .collection('houses')
        .where('inviteCode', isEqualTo: inviteCode)
        .limit(1)
        .get();

    if (houseQuery.docs.isNotEmpty) {
      String houseId = houseQuery.docs.first.id;
      await _firestore.collection('houses').doc(houseId).update({
        'members.$userId': {
          'name': userName,
          'role': 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        }
      });
    } else {
      throw Exception('Invalid invite code');
    }
  }

  Stream<House?> getHouseStream(String houseId) {
    return _firestore
        .collection('houses')
        .doc(houseId)
        .snapshots()
        .map((doc) => doc.exists ? House.fromFirestore(doc) : null);
  }

  // ============ TASK METHODS ============

  Stream<List<Task>> getTasksStream(String houseId) {
    return _firestore
        .collection('tasks')
        .where('houseId', isEqualTo: houseId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList());
  }

  Future<void> createTask({
    required String houseId,
    required String title,
    required String assignedTo,
    required String assignedToName,
    String description = '',
    DateTime? dueDate,
  }) async {
    await _firestore.collection('tasks').add({
      'houseId': houseId,
      'title': title,
      'description': description,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'status': 'pending',
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate) : null,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser!.uid,
    });

    // Create activity
    await _createActivity(
      houseId: houseId,
      type: 'task_created',
      title: 'Task Created',
      description: '$assignedToName was assigned a new task',
      metadata: {'taskTitle': title},
    );
  }

  Future<void> updateTaskStatus(String taskId, String status) async {
    String userId = _auth.currentUser!.uid;

    // Get task details first
    DocumentSnapshot taskDoc = await _firestore.collection('tasks').doc(taskId).get();
    Map<String, dynamic> taskData = taskDoc.data() as Map<String, dynamic>;

    Map<String, dynamic> updates = {
      'status': status,
    };

    if (status == 'completed') {
      updates['confirmedBy'] = userId;
      updates['completedAt'] = FieldValue.serverTimestamp();

      // Award points
      await _firestore.collection('users').doc(userId).set({
        'profile': {
          'points': FieldValue.increment(10),
        },
      }, SetOptions(merge: true));

      // Create activity
      await _createActivity(
        houseId: taskData['houseId'],
        type: 'task_completed',
        title: 'Task Completed',
        description: '${taskData['assignedToName']} finished their task',
        metadata: {'taskTitle': taskData['title'], 'taskId': taskId},
      );
    }

    await _firestore.collection('tasks').doc(taskId).update(updates);
  }

  // ============ CHAT METHODS ============

  Stream<List<ChatMessage>> getChatMessagesStream(String houseId) {
    return _firestore
        .collection('chatMessages')
        .where('houseId', isEqualTo: houseId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList());
  }

  Future<void> sendMessage({
    required String houseId,
    required String message,
    required String senderName,
    required String senderAvatar,
    required String senderColor,
  }) async {
    await _firestore.collection('chatMessages').add({
      'houseId': houseId,
      'senderId': _auth.currentUser!.uid,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'senderColor': senderColor,
      'message': message,
      'messageType': 'text',
      'timestamp': FieldValue.serverTimestamp(),
      'isBeemo': false,
    });

    // Create activity for important messages (longer than 50 chars)
    if (message.length > 50) {
      await _createActivity(
        houseId: houseId,
        type: 'message',
        title: 'Message Sent',
        description: '$senderName sent a message to the group',
        metadata: {'messagePreview': message.substring(0, 50)},
      );
    }
  }

  Future<void> createPoll({
    required String houseId,
    required String question,
    required List<String> options,
  }) async {
    await _firestore.collection('chatMessages').add({
      'houseId': houseId,
      'senderId': 'beemo',
      'senderName': 'Beemo',
      'senderAvatar': '🤖',
      'senderColor': '#FFC400',
      'message': question,
      'messageType': 'poll',
      'timestamp': FieldValue.serverTimestamp(),
      'isBeemo': true,
      'pollOptions': options.map((opt) => {
        'option': opt,
        'votes': [],
      }).toList(),
    });
  }

  Future<void> voteOnPoll(String messageId, int optionIndex) async {
    String userId = _auth.currentUser!.uid;
    await _firestore.collection('chatMessages').doc(messageId).update({
      'pollOptions.$optionIndex.votes': FieldValue.arrayUnion([userId]),
    });
  }

  // ============ AGENDA METHODS ============

  Stream<List<AgendaItem>> getAgendaItemsStream(String houseId) {
    return _firestore
        .collection('agendaItems')
        .where('houseId', isEqualTo: houseId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => AgendaItem.fromFirestore(doc)).toList());
  }

  Future<void> createAgendaItem({
    required String houseId,
    required String title,
    required String details,
    required String priority,
  }) async {
    await _firestore.collection('agendaItems').add({
      'houseId': houseId,
      'title': title,
      'details': details,
      'priority': priority,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser!.uid,
    });

    // Award points
    await _firestore.collection('users').doc(_auth.currentUser!.uid).set({
      'profile': {
        'points': FieldValue.increment(5),
      },
    }, SetOptions(merge: true));

    // Create activity
    String priorityLabel = priority == 'meeting' ? 'for meeting' :
                          priority == 'chat' ? 'for group chat' :
                          'with flexible priority';
    await _createActivity(
      houseId: houseId,
      type: 'agenda_created',
      title: 'Agenda Created',
      description: 'New agenda item added $priorityLabel',
      metadata: {'agendaTitle': title, 'priority': priority},
    );

    // If priority is chat, post to group chat
    if (priority == 'chat') {
      await _firestore.collection('chatMessages').add({
        'houseId': houseId,
        'senderId': 'beemo',
        'senderName': 'Beemo',
        'senderAvatar': '🤖',
        'senderColor': '#FFC400',
        'message': '📋 New agenda item: $title\n\n$details',
        'messageType': 'text',
        'timestamp': FieldValue.serverTimestamp(),
        'isBeemo': true,
      });
    }
  }

  // ============ MEETING METHODS ============

  Stream<List<Meeting>> getMeetingsStream(String houseId) {
    return _firestore
        .collection('meetings')
        .where('houseId', isEqualTo: houseId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Meeting.fromFirestore(doc)).toList());
  }

  Future<void> createMeeting({
    required String houseId,
    required String title,
    required DateTime date,
    required int duration,
    required List<String> participantIds,
    required List<String> participantNames,
    required String agendaTopic,
    required List<String> problemsIdentified,
    required List<String> decisionsAndRules,
  }) async {
    await _firestore.collection('meetings').add({
      'houseId': houseId,
      'title': title,
      'date': Timestamp.fromDate(date),
      'duration': duration,
      'participants': participantIds,
      'participantNames': participantNames,
      'agendaTopic': agendaTopic,
      'problemsIdentified': problemsIdentified,
      'decisionsAndRules': decisionsAndRules,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser!.uid,
    });
  }

  // ============ TIMER METHODS ============

  Future<void> saveTimerSession({
    required String mode,
    required int duration,
  }) async {
    String userId = _auth.currentUser!.uid;
    String fieldName = mode == 'focus' ? 'totalFocusTime' : 'totalBreakTime';

    await _firestore.collection('users').doc(userId).set({
      'timerStats': {
        'sessionsCompleted': FieldValue.increment(1),
        fieldName: FieldValue.increment(duration),
      },
    }, SetOptions(merge: true));

    if (mode == 'focus') {
      await _firestore.collection('users').doc(userId).set({
        'profile': {
          'points': FieldValue.increment(5),
        },
      }, SetOptions(merge: true));
    }
  }

  // ============ NEXT MEETING METHODS ============

  Stream<DateTime?> getNextMeetingTimeStream(String houseId) {
    return _firestore
        .collection('nextMeetings')
        .doc(houseId)
        .snapshots()
        .map((doc) => doc.exists && doc.data()?['scheduledTime'] != null
            ? (doc.data()!['scheduledTime'] as Timestamp).toDate()
            : null);
  }

  Future<void> scheduleNextMeeting({
    required String houseId,
    required DateTime scheduledTime,
    bool recurring = false,
  }) async {
    await _firestore.collection('nextMeetings').doc(houseId).set({
      'scheduledTime': Timestamp.fromDate(scheduledTime),
      'recurring': recurring,
      'recurrencePattern': recurring ? 'weekly' : null,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  // ============ ACTIVITY METHODS ============

  Stream<List<Activity>> getActivitiesStream(String houseId) {
    return _firestore
        .collection('activities')
        .where('houseId', isEqualTo: houseId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Activity.fromFirestore(doc)).toList());
  }

  Future<Map<String, int>> getActivityCounts(String houseId) async {
    Map<String, int> counts = {
      'ideas': 0,
      'tasks': 0,
      'events': 0,
      'projects': 0,
    };

    for (String type in counts.keys) {
      QuerySnapshot snapshot = await _firestore
          .collection('activities')
          .where('houseId', isEqualTo: houseId)
          .where('type', isEqualTo: type)
          .get();
      counts[type] = snapshot.docs.length;
    }

    return counts;
  }

  // ============ USER METHODS ============

  Stream<int> getUserPointsStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.data()?['profile']?['points'] ?? 500);
  }

  Stream<Map<String, dynamic>> getTimerStatsStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.data()?['timerStats'] ?? {
          'sessionsCompleted': 0,
          'totalFocusTime': 0,
          'totalBreakTime': 0,
        });
  }

  // ============ HELPER METHODS ============

  String _generateInviteCode() {
    return _uuid.v4().substring(0, 8).toUpperCase();
  }

  Future<void> _createActivity({
    required String houseId,
    required String type,
    required String title,
    required String description,
    Map<String, dynamic>? metadata,
  }) async {
    await _firestore.collection('activities').add({
      'houseId': houseId,
      'type': type,
      'title': title,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser!.uid,
      'metadata': metadata ?? {},
    });
  }
}
