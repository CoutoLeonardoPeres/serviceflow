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

  Future<void> _generatePdf(BuildContext context, Quotation quote) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await QuotationPdfGenerator.generate(quote);
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
                          onPressed: () => _generatePdf(context, quote),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Gerar PDF'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _copyPublicLink(context, ref, quote),
                          icon: const Icon(Icons.link),
                          label: const Text('Copiar link público'),
                        ),
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
                      ],
                    ),
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
            ],
          );
        },
      ),
    );
  }
}

Future<void> _noopAttachmentAction(StoredAttachment attachment) async {}
