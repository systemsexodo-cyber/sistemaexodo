import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/venda_balcao.dart';
import '../models/pedido.dart';
import '../models/forma_pagamento.dart';
import '../models/troca_devolucao.dart';
import '../models/caixa.dart';
import 'trocas_devolucoes_page.dart';
import 'home_page.dart';

/// Classe para agrupar informações de produto vendido
class _ProdutoVendido {
  final String nome;
  final String? produtoId;
  int quantidadeTotal = 0;
  double valorTotal = 0.0;
  List<_VendaProduto> vendas = [];

  _ProdutoVendido({
    required this.nome,
    this.produtoId,
  });
}

/// Classe para armazenar informações de uma venda específica de um produto
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

/// Classe wrapper para unificar vendas balcão e pedidos pagos
class ItemHistorico {
  final String id;
  final String numero;
  final DateTime data;
  final String? clienteNome;
  final double valorTotal;
  final TipoPagamento? tipoPagamento;
  final String tipo; // 'Venda Direta' ou 'Pedido'
  final VendaBalcao? vendaBalcao;
  final Pedido? pedido;

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
  });

  factory ItemHistorico.fromVendaBalcao(VendaBalcao venda) {
    // Para vendas parceladas no crediário ou boleto,
    // só contabiliza quando receber - valorRecebido será preenchido
    // Cartão de crédito contabiliza normalmente (pagamento à vista)
    final tiposParcelaveis = [TipoPagamento.crediario, TipoPagamento.boleto];

    double valorContabilizado;
    if (tiposParcelaveis.contains(venda.tipoPagamento)) {
      // Crediário e Boleto: só contabiliza o que foi recebido
      valorContabilizado = venda.valorRecebido ?? 0;
    } else {
      // Outros tipos (dinheiro, pix, cartões, etc): usa o valor total da venda
      // (que já considera trocas e devoluções)
      valorContabilizado = venda.valorTotal;
    }

    return ItemHistorico(
      id: venda.id,
      numero: venda.numero,
      data: venda.dataVenda,
      clienteNome: venda.clienteNome,
      valorTotal: valorContabilizado,
      tipoPagamento: venda.tipoPagamento,
      tipo: 'Venda Direta',
      vendaBalcao: venda,
    );
  }

  factory ItemHistorico.fromPedido(Pedido pedido) {
    // Pegar o tipo de pagamento principal (primeiro pagamento)
    TipoPagamento? tipoPag;
    TipoPagamento? tipoOriginal;
    if (pedido.pagamentos.isNotEmpty) {
      tipoPag = pedido.pagamentos.first.tipo;
      tipoOriginal = pedido.pagamentos.first.tipoOriginal;
    }

    // Verificar se algum pagamento é ou era crediário/fiado (incluindo tipoOriginal)
    final temCrediarioOuFiado = pedido.pagamentos.any(
      (p) =>
          p.tipo == TipoPagamento.crediario ||
          p.tipo == TipoPagamento.fiado ||
          p.tipoOriginal == TipoPagamento.crediario ||
          p.tipoOriginal == TipoPagamento.fiado,
    );

    // Determinar o tipo de origem
    String tipoOrigem;

    // Pedidos tradicionais (PED-) são sempre "Pedido"
    if (pedido.numero.startsWith('PED-')) {
      tipoOrigem = 'Pedido';
    } else if (temCrediarioOuFiado ||
        tipoPag == TipoPagamento.crediario ||
        tipoPag == TipoPagamento.fiado ||
        tipoPag == TipoPagamento.boleto ||
        tipoPag == TipoPagamento.outro ||
        tipoOriginal == TipoPagamento.crediario ||
        tipoOriginal == TipoPagamento.fiado) {
      // Crediário, Fiado, Boleto e "Outro" (Venda Salva) são "Venda a Prazo"
      tipoOrigem = 'Venda a Prazo';
    } else {
      // Vendas pagas do PDV são "Venda Direta"
      tipoOrigem = 'Venda Direta';
    }

    // Usar a data do último recebimento, não a data do pedido
    DateTime dataExibicao = pedido.dataPedido;
    final pagamentosRecebidos = pedido.pagamentos
        .where((p) => p.recebido && p.dataRecebimento != null)
        .toList();
    if (pagamentosRecebidos.isNotEmpty) {
      // Ordenar por data de recebimento e pegar a mais recente
      pagamentosRecebidos.sort(
        (a, b) => b.dataRecebimento!.compareTo(a.dataRecebimento!),
      );
      dataExibicao = pagamentosRecebidos.first.dataRecebimento!;
    }

    return ItemHistorico(
      id: pedido.id,
      numero: pedido.numero,
      data: dataExibicao, // Usa a data do recebimento
      clienteNome: pedido.clienteNome,
      valorTotal: pedido.totalRecebido, // Só contabiliza parcelas pagas
      tipoPagamento:
          tipoOriginal ?? tipoPag, // Mostra o tipo original se existir
      tipo: tipoOrigem,
      pedido: pedido,
    );
  }
}

/// Página de histórico de vendas do PDV
class HistoricoVendasPage extends StatefulWidget {
  const HistoricoVendasPage({super.key});

  @override
  State<HistoricoVendasPage> createState() => _HistoricoVendasPageState();
}

class _HistoricoVendasPageState extends State<HistoricoVendasPage> {
  // Inicializar com o dia atual (início e fim do dia)
  late DateTime _dataInicio;
  late DateTime _dataFim;
  TimeOfDay _horaInicio = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay _horaFim = const TimeOfDay(hour: 23, minute: 59);
  
  String _filtroTipoPagamento = 'Todos';
  String _filtroOrigem =
      'Todos'; // 'Todos', 'Venda Direta', 'Venda a Prazo', 'Pedido'

  // Campo de busca
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';

  final _formatoData = DateFormat('dd/MM/yyyy');
  final _formatoHora = DateFormat('HH:mm');
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    // Inicializar com o dia atual
    final hoje = DateTime.now();
    _dataInicio = DateTime(hoje.year, hoje.month, hoje.day);
    _dataFim = DateTime(hoje.year, hoje.month, hoje.day, 23, 59, 59);
    // Sincronizar horários com as datas
    _horaInicio = TimeOfDay.fromDateTime(_dataInicio);
    _horaFim = TimeOfDay.fromDateTime(_dataFim);
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true);

    // Log para confirmar que build() está sendo chamado e qual instância
    debugPrint(
      '>>> HISTÓRICO BUILD - DataService instanceId: ${dataService.instanceId}',
    );
    debugPrint('>>> vendasBalcao.length=${dataService.vendasBalcao.length}');

    // Buscar vendas do balcão por período
    var vendasBalcao = dataService.getVendasPorPeriodo(_dataInicio, _dataFim);

    // Debug: mostrar valores das vendas
    debugPrint(
      '=== HISTÓRICO BUILD - ${vendasBalcao.length} vendas no período ===',
    );
    for (final v in vendasBalcao) {
      final temTroca = v.itens.any(
        (i) => i.quantidadeTrocada > 0 || i.quantidadeDevolvida > 0,
      );
      if (temTroca) {
        debugPrint('Venda ${v.numero}: valor=${v.valorTotal}');
        for (final item in v.itens) {
          if (item.quantidadeTrocada > 0) {
            debugPrint(
              '  - ${item.nome}: trocado=${item.quantidadeTrocada}, por=${item.trocadoPor}',
            );
          }
        }
      }
    }

    // Buscar pedidos que têm algum valor recebido no período
    // Usar a data do recebimento, não a data do pedido
    // Excluir "Vendas Salvas" (tipo outro) que ainda não foram finalizadas
    final pedidosComRecebimento = dataService.pedidos.where((p) {
      // Verificar se tem algum pagamento recebido dentro do período
      final temRecebimentoNoPeriodo = p.pagamentos.any((pag) {
        if (!pag.recebido || pag.dataRecebimento == null) return false;

        // Excluir vendas salvas (tipo "outro") que não foram recebidas
        // Só mostra "outro" se TODOS os pagamentos foram recebidos
        if (pag.tipo == TipoPagamento.outro && !pag.recebido) return false;

        // Comparar considerando data e horário (incluindo os limites)
        return pag.dataRecebimento!.compareTo(_dataInicio) >= 0 && 
               pag.dataRecebimento!.compareTo(_dataFim) <= 0;
      });

      // Se for venda salva (primeiro pagamento é "outro"), só mostra se tiver recebimento
      if (p.pagamentos.isNotEmpty &&
          p.pagamentos.first.tipo == TipoPagamento.outro) {
        // Só mostra se pelo menos um pagamento foi recebido
        final algumRecebido = p.pagamentos.any((pag) => pag.recebido);
        if (!algumRecebido) return false;
      }

      return temRecebimentoNoPeriodo;
    }).toList();

    // Criar lista unificada
    List<ItemHistorico> itensHistorico = [];

    // Adicionar vendas balcão (inclui devoluções totais com valor zero)
    for (final venda in vendasBalcao) {
      final item = ItemHistorico.fromVendaBalcao(venda);
      // Mostrar se tem valor OU se teve devolução (valor original > 0 mas atual = 0)
      final teveDevolvido = venda.itens.any((i) => i.quantidadeDevolvida > 0);
      if (item.valorTotal > 0 || teveDevolvido) {
        itensHistorico.add(item);
      }
    }

    // Adicionar pedidos com recebimento (inclui devoluções totais com valor zero)
    for (final pedido in pedidosComRecebimento) {
      final item = ItemHistorico.fromPedido(pedido);
      // Mostrar se tem valor OU se já teve algum pagamento (pode ter sido devolvido)
      final teveAlgumPagamento = pedido.pagamentos.isNotEmpty;
      if (item.valorTotal > 0 || teveAlgumPagamento) {
        itensHistorico.add(item);
      }
    }

    // Evitar duplicidade de números de venda no histórico:
    // se existir uma VendaBalcao e também um Pedido com o mesmo número,
    // mantemos apenas UM registro (priorizando a VendaBalcao já adicionada acima).
    final Map<String, ItemHistorico> porNumero = {};
    for (final item in itensHistorico) {
      // Se já existe aquele número, não sobrescreve
      // (isso preserva a VendaDireta vinda de VendaBalcao, que foi adicionada primeiro).
      porNumero.putIfAbsent(item.numero, () => item);
    }
    itensHistorico = porNumero.values.toList();

    // Ordenar por data (mais recente primeiro)
    itensHistorico.sort((a, b) => b.data.compareTo(a.data));

    // Filtrar por origem (Venda Direta ou Pedido)
    if (_filtroOrigem != 'Todos') {
      itensHistorico = itensHistorico
          .where((i) => i.tipo == _filtroOrigem)
          .toList();
    }

    // Filtrar por tipo de pagamento
    if (_filtroTipoPagamento != 'Todos') {
      final tipo = TipoPagamento.values.firstWhere(
        (t) => t.nome == _filtroTipoPagamento,
        orElse: () => TipoPagamento.dinheiro,
      );
      itensHistorico = itensHistorico
          .where((i) => i.tipoPagamento == tipo)
          .toList();
    }

    // Filtrar por busca (cliente, número, valor)
    if (_termoBusca.isNotEmpty) {
      final termo = _termoBusca.toLowerCase().trim();
      itensHistorico = itensHistorico.where((item) {
        // Busca por número da venda
        final numeroMatch = item.numero.toLowerCase().contains(termo);

        // Busca por nome do cliente
        final clienteMatch =
            item.clienteNome?.toLowerCase().contains(termo) ?? false;

        // Busca por valor (se digitou número)
        final valorTermo = double.tryParse(termo.replaceAll(',', '.'));
        final valorMatch =
            valorTermo != null &&
            item.valorTotal.toStringAsFixed(2).contains(termo);

        // Busca por tipo de pagamento
        final pagamentoMatch =
            item.tipoPagamento?.nome.toLowerCase().contains(termo) ?? false;

        // Busca por tipo de origem
        final tipoMatch = item.tipo.toLowerCase().contains(termo);

        // Busca por produtos/serviços
        bool produtosMatch = false;
        if (item.vendaBalcao != null) {
          produtosMatch = item.vendaBalcao!.itens.any(
            (i) => i.nome.toLowerCase().contains(termo),
          );
        } else if (item.pedido != null) {
          produtosMatch =
              item.pedido!.produtos.any(
                (p) => p.nome.toLowerCase().contains(termo),
              ) ||
              item.pedido!.servicos.any(
                (s) => s.descricao.toLowerCase().contains(termo),
              );
        }

        return numeroMatch ||
            clienteMatch ||
            valorMatch ||
            pagamentoMatch ||
            tipoMatch ||
            produtosMatch;
      }).toList();
    }

    // Calcular totais
    final totalPeriodo = itensHistorico.fold(
      0.0,
      (sum, i) => sum + i.valorTotal,
    );
    final quantidadeVendas = itensHistorico.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Histórico de Vendas'),
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
        actions: [
          // Botão Fechar Caixa
          IconButton(
            icon: const Icon(Icons.lock, color: Colors.redAccent),
            onPressed: () =>
                _mostrarDialogFechamentoCaixa(context, dataService, itensHistorico),
            tooltip: 'Fechar Caixa',
          ),
          // Botão Resumo de Caixas
          IconButton(
            icon: const Icon(Icons.point_of_sale, color: Colors.amber),
            onPressed: () => _mostrarResumoCaixas(context, itensHistorico),
            tooltip: 'Resumo de Caixas',
          ),
          // Botão Vendas por Produto
          IconButton(
            icon: const Icon(Icons.inventory_2, color: Colors.green),
            onPressed: () => _mostrarVendasPorProduto(context, dataService, itensHistorico),
            tooltip: 'Vendas por Produto',
          ),
          // Botão Trocas e Devoluções
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.orange),
            onPressed: () async {
              // Aguardar retorno da página de trocas
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TrocasDevolucoesBuscarPage(),
                ),
              );
              // Forçar atualização quando voltar
              if (mounted) {
                setState(() {
                  debugPrint(
                    '>>> Forçando rebuild do histórico após retorno de trocas',
                  );
                });
              }
            },
            tooltip: 'Trocas e Devoluções',
          ),
          // Botão de refresh para debug
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: () {
              debugPrint('>>> REFRESH MANUAL PRESSIONADO');
              setState(() {});
            },
            tooltip: 'Atualizar',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _mostrarFiltros,
            tooltip: 'Filtros',
          ),
        ],
      ),
      body: Column(
        children: [
          // Campo de busca
          _buildCampoBusca(),
          // Resumo do período
          _buildResumo(totalPeriodo, quantidadeVendas, itensHistorico),
          // Lista de vendas
          Expanded(
            child: itensHistorico.isEmpty
                ? _buildListaVazia()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: itensHistorico.length,
                    itemBuilder: (context, index) {
                      return _buildCardItem(itensHistorico[index], dataService);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoBusca() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _buscaController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: '🔍 Buscar por cliente, número, produto, valor...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
          suffixIcon: _termoBusca.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54),
                  onPressed: () {
                    setState(() {
                      _buscaController.clear();
                      _termoBusca = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        onChanged: (value) {
          setState(() {
            _termoBusca = value;
          });
        },
      ),
    );
  }

  Widget _buildResumo(double total, int quantidade, List<ItemHistorico> itens) {
    // Agrupar por tipo de pagamento
    final porTipoPagamento = <TipoPagamento, double>{};
    for (final item in itens) {
      if (item.tipoPagamento != null) {
        porTipoPagamento[item.tipoPagamento!] =
            (porTipoPagamento[item.tipoPagamento!] ?? 0) + item.valorTotal;
      }
    }

    // Agrupar por origem
    final vendasDiretas = itens.where((i) => i.tipo == 'Venda Direta').length;
    final vendasPrazo = itens.where((i) => i.tipo == 'Venda a Prazo').length;
    final pedidos = itens.where((i) => i.tipo == 'Pedido').length;
    final totalVendasDiretas = itens
        .where((i) => i.tipo == 'Venda Direta')
        .fold(0.0, (sum, i) => sum + i.valorTotal);
    final totalVendasPrazo = itens
        .where((i) => i.tipo == 'Venda a Prazo')
        .fold(0.0, (sum, i) => sum + i.valorTotal);
    final totalPedidos = itens
        .where((i) => i.tipo == 'Pedido')
        .fold(0.0, (sum, i) => sum + i.valorTotal);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.withOpacity(0.2), Colors.blue.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Período selecionado
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _selecionarData(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatoData.format(_dataInicio)} ${_formatoHora.format(_dataInicio)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('até', style: TextStyle(color: Colors.white54)),
              ),
              GestureDetector(
                onTap: () => _selecionarData(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatoData.format(_dataFim)} ${_formatoHora.format(_dataFim)}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Total e quantidade
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Text(
                    'TOTAL DO PERÍODO',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatoMoeda.format(total),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(width: 1, height: 50, color: Colors.white24),
              Column(
                children: [
                  const Text(
                    'VENDAS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$quantidade',
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Resumo por origem (Venda Direta, Venda a Prazo, Pedido)
          if (vendasDiretas > 0 || vendasPrazo > 0 || pedidos > 0) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (vendasDiretas > 0)
                  _buildResumoOrigem(
                    'Venda Direta',
                    vendasDiretas,
                    totalVendasDiretas,
                    Colors.greenAccent,
                    Icons.point_of_sale,
                  ),
                if (vendasPrazo > 0)
                  _buildResumoOrigem(
                    'Venda a Prazo',
                    vendasPrazo,
                    totalVendasPrazo,
                    Colors.cyan,
                    Icons.schedule_send,
                  ),
                if (pedidos > 0)
                  _buildResumoOrigem(
                    'Pedidos',
                    pedidos,
                    totalPedidos,
                    Colors.orangeAccent,
                    Icons.receipt_long,
                  ),
              ],
            ),
          ],
          // Totais por tipo de pagamento
          if (porTipoPagamento.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: porTipoPagamento.entries.map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getIconeTipo(entry.key),
                        color: Colors.white54,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${entry.key.nome}: ${_formatoMoeda.format(entry.value)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResumoOrigem(
    String label,
    int quantidade,
    double total,
    Color cor,
    IconData icone,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icone, color: cor, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: cor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$quantidade vendas',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            _formatoMoeda.format(total),
            style: TextStyle(
              color: cor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem(ItemHistorico item, DataService dataService) {
    final isVendaDireta = item.tipo == 'Venda Direta';
    final isVendaPrazo = item.tipo == 'Venda a Prazo';

    // BUSCA DIRETA: Sempre buscar a venda atualizada do DataService
    VendaBalcao? vendaAtualizada = dataService.getVendaPorNumero(item.numero);
    
    // Log para debug
    if (vendaAtualizada != null) {
      debugPrint('>>> vendaAtualizada encontrada do DataService: ${item.numero}');
      // Verificar itens com troca
      for (final it in vendaAtualizada.itens) {
        if (it.quantidadeTrocada > 0) {
          debugPrint('>>>   Item trocado encontrado: ${it.nome} -> "${it.trocadoPor}"');
        }
      }
    } else {
      debugPrint('>>> AVISO: vendaAtualizada NÃO encontrada, usando item.vendaBalcao');
    }

    // Se não encontrou no DataService, usar a referência do item
    vendaAtualizada ??= item.vendaBalcao;
    
    // Garantir que temos os dados mais atualizados - buscar novamente
    if (vendaAtualizada != null) {
      // Buscar novamente para garantir que é a versão mais recente
      final vendaMaisRecente = dataService.getVendaPorNumero(vendaAtualizada.numero);
      if (vendaMaisRecente != null) {
        vendaAtualizada = vendaMaisRecente;
        debugPrint('>>> Usando venda mais recente do DataService');
      }
    }

    // VALOR A EXIBIR: Sempre do DataService atualizado
    final double valorParaExibir =
        vendaAtualizada?.valorTotal ?? item.valorTotal;

    debugPrint('=== CARD ${item.numero} ===');
    debugPrint('>>> valorParaExibir = $valorParaExibir');
    debugPrint('>>> item.valorTotal (antigo) = ${item.valorTotal}');
    if (vendaAtualizada != null) {
      debugPrint(
        '>>> vendaAtualizada.valorTotal = ${vendaAtualizada.valorTotal}',
      );
    }

    // Verificar se esta venda teve troca/devolução - por lista de trocas OU pelos itens
    final trocasDestaVenda = dataService.trocasDevolucoes
        .where((t) => t.numeroPedido == item.numero || t.pedidoId == item.id)
        .toList();

    // Verificar também pelos campos dos itens da venda
    bool teveAlteracaoNosItens = false;
    bool teveTrocaNosItens = false;
    bool teveDevolucaoNosItens = false;

    if (vendaAtualizada != null) {
      for (final it in vendaAtualizada.itens) {
        if (it.quantidadeTrocada > 0) {
          teveAlteracaoNosItens = true;
          teveTrocaNosItens = true;
        }
        if (it.quantidadeDevolvida > 0) {
          teveAlteracaoNosItens = true;
          teveDevolucaoNosItens = true;
        }
      }
    }

    final teveTroca = trocasDestaVenda.isNotEmpty || teveAlteracaoNosItens;
    TipoOperacao? tipoTroca;
    if (trocasDestaVenda.isNotEmpty) {
      tipoTroca = trocasDestaVenda.first.tipo;
    } else if (teveTrocaNosItens) {
      tipoTroca = TipoOperacao.troca;
    } else if (teveDevolucaoNosItens) {
      tipoTroca = TipoOperacao.devolucao;
    }

    // Cores baseadas no tipo
    Color corPrincipal;
    IconData iconePrincipal;

    if (isVendaDireta) {
      corPrincipal = Colors.greenAccent;
      iconePrincipal = Icons.point_of_sale;
    } else if (isVendaPrazo) {
      corPrincipal = Colors.cyan;
      iconePrincipal = Icons.schedule_send;
    } else {
      corPrincipal = Colors.orangeAccent;
      iconePrincipal = Icons.receipt_long;
    }

    // Obter quantidade de itens e resumo da troca
    int qtdItens = 0;
    String primeirosItens = '';
    String resumoTroca = ''; // Resumo: "X trocado por Y"

    if (vendaAtualizada != null) {
      qtdItens = vendaAtualizada.itens.length;
      primeirosItens = vendaAtualizada.itens
          .take(3)
          .map((i) => i.nome)
          .join(', ');
      if (vendaAtualizada.itens.length > 3) {
        primeirosItens += '...';
      }

      // DEBUG: Mostrar todos os itens
      debugPrint('>>> ${item.numero}: ${vendaAtualizada.itens.length} itens');
      for (final it in vendaAtualizada.itens) {
        debugPrint(
          '>>>   - ${it.nome}: qTrocada=${it.quantidadeTrocada}, qDevolvida=${it.quantidadeDevolvida}, trocadoPor="${it.trocadoPor}"',
        );
      }

      // Criar resumo da troca se houver
      final itensTrocados = vendaAtualizada.itens
          .where(
            (i) =>
                i.quantidadeTrocada > 0 &&
                i.trocadoPor != null &&
                i.trocadoPor!.isNotEmpty &&
                i.trocadoPor!.trim().isNotEmpty,
          )
          .toList();
      
      debugPrint('>>> Total de itens trocados encontrados: ${itensTrocados.length}');
      for (final it in itensTrocados) {
        debugPrint('>>>   - ${it.nome} foi trocado por: "${it.trocadoPor}"');
      }

      // Criar resumo da devolução se houver
      final itensDevolvidos = vendaAtualizada.itens
          .where((i) => i.quantidadeDevolvida > 0)
          .toList();

      debugPrint('>>> itensTrocados.length: ${itensTrocados.length}');
      debugPrint('>>> itensDevolvidos.length: ${itensDevolvidos.length}');

      if (itensTrocados.isNotEmpty) {
        final partes = <String>[];
        for (final it in itensTrocados) {
          partes.add('${it.nome} → ${it.trocadoPor}');
        }
        resumoTroca = partes.join(' | ');
        debugPrint('>>> resumoTroca construído: "$resumoTroca"');
      }

      // Se não teve troca mas teve devolução, criar resumo de devolução
      if (resumoTroca.isEmpty && itensDevolvidos.isNotEmpty) {
        final partes = <String>[];
        for (final it in itensDevolvidos) {
          partes.add('${it.nome} (${it.quantidadeDevolvida}x devolvido)');
        }
        resumoTroca = partes.join(' | ');
        debugPrint('>>> resumoDevolucao construído: "$resumoTroca"');
      }
    } else if (item.pedido != null) {
      qtdItens = item.pedido!.produtos.length + item.pedido!.servicos.length;
      final nomes = [
        ...item.pedido!.produtos.map((p) => p.nome),
        ...item.pedido!.servicos.map((s) => s.descricao),
      ];
      primeirosItens = nomes.take(3).join(', ');
      if (nomes.length > 3) {
        primeirosItens += '...';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1E2E),
            Color.lerp(const Color(0xFF1E1E2E), corPrincipal, 0.05)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corPrincipal.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: corPrincipal.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                corPrincipal.withOpacity(0.3),
                corPrincipal.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: corPrincipal.withOpacity(0.3)),
          ),
          child: Icon(iconePrincipal, color: corPrincipal, size: 26),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linha 1: Número e badges
            Row(
              children: [
                Text(
                  item.numero,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                // Badge de origem
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: corPrincipal.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.tipo,
                    style: TextStyle(
                      color: corPrincipal,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (item.tipoPagamento != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.tipoPagamento!.nome,
                      style: const TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
                // Badge de Troca/Devolução
                if (teveTroca) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tipoTroca == TipoOperacao.troca
                          ? Colors.orange.withOpacity(0.3)
                          : Colors.red.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: tipoTroca == TipoOperacao.troca
                            ? Colors.orange
                            : Colors.red,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tipoTroca == TipoOperacao.troca
                              ? Icons.swap_horiz
                              : Icons.keyboard_return,
                          color: tipoTroca == TipoOperacao.troca
                              ? Colors.orange
                              : Colors.red,
                          size: 10,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          tipoTroca == TipoOperacao.troca
                              ? 'TROCA'
                              : 'DEVOLUÇÃO',
                          style: TextStyle(
                            color: tipoTroca == TipoOperacao.troca
                                ? Colors.orange
                                : Colors.red,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // Linha 2: Cliente em destaque
            if (item.clienteNome != null && item.clienteNome!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person,
                      color: Colors.purpleAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.clienteNome!,
                        style: const TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Cliente não identificado',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha 3: Data/hora e quantidade de itens
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatoData.format(item.data),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatoHora.format(item.data),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_bag,
                          size: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$qtdItens ${qtdItens == 1 ? 'item' : 'itens'}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Linha 4: Preview dos itens
              if (primeirosItens.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  primeirosItens,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Mostrar informações de troca SEMPRE no card (mesmo fechado)
              if (vendaAtualizada != null &&
                  vendaAtualizada.itens.any(
                    (i) =>
                        i.quantidadeTrocada > 0 &&
                        i.trocadoPor != null &&
                        i.trocadoPor!.isNotEmpty &&
                        i.trocadoPor!.trim().isNotEmpty,
                  )) ...[
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final venda = vendaAtualizada!;
                    final itensTrocadosNoCard = venda.itens.where(
                      (i) =>
                          i.quantidadeTrocada > 0 &&
                          i.trocadoPor != null &&
                          i.trocadoPor!.isNotEmpty &&
                          i.trocadoPor!.trim().isNotEmpty,
                    ).toList();
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final itemTrocado in itensTrocadosNoCard) ...[
                            Row(
                              children: [
                                const Icon(
                                  Icons.swap_horiz,
                                  color: Colors.orange,
                                  size: 12,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${itemTrocado.quantidadeTrocada}x ${itemTrocado.nome} → ${itemTrocado.trocadoPor}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
              // Mostrar itens trocados/devolvidos sempre que houver (para seção expandida)
              if ((vendaAtualizada?.itens.any(
                        (i) =>
                            i.quantidadeTrocada > 0 &&
                            i.trocadoPor != null &&
                            i.trocadoPor!.isNotEmpty,
                      ) ??
                      false) ||
                  (vendaAtualizada?.itens.any(
                        (i) => i.quantidadeDevolvida > 0,
                      ) ??
                      false)) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        (tipoTroca == TipoOperacao.devolucao
                                ? Colors.red
                                : Colors.orange)
                            .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: tipoTroca == TipoOperacao.troca
                          ? Colors.orange.withOpacity(0.5)
                          : Colors.red.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            tipoTroca == TipoOperacao.troca
                                ? Icons.swap_horiz
                                : Icons.keyboard_return,
                            size: 16,
                            color: tipoTroca == TipoOperacao.troca
                                ? Colors.orange
                                : Colors.red,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            tipoTroca == TipoOperacao.troca
                                ? 'TROCA REALIZADA:'
                                : 'DEVOLUÇÃO REALIZADA:',
                            style: TextStyle(
                              color: tipoTroca == TipoOperacao.troca
                                  ? Colors.orange
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (tipoTroca == TipoOperacao.troca)
                        ...((vendaAtualizada?.itens
                                .toList()
                                .where(
                                  (i) =>
                                      i.quantidadeTrocada > 0 &&
                                      i.trocadoPor != null &&
                                      i.trocadoPor!.isNotEmpty,
                                )
                                .map(
                                  (i) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Item antigo (trocado)
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.remove_circle_outline,
                                              color: Colors.redAccent,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                '${i.quantidadeTrocada}x ${i.nome}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.redAccent,
                                                  decoration: TextDecoration
                                                      .lineThrough,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // Seta indicando troca
                                        Padding(
                                          padding: const EdgeInsets.only(left: 20),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.arrow_downward,
                                                size: 14,
                                                color:
                                                    Colors.orange.withOpacity(0.7),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'trocado por',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.orange
                                                      .withOpacity(0.7),
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        // Item novo (recebido)
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.add_circle_outline,
                                              color: Colors.greenAccent,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                '${i.quantidadeTrocada}x ${i.trocadoPor}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.greenAccent,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList()) ??
                            []),
                      if (tipoTroca == TipoOperacao.devolucao)
                        ...((vendaAtualizada?.itens
                                .toList()
                                .where((i) => i.quantidadeDevolvida > 0)
                                .map(
                                  (i) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.remove_circle_outline,
                                          color: Colors.redAccent,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${i.quantidadeDevolvida}x ${i.nome}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.redAccent,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList()) ??
                            []),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Builder(
          builder: (context) {
            // Usar o valor já calculado no início do método
            debugPrint(
              '>>> TRAILING ${item.numero}: valorParaExibir=$valorParaExibir, resumoTroca="$resumoTroca"',
            );

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Usar valor atualizado da venda (do DataService)
                Text(
                  _formatoMoeda.format(valorParaExibir),
                  style: TextStyle(
                    color: teveTroca ? Colors.orange : corPrincipal,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                // Indicador de troca/devolução
                if (teveTroca) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (tipoTroca == TipoOperacao.troca
                                  ? Colors.orange
                                  : Colors.red)
                              .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tipoTroca == TipoOperacao.troca
                              ? Icons.swap_horiz
                              : Icons.keyboard_return,
                          size: 10,
                          color: tipoTroca == TipoOperacao.troca
                              ? Colors.orange
                              : Colors.redAccent,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          tipoTroca == TipoOperacao.troca ? 'Troca' : 'Dev.',
                          style: TextStyle(
                            fontSize: 9,
                            color: tipoTroca == TipoOperacao.troca
                                ? Colors.orange
                                : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Icon(
                    Icons.expand_more,
                    color: Colors.white.withOpacity(0.3),
                    size: 18,
                  ),
                ],
              ],
            );
          },
        ),
        children: [
          // Mostrar detalhes com base no tipo (usar venda atualizada)
          if (vendaAtualizada != null)
            _buildDetalhesVendaBalcao(vendaAtualizada, dataService)
          else if (item.pedido != null)
            _buildDetalhesPedido(item.pedido!),
        ],
      ),
    );
  }

  Widget _buildDetalhesVendaBalcao(VendaBalcao venda, DataService dataService) {
    // Buscar trocas/devoluções desta venda
    final trocasDestaVenda = dataService.trocasDevolucoes
        .where((t) => t.pedidoId == venda.id || t.numeroPedido == venda.numero)
        .toList();

    // Calcular valor total das trocas (diferença)
    double totalDiferenca = 0;
    for (final troca in trocasDestaVenda) {
      totalDiferenca += troca.diferenca;
    }

    // Valor efetivo da venda após trocas/devoluções
    final valorEfetivo = venda.valorTotal + totalDiferenca;

    return Column(
      children: [
        // Itens da venda
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Cabeçalho
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Item',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Qtd',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Unit.',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Subtotal',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
              // Itens
              ...venda.itens.map((item) {
                final foiDevolvido = item.quantidadeDevolvida > 0;
                final foiTrocado = item.quantidadeTrocada > 0;
                final foiAlterado = foiDevolvido || foiTrocado;

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: foiAlterado
                        ? (foiTrocado ? Colors.orange : Colors.red).withOpacity(
                            0.05,
                          )
                        : null,
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Icon(
                                  item.isServico
                                      ? Icons.build
                                      : Icons.inventory_2,
                                  size: 14,
                                  color: foiAlterado
                                      ? (foiTrocado
                                                ? Colors.orange
                                                : Colors.red)
                                            .withOpacity(0.7)
                                      : (item.isServico
                                            ? Colors.purple
                                            : Colors.blue),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.nome,
                                    style: TextStyle(
                                      color: foiAlterado
                                          ? Colors.white.withOpacity(0.6)
                                          : Colors.white,
                                      fontSize: 13,
                                      decoration: item.foiTotalmenteDevolvido
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '${item.quantidade}',
                                  style: TextStyle(
                                    color: foiAlterado
                                        ? Colors.white.withOpacity(0.5)
                                        : Colors.white70,
                                    fontSize: 13,
                                    decoration: item.foiTotalmenteDevolvido
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (foiAlterado && !item.foiTotalmenteDevolvido)
                                  Text(
                                    '(${item.quantidadeEfetiva})',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _formatoMoeda.format(item.precoUnitario),
                              style: TextStyle(
                                color: foiAlterado
                                    ? Colors.white.withOpacity(0.5)
                                    : Colors.white70,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatoMoeda.format(item.subtotal),
                                  style: TextStyle(
                                    color: foiAlterado
                                        ? Colors.white.withOpacity(0.5)
                                        : Colors.greenAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    decoration: item.foiTotalmenteDevolvido
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                                if (foiAlterado && !item.foiTotalmenteDevolvido)
                                  Text(
                                    _formatoMoeda.format(item.subtotalEfetivo),
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.right,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Badge de status
                      if (foiAlterado) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (foiDevolvido)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.keyboard_return,
                                      color: Colors.redAccent,
                                      size: 10,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${item.quantidadeDevolvida} devolvido(s)',
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (foiDevolvido && foiTrocado)
                              const SizedBox(width: 6),
                            if (foiTrocado)
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.swap_horiz,
                                            color: Colors.orange,
                                            size: 10,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${item.quantidadeTrocada} trocado(s)',
                                            style: const TextStyle(
                                              color: Colors.orange,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (item.trocadoPor != null &&
                                          item.trocadoPor!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.arrow_forward,
                                                color: Colors.greenAccent,
                                                size: 8,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  item.trocadoPor!,
                                                  style: const TextStyle(
                                                    color: Colors.greenAccent,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        // Rodapé com informações adicionais
        if (venda.valorRecebido != null || venda.troco != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (venda.valorRecebido != null) ...[
                Text(
                  'Recebido: ${_formatoMoeda.format(venda.valorRecebido)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 16),
              ],
              if (venda.troco != null && venda.troco! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Troco: ${_formatoMoeda.format(venda.troco)}',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
        // Seção de Trocas e Devoluções
        if (trocasDestaVenda.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.withOpacity(0.1),
                  Colors.red.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabeçalho
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.swap_horiz,
                        color: Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Trocas e Devoluções',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${trocasDestaVenda.length}',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Lista de trocas
                ...trocasDestaVenda.map((troca) => _buildItemTroca(troca)),
                // Resumo de valores
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Valor Original:',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatoMoeda.format(venda.valorTotal),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            totalDiferenca >= 0
                                ? 'Cliente pagou a mais:'
                                : 'Devolvido ao cliente:',
                            style: TextStyle(
                              color: totalDiferenca >= 0
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatoMoeda.format(totalDiferenca.abs()),
                            style: TextStyle(
                              color: totalDiferenca >= 0
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'VALOR EFETIVO:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatoMoeda.format(valorEfetivo),
                            style: TextStyle(
                              color: valorEfetivo != venda.valorTotal
                                  ? Colors.orangeAccent
                                  : Colors.greenAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Constrói um item de troca/devolução
  Widget _buildItemTroca(TrocaDevolucao troca) {
    final isTroca = troca.tipo == TipoOperacao.troca;
    final cor = isTroca ? Colors.orange : Colors.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho da troca
          Row(
            children: [
              Icon(
                isTroca ? Icons.swap_horiz : Icons.keyboard_return,
                color: cor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                isTroca ? 'TROCA' : 'DEVOLUÇÃO',
                style: TextStyle(
                  color: cor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('dd/MM/yy HH:mm').format(troca.dataOperacao),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Itens devolvidos
          ...troca.itensDevolvidos.map(
            (item) => Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.redAccent,
                    size: 12,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${item.quantidade}x ${item.produtoNome}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                  Text(
                    '-${_formatoMoeda.format(item.valorTotal)}',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Seta de troca
          if (isTroca &&
              troca.itensNovos != null &&
              troca.itensNovos!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  Icon(
                    Icons.arrow_downward,
                    color: Colors.orange.withOpacity(0.5),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'trocado por',
                    style: TextStyle(
                      color: Colors.orange.withOpacity(0.7),
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            // Itens novos
            ...troca.itensNovos!.map(
              (item) => Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.add_circle_outline,
                      color: Colors.greenAccent,
                      size: 12,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${item.quantidade}x ${item.produtoNome}',
                        style: TextStyle(
                          color: Colors.greenAccent.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '+${_formatoMoeda.format(item.valorTotal)}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // Diferença
          if (troca.diferenca != 0)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (troca.diferenca > 0 ? Colors.green : Colors.red)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      troca.diferenca > 0
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      color: troca.diferenca > 0
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      troca.diferenca > 0
                          ? 'Cliente pagou: ${_formatoMoeda.format(troca.diferenca)}'
                          : 'Devolvido: ${_formatoMoeda.format(troca.diferenca.abs())}',
                      style: TextStyle(
                        color: troca.diferenca > 0
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Motivo
          if (troca.observacao != null && troca.observacao!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: Text(
                'Motivo: ${troca.observacao}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetalhesPedido(Pedido pedido) {
    return Column(
      children: [
        // Produtos do pedido
        if (pedido.produtos.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Cabeçalho
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2,
                        color: Colors.blue,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        flex: 3,
                        child: Text(
                          'Produtos',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'Qtd',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'Subtotal',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
                // Itens
                ...pedido.produtos.map(
                  (item) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            item.nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${item.quantidade}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _formatoMoeda.format(item.preco * item.quantidade),
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Serviços do pedido
        if (pedido.servicos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Cabeçalho
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.build, color: Colors.purple, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Serviços',
                          style: TextStyle(
                            color: Colors.purple,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Valor',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
                // Itens
                ...pedido.servicos.map(
                  (item) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            item.descricao,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _formatoMoeda.format(item.valor),
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        // Pagamentos
        if (pedido.pagamentos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Pagamentos:',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: pedido.pagamentos
                    .map(
                      (pag) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${pag.tipo.nome}: ${_formatoMoeda.format(pag.valor)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildListaVazia() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long,
            size: 80,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhuma venda encontrada',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Não há vendas registradas neste período',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _selecionarData(bool isInicio) async {
    final data = await showDatePicker(
      context: context,
      initialDate: isInicio ? _dataInicio : _dataFim,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.green,
              surface: Color(0xFF1E1E2E),
            ),
          ),
          child: child!,
        );
      },
    );

    if (data != null) {
      // Após selecionar a data, selecionar o horário
      final horaAtual = isInicio ? _horaInicio : _horaFim;
      final hora = await showTimePicker(
        context: context,
        initialTime: horaAtual,
        builder: (context, child) {
          return Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.green,
                surface: Color(0xFF1E1E2E),
              ),
            ),
            child: child!,
          );
        },
      );

      if (hora != null) {
        setState(() {
          if (isInicio) {
            _dataInicio = DateTime(
              data.year,
              data.month,
              data.day,
              hora.hour,
              hora.minute,
            );
            _horaInicio = hora;
            if (_dataInicio.isAfter(_dataFim)) {
              _dataFim = _dataInicio;
              _horaFim = hora;
            }
          } else {
            _dataFim = DateTime(
              data.year,
              data.month,
              data.day,
              hora.hour,
              hora.minute,
              59,
            );
            _horaFim = hora;
            if (_dataFim.isBefore(_dataInicio)) {
              _dataInicio = DateTime(
                data.year,
                data.month,
                data.day,
                0,
                0,
              );
              _horaInicio = const TimeOfDay(hour: 0, minute: 0);
            }
          }
        });
      }
    }
  }

  void _mostrarFiltros() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filtro por Origem
            const Text(
              'Filtrar por Tipo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChipFiltroOrigem('Todos'),
                _buildChipFiltroOrigem('Venda Direta'),
                _buildChipFiltroOrigem('Venda a Prazo'),
                _buildChipFiltroOrigem('Pedido'),
              ],
            ),
            const SizedBox(height: 24),
            // Filtro por Pagamento
            const Text(
              'Filtrar por Pagamento',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChipFiltroPagamento('Todos', null),
                ...TipoPagamento.values.map(
                  (tipo) => _buildChipFiltroPagamento(tipo.nome, tipo),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Atalhos de período
            const Text(
              'Período Rápido',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildBotaoPeriodo('Hoje', 0)),
                const SizedBox(width: 8),
                Expanded(child: _buildBotaoPeriodo('7 dias', 7)),
                const SizedBox(width: 8),
                Expanded(child: _buildBotaoPeriodo('30 dias', 30)),
                const SizedBox(width: 8),
                Expanded(child: _buildBotaoPeriodo('90 dias', 90)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildChipFiltroOrigem(String label) {
    final isSelected = _filtroOrigem == label;
    IconData icone;
    Color cor;
    if (label == 'Venda Direta') {
      icone = Icons.point_of_sale;
      cor = Colors.greenAccent;
    } else if (label == 'Venda a Prazo') {
      icone = Icons.schedule_send;
      cor = Colors.cyan;
    } else if (label == 'Pedido') {
      icone = Icons.receipt_long;
      cor = Colors.orangeAccent;
    } else {
      icone = Icons.all_inclusive;
      cor = Colors.white70;
    }

    return GestureDetector(
      onTap: () {
        setState(() => _filtroOrigem = label);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? cor.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? cor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: isSelected ? cor : Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipFiltroPagamento(String label, TipoPagamento? tipo) {
    final isSelected = _filtroTipoPagamento == label;
    return GestureDetector(
      onTap: () {
        setState(() => _filtroTipoPagamento = label);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.green.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.greenAccent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tipo != null) ...[
              Icon(
                _getIconeTipo(tipo),
                color: isSelected ? Colors.greenAccent : Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotaoPeriodo(String label, int dias) {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _dataFim = DateTime.now();
          _dataInicio = DateTime.now().subtract(Duration(days: dias));
        });
        Navigator.pop(context);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.withOpacity(0.2),
        foregroundColor: Colors.lightBlueAccent,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }

  // Função para agrupar produtos vendidos
  Map<String, _ProdutoVendido> _agruparProdutosVendidos(List<ItemHistorico> itensHistorico) {
    final produtos = <String, _ProdutoVendido>{};

    for (final item in itensHistorico) {
      // Processar itens de VendaBalcao
      if (item.vendaBalcao != null) {
        for (final itemVenda in item.vendaBalcao!.itens) {
          // Considerar apenas produtos (não serviços)
          if (itemVenda.isServico) continue;
          
          // Calcular quantidade efetiva (descontando devoluções e trocas)
          final qtdEfetiva = itemVenda.quantidadeEfetiva;
          if (qtdEfetiva <= 0) continue; // Pular se foi totalmente devolvido/trocado

          final chave = itemVenda.nome.toLowerCase();
          if (!produtos.containsKey(chave)) {
            produtos[chave] = _ProdutoVendido(
              nome: itemVenda.nome,
              produtoId: itemVenda.id,
            );
          }

          final produto = produtos[chave]!;
          produto.quantidadeTotal += qtdEfetiva;
          final valorItem = itemVenda.precoUnitario * qtdEfetiva;
          produto.valorTotal += valorItem;
          final vendasList = List<_VendaProduto>.from(produto.vendas);
          vendasList.add(
            _VendaProduto(
              numeroVenda: item.numero,
              data: item.data,
              quantidade: qtdEfetiva,
              precoUnitario: itemVenda.precoUnitario,
              valorTotal: valorItem,
              clienteNome: item.clienteNome,
            ),
          );
          produto.vendas = vendasList;
        }
      }

      // Processar itens de Pedido
      if (item.pedido != null) {
        for (final produtoPedido in item.pedido!.produtos) {
          final chave = produtoPedido.nome.toLowerCase();
          if (!produtos.containsKey(chave)) {
            produtos[chave] = _ProdutoVendido(
              nome: produtoPedido.nome,
              produtoId: produtoPedido.id,
            );
          }

          final produto = produtos[chave]!;
          produto.quantidadeTotal += produtoPedido.quantidade;
          final valorItem = produtoPedido.preco * produtoPedido.quantidade;
          produto.valorTotal += valorItem;
          final vendasList = List<_VendaProduto>.from(produto.vendas);
          vendasList.add(
            _VendaProduto(
              numeroVenda: item.numero,
              data: item.data,
              quantidade: produtoPedido.quantidade,
              precoUnitario: produtoPedido.preco,
              valorTotal: valorItem,
              clienteNome: item.clienteNome,
            ),
          );
          produto.vendas = vendasList;
        }
      }
    }

    return produtos;
  }

  // Função para mostrar vendas por produto
  void _mostrarVendasPorProduto(
      BuildContext context, DataService dataService, List<ItemHistorico> itensHistorico) {
    final produtos = _agruparProdutosVendidos(itensHistorico);
    final listaProdutos = produtos.values.toList()
      ..sort((a, b) => b.valorTotal.compareTo(a.valorTotal));

    if (listaProdutos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum produto vendido no período selecionado'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Cabeçalho
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, color: Colors.green, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vendas por Produto',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${listaProdutos.length} produto${listaProdutos.length != 1 ? 's' : ''} no período',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Lista de produtos
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: listaProdutos.length,
                itemBuilder: (context, index) {
                  final produto = listaProdutos[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: const Color(0xFF2D2D44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _mostrarDetalhesProduto(context, produto);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.shopping_bag,
                                color: Colors.green,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    produto.nome,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.shopping_cart,
                                        size: 14,
                                        color: Colors.white.withOpacity(0.6),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${produto.quantidadeTotal} unidade${produto.quantidadeTotal != 1 ? 's' : ''}',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(
                                        Icons.receipt,
                                        size: 14,
                                        color: Colors.white.withOpacity(0.6),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${produto.vendas.length} venda${produto.vendas.length != 1 ? 's' : ''}',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatoMoeda.format(produto.valorTotal),
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Total vendido',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  // Função para mostrar resumo de "caixas" (agrupado por caixa, não por dia)
  void _mostrarResumoCaixas(BuildContext context, List<ItemHistorico> itensHistorico) {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);

      // Criar lista de caixas com seus períodos (abertura até fechamento)
      final List<Map<String, dynamic>> caixas = [];

      for (final abertura in dataService.aberturasCaixa) {
        try {
      // Encontrar fechamento correspondente (se houver)
      final fechamentosEncontrados = dataService.fechamentosCaixa
          .where((f) => f.aberturaCaixaId == abertura.id);
      final fechamento = fechamentosEncontrados.isNotEmpty 
          ? fechamentosEncontrados.first 
          : null;

      // Período do caixa: da abertura até o fechamento (ou hoje se ainda aberto)
      final dataInicioCaixa = DateTime(
        abertura.dataAbertura.year,
        abertura.dataAbertura.month,
        abertura.dataAbertura.day,
        abertura.dataAbertura.hour,
        abertura.dataAbertura.minute,
      );
      final dataFimCaixa = fechamento != null
          ? DateTime(
              fechamento.dataFechamento.year,
              fechamento.dataFechamento.month,
              fechamento.dataFechamento.day,
              fechamento.dataFechamento.hour,
              fechamento.dataFechamento.minute,
              59,
            )
          : DateTime.now();

      // Verificar se o caixa está no período filtrado (considerando horário)
      if (dataFimCaixa.compareTo(_dataInicio) < 0 || dataInicioCaixa.compareTo(_dataFim) > 0) {
        continue; // Caixa fora do período filtrado
      }

      // Filtrar vendas apenas do período deste caixa (considerando horário)
      final vendasDoCaixa = itensHistorico.where((item) {
        // Comparar considerando data e horário (incluindo os limites)
        return item.data.compareTo(dataInicioCaixa) >= 0 && 
               item.data.compareTo(dataFimCaixa) <= 0;
      }).toList();

      // Calcular valores por tipo de pagamento
      final Map<TipoPagamento?, double> porTipo = {};
      double totalVendas = 0.0;

      for (final item in vendasDoCaixa) {
        totalVendas += item.valorTotal;
        final tipo = item.tipoPagamento;
        porTipo[tipo] = (porTipo[tipo] ?? 0) + item.valorTotal;
      }

      // Vendas canceladas do período do caixa (considerando horário)
      final pedidosCancelados = dataService.pedidos.where((p) {
        if (p.status.toLowerCase() != 'cancelado') return false;
        // Comparar considerando data e horário (incluindo os limites)
        return p.dataPedido.compareTo(dataInicioCaixa) >= 0 && 
               p.dataPedido.compareTo(dataFimCaixa) <= 0;
      }).toList();

      double totalCanceladas = 0.0;
      for (final pedido in pedidosCancelados) {
        totalCanceladas += pedido.totalGeral;
      }

      // Sangrias do caixa
      double totalSangrias = 0.0;
      if (fechamento != null) {
        for (final sangria in fechamento.sangrias) {
          totalSangrias += sangria.valor;
        }
      }

      // Total líquido do caixa
      final totalLiquido = abertura.valorInicial + totalVendas - totalCanceladas - totalSangrias;

          caixas.add({
            'abertura': abertura,
            'fechamento': fechamento,
            'dataInicio': dataInicioCaixa,
            'dataFim': dataFimCaixa,
            'valorInicial': abertura.valorInicial,
            'porTipo': porTipo,
            'totalVendas': totalVendas,
            'totalCanceladas': totalCanceladas,
            'totalSangrias': totalSangrias,
            'totalLiquido': totalLiquido,
          });
        } catch (e) {
          print('>>> Erro ao processar caixa ${abertura.numero}: $e');
          // Continua processando outros caixas
        }
      }

      // Ordenar por data de abertura (mais recente primeiro)
      caixas.sort((a, b) {
        try {
          return (b['dataInicio'] as DateTime).compareTo(a['dataInicio'] as DateTime);
        } catch (e) {
          print('>>> Erro ao ordenar caixas: $e');
          return 0;
        }
      });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Cabeçalho
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.point_of_sale, color: Colors.amber, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Resumo de Caixas',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${caixas.length} caixa${caixas.length == 1 ? '' : 's'} no período',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Lista de caixas
            Expanded(
              child: caixas.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum caixa no período selecionado',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: caixas.length,
                      itemBuilder: (context, index) {
                        final caixa = caixas[index];
                        final abertura = caixa['abertura'] as AberturaCaixa;
                        final fechamento = caixa['fechamento'] as FechamentoCaixa?;
                        final dataInicio = caixa['dataInicio'] as DateTime;
                        final dataFim = caixa['dataFim'] as DateTime;
                        final valorInicial = caixa['valorInicial'] as double;
                        final porTipo = caixa['porTipo'] as Map<TipoPagamento?, double>;
                        final totalCanceladas = caixa['totalCanceladas'] as double;
                        final totalSangrias = caixa['totalSangrias'] as double;
                        final totalLiquido = caixa['totalLiquido'] as double;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: const Color(0xFF2D2D44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.point_of_sale,
                                                  color: Colors.amber, size: 18),
                                              const SizedBox(width: 8),
                                              Text(
                                                abertura.numero,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              if (fechamento == null)
                                                Container(
                                                  margin: const EdgeInsets.only(left: 8),
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'ABERTO',
                                                    style: TextStyle(
                                                      color: Colors.greenAccent,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${_formatoData.format(dataInicio)} até ${_formatoData.format(dataFim)}',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.6),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _formatoMoeda.format(totalLiquido),
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Informações de abertura, canceladas e sangrias
                                if (valorInicial > 0 || totalCanceladas > 0 || totalSangrias > 0) ...[
                                  if (valorInicial > 0)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.blue.withOpacity(0.5),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.account_balance_wallet,
                                              color: Colors.blue, size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Abertura: ${_formatoMoeda.format(valorInicial)}',
                                            style: const TextStyle(
                                              color: Colors.blueAccent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (totalCanceladas > 0)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.red.withOpacity(0.5),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.cancel,
                                              color: Colors.red, size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Canceladas: ${_formatoMoeda.format(totalCanceladas)}',
                                            style: const TextStyle(
                                              color: Colors.redAccent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (totalSangrias > 0)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.orange.withOpacity(0.5),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.trending_down,
                                              color: Colors.orange, size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Saídas (Sangrias): ${_formatoMoeda.format(totalSangrias)}',
                                            style: const TextStyle(
                                              color: Colors.orangeAccent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                ],
                                // Tipos de pagamento
                                if (porTipo.isNotEmpty) ...[
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: porTipo.entries.map((entry) {
                                      final tipo = entry.key;
                                      final valor = entry.value;

                                      IconData icone;
                                      String label;

                                      if (tipo != null) {
                                        icone = _getIconeTipo(tipo);
                                        label = tipo.nome;
                                      } else {
                                        icone = Icons.help_outline;
                                        label = 'Sem classificação';
                                      }

                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(icone,
                                                color: Colors.white54, size: 16),
                                            const SizedBox(width: 6),
                                            Text(
                                              '$label: ${_formatoMoeda.format(valor)}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
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
    } catch (e, stackTrace) {
      print('>>> Erro ao mostrar resumo de caixas: $e');
      print('>>> Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exibir resumo de caixas: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // Função para dialog de fechamento de caixa
  void _mostrarDialogFechamentoCaixa(
    BuildContext context,
    DataService dataService,
    List<ItemHistorico> itensHistorico,
  ) {
    if (!dataService.caixaAberto || dataService.aberturaCaixaAtual == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum caixa aberto para fechar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final abertura = dataService.aberturaCaixaAtual!;

    // Calcular valores esperados por tipo de pagamento
    final totalDinheiro = itensHistorico
        .where((i) => i.tipoPagamento == TipoPagamento.dinheiro)
        .fold(0.0, (sum, i) => sum + i.valorTotal);
    final totalPix = itensHistorico
        .where((i) => i.tipoPagamento == TipoPagamento.pix)
        .fold(0.0, (sum, i) => sum + i.valorTotal);
    final totalDebito = itensHistorico
        .where((i) => i.tipoPagamento == TipoPagamento.cartaoDebito)
        .fold(0.0, (sum, i) => sum + i.valorTotal);
    final totalCredito = itensHistorico
        .where((i) => i.tipoPagamento == TipoPagamento.cartaoCredito)
        .fold(0.0, (sum, i) => sum + i.valorTotal);

    // Valor esperado em dinheiro = valor inicial + vendas em dinheiro
    final valorEsperadoDinheiro = abertura.valorInicial + totalDinheiro;

    // Controllers para valores reais informados
    final controllerDinheiro = TextEditingController(
      text: valorEsperadoDinheiro.toStringAsFixed(2),
    );
    final controllerPix = TextEditingController(
      text: totalPix.toStringAsFixed(2),
    );
    final controllerDebito = TextEditingController(
      text: totalDebito.toStringAsFixed(2),
    );
    final controllerCredito = TextEditingController(
      text: totalCredito.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Função para calcular totais e diferença
            void atualizarTotais() {
              setState(() {});
            }

            double parseValor(String texto) {
              if (texto.isEmpty) return 0.0;
              
              // Remove espaços e R$
              String normalizado = texto
                  .replaceAll('R\$', '')
                  .replaceAll(' ', '')
                  .trim();
              
              // Se tem vírgula, assume formato brasileiro (100,50)
              if (normalizado.contains(',') && !normalizado.contains('.')) {
                normalizado = normalizado.replaceAll(',', '.');
              }
              // Se tem ponto e vírgula, assume formato brasileiro (1.000,50)
              else if (normalizado.contains('.') && normalizado.contains(',')) {
                // Remove pontos (separadores de milhar) e substitui vírgula por ponto
                normalizado = normalizado.replaceAll('.', '').replaceAll(',', '.');
              }
              // Se só tem pontos, pode ser formato americano (100.50) ou milhar (1.000)
              else if (normalizado.contains('.') && !normalizado.contains(',')) {
                // Se tem mais de um ponto ou o último ponto não é seguido de 2 dígitos, é milhar
                final partes = normalizado.split('.');
                if (partes.length > 2 || (partes.length == 2 && partes.last.length != 2)) {
                  // É milhar, remove pontos
                  normalizado = normalizado.replaceAll('.', '');
                }
                // Caso contrário, mantém como está (formato americano 100.50)
              }
              
              return double.tryParse(normalizado) ?? 0.0;
            }

            final valorRealDinheiro = parseValor(controllerDinheiro.text);
            final valorRealPix = parseValor(controllerPix.text);
            final valorRealDebito = parseValor(controllerDebito.text);
            final valorRealCredito = parseValor(controllerCredito.text);

            final totalEsperado = valorEsperadoDinheiro + totalPix + totalDebito + totalCredito;
            final totalReal = valorRealDinheiro + valorRealPix + valorRealDebito + valorRealCredito;
            final diferenca = totalReal - totalEsperado;

            return AlertDialog(
              title: const Text('Fechamento de Caixa'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Resumo dos valores esperados
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Valores Esperados:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Valor de abertura separado
                          _buildLinhaValor('💰 Valor de Abertura', abertura.valorInicial, _formatoMoeda),
                          _buildLinhaValor('💰 Vendas em Dinheiro', totalDinheiro, _formatoMoeda),
                          _buildLinhaValor('💰 Total Dinheiro', valorEsperadoDinheiro, _formatoMoeda, isTotal: false),
                          const SizedBox(height: 4),
                          _buildLinhaValor('📱 PIX', totalPix, _formatoMoeda),
                          _buildLinhaValor('💳 Débito', totalDebito, _formatoMoeda),
                          _buildLinhaValor('💳 Crédito', totalCredito, _formatoMoeda),
                          const Divider(),
                          _buildLinhaValor('TOTAL ESPERADO', totalEsperado, _formatoMoeda, isTotal: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Informe os valores contados:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    // Campo Dinheiro
                    TextField(
                      controller: controllerDinheiro,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '💰 Dinheiro (Abertura + Vendas)',
                        prefixText: 'R\$ ',
                        helperText: 'Abertura: ${_formatoMoeda.format(abertura.valorInicial)} + Vendas: ${_formatoMoeda.format(totalDinheiro)} = ${_formatoMoeda.format(valorEsperadoDinheiro)}',
                        helperMaxLines: 2,
                        suffixText: _formatoMoeda.format(valorEsperadoDinheiro),
                        suffixStyle: TextStyle(
                          color: Colors.blue.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      onChanged: (_) => atualizarTotais(),
                    ),
                    const SizedBox(height: 12),
                    // Campo PIX
                    TextField(
                      controller: controllerPix,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '📱 PIX',
                        prefixText: 'R\$ ',
                        suffixText: _formatoMoeda.format(totalPix),
                        suffixStyle: TextStyle(
                          color: Colors.blue.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      onChanged: (_) => atualizarTotais(),
                    ),
                    const SizedBox(height: 12),
                    // Campo Débito
                    TextField(
                      controller: controllerDebito,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '💳 Débito',
                        prefixText: 'R\$ ',
                        suffixText: _formatoMoeda.format(totalDebito),
                        suffixStyle: TextStyle(
                          color: Colors.blue.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      onChanged: (_) => atualizarTotais(),
                    ),
                    const SizedBox(height: 12),
                    // Campo Crédito
                    TextField(
                      controller: controllerCredito,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '💳 Crédito',
                        prefixText: 'R\$ ',
                        suffixText: _formatoMoeda.format(totalCredito),
                        suffixStyle: TextStyle(
                          color: Colors.blue.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      onChanged: (_) => atualizarTotais(),
                    ),
                    const SizedBox(height: 16),
                    // Resumo dos valores reais e diferença
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: diferenca >= 0
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Resumo:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildLinhaValor('💰 Dinheiro Real', valorRealDinheiro, _formatoMoeda),
                          _buildLinhaValor('📱 PIX Real', valorRealPix, _formatoMoeda),
                          _buildLinhaValor('💳 Débito Real', valorRealDebito, _formatoMoeda),
                          _buildLinhaValor('💳 Crédito Real', valorRealCredito, _formatoMoeda),
                          const Divider(),
                          _buildLinhaValor('Total Real', totalReal, _formatoMoeda, isTotal: true),
                          _buildLinhaValor('Total Esperado', totalEsperado, _formatoMoeda),
                          const Divider(),
                          _buildLinhaValor(
                            'Diferença',
                            diferenca,
                            _formatoMoeda,
                            isTotal: true,
                            cor: diferenca >= 0 ? Colors.green : Colors.red,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Parsear valores novamente para garantir que estamos usando os valores mais atualizados
                    double parseValorFinal(String texto) {
                      if (texto.isEmpty) return 0.0;
                      
                      String normalizado = texto
                          .replaceAll('R\$', '')
                          .replaceAll(' ', '')
                          .trim();
                      
                      if (normalizado.contains(',') && !normalizado.contains('.')) {
                        normalizado = normalizado.replaceAll(',', '.');
                      }
                      else if (normalizado.contains('.') && normalizado.contains(',')) {
                        normalizado = normalizado.replaceAll('.', '').replaceAll(',', '.');
                      }
                      else if (normalizado.contains('.') && !normalizado.contains(',')) {
                        final partes = normalizado.split('.');
                        if (partes.length > 2 || (partes.length == 2 && partes.last.length != 2)) {
                          normalizado = normalizado.replaceAll('.', '');
                        }
                      }
                      
                      return double.tryParse(normalizado) ?? 0.0;
                    }

                    final valorRealDinheiroFinal = parseValorFinal(controllerDinheiro.text);
                    final valorRealPixFinal = parseValorFinal(controllerPix.text);
                    final valorRealDebitoFinal = parseValorFinal(controllerDebito.text);
                    final valorRealCreditoFinal = parseValorFinal(controllerCredito.text);

                    final totalRealFinal = valorRealDinheiroFinal + valorRealPixFinal + valorRealDebitoFinal + valorRealCreditoFinal;
                    final diferencaFinal = totalRealFinal - totalEsperado;

                    // Registrar fechamento usando o valor total real
                    await dataService.registrarFechamentoCaixa(
                      valorEsperado: totalEsperado,
                      valorReal: totalRealFinal,
                    );

                    if (mounted) {
                      Navigator.of(dialogContext).pop();
                      
                      // Mostrar mensagem de sucesso
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            diferencaFinal >= 0
                                ? 'Caixa fechado. Diferença: ${_formatoMoeda.format(diferencaFinal)}'
                                : 'Caixa fechado. Faltam: ${_formatoMoeda.format(-diferencaFinal)}',
                          ),
                          backgroundColor: diferencaFinal >= 0 ? Colors.green : Colors.orange,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      
                      // Fechar todas as telas e voltar para a Home
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomePage()),
                        (route) => false, // Remove todas as rotas anteriores
                      );
                    }
                  },
                  child: const Text('Fechar Caixa'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLinhaValor(String label, double valor, NumberFormat formato, {bool isTotal = false, Color? cor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 14 : 12,
              color: cor ?? Colors.white70,
            ),
          ),
          Text(
            formato.format(valor),
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 14 : 12,
              color: cor ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Função para mostrar detalhes de um produto específico
  void _mostrarDetalhesProduto(BuildContext context, _ProdutoVendido produto) {
    // Ordenar vendas por data (mais recente primeiro)
    final vendasOrdenadas = List<_VendaProduto>.from(produto.vendas)
      ..sort((a, b) => b.data.compareTo(a.data));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.withOpacity(0.2), Colors.blue.withOpacity(0.1)],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2,
                      color: Colors.green,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          produto.nome,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Período: ${_formatoData.format(_dataInicio)} até ${_formatoData.format(_dataFim)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Resumo
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildEstatistica(
                    'Quantidade',
                    '${produto.quantidadeTotal}',
                    Icons.shopping_cart,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  _buildEstatistica(
                    'Total Vendido',
                    _formatoMoeda.format(produto.valorTotal),
                    Icons.attach_money,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  _buildEstatistica(
                    'Vendas',
                    '${produto.vendas.length}',
                    Icons.receipt,
                  ),
                ],
              ),
            ),
            // Lista de vendas
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: vendasOrdenadas.length,
                itemBuilder: (context, index) {
                  final venda = vendasOrdenadas[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: const Color(0xFF2D2D44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.receipt,
                              color: Colors.blue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  venda.numeroVenda,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      size: 12,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_formatoData.format(venda.data)} ${_formatoHora.format(venda.data)}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.6),
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (venda.clienteNome != null) ...[
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.person,
                                        size: 12,
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          venda.clienteNome!,
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.6),
                                            fontSize: 11,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${venda.quantidade}x',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _formatoMoeda.format(venda.precoUnitario),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                _formatoMoeda.format(venda.valorTotal),
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
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

  Widget _buildEstatistica(String label, String valor, IconData icone) {
    return Column(
      children: [
        Icon(icone, color: Colors.green, size: 24),
        const SizedBox(height: 4),
        Text(
          valor,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  IconData _getIconeTipo(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_today;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
    }
  }
}
