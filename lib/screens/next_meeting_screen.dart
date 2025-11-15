import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/beemo_logo.dart';
import '../widgets/coin_display.dart';
import 'agenda_screen.dart';
import 'setup_house_screen.dart';

class NextMeetingScreen extends StatefulWidget {
  const NextMeetingScreen({super.key});

  @override
  State<NextMeetingScreen> createState() => _NextMeetingScreenState();
}

class _NextMeetingScreenState extends State<NextMeetingScreen> {
  Timer? _timer;
  Duration _timeRemaining = Duration.zero;
  DateTime? _scheduledTime;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_scheduledTime != null) {
          final diff = _scheduledTime!.difference(DateTime.now());
          _timeRemaining = diff.isNegative ? Duration.zero : diff;
        } else {
          _timeRemaining = Duration.zero;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final houseId = houseProvider.currentHouseId;

    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours % 24;
    final minutes = _timeRemaining.inMinutes % 60;
    final seconds = _timeRemaining.inSeconds % 60;

    return Scaffold(
      body: Stack(
        children: [
          // Background - Full screen landscape image
          Positioned.fill(
            child: Image.network(
              'https://images.unsplash.com/photo-1500382017468-9049fed747ef?w=800',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: const Color(0xFF7CB342));
              },
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      StreamBuilder<DocumentSnapshot>(
                        stream: houseId != null
                            ? FirebaseFirestore.instance
                                  .collection('houses')
                                  .doc(houseId)
                                  .snapshots()
                            : null,
                        builder: (context, snapshot) {
                          String houseName = 'House';
                          String houseEmoji = '🏠';
                          Color houseColor = const Color(0xFF00BCD4);

                          if (snapshot.hasData && snapshot.data != null) {
                            final houseData =
                                snapshot.data!.data() as Map<String, dynamic>?;
                            houseName = houseData?['houseName'] ?? 'House';
                            houseEmoji = houseData?['houseEmoji'] ?? '🏠';
                            final houseColorInt = houseData?['houseColor'];
                            if (houseColorInt != null) {
                              houseColor = Color(houseColorInt);
                            }
                          }

                          return Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: houseColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black,
                                    width: 2.5,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    houseEmoji,
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                houseName,
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      Consumer2<HouseProvider, AuthProvider>(
                        builder: (context, houseProvider, authProvider, _) {
                          final userId = authProvider.user?.uid;
                          final houseId = houseProvider.currentHouseId;

                          if (userId == null || houseId == null) {
                            return const CoinDisplay(
                              points: 0,
                              fontSize: 18,
                              coinSize: 22,
                              fontWeight: FontWeight.bold,
                              showBorder: true,
                            );
                          }

                          return CoinDisplay(
                            userId: userId,
                            houseId: houseId,
                            fontSize: 18,
                            coinSize: 22,
                            fontWeight: FontWeight.bold,
                            showBorder: true,
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Back button and title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC400),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2.5),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.black,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Next Meeting in...',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                StreamBuilder<DocumentSnapshot>(
                  stream: houseId != null
                      ? FirebaseFirestore.instance
                            .collection('nextMeetings')
                            .doc(houseId)
                            .snapshots()
                      : null,
                  builder: (context, snapshot) {
                    DateTime? meetingTime;

                    if (snapshot.hasData &&
                        snapshot.data != null &&
                        snapshot.data!.exists) {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      final ts = data?['scheduledTime'] as Timestamp?;
                      if (ts != null) {
                        meetingTime = ts.toDate();
                      }
                    }

                    if (meetingTime != _scheduledTime) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _scheduledTime = meetingTime;
                          if (meetingTime != null) {
                            final diff = meetingTime.difference(DateTime.now());
                            _timeRemaining = diff.isNegative
                                ? Duration.zero
                                : diff;
                          } else {
                            _timeRemaining = Duration.zero;
                          }
                        });
                      });
                    }

                    final hasMeeting = meetingTime != null;
                    final scheduleLabel = hasMeeting
                        ? DateFormat(
                            'EEEE, MMM d • h:mm a',
                          ).format(meetingTime!.toLocal())
                        : 'No weekly check-in is on the calendar yet.';
                    final helperText = hasMeeting
                        ? 'Recurring check-in coordinated with Beemo.'
                        : 'Open the Beemo chat to pick a time that works for everyone.';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                scheduleLabel,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                helperText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (hasMeeting)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildCountdownBox(
                                  days.toString().padLeft(2, '0'),
                                  'Days',
                                ),
                                _buildCountdownBox(
                                  hours.toString().padLeft(2, '0'),
                                  'Hours',
                                ),
                                _buildCountdownBox(
                                  minutes.toString().padLeft(2, '0'),
                                  'Minutes',
                                ),
                                _buildCountdownBox(
                                  seconds.toString().padLeft(2, '0'),
                                  'Seconds',
                                ),
                              ],
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 1.5,
                                ),
                              ),
                              child: const Text(
                                'No countdown yet—ask Beemo in the group chat to schedule your next weekly check-in.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),

                const Spacer(),

                // Bottom Navigation
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0, top: 8.0),
                  child: Center(
                    child: SizedBox(
                      height: 78,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16213E),
                          borderRadius: BorderRadius.circular(34),
                        ),
                        clipBehavior: Clip.none,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const SetupHouseScreen(),
                                  ),
                                );
                              },
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: const BoxDecoration(
                                  color: Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4.0),
                                    child: SvgPicture.asset(
                                      'assets/images/cube.svg',
                                      width: 42,
                                      height: 42,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () {
                                Navigator.of(
                                  context,
                                ).popUntil((route) => route.isFirst);
                              },
                              child: _buildBeemoNavIcon(true),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AgendaScreen(),
                                  ),
                                );
                              },
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: const BoxDecoration(
                                  color: Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4.0),
                                    child: SvgPicture.asset(
                                      'assets/images/note.svg',
                                      width: 42,
                                      height: 42,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownBox(String value, String label) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 5, right: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF4D8D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 2.5),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, bool isActive) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFF1B8D) : Colors.transparent,
        shape: BoxShape.circle,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        color: isActive ? Colors.white : Colors.white60,
        size: 36,
      ),
    );
  }

  Widget _buildBeemoNavIcon(bool isActive) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFF1B8D) : Colors.transparent,
        shape: BoxShape.circle,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Center(child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
      ),),
    );
  }
}
