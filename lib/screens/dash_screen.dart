import 'package:flutter/material.dart';
import 'meeting_notes_screen.dart';
import 'tasks_screen.dart';
import 'agenda_screen.dart';
import 'timer_screen.dart';
import 'chat_screen.dart';
import 'next_meeting_screen.dart';
import 'setup_house_screen.dart';
import 'recent_activity_screen.dart';

class DashScreen extends StatefulWidget {
  const DashScreen({super.key});

  @override
  State<DashScreen> createState() => _DashScreenState();
}

class _DashScreenState extends State<DashScreen> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    // Header
                    Row(
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
                    const SizedBox(height: 4),

                    // Agenda goal
                    const Center(
                      child: Text(
                        'Agenda items goal: 3/4',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Cards Custom Layout
                    SizedBox(
                      height: 222,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column
                          Expanded(
                            child: Column(
                              children: [
                                // Meeting Notes (small)
                                SizedBox(
                                  height: 60,
                                  child: _buildMeetingNotesCard(),
                                ),
                                const SizedBox(height: 12),
                                // Recent Activity (tall)
                                SizedBox(
                                  height: 150,
                                  child: _buildRecentActivityCard(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Right Column
                          Expanded(
                            child: Column(
                              children: [
                                // Tasks (tall)
                                SizedBox(
                                  height: 100,
                                  child: _buildTasksCard(),
                                ),
                                const SizedBox(height: 12),
                                // Next Meeting (short)
                                SizedBox(
                                  height: 110,
                                  child: _buildNextMeetingCard(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Group Chat Section
                    const Text(
                      'Group chat with beemo',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Chat Container with Neobrutalist Border
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ChatScreen(),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 5, right: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16213E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: Stack(
                          children: [
                            // Background cloud image on the right
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(17),
                                  bottomRight: Radius.circular(17),
                                ),
                                child: Container(
                                  width: 120,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF16213E),
                                        Color(0xFF334155),
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                  ),
                                  child: Opacity(
                                    opacity: 0.4,
                                    child: Image.network(
                                      'https://images.unsplash.com/photo-1534088568595-a066f410bcda?w=400',
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(color: Colors.transparent);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Content
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Profile Avatars (stacked horizontally)
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 110,
                                        height: 28,
                                        child: Stack(
                                          children: [
                                            _buildStackedAvatar('A', const Color(0xFFFF4D6D), 0),
                                            _buildStackedAvatar('B', const Color(0xFF4D9FFF), 20),
                                            _buildStackedAvatar('C', const Color(0xFF4DFF88), 40),
                                            _buildStackedAvatar('L', const Color(0xFFFFEB3B), 60),
                                            Positioned(
                                              left: 80,
                                              child: Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFFC400),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.black, width: 2),
                                                ),
                                                child: const Center(
                                                  child: Text(
                                                    '🤖',
                                                    style: TextStyle(fontSize: 13),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Beemo Message with icon outside
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Beemo Icon (outside bubble)
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFC400),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.black, width: 2),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            '🤖',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Chat Bubble
                                      Container(
                                        width: MediaQuery.of(context).size.width * 0.48,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Beemo',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            const Text(
                                              "let's poll",
                                              style: TextStyle(fontSize: 12),
                                            ),
                                            const SizedBox(height: 6),
                                            _buildPollOption('Friday : 9 am'),
                                            _buildPollOption('Friday : 10 am'),
                                            _buildPollOption('Friday : 11 am'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Chat Messages with Neobrutalist Borders
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildNeobrutalistChatBubble(
                                          "I've completed can\nsomeone confirm.",
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _buildNeobrutalistChatBubble(
                                          "Can we change time\nfor our next meeting?",
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Input Field
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            '|',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.black45,
                                            ),
                                          ),
                                        ),
                                        const Icon(Icons.mic, size: 20, color: Colors.black87),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFFC400),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.send,
                                            size: 16,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ),
                  ],
                ),
              ),
            ),
          // Bottom Navigation (always visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0, top: 4.0),
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
                    _buildBeemoNavIcon(true),
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
    );
  }

  Widget _buildMeetingNotesCard() {
    return _AnimatedMeetingNotesCard();
  }

  Widget _buildTasksCard() {
    return _AnimatedTasksCard();
  }

  Widget _buildRecentActivityCard() {
    return _AnimatedRecentActivityCard();
  }

  Widget _buildNextMeetingCard() {
    return _AnimatedNextMeetingCard();
  }

  Widget _buildAvatar(String letter, Color color) {
    return Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPollOption(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          height: 1.3,
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

  Widget _buildStackedAvatar(String letter, Color color, double leftPosition) {
    return Positioned(
      left: leftPosition,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Center(
          child: Text(
            letter,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNeobrutalistChatBubble(String text) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2, right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

// Animated Card Widgets
class _AnimatedMeetingNotesCard extends StatefulWidget {
  @override
  State<_AnimatedMeetingNotesCard> createState() => _AnimatedMeetingNotesCardState();
}

class _AnimatedMeetingNotesCardState extends State<_AnimatedMeetingNotesCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MeetingNotesScreen()),
          );
        }
        if (mounted) {
          setState(() => _isPressed = false);
        }
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 6,
            right: _isPressed ? 0 : 6,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFC400),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: const Align(
            alignment: Alignment.topLeft,
            child: Text(
              'Meeting Notes',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedTasksCard extends StatefulWidget {
  @override
  State<_AnimatedTasksCard> createState() => _AnimatedTasksCardState();
}

class _AnimatedTasksCardState extends State<_AnimatedTasksCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TasksScreen()),
          );
        }
        if (mounted) {
          setState(() => _isPressed = false);
        }
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 6,
            right: _isPressed ? 0 : 6,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF00BFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tasks',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              Text(
                'Clean carpet before sunday',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedRecentActivityCard extends StatefulWidget {
  @override
  State<_AnimatedRecentActivityCard> createState() => _AnimatedRecentActivityCardState();
}

class _AnimatedRecentActivityCardState extends State<_AnimatedRecentActivityCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RecentActivityScreen()),
          );
        }
        if (mounted) {
          setState(() => _isPressed = false);
        }
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 6,
            right: _isPressed ? 0 : 6,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFF4D8D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF1744),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Ria finished with her task',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: const Text(
                        'Confirm',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedNextMeetingCard extends StatefulWidget {
  @override
  State<_AnimatedNextMeetingCard> createState() => _AnimatedNextMeetingCardState();
}

class _AnimatedNextMeetingCardState extends State<_AnimatedNextMeetingCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NextMeetingScreen()),
          );
        }
        if (mounted) {
          setState(() => _isPressed = false);
        }
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 6,
            right: _isPressed ? 0 : 6,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Next Meeting',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  height: 1.0,
                ),
              ),
              Text(
                'Oct 8',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 0.95,
                ),
              ),
              Text(
                '1:00 pm',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
