import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_loading.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../application/auth_notifier.dart';
import '../data/invitation_repository.dart';
import '../domain/invitation_preview.dart';

final invitationRepositoryProvider = Provider<InvitationRepository>(
  (ref) => InvitationRepository(ref.read(supabaseClientProvider)),
);

final invitationPreviewProvider =
    FutureProvider.autoDispose.family<InvitationPreview, String>(
  (ref, token) => ref.read(invitationRepositoryProvider).getPreview(token),
);

class InvitationAcceptScreen extends ConsumerStatefulWidget {
  const InvitationAcceptScreen({
    super.key,
    required this.inviteToken,
  });

  final String inviteToken;

  @override
  ConsumerState<InvitationAcceptScreen> createState() =>
      _InvitationAcceptScreenState();
}

class _InvitationAcceptScreenState
    extends ConsumerState<InvitationAcceptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authNotifierProvider.notifier).signUpFromInvitation(
          fullName: _nameCtrl.text,
          email: _emailCtrl.text,
          password: _passCtrl.text,
          inviteToken: widget.inviteToken,
        );
  }

  @override
  Widget build(BuildContext context) {
    final previewAsync = ref.watch(
      invitationPreviewProvider(widget.inviteToken),
    );
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState is AuthActionLoading;

    ref.listen<AuthActionState>(authNotifierProvider, (_, next) {
      if (next is AuthActionError) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(next.error.userMessage),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        ref.read(authNotifierProvider.notifier).resetState();
      } else if (next is AuthActionSuccess) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(next.message ?? 'Convite aceito com sucesso.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        ref.read(authNotifierProvider.notifier).resetState();
        context.go(AppRoutes.dashboard);
      }
    });

    return Scaffold(
      body: NeomorphicBackdrop(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: NeomorphicPanel(
                borderRadius: 34,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.surfaceRaised,
                    AppColors.surfaceCanvas,
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(34, 34, 34, 30),
                child: previewAsync.when(
                  loading: () => const AppLoading(
                    message: 'Validando convite...',
                  ),
                  error: (error, _) => _InvitationErrorView(
                    message: error.toString(),
                    onBackToLogin: () => context.go(AppRoutes.login),
                  ),
                  data: (preview) {
                    if (_emailCtrl.text.isEmpty) {
                      _emailCtrl.text = preview.email;
                    }
                    if (!preview.isValid) {
                      return _InvitationErrorView(
                        message:
                            'Este convite está expirado, revogado ou já foi utilizado.',
                        onBackToLogin: () => context.go(
                          '${AppRoutes.login}?invite=${widget.inviteToken}&tenant=${preview.tenantSlug}',
                        ),
                      );
                    }
                    return Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Aceitar convite',
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Crie sua conta para entrar em ${preview.tenantName} como ${preview.roleName}.',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppColors.inkMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: NeomorphicBadge(
                              icon: Icons.schedule_outlined,
                              label:
                                  'Convite válido até ${DateFormat('dd/MM/yyyy', 'pt_BR').format(preview.expiresAt)}',
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _nameCtrl,
                            enabled: !isLoading,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Nome completo',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) =>
                                validateRequired(value, 'Nome completo'),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailCtrl,
                            enabled: false,
                            decoration: const InputDecoration(
                              labelText: 'E-mail do convite',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passCtrl,
                            enabled: !isLoading,
                            obscureText: _obscurePass,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Criar senha',
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePass = !_obscurePass,
                                ),
                                icon: Icon(
                                  _obscurePass
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: validatePassword,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmCtrl,
                            enabled: !isLoading,
                            obscureText: _obscureConfirm,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Confirmar senha',
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value != _passCtrl.text) {
                                return 'As senhas não conferem.';
                              }
                              return validatePassword(value);
                            },
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: isLoading ? null : _submit,
                            child: isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Criar conta e entrar'),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: isLoading
                                ? null
                                : () => context.go(
                                      '${AppRoutes.login}?invite=${widget.inviteToken}&tenant=${preview.tenantSlug}',
                                    ),
                            child: const Text('Já tenho conta'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InvitationErrorView extends StatelessWidget {
  const _InvitationErrorView({
    required this.message,
    required this.onBackToLogin,
  });

  final String message;
  final VoidCallback onBackToLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.mark_email_unread_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Convite indisponível',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.inkMuted,
              ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: onBackToLogin,
          child: const Text('Ir para o login'),
        ),
      ],
    );
  }
}
