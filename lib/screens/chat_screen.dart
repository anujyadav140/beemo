import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
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
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
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

    await _firestoreService.sendMessage(
      houseId: houseProvider.currentHouseId!,
      message: _messageController.text.trim(),
      senderName: userName,
      senderAvatar: initials,
      senderColor: '#$userColor',
    );

    _messageController.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
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
                // Yellow header
                Container(
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
                            const Text(
                              'The Lab',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                fontStyle: FontStyle.italic,
                                color: Colors.black,
                              ),
                            ),
                            Text(
                              'Meher, Charls, Ria, Ray and Beemo',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: Colors.black.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Avatar row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: SizedBox(
                    height: 24,
                    child: Stack(
                      children: [
                        Positioned(left: 0, child: _buildAvatar('A', const Color(0xFFFF3B79))),
                        Positioned(left: 14, child: _buildAvatar('B', const Color(0xFF63BDA4))),
                        Positioned(left: 28, child: _buildAvatar('C', const Color(0xFFFFEC5D), textColor: Colors.black)),
                        Positioned(left: 42, child: _buildAvatar('D', const Color(0xFF16A3D0))),
                        Positioned(left: 56, child: _buildBeemoAvatar()),
                      ],
                    ),
                  ),
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
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(color: Color(0xFFFFC400)),
                            );
                          }

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

                          // Auto-scroll when new messages arrive
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_scrollController.hasClients) {
                              _scrollController.animateTo(
                                _scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          });

                          return SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (messages.isEmpty)
                                  const Padding(
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
                                  )
                                else
                                  ...messages.map((message) {
                                    final isCurrentUser = message.senderId == currentUserId;
                                    final isBeemo = message.isBeemo;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _buildMessageWidget(message, isCurrentUser, isBeemo),
                                    );
                                  }),
                                const SizedBox(height: 100),
                              ],
                            ),
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
