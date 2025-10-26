import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../constants/colors.dart';

class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({super.key});

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen> {
  final TextEditingController _nameController = TextEditingController();
  String? _selectedPronouns;
  bool _isLoading = false;

  final List<String> _pronounOptions = [
    'he/him',
    'she/her',
    'they/them',
    'he/they',
    'she/they',
    'other',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.uid;

    if (userId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
          'profile.name': name,
          'profile.pronouns': _selectedPronouns ?? '',
          'hasCompletedGetStarted': true,
        });
        // AuthWrapper's StreamBuilder will automatically detect this change
      } catch (e) {
        print('Error saving user info: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving information: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0), // Off-white background
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),

                    // Curved line decoration at top (simplified)
                    Align(
                      alignment: Alignment.topRight,
                      child: CustomPaint(
                        size: const Size(100, 60),
                        painter: TopCurvesPainter(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'Great let\'s get\nstarted!',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        color: Colors.black,
                        height: 1.1,
                      ),
                    ),

                    const SizedBox(height: 60),

                    // Name input
                    const Text(
                      'What should we call you?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      controller: _nameController,
                      placeholder: 'Name',
                    ),

                    const SizedBox(height: 32),

                    // Pronouns dropdown
                    const Text(
                      'What are your pronouns?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildPronounsDropdown(),

                    const SizedBox(height: 120), // Space for bottom button
                  ],
                ),
              ),
            ),

            // Bottom Next button
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator(
                        color: Color(0xFFFFC400),
                      )
                    : GestureDetector(
                        onTap: _saveAndContinue,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 5, right: 5),
                            width: 160,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC400), // Yellow
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.black, width: 3),
                            ),
                            child: const Center(
                              child: Text(
                                'Next',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String placeholder,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2.5),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Colors.grey[400],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    setState(() {
                      controller.clear();
                    });
                  },
                  child: const Icon(
                    Icons.close,
                    color: Colors.black,
                    size: 20,
                  ),
                )
              : null,
        ),
        onChanged: (value) {
          setState(() {}); // Rebuild to show/hide X button
        },
      ),
    );
  }

  Widget _buildPronounsDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPronouns,
          hint: Text(
            'Select pronouns',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Colors.grey[400],
            ),
          ),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
          items: _pronounOptions.map((String pronoun) {
            return DropdownMenuItem<String>(
              value: pronoun,
              child: Text(pronoun),
            );
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _selectedPronouns = newValue;
            });
          },
        ),
      ),
    );
  }
}

// Custom painter for the top curved lines
class TopCurvesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path1 = Path();
    path1.moveTo(0, size.height * 0.3);
    path1.quadraticBezierTo(
      size.width * 0.3,
      0,
      size.width * 0.7,
      size.height * 0.4,
    );
    path1.quadraticBezierTo(
      size.width * 0.85,
      size.height * 0.6,
      size.width,
      size.height * 0.5,
    );

    final path2 = Path();
    path2.moveTo(size.width * 0.2, size.height * 0.7);
    path2.quadraticBezierTo(
      size.width * 0.4,
      size.height * 0.4,
      size.width * 0.7,
      size.height * 0.8,
    );
    path2.quadraticBezierTo(
      size.width * 0.85,
      size.height,
      size.width,
      size.height * 0.9,
    );

    canvas.drawPath(path1, paint);
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
