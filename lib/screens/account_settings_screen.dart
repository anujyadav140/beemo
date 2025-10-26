import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../providers/house_provider.dart';
import 'manage_members_screen.dart';
import 'edit_profile_screen.dart';
import 'edit_house_profile_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final houseProvider = Provider.of<HouseProvider>(context);
    final userId = authProvider.user?.uid;
    final houseId = houseProvider.currentHouseId;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: userId != null
              ? FirebaseFirestore.instance.collection('users').doc(userId).snapshots()
              : null,
          builder: (context, userSnapshot) {
            String userName = 'User';

            if (userSnapshot.hasData && userSnapshot.data != null) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
              userName = userData?['profile']?['name'] ?? 'User';
            }

            return StreamBuilder<DocumentSnapshot>(
              stream: houseId != null
                  ? FirebaseFirestore.instance.collection('houses').doc(houseId).snapshots()
                  : null,
              builder: (context, houseSnapshot) {
                String houseName = 'No House';
                String houseCode = '';

                if (houseSnapshot.hasData && houseSnapshot.data != null) {
                  final houseData = houseSnapshot.data!.data() as Map<String, dynamic>?;
                  houseName = houseData?['houseName'] ?? 'No House';
                  houseCode = houseData?['houseCode'] ?? '';
                }

                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with back button
                        Row(
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
                              'Account & settings',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // House settings
                        const Text(
                          'House settings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black, width: 2.5),
                          ),
                          child: Column(
                            children: [
                              _buildSettingItem(
                                icon: Icons.home,
                                iconColor: const Color(0xFFE91E63),
                                title: 'House Name',
                                trailing: houseName,
                                onTap: () {
                                  _showEditHouseNameDialog(context, houseName, houseId);
                                },
                              ),
                              const Divider(height: 1, color: Colors.black26),
                              _buildSettingItem(
                                icon: Icons.camera_alt,
                                iconColor: const Color(0xFFE91E63),
                                title: 'House profile picture',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const EditHouseProfileScreen(),
                                    ),
                                  );
                                },
                              ),
                              const Divider(height: 1, color: Colors.black26),
                              _buildSettingItem(
                                icon: Icons.people,
                                iconColor: const Color(0xFFE91E63),
                                title: 'Manage Members',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const ManageMembersScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Account settings
                        const Text(
                          'Account settings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black, width: 2.5),
                          ),
                          child: Column(
                            children: [
                              _buildSettingItem(
                                icon: Icons.person,
                                iconColor: const Color(0xFF00BCD4),
                                title: 'Edit Name',
                                trailing: userName,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const EditProfileScreen(),
                                    ),
                                  );
                                },
                              ),
                              const Divider(height: 1, color: Colors.black26),
                              _buildSettingItem(
                                icon: Icons.face,
                                iconColor: const Color(0xFF00BCD4),
                                title: 'Change Avatar',
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const EditProfileScreen(),
                                    ),
                                  );
                                },
                              ),
                              const Divider(height: 1, color: Colors.black26),
                              _buildSettingItem(
                                icon: Icons.card_membership,
                                iconColor: const Color(0xFF00BCD4),
                                title: 'Manage Subscription',
                                onTap: () {
                                  // TODO: Manage subscription
                                },
                              ),
                              const Divider(height: 1, color: Colors.black26),
                              _buildSettingItem(
                                icon: Icons.help,
                                iconColor: const Color(0xFF00BCD4),
                                title: 'Help and Support',
                                onTap: () {
                                  // TODO: Help and support
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Delete/leave house
                        GestureDetector(
                          onTap: () {
                            _showLeaveHouseDialog(context, houseName);
                          },
                          child: const Text(
                            'Delete/leave house',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE91E63),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Logout button
                        Center(
                          child: GestureDetector(
                            onTap: () {
                              _showLogoutDialog(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 60,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFC400),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(color: Colors.black, width: 2.5),
                              ),
                              child: const Text(
                                'Logout',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? trailing,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            if (trailing != null) ...[
              Text(
                trailing,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(
              Icons.chevron_right,
              color: Colors.black,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  void _showEditHouseNameDialog(BuildContext context, String currentName, String? houseId) {
    final TextEditingController controller = TextEditingController(text: currentName);

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
                    'Edit House Name',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
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
                      controller: controller,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'House Name',
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
                            if (houseId != null && controller.text.trim().isNotEmpty) {
                              await FirebaseFirestore.instance
                                  .collection('houses')
                                  .doc(houseId)
                                  .update({'houseName': controller.text.trim()});
                              if (context.mounted) {
                                Navigator.of(context).pop();
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
                                'Save',
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
                  const Text(
                    'Sign Out?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Are you sure you want to sign out?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
                            Navigator.of(context).pop();
                            Navigator.of(context).pop();
                            await Provider.of<AuthProvider>(context, listen: false).signOut();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.black, width: 2.5),
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

  void _showLeaveHouseDialog(BuildContext context, String houseName) {
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
                    'Leave House?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Are you sure you want to leave "$houseName"?',
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
                          onTap: () {
                            // TODO: Implement leave house
                            Navigator.of(context).pop();
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
                                'Leave',
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
