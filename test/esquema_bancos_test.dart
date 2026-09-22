// Testes do painel "Saúde dos Bancos" — a conferência de ESTRUTURA entre o
// banco LOCAL e o banco da NUVEM (Supabase).
//
// Tudo aqui é SOMENTE LEITURA contra os bancos reais do computador:
//   • `conferirEsquemaBancos` lê o catálogo dos dois lados e compara;
//   • `criarEstruturaFaltanteNoLocal(somenteComparar: true)` monta o SQL do que
//     falta no local e NÃO executa nada.
//
// Ao final o teste prova que a conferência não criou nada: a contagem de
// tabelas do banco local tem de ser exatamente a mesma de antes.

import 'dart:convert';
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

  /// Tabelas privadas do app: existem só no computador, de propósito — ficam
  /// fora da comparação e aparecem em `privadasDoApp`.
  const privadasEsperadas = {'_exodo_sync_log', '_sync_controle', 'cache_dados'};

  void prepararAmbiente() {
    HttpOverrides.global = null;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'dev.fluttercommunity.plus/connectivity',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), (call) async => null);
    }
    for (final canal in const [
      'xyz.luan/audioplayers.global/events',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockStreamHandler(
          EventChannel(canal), MockStreamHandler.inline(onListen: (args, sink) {}));
    }
  }

  late BackupRestoreService service;

  setUpAll(() async {
    prepararAmbiente();
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
    }
    service = BackupRestoreService(DataService());
  });

  test('conferência de estrutura lê os dois bancos e não cria nada', () async {
    final antes = await service.conferirEsquemaBancos();

    print('--- CONFERÊNCIA DE ESTRUTURA ---');
    print(antes.relatorioTexto);

    expect(antes.leuOsDois, isTrue,
        reason: 'os dois bancos deveriam responder: ${antes.resumo}');
    expect(antes.totalLocal, greaterThan(0));
    expect(antes.totalNuvem, greaterThan(0));

    // As tabelas privadas do app ficam fora da conta e são listadas à parte.
    for (final privada in privadasEsperadas) {
      expect(antes.privadasDoApp, contains(privada));
      expect(antes.somenteNoLocal, isNot(contains(privada)));
      expect(antes.somenteNaNuvem, isNot(contains(privada)));
    }

    // Nenhuma tabela/coluna privada pode aparecer como divergência.
    for (final tabela in [...antes.somenteNoLocal, ...antes.somenteNaNuvem]) {
      expect(tabela.startsWith('_'), isFalse);
      expect(privadasEsperadas.contains(tabela), isFalse);
    }

    // Nome que é TABELA aqui e VIEW na nuvem NÃO pode contar como tabela
    // faltando: não dá para criar tabela com um nome que já existe como view
    // (é o caso da vw_historico_recente — a nuvem tem como view).
    for (final nome in antes.objetoDiferenteNaNuvem) {
      expect(antes.somenteNoLocal, isNot(contains(nome)));
      expect(antes.somenteNaNuvem, isNot(contains(nome)));
    }
    for (final nome in antes.objetoDiferenteNoLocal) {
      expect(antes.somenteNoLocal, isNot(contains(nome)));
      expect(antes.somenteNaNuvem, isNot(contains(nome)));
    }

    // O botão "⬇️ Criar NO LOCAL" é alimentado por `tabelasParaIgualarLocal`,
    // que junta tabelas que faltam E colunas que faltam. Este é o caso real da
    // máquina: 0 tabela faltando e dezenas de colunas faltando — se a lista
    // saísse só de `somenteNaNuvem`, o botão diria "nada a criar" e não faria
    // nada, que era exatamente o defeito relatado.
    final trabalho = BackupRestoreService.trabalhosParaIgualarLocal(antes);
    final nomesParaTocar = BackupRestoreService.tabelasParaIgualarLocal(antes);
    print('BOTÃO LOCAL: ${trabalho.tabelasNovas.length} tabela(s) nova(s) + '
        '${trabalho.colunasPorTabela.values.fold<int>(0, (s, l) => s + l.length)} '
        'coluna(s) em ${trabalho.colunasPorTabela.length} tabela(s) — '
        '${nomesParaTocar.length} tabela(s) a tocar');
    expect(nomesParaTocar.toSet(),
        {...trabalho.tabelasNovas, ...trabalho.colunasPorTabela.keys});
    // Só exige trabalho quando existe coluna que o app PODE criar: as sensíveis e
    // as que precisam de decisão ficam de fora por definição.
    final colunasCriaveis = antes.colunasFaltandoNoLocal
        .where((c) => !BackupRestoreService.naoCriarSozinho(c.rotulo))
        .length;
    print('colunas que o app pode criar no local: $colunasCriaveis');
    if (colunasCriaveis > 0) {
      expect(nomesParaTocar, isNotEmpty,
          reason: 'com colunas criáveis faltando, o botão do local tem de ter o que '
              'fazer (mesmo com 0 tabela faltando)');
    } else {
      expect(nomesParaTocar, isEmpty,
          reason: 'sem nada criável, o botão não pode prometer trabalho');
    }
    // Coluna sensível (senha) e coluna que muda a LEITURA do app nunca entram no
    // trabalho automático — ficam comentadas no SQL em disco, por decisão do app.
    for (final e in trabalho.colunasPorTabela.entries) {
      for (final coluna in e.value) {
        expect(BackupRestoreService.naoCriarSozinho('${e.key}.$coluna'), isFalse,
            reason: '${e.key}.$coluna não pode ser criada sozinha');
      }
    }
    // `empresas.empresa_id` existe na nuvem e falta aqui, mas NÃO pode entrar no
    // trabalho automático: criá-la faria o carregador filtrar a leitura de
    // `empresas` por ela e a lista de empresas voltaria vazia.
    expect(trabalho.colunasPorTabela['empresas'] ?? const <String>[],
        isNot(contains('empresa_id')));
    final faltaEmpresaId = antes.colunasFaltandoNoLocal
        .any((x) => x.rotulo == 'empresas.empresa_id');
    expect(antes.decisaoFaltando.contains('empresas.empresa_id'), faltaEmpresaId);

    // O veredito tem de dizer quem está atrasado (e não deixar a pergunta
    // "é o local ou a nuvem?") — mas só existe lado atrasado quando há tabela ou
    // coluna a criar. Quando só sobraram TIPOS diferentes, o certo é dizer que
    // nenhum dos botões resolve, e não mandar clicar em um deles.
    print('VEREDITO: ${antes.veredito}');
    final haTabelaOuColunaACriar = antes.somenteNoLocal.isNotEmpty ||
        antes.somenteNaNuvem.isNotEmpty ||
        colunasCriaveis > 0 ||
        antes.colunasFaltandoNaNuvem.isNotEmpty;
    if (haTabelaOuColunaACriar) {
      expect(
        antes.veredito.toLowerCase().contains('local') ||
            antes.veredito.toLowerCase().contains('nuvem'),
        isTrue,
        reason: 'o veredito precisa apontar o lado atrasado: ${antes.veredito}',
      );
    } else if (antes.tiposDiferentes.isNotEmpty) {
      expect(antes.veredito, contains('TIPO'),
          reason: 'sem nada a criar, o veredito não pode mandar criar: ${antes.veredito}');
    } else {
      // Nada a criar e nenhum tipo diferente: os dois bancos estão iguais e o
      // veredito tem de dizer isso, em vez de mandar clicar em um botão.
      expect(antes.veredito, contains('iguais'),
          reason: 'com os dois bancos iguais, o veredito precisa dizer: ${antes.veredito}');
    }

    // A conferência é gravada em disco (JSON para a tela + texto para leitura).
    final json = File(BackupRestoreService.arquivoConferenciaEsquema);
    final txt = File(BackupRestoreService.arquivoConferenciaEsquemaTxt);
    expect(await json.exists(), isTrue);
    expect(await txt.exists(), isTrue);

    // E o que a tela lê de volta é exatamente o mesmo retrato.
    final lido = await service.lerUltimaConferenciaEsquema();
    expect(lido, isNotNull);
    expect(lido!.totalLocal, antes.totalLocal);
    expect(lido.totalNuvem, antes.totalNuvem);
    expect(lido.somenteNoLocal, antes.somenteNoLocal);
    expect(lido.somenteNaNuvem, antes.somenteNaNuvem);
    expect(lido.colunasFaltandoNoLocal.length, antes.colunasFaltandoNoLocal.length);
    expect(lido.colunasFaltandoNaNuvem.length, antes.colunasFaltandoNaNuvem.length);
    expect(lido.erroLocal, isNull);
    expect(lido.erroNuvem, isNull);

    // O relatório em texto termina explicando como igualar cada lado.
    expect(antes.relatorioTexto, contains('COMO IGUALAR'));

    // Uma segunda conferência (agora com o retrato já lido) tem de dar o MESMO
    // resultado: comparar não altera nada.
    final depois = await service.conferirEsquemaBancos();
    expect(depois.totalLocal, antes.totalLocal);
    expect(depois.totalNuvem, antes.totalNuvem);
    expect(depois.somenteNaNuvem, antes.somenteNaNuvem);
    expect(depois.somenteNoLocal, antes.somenteNoLocal);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('comparação do que falta no LOCAL gera o SQL sem executar', () async {
    final conferencia = await service.conferirEsquemaBancos();
    expect(conferencia.leuOsDois, isTrue, reason: conferencia.resumo);

    final (ok, logs) = await service.criarEstruturaFaltanteNoLocal(
      somenteComparar: true,
      onProgress: (m) => print('   $m'),
    );
    final texto = logs.join('\n');
    print('--- COMPARAÇÃO NUVEM → LOCAL ---');
    print(texto);

    expect(ok, isTrue);

    // O diálogo da nuvem usa a MESMA convenção do painel: conta só as tabelas de
    // negócio, avisa das privadas e mostra o diagnóstico dos dois sentidos.
    expect(texto, contains('de negócio +'),
        reason: 'a contagem precisa separar as tabelas de negócio das privadas');
    expect(texto, contains('DIAGNÓSTICO'),
        reason: 'o diálogo precisa dizer quem está atrasado, nos dois sentidos');
    expect(texto, contains('Faltam NO LOCAL:'),
        reason: 'a direção inversa precisa aparecer (é onde estão as colunas que faltam)');
    if (conferencia.objetoDiferenteNaNuvem.isNotEmpty) {
      expect(texto, contains('é TABELA aqui e VIEW na nuvem'),
          reason: 'a view não pode aparecer como tabela faltando');
    }

    // O que a nuvem tem e o local não tem é o mesmo que a conferência apontou.
    for (final tabela in conferencia.somenteNaNuvem) {
      expect(texto, contains('criar tabela $tabela'),
          reason: '$tabela deveria aparecer na comparação');
    }

    // Se existe algo a criar, o SQL foi gerado em disco e não é vazio.
    if (conferencia.somenteNaNuvem.isNotEmpty) {
      expect(texto, contains('MODO COMPARAÇÃO'));
      final pasta = Directory('C:\\ExodoBackups');
      final arquivos = pasta
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.split(Platform.pathSeparator).last.startsWith('CRIAR_TABELAS_LOCAL_'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      expect(arquivos, isNotEmpty);
      final sql = arquivos.first.readAsStringSync();
      expect(sql, contains('CREATE TABLE IF NOT EXISTS public.'));
      expect(sql, contains('Não apaga nada'));

      // Coluna sensível (senha) nunca sai executável: vai COMENTADA no arquivo,
      // para o app não mexer sozinho em como o usuário entra no sistema.
      final comSenha = sql
          .split('\n')
          .where((l) => l.contains('ADD COLUMN IF NOT EXISTS "senha"'))
          .toList();
      for (final linha in comSenha) {
        expect(linha.trimLeft().startsWith('--'), isTrue,
            reason: 'usuarios.senha não pode ser criada automaticamente: $linha');
      }
      for (final sensivel in BackupRestoreService.colunasSensiveis) {
        expect(sensivel.contains('.') || sensivel.isNotEmpty, isTrue);
      }
      print('SQL gerado: ${arquivos.first.path}');
      print(sql.split('\n').take(30).join('\n'));
    }

    // O `somenteComparar` não pode ter criado nada.
    final depois = await service.conferirEsquemaBancos();
    expect(depois.totalLocal, conferencia.totalLocal,
        reason: 'a comparação não pode ter criado tabela no banco local');
    expect(depois.somenteNaNuvem, conferencia.somenteNaNuvem);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('retrato da conferência sobrevive em disco (JSON ida e volta)', () async {
    final original = ConferenciaEsquema(
      quando: DateTime(2026, 9, 21, 22, 41),
      totalLocal: 45,
      totalNuvem: 50,
      somenteNoLocal: const ['tabela_so_aqui'],
      somenteNaNuvem: const ['caixa', 'precos'],
      colunasFaltandoNoLocal: const [
        ColunaDivergente(tabela: 'caixa', coluna: 'operador', tipoNuvem: 'text'),
      ],
      colunasFaltandoNaNuvem: const [
        ColunaDivergente(tabela: 'produtos', coluna: 'codigo_barras', tipoLocal: 'text'),
      ],
      tiposDiferentes: const ['caixa.saldo_inicial: local numeric × nuvem numeric'],
      privadasDoApp: const ['_exodo_sync_log', 'cache_dados'],
      objetoDiferenteNaNuvem: const ['vw_historico_recente'],
    );

    final volta = ConferenciaEsquema.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(volta.quando, original.quando);
    expect(volta.totalLocal, 45);
    expect(volta.totalNuvem, 50);
    expect(volta.somenteNoLocal, ['tabela_so_aqui']);
    expect(volta.somenteNaNuvem, ['caixa', 'precos']);
    expect(volta.colunasFaltandoNoLocal.single.rotulo, 'caixa.operador');
    expect(volta.colunasFaltandoNoLocal.single.tipoNuvem, 'text');
    expect(volta.colunasFaltandoNaNuvem.single.rotulo, 'produtos.codigo_barras');
    expect(volta.privadasDoApp, ['_exodo_sync_log', 'cache_dados']);
    expect(volta.objetoDiferenteNaNuvem, ['vw_historico_recente']);
    expect(volta.objetoDiferenteNoLocal, isEmpty);
    // A view com nome de tabela não entra na conta de divergências.
    expect(volta.divergencias, 6);
    expect(volta.leuOsDois, isTrue);
    expect(volta.iguais, isFalse);
    expect(volta.resumo, contains('Local 45'));
    expect(volta.relatorioTexto, contains('COMO IGUALAR'));

    // Divergência zero = estruturas iguais.
    final igual = ConferenciaEsquema(quando: DateTime.now(), totalLocal: 45, totalNuvem: 45);
    expect(igual.iguais, isTrue);
    expect(igual.divergencias, 0);

    // Coluna sensível (senha) aparece no relatório, mas NÃO conta como
    // pendência: o app não a cria sozinho de propósito.
    final soSensivel = ConferenciaEsquema(
      quando: DateTime.now(),
      totalLocal: 41,
      totalNuvem: 48,
      colunasFaltandoNoLocal: const [
        ColunaDivergente(tabela: 'usuarios', coluna: 'senha', tipoNuvem: 'text'),
      ],
    );
    expect(soSensivel.sensiveisFaltando, ['usuarios.senha']);
    expect(soSensivel.divergencias, 1);
    expect(soSensivel.divergenciasReais, 0);
    expect(soSensivel.iguais, isTrue);
    expect(soSensivel.resumo, contains('sensível'));
    expect(soSensivel.relatorioTexto, contains('Colunas SENSÍVEIS'));

    // Falha de um dos lados: nada é afirmado como igual.
    final falhou = ConferenciaEsquema(
      quando: DateTime.now(),
      totalLocal: 45,
      erroNuvem: 'A nuvem não respondeu (timeout). Confira a internet.',
    );
    expect(falhou.leuOsDois, isFalse);
    expect(falhou.iguais, isFalse);
    expect(falhou.resumo, contains('timeout'));
    expect(falhou.relatorioTexto, contains('Sem ler os dois lados'));
  });

  test('botão do local enxerga COLUNA faltando (0 tabela) e ignora a sensível', () {
    // O retrato exato da máquina do usuário: a nuvem não está devendo nada, o
    // local tem 0 tabela faltando e 100 colunas faltando em 25 tabelas.
    final c = ConferenciaEsquema(
      quando: DateTime.now(),
      totalLocal: 44,
      totalNuvem: 48,
      colunasFaltandoNoLocal: [
        const ColunaDivergente(tabela: 'empresas', coluna: 'nome_exibicao', tipoNuvem: 'text'),
        const ColunaDivergente(tabela: 'empresas', coluna: 'cor_primaria', tipoNuvem: 'text'),
        // Existe na nuvem, mas criá-la aqui faria o carregador filtrar a leitura
        // de `empresas` por ela (e a lista voltaria vazia). Não é criada sozinha.
        const ColunaDivergente(tabela: 'empresas', coluna: 'empresa_id', tipoNuvem: 'text'),
        const ColunaDivergente(tabela: 'clientes', coluna: 'celular', tipoNuvem: 'text'),
        const ColunaDivergente(tabela: 'nfces', coluna: 'chaveAcesso', tipoNuvem: 'text'),
        // Sensível: aparece no relatório, mas NÃO é criada automaticamente.
        const ColunaDivergente(tabela: 'usuarios', coluna: 'senha', tipoNuvem: 'text'),
      ],
    );

    final t = BackupRestoreService.trabalhosParaIgualarLocal(c);
    expect(t.tabelasNovas, isEmpty, reason: 'nenhuma tabela nova neste cenário');
    expect(t.colunasPorTabela.keys, ['empresas', 'clientes', 'nfces']);
    expect(t.colunasPorTabela['empresas'], ['cor_primaria', 'nome_exibicao']);
    expect(t.colunasPorTabela['usuarios'], isNull,
        reason: 'a coluna sensível não entra no trabalho automático');
    expect(c.decisaoFaltando, ['empresas.empresa_id']);
    expect(c.divergenciasReais, 4,
        reason: '6 divergências - 1 sensível - 1 de decisão = 4 pendências reais');
    expect(c.resumo, contains('precisam de decisão'));
    expect(c.relatorioTexto, contains('PRECISAM DE DECISÃO'));
    expect(BackupRestoreService.naoCriarSozinho('empresas.empresa_id'), isTrue);
    expect(BackupRestoreService.naoCriarSozinho('clientes.celular'), isFalse);

    // É essa lista que liga o botão — antes ele olhava só `somenteNaNuvem`
    // (vazio aqui) e não fazia nada.
    expect(BackupRestoreService.tabelasParaIgualarLocal(c),
        ['clientes', 'empresas', 'nfces']);

    // Só sobrar a coluna sensível = nada a criar (o app não mexe no login).
    final soSensivel = ConferenciaEsquema(
      quando: DateTime.now(),
      totalLocal: 44,
      totalNuvem: 48,
      colunasFaltandoNoLocal: const [
        ColunaDivergente(tabela: 'usuarios', coluna: 'senha', tipoNuvem: 'text'),
      ],
    );
    expect(BackupRestoreService.tabelasParaIgualarLocal(soSensivel), isEmpty);
    expect(soSensivel.divergenciasReais, 0);

    // Colunas duplicadas de `fechamentos_caixa` (aberturaCaixaId /
    // dataFechamento, camelCase): ANTES o app as apagava e elas voltavam a
    // faltar a cada start — o painel ficava amarelo para sempre. AGORA o app
    // REPARA (garante o tipo da nuvem e copia o valor da coluna snake_case),
    // então a conferência as trata como coluna comum: se faltarem de verdade,
    // são pendência e o botão do local tem o dever de criá-las.
    final reparadas = ConferenciaEsquema(
      quando: DateTime.now(),
      totalLocal: 44,
      totalNuvem: 48,
      colunasFaltandoNoLocal: const [
        ColunaDivergente(
            tabela: 'fechamentos_caixa',
            coluna: 'aberturaCaixaId',
            tipoNuvem: 'text'),
        ColunaDivergente(
            tabela: 'fechamentos_caixa',
            coluna: 'dataFechamento',
            tipoNuvem: 'timestamp with time zone'),
      ],
    );
    expect(reparadas.divergenciasReais, 2,
        reason: 'o app repara essas colunas — não há motivo para escondê-las');
    expect(BackupRestoreService.tabelasParaIgualarLocal(reparadas),
        ['fechamentos_caixa']);
    expect(
        BackupRestoreService.naoCriarSozinho(
            'fechamentos_caixa.aberturaCaixaId'),
        isFalse,
        reason: 'a coluna é reparada pelo app; quem cria é o botão do local');
    expect(BackupRestoreService.naoCriarSozinho('clientes.celular'), isFalse);

    // Tabela nova + coluna em tabela existente no mesmo trabalho.
    final misto = ConferenciaEsquema(
      quando: DateTime.now(),
      totalLocal: 44,
      totalNuvem: 48,
      somenteNaNuvem: const ['caixa'],
      colunasFaltandoNoLocal: const [
        ColunaDivergente(tabela: 'clientes', coluna: 'celular', tipoNuvem: 'text'),
      ],
    );
    expect(BackupRestoreService.tabelasParaIgualarLocal(misto), ['caixa', 'clientes']);
  });
}
