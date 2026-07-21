import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/tenant/presentation/create_tenant_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/responsive_shell.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/tenant_provider.dart';

// ── Rotas ──────────────────────────────────────────────────────────────────────
abstract class AppRoutes {
  static const splash        = '/';
  static const login         = '/login';
  static const forgotPassword = '/esqueci-senha';
  static const resetPassword = '/redefinir-senha';
  static const createTenant  = '/criar-empresa';
  static const dashboard     = '/dashboard';
}

// ── Provider do router ────────────────────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final isLoading = authAsync.isLoading;
      if (isLoading) return null; // aguarda — SplashScreen renderiza

      final isAuthenticated = ref.read(isAuthenticatedProvider);
      final hasTenant = ref.read(hasTenantProvider);

      final currentPath = state.matchedLocation;
      final publicRoutes = {
        AppRoutes.login,
        AppRoutes.forgotPassword,
        AppRoutes.resetPassword,
      };
      final isPublic = publicRoutes.contains(currentPath);

      // Não autenticado → sempre para login
      if (!isAuthenticated) {
        return isPublic ? null : AppRoutes.login;
      }

      // Autenticado mas sem tenant → criar empresa
      if (!hasTenant && currentPath != AppRoutes.createTenant) {
        return AppRoutes.createTenant;
      }

      // Autenticado com tenant → não ficar em rotas públicas nem raiz
      if (isAuthenticated && hasTenant) {
        if (isPublic || currentPath == AppRoutes.splash) {
          return AppRoutes.dashboard;
        }
      }

      return null;
    },
    refreshListenable: _GoRouterRefreshStream(ref),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, __) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.createTenant,
        builder: (_, __) => const CreateTenantScreen(),
      ),
      // Shell responsivo — rotas autenticadas
      ShellRoute(
        builder: (context, state, child) =>
            ResponsiveShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (_, __) => const DashboardScreen(),
          ),
          // Novas rotas serão adicionadas aqui nas entregas 3–8
        ],
      ),
    ],
  );
});

/// Notifica o GoRouter quando auth state ou tenant muda.
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(activeMembershipProvider, (_, __) => notifyListeners());
  }
}
