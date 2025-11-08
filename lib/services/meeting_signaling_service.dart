import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Profile information supplied when a participant joins a meeting room.
class MeetingParticipantProfile {
  MeetingParticipantProfile({
    required this.userId,
    required this.displayName,
    this.avatarEmoji = '🙂',
    this.avatarColor,
  });

  final String userId;
  final String displayName;
  final String avatarEmoji;
  final int? avatarColor;

  Map<String, Object?> toMap() => {
    'displayName': displayName,
    'avatarEmoji': avatarEmoji,
    'avatarColor': avatarColor,
  };
}

/// Participant state snapshot emitted from Firebase Realtime Database.
class MeetingParticipantState {
  MeetingParticipantState({
    required this.userId,
    required this.displayName,
    required this.avatarEmoji,
    required this.avatarColor,
    required this.handRaised,
    required this.isSpeaking,
    required this.isInQueue,
    required this.state,
    required this.audioLevel,
    required this.joinedAtMillis,
    required this.lastSeenMillis,
    this.agoraUid,
  });

  final String userId;
  final String displayName;
  final String avatarEmoji;
  final int? avatarColor;
  final bool handRaised;
  final bool isSpeaking;
  final bool isInQueue;
  final String state;
  final double audioLevel;
  final int? joinedAtMillis;
  final int? lastSeenMillis;
  final int? agoraUid;

  bool get isPresent => state == 'active' || state == 'paused';

  MeetingParticipantState copyWith({
    bool? handRaised,
    bool? isSpeaking,
    bool? isInQueue,
    String? state,
    double? audioLevel,
    int? lastSeenMillis,
  }) {
    return MeetingParticipantState(
      userId: userId,
      displayName: displayName,
      avatarEmoji: avatarEmoji,
      avatarColor: avatarColor,
      handRaised: handRaised ?? this.handRaised,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isInQueue: isInQueue ?? this.isInQueue,
      state: state ?? this.state,
      audioLevel: audioLevel ?? this.audioLevel,
      joinedAtMillis: joinedAtMillis,
      lastSeenMillis: lastSeenMillis ?? this.lastSeenMillis,
    );
  }

  static MeetingParticipantState fromData(
    String userId,
    Map<String, Object?> data,
  ) {
    return MeetingParticipantState(
      userId: userId,
      displayName: data['displayName']?.toString() ?? 'Member',
      avatarEmoji: data['avatarEmoji']?.toString() ?? '🙂',
      avatarColor: data['avatarColor'] is int
          ? data['avatarColor'] as int
          : null,
      handRaised: _asBool(data['handRaised']),
      isSpeaking: _asBool(data['isSpeaking']),
      isInQueue: _asBool(data['isInQueue']),
      state: data['state']?.toString() ?? 'offline',
      audioLevel: _asDouble(data['audioLevel']),
      joinedAtMillis: _asInt(data['joinedAt']),
      lastSeenMillis: _asInt(data['lastSeen']),
      agoraUid: _asInt(data['agoraUid']),
    );
  }

  static bool _asBool(Object? input) {
    if (input is bool) return input;
    if (input is num) return input != 0;
    if (input is String) return input.toLowerCase() == 'true';
    return false;
  }

  static double _asDouble(Object? input) {
    if (input is double) return input;
    if (input is int) return input.toDouble();
    if (input is num) return input.toDouble();
    if (input is String) {
      final parsed = double.tryParse(input);
      if (parsed != null) return parsed;
    }
    return 0;
  }

  static int? _asInt(Object? input) {
    if (input is int) return input;
    if (input is double) return input.toInt();
    if (input is num) return input.toInt();
    if (input is String) {
      return int.tryParse(input);
    }
    return null;
  }
}

/// Simple signaling payload exchanged between peers via Firebase.
class SignalingMessage {
  SignalingMessage({
    required this.fromUserId,
    required this.payload,
    required this.timestampMillis,
  });

  final String fromUserId;
  final Map<String, dynamic> payload;
  final int? timestampMillis;
}

/// Provides a WebSocket-like abstraction backed by Firebase Realtime Database
/// for coordinating meeting participation, presence, and peer signaling.
class MeetingSignalingService {
  MeetingSignalingService({FirebaseDatabase? database})
    : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  final _participantsController =
      StreamController<List<MeetingParticipantState>>.broadcast();
  final _incomingSignalsController =
      StreamController<SignalingMessage>.broadcast();

  DatabaseReference? _roomRef;
  DatabaseReference? _participantRef;
  DatabaseReference? _audioRef;
  DatabaseReference? _aiSessionRef;
  DatabaseReference? _aiAudioRef;
  StreamSubscription<DatabaseEvent>? _participantsSubscription;
  StreamSubscription<DatabaseEvent>? _signalsSubscription;
  StreamSubscription<DatabaseEvent>? _aiSessionSubscription;
  Timer? _heartbeatTimer;
  Timer? _aiHeartbeatTimer;

  String? _houseId;
  String? _meetingId;
  String? _userId;

  DateTime? _lastAudioPublish;
  DateTime? _lastAudioLevelUpdate;
  DateTime? _lastAiAudioPublish;
  bool _isAiCoordinator = false;

  final _aiCoordinatorController = StreamController<String?>.broadcast();

  Stream<List<MeetingParticipantState>> get participantsStream =>
      _participantsController.stream;

  Stream<SignalingMessage> get incomingSignals =>
      _incomingSignalsController.stream;

  Stream<String?> get aiCoordinatorStream => _aiCoordinatorController.stream;

  Future<void> joinRoom({
    required String houseId,
    required String meetingId,
    required MeetingParticipantProfile profile,
  }) async {
    _houseId = houseId;
    _meetingId = meetingId;
    _userId = profile.userId;

    final roomPath = 'meetingRooms/$houseId/$meetingId';
    _roomRef = _database.ref(roomPath);

    debugPrint('🔵 Joining meeting room: $roomPath');
    debugPrint('🔵 User: ${profile.userId} (${profile.displayName})');

    // Set up listeners BEFORE writing our own data to catch all participants
    _listenToParticipants();
    _listenForSignals(profile.userId);
    _listenToAiCoordinator();

    // Now write our participant data
    await _roomRef!.child('metadata').update({
      'createdAt': ServerValue.timestamp,
      'active': true,
    });

    _participantRef = _roomRef!.child('participants').child(profile.userId);
    await _participantRef!.set({
      ...profile.toMap(),
      'state': 'active',
      'handRaised': false,
      'isSpeaking': false,
      'isInQueue': false,
      'audioLevel': 0,
      'joinedAt': ServerValue.timestamp,
      'lastSeen': ServerValue.timestamp,
    });

    debugPrint('✅ Participant data written for ${profile.userId}');

    _participantRef!.onDisconnect().remove();

    _audioRef = _roomRef!.child('audioStreams').child(profile.userId);
    _audioRef!.onDisconnect().remove();

    _aiSessionRef = _roomRef!.child('aiSession');
    _aiAudioRef = _roomRef!.child('audioStreams').child('beemo_ai');

    _startHeartbeat();

    // Force an initial sync to catch any existing participants
    await _syncExistingParticipants();
  }

  Future<void> _syncExistingParticipants() async {
    final ref = _roomRef;
    if (ref == null) return;

    try {
      final snapshot = await ref.child('participants').get();
      final snapshotValue = snapshot.value;
      final participants = <MeetingParticipantState>[];

      if (snapshotValue is Map) {
        snapshotValue.forEach((key, value) {
          final userId = key.toString();
          final data = _castToMap(value);
          participants.add(MeetingParticipantState.fromData(userId, data));
        });
      }

      participants.sort((a, b) {
        final aTs = a.joinedAtMillis ?? 0;
        final bTs = b.joinedAtMillis ?? 0;
        return aTs.compareTo(bTs);
      });

      debugPrint(
        '🔄 Initial sync found ${participants.length} participant(s): ${participants.map((p) => p.displayName).join(", ")}',
      );
      _participantsController.add(participants);
    } catch (e) {
      debugPrint('⚠️ Failed to sync existing participants: $e');
    }
  }

  Future<void> updatePresence(String state) async {
    final ref = _participantRef;
    if (ref == null) return;
    await ref.update({'state': state, 'lastSeen': ServerValue.timestamp});
  }

  Future<void> updateSpeakingState({
    required bool isSpeaking,
    double? audioLevel,
  }) async {
    final ref = _participantRef;
    if (ref == null) return;

    final update = <String, Object?>{
      'isSpeaking': isSpeaking,
      'lastSeen': ServerValue.timestamp,
    };
    if (audioLevel != null) {
      update['audioLevel'] = double.parse(audioLevel.toStringAsFixed(4));
    }
    await ref.update(update);
  }

  Future<void> updateHandRaised(bool raised) async {
    final ref = _participantRef;
    if (ref == null) return;
    await ref.update({
      'handRaised': raised,
      'isInQueue': raised,
      'lastSeen': ServerValue.timestamp,
    });
  }

  Future<void> updateAgoraUid(int agoraUid) async {
    final ref = _participantRef;
    if (ref == null) return;
    debugPrint('📝 Updating Agora UID: $agoraUid');
    await ref.update({
      'agoraUid': agoraUid,
      'lastSeen': ServerValue.timestamp,
    });
  }

  Future<void> reportAudioLevel(double level) async {
    final ref = _participantRef;
    if (ref == null) return;

    final now = DateTime.now();
    if (_lastAudioLevelUpdate != null &&
        now.difference(_lastAudioLevelUpdate!).inMilliseconds < 200) {
      return;
    }
    _lastAudioLevelUpdate = now;

    await ref.update({
      'audioLevel': double.parse(level.toStringAsFixed(4)),
      'lastSeen': ServerValue.timestamp,
    });
  }

  Future<void> publishAudioChunk(Uint8List chunk) async {
    if (chunk.isEmpty) return;
    final ref = _audioRef;
    if (ref == null) return;

    final now = DateTime.now();
    if (_lastAudioPublish != null &&
        now.difference(_lastAudioPublish!).inMilliseconds < 120) {
      return;
    }
    _lastAudioPublish = now;

    await ref.set({
      'chunk': base64Encode(chunk),
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> publishAiAudioChunk(Uint8List chunk) async {
    if (!_isAiCoordinator) return;
    if (chunk.isEmpty) return;
    final ref = _aiAudioRef;
    if (ref == null) return;

    final now = DateTime.now();
    if (_lastAiAudioPublish != null &&
        now.difference(_lastAiAudioPublish!).inMilliseconds < 80) {
      return;
    }
    _lastAiAudioPublish = now;

    await ref.set({
      'chunk': base64Encode(chunk),
      'timestamp': ServerValue.timestamp,
    });
  }

  Stream<Uint8List> subscribeToRemoteAudio(String remoteUserId) {
    final roomRef = _roomRef;
    if (roomRef == null) return const Stream.empty();

    return roomRef
        .child('audioStreams')
        .child(remoteUserId)
        .onValue
        .map((event) {
          final raw = event.snapshot.value;
          if (raw is Map) {
            final data = raw.cast<Object?, Object?>();
            final chunk = data['chunk'];
            if (chunk is String && chunk.isNotEmpty) {
              try {
                return base64Decode(chunk);
              } catch (e) {
                debugPrint('⚠️ Failed to decode audio chunk: $e');
              }
            }
          }
          return Uint8List(0);
        })
        .where((chunk) => chunk.isNotEmpty);
  }

  Stream<Uint8List> subscribeToAiAudio() {
    final roomRef = _roomRef;
    if (roomRef == null) return const Stream.empty();

    return roomRef
        .child('audioStreams')
        .child('beemo_ai')
        .onValue
        .map((event) {
          final raw = event.snapshot.value;
          if (raw is Map) {
            final data = _castToMap(raw);
            final chunk = data['chunk'];
            if (chunk is String && chunk.isNotEmpty) {
              try {
                return base64Decode(chunk);
              } catch (e) {
                debugPrint('�s��,? Failed to decode AI audio chunk: $e');
              }
            }
          }
          return Uint8List(0);
        })
        .where((chunk) => chunk.isNotEmpty);
  }

  Future<bool> tryClaimAiCoordinator({
    Duration leaseDuration = const Duration(seconds: 6),
  }) async {
    final ref = _aiSessionRef;
    final userId = _userId;
    if (ref == null || userId == null) return false;

    try {
      final snapshot = await ref.get();
      final data = _castToMap(snapshot.value);
      final owner = data['coordinator']?.toString();
      final heartbeat = MeetingParticipantState._asInt(data['heartbeat']);
      final now = DateTime.now().millisecondsSinceEpoch;
      final leaseExpired =
          heartbeat == null || now - heartbeat > leaseDuration.inMilliseconds;

      if (owner == userId) {
        _isAiCoordinator = true;
        _startAiHeartbeat();
        try {
          await _aiAudioRef?.onDisconnect().remove();
        } catch (e) {
          debugPrint('�s��,? Failed to register AI audio onDisconnect: $e');
        }
        _aiCoordinatorController.add(userId);
        return true;
      }

      if (owner == null || leaseExpired) {
        await ref.set({
          'coordinator': userId,
          'heartbeat': ServerValue.timestamp,
        });
        final confirmation = await ref.child('coordinator').get();
        final confirmedOwner = confirmation.value?.toString();
        final didClaim = confirmedOwner == userId;
        _isAiCoordinator = didClaim;
        if (didClaim) {
          _startAiHeartbeat();
          try {
            await _aiAudioRef?.onDisconnect().remove();
          } catch (e) {
            debugPrint('�s��,? Failed to register AI audio onDisconnect: $e');
          }
          _aiCoordinatorController.add(userId);
        }
        return didClaim;
      }
    } catch (e) {
      debugPrint('�s��,? Failed to claim AI coordinator: $e');
    }
    return false;
  }

  Future<void> releaseAiCoordinator() async {
    final ref = _aiSessionRef;
    final userId = _userId;
    _stopAiHeartbeat();
    _isAiCoordinator = false;
    if (ref == null || userId == null) return;

    try {
      final snapshot = await ref.get();
      final data = _castToMap(snapshot.value);
      final owner = data['coordinator']?.toString();
      if (owner == userId) {
        await ref.remove();
        try {
          await _aiAudioRef?.onDisconnect().cancel();
        } catch (e) {
          debugPrint('�s��,? Failed to cancel AI audio onDisconnect: $e');
        }
      }
    } catch (e) {
      debugPrint('�s��,? Failed to release AI coordinator: $e');
    }
    _aiCoordinatorController.add(null);
  }

  Future<void> sendSignal({
    required String targetUserId,
    required Map<String, dynamic> payload,
  }) async {
    final ref = _roomRef;
    final from = _userId;
    if (ref == null || from == null) return;

    final messageRef = ref.child('signaling').child(targetUserId).push();
    await messageRef.set({
      'from': from,
      'payload': payload,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> leaveRoom() async {
    await _participantsSubscription?.cancel();
    await _signalsSubscription?.cancel();
    await _aiSessionSubscription?.cancel();
    _participantsSubscription = null;
    _signalsSubscription = null;
    _aiSessionSubscription = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _stopAiHeartbeat();

    await _participantRef?.remove();
    await _audioRef?.remove();
    if (_isAiCoordinator) {
      await _aiSessionRef?.remove();
      await _aiAudioRef?.remove();
    }
    _isAiCoordinator = false;

    _roomRef = null;
    _participantRef = null;
    _audioRef = null;
    _aiSessionRef = null;
    _aiAudioRef = null;
    _houseId = null;
    _meetingId = null;
    _userId = null;
  }

  Future<void> dispose() async {
    await leaveRoom();
    await _participantsController.close();
    await _incomingSignalsController.close();
    await _aiCoordinatorController.close();
  }

  void _listenToParticipants() {
    final ref = _roomRef;
    if (ref == null) return;

    debugPrint('🎧 Setting up participant listener...');
    _participantsSubscription?.cancel();
    _participantsSubscription = ref
        .child('participants')
        .onValue
        .listen(
          (event) {
            final snapshotValue = event.snapshot.value;
            final participants = <MeetingParticipantState>[];

            if (snapshotValue is Map) {
              snapshotValue.forEach((key, value) {
                final userId = key.toString();
                final data = _castToMap(value);
                participants.add(
                  MeetingParticipantState.fromData(userId, data),
                );
              });
            }

            participants.sort((a, b) {
              final aTs = a.joinedAtMillis ?? 0;
              final bTs = b.joinedAtMillis ?? 0;
              return aTs.compareTo(bTs);
            });

            debugPrint('📢 Participants updated: ${participants.length} total');
            for (final p in participants) {
              debugPrint('   - ${p.displayName} (${p.userId}) [${p.state}]');
            }

            _participantsController.add(participants);
          },
          onError: (error) {
            debugPrint('⚠️ Participant listener error: $error');
          },
        );
  }

  void _listenForSignals(String userId) {
    final ref = _roomRef;
    if (ref == null) return;

    _signalsSubscription?.cancel();
    _signalsSubscription = ref
        .child('signaling')
        .child(userId)
        .onChildAdded
        .listen((event) {
          final payload = _castToMap(event.snapshot.value);
          final from = payload['from']?.toString();
          final data = payload['payload'];

          if (from != null && data is Map) {
            _incomingSignalsController.add(
              SignalingMessage(
                fromUserId: from,
                payload: data.cast<String, dynamic>(),
                timestampMillis: MeetingParticipantState._asInt(
                  payload['timestamp'],
                ),
              ),
            );
          }

          // Remove processed message to avoid duplicate delivery
          event.snapshot.ref.remove();
        });
  }

  void _listenToAiCoordinator() {
    final ref = _aiSessionRef;
    if (ref == null) return;

    _aiSessionSubscription?.cancel();
    _aiSessionSubscription = ref.onValue.listen((event) {
      final data = _castToMap(event.snapshot.value);
      final owner = data['coordinator']?.toString();
      _aiCoordinatorController.add(owner);
      if (owner != _userId) {
        _stopAiHeartbeat();
        _isAiCoordinator = false;
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      final ref = _participantRef;
      if (ref == null) return;
      await ref.update({'lastSeen': ServerValue.timestamp});
    });
  }

  void _startAiHeartbeat() {
    _aiHeartbeatTimer?.cancel();
    final ref = _aiSessionRef;
    if (ref == null) return;
    _aiHeartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        await ref.update({'heartbeat': ServerValue.timestamp});
      } catch (e) {
        debugPrint('�s��,? Failed to update AI heartbeat: $e');
      }
    });
  }

  void _stopAiHeartbeat() {
    _aiHeartbeatTimer?.cancel();
    _aiHeartbeatTimer = null;
  }

  static Map<String, Object?> _castToMap(Object? raw) {
    if (raw is Map) {
      return raw.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return <String, Object?>{};
  }
}
