import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/colors.dart';
import '../providers/house_provider.dart';

class LabScreen extends StatelessWidget {
  const LabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final houseId = houseProvider.currentHouseId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
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
              final houseData = snapshot.data!.data() as Map<String, dynamic>?;
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
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: houseColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      houseEmoji,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(houseName),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Activity Cards Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.85,
                children: [
                  _buildActivityCard(
                    color: AppColors.pink,
                    icon: Icons.lightbulb,
                    title: 'Ideas',
                    subtitle: 'Capture insights',
                    count: '12',
                  ),
                  _buildActivityCard(
                    color: AppColors.cyan,
                    icon: Icons.task_alt,
                    title: 'Tasks',
                    subtitle: 'Get things done',
                    count: '8',
                  ),
                  _buildActivityCard(
                    color: AppColors.yellow,
                    icon: Icons.calendar_today,
                    title: 'Events',
                    subtitle: 'Plan ahead',
                    count: '5',
                  ),
                  _buildActivityCard(
                    color: AppColors.darkGray,
                    icon: Icons.folder,
                    title: 'Projects',
                    subtitle: 'Organize work',
                    count: '3',
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Recent Activity Section
              Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),

              // Timeline/Activity List
              _buildActivityItem(
                icon: Icons.lightbulb,
                color: AppColors.pink,
                title: 'New idea added',
                time: '2 hours ago',
              ),
              const SizedBox(height: 12),
              _buildActivityItem(
                icon: Icons.task_alt,
                color: AppColors.cyan,
                title: 'Task completed',
                time: '4 hours ago',
              ),
              const SizedBox(height: 12),
              _buildActivityItem(
                icon: Icons.calendar_today,
                color: AppColors.yellow,
                title: 'Event scheduled',
                time: 'Yesterday',
              ),
              const SizedBox(height: 12),
              _buildActivityItem(
                icon: Icons.folder,
                color: AppColors.darkGray,
                title: 'Project updated',
                time: '2 days ago',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityCard({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required String count,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            count,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityItem({
    required IconData icon,
    required Color color,
    required String title,
    required String time,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: AppColors.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }
}
