import 'package:supabase/supabase.dart';
import 'package:http/http.dart' as http;

void main() async {
  final client = SupabaseClient('https://febffvlpvxtiihvnfuts.supabase.co', 'sb_publishable_NVM4Zf1hN8TuW2BziNv_rg_NhU4Qsss');
  
  try {
    print('Tentando login com hmrzbdKJB6Bc4Vcr...');
    await client.auth.signInWithPassword(email: 'user@sistemaexodo.com', password: 'hmrzbdKJB6Bc4Vcr');
    print('Logado!');
  } catch (e) {
    print('Erro 1: \');
    try {
      print('Tentando login com ad1579036...');
      await client.auth.signInWithPassword(email: 'user@sistemaexodo.com', password: 'ad1579036');
      print('Logado!');
    } catch (e2) {
      print('Erro 2: \');
    }
  }
  
  try {
    final res = await client.from('empresas').select();
    print('Empresas no Supabase:');
    print(res);
  } catch (e) {
    print('Erro ao buscar empresas: \');
  }
}
