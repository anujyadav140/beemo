import 'dart:async';
import 'dart:math' as math;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'gemini_live_audio_service.dart';
import 'meeting_context_service.dart';
import 'meeting_signaling_service.dart';

/// Professional-grade audio service using Agora RTC Engine with Gemini AI
///
/// Architecture:
/// - All users join the same Agora channel for ultra-low latency audio (<50ms)
/// - Firebase signaling for participant tracking
/// - Gemini AI joins as virtual participant "Beemo AI"
/// - Audio from all users is sent to Gemini for live interaction
/// - Gemini's audio responses are broadcast to all participants
class AgoraMeetingService {
  AgoraMeetingService();

  // Agora App ID from https://console.agora.io/
  static const String _agoraAppId = '50b93c1b558a44daae3a8b869c45e048';
  static const int _geminiSampleRate = 24000;
  static const double _aiSpeakingLevelThreshold = 0.02;

  RtcEngine? _engine;
  int? _customAudioTrackId;
  StreamSubscription<String?>? _aiCoordinatorStreamSub;
  bool _aiCoordinatorClaimed = false;

  final MeetingSignalingService _signalingService = MeetingSignalingService();
  final GeminiLiveAudioService _geminiService = GeminiLiveAudioService();
  final MeetingContextService _contextService = MeetingContextService();

  String? _channelName;
  String? _currentUserId;
  String? _houseId;
  String? _meetingId;
  int? _localAgoraUid;
  bool _isMuted = false;
  bool _geminiEnabled = false;
  bool _isPaused = false;

  StreamSubscription? _geminiAudioSub;
  Timer? _aiSpeakingResetTimer;
  bool _aiIsSpeaking = false;

  // Map Agora UIDs to Firebase user IDs
  final Map<int, String> _uidToUserIdMap = {};
  // Map Firebase user IDs to display names for speaker identification
  final Map<String, String> _userIdToNameMap = {};
  // Store meeting context for building START messages
  MeetingContext? _meetingContext;
  // Track current participants from signaling service (real-time)
  List<MeetingParticipantState> _currentParticipants = [];

  // Audio level tracking
  final _localAudioLevelController = StreamController<double>.broadcast();
  final _remoteUsersController = StreamController<List<int>>.broadcast();
  final _speakingUserController = StreamController<String?>.broadcast();
  final _beemoAudioLevelController = StreamController<double>.broadcast();

  Stream<double> get localAudioLevel => _localAudioLevelController.stream;
  Stream<List<int>> get remoteUsers => _remoteUsersController.stream;
  Stream<String?> get speakingUserStream => _speakingUserController.stream;
  Stream<double> get beemoAudioLevel => _beemoAudioLevelController.stream;
  Stream<List<MeetingParticipantState>> get participantsStream =>
      _signalingService.participantsStream;

  Future<bool> initialize({
    required String userId,
    required String houseId,
    required String meetingId,
    required MeetingParticipantProfile profile,
  }) async {
    debugPrint('🎙️ Initializing Agora Meeting Service...');
    _currentUserId = userId;
    _houseId = houseId;
    _meetingId = meetingId;
    _channelName = '${houseId}_$meetingId';

    // Request permissions
    await [
      Permission.microphone,
      Permission.bluetooth,
      Permission.bluetoothConnect,
    ].request();

    try {
      // Initialize Agora Engine
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(RtcEngineContext(
        appId: _agoraAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      try {
        _customAudioTrackId = await _engine!.getMediaEngine().createCustomAudioTrack(
              trackType: AudioTrackType.audioTrackMixable,
              config: const AudioTrackConfig(enableLocalPlayback: false),
            );
        debugPrint(
          '? Created custom audio track for Beemo AI: $_customAudioTrackId',
        );
        if (_customAudioTrackId != null) {
          debugPrint('? Beemo custom audio track created successfully');
        }
      } catch (e, stackTrace) {
        _customAudioTrackId = null;
        debugPrint('?? Failed to create custom audio track: $e');
        debugPrint('$stackTrace');
      }

      // Register event handlers
      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          final uid = connection.localUid;
          debugPrint(
            '✅ Joined Agora channel: ${connection.channelId} (UID: $uid)',
          );
          if (uid != null && uid != 0) {
            _localAgoraUid = uid;
            // Map our own Agora UID to Firebase user ID
            _uidToUserIdMap[uid] = _currentUserId!;
            // Update Firebase with our Agora UID so others can map it
            _signalingService.updateAgoraUid(uid);
          }
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint('👤 User joined: UID $remoteUid');
          _updateRemoteUsers();
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          debugPrint('👋 User left: UID $remoteUid (reason: $reason)');
          _updateRemoteUsers();
        },
        onAudioVolumeIndication: (RtcConnection connection,
            List<AudioVolumeInfo> speakers, int speakerNumber, int totalVolume) {
          // Track audio levels for all speakers
          String? activeSpeaker;
          double maxVolume = 0.0;

          for (final speaker in speakers) {
            final volume = speaker.volume! / 255.0;

            if (speaker.uid == 0) {
              // Local user
              if (_isPaused) {
                _localAudioLevelController.add(0);
                continue;
              }
              _localAudioLevelController.add(volume);

              // Check if local user is speaking loudest
              if (volume > maxVolume && volume > 0.1) {
                maxVolume = volume;
                activeSpeaker = _currentUserId;
              }
            } else {
              // Remote user - check if they're speaking loudest
              if (volume > maxVolume && volume > 0.1) {
                maxVolume = volume;
                // Map Agora UID to Firebase user ID
                activeSpeaker = _uidToUserIdMap[speaker.uid];
              }
            }
          }

          // Emit the currently speaking user (or null if no one is speaking)
          _speakingUserController.add(activeSpeaker);

          // Log who is speaking for debugging (with display name if available)
          if (activeSpeaker != null && activeSpeaker != 'beemo_ai') {
            final displayName = _userIdToNameMap[activeSpeaker] ?? activeSpeaker;
            if (maxVolume > 0.2) { // Only log when volume is significant
              debugPrint('🎤 Speaker detected: $displayName (volume: ${maxVolume.toStringAsFixed(2)})');
            }
          }

          if (activeSpeaker != 'beemo_ai' || _isPaused) {
            _aiIsSpeaking = false;
            _aiSpeakingResetTimer?.cancel();
          }
        },
        onError: (ErrorCodeType err, String msg) {
          debugPrint('❌ Agora Error: $err - $msg');
        },
      ));

      // Enable audio
      await _engine!.enableAudio();
      await _engine!.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );

      // Set default audio route to loudspeaker for better volume
      await _engine!.setDefaultAudioRouteToSpeakerphone(true);

      // Increase playback volume for better audio clarity
      await _engine!.adjustPlaybackSignalVolume(200); // 200% volume
      await _engine!.adjustRecordingSignalVolume(200); // 200% recording volume

      // Join Firebase signaling for participant tracking
      await _signalingService.joinRoom(
        houseId: houseId,
        meetingId: meetingId,
        profile: profile,
      );

      // Listen to participants to build Agora UID mapping and name mapping
      _signalingService.participantsStream.listen((participants) {
        // Store current participants for Beemo context
        _currentParticipants = participants;
        debugPrint('🔄 Updated current participants: ${participants.length} people');

        for (final participant in participants) {
          // Map Agora UID to user ID
          if (participant.agoraUid != null && participant.userId.isNotEmpty) {
            _uidToUserIdMap[participant.agoraUid!] = participant.userId;
            debugPrint(
              '🗺️ Mapped Agora UID ${participant.agoraUid} -> ${participant.userId}',
            );
          }
          // Map user ID to display name for speaker identification
          if (participant.userId.isNotEmpty) {
            final displayName = participant.displayName;
            _userIdToNameMap[participant.userId] = displayName;
            debugPrint(
              '👤 Mapped User ID ${participant.userId} -> $displayName',
            );
          }
        }
      });

      _aiCoordinatorStreamSub?.cancel();
      _aiCoordinatorStreamSub =
          _signalingService.aiCoordinatorStream.listen((owner) {
        _aiCoordinatorClaimed = owner == _currentUserId;
      });


      debugPrint('✅ Agora Meeting Service initialized');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to initialize Agora: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  /// Join the Agora audio channel
  Future<void> joinChannel() async {
    if (_engine == null || _channelName == null) {
      debugPrint('⚠️ Cannot join channel: engine not initialized');
      return;
    }

    try {
      debugPrint('📞 Joining Agora channel: $_channelName');

      // Join channel with token (use null for testing, use RTC token in production)
      final publishCustomTrack = _customAudioTrackId != null;
      final mediaOptions = ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        autoSubscribeAudio: true,
        publishMicrophoneTrack: true,
        publishCustomAudioTrack: publishCustomTrack,
        publishCustomAudioTrackId:
            publishCustomTrack ? _customAudioTrackId : null,
      );

      await _engine!.joinChannel(
        token: '', // Replace with your Agora RTC token
        channelId: _channelName!,
        uid: 0, // Let Agora assign UID
        options: mediaOptions,
      );

      // Ensure loudspeaker is enabled for this channel
      await _engine!.setEnableSpeakerphone(true);

      await _signalingService.updatePresence('active');
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to join Agora channel: $e');
      debugPrint('$stackTrace');
    }
  }

  /// Toggle mute
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _engine?.muteLocalAudioStream(_isMuted);
    debugPrint('??? ');
  }

  Future<void> setPaused(bool paused) async {
    if (_isPaused == paused) return;
    _isPaused = paused;

    if (paused) {
      await _engine?.muteLocalAudioStream(true);
      await _engine?.enableLocalAudio(false);
      await _signalingService.updatePresence('paused');
      await _geminiService.stopConversation();
      await _geminiAudioSub?.cancel();
      _geminiAudioSub = null;
      _aiIsSpeaking = false;
      _aiSpeakingResetTimer?.cancel();
      _aiSpeakingResetTimer = null;
      _speakingUserController.add(null);
      _localAudioLevelController.add(0);
    } else {
      await _engine?.enableLocalAudio(true);
      await _engine?.muteLocalAudioStream(false);
      // Ensure loudspeaker is re-enabled when resuming
      await _engine?.setEnableSpeakerphone(true);
      await _signalingService.updatePresence('active');
      if (_geminiEnabled) {
        await _geminiService.startConversation(playLocally: true);
        _startGeminiForwarding();
      }
    }
  }

  /// Update hand raised status
  Future<void> setHandRaised(bool raised) async {
    await _signalingService.updateHandRaised(raised);
  }

  void _updateRemoteUsers() {
    // This would need proper implementation based on Agora's user list
    // For now just emit empty list
    _remoteUsersController.add([]);
  }


  Future<bool> _ensureAiCoordinator() async {
    if (_aiCoordinatorClaimed) {
      debugPrint('✅ Already claimed AI coordinator role');
      return true;
    }

    try {
      debugPrint('🔐 Attempting to claim AI coordinator role...');
      final claimed = await _signalingService.tryClaimAiCoordinator();
      _aiCoordinatorClaimed = claimed;

      if (claimed) {
        debugPrint('✅ Successfully claimed AI coordinator role!');
        debugPrint('   This user will run the SINGLE Beemo instance for the meeting');
      } else {
        debugPrint('⚠️ Unable to claim AI coordinator role - another user is already coordinator');
        debugPrint('   This user will NOT run Beemo to prevent multiple instances');
      }

      return claimed;
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to claim AI coordinator: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  void _startGeminiForwarding() {
    _geminiAudioSub?.cancel();
    _geminiAudioSub = _geminiService.geminiAudioOutput.listen((chunk) {
      if (chunk.isEmpty) {
        return;
      }
      _notifyAiSpeaking(chunk);
      unawaited(_pushGeminiAudioToAgora(chunk));
      unawaited(_signalingService.publishAiAudioChunk(chunk));
    }, onError: (error, stackTrace) {
      debugPrint('?? Gemini audio forwarding error: $error');
      debugPrint('$stackTrace');
    });
  }


  void _notifyAiSpeaking(Uint8List chunk) {
    if (_isPaused) {
      _beemoAudioLevelController.add(0);
      return;
    }
    final level = _computeAudioLevel(chunk);

    // Always emit the audio level for visualization, amplified for better visibility
    final amplifiedLevel = (level * 5.0).clamp(0.0, 1.0);
    _beemoAudioLevelController.add(amplifiedLevel);

    if (amplifiedLevel > 0.1) {
      debugPrint('🎵 Beemo audio level: ${amplifiedLevel.toStringAsFixed(2)}');
    }

    if (level < _aiSpeakingLevelThreshold) {
      return;
    }
    _aiIsSpeaking = true;
    _speakingUserController.add('beemo_ai');
    _aiSpeakingResetTimer?.cancel();
    _aiSpeakingResetTimer = Timer(const Duration(milliseconds: 600), () {
      if (!_aiIsSpeaking) {
        return;
      }
      _aiIsSpeaking = false;
      _speakingUserController.add(null);
      _beemoAudioLevelController.add(0);
    });
  }

  Future<void> _pushGeminiAudioToAgora(Uint8List chunk) async {
    final engine = _engine;
    final trackId = _customAudioTrackId;
    if (engine == null || trackId == null || chunk.isEmpty) {
      return;
    }

    final samplesPerChannel = chunk.length ~/ 2;
    if (samplesPerChannel <= 0) {
      return;
    }

    try {
      final frame = AudioFrame(
        type: AudioFrameType.frameTypePcm16,
        samplesPerChannel: samplesPerChannel,
        bytesPerSample: BytesPerSample.twoBytesPerSample,
        channels: 1,
        samplesPerSec: _geminiSampleRate,
        buffer: chunk,
        renderTimeMs: DateTime.now().millisecondsSinceEpoch,
      );
      await engine.getMediaEngine().pushAudioFrame(
        frame: frame,
        trackId: trackId,
      );
    } catch (e, stackTrace) {
      debugPrint('?? Failed to push Gemini audio to Agora: $e');
      debugPrint('$stackTrace');
    }
  }


  double _computeAudioLevel(Uint8List pcmBytes) {
    if (pcmBytes.isEmpty) return 0;
    final byteData = pcmBytes.buffer.asByteData();
    double sumSquares = 0;
    for (var i = 0; i < pcmBytes.length; i += 2) {
      final sample = byteData.getInt16(i, Endian.little).toDouble();
      sumSquares += sample * sample;
    }
    final meanSquare = sumSquares / (pcmBytes.length / 2);
    return math.sqrt(meanSquare) / 32768.0;
  }

  /// Enable Gemini AI in the meeting with Firebase-fetched context
  ///
  /// CONTEXT FETCHING FLOW:
  /// 1. Fetches meeting context from Firebase (participants + agendas)
  /// 2. Builds dynamic Beemo prompt with this context
  /// 3. Initializes Gemini with the context-aware prompt
  /// 4. Sends START signal to begin meeting
  ///
  /// This ensures Beemo knows:
  /// - Who is in the meeting (names, emojis)
  /// - What agendas to discuss
  /// - Meeting-specific details
  Future<bool> enableGemini() async {
    if (_geminiEnabled) {
      debugPrint('⚠️ Gemini already enabled');
      return true;
    }

    try {
      debugPrint('🤖 Enabling Gemini AI...');
      _aiIsSpeaking = false;

      // STEP 1: Fetch meeting context from Firebase to make Beemo context-aware
      String? systemPrompt;
      if (_houseId != null && _meetingId != null) {
        try {
          // WAIT for participants to be available (they're coming from the stream)
          debugPrint('⏳ Waiting for participants to join...');
          int waitAttempts = 0;
          while (_currentParticipants.isEmpty && waitAttempts < 10) {
            await Future.delayed(const Duration(milliseconds: 500));
            waitAttempts++;
            debugPrint('   Attempt $waitAttempts/10: ${_currentParticipants.length} participants');
          }

          if (_currentParticipants.isNotEmpty) {
            debugPrint('✅ Participants ready! Found ${_currentParticipants.length} people');
          } else {
            debugPrint('⚠️ Proceeding without participants after waiting');
          }

          debugPrint('📡 Fetching meeting context with live participants...');
          debugPrint('   Current participants in memory: ${_currentParticipants.length}');
          final context = await _contextService.fetchMeetingContext(
            houseId: _houseId!,
            meetingId: _meetingId!,
            liveParticipants: _currentParticipants, // Pass real-time participants!
          );
          // Store context for later use in START message
          _meetingContext = context;

          // STEP 2: Build dynamic prompt with Firebase data (participants + agendas)
          systemPrompt = _contextService.buildBeemoPrompt(context);
          debugPrint('✅ Context loaded from Firebase: ${context.agendas.length} agendas, ${context.participants.length} participants');

          // DEBUG: Show what context we're giving to Beemo
          debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          debugPrint('🔥 CONTEXT BEING PASSED TO BEEMO:');
          debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          debugPrint('📊 Participants (${context.participants.length}):');
          for (var p in context.participants) {
            debugPrint('   → ${p.avatarEmoji} ${p.displayName} (${p.userId})');
          }
          debugPrint('\n📋 Agendas (${context.agendas.length}):');
          for (var i = 0; i < context.agendas.length; i++) {
            debugPrint('   ${i + 1}. "${context.agendas[i].title}"');
            debugPrint('      Details: ${context.agendas[i].details}');
          }
          debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
        } catch (e) {
          debugPrint('⚠️ Failed to fetch Firebase context: $e');
          // Continue with default prompt if context fetch fails
        }
      }

      // STEP 3: Initialize Gemini service with context-aware system prompt
      debugPrint('🔧 Initializing Gemini with ${systemPrompt != null ? 'custom context-aware' : 'default'} system prompt...');
      await _geminiService.initialize(systemInstruction: systemPrompt);

      // CRITICAL: Claim AI coordinator role BEFORE starting Gemini
      // This ensures only ONE Beemo instance runs per meeting!
      final isCoordinator = await _ensureAiCoordinator();
      if (!isCoordinator) {
        debugPrint('🚫 NOT AI coordinator - aborting Gemini initialization');
        debugPrint('   Another user in the meeting is already running Beemo');
        debugPrint('   Only ONE Beemo instance should run per meeting to prevent chaos!');
        return false; // ABORT if not coordinator
      }

      debugPrint('🎯 Confirmed as AI coordinator - proceeding with Gemini startup');

      // Set up transcript listeners
      _setupTranscriptListeners();

      // STEP 4: Start bidirectional audio conversation
      await _geminiService.startConversation(playLocally: true);
      _startGeminiForwarding();

      // STEP 5: Send START signal to trigger Beemo with context
      // Build explicit START message with participant and agenda info
      final startMessage = _buildContextAwareStartMessage();
      await Future.delayed(const Duration(milliseconds: 500)); // Brief delay to ensure session is ready
      await _geminiService.sendTextPrompt(startMessage);
      debugPrint('🎬 START signal sent with explicit context');
      debugPrint('   Message: $startMessage');

      _geminiEnabled = true;
      debugPrint('? Gemini AI enabled in meeting - Live audio streaming active!');
      return true;
    } catch (e, stackTrace) {
      debugPrint('? Failed to enable Gemini: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  /// Disable Gemini AI
  Future<void> disableGemini() async {
    if (!_geminiEnabled) return;

    debugPrint('?? Disabling Gemini AI...');

    _geminiService.stopConversation();
    await _geminiAudioSub?.cancel();
    _geminiAudioSub = null;
    _aiSpeakingResetTimer?.cancel();
    _aiSpeakingResetTimer = null;
    _speakingUserController.add(null);
    _aiIsSpeaking = false;

    if (_aiCoordinatorClaimed) {
      await _signalingService.releaseAiCoordinator();
      _aiCoordinatorClaimed = false;
    }

    _geminiEnabled = false;
    debugPrint('? Gemini AI disabled');
  }

  /// Manually trigger Gemini with text (for testing)
  Future<void> askGemini(String question) async {
    if (!_geminiEnabled) {
      debugPrint('⚠️ Gemini not enabled');
      return;
    }
    await _geminiService.sendTextPrompt(question);
  }

  /// Build context-aware START message with explicit participant and agenda information
  String _buildContextAwareStartMessage() {
    if (_meetingContext == null || _meetingContext!.participants.isEmpty) {
      return 'START - Begin the meeting now! Greet everyone and introduce the agendas.';
    }

    final participants = _meetingContext!.participants
        .map((p) => p.displayName)
        .join(', ');

    final agendaInfo = _meetingContext!.agendas.isEmpty
        ? 'No specific agendas today - just facilitate a general discussion.'
        : 'The agendas for this meeting are: ${_meetingContext!.agendas.map((a) => a.title).join(', ')}';

    return '''
START - Begin the meeting NOW!

REMINDER - You have ${_meetingContext!.participants.length} people in this meeting: $participants

$agendaInfo

Your task:
1. Greet everyone enthusiastically by name
2. List ALL the agendas we're discussing today
3. Ask who wants to start

Be energetic and brief! Remember: you know exactly who is here and what we're discussing!
''';
  }

  StreamSubscription? _userTranscriptSub;
  StreamSubscription? _beemoTranscriptSub;

  /// Set up transcript listeners to store conversation to Firebase
  void _setupTranscriptListeners() {
    if (_meetingId == null) return;

    // Listen to user transcripts
    _userTranscriptSub = _geminiService.userTranscript.listen((text) {
      _contextService.addTranscriptEntry(
        meetingId: _meetingId!,
        speaker: 'User',
        text: text,
        speakerType: 'user',
      );
    });

    // Listen to Beemo transcripts
    _beemoTranscriptSub = _geminiService.beemoTranscript.listen((text) {
      _contextService.addTranscriptEntry(
        meetingId: _meetingId!,
        speaker: 'Beemo',
        text: text,
        speakerType: 'beemo',
      );
    });

    debugPrint('📝 Transcript listeners set up');
  }

  /// Leave the call
  Future<void> leaveChannel() async {
    debugPrint('👋 Leaving Agora channel...');

    await _engine?.leaveChannel();
    await _signalingService.updatePresence('ended');
    await _signalingService.leaveRoom();

    debugPrint('✅ Left channel');
  }

  /// Dispose all resources
  Future<void> dispose() async {
    debugPrint('🧹 Disposing Agora Meeting Service...');

    await _aiCoordinatorStreamSub?.cancel();
    _aiCoordinatorStreamSub = null;

    await disableGemini();
    _aiSpeakingResetTimer?.cancel();
    _aiSpeakingResetTimer = null;

    if (_customAudioTrackId != null) {
      try {
        await _engine?.getMediaEngine().destroyCustomAudioTrack(_customAudioTrackId!);
      } catch (e, stackTrace) {
        debugPrint('?? Failed to destroy custom audio track: $e');
        debugPrint('$stackTrace');
      }
      _customAudioTrackId = null;
    }
    await leaveChannel();

    await _engine?.release();
    _engine = null;

    await _localAudioLevelController.close();
    await _remoteUsersController.close();
    await _speakingUserController.close();
    await _beemoAudioLevelController.close();
    await _userTranscriptSub?.cancel();
    await _beemoTranscriptSub?.cancel();
    await _signalingService.dispose();
    await _geminiService.dispose();
    await _contextService.dispose();

    debugPrint('✅ Disposed');
  }
}
