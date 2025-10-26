import 'package:firebase_ai/firebase_ai.dart';
import 'dart:convert';

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
You are an AI assistant that helps identify tasks and agendas from group chat messages.

Analyze the following message and determine if it contains a task, action item, or agenda that should be tracked.

Message: "$message"
Sender: $senderName
House members: $memberNames

A task is typically:
- A request or instruction for someone to do something
- An action item mentioned in an agenda
- A chore or responsibility assignment
- Something that needs to be done by a specific person or in general

Extract the following information if it's a task:
1. isTask: true/false - whether this message contains a task
2. title: A short, clear title for the task (max 50 characters)
3. description: A brief description of what needs to be done
4. assignedTo: The name of the person assigned (if mentioned), or null if general/unassigned
5. dueDate: ISO 8601 date string if a due date is mentioned, otherwise null

House member details for assignment:
$memberIds

Respond ONLY with a valid JSON object in this exact format (no markdown, no code blocks, just the JSON):
{"isTask": boolean, "title": "string or null", "description": "string or null", "assignedTo": "name or null", "dueDate": "ISO date or null"}

Examples:
Message: "Can someone take out the trash tonight?"
{"isTask": true, "title": "Take out the trash", "description": "Take out the trash tonight", "assignedTo": null, "dueDate": null}

Message: "John, please buy groceries by Friday"
{"isTask": true, "title": "Buy groceries", "description": "Buy groceries by Friday", "assignedTo": "John", "dueDate": null}

Message: "Hey everyone, how's it going?"
{"isTask": false, "title": null, "description": null, "assignedTo": null, "dueDate": null}

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
Summarize the following agenda item in 1-2 concise sentences:

Title: $title
Details: $details

Provide only the summary, no additional text:
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
