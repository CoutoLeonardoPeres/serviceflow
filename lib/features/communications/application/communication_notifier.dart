import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../data/communication_repository.dart';
import '../domain/communication_log.dart';
import '../domain/message_template.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final communicationRepositoryProvider = Provider<CommunicationRepository>(
  (ref) => CommunicationRepository(ref.read(supabaseClientProvider)),
);

// ── Template providers ────────────────────────────────────────────────────────

final messageTemplatesProvider =
    FutureProvider.autoDispose<List<MessageTemplate>>((ref) async {
  return ref.read(communicationRepositoryProvider).listTemplates();
});

final messageTemplatesByChannelProvider =
    FutureProvider.autoDispose.family<List<MessageTemplate>, MessageChannel>(
        (ref, channel) async {
  return ref
      .read(communicationRepositoryProvider)
      .listTemplates(channel: channel);
});

// ── Log providers ─────────────────────────────────────────────────────────────

/// Logs de comunicação de um cliente específico.
final customerCommunicationLogsProvider =
    FutureProvider.autoDispose.family<List<CommunicationLog>, String>(
        (ref, customerId) async {
  return ref
      .read(communicationRepositoryProvider)
      .listLogs(customerId: customerId);
});

/// Logs de comunicação ligados a uma entidade (quotation, work_order, etc.).
final entityCommunicationLogsProvider = FutureProvider.autoDispose
    .family<List<CommunicationLog>, ({String entity, String entityId})>(
        (ref, args) async {
  return ref.read(communicationRepositoryProvider).listLogs(
        relatedEntity: args.entity,
        relatedEntityId: args.entityId,
      );
});
