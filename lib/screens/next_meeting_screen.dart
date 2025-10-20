import 'package:flutter/material.dart';
import 'dart:async';
import 'agenda_screen.dart';
import 'setup_house_screen.dart';

class NextMeetingScreen extends StatefulWidget {
  const NextMeetingScreen({super.key});

  @override
  State<NextMeetingScreen> createState() => _NextMeetingScreenState();
}

class _NextMeetingScreenState extends State<NextMeetingScreen> {
  Timer? _timer;
  Duration _timeRemaining = const Duration(days: 3, hours: 20, minutes: 12, seconds: 28);

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
      if (mounted) {
        setState(() {
          if (_timeRemaining.inSeconds > 0) {
            _timeRemaining = _timeRemaining - const Duration(seconds: 1);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                return Container(
                  color: const Color(0xFF7CB342),
                );
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
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2.5),
                            ),
                            child: ClipOval(
                              child: Container(
                                color: Colors.grey[800],
                                child: const Icon(
                                  Icons.public,
                                  color: Colors.white70,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'The Lab',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC400),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '500',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: Colors.orange[800],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF9500),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.orange[900],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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

                const SizedBox(height: 32),

                // Countdown boxes
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildCountdownBox(days.toString().padLeft(2, '0'), 'Days'),
                      _buildCountdownBox(hours.toString().padLeft(2, '0'), 'Hours'),
                      _buildCountdownBox(minutes.toString().padLeft(2, '0'), 'Minutes'),
                      _buildCountdownBox(seconds.toString().padLeft(2, '0'), 'Seconds'),
                    ],
                  ),
                ),

                const Spacer(),

                // Bottom Navigation
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0, top: 8.0),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16213E),
                        borderRadius: BorderRadius.circular(34),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SetupHouseScreen(),
                                ),
                              );
                            },
                            child: _buildNavIcon(Icons.view_in_ar_rounded, false),
                          ),
                          const SizedBox(width: 28),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            },
                            child: _buildBeemoNavIcon(true),
                          ),
                          const SizedBox(width: 28),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AgendaScreen(),
                                ),
                              );
                            },
                            child: _buildNavIcon(Icons.event_note_rounded, false),
                          ),
                        ],
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
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFF4D8D) : Colors.transparent,
        shape: BoxShape.circle,
        border: isActive ? Border.all(color: Colors.black, width: 2.5) : null,
      ),
      child: Icon(
        icon,
        color: isActive ? Colors.white : Colors.white60,
        size: 26,
      ),
    );
  }

  Widget _buildBeemoNavIcon(bool isActive) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFF4D8D) : Colors.transparent,
        shape: BoxShape.circle,
        border: isActive ? Border.all(color: Colors.black, width: 2.5) : null,
      ),
      child: Center(
        child: Text(
          '🤖',
          style: TextStyle(
            fontSize: isActive ? 24 : 20,
          ),
        ),
      ),
    );
  }
}
