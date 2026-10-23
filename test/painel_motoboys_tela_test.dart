// Teste de TELA do painel de motoboys: comissão por entrega + total + filtros +
// desfazer o "Entregue".
//
// Pedido do balcão: "no filtro de entregas já entregues do motoboy, a opção de
// ver o valor de cada comissão e o total, com filtro por motoboy e entrega" e
// "opção de tirar entregue e colocar como não entregue para não contabilizar na
// comissão".
//
// Aqui o DataService é um dublê em memória (não toca no PostgreSQL), então o
// teste roda sem banco nenhum.
//
// Rodar: flutter test test/painel_motoboys_tela_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/delivery_info.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/pages/painel_motoboys_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';

/// DataService só de memória: nada de banco local nem nuvem.
class _DataServiceFake extends DataService {
  _DataServiceFake({
    required this.pedidosFake,
    required this.motoristasFake,
    required this.entregasFake,
  });

  final List<Pedido> pedidosFake;
  final List<Motorista> motoristasFake;
  final List<Entrega> entregasFake;

  final List<Pedido> pedidosGravados = [];
  final List<Entrega> entregasGravadas = [];

  /// Quantas vezes a tela pediu a gravação imediata (sem esperar o debounce).
  int persistenciaForcada = 0;

  @override
  List<Pedido> get pedidos => pedidosFake;

  @override
  List<Motorista> get motoristas => motoristasFake;

  @override
  List<Entrega> get entregas => entregasFake;

  @override
  Future<void> updatePedido(Pedido pedido) async {
    pedidosGravados.add(pedido);
    final i = pedidosFake.indexWhere((p) => p.id == pedido.id);
    if (i != -1) pedidosFake[i] = pedido;
    notifyListeners();
  }

  @override
  Future<void> updateEntrega(Entrega entrega) async {
    entregasGravadas.add(entrega);
    final i = entregasFake.indexWhere((e) => e.id == entrega.id);
    if (i != -1) entregasFake[i] = entrega;
    notifyListeners();
  }

  @override
  Future<void> addEntrega(Entrega entrega) async {
    entregasGravadas.add(entrega);
    entregasFake.add(entrega);
  }

  /// No app real isto grava as linhas pendentes no PostgreSQL local. No dublê
  /// só registra a chamada: o teste confere que a tela NÃO deixa a alteração
  /// dependendo do debounce.
  @override
  Future<void> persistirAlteracoesPendentes() async {
    persistenciaForcada++;
  }
}

Pedido _pedido({
  required String id,
  required String numero,
  required Motorista? motorista,
  required String statusEntrega,
  double taxa = 0.0,
}) {
  return Pedido(
    id: id,
    numero: numero,
    clienteNome: 'Cliente $numero',
    status: 'Concluído',
    produtos: const [],
    servicos: const [],
    deliveryInfo: DeliveryInfo(
      id: 'd-$id',
      enderecoId: '',
      logradouro: 'Rua Teste',
      numero: '10',
      bairro: 'Centro',
      cidade: 'Cidade',
      uf: 'SP',
      taxaEntrega: taxa,
      status: statusEntrega,
      motoristaId: motorista?.id,
      motoristaNome: motorista?.nome,
    ),
  );
}

void main() {
  setUp(() {
    // Plugins de plataforma (connectivity/audioplayers/path_provider/
    // shared_preferences) não existem num teste headless e não têm relação com
    // o painel — sem isso eles derrubam o teste com MissingPluginException.
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
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['none'] : null,
    );
  });

  testWidgets(
    'painel: comissão por entrega, total, filtro por entrega e desfazer o entregue',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final volneizao = Motorista(
        id: 'm1',
        nome: 'volneizão',
        tipoComissao: 'Fixo por Entrega',
        valorComissao: 10.0,
      );
      final maria = Motorista(
        id: 'm2',
        nome: 'Maria',
        tipoComissao: 'Porcentagem',
        valorComissao: 50.0,
      );

      // PED-0151 (volneizão, ENTREGUE, taxa 8 → comissão 10)
      // PED-0150 (volneizão, em rota, taxa 8 → previsão 10)
      // PED-0149 (Maria, ENTREGUE, taxa 20 → comissão 10)
      final p1 = _pedido(
        id: 'p1',
        numero: 'PED-0151',
        motorista: volneizao,
        statusEntrega: 'Entregue',
        taxa: 8,
      );
      final p2 = _pedido(
        id: 'p2',
        numero: 'PED-0150',
        motorista: volneizao,
        statusEntrega: 'Saiu para entrega',
        taxa: 8,
      );
      final p3 = _pedido(
        id: 'p3',
        numero: 'PED-0149',
        motorista: maria,
        statusEntrega: 'Entregue',
        taxa: 20,
      );

      final dataService = _DataServiceFake(
        pedidosFake: [p1, p2, p3],
        motoristasFake: [volneizao, maria],
        entregasFake: [],
      );

      // `carregarAutomaticamente: false`: o teste não quer o boot do
      // AuthService (banco/nuvem) atrás da tela.
      final authService = AuthService(carregarAutomaticamente: false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DataService>.value(value: dataService),
            ChangeNotifierProvider<AuthService>.value(value: authService),
            ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
          ],
          child: const MaterialApp(home: PainelMotoboysPage()),
        ),
      );
      await tester.pump();

      // Sem "Ver Entregues" as entregues ficam fora da lista.
      expect(find.text('PED-0151'), findsNothing);
      expect(find.text('PED-0150'), findsOneWidget);

      // ── Liga o filtro "Ver Entregues" ────────────────────────────────
      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.text('PED-0151'), findsOneWidget);
      expect(find.text('PED-0150'), findsOneWidget);
      expect(find.text('PED-0149'), findsOneWidget);

      // Comissão de CADA entrega aparece no card.
      expect(find.textContaining('Comissão:'), findsWidgets);
      expect(find.textContaining('Prevista:'), findsOneWidget);

      // TOTAL: 10 (PED-0151) + 10 (PED-0149); a em rota não conta.
      expect(find.text('Comissões (entregues)'), findsOneWidget);
      expect(find.textContaining('20,00'), findsWidgets);
      expect(find.textContaining('2 entrega(s)'), findsWidgets);

      // Total do grupo do volneizão só considera o que está entregue.
      expect(find.textContaining('previsto'), findsWidgets);

      // ── Filtro por ENTREGA (busca) ───────────────────────────────────
      await tester.enterText(find.byType(TextField), 'PED-0149');
      await tester.pump();

      // O nome do cliente só existe dentro do card (o texto da busca não conta).
      expect(find.textContaining('Cliente PED-0149'), findsOneWidget);
      expect(find.textContaining('Cliente PED-0151'), findsNothing);
      expect(find.textContaining('Cliente PED-0150'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      // ── Filtro por MOTOBOY (dropdown) ────────────────────────────────
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Maria').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Cliente PED-0149'), findsOneWidget);
      expect(find.textContaining('Cliente PED-0151'), findsNothing);
      expect(find.textContaining('Cliente PED-0150'), findsNothing);

      // Volta para "Todos os motoboys".
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Todos os motoboys').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Cliente PED-0151'), findsOneWidget);
      expect(find.textContaining('Cliente PED-0150'), findsOneWidget);

      // ── Desfazer o "Entregue" ────────────────────────────────────────
      final botaoNaoEntregue = find.text('Não entregue');
      expect(botaoNaoEntregue, findsNWidgets(2)); // PED-0151 e PED-0149

      await tester.tap(botaoNaoEntregue.first);
      await tester.pump();

      final salvo = dataService.pedidosGravados.last;
      expect(salvo.id, 'p1');
      expect(salvo.deliveryInfo!.status, 'Saiu para entrega');
      expect(salvo.deliveryInfo!.dataEntrega, isNull);

      // A ENTREGA também volta para "Em Entrega" (é o que tira da comissão
      // na tela de Comissões).
      final entregaReaberta = dataService.entregasGravadas.last;
      expect(entregaReaberta.pedidoId, 'p1');
      expect(entregaReaberta.status, StatusEntrega.emEntrega);

      // A gravação foi forçada na hora (não ficou esperando o debounce, que é
      // o que fazia a entrega "voltar a não entregue" ao reabrir a tela).
      expect(dataService.persistenciaForcada, greaterThan(0));

      // E o TOTAL cai na hora: PED-0151 saiu da conta (sobrou só a Maria,
      // R$ 10,00), e o card dele passa a mostrar previsão em vez de comissão.
      await tester.pump();
      expect(find.textContaining('1 entrega(s) •'), findsOneWidget);
      expect(find.textContaining('Prevista:'), findsNWidgets(2));

      // ignore: avoid_print
      print('OK: painel mostra comissões, total, filtros e desfaz o entregue');

      // O AuthService/DataService abrem conexão com o banco/nuvem e agendam
      // timeouts de segurança; sem drenar isso o flutter_test acusa "A Timer is
      // still pending" (nada a ver com a tela).
      await tester.pump(const Duration(seconds: 16));
      dataService.dispose();
      // Timer periódico de 2 min do monitor de sync (aberto pelo DataService).
      SyncMonitorService.instance.dispose();
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(minutes: 7));
        tester.takeException();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
