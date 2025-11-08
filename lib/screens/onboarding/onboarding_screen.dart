import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../constants/colors.dart';
import '../../widgets/beemo_logo.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Welcome to\nBeemo!',
      subtitle: 'Your AI-powered household\ncoordination assistant',
      emoji: '🤖',
      backgroundColor: AppColors.yellow,
      description: 'Beemo helps you manage tasks, meetings, and household coordination with smart AI assistance—including automated weekly meeting check-ins.',
      showBeemoCharacter: true,
    ),
    OnboardingPage(
      title: 'Chat with\nBeemo',
      subtitle: 'Get intelligent help for\nyour household',
      emoji: '💬',
      backgroundColor: AppColors.cyan,
      description: 'Ask Beemo anything! It automatically detects tasks, creates agendas, and helps coordinate with housemates.',
      features: [
        'AI-powered task detection',
        'Smart polls and scheduling',
        'Group chat with everyone',
      ],
    ),
    OnboardingPage(
      title: 'Manage\nTasks',
      subtitle: 'Track and complete tasks\ntogether',
      emoji: '✅',
      backgroundColor: AppColors.pink,
      description: 'Assign tasks, set deadlines, and track progress. Beemo helps ensure nothing falls through the cracks.',
      features: [
        'Auto-assigned from chat',
        'Easy confirmation system',
        'Points and rewards',
      ],
    ),
    OnboardingPage(
      title: 'Share what’s\non your mind',
      subtitle: '',
      emoji: '🗒️',
      backgroundColor: AppColors.pink,
      description:
          'Each week, add one topic you’d like to talk about—a small concern, idea, or task. Beemo helps turn these into calm, fair discussions.',
    ),
    OnboardingPage(
      title: 'Earn &\nDecorate',
      subtitle: '',
      emoji: '🏡',
      backgroundColor: AppColors.pink,
      description:
          'Good habits unlock fun decorations for your virtual house. It’s for teamwork, not competition.',
      isLastPage: true,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _completeOnboarding() async {
    // Mark onboarding as complete in Firestore
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.uid;

    if (userId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({'hasCompletedOnboarding': true});
        // StreamBuilder in AuthWrapper will automatically switch to DashScreen
      } catch (e) {
        print('Error saving onboarding status: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // PageView
            PageView.builder(
              controller: _pageController,
              onPageChanged: (int page) {
                setState(() {
                  _currentPage = page;
                });
              },
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                return _buildPage(_pages[index]);
              },
            ),

            // Top Skip button
            Positioned(
              top: 20,
              right: 20,
              child: GestureDetector(
                onTap: _completeOnboarding,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(color: Colors.black, width: 2.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            // Bottom navigation
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  // Page Indicator
                  _buildPageIndicator(),
                  const SizedBox(height: 32),

                  // Navigation Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back Button
                      if (_currentPage > 0)
                        _buildNeobrutalistButton(
                          text: 'Back',
                          backgroundColor: Colors.white,
                          textColor: Colors.black,
                          onTap: _previousPage,
                          width: 100,
                        )
                      else
                        const SizedBox(width: 100),

                      // Next/Get Started Button
                      _buildNeobrutalistButton(
                        text: _currentPage == _pages.length - 1
                            ? 'Finish'
                            : 'Next',
                        backgroundColor: _pages[_currentPage].backgroundColor,
                        textColor: Colors.white,
                        onTap: _nextPage,
                        width: _currentPage == _pages.length - 1 ? 200 : 120,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 60),

          // Emoji/Icon in neobrutalist container
          Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6, right: 6),
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: page.backgroundColor,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.black, width: 3),
              ),
              child: Center(
                child: page.emoji == '🤖'
                    ? const BeemoLogo(size: 50)
                    : Text(
                        page.emoji,
                        style: const TextStyle(fontSize: 50),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Title
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              height: 1.0,
              color: Colors.black,
              letterSpacing: -1,
            ),
          ),

          const SizedBox(height: 16),

          // Subtitle
          Text(
            page.subtitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 32),

          // Description
          Text(
            page.description,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black54,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 24),

          // Features list (if present)
          if (page.features != null && page.features!.isNotEmpty)
            ...page.features!.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: page.backgroundColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _pages.length,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == index ? 32 : 12,
          height: 12,
          decoration: BoxDecoration(
            color: _currentPage == index
                ? _pages[_currentPage].backgroundColor
                : Colors.black26,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }

  Widget _buildNeobrutalistButton({
    required String text,
    required Color backgroundColor,
    required Color textColor,
    required VoidCallback onTap,
    required double width,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 5, right: 5),
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingPage {
  final String title;
  final String subtitle;
  final String emoji;
  final Color backgroundColor;
  final String description;
  final List<String>? features;
  final bool showBeemoCharacter;
  final bool isLastPage;

  OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.backgroundColor,
    required this.description,
    this.features,
    this.showBeemoCharacter = false,
    this.isLastPage = false,
  });
}
