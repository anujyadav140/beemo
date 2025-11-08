import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/task_model.dart';
import '../widgets/beemo_logo.dart';
import 'dash_screen.dart';
import 'setup_house_screen.dart';

class _TaskGroup {
  _TaskGroup({required this.key, String? assignedId, String? assignedName})
    : assignedId = _trimOrNull(assignedId),
      assignedName = _trimOrNull(assignedName);

  final String key;
  String? assignedId;
  String? assignedName;
  final List<Task> tasks = [];

  bool isCurrentUser(String? userId) {
    if (assignedId == null || userId == null) {
      return false;
    }
    return assignedId == userId;
  }

  bool get isUnassigned =>
      (assignedId == null || assignedId!.isEmpty) &&
      (assignedName == null || assignedName!.isEmpty);

  static String? _trimOrNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

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

  List<_TaskGroup> _groupTasksByAssignee(
    List<Task> tasks,
    HouseProvider houseProvider,
    String? currentUserId,
  ) {
    final Map<String, _TaskGroup> groups = {};

    for (final task in tasks) {
      final assignedId = task.assignedTo.trim();
      final assignedName = task.assignedToName.trim();

      String key;
      if (assignedId.isNotEmpty) {
        key = 'user:$assignedId';
      } else if (assignedName.isNotEmpty) {
        key = 'name:${assignedName.toLowerCase()}';
      } else {
        key = 'unassigned';
      }

      final group = groups.putIfAbsent(
        key,
        () => _TaskGroup(
          key: key,
          assignedId: assignedId.isNotEmpty ? assignedId : null,
          assignedName: null,
        ),
      );

      if ((group.assignedId == null || group.assignedId!.isEmpty) &&
          assignedId.isNotEmpty) {
        group.assignedId = assignedId;
      }

      final resolvedName = _resolveMemberName(
        assignedId: assignedId.isNotEmpty ? assignedId : group.assignedId,
        fallbackName: assignedName.isNotEmpty
            ? assignedName
            : group.assignedName,
        houseProvider: houseProvider,
      );

      if (resolvedName != null && resolvedName.isNotEmpty) {
        group.assignedName = resolvedName;
      }

      group.tasks.add(task);
    }

    final groupedList = groups.values.toList();

    groupedList.sort((a, b) {
      final aIsUnassigned = a.isUnassigned;
      final bIsUnassigned = b.isUnassigned;

      // Unassigned tasks come first
      if (aIsUnassigned != bIsUnassigned) {
        return aIsUnassigned ? -1 : 1;
      }

      final aIsCurrent = a.isCurrentUser(currentUserId);
      final bIsCurrent = b.isCurrentUser(currentUserId);

      // My tasks come second (after unassigned)
      if (aIsCurrent != bIsCurrent) {
        return aIsCurrent ? -1 : 1;
      }

      // Other tasks sorted alphabetically
      final aTitle = _taskGroupTitle(a, currentUserId);
      final bTitle = _taskGroupTitle(b, currentUserId);
      return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
    });

    return groupedList;
  }

  String _taskGroupTitle(_TaskGroup group, String? currentUserId) {
    // Check if unassigned first
    if (group.isUnassigned) {
      return 'Unassigned Tasks';
    }

    if (group.isCurrentUser(currentUserId)) {
      return 'My Tasks';
    }

    final name = group.assignedName;
    if (_isMeaningfulName(name)) {
      final trimmed = name!.trim();
      final lower = trimmed.toLowerCase();

      if (lower == 'unassigned') {
        return 'Unassigned Tasks';
      }
      if (lower == 'house' || lower == 'household') {
        return 'House Tasks';
      }

      return '${_formatPossessiveLabel(trimmed)} Tasks';
    }

    if (group.assignedId != null && group.assignedId!.isNotEmpty) {
      return 'Assigned Tasks';
    }

    return 'House Tasks';
  }

  String? _resolveMemberName({
    required String? assignedId,
    required String? fallbackName,
    required HouseProvider houseProvider,
  }) {
    if (_isMeaningfulName(fallbackName)) {
      return fallbackName!.trim();
    }

    final id = assignedId?.trim();
    if (id != null && id.isNotEmpty) {
      final member = houseProvider.currentHouse?.members[id];
      if (member != null && member.name.trim().isNotEmpty) {
        return member.name.trim();
      }

      final suffix = id.length > 4 ? id.substring(id.length - 4) : id;
      return 'Member $suffix';
    }

    if (fallbackName != null && fallbackName.trim().isNotEmpty) {
      return fallbackName.trim();
    }

    return null;
  }

  bool _isMeaningfulName(String? name) {
    if (name == null) {
      return false;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final lower = trimmed.toLowerCase();
    return lower != 'unknown' && lower != 'null';
  }

  String _formatPossessiveLabel(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'House';
    }
    final endsWithS = trimmed.toLowerCase().endsWith('s');
    final suffix = endsWithS ? '\'' : '\'s';
    return '$trimmed$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.uid;

    if (houseProvider.currentHouseId == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const Center(child: Text('Please create or join a house first')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: StreamBuilder<List<Task>>(
                stream: _firestoreService.getTasksStream(
                  houseProvider.currentHouseId!,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  final tasks = snapshot.data ?? [];

                  final taskGroups = _groupTasksByAssignee(
                    tasks,
                    houseProvider,
                    currentUserId,
                  );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 160),
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
                                  final houseData =
                                      snapshot.data!.data()
                                          as Map<String, dynamic>?;
                                  houseName =
                                      houseData?['houseName'] ?? 'House';
                                  houseEmoji = houseData?['houseEmoji'] ?? '🏠';
                                  final houseColorInt =
                                      houseData?['houseColor'];
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
                                        border: Border.all(
                                          color: Colors.black,
                                          width: 2.5,
                                        ),
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
                                  ? _firestoreService.getUserPointsStream(
                                      currentUserId,
                                    )
                                  : Stream.value(500),
                              builder: (context, pointsSnapshot) {
                                final points = pointsSnapshot.data ?? 500;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFC400),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.black,
                                      width: 2.5,
                                    ),
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
                                  border: Border.all(
                                    color: Colors.black,
                                    width: 2.5,
                                  ),
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
                          ...taskGroups.map((group) {
                            final title = _taskGroupTitle(group, currentUserId);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...group.tasks.map(
                                  (task) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildTaskCard(task, currentUserId),
                                  ),
                                ),
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SetupHouseScreen(),
                              ),
                            );
                          },
                          child: _buildNavIcon(Icons.view_in_ar_rounded, false),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DashScreen(),
                              ),
                            );
                          },
                          child: _buildBeemoNavIcon(false),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {},
                          child: _buildNavIcon(Icons.event_note_rounded, true),
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

  Widget _buildTaskCard(Task task, String? currentUserId) {
    final status = task.status.toLowerCase();
    final isCompleted = status == 'completed';
    final isAwaitingPeer = status == 'pending_confirmation';
    final isMyTask =
        task.assignedTo.isNotEmpty && task.assignedTo == currentUserId;
    final canMarkDone = !isCompleted && !isAwaitingPeer && isMyTask;
    final canPeerConfirm = isAwaitingPeer && !isMyTask && currentUserId != null;

    String displayText;
    Color buttonColor;
    bool canInteract;

    if (isCompleted) {
      displayText = 'Verified';
      buttonColor = Colors.black;
      canInteract = false;
    } else if (canMarkDone) {
      displayText = 'Done';
      buttonColor = const Color(0xFFFF4D8D);
      canInteract = true;
    } else if (canPeerConfirm) {
      displayText = 'Confirm';
      buttonColor = const Color(0xFFFF4D8D);
      canInteract = true;
    } else if (isAwaitingPeer && isMyTask) {
      displayText = 'Awaiting review';
      buttonColor = Colors.black;
      canInteract = false;
    } else {
      displayText = 'Waiting';
      buttonColor = Colors.black;
      canInteract = false;
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
                  if (isAwaitingPeer) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Awaiting peer confirmation',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                  if (isCompleted &&
                      (task.confirmedByName?.trim().isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Confirmed by ${task.confirmedByName}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16A3D0),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Neobrutalist button
            GestureDetector(
              onTap: canInteract
                  ? () async {
                      if (canMarkDone) {
                        await _firestoreService.updateTaskStatus(
                          task.id,
                          'pending_confirmation',
                        );
                      } else if (canPeerConfirm) {
                        await _firestoreService.updateTaskStatus(
                          task.id,
                          'completed',
                        );
                      }
                    }
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 3, right: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
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
     child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
      ),
    );
  }
}
