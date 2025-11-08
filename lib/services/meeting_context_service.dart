import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import '../models/agenda_item_model.dart';

/// Service that manages meeting context, transcription, and intelligence
class MeetingContextService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StreamController<TranscriptEntry> _transcriptController =
      StreamController<TranscriptEntry>.broadcast();

  Stream<TranscriptEntry> get transcriptStream => _transcriptController.stream;

  /// Fetch meeting context from Firebase to provide Beemo with conversation context
  ///
  /// Firebase Collections Accessed:
  /// 1. agendaItems (TOP-LEVEL collection)
  ///    - Fetches pending agenda items marked for the meeting
  ///    - Filters: houseId={houseId}, priority='meeting', status='pending'
  ///    - Ordered by creation date (oldest first)
  ///    - Limited to 10 items
  ///
  /// 2. meetingRooms/{meetingId}/participants
  ///    - Fetches ALL meeting participants (no status filter)
  ///    - Includes: displayName, avatarEmoji, status
  ///    - AGGRESSIVE RETRY: Up to 5 attempts with 1.5s delay between (participants join after Beemo starts)
  ///
  /// Returns: MeetingContext with agendas, participants, and meeting metadata
  Future<MeetingContext> fetchMeetingContext({
    required String houseId,
    required String meetingId,
    List<dynamic>? liveParticipants, // Real-time participants from signaling service
  }) async {
    try {
      debugPrint('📋 Fetching meeting context from Firebase for $meetingId...');

      // 1. Fetch agendas from Firebase (TOP-LEVEL agendaItems collection)
      debugPrint('  → Fetching agendas from agendaItems (filtered by houseId: $houseId)...');
      final agendasSnapshot = await _firestore
          .collection('agendaItems')  // TOP-LEVEL collection, not nested
          .where('houseId', isEqualTo: houseId)  // Filter by houseId field
          .where('priority', isEqualTo: 'meeting')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt')
          .limit(10)
          .get();

      final agendas = agendasSnapshot.docs
          .map((doc) => AgendaItem.fromFirestore(doc))
          .toList();

      // DEBUG: Print all fetched agendas
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('📋 FETCHED AGENDAS FROM FIREBASE: ${agendas.length} items');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      if (agendas.isEmpty) {
        debugPrint('⚠️ NO AGENDAS FOUND!');
      } else {
        for (var i = 0; i < agendas.length; i++) {
          debugPrint('${i + 1}. "${agendas[i].title}"');
          debugPrint('   Details: ${agendas[i].details}');
        }
      }
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

      // 2. Get participants from real-time signaling service OR fetch from Firebase
      List<MeetingParticipant> participants;

      if (liveParticipants != null && liveParticipants.isNotEmpty) {
        // USE REAL-TIME PARTICIPANTS FROM SIGNALING SERVICE (preferred!)
        debugPrint('  ✅ Using ${liveParticipants.length} live participants from signaling service');
        participants = liveParticipants.map((p) {
          return MeetingParticipant(
            userId: p.userId,
            displayName: p.displayName,
            avatarEmoji: p.avatarEmoji ?? '🙂',
          );
        }).toList();
      } else {
        // Fallback: Fetch from Firebase if no live participants available
        debugPrint('  → Fetching participants from meetingRooms/$meetingId/participants...');

        QuerySnapshot<Map<String, dynamic>>? participantsSnapshot;
        int retries = 0;
        const maxRetries = 5;

        // Keep retrying until we find participants or max retries reached
        while (retries < maxRetries) {
          debugPrint('  → Attempt ${retries + 1}/$maxRetries: Fetching participants...');
          participantsSnapshot = await _firestore
              .collection('meetingRooms')
              .doc(meetingId)
              .collection('participants')
              .get();

          debugPrint('     Firebase returned ${participantsSnapshot.docs.length} documents');

          if (participantsSnapshot.docs.isNotEmpty) {
            for (var doc in participantsSnapshot.docs) {
              final data = doc.data();
              debugPrint('     Found: ${data['displayName']} (${doc.id}) [status: ${data['status']}]');
            }
            debugPrint('  ✅ Found ${participantsSnapshot.docs.length} participants!');
            break;
          }

          retries++;
          if (retries < maxRetries) {
            debugPrint('  ⏳ No participants found, waiting 1.5 seconds (attempt $retries/$maxRetries)...');
            await Future.delayed(const Duration(milliseconds: 1500));
          } else {
            debugPrint('  ⚠️ Max retries reached - proceeding with 0 participants');
          }
        }

        participants = participantsSnapshot?.docs.map((doc) {
          final data = doc.data();
          return MeetingParticipant(
            userId: doc.id,
            displayName: data['displayName'] ?? 'Member',
            avatarEmoji: data['avatarEmoji'] ?? '🙂',
          );
        }).toList() ?? [];
      }

      // DEBUG: Print all participants being used
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('👥 PARTICIPANTS FOR BEEMO: ${participants.length} people');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      if (participants.isEmpty) {
        debugPrint('⚠️ NO PARTICIPANTS FOUND!');
      } else {
        for (var i = 0; i < participants.length; i++) {
          debugPrint('${i + 1}. ${participants[i].avatarEmoji} ${participants[i].displayName} (ID: ${participants[i].userId})');
        }
      }
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

      debugPrint('✅ Firebase context fetched: ${agendas.length} agendas, ${participants.length} participants');

      return MeetingContext(
        houseId: houseId,
        meetingId: meetingId,
        agendas: agendas,
        participants: participants,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching Firebase context: $e');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  /// Build Beemo's system prompt with Firebase-fetched meeting context
  ///
  /// This dynamically builds the prompt using:
  /// - Participant data from Firebase (meetingRooms/{meetingId}/participants)
  /// - Agenda data from Firebase (agendaItems collection, filtered by houseId)
  /// - Meeting metadata
  String buildBeemoPrompt(MeetingContext context) {
    // Build participant list from Firebase data
    final participantNames = context.participants
        .map((p) => '${p.avatarEmoji} ${p.displayName}')
        .join(', ');

    final participantCount = context.participants.length;

    // Build detailed agenda list from Firebase data
    final agendaList = context.agendas.isEmpty
        ? 'No specific agendas - facilitate general discussion.'
        : context.agendas
            .asMap()
            .entries
            .map((entry) =>
                '${entry.key + 1}. "${entry.value.title}"\n   Details: ${entry.value.details}')
            .join('\n\n');

    // DEBUG: Print the components being used to build the prompt
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🤖 BUILDING BEEMO PROMPT WITH:');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('Participant Count: $participantCount');
    debugPrint('Participant Names: $participantNames');
    debugPrint('Agenda Count: ${context.agendas.length}');
    debugPrint('Agenda List:\n$agendaList');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    final prompt = '''
You are Beemo - a warm, empathetic AI psychologist and meeting facilitator for roommates!

⚡ WHEN YOU GET "START" SIGNAL: IMMEDIATELY take charge and start the meeting with energy!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 THIS MEETING'S INFORMATION (FETCHED FROM FIREBASE):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

👥 PARTICIPANTS IN THIS MEETING: $participantCount people
$participantNames

🎯 AGENDA ITEMS FOR THIS MEETING: ${context.agendas.length} ${context.agendas.length == 1 ? 'item' : 'items'}
$agendaList

Meeting ID: ${context.meetingId}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 YOUR ROLE AS PSYCHOLOGIST-FACILITATOR:

You are NOT a passive listener - you are an ACTIVE, PROACTIVE psychologist who:
- Starts conversations and asks direct questions
- Makes sure EVERY person shares their perspective on EVERY agenda
- Gives thoughtful, valuable feedback and insights
- Helps resolve conflicts and find compromises
- Validates feelings while guiding toward solutions

🔥 HOW TO FACILITATE (BE VERY PROACTIVE):

1. START THE MEETING (when you get "START" signal):
   - Greet warmly: "Hey everyone! Beemo here! So happy to have all $participantCount of you: $participantNames"
   - Preview agendas: "We've got ${context.agendas.length} important things to discuss today!"
   - Dive in immediately: "Let's jump right into our first topic..."

2. FOR EACH AGENDA ITEM - Use this exact structure:

   a) INTRODUCE THE AGENDA (5 seconds):
      "Okay, agenda ${context.agendas.isNotEmpty ? '1' : ''}: [TITLE]"

   b) ASK EACH PERSON DIRECTLY (be specific with names):
      ${context.participants.map((p) => '- "${p.displayName}, what are your thoughts on this?"').join('\n      ')}

   c) AFTER EACH PERSON SPEAKS:
      - Validate: "I hear you, that makes sense..."
      - Probe deeper: "Can you tell me more about why you feel that way?"
      - Ask follow-up: "How does that affect you day-to-day?"

   d) GIVE PSYCHOLOGICAL INSIGHTS:
      - Notice patterns: "I'm hearing that everyone feels..."
      - Highlight common ground: "It sounds like you both want..."
      - Suggest compromises: "What if we tried..."
      - Offer perspective: "From a household harmony standpoint..."

   e) SUMMARIZE & GET CONSENSUS:
      "So here's what I'm hearing... Does that sound fair to everyone?"

3. MANAGE THE CONVERSATION:
   - If someone hasn't spoken: "[Name], we haven't heard from you yet - what do you think?"
   - If conflict arises: "I can see both perspectives here. Let's find middle ground..."
   - If vague answers: "Can you be more specific about what bothers you?"
   - If someone dominates: "[Name], thanks! Now let's hear from [Other Name]..."

4. WRAP UP:
   - Summarize decisions for ALL agendas
   - Celebrate progress: "Great work today, everyone!"
   - Check in: "How does everyone feel about what we decided?"

💬 VOICE CHAT RULES:
- Keep responses SHORT (2-3 sentences max)
- Be warm, empathetic, encouraging
- Ask DIRECT QUESTIONS to specific people by name
- Don't wait for people to volunteer - ASK them directly
- Give brief but meaningful feedback
- Use phrases like: "Tell me more...", "How does that make you feel?", "What would help?"

🚨 CRITICAL: You must be PROACTIVE! Don't wait for silence - guide the conversation!
After someone speaks, IMMEDIATELY ask the next person or give feedback.

YOU ARE THE PSYCHOLOGIST - LEAD THE DISCUSSION!

Remember: Be brief but impactful. This is VOICE chat - keep it conversational and moving!
''';

    // DEBUG: Print the FULL PROMPT being sent to Beemo
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📤 FULL BEEMO SYSTEM PROMPT:');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint(prompt);
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    return prompt;
  }

  /// Add a transcript entry to the meeting
  Future<void> addTranscriptEntry({
    required String meetingId,
    required String speaker,
    required String text,
    required String speakerType, // 'user' or 'beemo'
  }) async {
    try {
      final entry = TranscriptEntry(
        speaker: speaker,
        text: text,
        timestamp: DateTime.now(),
        speakerType: speakerType,
      );

      // Add to Firestore
      await _firestore
          .collection('meetingRooms')
          .doc(meetingId)
          .collection('transcript')
          .add(entry.toMap());

      // Emit to stream for real-time UI updates
      _transcriptController.add(entry);

      debugPrint('💬 Transcript added: [$speaker] $text');
    } catch (e) {
      debugPrint('❌ Error adding transcript: $e');
    }
  }

  /// Generate meeting recap/summary using Gemini
  Future<MeetingRecap> generateMeetingRecap({
    required String meetingId,
    required MeetingContext context,
  }) async {
    try {
      debugPrint('📝 Generating meeting recap...');

      // Fetch full transcript
      final transcriptSnapshot = await _firestore
          .collection('meetingRooms')
          .doc(meetingId)
          .collection('transcript')
          .orderBy('timestamp')
          .get();

      final transcript = transcriptSnapshot.docs.map((doc) {
        final data = doc.data();
        return TranscriptEntry.fromMap(data);
      }).toList();

      if (transcript.isEmpty) {
        debugPrint('⚠️ No transcript found for meeting');
        return MeetingRecap(
          summary: 'No discussion recorded',
          decisions: [],
          tasks: [],
          keyPoints: [],
          participantCount: context.participants.length,
        );
      }

      // Build transcript text
      final transcriptText = transcript
          .map((entry) =>
              '[${entry.timestamp.hour}:${entry.timestamp.minute.toString().padLeft(2, '0')}] ${entry.speaker}: ${entry.text}')
          .join('\n');

      // Use Gemini to generate summary
      final model = FirebaseAI.vertexAI().generativeModel(
        model: 'gemini-2.0-flash-lite-preview-12-19',
      );

      final prompt = '''
Analyze this meeting transcript and generate a structured summary.

MEETING TRANSCRIPT:
$transcriptText

AGENDAS DISCUSSED:
${context.agendas.map((a) => '- ${a.title}: ${a.details}').join('\n')}

Please provide:
1. A brief summary (2-3 sentences) of what was discussed
2. Key decisions made (list format)
3. Action items/tasks assigned (format: "Task - Assigned to Person")
4. Key points/highlights from the discussion

Format your response as:
SUMMARY:
[summary text]

DECISIONS:
- [decision 1]
- [decision 2]

TASKS:
- [task 1] - [person]
- [task 2] - [person]

KEY POINTS:
- [point 1]
- [point 2]
''';

      final response = await model.generateContent([Content.text(prompt)]);
      final responseText = response.text ?? '';

      // Parse response
      final recap = _parseRecapResponse(responseText, context);

      // Store recap in Firestore
      await _firestore
          .collection('meetingRooms')
          .doc(meetingId)
          .update({
        'recap': recap.toMap(),
        'recapGeneratedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Meeting recap generated and stored');

      return recap;
    } catch (e, stackTrace) {
      debugPrint('❌ Error generating meeting recap: $e');
      debugPrint('$stackTrace');
      return MeetingRecap(
        summary: 'Error generating summary',
        decisions: [],
        tasks: [],
        keyPoints: [],
        participantCount: context.participants.length,
      );
    }
  }

  /// Parse Gemini's recap response
  MeetingRecap _parseRecapResponse(String response, MeetingContext context) {
    String summary = '';
    List<String> decisions = [];
    List<String> tasks = [];
    List<String> keyPoints = [];

    String currentSection = '';

    for (final line in response.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('SUMMARY:')) {
        currentSection = 'summary';
        continue;
      } else if (trimmed.startsWith('DECISIONS:')) {
        currentSection = 'decisions';
        continue;
      } else if (trimmed.startsWith('TASKS:')) {
        currentSection = 'tasks';
        continue;
      } else if (trimmed.startsWith('KEY POINTS:')) {
        currentSection = 'keyPoints';
        continue;
      }

      if (trimmed.isEmpty) continue;

      switch (currentSection) {
        case 'summary':
          summary += '$trimmed ';
          break;
        case 'decisions':
          if (trimmed.startsWith('-')) {
            decisions.add(trimmed.substring(1).trim());
          }
          break;
        case 'tasks':
          if (trimmed.startsWith('-')) {
            tasks.add(trimmed.substring(1).trim());
          }
          break;
        case 'keyPoints':
          if (trimmed.startsWith('-')) {
            keyPoints.add(trimmed.substring(1).trim());
          }
          break;
      }
    }

    return MeetingRecap(
      summary: summary.trim(),
      decisions: decisions,
      tasks: tasks,
      keyPoints: keyPoints,
      participantCount: context.participants.length,
    );
  }

  Future<void> dispose() async {
    await _transcriptController.close();
  }
}

/// Meeting context data
class MeetingContext {
  final String houseId;
  final String meetingId;
  final List<AgendaItem> agendas;
  final List<MeetingParticipant> participants;

  MeetingContext({
    required this.houseId,
    required this.meetingId,
    required this.agendas,
    required this.participants,
  });
}

/// Meeting participant info
class MeetingParticipant {
  final String userId;
  final String displayName;
  final String avatarEmoji;

  MeetingParticipant({
    required this.userId,
    required this.displayName,
    required this.avatarEmoji,
  });
}

/// Transcript entry
class TranscriptEntry {
  final String speaker;
  final String text;
  final DateTime timestamp;
  final String speakerType; // 'user' or 'beemo'

  TranscriptEntry({
    required this.speaker,
    required this.text,
    required this.timestamp,
    required this.speakerType,
  });

  Map<String, dynamic> toMap() {
    return {
      'speaker': speaker,
      'text': text,
      'timestamp': Timestamp.fromDate(timestamp),
      'speakerType': speakerType,
    };
  }

  factory TranscriptEntry.fromMap(Map<String, dynamic> map) {
    return TranscriptEntry(
      speaker: map['speaker'] ?? '',
      text: map['text'] ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      speakerType: map['speakerType'] ?? 'user',
    );
  }
}

/// Meeting recap/summary
class MeetingRecap {
  final String summary;
  final List<String> decisions;
  final List<String> tasks;
  final List<String> keyPoints;
  final int participantCount;

  MeetingRecap({
    required this.summary,
    required this.decisions,
    required this.tasks,
    required this.keyPoints,
    required this.participantCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'summary': summary,
      'decisions': decisions,
      'tasks': tasks,
      'keyPoints': keyPoints,
      'participantCount': participantCount,
    };
  }

  factory MeetingRecap.fromMap(Map<String, dynamic> map) {
    return MeetingRecap(
      summary: map['summary'] ?? '',
      decisions: List<String>.from(map['decisions'] ?? []),
      tasks: List<String>.from(map['tasks'] ?? []),
      keyPoints: List<String>.from(map['keyPoints'] ?? []),
      participantCount: map['participantCount'] ?? 0,
    );
  }
}
