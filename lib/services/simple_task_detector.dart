/// Simple task detection that works WITHOUT AI/API calls
/// This is a fallback for when Vertex AI API is not enabled
class SimpleTaskDetector {
  /// Common action verbs that indicate a task
  static final List<String> _taskVerbs = [
    'buy', 'get', 'purchase', 'shop',
    'clean', 'wash', 'wipe', 'scrub', 'tidy',
    'take', 'bring', 'carry', 'move',
    'do', 'complete', 'finish', 'done',
    'fix', 'repair', 'mend',
    'call', 'contact', 'email', 'text',
    'make', 'create', 'prepare', 'cook',
    'pay', 'order', 'schedule', 'book',
    'check', 'verify', 'confirm',
    'organize', 'sort', 'arrange',
    'water', 'feed', 'walk',
    'vacuum', 'sweep', 'mop',
    'fold', 'iron', 'hang',
    'pick up', 'drop off', 'deliver',
  ];

  /// Days of the week for due date detection
  static final List<String> _days = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
    'today', 'tomorrow', 'tonight',
  ];

  /// Detect if a message contains a task
  static DetectedTaskInfo? detectTask(
    String message,
    List<Map<String, String>> houseMembers,
  ) {
    final lowerMessage = message.toLowerCase();

    // Check if message contains task-like action verbs
    final hasTaskVerb = _taskVerbs.any((verb) =>
      lowerMessage.contains(verb) ||
      lowerMessage.contains('$verb ') ||
      lowerMessage.contains(' $verb')
    );

    if (!hasTaskVerb) {
      return null; // Not a task
    }

    // Extract assigned person by checking for house member names
    String? assignedTo;
    String? assignedToName;

    for (var member in houseMembers) {
      final memberName = member['name']!.toLowerCase();
      final firstName = memberName.split(' ').first;

      // Check if name appears at start of message or after comma
      if (lowerMessage.startsWith(memberName) ||
          lowerMessage.startsWith(firstName) ||
          lowerMessage.contains(', $memberName') ||
          lowerMessage.contains(', $firstName') ||
          lowerMessage.contains('$memberName,') ||
          lowerMessage.contains('$firstName,') ||
          lowerMessage.contains('$memberName ') ||
          lowerMessage.contains('$firstName ')) {
        assignedTo = member['id'];
        assignedToName = member['name'];
        break;
      }
    }

    // Extract title (first sentence or up to 50 chars)
    String title = message;
    if (message.contains('.')) {
      title = message.split('.').first;
    }
    if (title.length > 50) {
      title = title.substring(0, 50).trim();
    }

    // Remove name prefix if present
    if (assignedToName != null) {
      final firstName = assignedToName.split(' ').first;
      title = title.replaceFirst(RegExp('$firstName,?\\s*', caseSensitive: false), '').trim();
      title = title.replaceFirst(RegExp('$assignedToName,?\\s*', caseSensitive: false), '').trim();
    }

    // Clean up common prefixes
    title = title.replaceFirst(RegExp('^(please|can you|could you|would you)\\s+', caseSensitive: false), '');
    title = title.replaceFirst(RegExp('^(hey|hi|hello)\\s+', caseSensitive: false), '');

    // Capitalize first letter
    if (title.isNotEmpty) {
      title = title[0].toUpperCase() + title.substring(1);
    }

    // Check for due date mentions
    DateTime? dueDate;
    for (var day in _days) {
      if (lowerMessage.contains(day)) {
        // Simple heuristic: if "today" or "tonight", set to today
        if (day == 'today' || day == 'tonight') {
          dueDate = DateTime.now();
        } else if (day == 'tomorrow') {
          dueDate = DateTime.now().add(const Duration(days: 1));
        }
        // For specific days, we'd need more complex date parsing
        break;
      }
    }

    return DetectedTaskInfo(
      isTask: true,
      title: title,
      description: message,
      assignedTo: assignedTo,
      assignedToName: assignedToName,
      dueDate: dueDate,
    );
  }

  /// Check if text mentions "by [date/time]" patterns
  static String? extractDeadline(String message) {
    final byPattern = RegExp(r'by\s+(\w+)', caseSensitive: false);
    final match = byPattern.firstMatch(message);
    return match?.group(1);
  }
}

/// Simple detected task info (without AI)
class DetectedTaskInfo {
  final bool isTask;
  final String? title;
  final String? description;
  final String? assignedTo;
  final String? assignedToName;
  final DateTime? dueDate;

  DetectedTaskInfo({
    required this.isTask,
    this.title,
    this.description,
    this.assignedTo,
    this.assignedToName,
    this.dueDate,
  });
}
