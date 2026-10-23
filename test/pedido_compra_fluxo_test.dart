// Fluxo completo do pedido de compra, do relatório de reposição até a entrada
// no estoque.
//
// O que este teste trava (é o caminho que o operador usa de verdade):
//   1. o relatório salva UM pedido por fornecedor, com numeração PC-0001;
//   2. o selo "JÁ PEDIDO" do produto nasce do pedido em aberto e cai quando
//      ele é recebido/cancelado/excluído (não fica mais preso no cadastro);
//   3. enviar mantém o pedido em aberto;
//   4. receber parcialmente soma a quantidade no produto, no saldo por
//      fornecedor, no saldo por estoque e no histórico — e deixa o restante
//      pendente;
//   5. receber o resto fecha o pedido, atualiza o custo e libera o selo;
//   6. pedido recebido não pode ser recebido de novo nem cancelado;
//   7. cancelar e excluir pedidos em aberto limpam o selo sem mexer no estoque.
//
// O teste roda com o banco local APONTADO PARA UM HOST INVÁLIDO de propósito:
// assim ele exercita a memória do DataService (a mesma usada pela tela) sem
// tocar no PostgreSQL/Neon de verdade.
//
// Rodar: flutter test test/pedido_compra_fluxo_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/pedido_compra.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';

Empresa _empresa() => Empresa(
  id: 'EMPRESA-PEDIDO-COMPRA-TESTE',
  razaoSocial: 'Empresa Teste Pedido de Compra',
  slug: 'empresa-teste-pedido-compra',
  createdAt: DateTime(2026, 10, 22),
  updatedAt: DateTime(2026, 10, 22),
  configuracoes: {
    'estoques': [
      {'id': 'estoque_loja', 'nome': 'Loja', 'principal': true, 'ordem': 0},
      {
        'id': 'estoque_deposito',
        'nome': 'Depósito',
        'principal': false,
        'ordem': 1,
      },
    ],
  },
);

Produto _produto({
  required String id,
  required String nome,
  required double estoque,
  required String fornecedor,
  double custo = 0,
}) => Produto(
  id: id,
  nome: nome,
  unidade: 'UN',
  grupo: 'Teste',
  preco: custo * 2,
  precoCusto: custo,
  estoque: estoque,
  estoquePorEstoque: {'estoque_deposito': estoque},
  estoquePadraoId: 'estoque_deposito',
  fornecedorNome: fornecedor,
  createdAt: DateTime(2026, 10, 22),
  updatedAt: DateTime(2026, 10, 22),
);

ItemPedidoCompra _item(
  Produto produto,
  double quantidade, {
  double custo = 0,
}) => ItemPedidoCompra(
  id: '',
  produtoId: produto.id,
  produtoNome: produto.nome,
  unidade: produto.unidade,
  quantidade: quantidade,
  precoCusto: custo,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});

    // O DataService abre canais de plugin no construtor. Em teste headless eles
    // não existem: sem os mocks o construtor quebra antes de qualquer asserção.
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

    // Nada de banco real: o teste é da lógica em memória. O host .invalid não
    // resolve, então a gravação local falha na hora (e é engolida pelo próprio
    // DataService) em vez de escrever no banco de produção.
    EnvConfig.aplicarOverrides({
      'DB_HOST': 'banco-de-teste.invalid',
      'DB_HOST_FALLBACK': '',
      'DB_CLOUD_HOST': '',
    });

    // O construtor do DataService pinga a nuvem para saber se está online.
    // Sem desligar a nuvem aqui, o teste faria chamadas reais ao Neon (e o
    // token seria recusado pelo ambiente de teste, derrubando a suíte).
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

  test('pedido por fornecedor: criar, enviar, receber parcial, receber tudo', () async {
    final ds = DataService();
    addTearDown(ds.dispose);
    ds.setEmpresaAtual(_empresa());

    final racao = _produto(
      id: 'prod-racao',
      nome: 'Ração Premium',
      estoque: 10,
      fornecedor: 'Fornecedor A',
      custo: 5,
    );
    final brinquedo = _produto(
      id: 'prod-brinquedo',
      nome: 'Brinquedo',
      estoque: 0,
      fornecedor: 'Fornecedor A',
      custo: 2,
    );
    await ds.addProduto(racao, registrarHistorico: false);
    await ds.addProduto(brinquedo, registrarHistorico: false);

    // ── 1. O relatório salva um pedido por fornecedor ──────────────────────
    final criados = await ds.criarPedidosCompraPorFornecedor(
      itensPorFornecedor: {
        'Fornecedor A': [_item(racao, 5, custo: 5), _item(brinquedo, 3, custo: 2)],
      },
      usuario: 'Operador Teste',
    );

    expect(criados, hasLength(1));
    final pedido = criados.single;
    expect(pedido.numero, 'PC-0001');
    expect(pedido.status, StatusPedidoCompra.rascunho);
    expect(pedido.itens, hasLength(2));
    expect(pedido.itens.every((item) => item.id.isNotEmpty), isTrue,
        reason: 'item sem id não pode ser recebido depois');
    expect(
      pedido.itens.map((item) => item.id).toSet(),
      hasLength(2),
      reason: 'dois itens com o mesmo id fariam o recebimento mexer no item errado',
    );
    expect(pedido.valorTotal, 5 * 5 + 3 * 2);
    expect(ds.pedidoCompraPorId(pedido.id), isNotNull);

    // O selo é derivado do pedido em aberto, não de um campo digitado à mão.
    expect(ds.produtos.firstWhere((p) => p.id == racao.id).pedidoCompraGerado, isTrue);
    expect(ds.produtos.firstWhere((p) => p.id == brinquedo.id).pedidoCompraGerado, isTrue);

    // ── 2. Enviar ao fornecedor ────────────────────────────────────────────
    await ds.marcarPedidoCompraEnviado(pedido.id);
    var atual = ds.pedidoCompraPorId(pedido.id)!;
    expect(atual.status, StatusPedidoCompra.enviado);
    expect(atual.dataEnvio, isNotNull);
    expect(atual.emAberto, isTrue);
    expect(ds.produtos.firstWhere((p) => p.id == racao.id).pedidoCompraGerado, isTrue,
        reason: 'enviado ainda não é recebido: continua marcado como "JÁ PEDIDO"');

    // ── 3. Recebimento parcial ─────────────────────────────────────────────
    final historicoAntes = ds.estoqueHistorico.length;
    final itemRacao = atual.itens.firstWhere((i) => i.produtoId == racao.id);
    final itemBrinquedo = atual.itens.firstWhere((i) => i.produtoId == brinquedo.id);

    final parcial = await ds.receberPedidoCompra(
      pedidoId: pedido.id,
      quantidadesPorItem: {itemRacao.id: 2},
      usuario: 'Operador Teste',
    );

    expect(parcial.pedido.status, StatusPedidoCompra.recebidoParcial);
    expect(parcial.completo, isFalse);
    expect(parcial.itensRecebidos, 1);
    expect(parcial.quantidadeRecebida, 2);

    var racaoAtual = ds.produtos.firstWhere((p) => p.id == racao.id);
    var brinquedoAtual = ds.produtos.firstWhere((p) => p.id == brinquedo.id);
    expect(racaoAtual.estoque, 12, reason: 'receber 2 de 10 tem que somar no total');
    expect(racaoAtual.estoquePorFornecedor['Fornecedor A'], 2);
    expect(racaoAtual.estoquePorEstoque['estoque_deposito'], 12);
    expect(brinquedoAtual.estoque, 0, reason: 'item não recebido não pode mexer no estoque');

    expect(ds.estoqueHistorico.length, historicoAntes + 1);
    final movimento = ds.estoqueHistorico.last;
    expect(movimento.produtoId, racao.id);
    expect(movimento.quantidade, 2);
    expect(movimento.tipo, 'entrada');
    expect(movimento.fornecedorNome, 'Fornecedor A');
    expect(movimento.observacao, contains('PC-0001'));

    // Ainda falta receber: o selo continua.
    expect(ds.produtos.firstWhere((p) => p.id == racao.id).pedidoCompraGerado, isTrue);
    expect(atual.itens.firstWhere((i) => i.id == itemBrinquedo.id).quantidadePendente, 3);

    // ── 4. Receber o restante (mapa vazio = receber tudo que falta) ────────
    final completo = await ds.receberPedidoCompra(
      pedidoId: pedido.id,
      usuario: 'Operador Teste',
    );

    expect(completo.pedido.status, StatusPedidoCompra.recebido);
    expect(completo.completo, isTrue);
    expect(completo.itensRecebidos, 2);
    expect(completo.quantidadeRecebida, 6, reason: 'faltavam 3 + 3');
    expect(completo.pedido.dataRecebimento, isNotNull);

    racaoAtual = ds.produtos.firstWhere((p) => p.id == racao.id);
    brinquedoAtual = ds.produtos.firstWhere((p) => p.id == brinquedo.id);
    expect(racaoAtual.estoque, 15);
    expect(brinquedoAtual.estoque, 3);
    expect(racaoAtual.estoquePorFornecedor['Fornecedor A'], 5);
    expect(brinquedoAtual.estoquePorFornecedor['Fornecedor A'], 3);
    expect(racaoAtual.estoquePorEstoque['estoque_deposito'], 15);
    expect(brinquedoAtual.estoquePorEstoque['estoque_deposito'], 3);

    // Pedido fechado: o selo cai sozinho.
    expect(racaoAtual.pedidoCompraGerado, isFalse);
    expect(brinquedoAtual.pedidoCompraGerado, isFalse);

    // ── 5. Pedido recebido é imutável ──────────────────────────────────────
    await expectLater(
      ds.receberPedidoCompra(pedidoId: pedido.id),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      ds.cancelarPedidoCompra(pedido.id, motivo: 'teste'),
      throwsA(isA<StateError>()),
    );
    expect(ds.pedidoCompraPorId(pedido.id)!.status, StatusPedidoCompra.recebido);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('editar rascunho, cancelar e excluir recalculam o selo sem mexer no estoque', () async {
    final ds = DataService();
    addTearDown(ds.dispose);
    ds.setEmpresaAtual(_empresa());

    final produto = _produto(
      id: 'prod-editado',
      nome: 'Produto Editado',
      estoque: 4,
      fornecedor: 'Fornecedor B',
      custo: 1,
    );
    await ds.addProduto(produto, registrarHistorico: false);

    final pedido = await ds.criarPedidoCompra(
      fornecedorNome: 'Fornecedor B',
      itens: [_item(produto, 2)],
    );
    expect(pedido.numero, 'PC-0001');
    expect(pedido.status, StatusPedidoCompra.rascunho);

    // Edição: novo item entra sem id (como o formulário cria) e recebe id único.
    final novoItem = _item(produto, 1, custo: 1);
    final editado = pedido.copyWith(itens: [...pedido.itens, novoItem]);
    await ds.atualizarPedidoCompra(editado);

    final depoisDaEdicao = ds.pedidoCompraPorId(pedido.id)!;
    expect(depoisDaEdicao.itens, hasLength(2));
    expect(depoisDaEdicao.itens.map((i) => i.id).toSet(), hasLength(2));
    expect(depoisDaEdicao.quantidadeTotal, 3);
    expect(ds.produtos.single.estoque, 4, reason: 'editar pedido não movimenta estoque');

    // Cancelamento: some do "JÁ PEDIDO" e não lança nada no histórico.
    final historicoAntes = ds.estoqueHistorico.length;
    await ds.cancelarPedidoCompra(pedido.id, motivo: 'Fornecedor sem estoque');
    final cancelado = ds.pedidoCompraPorId(pedido.id)!;
    expect(cancelado.status, StatusPedidoCompra.cancelado);
    expect(cancelado.motivoCancelamento, 'Fornecedor sem estoque');
    expect(cancelado.dataCancelamento, isNotNull);
    expect(cancelado.podeReceber, isFalse);
    expect(ds.produtos.single.pedidoCompraGerado, isFalse);
    expect(ds.estoqueHistorico.length, historicoAntes);
    expect(ds.produtos.single.estoque, 4);

    // Exclusão: o pedido sai da lista e o selo continua limpo.
    await ds.deletePedidoCompra(pedido.id);
    expect(ds.pedidoCompraPorId(pedido.id), isNull);
    expect(ds.produtos.single.pedidoCompraGerado, isFalse);
    expect(ds.produtos.single.estoque, 4);

    // Numeração não volta atrás por causa de um pedido excluído.
    final proximo = await ds.criarPedidoCompra(
      fornecedorNome: 'Fornecedor B',
      itens: [_item(produto, 1)],
    );
    expect(proximo.numero, 'PC-0001',
        reason: 'a série é derivada dos pedidos existentes; o excluído liberou o número');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('recebimento atualiza o custo combinado e registra o destino', () async {
    final ds = DataService();
    addTearDown(ds.dispose);
    ds.setEmpresaAtual(_empresa());

    final produto = _produto(
      id: 'prod-custo',
      nome: 'Produto Custo',
      estoque: 0,
      fornecedor: 'Fornecedor C',
      custo: 3,
    );
    await ds.addProduto(produto, registrarHistorico: false);

    final pedido = await ds.criarPedidoCompra(
      fornecedorNome: 'Fornecedor C',
      itens: [_item(produto, 2, custo: 7.5)],
      estoqueDestinoId: 'estoque_deposito',
      estoqueDestinoNome: 'Depósito',
    );

    final resultado = await ds.receberPedidoCompra(pedidoId: pedido.id);
    expect(resultado.completo, isTrue);

    final atualizado = ds.produtos.single;
    expect(atualizado.precoCusto, 7.5);
    expect(atualizado.estoque, 2);
    expect(atualizado.estoquePorEstoque['estoque_deposito'], 2);
    expect(ds.pedidoCompraPorId(pedido.id)!.estoqueDestinoNome, 'Depósito');
    expect(ds.pedidoCompraPorId(pedido.id)!.itens.single.precoCusto, 7.5);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
