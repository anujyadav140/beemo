import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'add_agenda_screen.dart';
import 'agenda_detail_screen.dart';
import 'package:intl/intl.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/agenda_item_model.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late DateTime _today;
  late List<DateTime> _weekDates;
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _generateWeekDates();
  }

  void _generateWeekDates() {
    _weekDates = [];
    // Generate 7 days centered around today
    for (int i = -3; i <= 3; i++) {
      _weekDates.add(_today.add(Duration(days: i)));
    }
  }

  String _getDayName(DateTime date) {
    return DateFormat('EEE').format(date); // Mon, Tue, Wed, etc.
  }

  String _getMonthAndDay(DateTime date) {
    return DateFormat('MMM d').format(date); // Oct 8, Oct 9, etc.
  }

  bool _isToday(DateTime date) {
    return date.year == _today.year &&
        date.month == _today.month &&
        date.day == _today.day;
  }

  bool _isUpcomingMeeting(DateTime date) {
    // Example: Oct 13 is highlighted
    return date.day == 13 && date.month == 10;
  }

  bool _isThisWeek(DateTime date) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return date.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
           date.isBefore(endOfWeek.add(const Duration(days: 1)));
  }

  bool _isLastWeek(DateTime date) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final startOfLastWeek = startOfWeek.subtract(const Duration(days: 7));
    final endOfLastWeek = startOfWeek.subtract(const Duration(days: 1));
    return date.isAfter(startOfLastWeek.subtract(const Duration(days: 1))) &&
           date.isBefore(endOfLastWeek.add(const Duration(days: 1)));
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'meeting':
        return const Color(0xFFFF4D8D);
      case 'chat':
        return const Color(0xFF63BDA4);
      case 'flexible':
        return const Color(0xFFFFC400);
      default:
        return const Color(0xFF4A4A4A);
    }
  }

  String _getPriorityLabel(String priority) {
    switch (priority) {
      case 'meeting':
        return 'Meeting';
      case 'chat':
        return 'Chat';
      case 'flexible':
        return 'Flexible';
      default:
        return priority;
    }
  }

  @override
  Widget build(BuildContext context) {
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
              // Header with back button, title, and points
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
                          'Agenda',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC400),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.black, width: 2.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '530',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.track_changes,
                                size: 20,
                                color: Colors.black,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Upcoming meet text
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upcoming meet on\n${_getMonthAndDay(_weekDates.last)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            height: 1.4,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AddAgendaScreen(),
                              ),
                            );
                          },
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC400),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 4),
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.black,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Date selector with agenda item indicators
                    Consumer<HouseProvider>(
                      builder: (context, houseProvider, _) {
                        if (houseProvider.currentHouseId == null) {
                          return SizedBox(
                            height: 94,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _weekDates.length,
                              separatorBuilder: (context, index) => const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final date = _weekDates[index];
                                final isToday = _isToday(date);

                                // Default grey when no house/items
                                final backgroundColor = const Color(0xFF4A4A4A);

                                return _buildDatePill(
                                  _getDayName(date),
                                  date.day.toString(),
                                  backgroundColor,
                                  isToday,
                                );
                              },
                            ),
                          );
                        }

                        return StreamBuilder<List<AgendaItem>>(
                          stream: _firestoreService.getAgendaItemsStream(houseProvider.currentHouseId!),
                          builder: (context, snapshot) {
                            // Build a map of dates that have agenda items
                            Map<String, bool> datesWithItems = {};

                            if (snapshot.hasData) {
                              for (var item in snapshot.data!) {
                                String dateKey = '${item.createdAt.year}-${item.createdAt.month}-${item.createdAt.day}';
                                datesWithItems[dateKey] = true;
                              }
                            }

                            return SizedBox(
                              height: 94,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _weekDates.length,
                                separatorBuilder: (context, index) => const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final date = _weekDates[index];
                                  final isToday = _isToday(date);
                                  final dateKey = '${date.year}-${date.month}-${date.day}';
                                  final hasItems = datesWithItems.containsKey(dateKey);
                                  final dateIsThisWeek = _isThisWeek(date);
                                  final dateIsLastWeek = _isLastWeek(date);

                                  Color backgroundColor;
                                  // Only days with agenda items get pink
                                  if (hasItems) {
                                    backgroundColor = const Color(0xFFFF4D8D); // Pink only for days with agenda items
                                  } else {
                                    backgroundColor = const Color(0xFF4A4A4A); // Grey for days without items
                                  }

                                  return _buildDatePill(
                                    _getDayName(date),
                                    date.day.toString(),
                                    backgroundColor,
                                    isToday,
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // This weeks Items
                    const Text(
                      'This weeks Items',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // StreamBuilder for this week's agenda items
                    Consumer<HouseProvider>(
                      builder: (context, houseProvider, _) {
                        if (houseProvider.currentHouseId == null) {
                          return const Text(
                            'Please create or join a house first',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.black54,
                            ),
                          );
                        }

                        return StreamBuilder<List<AgendaItem>>(
                          stream: _firestoreService.getAgendaItemsStream(houseProvider.currentHouseId!),
                          builder: (context, snapshot) {
                            final authProvider = Provider.of<AuthProvider>(context, listen: false);
                            final currentUserId = authProvider.user?.uid;

                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFFFC400),
                                ),
                              );
                            }

                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Text(
                                'you haven\'t added any agenda items this week',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.black54,
                                ),
                              );
                            }

                            // Filter items from this week
                            final thisWeekItems = snapshot.data!
                                .where((item) => _isThisWeek(item.createdAt))
                                .where((item) =>
                                    item.priority != 'meeting' ||
                                    (currentUserId != null && item.createdBy == currentUserId))
                                .toList();

                            if (thisWeekItems.isEmpty) {
                              return const Text(
                                'you haven\'t added any agenda items this week',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.black54,
                                ),
                              );
                            }

                            return _ExpandableAgendaList(
                              items: thisWeekItems,
                              getPriorityColor: _getPriorityColor,
                              getPriorityLabel: _getPriorityLabel,
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 32),

                    // StreamBuilder for recent agenda items (not this week)
                    Consumer<HouseProvider>(
                      builder: (context, houseProvider, _) {
                        if (houseProvider.currentHouseId == null) {
                          return const SizedBox.shrink();
                        }

                        return StreamBuilder<List<AgendaItem>>(
                          stream: _firestoreService.getAgendaItemsStream(houseProvider.currentHouseId!),
                          builder: (context, snapshot) {
                            final authProvider = Provider.of<AuthProvider>(context, listen: false);
                            final currentUserId = authProvider.user?.uid;

                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            // Filter items NOT from this week
                            final recentItems = snapshot.data!
                                .where((item) =>
                                    !_isThisWeek(item.createdAt) &&
                                    (item.priority != 'meeting' ||
                                        (currentUserId != null && item.createdBy == currentUserId)))
                                .take(5)
                                .toList();

                            if (recentItems.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            // Group by date
                            Map<String, List<AgendaItem>> groupedByDate = {};
                            for (var item in recentItems) {
                              String dateKey = DateFormat('MMMM d').format(item.createdAt);
                              if (!groupedByDate.containsKey(dateKey)) {
                                groupedByDate[dateKey] = [];
                              }
                              groupedByDate[dateKey]!.add(item);
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Recent agendas Items heading
                                const Text(
                                  'Recent agendas Items',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Grouped items
                                ...groupedByDate.entries.map((entry) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ...entry.value.map((item) {
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: _buildAgendaCard(
                                            title: item.title,
                                            subtitle: item.details.isNotEmpty
                                                ? item.details
                                                : 'No details provided',
                                            priority: item.priority,
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => AgendaDetailScreen(agendaItem: item),
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      }).toList(),
                                      const SizedBox(height: 12),
                                    ],
                                  );
                                }).toList(),
                              ],
                            );
                          },
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
                      _buildNavIcon(Icons.event_note_rounded, true),
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

  Widget _buildDatePill(String dayName, String dayNumber, Color color, bool isSelected) {
    return Container(
      width: 56,
      height: 94,
      decoration: isSelected ? BoxDecoration(
        color: const Color(0xFFFFC400), // Yellow background for today
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.black,
          width: 4,
        ),
      ) : null,
      padding: isSelected ? const EdgeInsets.all(3) : null,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(isSelected ? 25 : 28),
          border: Border.all(
            color: Colors.black,
            width: isSelected ? 3.5 : 2.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dayName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dayNumber,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgendaCard({
    required String title,
    required String subtitle,
    String? priority,
    VoidCallback? onTap,
  }) {
    return _AgendaCardWidget(
      title: title,
      subtitle: subtitle,
      priority: priority,
      onTap: onTap,
      getPriorityColor: _getPriorityColor,
      getPriorityLabel: _getPriorityLabel,
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

class _ExpandableAgendaList extends StatefulWidget {
  final List<AgendaItem> items;
  final Color Function(String) getPriorityColor;
  final String Function(String) getPriorityLabel;

  const _ExpandableAgendaList({
    required this.items,
    required this.getPriorityColor,
    required this.getPriorityLabel,
  });

  @override
  State<_ExpandableAgendaList> createState() => _ExpandableAgendaListState();
}

class _ExpandableAgendaListState extends State<_ExpandableAgendaList> {
  bool _showAll = false;
  List<Widget>? _cachedFirst3Widgets;
  List<AgendaItem>? _cachedFirst3Items;

  List<Widget> _getFirst3Widgets() {
    final first3Items = widget.items.take(3).toList();

    // Only rebuild if items changed
    if (_cachedFirst3Items == null ||
        _cachedFirst3Items!.length != first3Items.length ||
        !_listsEqual(_cachedFirst3Items!, first3Items)) {
      _cachedFirst3Items = first3Items;
      _cachedFirst3Widgets = first3Items.map((item) {
        return Padding(
          key: ValueKey('agenda_${item.id}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: _AgendaCardWidget(
            title: item.title,
            subtitle: item.details.isNotEmpty
                ? item.details
                : 'No details provided',
            priority: item.priority,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AgendaDetailScreen(agendaItem: item),
                ),
              );
            },
            getPriorityColor: widget.getPriorityColor,
            getPriorityLabel: widget.getPriorityLabel,
          ),
        );
      }).toList();
    }

    return _cachedFirst3Widgets!;
  }

  bool _listsEqual(List<AgendaItem> a, List<AgendaItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final hasMoreItems = widget.items.length > 3;
    final remaining = widget.items.skip(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ALWAYS render first 3 items - cached widgets
        ..._getFirst3Widgets(),

        // ONLY render remaining items when expanded
        if (_showAll && remaining.isNotEmpty)
          ...remaining.map((item) {
            return Padding(
              key: ValueKey('agenda_${item.id}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: _AgendaCardWidget(
                title: item.title,
                subtitle: item.details.isNotEmpty
                    ? item.details
                    : 'No details provided',
                priority: item.priority,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AgendaDetailScreen(agendaItem: item),
                    ),
                  );
                },
                getPriorityColor: widget.getPriorityColor,
                getPriorityLabel: widget.getPriorityLabel,
              ),
            );
          }),

        // Expandable button if more than 3 items
        if (hasMoreItems) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _showAll = !_showAll;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC400),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black, width: 3),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _showAll
                        ? 'Show less'
                        : 'Show ${remaining.length} more items',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _showAll ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.black,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AgendaCardWidget extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? priority;
  final VoidCallback? onTap;
  final Color Function(String) getPriorityColor;
  final String Function(String) getPriorityLabel;

  const _AgendaCardWidget({
    required this.title,
    required this.subtitle,
    this.priority,
    this.onTap,
    required this.getPriorityColor,
    required this.getPriorityLabel,
  });

  @override
  State<_AgendaCardWidget> createState() => _AgendaCardWidgetState();
}

class _AgendaCardWidgetState extends State<_AgendaCardWidget> {
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
        if (widget.onTap != null) widget.onTap!();
      },
      onTapCancel: () {
        setState(() {
          _isPressed = false;
        });
      },
      child: Container(
        height: 124,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: _isPressed ? 0 : 6,
            right: _isPressed ? 0 : 6,
          ),
          height: 124,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left content area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.priority != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.getPriorityColor(widget.priority!),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.black, width: 2),
                              ),
                              child: Text(
                                widget.getPriorityLabel(widget.priority!),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Colors.black87,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              // Right pink section with arrow
              Container(
                width: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4D8D),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(13),
                    bottomRight: Radius.circular(13),
                  ),
                  border: const Border(
                    left: BorderSide(color: Colors.black, width: 3),
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
