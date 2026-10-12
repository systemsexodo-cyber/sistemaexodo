// MONITOR DE PRODUÇÃO — fila das vias que NÃO saíram na impressora do setor.
//
// Cenário real: o lançamento manda uma via para cada setor (Cozinha, Bar, ...).
// Se a impressora do setor está desligada ou foi renomeada, a via não sai — e
// até agora o app só contava as que deram certo: a cozinha ficava sem o ticket
// e ninguém percebia. Aqui fica travado que:
//
//   1. via que sai na impressora do setor NÃO entra na fila;
//   2. impressora do setor indisponível (a via acaba na padrão do terminal)
//      entra na fila, com o motivo;
//   3. a mesma via não duplica — tentativa nova só soma e troca o motivo;
//   4. com a impressora de volta, a REIMPRESSÃO tira a via da fila;
//   5. reimpressão que falha de novo mantém a via (mais uma tentativa);
//   6. a fila separa por SETOR: dá para reimprimir só o setor que falhou;
//   7. descartar tira a via; a fila sobrevive ao reinício e é por empresa.
//
// Rodar: flutter test test/monitor_producao_fila_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/ticket_producao.dart';
import 'package:sistema_exodo_novo/pages/monitor_producao_page.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/fila_producao_service.dart';
import 'package:sistema_exodo_novo/services/producao_pdf_service.dart';

const _canalPrinting = MethodChannel('net.nfet.printing');
const _pdf = 'Microsoft Print to PDF';
const _impCozinha = 'Impressora Cozinha';
const _impBar = 'Impressora Bar';

/// Impressoras "instaladas" neste terminal — muda de teste para teste, para
/// simular a impressora do setor desligada/desinstalada.
late List<Map<String, Object>> _instaladas;
late List<Map<dynamic, dynamic>> _enviados;

Map<String, Object> _impressora(String nome, String url, {bool padrao = false}) =>
    {
      'name': nome,
      'url': url,
      'default': padrao,
      'available': true,
    };

Map<String, Object?> _dep(String id, String nome, String? impressora) => {
      'id': id,
      'nome': nome,
      'impressora_producao': impressora,
      'impressora_producao_extra': <String>[],
    };

Empresa _empresa(List<Map<String, Object?>> departamentos) => Empresa(
      id: 'EMPRESA-FILA-PRODUCAO',
      razaoSocial: 'Loja Teste Fila',
      slug: 'loja-teste-fila',
      createdAt: DateTime(2026, 10, 6),
      updatedAt: DateTime(2026, 10, 6),
      configuracoes: {'departamentos': departamentos},
    );

Produto _produto({String? departamentoId, List<String> adicionais = const []}) =>
    Produto(
      id: 'P1',
      nome: 'X-Burger',
      unidade: 'un',
      grupo: 'Teste',
      preco: 25,
      estoque: 10,
      departamentoId: departamentoId,
      departamentosAdicionais: adicionais,
      createdAt: DateTime(2026, 10, 6),
      updatedAt: DateTime(2026, 10, 6),
    );

DataService _dataService({
  required List<Map<String, Object?>> departamentos,
  Produto? produto,
}) {
  final ds = DataService();
  ds.setEmpresaAtual(_empresa(departamentos));
  if (produto != null) ds.produtos.add(produto);
  return ds;
}

void _mockImpressao() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_canalPrinting, (call) async {
    switch (call.method) {
      case 'printingInfo':
        return <String, Object>{
          'canPrint': true,
          'canListPrinters': true,
          'directPrint': true,
        };
      case 'listPrinters':
        return _instaladas;
      case 'printPdf':
        final args = Map<dynamic, dynamic>.from(call.arguments as Map);
        _enviados.add(args);
        await messenger.handlePlatformMessage(
          _canalPrinting.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onCompleted', <String, dynamic>{
              'job': args['job'],
              'completed': true,
            }),
          ),
          (_) {},
        );
        return args['job'];
      default:
        return null;
    }
  });
}

/// Imprime a venda/pedido pelos setores configurados no produto.
Future<int> _imprimir(
  DataService ds,
  FilaProducaoService fila, {
  String documento = 'PED-1',
  String? setorForcado,
}) {
  return ProducaoPdfService.imprimirTicketsProducao(
    itens: const [ItemProducaoInput(id: 'P1', nome: 'X-Burger', quantidade: 1)],
    dataService: ds,
    empresa: ds.empresaAtual!,
    numeroDocumento: documento,
    setorForcado: setorForcado,
    fila: fila,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Future<Object?> nulo(MethodCall call) async => null;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/shared_preferences',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), nulo);
    }
    _instaladas = [
      _impressora(_pdf, 'winspool://MS_PDF', padrao: true),
      _impressora(_impCozinha, 'winspool://COZINHA'),
      _impressora(_impBar, 'winspool://BAR'),
    ];
    _enviados = <Map<dynamic, dynamic>>[];
    _mockImpressao();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalPrinting, null);
  });

  group('fila de produção', () {
    test('via que sai na impressora do setor NÃO entra na fila', () async {
      final fila = FilaProducaoService.paraTeste();
      final ds = _dataService(
        departamentos: [_dep('dep_cozinha', 'Cozinha', _impCozinha)],
        produto: _produto(departamentoId: 'dep_cozinha'),
      );

      final impressos = await _imprimir(ds, fila);
      ds.dispose();

      expect(impressos, 1);
      expect(fila.pendentes, isEmpty);
      expect(_enviados.single['printer'], 'winspool://COZINHA');
    });

    test('impressora do setor indisponível: a via entra na fila com o motivo',
        () async {
      // A impressora da cozinha "sumiu" do Windows.
      _instaladas = [_impressora(_pdf, 'winspool://MS_PDF', padrao: true)];

      final fila = FilaProducaoService.paraTeste();
      final ds = _dataService(
        departamentos: [_dep('dep_cozinha', 'Cozinha', _impCozinha)],
        produto: _produto(departamentoId: 'dep_cozinha'),
      );

      await _imprimir(ds, fila);
      ds.dispose();

      expect(fila.pendentes, hasLength(1),
          reason: 'a cozinha ficou sem a via — tem de estar na fila');
      final via = fila.pendentes.single;
      expect(via.setor, 'Cozinha');
      expect(via.impressora, _impCozinha);
      expect(via.documento, 'PED-1');
      expect(via.tentativas, 1);
      expect(via.ultimoErro, contains('não encontrada'));
      expect(via.resumoItens, ['1x X-Burger'],
          reason: 'a via guarda os itens para poder ser reimpressa');
      expect(via.payloadItens, isNotEmpty);
    });

    test('a mesma via não duplica: nova tentativa só soma e troca o motivo',
        () async {
      // A impressora da cozinha continua fora do ar nas duas tentativas.
      _instaladas = [_impressora(_pdf, 'winspool://MS_PDF', padrao: true)];

      final fila = FilaProducaoService.paraTeste();
      final ds = _dataService(
        departamentos: [_dep('dep_cozinha', 'Cozinha', _impCozinha)],
        produto: _produto(departamentoId: 'dep_cozinha'),
      );

      await _imprimir(ds, fila, documento: 'PED-7');
      await _imprimir(ds, fila, documento: 'PED-7');
      ds.dispose();

      expect(fila.pendentes, hasLength(1));
      expect(fila.pendentes.single.tentativas, 2);
    });

    test('com a impressora de volta, REIMPRIMIR tira a via da fila', () async {
      _instaladas = [_impressora(_pdf, 'winspool://MS_PDF', padrao: true)];

      final fila = FilaProducaoService.paraTeste();
      final ds = _dataService(
        departamentos: [_dep('dep_cozinha', 'Cozinha', _impCozinha)],
        produto: _produto(departamentoId: 'dep_cozinha'),
      );
      await _imprimir(ds, fila);
      expect(fila.pendentes, hasLength(1));

      // A impressora da cozinha voltou.
      _instaladas = [
        _impressora(_pdf, 'winspool://MS_PDF', padrao: true),
        _impressora(_impCozinha, 'winspool://COZINHA'),
      ];
      final pendente = fila.pendentes.single;
      final ok = await ProducaoPdfService.reimprimirTicket(
        ticket: pendente,
        empresa: ds.empresaAtual!,
        fila: fila,
      );
      ds.dispose();

      expect(ok, isTrue);
      expect(fila.pendentes, isEmpty, reason: 'a via saiu: sai da fila');
      expect(_enviados.last['printer'], 'winspool://COZINHA');
    });

    test('reimpressão que falha de novo mantém a via com mais uma tentativa',
        () async {
      // Sem impressora nenhuma instalada: a via não sai mesmo.
      _instaladas = <Map<String, Object>>[];

      final fila = FilaProducaoService.paraTeste();
      final ds = _dataService(
        departamentos: [_dep('dep_cozinha', 'Cozinha', _impCozinha)],
        produto: _produto(departamentoId: 'dep_cozinha'),
      );
      await _imprimir(ds, fila);
      expect(fila.pendentes, hasLength(1));
      expect(fila.pendentes.single.ultimoErro, contains('Nenhuma impressora'));

      final ok = await ProducaoPdfService.reimprimirTicket(
        ticket: fila.pendentes.single,
        empresa: ds.empresaAtual!,
        fila: fila,
      );
      ds.dispose();

      expect(ok, isFalse);
      expect(fila.pendentes, hasLength(1));
      expect(fila.pendentes.single.tentativas, 2);
    });

    test('a fila separa por SETOR — dá para reimprimir só o que falhou',
        () async {
      // A cozinha tem impressora; o bar não.
      _instaladas = [
        _impressora(_pdf, 'winspool://MS_PDF', padrao: true),
        _impressora(_impCozinha, 'winspool://COZINHA'),
      ];

      final fila = FilaProducaoService.paraTeste();
      final ds = _dataService(
        departamentos: [
          _dep('dep_cozinha', 'Cozinha', _impCozinha),
          _dep('dep_bar', 'Bar', _impBar),
        ],
        produto: _produto(
          departamentoId: 'dep_cozinha',
          adicionais: ['dep_bar'],
        ),
      );

      await _imprimir(ds, fila);
      ds.dispose();

      expect(fila.pendentesDoSetor('Cozinha'), isEmpty,
          reason: 'a cozinha imprimiu: não pode aparecer como pendente');
      expect(fila.contarDoSetor('Bar'), 1);
      expect(fila.pendentes.single.setor, 'Bar');
      expect(fila.pendentes.single.ultimoErro, contains(_impBar));
    });

    test('descartar tira a via da fila sem imprimir', () async {
      _instaladas = [_impressora(_pdf, 'winspool://MS_PDF', padrao: true)];

      final fila = FilaProducaoService.paraTeste();
      final ds = _dataService(
        departamentos: [_dep('dep_cozinha', 'Cozinha', _impCozinha)],
        produto: _produto(departamentoId: 'dep_cozinha'),
      );
      await _imprimir(ds, fila);
      final id = fila.pendentes.single.id;

      await fila.descartar(id);
      ds.dispose();

      expect(fila.pendentes, isEmpty);
    });

    test('a fila é por empresa', () async {
      final fila = FilaProducaoService.paraTeste();
      fila.initialize(empresaId: 'EMPRESA-1');
      await fila.registrarFalha(TicketProducao(
        id: 'x',
        documento: 'PED-1',
        setor: 'Cozinha',
        impressora: _impCozinha,
        ultimoErro: 'sem papel',
      ));
      expect(fila.pendentes, hasLength(1));

      fila.initialize(empresaId: 'EMPRESA-2');
      await fila.carregar();
      expect(fila.pendentes, isEmpty,
          reason: 'a fila do outro CNPJ não pode aparecer aqui');

      fila.initialize(empresaId: 'EMPRESA-1');
      await fila.carregar();
      expect(fila.pendentes, hasLength(1));
    });

    test('a fila sobrevive ao reinício do app (persistência)', () async {
      final primeira = FilaProducaoService.paraTeste();
      await primeira.registrarFalha(TicketProducao(
        id: 'a|cozinha',
        documento: 'PED-9',
        tipoDocumento: 'PEDIDO DELIVERY',
        setor: 'Cozinha',
        impressora: _impCozinha,
        resumoItens: const ['2x X-Burger'],
        ultimoErro: 'impressora desligada',
        payloadItens: const [
          {'id': 'P1', 'nome': 'X-Burger', 'quantidade': 2.0},
        ],
      ));

      // "Reinício": instância nova lendo o que ficou guardado.
      final depois = FilaProducaoService.paraTeste();
      await depois.carregar();

      expect(depois.pendentes, hasLength(1));
      final via = depois.pendentes.single;
      expect(via.documento, 'PED-9');
      expect(via.tipoDocumento, 'PEDIDO DELIVERY');
      expect(via.resumoItens, ['2x X-Burger']);
      expect(via.payloadItens.single['nome'], 'X-Burger');
    });
  });

  group('tela Monitor de Produção', () {
    testWidgets('mostra a via pendente com o setor, a impressora e o motivo',
        (tester) async {
      // Estado da fila do terminal: uma via do Bar não saiu.
      final fila = FilaProducaoService.instancia;
      fila.initialize(empresaId: '');
      await fila.registrarFalha(TicketProducao(
        id: 'ped-1|bar',
        documento: 'PED-1',
        tipoDocumento: 'PEDIDO DE PRODUÇÃO',
        setor: 'Bar',
        impressora: _impBar,
        referencia: 'MESA 5',
        resumoItens: const ['1x Coca-Cola'],
        ultimoErro: 'Impressora "$_impBar" não encontrada',
      ));

      final ds = _dataService(departamentos: [
        _dep('dep_cozinha', 'Cozinha', _impCozinha),
        _dep('dep_bar', 'Bar', _impBar),
      ]);

      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider<DataService>.value(
          value: ds,
          child: const MaterialApp(home: MonitorProducaoPage()),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // A aba do setor mostra quantas vias estão pendentes (a Cozinha, que
      // imprimiu, fica limpa) + o total no topo.
      expect(find.text('Cozinha'), findsOneWidget);
      expect(find.text('Bar (1)'), findsOneWidget);
      expect(find.text('Todos (1)'), findsOneWidget);
      expect(find.text('1 pendente'), findsOneWidget);

      // Vai para a aba do Bar, que é a que falhou.
      await tester.tap(find.text('Bar (1)'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      // O card traz o que o operador precisa para decidir.
      expect(find.text('PEDIDO DE PRODUÇÃO'), findsWidgets);
      expect(find.text('Nº PED-1'), findsWidgets);
      expect(find.text('• 1x Coca-Cola'), findsWidgets);
      expect(find.text('Impressora: $_impBar'), findsWidgets);
      expect(find.text('Impressora "$_impBar" não encontrada'), findsWidgets);
      expect(find.text('REIMPRIMIR'), findsWidgets);
      expect(find.textContaining('via(s) não saíram na impressora'),
          findsWidgets);

      await tester.pump(const Duration(seconds: 16));
      await fila.descartarDoSetor('Bar');
      ds.dispose();
    });
  });
}
