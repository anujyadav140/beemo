import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import '../services/simple_task_detector.dart';

class AddAgendaScreen extends StatefulWidget {
  const AddAgendaScreen({super.key});

  @override
  State<AddAgendaScreen> createState() => _AddAgendaScreenState();
}

class _AddAgendaScreenState extends State<AddAgendaScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final AIService _aiService = AIService();
  String? _selectedPriority;
  String? _pressedPriority;
  bool _isSubmitPressed = false;
  bool _isLoading = false;
  int _meetingAgendaCount = 0;
  String? _selectedUserId;
  String? _selectedUserName;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(() {
      setState(() {});
    });
    _loadMeetingAgendaCount();
  }

  void _loadMeetingAgendaCount() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    if (houseProvider.currentHouseId != null) {
      final agendaItems = await _firestoreService
          .getAgendaItemsStream(houseProvider.currentHouseId!)
          .first;

      final meetingItems = agendaItems.where((item) =>
        item.priority == 'meeting' && item.status == 'pending'
      ).toList();

      setState(() {
        _meetingAgendaCount = meetingItems.length;
      });
    }
  }


  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title'),
          backgroundColor: Color(0xFFFF4D8D),
        ),
      );
      return;
    }

    // COMPULSORY: User must be selected
    if (_selectedUserId == null || _selectedUserName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a user to assign this agenda to'),
          backgroundColor: Color(0xFFFF4D8D),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_selectedPriority == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a priority'),
          backgroundColor: Color(0xFFFF4D8D),
        ),
      );
      return;
    }

    // Prevent adding more than 3 meeting agenda items
    if (_selectedPriority == 'meeting' && _meetingAgendaCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meeting agenda is full (3/3). Please select Chat or Flexible.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (houseProvider.currentHouseId == null) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create or join a house first')),
      );
      return;
    }

    try {
      // Create agenda item in Firestore
      await _firestoreService.createAgendaItem(
        houseId: houseProvider.currentHouseId!,
        title: _titleController.text.trim(),
        details: _detailsController.text.trim(),
        priority: _selectedPriority!,
      );

      // If priority is "chat", send message to group chat from the user
      if (_selectedPriority == 'chat' && authProvider.user != null) {
        final userName = authProvider.user?.displayName ??
                         authProvider.user?.email?.split('@')[0] ??
                         'User';

        // Get user initials for avatar
        final initials = userName.split(' ').map((n) => n.isNotEmpty ? n[0] : '').take(2).join();

        // Use a color based on user ID hash
        final colors = [
          const Color(0xFFFF3B79),
          const Color(0xFF63BDA4),
          const Color(0xFF16A3D0),
          const Color(0xFFFF4D8D),
        ];
        final colorIndex = authProvider.user!.uid.hashCode % colors.length;
        final userColor = colors[colorIndex].value.toRadixString(16).padLeft(8, '0').substring(2);

        // Format the message with title and details
        String message = '📋 ${_titleController.text.trim()}';
        if (_detailsController.text.trim().isNotEmpty) {
          message += '\n\n${_detailsController.text.trim()}';
        }

        await _firestoreService.sendMessage(
          houseId: houseProvider.currentHouseId!,
          message: message,
          senderName: userName,
          senderAvatar: initials,
          senderColor: '#$userColor',
        );
      }

      // Use Gemini AI to generate tasks for the selected user
      await _generateTasksFromAgenda(
        houseProvider.currentHouseId!,
        _titleController.text.trim(),
        _detailsController.text.trim(),
        _selectedUserId!,
        _selectedUserName!,
      );

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Agenda added! AI is generating tasks for $_selectedUserName...'),
            backgroundColor: const Color(0xFF63BDA4),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _analyzeAgendaForTask(
    String houseId,
    String title,
    String details,
    String creatorName,
  ) async {
    try {
      // Get house members for context
      final members = await _firestoreService.getHouseMembers(houseId);

      // Combine title and details for analysis
      final fullText = details.isNotEmpty ? '$title. $details' : title;

      // STRATEGY: Try simple detection first (works immediately without API)
      // Then try AI detection as fallback

      DetectedTaskInfo? simpleTask;

      // Try simple pattern-based detection (no API required)
      simpleTask = SimpleTaskDetector.detectTask(fullText, members);

      if (simpleTask != null && simpleTask.isTask) {
        // Simple detector found a task! Create it immediately
        await _firestoreService.createTaskFromAI(
          houseId: houseId,
          title: simpleTask.title!,
          description: simpleTask.description!,
          assignedTo: simpleTask.assignedTo,
          assignedToName: simpleTask.assignedToName,
          dueDate: simpleTask.dueDate,
          sourceMessage: 'Agenda: $title',
        );
        print('✅ Task created via simple detection: ${simpleTask.title}');
        return;
      }

      // If simple detection didn't find anything, try AI (requires API)
      try {
        final detectedTask = await _aiService.analyzeMessageForTask(
          fullText,
          creatorName,
          members,
        );

        if (detectedTask.isTask &&
            detectedTask.title != null &&
            detectedTask.description != null) {

          // Get the assigned user's name if we have an ID
          String? assignedToName;
          if (detectedTask.assignedTo != null) {
            final assignedMember = members.firstWhere(
              (m) => m['id'] == detectedTask.assignedTo,
              orElse: () => {'name': 'Unknown'},
            );
            assignedToName = assignedMember['name'];
          }

          // Create the task
          await _firestoreService.createTaskFromAI(
            houseId: houseId,
            title: detectedTask.title!,
            description: detectedTask.description!,
            assignedTo: detectedTask.assignedTo,
            assignedToName: assignedToName,
            dueDate: detectedTask.dueDate,
            sourceMessage: 'Agenda: $title',
          );
          print('✅ Task created via AI detection: ${detectedTask.title}');
        }
      } catch (aiError) {
        print('AI detection failed (API might not be enabled): $aiError');
        // This is OK - simple detection already ran above
      }
    } catch (e) {
      // Silently fail - don't interrupt the agenda creation flow
      print('Error analyzing agenda for task: $e');
    }
  }

  /// Generate tasks from agenda using Gemini AI when user is explicitly selected
  Future<void> _generateTasksFromAgenda(
    String houseId,
    String title,
    String details,
    String assignedToId,
    String assignedToName,
  ) async {
    try {
      print('🤖 Generating tasks for $assignedToName using Gemini AI...');

      final tasks = await _aiService.generateTasksFromAgenda(
        title: title,
        details: details.isNotEmpty ? details : title,
        assignedToName: assignedToName,
        assignedToId: assignedToId,
      );

      // Create each task in Firestore
      for (var task in tasks) {
        await _firestoreService.createTaskFromAI(
          houseId: houseId,
          title: task.title!,
          description: task.description!,
          assignedTo: assignedToId,
          assignedToName: assignedToName,
          dueDate: task.dueDate,
          sourceMessage: 'Agenda: $title',
        );
        print('✅ Task created: ${task.title}');
      }

      print('🎉 Generated ${tasks.length} task(s) for $assignedToName');
    } catch (e) {
      print('❌ Error generating tasks from agenda: $e');
      // Silently fail - don't interrupt the agenda creation flow
    }
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final houseId = houseProvider.currentHouseId;

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
                          'Add Agenda Item',
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

                    // Title label
                    const Text(
                      'Title',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Title input field
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                          top: const BorderSide(color: Colors.black, width: 3),
                          bottom: const BorderSide(color: Colors.black, width: 3),
                          left: const BorderSide(color: Colors.black, width: 3),
                          right: const BorderSide(color: Colors.black, width: 3),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _titleController,
                                decoration: const InputDecoration(
                                  hintText: 'Name',
                                  hintStyle: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 16,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            if (_titleController.text.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _titleController.clear();
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF4D8D),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Details label
                    const Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Details input field
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border(
                          top: const BorderSide(color: Colors.black, width: 3),
                          bottom: const BorderSide(color: Colors.black, width: 3),
                          left: const BorderSide(color: Colors.black, width: 3),
                          right: const BorderSide(color: Colors.black, width: 3),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: TextField(
                          controller: _detailsController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Details',
                            hintStyle: TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Assign To label (COMPULSORY)
                    Row(
                      children: [
                        const Text(
                          'Assign To',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4D8D),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: const Text(
                            'REQUIRED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // User selection chips with StreamBuilder - fetches user details from users collection
                    StreamBuilder<List<DocumentSnapshot>>(
                      stream: houseId != null
                          ? FirebaseFirestore.instance
                              .collection('houses')
                              .doc(houseId)
                              .snapshots()
                              .asyncMap((houseDoc) async {
                                final houseData = houseDoc.data() as Map<String, dynamic>?;
                                final members = List<String>.from(houseData?['members'] ?? []);

                                if (members.isEmpty) {
                                  return <DocumentSnapshot>[];
                                }

                                // Fetch user details for each member
                                final memberDocs = await Future.wait(
                                  members.map((memberId) =>
                                    FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(memberId)
                                      .get()
                                  )
                                );

                                return memberDocs;
                              })
                          : null,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.black, width: 2.5),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, color: Color(0xFFFF4D8D)),
                                const SizedBox(width: 12),
                                Text(
                                  'Error: ${snapshot.error}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final memberDocs = snapshot.data ?? [];

                        // Get current user ID to exclude from list
                        final authProvider = Provider.of<AuthProvider>(context, listen: false);
                        final currentUserId = authProvider.user?.uid;

                        // Build member list from user documents, excluding current user
                        List<Map<String, String>> membersList = [];
                        for (var doc in memberDocs) {
                          // Skip the currently signed-in user
                          if (doc.id == currentUserId) {
                            continue;
                          }

                          final userData = doc.data() as Map<String, dynamic>?;
                          final userName = userData?['profile']?['name'] ??
                                         userData?['displayName'] ??
                                         userData?['email']?.split('@')[0] ??
                                         'User';
                          membersList.add({
                            'id': doc.id,
                            'name': userName,
                          });
                        }

                        if (membersList.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.black, width: 2.5),
                            ),
                            child: const Text(
                              'No other house members found',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          );
                        }

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: membersList.map((member) {
                            final isSelected = _selectedUserId == member['id'];
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedUserId = member['id'];
                                  _selectedUserName = member['name'];
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Container(
                                  margin: EdgeInsets.only(
                                    bottom: isSelected ? 0 : 4,
                                    right: isSelected ? 0 : 4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFFFC400) : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.black, width: 2.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF4D8D),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.black, width: 2),
                                        ),
                                        child: Center(
                                          child: Text(
                                            member['name']?[0] ?? '?',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        member['name'] ?? 'Unknown',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Choose Priority label
                    const Text(
                      'Choose Priority',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Priority Options
                    _buildPriorityOption(
                      value: 'meeting',
                      title: 'Discuss in Meeting',
                      description: _meetingAgendaCount >= 3
                          ? 'Meeting agenda is full (3/3). Please use Chat or Flexible.'
                          : 'Best for important topics that need a calm, focused conversation. ($_meetingAgendaCount/3)',
                      isDisabled: _meetingAgendaCount >= 3,
                    ),
                    const SizedBox(height: 12),
                    _buildPriorityOption(
                      value: 'chat',
                      title: 'Send to Group Chat',
                      description: 'For quick questions or simple updates that don\'t need a full discussion.',
                      isDisabled: false,
                    ),
                    const SizedBox(height: 12),
                    _buildPriorityOption(
                      value: 'flexible',
                      title: 'Flexible',
                      description: 'Add to the meeting. If the agenda is full, Beemo will move this to the group chat.',
                      isDisabled: false,
                    ),
                    const SizedBox(height: 32),

                    // Submit button
                    Center(
                      child: GestureDetector(
                        onTapDown: (_) {
                          if (!_isLoading) {
                            setState(() {
                              _isSubmitPressed = true;
                            });
                          }
                        },
                        onTapUp: (_) async {
                          if (!_isLoading) {
                            setState(() {
                              _isSubmitPressed = false;
                            });
                            await _handleSubmit();
                          }
                        },
                        onTapCancel: () {
                          setState(() {
                            _isSubmitPressed = false;
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 100),
                            curve: Curves.easeOut,
                            margin: EdgeInsets.only(
                              bottom: _isSubmitPressed ? 0 : 5,
                              right: _isSubmitPressed ? 0 : 5,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 48,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4D8D),
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Submit',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
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
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: _buildNavIcon(Icons.event_note_rounded, true),
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

  Widget _buildPriorityOption({
    required String value,
    required String title,
    required String description,
    required bool isDisabled,
  }) {
    final isSelected = _selectedPriority == value;
    final isPressed = _pressedPriority == value;
    final showPressedEffect = isSelected || isPressed;

    return GestureDetector(
      onTapDown: isDisabled ? null : (_) {
        setState(() {
          _pressedPriority = value;
        });
      },
      onTapUp: isDisabled ? null : (_) {
        setState(() {
          _selectedPriority = value;
          _pressedPriority = null;
        });
      },
      onTapCancel: isDisabled ? null : () {
        setState(() {
          _pressedPriority = null;
        });
      },
      child: Opacity(
        opacity: isDisabled ? 0.4 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: isDisabled ? Colors.grey.shade400 : Colors.black,
            borderRadius: BorderRadius.circular(16),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            margin: EdgeInsets.only(
              bottom: showPressedEffect ? 0 : 5,
              right: showPressedEffect ? 0 : 5,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDisabled
                  ? Colors.grey.shade300
                  : (isSelected ? const Color(0xFFFFC400) : Colors.white),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDisabled ? Colors.grey.shade400 : Colors.black,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: isDisabled ? Colors.grey.shade600 : Colors.black,
                        ),
                      ),
                    ),
                    if (isDisabled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade700, width: 2),
                        ),
                        child: const Text(
                          'FULL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: isDisabled ? Colors.grey.shade600 : Colors.black87,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
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
