// Produto SEM perfil tributário usa o PADRÃO — e o vínculo precisa chegar ao
// banco LOCAL e à NUVEM.
//
// A regra escolhida é a que não reescreve o imposto do cadastro:
//   1. produto com código (CSOSN/CST) recebe o perfil PADRÃO daquele código;
//   2. produto sem código nenhum recebe o PADRÃO do regime;
//   3. código sem padrão equivalente (ex.: CSOSN 900) continua manual;
//   4. produto que JÁ tem perfil (inclusive personalizado) não é tocado.
//
// A última parte roda contra o PostgreSQL local de verdade, com uma empresa
// sintética: prova que `DataService.addProduto` e `addProdutosLote` gravam
// `perfil_tributario_id` junto com o produto (é o mesmo mapa que sobe para a
// nuvem).
//
// Rodar: flutter test test/produto_perfil_padrao_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/perfil_tributario.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';

const empresaTeste = 'EMPRESA-PERFIL-PADRAO-TESTE';

PerfilTributario perfilTributadoSimples() => PerfilTributario(
  id: 'padrao_tributado_simples',
  nome: 'Tributado (Simples Nacional)',
  cfop: '5102',
  csosn: '102',
  isDefault: true,
);

PerfilTributario perfilNaoTributadoSimples() => PerfilTributario(
  id: 'padrao_nao_tributado_simples',
  nome: 'Não Tributado (Simples Nacional)',
  cfop: '5102',
  csosn: '400',
);

PerfilTributario perfilSubstituicaoSimples() => PerfilTributario(
  id: 'padrao_substituicao_simples',
  nome: 'Substituição Tributária (Simples Nacional)',
  cfop: '5405',
  csosn: '500',
);

PerfilTributario perfilTributadoNormal() => PerfilTributario(
  id: 'padrao_tributado_normal',
  nome: 'Tributado (Regime Normal)',
  cfop: '5102',
  icmsCst: '00',
  isDefault: true,
);

PerfilTributario perfilNaoTributadoNormal() => PerfilTributario(
  id: 'padrao_nao_tributado_normal',
  nome: 'Não Tributado (Regime Normal)',
  cfop: '5102',
  icmsCst: '41',
);

PerfilTributario perfilSubstituicaoNormal() => PerfilTributario(
  id: 'padrao_substituicao_normal',
  nome: 'Substituição Tributária (Regime Normal)',
  cfop: '5405',
  icmsCst: '60',
);

List<PerfilTributario> perfisSimples() => [
  perfilTributadoSimples(),
  perfilNaoTributadoSimples(),
  perfilSubstituicaoSimples(),
];

List<PerfilTributario> perfisNormal() => [
  perfilTributadoNormal(),
  perfilNaoTributadoNormal(),
  perfilSubstituicaoNormal(),
];

Produto produto({
  required String id,
  String? csosn,
  String? icmsCst,
  String? perfilTributarioId,
  String? cfop,
  double preco = 10,
}) {
  final agora = DateTime(2026, 10, 23, 12);
  return Produto(
    id: id,
    empresaId: empresaTeste,
    nome: 'PRODUTO $id',
    unidade: 'UN',
    grupo: 'Teste',
    preco: preco,
    estoque: 5,
    createdAt: agora,
    updatedAt: agora,
    csosn: csosn,
    icmsCst: icmsCst,
    perfilTributarioId: perfilTributarioId,
    cfop: cfop,
  );
}

Empresa empresaComPerfis(List<PerfilTributario> perfis, {int crt = 1}) {
  return Empresa(
    id: empresaTeste,
    razaoSocial: 'Empresa Teste Perfil Padrão',
    slug: 'empresa-teste-perfil-padrao',
    crt: crt,
    createdAt: DateTime(2026, 10, 23),
    updatedAt: DateTime(2026, 10, 23),
    configuracoes: {
      // Desliga a nuvem neste teste: a gravação local continua de verdade, mas
      // nenhum upsert sai para o Neon.
      'nuvem_ativa': false,
      'perfis_tributarios': perfis.map((p) => p.toMap()).toList(),
    },
  );
}

Object? campo(Map<String, dynamic> linha, String camel, String snake) =>
    linha[camel] ?? linha[snake];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});

    // O DataService abre canais de plugin no construtor; em teste headless eles
    // não existem.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'plugins.flutter.io/path_provider',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(canal),
        (call) async => null,
      );
    }
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity_status',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockStreamHandler(
        EventChannel(canal),
        MockStreamHandler.inline(onListen: (args, sink) {}),
      );
    }

    // Nuvem desligada: os testes de persistência usam apenas o PostgreSQL local.
    NeonConfig.aplicarOverrides({
      'NEON_DATA_API_URL': '',
      'NEON_DATA_API_BASE_URL': '',
      'NEON_DATABASE_URL': '',
      'DATABASE_URL': '',
      'NEON_DATABASE_URL_UNPOOLED': '',
      'DATABASE_URL_UNPOOLED': '',
      'NEON_AUTH_BASE_URL': '',
      'NEON_AUTH_JWKS_URL': '',
      'NEON_FUNCTION_HELLO_BASE_URL': '',
      'NEON_FUNCTIONS_URL': '',
      'NEON_AWS_ENDPOINT_URL_S3': '',
      'AWS_ENDPOINT_URL_S3': '',
    });
  });

  group('produto sem perfil recebe o PADRÃO do regime', () {
    test('sem código nenhum: usa o padrão marcado do regime', () {
      final perfil = DataService.perfilPadraoParaProduto(
        perfisSimples(),
        paraSimples: true,
      );

      expect(perfil?.id, 'padrao_tributado_simples');
    });

    test('com CSOSN 102: usa o padrão do próprio código', () {
      final perfil = DataService.perfilPadraoParaProduto(
        perfisSimples(),
        paraSimples: true,
        csosn: '102',
      );

      expect(perfil?.id, 'padrao_tributado_simples');
    });

    test('com CSOSN 400: usa o padrão de NÃO tributado (não o tributado)', () {
      final perfil = DataService.perfilPadraoParaProduto(
        perfisSimples(),
        paraSimples: true,
        csosn: '400',
      );

      expect(
        perfil?.id,
        'padrao_nao_tributado_simples',
        reason: 'vincular o tributado mudaria o imposto do cadastro',
      );
    });

    test('com CST 00 no Regime Normal: usa o padrão normal', () {
      final perfil = DataService.perfilPadraoParaProduto(
        perfisNormal(),
        paraSimples: false,
        cst: '00',
      );

      expect(perfil?.id, 'padrao_tributado_normal');
    });

    test('CSOSN 900 (sem padrão equivalente) continua manual', () {
      final perfil = DataService.perfilPadraoParaProduto(
        perfisSimples(),
        paraSimples: true,
        csosn: '900',
      );

      expect(
        perfil,
        isNull,
        reason:
            'melhor continuar manual do que vincular um perfil que '
            'manda outro código',
      );
    });
  });

  group('produtoComPerfilTributarioPadrao preserva o cadastro', () {
    test('produto sem código ganha perfil + CFOP + CSOSN do padrão', () {
      final original = produto(id: 'SEM-CODIGO');
      final normalizado = DataService.produtoComPerfilTributarioPadrao(
        original,
        perfisSimples(),
        paraSimples: true,
      );

      expect(normalizado.perfilTributarioId, 'padrao_tributado_simples');
      expect(normalizado.cfop, '5102');
      expect(normalizado.csosn, '102');
      expect(
        original.perfilTributarioId,
        isNull,
        reason: 'o objeto original não é alterado',
      );
    });

    test('produto com código ganha só o vínculo (código e CFOP ficam)', () {
      final original = produto(id: 'COM-CODIGO', csosn: '400', cfop: '5405');
      final normalizado = DataService.produtoComPerfilTributarioPadrao(
        original,
        perfisSimples(),
        paraSimples: true,
      );

      expect(normalizado.perfilTributarioId, 'padrao_nao_tributado_simples');
      expect(normalizado.csosn, '400', reason: 'o código do cadastro manda');
      expect(
        normalizado.cfop,
        '5405',
        reason: 'o CFOP do cadastro é preservado',
      );
    });

    test('produto que JÁ tem perfil personalizado não é tocado', () {
      final original = produto(
        id: 'COM-PERFIL',
        csosn: '102',
        perfilTributarioId: 'meu_perfil',
      );
      final normalizado = DataService.produtoComPerfilTributarioPadrao(
        original,
        perfisSimples(),
        paraSimples: true,
      );

      expect(identical(normalizado, original), isTrue);
      expect(normalizado.perfilTributarioId, 'meu_perfil');
    });

    test(
      'o mapa do produto leva perfil_tributario_id (é o que sobe à nuvem)',
      () {
        final normalizado = DataService.produtoComPerfilTributarioPadrao(
          produto(id: 'MAPA-NUVEM'),
          perfisSimples(),
          paraSimples: true,
        );

        expect(
          normalizado.toMap()['perfil_tributario_id'],
          'padrao_tributado_simples',
          reason:
              'o upsert da nuvem usa este mesmo mapa; sem a chave o '
              'vínculo não chegaria ao Neon',
        );
      },
    );
  });

  group('no banco REAL: o padrão é persistido junto com o produto', () {
    final db = DatabaseService();
    const idProduto = 'PRODUTO-PERFIL-PADRAO-TESTE';
    const idLote = 'PRODUTO-PERFIL-PADRAO-LOTE';

    tearDown(() async {
      // O DataService enfileira o envio à nuvem mesmo quando ela está
      // desligada. Aqui a nuvem está desligada de propósito, mas a fila é
      // persistida no banco local: tira só as operações sintéticas deste teste
      // para não deixar lixo para o app tentar sincronizar depois.
      final fila = await db.carregarConfig('exodo_sync_queue');
      if (fila is List) {
        final restantes = fila
            .where(
              (op) =>
                  op is! Map ||
                  (op['data_id'] != idProduto && op['data_id'] != idLote),
            )
            .toList();
        if (restantes.length != fila.length) {
          await db.salvarConfig('exodo_sync_queue', restantes);
        }
      }

      await db.removerItemPostgres(
        LocalStorageService.keyProdutos,
        idProduto,
        empresaTeste,
        isSync: true,
      );
      await db.removerItemPostgres(
        LocalStorageService.keyProdutos,
        idLote,
        empresaTeste,
        isSync: true,
      );
      db.setEmpresaId('');
    });

    test('addProduto sem perfil grava o vínculo no PostgreSQL local', () async {
      final ds = DataService();
      addTearDown(ds.dispose);
      ds.setEmpresaAtual(empresaComPerfis(perfisSimples()));
      db.setEmpresaId(empresaTeste);

      await ds.addProduto(produto(id: idProduto), registrarHistorico: false);

      final linhas = await db.carregarLista(LocalStorageService.keyProdutos);
      final linha = linhas.firstWhere(
        (p) => p['id'] == idProduto,
        orElse: () => <String, dynamic>{},
      );

      expect(
        campo(linha, 'perfilTributarioId', 'perfil_tributario_id'),
        'padrao_tributado_simples',
        reason: 'sem o vínculo o produto voltaria a abrir "Sem Perfil"',
      );
      expect(campo(linha, 'csosn', 'csosn'), '102');
      expect(campo(linha, 'cfop', 'cfop'), '5102');
    });

    test('addProduto com perfil personalizado preserva o vínculo', () async {
      final ds = DataService();
      addTearDown(ds.dispose);
      ds.setEmpresaAtual(empresaComPerfis(perfisSimples()));
      db.setEmpresaId(empresaTeste);

      await ds.addProduto(
        produto(id: idProduto, perfilTributarioId: 'meu_perfil'),
        registrarHistorico: false,
      );

      final linhas = await db.carregarLista(LocalStorageService.keyProdutos);
      final linha = linhas.firstWhere(
        (p) => p['id'] == idProduto,
        orElse: () => <String, dynamic>{},
      );

      expect(
        campo(linha, 'perfilTributarioId', 'perfil_tributario_id'),
        'meu_perfil',
        reason: 'a regra só vale para produto SEM perfil',
      );
    });

    test('updateProduto sem perfil também grava o padrão', () async {
      final ds = DataService();
      addTearDown(ds.dispose);
      ds.setEmpresaAtual(empresaComPerfis(perfisSimples()));
      db.setEmpresaId(empresaTeste);

      // O produto entra com um perfil e depois é editado SEM perfil — é o
      // caminho de quem limpa o campo no formulário e salva.
      await ds.addProduto(
        produto(id: idProduto, perfilTributarioId: 'meu_perfil'),
        registrarHistorico: false,
      );
      await ds.updateProduto(
        produto(id: idProduto),
        registrarHistorico: false,
        notify: false,
      );

      final linhas = await db.carregarLista(LocalStorageService.keyProdutos);
      final linha = linhas.firstWhere(
        (p) => p['id'] == idProduto,
        orElse: () => <String, dynamic>{},
      );

      expect(
        campo(linha, 'perfilTributarioId', 'perfil_tributario_id'),
        'padrao_tributado_simples',
        reason: 'editar um produto sem perfil precisa devolver o padrão',
      );
    });

    test('addProdutosLote sem perfil também grava o padrão', () async {
      final ds = DataService();
      addTearDown(ds.dispose);
      ds.setEmpresaAtual(empresaComPerfis(perfisSimples()));
      db.setEmpresaId(empresaTeste);

      await ds.addProdutosLote([produto(id: idLote)]);

      final linhas = await db.carregarLista(LocalStorageService.keyProdutos);
      final linha = linhas.firstWhere(
        (p) => p['id'] == idLote,
        orElse: () => <String, dynamic>{},
      );

      expect(
        campo(linha, 'perfilTributarioId', 'perfil_tributario_id'),
        'padrao_tributado_simples',
      );
    });
  });
}
