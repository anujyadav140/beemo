import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

/// Service for bidirectional live audio streaming with Gemini 2.0 Flash Live
///
/// Architecture:
/// - Uses Gemini Live API for real-time bidirectional audio streaming
/// - Captures audio from microphone via record package
/// - Plays Gemini's audio responses via flutter_soloud
/// - Integrates with Agora meeting for multi-user conversations
/// - Provides live transcription of user speech and Beemo responses
class GeminiLiveAudioService {
  GeminiLiveAudioService();

  late final LiveGenerativeModel _liveModel;
  LiveSession? _session;
  bool _sessionOpened = false;
  bool _conversationActive = false;
  bool _playLocally = true;

  final _recorder = AudioRecorder();
  Stream<Uint8List>? _inputStream;
  AudioSource? _audioSource;
  SoundHandle? _soundHandle;

  StreamController<bool> _stopController = StreamController<bool>();

  // Stream controllers for audio, state, and transcription
  final _geminiAudioOutputController = StreamController<Uint8List>.broadcast();
  final _conversationStateController = StreamController<String>.broadcast();
  final _userTranscriptController = StreamController<String>.broadcast();
  final _beemoTranscriptController = StreamController<String>.broadcast();

  Stream<Uint8List> get geminiAudioOutput => _geminiAudioOutputController.stream;
  Stream<String> get conversationState => _conversationStateController.stream;
  Stream<String> get userTranscript => _userTranscriptController.stream;
  Stream<String> get beemoTranscript => _beemoTranscriptController.stream;

  /// Initialize Gemini Live Audio service with optional custom system instruction
  Future<void> initialize({String? systemInstruction}) async {
    debugPrint('🤖 Initializing Gemini Live Audio Service...');

    try {
      // Use custom system instruction if provided, otherwise use default
      final instruction = systemInstruction ?? '''
You are Beemo, a friendly AI household assistant participating in a voice meeting.

Your role:
- Listen to what household members are saying in the meeting
- Provide helpful, concise responses (keep it brief!)
- Help with task planning, scheduling, and household coordination
- Be warm, friendly, and supportive

Guidelines:
- Keep responses SHORT (1-2 sentences max when possible)
- Speak naturally like you're in a conversation
- Only respond when directly addressed or when you have something important to add
- If users are just chatting, listen quietly
- Be proactive about helping but not intrusive

Remember: This is a VOICE conversation in a meeting, so be conversational and brief!
''';

      debugPrint('📝 Using system instruction (${instruction.length} chars)');

      // Initialize LiveGenerativeModel for bidirectional audio streaming
      _liveModel = FirebaseAI.vertexAI().liveGenerativeModel(
        systemInstruction: Content.text(instruction),
        model: 'gemini-2.0-flash-live-preview-04-09',
        liveGenerationConfig: LiveGenerationConfig(
          speechConfig: SpeechConfig(voiceName: 'fenrir'),
          responseModalities: [ResponseModalities.audio],
        ),
      );

      // Initialize audio playback
      await SoLoud.instance.init(sampleRate: 24000, channels: Channels.mono);

      // Check microphone permission
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        debugPrint('⚠️ Microphone permission not granted');
        throw Exception('Microphone permission required for Gemini Live Audio');
      }

      debugPrint('✅ Gemini Live Audio Service initialized');
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to initialize Gemini Live Audio: $e');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  /// Start the bidirectional audio conversation
  Future<void> startConversation({bool playLocally = true}) async {
    if (_conversationActive) {
      debugPrint('⚠️ Conversation already active');
      return;
    }

    debugPrint('🎤 Starting Gemini conversation...');
    _conversationStateController.add('starting');
    _playLocally = playLocally;

    try {
      // Open Live session
      await _toggleLiveGeminiSession();

      // Start recording audio input stream
      _inputStream = await _startRecordingStream();
      debugPrint('✅ Input stream recording started');

      // Wrap input stream audio bytes in InlineDataPart and send to Gemini
      Stream<InlineDataPart> inlineDataStream = _inputStream!.map((data) {
        return InlineDataPart('audio/pcm', data);
      });
      _session!.sendMediaStream(inlineDataStream);

      // Start playing output audio stream (optional)
      if (_playLocally) {
        _audioSource = SoLoud.instance.setBufferStream(
          bufferingType: BufferingType.released,
          bufferingTimeNeeds: 0,
          onBuffering: (isBuffering, handle, time) {
            log('Buffering: isBuffering=$isBuffering, time=$time');
          },
        );
        _soundHandle = await SoLoud.instance.play(_audioSource!);
        debugPrint('? Output stream playback started');
      } else {
        _audioSource = null;
        _soundHandle = null;
        debugPrint('? Local playback disabled for Gemini audio');
      }
      debugPrint('✅ Output stream playback started');

      _conversationActive = true;
      _conversationStateController.add('listening');

      debugPrint('✅ Gemini conversation started');
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to start conversation: $e');
      debugPrint('$stackTrace');
      _conversationStateController.add('error');
    }
  }

  /// Stop the conversation
  Future<void> stopConversation() async {
    if (!_conversationActive) return;

    debugPrint('🛑 Stopping Gemini conversation...');

    try {
      // Stop recording input audio
      await _recorder.stop();

      // Stop playing output audio
      if (_playLocally && _audioSource != null && _soundHandle != null) {
        SoLoud.instance.setDataIsEnded(_audioSource!);
        await SoLoud.instance.stop(_soundHandle!);
      }

      // End the live session
      await _toggleLiveGeminiSession();

      _conversationActive = false;
      _conversationStateController.add('stopped');

      debugPrint('✅ Gemini conversation stopped');
    } catch (e, stackTrace) {
      debugPrint('❌ Error stopping conversation: $e');
      debugPrint('$stackTrace');
    }
  }

  /// Toggle Live Gemini Session
  Future<void> _toggleLiveGeminiSession() async {
    if (!_sessionOpened) {
      // Open session
      _session = await _liveModel.connect();
      _sessionOpened = true;

      // Start processing messages continuously
      unawaited(_processMessagesContinuously(stopSignal: _stopController));

      debugPrint('✅ Live session opened');
    } else {
      // Close session
      await _session?.close();
      _stopController.add(true);
      await _stopController.close();

      // Reset StreamController
      _stopController = StreamController<bool>();
      _sessionOpened = false;

      debugPrint('✅ Live session closed');
    }
  }

  /// Process messages continuously from Gemini
  Future<void> _processMessagesContinuously({
    required StreamController<bool> stopSignal,
  }) async {
    bool shouldContinue = true;

    stopSignal.stream.listen((stop) {
      if (stop) {
        shouldContinue = false;
      }
    });

    while (shouldContinue) {
      try {
        await for (final response in _session!.receive()) {
          LiveServerMessage message = response.message;
          await _handleLiveServerMessage(message);
        }
      } catch (e) {
        log('❌ Error receiving messages: $e');
        break;
      }
    }
  }

  /// Handle Live Server Message
  Future<void> _handleLiveServerMessage(LiveServerMessage response) async {
    if (response is LiveServerContent) {
      if (response.modelTurn != null) {
        await _handleLiveServerContent(response);
      }
      if (response.turnComplete != null && response.turnComplete!) {
        await _handleTurnComplete();
      }
      if (response.interrupted != null && response.interrupted!) {
        debugPrint('⚠️ Gemini interrupted: $response');
      }
    }
  }

  /// Handle Live Server Content
  Future<void> _handleLiveServerContent(LiveServerContent response) async {
    debugPrint('📨 Received response from Gemini!');
    final partList = response.modelTurn?.parts;

    if (partList != null) {
      for (final part in partList) {
        if (part is TextPart) {
          debugPrint('🤖 Gemini text: ${part.text}');
          _conversationStateController.add('speaking');

          // Emit Beemo's transcript
          if (part.text.isNotEmpty) {
            _beemoTranscriptController.add(part.text);
            debugPrint('💬 Beemo transcript emitted: ${part.text}');
          }
        } else if (part is InlineDataPart) {
          await _handleInlineDataPart(part);
        }
      }
    }

    // Note: User transcription is not directly available from LiveServerContent
    // Gemini Live API provides audio responses, not user speech transcription
    // User transcripts would need to be generated separately using Speech-to-Text
  }

  /// Handle Inline Data Part (audio output)
  Future<void> _handleInlineDataPart(InlineDataPart part) async {
    // If DataPart is audio, add data to the output audio stream
    if (part.mimeType.startsWith('audio')) {
      final audioData = part.bytes;
      debugPrint('🔊 Received ${audioData.length} bytes of audio from Gemini');

      // Add to audio output stream for playback
      if (_playLocally && _audioSource != null) {
        SoLoud.instance.addAudioDataStream(_audioSource!, audioData);
      }

      // Also emit to stream for external listeners (e.g., Agora)
      _geminiAudioOutputController.add(audioData);
      _conversationStateController.add('speaking');
    }
  }

  /// Handle turn complete
  Future<void> _handleTurnComplete() async {
    debugPrint('✅ Gemini turn complete');
    _conversationStateController.add('listening');
  }

  /// Start recording audio stream
  Future<Stream<Uint8List>> _startRecordingStream() async {
    final recordConfig = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 24000,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      androidConfig: const AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication,
      ),
      iosConfig: const IosRecordConfig(
        categoryOptions: [IosAudioCategoryOption.defaultToSpeaker],
      ),
    );

    return await _recorder.startStream(recordConfig);
  }

  /// Send a text prompt to Gemini (useful for triggering initial responses)
  Future<void> sendTextPrompt(String text) async {
    if (_session == null || !_sessionOpened) {
      debugPrint('⚠️ Cannot send text: session not open');
      return;
    }

    try {
      debugPrint('📤 Sending text to Gemini: $text');
      final textBytes = Uint8List.fromList(utf8.encode(text));
      _session!.sendMediaStream(Stream.value(InlineDataPart('text/plain', textBytes)));
      debugPrint('✅ Text sent successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to send text: $e');
      debugPrint('$stackTrace');
    }
  }

  /// Dispose service
  Future<void> dispose() async {
    debugPrint('🧹 Disposing Gemini Live Audio Service...');

    await stopConversation();
    await _recorder.dispose();
    await _geminiAudioOutputController.close();
    await _conversationStateController.close();
    await _userTranscriptController.close();
    await _beemoTranscriptController.close();

    debugPrint('✅ Disposed');
  }
}

/// Helper function for unawaited futures
void unawaited(Future<void> future) {
  // Ignore unawaited_futures lint
}
