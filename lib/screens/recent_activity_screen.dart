import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/activity_model.dart';

class RecentActivityScreen extends StatefulWidget {
  const RecentActivityScreen({super.key});

  @override
  State<RecentActivityScreen> createState() => _RecentActivityScreenState();
}

class _RecentActivityScreenState extends State<RecentActivityScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final activityDate = DateTime(date.year, date.month, date.day);

    if (activityDate == today) {
      return 'Today';
    } else if (activityDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('d MMMM').format(date);
    }
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'task_completed':
        return Colors.black;
      case 'task_created':
        return const Color(0xFFFF4D8D);
      case 'agenda_created':
        return const Color(0xFF63BDA4);
      case 'message':
        return const Color(0xFF16A3D0);
      default:
        return const Color(0xFF4A4A4A);
    }
  }

  Widget _getActivityBadge(Activity activity) {
    switch (activity.type) {
      case 'task_completed':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: const Text(
            'Completed',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        );
      case 'task_created':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF4D8D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: const Text(
            'Confirm',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        );
      case 'message':
      case 'agenda_created':
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF16A3D0),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: const Center(
            child: Text(
              '💬',
              style: TextStyle(fontSize: 20),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 100.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
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
                        'Recent Activity',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Activities Stream
                  if (houseProvider.currentHouseId == null)
                    const Center(
                      child: Text(
                        'Please create or join a house first',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                      ),
                    )
                  else
                    StreamBuilder<List<Activity>>(
                      stream: _firestoreService.getActivitiesStream(houseProvider.currentHouseId!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFFC400),
                            ),
                          );
                        }

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text(
                              'No recent activity',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                          );
                        }

                        // Group activities by date
                        Map<String, List<Activity>> groupedActivities = {};
                        for (var activity in snapshot.data!) {
                          String dateHeader = _formatDateHeader(activity.createdAt);
                          if (!groupedActivities.containsKey(dateHeader)) {
                            groupedActivities[dateHeader] = [];
                          }
                          groupedActivities[dateHeader]!.add(activity);
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: groupedActivities.entries.map((entry) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Date header
                                Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Activities for this date
                                ...entry.value.map((activity) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _ActivityCard(
                                      activity: activity,
                                      badge: _getActivityBadge(activity),
                                    ),
                                  );
                                }).toList(),

                                const SizedBox(height: 20),
                              ],
                            );
                          }).toList(),
                        );
                      },
                    ),
                ],
              ),
            ),

            // Floating Bottom Navigation
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
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
                        child: _buildBeemoNavIcon(false),
                      ),
                      const SizedBox(width: 28),
                      _buildNavIcon(Icons.history, true),
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

class _ActivityCard extends StatefulWidget {
  final Activity activity;
  final Widget badge;

  const _ActivityCard({
    required this.activity,
    required this.badge,
  });

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _isPressed = true;
        });
      },
      onTapUp: (_) {
        setState(() {
          _isPressed = false;
        });
        // TODO: Navigate to detail page or perform action
      },
      onTapCancel: () {
        setState(() {
          _isPressed = false;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 5,
            right: _isPressed ? 0 : 5,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.activity.description,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                widget.badge,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
