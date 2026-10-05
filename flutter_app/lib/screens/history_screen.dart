import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../providers/queue_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<QueueProvider>().loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Queue history')),
      body: Consumer<QueueProvider>(
        builder: (context, queue, _) {
          if (queue.history.isEmpty && queue.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (queue.history.isEmpty) {
            return const Center(child: Text('No queue history yet.'));
          }
          return RefreshIndicator(
            onRefresh: queue.loadHistory,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: queue.history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _HistoryTile(ticket: queue.history[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = switch (ticket.status) {
      'served' => Colors.green.shade700,
      'cancelled' || 'skipped' => colorScheme.error,
      'serving' => colorScheme.primary,
      _ => colorScheme.tertiary,
    };

    return Card(
      color: Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Text('${ticket.ticketNumber}'),
        ),
        title: Text(ticket.serviceName ?? 'Service'),
        subtitle: Text('Joined ${ticket.joinedAt.replaceFirst('T', ' ')}'),
        trailing: Chip(
          label: Text(
            ticket.status,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
          ),
          backgroundColor: statusColor.withOpacity(0.12),
          side: BorderSide.none,
        ),
      ),
    );
  }
}
