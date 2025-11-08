import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import '../services/simple_task_detector.dart';
import '../models/chat_message_model.dart';
import '../widgets/beemo_logo.dart';

class _ChatHeaderData {
  const _ChatHeaderData({required this.houseData, required this.memberDocs});

  final Map<String, dynamic>? houseData;
  final List<DocumentSnapshot<Map<String, dynamic>>> memberDocs;
}

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
  bool _isSchedulingMeeting = false;
  bool _isProcessingFollowUp = false;
  bool _autoCheckInEnabled = true;
  bool _isAutoSettingsLoading = true;
  bool _isUpdatingAutoSetting = false;
  DateTime? _lastAutoPromptAt;
  int _autoAssignMinutes = 2; // Default to 2 minutes
  bool _isUpdatingAutoAssignTime = false;
  StreamSubscription<Map<String, dynamic>>? _autoMeetingSettingsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _autoAssignCountdownSubscription;
  Timer? _countdownTimer;
  String? _countdownHouseId;
  final Map<String, DateTime> _assignmentDeadlines = {};
  final Map<String, String> _assignmentCountdowns = {};
  String? _autoCheckInCountdownLabel;
  StateSetter? _meetingAssistantSheetSetState;

  // Track pending task clarification
  String? _pendingClarificationUserId;
  String? _pendingClarificationUserName;
  List<Map<String, dynamic>>? _pendingClarificationTasks;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _scrollToBottom();
      }
    });
    _subscribeToAutoMeetingSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final houseProvider = Provider.of<HouseProvider>(context);
    final newHouseId = houseProvider.currentHouseId;
    if (_countdownHouseId == newHouseId) {
      return;
    }

    _countdownHouseId = newHouseId;
    _autoAssignCountdownSubscription?.cancel();
    _autoAssignCountdownSubscription = null;
    _assignmentDeadlines.clear();
    _assignmentCountdowns.clear();
    _refreshCountdownLabels();

    if (newHouseId != null) {
      _subscribeToTaskAssignmentCountdown(newHouseId);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _autoMeetingSettingsSubscription?.cancel();
    _autoAssignCountdownSubscription?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _refreshMeetingAssistantSheet() {
    final stateSetter = _meetingAssistantSheetSetState;
    if (stateSetter != null) {
      try {
        stateSetter(() {});
      } catch (_) {
        _meetingAssistantSheetSetState = null;
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _fetchMemberDocs(
    Map<String, dynamic>? houseData,
    HouseProvider houseProvider, {
    String? currentUserId,
  }) async {
    final memberIds = _resolveMemberIds(
      houseData,
      houseProvider,
      currentUserId: currentUserId,
    );
    if (memberIds.isEmpty) {
      return [];
    }
    final futures = memberIds.map(
      (memberId) =>
          FirebaseFirestore.instance.collection('users').doc(memberId).get(),
    );
    return Future.wait(futures);
  }

  List<String> _resolveMemberIds(
    Map<String, dynamic>? houseData,
    HouseProvider houseProvider, {
    String? currentUserId,
  }) {
    final ids = <String>{};
    final membersField = houseData?['members'];

    if (membersField is Map) {
      ids.addAll(membersField.keys.map((e) => e.toString()));
    } else if (membersField is List) {
      for (final entry in membersField) {
        if (entry is String) {
          ids.add(entry);
        } else if (entry is Map) {
          final idValue = entry['id']?.toString();
          if (idValue != null && idValue.isNotEmpty) {
            ids.add(idValue);
          }
        }
      }
    }

    final providerMembers = houseProvider.currentHouse?.members;
    if (providerMembers != null) {
      ids.addAll(providerMembers.keys);
    }

    if (currentUserId != null && currentUserId.isNotEmpty) {
      ids.add(currentUserId);
    }

    ids.removeWhere((element) => element.trim().isEmpty);
    return ids.toList();
  }

  List<String> _extractMemberNamesFromDocs(
    List<DocumentSnapshot<Map<String, dynamic>>> docs,
    HouseProvider houseProvider,
  ) {
    final names = <String>{};
    for (final doc in docs) {
      final data = doc.data();
      if (data == null) continue;

      final profile = data['profile'] as Map<String, dynamic>?;
      final candidates = [
        profile?['name'],
        data['displayName'],
        data['name'],
        (data['email'] is String)
            ? (data['email'] as String).split('@').first
            : null,
      ];

      for (final value in candidates) {
        if (value is String && value.trim().isNotEmpty) {
          names.add(value.trim());
          break;
        }
      }
    }

    if (names.isEmpty) {
      final members = houseProvider.currentHouse?.members.values;
      if (members != null) {
        for (final member in members) {
          final name = member.name.trim();
          if (name.isNotEmpty) names.add(name);
        }
      }
    }

    final sorted = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  String _formatMemberNameList(List<String> names) {
    if (names.isEmpty) return 'Beemo';
    if (names.length <= 3) {
      return '${names.join(', ')} & Beemo';
    }
    final displayed = names.take(3).join(', ');
    return '$displayed +${names.length - 3} more & Beemo';
  }

  String _extractHouseName(
    Map<String, dynamic>? houseData,
    HouseProvider houseProvider, {
    String fallback = 'House',
  }) {
    final providerName = houseProvider.currentHouse?.name;
    if (providerName != null && providerName.trim().isNotEmpty) {
      return providerName.trim();
    }

    if (houseData != null) {
      final info = houseData['info'];
      if (info is Map<String, dynamic>) {
        final infoName = info['name'];
        if (infoName is String && infoName.trim().isNotEmpty) {
          return infoName.trim();
        }
      }

      final docName = houseData['houseName'];
      if (docName is String && docName.trim().isNotEmpty) {
        return docName.trim();
      }
    }

    return fallback;
  }

  void _subscribeToAutoMeetingSettings() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final houseProvider = Provider.of<HouseProvider>(context, listen: false);
      final houseId = houseProvider.currentHouseId;
      if (houseId == null) {
        if (mounted) {
          setState(() {
            _isAutoSettingsLoading = false;
          });
        }
        return;
      }

      _autoMeetingSettingsSubscription?.cancel();
      _autoMeetingSettingsSubscription = _firestoreService
          .autoMeetingSettingsStream(houseId)
          .listen((settings) {
            final enabled = settings.containsKey('autoWeeklyCheckInEnabled')
                ? (settings['autoWeeklyCheckInEnabled'] ?? false) == true
                : true;
            final rawLastPrompt = settings['lastAutoPromptAt'];
            DateTime? lastPrompt;
            if (rawLastPrompt is Timestamp) {
              lastPrompt = rawLastPrompt.toDate();
            } else if (rawLastPrompt is DateTime) {
              lastPrompt = rawLastPrompt;
            }

            // Load autoAssignMinutes (defaults to 2)
            final autoAssignMinutes = settings['autoAssignMinutes'] is int
                ? settings['autoAssignMinutes'] as int
                : 2;

            if (mounted) {
              setState(() {
                _autoCheckInEnabled = enabled;
                _lastAutoPromptAt = lastPrompt;
                _autoAssignMinutes = autoAssignMinutes;
                _isAutoSettingsLoading = false;
                _isUpdatingAutoSetting = false;
                _isUpdatingAutoAssignTime = false;
              });
              _refreshMeetingAssistantSheet();
            }

            _maybeTriggerAutoCheckIn();
            _refreshCountdownLabels();
          });
    });
  }

  Future<void> _maybeTriggerAutoCheckIn() async {
    if (!_autoCheckInEnabled) return;

    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;
    if (houseId == null || _isSchedulingMeeting) {
      return;
    }

    final now = DateTime.now();
    // Midweek check-in: Wednesday (3) or Thursday (4)
    if (now.weekday < DateTime.wednesday || now.weekday > DateTime.thursday) {
      return;
    }

    if (_lastAutoPromptAt != null && _isSameWeek(now, _lastAutoPromptAt!)) {
      return;
    }

    final success = await _startWeeklyCheckInMeeting(autoTriggered: true);
    if (success) {
      await _firestoreService.updateAutoMeetingSettings(
        houseId,
        lastPromptAt: DateTime.now(),
      );
    }
  }

  bool _isSameWeek(DateTime a, DateTime b) {
    DateTime startOfWeek(DateTime dt) {
      final normalized = DateTime(dt.year, dt.month, dt.day);
      return normalized.subtract(Duration(days: normalized.weekday - 1));
    }

    final aStart = startOfWeek(a);
    final bStart = startOfWeek(b);
    return aStart.year == bStart.year &&
        aStart.month == bStart.month &&
        aStart.day == bStart.day;
  }

  Future<void> _toggleAutoCheckIn(bool value) async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;
    if (houseId == null) {
      return;
    }

    final previousEnabled = _autoCheckInEnabled;
    if (mounted) {
      setState(() {
        _isUpdatingAutoSetting = true;
        _autoCheckInEnabled = value;
      });
      _refreshMeetingAssistantSheet();
      _refreshCountdownLabels();
    }

    try {
      await _firestoreService.updateAutoMeetingSettings(
        houseId,
        enabled: value,
        clearLastPrompt: value && !previousEnabled,
      );
      _refreshCountdownLabels();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUpdatingAutoSetting = false;
          _autoCheckInEnabled = previousEnabled;
        });
        _refreshMeetingAssistantSheet();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update auto check-in: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      _refreshCountdownLabels();
    }
  }

  Future<bool> _startWeeklyCheckInMeeting({bool autoTriggered = false}) async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    if (houseId == null) {
      return false;
    }

    if (_isSchedulingMeeting) {
      return false;
    }

    if (autoTriggered) {
      _isSchedulingMeeting = true;
    } else {
      setState(() {
        _isSchedulingMeeting = true;
      });
    }

    try {
      await _firestoreService.clearMeetingPlanningSession(houseId);
      final houseDoc = await FirebaseFirestore.instance
          .collection('houses')
          .doc(houseId)
          .get();
      final houseData = houseDoc.data() as Map<String, dynamic>?;
      final houseName = _extractHouseName(
        houseData,
        houseProvider,
        fallback: houseProvider.currentHouse?.name ?? 'our house',
      );

      final members = await _firestoreService.getHouseMembers(houseId);
      final recentMessages = await _firestoreService.fetchRecentChatMessages(
        houseId,
        limit: 20,
      );
      final lastMeeting = await _firestoreService.getNextMeetingTimeOnce(
        houseId,
      );

      final plan = await _aiService.planWeeklyCheckInMeeting(
        houseName: houseName,
        members: members,
        recentMessages: recentMessages,
        lastScheduledTime: lastMeeting,
      );

      if (plan.messages.isEmpty) {
        await _firestoreService.sendBeemoMessage(
          houseId: houseId,
          message:
              'I need a bit more context before I can lock in a time. Share when you\'re free and I\'ll try again!',
        );
      } else {
        for (final message in plan.messages) {
          await _firestoreService.sendBeemoMessage(
            houseId: houseId,
            message: message,
          );
        }
      }

      if (plan.shouldSchedule && plan.scheduledTime != null) {
        final scheduledUtc = plan.scheduledTime!;
        await _firestoreService.scheduleNextMeeting(
          houseId: houseId,
          scheduledTime: scheduledUtc,
          recurring: true,
        );

        final displayTime = scheduledUtc.toLocal();
        final fallbackSummary = DateFormat(
          'EEEE, MMM d • h:mm a',
        ).format(displayTime);
        final summary =
            plan.scheduledSummary ??
            'Weekly check-in penciled in for $fallbackSummary';
        final alreadySummarized = plan.messages.any(
          (m) => plan.scheduledSummary != null
              ? m.toLowerCase().contains(plan.scheduledSummary!.toLowerCase())
              : m.toLowerCase().contains(fallbackSummary.toLowerCase()),
        );
        if (!alreadySummarized) {
          await _firestoreService.sendBeemoMessage(
            houseId: houseId,
            message:
                '$summary. I updated the Next Meeting card—tap it anytime if we need to adjust.',
          );
        }
        await _firestoreService.clearMeetingPlanningSession(houseId);
      } else {
        await _firestoreService.upsertMeetingPlanningSession(houseId, {
          'active': true,
          'mode': 'weekly_check_in',
          'houseName': houseName,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'lastAssistantMessageAt': FieldValue.serverTimestamp(),
        });
      }

      _scrollToBottom();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Beemo hit a snag scheduling the meeting: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    } finally {
      if (autoTriggered) {
        _isSchedulingMeeting = false;
      } else if (mounted) {
        setState(() {
          _isSchedulingMeeting = false;
        });
      }
    }
  }

  Widget _buildAutoMeetingToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.event_repeat,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Auto weekly check-in',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Midweek reminder to confirm the next meeting.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                if (_autoCheckInCountdownLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _autoCheckInCountdownLabel!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_isAutoSettingsLoading || _isUpdatingAutoSetting)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
              ),
            )
          else
            Switch.adaptive(
              value: _autoCheckInEnabled,
              onChanged: (value) => _toggleAutoCheckIn(value),
              activeColor: Colors.black,
              activeTrackColor: const Color(0xFFFFC400),
            ),
        ],
      ),
    );
  }

  Widget _buildAutoAssignTimeSetting() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEF7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.schedule, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Auto-assign time',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'How long to wait before auto-assigning tasks',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_isUpdatingAutoAssignTime)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
              ),
            )
          else
            GestureDetector(
              onTap: () => _showAutoAssignTimeSelector(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC400),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatAutoAssignTime(_autoAssignMinutes),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit, size: 14, color: Colors.black),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatHeaderBar({
    required String title,
    required String subtitle,
    required bool menuEnabled,
    bool subtleMenu = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEC5D),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
          ),
          const SizedBox(width: 12),
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.public, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
          const SizedBox(width: 12),
          _buildMeetingMenuButton(enabled: menuEnabled, subtle: subtleMenu),
        ],
      ),
    );
  }

  Widget _buildMemberAvatarRow(
    List<DocumentSnapshot<Map<String, dynamic>>> memberDocs,
  ) {
    final avatarWidgets = <Widget>[];
    final seenIds = <String>{};
    var index = 0;

    for (final doc in memberDocs) {
      if (!doc.exists) continue;
      if (!seenIds.add(doc.id)) continue;
      if (index >= 5) break;

      final data = doc.data();
      final profile = data?['profile'] as Map<String, dynamic>?;
      final avatarEmoji = profile?['avatarEmoji']?.toString() ?? '?';
      final avatarColorValue = profile?['avatarColor'];

      Color color = const Color(0xFFFF4D6D);
      if (avatarColorValue is int) {
        color = Color(avatarColorValue);
      }

      avatarWidgets.add(
        Positioned(
          left: index * 14.0,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Center(
              child: Text(avatarEmoji, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
      );
      index++;
    }

    avatarWidgets.add(
      Positioned(left: index * 14.0, child: _buildBeemoAvatar()),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: SizedBox(height: 24, child: Stack(children: avatarWidgets)),
    );
  }

  Widget _buildMeetingMenuButton({required bool enabled, bool subtle = false}) {
    final effectiveEnabled =
        enabled && !_isUpdatingAutoSetting && !_isAutoSettingsLoading;
    final outerColor = subtle ? Colors.black12 : Colors.black;
    final innerBorderColor = subtle ? Colors.black26 : Colors.black;
    final iconColor = subtle ? Colors.black45 : Colors.black;
    final opacity = effectiveEnabled ? 1.0 : 0.6;

    return GestureDetector(
      onTap: effectiveEnabled ? _showAutoMeetingMenu : null,
      child: Opacity(
        opacity: opacity,
        child: Container(
          decoration: BoxDecoration(
            color: outerColor,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: innerBorderColor, width: 2),
            ),
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.more_horiz, color: iconColor, size: 18),
          ),
        ),
      ),
    );
  }

  void _showAutoMeetingMenu() {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    if (houseProvider.currentHouseId == null) {
      return;
    }

    if (_isAutoSettingsLoading) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            _meetingAssistantSheetSetState = modalSetState;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Meeting assistant',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildAutoMeetingToggle(),
                            const SizedBox(height: 12),
                            _buildAutoAssignTimeSetting(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _meetingAssistantSheetSetState = null;
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (houseProvider.currentHouseId == null || authProvider.user == null) {
      return;
    }

    final userName =
        authProvider.user?.displayName ??
        authProvider.user?.email?.split('@')[0] ??
        'User';

    // Get user initials for avatar
    final initials = userName
        .split(' ')
        .map((n) => n.isNotEmpty ? n[0] : '')
        .take(2)
        .join();

    // Use a color based on user ID hash
    final colors = [
      const Color(0xFFFF3B79),
      const Color(0xFF63BDA4),
      const Color(0xFF16A3D0),
      const Color(0xFFFF4D8D),
    ];
    final colorIndex = authProvider.user!.uid.hashCode % colors.length;
    final userColor = colors[colorIndex].value
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2);

    final messageText = _messageController.text.trim();

    // Send the message
    await _firestoreService.sendMessage(
      houseId: houseProvider.currentHouseId!,
      message: messageText,
      senderName: userName,
      senderAvatar: initials,
      senderColor: '#$userColor',
    );

    final handledByAssignmentFlow = await _processAssignmentReply(
      messageText,
      authProvider.user!.uid,
      userName,
      houseProvider.currentHouseId!,
    );

    _messageController.clear();
    _scrollToBottom();
    unawaited(_processMeetingAssistantFollowUp());

    // AI-powered task detection
    // Skip detection when Beemo already processed this message for assignments.
    if (!handledByAssignmentFlow) {
      _analyzeMessageForTask(
        messageText,
        authProvider.user!.uid,
        userName,
        houseProvider.currentHouseId!,
      );
    }
  }

  Future<void> _analyzeMessageForTask(
    String message,
    String senderId,
    String senderName,
    String houseId,
  ) async {
    try {
      final lower = message.toLowerCase().trim();
      if (_isVolunteerMessage(lower) ||
          _isAssignCommand(lower) ||
          _isAffirmativeMessage(lower) ||
          _isNegativeMessage(lower) ||
          _isPassMessage(lower)) {
        return;
      }

      // Get house members for context
      final members = await _firestoreService.getHouseMembers(houseId);

      // STRATEGY: Try simple detection first (works immediately without API)
      // Then try AI detection as fallback

      // Try simple pattern-based detection (no API required)
      final simpleTask = SimpleTaskDetector.detectTask(message, members);

      if (simpleTask != null && simpleTask.isTask) {
        final title = (simpleTask.title ?? message).trim();
        final description = (simpleTask.description?.trim().isNotEmpty ?? false)
            ? simpleTask.description!.trim()
            : message;

        try {
          print(
            '🎯 [chat_screen] Starting task session from simple detection: "$title"',
          );
          await _firestoreService.startChatTaskSession(
            houseId: houseId,
            title: title.isNotEmpty ? title : 'Task',
            description: description,
            sourceMessage: message,
            requestedById: senderId,
            requestedByName: senderName,
          );
          print(
            '✅ [chat_screen] Task session queued via simple detection: $title',
          );
        } catch (sessionError) {
          print('❌ [chat_screen] FAILED to create task session: $sessionError');
        }
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
          final title = detectedTask.title!.trim();
          final description = detectedTask.description!.trim();

          try {
            print(
              '🎯 [chat_screen] Starting task session from AI detection: "$title"',
            );
            await _firestoreService.startChatTaskSession(
              houseId: houseId,
              title: title.isNotEmpty ? title : 'Task',
              description: description.isNotEmpty ? description : message,
              sourceMessage: message,
              requestedById: senderId,
              requestedByName: senderName,
            );
            print(
              '✅ [chat_screen] Task session queued via AI detection: $title',
            );
          } catch (sessionError) {
            print(
              '❌ [chat_screen] FAILED to create task session from AI: $sessionError',
            );
          }
        }
      } catch (aiError) {
        print(
          '⚠️  [chat_screen] AI detection failed (API might not be enabled): $aiError',
        );
        // This is OK - simple detection already ran above
      }
    } catch (e, stackTrace) {
      // Log detailed error - important for debugging
      print('❌ [chat_screen] Error analyzing message for task: $e');
      print('📚 [chat_screen] Stack trace: $stackTrace');
    }
  }

  Future<bool> _processAssignmentReply(
    String message,
    String senderId,
    String senderName,
    String houseId,
  ) async {
    final lowerMessage = message.toLowerCase().trim();

    try {
      print('🔄 Processing assignment reply: "$message" from $senderName');

      // First check if we're waiting for a clarification from this user
      if (_pendingClarificationUserId == senderId &&
          _pendingClarificationTasks != null) {
        print('🔍 User is responding to clarification request');
        return await _handleClarificationResponse(
          message,
          senderId,
          senderName,
          houseId,
        );
      }

      // Check if user is volunteering
      if (_isVolunteerMessage(lowerMessage)) {
        print('🙋 Recognized as volunteer message!');

        // Get ALL active sessions to check for ambiguity
        final allSessions = await _firestoreService
            .getAllActiveTaskAssignmentSessions(houseId);

        if (allSessions.isEmpty) {
          print('⚠️  No active assignment sessions found');
          return false;
        }

        if (allSessions.length == 1) {
          // Only one task, assign directly
          print('✅ Only one active task, assigning directly');
          await _firestoreService.finalizeAssignmentFromVolunteer(
            houseId: houseId,
            sessionData: allSessions.first,
            volunteerId: senderId,
            volunteerName: senderName,
          );
          return true;
        }

        // Multiple tasks - check if message specifies which one
        final matchedTask = _findMatchingTask(message, allSessions);

        if (matchedTask != null) {
          // User's message clearly matches one specific task
          print('✅ Message matches specific task: ${matchedTask['taskTitle']}');
          await _firestoreService.finalizeAssignmentFromVolunteer(
            houseId: houseId,
            sessionData: matchedTask,
            volunteerId: senderId,
            volunteerName: senderName,
          );
          return true;
        }

        // Ambiguous - ask for clarification
        print('❓ Multiple tasks available, asking for clarification');
        await _askForTaskClarification(
          allSessions,
          senderId,
          senderName,
          houseId,
        );
        return true;
      }

      // Check for other command patterns
      final session = await _firestoreService.getActiveTaskAssignmentSession(
        houseId,
      );
      if (session == null) {
        print('⚠️  No active assignment session found');
        return false;
      }

      print('✅ Found active assignment session: ${session['id']}');

      final sessionId = session['id']?.toString();
      final status = session['status']?.toString() ?? '';
      if (sessionId == null || sessionId.isEmpty) {
        print('⚠️  Session ID is null or empty');
        return false;
      }

      print('📋 Session status: $status');

      if (_isAssignCommand(lowerMessage)) {
        await _firestoreService.proposeFairAssignment(
          houseId: houseId,
          sessionData: session,
        );
        return true;
      }

      if (status == 'awaiting_confirmation') {
        if (_isAffirmativeMessage(lowerMessage)) {
          await _firestoreService.finalizeProposedAssignment(
            houseId: houseId,
            sessionData: session,
          );
          return true;
        }

        if (_isNegativeMessage(lowerMessage)) {
          await _firestoreService.resetAssignmentSession(
            houseId: houseId,
            sessionId: sessionId,
          );
          await _firestoreService.sendBeemoMessage(
            houseId: houseId,
            message:
                'Okay! I\'ll keep this open for volunteers. Say \"Beemo assign\" when you want me to pick someone again.',
          );
          return true;
        }
      } else {
        if (_isPassMessage(lowerMessage)) {
          await _firestoreService.recordAssignmentPass(
            houseId: houseId,
            sessionId: sessionId,
            userId: senderId,
          );
          return true;
        }
      }
    } catch (e) {
      print('Error processing assignment reply: $e');
    }

    return false;
  }

  Future<void> _processMeetingAssistantFollowUp() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    if (houseId == null || _isProcessingFollowUp) {
      return;
    }

    final session = await _firestoreService.getMeetingPlanningSession(houseId);
    if (session == null || session['active'] != true) {
      return;
    }
    if ((session['mode'] ?? 'weekly_check_in') != 'weekly_check_in') {
      return;
    }

    _isProcessingFollowUp = true;
    try {
      String houseName = session['houseName']?.toString() ?? 'our house';
      if (houseName == 'our house') {
        final houseDoc = await FirebaseFirestore.instance
            .collection('houses')
            .doc(houseId)
            .get();
        houseName = houseDoc.data()?['houseName']?.toString() ?? houseName;
      }

      final members = await _firestoreService.getHouseMembers(houseId);
      final conversation = await _firestoreService.fetchRecentChatMessages(
        houseId,
        limit: 40,
      );
      final lastMeeting = await _firestoreService.getNextMeetingTimeOnce(
        houseId,
      );

      final plan = await _aiService.followUpWeeklyCheckIn(
        houseName: houseName,
        members: members,
        recentMessages: conversation,
        lastScheduledTime: lastMeeting,
      );

      if (plan.messages.isEmpty && !plan.shouldSchedule) {
        await _firestoreService.upsertMeetingPlanningSession(houseId, {
          'active': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      for (final message in plan.messages) {
        await _firestoreService.sendBeemoMessage(
          houseId: houseId,
          message: message,
        );
      }

      if (plan.shouldSchedule && plan.scheduledTime != null) {
        final scheduledUtc = plan.scheduledTime!;
        await _firestoreService.scheduleNextMeeting(
          houseId: houseId,
          scheduledTime: scheduledUtc,
          recurring: true,
        );

        final displayTime = scheduledUtc.toLocal();
        final fallbackSummary = DateFormat(
          'EEEE, MMM d • h:mm a',
        ).format(displayTime);
        final summary =
            plan.scheduledSummary ??
            '**Weekly check-in** locked for $fallbackSummary.';
        final alreadySummarized = plan.messages.any(
          (m) => plan.scheduledSummary != null
              ? m.toLowerCase().contains(plan.scheduledSummary!.toLowerCase())
              : m.toLowerCase().contains(fallbackSummary.toLowerCase()),
        );
        if (!alreadySummarized) {
          await _firestoreService.sendBeemoMessage(
            houseId: houseId,
            message: summary,
          );
        }
        await _firestoreService.clearMeetingPlanningSession(houseId);
      } else {
        final updateData = <String, dynamic>{
          'active': true,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (plan.messages.isNotEmpty) {
          updateData['lastAssistantMessageAt'] = FieldValue.serverTimestamp();
        }
        await _firestoreService.upsertMeetingPlanningSession(
          houseId,
          updateData,
        );
      }

      _scrollToBottom();
    } catch (e) {
      debugPrint('Beemo follow-up failed: $e');
    } finally {
      _isProcessingFollowUp = false;
    }
  }

  bool _isVolunteerMessage(String message) {
    final trimmed = message.trim().toLowerCase();

    // Log the message being checked
    print(
      '🔍 Checking if volunteer message: "$message" (normalized: "$trimmed")',
    );

    // Quick prefix checks - these are the most common patterns
    final prefixes = [
      'i can ',
      'i will ',
      'ill ',
      "i'll ",
      'i got ',
      "i'm on it",
      'im on it',
    ];

    for (final prefix in prefixes) {
      if (trimmed.startsWith(prefix)) {
        print('✅ Matched prefix: "$prefix"');
        return true;
      }
    }

    // More comprehensive phrase matching with flexible word boundaries
    // This handles variations like "I will take that task", "I'll take it", etc.
    final volunteerPhrases = [
      // Take variations
      'i\'ll take',
      'ill take',
      'i will take',
      'i can take',
      'let me take',
      'i got the', // "i got the task", "i got the sofa"
      // Do variations
      'i can do',
      'i will do',
      'i\'ll do',
      'ill do',
      'let me do',

      // Help/Handle variations
      'i can help',
      'i will help',
      'i can handle',
      'i will handle',
      'i\'ll handle',
      'ill handle',
      'let me handle',

      // Grab variations
      'i\'ll grab',
      'ill grab',
      'i will grab',
      'i can grab',

      // Cover variations (for "can you cover")
      'i\'ll cover',
      'ill cover',
      'i will cover',
      'i can cover',

      // Direct affirmations
      'i got it',
      'i got this',
      'count me in',
      'i volunteer',
      'i\'m in',
      'im in',
      'sign me up',
      'put me down',
    ];

    for (final phrase in volunteerPhrases) {
      if (trimmed.contains(phrase)) {
        print('✅ Matched phrase: "$phrase"');
        return true;
      }
    }

    print('❌ Not recognized as volunteer message');
    return false;
  }

  bool _isAssignCommand(String message) {
    return _containsAnyPhrase(message, [
      'beemo assign',
      'beemo decide',
      'beemo choose',
      'beemo pick',
      'beemo handle it',
    ]);
  }

  bool _isAffirmativeMessage(String message) {
    return _containsAnyWord(message, [
          'yes',
          'yep',
          'sure',
          'ok',
          'okay',
          'yup',
        ]) ||
        _containsAnyPhrase(message, [
          'sounds good',
          'go for it',
          'works for me',
          'all good',
        ]);
  }

  bool _isNegativeMessage(String message) {
    return _containsAnyWord(message, ['no', 'nah', 'wait']) ||
        _containsAnyPhrase(message, [
          'hold on',
          'not yet',
          'someone else',
          'maybe later',
        ]);
  }

  bool _isPassMessage(String message) {
    return _containsAnyWord(message, ['pass']) ||
        _containsAnyPhrase(message, [
          'not me',
          'cant',
          'can\'t',
          'cannot',
          'too busy',
          'someone else should',
        ]);
  }

  bool _containsAnyPhrase(String message, List<String> phrases) {
    for (final phrase in phrases) {
      if (message.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  bool _containsAnyWord(String message, List<String> words) {
    for (final word in words) {
      final pattern = RegExp('\\b${RegExp.escape(word)}\\b');
      if (pattern.hasMatch(message)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final houseId = houseProvider.currentHouseId;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    final Stream<_ChatHeaderData>? headerStream = houseId != null
        ? FirebaseFirestore.instance
              .collection('houses')
              .doc(houseId)
              .snapshots()
              .asyncMap((houseDoc) async {
                final houseData = houseDoc.data() as Map<String, dynamic>?;
                final memberDocs = await _fetchMemberDocs(
                  houseData,
                  houseProvider,
                  currentUserId: currentUserId,
                );
                return _ChatHeaderData(
                  houseData: houseData,
                  memberDocs: memberDocs,
                );
              })
        : null;

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
                if (headerStream != null)
                  StreamBuilder<_ChatHeaderData>(
                    stream: headerStream,
                    builder: (context, snapshot) {
                      final headerInfo = snapshot.data;
                      final houseData = headerInfo?.houseData;
                      final memberDocs =
                          headerInfo?.memberDocs ??
                          const <DocumentSnapshot<Map<String, dynamic>>>[];
                      final houseName = _extractHouseName(
                        houseData,
                        houseProvider,
                        fallback: 'Group Chat',
                      );
                      final memberNames = _extractMemberNamesFromDocs(
                        memberDocs,
                        houseProvider,
                      );
                      final subtitle = memberNames.isNotEmpty
                          ? _formatMemberNameList(memberNames)
                          : (snapshot.connectionState == ConnectionState.waiting
                                ? 'Loading members...'
                                : 'Beemo');

                      return Column(
                        children: [
                          _buildChatHeaderBar(
                            title: houseName,
                            subtitle: subtitle,
                            menuEnabled: !_isAutoSettingsLoading,
                          ),
                          _buildMemberAvatarRow(memberDocs),
                        ],
                      );
                    },
                  )
                else
                  Column(
                    children: [
                      _buildChatHeaderBar(
                        title: 'Group Chat',
                        subtitle: 'Beemo',
                        menuEnabled: false,
                        subtleMenu: true,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: SizedBox(
                          height: 24,
                          child: Stack(
                            children: [
                              Positioned(left: 0, child: _buildBeemoAvatar()),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                        stream: _firestoreService.getChatMessagesStream(
                          houseProvider.currentHouseId!,
                        ),
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
                          final authProvider = Provider.of<AuthProvider>(
                            context,
                          );
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
                              final isCurrentUser =
                                  message.senderId == currentUserId;
                              final isBeemo = message.isBeemo;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildMessageWidget(
                                  message,
                                  isCurrentUser,
                                  isBeemo,
                                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
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

  Widget _buildMessageWidget(
    ChatMessage message,
    bool isCurrentUser,
    bool isBeemo,
  ) {
    if (isBeemo && message.messageType == 'poll') {
      return _buildFirebasePoll(message);
    } else if (isBeemo) {
      return _buildBeemoMessage(message);
    } else if (isCurrentUser) {
      return _buildRightAlignedMessage(message.message);
    } else {
      // Parse color from hex string
      Color avatarColor;
      try {
        avatarColor = Color(
          int.parse(message.senderColor.replaceFirst('#', '0xFF')),
        );
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

  Widget _buildAvatar(
    String letter,
    Color color, {
    Color textColor = Colors.white,
  }) {
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
     child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
      ),
    );
  }

  Widget _buildBeemoMessage(ChatMessage message) {
    // Show countdown ONLY below the specific message that asks about the task
    final sessionId = message.metadata?['assignmentSessionId']?.toString();
    final countdownLabel = sessionId != null
        ? _assignmentCountdowns[sessionId]
        : null;

    // Check if task has been assigned
    final taskAssigned = message.metadata?['taskAssigned'] == true;
    final assignedToName = message.metadata?['assignedToName']?.toString();

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
          child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
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
                MarkdownBody(
                  data: message.message,
                  shrinkWrap: true,
                  softLineBreak: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(
                        p: const TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                          height: 1.35,
                        ),
                        strong: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                        listBullet: const TextStyle(
                          fontSize: 13,
                          color: Colors.black,
                        ),
                      ),
                ),
                if (taskAssigned && assignedToName != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 2, right: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF63BDA4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Color(0xFF63BDA4),
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Task Assigned to $assignedToName',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (countdownLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    countdownLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _buildUserMessage(
    String avatar,
    String name,
    String text,
    Color avatarColor, {
    Color textColor = Colors.white,
  }) {
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
         child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
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
                  style: const TextStyle(fontSize: 14, color: Colors.black),
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
                              color: option.votes.isNotEmpty
                                  ? const Color(0xFFFFC400)
                                  : Colors.black,
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
         child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
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
                  style: TextStyle(fontSize: 14, color: Colors.black),
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
        Text(text, style: const TextStyle(fontSize: 14, color: Colors.black)),
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
            style: const TextStyle(fontSize: 14, color: Colors.black),
          ),
        ),
      ],
    );
  }

  void _subscribeToTaskAssignmentCountdown(String houseId) {
    _autoAssignCountdownSubscription?.cancel();
    _autoAssignCountdownSubscription = FirebaseFirestore.instance
        .collection('houses')
        .doc(houseId)
        .collection('taskAssignmentSessions')
        .where('status', isEqualTo: 'awaiting_volunteers')
        .orderBy('autoAssignAt')
        .snapshots()
        .listen((snapshot) {
          final newDeadlines = <String, DateTime>{};
          final now = DateTime.now();

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final sourceType = data['sourceType']?.toString() ?? '';

            // Only track chat and agenda items (not other sourceTypes)
            if (sourceType != 'chat' && sourceType != 'agenda') {
              continue;
            }

            final autoAssignAt = data['autoAssignAt'];
            DateTime? deadline;
            if (autoAssignAt is Timestamp) {
              deadline = autoAssignAt.toDate();
            } else if (autoAssignAt is DateTime) {
              deadline = autoAssignAt;
            }
            if (deadline != null) {
              newDeadlines[doc.id] = deadline;

              // Trigger auto-assignment if deadline has passed
              if (deadline.isBefore(now) || deadline.isAtSameMomentAs(now)) {
                _triggerAutoAssignment(houseId);
              }
            }
          }

          _assignmentDeadlines
            ..clear()
            ..addAll(newDeadlines);
          _refreshCountdownLabels();
        });
  }

  Future<void> _triggerAutoAssignment(String houseId) async {
    print('DEBUG [ChatScreen]: Triggering auto-assignment for house $houseId');
    try {
      await _firestoreService.maybeAutoAssignChatSessions(houseId);
      print('DEBUG [ChatScreen]: Auto-assignment completed successfully');
    } catch (e, stackTrace) {
      print('DEBUG [ChatScreen]: Error triggering auto-assignment: $e');
      print('DEBUG [ChatScreen]: Stack trace: $stackTrace');
    }
  }

  DateTime? _computeNextAutoCheckInTarget(DateTime now) {
    if (!_autoCheckInEnabled) {
      return null;
    }

    final triggeredThisWeek =
        _lastAutoPromptAt != null && _isSameWeek(now, _lastAutoPromptAt!);

    final inWindow =
        now.weekday >= DateTime.wednesday &&
        now.weekday <= DateTime.thursday &&
        !triggeredThisWeek;
    if (inWindow) {
      return now;
    }

    // If triggered this week, next check is midweek of NEXT week (7 days from last trigger)
    if (triggeredThisWeek && _lastAutoPromptAt != null) {
      // Simple: add 7 days to the last prompt to get next week's midweek
      return _lastAutoPromptAt!.add(const Duration(days: 7));
    }

    // Otherwise, find the next Wednesday (midweek)
    final normalized = DateTime(now.year, now.month, now.day);
    const int daysPerWeek = 7;
    int daysToAdd = (DateTime.wednesday - normalized.weekday) % daysPerWeek;

    // If we're already past Wednesday this week, go to next week's Wednesday
    if (daysToAdd <= 0) {
      daysToAdd += daysPerWeek;
    }

    final candidate = normalized.add(Duration(days: daysToAdd));
    DateTime target = DateTime(
      candidate.year,
      candidate.month,
      candidate.day,
      10,
    );

    // Safety check: if target is in the past, move to next week
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 7));
    }

    return target;
  }

  String _formatAutoAssignTime(int minutes) {
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      return '${hours}h';
    }
    return '${minutes}m';
  }

  Future<void> _showAutoAssignTimeSelector() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;
    if (houseId == null) return;

    final options = [
      {'value': 2, 'label': '2 minutes'},
      {'value': 5, 'label': '5 minutes'},
      {'value': 10, 'label': '10 minutes'},
      {'value': 15, 'label': '15 minutes'},
      {'value': 30, 'label': '30 minutes'},
      {'value': 60, 'label': '1 hour'},
      {'value': 120, 'label': '2 hours'},
    ];

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFFEF7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Auto-assign time limit',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...options.map((option) {
              final value = option['value'] as int;
              final label = option['label'] as String;
              final isSelected = value == _autoAssignMinutes;

              return InkWell(
                onTap: () async {
                  Navigator.pop(context);
                  await _updateAutoAssignTime(value);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFFC400).withOpacity(0.2)
                        : Colors.transparent,
                    border: Border(
                      top: BorderSide(
                        color: Colors.black.withOpacity(0.05),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC400),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.black,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _updateAutoAssignTime(int minutes) async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;
    if (houseId == null) return;

    // Store previous value for rollback on error
    final previousMinutes = _autoAssignMinutes;

    // Optimistically update UI immediately
    setState(() {
      _autoAssignMinutes = minutes;
      _isUpdatingAutoAssignTime = true;
    });
    _refreshMeetingAssistantSheet();

    try {
      await _firestoreService.updateAutoMeetingSettings(
        houseId,
        autoAssignMinutes: minutes,
      );

      // Success - update completes via Firestore stream
      if (mounted) {
        setState(() {
          _isUpdatingAutoAssignTime = false;
        });
        _refreshMeetingAssistantSheet();
      }
    } catch (e) {
      // Revert to previous value on error
      if (mounted) {
        setState(() {
          _autoAssignMinutes = previousMinutes;
          _isUpdatingAutoAssignTime = false;
        });
        _refreshMeetingAssistantSheet();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update auto-assign time: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    if (totalSeconds <= 0) {
      return '0m';
    }

    final totalMinutes = duration.inMinutes;
    final days = totalMinutes ~/ (24 * 60);
    final hours = (totalMinutes % (24 * 60)) ~/ 60;
    final minutes = totalMinutes % 60;

    final parts = <String>[];
    if (days > 0) {
      parts.add('${days}d');
    }
    if (hours > 0 && parts.length < 2) {
      parts.add('${hours}h');
    }
    if (minutes > 0 && parts.length < 2) {
      parts.add('${minutes}m');
    }
    if (parts.isEmpty) {
      parts.add('less than 1m');
    }
    return parts.join(' ');
  }

  void _refreshCountdownLabels() {
    if (!mounted) return;

    final now = DateTime.now();
    final newAssignmentLabels = <String, String>{};
    _assignmentDeadlines.forEach((sessionId, deadline) {
      final diff = deadline.difference(now);
      final label = diff <= const Duration(seconds: 30)
          ? 'Auto-assigning now'
          : 'Auto-assigns in ${_formatDuration(diff)}';
      newAssignmentLabels[sessionId] = label;
    });

    String? checkLabel;
    if (_autoCheckInEnabled) {
      final target = _computeNextAutoCheckInTarget(now);
      if (target != null) {
        final diff = target.difference(now);
        checkLabel = diff <= const Duration(seconds: 30)
            ? 'Auto check-in running now'
            : 'Auto check-in in ${_formatDuration(diff)}';
      }
    }

    final shouldRunTimer =
        newAssignmentLabels.isNotEmpty ||
        (checkLabel != null && checkLabel != 'Auto check-in running now');
    if (shouldRunTimer) {
      _countdownTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refreshCountdownLabels(),
      );
    } else {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }

    final assignmentsChanged =
        newAssignmentLabels.length != _assignmentCountdowns.length ||
        newAssignmentLabels.entries.any(
          (entry) => _assignmentCountdowns[entry.key] != entry.value,
        );

    if (assignmentsChanged || checkLabel != _autoCheckInCountdownLabel) {
      setState(() {
        _assignmentCountdowns
          ..clear()
          ..addAll(newAssignmentLabels);
        _autoCheckInCountdownLabel = checkLabel;
      });
      _refreshMeetingAssistantSheet();
    }
  }

  /// Tries to find a task that matches the user's message
  /// Returns the matched task or null if ambiguous
  Map<String, dynamic>? _findMatchingTask(
    String message,
    List<Map<String, dynamic>> tasks,
  ) {
    final lowerMessage = message.toLowerCase().trim();

    // Extract keywords from the message (remove volunteer phrases)
    String cleanedMessage = lowerMessage;
    for (final phrase in [
      "i'll take",
      "ill take",
      "i can do",
      "i will do",
      "i'll do",
      "ill do",
    ]) {
      cleanedMessage = cleanedMessage.replaceAll(phrase, '').trim();
    }

    // Try to match against task titles
    Map<String, dynamic>? bestMatch;
    int bestMatchScore = 0;

    for (final task in tasks) {
      final taskTitle = (task['taskTitle']?.toString() ?? '').toLowerCase();
      final taskDescription = (task['taskDescription']?.toString() ?? '')
          .toLowerCase();

      // Calculate match score
      int score = 0;

      // Check if message contains significant words from the task title
      final taskWords = taskTitle
          .split(' ')
          .where((w) => w.length > 3)
          .toList();
      for (final word in taskWords) {
        if (cleanedMessage.contains(word)) {
          score += 2; // Title matches are weighted higher
        }
      }

      // Check description too
      final descWords = taskDescription
          .split(' ')
          .where((w) => w.length > 3)
          .toList();
      for (final word in descWords) {
        if (cleanedMessage.contains(word)) {
          score += 1;
        }
      }

      if (score > bestMatchScore) {
        bestMatchScore = score;
        bestMatch = task;
      }
    }

    // Only return a match if the score is high enough (at least 2 matching words)
    if (bestMatchScore >= 2) {
      return bestMatch;
    }

    return null;
  }

  /// Asks the user to clarify which task they want to volunteer for
  Future<void> _askForTaskClarification(
    List<Map<String, dynamic>> tasks,
    String userId,
    String userName,
    String houseId,
  ) async {
    // Store the clarification state
    setState(() {
      _pendingClarificationUserId = userId;
      _pendingClarificationUserName = userName;
      _pendingClarificationTasks = tasks;
    });

    // Build the clarification message
    final taskList = tasks
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key + 1;
          final task = entry.value;
          final title = task['taskTitle']?.toString() ?? 'Unknown task';
          return '$index. **$title**';
        })
        .join('\n');

    final message =
        'Hey **$userName**, I see you want to help! '
        'There are ${tasks.length} unassigned tasks right now:\n\n'
        '$taskList\n\n'
        'Which one would you like to take? Just reply with the task name or number.';

    await _firestoreService.sendBeemoMessage(
      houseId: houseId,
      message: message,
    );

    // Clear clarification after 5 minutes
    Future.delayed(const Duration(minutes: 5), () {
      if (mounted && _pendingClarificationUserId == userId) {
        setState(() {
          _pendingClarificationUserId = null;
          _pendingClarificationUserName = null;
          _pendingClarificationTasks = null;
        });
      }
    });
  }

  /// Handles the user's response to a clarification request
  Future<bool> _handleClarificationResponse(
    String message,
    String userId,
    String userName,
    String houseId,
  ) async {
    final tasks = _pendingClarificationTasks;
    if (tasks == null || tasks.isEmpty) {
      return false;
    }

    final lowerMessage = message.toLowerCase().trim();
    Map<String, dynamic>? selectedTask;

    // Try to parse as a number first (e.g., "1", "2", etc.)
    final numberMatch = RegExp(r'^\d+$').firstMatch(lowerMessage);
    if (numberMatch != null) {
      final taskNumber = int.tryParse(lowerMessage);
      if (taskNumber != null && taskNumber > 0 && taskNumber <= tasks.length) {
        selectedTask = tasks[taskNumber - 1];
      }
    }

    // If not a number, try to match by task title
    if (selectedTask == null) {
      for (final task in tasks) {
        final taskTitle = (task['taskTitle']?.toString() ?? '').toLowerCase();
        final taskDescription = (task['taskDescription']?.toString() ?? '')
            .toLowerCase();

        // Check if message contains key words from the task
        final taskWords = taskTitle
            .split(' ')
            .where((w) => w.length > 3)
            .toList();
        bool matches = taskWords.any((word) => lowerMessage.contains(word));

        if (!matches) {
          final descWords = taskDescription
              .split(' ')
              .where((w) => w.length > 3)
              .toList();
          matches = descWords.any((word) => lowerMessage.contains(word));
        }

        if (matches) {
          selectedTask = task;
          break;
        }
      }
    }

    // Clear the pending clarification
    setState(() {
      _pendingClarificationUserId = null;
      _pendingClarificationUserName = null;
      _pendingClarificationTasks = null;
    });

    if (selectedTask != null) {
      // Assign the task
      print('✅ User selected task: ${selectedTask['taskTitle']}');
      await _firestoreService.finalizeAssignmentFromVolunteer(
        houseId: houseId,
        sessionData: selectedTask,
        volunteerId: userId,
        volunteerName: userName,
      );
      return true;
    } else {
      // Could not determine which task they meant
      await _firestoreService.sendBeemoMessage(
        houseId: houseId,
        message:
            "I'm not sure which task you mean, **$userName**. Can you try again? "
            "Reply with the task number (like '1' or '2') or the full task name.",
      );

      // Re-ask for clarification
      await _askForTaskClarification(tasks, userId, userName, houseId);
      return true;
    }
  }
}
