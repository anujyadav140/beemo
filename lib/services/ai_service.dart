import 'package:firebase_ai/firebase_ai.dart';
import 'dart:convert';
import '../models/chat_message_model.dart';

class DetectedTask {
  final bool isTask;
  final String? title;
  final String? description;
  final String? assignedTo;
  final DateTime? dueDate;

  DetectedTask({
    required this.isTask,
    this.title,
    this.description,
    this.assignedTo,
    this.dueDate,
  });

  factory DetectedTask.fromJson(Map<String, dynamic> json) {
    return DetectedTask(
      isTask: json['isTask'] ?? false,
      title: json['title'],
      description: json['description'],
      assignedTo: json['assignedTo'],
      dueDate: json['dueDate'] != null ? DateTime.tryParse(json['dueDate']) : null,
    );
  }
}

class BeemoMeetingPlan {
  final List<String> messages;
  final DateTime? scheduledTime;
  final String? scheduledSummary;
  final bool shouldSchedule;

  BeemoMeetingPlan({
    required this.messages,
    required this.scheduledTime,
    required this.scheduledSummary,
    required this.shouldSchedule,
  });

  factory BeemoMeetingPlan.empty() => BeemoMeetingPlan(
        messages: const [],
        scheduledTime: null,
        scheduledSummary: null,
        shouldSchedule: false,
      );
}

class AIService {
  late final GenerativeModel _model;

  AIService() {
    // Initialize the Gemini model via Firebase AI Logic
    _model = FirebaseAI.vertexAI().generativeModel(
      model: 'gemini-2.5-flash',
    );
  }

  /// Analyzes a chat message to detect if it contains a task/agenda
  /// Returns a DetectedTask object with extracted information
  Future<DetectedTask> analyzeMessageForTask(
    String message,
    String senderName,
    List<Map<String, String>> houseMembers,
  ) async {
    try {
      // Create a list of member names for the AI to reference
      final memberNames = houseMembers.map((m) => m['name']).join(', ');
      final memberIds = houseMembers.map((m) => '${m['name']} (ID: ${m['id']})').join(', ');

      final prompt = '''
You are a STRICT task detector for a household management app. Be CONSERVATIVE - only identify CLEAR, ACTIONABLE tasks.

Message: "$message"
Sender: $senderName
House members: $memberNames

CRITICAL: A task MUST meet ALL these criteria:
✅ Contains a CLEAR action verb (clean, buy, take, fix, organize, etc.)
✅ Describes something SPECIFIC that needs to be done
✅ Is a REQUEST, INSTRUCTION, or ASSIGNMENT (not a question, statement, or casual chat)
✅ Is about HOUSEHOLD CHORES or RESPONSIBILITIES

❌ NOT TASKS - REJECT these immediately:
- Greetings ("hey", "hi", "hello", "good morning")
- Questions about status ("how's it going?", "what's up?", "anyone home?")
- Statements of fact ("I'm going to the store", "the trash is full", "it's cold today")
- General discussion ("I think we should...", "maybe we could...")
- Emotional expressions ("I'm tired", "this sucks", "love you guys")
- Plans or suggestions WITHOUT a clear request ("we should clean sometime", "thinking about organizing")
- Reminders about existing tasks ("don't forget about X")
- Responses to other messages ("ok", "sure", "sounds good", "lol")

House member details:
$memberIds

Respond ONLY with JSON (no markdown, no code blocks):
{"isTask": boolean, "title": "string or null", "description": "string or null", "assignedTo": "name or null", "dueDate": "ISO date or null"}

EXAMPLES OF TASKS (isTask: true):
"Can someone take out the trash tonight?" → {"isTask": true, "title": "Take out trash", "description": "Take out the trash tonight", "assignedTo": null, "dueDate": null}
"John, please buy groceries by Friday" → {"isTask": true, "title": "Buy groceries", "description": "Buy groceries by Friday", "assignedTo": "John", "dueDate": null}
"Someone needs to clean the kitchen" → {"isTask": true, "title": "Clean kitchen", "description": "Clean the kitchen", "assignedTo": null, "dueDate": null}

EXAMPLES OF NON-TASKS (isTask: false):
"Hey everyone, how's it going?" → {"isTask": false, "title": null, "description": null, "assignedTo": null, "dueDate": null}
"I'm heading to the store" → {"isTask": false, "title": null, "description": null, "assignedTo": null, "dueDate": null}
"The trash is full" → {"isTask": false, "title": null, "description": null, "assignedTo": null, "dueDate": null}
"What's for dinner?" → {"isTask": false, "title": null, "description": null, "assignedTo": null, "dueDate": null}
"Anyone home?" → {"isTask": false, "title": null, "description": null, "assignedTo": null, "dueDate": null}
"I think we should organize the garage" → {"isTask": false, "title": null, "description": null, "assignedTo": null, "dueDate": null}
"good morning everyone" → {"isTask": false, "title": null, "description": null, "assignedTo": null, "dueDate": null}
"lol" → {"isTask": false, "title": null, "description": null, "assignedTo": null, "dueDate": null}

Now analyze the message above and respond with JSON only:
''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      if (response.text == null || response.text!.isEmpty) {
        return DetectedTask(isTask: false);
      }

      // Clean the response text to extract JSON
      String responseText = response.text!.trim();

      // Remove markdown code blocks if present
      if (responseText.startsWith('```json')) {
        responseText = responseText.replaceFirst('```json', '').trim();
      }
      if (responseText.startsWith('```')) {
        responseText = responseText.replaceFirst('```', '').trim();
      }
      if (responseText.endsWith('```')) {
        responseText = responseText.substring(0, responseText.length - 3).trim();
      }

      // Parse the JSON response
      final decodedResponse = json.decode(responseText);

      // Ensure we have a Map, not a List or other type
      if (decodedResponse is! Map<String, dynamic>) {
        print('AI response is not a Map: $decodedResponse');
        return DetectedTask(isTask: false);
      }

      final jsonResponse = decodedResponse as Map<String, dynamic>;

      // If assignedTo is mentioned, try to match it to a house member ID
      String? assignedToId;
      if (jsonResponse['assignedTo'] != null) {
        final assignedName = jsonResponse['assignedTo'].toString().toLowerCase();
        for (var member in houseMembers) {
          if (member['name']?.toLowerCase().contains(assignedName) ?? false) {
            assignedToId = member['id'];
            break;
          }
        }
      }

      return DetectedTask(
        isTask: jsonResponse['isTask'] ?? false,
        title: jsonResponse['title'],
        description: jsonResponse['description'],
        assignedTo: assignedToId,
        dueDate: jsonResponse['dueDate'] != null
            ? DateTime.tryParse(jsonResponse['dueDate'])
            : null,
      );
    } catch (e) {
      print('Error analyzing message for task: $e');
      return DetectedTask(isTask: false);
    }
  }

  /// Generates a smart summary of an agenda item
  Future<String> summarizeAgenda(String title, String details) async {
    try {
      final prompt = '''
You are helping a household assistant restate an agenda item without losing meaning.

Rewrite the agenda below in up to 2 sentences while preserving every important detail.
- Keep specific requests, names, dates, numbers, and constraints exactly as provided.
- If the original text is already short or crystal clear, return it unchanged.
- Never remove context or soften the user's wording.

Title: $title
Details: $details

Return only the rewritten text (no bullet points, no extra commentary):
''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      return response.text?.trim() ?? details;
    } catch (e) {
      print('Error summarizing agenda: $e');
      return details;
    }
  }

  /// Suggests task assignments based on past history and workload
  Future<String?> suggestTaskAssignment(
    String taskDescription,
    List<Map<String, dynamic>> members,
  ) async {
    try {
      final memberInfo = members.map((m) {
        return '${m['name']} (Current tasks: ${m['taskCount'] ?? 0}, Points: ${m['points'] ?? 0})';
      }).join('\n');

      final prompt = '''
Based on the following task and household members' current workload, suggest the most appropriate person to assign this task to.

Task: $taskDescription

Members:
$memberInfo

Consider:
- Balanced workload distribution
- Members with fewer current tasks
- Fair rotation of responsibilities

Respond with ONLY the name of the suggested member, or "unassigned" if no clear match. No additional text:
''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      final suggestion = response.text?.trim();

      // Match suggestion to a member ID
      if (suggestion != null && suggestion.toLowerCase() != 'unassigned') {
        for (var member in members) {
          if (member['name']?.toLowerCase() == suggestion.toLowerCase()) {
            return member['id'];
          }
        }
      }

      return null;
    } catch (e) {
      print('Error suggesting task assignment: $e');
      return null;
    }
  }

  Future<BeemoMeetingPlan> planWeeklyCheckInMeeting({
    required String houseName,
    required List<Map<String, String>> members,
    required List<ChatMessage> recentMessages,
    DateTime? lastScheduledTime,
  }) async {
    try {
      final currentUtc = DateTime.now().toUtc().toIso8601String();

      final memberLines = members.isEmpty
          ? 'No other members listed yet.'
          : members
              .map((member) =>
                  '- ${member['name'] ?? 'Unknown'} (id: ${member['id'] ?? 'unknown'})')
              .join('\n');

      final orderedMessages = List<ChatMessage>.from(recentMessages)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final trimmedMessages = orderedMessages.length > 15
          ? orderedMessages.sublist(orderedMessages.length - 15)
          : orderedMessages;

      final transcript = trimmedMessages.isEmpty
          ? 'No recent chat messages.'
          : trimmedMessages
              .map((msg) =>
                  '${msg.senderName}: ${msg.message.replaceAll('\n', ' ').trim()}')
              .join('\n');

      final lastMeetingIso =
          lastScheduledTime != null ? lastScheduledTime.toUtc().toIso8601String() : 'none';

      final prompt = '''
You are Beemo, the friendly AI coordinator for a house. Help the household schedule a 15-minute weekly check-in meeting.

Context:
- Current UTC time: $currentUtc
- House name: $houseName
- Last scheduled weekly check-in (if any): $lastMeetingIso
- Members:
$memberLines
- Recent chat transcript (oldest to newest):
$transcript

Instructions:
1. Consider the availability hints inside the transcript. If there is not enough information, propose reasonable default slots (e.g., weekday early evening) and invite members to weigh in.
2. Compose up to 3 Beemo chat messages, each no longer than two concise sentences (~200 characters). Keep the tone encouraging and helpful.
3. Use Markdown sparingly for clarity – e.g., **bold** for proposed times, bullet lists for options, short emoji if it adds warmth.
4. Decide whether enough information exists to pick a meeting time now. If yes, choose a single ISO 8601 UTC timestamp within the next seven days that works for everyone (recurring weekly) and write a concise summary (e.g., "**Friday at 1:00 PM**").
5. If there is NOT enough agreement, set shouldSchedule to false and leave scheduledTime and summary as null. In your messages, clearly ask members what else you still need and remind them gently.

Respond ONLY with valid JSON (no markdown, no commentary) in this format:
{
  "messages": ["string", "string", "..."],
  "finalDecision": {
    "shouldSchedule": true/false,
    "scheduledTime": "ISO8601-UTC string or null",
    "summary": "short human summary or null"
  }
}
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      if (response.text == null || response.text!.trim().isEmpty) {
        return BeemoMeetingPlan.empty();
      }

      String responseText = response.text!.trim();
      if (responseText.startsWith('```json')) {
        responseText = responseText.replaceFirst('```json', '').trim();
      }
      if (responseText.startsWith('```')) {
        responseText = responseText.replaceFirst('```', '').trim();
      }
      if (responseText.endsWith('```')) {
        responseText = responseText.substring(0, responseText.length - 3).trim();
      }

      final decoded = json.decode(responseText);
      if (decoded is! Map<String, dynamic>) {
        print('Meeting planner response not a map: $decoded');
        return BeemoMeetingPlan.empty();
      }

      final rawMessages = decoded['messages'];
      final finalDecision = decoded['finalDecision'] as Map<String, dynamic>?;

      final messages = rawMessages is List
          ? rawMessages.whereType<String>().map((m) => m.trim()).where((m) => m.isNotEmpty).toList()
          : <String>[];

      bool shouldSchedule = false;
      DateTime? scheduledTime;
      String? summary;

      if (finalDecision != null) {
        shouldSchedule = finalDecision['shouldSchedule'] == true;
        final scheduledIso = finalDecision['scheduledTime'] as String?;
        summary = finalDecision['summary'] as String?;
        if (scheduledIso != null && scheduledIso.isNotEmpty) {
          try {
            scheduledTime = DateTime.parse(scheduledIso).toUtc();
          } catch (e) {
            print('Unable to parse scheduled time: $scheduledIso');
            scheduledTime = null;
          }
        }
      }

      return BeemoMeetingPlan(
        messages: messages,
        scheduledTime: scheduledTime,
        scheduledSummary: summary,
        shouldSchedule: shouldSchedule && scheduledTime != null,
      );
    } catch (e) {
      print('Error planning weekly check-in: $e');
      return BeemoMeetingPlan.empty();
    }
  }

  Future<BeemoMeetingPlan> followUpWeeklyCheckIn({
    required String houseName,
    required List<Map<String, String>> members,
    required List<ChatMessage> recentMessages,
    DateTime? lastScheduledTime,
  }) async {
    try {
      final currentUtc = DateTime.now().toUtc().toIso8601String();

      final memberLines = members.isEmpty
          ? 'No other members listed yet.'
          : members
              .map((member) =>
                  '- ${member['name'] ?? 'Unknown'} (id: ${member['id'] ?? 'unknown'})')
              .join('\n');

      final orderedMessages = List<ChatMessage>.from(recentMessages)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final transcript = orderedMessages.isEmpty
          ? 'No chat messages yet.'
          : orderedMessages
              .map(
                (msg) =>
                    '${msg.senderName}${msg.isBeemo ? " (Beemo)" : ""}: ${msg.message.replaceAll('\n', ' ').trim()}',
              )
              .join('\n');

      final lastMeetingIso =
          lastScheduledTime != null ? lastScheduledTime.toUtc().toIso8601String() : 'none';

      final prompt = '''
You are Beemo, the AI coordinator for a household. A weekly 15-minute check-in is being organised in the chat.

Context:
- Current UTC time: $currentUtc
- House name: $houseName
- Last scheduled weekly check-in (if any): $lastMeetingIso
- Members:
$memberLines
- Full conversation transcript (oldest to newest):
$transcript

Your goals right now:
1. Detect if there are NEW human replies since your latest Beemo message and decide if consensus has been reached.
2. If everyone has agreed (explicitly or implicitly) on a specific slot, lock it in: set shouldSchedule to true, provide the ISO 8601 UTC timestamp, and craft one short confirmation message (<=2 sentences) summarising the decision.
3. If more input is required, craft up to 2 concise follow-up messages (<=2 sentences each, max ~200 characters). Use Markdown for clarity (**bold**, bullet lists) and mention only the slots still under consideration. Ask missing participants by name if helpful.
4. If there is no new information since your last response, return an empty "messages" array and set shouldSchedule to false.
5. Never repeat the exact same wording in consecutive turns; keep the conversation feeling fresh and supportive.

Respond ONLY with valid JSON (no markdown, no commentary) in this format:
{
  "messages": ["string", "string", "..."],
  "finalDecision": {
    "shouldSchedule": true/false,
    "scheduledTime": "ISO8601-UTC string or null",
    "summary": "short human summary or null"
  }
}
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      if (response.text == null || response.text!.trim().isEmpty) {
        return BeemoMeetingPlan.empty();
      }

      String responseText = response.text!.trim();
      if (responseText.startsWith('```json')) {
        responseText = responseText.replaceFirst('```json', '').trim();
      }
      if (responseText.startsWith('```')) {
        responseText = responseText.replaceFirst('```', '').trim();
      }
      if (responseText.endsWith('```')) {
        responseText = responseText.substring(0, responseText.length - 3).trim();
      }

      final decoded = json.decode(responseText);
      if (decoded is! Map<String, dynamic>) {
        print('Meeting follow-up response not a map: $decoded');
        return BeemoMeetingPlan.empty();
      }

      final rawMessages = decoded['messages'];
      final finalDecision = decoded['finalDecision'] as Map<String, dynamic>?;

      final messages = rawMessages is List
          ? rawMessages.whereType<String>().map((m) => m.trim()).where((m) => m.isNotEmpty).toList()
          : <String>[];

      bool shouldSchedule = false;
      DateTime? scheduledTime;
      String? summary;

      if (finalDecision != null) {
        shouldSchedule = finalDecision['shouldSchedule'] == true;
        final scheduledIso = finalDecision['scheduledTime'] as String?;
        summary = finalDecision['summary'] as String?;
        if (scheduledIso != null && scheduledIso.isNotEmpty) {
          try {
            scheduledTime = DateTime.parse(scheduledIso).toUtc();
          } catch (e) {
            print('Unable to parse scheduled time: $scheduledIso');
            scheduledTime = null;
          }
        }
      }

      return BeemoMeetingPlan(
        messages: messages,
        scheduledTime: scheduledTime,
        scheduledSummary: summary,
        shouldSchedule: shouldSchedule && scheduledTime != null,
      );
    } catch (e) {
      print('Error in follow-up weekly check-in: $e');
      return BeemoMeetingPlan.empty();
    }
  }

  /// Generates tasks from an agenda item using AI
  /// Breaks down the agenda into actionable tasks for the assigned user
  Future<List<DetectedTask>> generateTasksFromAgenda({
    required String title,
    required String details,
    required String assignedToName,
    required String assignedToId,
  }) async {
    try {
      final prompt = '''
You are an AI assistant that helps convert agenda items into actionable tasks for household members.

CRITICAL: Your job is to preserve the user's exact intent and create tasks that accurately reflect what they wrote. Do NOT add extra tasks or change their requirements.

Analyze the following agenda item and convert it into 1-3 tasks:

Agenda Title: "$title"
Agenda Details: "$details"
Assigned To: $assignedToName

Guidelines:
- STAY FAITHFUL to the user's original text - don't add tasks they didn't mention
- If the agenda is already a specific, single action, create just 1 task that matches it exactly
- Only break into multiple tasks if the user clearly described multiple distinct steps
- Keep task titles short (max 50 characters) but ACCURATE to what the user wrote
- Each task description should preserve the user's exact requirements and wording when possible
- Do NOT invent additional steps or requirements the user didn't mention

Respond ONLY with a valid JSON array in this exact format (no markdown, no code blocks, just the JSON):
[
  {"title": "Task title", "description": "What needs to be done"},
  {"title": "Task title", "description": "What needs to be done"}
]

Examples:

User writes: "Plan grocery shopping for the week"
[
  {"title": "Make shopping list", "description": "List all needed items for the week"},
  {"title": "Go to grocery store", "description": "Buy all items from the list"},
  {"title": "Put groceries away", "description": "Organize groceries in pantry and fridge"}
]

User writes: "Fix the leaky kitchen faucet"
[
  {"title": "Fix kitchen faucet leak", "description": "Repair or replace the leaky faucet in the kitchen"}
]

User writes: "Buy milk from the store"
[
  {"title": "Buy milk from the store", "description": "Buy milk from the store"}
]

User writes: "Organize monthly house meeting: send calendar invite, prepare agenda with budget discussion"
[
  {"title": "Send calendar invite", "description": "Send calendar invite for monthly house meeting"},
  {"title": "Prepare meeting agenda", "description": "Prepare agenda including budget discussion"}
]

Now analyze the agenda above and respond with JSON only:
''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      if (response.text == null || response.text!.isEmpty) {
        return [];
      }

      // Clean the response text to extract JSON
      String responseText = response.text!.trim();

      // Remove markdown code blocks if present
      if (responseText.startsWith('```json')) {
        responseText = responseText.replaceFirst('```json', '').trim();
      }
      if (responseText.startsWith('```')) {
        responseText = responseText.replaceFirst('```', '').trim();
      }
      if (responseText.endsWith('```')) {
        responseText = responseText.substring(0, responseText.length - 3).trim();
      }

      // Parse the JSON response
      final decodedResponse = json.decode(responseText);

      // Ensure we have a List
      if (decodedResponse is! List) {
        print('AI response is not a List: $decodedResponse');
        return [];
      }

      final List<dynamic> jsonResponse = decodedResponse as List<dynamic>;

      // Convert to DetectedTask objects
      List<DetectedTask> tasks = [];
      for (var taskJson in jsonResponse) {
        // Ensure each task is a Map
        if (taskJson is! Map<String, dynamic>) {
          continue;
        }
        tasks.add(DetectedTask(
          isTask: true,
          title: taskJson['title'],
          description: taskJson['description'],
          assignedTo: assignedToId,
          dueDate: null, // Can be set by the user later
        ));
      }

      return tasks;
    } catch (e) {
      print('Error generating tasks from agenda: $e');
      return [];
    }
  }
}
