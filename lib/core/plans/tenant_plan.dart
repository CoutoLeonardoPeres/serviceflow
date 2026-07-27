enum TenantFeature {
  dashboard,
  customers,
  serviceRequests,
  appointments,
  professionals,
  quotations,
  workOrders,
  stock,
  financials,
  reports,
  settings,
  payments,
  fiscal,
  promotions,
  campaigns,
  packages,
  commissions,
  ai,
  advancedBi,
  multiUnit,
}

class TenantPlanDefinition {
  const TenantPlanDefinition({
    required this.key,
    required this.label,
    required this.monthlyPriceCents,
    required this.userLimit,
    required this.unitLimit,
    required this.trialDays,
    required this.features,
    required this.description,
  });

  final String key;
  final String label;
  final int monthlyPriceCents;
  final int userLimit;
  final int unitLimit;
  final int trialDays;
  final Set<TenantFeature> features;
  final String description;

  bool hasFeature(TenantFeature feature) => features.contains(feature);
}

const starterPlan = TenantPlanDefinition(
  key: 'starter',
  label: 'Starter',
  monthlyPriceCents: 9900,
  userLimit: 3,
  unitLimit: 1,
  trialDays: 14,
  description: 'Profissional autônomo ou operação pequena.',
  features: {
    TenantFeature.dashboard,
    TenantFeature.customers,
    TenantFeature.serviceRequests,
    TenantFeature.appointments,
    TenantFeature.quotations,
    TenantFeature.workOrders,
    TenantFeature.stock,
    TenantFeature.financials,
    TenantFeature.settings,
  },
);

const professionalPlan = TenantPlanDefinition(
  key: 'professional',
  label: 'Professional',
  monthlyPriceCents: 29900,
  userLimit: 10,
  unitLimit: 2,
  trialDays: 14,
  description: 'Operação em crescimento com equipe técnica e gestão.',
  features: {
    TenantFeature.dashboard,
    TenantFeature.customers,
    TenantFeature.serviceRequests,
    TenantFeature.appointments,
    TenantFeature.professionals,
    TenantFeature.quotations,
    TenantFeature.workOrders,
    TenantFeature.stock,
    TenantFeature.financials,
    TenantFeature.reports,
    TenantFeature.settings,
    TenantFeature.packages,
    TenantFeature.commissions,
  },
);

const businessPlan = TenantPlanDefinition(
  key: 'business',
  label: 'Business',
  monthlyPriceCents: 59900,
  userLimit: 50,
  unitLimit: 10,
  trialDays: 14,
  description: 'Empresa estruturada com operação, cobrança e marketing.',
  features: {
    TenantFeature.dashboard,
    TenantFeature.customers,
    TenantFeature.serviceRequests,
    TenantFeature.appointments,
    TenantFeature.professionals,
    TenantFeature.quotations,
    TenantFeature.workOrders,
    TenantFeature.stock,
    TenantFeature.financials,
    TenantFeature.reports,
    TenantFeature.settings,
    TenantFeature.payments,
    TenantFeature.fiscal,
    TenantFeature.promotions,
    TenantFeature.campaigns,
    TenantFeature.packages,
    TenantFeature.commissions,
    TenantFeature.multiUnit,
  },
);

const enterprisePlan = TenantPlanDefinition(
  key: 'enterprise',
  label: 'Enterprise',
  monthlyPriceCents: 149900,
  userLimit: 999,
  unitLimit: 999,
  trialDays: 14,
  description: 'Redes, franquias e operações com alta complexidade.',
  features: {
    TenantFeature.dashboard,
    TenantFeature.customers,
    TenantFeature.serviceRequests,
    TenantFeature.appointments,
    TenantFeature.professionals,
    TenantFeature.quotations,
    TenantFeature.workOrders,
    TenantFeature.stock,
    TenantFeature.financials,
    TenantFeature.reports,
    TenantFeature.settings,
    TenantFeature.payments,
    TenantFeature.fiscal,
    TenantFeature.promotions,
    TenantFeature.campaigns,
    TenantFeature.packages,
    TenantFeature.commissions,
    TenantFeature.ai,
    TenantFeature.advancedBi,
    TenantFeature.multiUnit,
  },
);

const tenantPlans = <String, TenantPlanDefinition>{
  'starter': starterPlan,
  'professional': professionalPlan,
  'business': businessPlan,
  'enterprise': enterprisePlan,
};

TenantPlanDefinition resolveTenantPlan(String? key) {
  return tenantPlans[key] ?? enterprisePlan;
}

class TenantPlanSnapshot {
  const TenantPlanSnapshot({
    required this.plan,
    required this.billingStatus,
    required this.trialEndsAt,
    required this.planSelectedAt,
  });

  final TenantPlanDefinition plan;
  final String billingStatus;
  final DateTime? trialEndsAt;
  final DateTime? planSelectedAt;

  bool get isTrialing => billingStatus == 'trialing';
  bool get requiresPlanSelection => planSelectedAt == null;

  bool get isTrialExpired {
    if (!isTrialing || trialEndsAt == null) return false;
    return trialEndsAt!.isBefore(DateTime.now());
  }

  bool get hasCommercialBlock {
    return billingStatus == 'past_due' ||
        billingStatus == 'canceled' ||
        isTrialExpired;
  }
}
