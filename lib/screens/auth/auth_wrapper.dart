import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/house_provider.dart';
import '../../services/firestore_service.dart';
import '../dash_screen.dart';
import '../onboarding/get_started_screen.dart';
import '../onboarding/avatar_selection_screen.dart';
import '../onboarding/house_setup_screen.dart';
import '../onboarding/onboarding_screen.dart';
import 'login_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final FirestoreService _firestoreService = FirestoreService();
  String? _loadedHouseForUserId;
  final Set<String> _restoringUserIds = {};

  Future<void> _loadUserHouse(String userId) async {
    if (_loadedHouseForUserId == userId) return; // Already loaded for this user

    final houseProvider = Provider.of<HouseProvider>(context, listen: false);

    // Get user's house ID
    String? houseId = await _firestoreService.getUserHouseId(userId);

    if (houseId != null) {
      houseProvider.setCurrentHouseId(houseId);
    }

    _loadedHouseForUserId = userId;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        // Show loading indicator while checking auth state
        if (authProvider.user == null && authProvider.isLoading) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F5F0),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFFC400),
              ),
            ),
          );
        }

        // If user is authenticated
        if (authProvider.isAuthenticated) {
          final userId = authProvider.user!.uid;

          // Load user house once
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadUserHouse(userId);
          });

          // Use StreamBuilder to listen to user document changes
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .snapshots(),
            builder: (context, snapshot) {
              // Show loading while waiting for user data
              if (!snapshot.hasData) {
                return const Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFFC400),
                    ),
                  ),
                );
              }

              final docSnapshot = snapshot.data;

              if (docSnapshot == null || !docSnapshot.exists) {
                if (!_restoringUserIds.contains(userId)) {
                  _restoringUserIds.add(userId);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    () async {
                      try {
                        await _firestoreService.ensureUserDocument(
                          userId: userId,
                          displayName: authProvider.user?.displayName ?? '',
                          email: authProvider.user?.email ?? '',
                          avatarUrl: authProvider.user?.photoURL,
                        );
                      } finally {
                        _restoringUserIds.remove(userId);
                        if (mounted) {
                          setState(() {});
                        }
                      }
                    }();
                  });
                }

                return const Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFFC400),
                    ),
                  ),
                );
              }

              // Get user status from document
              final userData = docSnapshot.data() as Map<String, dynamic>?;
              final hasCompletedGetStarted = userData?['hasCompletedGetStarted'] ?? false;
              final hasCompletedAvatarSelection = userData?['hasCompletedAvatarSelection'] ?? false;
              final hasCompletedHouseSetup = userData?['hasCompletedHouseSetup'] ?? false;
              final hasCompletedOnboarding = userData?['hasCompletedOnboarding'] ?? false;

              // Show Get Started screen if not completed
              if (!hasCompletedGetStarted) {
                return const GetStartedScreen();
              }

              // Show Avatar Selection screen if Get Started is done but avatar not selected
              if (!hasCompletedAvatarSelection) {
                return const AvatarSelectionScreen();
              }

              // Show House Setup screen if avatar is selected but house not set up
              if (!hasCompletedHouseSetup) {
                return const HouseSetupScreen();
              }

              // Show onboarding if house is set up but onboarding is not
              if (!hasCompletedOnboarding) {
                return const OnboardingScreen();
              }

              // Show main app if everything is completed
              return const DashScreen();
            },
          );
        }

        // Otherwise show login screen
        return const LoginScreen();
      },
    );
  }
}
