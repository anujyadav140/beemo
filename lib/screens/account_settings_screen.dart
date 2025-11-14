import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/house_provider.dart';
import '../models/house_model.dart';
import 'manage_members_screen.dart';
import 'edit_profile_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _MemberTileData {
  const _MemberTileData({
    required this.id,
    required this.displayName,
    required this.role,
    required this.isCurrentUser,
  });

  final String id;
  final String displayName;
  final String role;
  final bool isCurrentUser;
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
                String inviteCode = '';
                Map<String, dynamic>? houseData;

                if (houseSnapshot.hasData && houseSnapshot.data != null) {
                  houseData = houseSnapshot.data!.data() as Map<String, dynamic>?;
                  houseName = houseData?['houseName'] ?? 'No House';
                  inviteCode = houseData?['inviteCode'] ?? '';
                }

                final memberTiles = _collectHouseMembers(
                  houseData,
                  houseProvider,
                  userId,
                );

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
                              const Divider(height: 1, color: Colors.black26),
                              _buildSettingItem(
                                icon: Icons.qr_code,
                                iconColor: const Color(0xFFE91E63),
                                title: 'Share QR Code',
                                onTap: () {
                                  _showShareDialog(context, houseName, inviteCode);
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

  List<_MemberTileData> _collectHouseMembers(
    Map<String, dynamic>? houseData,
    HouseProvider houseProvider,
    String? currentUserId,
  ) {
    final Map<String, _MemberTileData> collected = {};
    final membersField = houseData?['members'];
    final providerMembers = houseProvider.currentHouse?.members;

    void addMember(
      String id, {
      Map<String, dynamic>? rawMember,
      HouseMember? providerMember,
    }) {
      final trimmedId = id.trim();
      if (trimmedId.isEmpty) {
        return;
      }

      final existing = collected[trimmedId];

      String? displayName;
      final nameCandidates = <String?>[
        rawMember?['name']?.toString(),
        rawMember?['displayName']?.toString(),
        providerMember?.name,
        existing?.displayName,
      ];
      for (final candidate in nameCandidates) {
        if (candidate != null && candidate.trim().isNotEmpty) {
          displayName = candidate.trim();
          break;
        }
      }
      displayName ??= 'Member';

      String? role;
      final roleCandidates = <String?>[
        rawMember?['role']?.toString(),
        providerMember?.role,
        existing?.role,
      ];
      for (final candidate in roleCandidates) {
        if (candidate != null && candidate.trim().isNotEmpty) {
          role = candidate.trim();
          break;
        }
      }
      role ??= 'member';

      final isCurrent = currentUserId != null && trimmedId == currentUserId;

      collected[trimmedId] = _MemberTileData(
        id: trimmedId,
        displayName: displayName,
        role: role,
        isCurrentUser: isCurrent,
      );
    }

    if (membersField is Map) {
      membersField.forEach((key, value) {
        final memberId = key.toString();
        if (value is Map) {
          final map = <String, dynamic>{};
          value.forEach((entryKey, entryValue) {
            map[entryKey.toString()] = entryValue;
          });
          addMember(
            memberId,
            rawMember: map,
            providerMember: providerMembers?[memberId],
          );
        } else {
          addMember(
            memberId,
            providerMember: providerMembers?[memberId],
          );
        }
      });
    } else if (membersField is List) {
      for (var index = 0; index < membersField.length; index++) {
        final entry = membersField[index];
        if (entry is Map) {
          final rawMember = <String, dynamic>{};
          entry.forEach((entryKey, entryValue) {
            rawMember[entryKey.toString()] = entryValue;
          });

          String memberId = '';
          const possibleKeys = [
            'id',
            'uid',
            'userId',
            'memberId',
            'authId',
            'ref',
          ];
          for (final key in possibleKeys) {
            final candidate = rawMember[key];
            if (candidate != null && candidate.toString().trim().isNotEmpty) {
              memberId = candidate.toString().trim();
              break;
            }
          }

          if (memberId.isEmpty) {
            final nameFallback = rawMember['name']?.toString() ?? rawMember['displayName']?.toString();
            if (nameFallback != null && nameFallback.trim().isNotEmpty) {
              memberId = nameFallback.trim();
            } else {
              memberId = 'member_${index + 1}';
            }
          }

          addMember(memberId, rawMember: rawMember, providerMember: providerMembers?[memberId]);
        }
      }
    }

    if (providerMembers != null) {
      providerMembers.forEach((id, member) {
        addMember(id, providerMember: member);
      });
    }

    if (currentUserId != null && !collected.containsKey(currentUserId)) {
      addMember(currentUserId, providerMember: providerMembers?[currentUserId]);
    }

    final List<_MemberTileData> members = collected.values.toList()
      ..sort((a, b) {
        if (a.isCurrentUser != b.isCurrentUser) {
          return a.isCurrentUser ? -1 : 1;
        }
        final nameCompare = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        if (nameCompare != 0) {
          return nameCompare;
        }
        return a.id.compareTo(b.id);
      });

    return members;
  }

  Widget _buildMemberListSection(List<_MemberTileData> members) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2.5),
      ),
      child: Column(
        children: [
          for (var index = 0; index < members.length; index++)
            _buildMemberRow(
              members[index],
              isLast: index == members.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildMemberRow(_MemberTileData member, {required bool isLast}) {
    final roleLabel = _formatRoleLabel(member.role);

    return Container(
      decoration: BoxDecoration(
        border: isLast ? null : const Border(
          bottom: BorderSide(color: Colors.black12, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3C9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: const Icon(
              Icons.person,
              size: 18,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        member.displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (member.isCurrentUser) ...[
                      const SizedBox(width: 8),
                      _buildYouChip(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  roleLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYouChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'You',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _formatRoleLabel(String role) {
    final trimmed = role.trim();
    if (trimmed.isEmpty) {
      return 'Member';
    }

    if (trimmed.length == 1) {
      return trimmed.toUpperCase();
    }

    final lower = trimmed.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
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

  void _showShareDialog(
    BuildContext context,
    String houseName,
    String inviteCode,
  ) {
    if (inviteCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No invite code available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final inviteUrl = 'beemo://join-house?code=$inviteCode';
    final shareText =
        'Join my house "$houseName" on Beemo! Use code: $inviteCode';

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
                      inviteCode,
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

                  const SizedBox(height: 16),

                  // Close button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
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
}
