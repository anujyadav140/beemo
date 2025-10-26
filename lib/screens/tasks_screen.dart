import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/task_model.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _cleanupTestTasks();
  }

  Future<void> _cleanupTestTasks() async {
    // Clean up test tasks on screen load
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    if (houseProvider.currentHouseId != null) {
      await _firestoreService.deleteTestTasks(houseProvider.currentHouseId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.uid;

    if (houseProvider.currentHouseId == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const Center(
          child: Text('Please create or join a house first'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Task>>(
                stream: _firestoreService.getTasksStream(houseProvider.currentHouseId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final tasks = snapshot.data ?? [];

                  // Group tasks by user
                  final Map<String, List<Task>> tasksByUser = {};
                  for (final task in tasks) {
                    if (!tasksByUser.containsKey(task.assignedToName)) {
                      tasksByUser[task.assignedToName] = [];
                    }
                    tasksByUser[task.assignedToName]!.add(task);
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top header with house icon and points badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('houses')
                                  .doc(houseProvider.currentHouseId)
                                  .snapshots(),
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
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: houseColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black, width: 2.5),
                                      ),
                                      child: Center(
                                        child: Text(
                                          houseEmoji,
                                          style: const TextStyle(fontSize: 24),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      houseName,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            StreamBuilder<int>(
                              stream: currentUserId != null
                                  ? _firestoreService.getUserPointsStream(currentUserId)
                                  : Stream.value(500),
                              builder: (context, pointsSnapshot) {
                                final points = pointsSnapshot.data ?? 500;
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFC400),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.black, width: 2.5),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        points.toString(),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFFFF6B6B),
                                        ),
                                        child: const Center(
                                          child: Text(
                                            '🎯',
                                            style: TextStyle(fontSize: 10),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Back button and title
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
                              'Tasks for the week',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // Tasks grouped by user
                        if (tasks.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40.0),
                              child: Text(
                                'No tasks yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          )
                        else
                          ...tasksByUser.entries.map((entry) {
                            final userName = entry.key;
                            final userTasks = entry.value;
                            final isCurrentUser = userTasks.any((task) => task.assignedTo == currentUserId);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isCurrentUser ? 'My Tasks' : '$userName\'s Tasks',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...userTasks.map((task) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildTaskCard(task, currentUserId),
                                )),
                                const SizedBox(height: 20),
                              ],
                            );
                          }),
                      ],
                    ),
                  );
                },
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
                      _buildNavIcon(Icons.view_in_ar_rounded, false),
                      const SizedBox(width: 28),
                      _buildBeemoNavIcon(true),
                      const SizedBox(width: 28),
                      _buildNavIcon(Icons.event_note_rounded, false),
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

  Widget _buildTaskCard(Task task, String? currentUserId) {
    final isCompleted = task.status == 'completed';
    final isMyTask = task.assignedTo == currentUserId;

    String displayText;
    Color buttonColor;
    bool canInteract;

    if (isCompleted) {
      displayText = 'Completed';
      buttonColor = Colors.black;
      canInteract = false;
    } else if (isMyTask) {
      displayText = 'Done';
      buttonColor = const Color(0xFFFF4D8D);
      canInteract = true;
    } else {
      displayText = 'Confirm';
      buttonColor = const Color(0xFFFF4D8D);
      canInteract = true;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6, right: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Neobrutalist button
            GestureDetector(
              onTap: canInteract
                  ? () async {
                      await _firestoreService.updateTaskStatus(task.id, 'completed');
                    }
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 3, right: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: buttonColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black, width: 2.5),
                  ),
                  child: Text(
                    displayText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
