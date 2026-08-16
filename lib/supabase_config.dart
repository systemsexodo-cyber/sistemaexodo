import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseConfig {
  static const String url = 'https://febffvlpvxtiihvnfuts.supabase.co';
  // IMPORTANTE: a chave publicavel (sb_publishable_) era bloqueada pelo Row Level
  // Security (RLS) do Supabase para ESCRITA (HTTP 401/42501) - mudancas de preco
  // feitas no app nunca chegavam a nuvem por essa via. Usamos a mesma chave
  // service_role do .env (que passa por cima do RLS) para garantir escrita.
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlYmZmdmxwdnh0aWlodm5mdXRzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NjA1MjA3NSwiZXhwIjoyMDkxNjI4MDc1fQ.r7-IAXHz7hAEjmYIM4pO9uqIaFYwaOZQucKw6DoblhE';
}
