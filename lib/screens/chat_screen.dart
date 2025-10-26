import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import '../services/simple_task_detector.dart';
import '../models/chat_message_model.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final FirestoreService _firestoreService = FirestoreService();
  final AIService _aiService = AIService();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (houseProvider.currentHouseId == null || authProvider.user == null) {
      return;
    }

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

    final messageText = _messageController.text.trim();

    // Send the message
    await _firestoreService.sendMessage(
      houseId: houseProvider.currentHouseId!,
      message: messageText,
      senderName: userName,
      senderAvatar: initials,
      senderColor: '#$userColor',
    );

    _messageController.clear();
    _scrollToBottom();

    // AI-powered task detection
    // Analyze the message in the background to detect if it contains a task
    _analyzeMessageForTask(
      messageText,
      userName,
      houseProvider.currentHouseId!,
    );
  }

  Future<void> _analyzeMessageForTask(
    String message,
    String senderName,
    String houseId,
  ) async {
    try {
      // Get house members for context
      final members = await _firestoreService.getHouseMembers(houseId);

      // STRATEGY: Try simple detection first (works immediately without API)
      // Then try AI detection as fallback

      // Try simple pattern-based detection (no API required)
      final simpleTask = SimpleTaskDetector.detectTask(message, members);

      if (simpleTask != null && simpleTask.isTask) {
        // Simple detector found a task! Create it immediately
        await _firestoreService.createTaskFromAI(
          houseId: houseId,
          title: simpleTask.title!,
          description: simpleTask.description!,
          assignedTo: simpleTask.assignedTo,
          assignedToName: simpleTask.assignedToName,
          dueDate: simpleTask.dueDate,
          sourceMessage: message,
        );
        print('✅ Task created via simple detection: ${simpleTask.title}');
        return;
      }

      // If simple detection didn't find anything, try AI (requires API)
      try {
        final detectedTask = await _aiService.analyzeMessageForTask(
          message,
          senderName,
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
            sourceMessage: message,
          );
          print('✅ Task created via AI detection: ${detectedTask.title}');
        }
      } catch (aiError) {
        print('AI detection failed (API might not be enabled): $aiError');
        // This is OK - simple detection already ran above
      }
    } catch (e) {
      // Silently fail - don't interrupt the chat experience
      print('Error analyzing message for task: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final houseId = houseProvider.currentHouseId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Background cloud image
            Positioned.fill(
              child: Opacity(
                opacity: 0.4,
                child: Image.network(
                  'https://images.unsplash.com/photo-1534088568595-a066f410bcda?w=400',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(color: Colors.grey[800]);
                  },
                ),
              ),
            ),

            // Main content
            Column(
              children: [
                // Yellow header with house info
                StreamBuilder<List<DocumentSnapshot>>(
                  stream: houseId != null
                      ? FirebaseFirestore.instance
                          .collection('houses')
                          .doc(houseId)
                          .snapshots()
                          .asyncMap((houseDoc) async {
                            final houseData = houseDoc.data() as Map<String, dynamic>?;
                            final members = List<String>.from(houseData?['members'] ?? []);

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
                  builder: (context, memberSnapshot) {
                    String houseName = 'Group Chat';
                    String memberNames = 'and Beemo';

                    if (houseId != null) {
                      return StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('houses')
                            .doc(houseId)
                            .snapshots(),
                        builder: (context, houseSnapshot) {
                          if (houseSnapshot.hasData && houseSnapshot.data != null) {
                            final houseData = houseSnapshot.data!.data() as Map<String, dynamic>?;
                            houseName = houseData?['houseName'] ?? 'Group Chat';
                          }

                          if (memberSnapshot.hasData && memberSnapshot.data != null) {
                            final memberDocs = memberSnapshot.data!;
                            final names = memberDocs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>?;
                              return data?['profile']?['name'] ?? 'User';
                            }).toList();

                            if (names.isNotEmpty) {
                              memberNames = '${names.join(', ')} and Beemo';
                            }
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEC5D),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.black,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 39,
                                  height: 39,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[700],
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.public,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        houseName,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.black,
                                        ),
                                      ),
                                      Text(
                                        memberNames,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.black.withOpacity(0.8),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEC5D),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.black,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Group Chat',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Avatar row with real member data
                StreamBuilder<List<DocumentSnapshot>>(
                  stream: houseId != null
                      ? FirebaseFirestore.instance
                          .collection('houses')
                          .doc(houseId)
                          .snapshots()
                          .asyncMap((houseDoc) async {
                            final houseData = houseDoc.data() as Map<String, dynamic>?;
                            final members = List<String>.from(houseData?['members'] ?? []);

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
                    List<Widget> avatarWidgets = [];

                    if (snapshot.hasData && snapshot.data != null) {
                      final memberDocs = snapshot.data!;

                      for (int i = 0; i < memberDocs.length && i < 5; i++) {
                        final memberData = memberDocs[i].data() as Map<String, dynamic>?;
                        final avatarEmoji = memberData?['profile']?['avatarEmoji'] ?? '👤';
                        final avatarColor = memberData?['profile']?['avatarColor'];

                        Color color = const Color(0xFFFF4D6D);
                        if (avatarColor != null) {
                          color = Color(avatarColor);
                        }

                        avatarWidgets.add(
                          Positioned(
                            left: i * 14.0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  avatarEmoji,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      // Add Beemo at the end
                      avatarWidgets.add(
                        Positioned(
                          left: avatarWidgets.length * 14.0,
                          child: _buildBeemoAvatar(),
                        ),
                      );
                    } else {
                      // Default fallback
                      avatarWidgets = [
                        Positioned(left: 0, child: _buildBeemoAvatar()),
                      ];
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: SizedBox(
                        height: 24,
                        child: Stack(
                          children: avatarWidgets,
                        ),
                      ),
                    );
                  },
                ),

                // Chat messages
                Expanded(
                  child: Consumer<HouseProvider>(
                    builder: (context, houseProvider, _) {
                      if (houseProvider.currentHouseId == null) {
                        return const Center(
                          child: Text(
                            'Please create or join a house first',
                            style: TextStyle(color: Colors.white),
                          ),
                        );
                      }

                      return StreamBuilder<List<ChatMessage>>(
                        stream: _firestoreService.getChatMessagesStream(houseProvider.currentHouseId!),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                'Error: ${snapshot.error}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            );
                          }

                          final messages = snapshot.data ?? [];
                          final authProvider = Provider.of<AuthProvider>(context);
                          final currentUserId = authProvider.user?.uid;

                          // Auto-scroll to bottom when new messages arrive
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_scrollController.hasClients) {
                              _scrollController.jumpTo(
                                _scrollController.position.maxScrollExtent,
                              );
                            }
                          });

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(
                              left: 12,
                              right: 12,
                              top: 8,
                              bottom: 80, // Space for the input bar
                            ),
                            itemCount: messages.isEmpty ? 1 : messages.length,
                            itemBuilder: (context, index) {
                              if (messages.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(40.0),
                                  child: Center(
                                    child: Text(
                                      'No messages yet.\nStart the conversation!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final message = messages[index];
                              final isCurrentUser = message.senderId == currentUserId;
                              final isBeemo = message.isBeemo;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildMessageWidget(message, isCurrentUser, isBeemo),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),

            // Bottom input bar
            Positioned(
              bottom: 20,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(39),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 120, // 5 lines * 24px per line
                        ),
                        child: Scrollbar(
                          thumbVisibility: false,
                          child: TextField(
                            controller: _messageController,
                            focusNode: _focusNode,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black,
                            ),
                            maxLines: null,
                            minLines: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.mic, size: 20, color: Colors.black87),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _sendMessage,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFC400),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          size: 20,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageWidget(ChatMessage message, bool isCurrentUser, bool isBeemo) {
    if (isBeemo && message.messageType == 'poll') {
      return _buildFirebasePoll(message);
    } else if (isBeemo) {
      return _buildBeemoMessage(message.message);
    } else if (isCurrentUser) {
      return _buildRightAlignedMessage(message.message);
    } else {
      // Parse color from hex string
      Color avatarColor;
      try {
        avatarColor = Color(int.parse(message.senderColor.replaceFirst('#', '0xFF')));
      } catch (e) {
        avatarColor = const Color(0xFF16A3D0); // Default color
      }

      return _buildUserMessage(
        message.senderAvatar,
        message.senderName,
        message.message,
        avatarColor,
      );
    }
  }

  Widget _buildAvatar(String letter, Color color, {Color textColor = Colors.white}) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildBeemoAvatar() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFFFFC400),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: const Center(
        child: Text(
          '🤖',
          style: TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildBeemoMessage(String text, {String? boldText}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFFFC400),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: const Center(
            child: Text(
              '🤖',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6.5),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Beemo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                boldText != null
                    ? RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                            height: 1.4,
                          ),
                          children: _buildTextWithBold(text, boldText),
                        ),
                      )
                    : Text(
                        text,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                          height: 1.4,
                        ),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }

  List<TextSpan> _buildTextWithBold(String fullText, String boldPart) {
    final parts = fullText.split(boldPart);
    return [
      TextSpan(text: parts[0]),
      TextSpan(
        text: boldPart,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      if (parts.length > 1) TextSpan(text: parts[1]),
    ];
  }

  Widget _buildUserMessage(String avatar, String name, String text, Color avatarColor, {Color textColor = Colors.white}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: avatarColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Center(
            child: Text(
              avatar,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6.5),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _buildFirebasePoll(ChatMessage message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFFFC400),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: const Center(
            child: Text(
              '🤖',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6.5),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Beemo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                ...(message.pollOptions ?? []).asMap().entries.map((entry) {
                  final index = entry.key;
                  final option = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: GestureDetector(
                      onTap: () async {
                        await _firestoreService.voteOnPoll(message.id, index);
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: option.votes.isNotEmpty ? const Color(0xFFFFC400) : Colors.black,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${option.option} (${option.votes.length})',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _buildBeeomoPoll() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFFFC400),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: const Center(
            child: Text(
              '🤖',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6.5),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Beemo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "let's poll",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                _buildPollOption('Friday : 9 am'),
                const SizedBox(height: 4),
                _buildPollOption('Friday : 10 am'),
                const SizedBox(height: 4),
                _buildPollOption('Friday : 11 am'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _buildPollOption(String text) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Colors.black,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildRightAlignedMessage(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const SizedBox(width: 80),
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE3E3E3),
              borderRadius: BorderRadius.circular(6.5),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRightAlignedSmallMessage(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6.5),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }
}
