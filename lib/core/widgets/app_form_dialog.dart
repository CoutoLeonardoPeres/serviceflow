import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'neomorphic.dart';

/// Diálogo de formulário com cabeçalho e botão de fechar.
///
/// **O conteúdo NÃO rola sozinho.** A altura é limitada em 760px e o `child`
/// entra num `Flexible`, então formulário mais alto que isso estoura com
/// "BOTTOM OVERFLOWED BY N PIXELS". Formulário longo precisa se envolver em
/// `SingleChildScrollView` — veja `_SupplierForm` ou os formulários da OS.
///
/// O scroll não fica aqui de propósito: vários filhos usam `Expanded` e
/// `ListView` (calendário do dia, transferência de estoque, movimentos), que
/// quebram sob altura ilimitada.
Future<T?> showAppFormDialog<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  double maxWidth = 860,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 24,
        vertical: 20,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusContainer),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 760),
        child: NeomorphicBackdrop(
          topOrb: false,
          bottomOrb: false,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppColors.radiusContainer),
            child: NeomorphicPanel(
              borderRadius: AppColors.radiusContainer,
              color: AppColors.background,
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 22, 18, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        NeomorphicInset(
                          borderRadius: 18,
                          padding: EdgeInsets.zero,
                          child: IconButton(
                            tooltip: 'Fechar',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(AppColors.radiusContainer),
                        bottomRight: Radius.circular(AppColors.radiusContainer),
                      ),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
