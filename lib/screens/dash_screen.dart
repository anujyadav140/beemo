import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/auth_provider.dart';
import '../providers/house_provider.dart';
import '../services/firestore_service.dart';
import '../models/activity_model.dart';
import '../widgets/beemo_logo.dart';
import 'meeting_notes_screen.dart';
import 'tasks_screen.dart';
import 'agenda_screen.dart';
import 'timer_screen.dart';
import 'chat_screen.dart';
import 'next_meeting_screen.dart';
import 'setup_house_screen.dart';
import 'virtual_house_screen.dart';
import 'edit_house_webview_screen.dart';
import 'recent_activity_screen.dart';
import 'account_settings_screen.dart';
import 'meeting_screen.dart';
import 'dart:async';
import '../widgets/coin_display.dart';

class DashScreen extends StatefulWidget {
  const DashScreen({super.key});

  @override
  State<DashScreen> createState() => _DashScreenState();
}

class _DashScreenState extends State<DashScreen> {
  final TextEditingController _messageController = TextEditingController();
  Timer? _meetingPopupTimer;
  bool _meetingPopupShown = false;
  DateTime? _lastScheduledMeeting;
  int _beemoTapCount = 0; // Testing hack: tap 20 times for 1000 coins
  Timer? _beemoTapResetTimer; // Reset tap count if not consecutive

  @override
  void initState() {
    super.initState();
    // Check for scheduled meeting every minute
    _meetingPopupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkAndShowMeetingPopup();
    });
    // Initial check after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _checkAndShowMeetingPopup();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _meetingPopupTimer?.cancel();
    _beemoTapResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkAndShowMeetingPopup() async {
    if (!mounted) return;

    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    if (houseId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('nextMeetings')
          .doc(houseId)
          .get();

      if (!doc.exists || !mounted) return;

      final data = doc.data();
      if (data == null) return;

      final scheduledTimestamp = data['scheduledTime'] as Timestamp?;
      if (scheduledTimestamp == null) return;

      final scheduledTime = scheduledTimestamp.toDate();
      final now = DateTime.now();

      // Check if scheduled time has arrived (within 5 minute window)
      final timeDiff = now.difference(scheduledTime).inMinutes;
      final isTimeToMeet = timeDiff >= 0 && timeDiff <= 5;

      // Only show if it's time and we haven't shown it for this meeting yet
      if (isTimeToMeet &&
          (_lastScheduledMeeting == null ||
           !_isSameMeeting(scheduledTime, _lastScheduledMeeting!))) {
        _lastScheduledMeeting = scheduledTime;
        _meetingPopupShown = false;
      }

      if (isTimeToMeet && !_meetingPopupShown) {
        _meetingPopupShown = true;
        _showMeetingPopup();
      }
    } catch (e) {
      // Silently fail - don't show popup on error
      debugPrint('Error checking meeting time: $e');
    }
  }

  bool _isSameMeeting(DateTime time1, DateTime time2) {
    return time1.year == time2.year &&
           time1.month == time2.month &&
           time1.day == time2.day &&
           time1.hour == time2.hour &&
           (time1.minute - time2.minute).abs() < 10;
  }

  // Testing hack: 20 consecutive Beemo taps = 1000 coins
  void _handleBeemoTap() async {
    // Cancel previous reset timer
    _beemoTapResetTimer?.cancel();

    // Increment tap count
    setState(() {
      _beemoTapCount++;
    });

    // Debug: Show current tap count (for testing)
    print('🎮 Beemo taps: $_beemoTapCount/20');

    // Check if reached 20 taps
    if (_beemoTapCount >= 20) {
      // Award 1000 coins
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final houseProvider = Provider.of<HouseProvider>(context, listen: false);
      final userId = authProvider.user?.uid;
      final houseId = houseProvider.currentHouseId;

      if (userId != null && houseId != null) {
        try {
          // Add 1000 coins
          await FirebaseFirestore.instance
              .collection('houses')
              .doc(houseId)
              .update({
            'members.$userId.coins': FieldValue.increment(1000),
          });

          // Reset tap count
          setState(() {
            _beemoTapCount = 0;
          });

          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Testing Mode: +1000 coins!'),
                backgroundColor: Color(0xFF4CAF50),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          print('❌ Failed to award coins: $e');
          setState(() {
            _beemoTapCount = 0;
          });
        }
      } else {
        setState(() {
          _beemoTapCount = 0;
        });
      }
    } else {
      // Start reset timer (2 seconds)
      _beemoTapResetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _beemoTapCount = 0;
          });
          print('⏰ Beemo tap count reset (not consecutive)');
        }
      });
    }
  }

  void _showMeetingPopup() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Stack(
            children: [
              // Main dialog container with shadow
              Container(
                margin: const EdgeInsets.only(
                  top: 50,
                  left: 6,
                  bottom: 6,
                  right: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 5, right: 5),
                  padding: const EdgeInsets.fromLTRB(28, 70, 28, 32),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFEF7),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title
                      Text(
                        'Weekly Check-in',
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Message
                      Text(
                        'Time for your weekly house meeting!\nLet\'s discuss what matters.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF414141),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Join button
                      _buildNeobrutalistButton(
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MeetingScreen(),
                            ),
                          );
                        },
                        backgroundColor: const Color(0xFFFFC400),
                        textColor: Colors.black,
                        text: 'Join Meeting',
                        icon: Icons.video_call_rounded,
                      ),
                      const SizedBox(height: 14),
                      // Dismiss button
                      _buildNeobrutalistButton(
                        onTap: () {
                          Navigator.pop(context);
                        },
                        backgroundColor: Colors.white,
                        textColor: const Color(0xFF414141),
                        text: 'Maybe Later',
                        icon: Icons.close_rounded,
                        isSecondary: true,
                      ),
                    ],
                  ),
                ),
              ),
              // Floating Beemo icon at the top
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B79),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                      child: Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF63BDA4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black,
                                offset: Offset(3, 3),
                              ),
                            ],
                          ),
                         child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
      ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNeobrutalistButton({
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color textColor,
    required String text,
    required IconData icon,
    bool isSecondary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4, right: 4),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: textColor, size: 22),
              const SizedBox(width: 10),
              Text(
                text,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontSize: 17,
                  fontWeight: isSecondary ? FontWeight.w700 : FontWeight.w900,
                  color: textColor,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final houseProvider = Provider.of<HouseProvider>(context);
    final userId = authProvider.user?.uid;
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
                  const SizedBox(height: 8),
                  // Header with StreamBuilder for both house and user data
                  StreamBuilder<DocumentSnapshot>(
                    stream: houseId != null
                        ? FirebaseFirestore.instance
                              .collection('houses')
                              .doc(houseId)
                              .snapshots()
                        : null,
                    builder: (context, houseSnapshot) {
                      String houseName = 'My House';
                      String houseCode = '';
                      String houseEmoji = '🏠';
                      Color houseColor = const Color(0xFF00BCD4);

                      if (houseSnapshot.hasData && houseSnapshot.data != null) {
                        final houseData =
                            houseSnapshot.data!.data() as Map<String, dynamic>?;
                        houseName = houseData?['houseName'] ?? 'My House';
                        houseCode = houseData?['houseCode'] ?? '';
                        houseEmoji = houseData?['houseEmoji'] ?? '🏠';
                        final houseColorInt = houseData?['houseColor'];
                        if (houseColorInt != null) {
                          houseColor = Color(houseColorInt);
                        }
                      }

                      return StreamBuilder<DocumentSnapshot>(
                        stream: userId != null
                            ? FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(userId)
                                  .snapshots()
                            : null,
                        builder: (context, userSnapshot) {
                          String avatarEmoji = '👤';
                          Color avatarColor = const Color(0xFFFF4D8D);

                          if (userSnapshot.hasData &&
                              userSnapshot.data != null) {
                            final userData =
                                userSnapshot.data!.data()
                                    as Map<String, dynamic>?;
                            avatarEmoji =
                                userData?['profile']?['avatarEmoji'] ?? '👤';
                            final avatarColorInt =
                                userData?['profile']?['avatarColor'];
                            if (avatarColorInt != null) {
                              avatarColor = Color(avatarColorInt);
                            }
                          }

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    // House Avatar
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const AccountSettingsScreen(),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        width: 52,
                                        height: 52,
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
                                            style: const TextStyle(
                                              fontSize: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const AccountSettingsScreen(),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          houseName,
                                          style: const TextStyle(
                                            fontSize: 34,
                                            fontWeight: FontWeight.w900,
                                            fontStyle: FontStyle.italic,
                                            letterSpacing: -0.5,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              userId != null && houseId != null
                                  ? CoinDisplay(
                                      userId: userId,
                                      houseId: houseId,
                                      fontSize: 18,
                                      coinSize: 22,
                                      fontWeight: FontWeight.bold,
                                      showBorder: true,
                                    )
                                  : const CoinDisplay(
                                      points: 0,
                                      fontSize: 18,
                                      coinSize: 22,
                                      fontWeight: FontWeight.bold,
                                      showBorder: true,
                                    ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 4),

                  // Agenda goal
                  StreamBuilder<QuerySnapshot>(
                    stream: houseId != null
                        ? FirebaseFirestore.instance
                              .collection('agendaItems')
                              .where('houseId', isEqualTo: houseId)
                              .where('priority', isEqualTo: 'meeting')
                              .snapshots()
                        : null,
                    builder: (context, agendaSnapshot) {
                      final meetingAgendaCount = agendaSnapshot.hasData
                          ? agendaSnapshot.data!.docs.length
                          : 0;
                      return Center(
                        child: Text(
                          'Agenda items goal: $meetingAgendaCount/4',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                      );
                    },
                  ),

                  // Cards 2x2 Grid - Completely redesigned from scratch
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column
                      Expanded(
                        child: Column(
                          children: [
                            // Meeting Notes (yellow) - Very short
                            SizedBox(
                              height: 70,
                              child: _buildMeetingNotesCard(),
                            ),
                            const SizedBox(height: 12),
                            // Tasks (pink) - Tall
                            SizedBox(height: 200, child: _buildTasksCard()),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Right Column
                      Expanded(
                        child: Column(
                          children: [
                            // Activity (cyan) - Tall
                            SizedBox(
                              height: 160,
                              child: _buildRecentActivityCard(),
                            ),
                            const SizedBox(height: 12),
                            // Next Meeting (green) - Medium
                            SizedBox(
                              height: 110,
                              child: _buildNextMeetingCard(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Group Chat Section
                  const Text(
                    'Group chat with beemo',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),

                  // Chat Container with Neobrutalist Border
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => ChatScreen()),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 5, right: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16213E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: Stack(
                          children: [
                            // Background cloud image on the right
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(17),
                                  bottomRight: Radius.circular(17),
                                ),
                                child: Container(
                                  width: 120,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF16213E),
                                        Color(0xFF334155),
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                  ),
                                  child: Opacity(
                                    opacity: 0.4,
                                    child: Image.network(
                                      'https://images.unsplash.com/photo-1534088568595-a066f410bcda?w=400',
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.transparent,
                                            );
                                          },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Content
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Profile Avatars (stacked horizontally) - Dynamic from house members
                                  StreamBuilder<List<DocumentSnapshot>>(
                                    stream: houseId != null
                                        ? FirebaseFirestore.instance
                                              .collection('houses')
                                              .doc(houseId)
                                              .snapshots()
                                              .asyncMap((houseDoc) async {
                                                final houseData =
                                                    houseDoc.data()
                                                        as Map<
                                                          String,
                                                          dynamic
                                                        >?;
                                                final members =
                                                    List<String>.from(
                                                      houseData?['members'] ??
                                                          [],
                                                    );

                                                // Fetch user details for each member
                                                final memberDocs =
                                                    await Future.wait(
                                                      members.map(
                                                        (memberId) =>
                                                            FirebaseFirestore
                                                                .instance
                                                                .collection(
                                                                  'users',
                                                                )
                                                                .doc(memberId)
                                                                .get(),
                                                      ),
                                                    );

                                                return memberDocs;
                                              })
                                        : null,
                                    builder: (context, snapshot) {
                                      List<Widget> avatarWidgets = [];

                                      if (snapshot.hasData &&
                                          snapshot.data != null) {
                                        final memberDocs = snapshot.data!;

                                        // Show ALL members, not just 4
                                        for (
                                          int i = 0;
                                          i < memberDocs.length;
                                          i++
                                        ) {
                                          final memberData =
                                              memberDocs[i].data()
                                                  as Map<String, dynamic>?;
                                          final avatarEmoji =
                                              memberData?['profile']?['avatarEmoji'] ??
                                              '👤';
                                          final avatarColor =
                                              memberData?['profile']?['avatarColor'];

                                          Color color = const Color(0xFFFF4D6D);
                                          if (avatarColor != null) {
                                            color = Color(avatarColor);
                                          }

                                          avatarWidgets.add(
                                            Positioned(
                                              left: i * 20.0,
                                              child: Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: Colors.black,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    avatarEmoji,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        // Add Beemo at the end
                                        avatarWidgets.add(
                                          Positioned(
                                            left: avatarWidgets.length * 20.0,
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFC400),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.black,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Center(
                                                child: BeemoLogo(size: 14),
                                              ),
                                            ),
                                          ),
                                        );
                                      } else {
                                        // Default fallback
                                        avatarWidgets = [
                                          Positioned(
                                            left: 0,
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFC400),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.black,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Center(
                                                child: BeemoLogo(size: 14),
                                              ),
                                            ),
                                          ),
                                        ];
                                      }

                                      // Calculate dynamic width based on number of avatars
                                      final stackWidth =
                                          (avatarWidgets.length * 20.0) + 8;

                                      return Row(
                                        children: [
                                          SizedBox(
                                            width: stackWidth,
                                            height: 28,
                                            child: Stack(
                                              children: avatarWidgets,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),

                                  // Latest messages from Firebase (showing last 3)
                                  StreamBuilder<QuerySnapshot>(
                                    stream: houseId != null
                                        ? FirebaseFirestore.instance
                                              .collection('chatMessages')
                                              .where(
                                                'houseId',
                                                isEqualTo: houseId,
                                              )
                                              .orderBy(
                                                'timestamp',
                                                descending: true,
                                              )
                                              .limit(3)
                                              .snapshots()
                                        : null,
                                    builder: (context, snapshot) {
                                      if (snapshot.hasError) {
                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Error: ${snapshot.error}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        );
                                      }

                                      final messages =
                                          snapshot.data?.docs ?? [];

                                      if (messages.isEmpty) {
                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Center(
                                            child: Text(
                                              'No messages yet. Start the conversation!',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        );
                                      }

                                      return Column(
                                        children: messages.reversed.map((
                                          messageDoc,
                                        ) {
                                          final messageData =
                                              messageDoc.data()
                                                  as Map<String, dynamic>?;
                                          final message =
                                              messageData?['message'] ?? '';
                                          final senderName =
                                              messageData?['senderName'] ??
                                              'User';
                                          final isBeemo =
                                              messageData?['isBeemo'] ?? false;
                                          final senderAvatar =
                                              messageData?['senderAvatar'] ??
                                              '👤';
                                          final senderColorHex =
                                              messageData?['senderColor'] ??
                                              '#16A3D0';

                                          Color avatarColor = const Color(
                                            0xFF16A3D0,
                                          );
                                          try {
                                            avatarColor = Color(
                                              int.parse(
                                                senderColorHex.replaceFirst(
                                                  '#',
                                                  '0xFF',
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            // Use default color
                                          }

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Avatar Icon
                                                Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: isBeemo
                                                        ? const Color(
                                                            0xFFFFC400,
                                                          )
                                                        : avatarColor,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.black,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: isBeemo
                                                        ? const BeemoLogo(
                                                            size: 14,
                                                          )
                                                        : Text(
                                                            senderAvatar,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight: FontWeight.w600,
                                                                ),
                                                          ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Chat Bubble
                                                Expanded(
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          isBeemo
                                                              ? 'Beemo'
                                                              : senderName,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                fontSize: 13,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Text(
                                                          message.length > 60
                                                              ? '${message.substring(0, 60)}...'
                                                              : message,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),

                                  // Input Field
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            '|',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.black45,
                                            ),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.mic,
                                          size: 20,
                                          color: Colors.black87,
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFFC400),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.send,
                                            size: 16,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                                builder: (context) => const EditHouseWebViewScreen(),
                              ),
                            );
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
                          onTap: _handleBeemoTap,
                          child: _buildBeemoNavIcon(true),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AgendaScreen(),
                              ),
                            );
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
                                  'assets/images/note.svg',
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.contain,
                                ),
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

  Widget _buildMeetingNotesCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MeetingNotesScreen()),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFD93D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Notes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit, size: 16, color: Color(0xFFFFD93D)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksCard() {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    return StreamBuilder<QuerySnapshot>(
      stream: houseId != null
          ? FirebaseFirestore.instance
                .collection('tasks')
                .where('houseId', isEqualTo: houseId)
                .orderBy('createdAt', descending: true)
                .limit(3)
                .snapshots()
          : null,
      builder: (context, snapshot) {
        // Filter out archived tasks to prevent duplicates
        final tasks = snapshot.hasData
            ? snapshot.data!.docs.where((doc) {
                final task = doc.data() as Map<String, dynamic>;
                final status = (task['status'] ?? '').toString().toLowerCase();
                return status != 'archived';
              }).toList()
            : [];

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const TasksScreen()),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFF4D8D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Tasks',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_box_outlined,
                        size: 16,
                        color: Color(0xFFFF4D8D),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: tasks.isEmpty
                      ? const Text(
                          'No tasks yet',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        )
                      : SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            children: tasks.take(3).map((taskDoc) {
                              final task =
                                  taskDoc.data() as Map<String, dynamic>;
                              final title = task['title'] ?? 'Untitled';
                              final status = (task['status'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              final isCompleted =
                                  status == 'completed' ||
                                  task['isCompleted'] == true;
                              final isAwaitingConfirmation =
                                  status == 'pending_confirmation';
                              final confirmedByName =
                                  (task['confirmedByName'] ?? '')
                                      .toString()
                                      .trim();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      margin: const EdgeInsets.only(top: 1),
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2.5,
                                        ),
                                      ),
                                      child: isCompleted
                                          ? const Icon(
                                              Icons.check,
                                              size: 12,
                                              color: Color(0xFFFF4D8D),
                                            )
                                          : isAwaitingConfirmation
                                          ? const Icon(
                                              Icons.hourglass_bottom,
                                              size: 12,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            style: TextStyle(
                                              color: isCompleted
                                                  ? Colors.white70
                                                  : Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              height: 1.3,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (isAwaitingConfirmation)
                                            const Padding(
                                              padding: EdgeInsets.only(top: 2),
                                              child: Text(
                                                'Awaiting peer confirmation',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          if (isCompleted &&
                                              confirmedByName.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              child: Text(
                                                'Confirmed by $confirmedByName',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentActivityCard() {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    return StreamBuilder<QuerySnapshot>(
      stream: houseId != null
          ? FirebaseFirestore.instance
                .collection('activities')
                .where('houseId', isEqualTo: houseId)
                .orderBy('createdAt', descending: true)
                .limit(1)
                .snapshots()
          : null,
      builder: (context, snapshot) {
        final activities = snapshot.hasData ? snapshot.data!.docs : [];
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;

        String primaryText = 'No activity yet';
        String? secondaryText;
        String timeText = '';

        if (activities.isNotEmpty) {
          final activity = activities.first.data() as Map<String, dynamic>;
          final rawDescription = (activity['description'] ?? '')
              .toString()
              .trim();
          final rawTitle = (activity['title'] ?? '').toString().trim();
          final createdAt = activity['createdAt'];

          primaryText = rawDescription.isNotEmpty
              ? rawDescription
              : (rawTitle.isNotEmpty ? rawTitle : 'Latest update');

          if (rawTitle.isNotEmpty && rawTitle != primaryText) {
            secondaryText = rawTitle;
          }

          if (createdAt is Timestamp) {
            final activityTime = createdAt.toDate();
            final now = DateTime.now();
            if (DateUtils.isSameDay(activityTime, now)) {
              timeText =
                  'Today \u2022 ${DateFormat('h:mm a').format(activityTime)}';
            } else if (DateUtils.isSameDay(
              activityTime,
              now.subtract(const Duration(days: 1)),
            )) {
              timeText =
                  'Yesterday \u2022 ${DateFormat('h:mm a').format(activityTime)}';
            } else {
              final dateLabel = DateFormat('MMM d').format(activityTime);
              final timeLabel = DateFormat('h:mm a').format(activityTime);
              timeText = '$dateLabel \u2022 $timeLabel';
            }
          }
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const RecentActivityScreen(),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF00BCD4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Activity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications,
                        size: 16,
                        color: Color(0xFF00BCD4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isLoading)
                  const SizedBox(
                    height: 36,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '\u2022',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              primaryText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (secondaryText != null &&
                                secondaryText!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  secondaryText!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (timeText.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  timeText,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNextMeetingCard() {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    return StreamBuilder<DocumentSnapshot>(
      stream: houseId != null
          ? FirebaseFirestore.instance
                .collection('nextMeetings')
                .doc(houseId)
                .snapshots()
          : null,
      builder: (context, snapshot) {
        DateTime? scheduledTime;

        if (snapshot.hasData &&
            snapshot.data != null &&
            snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final timestamp = data?['scheduledTime'] as Timestamp?;
          if (timestamp != null) {
            scheduledTime = timestamp.toDate();
          }
        }

        final hasMeeting = scheduledTime != null;
        final meetingDate = hasMeeting
            ? DateFormat('MMM d').format(scheduledTime!)
            : 'No meeting decided';
        final meetingTime = hasMeeting
            ? DateFormat('h:mm a').format(scheduledTime!)
            : 'Tap to plan with Beemo';

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NextMeetingScreen(),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFA8E6CF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Next Meeting',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Color(0xFFA8E6CF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return FittedBox(
                        alignment: Alignment.bottomLeft,
                        fit: BoxFit.scaleDown,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                meetingDate,
                                style: hasMeeting
                                    ? const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black,
                                        height: 1.0,
                                      )
                                    : TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black.withOpacity(0.65),
                                        height: 1.15,
                                      ),
                                maxLines: hasMeeting ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                meetingTime,
                                style: hasMeeting
                                    ? const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                        height: 1.1,
                                      )
                                    : TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black.withOpacity(0.6),
                                        height: 1.2,
                                      ),
                                maxLines: hasMeeting ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(String letter, Color color) {
    return Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPollOption(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 11, height: 1.2)),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, height: 1.3)),
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
      child: Center(child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
      ),),
    );
  }

  Widget _buildFloatingNavIcon(IconData icon, bool isActive) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFF1B8D) : Colors.white,
        shape: BoxShape.circle,
        border: isActive ? null : Border.all(color: Colors.black, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isActive ? 0.35 : 0.25),
            blurRadius: isActive ? 16 : 12,
            offset: Offset(0, isActive ? 8 : 6),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: isActive ? Colors.white : Colors.black,
        size: 36,
      ),
    );
  }

  Widget _buildFloatingBeemoNavIcon(bool isActive) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFF1B8D) : Colors.white,
        shape: BoxShape.circle,
        border: isActive ? null : Border.all(color: Colors.black, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isActive ? 0.35 : 0.25),
            blurRadius: isActive ? 16 : 12,
            offset: Offset(0, isActive ? 8 : 6),
          ),
        ],
      ),
      child: Center(child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
      ),),
    );
  }

  Widget _buildStackedAvatar(String letter, Color color, double leftPosition) {
    return Positioned(
      left: leftPosition,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Center(
          child: Text(
            letter,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNeobrutalistChatBubble(String text) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2, right: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, height: 1.3)),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6, right: 6),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black, width: 3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4, right: 4),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4D8D),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.logout,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  const Text(
                    'Sign Out?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Message
                  const Text(
                    'Are you sure you want to sign out\nfrom your account?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Buttons
                  Row(
                    children: [
                      // Cancel Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(
                                bottom: 4,
                                right: 4,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.black,
                                  width: 2.5,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Sign Out Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            Navigator.of(context).pop(); // Close dialog
                            await Provider.of<AuthProvider>(
                              context,
                              listen: false,
                            ).signOut();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(
                                bottom: 4,
                                right: 4,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF4D8D),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.black,
                                  width: 2.5,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Sign Out',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showShareDialog(
    BuildContext context,
    String houseName,
    String houseCode,
  ) {
    if (houseCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No house code available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final inviteUrl = 'beemo://join-house?code=$houseCode';
    final shareText =
        'Join my house "$houseName" on Beemo! Use code: $houseCode';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6, right: 6),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black, width: 3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  const Text(
                    'Invite to House',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // House Name
                  Text(
                    houseName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // QR Code
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    child: QrImageView(
                      data: inviteUrl,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // House Code
                  const Text(
                    'House Code',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2.5),
                    ),
                    child: Text(
                      houseCode,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 2,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Share Button
                  GestureDetector(
                    onTap: () {
                      Share.share(shareText);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4, right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00BCD4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black, width: 2.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.share, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Share Invite',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Close Button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Animated Card Widgets
class _AnimatedMeetingNotesCard extends StatefulWidget {
  @override
  State<_AnimatedMeetingNotesCard> createState() =>
      _AnimatedMeetingNotesCardState();
}

class _AnimatedMeetingNotesCardState extends State<_AnimatedMeetingNotesCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MeetingNotesScreen()),
          );
        }
        if (mounted) {
          setState(() => _isPressed = false);
        }
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 6,
            right: _isPressed ? 0 : 6,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFC400),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: const Align(
            alignment: Alignment.topLeft,
            child: Text(
              'Meeting Notes',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedTasksCard extends StatefulWidget {
  @override
  State<_AnimatedTasksCard> createState() => _AnimatedTasksCardState();
}

class _AnimatedTasksCardState extends State<_AnimatedTasksCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final houseProvider = Provider.of<HouseProvider>(context);
    final userId = authProvider.user?.uid;
    final houseId = houseProvider.currentHouseId;

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TasksScreen()),
          );
        }
        if (mounted) {
          setState(() => _isPressed = false);
        }
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 6,
            right: _isPressed ? 0 : 6,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF00BFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: houseId != null && userId != null
                ? FirebaseFirestore.instance
                      .collection('tasks')
                      .where('houseId', isEqualTo: houseId)
                      .where('assignedTo', isEqualTo: userId)
                      .where(
                        'status',
                        whereIn: ['pending', 'pending_confirmation'],
                      )
                      .orderBy('createdAt', descending: true)
                      .limit(1)
                      .snapshots()
                : null,
            builder: (context, snapshot) {
              String taskText = 'No tasks yet';

              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                final taskData =
                    snapshot.data!.docs.first.data() as Map<String, dynamic>?;
                final status = (taskData?['status'] ?? '')
                    .toString()
                    .toLowerCase();
                final title = (taskData?['title'] ?? 'Task').toString();
                if (status == 'pending_confirmation') {
                  taskText = 'Awaiting confirmation: $title';
                } else {
                  taskText = title;
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tasks',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    taskText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnimatedRecentActivityCard extends StatefulWidget {
  @override
  State<_AnimatedRecentActivityCard> createState() =>
      _AnimatedRecentActivityCardState();
}

class _AnimatedRecentActivityCardState
    extends State<_AnimatedRecentActivityCard> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const RecentActivityScreen(),
            ),
          );
        }
        if (mounted) {
          setState(() => _isPressed = false);
        }
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 6,
            right: _isPressed ? 0 : 6,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFF4D8D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: _buildActivityContent(context),
        ),
      ),
    );
  }

  Widget _buildActivityContent(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final houseId = houseProvider.currentHouseId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: houseId == null
              ? const _ActivityEmptyState(
                  message: 'Join a house to start tracking activity.',
                )
              : StreamBuilder<List<Activity>>(
                  stream: _firestoreService.getActivitiesStream(houseId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      );
                    }

                    final activities = (snapshot.data ?? [])
                        .where(_isRelevantActivity)
                        .toList();

                    if (activities.isEmpty) {
                      return const _ActivityEmptyState(
                        message: 'No activity yet. I\'ll keep you posted!',
                      );
                    }

                    final sections = _groupActivitiesByDay(activities);
                    final widgets = <Widget>[];
                    const int maxRows = 4;
                    int rowCount = 0;

                    for (final entry in sections) {
                      if (entry.activities.isEmpty) continue;
                      widgets.add(
                        Text(
                          entry.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70,
                          ),
                        ),
                      );
                      widgets.add(const SizedBox(height: 6));

                      for (final activity in entry.activities) {
                        if (rowCount >= maxRows) break;
                        widgets.add(_ActivityRow(activity: activity));
                        widgets.add(const SizedBox(height: 10));
                        rowCount++;
                      }

                      if (rowCount >= maxRows) break;
                      widgets.add(const SizedBox(height: 4));
                    }

                    if (widgets.isNotEmpty) {
                      widgets.removeLast();
                    }

                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: widgets,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  bool _isRelevantActivity(Activity activity) {
    switch (activity.type) {
      case 'task_completed':
      case 'task_created':
      case 'task_assigned':
      case 'agenda_created':
        return true;
      default:
        return false;
    }
  }

  List<_ActivitySection> _groupActivitiesByDay(List<Activity> activities) {
    final now = DateTime.now();
    final List<_ActivitySection> sections = [];

    final List<Activity> today = [];
    final List<Activity> yesterday = [];
    final List<Activity> earlier = [];

    for (final activity in activities) {
      final created = activity.createdAt.toLocal();
      final createdDay = DateTime(created.year, created.month, created.day);
      final todayStart = DateTime(now.year, now.month, now.day);
      final difference = todayStart.difference(createdDay).inDays;

      if (difference == 0) {
        today.add(activity);
      } else if (difference == 1) {
        yesterday.add(activity);
      } else {
        earlier.add(activity);
      }
    }

    if (today.isNotEmpty) {
      sections.add(_ActivitySection('Today', today));
    }
    if (yesterday.isNotEmpty) {
      sections.add(_ActivitySection('Yesterday', yesterday));
    }
    if (earlier.isNotEmpty) {
      sections.add(_ActivitySection('Earlier', earlier));
    }

    return sections;
  }
}

class _ActivitySection {
  _ActivitySection(this.label, this.activities);

  final String label;
  final List<Activity> activities;
}

class _ActivityEmptyState extends StatelessWidget {
  const _ActivityEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final _ActivityPresentation presentation = _activityPresentation(activity);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: presentation.color,
            shape: BoxShape.circle,
          ),
          child: presentation.emoji == '🤖'
              ? const Center(child: BeemoLogo(size: 38))
              : presentation.emoji != null
              ? Center(
                  child: Text(
                    presentation.emoji!,
                    style: const TextStyle(fontSize: 14),
                  ),
                )
              : Icon(presentation.icon, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            presentation.message,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              height: 1.3,
            ),
          ),
        ),
        if (presentation.showConfirmChip)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: const Text(
              'Confirm',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
      ],
    );
  }

  _ActivityPresentation _activityPresentation(Activity activity) {
    switch (activity.type) {
      case 'task_completed':
        // Task completion - show who did it and what needs confirmation
        final description = activity.description.isNotEmpty
            ? activity.description
            : 'Task completed - needs confirmation';
        return _ActivityPresentation(
          icon: Icons.check_circle,
          color: const Color(0xFFFF1744),
          message: description,
          showConfirmChip: true,
        );
      case 'task_created':
      case 'task_assigned':
        final taskTitle =
            activity.metadata['taskTitle']?.toString() ?? activity.title;
        final assignedTo =
            activity.metadata['assignedToName']?.toString() ?? '';
        final assignedPhrase = assignedTo.isNotEmpty ? ' → $assignedTo' : '';
        // Check if it's an AI assignment
        final isAIAssignment =
            activity.title.contains('(AI)') ||
            activity.description.contains('Beemo') ||
            activity.createdBy == 'ai_agent';
        return _ActivityPresentation(
          icon: Icons.assignment,
          color: isAIAssignment
              ? const Color(0xFFFFC400)
              : const Color(0xFF6200EA),
          message: 'New task$assignedPhrase: "$taskTitle".',
          emoji: isAIAssignment ? '🤖' : null,
        );
      case 'agenda_created':
        final agendaTitle =
            activity.metadata['agendaTitle']?.toString() ?? activity.title;
        final priority = activity.metadata['priority']?.toString();
        final priorityLabel = priority != null
            ? priority.toUpperCase()
            : 'AGENDA';
        return _ActivityPresentation(
          icon: Icons.event_note,
          color: const Color(0xFFFFC400),
          message: '$priorityLabel agenda added: "$agendaTitle".',
        );
      default:
        return _ActivityPresentation(
          icon: Icons.notifications,
          color: Colors.black,
          message: activity.description.isNotEmpty
              ? activity.description
              : activity.title,
        );
    }
  }
}

class _ActivityPresentation {
  _ActivityPresentation({
    required this.icon,
    required this.color,
    required this.message,
    this.showConfirmChip = false,
    this.emoji, // Optional emoji to show instead of icon
  });

  final IconData icon;
  final Color color;
  final String message;
  final bool showConfirmChip;
  final String? emoji;
}

class _AnimatedNextMeetingCard extends StatefulWidget {
  @override
  State<_AnimatedNextMeetingCard> createState() =>
      _AnimatedNextMeetingCardState();
}

class _AnimatedNextMeetingCardState extends State<_AnimatedNextMeetingCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NextMeetingScreen()),
          );
        }
        if (mounted) {
          setState(() => _isPressed = false);
        }
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 6,
            right: _isPressed ? 0 : 6,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Next Meeting',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  height: 1.0,
                ),
              ),
              Text(
                'Oct 8',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 0.95,
                ),
              ),
              Text(
                '1:00 pm',
                style: TextStyle(fontSize: 14, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
