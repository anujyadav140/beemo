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
    final trimmedMessage = message.trim();

    // Filter 1: Ignore very short messages (likely casual chat)
    if (trimmedMessage.length < 10) {
      print('Task detection: Rejected (too short) - "$trimmedMessage"');
      return null;
    }

    // Filter 2: Ignore common greetings and casual phrases
    final casualPhrases = [
      'hey', 'hi ', 'hello', 'good morning', 'good night', 'good evening',
      'how are you', 'whats up', 'what\'s up', 'how\'s it going',
      'anyone home', 'i\'m home', 'im home', 'heading out',
      'on my way', 'be back', 'brb', 'gtg', 'lol', 'lmao', 'haha',
      'thanks', 'thank you', 'ok', 'okay', 'sure', 'sounds good',
      'love you', 'miss you', 'see you', 'bye', 'later',
    ];

    for (var phrase in casualPhrases) {
      if (lowerMessage.startsWith(phrase) ||
          lowerMessage == phrase ||
          (lowerMessage.length < 30 && lowerMessage.contains(phrase))) {
        print('Task detection: Rejected (casual phrase: "$phrase") - "$trimmedMessage"');
        return null; // Casual chat, not a task
      }
    }

    // Filter 3: Must contain task-like action verbs
    final hasTaskVerb = _taskVerbs.any((verb) =>
      lowerMessage.contains(verb) ||
      lowerMessage.contains('$verb ') ||
      lowerMessage.contains(' $verb')
    );

    if (!hasTaskVerb) {
      print('Task detection: Rejected (no action verb) - "$trimmedMessage"');
      return null; // Not a task
    }

    // Filter 4: Check if it's an IMPERATIVE command (starts with task verb)
    // Examples: "clean the table", "buy groceries", "take out trash"
    bool isImperativeCommand = false;
    for (var verb in _taskVerbs) {
      // Check if message starts with the verb followed by space or is exactly the verb
      // This handles: "clean the table", "clean", but NOT "cleaning supplies"
      if (lowerMessage == verb ||
          lowerMessage.startsWith('$verb ') ||
          lowerMessage.startsWith('$verb\t')) {
        isImperativeCommand = true;
        print('Task detection: Detected imperative command starting with "$verb" - "$trimmedMessage"');
        break;
      }
    }

    // Filter 5: Check for request indicators
    final requestIndicators = [
      'can someone', 'could someone', 'anyone', 'someone',
      'please', 'need to', 'needs to', 'should',
      'can you', 'could you', 'would you', 'will you',
      'reminder', 'don\'t forget', 'remember to',
      'we need', 'we should', 'lets ', 'let\'s ',
    ];

    final hasRequestIndicator = requestIndicators.any((indicator) =>
      lowerMessage.contains(indicator)
    );

    // Filter 6: Or must directly address someone by name
    bool directlyAddressed = false;
    for (var member in houseMembers) {
      final memberName = member['name']!.toLowerCase();
      final firstName = memberName.split(' ').first;

      if (lowerMessage.startsWith('$firstName,') ||
          lowerMessage.startsWith('$memberName,')) {
        directlyAddressed = true;
        break;
      }
    }

    // Must have either: imperative command, request indicator, OR be directly addressed
    if (!isImperativeCommand && !hasRequestIndicator && !directlyAddressed) {
      print('Task detection: Rejected (no imperative/request indicator/direct address) - "$trimmedMessage"');
      return null; // Just a statement, not a task request
    }

    print('Task detection: ACCEPTED as task - "$trimmedMessage"');

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
