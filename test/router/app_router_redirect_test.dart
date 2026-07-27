import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/plans/tenant_plan.dart';
import 'package:serviceflow/core/router/app_router.dart';

void main() {
  group('appRedirectTarget', () {
    test('envia usuario autenticado com empresa ativa do login para dashboard',
        () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.login,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, AppRoutes.dashboard);
    });

    test('mantem usuario autenticado sem empresa na tela de criar empresa', () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: false,
        currentPath: AppRoutes.dashboard,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, AppRoutes.createTenant);
    });

    test(
        'envia usuario com empresa ativa da tela de criar empresa para dashboard',
        () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.createTenant,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, AppRoutes.dashboard);
    });

    test('mantem link publico de orcamento aberto mesmo com usuario logado',
        () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.quotationPublic('token-123'),
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, isNull);
    });

    test('mantem pesquisa publica aberta para visitante sem autenticacao', () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: false,
        hasTenant: false,
        currentPath: AppRoutes.satisfactionPublic('token-abc'),
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, isNull);
    });

    test('mantem pesquisa publica aberta mesmo com plano bloqueado', () {
      // O cliente final nao pode ser barrado pela situacao comercial do tenant.
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.satisfactionPublic('token-abc'),
        planFeatures: enterprisePlan.features,
        isPlanBlocked: true,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, isNull);
    });

    test(
        'mantem rota de aceite de convite aberta para usuario sem autenticacao',
        () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: false,
        hasTenant: false,
        currentPath: AppRoutes.acceptInvitation,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, isNull);
    });

    test(
        'mantem rota de aceite de convite para usuario autenticado sem empresa durante onboarding',
        () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: false,
        currentPath: AppRoutes.acceptInvitation,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, isNull);
    });

    test('redireciona quando rota nao faz parte do plano atual', () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.reports,
        planFeatures: starterPlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, AppRoutes.dashboard);
    });

    test('redireciona tenant bloqueado para a tela de assinatura', () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.dashboard,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: true,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, AppRoutes.subscription);
    });

    test('permite abrir configuracoes quando tenant estiver bloqueado', () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.settings,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: true,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, isNull);
    });

    test('mantem link publico de orcamento aberto mesmo com bloqueio', () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.quotationPublic('token-123'),
        planFeatures: enterprisePlan.features,
        isPlanBlocked: true,
        requiresPlanSelection: false,
        hasOnboardingBypass: false,
      );

      expect(target, isNull);
    });

    test('redireciona owner para onboarding de plano apos criar empresa', () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.dashboard,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: true,
        hasOnboardingBypass: false,
      );

      expect(target, AppRoutes.planOnboarding);
    });

    test('mantem tela de onboarding de plano quando selecao ainda nao ocorreu',
        () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.planOnboarding,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: true,
        hasOnboardingBypass: false,
      );

      expect(target, isNull);
    });

    test('permite entrar no sistema quando houver bypass de onboarding', () {
      final target = appRedirectTarget(
        isAuthLoading: false,
        isMembershipLoading: false,
        isAuthenticated: true,
        hasTenant: true,
        currentPath: AppRoutes.dashboard,
        planFeatures: enterprisePlan.features,
        isPlanBlocked: false,
        requiresPlanSelection: true,
        hasOnboardingBypass: true,
      );

      expect(target, isNull);
    });
  });
}
