import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/work_order_list_notifier.dart';
import '../domain/satisfaction_public_context.dart';

/// Tela pública da pesquisa de satisfação — acessada pelo cliente final,
/// sem autenticação, por link com token opaco.
///
/// O contexto exibido vem do RPC `get_public_satisfaction_context`, que por
/// decisão de segurança devolve apenas número da OS, título do serviço e nome
/// da empresa. Nenhum dado do cliente é exposto nesta página.
class SatisfactionPublicScreen extends ConsumerStatefulWidget {
  const SatisfactionPublicScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<SatisfactionPublicScreen> createState() =>
      _SatisfactionPublicScreenState();
}

class _SatisfactionPublicScreenState
    extends ConsumerState<SatisfactionPublicScreen> {
  final _nameController = TextEditingController();
  final _commentController = TextEditingController();

  int? _rating;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rating = _rating;
    if (rating == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha uma nota de 1 a 5.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(workOrderRepositoryProvider).submitPublicSatisfaction(
            token: widget.token,
            rating: rating,
            contactName: _nameController.text.trim().isEmpty
                ? null
                : _nameController.text.trim(),
            comment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AppError ? e.userMessage : 'Não foi possível enviar.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final contextAsync = ref.watch(_publicSatisfactionProvider(widget.token));

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: contextAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const ErrorView(
                message: 'Link inválido, expirado ou indisponível.',
              ),
              data: (ctx) => _submitted
                  ? _ThankYouPanel(companyName: ctx.companyName)
                  : _SurveyPanel(
                      context: ctx,
                      rating: _rating,
                      submitting: _submitting,
                      nameController: _nameController,
                      commentController: _commentController,
                      onRatingChanged: (r) => setState(() => _rating = r),
                      onSubmit: _submit,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SurveyPanel extends StatelessWidget {
  const _SurveyPanel({
    required this.context,
    required this.rating,
    required this.submitting,
    required this.nameController,
    required this.commentController,
    required this.onRatingChanged,
    required this.onSubmit,
  });

  final SatisfactionPublicContext context;
  final int? rating;
  final bool submitting;
  final TextEditingController nameController;
  final TextEditingController commentController;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);

    return NeomorphicPanel(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.companyName,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Como foi o nosso atendimento?',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            'OS ${context.workOrderNumber} — ${context.serviceTitle}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (context.alreadyAnswered) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Você já respondeu esta pesquisa. Se quiser, pode alterar a '
                'sua resposta abaixo.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: 26),
          _RatingSelector(value: rating, onChanged: onRatingChanged),
          if (rating != null) ...[
            const SizedBox(height: 12),
            Text(
              satisfactionRatingLabel(rating!),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 26),
          TextField(
            controller: nameController,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Seu nome (opcional)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: commentController,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Quer contar mais alguma coisa? (opcional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: submitting ? null : onSubmit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enviar avaliação'),
          ),
        ],
      ),
    );
  }
}

class _RatingSelector extends StatelessWidget {
  const _RatingSelector({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final star = i + 1;
        final selected = value != null && star <= value!;
        return Semantics(
          button: true,
          label: '$star ${star == 1 ? 'estrela' : 'estrelas'} — '
              '${satisfactionRatingLabel(star)}',
          selected: selected,
          child: IconButton(
            iconSize: 44,
            onPressed: () => onChanged(star),
            icon: Icon(
              selected ? Icons.star_rounded : Icons.star_outline_rounded,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
        );
      }),
    );
  }
}

class _ThankYouPanel extends StatelessWidget {
  const _ThankYouPanel({required this.companyName});

  final String companyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NeomorphicPanel(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 68,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'Obrigado pela sua avaliação!',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Text(
            'Sua resposta foi registrada e ajuda $companyName a melhorar o '
            'atendimento.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

final _publicSatisfactionProvider = FutureProvider.autoDispose
    .family<SatisfactionPublicContext, String>((ref, token) async {
  return ref
      .read(workOrderRepositoryProvider)
      .getPublicSatisfactionContext(token);
});
