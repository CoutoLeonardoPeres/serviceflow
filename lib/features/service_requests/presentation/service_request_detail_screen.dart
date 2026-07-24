import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/error_view.dart';
import '../application/service_request_list_notifier.dart';
import '../domain/service_request.dart';
import 'widgets/service_request_status_chip.dart';

class ServiceRequestDetailScreen extends ConsumerWidget {
  const ServiceRequestDetailScreen({
    super.key,
    required this.requestId,
  });

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestAsync = ref.watch(serviceRequestDetailProvider(requestId));
    final historyAsync =
        ref.watch(serviceRequestStatusHistoryProvider(requestId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe do chamado')),
      body: requestAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ErrorView(
          message: 'Nao foi possivel carregar o chamado.',
          onRetry: () =>
              ref.invalidate(serviceRequestDetailProvider(requestId)),
        ),
        data: (request) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Header(request: request),
            const SizedBox(height: 16),
            _Section(
              title: 'Solicitacao',
              children: [
                _Row(label: 'Cliente', value: request.customerName ?? '-'),
                _Row(label: 'Canal', value: request.channel.label),
                _Row(label: 'Categoria', value: request.categoryName ?? '-'),
                _Row(label: 'Prioridade', value: request.priorityName ?? '-'),
                if (request.availabilityNotes != null)
                  _Row(
                    label: 'Disponibilidade',
                    value: request.availabilityNotes!,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Descricao',
              children: [
                Text(request.description),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Historico',
              children: [
                historyAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Historico indisponivel.'),
                  data: (rows) => rows.isEmpty
                      ? const Text('Nenhuma mudanca de status registrada.')
                      : Column(
                          children: rows
                              .map(
                                (row) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.timeline),
                                  title: Text(
                                    '${row['from_status'] ?? '-'} -> ${row['to_status']}',
                                  ),
                                  subtitle: Text(
                                    row['reason'] as String? ??
                                        'Sem motivo informado',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${request.displayNumber} · ${request.title}',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ServiceRequestStatusChip(status: request.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
