import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/service.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/queue_provider.dart';
import 'admin_dashboard_screen.dart';
import 'history_screen.dart';
import 'queue_status_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final queue = context.read<QueueProvider>();
        queue.loadServices();
        queue.loadHistory();
      });
    }
  }

  Future<void> _refresh() async {
    final queue = context.read<QueueProvider>();
    await Future.wait([queue.loadServices(), queue.loadHistory()]);
  }

  Future<void> _join(ServiceModel service) async {
    final queue = context.read<QueueProvider>();
    final ticket = await queue.joinQueue(service);
    if (!mounted || ticket == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QueueStatusScreen(service: service),
      ),
    );
    if (mounted) queue.loadHistory();
  }

  void _logout() {
    context.read<QueueProvider>().clear();
    context.read<AdminProvider>().clear();
    context.read<AuthProvider>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Queue'),
        actions: [
          if (auth.user?.isStaff == true)
            IconButton(
              tooltip: 'Staff dashboard',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
              ),
              icon: const Icon(Icons.dashboard_outlined),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'history') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              } else if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'history', child: Text('Queue history')),
              PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      body: Consumer<QueueProvider>(
        builder: (context, queue, _) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                Text(
                  'Hello, ${auth.user?.fullName.split(' ').first ?? 'there'}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose a service and take your place in line.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (queue.error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorCard(message: queue.error!),
                ],
                if (queue.activeTicket != null) ...[
                  const SizedBox(height: 20),
                  _ActiveTicketCard(
                    ticket: queue.activeTicket!,
                    service: _serviceForTicket(queue),
                    onTap: () {
                      final service = _serviceForTicket(queue);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => QueueStatusScreen(service: service),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available services',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (queue.isLoading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!queue.isLoading && queue.services.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No active services are available right now.'),
                    ),
                  ),
                ...queue.services.map(
                  (service) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ServiceCard(
                      service: service,
                      isJoining: queue.isActionLoading,
                      onJoin: () => _join(service),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  ServiceModel _serviceForTicket(QueueProvider queue) {
    final ticket = queue.activeTicket!;
    return queue.services.firstWhere(
      (service) => service.id == ticket.serviceId,
      orElse: () => ServiceModel(
        id: ticket.serviceId,
        name: ticket.serviceName ?? 'Queue service',
        averageServiceMinutes: 5,
        isActive: true,
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.isJoining,
    required this.onJoin,
  });

  final ServiceModel service;
  final bool isJoining;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: const Icon(Icons.support_agent_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (service.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      service.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Typical service: ${service.averageServiceMinutes.toStringAsFixed(0)} min',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: isJoining ? null : onJoin,
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTicketCard extends StatelessWidget {
  const _ActiveTicketCard({
    required this.ticket,
    required this.service,
    required this.onTap,
  });

  final Ticket ticket;
  final ServiceModel service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.confirmation_number_outlined, color: colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active ticket · ${service.name}'),
                    const SizedBox(height: 4),
                    Text(
                      '#${ticket.ticketNumber}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
