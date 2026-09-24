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
      borderRadius: AppColors.radiusContainer,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NeomorphicInset(
                borderRadius: AppColors.radiusBase,
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
    this.minFieldWidth = 160,
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

        final baseWidth = fieldWidth.isFinite ? fieldWidth : minFieldWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children.map((child) {
            var width = baseWidth;
            var actual = child;
            if (child is AppFormFieldSpan) {
              actual = child.child;
              final span = child.columns;
              if (span != null) {
                // Colunas inteiras precisam somar o espaçamento que ficaria
                // entre elas; `baseWidth * n` sozinho deixa o campo estreito
                // demais e o vizinho sobe de linha sem motivo.
                final n = span.clamp(1, columns);
                width = baseWidth * n + spacing * (n - 1);
              } else {
                width = baseWidth * child.widthFactor;
              }
            }
            return SizedBox(width: width, child: actual);
          }).toList(),
        );
      },
    );
  }
}

/// Marca um campo do [AppFormGrid] para ocupar uma largura diferente da
/// padrão da coluna.
///
/// [columns] ocupa esse número de colunas inteiras, somando o espaçamento
/// entre elas — use quando o campo precisa caber um rótulo ou um valor longo.
/// [widthFactor] é o ajuste fino proporcional (1.3 = 30% mais largo); quando
/// [columns] é informado, ele vence.
class AppFormFieldSpan extends StatelessWidget {
  const AppFormFieldSpan({
    super.key,
    required this.child,
    this.widthFactor = 1.0,
    this.columns,
  });

  final Widget child;
  final double widthFactor;
  final int? columns;

  @override
  Widget build(BuildContext context) => child;
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
