import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/agenda_item_model.dart';

class AgendaDetailScreen extends StatelessWidget {
  final AgendaItem agendaItem;

  const AgendaDetailScreen({
    super.key,
    required this.agendaItem,
  });

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'meeting':
        return const Color(0xFFFF4D8D);
      case 'chat':
        return const Color(0xFF63BDA4);
      case 'flexible':
        return const Color(0xFFFFC400);
      default:
        return const Color(0xFF4A4A4A);
    }
  }

  String _getPriorityLabel(String priority) {
    switch (priority) {
      case 'meeting':
        return 'Discuss in Meeting';
      case 'chat':
        return 'Send to Group Chat';
      case 'flexible':
        return 'Flexible';
      default:
        return priority;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with back button
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 48,
                      height: 48,
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
                  const Expanded(
                    child: Text(
                      'Agenda Details',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Priority Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _getPriorityColor(agendaItem.priority),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black, width: 2.5),
                ),
                child: Text(
                  _getPriorityLabel(agendaItem.priority),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Title',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                agendaItem.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 32),

              // Details
              const Text(
                'Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.black, width: 3),
                ),
                child: Text(
                  agendaItem.details.isNotEmpty
                      ? agendaItem.details
                      : 'No details provided',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: agendaItem.details.isNotEmpty
                        ? Colors.black87
                        : Colors.black38,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Created Date
              const Text(
                'Created',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('EEEE, MMMM d, yyyy \'at\' h:mm a')
                    .format(agendaItem.createdAt),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 32),

              // Status
              const Text(
                'Status',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: agendaItem.status == 'pending'
                      ? const Color(0xFFFFC400)
                      : const Color(0xFF63BDA4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black, width: 2.5),
                ),
                child: Text(
                  agendaItem.status.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
