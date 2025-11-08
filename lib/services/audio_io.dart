import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

/// Handles microphone capture and exposes a live PCM16 mono stream.
class MeetingAudioInput extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioEncoder _encoder = AudioEncoder.pcm16bits;

  Stream<Uint8List>? _audioStream;
  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isPaused = false;

  bool get isInitialized => _isInitialized;
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;

  Future<void> init() async {
    if (_isInitialized) return;
    debugPrint('🔐 Checking microphone permission...');
    final hasPermission = await _recorder.hasPermission();
    debugPrint('🔐 Microphone permission: $hasPermission');
    if (!hasPermission) {
      debugPrint('❌ Microphone permission denied!');
      throw MicrophonePermissionDeniedException(
        'Microphone permission must be granted to join the meeting audio.',
      );
    }
    debugPrint('✅ Microphone permission granted');
    _isInitialized = true;
    notifyListeners();
  }

  Future<Stream<Uint8List>?> start() async {
    if (!_isInitialized) {
      await init();
    }
    if (_isRecording) {
      debugPrint('🎤 Already recording, returning existing stream');
      return _audioStream;
    }

    debugPrint('🎤 Starting audio recorder with config: 24kHz, PCM16, mono');
    final config = RecordConfig(
      encoder: _encoder,
      sampleRate: 24000,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      androidConfig: const AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication,
      ),
      iosConfig: const IosRecordConfig(categoryOptions: []),
    );

    _audioStream = await _recorder.startStream(config);
    _isRecording = true;
    _isPaused = false;
    debugPrint('✅ Audio recorder started, stream: ${_audioStream != null}');
    notifyListeners();
    return _audioStream;
  }

  Future<void> stop() async {
    await _recorder.stop();
    _audioStream = null;
    _isRecording = false;
    _isPaused = false;
    notifyListeners();
  }

  Future<void> togglePause() async {
    if (!_isRecording) return;
    if (_isPaused) {
      await _recorder.resume();
      _isPaused = false;
    } else {
      await _recorder.pause();
      _isPaused = true;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }
}

/// Streams decoded PCM chunks to the output speaker using SoLoud.
class MeetingAudioOutput {
  AudioSource? _stream;
  SoundHandle? _handle;
  bool _initialized = false;

  final _isPlayingController = StreamController<bool>.broadcast();

  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  Future<void> init() async {
    if (_initialized) return;
    await SoLoud.instance.init(sampleRate: 24000, channels: Channels.mono);
    await _prepareStream();
    _initialized = true;
  }

  Future<void> _prepareStream() async {
    await stop();
    _stream = SoLoud.instance.setBufferStream(
      maxBufferSizeBytes: 1024 * 1024 * 6,
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0,
      onBuffering: (isBuffering, handle, time) {},
    );
    _handle = null;
  }

  Future<void> play() async {
    if (_stream == null) {
      await _prepareStream();
    }
    _handle = await SoLoud.instance.play(_stream!);
    _isPlayingController.add(true);
  }

  void addChunk(Uint8List data) {
    if (_stream == null) return;
    SoLoud.instance.addAudioDataStream(_stream!, data);
    _isPlayingController.add(true);
  }

  Future<void> stop() async {
    if (_stream != null &&
        _handle != null &&
        SoLoud.instance.getIsValidVoiceHandle(_handle!)) {
      SoLoud.instance.setDataIsEnded(_stream!);
      await SoLoud.instance.stop(_handle!);
      _isPlayingController.add(false);
    }
  }

  Future<void> dispose() async {
    await stop();
    SoLoud.instance.deinit();
    await _isPlayingController.close();
  }
}

/// Calculates the root-mean-square level from a PCM16 mono buffer.
double pcmLevel(Uint8List pcmBytes) {
  if (pcmBytes.isEmpty) return 0;
  final byteData = pcmBytes.buffer.asByteData();
  double sumSquares = 0;
  for (var i = 0; i < pcmBytes.lengthInBytes; i += 2) {
    final sample = byteData.getInt16(i, Endian.little).toDouble();
    sumSquares += sample * sample;
  }
  final meanSquare = sumSquares / (pcmBytes.lengthInBytes / 2);
  final rms = sqrt(meanSquare) / 32768.0;
  return rms.clamp(0.0, 1.0);
}

/// Thrown when the meeting audio pipeline cannot acquire the microphone.
class MicrophonePermissionDeniedException implements Exception {
  MicrophonePermissionDeniedException(this.message);
  final String message;

  @override
  String toString() => 'MicrophonePermissionDeniedException: $message';
}
