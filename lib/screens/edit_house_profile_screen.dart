import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/house_provider.dart';

class EditHouseProfileScreen extends StatefulWidget {
  const EditHouseProfileScreen({super.key});

  @override
  State<EditHouseProfileScreen> createState() => _EditHouseProfileScreenState();
}

class _EditHouseProfileScreenState extends State<EditHouseProfileScreen> {
  String _selectedEmoji = '🏠';
  Color _selectedColor = const Color(0xFF00BCD4);
  bool _isLoading = false;
  bool _isInitialized = false;

  final List<String> _emojiOptions = [
    '🏠', '🏡', '🏢', '🏰', '🏛', '🏚',
    '🏘', '🏗', '⛺', '🏕', '🏞', '🏟',
    '🌆', '🌃', '🏙', '🌇', '🌉', '🌌',
    '⭐', '🌟', '✨', '💫', '🌈', '☀',
    '🌙', '🪐', '🚀', '🛸', '🎪', '🎡',
    '🎢', '🎠', '🎨', '🎭', '🎪', '🎯',
  ];

  final List<Color> _colorOptions = [
    const Color(0xFFFF4D8D), // Pink
    const Color(0xFFFFC400), // Yellow
    const Color(0xFF00BCD4), // Cyan
    const Color(0xFFE91E63), // Deep Pink
    const Color(0xFF9C27B0), // Purple
    const Color(0xFF673AB7), // Deep Purple
    const Color(0xFF3F51B5), // Indigo
    const Color(0xFF2196F3), // Blue
    const Color(0xFF03A9F4), // Light Blue
    const Color(0xFF00BCD4), // Cyan
    const Color(0xFF009688), // Teal
    const Color(0xFF4CAF50), // Green
    const Color(0xFF8BC34A), // Light Green
    const Color(0xFFCDDC39), // Lime
    const Color(0xFFFFEB3B), // Yellow
    const Color(0xFFFFC107), // Amber
    const Color(0xFFFF9800), // Orange
    const Color(0xFFFF5722), // Deep Orange
    const Color(0xFF795548), // Brown
    const Color(0xFF607D8B), // Blue Grey
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _loadHouseData();
    }
  }

  Future<void> _loadHouseData() async {
    if (_isInitialized) return;

    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    if (houseId != null) {
      try {
        final houseDoc = await FirebaseFirestore.instance
            .collection('houses')
            .doc(houseId)
            .get();

        if (houseDoc.exists) {
          final houseData = houseDoc.data() as Map<String, dynamic>?;
          setState(() {
            _selectedEmoji = houseData?['houseEmoji'] ?? '🏠';
            final houseColorInt = houseData?['houseColor'];
            if (houseColorInt != null) {
              _selectedColor = Color(houseColorInt);
            }
            _isInitialized = true;
          });
        }
      } catch (e) {
        print('Error loading house data: $e');
        setState(() {
          _isInitialized = true;
        });
      }
    } else {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  Future<void> _saveHouseProfile() async {
    setState(() {
      _isLoading = true;
    });

    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    if (houseId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('houses')
            .doc(houseId)
            .update({
          'houseEmoji': _selectedEmoji,
          'houseColor': _selectedColor.value,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('House profile updated successfully'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        print('Error saving house profile: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating house profile: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isInitialized
            ? Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 40,
                            height: 40,
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
                          'House Profile',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),

                          // House Avatar Preview
                          Center(
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: _selectedColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black, width: 3),
                              ),
                              child: Center(
                                child: Text(
                                  _selectedEmoji,
                                  style: const TextStyle(fontSize: 60),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),

                          // Emoji selector
                          const Text(
                            'House Icon',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildEmojiPicker(),

                          const SizedBox(height: 24),

                          // Color selector
                          const Text(
                            'House Color',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildColorPicker(),

                          const SizedBox(height: 120), // Space for button
                        ],
                      ),
                    ),
                  ),

                  // Save button
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFFC400),
                            ),
                          )
                        : GestureDetector(
                            onTap: _saveHouseProfile,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFC400),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(color: Colors.black, width: 2.5),
                              ),
                              child: const Center(
                                child: Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              )
            : const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFFC400),
                ),
              ),
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2.5),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _emojiOptions.length,
        itemBuilder: (context, index) {
          final emoji = _emojiOptions[index];
          final isSelected = emoji == _selectedEmoji;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedEmoji = emoji;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFFC400) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.black : Colors.grey[300]!,
                  width: isSelected ? 2.5 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColorPicker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2.5),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _colorOptions.length,
        itemBuilder: (context, index) {
          final color = _colorOptions[index];
          final isSelected = color.value == _selectedColor.value;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedColor = color;
              });
            },
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black,
                  width: isSelected ? 3 : 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 24,
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}
