import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../core/config/env_config.dart';
import '../../../core/error/app_error.dart';
import '../../../core/files/attachment_link_action.dart';
import '../../../core/router/app_router.dart';
import '../../../core/files/attachment_picker.dart';
import '../../../core/files/stored_attachment.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/attachment_gallery.dart';
import '../../../core/widgets/attachment_preview_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../shared/providers/tenant_provider.dart';
import '../../communications/presentation/send_message_panel.dart';
import '../../customers/application/customer_list_notifier.dart';
import '../../stock/application/stock_notifier.dart';
import '../../stock/domain/product.dart';
import '../application/work_order_list_notifier.dart';
import '../domain/work_order.dart';
import 'widgets/work_order_status_chip.dart';

class WorkOrderDetailScreen extends ConsumerWidget {
  const WorkOrderDetailScreen({super.key, required this.workOrderId});

  final String workOrderId;

  Future<void> _transition(
    BuildContext context,
    WidgetRef ref,
    WorkOrderStatus status,
  ) async {
    try {
      await ref.read(workOrderRepositoryProvider).transitionStatus(
            id: workOrderId,
            status: status,
          );
      ref.invalidate(workOrderDetailProvider(workOrderId));
      ref.read(workOrderListProvider.notifier).refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('OS marcada como ${status.label.toLowerCase()}.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _openTimeEntryDialog(BuildContext context, WidgetRef ref) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: 'Horas trabalhadas',
      maxWidth: 620,
      child: _TimeEntryForm(workOrderId: workOrderId),
    );
    if (saved == true) {
      ref.invalidate(workOrderDetailProvider(workOrderId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horas registradas.')),
      );
    }
  }

  Future<void> _openMaterialDialog(BuildContext context, WidgetRef ref) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: 'Adicionar material',
      maxWidth: 620,
      child: _MaterialForm(workOrderId: workOrderId),
    );
    if (saved == true) {
      ref.invalidate(workOrderDetailProvider(workOrderId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Material adicionado.')),
      );
    }
  }

  Future<void> _openAcceptanceDialog(
    BuildContext context,
    WidgetRef ref,
    WorkOrder workOrder,
  ) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: 'Aceite do cliente',
      maxWidth: 620,
      child: _AcceptanceForm(workOrder: workOrder),
    );
    if (saved == true) {
      ref.invalidate(workOrderDetailProvider(workOrderId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aceite registrado.')),
      );
    }
  }

  Future<void> _openExpenseDialog(BuildContext context, WidgetRef ref) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: 'Despesa da OS',
      maxWidth: 620,
      child: _ExpenseForm(workOrderId: workOrderId),
    );
    if (saved == true) {
      ref.invalidate(workOrderDetailProvider(workOrderId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Despesa registrada.')),
      );
    }
  }

  Future<void> _openEvidenceDialog(
    BuildContext context,
    WidgetRef ref,
    WorkOrder workOrder,
  ) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: 'Evidência da OS',
      maxWidth: 620,
      child: _EvidenceForm(workOrder: workOrder),
    );
    if (saved == true) {
      ref.invalidate(workOrderDetailProvider(workOrderId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evidência anexada.')),
      );
    }
  }

  /// Gera o link público da pesquisa e abre o painel de envio já com o link
  /// preenchido na variável {{link}} dos templates.
  ///
  /// Gerar um link novo revoga o anterior desta OS (regra da migration 0041),
  /// então o link antigo deixa de funcionar.
  Future<void> _sendSatisfactionSurvey(
    BuildContext context,
    WidgetRef ref,
    WorkOrder workOrder,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final token = await ref
          .read(workOrderRepositoryProvider)
          .createSatisfactionPublicLink(workOrder.id);
      final link =
          EnvConfig.publicUrl(AppRoutes.satisfactionPublic(token));

      if (!context.mounted) return;

      final customer =
          await ref.read(customerDetailProvider(workOrder.customerId).future);
      final tenant = ref.read(currentTenantProvider);

      if (!context.mounted) return;

      await showSendMessageSheet(
        context,
        MessageContext(
          customerId: customer.id,
          customerName: customer.name,
          customerPhone: customer.phone ?? '',
          customerEmail: customer.email ?? '',
          companyName: tenant?['name'] as String? ?? '',
          workOrderNumber: workOrder.displayNumber.toString(),
          serviceTitle: workOrder.title,
          publicLink: link,
          relatedEntity: 'work_orders',
          relatedEntityId: workOrder.id,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AppError
                ? e.userMessage
                : 'Não foi possível gerar o link da pesquisa.',
          ),
        ),
      );
    }
  }

  Future<void> _createReturn(
    BuildContext context,
    WidgetRef ref,
    WorkOrder workOrder,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _CancelReasonDialog(
        title: 'Criar OS de retorno',
        hint: 'Descreva o motivo do retorno / problema que persiste…',
        confirmLabel: 'Criar retorno',
        confirmColor: Theme.of(context).colorScheme.primary,
      ),
    );
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final returnWo =
          await ref.read(workOrderRepositoryProvider).createReturn(
                workOrder.id,
                reason,
              );
      ref.read(workOrderListProvider.notifier).refresh();
      ref.invalidate(workOrderEventsProvider(workOrder.id));
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content:
              Text('OS de retorno ${returnWo.displayNumber} criada.'),
          action: SnackBarAction(
            label: 'Abrir',
            onPressed: () =>
                context.push(AppRoutes.workOrderDetail(returnWo.id)),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is Exception
                ? e.toString().replaceAll('Exception: ', '')
                : 'Erro ao criar retorno.',
          ),
        ),
      );
    }
  }

  Future<void> _cancelWorkOrder(
    BuildContext context,
    WidgetRef ref,
    WorkOrder workOrder,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _CancelReasonDialog(
        title: 'Cancelar OS',
        hint: 'Ex.: cliente solicitou cancelamento, serviço já foi executado…',
        confirmLabel: 'Confirmar cancelamento',
      ),
    );
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(workOrderRepositoryProvider).cancel(workOrder.id, reason);
      ref.invalidate(workOrderDetailProvider(workOrderId));
      ref.read(workOrderListProvider.notifier).refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('OS cancelada.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is Exception
                ? e.toString().replaceAll('Exception: ', '')
                : 'Erro ao cancelar OS.',
          ),
        ),
      );
    }
  }

  Future<void> _createReceivable(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(workOrderRepositoryProvider)
          .createReceivableFromWorkOrder(workOrderId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cobrança gerada no financeiro.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _openSatisfactionDialog(
    BuildContext context,
    WidgetRef ref,
    WorkOrder workOrder,
  ) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: 'Satisfação do cliente',
      maxWidth: 620,
      child: _SatisfactionForm(workOrder: workOrder),
    );
    if (saved == true) {
      ref.invalidate(workOrderSatisfactionProvider(workOrder.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Satisfação registrada.')),
      );
    }
  }

  Future<void> _openEvidenceAttachment(
    BuildContext context,
    WidgetRef ref,
    StoredAttachment attachment,
  ) async {
    try {
      final url = await ref
          .read(workOrderRepositoryProvider)
          .createEvidenceSignedUrl(attachment.storagePath);
      await openAttachmentLink(url);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _downloadEvidenceAttachment(
    BuildContext context,
    WidgetRef ref,
    StoredAttachment attachment,
  ) async {
    try {
      final url = await ref
          .read(workOrderRepositoryProvider)
          .createEvidenceSignedUrl(attachment.storagePath);
      await downloadAttachmentLink(url, attachment.fileName);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _previewEvidenceAttachment(
    BuildContext context,
    WidgetRef ref,
    StoredAttachment attachment,
  ) async {
    try {
      final url = await ref
          .read(workOrderRepositoryProvider)
          .createEvidenceSignedUrl(attachment.storagePath);
      if (!context.mounted) return;
      if (attachment.isImage) {
        await showImageAttachmentPreview(
          context: context,
          title: attachment.fileName,
          imageUrl: url,
        );
        return;
      }
      if (attachment.isPdf) {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Falha ao carregar PDF.');
        }
        if (!context.mounted) return;
        await showPdfAttachmentPreview(
          context: context,
          title: attachment.fileName,
          bytes: response.bodyBytes,
        );
        return;
      }
      await openAttachmentLink(url);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(workOrderDetailProvider(workOrderId));
    final evidenceAsync = ref.watch(workOrderEvidenceProvider(workOrderId));
    final itemsAsync = ref.watch(workOrderItemsProvider(workOrderId));
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return Scaffold(
      appBar: AppBar(title: const Text('Ordem de serviço')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(workOrderDetailProvider(workOrderId)),
        ),
        data: (workOrder) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            NeomorphicPanel(
              borderRadius: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (workOrder.isReturn)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Chip(
                                  label: const Text('Retorno'),
                                  avatar: const Icon(Icons.replay_outlined,
                                      size: 14),
                                  labelStyle: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                  ),
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .tertiaryContainer,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            Text(
                              '${workOrder.displayNumber} · ${workOrder.title}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      WorkOrderStatusChip(status: workOrder.status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _transition(
                          context,
                          ref,
                          WorkOrderStatus.inProgress,
                        ),
                        icon: const Icon(Icons.play_arrow_outlined),
                        label: const Text('Iniciar execução'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _transition(
                          context,
                          ref,
                          WorkOrderStatus.done,
                        ),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Concluir OS'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openTimeEntryDialog(context, ref),
                        icon: const Icon(Icons.timer_outlined),
                        label: const Text('Registrar horas'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openMaterialDialog(context, ref),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Adicionar material'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openExpenseDialog(context, ref),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Registrar despesa'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _openEvidenceDialog(context, ref, workOrder),
                        icon: const Icon(Icons.attach_file_outlined),
                        label: const Text('Anexar foto/evidência'),
                      ),
                      FilledButton.icon(
                        onPressed: () =>
                            _openAcceptanceDialog(context, ref, workOrder),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Registrar aceite'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _createReceivable(context, ref),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Gerar cobrança'),
                      ),
                      OutlinedButton.icon(
                        onPressed: workOrder.status == WorkOrderStatus.done
                            ? () =>
                                _openSatisfactionDialog(context, ref, workOrder)
                            : null,
                        icon:
                            const Icon(Icons.sentiment_satisfied_alt_outlined),
                        label: const Text('Registrar satisfação'),
                      ),
                      if (workOrder.status == WorkOrderStatus.done)
                        OutlinedButton.icon(
                          onPressed: () =>
                              _sendSatisfactionSurvey(context, ref, workOrder),
                          icon: const Icon(Icons.poll_outlined),
                          label: const Text('Enviar pesquisa'),
                        ),
                      if (workOrder.status == WorkOrderStatus.done)
                        FilledButton.icon(
                          onPressed: () =>
                              _createReturn(context, ref, workOrder),
                          icon: const Icon(Icons.replay_outlined),
                          label: const Text('Criar retorno'),
                        ),
                      if (workOrder.status != WorkOrderStatus.done &&
                          workOrder.status != WorkOrderStatus.cancelled)
                        OutlinedButton.icon(
                          onPressed: () =>
                              _cancelWorkOrder(context, ref, workOrder),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancelar OS'),
                        ),
                    ],
                  ),
                  if (workOrder.status == WorkOrderStatus.cancelled &&
                      workOrder.cancellationReason != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .errorContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Motivo do cancelamento',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  workOrder.cancellationReason!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                ),
                                if (workOrder.cancelledAt != null)
                                  Text(
                                    DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                                        .format(
                                            workOrder.cancelledAt!.toLocal()),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onErrorContainer
                                              .withValues(alpha: 0.7),
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            NeomorphicPanel(
              borderRadius: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoLine(
                      label: 'Cliente',
                      value: workOrder.customerName ?? workOrder.customerId),
                  Consumer(builder: (context, ref, _) {
                    final tenant = ref.watch(currentTenantProvider);
                    final customerAsync =
                        ref.watch(customerDetailProvider(workOrder.customerId));
                    return customerAsync.maybeWhen(
                      data: (c) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SendMessageButton(
                          messageContext: MessageContext(
                            customerId: c.id,
                            customerName: c.name,
                            customerPhone: c.phone ?? '',
                            customerEmail: c.email ?? '',
                            companyName:
                                tenant?['name'] as String? ?? '',
                            workOrderNumber:
                                workOrder.displayNumber.toString(),
                            serviceTitle: workOrder.title,
                            relatedEntity: 'work_orders',
                            relatedEntityId: workOrder.id,
                          ),
                        ),
                      ),
                      orElse: () => const SizedBox.shrink(),
                    );
                  }),
                  _InfoLine(label: 'Descrição', value: workOrder.description),
                  _InfoLine(
                    label: 'Valor',
                    value: currency.format(workOrder.totalCents / 100),
                  ),
                  if (workOrder.requestTitle != null)
                    _InfoLine(label: 'Chamado', value: workOrder.requestTitle!),
                  if (workOrder.quotationNumber != null)
                    _InfoLine(
                      label: 'Orçamento',
                      value:
                          '#${workOrder.quotationNumber!.toString().padLeft(5, '0')}',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            NeomorphicPanel(
              borderRadius: 20,
              child: itemsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Text('Nao foi possivel carregar as linhas da OS.'),
                data: (items) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Composição da OS',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      const Text('Nenhuma linha encontrada.')
                    else
                      ...items.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.description),
                          subtitle: Text(
                            '${item.kind} · Qtd ${item.quantity} · Unit. ${currency.format(item.unitPriceCents / 100)}',
                          ),
                          trailing: Text(
                            currency.format(item.totalCents / 100),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            evidenceAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const AttachmentGallery(
                title: 'Evidências e anexos',
                attachments: [],
                emptyMessage: 'Não foi possível carregar os anexos agora.',
                onOpen: _noopStoredAttachmentAction,
                onDownload: _noopStoredAttachmentAction,
              ),
              data: (items) => AttachmentGallery(
                title: 'Evidências e anexos',
                attachments: items,
                emptyMessage: 'Esta OS ainda não possui anexos no histórico.',
                onPreview: (attachment) =>
                    _previewEvidenceAttachment(context, ref, attachment),
                onOpen: (attachment) =>
                    _openEvidenceAttachment(context, ref, attachment),
                onDownload: (attachment) =>
                    _downloadEvidenceAttachment(context, ref, attachment),
                thumbnailUrlBuilder: (attachment) async {
                  if (!attachment.isImage) return null;
                  return ref
                      .read(workOrderRepositoryProvider)
                      .createEvidenceSignedUrl(attachment.storagePath);
                },
              ),
            ),
            const SizedBox(height: 16),
            _SatisfactionPanel(workOrderId: workOrder.id),
            const SizedBox(height: 16),
            _WorkOrderEventsPanel(workOrderId: workOrder.id),
          ],
        ),
      ),
    );
  }
}

Future<void> _noopStoredAttachmentAction(StoredAttachment attachment) async {}

// ── Painel de histórico de eventos da OS ──────────────────────────────────────

class _WorkOrderEventsPanel extends ConsumerWidget {
  const _WorkOrderEventsPanel({required this.workOrderId});

  final String workOrderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(workOrderEventsProvider(workOrderId));

    return eventsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (events) {
        if (events.isEmpty) return const SizedBox.shrink();
        return NeomorphicPanel(
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Histórico de eventos',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...events.asMap().entries.map((entry) {
                final event = entry.value;
                final isLast = entry.key == events.length - 1;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(
                                width: 2,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (event.notes != null)
                                Text(
                                  event.notes!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              Text(
                                DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                                    .format(event.createdAt.toLocal()),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ── Diálogo de motivo de cancelamento ────────────────────────────────────────

class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog({
    required this.title,
    required this.hint,
    this.confirmLabel = 'Confirmar',
    this.confirmColor, // null = error color, use false-y Color.transparent to use primary
  });

  final String title;
  final String hint;
  final String confirmLabel;
  final Color? confirmColor;

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor =
        widget.confirmColor ?? Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _ctrl,
          autofocus: true,
          maxLines: 3,
          maxLength: 300,
          decoration: InputDecoration(
            labelText: 'Motivo / descrição *',
            hintText: widget.hint,
            border: const OutlineInputBorder(),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Informe o motivo.';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Voltar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: buttonColor),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_ctrl.text.trim());
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _SatisfactionPanel extends ConsumerWidget {
  const _SatisfactionPanel({required this.workOrderId});

  final String workOrderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(workOrderSatisfactionProvider(workOrderId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (satisfaction) {
        if (satisfaction == null) {
          return NeomorphicPanel(
            borderRadius: 20,
            child: Row(
              children: [
                Icon(
                  Icons.sentiment_neutral_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Satisfação ainda não registrada.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }
        return NeomorphicPanel(
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Satisfação do cliente',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  Text(
                    '${satisfaction.rating}/5',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(satisfaction.ratingLabel),
              if (satisfaction.contactName != null) ...[
                const SizedBox(height: 8),
                _InfoLine(
                  label: 'Respondido por',
                  value: satisfaction.contactName!,
                ),
              ],
              if (satisfaction.comment != null) ...[
                const SizedBox(height: 8),
                _InfoLine(label: 'Comentário', value: satisfaction.comment!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SatisfactionForm extends ConsumerStatefulWidget {
  const _SatisfactionForm({required this.workOrder});

  final WorkOrder workOrder;

  @override
  ConsumerState<_SatisfactionForm> createState() => _SatisfactionFormState();
}

class _SatisfactionFormState extends ConsumerState<_SatisfactionForm> {
  final _formKey = GlobalKey<FormState>();
  final _contactController = TextEditingController();
  final _commentController = TextEditingController();
  int _rating = 5;
  bool _isSaving = false;

  @override
  void dispose() {
    _contactController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(workOrderRepositoryProvider).recordSatisfaction(
            workOrderId: widget.workOrder.id,
            rating: _rating,
            contactName: _contactController.text.trim().isEmpty
                ? null
                : _contactController.text.trim(),
            comment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Avaliação',
              icon: Icons.sentiment_satisfied_alt_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: List.generate(
                      5,
                      (index) => ButtonSegment(
                        value: index + 1,
                        label: Text('${index + 1}'),
                        icon: const Icon(Icons.star_rounded),
                      ),
                    ),
                    selected: {_rating},
                    onSelectionChanged: _isSaving
                        ? null
                        : (value) => setState(() => _rating = value.first),
                  ),
                  const SizedBox(height: 14),
                  AppFormGrid(
                    children: [
                      TextFormField(
                        controller: _contactController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Pessoa que respondeu',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _commentController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Comentário',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar satisfação'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeEntryForm extends ConsumerStatefulWidget {
  const _TimeEntryForm({required this.workOrderId});

  final String workOrderId;

  @override
  ConsumerState<_TimeEntryForm> createState() => _TimeEntryFormState();
}

class _TimeEntryFormState extends ConsumerState<_TimeEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _hoursController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _hoursController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final hours = double.parse(_hoursController.text.replaceAll(',', '.'));
    final endedAt = DateTime.now();
    final startedAt = endedAt.subtract(
      Duration(minutes: (hours * 60).round()),
    );

    try {
      await ref.read(workOrderRepositoryProvider).recordTimeEntry(
            workOrderId: widget.workOrderId,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Apontamento',
              icon: Icons.timer_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormGrid(
                    children: [
                      TextFormField(
                        controller: _hoursController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Horas trabalhadas',
                          prefixIcon: Icon(Icons.timer_outlined),
                        ),
                        validator: (value) {
                          final parsed = double.tryParse(
                            (value ?? '').replaceAll(',', '.'),
                          );
                          if (parsed == null || parsed <= 0 || parsed > 24) {
                            return 'Informe horas entre 0 e 24.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar horas'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialForm extends ConsumerStatefulWidget {
  const _MaterialForm({required this.workOrderId});

  final String workOrderId;

  @override
  ConsumerState<_MaterialForm> createState() => _MaterialFormState();
}

class _MaterialFormState extends ConsumerState<_MaterialForm> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _unitCostController = TextEditingController(text: '0');
  final _unitPriceController = TextEditingController(text: '0');
  final _lotController = TextEditingController();
  bool _isSaving = false;

  /// Produto do catálogo. Null = lançamento em texto livre, sem baixa de
  /// estoque — caminho mantido de propósito no F3-P2, para não travar o
  /// técnico quando o cadastro está incompleto.
  String? _productId;

  /// Depósito da baixa (F3-P4). Null usa o padrão do tenant.
  String? _warehouseId;

  /// Rastreio do produto selecionado (ADR-024, F3-P5). None = sem produto ou
  /// produto sem rastreio — campo de lote/série some.
  ProductTrackingType _trackingType = ProductTrackingType.none;

  @override
  void dispose() {
    _descriptionController.dispose();
    _quantityController.dispose();
    _unitCostController.dispose();
    _unitPriceController.dispose();
    _lotController.dispose();
    super.dispose();
  }

  int _moneyToCents(String value) {
    final parsed = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return (parsed * 100).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await ref.read(workOrderRepositoryProvider).addMaterial(
            workOrderId: widget.workOrderId,
            description: _descriptionController.text.trim(),
            quantity:
                double.parse(_quantityController.text.replaceAll(',', '.')),
            unitCostCents: _moneyToCents(_unitCostController.text),
            unitPriceCents: _moneyToCents(_unitPriceController.text),
            productId: _productId,
            warehouseId: _warehouseId,
            lotCode: _lotController.text.trim().isEmpty
                ? null
                : _lotController.text.trim(),
          );

      if (result.fromStock) {
        // O saldo mudou: quem estiver olhando a tela de estoque precisa ver.
        invalidateStockAfterMovement(ref);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);

      if (result.fromStock) {
        final applied = (result.unitCostCents / 100).toStringAsFixed(2);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Material baixado do estoque. Custo aplicado: R\$ $applied '
              '(custo médio do saldo).',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AppError ? e.userMessage : 'Não foi possível salvar.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Material aplicado',
              icon: Icons.inventory_2_outlined,
              child: AppFormGrid(
                children: [
                  // Seletor de catálogo. Escolher um produto faz o servidor
                  // baixar o estoque e aplicar o custo médio; deixar em
                  // "Fora do catálogo" registra apenas o custo digitado.
                  Consumer(
                    builder: (context, ref, _) {
                      final productsAsync =
                          ref.watch(stockTrackedProductsProvider);
                      return productsAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (products) => DropdownButtonFormField<String?>(
                          initialValue: _productId,
                          decoration: const InputDecoration(
                            labelText: 'Produto do estoque',
                            prefixIcon: Icon(Icons.inventory_outlined),
                            helperText:
                                'Baixa o saldo e usa o custo médio. Deixe em '
                                '"Fora do catálogo" para item avulso.',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Fora do catálogo'),
                            ),
                            ...products.map(
                              (p) => DropdownMenuItem<String?>(
                                value: p.id,
                                child: Text(p.displayName),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _productId = value;
                              _trackingType = ProductTrackingType.none;
                              if (value != null) {
                                // O custo virá do saldo; digitar aqui não
                                // teria efeito e confundiria.
                                _unitCostController.text = '0';
                                final p = products
                                    .where((e) => e.id == value)
                                    .firstOrNull;
                                if (p != null &&
                                    _descriptionController.text
                                        .trim()
                                        .isEmpty) {
                                  _descriptionController.text = p.name;
                                }
                                _trackingType =
                                    p?.trackingType ?? ProductTrackingType.none;
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
                  // Depósito só aparece quando há produto e mais de um depósito
                  // — quem tem um só não precisa ver o campo (F3-P4).
                  if (_productId != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final whAsync = ref.watch(warehousesProvider);
                        return whAsync.maybeWhen(
                          data: (warehouses) {
                            if (warehouses.length < 2) {
                              return const SizedBox.shrink();
                            }
                            return DropdownButtonFormField<String?>(
                              initialValue: _warehouseId,
                              decoration: const InputDecoration(
                                labelText: 'Depósito da baixa',
                                prefixIcon: Icon(Icons.warehouse_outlined),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Padrão da empresa'),
                                ),
                                ...warehouses.map(
                                  (w) => DropdownMenuItem<String?>(
                                    value: w.id,
                                    child: Text(w.name),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _warehouseId = v),
                            );
                          },
                          orElse: () => const SizedBox.shrink(),
                        );
                      },
                    ),
                  if (_trackingType != ProductTrackingType.none)
                    TextFormField(
                      controller: _lotController,
                      decoration: InputDecoration(
                        labelText: _trackingType == ProductTrackingType.serial
                            ? 'Número de série'
                            : 'Lote',
                        prefixIcon: const Icon(Icons.qr_code_2_outlined),
                        helperText: 'Código já existente no depósito.',
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty ? 'Informe o código.' : null,
                    ),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Material',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    validator: (value) =>
                        value == null || value.trim().length < 3
                            ? 'Informe o material.'
                            : null,
                  ),
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                    validator: (value) {
                      final parsed = double.tryParse(
                        (value ?? '').replaceAll(',', '.'),
                      );
                      return parsed == null || parsed <= 0
                          ? 'Informe uma quantidade válida.'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: _unitCostController,
                    // Com produto do catálogo, o custo é o médio do saldo,
                    // definido no servidor. Editar aqui não teria efeito.
                    enabled: _productId == null,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Custo unitário',
                      helperText: _productId == null
                          ? null
                          : 'Definido pelo custo médio do estoque.',
                    ),
                  ),
                  TextFormField(
                    controller: _unitPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration:
                        const InputDecoration(labelText: 'Preço unitário'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar material'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcceptanceForm extends ConsumerStatefulWidget {
  const _AcceptanceForm({required this.workOrder});

  final WorkOrder workOrder;

  @override
  ConsumerState<_AcceptanceForm> createState() => _AcceptanceFormState();
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm({required this.workOrderId});

  final String workOrderId;

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '0');
  final _descriptionController = TextEditingController();
  String _kind = 'travel';
  bool _isSaving = false;

  static const _kinds = [
    ('travel', 'Deslocamento'),
    ('toll', 'Pedágio'),
    ('parking', 'Estacionamento'),
    ('meal', 'Alimentação'),
    ('lodging', 'Hospedagem'),
    ('freight', 'Frete'),
    ('other', 'Outro'),
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  int _moneyToCents(String value) {
    final parsed = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return (parsed * 100).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await ref.read(workOrderRepositoryProvider).addExpense(
            workOrderId: widget.workOrderId,
            kind: _kind,
            amountCents: _moneyToCents(_amountController.text),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Despesa operacional',
              icon: Icons.receipt_long_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormGrid(
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _kind,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de despesa',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: _kinds
                            .map(
                              (kind) => DropdownMenuItem(
                                value: kind.$1,
                                child: Text(
                                  kind.$2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() => _kind = value ?? _kind),
                      ),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Valor',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        validator: (value) {
                          final cents = _moneyToCents(value ?? '');
                          return cents <= 0 ? 'Informe um valor válido.' : null;
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar despesa'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AcceptanceFormState extends ConsumerState<_AcceptanceForm> {
  final _formKey = GlobalKey<FormState>();
  final _signatureKey = GlobalKey();
  final _signerNameController = TextEditingController();
  final _documentController = TextEditingController();
  final _commentsController = TextEditingController();
  final List<Offset?> _signaturePoints = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _signerNameController.dispose();
    _documentController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      if (_signaturePoints.whereType<Offset>().isNotEmpty) {
        final signatureBytes = await _signatureToPng();
        await ref.read(workOrderRepositoryProvider).uploadEvidence(
              tenantId: widget.workOrder.tenantId,
              workOrderId: widget.workOrder.id,
              kind: 'signature',
              fileName: 'assinatura.png',
              bytes: signatureBytes,
              mimeType: 'image/png',
            );
      }
      await ref.read(workOrderRepositoryProvider).recordAcceptance(
            workOrderId: widget.workOrder.id,
            signerName: _signerNameController.text.trim(),
            signerDocumentPartial: _documentController.text.trim().isEmpty
                ? null
                : _documentController.text.trim(),
            comments: _commentsController.text.trim().isEmpty
                ? null
                : _commentsController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<Uint8List> _signatureToPng() async {
    final box = _signatureKey.currentContext!.findRenderObject()! as RenderBox;
    final size = box.size;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final background = Paint()..color = const Color(0xFFE8EEF5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(20),
      ),
      background,
    );
    _SignaturePainter(_signaturePoints).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.ceil(),
      size.height.ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NeomorphicInset(
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Confirme quem recebeu e aprovou a execução do serviço.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppFormGrid(
              children: [
                TextFormField(
                  controller: _signerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do responsável *',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'Informe o responsável pelo aceite.'
                      : null,
                ),
                TextFormField(
                  controller: _documentController,
                  decoration: const InputDecoration(
                    labelText: 'Documento parcial',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _commentsController,
              decoration: const InputDecoration(
                labelText: 'Observações do aceite',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Assinatura do cliente',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            _SignatureBox(
              key: _signatureKey,
              points: _signaturePoints,
              onChanged: (point) {
                setState(() => _signaturePoints.add(point));
              },
              onStrokeEnd: () {
                setState(() => _signaturePoints.add(null));
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _signaturePoints.isEmpty
                    ? null
                    : () => setState(_signaturePoints.clear),
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Limpar assinatura'),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Salvar aceite'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceForm extends ConsumerStatefulWidget {
  const _EvidenceForm({required this.workOrder});

  final WorkOrder workOrder;

  @override
  ConsumerState<_EvidenceForm> createState() => _EvidenceFormState();
}

class _EvidenceFormState extends ConsumerState<_EvidenceForm> {
  PlatformFile? _file;
  bool _isSaving = false;

  Future<void> _pickFile() async {
    try {
      final files = await pickAttachments(
        allowDocuments: true,
        allowMultiple: false,
      );
      if (files == null || files.isEmpty) return;
      setState(() => _file = files.single);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Nao foi possivel abrir o seletor. ${error.toString()}'),
        ),
      );
    }
  }

  Future<void> _save() async {
    final file = _file;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um arquivo para anexar.')),
      );
      return;
    }
    setState(() => _isSaving = true);

    try {
      await ref.read(workOrderRepositoryProvider).uploadEvidence(
            tenantId: widget.workOrder.tenantId,
            workOrderId: widget.workOrder.id,
            kind: _kindFor(file),
            fileName: file.name,
            bytes: bytes,
            mimeType: _mimeFor(file.name),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _kindFor(PlatformFile file) {
    final mime = _mimeFor(file.name);
    if (mime.startsWith('image/')) return 'photo';
    if (mime.startsWith('video/')) return 'video';
    return 'document';
  }

  String _mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeomorphicInset(
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Fotos, vídeos e PDFs ficam vinculados à etapa da OS, ao histórico do serviço e ao catálogo do cliente/equipamento.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isSaving ? null : _pickFile,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Selecionar foto ou arquivo'),
          ),
          if (file != null) ...[
            const SizedBox(height: 12),
            NeomorphicInset(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(file.name),
                subtitle: Text('${(file.size / 1024).toStringAsFixed(1)} KB'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: const Icon(Icons.attach_file_outlined),
            label: const Text('Anexar ao histórico'),
          ),
        ],
      ),
    );
  }
}

class _SignatureBox extends StatelessWidget {
  const _SignatureBox({
    super.key,
    required this.points,
    required this.onChanged,
    required this.onStrokeEnd,
  });

  final List<Offset?> points;
  final ValueChanged<Offset> onChanged;
  final VoidCallback onStrokeEnd;

  @override
  Widget build(BuildContext context) {
    return NeomorphicInset(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 180,
        child: GestureDetector(
          onPanUpdate: (details) => onChanged(details.localPosition),
          onPanEnd: (_) => onStrokeEnd(),
          child: CustomPaint(
            painter: _SignaturePainter(points),
            child: Center(
              child: points.isEmpty
                  ? Text(
                      'Assine aqui',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.points);

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5F56A6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      if (current != null && next != null) {
        canvas.drawLine(current, next, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return true;
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}
