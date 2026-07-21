import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/validators.dart';
import '../application/tenant_notifier.dart';

/// Tela de criação da empresa — exibida quando o usuário está autenticado
/// mas não possui membership ativa.
class CreateTenantScreen extends ConsumerStatefulWidget {
  const CreateTenantScreen({super.key});

  @override
  ConsumerState<CreateTenantScreen> createState() =>
      _CreateTenantScreenState();
}

class _CreateTenantScreenState extends ConsumerState<CreateTenantScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _slugCtrl  = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    super.dispose();
  }

  void _autoFillSlug(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    _slugCtrl.text = slug.length > 63 ? slug.substring(0, 63) : slug;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(tenantNotifierProvider.notifier).createTenant(
          name: _nameCtrl.text.trim(),
          slug: _slugCtrl.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tenantNotifierProvider);
    final isLoading = state is TenantActionLoading;

    ref.listen<TenantActionState>(tenantNotifierProvider, (_, next) {
      if (next is TenantActionError) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(next.error.userMessage),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        ref.read(tenantNotifierProvider.notifier).resetState();
      }
    });

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.business_rounded, size: 48, color: colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        'Criar sua empresa',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Configure sua empresa para começar a usar o ServiceFlow.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _nameCtrl,
                        textInputAction: TextInputAction.next,
                        enabled: !isLoading,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nome da empresa *',
                          hintText: 'Ex: Alpha Elétrica',
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                        validator: (v) => validateRequired(v, 'Nome da empresa'),
                        onChanged: _autoFillSlug,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _slugCtrl,
                        textInputAction: TextInputAction.done,
                        enabled: !isLoading,
                        decoration: const InputDecoration(
                          labelText: 'Identificador único *',
                          hintText: 'alpha-eletrica',
                          prefixIcon: Icon(Icons.link_rounded),
                          helperText: 'Apenas letras minúsculas, números e hífens.',
                          helperMaxLines: 2,
                        ),
                        validator: validateSlug,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        child: isLoading
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text('Criar empresa e continuar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
