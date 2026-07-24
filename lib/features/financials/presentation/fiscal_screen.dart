import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/financial_list_notifier.dart';
import '../domain/receipt.dart';
import '../domain/receivable.dart';
import '../pdf/receipt_pdf_generator.dart';

class FiscalScreen extends ConsumerStatefulWidget {
  const FiscalScreen({super.key});

  @override
  ConsumerState<FiscalScreen> createState() => _FiscalScreenState();
}

class _FiscalScreenState extends ConsumerState<FiscalScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(financialListProvider.notifier).load();
    });
  }

  Future<void> _showReceiptPdf(Receipt receipt) async {
    final result = await ReceiptPdfGenerator.generate(receipt);
    await Printing.layoutPdf(
      name: result.fileName,
      onLayout: (_) async => result.bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financialListProvider);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final receipts = state.items
        .where((item) => item.latestReceipt != null)
        .map((item) => item.latestReceipt!)
        .toList()
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    final paidWithoutReceipt = state.items.where(
      (item) =>
          item.status == ReceivableStatus.paid && item.latestReceipt == null,
    );
    final documentedCents = receipts.fold<int>(
      0,
      (total, receipt) => total + receipt.amountCents,
    );
    final openDocuments = state.items.where(
      (item) => item.balanceCents > 0 && item.latestReceipt != null,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiscal'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(financialListProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(financialListProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            NeomorphicPanel(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Documentação e conferência',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Acompanhe os recibos emitidos, localize pendências documentais e use esta base como ponto de partida para a evolução fiscal completa do sistema.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 16),
                  const Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      NeomorphicBadge(
                        icon: Icons.receipt_long_outlined,
                        label: 'Recibos emitidos',
                      ),
                      NeomorphicBadge(
                        icon: Icons.fact_check_outlined,
                        label: 'Conferência documental',
                      ),
                      NeomorphicBadge(
                        icon: Icons.rule_folder_outlined,
                        label: 'Base para notas e retenções',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            NeomorphicPanel(
              borderRadius: 24,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _FiscalSummaryTile(
                    icon: Icons.description_outlined,
                    label: 'Recibos emitidos',
                    value: receipts.length.toString(),
                  ),
                  _FiscalSummaryTile(
                    icon: Icons.payments_outlined,
                    label: 'Valor documentado',
                    value: currency.format(documentedCents / 100),
                  ),
                  _FiscalSummaryTile(
                    icon: Icons.pending_actions_outlined,
                    label: 'Pagos sem recibo',
                    value: paidWithoutReceipt.length.toString(),
                  ),
                  _FiscalSummaryTile(
                    icon: Icons.warning_amber_outlined,
                    label: 'Abertos com recibo',
                    value: openDocuments.length.toString(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 96),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null)
              ErrorView(
                message: state.error?.userMessage ?? 'Erro ao carregar fiscal.',
                onRetry: () =>
                    ref.read(financialListProvider.notifier).refresh(),
              )
            else if (state.isEmpty)
              const EmptyView(
                message:
                    'Ainda não há documentos emitidos. Os recibos fiscais aparecerão aqui após registrar pagamentos.',
              )
            else ...[
              Text(
                'Últimos documentos emitidos',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              if (receipts.isEmpty)
                const NeomorphicPanel(
                  borderRadius: 24,
                  child: Text(
                    'Nenhum recibo foi emitido até agora. Registre um pagamento para gerar o primeiro documento.',
                  ),
                )
              else
                ...receipts.map(
                  (receipt) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ReceiptDocumentCard(
                      receipt: receipt,
                      onOpenPdf: () => _showReceiptPdf(receipt),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FiscalSummaryTile extends StatelessWidget {
  const _FiscalSummaryTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: NeomorphicInset(
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptDocumentCard extends StatelessWidget {
  const _ReceiptDocumentCard({
    required this.receipt,
    required this.onOpenPdf,
  });

  final Receipt receipt;
  final VoidCallback onOpenPdf;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date = DateFormat('dd/MM/yyyy');

    return NeomorphicPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  receipt.customerName ?? 'Cliente',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              NeomorphicBadge(
                icon: Icons.receipt_long_outlined,
                label: receipt.displayNumber,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            receipt.receivableDescription ?? 'Documento de recebimento',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.3,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              NeomorphicBadge(
                icon: Icons.payments_outlined,
                label: currency.format(receipt.amountCents / 100),
              ),
              NeomorphicBadge(
                icon: Icons.event_outlined,
                label: 'Emitido em ${date.format(receipt.issuedAt)}',
              ),
              if (receipt.paymentMethod != null)
                NeomorphicBadge(
                  icon: Icons.account_balance_wallet_outlined,
                  label: _paymentMethodLabel(receipt.paymentMethod!),
                ),
              if (receipt.paymentReference != null &&
                  receipt.paymentReference!.trim().isNotEmpty)
                NeomorphicBadge(
                  icon: Icons.tag_outlined,
                  label: receipt.paymentReference!,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onOpenPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Visualizar documento'),
            ),
          ),
        ],
      ),
    );
  }
}

String _paymentMethodLabel(String method) {
  switch (method) {
    case 'pix_manual':
      return 'Pix manual';
    case 'cash':
      return 'Dinheiro';
    case 'transfer':
      return 'Transferência';
    case 'card_machine':
      return 'Máquina de cartão';
    default:
      return 'Outro';
  }
}
