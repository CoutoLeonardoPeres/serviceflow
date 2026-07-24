import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../customers/application/customer_list_notifier.dart';
import '../../customers/domain/customer.dart';

class PromotionsScreen extends ConsumerStatefulWidget {
  const PromotionsScreen({super.key});

  @override
  ConsumerState<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends ConsumerState<PromotionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(customerListProvider.notifier);
      if (ref.read(customerListProvider).items.isEmpty) {
        notifier.load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerListProvider);
    final customers = state.items;
    final activeCustomers = customers.where((item) => item.isActive).toList();
    final companyCustomers = activeCustomers
        .where((item) => item.type == CustomerType.company)
        .length;
    final personCustomers = activeCustomers
        .where((item) => item.type == CustomerType.person)
        .length;
    final condominiumCustomers = activeCustomers
        .where((item) => item.type == CustomerType.condominium)
        .length;

    final promotionCards = [
      _PromotionCardData(
        title: 'Reativação da carteira',
        subtitle: 'Clientes sem recorrência recente',
        highlight:
            '${(activeCustomers.length * 0.18).round()} clientes estimados',
        description:
            'Condição focada em recuperar clientes parados com benefício temporário e contato ativo.',
        chips: const [
          'WhatsApp',
          'Desconto limitado',
          'Orçamento rápido',
        ],
        icon: Icons.refresh_rounded,
      ),
      _PromotionCardData(
        title: 'Combo residencial',
        subtitle: 'Pessoa física e atendimento preventivo',
        highlight: '$personCustomers clientes no perfil principal',
        description:
            'Monte ofertas com visita técnica, mão de obra e materiais básicos em um pacote simples de fechar.',
        chips: const [
          'Pessoa física',
          'Ticket médio',
          'Pacote',
        ],
        icon: Icons.home_repair_service_outlined,
      ),
      _PromotionCardData(
        title: 'Contrato corporativo',
        subtitle: 'Empresa, condomínio e operação recorrente',
        highlight:
            '${companyCustomers + condominiumCustomers} contas com perfil B2B',
        description:
            'Direcione propostas de manutenção mensal, atendimento prioritário e SLA por unidade.',
        chips: const [
          'Empresas',
          'Condomínios',
          'SLA',
        ],
        icon: Icons.apartment_outlined,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Promoções'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => ref.read(customerListProvider.notifier).refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(customerListProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            NeomorphicPanel(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ofertas e ativação comercial',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use este módulo para organizar promoções por público, janela comercial e objetivo. A base já lê a carteira atual para ajudar na priorização.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 16),
                  const Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      NeomorphicBadge(
                        icon: Icons.local_offer_outlined,
                        label: 'Ofertas com vigência',
                      ),
                      NeomorphicBadge(
                        icon: Icons.groups_outlined,
                        label: 'Público-alvo por carteira',
                      ),
                      NeomorphicBadge(
                        icon: Icons.campaign_outlined,
                        label: 'Pronto para campanhas',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.isLoading && customers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 96),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null && customers.isEmpty)
              ErrorView(
                message: state.error?.userMessage ??
                    'Erro ao carregar base comercial.',
                onRetry: () =>
                    ref.read(customerListProvider.notifier).refresh(),
              )
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _PromotionSummaryTile(
                    icon: Icons.people_outline,
                    label: 'Clientes ativos',
                    value: activeCustomers.length.toString(),
                  ),
                  _PromotionSummaryTile(
                    icon: Icons.business_outlined,
                    label: 'Empresas',
                    value: companyCustomers.toString(),
                  ),
                  _PromotionSummaryTile(
                    icon: Icons.person_outline,
                    label: 'Pessoa física',
                    value: personCustomers.toString(),
                  ),
                  _PromotionSummaryTile(
                    icon: Icons.domain_add_outlined,
                    label: 'Condomínios',
                    value: condominiumCustomers.toString(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Modelos sugeridos para ativação',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 1200;
                  final isMedium = constraints.maxWidth >= 760;
                  final cardWidth = isWide
                      ? (constraints.maxWidth - 24) / 3
                      : isMedium
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: promotionCards
                        .map(
                          (item) => SizedBox(
                            width: cardWidth,
                            child: _PromotionCard(data: item),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 18),
              NeomorphicPanel(
                borderRadius: 24,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Próximo encaixe deste módulo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'A próxima evolução natural daqui é conectar cada promoção aos módulos de campanhas, orçamentos e pacotes para medir conversão real por oferta.',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromotionSummaryTile extends StatelessWidget {
  const _PromotionSummaryTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: NeomorphicInset(
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromotionCardData {
  const _PromotionCardData({
    required this.title,
    required this.subtitle,
    required this.highlight,
    required this.description,
    required this.chips,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String highlight;
  final String description;
  final List<String> chips;
  final IconData icon;
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({required this.data});

  final _PromotionCardData data;

  @override
  Widget build(BuildContext context) {
    return NeomorphicPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NeomorphicInset(
                borderRadius: 18,
                padding: const EdgeInsets.all(12),
                child: Icon(
                  data.icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(data.subtitle),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            data.highlight,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            data.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: data.chips
                .map(
                  (chip) => NeomorphicBadge(
                    icon: Icons.check_circle_outline,
                    label: chip,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
