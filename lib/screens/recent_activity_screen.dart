import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/activity_model.dart';
import '../widgets/beemo_logo.dart';

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

  Widget _getActivityBadge(Activity activity, String? currentUserId) {
    switch (activity.type) {
      case 'task_completed':
        // Task completion needs confirmation from others
        // Check if already confirmed by checking metadata
        final isConfirmed = activity.metadata['confirmed'] == true;

        if (isConfirmed) {
          // Task already confirmed - show "Confirmed" state
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: const Text(
              'Confirmed',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          );
        }

        // Not confirmed yet - check if current user can confirm
        final completedBy = activity.metadata['completedBy']?.toString();
        final isMyTask =
            currentUserId != null &&
            completedBy != null &&
            completedBy.isNotEmpty &&
            completedBy == currentUserId;
        final canConfirm =
            currentUserId != null &&
            completedBy != null &&
            completedBy.isNotEmpty &&
            completedBy != currentUserId;

        String buttonText;
        Color buttonColor;
        if (isMyTask) {
          buttonText = 'Awaiting review';
          buttonColor = const Color(0xFF16A3D0);
        } else if (canConfirm) {
          buttonText = 'Confirm';
          buttonColor = const Color(0xFFFF4D8D);
        } else {
          buttonText = 'Confirmed';
          buttonColor = Colors.black;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Text(
            buttonText,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        );
      case 'task_created':
        // Task assignment - show Beemo icon if assigned by AI, otherwise show assignment icon
        final isAIAssignment =
            activity.title.contains('(AI)') ||
            activity.description.contains('Beemo') ||
            activity.createdBy == 'ai_agent';
        if (isAIAssignment) {
          // Beemo icon for AI assignments
          return Container(
            width: 56,
            height: 56,
            child: Center(
              child: BeemoLogo(size: 42),
            ),
          );
        } else {
          // Regular assignment icon
          return Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF63BDA4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: const Center(
              child: Icon(
                Icons.assignment_turned_in,
                color: Colors.white,
                size: 20,
              ),
            ),
          );
        }
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
            child: Text('💬', style: TextStyle(fontSize: 20)),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.uid;

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
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    )
                  else
                    StreamBuilder<List<Activity>>(
                      stream: _firestoreService.getActivitiesStream(
                        houseProvider.currentHouseId!,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
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
                          String dateHeader = _formatDateHeader(
                            activity.createdAt,
                          );
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
                                      badge: _getActivityBadge(
                                        activity,
                                        currentUserId,
                                      ),
                                      currentUserId: currentUserId,
                                      firestoreService: _firestoreService,
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
                            Navigator.of(
                              context,
                            ).popUntil((route) => route.isFirst);
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
                        Container(
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
                      ],
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
      child: Center(child: BeemoLogo(size: 36)),
    );
  }
}

class _ActivityCard extends StatefulWidget {
  final Activity activity;
  final Widget badge;
  final String? currentUserId;
  final FirestoreService firestoreService;

  const _ActivityCard({
    required this.activity,
    required this.badge,
    this.currentUserId,
    required this.firestoreService,
  });

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  bool _isPressed = false;

  Future<void> _handleConfirmTap() async {
    // Check if this is a task completion activity
    if (widget.activity.type != 'task_completed') {
      return;
    }

    final taskId = widget.activity.metadata['taskId']?.toString();
    final completedBy = widget.activity.metadata['completedBy']?.toString();

    if (taskId == null || taskId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task ID not found')));
      return;
    }

    // Prevent self-confirmation
    if (widget.currentUserId == null ||
        completedBy == null ||
        completedBy.isEmpty ||
        completedBy == widget.currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot confirm your own task'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Confirm the task
    try {
      // updateTaskStatus will handle both task update AND activity update
      await widget.firestoreService.updateTaskStatus(taskId, 'completed');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task confirmed successfully!'),
            backgroundColor: Color(0xFF63BDA4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _isPressed = true;
        });
      },
      onTapUp: (_) async {
        setState(() {
          _isPressed = false;
        });
        // Handle confirmation for task completion activities
        await _handleConfirmTap();
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
