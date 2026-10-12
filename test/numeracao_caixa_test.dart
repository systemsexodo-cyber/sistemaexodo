// Numeração por caixa: 'CX1-0001' no computador da frente e 'CX2-0001' no do
// fundo. É isso que impede dois PCs sem internet de emitirem o mesmo número de
// venda — cada prefixo é uma sequência independente.
//
// Cobre também o aviso de nome REPETIDO (dois computadores com o mesmo nome
// voltam a numerar igual): quem usa cada nome é lido das publicações que cada
// máquina grava em `sync_logs`.
//
// Rodar: flutter test test/numeracao_caixa_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/utils/identidade_caixa.dart';
import 'package:sistema_exodo_novo/utils/numeracao_venda.dart';
import 'package:sistema_exodo_novo/widgets/caixa_identidade_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // Sem plugin de verdade num teste headless: os canais do app (conectividade,
  // áudio, path_provider) precisam responder nada em vez de estourar.
  setUp(() {
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
  });

  group('separar / formatar', () {
    test('quebra o número no prefixo e na sequência', () {
      expect(NumeracaoVenda.separar('CX1-0003'), ('CX1', 3));
      expect(NumeracaoVenda.separar('VND-0433'), ('VND', 433));
      expect(NumeracaoVenda.separar('ped-0007'), ('PED', 7));
      expect(NumeracaoVenda.prefixoDe('CX10-0012'), 'CX10');
      expect(NumeracaoVenda.valorDe('CX10-0012'), 12);
    });

    test('número fora do formato não vira prefixo', () {
      expect(NumeracaoVenda.separar(''), isNull);
      expect(NumeracaoVenda.separar(null), isNull);
      expect(NumeracaoVenda.separar('123'), isNull);
      expect(NumeracaoVenda.separar('CX1-'), isNull);
      expect(NumeracaoVenda.separar('CX1-abc'), isNull);
      expect(NumeracaoVenda.separar('1CX-0001'), isNull);
    });

    test('formata com 4 dígitos e aceita sequências maiores', () {
      expect(NumeracaoVenda.formatar('cx1', 3), 'CX1-0003');
      expect(NumeracaoVenda.formatar('CX2', 12345), 'CX2-12345');
    });
  });

  group('normalizarCaixa', () {
    test('limpa o que o operador digita', () {
      expect(NumeracaoVenda.normalizarCaixa('cx 1'), 'CX1');
      expect(NumeracaoVenda.normalizarCaixa(' cx-2 '), 'CX2');
      expect(NumeracaoVenda.normalizarCaixa('loja1'), 'LOJA1');
    });

    test('recusa o que recriaria a colisão ou quebra o formato', () {
      expect(NumeracaoVenda.normalizarCaixa(''), isNull);
      expect(NumeracaoVenda.normalizarCaixa('PED'), isNull,
          reason: 'PED é do pedido tradicional');
      expect(NumeracaoVenda.normalizarCaixa('VND'), isNull,
          reason: 'VND é o prefixo das máquinas sem nome');
      expect(NumeracaoVenda.normalizarCaixa('123'), isNull,
          reason: 'precisa começar com letra');
      expect(NumeracaoVenda.normalizarCaixa('CAIXA1234'), isNull,
          reason: 'mais de 8 caracteres');
    });
  });

  group('nome de caixa repetido entre máquinas', () {
    /// Uma publicação como a nuvem a devolve em `sync_logs` (a lista chega do
    /// mais recente para o mais antigo).
    Map<String, dynamic> publicacao(String pc, String nome) =>
        {'pc_name': pc, 'detalhes': nome};

    test('o ÚLTIMO nome publicado de cada PC é o que vale', () {
      final ultimo = IdentidadeCaixa.ultimoNomePorPc([
        publicacao('PDV-B', 'CX2'), // o PDV-B foi renomeado para CX2
        publicacao('PDV-B', 'CX1'),
        publicacao('PDV-A', 'CX1'),
      ]);
      expect(ultimo, {'PDV-B': 'CX2', 'PDV-A': 'CX1'});
    });

    test('acha a outra máquina que está com o mesmo nome', () {
      final eventos = [
        publicacao('DESKTOP-1', 'CX1'),
        publicacao('PDV-B', 'CX1'),
      ];
      expect(
        IdentidadeCaixa.maquinasUsandoNome(
            eventos: eventos, meuPc: 'DESKTOP-1', nome: 'cx 1'),
        ['PDV-B'],
        reason: 'o nome digitado é normalizado e EU não conto como "outra"',
      );
    });

    test('nome já abandonado pela outra máquina não conta como repetido', () {
      final eventos = [
        publicacao('PDV-B', 'CX2'), // mais recente: já saiu do CX1
        publicacao('PDV-B', 'CX1'),
      ];
      expect(
        IdentidadeCaixa.maquinasUsandoNome(
            eventos: eventos, meuPc: 'DESKTOP-1', nome: 'CX1'),
        isEmpty,
      );
    });

    test('hostname em outra caixa de letras é o MESMO computador', () {
      // O Windows devolve o hostname em maiúsculas e a nuvem pode ter uma linha
      // antiga em minúsculas: as duas não podem virar "duas máquinas".
      final eventos = [publicacao('desktop-1', 'CX1')];
      expect(
        IdentidadeCaixa.maquinasUsandoNome(
            eventos: eventos, meuPc: 'DESKTOP-1', nome: 'CX1'),
        isEmpty,
      );
    });

    test('caixa sem nome publicado não ocupa prefixo nenhum', () {
      final eventos = [
        publicacao('PDV-B', ''), // mais recente: o operador apagou o nome
        publicacao('PDV-B', 'CX1'),
      ];
      expect(
        IdentidadeCaixa.maquinasUsandoNome(
            eventos: eventos, meuPc: 'DESKTOP-1', nome: 'CX1'),
        isEmpty,
      );
    });

    test('lista as máquinas em texto para o aviso na tela', () {
      expect(IdentidadeCaixa.listarMaquinas(const []), '');
      expect(IdentidadeCaixa.listarMaquinas(const ['PDV-A']), 'PDV-A');
      expect(
          IdentidadeCaixa.listarMaquinas(const ['PDV-A', 'PDV-B']), 'PDV-A e PDV-B');
      expect(IdentidadeCaixa.listarMaquinas(const ['PDV-A', 'PDV-B', 'PDV-C']),
          'PDV-A, PDV-B e PDV-C');
    });
  });

  group('venda do PDV x pedido tradicional', () {
    test('tudo o que não é PED- é venda do PDV', () {
      expect(NumeracaoVenda.ehVendaPdv('CX1-0003'), isTrue);
      expect(NumeracaoVenda.ehVendaPdv('CX2-0009'), isTrue);
      expect(NumeracaoVenda.ehVendaPdv('VND-0433'), isTrue);
      expect(NumeracaoVenda.ehVendaPdv('PED-0001'), isFalse);
      expect(NumeracaoVenda.ehVendaPdv(''), isFalse);
      expect(NumeracaoVenda.ehPedidoTradicional('PED-0042'), isTrue);
      expect(NumeracaoVenda.ehPedidoTradicional(''), isTrue,
          reason: 'pedido antigo sem número continua aparecendo na lista');
    });
  });

  group('próximo número livre', () {
    test('cada prefixo tem a própria sequência (offline nos dois PCs)', () {
      // O PC 1 já vendeu CX1-0001..0003 offline; o PC 2 começou do outro lado.
      final numeros = ['CX1-0001', 'CX1-0002', 'CX1-0003', 'CX2-0001'];

      expect(
        NumeracaoVenda.proximoNumeroLivre(numeros: numeros, prefixo: 'CX1'),
        4,
        reason: 'o CX1 segue do 3',
      );
      expect(
        NumeracaoVenda.proximoNumeroLivre(numeros: numeros, prefixo: 'CX2'),
        2,
        reason: 'o CX2 não é afetado pelas vendas do CX1',
      );
      // O caso que o sistema não podia resolver antes: os dois no 0003.
      expect(NumeracaoVenda.maiorDoPrefixo(numeros, 'CX1'), 3);
      expect(NumeracaoVenda.maiorDoPrefixo(numeros, 'CX2'), 1);
    });

    test('a sequência VND antiga não interfere no caixa novo', () {
      final numeros = ['VND-0433', 'PED-0077', 'CX1-0001'];
      expect(NumeracaoVenda.proximoNumeroLivre(numeros: numeros, prefixo: 'CX1'), 2);
      expect(NumeracaoVenda.proximoNumeroLivre(numeros: numeros, prefixo: 'VND'), 434);
      expect(NumeracaoVenda.proximoNumeroLivre(numeros: numeros, prefixo: 'PED'), 78);
    });

    test('piso segura a numeração quando a lista ainda não carregou', () {
      // App abrindo: lista vazia, mas o banco já sabe que CX1-0007 foi emitido.
      expect(
        NumeracaoVenda.proximoNumeroLivre(numeros: const [], prefixo: 'CX1', piso: 7),
        8,
      );
      expect(
        NumeracaoVenda.proximoNumeroLivre(numeros: const [], prefixo: 'CX1'),
        1,
      );
    });

    test('não repete um número já usado (nenhum buraco é reaproveitado por engano)',
        () {
      expect(
        NumeracaoVenda.proximoNumeroLivre(
          numeros: ['CX1-0001', 'CX1-0003'],
          prefixo: 'CX1',
        ),
        4,
      );
    });
  });

  group('número na observação do histórico', () {
    test('acha o número com o prefixo antigo e com o do caixa', () {
      expect(NumeracaoVenda.numeroNaObservacao('Venda VND-0168 - João'),
          'VND-0168');
      expect(NumeracaoVenda.numeroNaObservacao('Venda CX2-0007 - Maria'),
          'CX2-0007');
      expect(NumeracaoVenda.numeroNaObservacao('Entrada por nota 1234'), isNull);
      expect(NumeracaoVenda.numeroNaObservacao(''), isNull);
      expect(NumeracaoVenda.numeroNaObservacao(null), isNull);
    });
  });

  group('diálogo de identificação do caixa', () {
    /// Num teste headless não existe rede, banco nem o ciclo de sincronização:
    /// o que interessa é erro do FRAMEWORK em cima do diálogo.
    bool eRuido(Object? e) =>
        e == null ||
        '$e'.contains('overflowed') ||
        '$e'.contains('MissingPluginException') ||
        '$e'.contains('was used after being disposed') ||
        '$e'.contains('Cannot add to an unmodifiable list') ||
        '$e'.contains('Supabase');

    /// Drena os timers do DataService (sincronização) para o teste não terminar
    /// com "A Timer is still pending".
    Future<List<Object?>> drenar(WidgetTester tester, DataService service) async {
      final erros = <Object?>[tester.takeException()];
      await tester.pump(const Duration(seconds: 16));
      service.dispose();
      SyncMonitorService.instance.dispose();
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(minutes: 7));
        erros.add(tester.takeException());
      }
      return erros;
    }

    Future<void> abrir(WidgetTester tester, DataService service) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    mostrarDialogoIdentidadeDoCaixa(context, service),
                child: const Text('ABRIR'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ABRIR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('mostra o campo, o exemplo de numeração e o aviso sem nome',
        (tester) async {
      final service = DataService();
      await abrir(tester, service);

      expect(find.text('Identificação deste caixa'), findsOneWidget);
      expect(find.textContaining('geram o MESMO número de venda'), findsOneWidget,
          reason: 'sem nome o risco precisa estar na cara do usuário');
      expect(find.textContaining('VND-0001, VND-0002'), findsOneWidget);
      final erros = await drenar(tester, service);
      expect(erros.where((e) => !eRuido(e)), isEmpty);
    });

    testWidgets('o exemplo acompanha o nome digitado', (tester) async {
      final service = DataService();
      await abrir(tester, service);

      await tester.enterText(find.byType(TextField).first, 'cx 1');
      await tester.pump();

      expect(find.textContaining('CX1-0001, CX1-0002, CX1-0003'), findsOneWidget);
      final erros = await drenar(tester, service);
      expect(erros.where((e) => !eRuido(e)), isEmpty);
    });

    testWidgets('nome reservado (PED) é recusado com explicação', (tester) async {
      final service = DataService();
      await abrir(tester, service);

      await tester.enterText(find.byType(TextField).first, 'PED');
      await tester.pump();
      await tester.tap(find.text('SALVAR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('PED e VND são reservados'), findsOneWidget);
      expect(find.text('Identificação deste caixa'), findsOneWidget,
          reason: 'o diálogo não pode fechar com um nome inválido');
      final erros = await drenar(tester, service);
      expect(erros.where((e) => !eRuido(e)), isEmpty);
    });

    testWidgets('CANCELAR fecha sem gravar nada', (tester) async {
      final service = DataService();
      await abrir(tester, service);

      await tester.enterText(find.byType(TextField).first, 'CX9');
      await tester.pump();
      await tester.tap(find.text('CANCELAR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Identificação deste caixa'), findsNothing);
      expect(service.nomeDoCaixa, isEmpty);
      final erros = await drenar(tester, service);
      expect(erros.where((e) => !eRuido(e)), isEmpty);
    });
  });
}
