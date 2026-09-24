import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../plans/tenant_plan.dart';
import 'onboarding_access_override_stub.dart'
    if (dart.library.html) 'onboarding_access_override_web.dart';

import '../../features/marketing/presentation/public_plans_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/invitation_accept_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/tenant/presentation/create_tenant_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/customers/domain/customer.dart';
import '../../features/customers/presentation/customer_list_screen.dart';
import '../../features/customers/presentation/customer_detail_screen.dart';
import '../../features/customers/presentation/customer_form_screen.dart';
import '../../features/service_requests/presentation/service_category_screen.dart';
import '../../features/service_requests/presentation/service_priority_screen.dart';
import '../../features/service_requests/presentation/service_request_detail_screen.dart';
import '../../features/service_requests/presentation/service_request_form_screen.dart';
import '../../features/service_requests/presentation/service_request_list_screen.dart';
import '../../features/scheduling/presentation/appointment_detail_screen.dart';
import '../../features/scheduling/presentation/appointment_form_screen.dart';
import '../../features/scheduling/presentation/appointment_list_screen.dart';
import '../../features/professionals/presentation/service_professional_list_screen.dart';
import '../../features/quotations/presentation/quotation_detail_screen.dart';
import '../../features/quotations/presentation/quotation_form_screen.dart';
import '../../features/quotations/presentation/quotation_list_screen.dart';
import '../../features/quotations/presentation/quotation_public_screen.dart';
import '../../features/purchases/presentation/purchase_order_detail_screen.dart';
import '../../features/purchases/presentation/purchase_order_form_screen.dart';
import '../../features/purchases/presentation/purchase_order_list_screen.dart';
import '../../features/purchases/presentation/supplier_list_screen.dart';
import '../../features/stock/domain/stock_balance.dart';
import '../../features/stock/presentation/product_list_screen.dart';
import '../../features/stock/presentation/stock_count_screen.dart';
import '../../features/stock/presentation/stock_list_screen.dart';
import '../../features/stock/presentation/stock_movements_screen.dart';
import '../../features/stock/presentation/stock_transfer_screen.dart';
import '../../features/work_orders/presentation/satisfaction_public_screen.dart';
import '../../features/work_orders/presentation/work_order_detail_screen.dart';
import '../../features/work_orders/presentation/work_order_form_screen.dart';
import '../../features/work_orders/presentation/work_order_list_screen.dart';
import '../../features/financials/presentation/dre_screen.dart';
import '../../features/financials/presentation/financial_list_screen.dart';
import '../../features/financials/presentation/payables_screen.dart';
import '../../features/financials/presentation/payments_screen.dart';
import '../../features/financials/presentation/fiscal_screen.dart';
import '../../features/promotions/presentation/promotions_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/modules/presentation/module_placeholder_screen.dart';
import '../../features/communications/presentation/message_template_screen.dart';
import '../../features/settings/presentation/audit_log_screen.dart';
import '../../features/settings/presentation/plan_onboarding_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/subscription_gate_screen.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/responsive_shell.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/tenant_provider.dart';

// ── Rotas ──────────────────────────────────────────────────────────────────────
abstract class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const acceptInvitation = '/aceitar-convite';
  static const forgotPassword = '/esqueci-senha';
  static const resetPassword = '/redefinir-senha';
  static const createTenant = '/criar-empresa';
  static const dashboard = '/dashboard';

  // Clientes (E3)
  static const customers = '/clientes';
  static const customerNew = '/clientes/novo';
  static String customerDetail(String id) => '/clientes/$id';
  static String customerEdit(String id) => '/clientes/$id/editar';

  // Chamados (E4)
  static const serviceRequests = '/chamados';
  static const serviceRequestNew = '/chamados/novo';
  static String serviceRequestDetail(String id) => '/chamados/$id';

  // Agenda (E5)
  static const appointments = '/agenda';
  static const appointmentNew = '/agenda/novo';
  static String appointmentDetail(String id) => '/agenda/$id';

  // Profissionais (F2)
  static const professionals = '/profissionais';

  // Orçamentos (E6)
  static const quotations = '/orcamentos';
  static const quotationNew = '/orcamentos/novo';
  static String quotationDetail(String id) => '/orcamentos/$id';
  static String quotationPublic(String token) => '/orcamento-publico/$token';

  // Ordens de serviço (E7)
  static const workOrders = '/ordens-servico';
  static const workOrderNew = '/ordens-servico/novo';
  static String workOrderDetail(String id) => '/ordens-servico/$id';
  static String satisfactionPublic(String token) => '/pesquisa/$token';

  // Estoque (F3-P1)
  static const stock = '/estoque';
  static const products = '/estoque/produtos';
  static String stockMovements(String productId) =>
      '/estoque/movimentos/$productId';
  static const stockTransfers = '/estoque/transferencias';
  static const stockCounts = '/estoque/inventario';

  // Compras (F3-P3)
  static const purchases = '/compras';
  static const purchaseOrderNew = '/compras/novo';
  static const suppliers = '/compras/fornecedores';
  static String purchaseOrderDetail(String id) => '/compras/pedido/$id';

  // Financeiro (E8)
  static const financials = '/financeiro';
  static const payables = '/financeiro/pagar';
  static const dre = '/financeiro/dre';
  static const payments = '/pagamentos';
  static const fiscal = '/fiscal';
  static const promotions = '/promocoes';
  static const campaigns = '/campanhas';
  static const advancedBi = '/bi-avancado';
  static const ai = '/ia';

  // Relatórios (F2)
  static const reports = '/relatorios';

  // Configurações
  static const settings = '/configuracoes';
  static const auditLog = '/configuracoes/auditoria';
  static const messageTemplates = '/configuracoes/templates-mensagem';
  static const serviceCategories = '/configuracoes/categorias-chamado';
  static const servicePriorities = '/configuracoes/prioridades-chamado';
  static const subscription = '/assinatura';
  static const planOnboarding = '/onboarding-plano';
}

String? appRedirectTarget({
  required bool isAuthLoading,
  required bool isMembershipLoading,
  required bool isAuthenticated,
  required bool hasTenant,
  required String currentPath,
  required Set<TenantFeature> planFeatures,
  required bool isPlanBlocked,
  required bool requiresPlanSelection,
  required bool hasOnboardingBypass,
}) {
  if (isAuthLoading) return null;

  final publicRoutes = {
    AppRoutes.splash,
    AppRoutes.login,
    AppRoutes.acceptInvitation,
    AppRoutes.forgotPassword,
    AppRoutes.resetPassword,
  };
  final isPublic = publicRoutes.contains(currentPath) ||
      currentPath.startsWith('/orcamento-publico/') ||
      currentPath.startsWith('/pesquisa/');
  final isAuthPublicRoute = publicRoutes.contains(currentPath);

  if (!isAuthenticated) {
    return isPublic ? null : AppRoutes.login;
  }

  if (isMembershipLoading) return null;

  // O link de recuperação cria uma sessão temporária no Supabase. A rota de
  // redefinição precisa permanecer aberta até que o usuário salve a nova
  // senha, mesmo quando ele já possui uma empresa ativa.
  if (currentPath == AppRoutes.resetPassword) return null;

  if (!hasTenant &&
      currentPath != AppRoutes.createTenant &&
      currentPath != AppRoutes.acceptInvitation) {
    return AppRoutes.createTenant;
  }

  if (hasTenant &&
      requiresPlanSelection &&
      !hasOnboardingBypass &&
      currentPath != AppRoutes.planOnboarding) {
    return AppRoutes.planOnboarding;
  }

  if (hasTenant &&
      (isAuthPublicRoute ||
          currentPath == AppRoutes.splash ||
          currentPath == AppRoutes.createTenant)) {
    return AppRoutes.dashboard;
  }

  if (hasTenant &&
      isPlanBlocked &&
      currentPath != AppRoutes.subscription &&
      currentPath != AppRoutes.settings &&
      !currentPath.startsWith('/orcamento-publico/') &&
      !currentPath.startsWith('/pesquisa/')) {
    return AppRoutes.subscription;
  }

  final requiredFeature = featureForRoute(currentPath);
  if (hasTenant &&
      requiredFeature != null &&
      !planFeatures.contains(requiredFeature)) {
    return AppRoutes.dashboard;
  }

  return null;
}

TenantFeature? featureForRoute(String currentPath) {
  if (currentPath.startsWith(AppRoutes.customers)) {
    return TenantFeature.customers;
  }
  if (currentPath.startsWith(AppRoutes.serviceRequests)) {
    return TenantFeature.serviceRequests;
  }
  if (currentPath.startsWith(AppRoutes.appointments)) {
    return TenantFeature.appointments;
  }
  if (currentPath.startsWith(AppRoutes.professionals)) {
    return TenantFeature.professionals;
  }
  if (currentPath.startsWith(AppRoutes.quotations)) {
    return TenantFeature.quotations;
  }
  if (currentPath.startsWith(AppRoutes.workOrders)) {
    return TenantFeature.workOrders;
  }
  if (currentPath.startsWith(AppRoutes.stock)) {
    return TenantFeature.stock;
  }
  // Compras faz parte do módulo de estoque para efeito de plano — separar as
  // duas travas criaria o caso absurdo de comprar sem poder ver o saldo.
  if (currentPath.startsWith(AppRoutes.purchases)) {
    return TenantFeature.stock;
  }
  if (currentPath.startsWith(AppRoutes.financials)) {
    return TenantFeature.financials;
  }
  if (currentPath.startsWith(AppRoutes.payments)) {
    return TenantFeature.payments;
  }
  if (currentPath.startsWith(AppRoutes.fiscal)) {
    return TenantFeature.fiscal;
  }
  if (currentPath.startsWith(AppRoutes.promotions)) {
    return TenantFeature.promotions;
  }
  if (currentPath.startsWith(AppRoutes.campaigns)) {
    return TenantFeature.campaigns;
  }
  if (currentPath.startsWith(AppRoutes.advancedBi)) {
    return TenantFeature.advancedBi;
  }
  if (currentPath.startsWith(AppRoutes.ai)) {
    return TenantFeature.ai;
  }
  if (currentPath.startsWith(AppRoutes.reports)) {
    return TenantFeature.reports;
  }
  if (currentPath.startsWith(AppRoutes.settings)) {
    return TenantFeature.settings;
  }
  return null;
}

/// Tela raiz ('/'). Visitante não autenticado vê a vitrine pública de
/// planos; autenticado vê o splash por um instante até o redirect (acima)
/// mandar pro dashboard.
class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);
    if (authAsync.isLoading) return const SplashScreen();
    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    return isAuthenticated ? const SplashScreen() : const PublicPlansScreen();
  }
}

// ── Provider do router ────────────────────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      final membershipAsync = ref.read(activeMembershipProvider);
      final isAuthenticated = ref.read(isAuthenticatedProvider);
      final hasTenant = ref.read(hasTenantProvider);
      final planFeatures = ref.read(currentPlanFeatureSetProvider);
      final isPlanBlocked = ref.read(isPlanAccessBlockedProvider);
      final requiresPlanSelection =
          ref.read(requiresInitialPlanSelectionProvider);
      return appRedirectTarget(
        isAuthLoading: authAsync.isLoading,
        isMembershipLoading: isAuthenticated && membershipAsync.isLoading,
        isAuthenticated: isAuthenticated,
        hasTenant: hasTenant,
        currentPath: state.matchedLocation,
        planFeatures: planFeatures,
        isPlanBlocked: isPlanBlocked,
        requiresPlanSelection: requiresPlanSelection,
        hasOnboardingBypass: hasOnboardingAccessOverride(),
      );
    },
    refreshListenable: _GoRouterRefreshStream(ref),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const RootScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, state) => LoginScreen(
          inviteToken: state.uri.queryParameters['invite'],
          tenantSlug: state.uri.queryParameters['tenant'],
        ),
      ),
      GoRoute(
        path: AppRoutes.acceptInvitation,
        builder: (_, state) => InvitationAcceptScreen(
          inviteToken: state.uri.queryParameters['invite'] ?? '',
        ),
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
        path: '/orcamento-publico/:token',
        builder: (_, state) => QuotationPublicScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      GoRoute(
        path: '/pesquisa/:token',
        builder: (_, state) => SatisfactionPublicScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.createTenant,
        builder: (_, __) => const CreateTenantScreen(),
      ),
      GoRoute(
        path: AppRoutes.subscription,
        builder: (_, __) => const SubscriptionGateScreen(),
      ),
      GoRoute(
        path: AppRoutes.planOnboarding,
        builder: (_, __) => const PlanOnboardingScreen(),
      ),
      // Shell responsivo — rotas autenticadas
      ShellRoute(
        builder: (context, state, child) => ResponsiveShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (_, __) => const DashboardScreen(),
          ),

          // ── Clientes (E3) ────────────────────────────────────────────
          GoRoute(
            path: AppRoutes.customers,
            builder: (_, __) => const CustomerListScreen(),
          ),
          GoRoute(
            path: AppRoutes.customerNew,
            builder: (_, __) => const CustomerFormScreen(),
          ),
          GoRoute(
            path: '/clientes/:id',
            builder: (_, state) => CustomerDetailScreen(
              customerId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/clientes/:id/editar',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              // Customer passado via extra (de CustomerDetailScreen.handleAction)
              final extra = state.extra;
              if (extra is Customer) {
                return CustomerFormScreen(customer: extra);
              }
              // Fallback sem extra: tela de detalhe navega de volta
              return CustomerDetailScreen(customerId: id);
            },
          ),

          // ── Chamados (E4) ───────────────────────────────────────────
          GoRoute(
            path: AppRoutes.serviceRequests,
            builder: (_, __) => const ServiceRequestListScreen(),
          ),
          GoRoute(
            path: AppRoutes.serviceRequestNew,
            builder: (_, __) => const ServiceRequestFormScreen(),
          ),
          GoRoute(
            path: '/chamados/:id',
            builder: (_, state) => ServiceRequestDetailScreen(
              requestId: state.pathParameters['id']!,
            ),
          ),

          // ── Agenda (E5) ─────────────────────────────────────────────
          GoRoute(
            path: AppRoutes.appointments,
            builder: (_, __) => const AppointmentListScreen(),
          ),
          GoRoute(
            path: AppRoutes.professionals,
            builder: (_, __) => const ServiceProfessionalListScreen(),
          ),
          GoRoute(
            path: AppRoutes.appointmentNew,
            builder: (_, __) => const AppointmentFormScreen(),
          ),
          GoRoute(
            path: '/agenda/:id',
            builder: (_, state) => AppointmentDetailScreen(
              appointmentId: state.pathParameters['id']!,
            ),
          ),

          // ── Orçamentos (E6) ─────────────────────────────────────────
          GoRoute(
            path: AppRoutes.quotations,
            builder: (_, __) => const QuotationListScreen(),
          ),
          GoRoute(
            path: AppRoutes.quotationNew,
            // ?chamado=<id> vem da agenda, ao transformar uma visita técnica
            // em orçamento.
            builder: (_, state) => QuotationFormScreen(
              initialRequestId: state.uri.queryParameters['chamado'],
            ),
          ),
          GoRoute(
            path: '/orcamentos/:id',
            builder: (_, state) => QuotationDetailScreen(
              quotationId: state.pathParameters['id']!,
            ),
          ),

          // ── Ordens de serviço (E7) ─────────────────────────────────
          GoRoute(
            path: AppRoutes.workOrders,
            builder: (_, __) => const WorkOrderListScreen(),
          ),
          GoRoute(
            path: AppRoutes.workOrderNew,
            builder: (_, __) => const WorkOrderFormScreen(),
          ),
          GoRoute(
            path: '/ordens-servico/:id',
            builder: (_, state) => WorkOrderDetailScreen(
              workOrderId: state.pathParameters['id']!,
            ),
          ),

          // ── Estoque (F3-P1) ────────────────────────────────────────
          GoRoute(
            path: AppRoutes.stock,
            builder: (_, __) => const StockListScreen(),
          ),
          GoRoute(
            path: AppRoutes.products,
            builder: (_, __) => const ProductListScreen(),
          ),
          GoRoute(
            path: '/estoque/movimentos/:productId',
            builder: (_, state) => StockMovementsScreen(
              productId: state.pathParameters['productId']!,
              // Vem da lista de saldos para evitar consulta extra; quando a URL
              // é aberta direto, a tela funciona sem o cabeçalho.
              balance: state.extra is StockBalance
                  ? state.extra! as StockBalance
                  : null,
            ),
          ),

          GoRoute(
            path: AppRoutes.stockTransfers,
            builder: (_, __) => const StockTransferScreen(),
          ),
          GoRoute(
            path: AppRoutes.stockCounts,
            builder: (_, __) => const StockCountListScreen(),
          ),

          // ── Compras (F3-P3) ────────────────────────────────────────
          GoRoute(
            path: AppRoutes.purchases,
            builder: (_, __) => const PurchaseOrderListScreen(),
          ),
          GoRoute(
            path: AppRoutes.purchaseOrderNew,
            builder: (_, __) => const PurchaseOrderFormScreen(),
          ),
          GoRoute(
            path: AppRoutes.suppliers,
            builder: (_, __) => const SupplierListScreen(),
          ),
          GoRoute(
            path: '/compras/pedido/:id',
            builder: (_, state) => PurchaseOrderDetailScreen(
              orderId: state.pathParameters['id']!,
            ),
          ),

          // ── Financeiro (E8) ───────────────────────────────────────
          GoRoute(
            path: AppRoutes.financials,
            builder: (_, __) => const FinancialListScreen(),
          ),
          GoRoute(
            path: AppRoutes.payables,
            builder: (_, __) => const PayablesScreen(),
          ),
          GoRoute(
            path: AppRoutes.dre,
            builder: (_, __) => const DreScreen(),
          ),
          GoRoute(
            path: AppRoutes.payments,
            builder: (_, __) => const PaymentsScreen(),
          ),
          GoRoute(
            path: AppRoutes.fiscal,
            builder: (_, __) => const FiscalScreen(),
          ),
          GoRoute(
            path: AppRoutes.promotions,
            builder: (_, __) => const PromotionsScreen(),
          ),
          GoRoute(
            path: AppRoutes.campaigns,
            builder: (_, __) => const ModulePlaceholderScreen(
              title: 'Campanhas',
              subtitle: 'Planejamento de ações comerciais recorrentes.',
              icon: Icons.campaign_outlined,
              summary:
                  'A área de campanhas vai concentrar comunicação ativa, recuperação de clientes e estímulo de novas vendas por segmento.',
              highlights: [
                'Estrutura inicial habilitada para tenants Business e Enterprise.',
                'Base navegável preparada para histórico e calendário de campanhas.',
                'Consistência visual com os demais módulos operacionais.',
              ],
              nextSteps: [
                'Criar campanhas por objetivo, canal e público.',
                'Registrar disparos, respostas e conversões.',
                'Conectar templates e trilha de comunicação.',
              ],
            ),
          ),
          GoRoute(
            path: AppRoutes.advancedBi,
            builder: (_, __) => const ModulePlaceholderScreen(
              title: 'BI avançado',
              subtitle: 'Indicadores executivos para escala operacional.',
              icon: Icons.insights_outlined,
              summary:
                  'Este módulo evolui os relatórios atuais para análises comparativas, funis, metas, eficiência operacional e visão multiunidade.',
              highlights: [
                'Módulo reservado para plano Enterprise.',
                'Entrada já visível e protegida por feature flag do plano.',
                'Base pronta para painéis analíticos mais densos.',
              ],
              nextSteps: [
                'Adicionar comparativos mensais e metas.',
                'Abrir visões por unidade, técnico e categoria.',
                'Criar dashboards executivos com filtros persistentes.',
              ],
            ),
          ),
          GoRoute(
            path: AppRoutes.ai,
            builder: (_, __) => const ModulePlaceholderScreen(
              title: 'IA',
              subtitle:
                  'Assistência operacional para triagem, execução e gestão.',
              icon: Icons.auto_awesome_outlined,
              summary:
                  'A área de IA concentrará apoio inteligente para priorização, composição de orçamento, análise de rota, resumo de histórico e recomendações operacionais.',
              highlights: [
                'Módulo reservado para plano Enterprise.',
                'Espaço preparado para automações e assistentes contextuais.',
                'Coerência com a evolução planejada do produto.',
              ],
              nextSteps: [
                'Gerar resumos automáticos de chamados e OS.',
                'Sugerir composição de materiais e HH por serviço.',
                'Apoiar priorização, roteiro e follow-up comercial.',
              ],
            ),
          ),

          // ── Relatórios (F2) ───────────────────────────────────────
          GoRoute(
            path: AppRoutes.reports,
            builder: (_, __) => const ReportsScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (_, __) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'auditoria',
                builder: (_, __) => const AuditLogScreen(),
              ),
              GoRoute(
                path: 'templates-mensagem',
                builder: (_, __) => const MessageTemplateScreen(),
              ),
              GoRoute(
                path: 'categorias-chamado',
                builder: (_, __) => const ServiceCategoryScreen(),
              ),
              GoRoute(
                path: 'prioridades-chamado',
                builder: (_, __) => const ServicePriorityScreen(),
              ),
            ],
          ),
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
