import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AdminProvider>().loadServices();
      });
    }
  }

  Future<void> _performAction(Future<bool> Function() action) async {
    final success = await action();
    if (!mounted || success) return;
    final message = context.read<AdminProvider>().error ?? 'Action failed.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addService() async {
    final result = await showDialog<_NewServiceData>(
      context: context,
      builder: (_) => const _AddServiceDialog(),
    );
    if (result == null || !mounted) return;
    await _performAction(
      () => context.read<AdminProvider>().addService(
            name: result.name,
            description: result.description,
            averageServiceMinutes: result.averageMinutes,
          ),
    );
  }

  Future<void> _removeService() async {
    final admin = context.read<AdminProvider>();
    final service = admin.queue?.service;
    if (service == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove service?'),
        content: Text('Remove ${service.name} from the active service list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _performAction(() => admin.removeSelectedService());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAdmin = auth.user?.isAdmin == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh queue',
            onPressed: () => context.read<AdminProvider>().loadServices(),
            icon: const Icon(Icons.refresh),
          ),
          if (isAdmin)
            IconButton(
              tooltip: 'Add service',
              onPressed: () => _addService(),
              icon: const Icon(Icons.add_business_outlined),
            ),
        ],
      ),
      body: Consumer<AdminProvider>(
        builder: (context, admin, _) {
          if (admin.isLoading && admin.services.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (admin.services.isEmpty) {
            return _EmptyAdminState(isAdmin: isAdmin, onAdd: () => _addService());
          }
          final queue = admin.queue;
          return RefreshIndicator(
            onRefresh: admin.loadServices,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                Text(
                  'Live queue control',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Call, complete, or skip customers in real time.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              value: admin.selectedServiceId,
                              hint: const Text('Choose a service'),
                              items: admin.services
                                  .map(
                                    (service) => DropdownMenuItem<int>(
                                      value: service.id,
                                      child: Text(service.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) {
                                if (id != null) admin.loadQueue(id);
                              },
                            ),
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Remove selected service',
                            onPressed: admin.isActionLoading ? null : _removeService,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (admin.error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(admin.error!),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (queue == null)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  _QueueSummary(queue: queue),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: admin.isActionLoading || queue.currentServing != null || queue.waitingCount == 0
                        ? null
                        : () => _performAction(admin.callNext),
                    icon: const Icon(Icons.campaign_outlined),
                    label: Text(
                      queue.currentServing != null
                          ? 'Finish the current ticket first'
                          : queue.waitingCount == 0
                              ? 'No waiting customers'
                              : 'Call next customer',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Active tickets',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (queue.tickets.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('The queue is empty.'),
                      ),
                    ),
                  ...queue.tickets.map(
                    (ticket) => _AdminTicketTile(
                      ticket: ticket,
                      isLoading: admin.isActionLoading,
                      onComplete: () => _performAction(() => admin.complete(ticket.id)),
                      onSkip: () => _performAction(() => admin.skip(ticket.id)),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QueueSummary extends StatelessWidget {
  const _QueueSummary({required this.queue});

  final AdminQueueStatus queue;

  @override
  Widget build(BuildContext context) {
    final servingNumber = queue.currentServing?.ticketNumber;
    return Row(
      children: [
        Expanded(child: _SummaryItem(label: 'Waiting', value: '${queue.waitingCount}')),
        const SizedBox(width: 10),
        Expanded(child: _SummaryItem(label: 'Serving', value: servingNumber == null ? '—' : '#$servingNumber')),
        const SizedBox(width: 10),
        Expanded(child: _SummaryItem(label: 'Avg. time', value: '${queue.averageServiceMinutes.toStringAsFixed(0)}m')),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

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
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _AdminTicketTile extends StatelessWidget {
  const _AdminTicketTile({
    required this.ticket,
    required this.isLoading,
    required this.onComplete,
    required this.onSkip,
  });

  final Ticket ticket;
  final bool isLoading;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final isServing = ticket.status == 'serving';
    return Card(
      color: isServing ? Theme.of(context).colorScheme.tertiaryContainer : Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            CircleAvatar(child: Text('${ticket.ticketNumber}')),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ticket.customerName ?? 'Customer'),
                  const SizedBox(height: 3),
                  Text(
                    isServing ? 'Currently serving' : 'Waiting',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (isServing)
              IconButton(
                tooltip: 'Mark served',
                onPressed: isLoading ? null : onComplete,
                icon: const Icon(Icons.check_circle_outline),
              ),
            IconButton(
              tooltip: 'Skip customer',
              onPressed: isLoading ? null : onSkip,
              icon: const Icon(Icons.skip_next_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAdminState extends StatelessWidget {
  const _EmptyAdminState({required this.isAdmin, required this.onAdd});

  final bool isAdmin;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 52),
            const SizedBox(height: 12),
            const Text('No active services.'),
            if (isAdmin) ...[
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add service')),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewServiceData {
  const _NewServiceData(this.name, this.description, this.averageMinutes);

  final String name;
  final String description;
  final double averageMinutes;
}

class _AddServiceDialog extends StatefulWidget {
  const _AddServiceDialog();

  @override
  State<_AddServiceDialog> createState() => _AddServiceDialogState();
}

class _AddServiceDialogState extends State<_AddServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _average = TextEditingController(text: '5');

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _average.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _NewServiceData(
        _name.text.trim(),
        _description.text.trim(),
        double.parse(_average.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add service'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Service name'),
                validator: (value) => value == null || value.trim().length < 2 ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _average,
                decoration: const InputDecoration(labelText: 'Fallback minutes'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => double.tryParse(value ?? '') == null ? 'Enter a number' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
