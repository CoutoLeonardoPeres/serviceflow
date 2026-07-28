import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/files/attachment_link_action.dart';
import '../../../core/files/stored_attachment.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/attachment_gallery.dart';
import '../../../core/widgets/attachment_preview_dialog.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../shared/providers/tenant_provider.dart';
import '../../communications/presentation/send_message_panel.dart';
import '../../customers/application/customer_list_notifier.dart';
import '../application/quotation_list_notifier.dart';
import '../domain/quotation.dart';
import '../pdf/quotation_pdf_generator.dart';
import 'widgets/quotation_status_chip.dart';
import '../../work_orders/application/work_order_list_notifier.dart';

class QuotationDetailScreen extends ConsumerWidget {
  const QuotationDetailScreen({super.key, required this.quotationId});

  final String quotationId;

  Future<void> _copyPublicLink(
    BuildContext context,
    WidgetRef ref,
    Quotation quote,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final token = await ref
          .read(quotationRepositoryProvider)
          .createPublicLink(quote.id);
      final link = '${Uri.base.origin}/#${AppRoutes.quotationPublic(token)}';
      await Clipboard.setData(ClipboardData(text: link));
      ref.invalidate(quotationDetailProvider(quote.id));
      messenger.showSnackBar(
        const SnackBar(content: Text('Link público copiado.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível gerar o link agora.'),
        ),
      );
    }
  }

  Future<void> _generatePdf(
    BuildContext context,
    WidgetRef ref,
    Quotation quote,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // As linhas não vêm no objeto Quotation — sem buscá-las, o PDF saía só
      // com os totais.
      final items =
          await ref.read(quotationRepositoryProvider).listItems(quote.id);
      final result = await QuotationPdfGenerator.generate(quote, items: items);
      await Printing.sharePdf(
        bytes: result.bytes,
        filename: result.fileName,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('PDF do orçamento gerado.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível gerar o PDF agora.'),
        ),
      );
    }
  }

  Future<void> _revokePublicLinks(
    BuildContext context,
    WidgetRef ref,
    Quotation quote,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revogar link público?'),
        content: const Text(
          'Links já enviados para este orçamento deixarão de funcionar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await ref
          .read(quotationRepositoryProvider)
          .revokePublicLinks(quote.id);
      ref.invalidate(quotationDetailProvider(quote.id));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Nenhum link ativo para revogar.'
                : 'Link público revogado.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível revogar o link agora.'),
        ),
      );
    }
  }

  Future<void> _cancelQuotation(
    BuildContext context,
    WidgetRef ref,
    Quotation quote,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _CancelReasonDialog(
        title: 'Cancelar orçamento',
        hint: 'Ex.: cliente desistiu, preço fora do orçamento…',
      ),
    );
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(quotationRepositoryProvider).cancel(quote.id, reason);
      ref.invalidate(quotationDetailProvider(quote.id));
      ref.invalidate(quotationListProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Orçamento cancelado.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is Exception ? e.toString().replaceAll('Exception: ', '') : 'Erro ao cancelar orçamento.')),
      );
    }
  }

  Future<void> _convertToWorkOrder(
    BuildContext context,
    WidgetRef ref,
    Quotation quote,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final workOrder = await ref
          .read(workOrderRepositoryProvider)
          .convertApprovedQuotation(quote.id);
      ref.read(workOrderListProvider.notifier).refresh();
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('OS gerada a partir do orçamento.')),
      );
      context.go(AppRoutes.workOrderDetail(workOrder.id));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível gerar a OS agora.'),
        ),
      );
    }
  }

  Future<void> _openAttachment(
    BuildContext context,
    WidgetRef ref,
    StoredAttachment attachment,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref
          .read(quotationRepositoryProvider)
          .createAttachmentSignedUrl(attachment.storagePath);
      await openAttachmentLink(url);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o anexo agora.')),
      );
    }
  }

  Future<void> _downloadAttachment(
    BuildContext context,
    WidgetRef ref,
    StoredAttachment attachment,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref
          .read(quotationRepositoryProvider)
          .createAttachmentSignedUrl(attachment.storagePath);
      await downloadAttachmentLink(url, attachment.fileName);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível baixar o anexo agora.')),
      );
    }
  }

  Future<void> _previewAttachment(
    BuildContext context,
    WidgetRef ref,
    StoredAttachment attachment,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ref
          .read(quotationRepositoryProvider)
          .createAttachmentSignedUrl(attachment.storagePath);
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
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível visualizar o anexo agora.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotation = ref.watch(quotationDetailProvider(quotationId));
    final attachments = ref.watch(quotationAttachmentsProvider(quotationId));
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date = DateFormat('dd/MM/yyyy', 'pt_BR');

    return Scaffold(
      appBar: AppBar(title: const Text('Orçamento')),
      body: quotation.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ErrorView(
          message: 'Não foi possível carregar este orçamento.',
          onRetry: () => ref.invalidate(quotationDetailProvider(quotationId)),
        ),
        data: (quote) {
          final itemsAsync = ref.watch(
            quotationItemsProvider((
              quotationId: quote.id,
              versionId: quote.currentVersionId,
            )),
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              NeomorphicPanel(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${quote.displayNumber} · ${quote.customerName ?? 'Cliente'}',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 12),
                        QuotationStatusChip(status: quote.status),
                      ],
                    ),
                    if (quote.requestTitle != null) ...[
                      const SizedBox(height: 8),
                      Text(quote.requestTitle!),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      currency.format(quote.totalCents / 100),
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                        'Subtotal: ${currency.format(quote.subtotalCents / 100)}'),
                    Text('Impostos: ${currency.format(quote.taxCents / 100)}'),
                    Text(
                        'Descontos: ${currency.format(quote.discountCents / 100)}'),
                    if (quote.validUntil != null)
                      Text('Validade: ${date.format(quote.validUntil!)}'),
                    if (quote.notes != null) ...[
                      const SizedBox(height: 16),
                      Text(quote.notes!),
                    ],
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _generatePdf(context, ref, quote),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Gerar PDF'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _copyPublicLink(context, ref, quote),
                          icon: const Icon(Icons.link),
                          label: const Text('Copiar link público'),
                        ),
                        Consumer(builder: (context, ref, _) {
                          final tenant = ref.watch(currentTenantProvider);
                          final customerAsync = ref.watch(
                              customerDetailProvider(quote.customerId));
                          return customerAsync.maybeWhen(
                            data: (c) => SendMessageButton(
                              messageContext: MessageContext(
                                customerId: c.id,
                                customerName: c.name,
                                customerPhone: c.phone ?? '',
                                customerEmail: c.email ?? '',
                                companyName:
                                    tenant?['name'] as String? ?? '',
                                quotationNumber: quote.number.toString(),
                                amount: (quote.totalCents / 100)
                                    .toStringAsFixed(2)
                                    .replaceAll('.', ','),
                                relatedEntity: 'quotations',
                                relatedEntityId: quote.id,
                              ),
                            ),
                            orElse: () => const SizedBox.shrink(),
                          );
                        }),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _revokePublicLinks(context, ref, quote),
                          icon: const Icon(Icons.link_off_outlined),
                          label: const Text('Revogar link público'),
                        ),
                        if (quote.status == QuotationStatus.approved)
                          FilledButton.icon(
                            onPressed: () =>
                                _convertToWorkOrder(context, ref, quote),
                            icon: const Icon(Icons.engineering_outlined),
                            label: const Text('Gerar OS'),
                          ),
                        if (!quote.status.isTerminal)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _cancelQuotation(context, ref, quote),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error,
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Cancelar orçamento'),
                          ),
                      ],
                    ),
                    if (quote.status == QuotationStatus.cancelled &&
                        quote.cancellationReason != null) ...[
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
                              color: Theme.of(context).colorScheme.onErrorContainer,
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
                                    quote.cancellationReason!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onErrorContainer,
                                        ),
                                  ),
                                  if (quote.cancelledAt != null)
                                    Text(
                                      DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                                          .format(quote.cancelledAt!.toLocal()),
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
                padding: const EdgeInsets.all(20),
                child: itemsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const Text(
                      'Nao foi possivel carregar as linhas deste orçamento.'),
                  data: (items) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Composição do orçamento',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
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
                              '${item.kind.label} · Qtd ${item.quantity} · Unit. ${currency.format(item.unitPriceCents / 100)}',
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
              attachments.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const AttachmentGallery(
                  title: 'Arquivos do orçamento',
                  attachments: [],
                  emptyMessage: 'Não foi possível carregar os anexos agora.',
                  onOpen: _noopAttachmentAction,
                  onDownload: _noopAttachmentAction,
                ),
                data: (items) => AttachmentGallery(
                  title: 'Arquivos do orçamento',
                  attachments: items,
                  emptyMessage: 'Este orçamento ainda não possui anexos.',
                  onPreview: (attachment) =>
                      _previewAttachment(context, ref, attachment),
                  onOpen: (attachment) =>
                      _openAttachment(context, ref, attachment),
                  onDownload: (attachment) =>
                      _downloadAttachment(context, ref, attachment),
                  thumbnailUrlBuilder: (attachment) async {
                    if (!attachment.isImage) return null;
                    return ref
                        .read(quotationRepositoryProvider)
                        .createAttachmentSignedUrl(attachment.storagePath);
                  },
                ),
              ),
              const SizedBox(height: 16),
              // ── Versões do orçamento ──────────────────────────────────────
              _QuotationVersionsPanel(quotationId: quote.id),
              const SizedBox(height: 16),
              // ── Histórico de status ───────────────────────────────────────
              _QuotationHistoryPanel(quotationId: quote.id),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _noopAttachmentAction(StoredAttachment attachment) async {}

// ── Painel de versões do orçamento ────────────────────────────────────────────

class _QuotationVersionsPanel extends ConsumerWidget {
  const _QuotationVersionsPanel({required this.quotationId});

  final String quotationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionsAsync = ref.watch(quotationVersionsProvider(quotationId));
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return versionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (versions) {
        if (versions.isEmpty) return const SizedBox.shrink();
        return NeomorphicPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Versões do orçamento',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...versions.map((v) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: v.isCurrent
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      child: Text(
                        '${v.versionNumber}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: v.isCurrent
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    title: Text(v.label),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                          .format(v.createdAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Text(
                      currency.format(v.totalCents / 100),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }
}

// ── Painel de histórico de status do orçamento ────────────────────────────────

class _QuotationHistoryPanel extends ConsumerWidget {
  const _QuotationHistoryPanel({required this.quotationId});

  final String quotationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync =
        ref.watch(quotationStatusHistoryProvider(quotationId));

    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (events) {
        if (events.isEmpty) return const SizedBox.shrink();
        return NeomorphicPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Histórico de status',
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
                                _statusLabel(event.status),
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
                                    .format(event.changedAt.toLocal()),
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

  String _statusLabel(String status) => switch (status) {
        'draft' => 'Rascunho',
        'under_review' => 'Em revisão',
        'sent' => 'Enviado',
        'viewed' => 'Visualizado',
        'awaiting_approval' => 'Aguardando aprovação',
        'approved' => 'Aprovado',
        'rejected' => 'Rejeitado',
        'change_requested' => 'Solicitou alteração',
        'expired' => 'Expirado',
        'cancelled' => 'Cancelado',
        _ => status,
      };
}

// ── Diálogo de motivo de cancelamento ────────────────────────────────────────

class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog({required this.title, required this.hint});

  final String title;
  final String hint;

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
            labelText: 'Motivo *',
            hintText: widget.hint,
            border: const OutlineInputBorder(),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Informe o motivo do cancelamento.';
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
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_ctrl.text.trim());
            }
          },
          child: const Text('Confirmar cancelamento'),
        ),
      ],
    );
  }
}
