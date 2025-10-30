import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/house_provider.dart';
import '../services/firestore_service.dart';

class AddAgendaScreen extends StatefulWidget {
  const AddAgendaScreen({super.key});

  @override
  State<AddAgendaScreen> createState() => _AddAgendaScreenState();
}

class _AddAgendaScreenState extends State<AddAgendaScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  String? _selectedPriority = 'meeting';
  String? _pressedPriority;
  bool _isSubmitPressed = false;
  bool _isLoading = false;
  int _meetingAgendaCount = 0;

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
        if (_meetingAgendaCount >= 4 && _selectedPriority == 'meeting') {
          _selectedPriority = 'chat';
        }
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

    if (_selectedPriority == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a priority'),
          backgroundColor: Color(0xFFFF4D8D),
        ),
      );
      return;
    }

    if (_selectedPriority == 'meeting' && _meetingAgendaCount >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meeting agenda is full (4/4). Please select Chat or Flexible.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    if (houseId == null) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create or join a house first')),
      );
      return;
    }

    try {
      await _firestoreService.createAgendaItem(
        houseId: houseId,
        title: _titleController.text.trim(),
        details: _detailsController.text.trim(),
        priority: _selectedPriority!,
      );

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Agenda added! Beemo will follow up in chat to lock an owner.'),
            backgroundColor: Color(0xFF63BDA4),
            duration: Duration(seconds: 3),
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

                    const SizedBox(height: 16),

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
                      description: _meetingAgendaCount >= 4
                          ? 'Meeting agenda is full (4/4). Please use Chat or Flexible.'
                          : 'Best for important topics that need a calm, focused conversation. (${_meetingAgendaCount > 4 ? 4 : _meetingAgendaCount}/4)',
                      isDisabled: _meetingAgendaCount >= 4,
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
          'ÃƒÂ°Ã…Â¸Ã‚Â¤Ã¢â‚¬â€œ',
          style: TextStyle(
            fontSize: isActive ? 24 : 20,
          ),
        ),
      ),
    );
  }
}

