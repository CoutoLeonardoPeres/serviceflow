import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../data/platform_admin_repository.dart';
import '../domain/platform_tenant.dart';

final platformAdminRepositoryProvider = Provider<PlatformAdminRepository>(
  (ref) => PlatformAdminRepository(ref.read(supabaseClientProvider)),
);

final isPlatformAdminProvider = FutureProvider.autoDispose<bool>((ref) async {
  return ref.read(platformAdminRepositoryProvider).isPlatformAdmin();
});

final platformTenantsProvider =
    FutureProvider.autoDispose<List<PlatformTenant>>((ref) async {
  ref.watch(isPlatformAdminProvider);
  return ref.read(platformAdminRepositoryProvider).listTenants();
});
