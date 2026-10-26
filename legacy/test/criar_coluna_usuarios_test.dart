// O ERRO QUE DEIXAVA A TABELA `usuarios` SEM AJUSTE.
//
// Sintoma relatado: ao clicar em "Criar NO LOCAL o que falta", todas as tabelas
// eram ajustadas menos `usuarios`:
//
//   🔒 Colunas sensíveis que o app NÃO cria sozinho: usuarios.senha
//   🔧 Ajustando usuarios no banco local...
//   ❌ usuarios: ERRO: sequência de bytes é inválida para codificação "UTF8": 0xed 0x76 0x65
//
// Causa: o SQL era executado por `psql -c` (linha de comando). No Windows a linha
// de comando é convertida para a página de código ANSI — e o comentário que marca
// a coluna sensível tem acento ("sensível", "NÃO"). Os acentos viravam bytes
// latin1 (0xED = "í") e o PostgreSQL recusava o COMANDO INTEIRO, então
// `usuarios.empresa_id` nunca era criada.
//
// Este teste prova as duas correções:
//   1. o SQL de estrutura vai por ARQUIVO (`psql -f`), não por `-c`;
//   2. o SQL gerado é ASCII puro (o comentário diz "sensivel"/"NAO"), então nem a
//      linha de comando nem um psql com cliente WIN1252 podem estragar;
//   3. e, de verdade: o caminho real rodou em `usuarios` e a estrutura agora está
//      igual à nuvem — `empresa_id` foi criada e nada mais falta ali.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/services/backup_restore_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/supabase_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() async {
    HttpOverrides.global = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'dev.fluttercommunity.plus/connectivity',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), (call) async => null);
    }
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
          url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
    }
  });

  test('o SQL de estrutura é ASCII e a coluna usuarios.empresa_id entra de verdade',
      () async {
    final service = BackupRestoreService(DataService());

    // Comparação (não aplica nada): gera o SQL e salva em disco.
    final (okComparacao, logsComparacao) =
        await service.criarEstruturaFaltanteNoLocal(somenteComparar: true);
    print(logsComparacao.join('\n'));
    expect(okComparacao, isTrue);

    // 1. O app tem de executar o SQL por ARQUIVO, não por `-c` (a linha de
    //    comando do Windows converte para ANSI e estoura a codificação).
    final fonte = File('lib/services/backup_restore_service.dart').readAsStringSync();
    expect(fonte, contains('_executarSqlViaArquivo'));
    expect(fonte, contains("SET client_encoding = 'UTF8';"));

    // 2. Quando há algo a criar, o arquivo é salvo e o caminho aparece no log —
    //    é ele (e não "o mais recente da pasta", que pode ser de uma rodada
    //    antiga) que este teste lê.
    final linhaCaminho = logsComparacao
        .firstWhere((l) => l.startsWith('📄 SQL salvo em:'), orElse: () => '')
        .replaceFirst('📄 SQL salvo em:', '')
        .trim();
    print('arquivo de SQL desta rodada: $linhaCaminho');
    if (linhaCaminho.isNotEmpty) {
      final sqlArquivo = File(linhaCaminho).readAsStringSync();

      // O arquivo diz ao psql que os bytes são UTF-8 (senão um cliente em
      // WIN1252 leria os acentos do cabeçalho como bytes inválidos).
      expect(sqlArquivo, contains("SET client_encoding = 'UTF8';"));

      // Nenhuma linha EXECUTÁVEL pode ter acento: acento no SQL foi exatamente
      // o que quebrou o ajuste de `usuarios` no Windows.
      final executaveis = sqlArquivo
          .split(RegExp(r'\r?\n'))
          .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('--'))
          .toList();
      expect(executaveis, isNotEmpty);
      for (final linha in executaveis) {
        expect(linha.codeUnits.every((c) => c < 128), isTrue,
            reason: 'linha executável com caractere não-ASCII: $linha');
      }

      // Se senha aparecer, tem de estar COMENTADA.
      for (final linha in sqlArquivo
          .split(RegExp(r'\r?\n'))
          .where((l) => l.contains('ADD COLUMN IF NOT EXISTS "senha"'))) {
        expect(linha.trimLeft().startsWith('--'), isTrue,
            reason: 'usuarios.senha nunca pode sair executável: $linha');
      }
    }

    // 3. A linha que "reserva" a coluna de autorização (é a MESMA função que
    //    monta o arquivo) sai comentada, em ASCII puro e com o motivo certo —
    //    este é o texto que ia na linha de comando e derrubava o comando todo.
    final comentadaSenha =
        BackupRestoreService.linhaComentadaDeColunaQueNaoCriaSozinho(
      'usuarios.senha',
      'ALTER TABLE public."usuarios" ADD COLUMN IF NOT EXISTS "senha" text',
    );
    expect(comentadaSenha.trimLeft().startsWith('--'), isTrue);
    expect(comentadaSenha, contains('sensivel'));
    expect(comentadaSenha.contains('sensível'), isFalse);
    expect(comentadaSenha.contains('NÃO'), isFalse);
    expect(comentadaSenha.codeUnits.every((c) => c < 128), isTrue,
        reason: 'SQL com acento quebra o psql no Windows: $comentadaSenha');

    final comentadaEmpresaId =
        BackupRestoreService.linhaComentadaDeColunaQueNaoCriaSozinho(
      'empresas.empresa_id',
      'ALTER TABLE public."empresas" ADD COLUMN IF NOT EXISTS "empresa_id" text',
    );
    expect(comentadaEmpresaId.trimLeft().startsWith('--'), isTrue);
    expect(comentadaEmpresaId, contains('precisa de decisao'));
    expect(comentadaEmpresaId.codeUnits.every((c) => c < 128), isTrue);

    // 4. A prova de verdade: rodar o caminho real para `usuarios` e conferir no
    //    banco que a estrutura ficou igual (idempotente: não quebra nada).
    final conferencia = await service.conferirEsquemaBancos();
    final faltaEmpresaId = conferencia.colunasFaltandoNoLocal
        .any((c) => c.rotulo == 'usuarios.empresa_id');
    print('usuarios.empresa_id faltando antes: $faltaEmpresaId');

    final (ok, logs) = await service.criarEstruturaFaltanteNoLocal(
      tabelas: {'usuarios'},
      onProgress: (m) => print('   $m'),
    );
    print(logs.join('\n'));
    expect(ok, isTrue, reason: logs.join('\n'));

    final depois = await service.conferirEsquemaBancos();
    final aindaFalta = depois.colunasFaltandoNoLocal
        .map((c) => c.rotulo)
        .where((r) => r.startsWith('usuarios.'))
        .toList();
    print('continuam faltando em usuarios: $aindaFalta');
    expect(aindaFalta, isNot(contains('usuarios.empresa_id')),
        reason: 'a coluna empresa_id não pode continuar faltando');
    // `usuarios` já foi igualada (empresa_id e senha entraram com a autorização
    // explícita do diálogo), então o certo aqui é não sobrar nenhuma coluna.
    expect(aindaFalta, isEmpty,
        reason: 'usuarios já está igual à nuvem: nada pode continuar faltando');

    // 5. Nada foi para a nuvem: a contagem de lá segue igual.
    expect(depois.colunasFaltandoNaNuvem.where((c) => c.tabela == 'usuarios'),
        isEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
