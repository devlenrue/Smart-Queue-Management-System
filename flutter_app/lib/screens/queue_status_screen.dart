import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/service.dart';
import '../models/ticket.dart';
import '../providers/queue_provider.dart';

class QueueStatusScreen extends StatefulWidget {
  const QueueStatusScreen({super.key, required this.service});

  final ServiceModel service;

  @override
  State<QueueStatusScreen> createState() => _QueueStatusScreenState();
}

class _QueueStatusScreenState extends State<QueueStatusScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<QueueProvider>().startPolling(widget.service.id);
    });
  }

  @override
  void dispose() {
    context.read<QueueProvider>().stopPolling();
    super.dispose();
  }

  Future<void> _cancelTicket(Ticket ticket) async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this queue?'),
        content: Text('Ticket #${ticket.ticketNumber} will be cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep ticket'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave queue'),
          ),
        ],
      ),
    );
    if (shouldCancel != true || !mounted) return;
    final success = await context.read<QueueProvider>().cancelTicket(ticket.id);
    if (!mounted || !success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You left the queue.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.service.name),
        actions: [
          IconButton(
            tooltip: 'Refresh now',
            onPressed: () => context.read<QueueProvider>().loadStatus(widget.service.id),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Consumer<QueueProvider>(
        builder: (context, queue, _) {
          final status = queue.status;
          if (status == null) {
            if (queue.error != null) {
              return _StatusError(message: queue.error!);
            }
            return const Center(child: CircularProgressIndicator());
          }
          final ticket = status.myTicket;
          return RefreshIndicator(
            onRefresh: () => queue.loadStatus(widget.service.id),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                if (status.isNearTurn) ...[
                  _NearTurnAlert(peopleAhead: status.peopleAhead),
                  const SizedBox(height: 14),
                ],
                if (queue.error != null) ...[
                  _StatusError(message: queue.error!),
                  const SizedBox(height: 14),
                ],
                if (ticket == null)
                  const _NoActiveTicket()
                else ...[
                  _TicketHero(ticket: ticket),
                  const SizedBox(height: 18),
                  _MetricRow(status: status),
                  const SizedBox(height: 18),
                  Card(
                    color: Colors.white,
                    child: ListTile(
                      leading: const Icon(Icons.campaign_outlined),
                      title: const Text('Now serving'),
                      subtitle: Text(
                        status.currentServing == null
                            ? 'No customer is being served'
                            : 'Ticket #${status.currentServing!.ticketNumber}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Live queue',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...status.tickets.map(
                    (item) => _QueueTicketRow(
                      ticket: item,
                      isMine: item.id == ticket.id,
                    ),
                  ),
                  if (ticket.isActive) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: queue.isActionLoading ? null : () => _cancelTicket(ticket),
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Leave queue'),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TicketHero extends StatelessWidget {
  const _TicketHero({required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isServing = ticket.status == 'serving';
    return Card(
      color: isServing ? colorScheme.tertiaryContainer : colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              isServing ? 'Your ticket is being served' : 'Your queue number',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '#${ticket.ticketNumber}',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
            ),
            const SizedBox(height: 8),
            Chip(label: Text(ticket.status.toUpperCase())),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.status});

  final QueueStatus status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            icon: Icons.format_list_numbered,
            label: 'Position',
            value: status.currentPosition?.toString() ?? '—',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            icon: Icons.groups_outlined,
            label: 'Ahead',
            value: '${status.peopleAhead}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            icon: Icons.schedule_outlined,
            label: 'Est. wait',
            value: '${status.estimatedWaitMinutes}m',
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _QueueTicketRow extends StatelessWidget {
  const _QueueTicketRow({required this.ticket, required this.isMine});

  final Ticket ticket;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isMine ? Theme.of(context).colorScheme.primaryContainer : Colors.white,
      child: ListTile(
        leading: CircleAvatar(child: Text('${ticket.ticketNumber}')),
        title: Text(isMine ? 'Your ticket' : 'Ticket #${ticket.ticketNumber}'),
        trailing: Text(
          ticket.status,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _NearTurnAlert extends StatelessWidget {
  const _NearTurnAlert({required this.peopleAhead});

  final int peopleAhead;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: const Text('You are nearly next'),
        subtitle: Text('$peopleAhead ${peopleAhead == 1 ? 'person is' : 'people are'} ahead of you.'),
      ),
    );
  }
}

class _NoActiveTicket extends StatelessWidget {
  const _NoActiveTicket();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline, size: 48),
            SizedBox(height: 12),
            Text('You do not have an active ticket for this service.'),
          ],
        ),
      ),
    );
  }
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message),
      ),
    );
  }
}
