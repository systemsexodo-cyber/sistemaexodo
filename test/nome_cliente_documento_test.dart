// Edição do nome do cliente na lista "Pedidos".
//
// A lista mistura PEDIDOS e VENDAS DE BALCÃO: o card de uma venda é um `Pedido`
// temporário montado em `_buscarPedidos` (lib/pages/pdv_page.dart). Quando a
// edição do nome gravava sempre em `pedidos`, o nome de uma venda (ex.:
// CAIXA1-0006) não era salvo — nada mudava e, ao reabrir, o nome antigo voltava.
//
// Rodar: flutter test test/nome_cliente_documento_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';

final _empresa = Empresa(
  id: 'E-NOME-CLIENTE',
  razaoSocial: 'Loja Teste Nome',
  slug: 'loja-teste-nome',
  createdAt: DateTime(2026, 11, 3),
  updatedAt: DateTime(2026, 11, 3),
);

VendaBalcao _venda({String? clienteNome}) => VendaBalcao(
  id: 'VENDA-1',
  numero: 'CAIXA1-0006',
  dataVenda: DateTime(2026, 11, 3, 23, 32),
  clienteNome: clienteNome,
  itens: [
    ItemVendaBalcao(
      id: 'ITEM-1',
      nome: 'COPAO MASTER GOLD 700ML',
      precoUnitario: 9,
      quantidade: 1,
    ),
  ],
  tipoPagamento: TipoPagamento.outro,
  valorTotal: 9,
);

Pedido _pedido({String? clienteNome}) => Pedido(
  id: 'PEDIDO-1',
  numero: 'CAIXA1-0007',
  clienteNome: clienteNome,
  dataPedido: DateTime(2026, 11, 3, 23, 40),
  produtos: [ItemPedido(id: 'ITEM-2', nome: 'Ração', quantidade: 1, preco: 10)],
  servicos: const [],
);

/// Card que o PDV monta para uma venda de balcão na lista "Pedidos".
Pedido _cardDaVenda(VendaBalcao venda) => Pedido(
  id: venda.id,
  numero: venda.numero,
  clienteId: venda.clienteId,
  clienteNome: venda.clienteNome,
  dataPedido: venda.dataVenda,
  status: 'Pendente',
  total: venda.valorTotal,
  produtos: const [],
  servicos: const [],
  pagamentos: venda.pagamentos,
);

DataService _dataService() {
  final ds = DataService();
  ds.setEmpresaAtual(_empresa);
  return ds;
}

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
      messenger.setMockMethodCallHandler(MethodChannel(canal), (call) async {
        if (call.method == 'create') return 1;
        if (call.method == 'check') return <String>['wifi'];
        return null;
      });
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
    EnvConfig.aplicarOverrides({
      'DB_HOST': 'banco-de-teste.invalid',
      'DB_HOST_FALLBACK': '',
      'DB_CLOUD_HOST': '',
    });
    NeonConfig.aplicarOverrides({
      'NEON_DATA_API_URL': '',
      'NEON_DATA_API_BASE_URL': '',
      'NEON_DATABASE_URL': '',
      'DATABASE_URL': '',
      'NEON_DATABASE_URL_UNPOOLED': '',
      'DATABASE_URL_UNPOOLED': '',
      'NEON_AUTH_BASE_URL': '',
      'NEON_AUTH_JWKS_URL': '',
    });
  });

  test(
    'grava o nome na VENDA quando o card da lista é uma venda de balcão',
    () async {
      final ds = _dataService();
      final venda = _venda(clienteNome: 'yago');
      await ds.addVendaBalcao(venda);

      final salvo = await ds.atualizarNomeClienteDocumento(
        _cardDaVenda(venda),
        nome: 'yago zika',
      );

      expect(salvo, isNotNull);
      expect(salvo!.clienteNome, 'yago zika');
      expect(
        ds.vendasBalcao.single.clienteNome,
        'yago zika',
        reason: 'o nome tem de ser gravado na venda, que é o documento real',
      );
      expect(
        ds.pedidos,
        isEmpty,
        reason: 'não pode criar um pedido fantasma para a venda',
      );

      ds.dispose();
    },
  );

  test('grava o nome no PEDIDO quando o card é um pedido de verdade', () async {
    final ds = _dataService();
    final pedido = _pedido(clienteNome: 'yago');
    await ds.addPedido(pedido);

    final salvo = await ds.atualizarNomeClienteDocumento(
      pedido,
      nome: 'yago zika',
    );

    expect(salvo, isNotNull);
    expect(ds.pedidos.single.clienteNome, 'yago zika');
    expect(ds.vendasBalcao, isEmpty);

    ds.dispose();
  });

  test('nome vazio limpa o cliente dos dois tipos de documento', () async {
    final ds = _dataService();
    final venda = _venda(clienteNome: 'yago');
    final pedido = _pedido(clienteNome: 'yago');
    await ds.addVendaBalcao(venda);
    await ds.addPedido(pedido);

    await ds.atualizarNomeClienteDocumento(_cardDaVenda(venda), nome: '');
    await ds.atualizarNomeClienteDocumento(pedido, nome: '');

    expect(ds.vendasBalcao.single.clienteNome, isNull);
    expect(ds.pedidos.single.clienteNome, isNull);

    ds.dispose();
  });

  test(
    'documento inexistente devolve null (a tela avisa em vez de mentir)',
    () async {
      final ds = _dataService();

      final salvo = await ds.atualizarNomeClienteDocumento(
        _cardDaVenda(_venda(clienteNome: 'yago')),
        nome: 'yago zika',
      );

      expect(salvo, isNull);

      ds.dispose();
    },
  );
}
