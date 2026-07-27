import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'neomorphic.dart';

class AppFormSection extends StatelessWidget {
  const AppFormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NeomorphicPanel(
      borderRadius: 32,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.surfaceRaised,
          AppColors.surfaceCanvas,
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NeomorphicInset(
                borderRadius: 18,
                padding: const EdgeInsets.all(12),
                child: Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class AppFormGrid extends StatelessWidget {
  const AppFormGrid({
    super.key,
    required this.children,
    this.minFieldWidth = 180,
    this.spacing = 16,
    this.runSpacing = 16,
  });

  final List<Widget> children;
  final double minFieldWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columns = (availableWidth / minFieldWidth).floor().clamp(1, 6);
        final fieldWidth =
            (availableWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map(
                (child) => SizedBox(
                  width: fieldWidth.isFinite ? fieldWidth : minFieldWidth,
                  child: child,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class AppFormWideField extends StatelessWidget {
  const AppFormWideField({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: double.infinity, child: child);
}

/// Scaffold de formulário sem AppBar: seta de voltar + título inline no topo
/// do conteúdo rolável, e um botão de ação fixo em faixa cheia no rodapé.
/// Substitui o padrão Scaffold(appBar: ...) + botão dentro do scroll nas
/// telas de formulário — ver referência de layout em customer_form_screen.
class AppFormScaffold extends StatelessWidget {
  const AppFormScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.actionLoading = false,
  });

  final String title;
  final Widget body;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool actionLoading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ElevatedButton(
          onPressed: actionLoading ? null : onAction,
          child: actionLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Text(actionLabel),
        ),
      ),
    );
  }
}
