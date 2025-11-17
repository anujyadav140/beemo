import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import 'dart:io';
import '../../providers/auth_provider.dart';
import '../../providers/house_provider.dart';
import 'qr_scanner_screen.dart';

class HouseSetupScreen extends StatefulWidget {
  const HouseSetupScreen({super.key});

  @override
  State<HouseSetupScreen> createState() => _HouseSetupScreenState();
}

class _HouseSetupScreenState extends State<HouseSetupScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _houseNameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = false;
  File? _houseImage;

  @override
  void dispose() {
    _houseNameController.dispose();
    super.dispose();
  }

  // Generate a unique 6-character house code
  String _generateHouseCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed confusing characters
    final random = Random();
    return List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
  }

  // Check if house code already exists
  Future<bool> _isHouseCodeUnique(String code) async {
    final querySnapshot = await _firestore
        .collection('houses')
        .where('houseCode', isEqualTo: code)
        .limit(1)
        .get();
    return querySnapshot.docs.isEmpty;
  }

  // Generate a unique house code
  Future<String> _generateUniqueHouseCode() async {
    String code;
    bool isUnique = false;
    int attempts = 0;

    do {
      code = _generateHouseCode();
      isUnique = await _isHouseCodeUnique(code);
      attempts++;
    } while (!isUnique && attempts < 10);

    if (!isUnique) {
      throw Exception('Failed to generate unique house code');
    }

    return code;
  }

  Future<void> _pickHouseImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _houseImage = File(image.path);
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      _showErrorSnackBar('Failed to pick image: ${e.toString()}');
    }
  }

  Future<void> _createNewHouse() async {
    final houseName = _houseNameController.text.trim();

    if (houseName.isEmpty) {
      _showErrorSnackBar('Please enter a house name');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final userId = authProvider.user?.uid;

    if (userId == null) {
      if (mounted) {
        _showErrorSnackBar('User not authenticated');
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      // Get user data
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data();
      final userName = userData?['profile']?['name'] ?? 'User';

      // Generate unique house code
      final houseCode = await _generateUniqueHouseCode();

      // Create new house document
      final houseRef = _firestore.collection('houses').doc();
      final houseId = houseRef.id;

      await houseRef.set({
        'houseCode': houseCode,
        'houseName': houseName,
        'houseEmoji': '🏠',
        'houseColor': const Color(0xFF00BCD4).value, // Default cyan color
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'members': [userId],
        'memberCount': 1,
        'maxMembers': 4, // Maximum 4 people
        'settings': {
          'allowJoinByCode': true,
          'requireApproval': false,
        },
      });

      // Update user's house reference
      await _firestore.collection('users').doc(userId).update({
        'houseId': houseId,
        'houseName': houseName,
        'houseRole': 'owner',
        'hasCompletedHouseSetup': true,
      });

      // Set current house in provider
      houseProvider.setCurrentHouseId(houseId);

      // Show success dialog with house code and QR
      if (mounted) {
        _showHouseCreatedDialog(houseCode, houseName, houseId);
      }
    } catch (e) {
      print('Error creating house: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to create house: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _quickJoinHouse() async {
    // Show dialog to enter house code
    final houseCode = await _showJoinHouseDialog();

    if (houseCode == null || houseCode.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final userId = authProvider.user?.uid;

    if (userId == null) {
      if (mounted) {
        _showErrorSnackBar('User not authenticated');
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      // Find house with this code
      final querySnapshot = await _firestore
          .collection('houses')
          .where('houseCode', isEqualTo: houseCode.toUpperCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        if (mounted) {
          _showErrorSnackBar('House not found. Please check the code.');
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final houseDoc = querySnapshot.docs.first;
      final houseId = houseDoc.id;
      final houseData = houseDoc.data();
      final houseName = houseData['houseName'] ?? 'House';

      // Handle both member formats: List (array) or Map (object)
      List<String> members;
      final membersData = houseData['members'];
      if (membersData is List) {
        // Members stored as array: ['userId1', 'userId2', ...]
        members = List<String>.from(membersData);
      } else if (membersData is Map) {
        // Members stored as map: { 'userId1': {...}, 'userId2': {...} }
        members = membersData.keys.cast<String>().toList();
      } else {
        members = [];
      }

      final memberCount = houseData['memberCount'] ?? members.length;
      final maxMembers = houseData['maxMembers'] ?? 4;

      // Check if user is already a member
      if (members.contains(userId)) {
        if (mounted) {
          _showErrorSnackBar('You are already a member of this house');
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Check if house has reached maximum capacity (4 people)
      if (memberCount >= maxMembers) {
        if (mounted) {
          _showErrorSnackBar('This house is full (maximum $maxMembers members)');
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Get user data for the member info
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data();
      final userName = userData?['profile']?['name'] ?? 'User';

      // Add user to house members based on current format
      if (membersData is List) {
        // Members stored as array - use arrayUnion
        await _firestore.collection('houses').doc(houseId).update({
          'members': FieldValue.arrayUnion([userId]),
          'memberCount': FieldValue.increment(1),
        });
      } else {
        // Members stored as map - add as map entry
        await _firestore.collection('houses').doc(houseId).update({
          'members.$userId': {
            'name': userName,
            'role': 'member',
            'joinedAt': FieldValue.serverTimestamp(),
            'coins': 0,
            'purchasedItems': [],
          },
          'memberCount': FieldValue.increment(1),
        });
      }

      // Update user's house reference
      await _firestore.collection('users').doc(userId).update({
        'houseId': houseId,
        'houseName': houseName,
        'houseRole': 'member',
        'hasCompletedHouseSetup': true,
      });

      // Set current house in provider
      houseProvider.setCurrentHouseId(houseId);

      // Wait a moment for the state to propagate
      await Future.delayed(const Duration(milliseconds: 300));

      // Show success dialog
      if (mounted) {
        _showJoinSuccessDialog(houseName);
      }
    } catch (e) {
      print('Error joining house: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to join house: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showJoinSuccessDialog(String houseName) {
    showDialog(
      context: context,
      barrierDismissible: false,
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Success!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You have joined $houseName',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop(); // Close dialog
                      // AuthWrapper will automatically navigate to onboarding/dashboard
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 5, right: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE91E63),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.black, width: 3),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
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
      },
    );
  }

  Future<String?> _showJoinHouseDialog() async {
    final TextEditingController codeController = TextEditingController();

    return showDialog<String>(
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
                  const Text(
                    'Enter House Code',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2.5),
                    ),
                    child: TextField(
                      controller: codeController,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4,
                      ),
                      maxLength: 6,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'ABC123',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildDialogButton(
                        text: 'Cancel',
                        backgroundColor: Colors.white,
                        textColor: Colors.black,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      _buildDialogButton(
                        text: 'Join',
                        backgroundColor: const Color(0xFFE91E63),
                        textColor: Colors.white,
                        onTap: () {
                          Navigator.of(context).pop(codeController.text);
                        },
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

  void _showHouseCreatedDialog(String houseCode, String houseName, String houseId) {
    // Create deep link for sharing
    final deepLink = 'beemo://join-house?code=$houseCode';

    showDialog(
      context: context,
      barrierDismissible: false,
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                      child: const Icon(
                        Icons.home,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'House Created!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      houseName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Share this code with your roommates:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC400),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            houseCode,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: houseCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Code copied to clipboard!'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Icon(
                              Icons.copy,
                              size: 24,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // QR Code
                    const Text(
                      'Or scan this QR code:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                      child: QrImageView(
                        data: deepLink,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.H,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Share buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildShareButton(
                          icon: Icons.qr_code,
                          label: 'Share QR',
                          onTap: () {
                            Share.share(
                              'Join my house on Beemo! Use code: $houseCode\n\nOr click this link: $deepLink',
                              subject: 'Join $houseName on Beemo',
                            );
                          },
                        ),
                        _buildShareButton(
                          icon: Icons.link,
                          label: 'Share Link',
                          onTap: () {
                            Share.share(
                              deepLink,
                              subject: 'Join $houseName on Beemo',
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        // AuthWrapper will automatically navigate to onboarding
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 5, right: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE91E63),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.black, width: 3),
                          ),
                          child: const Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
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
        );
      },
    );
  }

  Widget _buildShareButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4, right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF00BCD4), // Cyan
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 2.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogButton({
    required String text,
    required Color backgroundColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4, right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 2.5),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInviteButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return IntrinsicWidth(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 5, right: 5),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE91E63), // Pink
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black, width: 3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),

                // Title
                const Text(
                  "Great let's set up\nyour house",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: Colors.black,
                    height: 1.1,
                  ),
                ),

                const SizedBox(height: 20),

                // Join options
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'Already have an invite?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IntrinsicWidth(
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const QRScannerScreen(),
                                  ),
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 4, right: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00BCD4), // Cyan
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.black, width: 2.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.qr_code_scanner,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Scan QR Code',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IntrinsicWidth(
                            child: GestureDetector(
                              onTap: _quickJoinHouse,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 4, right: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE91E63), // Pink
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.black, width: 2.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.vpn_key,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Enter Code',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
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
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Divider
                Row(
                  children: const [
                    Expanded(child: Divider(color: Colors.black26, thickness: 1)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.black26, thickness: 1)),
                  ],
                ),

                const SizedBox(height: 40),

                // House name input
                const Text(
                  'Give your house a name',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  child: TextField(
                    controller: _houseNameController,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g., The Cool House',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                      suffixIcon: _houseNameController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setState(() {
                                  _houseNameController.clear();
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {}); // Rebuild to show/hide clear button
                    },
                  ),
                ),

                const SizedBox(height: 30),

                // Add house picture button
                GestureDetector(
                  onTap: _pickHouseImage,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 5, right: 5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE91E63), // Pink
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.camera_alt,
                            size: 20,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _houseImage != null
                                ? 'Change house picture'
                                : 'Add house picture',
                            style: const TextStyle(
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

                const SizedBox(height: 40),

                // Invite roommates section
                const Text(
                  'Invite your roommates to beemo:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),

                // Invite buttons row
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildInviteButton(
                      icon: Icons.qr_code_scanner,
                      label: 'Share QR Code',
                      onTap: () {
                        _showErrorSnackBar('Create your house first to get a QR code');
                      },
                    ),
                    _buildInviteButton(
                      icon: Icons.link,
                      label: 'Share Link',
                      onTap: () {
                        _showErrorSnackBar('Create your house first to get a link');
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 50),

                // Next button
                Center(
                  child: _isLoading
                      ? const CircularProgressIndicator(
                          color: Color(0xFFFFC400),
                        )
                      : GestureDetector(
                          onTap: _createNewHouse,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 5, right: 5),
                              width: 160,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFC400), // Yellow
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.black, width: 3),
                              ),
                              child: const Center(
                                child: Text(
                                  'Next',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: 30),

                // Decorative cyan blob
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BCD4).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(60),
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
