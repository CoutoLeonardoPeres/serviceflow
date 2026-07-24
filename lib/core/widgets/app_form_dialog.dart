import 'package:flutter/material.dart';

import 'neomorphic.dart';

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
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(34),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 760),
        child: NeomorphicBackdrop(
          topOrb: false,
          bottomOrb: false,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: NeomorphicPanel(
              borderRadius: 34,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF4F7FC),
                  Color(0xFFEEF3F9),
                ],
              ),
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
                        bottomLeft: Radius.circular(34),
                        bottomRight: Radius.circular(34),
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
