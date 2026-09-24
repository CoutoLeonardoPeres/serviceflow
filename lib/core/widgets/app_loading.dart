import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'neomorphic.dart';

/// Indicador de carregamento centralizado.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: NeomorphicPanel(
        borderRadius: AppColors.radiusContainer,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.8,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkMuted,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tela de splash/loading para navegação inicial.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NeomorphicBackdrop(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: NeomorphicPanel(
              borderRadius: AppColors.radiusContainer,
              color: AppColors.background,
              padding: const EdgeInsets.fromLTRB(40, 34, 40, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primaryLight,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusContainer),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.electricViolet.withValues(alpha: 0.28),
                          offset: const Offset(12, 16),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.electrical_services_rounded,
                      size: 42,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'ServiceFlow',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Preparando sua operação de serviços',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                    child: LinearProgressIndicator(minHeight: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
