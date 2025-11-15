import 'dart:math';

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
  final Random _random = Random();

  /// Retry helper for transient Firestore errors with exponential backoff
  Future<T> _retryOperation<T>(
    Future<T> Function() operation, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 200),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      attempt++;
      try {
        return await operation();
      } catch (e) {
        // Check if it's a transient error we should retry
        final isTransientError = e.toString().contains('unavailable') ||
            e.toString().contains('deadline-exceeded') ||
            e.toString().contains('UNAVAILABLE') ||
            e.toString().contains('DEADLINE_EXCEEDED');

        if (attempt >= maxAttempts || !isTransientError) {
          print('❌ Operation failed after $attempt attempts: $e');
          rethrow;
        }

        print('⚠️  Transient error on attempt $attempt/$maxAttempts, retrying in ${delay.inMilliseconds}ms: $e');
        await Future.delayed(delay);

        // Exponential backoff with jitter
        delay = Duration(
          milliseconds: (delay.inMilliseconds * 2) + _random.nextInt(100),
        );
      }
    }
  }

  CollectionReference<Map<String, dynamic>> _taskLedgerCollection(String houseId) {
    return _firestore.collection('houses').doc(houseId).collection('taskLedger');
  }

  CollectionReference<Map<String, dynamic>> _taskAssignmentSessions(String houseId) {
    return _firestore.collection('houses').doc(houseId).collection('taskAssignmentSessions');
  }

  // Ensure the user's profile document exists with default values.
  Future<void> ensureUserDocument({
    required String userId,
    required String displayName,
    required String email,
    String? avatarUrl,
  }) async {
    final docRef = _firestore.collection('users').doc(userId);
    final snapshot = await _retryOperation(() => docRef.get());

    if (snapshot.exists) {
      return;
    }

    final name = displayName.isNotEmpty ? displayName : 'Beemo Member';

    await docRef.set({
      'profile': {
        'name': name,
        'email': email,
        'avatarUrl': avatarUrl ?? '',
        'initials': _deriveInitials(name),
        'points': 500,
        'pronouns': '',
      },
      'settings': {
        'notifications': true,
        'theme': 'light',
        'language': 'en',
      },
      'timerStats': {
        'sessionsCompleted': 0,
        'totalFocusTime': 0,
        'totalBreakTime': 0,
      },
      'hasCompletedGetStarted': false,
      'hasCompletedAvatarSelection': false,
      'hasCompletedHouseSetup': false,
      'hasCompletedOnboarding': false,
      'houseId': null,
      'houseName': null,
      'houseRole': null,
    });
  }

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
      'houseName': name,
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
          'coins': 0,
          'purchasedItems': [],
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
          'coins': 0,
          'purchasedItems': [],
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

  // ============ COIN MANAGEMENT METHODS ============

  /// Award coins to a user in a house
  Future<void> awardCoins({
    required String houseId,
    required String userId,
    required int amount,
  }) async {
    try {
      await _firestore.collection('houses').doc(houseId).update({
        'members.$userId.coins': FieldValue.increment(amount),
      });
      print('DEBUG: Awarded $amount coins to user $userId in house $houseId');
    } catch (e) {
      print('ERROR: Failed to award coins: $e');
      rethrow;
    }
  }

  /// Get user's coin count in a specific house
  Future<int> getUserCoins({
    required String houseId,
    required String userId,
  }) async {
    try {
      final houseDoc = await _firestore.collection('houses').doc(houseId).get();
      if (!houseDoc.exists) {
        return 0;
      }
      final data = houseDoc.data() as Map<String, dynamic>?;
      final members = data?['members'] as Map<String, dynamic>?;
      final userMember = members?[userId] as Map<String, dynamic>?;
      return (userMember?['coins'] ?? 0) as int;
    } catch (e) {
      print('ERROR: Failed to get user coins: $e');
      return 0;
    }
  }

  /// Stream of user's coins in a specific house
  Stream<int> getUserCoinsStream({
    required String houseId,
    required String userId,
  }) {
    return _firestore
        .collection('houses')
        .doc(houseId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return 0;
      final data = doc.data() as Map<String, dynamic>?;
      final members = data?['members'] as Map<String, dynamic>?;
      final userMember = members?[userId] as Map<String, dynamic>?;
      return (userMember?['coins'] ?? 0) as int;
    });
  }

  /// Purchase an item (wall color, floor color, etc.)
  /// Returns true if purchase successful, false if insufficient coins
  Future<bool> purchaseItem({
    required String houseId,
    required String userId,
    required String itemId,
    required int cost,
  }) async {
    try {
      // Use transaction to ensure atomic coin deduction and item purchase
      bool success = false;
      await _firestore.runTransaction((transaction) async {
        final houseRef = _firestore.collection('houses').doc(houseId);
        final houseDoc = await transaction.get(houseRef);

        if (!houseDoc.exists) {
          return;
        }

        final data = houseDoc.data() as Map<String, dynamic>?;
        final members = data?['members'] as Map<String, dynamic>?;
        final userMember = members?[userId] as Map<String, dynamic>?;

        final currentCoins = (userMember?['coins'] ?? 0) as int;
        final purchasedItems = List<String>.from(userMember?['purchasedItems'] ?? []);

        // Check if already purchased
        if (purchasedItems.contains(itemId)) {
          success = true; // Already owned
          return;
        }

        // Check if enough coins
        if (currentCoins < cost) {
          success = false;
          return;
        }

        // Deduct coins and add item
        purchasedItems.add(itemId);
        transaction.update(houseRef, {
          'members.$userId.coins': currentCoins - cost,
          'members.$userId.purchasedItems': purchasedItems,
        });

        success = true;
      });

      if (success) {
        print('DEBUG: User $userId purchased $itemId for $cost coins');
      }
      return success;
    } catch (e) {
      print('ERROR: Failed to purchase item: $e');
      return false;
    }
  }

  /// Check if user owns an item
  Future<bool> ownsItem({
    required String houseId,
    required String userId,
    required String itemId,
  }) async {
    try {
      final houseDoc = await _firestore.collection('houses').doc(houseId).get();
      if (!houseDoc.exists) {
        return false;
      }
      final data = houseDoc.data() as Map<String, dynamic>?;
      final members = data?['members'] as Map<String, dynamic>?;
      final userMember = members?[userId] as Map<String, dynamic>?;
      final purchasedItems = List<String>.from(userMember?['purchasedItems'] ?? []);
      return purchasedItems.contains(itemId);
    } catch (e) {
      print('ERROR: Failed to check item ownership: $e');
      return false;
    }
  }

  /// Get list of all purchased items for a user
  Stream<List<String>> getPurchasedItemsStream({
    required String houseId,
    required String userId,
  }) {
    return _firestore
        .collection('houses')
        .doc(houseId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return <String>[];
      final data = doc.data() as Map<String, dynamic>?;
      final members = data?['members'] as Map<String, dynamic>?;
      final userMember = members?[userId] as Map<String, dynamic>?;
      return List<String>.from(userMember?['purchasedItems'] ?? []);
    });
  }

  // ============ TASK METHODS ============

  Stream<List<Task>> getTasksStream(String houseId) {
    return _firestore
        .collection('tasks')
        .where('houseId', isEqualTo: houseId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          // Return all tasks including completed ones, but EXCLUDE archived tasks
          // The Tasks page needs to show completed tasks with checkmarks
          return snapshot.docs
              .where((doc) {
                final status = (doc.data()['status'] ?? '').toString().toLowerCase();
                return status != 'archived';
              })
              .map((doc) => Task.fromFirestore(doc))
              .toList();
        });
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

  /// Get house members for AI analysis
  Future<List<Map<String, String>>> getHouseMembers(String houseId) async {
    try {
      print('DEBUG [getHouseMembers]: Fetching house doc for $houseId');
      DocumentSnapshot houseDoc = await _retryOperation(
        () => _firestore.collection('houses').doc(houseId).get(),
      );

      if (!houseDoc.exists) {
        print('DEBUG [getHouseMembers]: House document does not exist!');
        return [];
      }

      Map<String, dynamic> houseData = houseDoc.data() as Map<String, dynamic>;
      print('DEBUG [getHouseMembers]: House data keys: ${houseData.keys.toList()}');
      print('DEBUG [getHouseMembers]: Full house data: $houseData');

      var membersData = houseData['members'];
      print('DEBUG [getHouseMembers]: Members data type: ${membersData.runtimeType}');
      print('DEBUG [getHouseMembers]: Members data: $membersData');

      List<Map<String, String>> membersList = [];

      // Handle multiple formats
      if (membersData is Map) {
        print('DEBUG [getHouseMembers]: Processing as Map, ${membersData.length} entries');

        membersData.forEach((key, value) {
          print('DEBUG [getHouseMembers]: Processing entry $key: $value (type: ${value.runtimeType})');

          // Case 1: Value is a Map with member details {name: "John", role: "admin"}
          if (value is Map) {
            final userId = key.toString();
            final name = value['name']?.toString() ?? 'Member';
            membersList.add({
              'id': userId,
              'name': name,
            });
            print('DEBUG [getHouseMembers]: Added member from Map: $userId -> $name');
          }
          // Case 2: Value is a String (the user ID itself)
          else if (value is String) {
            final userId = value;
            membersList.add({
              'id': userId,
              'name': 'Member', // Will try to fetch name from users collection later
            });
            print('DEBUG [getHouseMembers]: Added member from String: $userId');
          }
        });
      } else if (membersData is List) {
        print('DEBUG [getHouseMembers]: Processing as List, ${membersData.length} entries');

        for (var item in membersData) {
          // Case 1: List item is a Map {id: "userId", name: "John"}
          if (item is Map) {
            final userId = item['id']?.toString() ?? '';
            final name = item['name']?.toString() ?? 'Member';
            if (userId.isNotEmpty) {
              membersList.add({
                'id': userId,
                'name': name,
              });
              print('DEBUG [getHouseMembers]: Added member from List Map: $userId -> $name');
            }
          }
          // Case 2: List item is a String (user ID)
          else if (item is String) {
            membersList.add({
              'id': item,
              'name': 'Member',
            });
            print('DEBUG [getHouseMembers]: Added member from List String: $item');
          }
        }
      } else if (membersData == null) {
        print('DEBUG [getHouseMembers]: ERROR - members field is null!');
      } else {
        print('DEBUG [getHouseMembers]: ERROR - Unknown members data type: ${membersData.runtimeType}');
      }

      // Fetch real names from users collection for members with default names
      for (int i = 0; i < membersList.length; i++) {
        if (membersList[i]['name'] == 'Member') {
          try {
            final userId = membersList[i]['id']!;
            final userDoc = await _retryOperation(
              () => _firestore.collection('users').doc(userId).get(),
            );
            if (userDoc.exists) {
              final userData = userDoc.data();
              final realName = userData?['profile']?['name']?.toString();
              if (realName != null && realName.trim().isNotEmpty) {
                membersList[i]['name'] = realName.trim();
                print('DEBUG [getHouseMembers]: Fetched real name for $userId: $realName');
              }
            }
          } catch (e) {
            print('DEBUG [getHouseMembers]: Could not fetch name for ${membersList[i]['id']}: $e');
          }
        }
      }

      print('DEBUG [getHouseMembers]: Returning ${membersList.length} members');
      for (var member in membersList) {
        print('DEBUG [getHouseMembers]: Member: ${member['name']} (${member['id']})');
      }

      return membersList;
    } catch (e, stackTrace) {
      print('DEBUG [getHouseMembers]: ERROR loading house members: $e');
      print('DEBUG [getHouseMembers]: Stack trace: $stackTrace');
      return [];
    }
  }

  /// Create a task from an AI-detected chat message or automated assignment
  Future<String?> createTaskFromAI({
    required String houseId,
    required String title,
    required String description,
    String? assignedTo,
    String? assignedToName,
    DateTime? dueDate,
    required String sourceMessage,
    String assignmentContext = "ai_detection",
    String? requestedByName,
    bool notify = true,
    bool allowUnassigned = false, // NEW: Allow truly unassigned tasks
  }) async {
    final tasksCollection = _firestore.collection("tasks");

    final existingBySource = await tasksCollection
        .where("houseId", isEqualTo: houseId)
        .where("sourceMessage", isEqualTo: sourceMessage)
        .limit(5)
        .get();

    // Filter out archived tasks - only return if there's a NON-archived task with same source
    final nonArchivedExisting = existingBySource.docs.where((doc) {
      final status = (doc.data()["status"] ?? "").toString().toLowerCase();
      return status != "archived";
    }).toList();

    if (nonArchivedExisting.isNotEmpty) {
      print('DEBUG: Found existing non-archived task with same sourceMessage: ${nonArchivedExisting.first.id}');
      return nonArchivedExisting.first.id;
    }

    final existingWithTitle = await tasksCollection
        .where("houseId", isEqualTo: houseId)
        .where("title", isEqualTo: title)
        .limit(5)
        .get();
    final hasOpenWithTitle = existingWithTitle.docs.any((doc) {
      final data = doc.data();
      final status = (data["status"] ?? "").toString().toLowerCase();
      return status != "completed" && status != "archived";
    });
    if (hasOpenWithTitle) {
      return null;
    }

    // Only auto-assign if not explicitly allowing unassigned
    if (!allowUnassigned && (assignedTo == null || assignedTo.isEmpty || assignedToName == null || assignedToName.isEmpty)) {
      final fairAssignee = await _pickFairAssignee(houseId);
      if (fairAssignee != null) {
        assignedTo = fairAssignee.userId;
        assignedToName = fairAssignee.userName;
      } else {
        final members = await getHouseMembers(houseId);
        if (members.isNotEmpty) {
          assignedTo = members.first["id"]!;
          assignedToName = members.first["name"]!;
        } else {
          assignedTo = _auth.currentUser!.uid;
          assignedToName = _auth.currentUser!.displayName ?? "Housemate";
        }
      }
    }

    // Ensure empty strings for unassigned tasks
    assignedTo = assignedTo ?? '';
    assignedToName = assignedToName ?? '';

    // Determine status based on whether task is assigned
    final bool isUnassigned = assignedTo.isEmpty || assignedToName.isEmpty;
    final taskStatus = isUnassigned ? "unassigned" : "pending";

    print('DEBUG [createTaskFromAI]: Creating task with status=$taskStatus, assignedTo="$assignedTo", assignedToName="$assignedToName", allowUnassigned=$allowUnassigned');

    final taskRef = await tasksCollection.add({
      "houseId": houseId,
      "title": title,
      "description": description,
      "assignedTo": assignedTo,
      "assignedToName": assignedToName,
      "status": taskStatus,
      "dueDate": dueDate != null ? Timestamp.fromDate(dueDate) : null,
      "createdAt": FieldValue.serverTimestamp(),
      "createdBy": "ai_agent",
      "sourceMessage": sourceMessage,
      "assignmentContext": assignmentContext,
    });

    await _createActivity(
      houseId: houseId,
      type: "task_created",
      title: "Task Created (AI)",
      description: isUnassigned
          ? 'Beemo logged "$title" as an unassigned task'
          : 'Beemo logged "$title" and assigned it to $assignedToName',
      metadata: {
        "taskTitle": title,
        "aiDetected": assignmentContext,
        "assignedTo": assignedTo,
      },
    );

    if (notify && !isUnassigned) {
      final confirmation = _composeTaskConfirmationMessage(
        title: title,
        assignedToName: assignedToName,
        assignmentContext: assignmentContext,
        requestedByName: requestedByName,
      );
      await sendBeemoMessage(
        houseId: houseId,
        message: confirmation,
      );
    }

    return taskRef.id;
  }

  String _composeTaskConfirmationMessage({
    required String title,
    required String? assignedToName,
    required String assignmentContext,
    String? requestedByName,
  }) {
    final assignee = (assignedToName ?? "someone");
    final requester = requestedByName != null && requestedByName.trim().isNotEmpty
        ? requestedByName.trim()
        : null;

    switch (assignmentContext) {
      case "volunteer_chat":
        return 'Thanks, ' + assignee + '! I added "' + title + '" to your task list so it stays on everyone''s radar.';
      case "auto_chat":
        return 'No one volunteered, so I assigned "' + title + '" to ' + assignee + ' using our task ledger. Let me know if we should swap it around.';
      case "manual_chat":
        return 'You got it. I assigned "' + title + '" to ' + assignee + ' just now.';
      case "direct_request":
        final prefix = requester != null ? requester + ' asked for this. ' : '';
        return prefix + '"' + title + '" is logged and assigned to ' + assignee + '.';
      default:
        final prefix = requester != null ? requester + ' flagged a new task. ' : '';
        return prefix + 'I added "' + title + '" and assigned it to ' + assignee + '.';
    }
  }

  Future<Map<String, dynamic>?> startChatTaskSession({
    required String houseId,
    required String title,
    required String description,
    required String sourceMessage,
    required String requestedById,
    required String requestedByName,
  }) async {
    try {
      print('🚀 [startChatTaskSession] Starting for: "$title"');

      // ONLY check for duplicate if there's an ACTIVE session created very recently (within 30 seconds)
      // This prevents race conditions but ALLOWS recurring chores like "clean the table"
      print('🔍 [startChatTaskSession] Checking for duplicate session within last 30 seconds...');

      // Get recent sessions for this source message
      final recentSessions = await _taskAssignmentSessions(houseId)
          .where('sourceMessage', isEqualTo: sourceMessage)
          .limit(10)
          .get();

      print('   Found ${recentSessions.docs.length} previous sessions with same message');

      // Check if any are still active and created in last 30 seconds
      for (final doc in recentSessions.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'] as Timestamp?;
        final status = data['status']?.toString() ?? '';

        if (createdAt != null) {
          final createdTime = createdAt.toDate();
          final ageInSeconds = DateTime.now().difference(createdTime).inSeconds;

          print('   Session ${doc.id}: status=$status, age=${ageInSeconds}s');

          if (ageInSeconds <= 30 &&
              (status == 'awaiting_volunteers' || status == 'awaiting_confirmation')) {
            print('⚠️  [startChatTaskSession] Active session from last 30 seconds already exists, skipping to prevent duplicate');
            return {...data, 'id': doc.id};
          }
        }
      }

      print('✅ [startChatTaskSession] No recent duplicate found, creating new task!');

      print('📊 [startChatTaskSession] Loading task workload snapshot...');
      final loads = await _loadTaskLoadSnapshot(
        houseId,
        requesterId: requestedById,
        requesterName: requestedByName,
      );

      final docRef = _taskAssignmentSessions(houseId).doc();
      final now = DateTime.now();

      // Get custom auto-assign duration (defaults to 2 minutes)
      final autoAssignMinutes = await getAutoAssignMinutes(houseId);
      final autoAssignAt = Timestamp.fromDate(now.add(Duration(minutes: autoAssignMinutes)));
      print('⏱️  [startChatTaskSession] Auto-assign set for $autoAssignMinutes minutes');

      final friendlyTitle = _sanitizeTaskLine(title, description);

      final ledgerNote = _buildLedgerSnapshotNote(loads);
      final trimmedName = requestedByName.trim();
      final opener = trimmedName.isEmpty
          ? 'Hey everyone, we have **"$friendlyTitle"** on the list.'
          : 'Hey everyone, **$trimmedName** asked if anyone can **"$friendlyTitle"**.';
      final fairnessLine = trimmedName.isEmpty
          ? "I'll only assign it back to the requester if they're behind on recent completions."
          : "I'll only assign it back to **$trimmedName** if they're behind on recent completions.";

      // Format duration nicely
      final durationText = autoAssignMinutes >= 60
          ? '**${autoAssignMinutes ~/ 60} ${autoAssignMinutes ~/ 60 == 1 ? 'hour' : 'hours'}**'
          : '**$autoAssignMinutes ${autoAssignMinutes == 1 ? 'minute' : 'minutes'}**';

      final message = '$opener\n\nIf you can help, just say so (like "I\'ll take it" or "I can do that"). '
          'Otherwise I\'ll auto-assign someone fairly in about $durationText. $fairnessLine$ledgerNote';

      print('💬 [startChatTaskSession] Sending Beemo message...');
      final messageId = await sendBeemoMessage(
        houseId: houseId,
        message: message,
        metadata: {
          'assignmentSessionId': docRef.id,
          'autoAssignAt': autoAssignAt,
        },
      );
      print('✅ [startChatTaskSession] Beemo message sent, ID: $messageId');

      // Create an unassigned task immediately so it appears in the tasks list
      print('📝 [startChatTaskSession] Creating unassigned task...');
      final unassignedTaskId = await createTaskFromAI(
        houseId: houseId,
        title: title,
        description: description,
        assignedTo: '',
        assignedToName: '',
        sourceMessage: sourceMessage,
        assignmentContext: 'awaiting_assignment',
        allowUnassigned: true,
        notify: false,
      );
      print('✅ [startChatTaskSession] Task created, ID: $unassignedTaskId');

      // Create an agenda item so it appears in "This week's items"
      print('📋 [startChatTaskSession] Creating agenda item...');
      final agendaItemRef = await _firestore.collection('agendaItems').add({
        'houseId': houseId,
        'title': title,
        'details': description,
        'priority': 'chat',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': requestedById,
        'sourceMessage': sourceMessage,
        'assignmentSessionId': docRef.id,
      });
      print('✅ [startChatTaskSession] Agenda item created, ID: ${agendaItemRef.id}');

      print('💾 [startChatTaskSession] Saving assignment session...');
      await docRef.set({
      'id': docRef.id,
      'houseId': houseId,
      'sourceType': 'chat',
      'status': 'awaiting_volunteers',
      'taskTitle': title,
      'taskDescription': description,
      'agendaTitle': title,
      'agendaDetails': description,
      'agendaItemId': agendaItemRef.id,
      'requestedById': requestedById,
      'requestedByName': requestedByName,
      'sourceMessage': sourceMessage,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
      'autoAssignAt': autoAssignAt,
      'volunteers': <String>[],
      'passes': <String>[],
      'ranking': loads.map((load) => load.toFirestore()).toList(),
      'messageId': messageId,
      'unassignedTaskId': unassignedTaskId, // Track the unassigned task
    });
      print('✅ [startChatTaskSession] Assignment session saved successfully');

      print('🎉 [startChatTaskSession] COMPLETED SUCCESSFULLY for: "$title"');
      return {
        'id': docRef.id,
        'houseId': houseId,
        'sourceType': 'chat',
        'status': 'awaiting_volunteers',
        'taskTitle': title,
        'taskDescription': description,
        'requestedById': requestedById,
        'requestedByName': requestedByName,
        'sourceMessage': sourceMessage,
        'autoAssignAt': autoAssignAt,
        'passes': <String>[],
      };
    } catch (e, stackTrace) {
      print('❌ [startChatTaskSession] FAILED with error: $e');
      print('📚 [startChatTaskSession] Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<bool> finalizeChatTaskWithVolunteer({
    required String houseId,
    required Map<String, dynamic> sessionData,
    required String volunteerId,
    required String volunteerName,
  }) async {
    final sessionId = sessionData['id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      return false;
    }
    final status = sessionData['status']?.toString() ?? '';
    if (status == 'assigned') {
      return false;
    }

    final title = sessionData['taskTitle']?.toString() ?? 'Task';
    final description = sessionData['taskDescription']?.toString() ?? '';
    final sourceMessage = sessionData['sourceMessage']?.toString() ?? sessionId;
    final unassignedTaskId = sessionData['unassignedTaskId']?.toString();

    print('DEBUG: ========== VOLUNTEER ASSIGNMENT START ==========');
    print('DEBUG: Volunteer $volunteerName is taking task "$title"');
    print('DEBUG: Unassigned task ID from session: $unassignedTaskId');

    // AGGRESSIVE FIX: Find and archive ALL unassigned tasks with this title
    print('DEBUG: Finding ALL unassigned tasks with title "$title" in house $houseId');
    final allTasksQuery = await _firestore.collection('tasks')
        .where('houseId', isEqualTo: houseId)
        .where('title', isEqualTo: title)
        .get();

    final unassignedTasksToArchive = <String>[];
    for (var doc in allTasksQuery.docs) {
      final data = doc.data();
      final assignedTo = (data['assignedTo'] ?? '').toString().trim();
      final assignedToName = (data['assignedToName'] ?? '').toString().trim();
      final status = (data['status'] ?? '').toString().toLowerCase();

      // Task is unassigned if both assignedTo and assignedToName are empty AND not already archived
      if (assignedTo.isEmpty && assignedToName.isEmpty && status != 'archived') {
        print('DEBUG: Found unassigned task: ${doc.id}');
        unassignedTasksToArchive.add(doc.id);
      }
    }

    print('DEBUG: Found ${unassignedTasksToArchive.length} unassigned tasks to archive');

    // Archive all unassigned tasks NOW before creating assigned task
    for (var taskIdToArchive in unassignedTasksToArchive) {
      try {
        print('DEBUG: Archiving unassigned task $taskIdToArchive');
        await _firestore.collection('tasks').doc(taskIdToArchive).update({
          'status': 'archived',
          'archivedReason': 'volunteer_assigned',
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        print('DEBUG: Successfully archived $taskIdToArchive');
      } catch (e) {
        print('DEBUG: ERROR archiving task $taskIdToArchive: $e');
      }
    }

    // Now create the assigned task
    print('DEBUG: Creating new assigned task for $volunteerName');
    final taskId = await createTaskFromAI(
      houseId: houseId,
      title: title,
      description: description,
      assignedTo: volunteerId,
      assignedToName: volunteerName,
      sourceMessage: sourceMessage,
      assignmentContext: 'volunteer_chat',
      requestedByName: sessionData['requestedByName']?.toString(),
      notify: false,
    );

    if (taskId == null) {
      print('DEBUG: CRITICAL ERROR - Could not create assigned task');
      return false;
    }

    print('DEBUG: Successfully created assigned task $taskId for $volunteerName');
    print('DEBUG: ========== VOLUNTEER ASSIGNMENT END ==========');

    await _taskAssignmentSessions(houseId).doc(sessionId).set({
      'status': 'assigned',
      'assignedToId': volunteerId,
      'assignedToName': volunteerName,
      'assignmentReason': 'volunteer',
      'assignedTaskId': taskId,
      'volunteers': FieldValue.arrayUnion([volunteerId]),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update agenda item if it exists
    final agendaItemId = sessionData['agendaItemId']?.toString();
    if (agendaItemId != null && agendaItemId.isNotEmpty) {
      await _firestore.collection('agendaItems').doc(agendaItemId).update({
        'status': 'assigned',
        'assignedTo': volunteerId,
        'assignedToName': volunteerName,
        'assignedTaskId': taskId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    // Update the original message to show task has been assigned
    final messageId = sessionData['messageId']?.toString();
    if (messageId != null && messageId.isNotEmpty) {
      try {
        await updateMessageWithAssignment(
          messageId: messageId,
          assignedToName: volunteerName,
          assignmentReason: 'volunteer',
        );
      } catch (e) {
        print('Could not update message with assignment: $e');
      }
    }

    await sendBeemoMessage(
      houseId: houseId,
      message:
          'Thanks, $volunteerName! I logged "$title" under your tasks so everyone knows it\'s covered.',
    );

    return true;
  }

  Future<bool> autoAssignChatTask({
    required String houseId,
    required Map<String, dynamic> sessionData,
    String assignmentContext = 'auto_chat',
  }) async {
    final sessionId = sessionData['id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      print('DEBUG: No session ID found');
      return false;
    }
    final status = sessionData['status']?.toString() ?? '';
    if (status == 'assigned' || status == 'assigning') {
      print('DEBUG: Task already assigned or being assigned (status: $status)');
      return false;
    }

    print('DEBUG: Auto-assigning task for session $sessionId in house $houseId');

    // CRITICAL: Immediately claim this session to prevent duplicate assignments
    // Use an atomic update to ensure only ONE call wins the race
    print('DEBUG: Attempting to claim session with atomic status update...');
    try {
      final sessionRef = _taskAssignmentSessions(houseId).doc(sessionId);
      final sessionSnapshot = await sessionRef.get();

      if (!sessionSnapshot.exists) {
        print('DEBUG: Session no longer exists, aborting');
        return false;
      }

      final currentStatus = sessionSnapshot.data()?['status']?.toString() ?? '';
      if (currentStatus == 'assigned' || currentStatus == 'assigning') {
        print('DEBUG: Session already claimed by another process (status: $currentStatus)');
        return false;
      }

      // Claim the session by updating status to 'assigning'
      await sessionRef.update({
        'status': 'assigning',
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('DEBUG: ✅ Successfully claimed session! Proceeding with assignment...');
    } catch (e) {
      print('DEBUG: ❌ Failed to claim session: $e');
      return false;
    }

    final passes =
        ((sessionData['passes'] as List<dynamic>?) ?? const []).map((value) => value.toString()).toSet();
    final requesterId = sessionData['requestedById']?.toString();
    final requesterName = (sessionData['requestedByName']?.toString() ?? '').trim();

    print('DEBUG: Loading task load snapshot...');
    final loads = await _loadTaskLoadSnapshot(
      houseId,
      requesterId: requesterId,
      requesterName: requesterName,
    );
    print('DEBUG: Loaded ${loads.length} members from task ledger');

    if (loads.isEmpty) {
      print('DEBUG: ERROR - No house members found!');
      await sendBeemoMessage(
        houseId: houseId,
        message:
            'I couldn\'t find any house members to assign this task to. Please check your house setup.',
      );
      return false;
    }

    print('DEBUG: Selecting candidate (requester: $requesterId, excluded: ${passes.length})');

    final assignmentResult = _selectCandidateFromLoads(
      loads,
      excludedIds: passes,
      requesterId: requesterId,
    );

    if (assignmentResult == null) {
      print('DEBUG: ERROR - Selection returned null!');
      await sendBeemoMessage(
        houseId: houseId,
        message:
            'I tried to assign this fairly but couldn\'t find a good fit. Anyone able to volunteer?',
      );
      return false;
    }

    print('DEBUG: Selected ${assignmentResult.candidate.userName} for assignment');

    final candidate = assignmentResult.candidate;
    // Support both chat tasks (taskTitle/taskDescription) and agenda items (agendaTitle/agendaDetails)
    final title = sessionData['taskTitle']?.toString() ??
                  sessionData['agendaTitle']?.toString() ?? 'Task';
    final description = sessionData['taskDescription']?.toString() ??
                        sessionData['agendaDetails']?.toString() ?? '';
    final sourceMessage = sessionData['sourceMessage']?.toString() ?? sessionId;
    final unassignedTaskId = sessionData['unassignedTaskId']?.toString();

    print('DEBUG: ========== AUTO ASSIGNMENT START ==========');
    print('DEBUG: Auto-assigning task "$title" to ${candidate.userName}');
    print('DEBUG: Unassigned task ID from session: $unassignedTaskId');

    // AGGRESSIVE FIX: Find and archive ALL unassigned tasks with this title
    print('DEBUG: Finding ALL unassigned tasks with title "$title" in house $houseId');
    final allTasksQuery = await _firestore.collection('tasks')
        .where('houseId', isEqualTo: houseId)
        .where('title', isEqualTo: title)
        .get();

    final unassignedTasksToArchive = <String>[];
    for (var doc in allTasksQuery.docs) {
      final data = doc.data();
      final assignedTo = (data['assignedTo'] ?? '').toString().trim();
      final assignedToName = (data['assignedToName'] ?? '').toString().trim();
      final status = (data['status'] ?? '').toString().toLowerCase();

      // Task is unassigned if both assignedTo and assignedToName are empty AND not already archived
      if (assignedTo.isEmpty && assignedToName.isEmpty && status != 'archived') {
        print('DEBUG: Found unassigned task: ${doc.id}');
        unassignedTasksToArchive.add(doc.id);
      }
    }

    print('DEBUG: Found ${unassignedTasksToArchive.length} unassigned tasks to archive');

    // Archive all unassigned tasks NOW before creating assigned task
    for (var taskIdToArchive in unassignedTasksToArchive) {
      try {
        print('DEBUG: Archiving unassigned task $taskIdToArchive');
        await _firestore.collection('tasks').doc(taskIdToArchive).update({
          'status': 'archived',
          'archivedReason': 'auto_assigned',
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        print('DEBUG: Successfully archived $taskIdToArchive');
      } catch (e) {
        print('DEBUG: ERROR archiving task $taskIdToArchive: $e');
      }
    }

    // Now create the assigned task
    print('DEBUG: Creating new assigned task for ${candidate.userName}');
    final taskId = await createTaskFromAI(
      houseId: houseId,
      title: title,
      description: description,
      assignedTo: candidate.userId,
      assignedToName: candidate.userName,
      sourceMessage: sourceMessage,
      assignmentContext: assignmentContext,
      requestedByName: sessionData['requestedByName']?.toString(),
      notify: false,
    );

    if (taskId == null) {
      print('DEBUG: CRITICAL ERROR - Could not create assigned task');
      return false;
    }

    print('DEBUG: Successfully created assigned task $taskId for ${candidate.userName}');
    print('DEBUG: ========== AUTO ASSIGNMENT END ==========');

    await _taskAssignmentSessions(houseId).doc(sessionId).set({
      'status': 'assigned',
      'assignedToId': candidate.userId,
      'assignedToName': candidate.userName,
      'assignmentReason': assignmentContext,
      'assignedTaskId': taskId,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update agenda item if it exists
    final agendaItemId = sessionData['agendaItemId']?.toString();
    if (agendaItemId != null && agendaItemId.isNotEmpty) {
      await _firestore.collection('agendaItems').doc(agendaItemId).update({
        'status': 'assigned',
        'assignedTo': candidate.userId,
        'assignedToName': candidate.userName,
        'assignedTaskId': taskId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    // Update the original message to show task has been assigned
    final messageId = sessionData['messageId']?.toString();
    if (messageId != null && messageId.isNotEmpty) {
      try {
        await updateMessageWithAssignment(
          messageId: messageId,
          assignedToName: candidate.userName,
          assignmentReason: assignmentContext,
        );
      } catch (e) {
        print('Could not update message with assignment: $e');
      }
    }

    late final String reasonMessage;

    // Check if it was a random selection due to tie
    if (assignmentResult.wasRandomSelection) {
      final tiedNames = assignmentResult.tiedCandidateNames ?? [];
      final namesDisplay = tiedNames.length > 3
          ? '${tiedNames.take(3).join(', ')} and ${tiedNames.length - 3} others'
          : tiedNames.join(', ');

      // Special message when everyone has 0 tasks
      if (candidate.weeklyCount == 0 && candidate.monthlyCount == 0 && candidate.pendingCount == 0) {
        reasonMessage = 'No one volunteered, so I picked randomly between $namesDisplay '
            'since nobody has any pending or completed tasks yet. "${title}" goes to ${candidate.userName}. '
            'Feel free to swap if needed!';
      } else {
        reasonMessage = 'No one volunteered, so I picked randomly between $namesDisplay '
            'since you all have the same workload (${candidate.pendingCount} pending, ${candidate.weeklyCount} completed this week). '
            '"${title}" goes to ${candidate.userName}. Feel free to swap if needed!';
      }
    } else if (candidate.userId == requesterId && requesterName.isNotEmpty) {
      reasonMessage = assignmentContext == 'manual_chat'
          ? '$requesterName has fewer tasks right now (${candidate.pendingCount} pending), so I assigned "$title" to them to keep things fair. Let me know if we should swap.'
          : 'No one volunteered, and $requesterName has the lightest workload (${candidate.pendingCount} pending, ${candidate.weeklyCount} completed this week), so I assigned "$title" to them. Feel free to swap if needed.';
    } else {
      reasonMessage = assignmentContext == 'manual_chat'
          ? 'You asked me to decide, so I assigned "$title" to ${candidate.userName} (${candidate.pendingCount} pending tasks). Let me know if someone else wants it.'
          : 'No one stepped up, so I assigned "$title" to ${candidate.userName} who has the lightest current workload (${candidate.pendingCount} pending, ${candidate.weeklyCount} completed this week). Feel free to swap if needed.';
    }

    await sendBeemoMessage(
      houseId: houseId,
      message: reasonMessage,
    );

    // Create activity for Recent Activity feed
    await _createActivity(
      houseId: houseId,
      type: 'task_created',
      title: 'Task Assigned (AI)',
      description: 'Beemo assigned "$title" to ${candidate.userName}',
      metadata: {
        'taskTitle': title,
        'assignedTo': candidate.userId,
        'assignedToName': candidate.userName,
        'assignmentContext': assignmentContext,
      },
    );

    return true;
  }

  Future<void> maybeAutoAssignChatSessions(String houseId) async {
    print('DEBUG: maybeAutoAssignChatSessions called for house $houseId');
    final now = DateTime.now();
    // Add 5 second buffer to catch sessions that are about to expire
    final nowWithBuffer = now.add(const Duration(seconds: 5));
    final nowTs = Timestamp.fromDate(nowWithBuffer);
    print('DEBUG: Current time: $now');
    print('DEBUG: Looking for sessions with autoAssignAt <= $nowTs (with 5s buffer)');

    // Get all sessions that are ready for auto-assignment
    // ONLY get 'awaiting_volunteers' - this excludes 'assigning' and 'assigned'
    final query = await _taskAssignmentSessions(houseId)
        .where('status', isEqualTo: 'awaiting_volunteers')
        .where('autoAssignAt', isLessThanOrEqualTo: nowTs)
        .limit(10)
        .get();

    print('DEBUG: Found ${query.docs.length} sessions ready for auto-assignment (awaiting_volunteers only)');

    if (query.docs.isEmpty) {
      print('DEBUG: No sessions found to auto-assign');
      return;
    }

    for (final doc in query.docs) {
      print('DEBUG: Processing session ${doc.id}');
      final data = doc.data();
      print('DEBUG: Session data: ${data['taskTitle']}, status: ${data['status']}, autoAssignAt: ${data['autoAssignAt']}');
      data['id'] = doc.id;
      try {
        final success = await autoAssignChatTask(
          houseId: houseId,
          sessionData: data,
          assignmentContext: 'auto_chat',
        );
        print('DEBUG: Auto-assign result for ${doc.id}: $success');
      } catch (e, stackTrace) {
        print('DEBUG: ERROR - Auto-assign chat task failed for session ${doc.id}: $e');
        print('DEBUG: Stack trace: $stackTrace');
      }
    }
  }

  String _buildLedgerSnapshotNote(List<_TaskLoad> loads) {
    if (loads.isEmpty) {
      return '';
    }
    final preview = loads.take(3).map((load) {
      return '${load.userName}: ${load.pendingCount} pending / ${load.weeklyCount} completed wk';
    }).join(', ');
    return '\n\nCurrent workload: $preview';
  }

  String _sanitizeTaskLine(String title, String description) {
    final raw = description.trim().isNotEmpty ? description.trim() : title.trim();
    if (raw.isEmpty) {
      return 'this task';
    }
    return raw.length <= 120 ? raw : '${raw.substring(0, 117)}...';
  }

  // ============ TASK LEDGER & ASSIGNMENT SUPPORT ============

  Future<_TaskLoad?> _pickFairAssignee(
    String houseId, {
    Set<String>? excludedUserIds,
    String? requesterId,
    String? requesterName,
  }) async {
    final loads = await _loadTaskLoadSnapshot(
      houseId,
      requesterId: requesterId,
      requesterName: requesterName,
    );
    final result = _selectCandidateFromLoads(
      loads,
      excludedIds: excludedUserIds,
      requesterId: requesterId,
    );
    return result?.candidate;
  }

  Future<List<_TaskLoad>> _loadTaskLoadSnapshot(
    String houseId, {
    String? requesterId,
    String? requesterName,
  }) async {
    print('DEBUG: Getting house members for house $houseId');
    final members = await getHouseMembers(houseId);
    print('DEBUG: Found ${members.length} house members');

    if (members.isEmpty) {
      print('DEBUG: WARNING - No members returned from getHouseMembers!');
    }

    for (final member in members) {
      print('DEBUG: Member: ${member['name']} (${member['id']})');
    }

    // CRITICAL FIX: Ensure requester is included even if not in members list
    if (requesterId != null && requesterId.isNotEmpty) {
      final hasRequester = members.any((m) => m['id'] == requesterId);
      if (!hasRequester) {
        print('DEBUG: WARNING - Requester $requesterId ($requesterName) not in members list! Adding them.');
        members.add({
          'id': requesterId,
          'name': requesterName ?? 'Requester',
        });
      }
    }

    final ledgerSnapshot = await _taskLedgerCollection(houseId).get();
    print('DEBUG: Ledger has ${ledgerSnapshot.docs.length} entries');

    final Map<String, Map<String, dynamic>> ledgerById = {};

    for (final doc in ledgerSnapshot.docs) {
      ledgerById[doc.id] = doc.data();
      print('DEBUG: Ledger entry for ${doc.id}: ${doc.data()}');
    }

    // NEW: Fetch pending tasks for each user
    print('DEBUG: Fetching pending tasks for workload balancing...');
    final pendingTasksSnapshot = await _firestore
        .collection('tasks')
        .where('houseId', isEqualTo: houseId)
        .where('status', whereIn: ['pending', 'in_progress'])
        .get();

    final Map<String, int> pendingCountByUser = {};
    for (final doc in pendingTasksSnapshot.docs) {
      final data = doc.data();
      final assignedTo = data['assignedTo']?.toString() ?? '';
      if (assignedTo.isNotEmpty) {
        pendingCountByUser[assignedTo] = (pendingCountByUser[assignedTo] ?? 0) + 1;
      }
    }

    print('DEBUG: Pending task counts: $pendingCountByUser');

    final loads = <_TaskLoad>[];

    for (final member in members) {
      final userId = member['id'] ?? '';
      if (userId.isEmpty) {
        print('DEBUG: Skipping member with empty ID');
        continue;
      }

      final ledgerData = ledgerById[userId];
      final pendingCount = pendingCountByUser[userId] ?? 0;

      final load = _TaskLoad(
        userId: userId,
        userName: member['name'] ?? 'Member',
        weeklyCount: _toInt(ledgerData?['weeklyCount']),
        monthlyCount: _toInt(ledgerData?['monthlyCount']),
        totalCount: _toInt(ledgerData?['totalCount']),
        pendingCount: pendingCount,
      );

      print('DEBUG: Created load for ${load.userName}: ${load.weeklyCount}w/${load.monthlyCount}m/${load.totalCount}t/${load.pendingCount}p');
      loads.add(load);
    }

    loads.sort(_compareTaskLoads);
    print('DEBUG: Returning ${loads.length} loads after sorting');
    return loads;
  }

  Future<void> recordTaskCompletionLedger({
    required String houseId,
    required String userId,
    required String userName,
    DateTime? completedAt,
  }) async {
    final docRef = _taskLedgerCollection(houseId).doc(userId);
    final now = completedAt ?? DateTime.now();

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      List<DateTime> history = [];
      int totalCount = 0;

      if (snapshot.exists) {
        final data = snapshot.data();
        final raw = data?['completedTimestamps'] as List<dynamic>? ?? const [];
        for (final entry in raw) {
          if (entry is Timestamp) {
            history.add(entry.toDate());
          } else if (entry is DateTime) {
            history.add(entry);
          }
        }
        totalCount = _toInt(data?['totalCount']);
      }

      history.add(now);
      final monthlyCutoff = now.subtract(const Duration(days: 30));
      history = history.where((dt) => !dt.isBefore(monthlyCutoff)).toList()
        ..sort();

      final weeklyCutoff = now.subtract(const Duration(days: 7));
      final weeklyCount = history.where((dt) => !dt.isBefore(weeklyCutoff)).length;
      final monthlyCount = history.length;

      final timestampData = history.map((dt) => Timestamp.fromDate(dt)).toList();

      transaction.set(
        docRef,
        {
          'userId': userId,
          'userName': userName,
          'completedTimestamps': timestampData,
          'weeklyCount': weeklyCount,
          'monthlyCount': monthlyCount,
          'totalCount': totalCount + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _startAssignmentSessionFromAgenda({
    required String houseId,
    required String agendaItemId,
    required String title,
    required String details,
    String? requestedById,
    String? requestedByName,
  }) async {
    final loads = await _loadTaskLoadSnapshot(
      houseId,
      requesterId: requestedById,
      requesterName: requestedByName,
    );
    final sessionRef = _taskAssignmentSessions(houseId).doc(agendaItemId);
    final now = DateTime.now();

    // Get custom auto-assign duration (defaults to 2 minutes)
    final autoAssignMinutes = await getAutoAssignMinutes(houseId);
    final autoAssignAt = Timestamp.fromDate(now.add(Duration(minutes: autoAssignMinutes)));

    // Create an unassigned task immediately (same as chat tasks)
    final unassignedTaskId = await createTaskFromAI(
      houseId: houseId,
      title: title,
      description: details,
      assignedTo: '',
      assignedToName: '',
      sourceMessage: agendaItemId,
      assignmentContext: 'awaiting_assignment',
      allowUnassigned: true,
      notify: false,
    );

    await sessionRef.set({
      'houseId': houseId,
      'agendaItemId': agendaItemId,
      'agendaTitle': title,
      'agendaDetails': details,
      'sourceType': 'agenda',
      'status': 'awaiting_volunteers',
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
      'autoAssignAt': autoAssignAt,
      'ranking': loads.map((load) => load.toFirestore()).toList(),
      'passes': <String>[],
      'unassignedTaskId': unassignedTaskId, // Track the unassigned task
      if (requestedById != null && requestedById.isNotEmpty) 'requestedById': requestedById,
      if (requestedByName != null && requestedByName.trim().isNotEmpty)
        'requestedByName': requestedByName.trim(),
    });

    final detailBlock = details.trim().isEmpty ? '' : '\n\nDetails: ${details.trim()}';
    final requesterDisplay = (requestedByName ?? '').trim();
    final opener = requesterDisplay.isNotEmpty
        ? 'Hey everyone, **$requesterDisplay** asked if anyone can cover **"$title"**.'
        : 'Hey everyone, can we cover **"$title"**?';
    final summary = loads.isEmpty
        ? 'No one has any pending or completed tasks yet.'
        : loads
            .take(3)
            .map((load) => '${load.userName}: ${load.pendingCount} pending / ${load.weeklyCount} completed wk')
            .join(', ');

    // Format duration nicely
    final durationText = autoAssignMinutes >= 60
        ? '**${autoAssignMinutes ~/ 60} ${autoAssignMinutes ~/ 60 == 1 ? 'hour' : 'hours'}**'
        : '**$autoAssignMinutes ${autoAssignMinutes == 1 ? 'minute' : 'minutes'}**';

    // Send Beemo message WITH metadata to show countdown timer
    final messageId = await sendBeemoMessage(
      houseId: houseId,
      message:
          '$opener$detailBlock\n\nIf you can take it, just say so (like "I\'ll take it" or "I can do that"). Otherwise I\'ll auto-assign someone fairly in about $durationText. '
          "${requesterDisplay.isNotEmpty ? "I'll only assign it back to **$requesterDisplay**" : "I\'ll only assign it back to the original requester"} if they have the lightest workload.\n\n"
          'Current workload: $summary',
      metadata: {
        'assignmentSessionId': agendaItemId,
        'autoAssignAt': autoAssignAt,
      },
    );

    // Update the session with the message ID
    await sessionRef.update({
      'messageId': messageId,
    });

    // Update the agenda item to link it to the session
    await _firestore.collection('agendaItems').doc(agendaItemId).update({
      'assignmentSessionId': agendaItemId,
      'status': 'awaiting_assignment',
    });
  }

  Future<Map<String, dynamic>?> getActiveTaskAssignmentSession(String houseId) async {
    return _retryOperation(() async {
      final query = await _taskAssignmentSessions(houseId)
          .orderBy('createdAt', descending: false)
          .limit(10)
          .get();

      for (final doc in query.docs) {
        final data = doc.data();
        final status = data['status']?.toString() ?? '';
        if (status == 'awaiting_volunteers' || status == 'awaiting_confirmation') {
          return {...data, 'id': doc.id};
        }
      }
      return null;
    });
  }

  /// Gets ALL active task assignment sessions (awaiting volunteers)
  /// This is used to detect ambiguity when a user volunteers for a task
  Future<List<Map<String, dynamic>>> getAllActiveTaskAssignmentSessions(String houseId) async {
    return _retryOperation(() async {
      final query = await _taskAssignmentSessions(houseId)
          .where('status', isEqualTo: 'awaiting_volunteers')
          .orderBy('createdAt', descending: false)
          .limit(20)
          .get();

      return query.docs.map((doc) {
        return {...doc.data(), 'id': doc.id};
      }).toList();
    });
  }

  Future<void> recordAssignmentPass({
    required String houseId,
    required String sessionId,
    required String userId,
  }) async {
    await _taskAssignmentSessions(houseId).doc(sessionId).set({
      'passes': FieldValue.arrayUnion([userId]),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> resetAssignmentSession({
    required String houseId,
    required String sessionId,
  }) async {
    await _taskAssignmentSessions(houseId).doc(sessionId).set({
      'status': 'awaiting_volunteers',
      'proposedAssigneeId': FieldValue.delete(),
      'proposedAssigneeName': FieldValue.delete(),
      'proposedWeeklyCount': FieldValue.delete(),
      'proposedMonthlyCount': FieldValue.delete(),
      'proposedTotalCount': FieldValue.delete(),
      'proposedPendingCount': FieldValue.delete(),
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<_TaskLoad?> proposeFairAssignment({
    required String houseId,
    required Map<String, dynamic> sessionData,
  }) async {
    final sessionId = sessionData['id']?.toString() ?? '';
    if (sessionId.isEmpty) {
      return null;
    }
    if ((sessionData['status']?.toString() ?? '') == 'assigned') {
      return null;
    }

    final passes =
        ((sessionData['passes'] as List<dynamic>?) ?? const []).map((value) => value.toString()).toSet();

    final requesterId = sessionData['requestedById']?.toString();
    final requesterName = (sessionData['requestedByName']?.toString() ?? '').trim();

    final loads = await _loadTaskLoadSnapshot(
      houseId,
      requesterId: requesterId,
      requesterName: requesterName,
    );
    final assignmentResult = _selectCandidateFromLoads(
      loads,
      excludedIds: passes,
      requesterId: requesterId,
    );
    if (assignmentResult == null) {
      final agendaTitle = sessionData['agendaTitle']?.toString() ?? 'this item';
      await sendBeemoMessage(
        houseId: houseId,
        message:
            'I could not find a fair fallback for "$agendaTitle". Let me know if someone can volunteer!',
      );
      return null;
    }

    final candidate = assignmentResult.candidate;
    final sessionRef = _taskAssignmentSessions(houseId).doc(sessionId);
    await sessionRef.set({
      'status': 'awaiting_confirmation',
      'proposedAssigneeId': candidate.userId,
      'proposedAssigneeName': candidate.userName,
      'proposedWeeklyCount': candidate.weeklyCount,
      'proposedMonthlyCount': candidate.monthlyCount,
      'proposedTotalCount': candidate.totalCount,
      'proposedPendingCount': candidate.pendingCount,
      'lastUpdated': FieldValue.serverTimestamp(),
      'ranking': loads.map((load) => load.toFirestore()).toList(),
    }, SetOptions(merge: true));

    final agendaTitle = sessionData['agendaTitle']?.toString() ?? 'this item';
    final bool isRequester = candidate.userId == requesterId && requesterName.isNotEmpty;

    late final String recommendation;
    if (assignmentResult.wasRandomSelection) {
      final tiedNames = assignmentResult.tiedCandidateNames ?? [];
      final namesDisplay = tiedNames.length > 3
          ? '${tiedNames.take(3).join(', ')} and ${tiedNames.length - 3} others'
          : tiedNames.join(', ');
      recommendation = 'I picked randomly between $namesDisplay since you all have the same workload (${candidate.pendingCount} pending, ${candidate.weeklyCount} completed last 7 days). Assigning "$agendaTitle" to ${candidate.userName}.';
    } else if (isRequester) {
      recommendation = '$requesterName has the lightest workload, so assigning "$agendaTitle" to them will keep things balanced (${candidate.pendingCount} pending, ${candidate.weeklyCount} completed last 7 days).';
    } else {
      recommendation = 'Based on current workload, I recommend assigning "$agendaTitle" to ${candidate.userName} (${candidate.pendingCount} pending tasks, ${candidate.weeklyCount} completed last 7 days).';
    }

    await sendBeemoMessage(
      houseId: houseId,
      message:
          'No volunteers yet. $recommendation Reply "yes" to confirm or "I\'ll take it" if someone else wants it.',
    );

    return candidate;
  }

  Future<bool> finalizeAssignmentFromVolunteer({
    required String houseId,
    required Map<String, dynamic> sessionData,
    required String volunteerId,
    required String volunteerName,
  }) async {
    final sessionId = sessionData['id']?.toString() ?? '';
    if (sessionId.isEmpty) {
      return false;
    }
    if ((sessionData['status']?.toString() ?? '') == 'assigned') {
      return false;
    }

    return _completeAssignmentSession(
      houseId: houseId,
      sessionData: sessionData,
      sessionId: sessionId,
      assignedToId: volunteerId,
      assignedToName: volunteerName,
      assignmentReason: 'volunteer',
      metrics: null,
    );
  }

  Future<bool> finalizeProposedAssignment({
    required String houseId,
    required Map<String, dynamic> sessionData,
  }) async {
    final sessionId = sessionData['id']?.toString() ?? '';
    if (sessionId.isEmpty) {
      return false;
    }
    if ((sessionData['status']?.toString() ?? '') == 'assigned') {
      return false;
    }

    final proposedId = sessionData['proposedAssigneeId']?.toString();
    if (proposedId == null || proposedId.isEmpty) {
      return false;
    }

    final proposedName = sessionData['proposedAssigneeName']?.toString() ?? 'Member';
    final metrics = _TaskLoad(
      userId: proposedId,
      userName: proposedName,
      weeklyCount: _toInt(sessionData['proposedWeeklyCount']),
      monthlyCount: _toInt(sessionData['proposedMonthlyCount']),
      totalCount: _toInt(sessionData['proposedTotalCount']),
      pendingCount: _toInt(sessionData['proposedPendingCount']),
    );

    return _completeAssignmentSession(
      houseId: houseId,
      sessionData: sessionData,
      sessionId: sessionId,
      assignedToId: proposedId,
      assignedToName: proposedName,
      assignmentReason: 'fairness',
      metrics: metrics,
    );
  }

  Future<bool> _completeAssignmentSession({
    required String houseId,
    required Map<String, dynamic> sessionData,
    required String sessionId,
    required String assignedToId,
    required String assignedToName,
    required String assignmentReason,
    _TaskLoad? metrics,
  }) async {
    final agendaTitle = sessionData['agendaTitle']?.toString() ?? 'Agenda item';
    final agendaDetails = sessionData['agendaDetails']?.toString() ?? '';
    final requestedById = sessionData['requestedById']?.toString() ?? '';
    final assignedToWasRequester =
        requestedById.isNotEmpty && requestedById == assignedToId;

    print('DEBUG: ========== AGENDA ASSIGNMENT START ==========');
    print('DEBUG: Assigning agenda "$agendaTitle" to $assignedToName');

    // AGGRESSIVE FIX: Find and archive ALL unassigned tasks with this title
    print('DEBUG: Finding ALL unassigned tasks with title "$agendaTitle" in house $houseId');
    final allTasksQuery = await _firestore.collection('tasks')
        .where('houseId', isEqualTo: houseId)
        .where('title', isEqualTo: agendaTitle)
        .get();

    final unassignedTasksToArchive = <String>[];
    for (var doc in allTasksQuery.docs) {
      final data = doc.data();
      final assignedTo = (data['assignedTo'] ?? '').toString().trim();
      final assignedToNameField = (data['assignedToName'] ?? '').toString().trim();
      final status = (data['status'] ?? '').toString().toLowerCase();

      // Task is unassigned if both assignedTo and assignedToName are empty AND not already archived
      if (assignedTo.isEmpty && assignedToNameField.isEmpty && status != 'archived') {
        print('DEBUG: Found unassigned task: ${doc.id}');
        unassignedTasksToArchive.add(doc.id);
      }
    }

    print('DEBUG: Found ${unassignedTasksToArchive.length} unassigned tasks to archive');

    // Archive all unassigned tasks NOW before creating assigned task
    for (var taskIdToArchive in unassignedTasksToArchive) {
      try {
        print('DEBUG: Archiving unassigned task $taskIdToArchive');
        await _firestore.collection('tasks').doc(taskIdToArchive).update({
          'status': 'archived',
          'archivedReason': 'agenda_assigned',
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        print('DEBUG: Successfully archived $taskIdToArchive');
      } catch (e) {
        print('DEBUG: ERROR archiving task $taskIdToArchive: $e');
      }
    }

    // Now create the assigned task
    print('DEBUG: Creating assigned task for $assignedToName');
    final taskId = await _createTaskFromAssignment(
      houseId: houseId,
      agendaItemId: sessionId,
      agendaTitle: agendaTitle,
      agendaDetails: agendaDetails,
      assignedToId: assignedToId,
      assignedToName: assignedToName,
      assignmentSource: assignmentReason,
      assignedToWasRequester: assignedToWasRequester,
      metrics: metrics,
    );

    print('DEBUG: Successfully created assigned task $taskId for $assignedToName');
    print('DEBUG: ========== AGENDA ASSIGNMENT END ==========');

    final updates = <String, dynamic>{
      'status': 'assigned',
      'assignedToId': assignedToId,
      'assignedToName': assignedToName,
      'assignmentReason': assignmentReason,
      'taskId': taskId,
      'lastUpdated': FieldValue.serverTimestamp(),
      'proposedAssigneeId': FieldValue.delete(),
      'proposedAssigneeName': FieldValue.delete(),
      'proposedWeeklyCount': FieldValue.delete(),
      'proposedMonthlyCount': FieldValue.delete(),
      'proposedTotalCount': FieldValue.delete(),
      'proposedPendingCount': FieldValue.delete(),
    };

    if (assignmentReason == 'volunteer') {
      updates['volunteerId'] = assignedToId;
      updates['volunteerName'] = assignedToName;
    }

    await _taskAssignmentSessions(houseId).doc(sessionId).set(
          updates,
          SetOptions(merge: true),
        );

    await _firestore.collection('agendaItems').doc(sessionId).set({
      'assignedToId': assignedToId,
      'assignedToName': assignedToName,
      'linkedTaskId': taskId,
      'assignmentReason': assignmentReason,
      'assignmentTimestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update the original message to show task has been assigned
    final messageId = sessionData['messageId']?.toString();
    if (messageId != null && messageId.isNotEmpty) {
      try {
        await updateMessageWithAssignment(
          messageId: messageId,
          assignedToName: assignedToName,
          assignmentReason: assignmentReason,
        );
      } catch (e) {
        print('Could not update message with assignment: $e');
      }
    }

    return true;
  }

  Future<String> _createTaskFromAssignment({
    required String houseId,
    required String agendaItemId,
    required String agendaTitle,
    required String agendaDetails,
    required String assignedToId,
    required String assignedToName,
    required String assignmentSource,
    bool assignedToWasRequester = false,
    _TaskLoad? metrics,
  }) async {
    final tasksCollection = _firestore.collection('tasks');
    final existingSnapshot = await tasksCollection
        .where('agendaItemId', isEqualTo: agendaItemId)
        .limit(1)
        .get();

    final taskData = {
      'houseId': houseId,
      'title': agendaTitle,
      'description': agendaDetails.isNotEmpty
          ? agendaDetails
          : 'Follow up on agenda item "$agendaTitle"',
      'assignedTo': assignedToId,
      'assignedToName': assignedToName,
      'status': 'pending',
      'dueDate': null,
      'createdBy': 'beemo_assignment',
      'sourceMessage': 'Agenda assignment: $agendaItemId',
      'agendaItemId': agendaItemId,
      'assignmentSource': assignmentSource,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    DocumentReference taskRef;
    if (existingSnapshot.docs.isNotEmpty) {
      taskRef = existingSnapshot.docs.first.reference;
      await taskRef.set(taskData, SetOptions(merge: true));
    } else {
      taskRef = await tasksCollection.add({
        ...taskData,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await _createActivity(
      houseId: houseId,
      type: 'task_assigned',
      title: 'Agenda Assigned',
      description: '"$agendaTitle" was assigned to $assignedToName',
      metadata: {
        'agendaItemId': agendaItemId,
        'assignmentSource': assignmentSource,
        'assignedTo': assignedToId,
      },
    );

    final metricsLine = metrics != null
        ? ' (last 7 days: ${metrics.weeklyCount}, last 30 days: ${metrics.monthlyCount})'
        : '';
    final acknowledgment = assignmentSource == 'volunteer'
        ? 'Thanks, $assignedToName! I assigned "$agendaTitle" to you so it stays on track.'
        : assignedToWasRequester
            ? '$assignedToName is still behind on task completions, so I assigned "$agendaTitle" to them to even things out$metricsLine. If that feels off, let me know and we can swap.'
            : 'Nobody volunteered, so I assigned "$agendaTitle" to $assignedToName using our task ledger$metricsLine. If anyone wants to swap, just let me know.';
    await sendBeemoMessage(
      houseId: houseId,
      message: acknowledgment,
    );

    return taskRef.id;
  }

  /// Delete all test tasks (for cleanup)
  Future<void> deleteTestTasks(String houseId) async {
    QuerySnapshot testTasks = await _firestore
        .collection('tasks')
        .where('houseId', isEqualTo: houseId)
        .get();

    WriteBatch batch = _firestore.batch();
    int deleteCount = 0;

    for (var doc in testTasks.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      String title = data['title'] ?? '';

      // Delete if title contains "Test Task" or was created by test
      if (title.contains('Test Task') || title.toLowerCase().contains('test')) {
        batch.delete(doc.reference);
        deleteCount++;
      }
    }

    if (deleteCount > 0) {
      await batch.commit();
      print('Deleted $deleteCount test tasks');
    }
  }

  Future<void> updateTaskStatus(String taskId, String status) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return;
    }

    final currentUserId = currentUser.uid;
    final currentUserName = (currentUser.displayName ??
            currentUser.email?.split('@').first ??
            '')
        .trim();
    final taskRef = _firestore.collection('tasks').doc(taskId);

    if (status == 'pending_confirmation') {
      Map<String, dynamic>? taskData;
      bool updated = false;

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(taskRef);
        if (!snapshot.exists) {
          return;
        }
        final data = snapshot.data() as Map<String, dynamic>;
        final assignedUserId = data['assignedTo']?.toString() ?? '';
        final currentStatus = (data['status'] ?? '').toString();

        if (assignedUserId != currentUserId) {
          return;
        }
        if (currentStatus == 'completed' || currentStatus == 'pending_confirmation') {
          return;
        }

        transaction.update(taskRef, {
          'status': 'pending_confirmation',
          'completionRequestedBy': currentUserId,
          'completionRequestedAt': FieldValue.serverTimestamp(),
          'confirmedBy': FieldValue.delete(),
          'confirmedByName': FieldValue.delete(),
          'completedAt': null,
        });

        taskData = data;
        updated = true;
      });

      // Create activity when user marks task as done (pending confirmation)
      if (updated && taskData != null) {
        final houseId = (taskData!['houseId'] ?? '').toString();
        final assignedUserId = (taskData!['assignedTo'] ?? '').toString();
        final assignedUserName = (taskData!['assignedToName'] ?? 'Member').toString();
        final taskTitle = (taskData!['title'] ?? 'task').toString();

        if (houseId.isNotEmpty && assignedUserId.isNotEmpty) {
          await _createActivity(
            houseId: houseId,
            type: 'task_completed',
            title: 'Task Completed',
            description: '$assignedUserName completed "$taskTitle" - needs confirmation',
            metadata: {
              'taskTitle': taskTitle,
              'taskId': taskId,
              'completedBy': assignedUserId,
              'completedByName': assignedUserName,
            },
          );
        }
      }
      return;
    }

    if (status == 'completed') {
      Map<String, dynamic>? taskData;
      bool updated = false;

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(taskRef);
        if (!snapshot.exists) {
          return;
        }

        final data = snapshot.data() as Map<String, dynamic>;
        final assignedUserId = data['assignedTo']?.toString() ?? '';
        final currentStatus = (data['status'] ?? '').toString();

        if (currentStatus != 'pending_confirmation') {
          return;
        }
        if (assignedUserId.isNotEmpty && assignedUserId == currentUserId) {
          return;
        }

        transaction.update(taskRef, {
          'status': 'completed',
          'confirmedBy': currentUserId,
          'confirmedByName':
              currentUserName.isNotEmpty ? currentUserName : 'Housemate',
          'completedAt': FieldValue.serverTimestamp(),
        });

        taskData = data;
        updated = true;
      });

      if (!updated || taskData == null) {
        return;
      }

      final houseId = taskData?['houseId']?.toString() ?? '';
      final assignedUserId = taskData?['assignedTo']?.toString() ?? '';
      final assignedUserName = taskData?['assignedToName']?.toString() ?? 'Member';

      if (houseId.isNotEmpty && assignedUserId.isNotEmpty) {
        await recordTaskCompletionLedger(
          houseId: houseId,
          userId: assignedUserId,
          userName: assignedUserName,
        );

        await _firestore.collection('users').doc(assignedUserId).set({
          'profile': {
            'points': FieldValue.increment(10),
          },
        }, SetOptions(merge: true));

        // Find and update the existing activity that was created when task was marked as done
        // (instead of creating a duplicate activity)
        try {
          final activityQuery = await _firestore
              .collection('activities')
              .where('houseId', isEqualTo: houseId)
              .where('type', isEqualTo: 'task_completed')
              .limit(50)
              .get();

          print('DEBUG: Found ${activityQuery.docs.length} task_completed activities');

          // Find the matching activity by checking metadata in memory
          DocumentSnapshot? matchingActivity;
          for (var doc in activityQuery.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            final metadata = data?['metadata'] as Map<String, dynamic>?;
            if (metadata != null &&
                metadata['taskId'] == taskId &&
                metadata['completedBy'] == assignedUserId) {
              matchingActivity = doc;
              break;
            }
          }

          if (matchingActivity != null) {
            // Update existing activity to mark it as confirmed
            // Get existing metadata and merge with new fields
            final data = matchingActivity.data() as Map<String, dynamic>?;
            final existingMetadata = Map<String, dynamic>.from(data?['metadata'] as Map<String, dynamic>? ?? {});

            // Merge in the confirmation fields
            existingMetadata['confirmed'] = true;
            existingMetadata['confirmedBy'] = currentUserId;
            existingMetadata['confirmedAt'] = FieldValue.serverTimestamp();

            await matchingActivity.reference.update({
              'metadata': existingMetadata,
            });
            print('DEBUG: Updated existing activity ${matchingActivity.id} to confirmed state');

            // Award 20 coins to the confirmer
            try {
              await awardCoins(
                houseId: houseId,
                userId: currentUserId,
                amount: 20,
              );
              print('DEBUG: Awarded 20 coins to $currentUserName for confirming task');
            } catch (e) {
              print('ERROR: Failed to award coins for task confirmation: $e');
            }

            // Award 30 coins to the task completer (now that it's confirmed)
            try {
              await awardCoins(
                houseId: houseId,
                userId: assignedUserId,
                amount: 30,
              );
              print('DEBUG: Awarded 30 coins to $assignedUserName for completing task');
            } catch (e) {
              print('ERROR: Failed to award coins for task completion: $e');
            }
          } else {
            print('DEBUG: No matching activity found, creating new one');
            // Backward compatibility: Create activity if it doesn't exist
            // (for tasks that were marked as pending_confirmation before this code change)
            await _createActivity(
              houseId: houseId,
              type: 'task_completed',
              title: 'Task Completed',
              description: '$assignedUserName completed "${taskData?['title'] ?? 'task'}"',
              metadata: {
                'taskTitle': taskData?['title'],
                'taskId': taskId,
                'completedBy': assignedUserId,
                'completedByName': assignedUserName,
                'confirmed': true,
                'confirmedBy': currentUserId,
                'confirmedAt': FieldValue.serverTimestamp(),
              },
            );
            print('DEBUG: Created new activity for completed task (backward compatibility)');

            // Award coins for backward compatibility case
            // Award 20 coins to the confirmer
            try {
              await awardCoins(
                houseId: houseId,
                userId: currentUserId,
                amount: 20,
              );
              print('DEBUG: Awarded 20 coins to $currentUserName for confirming task');
            } catch (e) {
              print('ERROR: Failed to award coins for task confirmation: $e');
            }

            // Award 30 coins to the task completer (now that it's confirmed)
            try {
              await awardCoins(
                houseId: houseId,
                userId: assignedUserId,
                amount: 30,
              );
              print('DEBUG: Awarded 30 coins to $assignedUserName for completing task');
            } catch (e) {
              print('ERROR: Failed to award coins for task completion: $e');
            }
          }
        } catch (e) {
          print('DEBUG: ERROR updating activity for completed task: $e');
        }
      }
      return;
    }

    await taskRef.update({'status': status});
  }

  // ============ CHAT METHODS ============

  Future<List<ChatMessage>> fetchRecentChatMessages(
    String houseId, {
    int limit = 20,
  }) async {
    final query = await _firestore
        .collection('chatMessages')
        .where('houseId', isEqualTo: houseId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    return query.docs.map(ChatMessage.fromFirestore).toList();
  }

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

    // Check if this message is a volunteer response
    await processNewMessageForVolunteer(
      houseId: houseId,
      messageText: message,
      senderId: _auth.currentUser!.uid,
      senderName: senderName,
    );
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
      'senderAvatar': 'ÃƒÂ°Ã…Â¸Ã‚Â¤Ã¢â‚¬â€œ',
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

  Future<String> sendBeemoMessage({
    required String houseId,
    required String message,
    String messageType = 'text',
    List<String>? pollOptions,
    Map<String, dynamic>? metadata,
  }) async {
    final data = {
      'houseId': houseId,
      'senderId': 'beemo',
      'senderName': 'Beemo',
      'senderAvatar': 'dY-',
      'senderColor': '#FFC400',
      'message': message,
      'messageType': messageType,
      'timestamp': FieldValue.serverTimestamp(),
      'isBeemo': true,
      if (metadata != null) 'metadata': metadata,
    };

    if (pollOptions != null && pollOptions.isNotEmpty) {
      data['pollOptions'] = pollOptions
          .map((opt) => {
                'option': opt,
                'votes': <String>[],
              })
          .toList();
    }

    final docRef = await _firestore.collection('chatMessages').add(data);
    return docRef.id;
  }

  Future<void> upsertMeetingPlanningSession(
    String houseId,
    Map<String, dynamic> data,
  ) async {
    await _firestore
        .collection('meetingPlanningSessions')
        .doc(houseId)
        .set(data, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getMeetingPlanningSession(String houseId) async {
    return _retryOperation(() async {
      final snapshot =
          await _firestore.collection('meetingPlanningSessions').doc(houseId).get();
      if (!snapshot.exists) return null;
      return snapshot.data();
    });
  }

  Future<void> clearMeetingPlanningSession(String houseId) async {
    try {
      await _firestore.collection('meetingPlanningSessions').doc(houseId).delete();
    } catch (_) {
      // Safe to ignore if the document does not exist.
    }
  }

  Future<void> voteOnPoll(String messageId, int optionIndex) async {
    String userId = _auth.currentUser!.uid;
    await _firestore.collection('chatMessages').doc(messageId).update({
      'pollOptions.$optionIndex.votes': FieldValue.arrayUnion([userId]),
    });
  }

  /// Update the task assignment message to show it's been assigned
  Future<void> updateMessageWithAssignment({
    required String messageId,
    required String assignedToName,
    required String assignmentReason,
  }) async {
    await _firestore.collection('chatMessages').doc(messageId).update({
      'metadata.taskAssigned': true,
      'metadata.assignedToName': assignedToName,
      'metadata.assignmentReason': assignmentReason,
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

  Future<String> createAgendaItem({
    required String houseId,
    required String title,
    required String details,
    required String priority,
  }) async {
    final docRef = await _firestore.collection('agendaItems').add({
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

    // If priority is chat, initiate Beemo's autonomous assignment flow.
    if (priority == 'chat') {
      final currentUser = _auth.currentUser;
      final requesterId = currentUser?.uid ?? '';
      final requesterName = (() {
        final rawName = currentUser?.displayName ?? '';
        if (rawName.trim().isNotEmpty) {
          return rawName.trim();
        }
        final email = currentUser?.email ?? '';
        if (email.isNotEmpty) {
          return email.split('@').first;
        }
        return '';
      })();

      await _startAssignmentSessionFromAgenda(
        houseId: houseId,
        agendaItemId: docRef.id,
        title: title,
        details: details,
        requestedById: requesterId.isNotEmpty ? requesterId : null,
        requestedByName: requesterName.isNotEmpty ? requesterName : null,
      );
    }

    return docRef.id;
  }

  // ============ MEETING METHODS ============

  // Meeting assistant settings
  Stream<Map<String, dynamic>> autoMeetingSettingsStream(String houseId) {
    return _firestore
        .collection('meetingAssistantSettings')
        .doc(houseId)
        .snapshots()
        .map((doc) => doc.data() ?? {});
  }

  Future<void> updateAutoMeetingSettings(
    String houseId, {
    bool? enabled,
    DateTime? lastPromptAt,
    bool clearLastPrompt = false,
    int? autoAssignMinutes,
  }) async {
    final Map<String, dynamic> data = {
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (enabled != null) {
      data['autoWeeklyCheckInEnabled'] = enabled;
    }

    if (clearLastPrompt) {
      data['lastAutoPromptAt'] = FieldValue.delete();
    } else if (lastPromptAt != null) {
      data['lastAutoPromptAt'] = Timestamp.fromDate(lastPromptAt);
    }

    if (autoAssignMinutes != null) {
      data['autoAssignMinutes'] = autoAssignMinutes;
    }

    await _firestore
        .collection('meetingAssistantSettings')
        .doc(houseId)
        .set(data, SetOptions(merge: true));
  }

  /// Get the custom auto-assign duration in minutes (defaults to 2 minutes)
  Future<int> getAutoAssignMinutes(String houseId) async {
    try {
      final doc = await _firestore
          .collection('meetingAssistantSettings')
          .doc(houseId)
          .get();

      if (doc.exists && doc.data() != null) {
        final minutes = doc.data()?['autoAssignMinutes'];
        if (minutes is int && minutes > 0) {
          return minutes;
        }
      }
    } catch (e) {
      print('Error fetching auto-assign minutes: $e');
    }
    return 2; // Default to 2 minutes
  }

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

    // Award 50 coins to each participant for attending the meeting
    for (int i = 0; i < participantIds.length; i++) {
      try {
        await awardCoins(
          houseId: houseId,
          userId: participantIds[i],
          amount: 50,
        );
        final name = i < participantNames.length ? participantNames[i] : 'Member';
        print('DEBUG: Awarded 50 coins to $name for attending meeting "$title"');
      } catch (e) {
        print('ERROR: Failed to award coins for meeting attendance to ${participantIds[i]}: $e');
      }
    }
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

  Future<DateTime?> getNextMeetingTimeOnce(String houseId) async {
    return _retryOperation(() async {
      final doc =
          await _firestore.collection('nextMeetings').doc(houseId).get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null || data['scheduledTime'] == null) return null;
      return (data['scheduledTime'] as Timestamp).toDate();
    });
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

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  int _compareTaskLoads(_TaskLoad a, _TaskLoad b) {
    // PRIORITY 1: Fewest pending tasks (workload balance)
    final pendingDiff = a.pendingCount.compareTo(b.pendingCount);
    if (pendingDiff != 0) return pendingDiff;

    // PRIORITY 2: Fewest completed tasks this week (recent contribution)
    final weeklyDiff = a.weeklyCount.compareTo(b.weeklyCount);
    if (weeklyDiff != 0) return weeklyDiff;

    // PRIORITY 3: Fewest completed tasks this month
    final monthlyDiff = a.monthlyCount.compareTo(b.monthlyCount);
    if (monthlyDiff != 0) return monthlyDiff;

    // PRIORITY 4: Fewest total completed tasks
    final totalDiff = a.totalCount.compareTo(b.totalCount);
    if (totalDiff != 0) return totalDiff;

    // PRIORITY 5: Alphabetical by name (consistent tiebreaker)
    return a.userName.compareTo(b.userName);
  }

  _AssignmentResult? _selectCandidateFromLoads(
    List<_TaskLoad> loads, {
    Set<String>? excludedIds,
    String? requesterId,
  }) {
    if (loads.isEmpty) {
      print('DEBUG: No loads - no house members found');
      return null;
    }

    print('DEBUG: Starting selection with ${loads.length} members');
    for (final load in loads) {
      print('DEBUG: ${load.userName}: pending=${load.pendingCount}, weekly=${load.weeklyCount}, monthly=${load.monthlyCount}, total=${load.totalCount}');
    }

    final baseExcluded = excludedIds ?? const <String>{};
    final forcedExcluded = <String>{};

    // Only exclude requester if they're AHEAD of everyone else, not if tied
    if (requesterId != null && requesterId.isNotEmpty) {
      _TaskLoad? requesterLoad;
      for (final load in loads) {
        if (load.userId == requesterId) {
          requesterLoad = load;
          break;
        }
      }

      if (requesterLoad != null) {
        final rLoad = requesterLoad;
        bool isAheadOf(_TaskLoad other) {
          if (other.userId == requesterId) {
            return false; // Not ahead of self
          }

          // PRIORITY 1: Check pending tasks (current workload)
          if (rLoad.pendingCount > other.pendingCount) return true;
          if (rLoad.pendingCount < other.pendingCount) return false;

          // PRIORITY 2: Check weekly completions (recent contribution)
          if (rLoad.weeklyCount > other.weeklyCount) return true;
          if (rLoad.weeklyCount < other.weeklyCount) return false;

          // PRIORITY 3: Check monthly completions
          if (rLoad.monthlyCount > other.monthlyCount) return true;
          if (rLoad.monthlyCount < other.monthlyCount) return false;

          // PRIORITY 4: Check total completions
          if (rLoad.totalCount > other.totalCount) return true;
          if (rLoad.totalCount < other.totalCount) return false;

          return false; // Tied = not ahead
        }

        // Only exclude if requester is ahead of SOMEONE (not just tied)
        final requesterIsAheadOfSomeone = loads.any((load) =>
          load.userId != requesterId && isAheadOf(load)
        );

        if (requesterIsAheadOfSomeone) {
          forcedExcluded.add(requesterId);
          print('DEBUG: Excluding requester ${rLoad.userName} (ahead of others: ${rLoad.pendingCount}p/${rLoad.weeklyCount}w/${rLoad.monthlyCount}m)');
        } else {
          print('DEBUG: Including requester ${rLoad.userName} (not ahead: ${rLoad.pendingCount}p/${rLoad.weeklyCount}w/${rLoad.monthlyCount}m)');
        }
      }
    }

    // Filter out excluded users
    final filtered = loads
        .where((load) =>
            !baseExcluded.contains(load.userId) && !forcedExcluded.contains(load.userId))
        .toList();

    print('DEBUG: After filtering: ${filtered.length} candidates');

    // If no one left after filtering, try without forced exclusions
    final evaluationPool = filtered.isNotEmpty ? filtered : loads
        .where((load) => !baseExcluded.contains(load.userId))
        .toList();

    if (evaluationPool.isEmpty) {
      print('DEBUG: No candidates available after all filtering');
      return null;
    }

    print('DEBUG: Evaluation pool: ${evaluationPool.length} candidates');

    // STEP 1: Filter by minimum pending tasks (workload)
    final minPending = evaluationPool.map((load) => load.pendingCount).reduce(min);
    final pendingCandidates =
        evaluationPool.where((load) => load.pendingCount == minPending).toList();

    print('DEBUG: After pending filter (${minPending} pending): ${pendingCandidates.length} candidates');

    // STEP 2: Filter by minimum weekly completions
    final minWeekly = pendingCandidates.map((load) => load.weeklyCount).reduce(min);
    final weeklyCandidates =
        pendingCandidates.where((load) => load.weeklyCount == minWeekly).toList();

    print('DEBUG: After weekly filter (${minWeekly} weekly): ${weeklyCandidates.length} candidates');

    // STEP 3: Filter by minimum monthly completions
    final minMonthly =
        weeklyCandidates.map((load) => load.monthlyCount).reduce(min);
    final monthlyCandidates =
        weeklyCandidates.where((load) => load.monthlyCount == minMonthly).toList();

    print('DEBUG: After monthly filter (${minMonthly} monthly): ${monthlyCandidates.length} candidates');

    // STEP 4: Filter by minimum total completions
    final minTotal =
        monthlyCandidates.map((load) => load.totalCount).reduce(min);
    final finalCandidates =
        monthlyCandidates.where((load) => load.totalCount == minTotal).toList();

    print('DEBUG: Final candidates: ${finalCandidates.length}');
    for (final candidate in finalCandidates) {
      print('DEBUG: Candidate: ${candidate.userName} (${candidate.pendingCount}p/${candidate.weeklyCount}w/${candidate.monthlyCount}m/${candidate.totalCount}t)');
    }

    if (finalCandidates.length == 1) {
      return _AssignmentResult(
        candidate: finalCandidates.first,
        wasRandomSelection: false,
        tiedCandidatesCount: 1,
      );
    }

    // Multiple people tied - random selection
    final selectedCandidate = finalCandidates[_random.nextInt(finalCandidates.length)];
    print('DEBUG: Random selection from ${finalCandidates.length} tied candidates: ${selectedCandidate.userName}');
    return _AssignmentResult(
      candidate: selectedCandidate,
      wasRandomSelection: true,
      tiedCandidatesCount: finalCandidates.length,
      tiedCandidateNames: finalCandidates.map((c) => c.userName).toList(),
    );
  }

  String _generateInviteCode() {
    return _uuid.v4().substring(0, 8).toUpperCase();
  }

  String _deriveInitials(String name) {
    final parts = name.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return 'B';
    }
    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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

  /// Mark an activity as confirmed
  /// This updates the activity metadata to indicate it has been confirmed by a peer
  Future<void> markActivityAsConfirmed(String activityId, String confirmedBy) async {
    try {
      await _firestore.collection('activities').doc(activityId).update({
        'metadata.confirmed': true,
        'metadata.confirmedBy': confirmedBy,
        'metadata.confirmedAt': FieldValue.serverTimestamp(),
      });
      print('DEBUG: Activity $activityId marked as confirmed by $confirmedBy');
    } catch (e) {
      print('DEBUG: ERROR marking activity as confirmed: $e');
      rethrow;
    }
  }

  /// Detect if a message is a volunteer response
  bool _isVolunteerResponse(String message) {
    final lowerMessage = message.toLowerCase().trim();

    // Common volunteer phrases
    final volunteerPhrases = [
      "i'll take it",
      "i'll do it",
      "i can do it",
      "i can do this",
      "i'll handle it",
      "i got it",
      "i got this",
      "i'll take care of it",
      "i volunteer",
      "i can take this",
      "i'll get it",
      "i can help",
      "i'll help",
      "ill take it", // without apostrophe
      "ill do it",
      "ill handle it",
    ];

    return volunteerPhrases.any((phrase) => lowerMessage.contains(phrase));
  }

  /// Process new chat messages for volunteer detection
  Future<void> processNewMessageForVolunteer({
    required String houseId,
    required String messageText,
    required String senderId,
    required String senderName,
  }) async {
    // Don't process Beemo's own messages
    if (senderId == 'beemo_ai' || senderName.toLowerCase() == 'beemo') {
      return;
    }

    // Check if this is a volunteer response
    if (!_isVolunteerResponse(messageText)) {
      return;
    }

    print('DEBUG: ========== VOLUNTEER DETECTED ==========');
    print('DEBUG: $senderName said: "$messageText"');

    // Find active task assignment session awaiting volunteers
    final sessionQuery = await _taskAssignmentSessions(houseId)
        .where('status', isEqualTo: 'awaiting_volunteers')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (sessionQuery.docs.isEmpty) {
      print('DEBUG: No active task assignment session found');
      return;
    }

    final sessionData = {
      ...sessionQuery.docs.first.data(),
      'id': sessionQuery.docs.first.id,
    };

    print('DEBUG: Found active session: ${sessionData['id']}');

    // Check if this is a chat task or agenda item
    final sourceType = sessionData['sourceType']?.toString() ?? 'chat';
    final taskTitle = sourceType == 'chat'
        ? sessionData['taskTitle']?.toString() ?? 'task'
        : sessionData['agendaTitle']?.toString() ?? 'task';

    print('DEBUG: Source type: $sourceType');
    print('DEBUG: Task/Agenda: $taskTitle');

    // Call the appropriate function based on source type
    bool success;
    if (sourceType == 'agenda') {
      // Agenda item volunteer
      success = await finalizeAssignmentFromVolunteer(
        houseId: houseId,
        sessionData: sessionData,
        volunteerId: senderId,
        volunteerName: senderName,
      );
    } else {
      // Chat task volunteer
      success = await finalizeChatTaskWithVolunteer(
        houseId: houseId,
        sessionData: sessionData,
        volunteerId: senderId,
        volunteerName: senderName,
      );
    }

    if (success) {
      print('DEBUG: Successfully assigned $sourceType to $senderName');
    } else {
      print('DEBUG: Failed to assign $sourceType to $senderName');
    }
  }

  // ==================== Room Furniture State Management ====================

  /// Save the complete furniture state for a specific room
  Future<void> saveRoomFurnitureState({
    required String houseId,
    required String roomName,
    required List<Map<String, dynamic>> furnitureItems,
  }) async {
    try {
      await _retryOperation(() async {
        await _firestore
            .collection('houses')
            .doc(houseId)
            .collection('rooms')
            .doc(roomName)
            .set({
          'furniture_items': furnitureItems,
          'last_modified': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      print('✅ Saved furniture state for room: $roomName');
    } catch (e) {
      print('❌ Failed to save furniture state for room $roomName: $e');
      rethrow;
    }
  }

  /// Load the furniture state for a specific room
  Future<List<Map<String, dynamic>>> loadRoomFurnitureState({
    required String houseId,
    required String roomName,
  }) async {
    try {
      final snapshot = await _retryOperation(() async {
        return await _firestore
            .collection('houses')
            .doc(houseId)
            .collection('rooms')
            .doc(roomName)
            .get();
      });

      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        final items = data['furniture_items'] as List<dynamic>?;
        if (items != null) {
          return items.map((item) => item as Map<String, dynamic>).toList();
        }
      }
      print('📭 No furniture state found for room: $roomName');
      return [];
    } catch (e) {
      print('❌ Failed to load furniture state for room $roomName: $e');
      return [];
    }
  }

  /// Stream of furniture state changes for a specific room
  Stream<List<Map<String, dynamic>>> getRoomFurnitureStateStream({
    required String houseId,
    required String roomName,
  }) {
    return _firestore
        .collection('houses')
        .doc(houseId)
        .collection('rooms')
        .doc(roomName)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        final items = data['furniture_items'] as List<dynamic>?;
        if (items != null) {
          return items.map((item) => item as Map<String, dynamic>).toList();
        }
      }
      return <Map<String, dynamic>>[];
    });
  }

  /// Clear all furniture from a specific room
  Future<void> clearRoomFurniture({
    required String houseId,
    required String roomName,
  }) async {
    try {
      await _retryOperation(() async {
        await _firestore
            .collection('houses')
            .doc(houseId)
            .collection('rooms')
            .doc(roomName)
            .set({
          'furniture_items': [],
          'last_modified': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      print('✅ Cleared furniture for room: $roomName');
    } catch (e) {
      print('❌ Failed to clear furniture for room $roomName: $e');
      rethrow;
    }
  }
}

class _TaskLoad {
  _TaskLoad({
    required this.userId,
    required this.userName,
    required this.weeklyCount,
    required this.monthlyCount,
    required this.totalCount,
    required this.pendingCount,
  });

  final String userId;
  final String userName;
  final int weeklyCount;
  final int monthlyCount;
  final int totalCount;
  final int pendingCount; // NEW: Number of pending/assigned tasks

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': userName,
      'weeklyCount': weeklyCount,
      'monthlyCount': monthlyCount,
      'totalCount': totalCount,
      'pendingCount': pendingCount,
    };
  }
}

class _AssignmentResult {
  _AssignmentResult({
    required this.candidate,
    required this.wasRandomSelection,
    required this.tiedCandidatesCount,
    this.tiedCandidateNames,
  });

  final _TaskLoad candidate;
  final bool wasRandomSelection;
  final int tiedCandidatesCount;
  final List<String>? tiedCandidateNames;
}

