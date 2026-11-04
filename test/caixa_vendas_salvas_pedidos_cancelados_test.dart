// Vendas salvas, pedidos em aberto e pedidos cancelados NÃO entram no caixa.
//
// O bug que este teste trava (é o caminho real do operador):
//   1. uma venda salva (guardada para receber depois) aparecia no Fluxo de
//      Caixa e no saldo como se o dinheiro já tivesse entrado;
//   2. o "restante" de uma divisão de conta virava UM PEDIDO junto com a
//      venda salva — a mesma venda existia duas vezes (venda + pedido gêmeo);
//   3. cancelar o pedido não tirava o valor do caixa, porque a venda gêmea
//      continuava ativa.
//
// Regras travadas aqui:
//   - `VendaBalcao.ehVendaSalva` marca a venda guardada (valorRecebido == 0 e
//     nenhum pagamento recebido);
//   - `getVendasDoCaixa` (fonte do saldo, do card por forma, do Fluxo de Caixa
//     e do fechamento) não devolve venda salva;
//   - `calcularRecebimentosDePedidosDoCaixa` ignora pedido cancelado (e pedido
//     em aberto, sem pagamento recebido, já era ignorado);
//   - `cancelarPedido` cancela também a venda gêmea (mesmo id/número).
//
// O teste roda com o banco local APONTADO PARA UM HOST INVÁLIDO de propósito:
// ele exercita a memória do DataService sem tocar no PostgreSQL de verdade.
//
// Rodar: flutter test test/caixa_vendas_salvas_pedidos_cancelados_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';

Empresa _empresa() => Empresa(
  id: 'EMPRESA-CAIXA-VENDA-SALVA-TESTE',
  razaoSocial: 'Empresa Teste Venda Salva',
  slug: 'empresa-teste-venda-salva',
  createdAt: DateTime(2026, 10, 28),
  updatedAt: DateTime(2026, 10, 28),
);

AberturaCaixa _abertura({
  String responsavel = 'carlos@exodo.com',
  DateTime? inicio,
}) =>
    AberturaCaixa(
      id: 'ab-1',
      numero: 'CX1-0001',
      dataAbertura: inicio ?? DateTime(2026, 10, 27, 8),
      valorInicial: 0,
      responsavel: responsavel,
    );

VendaBalcao _venda({
  required String id,
  required double total,
  double? valorRecebido,
  List<PagamentoPedido> pagamentos = const [],
  TipoPagamento tipo = TipoPagamento.dinheiro,
  DateTime? dataVenda,
  String operador = 'carlos@exodo.com',
}) =>
    VendaBalcao(
      id: id,
      numero: 'VND-$id',
      dataVenda: dataVenda ?? DateTime(2026, 10, 27, 9),
      itens: const [],
      tipoPagamento: tipo,
      pagamentos: pagamentos,
      valorTotal: total,
      valorRecebido: valorRecebido,
      operador: operador,
    );

PagamentoPedido _pagamento({
  required String id,
  required double valor,
  TipoPagamento tipo = TipoPagamento.dinheiro,
  DateTime? recebidoEm,
}) =>
    PagamentoPedido(
      id: id,
      tipo: tipo,
      valor: valor,
      recebido: recebidoEm != null,
      dataRecebimento: recebidoEm,
    );

Pedido _pedido({
  required String id,
  String status = 'Pendente',
  List<PagamentoPedido> pagamentos = const [],
  DateTime? dataPedido,
  String operador = 'carlos@exodo.com',
}) =>
    Pedido(
      id: id,
      numero: 'PED-$id',
      dataPedido: dataPedido ?? DateTime(2026, 10, 27, 9),
      status: status,
      vendedorNome: operador,
      produtos: const [],
      servicos: const [],
      pagamentos: pagamentos,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/shared_preferences',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), (call) async => null);
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

    // Sem banco real: só a lógica em memória (host .invalid não resolve).
    EnvConfig.aplicarOverrides({
      'DB_HOST': 'banco-de-teste.invalid',
      'DB_HOST_FALLBACK': '',
      'DB_CLOUD_HOST': '',
    });
    // Sem chamadas reais à nuvem no construtor do DataService.
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

  test('venda salva não entra no caixa (nem no saldo nem no resumo por forma)', () {
    final ds = DataService();
    addTearDown(ds.dispose);
    final ab = _abertura();
    ds.aberturasCaixa.add(ab);

    // Venda salva: guardada para receber depois (valorRecebido 0, sem pagamento).
    ds.vendasBalcao.add(_venda(id: '1', total: 42, valorRecebido: 0));
    // Venda finalizada: dinheiro de verdade no caixa.
    ds.vendasBalcao.add(
      _venda(
        id: '2',
        total: 20,
        valorRecebido: 20,
        pagamentos: [_pagamento(id: 'p2', valor: 20, recebidoEm: DateTime(2026, 10, 27, 9))],
      ),
    );
    // Venda antiga gravada sem controle de recebimento: continua contando.
    ds.vendasBalcao.add(_venda(id: '3', total: 30));

    expect(
      ds.getVendasDoCaixa(ab).map((v) => v.numero).toList(),
      ['VND-2', 'VND-3'],
      reason: 'a venda salva (VND-1) não pode aparecer no caixa',
    );
    expect(ds.calcularSaldoDoCaixa(ab), 50);
    expect(ds.calcularResumoFormaPagamentoDoCaixa(ab).length, 1);
    expect(
      ds.calcularResumoFormaPagamentoDoCaixa(ab).first.valor,
      50,
      reason: 'só o que foi recebido entra no card de entradas por forma',
    );
  });

  test('venda salva vira venda normal quando o PDV recebe o valor', () {
    final venda = _venda(id: '7', total: 42, valorRecebido: 0);
    expect(venda.ehVendaSalva, isTrue);

    final recebida = venda.copyWith(
      valorRecebido: 42,
      pagamentos: [
        _pagamento(id: 'p7', valor: 42, recebidoEm: DateTime(2026, 10, 27, 10)),
      ],
    );
    expect(recebida.ehVendaSalva, isFalse);
  });

  test('pedido cancelado não entra no caixa, mesmo com pagamento recebido', () {
    final ds = DataService();
    addTearDown(ds.dispose);
    final ab = _abertura();
    ds.aberturasCaixa.add(ab);

    ds.pedidos.add(
      _pedido(
        id: '1',
        pagamentos: [
          _pagamento(id: 'p1', valor: 999, recebidoEm: DateTime(2026, 10, 27, 10)),
        ],
      ),
    );
    ds.pedidos.add(
      _pedido(
        id: '2',
        status: 'Cancelado',
        pagamentos: [
          _pagamento(id: 'p2', valor: 42, recebidoEm: DateTime(2026, 10, 27, 10)),
        ],
      ),
    );
    // Pedido em aberto (nada recebido) também não entra.
    ds.pedidos.add(_pedido(id: '3'));

    final totais = ds.calcularRecebimentosDePedidosDoCaixa(ab);
    expect(totais.length, 1);
    expect(totais[TipoPagamento.dinheiro], 999);
  });

  test('cancelar um pedido cancela a venda gêmea e tira o valor do caixa', () async {
    final ds = DataService();
    addTearDown(ds.dispose);
    ds.setEmpresaAtual(_empresa());
    final ab = _abertura();
    ds.aberturasCaixa.add(ab);

    // O pedido pago gera a VendaBalcao com o MESMO id (é a mesma venda).
    final pagamentos = [
      _pagamento(id: 'p1', valor: 42, recebidoEm: DateTime(2026, 10, 27, 10)),
    ];
    ds.pedidos.add(_pedido(id: 'gemeo-1', pagamentos: pagamentos));
    ds.vendasBalcao.add(
      _venda(
        id: 'gemeo-1',
        total: 42,
        valorRecebido: 42,
        pagamentos: pagamentos,
      ),
    );

    expect(ds.calcularSaldoDoCaixa(ab), 42);

    await ds.cancelarPedido('gemeo-1', motivo: 'cliente desistiu');

    expect(ds.calcularSaldoDoCaixa(ab), 0,
        reason: 'cancelar o pedido tem de tirar o valor da venda gêmea do caixa');
    expect(ds.calcularRecebimentosDePedidosDoCaixa(ab), isEmpty);
    final venda = ds.vendasBalcao.firstWhere((v) => v.id == 'gemeo-1');
    expect(venda.isCancelada, isTrue);
  });
}
