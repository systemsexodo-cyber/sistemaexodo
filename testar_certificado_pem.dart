import 'dart:io';
import 'dart:convert';

void main(List<String> args) async {
  print('========================================');
  print('  TESTE DE CERTIFICADO PEM');
  print('========================================');
  print('');
  
  String? caminhoPEM;
  
  if (args.isNotEmpty) {
    caminhoPEM = args[0];
  } else {
    print('Uso: dart testar_certificado_pem.dart "CAMINHO_DO_ARQUIVO.pem"');
    print('');
    print('Exemplo:');
    print('  dart testar_certificado_pem.dart "C:\\Users\\USER\\certificado.pem"');
    exit(1);
  }
  
  if (caminhoPEM == null || caminhoPEM.isEmpty) {
    print('ERRO: Caminho não fornecido');
    exit(1);
  }
  
  final file = File(caminhoPEM);
  if (!await file.exists()) {
    print('ERRO: Arquivo não encontrado: $caminhoPEM');
    exit(1);
  }
  
  print('');
  print('Lendo arquivo...');
  final conteudo = await file.readAsString();
  print('Tamanho: ${conteudo.length} caracteres');
  print('');
  
  // Verificar se tem certificado
  final temCertificado = conteudo.contains('-----BEGIN CERTIFICATE-----');
  print('Tem certificado: ${temCertificado ? "SIM" : "NÃO"}');
  
  // Verificar se tem chave privada
  final temChaveRSA = conteudo.contains('-----BEGIN RSA PRIVATE KEY-----');
  final temChavePrivada = conteudo.contains('-----BEGIN PRIVATE KEY-----');
  print('Tem chave RSA: ${temChaveRSA ? "SIM" : "NÃO"}');
  print('Tem chave privada: ${temChavePrivada ? "SIM" : "NÃO"}');
  
  // Contar blocos
  final blocosCert = RegExp(r'-----BEGIN CERTIFICATE-----').allMatches(conteudo).length;
  final blocosChave = RegExp(r'-----BEGIN (RSA )?PRIVATE KEY-----').allMatches(conteudo).length;
  print('');
  print('Blocos de certificado encontrados: $blocosCert');
  print('Blocos de chave privada encontrados: $blocosChave');
  
  // Mostrar primeiras linhas
  print('');
  print('Primeiras 10 linhas do arquivo:');
  final linhas = conteudo.split('\n');
  for (var i = 0; i < linhas.length && i < 10; i++) {
    print('  ${i + 1}: ${linhas[i]}');
  }
  
  print('');
  print('========================================');
  if (temCertificado && (temChaveRSA || temChavePrivada)) {
    print('  ✓ ARQUIVO PEM VÁLIDO');
  } else {
    print('  ✗ ARQUIVO PEM INVÁLIDO OU INCOMPLETO');
    print('');
    if (!temCertificado) {
      print('  FALTA: Certificado (-----BEGIN CERTIFICATE-----)');
    }
    if (!temChaveRSA && !temChavePrivada) {
      print('  FALTA: Chave privada (-----BEGIN RSA PRIVATE KEY-----)');
    }
  }
  print('========================================');
}

