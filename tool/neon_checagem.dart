// Prova ponta a ponta da CAMADA DE DADOS do app no Neon — o mesmo código que o
// aplicativo usa depois da migração (lib/services/neon_client.dart e
// lib/services/neon_storage.dart, sem Flutter).
//
//   * Neon Auth      → emissão do token que a Data API exige;
//   * Data API       → SELECT, INSERT, SELECT, UPDATE, DELETE e RPC;
//   * Object Storage → listBuckets, upload, list (raiz e subpasta), download,
//                      URL pública (bucket public_read) e remove.
//
// Rode na raiz do projeto:
//
//   dart run tool/neon_checagem.dart
//
// Sai com 0 quando tudo passa.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sistema_exodo_novo/services/neon_client.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';
import 'package:sistema_exodo_novo/services/neon_storage.dart';

final List<String> _falhas = [];
final List<String> _passos = [];

void _ok(String nome, [String detalhe = '']) {
  _passos.add(nome);
  print('[OK   ] $nome${detalhe.isEmpty ? '' : '  →  $detalhe'}');
}

void _falha(String nome, Object erro) {
  _falhas.add(nome);
  print('[FALHA] $nome\n          $erro');
}

bool _mesmosBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> main() async {
  print('=' * 76);
  print('Neon — checagem da camada de dados (Data API / Storage / Auth)');
  print('credenciais : ${NeonConfig.nomeArquivo}');
  print('Data API    : ${NeonConfig.dataApiUrl}');
  print('Storage S3  : ${NeonConfig.storageEndpoint}');
  print('=' * 76);

  if (!NeonConfig.dataApiDisponivel) {
    print('NEON_DATA_API_URL ausente em ${NeonConfig.nomeArquivo}.');
    exit(2);
  }

  final nuvem = NeonClient.instance;

  // ---------------------------------------------------------------- Neon Auth
  try {
    await nuvem.inicializar();
    if (!nuvem.auth.disponivel) {
      throw 'o Neon Auth respondeu sem token';
    }
    _ok('Neon Auth → token anônimo da Data API');
  } catch (e) {
    _falha('Neon Auth → token anônimo da Data API', e);
  }

  // ----------------------------------------------------- Data API: leitura
  String? empresaId;
  try {
    final empresas = await nuvem
        .from('empresas')
        .select('id, razao_social')
        .limit(5);
    if (empresas.isEmpty) throw 'nenhuma linha em empresas';
    empresaId = empresas.first['id']?.toString();
    _ok('Data API → SELECT empresas', '${empresas.length} linha(s)');
  } catch (e) {
    _falha('Data API → SELECT empresas', e);
  }

  // ------------------------------------------ Data API: escrita (round-trip)
  final marcador = 'checagem-neon-${DateTime.now().millisecondsSinceEpoch}';
  try {
    await nuvem.from('sync_logs').insert({
      'empresa_id': empresaId ?? '',
      'pc_name': 'tool/neon_checagem',
      'evento': marcador,
      'detalhes': 'prova de escrita da migração Supabase→Neon',
    });

    final lidas = await nuvem
        .from('sync_logs')
        .select('id, evento')
        .eq('evento', marcador);
    if (lidas.isEmpty) throw 'a linha inserida não voltou no SELECT';
    final id = lidas.first['id'].toString();

    await nuvem
        .from('sync_logs')
        .update({'detalhes': 'atualizado pela checagem'}).eq('id', id);

    await nuvem.from('sync_logs').delete().eq('id', id);

    final restou = await nuvem
        .from('sync_logs')
        .select('id')
        .eq('id', id);
    if (restou.isNotEmpty) throw 'a linha continuou depois do DELETE';

    _ok('Data API → INSERT + SELECT + UPDATE + DELETE (sync_logs)');
  } catch (e) {
    _falha('Data API → INSERT + SELECT + UPDATE + DELETE (sync_logs)', e);
  }

  // --------------------------------------------------------- Data API: RPC
  try {
    final resposta = await nuvem.rpc<dynamic>(
      'decrementar_estoque',
      params: {'p_id': 'produto-inexistente-checagem', 'p_quantidade': 1},
    );
    _ok('Data API → RPC decrementar_estoque', jsonEncode(resposta));
  } catch (e) {
    _falha('Data API → RPC decrementar_estoque', e);
  }

  // ------------------------------------------- Data API: predicado do login
  // Replica o que `SupabaseService.validarCredenciaisNaNuvem` faz no login:
  // busca o e-mail (com e sem domínio) e confere a senha da tabela `usuarios`.
  // O resultado é tri-estado: true = confere, false = nuvem conhece e recusa,
  // null = nuvem não conhece o e-mail (aí quem decide é o banco local).
  try {
    // Pega uma amostra que REALMENTE tenha email e senha: existem usuários
    // legados sem senha no banco (não servem para provar o login) e o SELECT
    // sem ORDER BY podia devolver justamente um deles.
    final candidatos =
        await nuvem.from('usuarios').select('id, email, senha').limit(50);
    if (candidatos.isEmpty) throw 'a tabela usuarios está vazia';
    final linha = candidatos.firstWhere(
      (l) =>
          (l['email']?.toString() ?? '').trim().isNotEmpty &&
          (l['senha']?.toString() ?? '').trim().isNotEmpty,
      orElse: () => <String, dynamic>{},
    );
    final email = (linha['email']?.toString() ?? '').trim().toLowerCase();
    final senha = (linha['senha']?.toString() ?? '').trim();
    if (email.isEmpty || senha.isEmpty) {
      throw 'nenhum usuário com email e senha nas primeiras 50 linhas';
    }

    Future<bool?> validar(String candidato, String tentativa) async {
      final alvo = candidato.trim().toLowerCase();
      final local = alvo.contains('@') ? alvo.split('@').first : alvo;
      final linhas = await nuvem
          .from('usuarios')
          .select('id, senha')
          .inFilter('email', <String>{alvo, local}.toList())
          .limit(20);
      if (linhas.isEmpty) return null;
      return linhas.any(
        (l) => (l['senha']?.toString() ?? '').trim() == tentativa.trim(),
      );
    }

    if (await validar(email, senha) != true) {
      throw 'a senha CORRETA foi recusada';
    }
    if (await validar(email, '$senha-errada') != false) {
      throw 'a senha ERRADA foi aceita';
    }
    if (await validar('nao-existe-checagem@exodo.test', 'x') != null) {
      throw 'e-mail desconhecido deveria dar null';
    }
    _ok(
      'Data API → predicado do login em usuarios',
      'correta=true, errada=false, desconhecido=null',
    );
  } catch (e) {
    _falha('Data API → predicado do login em usuarios', e);
  }

  // ------------------------------------------------------------ Object Storage
  final storage = NeonStorage.instance;

  try {
    final buckets = await storage.listBuckets();
    final nomes = buckets.map((b) => b.id).toList()..sort();
    for (final esperado in const [
      'assets',
      'atualizacoes',
      'backups',
      'dumps',
      'imagens',
      'xmls',
    ]) {
      if (!nomes.contains(esperado)) {
        throw 'bucket "$esperado" não encontrado';
      }
    }
    _ok('Storage → listBuckets', nomes.join(', '));
  } catch (e) {
    _falha('Storage → listBuckets', e);
  }

  final bucket = storage.from('assets');
  const caminho = '_checagem/pasta/ola.txt';
  final conteudo = utf8.encode('ola neon ${DateTime.now().toIso8601String()}');

  try {
    await bucket.uploadBinary(
      caminho,
      Uint8List.fromList(conteudo),
      fileOptions: const FileOptions(upsert: true, contentType: 'text/plain'),
    );
    _ok('Storage → uploadBinary', 'assets/$caminho');
  } catch (e) {
    _falha('Storage → uploadBinary', e);
  }

  try {
    final raiz = (await bucket.list(path: '_checagem'))
        .map((f) => f.name)
        .toList()
      ..sort();
    if (!raiz.contains('pasta')) {
      throw '"pasta" não apareceu na listagem da raiz: $raiz';
    }
    _ok('Storage → list(path) raiz', raiz.join(', '));

    final pasta = (await bucket.list(path: '_checagem/pasta'))
        .map((f) => f.name)
        .toList()
      ..sort();
    if (!pasta.contains('ola.txt')) {
      throw '"ola.txt" não apareceu na subpasta: $pasta';
    }
    _ok('Storage → list(path) subpasta', pasta.join(', '));
  } catch (e) {
    _falha('Storage → list', e);
  }

  try {
    final bytes = await bucket.download(caminho);
    if (!_mesmosBytes(bytes, conteudo)) {
      throw 'conteúdo baixado é diferente do enviado '
          '(${bytes.length} vs ${conteudo.length} bytes)';
    }
    _ok('Storage → download', '${bytes.length} bytes iguais aos enviados');
  } catch (e) {
    _falha('Storage → download', e);
  }

  // Bucket `public_read`: a URL tem de abrir SEM credencial nenhuma.
  try {
    const caminhoPublico = '_checagem/publico.txt';
    final conteudoPublico = utf8.encode('publico ${DateTime.now().toIso8601String()}');
    await storage.from('imagens').uploadBinary(
          caminhoPublico,
          Uint8List.fromList(conteudoPublico),
          fileOptions: const FileOptions(upsert: true, contentType: 'text/plain'),
        );

    final url = storage.from('imagens').getPublicUrl(caminhoPublico);
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200 || !_mesmosBytes(resp.bodyBytes, conteudoPublico)) {
      throw 'HTTP ${resp.statusCode} ao abrir $url sem credencial';
    }
    _ok('Storage → URL pública sem credencial (bucket imagens)', url);

    await storage.from('imagens').remove([caminhoPublico]);
  } catch (e) {
    _falha('Storage → URL pública sem credencial (bucket imagens)', e);
  }

  try {
    await bucket.remove([caminho]);
    final restou = (await bucket.list(path: '_checagem/pasta'))
        .map((f) => f.name)
        .toList();
    if (restou.contains('ola.txt')) throw 'o arquivo continuou depois do remove';
    _ok('Storage → remove');
  } catch (e) {
    _falha('Storage → remove', e);
  }

  nuvem.auth.parar();

  print('-' * 76);
  print('resumo: ${_passos.length - _falhas.length}/${_passos.length} OK');
  if (_falhas.isNotEmpty) {
    print('falharam: ${_falhas.join(' | ')}');
  }
  print('=' * 76);
  exit(_falhas.isEmpty ? 0 : 1);
}
