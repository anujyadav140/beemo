import 'package:flutter/material.dart';
import '../constants/colors.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Help and Support'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quick Actions
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildQuickAction(
                      icon: Icons.email_outlined,
                      title: 'Contact Support',
                      subtitle: 'Get help from our team',
                      color: AppColors.pink,
                      onTap: () {},
                    ),
                    const SizedBox(height: 16),
                    _buildQuickAction(
                      icon: Icons.chat_bubble_outline,
                      title: 'Live Chat',
                      subtitle: 'Chat with us now',
                      color: AppColors.cyan,
                      onTap: () {},
                    ),
                    const SizedBox(height: 16),
                    _buildQuickAction(
                      icon: Icons.bug_report_outlined,
                      title: 'Report a Bug',
                      subtitle: 'Help us improve',
                      color: AppColors.orange,
                      onTap: () {},
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // FAQ Section
              Text(
                'Frequently Asked Questions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              _buildFAQItem(
                question: 'How do I create a new task?',
                answer: 'Tap the + button on The Lab screen and select "New Task". Fill in the details and tap Save.',
              ),
              const SizedBox(height: 12),
              _buildFAQItem(
                question: 'How does the Focus Timer work?',
                answer: 'The Focus Timer uses the Pomodoro Technique. Work for 25 minutes, then take a 5-minute break. After 4 sessions, take a longer 15-minute break.',
              ),
              const SizedBox(height: 12),
              _buildFAQItem(
                question: 'Can I sync my data across devices?',
                answer: 'Yes! Sign in with your account to automatically sync all your data across all your devices.',
              ),
              const SizedBox(height: 12),
              _buildFAQItem(
                question: 'How do I change the app theme?',
                answer: 'Go to Account > Appearance to customize your theme, colors, and display preferences.',
              ),
              const SizedBox(height: 12),
              _buildFAQItem(
                question: 'What are the different agenda categories?',
                answer: 'You can create custom categories for your agenda items. Each category can have its own color and icon for easy identification.',
              ),

              const SizedBox(height: 24),

              // Resources Section
              Text(
                'Resources',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildResourceItem(
                      icon: Icons.menu_book,
                      title: 'User Guide',
                      color: AppColors.purple,
                    ),
                    const Divider(height: 32),
                    _buildResourceItem(
                      icon: Icons.video_library,
                      title: 'Video Tutorials',
                      color: AppColors.cyan,
                    ),
                    const Divider(height: 32),
                    _buildResourceItem(
                      icon: Icons.article,
                      title: 'Documentation',
                      color: AppColors.yellow,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAQItem({
    required String question,
    required String answer,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            question,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          children: [
            Text(
              answer,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceItem({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: AppColors.textSecondary,
        ),
      ],
    );
  }
}
