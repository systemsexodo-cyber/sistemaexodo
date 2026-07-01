import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://febffvlpvxtiihvnfuts.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZlYmZmdmxwdnh0aWlodm5mdXRzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NjA1MjA3NSwiZXhwIjoyMDkxNjI4MDc1fQ.r7-IAXHz7hAEjmYIM4pO9uqIaFYwaOZQucKw6DoblhE');
  try {
    print('Logando...');
    await client.auth.signInWithPassword(email: 'user@sistemaexodo.com', password: 'ad1579036');
    print('Logado!');
  } catch(e) {}
  
  try {
    final res = await client.from('empresas').select('id, razao_social, nome_fantasia, slug');
    print('Empresas:');
    print(res);
  } catch (e) {
    print('Erro: ' + e.toString());
  }
}
