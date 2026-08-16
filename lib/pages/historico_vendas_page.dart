import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import '../services/data_service.dart';
import '../models/venda_balcao.dart';
import '../models/pedido.dart';
import '../models/forma_pagamento.dart';
import '../models/troca_devolucao.dart';
import '../models/caixa.dart';
import '../models/mesa_comanda.dart';
import '../models/nfce.dart';
import '../models/conta_pagar.dart';
import '../models/produto.dart';
import '../models/estoque_historico.dart';
import '../services/nfce_service_factory.dart';
import '../services/danfe_service.dart';
import 'trocas_devolucoes_page.dart';
import 'home_page.dart';
import 'package:printing/printing.dart';
import '../widgets/sync_status_widget.dart';
import '../widgets/historico_nfce_pdv_dialog.dart';
import '../services/auth_service.dart';
import '../widgets/permission_widget.dart';
import '../services/caixa_pdf_service.dart';
import '../services/venda_pdf_service.dart';
import '../services/pedido_pdf_service.dart';

class _ProdutoVendido {
  final String nome;
  final String? produtoId;
  int quantidadeTotal = 0;
  double valorTotal = 0.0;
  double? custoTotal;
  String abc = 'C';
  List<_VendaProduto> vendas = [];
  _ProdutoVendido({required this.nome, this.produtoId});

  double get lucroTotal => valorTotal - (custoTotal ?? 0.0);

  // Markup: Lucro / Custo (Quanto adicionamos sobre o custo)
  double get markupPercentual => (custoTotal != null && custoTotal! > 0)
      ? (lucroTotal / custoTotal!) * 100
      : 0;

  // Margem: Lucro / Venda (Quanto do preço final é lucro)
  double get margemPercentual =>
      (valorTotal > 0) ? (lucroTotal / valorTotal) * 100 : 0;

  bool get temCusto => custoTotal != null && custoTotal! > 0;
}

class _VendaProduto {
  final String numeroVenda;
  final DateTime data;
  final int quantidade;
  final double precoUnitario;
  final double valorTotal;
  final String? clienteNome;
  _VendaProduto({
    required this.numeroVenda,
    required this.data,
    required this.quantidade,
    required this.precoUnitario,
    required this.valorTotal,
    this.clienteNome,
  });
}

bool _identificarMesaComanda(
  String? numero,
  String? clienteNome,
  String? status, [
  String? observacoes,
  String? origem,
]) {
  final n = (numero ?? '').toUpperCase();
  final c = (clienteNome ?? '').toUpperCase();
  final st = (status ?? '').toUpperCase();
  final obs = (observacoes ?? '').toUpperCase();
  final ori = (origem ?? '').toUpperCase();
  final allText = '$n $c $st $obs $ori';
  return allText.contains('MESA') ||
      allText.contains('COMANDA') ||
      allText.contains('CMD') ||
      allText.contains('CO-') ||
      allText.contains('[VIP-MC]');
}

String _limparNomeCliente(String nome, String? destaque) {
  String res = nome;
  if (destaque != null) {
    res = res.replaceAll(destaque, '');
  }
  // Limpar colchetes vazios, hifens e espaços extras
  res = res
      .replaceAll('[]', '')
      .replaceAll('[[', '[')
      .replaceAll(']]', ']')
      .replaceAll('[ ]', '')
      .replaceAll('- ', '')
      .trim();

  if (res.startsWith('•')) res = res.substring(1).trim();
  return res;
}

class ItemHistorico {
  final String id;
  final String numero;
  final DateTime data;
  final String? clienteNome;
  final double valorTotal;
  final TipoPagamento? tipoPagamento;
  final String tipo;
  final VendaBalcao? vendaBalcao;
  final Pedido? pedido;
  final TrocaDevolucao? trocaDevolucao;
  final FechamentoCaixa? fechamentoCaixa;
  final SangriaCaixa? sangria;
  final SuprimentoCaixa? suprimento;
  final bool isCancelada;
  final bool isSangria;
  final bool isSuprimento;
  final bool isPagamento;
  final bool isNfce;
  final String? responsavel;
  final String? motoristaNome;
  final EstoqueHistorico? estoqueHistorico;

  ItemHistorico({
    required this.id,
    required this.numero,
    required this.data,
    this.clienteNome,
    required this.valorTotal,
    this.tipoPagamento,
    required this.tipo,
    this.vendaBalcao,
    this.pedido,
    this.trocaDevolucao,
    this.fechamentoCaixa,
    this.sangria,
    this.suprimento,
    this.isCancelada = false,
    this.isSangria = false,
    this.isSuprimento = false,
    this.isPagamento = false,
    this.isNfce = false,
    this.responsavel,
    this.motoristaNome,
    this.estoqueHistorico,
  });

  /// Quebra de mercadoria registrada pelo PDV (saída de estoque — NÃO é venda)
  bool get isQuebra => estoqueHistorico != null;

  double? get valorRecebido {
    if (vendaBalcao != null) {
      if (vendaBalcao!.valorRecebido != null) return vendaBalcao!.valorRecebido;
      // Compatibilidade: se for venda direta e não for pendente, assumir valor total como recebido
      if (tipoPagamento != TipoPagamento.outro &&
          tipoPagamento != TipoPagamento.fiado &&
          tipoPagamento != TipoPagamento.crediario) {
        return valorTotal;
      }
      return null;
    }
    if (pedido != null) {
      double total = pedido!.pagamentos
          .where((p) => p.recebido)
          .fold(0.0, (sum, p) => sum + p.valor);
      return total > 0 ? total : null;
    }
    if (isSuprimento) return valorTotal;
    return null;
  }

  ItemHistorico copyWith({
    String? id,
    String? numero,
    DateTime? data,
    String? clienteNome,
    double? valorTotal,
    TipoPagamento? tipoPagamento,
    String? tipo,
    VendaBalcao? vendaBalcao,
    Pedido? pedido,
    TrocaDevolucao? trocaDevolucao,
    FechamentoCaixa? fechamentoCaixa,
    SangriaCaixa? sangria,
    SuprimentoCaixa? suprimento,
    bool? isCancelada,
    bool? isSangria,
    bool? isSuprimento,
    bool? isPagamento,
    bool? isNfce,
    String? responsavel,
    String? motoristaNome,
    EstoqueHistorico? estoqueHistorico,
  }) {
    return ItemHistorico(
      id: id ?? this.id,
      numero: numero ?? this.numero,
      data: data ?? this.data,
      clienteNome: clienteNome ?? this.clienteNome,
      valorTotal: valorTotal ?? this.valorTotal,
      tipoPagamento: tipoPagamento ?? this.tipoPagamento,
      tipo: tipo ?? this.tipo,
      vendaBalcao: vendaBalcao ?? this.vendaBalcao,
      pedido: pedido ?? this.pedido,
      trocaDevolucao: trocaDevolucao ?? this.trocaDevolucao,
      fechamentoCaixa: fechamentoCaixa ?? this.fechamentoCaixa,
      sangria: sangria ?? this.sangria,
      suprimento: suprimento ?? this.suprimento,
      isCancelada: isCancelada ?? this.isCancelada,
      isSangria: isSangria ?? this.isSangria,
      isSuprimento: isSuprimento ?? this.isSuprimento,
      isPagamento: isPagamento ?? this.isPagamento,
      isNfce: isNfce ?? this.isNfce,
      responsavel: responsavel ?? this.responsavel,
      motoristaNome: motoristaNome ?? this.motoristaNome,
      estoqueHistorico: estoqueHistorico ?? this.estoqueHistorico,
    );
  }

  factory ItemHistorico.fromVendaBalcao(VendaBalcao v, {bool isNfce = false}) =>
      ItemHistorico(
        id: v.id,
        numero: v.numero,
        data: v.dataVenda,
        clienteNome: v.clienteNome,
        valorTotal: v.valorTotal,
        tipoPagamento: v.tipoPagamento,
        tipo: isNfce
            ? 'Venda NFC-e'
            : (v.deliveryInfo != null ? 'Delivery' : 'Venda Direta'),
        vendaBalcao: v,
        isCancelada: v.isCancelada,
        isNfce: isNfce,
        responsavel: v.operador,
        motoristaNome: v.deliveryInfo?.motoristaNome,
      );

  factory ItemHistorico.fromPedido(Pedido p) => ItemHistorico(
    id: p.id,
    numero: p.numero,
    data: p.dataPedido,
    clienteNome: p.clienteNome,
    valorTotal: p.totalGeral,
    tipoPagamento: p.pagamentos.isNotEmpty ? p.pagamentos.first.tipo : null,
    tipo: p.deliveryInfo != null ? 'Delivery' : 'Pedido',
    pedido: p,
    isCancelada: p.status.toLowerCase() == 'cancelado',
    responsavel: p.vendedorNome ?? p.operador,
    motoristaNome: p.deliveryInfo?.motoristaNome,
  );
  factory ItemHistorico.fromTrocaDevolucao(TrocaDevolucao t) => ItemHistorico(
    id: t.id,
    numero: 'TD-${t.numeroPedido}',
    data: t.dataOperacao,
    clienteNome: t.clienteNome,
    valorTotal: t.diferenca,
    tipo: t.tipo == TipoOperacao.troca ? 'Troca' : 'Devolução',
    trocaDevolucao: t,
    isCancelada: t.status.toLowerCase() == 'cancelado',
  );
  factory ItemHistorico.fromFechamentoCaixa(FechamentoCaixa f) => ItemHistorico(
    id: f.id,
    numero: f.numero ?? 'FECH-CAIXA',
    data: f.dataFechamento,
    valorTotal: f.valorReal,
    tipo: 'Fechamento de Caixa',
    fechamentoCaixa: f,
    responsavel: f.responsavel,
  );
  factory ItemHistorico.fromEstoqueHistorico(
    EstoqueHistorico h, {
    String? produtoNome,
  }) =>
      ItemHistorico(
        id: h.id,
        numero: 'QUEBRA',
        data: h.data,
        clienteNome: produtoNome,
        valorTotal: h.valorCusto ?? 0,
        tipo: 'Quebra',
        estoqueHistorico: h,
        responsavel: h.usuario,
      );

  factory ItemHistorico.fromSangria(SangriaCaixa s) {
    bool isPag = s.motivo.startsWith('[PAGAMENTO]');
    return ItemHistorico(
      id: s.id,
      numero: isPag ? 'PAGAMENTO' : 'SANGRIA',
      data: s.data,
      valorTotal: s.valor,
      tipo: isPag ? 'Pagamento' : 'Sangria',
      sangria: s,
      isSangria: !isPag,
      isPagamento: isPag,
      responsavel: s.responsavel,
    );
  }
  factory ItemHistorico.fromSuprimento(SuprimentoCaixa s) => ItemHistorico(
    id: s.id,
    numero: 'SUPRIMENTO',
    data: s.data,
    valorTotal: s.valor,
    tipo: 'Suprimento',
    suprimento: s,
    isSuprimento: true,
    responsavel: s.responsavel,
  );
}

TipoPagamento? _parseTipoPagamento(String? t) {
  if (t == null) return null;
  final s = t.toLowerCase();
  if (s.contains('dinheiro')) return TipoPagamento.dinheiro;
  if (s.contains('pix')) return TipoPagamento.pix;
  if (s.contains('débito') || s.contains('debito'))
    return TipoPagamento.cartaoDebito;
  if (s.contains('crédito') || s.contains('credito'))
    return TipoPagamento.cartaoCredito;
  if (s.contains('boleto')) return TipoPagamento.boleto;
  if (s.contains('crediario') || s.contains('crediário'))
    return TipoPagamento.crediario;
  if (s.contains('fiado')) return TipoPagamento.fiado;
  return TipoPagamento.outro;
}

class HistoricoVendasPage extends StatefulWidget {
  const HistoricoVendasPage({super.key});
  @override
  State<HistoricoVendasPage> createState() => _HistoricoVendasPageState();
}

class _HistoricoVendasPageState extends State<HistoricoVendasPage> {
  final TextEditingController _buscaController = TextEditingController();
  final NumberFormat _formatoMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _formatoData = DateFormat('dd/MM HH:mm');
  DateTime _dataInicio = DateTime.now().copyWith(
    hour: 0,
    minute: 0,
    second: 0,
    millisecond: 0,
    microsecond: 0,
  );
  DateTime _dataFim = DateTime.now().copyWith(
    hour: 23,
    minute: 59,
    second: 59,
    millisecond: 999,
    microsecond: 999,
  );
  String _termoBusca = '';
  String _filtroTipo = 'Todos';
  String _filtroProdutoBusca = '';
  int _limiteLocal = 100;
  bool _filtrarApenasMeuCaixa = false;

  @override
  void initState() {
    super.initState();
    _loadFiltroMeuCaixa();
  }

  void _loadFiltroMeuCaixa() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _filtrarApenasMeuCaixa =
            prefs.getBool('filtrar_apenas_meu_caixa') ?? false;
      });
    }
  }

  void _saveFiltroMeuCaixa(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('filtrar_apenas_meu_caixa', value);
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  /// Monta a lista de itens do histórico respeitando o período selecionado e,
  /// opcionalmente, o caixa do usuário. Reutilizado pela página e pela Análise
  /// de Produtos (que usa seus próprios filtros de data e forma de pagamento).
  List<ItemHistorico> _montarItensHistorico(
    DataService dataService,
    DateTime inicio,
    DateTime fim, {
    bool apenasMeuCaixa = false,
  }) {
    final Map<String, ItemHistorico> mapItens = {};

    // Determinar início e fim da sessão de caixa do OPERADOR atual (ou a última
    // sessão dele, se já fechada). ANTES pegava a abertura mais recente GLOBAL
    // — caixa de outro usuário, ou uma abertura já fechada com janela minúscula,
    // fazia TODAS as vendas sumirem do filtro.
    DateTime? inicioCaixa;
    DateTime? fimCaixa;
    AberturaCaixa? ultimaAbertura;
    if (apenasMeuCaixa) {
      final operadorAtual =
          dataService.responsavelAtivo ?? dataService.usuarioAtualEmail;
      ultimaAbertura = dataService.ultimaAberturaDoOperador(operadorAtual);
      final ultima = ultimaAbertura;
      if (ultima != null) {
        inicioCaixa = ultima.dataAbertura;

        // Se já foi fechado, filtrar até o momento do fechamento
        final fechamento = dataService.fechamentosCaixa.firstWhereOrNull(
          (f) => f.aberturaCaixaId == ultima.id,
        );
        if (fechamento != null) {
          fimCaixa = fechamento.dataFechamento;
        }
      }
    }
    final _dataInicio = (apenasMeuCaixa && inicioCaixa != null) ? inicioCaixa : inicio;
    final _dataFim = (apenasMeuCaixa && inicioCaixa != null) ? (fimCaixa ?? DateTime.now().add(const Duration(days: 1))) : fim;

    bool pertenceAoCaixa(DateTime data, {String? operador}) {
      if (!apenasMeuCaixa) return true;
      if (inicioCaixa == null) return false;
      if (data.isBefore(inicioCaixa)) return false;
      if (fimCaixa != null && data.isAfter(fimCaixa)) return false;
      // Sessão do caixa: vendas de OUTRO operador (quando identificadas) não entram
      // no "meu caixa" (venda sem operador é legada e continua entrando).
      if (operador != null &&
          !dataService.vendaPertenceAoOperador(
              operador, ultimaAbertura?.responsavel)) {
        return false;
      }
      return true;
    }

    // 0. NFC-es e NF-es (Para identificar quais vendas possuem nota fiscal emitida)
    final Map<String, NFCe> mapNfces = {};
    final todasNotas = [...dataService.nfces, ...dataService.nfes];
    for (var n in todasNotas.where(
      (n) =>
          n.dataEmissao.isAfter(_dataInicio) &&
          n.dataEmissao.isBefore(_dataFim),
    )) {
      if (n.vendaId != null) mapNfces[n.vendaId!] = n;
      // Também marcar por vendaNumero se vendaId falhar (fallback)
      if (n.vendaNumero != null) mapNfces[n.vendaNumero!] = n;
    }

    // 1. Vendas Balcão (Prioridade para exibição correta de valores do PDV)
    // Apenas incluir vendas que JA FORAM RECEBIDAS (finalizadas no PDV)
    // Vendas pendentes (salvas para receber depois) devem aparecer apenas no PDV, não no histórico
    for (var v in dataService.vendasBalcao.where(
      (v) =>
          v.dataVenda.isAfter(_dataInicio) &&
          v.dataVenda.isBefore(_dataFim) &&
          pertenceAoCaixa(v.dataVenda, operador: v.operador),
    )) {
      // Verificar se a venda já foi recebida (tem valor recebido > 0)
      final foiRecebida = (v.valorRecebido ?? 0) > 0;
      final isCancelada = v.isCancelada;

      // Só incluir no histórico se foi recebida ou cancelada (não incluir pendentes)
      if (!foiRecebida && !isCancelada) continue;

      bool isNfce =
          mapNfces.containsKey(v.id) || mapNfces.containsKey(v.numero);
      mapItens[v.id] = ItemHistorico.fromVendaBalcao(v, isNfce: isNfce);
    }

    // 2. Pedidos (Mesclar com VendaBalcao se existir, senão adicionar novo)
    for (var p in dataService.pedidos.where(
      (p) =>
          p.dataPedido.isAfter(_dataInicio) &&
          p.dataPedido.isBefore(_dataFim) &&
          pertenceAoCaixa(p.dataPedido),
    )) {
      // Regra: Pedidos "Pendentes" (como Delivery que ainda não foi pago/entregue)
      // não devem aparecer no histórico ainda, apenas no PDV (aba Receber).
      final isPendente = p.status.toLowerCase() == 'pendente';

      if (mapItens.containsKey(p.id)) {
        // MESCLAR: Venda Direta + Pedido (Mesmo ID)
        final existing = mapItens[p.id]!;
        final TipoPagamento? novoTipo = p.pagamentos.isNotEmpty
            ? p.pagamentos.first.tipo
            : existing.tipoPagamento;

        mapItens[p.id] = existing.copyWith(pedido: p, tipoPagamento: novoTipo);
      } else if (!isPendente) {
        // Apenas adiciona ao histórico se NÃO estiver pendente (ex: Cancelado ou Pago)
        mapItens[p.id] = ItemHistorico.fromPedido(p);
      }
    }

    // 3. Demais itens operacionais (Caixa, Sangrias, Suprimentos)
    for (var f in dataService.fechamentosCaixa.where(
      (f) =>
          f.dataFechamento.isAfter(_dataInicio) &&
          f.dataFechamento.isBefore(_dataFim) &&
          pertenceAoCaixa(f.dataFechamento),
    )) {
      mapItens['FECH-${f.id}'] = ItemHistorico.fromFechamentoCaixa(f);
    }
    for (var s in dataService.sangrias.where(
      (s) =>
          s.data.isAfter(_dataInicio) &&
          s.data.isBefore(_dataFim) &&
          pertenceAoCaixa(s.data),
    )) {
      mapItens['SANG-${s.id}'] = ItemHistorico.fromSangria(s);
    }
    for (var s in dataService.suprimentos.where(
      (s) =>
          s.data.isAfter(_dataInicio) &&
          s.data.isBefore(_dataFim) &&
          pertenceAoCaixa(s.data),
    )) {
      mapItens['SUPR-${s.id}'] = ItemHistorico.fromSuprimento(s);
    }

    // 4. Trocas e Devoluções
    try {
      final trocasDevolucoes = dataService.getTrocasDevolucoesPorPeriodo(
        _dataInicio,
        _dataFim,
      );
      for (var t in trocasDevolucoes) {
        if (pertenceAoCaixa(t.dataOperacao)) {
          mapItens['TD-${t.id}'] = ItemHistorico.fromTrocaDevolucao(t);
        }
      }
    } catch (e) {
      final trocas =
          (dataService as dynamic).trocasDevolucoes as List<TrocaDevolucao>;
      for (var t in trocas.where(
        (t) =>
            t.dataOperacao.isAfter(_dataInicio) &&
            t.dataOperacao.isBefore(_dataFim) &&
            pertenceAoCaixa(t.dataOperacao),
      )) {
        mapItens['TD-${t.id}'] = ItemHistorico.fromTrocaDevolucao(t);
      }
    }

    // 5. Quebras de mercadoria (saída de estoque lançada pelo PDV — NÃO é venda)
    try {
      for (var h in dataService.estoqueHistorico.where(
        (h) =>
            h.ehQuebra &&
            h.data.isAfter(_dataInicio) &&
            h.data.isBefore(_dataFim) &&
            pertenceAoCaixa(h.data, operador: h.usuario),
      )) {
        final prodNome = dataService.produtos
            .firstWhereOrNull((p) => p.id == h.produtoId)
            ?.nome;
        mapItens['QB-${h.id}'] =
            ItemHistorico.fromEstoqueHistorico(h, produtoNome: prodNome);
      }
    } catch (_) {}

    // 6. Contas Pagas (Despesas registradas no Contas a Pagar)
    for (var cp in dataService.contasPagar.where(
      (cp) =>
          cp.status == StatusContaPagar.pago &&
          cp.dataPagamento != null &&
          cp.dataPagamento!.isAfter(_dataInicio) &&
          cp.dataPagamento!.isBefore(_dataFim) &&
          pertenceAoCaixa(cp.dataPagamento!),
    )) {
      // Evitar duplicidade se já foi registrado como Sangria no PDV
      if (!mapItens.values.any(
        (item) =>
            item.isPagamento &&
            item.valorTotal == cp.valor &&
            (item.responsavel == cp.usuarioCriacao ||
                item.responsavel == cp.fornecedorNome),
      )) {
        mapItens['CP-${cp.id}'] = ItemHistorico(
          id: cp.id,
          numero: cp.numero ?? 'CONTA-PAG',
          data: cp.dataPagamento!,
          clienteNome: cp.fornecedorNome,
          valorTotal: cp.valor,
          tipo: 'Pagamento (Conta)',
          tipoPagamento: _parseTipoPagamento(cp.formaPagamento),
          isPagamento: true,
          responsavel: cp.usuarioCriacao,
        );
      }
    }

    // 7. Pagamentos avulsos/posteriores de pedidos (Pagamentos recebidos hoje para pedidos antigos)
    for (var p in dataService.pedidos) {
      if (mapItens.containsKey(p.id))
        continue; // Evita lançar o pagamento avulso se o pedido principal já está na lista de hoje
      for (var pag in p.pagamentos.where(
        (pag) =>
            pag.recebido &&
            pag.dataRecebimento != null &&
            pag.dataRecebimento!.isAfter(_dataInicio) &&
            pag.dataRecebimento!.isBefore(_dataFim) &&
            pertenceAoCaixa(pag.dataRecebimento!),
      )) {
        // Adicionamos como linha separada para o fluxo de caixa de HOJE ser real
        mapItens['PAG-${pag.id}'] = ItemHistorico(
          id: pag.id,
          numero: '${p.numero} (PAG)',
          data: pag.dataRecebimento!,
          clienteNome: p.clienteNome,
          valorTotal: pag.valor,
          tipo: 'Recebimento',
          tipoPagamento: pag.tipo,
          pedido: p,
          responsavel: p.vendedorNome,
        );
      }
    }

    return mapItens.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    List<ItemHistorico> itens = _montarItensHistorico(
      dataService,
      _dataInicio,
      _dataFim,
      apenasMeuCaixa: _filtrarApenasMeuCaixa,
    );

    // Filtro por Tipo
    if (_filtroTipo != 'Todos') {
      itens = itens.where((i) {
        switch (_filtroTipo) {
          case 'Vendas':
            return i.vendaBalcao != null || i.pedido != null;
          case 'Balcão':
            return (i.vendaBalcao != null || i.pedido != null) &&
                i.tipo != 'Delivery';
          case 'Delivery':
            return i.tipo == 'Delivery';
          case 'NFC-e':
            return i.isNfce;
          case 'Pagamento':
            return i.isPagamento;
          case 'Sangria':
            return i.isSangria;
          case 'Suprimento':
            return i.isSuprimento;
          case 'Trocas':
            return i.trocaDevolucao != null;
          case 'Quebra':
            return i.isQuebra;
          default:
            return true;
        }
      }).toList();
    }

    if (_termoBusca.isNotEmpty) {
      final t = _termoBusca.toLowerCase();
      itens = itens.where((i) {
        final matchesBase =
            i.numero.toLowerCase().contains(t) ||
            (i.clienteNome ?? '').toLowerCase().contains(t) ||
            i.tipo.toLowerCase().contains(t);
        bool matchesProd = false;
        if (i.vendaBalcao != null)
          matchesProd = i.vendaBalcao!.itens.any(
            (iv) => iv.nome.toLowerCase().contains(t),
          );
        else if (i.pedido != null)
          matchesProd = i.pedido!.produtos.any(
            (ip) => ip.nome.toLowerCase().contains(t),
          );
        else if (i.trocaDevolucao != null)
          matchesProd =
              i.trocaDevolucao!.itensDevolvidos.any(
                (id) => id.produtoNome.toLowerCase().contains(t),
              ) ||
              (i.trocaDevolucao!.itensNovos?.any(
                    (inew) => inew.produtoNome.toLowerCase().contains(t),
                  ) ??
                  false);
        return matchesBase || matchesProd;
      }).toList();
    }

    itens.sort((a, b) => b.data.compareTo(a.data));

    // Calcular estatísticas financeiras
    double totalEntradas = 0;
    double totalSaidas = 0;
    int vendasBalcaoCount = 0;
    double totalVendasBalcao = 0;
    int deliveryCount = 0;
    double totalDelivery = 0;
    final Map<TipoPagamento, double> totaisPorPagamento = {};

    for (final i in itens.where((i) => !i.isCancelada)) {
      if (i.vendaBalcao != null || i.pedido != null) {
        if (i.tipo == 'Delivery') {
          deliveryCount++;
          totalDelivery += i.valorTotal;
        } else {
          vendasBalcaoCount++;
          totalVendasBalcao += i.valorTotal;
        }
      }

      if (i.isSangria || i.isPagamento) {
        totalSaidas += i.valorTotal;
        // Subtrair da forma de pagamento
        final tp = i.tipoPagamento ?? TipoPagamento.dinheiro;
        totaisPorPagamento[tp] = (totaisPorPagamento[tp] ?? 0) - i.valorTotal;
      } else if (i.fechamentoCaixa == null) {
        // Para o resumo financeiro, usamos o VALOR RECEBIDO (Fluxo de Caixa)
        // Se for um suprimento, o valor total é o recebido
        double valRecebido = i.valorRecebido ?? 0;

        if (i.trocaDevolucao != null && i.valorTotal < 0) {
          // Se foi estornando em DINHEIRO, a Sangria já registrou a saída.
          // Ignoramos o valor da TD aqui para não duplicar a saída no resumo financeiro.
          if (i.trocaDevolucao?.metodoEstorno == 'dinheiro') continue;

          // Caso contrário (crédito/outros), subtraímos das entradas
          totalEntradas -= i.valorTotal.abs();
          final tp = i.tipoPagamento ?? TipoPagamento.dinheiro;
          totaisPorPagamento[tp] =
              (totaisPorPagamento[tp] ?? 0) - i.valorTotal.abs();
          continue;
        }

        // BUG FIX: Se for uma linha de RECEBIMENTO avulso, usamos apenas o valorTotal da linha
        // para evitar somar o pedido inteiro múltiplas vezes no dashboard
        if (i.tipo == 'Recebimento' || i.id.startsWith('PAG-')) {
          final tp = i.tipoPagamento ?? TipoPagamento.dinheiro;
          totaisPorPagamento[tp] = (totaisPorPagamento[tp] ?? 0) + i.valorTotal;
          totalEntradas += i.valorTotal;
          continue;
        }

        // Se tem pedido (Mesa/Comanda ou Venda Salva), somar apenas o que foi marcado como recebido
        if (i.pedido != null) {
          double somaRecebidaPedido = 0;
          // Aqui filtramos pagamentos que ocorreram NO PERIODO selecionado
          // para que o total do dashboard reflita apenas o dinheiro que entrou hoje
          for (final pag in i.pedido!.pagamentos.where((p) => p.recebido)) {
            final dataPag = pag.dataRecebimento ?? i.pedido!.dataPedido;
            if (dataPag.isAfter(_dataInicio) && dataPag.isBefore(_dataFim)) {
              totaisPorPagamento[pag.tipo] =
                  (totaisPorPagamento[pag.tipo] ?? 0) + pag.valor;
              somaRecebidaPedido += pag.valor;
            }
          }
          totalEntradas += somaRecebidaPedido;
        } else {
          // Venda Direta Simples ou Suprimento
          // Usamos o valor que foi efetivamente recebido (evita que vendas pendentes entrem no caixa)
          if (valRecebido > 0 || i.isSuprimento) {
            // Se a venda tem múltiplas formas de pagamento (split), somar cada forma
            // individualmente para o resumo refletir o fluxo de caixa correto
            final pagsVenda = i.vendaBalcao?.pagamentos ?? const <PagamentoPedido>[];
            if (pagsVenda.isNotEmpty && !i.isSuprimento) {
              for (final pag in pagsVenda.where((p) => p.recebido)) {
                totaisPorPagamento[pag.tipo] =
                    (totaisPorPagamento[pag.tipo] ?? 0) + pag.valor;
              }
              totalEntradas += valRecebido;
            } else {
              final tp = i.tipoPagamento ?? TipoPagamento.dinheiro;
              totaisPorPagamento[tp] =
                  (totaisPorPagamento[tp] ?? 0) +
                  (i.isSuprimento ? i.valorTotal : valRecebido);
              totalEntradas += (i.isSuprimento ? i.valorTotal : valRecebido);
            }
          }
        }
      }
    }

    final double totalLiquido = totalEntradas - totalSaidas;
    final Color totalColor = totalLiquido >= 0
        ? Colors.greenAccent
        : Colors.redAccent;

    // Ocultar totais financeiros para operador/funcionário sem permissão
    // (dashboard.ver_totais) — eles operam o caixa, mas não veem quanto a
    // empresa vende. Admin/Master/Gerente sempre veem.
    final authServiceTotais = Provider.of<AuthService>(context, listen: false);
    final podeVerTotais = PermissionHelper.podeVerTotais(authServiceTotais.usuarioAtual);
    // Total por forma de pagamento: permissão própria
    // (caixa.ver_totais_formas_pagamento)
    final podeVerFormasPagamento = PermissionHelper.podeVerTotaisFormasPagamento(authServiceTotais.usuarioAtual);

    return Scaffold(
      backgroundColor: const Color(0xFF161621),
      appBar: AppBar(
        title: const Text(
          'Historico de Vendas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E1E2E),
        actions: [
          const SyncStatusWidget(),
          IconButton(
            icon: const Icon(Icons.point_of_sale, color: Colors.greenAccent),
            onPressed: () => _mostrarResumoCaixas(context, itens, dataService),
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2, color: Colors.blueAccent),
            tooltip: 'Produtos Vendidos',
            onPressed: () =>
                _mostrarVendasPorProduto(context, dataService, itens),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.amberAccent),
            tooltip: 'Trocas e Devoluções',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TrocasDevolucoesBuscarPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long, color: Colors.cyanAccent),
            tooltip: 'Histórico NFC-e',
            onPressed: () {
              final authService = Provider.of<AuthService>(
                context,
                listen: false,
              );
              final empresa = authService.empresaAtual;
              if (empresa == null) return;

              showDialog(
                context: context,
                builder: (context) => HistoricoNFCePDVDialog(empresa: empresa),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltros(),
          if (podeVerTotais)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  _buildStatCard(
                    'TOTAL ENTRADAS',
                    totalEntradas,
                    Colors.greenAccent,
                  ),
                  const SizedBox(width: 8),
                  _buildStatCard('TOTAL SAÍDAS', totalSaidas, Colors.redAccent),
                  const SizedBox(width: 8),
                  _buildStatCard('TOTAL LÍQUIDO', totalLiquido, totalColor),
                ],
              ),
            ),
          // Divisão Balcão vs Delivery
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _filtroTipo = _filtroTipo == 'Balcão'
                            ? 'Todos'
                            : 'Balcão';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _filtroTipo == 'Balcão'
                              ? Colors.blueAccent
                              : Colors.white10,
                          width: _filtroTipo == 'Balcão' ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.storefront,
                                color: Colors.blueAccent,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Balcão',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            podeVerTotais
                                ? '$vendasBalcaoCount (${_formatoMoeda.format(totalVendasBalcao)})'
                                : '$vendasBalcaoCount',
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _filtroTipo = _filtroTipo == 'Delivery'
                            ? 'Todos'
                            : 'Delivery';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _filtroTipo == 'Delivery'
                              ? Colors.orangeAccent
                              : Colors.white10,
                          width: _filtroTipo == 'Delivery' ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.delivery_dining,
                                color: Colors.orangeAccent,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delivery',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            podeVerTotais
                                ? '$deliveryCount (${_formatoMoeda.format(totalDelivery)})'
                                : '$deliveryCount',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Resumo por Forma de Pagamento (permissão própria:
          // caixa.ver_totais_formas_pagamento)
          if (podeVerFormasPagamento && totaisPorPagamento.isNotEmpty)
            Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: totaisPorPagamento.entries.map((e) {
                  return InkWell(
                    onTap: () => _mostrarVendasDoTipo(context, e.key, itens),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                e.key.nome.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.open_in_new,
                                color: Colors.white12,
                                size: 8,
                              ),
                            ],
                          ),
                          Text(
                            _formatoMoeda.format(e.value),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: itens.length > _limiteLocal
                  ? _limiteLocal + 1
                  : itens.length,
              itemBuilder: (context, index) {
                if (index == _limiteLocal)
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(() => _limiteLocal += 50),
                      child: const Text('Carregar mais...'),
                    ),
                  );
                return _buildCardItem(itens[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    final dataService = Provider.of<DataService>(context, listen: false);
    DateTime? inicioCaixa;
    DateTime? fimCaixa;
    final aberturas = dataService.aberturasCaixa;
    if (aberturas.isNotEmpty) {
      final sorted = List<AberturaCaixa>.from(aberturas)
        ..sort((a, b) => b.dataAbertura.compareTo(a.dataAbertura));
      final ultimaAbertura = sorted.first;
      inicioCaixa = ultimaAbertura.dataAbertura;
      final fechamento = dataService.fechamentosCaixa.firstWhereOrNull(
        (f) => f.aberturaCaixaId == ultimaAbertura.id,
      );
      if (fechamento != null) {
        fimCaixa = fechamento.dataFechamento;
      }
    }
    return Container(
      color: const Color(0xFF1E1E2E),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildDatePicker(_dataInicio, 'Inicio', true)),
              const SizedBox(width: 8),
              Expanded(child: _buildDatePicker(_dataFim, 'Fim', false)),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  [
                    'Todos',
                    'Vendas',
                    'Balcão',
                    'Delivery',
                    'NFC-e',
                    'Pagamento',
                    'Sangria',
                    'Suprimento',
                    'Trocas',
                    'Quebra',
                  ].map((tipo) {
                    final isSelected = _filtroTipo == tipo;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tipo),
                        selected: isSelected,
                        onSelected: (val) => setState(() => _filtroTipo = tipo),
                        backgroundColor: const Color(0xFF2D2D44),
                        selectedColor: Colors.blueAccent.withOpacity(0.3),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.blueAccent
                              : Colors.white60,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.blueAccent
                              : Colors.transparent,
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _buscaController,
            onChanged: (v) => setState(() => _termoBusca = v),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar...',
              prefixIcon: const Icon(Icons.search, color: Colors.white24),
              filled: true,
              fillColor: const Color(0xFF2D2D44),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Checkbox(
                value: _filtrarApenasMeuCaixa,
                activeColor: Colors.blueAccent,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _filtrarApenasMeuCaixa = val;
                      if (!val) {
                        if (inicioCaixa != null) {
                          _dataInicio = inicioCaixa!;
                          _dataFim = fimCaixa ?? DateTime.now().copyWith(hour: 23, minute: 59, second: 59);
                        }
                      }
                    });
                    _saveFiltroMeuCaixa(val);
                  }
                },
              ),
              const Text(
                'Apenas Meu Caixa (Sessão)',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(DateTime date, String label, bool isInicio) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (d != null) {
          setState(() {
            if (isInicio) {
              _dataInicio = d.copyWith(
                hour: 0,
                minute: 0,
                second: 0,
                millisecond: 0,
                microsecond: 0,
              );
            } else {
              _dataFim = d.copyWith(
                hour: 23,
                minute: 59,
                second: 59,
                millisecond: 999,
                microsecond: 999,
              );
            }
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D44),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            Text(
              DateFormat('dd/MM/yyyy').format(date),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    double val,
    Color col, {
    bool isMoeda = true,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: col.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: col.withOpacity(0.7),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              isMoeda ? _formatoMoeda.format(val) : val.toInt().toString(),
              style: TextStyle(
                color: col,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardItem(ItemHistorico item) {
    final bool isVip = _identificarMesaComanda(
      item.numero,
      item.clienteNome,
      item.pedido?.status,
      item.vendaBalcao?.observacoes ?? item.pedido?.observacoes,
      item.vendaBalcao?.origem ?? item.pedido?.origem,
    );

    // Tentar extrair o número da comanda/mesa para destaque
    String? mcDestaque;
    bool isRealComanda = false;

    if (isVip) {
      final t = (item.clienteNome ?? '').toUpperCase();
      final n = item.numero.toUpperCase();
      final obs =
          (item.vendaBalcao?.observacoes ?? item.pedido?.observacoes ?? '')
              .toUpperCase();
      final ori = (item.vendaBalcao?.origem ?? item.pedido?.origem ?? '')
          .toUpperCase();
      final fullData = '$t $n $obs $ori';

      // Prioridade 1: Buscar padrão MESA XX ou CMD XX nas observações ou cliente
      final match = RegExp(
        r'(MESA \d+|CMD-\d+|COMANDA \d+)',
      ).firstMatch(fullData);
      if (match != null) {
        mcDestaque = match.group(0);
      } else if (t.contains('CMD-') || t.contains('COMANDA')) {
        mcDestaque = t.split(' • ').first;
      } else if (n.contains('CMD-') || n.contains('MESA')) {
        mcDestaque = item.numero;
      }
    }

    // Diferenciar Ícone e Cor: Comanda vs Mesa vs Venda Direta
    if (isVip) {
      isRealComanda =
          (mcDestaque ?? '').contains('CMD') ||
          (mcDestaque ?? '').contains('COMANDA');
    }

    IconData icon = item.isCancelada
        ? Icons.cancel_outlined
        : (item.tipo == 'Delivery'
              ? Icons.delivery_dining
              : (isVip
                    ? (isRealComanda
                          ? Icons.receipt_long_rounded
                          : Icons.table_restaurant_rounded)
                    : Icons.shopping_bag_rounded));

    Color color = item.isCancelada
        ? Colors.redAccent
        : (item.tipo == 'Delivery'
              ? Colors.orangeAccent
              : (isVip
                    ? (isRealComanda
                          ? Colors.purpleAccent
                          : Colors.orangeAccent)
                    : Colors.blueAccent));

    if (item.isPagamento || item.tipo == 'Pagamento (Conta)') {
      icon = Icons.payments_outlined;
      color = Colors.purpleAccent;
    } else if (item.isSangria) {
      icon = Icons.money_off_rounded;
      color = Colors.orangeAccent;
    } else if (item.isSuprimento) {
      icon = Icons.add_circle_outline_rounded;
      color = Colors.cyanAccent;
    } else if (item.tipo == 'Recebimento') {
      icon = Icons.account_balance_wallet_rounded;
      color = Colors.greenAccent;
    } else if (item.fechamentoCaixa != null) {
      icon = Icons.lock_clock_rounded;
      color = Colors.deepPurpleAccent;
    } else if (item.trocaDevolucao != null) {
      icon = item.trocaDevolucao!.tipo == TipoOperacao.troca
          ? Icons.swap_horizontal_circle_outlined
          : Icons.history_rounded;
      color = Colors.amber;
    } else if (item.isQuebra) {
      icon = Icons.broken_image_rounded;
      color = Colors.orangeAccent;
    }

    String formaPagamentoStr = '';
    bool isParcial = false;

    if (item.vendaBalcao != null) {
      final pagsVenda = item.vendaBalcao!.pagamentos;
      if (pagsVenda.isNotEmpty) {
        // Venda com múltiplas formas de pagamento (split/parcial)
        final nomes = pagsVenda.map((p) => p.tipo.nome).toSet().toList();
        formaPagamentoStr = nomes.join(' + ');
        final totalPago = pagsVenda
            .where((p) => p.recebido)
            .fold(0.0, (s, p) => s + p.valor);
        isParcial = totalPago < item.vendaBalcao!.valorTotal && totalPago > 0;
      } else {
        formaPagamentoStr = item.vendaBalcao!.tipoPagamento.nome;
      }
    } else if (item.pedido != null) {
      final pags = item.pedido!.pagamentos;
      if (pags.isNotEmpty) {
        formaPagamentoStr = pags.map((p) => p.tipo.nome).toSet().join(', ');
        final totalPago = pags
            .where((p) => p.recebido)
            .fold(0.0, (s, p) => s + p.valor);
        isParcial = totalPago < item.pedido!.totalGeral && totalPago > 0;
      }
    } else if (item.tipoPagamento != null) {
      formaPagamentoStr = item.tipoPagamento!.nome;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _mostrarDetalhesVenda(item),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                item.numero,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (mcDestaque != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    mcDestaque,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ] else if (!item.isQuebra &&
                                  item.clienteNome != null &&
                                  item.clienteNome!.isNotEmpty &&
                                  item.clienteNome!.toLowerCase() !=
                                      'venda direta' &&
                                  item.clienteNome!.toLowerCase() !=
                                      'consumidor') ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.blue.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Text(
                                    _limparNomeCliente(
                                      item.clienteNome!,
                                      null,
                                    ).toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.blueAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      () {
                        final String displayNome = () {
                          if (item.isSangria || item.isPagamento) {
                            String m = item.sangria?.motivo ?? '';
                            if (item.isPagamento)
                              m = m.replaceAll('[PAGAMENTO]', '').trim();
                            return m.isNotEmpty ? m : 'Sem motivo';
                          }
                          if (item.isSuprimento) {
                            return (item.suprimento?.motivo ?? '').isNotEmpty
                                ? item.suprimento!.motivo
                                : 'Suprimento de caixa';
                          }
                          if (item.isQuebra) {
                            final q = item.estoqueHistorico!;
                            final qtd = q.quantidade.abs().toStringAsFixed(
                                q.quantidade.abs() ==
                                        q.quantidade.abs().roundToDouble()
                                    ? 0
                                    : 2);
                            final custo = (q.valorCusto != null &&
                                    q.valorCusto! > 0)
                                ? ' • Prejuízo: R\$ ${q.valorCusto!.toStringAsFixed(2)}'
                                : '';
                            return 'QUEBRA DE MERCADORIA • $qtd un$custo';
                          }
                          if (item.trocaDevolucao != null &&
                              item.trocaDevolucao!.tipo ==
                                  TipoOperacao.devolucao) {
                            return 'ENTRADA DE ESTOQUE${item.clienteNome != null ? ' • ${_limparNomeCliente(item.clienteNome!, mcDestaque)}' : ''}';
                          }

                          // Se mcDestaque for nulo, o nome já está sendo mostrado como badge no cabeçalho
                          // Não precisamos mostrar de novo aqui embaixo para evitar redundância.
                          if (mcDestaque == null &&
                              item.clienteNome != null &&
                              item.clienteNome!.isNotEmpty) {
                            return '';
                          }

                          final cNome = item.clienteNome != null
                              ? _limparNomeCliente(
                                  item.clienteNome!,
                                  mcDestaque,
                                )
                              : '';
                          return (cNome.toLowerCase() == 'venda direta' ||
                                  cNome.toLowerCase() == 'consumidor')
                              ? ''
                              : cNome;
                        }();

                        if (displayNome.isEmpty) return const SizedBox.shrink();

                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            displayNome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color.withOpacity(0.2)),
                            ),
                            child: Text(
                              item.tipo.toUpperCase(),
                              style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          if (formaPagamentoStr.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.blueGrey.withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                formaPagamentoStr.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.blueGrey,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          if (isParcial)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.2),
                                ),
                              ),
                              child: const Text(
                                'PARCIAL',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          if (!item.isCancelada &&
                              !item.isSangria &&
                              !item.isSuprimento &&
                              !item.isPagamento &&
                              !item.isQuebra &&
                              item.fechamentoCaixa == null &&
                              (item.trocaDevolucao == null ||
                                  item.trocaDevolucao!.tipo !=
                                      TipoOperacao.devolucao) &&
                              (item.valorRecebido ?? 0) <= 0.01)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.2),
                                ),
                              ),
                              child: const Text(
                                'PENDENTE',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            color: Colors.white.withOpacity(0.3),
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatoData.format(item.data.toLocal()),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12,
                            ),
                          ),
                          if (item.responsavel != null) ...[
                            Text(
                              ' • ',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                            Text(
                              'Resp: ${item.responsavel}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (item.motoristaNome != null) ...[
                            Text(
                              ' • ',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                            Icon(
                              Icons.two_wheeler_rounded,
                              color: Colors.lightBlueAccent.withOpacity(0.7),
                              size: 12,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${item.motoristaNome}',
                              style: TextStyle(
                                color: Colors.lightBlueAccent.withOpacity(0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item.fechamentoCaixa == null &&
                        (item.trocaDevolucao == null ||
                            item.trocaDevolucao!.tipo !=
                                TipoOperacao.devolucao))
                      Text(
                        '${(item.isSangria || item.isPagamento || item.valorTotal < 0) ? "- " : "+ "}${_formatoMoeda.format(item.valorTotal.abs())}',
                        style: TextStyle(
                          color: item.isCancelada
                              ? Colors.white24
                              : (item.isSangria ||
                                        item.isPagamento ||
                                        item.valorTotal < 0
                                    ? Colors.redAccent
                                    : Colors.greenAccent),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            if (!item.isCancelada)
                              Shadow(
                                color:
                                    (item.isSangria ||
                                                item.isPagamento ||
                                                item.valorTotal < 0
                                            ? Colors.redAccent
                                            : Colors.greenAccent)
                                        .withOpacity(0.5),
                                blurRadius: 10,
                              ),
                          ],
                        ),
                      ),
                    if (item.isCancelada)
                      const Text(
                        'CANCELADO',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarDetalhesVenda(ItemHistorico item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      builder: (context) {
        final dataService = Provider.of<DataService>(context, listen: false);
        final List<NFCe> matchingNfces = dataService.nfces
            .where((n) => n.vendaId == item.id || n.vendaNumero == item.numero)
            .toList();
        final NFCe? nfceExistente = matchingNfces.isNotEmpty
            ? matchingNfces.first
            : null;

        return Container(
          height: MediaQuery.of(context).size.height * 0.78,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detalhes ${item.numero}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        item.tipo,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white10),
              Expanded(
                child: ListView(
                  children: [
                    if (item.vendaBalcao != null)
                      ...item.vendaBalcao!.itens.map(
                        (iv) => ListTile(
                          title: Text(
                            iv.nome,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (iv.fornecedorNome != null) ...[
                                Text(
                                  'Fornecedor: ${iv.fornecedorNome}',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              if (iv.adicionais.isNotEmpty)
                                ...iv.adicionais.map(
                                  (a) => Text(
                                    '+ ${a.nome} (${_formatoMoeda.format(a.preco)})',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              if (iv.opcoesCombo.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                ...iv.opcoesCombo.map(
                                  (o) => Text(
                                    o.precoAdicional > 0
                                        ? '• ${o.nome} (+ ${_formatoMoeda.format(o.precoAdicional)})'
                                        : '• ${o.nome}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Text(
                            '${iv.quantidade}x ${_formatoMoeda.format(iv.precoUnitario)}',
                          ),
                        ),
                      ),
                    if (item.pedido != null)
                      ...item.pedido!.produtos.map(
                        (pp) => ListTile(
                          title: Text(
                            pp.nome,
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: Text(
                            '${pp.quantidade}x ${_formatoMoeda.format(pp.preco)}',
                          ),
                        ),
                      ),
                    if (item.trocaDevolucao != null) ...[
                      const ListTile(
                        title: Text(
                          'ITENS DEVOLVIDOS',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...item.trocaDevolucao!.itensDevolvidos.map(
                        (id) => ListTile(
                          title: Text(
                            id.produtoNome,
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: Text(
                            '${id.quantidade}x ${_formatoMoeda.format(id.precoUnitario)}',
                          ),
                        ),
                      ),
                      if (item.trocaDevolucao!.itensNovos != null &&
                          item.trocaDevolucao!.itensNovos!.isNotEmpty) ...[
                        const ListTile(
                          title: Text(
                            'NOVOS ITENS',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...item.trocaDevolucao!.itensNovos!.map(
                          (inew) => ListTile(
                            title: Text(
                              inew.produtoNome,
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: Text(
                              '${inew.quantidade}x ${_formatoMoeda.format(inew.precoUnitario)}',
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (item.fechamentoCaixa != null)
                      ...() {
                        final f = item.fechamentoCaixa!;
                        final ab = dataService.aberturasCaixa.firstWhereOrNull(
                          (a) => a.id == f.aberturaCaixaId,
                        );

                        // Obter a data de abertura e data de fechamento para filtrar as vendas do caixa
                        final start =
                            ab?.dataAbertura ??
                            f.dataFechamento.subtract(
                              const Duration(hours: 12),
                            );
                        final end = f.dataFechamento;

                        // Filtrar vendas ocorridas durante o período do caixa
                        final vendasSessao = dataService.vendasBalcao
                            .where(
                              (v) =>
                                  !v.isCancelada &&
                                  (v.valorRecebido ?? 0) > 0 &&
                                  v.dataVenda.isAfter(start) &&
                                  v.dataVenda.isBefore(end),
                            )
                            .toList();

                        final pedidosSessao = dataService.pedidos
                            .where(
                              (p) =>
                                  p.status.toLowerCase() != 'pendente' &&
                                  p.dataPedido.isAfter(start) &&
                                  p.dataPedido.isBefore(end),
                            )
                            .toList();

                        final Map<TipoPagamento, double> totaisSessao = {};
                        for (var v in vendasSessao) {
                          // Se a venda tem múltiplas formas de pagamento (split),
                          // somar cada forma individualmente no fechamento do caixa
                          if (v.pagamentos.isNotEmpty) {
                            for (final pag in v.pagamentos.where((p) => p.recebido)) {
                              totaisSessao[pag.tipo] =
                                  (totaisSessao[pag.tipo] ?? 0.0) + pag.valor;
                            }
                          } else {
                            totaisSessao[v.tipoPagamento] =
                                (totaisSessao[v.tipoPagamento] ?? 0.0) +
                                v.valorTotal;
                          }
                        }
                        for (var p in pedidosSessao) {
                          for (var pag in p.pagamentos.where(
                            (pg) => pg.recebido,
                          )) {
                            if (pag.dataRecebimento != null &&
                                pag.dataRecebimento!.isAfter(start) &&
                                pag.dataRecebimento!.isBefore(end)) {
                              totaisSessao[pag.tipo] =
                                  (totaisSessao[pag.tipo] ?? 0.0) + pag.valor;
                            }
                          }
                        }

                        final double totalVendas = totaisSessao.values.fold(
                          0.0,
                          (sum, val) => sum + val,
                        );
                        final double totalSang = f.sangrias.fold(
                          0.0,
                          (sum, s) => sum + s.valor,
                        );
                        final double totalSup = f.suprimentos.fold(
                          0.0,
                          (sum, s) => sum + s.valor,
                        );

                        return [
                          ListTile(
                            title: const Text(
                              'Número do Caixa',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Text(
                              ab?.numero ?? 'N/A',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ListTile(
                            title: const Text(
                              'Abertura (Fundo de Troco)',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Text(
                              _formatoMoeda.format(ab?.valorInicial ?? 0.0),
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ListTile(
                            title: const Text(
                              'Entradas (Suprimentos)',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Text(
                              _formatoMoeda.format(totalSup),
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ListTile(
                            title: const Text(
                              'Saídas (Sangrias)',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Text(
                              _formatoMoeda.format(-totalSang),
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white10),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              'VENDAS NA SESSÃO',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          if (totaisSessao.isEmpty)
                            const ListTile(
                              title: Text(
                                'Nenhuma venda registrada na sessão',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          else
                            ...totaisSessao.entries.map(
                              (e) => ListTile(
                                dense: true,
                                title: Text(
                                  e.key
                                      .toString()
                                      .split('.')
                                      .last
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: Text(
                                  _formatoMoeda.format(e.value),
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ListTile(
                            title: const Text(
                              'Total de Vendas',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Text(
                              _formatoMoeda.format(totalVendas),
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white10),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              'CONFERÊNCIA DE VALORES',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          ListTile(
                            title: const Text(
                              'Valor Esperado',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Text(
                              _formatoMoeda.format(f.valorEsperado),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ListTile(
                            title: const Text(
                              'Valor Real Declarado',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Text(
                              _formatoMoeda.format(f.valorReal),
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ListTile(
                            title: const Text(
                              'Diferença',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            trailing: Text(
                              _formatoMoeda.format(f.diferenca),
                              style: TextStyle(
                                color: f.diferenca < 0
                                    ? Colors.redAccent
                                    : Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ];
                      }(),
                    if (item.sangria != null || item.suprimento != null) ...[
                      ListTile(
                        title: const Text(
                          'Motivo',
                          style: TextStyle(color: Colors.white70),
                        ),
                        subtitle: Text(
                          (item.sangria?.motivo ??
                                  item.suprimento?.motivo ??
                                  '')
                              .replaceAll('[PAGAMENTO] ', ''),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (item.responsavel != null)
                        ListTile(
                          title: const Text(
                            'Responsável',
                            style: TextStyle(color: Colors.white70),
                          ),
                          subtitle: Text(
                            item.responsavel!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      if (item.sangria?.observacao != null ||
                          item.suprimento?.observacao != null)
                        ListTile(
                          title: const Text(
                            'Observação',
                            style: TextStyle(color: Colors.white70),
                          ),
                          subtitle: Text(
                            item.sangria?.observacao ??
                                item.suprimento?.observacao ??
                                '',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                    ],
                    if (item.isQuebra) ...[
                      ListTile(
                        leading: const Icon(
                          Icons.broken_image_rounded,
                          color: Colors.orangeAccent,
                          size: 18,
                        ),
                        title: const Text(
                          'Produto',
                          style: TextStyle(color: Colors.white70),
                        ),
                        subtitle: Text(
                          item.clienteNome ?? 'Produto excluído',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ListTile(
                        title: const Text(
                          'Quantidade quebrada',
                          style: TextStyle(color: Colors.white70),
                        ),
                        subtitle: Text(
                          '${item.estoqueHistorico!.quantidade.abs().toStringAsFixed(2)} un',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if ((item.estoqueHistorico!.valorCusto ?? 0) > 0)
                        ListTile(
                          title: const Text(
                            'Prejuízo (custo)',
                            style: TextStyle(color: Colors.white70),
                          ),
                          subtitle: Text(
                            'R\$ ${item.estoqueHistorico!.valorCusto!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (item.estoqueHistorico!.observacao != null &&
                          item.estoqueHistorico!.observacao!.isNotEmpty)
                        ListTile(
                          title: const Text(
                            'Observação',
                            style: TextStyle(color: Colors.white70),
                          ),
                          subtitle: Text(
                            item.estoqueHistorico!.observacao!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      if (item.responsavel != null)
                        ListTile(
                          leading: const Icon(
                            Icons.person_pin_rounded,
                            color: Colors.white54,
                            size: 18,
                          ),
                          title: const Text(
                            'Responsável pela quebra',
                            style: TextStyle(color: Colors.white70),
                          ),
                          subtitle: Text(
                            item.responsavel!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                    ],
                    // Detalhes das formas de pagamento (split/parcial)
                    if (item.vendaBalcao != null &&
                        item.vendaBalcao!.pagamentos.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          'FORMAS DE PAGAMENTO',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      ...item.vendaBalcao!.pagamentos.map(
                        (pg) => ListTile(
                          dense: true,
                          leading: Icon(
                            pg.tipo.icone,
                            color: pg.tipo.cor,
                            size: 18,
                          ),
                          title: Text(
                            pg.tipo.nome,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            pg.recebido
                                ? 'Recebido'
                                : 'Pendente',
                            style: TextStyle(
                              color: pg.recebido
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                              fontSize: 11,
                            ),
                          ),
                          trailing: Text(
                            _formatoMoeda.format(pg.valor),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (item.pedido != null &&
                        item.pedido!.pagamentos.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          'FORMAS DE PAGAMENTO',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      ...item.pedido!.pagamentos.map(
                        (pg) => ListTile(
                          dense: true,
                          leading: Icon(
                            pg.tipo.icone,
                            color: pg.tipo.cor,
                            size: 18,
                          ),
                          title: Text(
                            pg.tipo.nome,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            pg.recebido
                                ? 'Recebido'
                                : 'Pendente',
                            style: TextStyle(
                              color: pg.recebido
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                              fontSize: 11,
                            ),
                          ),
                          trailing: Text(
                            _formatoMoeda.format(pg.valor),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (item.responsavel != null &&
                        (item.vendaBalcao != null || item.pedido != null))
                      ListTile(
                        leading: const Icon(
                          Icons.person_pin_rounded,
                          color: Colors.white54,
                          size: 18,
                        ),
                        title: const Text(
                          'Responsável pela venda',
                          style: TextStyle(color: Colors.white70),
                        ),
                        subtitle: Text(
                          item.responsavel!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    if (item.motoristaNome != null)
                      ListTile(
                        leading: const Icon(
                          Icons.two_wheeler_rounded,
                          color: Colors.lightBlueAccent,
                          size: 18,
                        ),
                        title: const Text(
                          'Motorista',
                          style: TextStyle(color: Colors.white70),
                        ),
                        subtitle: Text(
                          item.motoristaNome!,
                          style: const TextStyle(color: Colors.lightBlueAccent),
                        ),
                      ),
                    if (item.vendaBalcao?.observacoes != null)
                      ListTile(
                        title: const Text(
                          'Observações',
                          style: TextStyle(color: Colors.white70),
                        ),
                        subtitle: Text(
                          item.vendaBalcao!.observacoes!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    if (item.pedido?.observacoes != null)
                      ListTile(
                        title: const Text(
                          'Observações',
                          style: TextStyle(color: Colors.white70),
                        ),
                        subtitle: Text(
                          item.pedido!.observacoes!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'VALOR TOTAL:',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatoMoeda.format(item.valorTotal),
                      style: TextStyle(
                        color: item.isCancelada
                            ? Colors.white24
                            : (item.isSangria || item.isPagamento
                                  ? Colors.redAccent
                                  : Colors.greenAccent),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Seção de NFC-e
              if (!item.isCancelada &&
                  (item.vendaBalcao != null || item.pedido != null) &&
                  !item.isSangria &&
                  !item.isSuprimento &&
                  item.fechamentoCaixa == null) ...[
                if (nfceExistente != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.greenAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'NFC-e EMITIDA E AUTORIZADA',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Nº ${nfceExistente.numero}',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Chave: ${nfceExistente.chaveAcesso ?? "Não informada"}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            if (nfceExistente.chaveAcesso != null && nfceExistente.chaveAcesso!.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy, size: 14, color: Colors.blueAccent),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Copiar chave completa',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: nfceExistente.chaveAcesso!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✓ Chave de acesso copiada para a área de transferência!'),
                                      duration: Duration(seconds: 2),
                                      backgroundColor: Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  final authService = Provider.of<AuthService>(
                                    context,
                                    listen: false,
                                  );
                                  final emp = authService.empresaAtual;
                                  if (emp != null) {
                                    DANFEService.visualizarPDF(
                                      context: context,
                                      nfce: nfceExistente,
                                      empresa: emp,
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.picture_as_pdf,
                                  size: 14,
                                  color: Colors.cyanAccent,
                                ),
                                label: const Text(
                                  'VISUALIZAR',
                                  style: TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 11,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Colors.cyanAccent,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  final authService = Provider.of<AuthService>(
                                    context,
                                    listen: false,
                                  );
                                  final emp = authService.empresaAtual;
                                  if (emp != null) {
                                    DANFEService.imprimir(
                                      nfce: nfceExistente,
                                      empresa: emp,
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.print,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'IMPRIMIR',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _mostrarDialogoEmissaoNFCe(item),
                      icon: const Icon(Icons.receipt_long, color: Colors.white),
                      label: const Text(
                        'EMITIR NFC-e PARA ESTA VENDA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.withOpacity(0.8),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
              // Botão de Reimpressão do Cupom Não Fiscal
              if (!item.isCancelada &&
                  (item.vendaBalcao != null || item.pedido != null) &&
                  !item.isSangria &&
                  !item.isSuprimento &&
                  item.fechamentoCaixa == null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _reimprimirCupomNaoFiscal(item),
                    icon: const Icon(Icons.print, color: Colors.cyanAccent),
                    label: const Text(
                      'REIMPRIMIR CUPOM NÃO FISCAL',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.cyanAccent),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Botão de Cancelamento (Apenas se não estiver cancelado e for venda/pedido)
              if (!item.isCancelada &&
                  (item.vendaBalcao != null || item.pedido != null) &&
                  !item.isSangria &&
                  !item.isSuprimento &&
                  item.fechamentoCaixa == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmarCancelamento(item),
                    icon: const Icon(Icons.cancel, color: Colors.white),
                    label: const Text(
                      'CANCELAR ESTA VENDA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.8),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (item.trocaDevolucao != null && !item.isCancelada)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmarCancelamentoTroca(item),
                    icon: const Icon(Icons.undo, color: Colors.white),
                    label: const Text(
                      'CANCELAR LANÇAMENTO',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent.withOpacity(0.85),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              // Botão de Troca/Devolução (Apenas se não estiver cancelado e for venda/pedido)
              if (!item.isCancelada &&
                  (item.vendaBalcao != null || item.pedido != null) &&
                  !item.isSangria &&
                  !item.isSuprimento &&
                  item.fechamentoCaixa == null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final vParaTroca = item.vendaBalcao != null
                          ? VendaParaTroca.fromVendaBalcao(item.vendaBalcao!)
                          : VendaParaTroca.fromPedido(item.pedido!);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              SelecionarItensTrocaPage(venda: vParaTroca),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.swap_horiz,
                      color: Colors.orangeAccent,
                    ),
                    label: const Text(
                      'TROCAR OU DEVOLVER ITENS',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.orangeAccent),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _reimprimirCupomNaoFiscal(ItemHistorico item) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final emp = authService.empresaAtual;
      if (emp == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma empresa selecionada para imprimir o cupom'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      if (item.vendaBalcao != null) {
        await VendaPDFService.imprimirPDFTermico(
          venda: item.vendaBalcao!,
          empresa: emp,
          context: context,
        );
      } else if (item.pedido != null) {
        await PedidoPDFService.imprimirPDFTermico(
          pedido: item.pedido!,
          empresa: emp,
          context: context,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reimprimir cupom: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _confirmarCancelamento(ItemHistorico item) {
    final dataService = Provider.of<DataService>(context, listen: false);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 12),
            Text(
              'Confirmar Cancelamento',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja realmente cancelar ${item.tipo} ${item.numero}?',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            const Text(
              'Esta ação irá reverter os valores no sistema e no caixa. Esta operação não pode ser desfeita.',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'BOA, MANTER',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Fecha o dialog
              Navigator.pop(context); // Fecha o modal de detalhes

              try {
                if (item.vendaBalcao != null) {
                  await dataService.cancelarVendaBalcao(item.id);
                } else if (item.pedido != null) {
                  await dataService.cancelarPedido(item.id);
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${item.tipo} cancelado(a) com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao cancelar: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text(
              'SIM, CANCELAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmarCancelamentoTroca(ItemHistorico item) {
    final dataService = Provider.of<DataService>(context, listen: false);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 12),
            Text('Cancelar lançamento', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja cancelar este lançamento de ${item.tipo.toLowerCase()}?\n\nO registro ficará marcado como cancelado e permanecerá no histórico para auditoria.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            const Text(
              'Atenção: a operação não será removida do sistema.',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('MANTER', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              Navigator.pop(context);

              try {
                if (item.trocaDevolucao != null) {
                  await dataService.cancelarTrocaDevolucao(
                    item.trocaDevolucao!.id,
                  );
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${item.tipo} cancelado(a) e mantido no histórico!',
                      ),
                      backgroundColor: Colors.orangeAccent,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao cancelar lançamento: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
            ),
            child: const Text(
              'SIM, CANCELAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarResumoCaixas(
    BuildContext context,
    List<ItemHistorico> itens,
    DataService dataService,
  ) {
    final aberturaCaixa = dataService.aberturaCaixaAtual;
    final isAberto = dataService.caixaAberto && aberturaCaixa != null;
    List<ItemHistorico> itensSessao;
    double abertura;
    if (isAberto) {
      final Map<String, ItemHistorico> mapItensSessao = {};

      // Somente vendas do MESMO operador do caixa (getVendasDoCaixa já filtra
      // por operador e pela janela [abertura, fechamento]).
      final vendasSessao = dataService.getVendasDoCaixa(aberturaCaixa);

      for (var v in vendasSessao) {
        final foiRecebida = (v.valorRecebido ?? 0) > 0;
        final isCancelada = v.isCancelada;
        if (!foiRecebida && !isCancelada) continue;
        mapItensSessao[v.id] = ItemHistorico.fromVendaBalcao(v);
      }

      // Pedidos do mesmo operador do caixa, dentro da janela de abertura.
      final respCaixa = aberturaCaixa.responsavel?.trim().toLowerCase();
      final temRespCaixa = respCaixa != null && respCaixa.isNotEmpty;
      bool mesmoOperador(String? a, String? b) {
        if (a == null || b == null) return false;
        String norm(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9@]'), '');
        final na = norm(a), nb = norm(b);
        if (na.isEmpty || nb.isEmpty) return false;
        if (na == nb) return true;
        final localA = na.contains('@') ? na.split('@').first : na;
        final localB = nb.contains('@') ? nb.split('@').first : nb;
        return localA == localB && localA.isNotEmpty;
      }

      final pedidosSessao = dataService.pedidos.where((p) {
        if (!(p.dataPedido.isAfter(aberturaCaixa.dataAbertura) ||
              p.dataPedido.isAtSameMomentAs(aberturaCaixa.dataAbertura))) {
          return false;
        }
        if (temRespCaixa) {
          final operadorPedido = p.vendedorNome;
          if (operadorPedido == null || operadorPedido.trim().isEmpty) return false;
          if (!mesmoOperador(operadorPedido, respCaixa)) return false;
        }
        return true;
      }).toList();

      for (var p in pedidosSessao) {
        final isPendente = p.status.toLowerCase() == 'pendente';
        if (mapItensSessao.containsKey(p.id)) {
          final existing = mapItensSessao[p.id]!;
          final TipoPagamento? novoTipo = p.pagamentos.isNotEmpty
              ? p.pagamentos.first.tipo
              : existing.tipoPagamento;
          mapItensSessao[p.id] = existing.copyWith(pedido: p, tipoPagamento: novoTipo);
        } else if (!isPendente) {
          mapItensSessao[p.id] = ItemHistorico.fromPedido(p);
        }
      }

      itensSessao = mapItensSessao.values.toList();
      abertura = aberturaCaixa.valorInicial;
    } else {
      itensSessao = itens;
      abertura = 0;
      final aberturasNoPeriodo = dataService.aberturasCaixa
          .where(
            (a) =>
                a.dataAbertura.isAfter(_dataInicio) &&
                a.dataAbertura.isBefore(_dataFim),
          )
          .toList();
      if (aberturasNoPeriodo.isNotEmpty) {
        aberturasNoPeriodo.sort(
          (a, b) => b.dataAbertura.compareTo(a.dataAbertura),
        );
        abertura = aberturasNoPeriodo.first.valorInicial;
      }
    }
    final todasSangrias = dataService.sangrias;
    final pagamentos = todasSangrias.where((s) {
      if (!s.motivo.startsWith('[PAGAMENTO]')) return false;
      if (isAberto)
        return s.data.isAfter(aberturaCaixa.dataAbertura) ||
            s.data.isAtSameMomentAs(aberturaCaixa.dataAbertura);
      return s.data.isAfter(_dataInicio) && s.data.isBefore(_dataFim);
    }).toList();
    final sangriasGeral = todasSangrias.where((s) {
      if (s.motivo.startsWith('[PAGAMENTO]')) return false;
      if (isAberto)
        return s.data.isAfter(aberturaCaixa.dataAbertura) ||
            s.data.isAtSameMomentAs(aberturaCaixa.dataAbertura);
      return s.data.isAfter(_dataInicio) && s.data.isBefore(_dataFim);
    }).toList();
    final suprimentos = dataService.suprimentos.where((s) {
      if (isAberto)
        return s.data.isAfter(aberturaCaixa.dataAbertura) ||
            s.data.isAtSameMomentAs(aberturaCaixa.dataAbertura);
      return s.data.isAfter(_dataInicio) && s.data.isBefore(_dataFim);
    }).toList();
    final vendasValidas = itensSessao
        .where((i) => !i.isCancelada && i.fechamentoCaixa == null)
        .toList();
    final totalPagamentos = pagamentos.fold(0.0, (sum, s) => sum + s.valor);
    final totalS = sangriasGeral.fold(0.0, (sum, s) => sum + s.valor);
    final totalSup = suprimentos.fold(0.0, (sum, s) => sum + s.valor);
    final Map<TipoPagamento, double> totaisPorTipo = {};
    double totalVendas = 0;

    final Map<String, double> itemQuantities = {};
    final Map<String, double> itemTotals = {};
    final List<String> itensDeletadosMesa = [];
    final List<ItemHistorico> vendasCanceladasSessao = [];

    // Coletar itens cancelados de mesas/comandas que ainda estão ABERTAS
    for (var mesa in dataService.mesasComandas) {
      final cancelados = mesa.itens.where((i) {
        if (i.status != StatusItem.cancelado) return false;
        if (i.dataModificacao == null) return false;
        if (isAberto) {
          return i.dataModificacao!.isAfter(aberturaCaixa.dataAbertura) ||
                 i.dataModificacao!.isAtSameMomentAs(aberturaCaixa.dataAbertura);
        } else {
          return i.dataModificacao!.isAfter(_dataInicio) && i.dataModificacao!.isBefore(_dataFim);
        }
      }).toList();
      
      if (cancelados.isNotEmpty) {
        final labelOrigem = mesa.tipo == TipoControle.comanda ? '[COMANDA]' : '[MESA]';
        final canceladosInfo = cancelados.map((i) => 
          '${i.quantidade.toStringAsFixed(0)}x ${i.nome} por ${i.usuarioModificou ?? "Sistema"}'
        ).join(', ');
        itensDeletadosMesa.add('$labelOrigem ${mesa.numero} (Aberta): $canceladosInfo');
      }
    }

    // 1. Processar vendas válidas (ativas)
    for (var i in vendasValidas) {
      if (i.vendaBalcao != null && i.vendaBalcao!.observacoes != null && i.vendaBalcao!.observacoes!.contains('CANCELADOS:')) {
        final parts = i.vendaBalcao!.observacoes!.split('CANCELADOS:');
        if (parts.length > 1) {
          final orig = i.vendaBalcao!.observacoes!.split('|').first.replaceAll('[VIP-MC] originado de ', '').trim();
          itensDeletadosMesa.add('$orig: ${parts[1].trim()}');
        }
      }

      if (i.vendaBalcao != null) {
        for (var item in i.vendaBalcao!.itens) {
          itemQuantities[item.nome] = (itemQuantities[item.nome] ?? 0.0) + item.quantidade;
          itemTotals[item.nome] = (itemTotals[item.nome] ?? 0.0) + (item.precoUnitario * item.quantidade);
        }
      } else if (i.pedido != null) {
        for (var item in i.pedido!.produtos) {
          itemQuantities[item.nome] = (itemQuantities[item.nome] ?? 0.0) + item.quantidade;
          itemTotals[item.nome] = (itemTotals[item.nome] ?? 0.0) + (item.preco * item.quantidade);
        }
      }
    }

    // 2. Processar vendas canceladas e coletar deleções delas se houver
    for (var i in itensSessao) {
      if (i.isCancelada) {
        vendasCanceladasSessao.add(i);
        if (i.vendaBalcao != null && i.vendaBalcao!.observacoes != null && i.vendaBalcao!.observacoes!.contains('CANCELADOS:')) {
          final parts = i.vendaBalcao!.observacoes!.split('CANCELADOS:');
          if (parts.length > 1) {
            final orig = i.vendaBalcao!.observacoes!.split('|').first.replaceAll('[VIP-MC] originado de ', '').trim();
            itensDeletadosMesa.add('$orig (Venda Canc.): ${parts[1].trim()}');
          }
        }
      }
    }

    for (var i in vendasValidas) {
      if (i.pedido != null) {
        for (var pag in i.pedido!.pagamentos.where((p) => p.recebido)) {
          if (isAberto) {
            if (pag.dataRecebimento == null ||
                pag.dataRecebimento!.isBefore(aberturaCaixa.dataAbertura))
              continue;
          }
          totaisPorTipo[pag.tipo] =
              (totaisPorTipo[pag.tipo] ?? 0.0) + pag.valor;
          totalVendas += pag.valor;
        }
      } else if (i.vendaBalcao != null) {
        // Se a venda tem múltiplas formas de pagamento, somar cada forma individualmente
        final pagsVenda = i.vendaBalcao!.pagamentos;
        if (pagsVenda.isNotEmpty) {
          for (final pag in pagsVenda.where((p) => p.recebido)) {
            totaisPorTipo[pag.tipo] =
                (totaisPorTipo[pag.tipo] ?? 0.0) + pag.valor;
          }
          totalVendas += i.vendaBalcao!.valorTotal;
        } else {
          totaisPorTipo[i.vendaBalcao!.tipoPagamento] =
              (totaisPorTipo[i.vendaBalcao!.tipoPagamento] ?? 0.0) +
              i.vendaBalcao!.valorTotal;
          totalVendas += i.vendaBalcao!.valorTotal;
        }
      }
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resumo de Caixa Inteligente',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isAberto
                          ? 'CAIXA ATUAL: ${aberturaCaixa.numero} (Aberto em ${DateFormat('HH:mm').format(aberturaCaixa.dataAbertura)})'
                          : 'RESUMO DO PERÍODO SELECIONADO',
                      style: TextStyle(
                        color: isAberto ? Colors.greenAccent : Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView(
                children: [
                  _tileResumo('Abertura de Caixa', abertura, Colors.blueAccent),
                  _tileResumo(
                    'Entradas (Suprimentos)',
                    totalSup,
                    Colors.cyanAccent,
                  ),
                  if (totalPagamentos > 0)
                    InkWell(
                      onTap: () => _mostrarDetalhesSaidas(
                        context,
                        'Pagamentos Efetuados',
                        pagamentos,
                      ),
                      child: _tileResumo(
                        'Pagamentos (Saídas)',
                        -totalPagamentos,
                        Colors.purpleAccent,
                        showChevron: true,
                      ),
                    ),
                  if (totalS > 0)
                    InkWell(
                      onTap: () => _mostrarDetalhesSaidas(
                        context,
                        'Sangrias Realizadas',
                        sangriasGeral,
                      ),
                      child: _tileResumo(
                        'Sangrias (Retiradas)',
                        -totalS,
                        Colors.orangeAccent,
                        showChevron: true,
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'VENDAS POR FORMA DE PAGAMENTO',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ...totaisPorTipo.entries.map(
                    (e) => InkWell(
                      onTap: () =>
                          _mostrarVendasDoTipo(context, e.key, vendasValidas),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _getIconePagamento(e.key),
                                  color: Colors.white70,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  e.key
                                      .toString()
                                      .split('.')
                                      .last
                                      .toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(
                                  _formatoMoeda.format(e.value),
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white24,
                                  size: 16,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 32),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: Column(
                      children: [
                        ExpansionTile(
                          title: const Text(
                            'PRODUTOS VENDIDOS NO PERÍODO',
                            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                          ),
                          leading: const Icon(Icons.shopping_bag_outlined, color: Colors.white54, size: 20),
                          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          children: itemQuantities.isEmpty
                              ? [const Text('Nenhum item vendido', style: TextStyle(color: Colors.white38, fontSize: 12))]
                              : itemQuantities.entries.map((e) {
                                  final nome = e.key;
                                  final qtd = e.value;
                                  final totalVal = itemTotals[nome] ?? 0.0;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${qtd.toStringAsFixed(0)}x $nome',
                                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                        ),
                                        Text(
                                          _formatoMoeda.format(totalVal),
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                        ),
                        ExpansionTile(
                          title: Text(
                            'VENDAS CANCELADAS (${vendasCanceladasSessao.length})',
                            style: TextStyle(
                              color: vendasCanceladasSessao.isNotEmpty ? Colors.redAccent : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          leading: Icon(Icons.cancel_outlined, color: vendasCanceladasSessao.isNotEmpty ? Colors.redAccent : Colors.white54, size: 20),
                          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          children: vendasCanceladasSessao.isEmpty
                              ? [const Text('Nenhuma venda cancelada', style: TextStyle(color: Colors.white38, fontSize: 12))]
                              : vendasCanceladasSessao.map((v) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${v.numero} - ${v.clienteNome ?? "Consumidor"}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                                        ),
                                        Text(
                                          _formatoMoeda.format(v.valorTotal),
                                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                        ),
                        ExpansionTile(
                          title: Text(
                            'ITENS DELETADOS (CARRINHO/MESAS) (${itensDeletadosMesa.length})',
                            style: TextStyle(
                              color: itensDeletadosMesa.isNotEmpty ? Colors.orangeAccent : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          leading: Icon(Icons.delete_outline, color: itensDeletadosMesa.isNotEmpty ? Colors.orangeAccent : Colors.white54, size: 20),
                          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          children: itensDeletadosMesa.isEmpty
                              ? [const Text('Nenhum item removido', style: TextStyle(color: Colors.white38, fontSize: 12))]
                              : itensDeletadosMesa.map((text) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        text,
                                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                                      ),
                                    ),
                                  );
                                }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 32),
                  _tileResumo(
                    'TOTAL ESPERADO EM CAIXA',
                    abertura +
                        totalVendas +
                        totalSup -
                        totalPagamentos -
                        totalS,
                    Colors.white,
                    isTotal: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (dataService.caixaAberto)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _confirmarFechamentoInteligente(
                      context,
                      dataService,
                      aberturaCaixa!,
                      totaisPorTipo,
                      totalSup,
                      totalS,
                    );
                  },
                  icon: const Icon(Icons.lock_outline, color: Colors.white),
                  label: const Text(
                    'REALIZAR FECHAMENTO DETALHADO',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.2),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_user,
                      color: Colors.greenAccent,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'CAIXA FECHADO',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getIconePagamento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.payments_outlined;
      case TipoPagamento.pix:
        return Icons.qr_code_2_rounded;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card_rounded;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_score_rounded;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  void _mostrarVendasDoTipo(
    BuildContext context,
    TipoPagamento tipo,
    List<ItemHistorico> vendas,
  ) {
    // Filtrar vendas que possuem este tipo de pagamento
    final filtradas = vendas.where((v) {
      if (v.isCancelada) return false;

      // Se for Sangria ou Suprimento, verificar o tipoPagamento (geralmente dinheiro)
      if (v.isSangria || v.isSuprimento || v.isPagamento) {
        return (v.tipoPagamento ?? TipoPagamento.dinheiro) == tipo;
      }

      // Se for Venda Direta
      if (v.vendaBalcao != null) {
        // Se tem múltiplas formas (split), considerar se ALGUMA delas é do tipo
        final pagsVenda = v.vendaBalcao!.pagamentos;
        if (pagsVenda.isNotEmpty) {
          return pagsVenda.any((p) => p.recebido && p.tipo == tipo);
        }
        return v.vendaBalcao!.tipoPagamento == tipo;
      }

      // Se for Pedido, verificar se algum dos pagamentos recebidos é do tipo
      if (v.pedido != null) {
        return v.pedido!.pagamentos.any((p) => p.recebido && p.tipo == tipo);
      }

      // Fallback
      return v.tipoPagamento == tipo;
    }).toList();

    String queryModal = '';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161621),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            final queryLower = queryModal.trim().toLowerCase();
            final exibidas = queryLower.isEmpty
                ? filtradas
                : filtradas.where((v) {
                    if (v.numero.toLowerCase().contains(queryLower)) return true;
                    final numericoQuery = queryLower.replaceAll(RegExp(r'[^0-9]'), '');
                    if (numericoQuery.isNotEmpty) {
                      final numericoVenda = v.numero.replaceAll(RegExp(r'[^0-9]'), '');
                      final querySemZeros = int.tryParse(numericoQuery)?.toString() ?? numericoQuery;
                      final vendaSemZeros = int.tryParse(numericoVenda)?.toString() ?? numericoVenda;
                      if (vendaSemZeros.contains(querySemZeros)) return true;
                    }
                    if (v.clienteNome != null && v.clienteNome!.toLowerCase().contains(queryLower)) return true;
                    if (v.vendaBalcao != null) {
                      if (v.vendaBalcao!.itens.any((item) => item.nome.toLowerCase().contains(queryLower))) {
                        return true;
                      }
                    }
                    if (v.pedido != null) {
                      if (v.pedido!.produtos.any((item) => item.nome.toLowerCase().contains(queryLower)) ||
                          v.pedido!.servicos.any((item) => item.descricao.toLowerCase().contains(queryLower))) {
                        return true;
                      }
                    }
                    return false;
                  }).toList();

            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tipo.cor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(tipo.icone, color: tipo.cor, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vendas em ${tipo.nome.toUpperCase()}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${exibidas.length} itens encontrados',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white38),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        icon: const Icon(Icons.search, color: Colors.white38, size: 20),
                        hintText: 'Buscar por número ou item...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        suffixIcon: queryModal.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                                onPressed: () {
                                  setModalState(() {
                                    queryModal = '';
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          queryModal = val;
                        });
                      },
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 32),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: exibidas.length,
                      itemBuilder: (context, index) {
                        final v = exibidas[index];

                    // Calcular o valor específico deste tipo de pagamento se for multi-pagamento
                    double valorNesteTipo = v.valorTotal;
                    if (v.pedido != null) {
                      valorNesteTipo = v.pedido!.pagamentos
                          .where((p) => p.recebido && p.tipo == tipo)
                          .fold(0.0, (sum, p) => sum + p.valor);
                    } else if (v.vendaBalcao != null &&
                        v.vendaBalcao!.pagamentos.isNotEmpty) {
                      valorNesteTipo = v.vendaBalcao!.pagamentos
                          .where((p) => p.recebido && p.tipo == tipo)
                          .fold(0.0, (sum, p) => sum + p.valor);
                    } else if (v.isSangria || v.isPagamento) {
                      valorNesteTipo = -v.valorTotal;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        onTap: () {
                          Navigator.pop(context);
                          _mostrarDetalhesVenda(v);
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            v.isSangria || v.isPagamento
                                ? Icons.remove_circle_outline
                                : Icons.add_circle_outline,
                            color: v.isSangria || v.isPagamento
                                ? Colors.redAccent
                                : Colors.greenAccent,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          v.numero,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${DateFormat('HH:mm').format(v.data.toLocal())} • ${v.clienteNome ?? "Consumidor"}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Text(
                          _formatoMoeda.format(valorNesteTipo),
                          style: TextStyle(
                            color: valorNesteTipo < 0
                                ? Colors.redAccent
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
    ),
    );
  }

  void _mostrarDetalhesSaidas(
    BuildContext context,
    String titulo,
    List<SangriaCaixa> lista,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              titulo,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                itemCount: lista.length,
                itemBuilder: (context, index) {
                  final s = lista[index];
                  String motivo = s.motivo.replaceAll('[PAGAMENTO] ', '');
                  return ListTile(
                    title: Text(
                      motivo,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      DateFormat('HH:mm').format(s.data.toLocal()),
                      style: const TextStyle(color: Colors.white38),
                    ),
                    trailing: Text(
                      _formatoMoeda.format(s.valor),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarFechamentoInteligente(
    BuildContext context,
    DataService ds,
    AberturaCaixa abertura,
    Map<TipoPagamento, double> totaisEsperados,
    double suprimentos,
    double sangriasTotais,
  ) {
    final Map<TipoPagamento, TextEditingController> controllers = {};
    for (var tipo in TipoPagamento.values) {
      double esperado = totaisEsperados[tipo] ?? 0.0;
      if (tipo == TipoPagamento.dinheiro) {
        esperado += abertura.valorInicial + suprimentos - sangriasTotais;
      }
      controllers[tipo] = TextEditingController(
        text: esperado > 0
            ? esperado.toStringAsFixed(2).replaceAll('.', ',')
            : '0,00',
      );
    }

    final TextEditingController responsavelController = TextEditingController();
    final TextEditingController observacaoController = TextEditingController();

    bool salvandoFechamento = false;

    Future<void> fecharHistorico() async {
      if (salvandoFechamento) {
        debugPrint('>>> [fecharHistorico] Ignorando clique duplicado...');
        return;
      }
      salvandoFechamento = true;
      try {
        debugPrint('>>> [fecharHistorico] Iniciando fechamento');

        final String obsDetalhada = observacaoController.text.trim();

        if (responsavelController.text.trim().isEmpty) {
          salvandoFechamento = false;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Informe o nome de quem está fechando o caixa.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        final double somaReal = controllers.values.fold(
          0.0,
          (sum, ctrl) =>
              sum + (double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0),
        );
        final double somaEsperada = TipoPagamento.values.fold(0.0, (sum, tipo) {
          double esperado = totaisEsperados[tipo] ?? 0;
          if (tipo == TipoPagamento.dinheiro)
            esperado += abertura.valorInicial + suprimentos - sangriasTotais;
          return sum + esperado;
        });

        debugPrint(
          '>>> [fecharHistorico] Registrando: soma_esperada=$somaEsperada, soma_real=$somaReal',
        );

        final fechamento = await ds.registrarFechamentoCaixa(
          valorEsperado: somaEsperada,
          valorReal: somaReal,
          diferenca: somaReal - somaEsperada,
          observacao: obsDetalhada.isNotEmpty ? obsDetalhada : null,
          responsavel: responsavelController.text.trim(),
          abertura: abertura,
        );

        if (fechamento == null) {
          debugPrint('>>> [fecharHistorico] Erro: fechamento é null');
          salvandoFechamento = false;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Erro ao fechar caixa.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        if (!context.mounted) {
          debugPrint('>>> [fecharHistorico] Context não montado, abortando');
          return;
        }

        debugPrint('>>> [fecharHistorico] Mostrando pergunta de impressão');
        final bool imprimirEscolhido =
            await showDialog<bool>(
              context: context,
              useRootNavigator: true,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E2E),
                title: const Text(
                  'Imprimir Fechamento?',
                  style: TextStyle(color: Colors.white),
                ),
                content: const Text(
                  'Deseja imprimir o recibo do fechamento de caixa?',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text(
                      'NÃO',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                    ),
                    child: const Text(
                      'SIM, IMPRIMIR',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ) ??
            false;

        if (imprimirEscolhido) {
          _imprimirFechamentoCaixa(context, abertura, fechamento, ds);
        }

        debugPrint('>>> [fecharHistorico] Fechando diálogo de conferência');
        Navigator.pop(context);

        debugPrint('>>> [fecharHistorico] Navegando para HomePage');
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
        );

        debugPrint('>>> [fecharHistorico] Completado');
      } catch (e, stack) {
        debugPrint('>>> [fecharHistorico] ERRO: $e');
        debugPrintStack(stackTrace: stack);
        salvandoFechamento = false;
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double somaReal = 0;
          double somaEsperada = 0;
          controllers.forEach((tipo, ctrl) {
            somaReal += double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
            double esperado = totaisEsperados[tipo] ?? 0;
            if (tipo == TipoPagamento.dinheiro)
              esperado += abertura.valorInicial + suprimentos - sangriasTotais;
            somaEsperada += esperado;
          });
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text(
              'Conferência de Valores',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...TipoPagamento.values.map((tipo) {
                      double esperado = totaisEsperados[tipo] ?? 0;
                      if (tipo == TipoPagamento.dinheiro)
                        esperado +=
                            abertura.valorInicial +
                            suprimentos -
                            sangriasTotais;
                      if (esperado <= 0 &&
                          (double.tryParse(controllers[tipo]!.text) ?? 0) == 0)
                        return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  tipo.toString().split('.').last.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'Esperado: ${_formatoMoeda.format(esperado)}',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: controllers[tipo],
                              onChanged: (_) => setDialogState(() {}),
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                prefixText: r'R$ ',
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(color: Colors.white10),
                    _tileResumoDialog(
                      'TOTAL ESPERADO',
                      somaEsperada,
                      Colors.white38,
                    ),
                    _tileResumoDialog(
                      'TOTAL INFORMADO',
                      somaReal,
                      Colors.white,
                    ),
                    _tileResumoDialog(
                      'DIFERENÇA GERAL',
                      somaReal - somaEsperada,
                      (somaReal - somaEsperada) >= 0
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      isTotal: true,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: responsavelController,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Responsável pelo fechamento',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: observacaoController,
                      keyboardType: TextInputType.text,
                      maxLines: 3,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Observações (opcional)',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'VOLTAR',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  await fecharHistorico();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                child: const Text(
                  'FECHAR CAIXA',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _imprimirFechamentoCaixa(
    BuildContext context,
    AberturaCaixa abertura,
    FechamentoCaixa fechamento,
    DataService ds,
  ) {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa == null) return;

      final vendas = ds.vendasBalcao.where((v) {
        return (v.dataVenda.isAfter(abertura.dataAbertura) ||
                v.dataVenda.isAtSameMomentAs(abertura.dataAbertura)) &&
            v.dataVenda.isBefore(
              fechamento.dataFechamento.add(const Duration(seconds: 1)),
            );
      }).toList();

      final List<String> canceladosExtra = [];
      for (var mesa in ds.mesasComandas) {
        final cancelados = mesa.itens.where((i) {
          if (i.status != StatusItem.cancelado) return false;
          if (i.dataModificacao == null) return false;
          return (i.dataModificacao!.isAfter(abertura.dataAbertura) ||
                  i.dataModificacao!.isAtSameMomentAs(abertura.dataAbertura)) &&
                 i.dataModificacao!.isBefore(fechamento.dataFechamento.add(const Duration(seconds: 1)));
        }).toList();
        if (cancelados.isNotEmpty) {
          final labelOrigem = mesa.tipo == TipoControle.comanda ? '[COMANDA]' : '[MESA]';
          final canceladosInfo = cancelados.map((i) => 
            '${i.quantidade.toStringAsFixed(0)}x ${i.nome} por ${i.usuarioModificou ?? "Sistema"}'
          ).join(', ');
          canceladosExtra.add('$labelOrigem ${mesa.numero} (Aberta): $canceladosInfo');
        }
      }

      CaixaPDFService.gerarPDFTermico(
            abertura: abertura,
            fechamento: fechamento,
            empresa: empresa,
            vendas: vendas,
            itensDeletadosExtra: canceladosExtra,
          )
          .then((pdfData) async {
            try {
              await Printing.layoutPdf(
                onLayout: (format) async => pdfData,
                name: 'Fechamento_Caixa_${abertura.numero}.pdf',
              );
            } catch (e) {
              debugPrint('Erro ao exibir PDF: $e');
            }
          })
          .catchError((e) {
            debugPrint('Erro ao gerar PDF: $e');
          });
    } catch (e) {
      debugPrint('Erro na impressão: $e');
    }
  }

  Widget _tileResumoDialog(
    String L,
    double v,
    Color c, {
    bool isTotal = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          L,
          style: TextStyle(
            color: Colors.white54,
            fontSize: isTotal ? 14 : 12,
            fontWeight: isTotal ? FontWeight.bold : null,
          ),
        ),
        Text(
          _formatoMoeda.format(v),
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.bold,
            fontSize: isTotal ? 16 : 13,
          ),
        ),
      ],
    ),
  );

  Widget _tileResumo(
    String L,
    double v,
    Color c, {
    bool isTotal = false,
    bool showChevron = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              L,
              style: TextStyle(
                color: Colors.white70,
                fontWeight: isTotal ? FontWeight.bold : null,
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right, color: Colors.white24, size: 14),
          ],
        ),
        Text(
          _formatoMoeda.format(v),
          style: TextStyle(color: c, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  void _mostrarVendasPorProduto(
    BuildContext context,
    DataService dataService,
    List<ItemHistorico> itens,
  ) {
    // Só bloqueia a abertura se não houver nenhuma venda em todo o sistema;
    // como o modal tem filtro de período próprio, o usuário pode escolher
    // outro intervalo mesmo que o período atual da página esteja vazio.
    if (itens.isEmpty &&
        dataService.vendasBalcao.isEmpty &&
        dataService.pedidos.isEmpty) {
      return;
    }

    // Filtros próprios da Análise de Produtos (não alteram o período da página)
    DateTime analiseInicio = _dataInicio;
    DateTime analiseFim = _dataFim;
    String formaFiltro = 'Todas';

    // Verifica se o item foi pago com a forma selecionada (suporta split)
    bool itemUsaFormaPagamento(ItemHistorico i, String forma) {
      if (forma == 'Todas') return true;
      final tp = TipoPagamento.values
          .where((t) => t.nome == forma)
          .firstOrNull;
      if (tp == null) return false;
      final pagamentos = <PagamentoPedido>[
        ...?i.vendaBalcao?.pagamentos,
        ...?i.pedido?.pagamentos,
      ];
      if (pagamentos.isNotEmpty) return pagamentos.any((p) => p.tipo == tp);
      return i.tipoPagamento == tp;
    }

    // Agrega os produtos vendidos a partir de uma lista de itens
    List<_ProdutoVendido> agregarProdutos(List<ItemHistorico> lista) {
      final Map<String, _ProdutoVendido> produtosMap = {};
      for (var i in lista) {
        if (i.isCancelada ||
            i.isSangria ||
            i.isSuprimento ||
            i.fechamentoCaixa != null)
          continue;

        if (i.vendaBalcao != null) {
          for (var iv in i.vendaBalcao!.itens) {
            final id = iv.id;
            produtosMap.putIfAbsent(
              id,
              () => _ProdutoVendido(nome: iv.nome, produtoId: iv.id),
            );
            produtosMap[id]!.quantidadeTotal += iv.quantidade.toInt();
            produtosMap[id]!.valorTotal +=
                (iv.precoUnitario * iv.quantidade);

            final prod = dataService.produtos
                .where((p) => p.id == iv.id || p.nome == iv.nome)
                .firstOrNull;
            if (prod != null && prod.precoCusto != null) {
              produtosMap[id]!.custoTotal =
                  (produtosMap[id]!.custoTotal ?? 0.0) +
                  (prod.precoCusto! * iv.quantidade);
            }
            produtosMap[id]!.vendas.add(
              _VendaProduto(
                numeroVenda: i.numero,
                data: i.data,
                quantidade: iv.quantidade.toInt(),
                precoUnitario: iv.precoUnitario,
                valorTotal: iv.precoUnitario * iv.quantidade,
                clienteNome: i.clienteNome,
              ),
            );
          }
        } else if (i.pedido != null) {
          for (var ip in i.pedido!.produtos) {
            final id = ip.nome;
            produtosMap.putIfAbsent(id, () => _ProdutoVendido(nome: ip.nome));
            produtosMap[id]!.quantidadeTotal += ip.quantidade.toInt();
            produtosMap[id]!.valorTotal += (ip.preco * ip.quantidade);

            final prod = dataService.produtos
                .where((p) => p.nome == ip.nome)
                .firstOrNull;
            if (prod != null && prod.precoCusto != null) {
              produtosMap[id]!.custoTotal =
                  (produtosMap[id]!.custoTotal ?? 0.0) +
                  (prod.precoCusto! * ip.quantidade);
            }
            produtosMap[id]!.vendas.add(
              _VendaProduto(
                numeroVenda: i.numero,
                data: i.data,
                quantidade: ip.quantidade.toInt(),
                precoUnitario: ip.preco,
                valorTotal: ip.preco * ip.quantidade,
                clienteNome: i.clienteNome,
              ),
            );
          }
        }
      }
      return produtosMap.values.toList();
    }

    // Itens filtrados por período + forma de pagamento. Recalculados apenas
    // quando esses filtros mudam (a busca por nome é aplicada por cima, no modal).
    List<ItemHistorico> itensAnalise = [];
    void recalcularAnalise() {
      itensAnalise = _montarItensHistorico(
        dataService,
        analiseInicio,
        analiseFim,
        apenasMeuCaixa: _filtrarApenasMeuCaixa,
      ).where((i) => itemUsaFormaPagamento(i, formaFiltro)).toList();
    }

    recalcularAnalise();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (context) => DefaultTabController(
        length: 2,
        child: StatefulBuilder(
          builder: (context, setModalState) {
            // Agrega a partir da lista já filtrada por período + forma (barato)
            final listaBase = agregarProdutos(itensAnalise);
            final totalVendasGeral =
                listaBase.fold(0.0, (s, p) => s + p.valorTotal);
            final listaABC = List<_ProdutoVendido>.from(listaBase)
              ..sort((a, b) => b.valorTotal.compareTo(a.valorTotal));
            double acumuladoFiltro = 0;
            for (var p in listaABC) {
              if (totalVendasGeral > 0) {
                acumuladoFiltro += p.valorTotal;
                double percentual =
                    (acumuladoFiltro / totalVendasGeral) * 100;
                if (percentual <= 80.1)
                  p.abc = 'A';
                else if (percentual <= 95.1)
                  p.abc = 'B';
                else
                  p.abc = 'C';
              }
            }

            final filtradosLucro = listaBase
                .where(
                  (p) => p.nome.toLowerCase().contains(
                    _filtroProdutoBusca.toLowerCase(),
                  ),
                )
                .toList();
            final filtradosABC = listaABC
                .where(
                  (p) => p.nome.toLowerCase().contains(
                    _filtroProdutoBusca.toLowerCase(),
                  ),
                )
                .toList();

            final int totalUnidades = listaBase.fold(
              0,
              (sum, p) => sum + p.quantidadeTotal,
            );
            final double totalLucro = listaBase
                .where((p) => p.temCusto)
                .fold(0.0, (sum, p) => sum + p.lucroTotal);

            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Análise de Produtos',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$totalUnidades unidades vendidas no período (${DateFormat('dd/MM/yyyy').format(analiseInicio)} até ${DateFormat('dd/MM/yyyy').format(analiseFim)})${formaFiltro != 'Todas' ? ' • Forma: $formaFiltro' : ''}',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const TabBar(
                    indicatorColor: Colors.orangeAccent,
                    labelColor: Colors.orangeAccent,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(
                        text: 'LUCRATIVIDADE',
                        icon: Icon(Icons.monetization_on_outlined),
                      ),
                      Tab(
                        text: 'CURVA ABC / RANKING',
                        icon: Icon(Icons.analytics_outlined),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: analiseInicio,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (d != null) {
                                setModalState(() {
                                  analiseInicio = d.copyWith(
                                    hour: 0,
                                    minute: 0,
                                    second: 0,
                                    millisecond: 0,
                                    microsecond: 0,
                                  );
                                  recalcularAnalise();
                                });
                              }
                            },
                            child: _chipDataAnalise(analiseInicio, 'Início'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: analiseFim,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (d != null) {
                                setModalState(() {
                                  analiseFim = d.copyWith(
                                    hour: 23,
                                    minute: 59,
                                    second: 59,
                                    millisecond: 999,
                                    microsecond: 999,
                                  );
                                  recalcularAnalise();
                                });
                              }
                            },
                            child: _chipDataAnalise(analiseFim, 'Fim'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(
                              Icons.filter_alt_outlined,
                              size: 16,
                              color: formaFiltro == 'Todas'
                                  ? Colors.orangeAccent
                                  : Colors.white54,
                            ),
                            label: const Text('Todas'),
                            selected: formaFiltro == 'Todas',
                            onSelected: (_) => setModalState(() {
                              formaFiltro = 'Todas';
                              recalcularAnalise();
                            }),
                            backgroundColor: const Color(0xFF2D2D44),
                            selectedColor:
                                Colors.orangeAccent.withOpacity(0.25),
                            labelStyle: TextStyle(
                              color: formaFiltro == 'Todas'
                                  ? Colors.orangeAccent
                                  : Colors.white60,
                              fontWeight: formaFiltro == 'Todas'
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            side: BorderSide(
                              color: formaFiltro == 'Todas'
                                  ? Colors.orangeAccent
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        ...TipoPagamento.values.map((t) {
                          final sel = formaFiltro == t.nome;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(
                                t.icone,
                                size: 16,
                                color: sel
                                    ? Colors.orangeAccent
                                    : Colors.white54,
                              ),
                              label: Text(t.nome),
                              selected: sel,
                              onSelected: (_) => setModalState(() {
                                formaFiltro = t.nome;
                                recalcularAnalise();
                              }),
                              backgroundColor: const Color(0xFF2D2D44),
                              selectedColor:
                                  Colors.orangeAccent.withOpacity(0.25),
                              labelStyle: TextStyle(
                                color: sel
                                    ? Colors.orangeAccent
                                    : Colors.white60,
                                fontWeight:
                                    sel ? FontWeight.bold : FontWeight.normal,
                                fontSize: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              side: BorderSide(
                                color: sel
                                    ? Colors.orangeAccent
                                    : Colors.transparent,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      onChanged: (v) =>
                          setModalState(() => _filtroProdutoBusca = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Filtrar produto...',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white24,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF2D2D44),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Aba Lucratividade
                        _buildListaLucratividade(filtradosLucro, totalLucro),
                        // Aba Curva ABC
                        _buildListaABC(filtradosABC, totalVendasGeral),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chipDataAnalise(DateTime data, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D44),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: Colors.white38, size: 14),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                DateFormat('dd/MM/yyyy').format(data),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListaLucratividade(
    List<_ProdutoVendido> produtos,
    double totalLucro,
  ) {
    produtos.sort((a, b) => b.lucroTotal.compareTo(a.lucroTotal));
    final double totalCusto = produtos.fold(0.0, (s, p) => s + (p.custoTotal ?? 0.0));
    final double totalFaturamento = produtos.fold(0.0, (s, p) => s + p.valorTotal);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'FATURAMENTO',
                          style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatoMoeda.format(totalFaturamento),
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 30, color: Colors.white10),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'CUSTO TOTAL',
                          style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatoMoeda.format(totalCusto),
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 30, color: Colors.white10),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'LUCRO TOTAL',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatoMoeda.format(totalLucro),
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: produtos.length,
            itemBuilder: (context, index) {
              final p = produtos[index];
              return _buildCardProdutoLucro(p);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListaABC(List<_ProdutoVendido> produtos, double totalGeral) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                'FATURAMENTO TOTAL: ${_formatoMoeda.format(totalGeral)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                'Ranking baseado no volume de vendas em reais',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: produtos.length,
            itemBuilder: (context, index) {
              final p = produtos[index];
              final perc = totalGeral > 0
                  ? (p.valorTotal / totalGeral) * 100
                  : 0.0;

              Color abcColor = Colors.greenAccent;
              String abcDesc = 'Essencial (80%)';
              if (p.abc == 'B') {
                abcColor = Colors.orangeAccent;
                abcDesc = 'Intermediário (15%)';
              } else if (p.abc == 'C') {
                abcColor = Colors.redAccent;
                abcDesc = 'Baixo Impacto (5%)';
              }

              return Card(
                color: const Color(0xFF2D2D44).withOpacity(0.5),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  onTap: () => _mostrarVendasDatalhadasDoProduto(context, p),
                  leading: CircleAvatar(
                    backgroundColor: abcColor.withOpacity(0.2),
                    child: Text(
                      p.abc,
                      style: TextStyle(
                        color: abcColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  title: Text(
                    p.nome,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.quantidadeTotal} unidades • ${perc.toStringAsFixed(1)}% do faturamento',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        abcDesc,
                        style: TextStyle(
                          color: abcColor.withOpacity(0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  trailing: Text(
                    _formatoMoeda.format(p.valorTotal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCardProdutoLucro(_ProdutoVendido p) {
    return Card(
      color: const Color(0xFF2D2D44).withOpacity(0.5),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _mostrarVendasDatalhadasDoProduto(context, p),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      p.nome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    _formatoMoeda.format(p.valorTotal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.quantidadeTotal} unidades vendidas',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                      if (p.temCusto)
                        Text(
                          'Custo Total: ${_formatoMoeda.format(p.custoTotal)}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (p.temCusto) ...[
                        Text(
                          'Lucro: ${_formatoMoeda.format(p.lucroTotal)}',
                          style: TextStyle(
                            color: p.lucroTotal >= 0
                                ? Colors.orangeAccent
                                : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Margem: ${p.margemPercentual.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Text(
                              ' • ',
                              style: TextStyle(color: Colors.white24),
                            ),
                            Text(
                              'Markup: ${p.markupPercentual.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ] else
                        const Text(
                          'Custo não informado',
                          style: TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarVendasDatalhadasDoProduto(
    BuildContext context,
    _ProdutoVendido p,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vendas de ${p.nome}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${p.vendas.length} operações realizadas',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                itemCount: p.vendas.length,
                itemBuilder: (context, index) {
                  final v = p.vendas[index];
                  return Card(
                    color: const Color(0xFF2D2D44).withOpacity(0.5),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            v.numeroVenda,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            DateFormat('dd/MM HH:mm').format(v.data.toLocal()),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            v.clienteNome ?? 'Venda Direta',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${v.quantidade}x ${_formatoMoeda.format(v.precoUnitario)}',
                          ),
                        ],
                      ),
                      trailing: Text(
                        _formatoMoeda.format(v.valorTotal),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoEmissaoNFCe(ItemHistorico item) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;
    if (empresa == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Empresa não selecionada!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    String initialCpf = '';
    String initialNome = '';
    if (item.vendaBalcao != null) {
      initialCpf = item.vendaBalcao!.clienteCpfCnpj ?? '';
      initialNome = item.vendaBalcao!.clienteNome ?? '';
    } else if (item.pedido != null) {
      initialCpf = item.pedido!.clienteCpfCnpj ?? '';
      initialNome = item.pedido!.clienteNome ?? '';
    }

    final cpfController = TextEditingController(text: initialCpf);
    final nomeController = TextEditingController(text: initialNome);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: Colors.blueAccent),
            SizedBox(width: 12),
            Text('Emitir NFC-e', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Você está emitindo a NFC-e para a venda ${item.numero}.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text(
                'CPF/CNPJ do Consumidor (Opcional)',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cpfController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ex: 123.456.789-00',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF2D2D44),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nome do Consumidor (Opcional)',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nomeController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ex: João Silva',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: const Color(0xFF2D2D44),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _processarEmissaoNFCe(
                item,
                cpfController.text.trim(),
                nomeController.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text(
              'EMITIR AGORA',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _processarEmissaoNFCe(
    ItemHistorico item,
    String cpfCnpj,
    String nomeConsumidor,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E2E),
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.blueAccent),
              SizedBox(height: 16),
              Text(
                'Transmitindo NFC-e...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Aguardando retorno da SEFAZ',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresa = authService.empresaAtual!;

      final List<Produto> produtos = [];
      final Map<String, double> quantidades = {};
      final List<NFCePagamento> pagamentos = [];

      if (item.vendaBalcao != null) {
        final venda = item.vendaBalcao!;
        for (final iv in venda.itens) {
          final pReal = dataService.produtos.firstWhere(
            (p) => p.id == iv.id || p.nome == iv.nome,
            orElse: () => Produto(
              id: iv.id,
              nome: iv.nome,
              preco: iv.precoUnitario,
              unidade: 'UN',
              ncm: '00000000',
              cfop: '5102',
              grupo: 'Geral',
              estoque: 0.0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
          produtos.add(pReal);
          quantidades[pReal.id] = iv.quantidade;
        }

        String tipoPag = '99';
        switch (venda.tipoPagamento) {
          case TipoPagamento.dinheiro:
            tipoPag = '01';
            break;
          case TipoPagamento.pix:
            tipoPag = '17';
            break;
          case TipoPagamento.cartaoCredito:
            tipoPag = '03';
            break;
          case TipoPagamento.cartaoDebito:
            tipoPag = '04';
            break;
          default:
            tipoPag = '99';
        }
        pagamentos.add(NFCePagamento(tipo: tipoPag, valor: venda.valorTotal));
      } else if (item.pedido != null) {
        final ped = item.pedido!;
        for (final ip in ped.produtos) {
          final pReal = dataService.produtos.firstWhere(
            (p) => p.id == ip.id || p.nome == ip.nome,
            orElse: () => Produto(
              id: ip.id,
              nome: ip.nome,
              preco: ip.preco,
              unidade: 'UN',
              ncm: '00000000',
              cfop: '5102',
              grupo: 'Geral',
              estoque: 0.0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
          produtos.add(pReal);
          quantidades[pReal.id] = ip.quantidade;
        }

        if (ped.pagamentos.isNotEmpty) {
          for (final p in ped.pagamentos) {
            String tipoPag = '99';
            switch (p.tipo) {
              case TipoPagamento.dinheiro:
                tipoPag = '01';
                break;
              case TipoPagamento.pix:
                tipoPag = '17';
                break;
              case TipoPagamento.cartaoCredito:
                tipoPag = '03';
                break;
              case TipoPagamento.cartaoDebito:
                tipoPag = '04';
                break;
              default:
                tipoPag = '99';
            }
            pagamentos.add(NFCePagamento(tipo: tipoPag, valor: p.valor));
          }
        } else {
          pagamentos.add(NFCePagamento(tipo: '99', valor: ped.totalGeral));
        }
      }

      final configUrl = empresa.configuracoes?['bridgeNfceUrl'] as String?;
      if (configUrl != null && configUrl.isNotEmpty) {
        NFCeServiceFactory.configurarBackend(url: configUrl);
      } else {
        NFCeServiceFactory.configurarBackend(url: null);
      }

      final nfceService = NFCeServiceFactory.criar();
      final ambienteHomologacao = empresa.ambienteHomologacao ?? true;
      final usuario = authService.usuarioAtual;
      final serieUsuario = usuario?.serieNfce;

      final nextNfceNumero = dataService.getProximoNumeroNfce(
        serie: serieUsuario?.toString() ?? '1',
        numeroInicial: usuario?.numeroInicialNfce ?? 1,
      ).toString();

      final nfce = await nfceService.emitir(
        empresa: empresa,
        produtos: produtos,
        quantidades: quantidades,
        pagamentos: pagamentos,
        valorTotal: item.valorTotal,
        cpfCnpjConsumidor: cpfCnpj.isNotEmpty ? cpfCnpj : null,
        nomeConsumidor: nomeConsumidor.isNotEmpty ? nomeConsumidor : null,
        observacoes: item.vendaBalcao?.observacoes ?? item.pedido?.observacoes,
        vendaId: item.id,
        vendaNumero: nextNfceNumero,
        ambienteHomologacao: ambienteHomologacao,
        serie: serieUsuario,
      );

      await dataService.adicionarNFCe(nfce);

      if (mounted) Navigator.pop(context);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('NFC-e Nº ${nfce.numero} emitida com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context);

        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent),
                SizedBox(width: 12),
                Text('NFC-e Emitida', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              'A NFC-e Nº ${nfce.numero} foi emitida com sucesso!\nDeseja imprimir a DANFE agora?',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('NÃO', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  DANFEService.imprimir(nfce: nfce, empresa: empresa);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                ),
                child: const Text(
                  'IMPRIMIR',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent),
                SizedBox(width: 12),
                Text('Erro na Emissão', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              'Falha ao emitir NFC-e:\n\n$e',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  'OK',
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
            ],
          ),
        );
      }
    }
  }
}
