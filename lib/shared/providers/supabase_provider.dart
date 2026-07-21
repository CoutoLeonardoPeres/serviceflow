import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cliente Supabase singleton.
/// Inicializado em main.dart antes de runApp.
/// Nunca expõe service_role key — usa apenas anon key.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
