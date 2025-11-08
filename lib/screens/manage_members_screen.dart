import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/house_provider.dart';

class ManageMembersScreen extends StatefulWidget {
  const ManageMembersScreen({super.key});

  @override
  State<ManageMembersScreen> createState() => _ManageMembersScreenState();
}

class _Member {
  final String id;
  final String name;
  final String avatarEmoji;
  final Color avatarColor;
  final String role;
  final bool isCurrentUser;

  _Member({
    required this.id,
    required this.name,
    required this.avatarEmoji,
    required this.avatarColor,
    required this.role,
    required this.isCurrentUser,
  });
}

class _ManageMembersScreenState extends State<ManageMembersScreen> {
  List<_Member> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final userId = authProvider.user?.uid;
    final houseId = houseProvider.currentHouseId;

    if (houseId == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      debugPrint('🔍 Fetching members for house: $houseId');

      // Get house document
      final houseDoc = await FirebaseFirestore.instance
          .collection('houses')
          .doc(houseId)
          .get();

      if (!houseDoc.exists) {
        debugPrint('⚠️ House document not found');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final houseData = houseDoc.data() as Map<String, dynamic>?;
      final membersField = houseData?['members'];

      debugPrint('📋 Members field type: ${membersField.runtimeType}');
      debugPrint('📋 Members field value: $membersField');

      List<String> memberIds = [];

      // Handle both Map and List structures
      if (membersField is Map) {
        // Firebase structure: members is a Map with userId as keys
        memberIds = membersField.keys.map((k) => k.toString()).toList();
        debugPrint('✅ Found ${memberIds.length} members in Map format');
      } else if (membersField is List) {
        // Fallback: members is a List of user IDs
        memberIds = membersField.map((m) => m.toString()).toList();
        debugPrint('✅ Found ${memberIds.length} members in List format');
      }

      debugPrint('👥 Member IDs: $memberIds');

      // Fetch user details for each member
      List<_Member> fetchedMembers = [];
      for (final memberId in memberIds) {
        try {
          debugPrint('   Fetching user: $memberId');
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(memberId)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>?;
            final profile = userData?['profile'] as Map<String, dynamic>?;

            final name = profile?['name']?.toString() ?? 'User';
            final avatarEmoji = profile?['avatarEmoji']?.toString() ?? '👤';
            final role = userData?['houseRole']?.toString() ?? 'member';
            final avatarColorInt = profile?['avatarColor'];
            Color avatarColor = const Color(0xFFFF4D8D);
            if (avatarColorInt != null && avatarColorInt is int) {
              avatarColor = Color(avatarColorInt);
            }

            fetchedMembers.add(_Member(
              id: memberId,
              name: name,
              avatarEmoji: avatarEmoji,
              avatarColor: avatarColor,
              role: role,
              isCurrentUser: memberId == userId,
            ));

            debugPrint('   ✓ Added: $name ($role)');
          } else {
            debugPrint('   ⚠️ User document not found for: $memberId');
          }
        } catch (e) {
          debugPrint('   ❌ Error fetching user $memberId: $e');
        }
      }

      // Sort: current user first, then alphabetically
      fetchedMembers.sort((a, b) {
        if (a.isCurrentUser != b.isCurrentUser) {
          return a.isCurrentUser ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      debugPrint('🎉 Fetched ${fetchedMembers.length} members successfully');

      setState(() {
        _members = fetchedMembers;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching members: $e');
      debugPrint('$stackTrace');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final houseProvider = Provider.of<HouseProvider>(context);
    final houseId = houseProvider.currentHouseId;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: houseId != null
              ? FirebaseFirestore.instance.collection('houses').doc(houseId).snapshots()
              : null,
          builder: (context, houseSnapshot) {
            String houseName = 'House';
            String houseCode = '';

            if (houseSnapshot.hasData && houseSnapshot.data != null) {
              final houseData = houseSnapshot.data!.data() as Map<String, dynamic>?;
              houseName = houseData?['houseName'] ?? 'House';
              houseCode = houseData?['houseCode'] ?? '';
            }

            final inviteUrl = 'beemo://join-house?code=$houseCode';
            final shareText = 'Join my house "$houseName" on Beemo! Use code: $houseCode';

            return Column(
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
                        'Manage Members',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),

                // Add Member Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: () {
                      _showAddMemberDialog(context, houseId);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black, width: 2.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.person_add, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Add Member',
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
                const SizedBox(height: 20),

                // Members List
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFFC400),
                            strokeWidth: 3,
                          ),
                        )
                      : _members.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.people_outline,
                                    size: 64,
                                    color: Colors.black26,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'No members found',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchMembers,
                              color: const Color(0xFFFFC400),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: _members.length,
                                itemBuilder: (context, index) {
                                  final member = _members[index];
                                  return _buildMemberTile(member, houseId);
                                },
                              ),
                            ),
                ),

                // Share buttons
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _showQRCodeDialog(context, inviteUrl, houseName, houseCode);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE91E63),
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: Colors.black, width: 2.5),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.qr_code, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Share QR',
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Share.share(shareText);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE91E63),
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: Colors.black, width: 2.5),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.link, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Invite link',
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
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMemberTile(_Member member, String? houseId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black, width: 2.5),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: member.avatarColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2.5),
              ),
              child: Center(
                child: Text(
                  member.avatarEmoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name and Role
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatRole(member.role),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            // Badge or Remove button
            if (member.isCurrentUser || member.role.toLowerCase() == 'admin')
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: member.role.toLowerCase() == 'admin'
                      ? const Color(0xFFFFC400)
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: member.role.toLowerCase() == 'admin'
                      ? Border.all(color: Colors.black, width: 2)
                      : null,
                ),
                child: Text(
                  member.role.toLowerCase() == 'admin' ? 'Admin' : 'You',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: member.role.toLowerCase() == 'admin'
                        ? Colors.black
                        : Colors.black87,
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: () {
                  _showRemoveMemberDialog(
                    context,
                    member.name,
                    member.id,
                    houseId,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE91E63).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Remove',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE91E63),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatRole(String role) {
    final trimmed = role.trim();
    if (trimmed.isEmpty) return 'Member';
    if (trimmed.length == 1) return trimmed.toUpperCase();
    final lower = trimmed.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  void _showAddMemberDialog(BuildContext context, String? houseId) {
    final TextEditingController emailController = TextEditingController();

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
                  const Text(
                    'Add Member',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Enter the user\'s email or user ID',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black, width: 2.5),
                    ),
                    child: TextField(
                      controller: emailController,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Email or User ID',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.black, width: 2.5),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final input = emailController.text.trim();
                            if (input.isEmpty || houseId == null) return;

                            // Show loading
                            Navigator.of(context).pop();
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFFFC400),
                                ),
                              ),
                            );

                            try {
                              // Find user by email or UID
                              String? userId;
                              if (input.contains('@')) {
                                // Search by email
                                final usersSnapshot = await FirebaseFirestore.instance
                                    .collection('users')
                                    .where('email', isEqualTo: input)
                                    .limit(1)
                                    .get();

                                if (usersSnapshot.docs.isNotEmpty) {
                                  userId = usersSnapshot.docs.first.id;
                                }
                              } else {
                                // Assume it's a UID
                                final userDoc = await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(input)
                                    .get();

                                if (userDoc.exists) {
                                  userId = input;
                                }
                              }

                              if (userId == null) {
                                if (context.mounted) {
                                  Navigator.of(context).pop(); // Close loading
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('User not found'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }

                              // Get house data
                              final houseDoc = await FirebaseFirestore.instance
                                  .collection('houses')
                                  .doc(houseId)
                                  .get();

                              final houseName = houseDoc.data()?['houseName'] ?? 'House';

                              // Add member to house
                              await FirebaseFirestore.instance
                                  .collection('houses')
                                  .doc(houseId)
                                  .update({
                                'members.$userId': {
                                  'joinedAt': FieldValue.serverTimestamp(),
                                  'role': 'member',
                                },
                                'memberCount': FieldValue.increment(1),
                              });

                              // Update user's house reference
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(userId)
                                  .update({
                                'houseId': houseId,
                                'houseName': houseName,
                                'houseRole': 'member',
                              });

                              // Refresh member list
                              await _fetchMembers();

                              if (context.mounted) {
                                Navigator.of(context).pop(); // Close loading
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Member added successfully!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              debugPrint('❌ Error adding member: $e');
                              if (context.mounted) {
                                Navigator.of(context).pop(); // Close loading
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00BCD4),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.black, width: 2.5),
                            ),
                            child: const Center(
                              child: Text(
                                'Add',
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

  void _showQRCodeDialog(BuildContext context, String inviteUrl, String houseName, String houseCode) {
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
                  const Text(
                    'Invite to House',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    houseName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),
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
                        letterSpacing: 2,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black, width: 2.5),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
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

  void _showRemoveMemberDialog(
    BuildContext context,
    String memberName,
    String memberId,
    String? houseId,
  ) {
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
                  const Text(
                    'Remove Member?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Remove $memberName from the house?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.black, width: 2.5),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            if (houseId != null) {
                              Navigator.of(context).pop();

                              // Show loading
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFFFC400),
                                  ),
                                ),
                              );

                              try {
                                // Remove member from house
                                await FirebaseFirestore.instance
                                    .collection('houses')
                                    .doc(houseId)
                                    .update({
                                  'members.$memberId': FieldValue.delete(),
                                  'memberCount': FieldValue.increment(-1),
                                });

                                // Update user's house reference
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(memberId)
                                    .update({
                                  'houseId': null,
                                  'houseName': null,
                                  'houseRole': null,
                                });

                                // Refresh member list
                                await _fetchMembers();

                                if (context.mounted) {
                                  Navigator.of(context).pop(); // Close loading
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Member removed successfully'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                debugPrint('❌ Error removing member: $e');
                                if (context.mounted) {
                                  Navigator.of(context).pop(); // Close loading
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE91E63),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.black, width: 2.5),
                            ),
                            child: const Center(
                              child: Text(
                                'Remove',
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
}
