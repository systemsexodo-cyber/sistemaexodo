import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://febffvlpvxtiihvnfuts.supabase.co', 'sb_publishable_NVM4Zf1hN8TuW2BziNv_rg_NhU4Qsss');
  try {
    print('Logando...');
    await client.auth.signInWithPassword(email: 'user@sistemaexodo.com', password: 'ad1579036');
    print('Logado!');
  } catch(e) {}
  
  try {
    final res = await client.from('empresas').select('id, nome_exibicao');
    print('Empresas:');
    print(res);
  } catch (e) {
    print('Erro: ' + e.toString());
  }
}
