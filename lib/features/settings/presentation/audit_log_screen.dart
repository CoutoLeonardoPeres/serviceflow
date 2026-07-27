import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../data/audit_log_repository.dart';
import '../domain/audit_log_event.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final auditLogRepositoryProvider = Provider<AuditLogRepository>(
  (ref) => AuditLogRepository(ref.read(supabaseClientProvider)),
);

final _auditFilterEntityProvider = StateProvider<String?>((ref) => null);
final _auditLimitProvider = StateProvider<int>((ref) => 50);

final auditLogEventsProvider =
    FutureProvider.autoDispose<List<AuditLogEvent>>((ref) async {
  final entity = ref.watch(_auditFilterEntityProvider);
  final limit = ref.watch(_auditLimitProvider);
  return ref
      .read(auditLogRepositoryProvider)
      .listEvents(limit: limit, entity: entity);
});

// ── Tela ──────────────────────────────────────────────────────────────────────

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  static const _entityOptions = <String?, String>{
    null: 'Todos',
    'quotations': 'Orçamentos',
    'work_orders': 'OS',
    'customers': 'Clientes',
    'service_requests': 'Chamados',
    'appointments': 'Agenda',
    'receivables': 'Financeiro',
    'tenant_memberships': 'Membros',
    'tenants': 'Empresa',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final eventsAsync = ref.watch(auditLogEventsProvider);
    final selectedEntity = ref.watch(_auditFilterEntityProvider);
    final limit = ref.watch(_auditLimitProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trilha de auditoria'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(auditLogEventsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(
                  'Filtrar por:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _entityOptions.entries.map((entry) {
                        final selected = selectedEntity == entry.key;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(entry.value),
                            selected: selected,
                            onSelected: (_) => ref
                                .read(_auditFilterEntityProvider.notifier)
                                .state = entry.key,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Lista
          Expanded(
            child: eventsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) {
                final msg = e is AppError
                    ? e.userMessage
                    : 'Erro ao carregar auditoria.';
                return ErrorView(
                  message: msg,
                  onRetry: () => ref.invalidate(auditLogEventsProvider),
                );
              },
              data: (events) {
                if (events.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_outlined,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(
                          'Nenhum evento de auditoria registrado.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length + (events.length >= limit ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == events.length) {
                      // Botão "Carregar mais"
                      return Center(
                        child: TextButton.icon(
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Carregar mais'),
                          onPressed: () {
                            ref.read(_auditLimitProvider.notifier).state =
                                limit + 50;
                          },
                        ),
                      );
                    }
                    return _AuditEventCard(event: events[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card de evento ────────────────────────────────────────────────────────────

class _AuditEventCard extends StatelessWidget {
  const _AuditEventCard({required this.event});

  final AuditLogEvent event;

  static final _dtFmt =
      DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final entityColor = _entityColor(event.entity, theme);

    return NeomorphicPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ícone colorido por entidade
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: entityColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _entityIcon(event.entity),
              size: 20,
              color: entityColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ação
                Text(
                  event.actionLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                // Entidade + ID
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: entityColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        event.entityLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: entityColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (event.entityId != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '#${event.entityId!.substring(0, 8)}…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Timestamp
                Text(
                  _dtFmt.format(event.createdAt.toLocal()),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Seta para detalhe
          Icon(
            Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Color _entityColor(String entity, ThemeData theme) => switch (entity) {
        'quotations' => Colors.blue,
        'work_orders' => Colors.orange,
        'customers' => Colors.green,
        'service_requests' => Colors.purple,
        'appointments' => Colors.teal,
        'receivables' => Colors.indigo,
        'tenant_memberships' => Colors.pink,
        'tenants' => theme.colorScheme.primary,
        _ => theme.colorScheme.secondary,
      };

  IconData _entityIcon(String entity) => switch (entity) {
        'quotations' => Icons.request_quote_outlined,
        'work_orders' => Icons.build_outlined,
        'customers' => Icons.people_outline,
        'service_requests' => Icons.support_agent_outlined,
        'appointments' => Icons.event_outlined,
        'receivables' => Icons.attach_money_outlined,
        'tenant_memberships' => Icons.group_outlined,
        'tenants' => Icons.business_outlined,
        _ => Icons.receipt_long_outlined,
      };
}
