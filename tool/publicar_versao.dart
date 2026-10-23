// ignore_for_file: avoid_print
//
// publicar_versao.dart — publica uma versão no canal de atualização do
// Sistema Êxodo, direto do terminal (sem abrir a tela "Atualização").
//
// Uso:
//   dart run tool/publicar_versao.dart <versao> [opções]
//
// Opções:
//   --notas "texto"            detalhes da versão (vão para o ...notas.txt)
//   --notas-arquivo caminho    lê os detalhes de um arquivo .md/.txt
//   --empresa <id>             publica só para uma empresa (repetível);
//                              sem --empresa, publica para TODOS (app_latest)
//   --forcar                   grava a versão com '!' (atualiza mesmo quem já
//                              está numa versão mais nova)
//   --pasta <dir>              pasta do programa compilado (default:
//                              build/windows/x64/runner/Release)
//   --simular                  só mostra o que faria (não envia nada)
//
// O que ele faz (o mesmo que AppUpdateService.publicarAtualizacao):
//   1. empacota o Release do Windows em sistema_exodo_novo_<versao>.zip com
//      data/app.so + data/flutter_assets/** + sistema_exodo_novo.exe
//      (layout exigido por AppUpdateService.prepararPacoteBaixado);
//   2. envia o zip para o bucket `atualizacoes` (public_read);
//   3. envia os detalhes como sistema_exodo_novo_<versao>.notas.txt;
//   4. grava a linha app_latest (ou app_update_<empresa>) na `bridge_config`
//      com SOMENTE id, version e download_url (coluna a mais faz o PostgREST
//      recusar o registro inteiro).
//
// ATENÇÃO — dois cuidados antes de publicar:
//   * compile o programa ANTES (`flutter build windows --release`) e confira que
//     AppUpdateService.currentAppVersion no código é IGUAL à versão publicada.
//     Se a constante ficar atrás, o cliente baixa a atualização em toda abertura.
//   * o pacote leva o `assets/app.env` embutido, com as credenciais do Neon, e o
//     bucket `atualizacoes` é public_read: quem tiver o endereço baixa o pacote.
//     É o desenho que o sistema já usa para atualizar os clientes.
//
// As credenciais saem do `.env.neon` (o mesmo arquivo que o app usa).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sistema_exodo_novo/services/neon_client.dart';
import 'package:sistema_exodo_novo/services/neon_storage.dart';

/// Bucket dos pacotes por versão (igual a AppUpdateService.bucketAtualizacoes).
const String bucketAtualizacoes = 'atualizacoes';

/// Id da publicação global (igual a PublicacaoVersao.idGlobal).
const String idGlobal = 'app_latest';

/// Prefixo das publicações por empresa.
const String prefixoEmpresa = 'app_update_';

/// Nome do pacote na nuvem: um por versão (nunca sobrescreve outra versão).
String nomePacoteDaVersao(String versao) {
  final limpa = versao.replaceAll('!', '').trim();
  final segura = limpa.isEmpty
      ? 'sem_versao'
      : limpa.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
  return 'sistema_exodo_novo_$segura.zip';
}

/// Nome do arquivo de detalhes da versão (fica ao lado do pacote).
String nomeNotasDaVersao(String versao) =>
    nomePacoteDaVersao(versao).replaceAll('.zip', '.notas.txt');

/// Id do registro na `bridge_config` para um destino (vazio = global).
String idConfigDoDestino(String? empresaId) =>
    (empresaId == null || empresaId.isEmpty)
        ? idGlobal
        : '$prefixoEmpresa$empresaId';

String _homanos(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes bytes';
}

Future<void> main(List<String> args) async {
  final opcoes = _lerArgumentos(args);
  final versao = opcoes.versao;
  final simular = opcoes.simular;
  final empresas = opcoes.empresas;

  print('=' * 76);
  print('Sistema Êxodo — publicar versão no canal de atualização');
  print('=' * 76);
  print('versão   : $versao${opcoes.forcar ? " (FORÇADA)" : ""}');
  print('destino  : ${empresas.isEmpty ? "TODOS os clientes (app_latest)" : "empresas: ${empresas.join(", ")}"}');
  print('pacote   : ${nomePacoteDaVersao(versao)}');
  print('detalhes : ${opcoes.notas.trim().isEmpty ? "(não informados)" : "${opcoes.notas.trim().length} caractere(s)"}');
  print('simular  : ${simular ? "SIM (nada será enviado)" : "não"}');
  print('-' * 76);

  // ---------------------------------------------------------- 1. o programa
  final origem = _acharProgramaCompilado(opcoes.pasta);
  if (origem == null) {
    print('[ERRO] não achei o programa compilado (precisa de data/app.so e');
    print('       sistema_exodo_novo.exe). Rode antes:');
    print('         flutter build windows --release');
    exit(2);
  }
  print('programa : $origem');

  final zipPath = await _empacotar(origem);
  final zip = File(zipPath);
  final zipBytes = await zip.readAsBytes();
  print('pacote   : $zipPath (${_homanos(zipBytes.length)})');

  // ------------------------------------------------------------- 2. a nuvem
  final nuvem = NeonClient.instance;
  final storage = NeonStorage.instance;
  final bucket = storage.from(bucketAtualizacoes);

  String url;
  try {
    if (!simular) {
      print('enviando o pacote...');
      await bucket.uploadBinary(
        nomePacoteDaVersao(versao),
        Uint8List.fromList(zipBytes),
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'application/zip',
        ),
      );
    }
    url = bucket.getPublicUrl(nomePacoteDaVersao(versao));
    print('link     : $url');
  } catch (e) {
    print('[ERRO] falhou o envio do pacote: $e');
    exit(3);
  }

  // Confere o que ficou na nuvem e se o endereço público responde de verdade.
  if (!simular) {
    try {
      final lista = await bucket.list();
      final achado = lista.where((f) => f.name == nomePacoteDaVersao(versao));
      if (achado.isEmpty) {
        print('[AVISO] o pacote não apareceu na listagem do bucket.');
      } else {
        print('na nuvem : ${nomePacoteDaVersao(versao)} — '
            '${_homanos((achado.first.metadata?['size'] as num?)?.toInt() ?? zipBytes.length)}');
      }
      final resp = await http.head(Uri.parse(url));
      print('http head: ${resp.statusCode} ${resp.headers['content-length'] ?? ""} '
          '(public_read: abre sem credencial)');
      if (resp.statusCode != 200) {
        print('[AVISO] o link público não respondeu 200 — confira o acesso do '
            'bucket "$bucketAtualizacoes".');
      }
    } catch (e) {
      print('[AVISO] não consegui confirmar o pacote na nuvem: $e');
    }
  }

  // --------------------------------------------------------- 3. os detalhes
  final notas = opcoes.notas.trim();
  if (notas.isNotEmpty && !simular) {
    try {
      await bucket.uploadBinary(
        nomeNotasDaVersao(versao),
        Uint8List.fromList(utf8.encode('$notas\n')),
        fileOptions: const FileOptions(upsert: true, contentType: 'text/plain'),
      );
      print('detalhes : ${nomeNotasDaVersao(versao)} enviado');
    } catch (e) {
      print('[AVISO] o pacote subiu, mas os detalhes não: $e');
    }
  }

  // --------------------------------------------------- 4. a versão na nuvem
  final versaoNaNuvem = opcoes.forcar ? '!$versao' : versao;
  final alvos = empresas.isEmpty ? <String?>[null] : empresas;
  var falhas = 0;

  for (final destino in alvos) {
    final configId = idConfigDoDestino(destino);
    if (simular) {
      print('[simulado] gravar em $configId: version=$versaoNaNuvem');
      continue;
    }
    try {
      await nuvem.from('bridge_config').upsert(
        {'id': configId, 'version': versaoNaNuvem, 'download_url': url},
        onConflict: 'id',
      );
      final confirma = await nuvem
          .from('bridge_config')
          .select()
          .eq('id', configId)
          .maybeSingle();
      if (confirma == null) {
        print('[ERRO] $configId: registro não confirmado');
        falhas++;
      } else {
        print('gravado  : $configId → version=${confirma['version']}');
      }
    } catch (e) {
      print('[ERRO] $configId: $e');
      falhas++;
    }
  }

  print('-' * 76);
  if (simular) {
    print('SIMULAÇÃO concluída — nada foi enviado nem gravado.');
  } else if (falhas == 0) {
    print('PUBLICADO: versão $versao '
        '${empresas.isEmpty ? "para TODOS os clientes" : "para ${empresas.length} empresa(s)"}.');
    print('Os clientes que já estão abertos pegam no próximo boot; quem está '
        'na versão anterior vai baixar ${_homanos(zipBytes.length)}.');
  } else {
    print('PUBLICAÇÃO COM FALHA em $falhas destino(s) — veja acima.');
    exit(4);
  }
  print('=' * 76);
}

// ==========================================================================
// Argumentos
// ==========================================================================

class _Opcoes {
  final String versao;
  final String notas;
  final List<String> empresas;
  final bool forcar;
  final String? pasta;
  final bool simular;

  _Opcoes({
    required this.versao,
    required this.notas,
    required this.empresas,
    required this.forcar,
    required this.pasta,
    required this.simular,
  });
}

_Opcoes _lerArgumentos(List<String> args) {
  String? versao;
  var notas = '';
  final empresas = <String>[];
  var forcar = false;
  String? pasta;
  var simular = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--notas':
        notas = (i + 1 < args.length) ? args[++i] : '';
      case '--notas-arquivo':
        final caminho = (i + 1 < args.length) ? args[++i] : '';
        if (caminho.isNotEmpty && File(caminho).existsSync()) {
          notas = File(caminho).readAsStringSync();
        }
      case '--empresa':
        if (i + 1 < args.length) empresas.add(args[++i]);
      case '--forcar':
        forcar = true;
      case '--pasta':
        if (i + 1 < args.length) pasta = args[++i];
      case '--simular':
        simular = true;
      case '--ajuda':
      case '-h':
        _uso();
      default:
        if (a.startsWith('--')) {
          print('opção desconhecida: $a');
          _uso();
        }
        versao ??= a;
    }
  }

  final v = (versao ?? '').replaceAll('!', '').trim();
  if (!RegExp(r'^\d+(\.\d+){1,3}$').hasMatch(v)) {
    print('informe a versão, ex: dart run tool/publicar_versao.dart 1.0.54');
    _uso();
  }
  return _Opcoes(
    versao: v,
    notas: notas,
    empresas: empresas,
    forcar: forcar,
    pasta: pasta,
    simular: simular,
  );
}

Never _uso() {
  print('');
  print('uso: dart run tool/publicar_versao.dart <versao> [opções]');
  print('  --notas "texto" | --notas-arquivo arquivo.md');
  print('  --empresa <id> (repetível)   --forcar   --simular');
  print('  --pasta <dir do programa compilado>');
  exit(1);
}

// ==========================================================================
// Pacote
// ==========================================================================

/// Procura a pasta do programa compilado (mesma ordem do app).
String? _acharProgramaCompilado(String? pasta) {
  final candidatas = <String>[
    ?pasta,
    p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release'),
    p.join(p.dirname(Platform.resolvedExecutable)),
    r'C:\SistemaExodo',
    p.join(Platform.environment['USERPROFILE'] ?? '', 'SistemaExodo'),
  ];
  for (final c in candidatas) {
    final dir = Directory(c);
    if (File(p.join(dir.path, 'data', 'app.so')).existsSync() &&
        File(p.join(dir.path, 'sistema_exodo_novo.exe')).existsSync()) {
      return p.normalize(dir.path);
    }
  }
  return null;
}

/// Monta o .zip com o MESMO layout que AppUpdateService.empacotarAtualizacao:
/// `data/app.so`, `data/flutter_assets/**` e `sistema_exodo_novo.exe`.
Future<String> _empacotar(String origem) async {
  final zip = File(p.join(Directory.systemTemp.path,
      'exodo_publicar_${DateTime.now().millisecondsSinceEpoch}.zip'));
  final encoder = ZipFileEncoder();
  try {
    encoder.create(zip.path);
    await encoder.addFile(
        File(p.join(origem, 'data', 'app.so')), 'data/app.so');

    final assets = Directory(p.join(origem, 'data', 'flutter_assets'));
    if (assets.existsSync()) {
      final raiz = assets.path;
      for (final item in assets.listSync(recursive: true)) {
        if (item is! File) continue;
        final rel = p.relative(item.path, from: raiz).replaceAll('\\', '/');
        await encoder.addFile(item, 'data/flutter_assets/$rel');
      }
    }

    await encoder.addFile(
        File(p.join(origem, 'sistema_exodo_novo.exe')), 'sistema_exodo_novo.exe');
    await encoder.close();
  } catch (e) {
    try {
      await encoder.close();
    } catch (_) {}
    throw 'erro ao montar o pacote: $e';
  }
  return zip.path;
}
