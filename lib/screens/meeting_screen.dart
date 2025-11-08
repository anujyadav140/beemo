import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agenda_item_model.dart';
import '../providers/auth_provider.dart';
import '../providers/house_provider.dart';
import '../services/agora_meeting_service.dart';
import '../services/firestore_service.dart';
import '../services/meeting_signaling_service.dart';
import '../widgets/beemo_logo.dart';

// Meeting screen with 2x2 grid layout for participants
class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen>
    with TickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final AgoraMeetingService _audioService = AgoraMeetingService();

  bool _isPaused = false;
  bool _handRaised = false;
  final int _currentAgendaIndex = 0;
  late final AnimationController _voiceAnimationController;
  String? _meetingId;

  double _currentAudioLevel = 0.0;
  double _beemoAudioLevel = 0.0;
  String? _activeSpeakerId;
  String? _currentUserId;
  StreamSubscription<double>? _localLevelSub;
  StreamSubscription<double>? _beemoLevelSub;
  StreamSubscription<String?>? _speakingSub;

  int _remainingSeconds = 900;
  String _timerDisplay = '15:00';

  @override
  void initState() {
    super.initState();
    _voiceAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat(reverse: true);

    _initializeAudio();
    _startMeetingTimer();
  }

  Future<void> _initializeAudio() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final userId = authProvider.user?.uid;
    final houseId = houseProvider.currentHouseId;

    if (userId == null || houseId == null) return;

    _currentUserId = userId;

    _meetingId = await _resolveMeetingId(houseId);

    MeetingParticipantProfile participantProfile = MeetingParticipantProfile(
      userId: userId,
      displayName: authProvider.user?.displayName ?? 'Member',
    );

    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final userData = userDoc.data();
      final profileData = userData?['profile'] as Map<String, dynamic>?;

      final displayName = [
        profileData?['name']?.toString(),
        userData?['displayName']?.toString(),
        authProvider.user?.displayName,
      ].firstWhere(
        (value) => value != null && value.trim().isNotEmpty,
        orElse: () => 'Member',
      )!;

      final rawAvatarEmoji = profileData?['avatarEmoji']?.toString();
      final avatarEmoji = (rawAvatarEmoji != null && rawAvatarEmoji.isNotEmpty)
          ? rawAvatarEmoji
          : '🙂';
      final avatarColorRaw = profileData?['avatarColor'];
      final avatarColor = avatarColorRaw is int
          ? avatarColorRaw
          : int.tryParse(avatarColorRaw?.toString() ?? '');

      participantProfile = MeetingParticipantProfile(
        userId: userId,
        displayName: displayName,
        avatarEmoji: avatarEmoji,
        avatarColor: avatarColor,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load user profile for meeting: $e');
    }

    final initialized = await _audioService.initialize(
      userId: userId,
      houseId: houseId,
      meetingId: _meetingId!,
      profile: participantProfile,
    );

    if (!initialized || !mounted) return;

    await _audioService.joinChannel();
    await _audioService.enableGemini();

    _localLevelSub = _audioService.localAudioLevel.listen((level) {
      if (!mounted) return;
      setState(() => _currentAudioLevel = level);
    });

    _beemoLevelSub = _audioService.beemoAudioLevel.listen((level) {
      if (!mounted) return;
      if (level > 0.1) {
        debugPrint('📊 Meeting screen received Beemo level: ${level.toStringAsFixed(2)}');
      }
      setState(() => _beemoAudioLevel = level);
    });

    _speakingSub = _audioService.speakingUserStream.listen((speakerId) {
      if (!mounted) return;
      setState(() => _activeSpeakerId = speakerId);
    });
  }

  Future<String> _resolveMeetingId(String houseId) async {
    const fallbackSuffix = 'open-call';
    try {
      final scheduledTime =
          await _firestoreService.getNextMeetingTimeOnce(houseId);
      if (scheduledTime != null) {
        final epoch = scheduledTime.toUtc().millisecondsSinceEpoch;
        return '${houseId}_meeting_$epoch';
      }
    } catch (e) {
      debugPrint('?? Failed to resolve scheduled meeting time: $e');
    }
    return '${houseId}_meeting_$fallbackSuffix';
  }

  void _startMeetingTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;

      setState(() {
        if (_remainingSeconds > 0 && !_isPaused) {
          _remainingSeconds--;
          final minutes = _remainingSeconds ~/ 60;
          final seconds = _remainingSeconds % 60;
          _timerDisplay =
              '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        }
      });

      return mounted && _remainingSeconds > 0;
    });
  }

  @override
  void dispose() {
    _voiceAnimationController.dispose();
    _localLevelSub?.cancel();
    _beemoLevelSub?.cancel();
    _speakingSub?.cancel();
    unawaited(_audioService.dispose());
    super.dispose();
  }

  void _togglePause() async {
    final nextPaused = !_isPaused;

    await _audioService.setPaused(nextPaused);
    if (nextPaused) {
      await _audioService.setHandRaised(false);
    }

    if (!mounted) return;
    setState(() {
      _isPaused = nextPaused;
      if (nextPaused) {
        _currentAudioLevel = 0;
        _activeSpeakerId = null;
      }
    });
    if (nextPaused) {
      _voiceAnimationController.stop();
    } else {
      _voiceAnimationController.repeat(reverse: true);
    }
  }

  void _toggleRaiseHand() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final userId = authProvider.user?.uid;
    final houseId = houseProvider.currentHouseId;

    if (userId == null || houseId == null) return;

    setState(() => _handRaised = !_handRaised);
    await _audioService.setHandRaised(_handRaised);
  }

  @override
  Widget build(BuildContext context) {
    final houseId = Provider.of<HouseProvider>(context).currentHouseId;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFCF7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const SizedBox(height: 20),
              _buildAvatarSection(),
              const SizedBox(height: 24),
              _buildAgendaSection(houseId),
              const SizedBox(height: 24),
              _buildControlsRow(),
              const SizedBox(height: 24),
              Expanded(child: _buildParticipantsSection()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC400),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black, offset: Offset(4, 4)),
              ],
            ),
            child: const Icon(Icons.arrow_back, color: Colors.black, size: 28),
          ),
        ),
        const Spacer(),
        _buildTimerChip(),
      ],
    );
  }

  Widget _buildTimerChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _remainingSeconds < 60
            ? const Color(0xFFFF3B79)
            : const Color(0xFFFFEC5D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(2, 2)),
        ],
      ),
      child: Text(
        _timerDisplay,
        style: const TextStyle(
          fontFamily: 'Urbanist',
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 154,
          height: 154,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 154,
                height: 154,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B79),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black, offset: Offset(4, 4)),
                  ],
                ),
              ),
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF63BDA4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black, offset: Offset(4, 4)),
                  ],
                ),
                child: const Center(
                  child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildVoiceIndicator(),
      ],
    );
  }

  Widget _buildVoiceIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (index) {
        // Show wave animation based on Beemo's audio level (when > 0)
        // This ensures the wave moves throughout Beemo's entire speech
        final waveLevel = _beemoAudioLevel;
        final centerIndex = 3;
        final distanceFromCenter = (index - centerIndex).abs();
        final baseHeight = 4.0;
        final maxHeight = 20.0;
        final baseMultiplier = (1.0 - distanceFromCenter * 0.15).clamp(0.1, 1.0);
        final intensity = waveLevel.clamp(0.0, 1.0);
        final height = baseHeight + (maxHeight * baseMultiplier * intensity);
        final barWidth = 5 + (intensity * 3);

        final Color dynamicColor;
        if (_isPaused) {
          dynamicColor = Colors.grey.withOpacity(0.3);
        } else if (_beemoAudioLevel > 0) {
          // Beemo is speaking - show animated yellow/green wave
          dynamicColor = (Color.lerp(
                    const Color(0xFF63BDA4),
                    const Color(0xFFFFEC5D),
                    intensity,
                  ) ??
                  const Color(0xFFFFEC5D))
              .withOpacity(0.6 + (0.4 * intensity));
        } else {
          // No audio - show minimal green wave
          dynamicColor =
              const Color(0xFF63BDA4).withOpacity(0.3 + (0.4 * intensity));
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: barWidth,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: dynamicColor,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.black, width: 1),
          ),
        );
      }),
    );
  }

  Widget _buildAgendaSection(String? houseId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Agenda Items',
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            height: 1.17,
          ),
        ),
        const SizedBox(height: 12),
        if (houseId == null)
          const SizedBox()
        else
          StreamBuilder<List<AgendaItem>>(
            stream: _firestoreService.getAgendaItemsStream(houseId),
            builder: (context, snapshot) {
              final meetingItems = (snapshot.data ?? [])
                  .where((item) => item.priority == 'meeting')
                  .take(4)
                  .toList();
              return _buildAgendaSlots(meetingItems);
            },
          ),
      ],
    );
  }

  Widget _buildAgendaSlots(List<AgendaItem> items) {
    if (items.isEmpty) {
      return const SizedBox();
    }

    return Column(
      children: List.generate(items.length, (index) {
        final item = items[index];
        final isActive = index == _currentAgendaIndex;

        return Padding(
          padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 10),
          child: _buildAgendaCard(
            item: item,
            index: index,
            isActive: isActive,
          ),
        );
      }),
    );
  }

  Widget _buildAgendaCard({
    required AgendaItem item,
    required int index,
    required bool isActive,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFFEC5D) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black, width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFFF3B79) : const Color(0xFF63BDA4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 1.5),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  height: 1.83,
                  letterSpacing: -0.8,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.title,
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.black : const Color(0xFF414141),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsRow() {
    return Row(
      children: [
        Expanded(child: _buildPauseButton()),
        const SizedBox(width: 20),
        Expanded(child: _buildRaiseHandButton()),
      ],
    );
  }

  Widget _buildPauseButton() {
    final Color backgroundColor =
        _isPaused ? const Color(0xFFFF3B79) : Colors.white;
    final Color foregroundColor = _isPaused ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: _togglePause,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(5, 5)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 42,
              color: foregroundColor,
            ),
            const SizedBox(height: 10),
            Text(
              _isPaused ? 'Continue' : 'Pause',
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRaiseHandButton() {
    final Color backgroundColor =
        _handRaised ? const Color(0xFFFF3B79) : Colors.white;
    final Color foregroundColor = _handRaised ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: _toggleRaiseHand,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(5, 5)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.back_hand, size: 42, color: foregroundColor),
            const SizedBox(height: 10),
            Text(
              'Raise hand',
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantsSection() {
    return StreamBuilder<List<MeetingParticipantState>>(
      stream: _audioService.participantsStream,
      builder: (context, snapshot) {
        final participants = (snapshot.data ?? [])
            .where((participant) =>
                participant.userId != 'beemo_ai' && participant.isPresent)
            .toList();

        if (participants.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black26, width: 2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: const Center(
              child: Text(
                'Waiting for housemates to join…',
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF606060),
                ),
              ),
            ),
          );
        }

        final visibleParticipants = participants.take(4).toList();

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: visibleParticipants.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2.2,
          ),
          itemBuilder: (context, index) {
            final participant = visibleParticipants[index];
            final memberId = participant.userId;
            final avatarColor = participant.avatarColor != null
                ? Color(participant.avatarColor!)
                : _getAvatarColor(index);
            final displayName =
                memberId == _currentUserId ? 'You' : participant.displayName;
            final avatarEmoji = participant.avatarEmoji.isNotEmpty
                ? participant.avatarEmoji
                : '🙂';
            final isSpeaking =
                participant.isSpeaking || _activeSpeakerId == memberId;
            final isInQueue =
                participant.isInQueue || participant.handRaised;

            return _buildParticipantCard(
              memberId: memberId,
              displayName: displayName,
              avatarEmoji: avatarEmoji,
              avatarColor: avatarColor,
              handRaised: participant.handRaised,
              isSpeaking: isSpeaking,
              isInQueue: isInQueue,
              isPresent: participant.isPresent,
            );
          },
        );
      },
    );
  }

  Widget _buildParticipantCard({
    required String memberId,
    required String displayName,
    required String avatarEmoji,
    required Color avatarColor,
    required bool handRaised,
    required bool isSpeaking,
    required bool isInQueue,
    required bool isPresent,
  }) {
    final bool isSelf = memberId == _currentUserId;
    final Color borderColor =
        isSpeaking ? const Color(0xFFFF3B79) : Colors.black;
    final Color fillColor = isSpeaking
        ? const Color(0xFFFFEC5D)
        : (isPresent ? const Color(0xFFEFEFEF) : const Color(0xFFE4E4E4));

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black, offset: Offset(4, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: avatarColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          avatarEmoji,
                          style: const TextStyle(fontSize: 19),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isSpeaking
                                  ? Colors.black
                                  : const Color(0xFF414141),
                              height: 1.1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isSpeaking
                                ? (isSelf ? "You're speaking" : 'Speaking')
                                : (isInQueue ? 'In queue' : 'Listening'),
                            style: TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isSpeaking
                                  ? Colors.black
                                  : const Color(0xFF606060),
                              height: 1.05,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (handRaised)
              Positioned(
                top: -10,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: const Text(
                    '✋',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _getAvatarColor(int index) {
    const colors = [
      Color(0xFFFFC400),
      Color(0xFFFF3B79),
      Color(0xFF63BDA4),
      Color(0xFF16A3D0),
    ];
    return colors[index % colors.length];
  }
}
