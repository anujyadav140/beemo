import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';

class AvatarSelectionScreen extends StatefulWidget {
  const AvatarSelectionScreen({super.key});

  @override
  State<AvatarSelectionScreen> createState() => _AvatarSelectionScreenState();
}

class _AvatarSelectionScreenState extends State<AvatarSelectionScreen> {
  int? _selectedAvatarIndex;
  bool _isLoading = false;

  // Avatar data: emoji, backgroundColor
  final List<AvatarOption> _avatars = [
    // Row 1 - Pink avatars
    AvatarOption(emoji: '✨', backgroundColor: const Color(0xFFE91E63), name: 'sparkle'),
    AvatarOption(emoji: '💊', backgroundColor: const Color(0xFFE91E63), name: 'pill'),

    // Row 2 - Yellow avatars
    AvatarOption(emoji: '🐝', backgroundColor: const Color(0xFFFFC400), name: 'bee'),
    AvatarOption(emoji: '📦', backgroundColor: const Color(0xFFFFC400), name: 'box'),

    // Row 3 - Cyan avatars
    AvatarOption(emoji: '👨‍🚀', backgroundColor: const Color(0xFF00BCD4), name: 'astronaut'),
    AvatarOption(emoji: '🚀', backgroundColor: const Color(0xFF00BCD4), name: 'rocket'),

    // Row 4 - Green avatars
    AvatarOption(emoji: '🐸', backgroundColor: const Color(0xFF4CAF50), name: 'frog'),
    AvatarOption(emoji: '🤖', backgroundColor: const Color(0xFF4CAF50), name: 'robot'),
  ];

  Future<void> _saveAndContinue() async {
    if (_selectedAvatarIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an avatar'),
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
        final selectedAvatar = _avatars[_selectedAvatarIndex!];
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
          'profile.avatar': selectedAvatar.name,
          'profile.avatarEmoji': selectedAvatar.emoji,
          'profile.avatarColor': selectedAvatar.backgroundColor.value,
          'hasCompletedAvatarSelection': true,
        });
        // AuthWrapper's StreamBuilder will automatically detect this change
      } catch (e) {
        print('Error saving avatar: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving avatar: $e'),
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),

              // Title
              const Text(
                'Choose your Avatar',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: Colors.black,
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle
              const Text(
                'you can change this later anytime you like.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.black54,
                ),
              ),

              const SizedBox(height: 40),

              // Avatar Grid
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 24,
                    childAspectRatio: 1,
                  ),
                  itemCount: _avatars.length,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemBuilder: (context, index) {
                    return _buildAvatarOption(index);
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Next Button
              _isLoading
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

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarOption(int index) {
    final avatar = _avatars[index];
    final isSelected = _selectedAvatarIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAvatarIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black,
            width: isSelected ? 4 : 3,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    offset: const Offset(0, 4),
                    blurRadius: 8,
                  ),
                ]
              : [],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatar.backgroundColor,
          ),
          child: Center(
            child: Text(
              avatar.emoji,
              style: const TextStyle(
                fontSize: 50,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AvatarOption {
  final String emoji;
  final Color backgroundColor;
  final String name;

  AvatarOption({
    required this.emoji,
    required this.backgroundColor,
    required this.name,
  });
}
