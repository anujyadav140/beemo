import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String avatarUrl;
  final String initials;
  final int points;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.initials,
    required this.points,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    Map<String, dynamic> profile = data['profile'] ?? {};

    return UserProfile(
      id: doc.id,
      name: profile['name'] ?? '',
      email: profile['email'] ?? '',
      avatarUrl: profile['avatarUrl'] ?? '',
      initials: profile['initials'] ?? '',
      points: profile['points'] ?? 500,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'profile': {
        'name': name,
        'email': email,
        'avatarUrl': avatarUrl,
        'initials': initials,
        'points': points,
      },
    };
  }
}

class TimerStats {
  final int sessionsCompleted;
  final int totalFocusTime;
  final int totalBreakTime;

  TimerStats({
    required this.sessionsCompleted,
    required this.totalFocusTime,
    required this.totalBreakTime,
  });

  factory TimerStats.fromMap(Map<String, dynamic> data) {
    return TimerStats(
      sessionsCompleted: data['sessionsCompleted'] ?? 0,
      totalFocusTime: data['totalFocusTime'] ?? 0,
      totalBreakTime: data['totalBreakTime'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionsCompleted': sessionsCompleted,
      'totalFocusTime': totalFocusTime,
      'totalBreakTime': totalBreakTime,
    };
  }
}

class UserSettings {
  final bool notifications;
  final String theme;
  final String language;

  UserSettings({
    required this.notifications,
    required this.theme,
    required this.language,
  });

  factory UserSettings.fromMap(Map<String, dynamic> data) {
    return UserSettings(
      notifications: data['notifications'] ?? true,
      theme: data['theme'] ?? 'light',
      language: data['language'] ?? 'en',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'notifications': notifications,
      'theme': theme,
      'language': language,
    };
  }
}
