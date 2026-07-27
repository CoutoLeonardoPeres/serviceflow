import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/financial_list_notifier.dart';
import '../domain/payable.dart';
import '../domain/receivable.dart';

/// Lista de contas a pagar (F4-P1). Sem paginação própria: reaproveita
/// `list_payables`, que já devolve tudo — volume normal é bem menor que o
/// de recebíveis.
final payablesProvider = FutureProvider.autoDispose<List<Payable>>(
  (ref) => ref.read(financialRepositoryProvider).listPayables(),
);

class PayablesScreen extends ConsumerWidget {
  const PayablesScreen({super.key});

  Future<void> _openPaymentDialog(
    BuildContext context,
    WidgetRef ref,
    Payable payable,
  ) async {
    final saved = await showAppFormDialog<bool>(
      context: context,
      title: 'Baixa manual',
      maxWidth: 620,
      child: _PayablePaymentForm(payable: payable),
    );
    if (saved == true) {
      ref.invalidate(payablesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pagamento registrado.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(payablesProvider);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas a pagar'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(payablesProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(payablesProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorView(
            message: 'Erro ao carregar contas a pagar.',
            onRetry: () => ref.invalidate(payablesProvider),
          ),
          data: (items) {
            final openBalance =
                items.fold<int>(0, (total, p) => total + p.balanceCents);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                NeomorphicPanel(
                  borderRadius: 24,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 220,
                        child: NeomorphicInset(
                          child: Row(
                            children: [
                              Icon(
                                Icons.account_balance_wallet_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Saldo em aberto'),
                                    const SizedBox(height: 2),
                                    Text(
                                      currency.format(openBalance / 100),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  const EmptyView(
                    message:
                        'Nenhuma conta a pagar. Recebimentos de pedidos de compra geram cobranças aqui.',
                  )
                else
                  ...items.map(
                    (payable) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PayableCard(
                        payable: payable,
                        onRegisterPayment: () =>
                            _openPaymentDialog(context, ref, payable),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PayableCard extends StatelessWidget {
  const _PayableCard({required this.payable, required this.onRegisterPayment});

  final Payable payable;
  final VoidCallback onRegisterPayment;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final date = DateFormat('dd/MM/yyyy');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    payable.supplierName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Chip(
                  avatar: Icon(
                    payable.status == ReceivableStatus.paid
                        ? Icons.check_circle_outline
                        : Icons.pending_actions_outlined,
                    size: 18,
                  ),
                  label: Text(payable.status.label),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(payable.description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                NeomorphicBadge(
                  icon: Icons.payments_outlined,
                  label: currency.format(payable.balanceCents / 100),
                ),
                NeomorphicBadge(
                  icon: Icons.event_outlined,
                  label: 'Vence ${date.format(payable.dueDate)}',
                ),
                NeomorphicBadge(
                  icon: Icons.shopping_cart_outlined,
                  label:
                      'Pedido #${payable.purchaseOrderNumber.toString().padLeft(5, '0')}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: payable.balanceCents <= 0 ? null : onRegisterPayment,
                icon: const Icon(Icons.price_check_outlined),
                label: const Text('Registrar pagamento'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayablePaymentForm extends ConsumerStatefulWidget {
  const _PayablePaymentForm({required this.payable});

  final Payable payable;

  @override
  ConsumerState<_PayablePaymentForm> createState() =>
      _PayablePaymentFormState();
}

class _PayablePaymentFormState extends ConsumerState<_PayablePaymentForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  String _method = 'transfer';
  bool _isSaving = false;

  static const _methods = [
    ('transfer', 'Transferência'),
    ('pix_manual', 'Pix manual'),
    ('cash', 'Dinheiro'),
    ('card_machine', 'Máquina de cartão'),
    ('other', 'Outro'),
  ];

  @override
  void initState() {
    super.initState();
    _amountController.text =
        (widget.payable.balanceCents / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
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
      await ref.read(financialRepositoryProvider).registerPayablePayment(
            payableId: widget.payable.id,
            method: _method,
            amountCents: _moneyToCents(_amountController.text),
            reference: _referenceController.text.trim().isEmpty
                ? null
                : _referenceController.text.trim(),
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
              title: 'Baixa da conta a pagar',
              icon: Icons.price_check_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormGrid(
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _method,
                        decoration: const InputDecoration(
                          labelText: 'Forma de pagamento',
                          prefixIcon:
                              Icon(Icons.account_balance_wallet_outlined),
                        ),
                        items: _methods
                            .map(
                              (method) => DropdownMenuItem(
                                value: method.$1,
                                child: Text(
                                  method.$2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) =>
                                setState(() => _method = value ?? _method),
                      ),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Valor pago',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        validator: (value) {
                          final cents = _moneyToCents(value ?? '');
                          if (cents <= 0) return 'Informe um valor válido.';
                          if (cents > widget.payable.balanceCents) {
                            return 'Valor maior que o saldo em aberto.';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: _referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Referência (nota, NF)',
                          prefixIcon: Icon(Icons.tag_outlined),
                        ),
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
              icon: const Icon(Icons.price_check_outlined),
              label: const Text('Salvar pagamento'),
            ),
          ],
        ),
      ),
    );
  }
}
