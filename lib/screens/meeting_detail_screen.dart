import 'package:flutter/material.dart';
import 'agenda_screen.dart';

class MeetingDetailScreen extends StatelessWidget {
  const MeetingDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with back button and title
                    Row(
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
                          'Meeting notes',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Date
                    const Text(
                      'October 8th',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Participants and Duration
                    const Text(
                      'Participants: Priya, Rohan, Anika',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                    const Text(
                      'Duration: 10 minutes',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Agenda Topic Section
                    const Text(
                      'Agenda Topic',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Dishwasher Trouble',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Problems Identified Section
                    const Text(
                      'Problems Identified',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildBulletPoint(
                      'It is often unclear whether the dishes in the dishwasher are clean or dirty.',
                    ),
                    const SizedBox(height: 8),
                    _buildBulletPoint(
                      'This confusion leads to clean dishes not being unloaded and dirty dishes piling up in the sink.',
                    ),
                    const SizedBox(height: 8),
                    _buildBulletPoint(
                      'There is no clear system for who is responsible for unloading the dishwasher.',
                    ),
                    const SizedBox(height: 24),

                    // Decisions & New House Rules Section
                    const Text(
                      'Decisions & New House Rules',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildBulletPoint(
                      'Visual Indicator: A "Clean/Dirty" magnet will be placed on the dishwasher to clearly communicate its status to everyone.',
                    ),
                    const SizedBox(height: 8),
                    _buildBulletPoint(
                      'Shared Responsibility: Unloading the dishwasher is now a shared task. If the magnet says CLEAN, any roommate with a free moment is encouraged to help unload.',
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

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
                          Navigator.of(context).popUntil((route) => route.isFirst);
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
    );
  }

  Widget _buildBulletPoint(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7.0, right: 8.0),
          child: Icon(
            Icons.circle,
            size: 6,
            color: Colors.black87,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ),
      ],
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
