import '../config/env_config.dart';

class PlanCheckoutLink {
  const PlanCheckoutLink({
    required this.externalUri,
    required this.returnUri,
    required this.checkoutSessionId,
  });

  final Uri externalUri;
  final Uri returnUri;
  final String checkoutSessionId;
}

Uri buildAppHashReturnUri(
  String route, {
  Map<String, String>? queryParameters,
}) {
  final base = Uri.base.removeFragment();
  final path = route.startsWith('/') ? route : '/$route';
  final query = queryParameters == null || queryParameters.isEmpty
      ? ''
      : '?${Uri(queryParameters: queryParameters).query}';
  return base.replace(fragment: '$path$query');
}

PlanCheckoutLink? buildPlanCheckoutLink({
  required String planKey,
  required String checkoutSessionId,
  String? tenantSlug,
  required String source,
}) {
  final template = EnvConfig.checkoutUrlForPlan(planKey);
  if (template == null) return null;

  final returnUri = buildAppHashReturnUri(
    '/assinatura',
    queryParameters: {
      'checkout': 'success',
      'plan': planKey,
      'source': source,
      'checkout_ref': checkoutSessionId,
    },
  );

  final encodedReturn = Uri.encodeComponent(returnUri.toString());
  final encodedTenant = Uri.encodeComponent(tenantSlug ?? '');
  final encodedPlan = Uri.encodeComponent(planKey);
  final encodedSource = Uri.encodeComponent(source);
  final encodedCheckout = Uri.encodeComponent(checkoutSessionId);

  final resolved = template
      .replaceAll('{RETURN_URL}', encodedReturn)
      .replaceAll('{TENANT_SLUG}', encodedTenant)
      .replaceAll('{PLAN_KEY}', encodedPlan)
      .replaceAll('{SOURCE}', encodedSource)
      .replaceAll('{CHECKOUT_SESSION_ID}', encodedCheckout);

  var uri = Uri.parse(resolved);
  if (!template.contains('{RETURN_URL}') ||
      !template.contains('{TENANT_SLUG}') ||
      !template.contains('{PLAN_KEY}') ||
      !template.contains('{SOURCE}') ||
      !template.contains('{CHECKOUT_SESSION_ID}')) {
    uri = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'return_url': returnUri.toString(),
        'tenant': tenantSlug ?? '',
        'plan': planKey,
        'source': source,
        'checkout_session_id': checkoutSessionId,
      },
    );
  }

  return PlanCheckoutLink(
    externalUri: uri,
    returnUri: returnUri,
    checkoutSessionId: checkoutSessionId,
  );
}

Uri? buildBillingPortalUri({String? tenantSlug, required String source}) {
  final template = EnvConfig.billingPortalUrl;
  if (template == null) return null;

  final returnUri = buildAppHashReturnUri(
    '/assinatura',
    queryParameters: {'portal': 'return', 'source': source},
  );

  final resolved = template
      .replaceAll('{RETURN_URL}', Uri.encodeComponent(returnUri.toString()))
      .replaceAll('{TENANT_SLUG}', Uri.encodeComponent(tenantSlug ?? ''))
      .replaceAll('{SOURCE}', Uri.encodeComponent(source));

  var uri = Uri.parse(resolved);
  if (!template.contains('{RETURN_URL}') ||
      !template.contains('{TENANT_SLUG}') ||
      !template.contains('{SOURCE}')) {
    uri = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'return_url': returnUri.toString(),
        'tenant': tenantSlug ?? '',
        'source': source,
      },
    );
  }
  return uri;
}
