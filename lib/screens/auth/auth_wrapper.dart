import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/house_provider.dart';
import '../../services/firestore_service.dart';
import '../dash_screen.dart';
import 'login_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<void> _loadUserHouse(BuildContext context, String userId) async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final firestoreService = FirestoreService();

    // Get user's house ID
    String? houseId = await firestoreService.getUserHouseId(userId);

    if (houseId != null) {
      houseProvider.setCurrentHouseId(houseId);
    }
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

        // If user is authenticated, load their house and show main app
        if (authProvider.isAuthenticated) {
          // Load user's house in the background
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadUserHouse(context, authProvider.user!.uid);
          });

          return const DashScreen();
        }

        // Otherwise show login screen
        return const LoginScreen();
      },
    );
  }
}
