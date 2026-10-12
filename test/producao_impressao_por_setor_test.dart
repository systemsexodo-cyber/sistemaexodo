// IMPRESSÃO DE PRODUÇÃO POR SETOR — fim a fim (até o canal da impressora).
//
// O teste puro em `producao_destinos_por_setor_test.dart` trava a RESOLUÇÃO
// (quantos setores, em qual impressora). Aqui travamos o que realmente sai na
// impressora: a contagem de trabalhos enviados ao canal `net.nfet.printing` e o
// nome de cada trabalho ('Producao_<documento>_<SETOR>'), que é o que prova
// "saiu um em cada setor de produção".
//
// Caso relatado: no diálogo "Editar Produto" → IMPRESSÃO DE PRODUÇÃO, os 3
// setores (Cozinha, Bar, Doce) estavam marcados e todos apontavam para a mesma
// impressora ("Microsoft Print to PDF"). Antes saía UMA via só, porque a
// resolução guardava as impressoras num Set pelo NOME — os 3 setores colapsavam
// em 1. Agora sai uma via por setor.
//
// Rodar: flutter test test/producao_impressao_por_setor_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/produto_form.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/producao_pdf_service.dart';

const _canalPrinting = MethodChannel('net.nfet.printing');

const _pdf = 'Microsoft Print to PDF';
const _impCozinha = 'Impressora Cozinha';
const _impBar = 'Impressora Bar';
const _impDoce = 'Impressora Doce';

/// Impressoras "instaladas" no PC de teste (o kanal do plugin é mockado).
const _impressorasDoSistema = <Map<String, Object>>[
  {
    'name': _pdf,
    'url': 'winspool://MS_PDF',
    'default': true,
    'available': true,
  },
  {
    'name': _impCozinha,
    'url': 'winspool://COZINHA',
    'default': false,
    'available': true,
  },
  {
    'name': _impBar,
    'url': 'winspool://BAR',
    'default': false,
    'available': true,
  },
  {
    'name': _impDoce,
    'url': 'winspool://DOCE',
    'default': false,
    'available': true,
  },
];

Map<String, Object?> _dep(String id, String nome, String? impressora) => {
      'id': id,
      'nome': nome,
      'impressora_producao': impressora,
      'impressora_producao_extra': <String>[],
    };

Empresa _empresa(List<Map<String, Object?>> departamentos) => Empresa(
      id: 'EMPRESA-TESTE-PRODUCAO',
      razaoSocial: 'Loja Teste Produção',
      slug: 'loja-teste-producao',
      createdAt: DateTime(2026, 10, 6),
      updatedAt: DateTime(2026, 10, 6),
      configuracoes: {'departamentos': departamentos},
    );

Produto _produto({
  String? departamentoId,
  List<String> adicionais = const [],
}) =>
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

/// Monta o DataService já com a empresa (departamentos vindos de
/// `configuracoes['departamentos']`, como no app) e o produto da venda.
DataService _dataServiceCom({
  required List<Map<String, Object?>> departamentos,
  required Produto produto,
}) {
  final ds = DataService();
  ds.setEmpresaAtual(_empresa(departamentos));
  ds.produtos.add(produto);
  return ds;
}

/// Mock do canal da impressora: registra cada trabalho enviado e responde ao
/// plugin como a plataforma faria (job concluído), para `directPrintPdf`
/// devolver true sem abrir diálogo nativo.
void _mockImpressao(List<Map<dynamic, dynamic>> enviados) {
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
        return _impressorasDoSistema;
      case 'printPdf':
        final args = Map<dynamic, dynamic>.from(call.arguments as Map);
        enviados.add(args);
        // Avisa o plugin que o job terminou (é o que a plataforma faz).
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<dynamic, dynamic>> enviados;

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
    enviados = <Map<dynamic, dynamic>>[];
    _mockImpressao(enviados);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalPrinting, null);
  });

  test('3 setores marcados, TODOS na mesma impressora → 3 vias (uma por setor)',
      () async {
    final ds = _dataServiceCom(
      departamentos: [
        _dep('dep_cozinha', 'Cozinha', _pdf),
        _dep('dep_bar', 'Bar', _pdf),
        _dep('dep_doce', 'Doce', _pdf),
      ],
      // Igual ao cadastro da captura: nenhum departamento principal, os 3
      // setores marcados como extras.
      produto:
          _produto(adicionais: ['dep_cozinha', 'dep_bar', 'dep_doce']),
    );

    final impressos = await ProducaoPdfService.imprimirTicketsProducao(
      itens: const [
        ItemProducaoInput(id: 'P1', nome: 'X-Burger', quantidade: 1),
      ],
      dataService: ds,
      empresa: ds.empresaAtual!,
      numeroDocumento: 'PED-1',
    );
    ds.dispose();

    expect(impressos, 3,
        reason: 'era para sair um em cada setor de produção, não uma via só');
    expect(
      enviados.map((e) => '${e['name']}').toList(),
      [
        'Producao_PED-1_Cozinha',
        'Producao_PED-1_Bar',
        'Producao_PED-1_Doce',
      ],
      reason: 'uma via por SETOR, cada uma com o setor no nome',
    );
    expect(enviados.map((e) => '${e['printer']}').toSet(),
        {'winspool://MS_PDF'},
        reason: 'os 3 setores estão na mesma impressora');
    expect(enviados, hasLength(3));
  });

  test('cada setor sai na impressora do seu departamento', () async {
    final ds = _dataServiceCom(
      departamentos: [
        _dep('dep_cozinha', 'Cozinha', _impCozinha),
        _dep('dep_bar', 'Bar', _impBar),
        _dep('dep_doce', 'Doce', _impDoce),
      ],
      produto: _produto(
        departamentoId: 'dep_cozinha',
        adicionais: ['dep_bar', 'dep_doce'],
      ),
    );

    final impressos = await ProducaoPdfService.imprimirTicketsProducao(
      itens: const [
        ItemProducaoInput(id: 'P1', nome: 'X-Burger', quantidade: 2),
      ],
      dataService: ds,
      empresa: ds.empresaAtual!,
      numeroDocumento: 'PED-2',
    );
    ds.dispose();

    expect(impressos, 3);
    expect(
      {for (final e in enviados) '${e['name']}': '${e['printer']}'},
      {
        'Producao_PED-2_Cozinha': 'winspool://COZINHA',
        'Producao_PED-2_Bar': 'winspool://BAR',
        'Producao_PED-2_Doce': 'winspool://DOCE',
      },
    );
  });

  test('setor sem impressora configurada cai na padrão do terminal',
      () async {
    final ds = _dataServiceCom(
      departamentos: [_dep('dep_bar', 'Bar', null)],
      produto: _produto(departamentoId: 'dep_bar'),
    );

    final impressos = await ProducaoPdfService.imprimirTicketsProducao(
      itens: const [
        ItemProducaoInput(id: 'P1', nome: 'Refri', quantidade: 1),
      ],
      dataService: ds,
      empresa: ds.empresaAtual!,
      numeroDocumento: 'PED-3',
    );
    ds.dispose();

    expect(impressos, 1);
    expect(enviados.single['name'], 'Producao_PED-3_Bar');
    expect(enviados.single['printer'], 'winspool://MS_PDF',
        reason: 'sem impressora no setor, sai na padrão do Windows');
  });

  testWidgets(
      'a seção IMPRESSÃO DE PRODUÇÃO mostra a impressora de cada setor e a via de cada um',
      (tester) async {
    final ds = _dataServiceCom(
      departamentos: [
        _dep('dep_cozinha', 'Cozinha', _pdf),
        _dep('dep_bar', 'Bar', _impBar),
        _dep('dep_doce', 'Doce', _impDoce),
      ],
      produto: _produto(adicionais: ['dep_cozinha', 'dep_bar', 'dep_doce']),
    );

    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DataService>.value(value: ds),
          ChangeNotifierProvider<AuthService>.value(value: AuthService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ProdutoServicoForm(
              item: ds.produtos.single,
              onSave: (p) async {},
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    // A seção "Departamento e Impressora" fica na aba Básico (aberta por padrão).

    // Cada chip mostra o setor E a impressora que recebe a via dele.
    expect(find.text('Cozinha'), findsOneWidget);
    expect(find.text('Bar'), findsOneWidget);
    expect(find.text('Doce'), findsOneWidget);
    expect(find.text(_pdf), findsOneWidget, reason: 'impressora do setor Cozinha');
    expect(find.text(_impBar), findsOneWidget, reason: 'impressora do setor Bar');
    expect(find.text(_impDoce), findsOneWidget, reason: 'impressora do setor Doce');

    // E a lista "Vai imprimir em:" mostra uma via por setor (3 no total).
    expect(find.text('Vai imprimir em:'), findsOneWidget);
    expect(find.text('• Cozinha → $_pdf'), findsOneWidget);
    expect(find.text('• Bar → $_impBar'), findsOneWidget);
    expect(find.text('• Doce → $_impDoce'), findsOneWidget);

    // Drena os timers de rede/banco do DataService e confere que a tela não
    // soltou exceção de verdade (só o ruído esperado de teste headless).
    final erros = <Object?>[tester.takeException()];
    await tester.pump(const Duration(seconds: 16));
    ds.dispose();
    SyncMonitorService.instance.dispose();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(minutes: 7));
      erros.add(tester.takeException());
    }
    final problemas = erros
        .where((e) => e != null)
        .map((e) => '$e')
        .where((e) =>
            !e.contains('overflowed') &&
            !e.contains('MissingPluginException') &&
            !e.contains('was used after being disposed') &&
            !e.contains('Cannot add to an unmodifiable list'))
        .toList();
    expect(problemas, isEmpty, reason: 'a seção não pode soltar exceção');
  });

  test('TESTAR IMPRESSÃO DE PRODUÇÃO manda uma via por setor', () async {
    final ds = _dataServiceCom(
      departamentos: [
        _dep('dep_cozinha', 'Cozinha', _pdf),
        _dep('dep_bar', 'Bar', _pdf),
        _dep('dep_doce', 'Doce', _pdf),
      ],
      produto: _produto(),
    );

    final impressos = await ProducaoPdfService.imprimirTicketTeste(
      empresa: ds.empresaAtual!,
      dataService: ds,
      destinos: const [
        DestinoProducao(setor: 'Cozinha', impressora: _pdf),
        DestinoProducao(setor: 'Bar', impressora: _pdf),
        DestinoProducao(setor: 'Doce', impressora: _pdf),
      ],
    );
    ds.dispose();

    expect(impressos, 3);
    expect(
      enviados.map((e) => '${e['name']}').toList(),
      [
        'Teste_Producao_Cozinha',
        'Teste_Producao_Bar',
        'Teste_Producao_Doce',
      ],
    );
  });
}
