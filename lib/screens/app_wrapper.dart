import 'package:flutter/material.dart';
import 'auth/auth_wrapper.dart';

// AppWrapper is now a simple passthrough to AuthWrapper
// AuthWrapper handles both authentication AND onboarding checks
class AppWrapper extends StatelessWidget {
  const AppWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthWrapper();
  }
}
