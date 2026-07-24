import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/quotation_list_notifier.dart';
import '../domain/quotation.dart';

class QuotationPublicScreen extends ConsumerStatefulWidget {
  const QuotationPublicScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<QuotationPublicScreen> createState() =>
      _QuotationPublicScreenState();
}

class _QuotationPublicScreenState extends ConsumerState<QuotationPublicScreen> {
  final _nameController = TextEditingController();
  final _commentsController = TextEditingController();
  QuotationPublicDecision? _sentDecision;

  @override
  void dispose() {
    _nameController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _decide(QuotationPublicDecision decision) async {
    if (_nameController.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do aprovador.')),
      );
      return;
    }
    await ref.read(quotationRepositoryProvider).decidePublic(
          token: widget.token,
          decision: decision,
          approverName: _nameController.text,
          comments: _commentsController.text,
        );
    if (!mounted) return;
    setState(() => _sentDecision = decision);
  }

  @override
  Widget build(BuildContext context) {
    final quoteAsync = ref.watch(_publicQuotationProvider(widget.token));
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: quoteAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const ErrorView(
                message: 'Link inválido, expirado ou indisponível.',
              ),
              data: (quote) {
                final sent = _sentDecision;
                return NeomorphicPanel(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Orçamento ${quote.displayNumber}',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(quote.customerName ?? 'Cliente'),
                      const SizedBox(height: 22),
                      Text(
                        currency.format(quote.totalCents / 100),
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                      ),
                      if (quote.notes != null) ...[
                        const SizedBox(height: 18),
                        Text(quote.notes!),
                      ],
                      const SizedBox(height: 24),
                      if (sent == null) ...[
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nome do aprovador',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _commentsController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Comentários',
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: () =>
                                  _decide(QuotationPublicDecision.approved),
                              icon: const Icon(Icons.check),
                              label: const Text('Aprovar'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _decide(
                                QuotationPublicDecision.changeRequested,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Solicitar alteração'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _decide(QuotationPublicDecision.rejected),
                              icon: const Icon(Icons.close),
                              label: const Text('Rejeitar'),
                            ),
                          ],
                        ),
                      ] else
                        Text(
                          'Resposta registrada: ${sent.label}.',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

final _publicQuotationProvider =
    FutureProvider.autoDispose.family<Quotation, String>((ref, token) async {
  return ref.read(quotationRepositoryProvider).getPublicByToken(token);
});
