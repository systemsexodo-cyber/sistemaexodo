// Verificar se certificado foi salvo no Supabase
// Execute no console do Flutter (F12 > Console)

void verificarCertificadoSupabase() async {
  final supabase = Supabase.instance.client;
  
  // Buscar empresa
  final response = await supabase
      .from('empresas')
      .select('razao_social, configuracoes')
      .limit(1);
  
  if (response.isEmpty) {
    print('❌ Nenhuma empresa encontrada');
    return;
  }
  
  final empresa = response.first;
  final configuracoes = empresa['configuracoes'] as Map<String, dynamic>?;
  
  print('Empresa: ${empresa['razao_social']}');
  print('Configurações: ${configuracoes?.keys.toList()}');
  
  // Verificar certificado
  final certBytes = configuracoes?['certificadoDigitalBytes'] as String?;
  
  if (certBytes == null) {
    print('❌ CERTIFICADO NÃO ESTÁ NO SUPABASE!');
    print('   certificadoDigitalBytes é null');
  } else {
    print('✅ CERTIFICADO ENCONTRADO NO SUPABASE');
    print('   Tamanho: ${certBytes.length} caracteres');
    print('   Primeiros 50 chars: ${certBytes.substring(0, certBytes.length > 50 ? 50 : certBytes.length)}...');
  }
}
