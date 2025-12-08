import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/pedido.dart';
import '../models/venda_balcao.dart';
import '../models/troca_devolucao.dart';
import '../models/forma_pagamento.dart';
import '../models/produto.dart';
import 'historico_vendas_page.dart';

/// Página inteligente de Trocas e Devoluções
class TrocasDevolucoesBuscarPage extends StatefulWidget {
  const TrocasDevolucoesBuscarPage({super.key});

  @override
  State<TrocasDevolucoesBuscarPage> createState() =>
      _TrocasDevolucoesBuscarPageState();
}

class _TrocasDevolucoesBuscarPageState
    extends State<TrocasDevolucoesBuscarPage> {
  final _buscaController = TextEditingController();
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  String _termoBusca = '';
  List<_VendaUnificada> _resultados = [];

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _buscar(DataService dataService) {
    if (_termoBusca.isEmpty) {
      setState(() => _resultados = []);
      return;
    }

    final termo = _termoBusca.toLowerCase().trim();
    final resultados = <_VendaUnificada>[];

    // Buscar nos pedidos - apenas pedidos finalizados (totalmente recebidos)
    for (final pedido in dataService.pedidos) {
      // Filtrar apenas pedidos finalizados (totalmente recebidos) e não cancelados
      if (pedido.status.toLowerCase() == 'cancelado') continue;
      if (!pedido.totalmenteRecebido) continue;
      
      bool match = false;

      // Busca por número
      if (pedido.numero.toLowerCase().contains(termo)) match = true;

      // Busca por cliente
      if (pedido.clienteNome?.toLowerCase().contains(termo) ?? false) {
        match = true;
      }

      // Busca por produto
      for (final prod in pedido.produtos) {
        if (prod.nome.toLowerCase().contains(termo)) {
          match = true;
          break;
        }
      }

      if (match) {
        resultados.add(_VendaUnificada.fromPedido(pedido));
      }
    }

    // Buscar nas vendas balcão - apenas vendas finalizadas (com valorRecebido ou não canceladas)
    for (final venda in dataService.vendasBalcao) {
      // Filtrar apenas vendas finalizadas:
      // - Não canceladas
      // - Com valorRecebido definido (vendas pagas) OU tipo diferente de "outro" (vendas salvas não aparecem)
      if (venda.isCancelada) continue;
      if (venda.tipoPagamento == TipoPagamento.outro && venda.valorRecebido == null) continue;
      
      bool match = false;

      // Busca por número
      if (venda.numero.toLowerCase().contains(termo)) match = true;

      // Busca por cliente
      if (venda.clienteNome?.toLowerCase().contains(termo) ?? false) {
        match = true;
      }

      // Busca por produto
      for (final item in venda.itens) {
        if (item.nome.toLowerCase().contains(termo)) {
          match = true;
          break;
        }
      }

      if (match) {
        resultados.add(_VendaUnificada.fromVendaBalcao(venda));
      }
    }

    // Ordenar por data (mais recente primeiro)
    resultados.sort((a, b) => b.data.compareTo(a.data));

    setState(() => _resultados = resultados);
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withOpacity(0.3),
                    Colors.red.withOpacity(0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.swap_horiz,
                color: Colors.orange,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Trocas e Devoluções',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Instruções
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.withOpacity(0.1),
                  Colors.red.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb,
                      color: Colors.orange.withOpacity(0.8),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Busque a venda original para iniciar uma troca ou devolução',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildDica(Icons.receipt, 'Número da venda'),
                    const SizedBox(width: 12),
                    _buildDica(Icons.person, 'Nome do cliente'),
                    const SizedBox(width: 12),
                    _buildDica(Icons.inventory_2, 'Nome do produto'),
                  ],
                ),
              ],
            ),
          ),

          // Campo de busca
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _buscaController,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: '🔍 Digite para buscar a venda...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                prefixIcon: const Icon(Icons.search, color: Colors.orange),
                suffixIcon: _termoBusca.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _buscaController.clear();
                          setState(() {
                            _termoBusca = '';
                            _resultados = [];
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(20),
              ),
              onChanged: (value) {
                setState(() => _termoBusca = value);
                _buscar(dataService);
              },
            ),
          ),

          const SizedBox(height: 16),

          // Resultados
          Expanded(
            child: _resultados.isEmpty
                ? _buildEstadoVazio()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _resultados.length,
                    itemBuilder: (context, index) {
                      return _buildCardVenda(_resultados[index], dataService);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDica(IconData icon, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            texto,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoVazio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _termoBusca.isEmpty ? Icons.swap_horiz : Icons.search_off,
            size: 80,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 24),
          Text(
            _termoBusca.isEmpty
                ? 'Digite para buscar uma venda'
                : 'Nenhuma venda encontrada',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _termoBusca.isEmpty
                ? 'Busque pelo número, cliente ou produto'
                : 'Tente buscar por outro termo',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardVenda(_VendaUnificada venda, DataService dataService) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1E2E),
            Color.lerp(const Color(0xFF1E1E2E), Colors.orange, 0.03)!,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Navegar para a tela de seleção de itens
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => _SelecionarItensTrocaPage(venda: venda),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linha 1: Número e tipo
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.withOpacity(0.3),
                            Colors.red.withOpacity(0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.receipt_long,
                        color: Colors.orange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                venda.numero,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: venda.isPedido
                                      ? Colors.blue.withOpacity(0.2)
                                      : Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  venda.isPedido ? 'Pedido' : 'Venda Direta',
                                  style: TextStyle(
                                    color: venda.isPedido
                                        ? Colors.lightBlueAccent
                                        : Colors.greenAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatoData.format(venda.data),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatoMoeda.format(venda.valorTotal),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          '${venda.itens.length} ${venda.itens.length == 1 ? 'item' : 'itens'}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Cliente
                if (venda.clienteNome != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person,
                          color: Colors.purpleAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          venda.clienteNome!,
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Lista de itens (preview)
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: venda.itens.take(4).map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${item.quantidade}x ${item.nome}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (venda.itens.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '+${venda.itens.length - 4} itens...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                // Botão de ação
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.withOpacity(0.2),
                            Colors.red.withOpacity(0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_horiz,
                            color: Colors.orange,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Iniciar Troca/Devolução',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
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
}

/// Página de seleção de itens para troca/devolução
class _SelecionarItensTrocaPage extends StatefulWidget {
  final _VendaUnificada venda;

  const _SelecionarItensTrocaPage({required this.venda});

  @override
  State<_SelecionarItensTrocaPage> createState() =>
      _SelecionarItensTrocaPageState();
}

class _SelecionarItensTrocaPageState extends State<_SelecionarItensTrocaPage> {
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _motivoController = TextEditingController();

  // Mapa de itens selecionados: produtoId -> quantidade a devolver
  final Map<String, int> _itensSelecionados = {};
  TipoOperacao _tipoOperacao = TipoOperacao.devolucao;
  String _motivo = '';

  double get _valorTotal {
    double total = 0;
    for (final item in widget.venda.itens) {
      final qtdDevolver = _itensSelecionados[item.id] ?? 0;
      total += qtdDevolver * item.preco;
    }
    return total;
  }

  int get _qtdItensSelecionados {
    return _itensSelecionados.values.fold(0, (sum, qtd) => sum + qtd);
  }

  @override
  void dispose() {
    _motivoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecionar Itens',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.venda.numero,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Tipo de operação
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tipo de Operação',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildOpcaoTipo(
                        TipoOperacao.devolucao,
                        Icons.keyboard_return,
                        'Devolução',
                        'Devolver produtos e receber o valor',
                        Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildOpcaoTipo(
                        TipoOperacao.troca,
                        Icons.swap_horiz,
                        'Troca',
                        'Trocar por outros produtos',
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista de itens
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.venda.itens.length,
              itemBuilder: (context, index) {
                final item = widget.venda.itens[index];
                return _buildItemCard(item);
              },
            ),
          ),

          // Resumo e botão de confirmar
          if (_qtdItensSelecionados > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Campo de motivo
                    TextField(
                      controller: _motivoController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText:
                            'Motivo da ${_tipoOperacao.nome.toLowerCase()} (opcional)',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(
                          Icons.comment,
                          color: Colors.white54,
                        ),
                      ),
                      onChanged: (value) => setState(() => _motivo = value),
                    ),
                    const SizedBox(height: 16),
                    // Resumo
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_qtdItensSelecionados ${_qtdItensSelecionados == 1 ? 'item' : 'itens'} selecionados',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Valor: ${_formatoMoeda.format(_valorTotal)}',
                              style: TextStyle(
                                color: _tipoOperacao == TipoOperacao.devolucao
                                    ? Colors.greenAccent
                                    : Colors.orange,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _confirmarOperacao(dataService),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _tipoOperacao == TipoOperacao.devolucao
                                ? Colors.red.withOpacity(0.8)
                                : Colors.orange.withOpacity(0.8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            _tipoOperacao == TipoOperacao.devolucao
                                ? Icons.keyboard_return
                                : Icons.swap_horiz,
                          ),
                          label: Text(
                            _tipoOperacao == TipoOperacao.devolucao
                                ? 'Confirmar Devolução'
                                : 'Ir para Troca',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOpcaoTipo(
    TipoOperacao tipo,
    IconData icon,
    String label,
    String descricao,
    Color cor,
  ) {
    final isSelected = _tipoOperacao == tipo;
    return GestureDetector(
      onTap: () => setState(() => _tipoOperacao = tipo),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [cor.withOpacity(0.2), cor.withOpacity(0.1)],
                )
              : null,
          color: isSelected ? null : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? cor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? cor : Colors.white54, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? cor : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              descricao,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(_ItemVenda item) {
    final qtdSelecionada = _itensSelecionados[item.id] ?? 0;
    final isSelected = qtdSelecionada > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? (_tipoOperacao == TipoOperacao.devolucao
                    ? Colors.red.withOpacity(0.5)
                    : Colors.orange.withOpacity(0.5))
              : Colors.white.withOpacity(0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Checkbox visual
            GestureDetector(
              onTap: () {
                setState(() {
                  if (qtdSelecionada > 0) {
                    _itensSelecionados.remove(item.id);
                  } else {
                    _itensSelecionados[item.id] = item.quantidade;
                  }
                });
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (_tipoOperacao == TipoOperacao.devolucao
                            ? Colors.red.withOpacity(0.8)
                            : Colors.orange.withOpacity(0.8))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            // Info do item
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nome,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Qtd comprada: ${item.quantidade}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatoMoeda.format(item.preco),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Seletor de quantidade
            if (isSelected)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          if (qtdSelecionada > 1) {
                            _itensSelecionados[item.id] = qtdSelecionada - 1;
                          } else {
                            _itensSelecionados.remove(item.id);
                          }
                        });
                      },
                      icon: const Icon(Icons.remove, color: Colors.white70),
                      iconSize: 20,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                    Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text(
                        '$qtdSelecionada',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: qtdSelecionada < item.quantidade
                          ? () {
                              setState(() {
                                _itensSelecionados[item.id] =
                                    qtdSelecionada + 1;
                              });
                            }
                          : null,
                      icon: Icon(
                        Icons.add,
                        color: qtdSelecionada < item.quantidade
                            ? Colors.white70
                            : Colors.white24,
                      ),
                      iconSize: 20,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
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

  void _confirmarOperacao(DataService dataService) {
    if (_tipoOperacao == TipoOperacao.devolucao) {
      _processarDevolucao(dataService);
    } else {
      _navegarParaTroca(dataService);
    }
  }

  Future<void> _processarDevolucao(DataService dataService) async {
    final venda = widget.venda;

    // 1. CRIAR LISTA DE ITENS DEVOLVIDOS E DEVOLVER AO ESTOQUE
    final itensDevolvidos = <ItemTrocaDevolucao>[];

    for (final item in venda.itens) {
      final qtdDevolver = _itensSelecionados[item.id] ?? 0;
      if (qtdDevolver > 0) {
        itensDevolvidos.add(
          ItemTrocaDevolucao(
            produtoId: item.produtoId ?? item.id,
            produtoNome: item.nome,
            quantidade: qtdDevolver,
            precoUnitario: item.preco,
            valorTotal: qtdDevolver * item.preco,
            motivo: _motivo.isNotEmpty ? _motivo : null,
          ),
        );

        // Devolver ao estoque
        try {
          // Tentar buscar pelo ID primeiro (mais confiável), depois pelo nome
          Produto? produto;
          try {
            produto = dataService.produtos.firstWhere(
              (p) => p.id == item.id,
            );
          } catch (_) {
            // Se não encontrou pelo ID, tentar pelo nome
            produto = dataService.produtos.firstWhere(
              (p) => p.nome == item.nome,
            );
          }
          
          final estoqueAnterior = produto.estoque;
          final novoEstoque = produto.estoque + qtdDevolver;
          
          dataService.updateProduto(
            produto.copyWith(
              estoque: novoEstoque,
              updatedAt: DateTime.now(),
            ),
          );
          
          debugPrint('>>> ✓ Estoque atualizado - Devolução:');
          debugPrint('>>>   Produto: ${produto.nome}');
          debugPrint('>>>   Estoque anterior: $estoqueAnterior');
          debugPrint('>>>   Quantidade devolvida: $qtdDevolver');
          debugPrint('>>>   Novo estoque: $novoEstoque');
        } catch (e) {
          debugPrint('>>> ERRO ao devolver produto ${item.nome} ao estoque: $e');
        }
      }
    }

    // 2. CALCULAR NOVO VALOR: (original - valor devolvido), mínimo 0
    final novoValor = (venda.valorTotal - _valorTotal).clamp(
      0.0,
      double.infinity,
    );

    // 3. CRIAR ITENS ATUALIZADOS (zerar preço dos devolvidos)
    final novosItens = <ItemVendaBalcao>[];
    for (final item in venda.itens) {
      final qtdDevolver = _itensSelecionados[item.id] ?? 0;

      if (qtdDevolver > 0 && qtdDevolver >= item.quantidade) {
        // Item totalmente devolvido: zerar preço
        novosItens.add(
          ItemVendaBalcao(
            id: item.id,
            nome: item.nome,
            precoUnitario: 0,
            quantidade: item.quantidade,
            isServico: false,
            quantidadeDevolvida: item.quantidade,
          ),
        );
      } else if (qtdDevolver > 0) {
        // Item parcialmente devolvido
        novosItens.add(
          ItemVendaBalcao(
            id: item.id,
            nome: item.nome,
            precoUnitario: item.preco,
            quantidade: item.quantidade - qtdDevolver,
            isServico: false,
            quantidadeDevolvida: qtdDevolver,
          ),
        );
      } else {
        // Item não devolvido: manter igual
        novosItens.add(
          ItemVendaBalcao(
            id: item.id,
            nome: item.nome,
            precoUnitario: item.preco,
            quantidade: item.quantidade,
            isServico: false,
          ),
        );
      }
    }

    // 4. CRIAR/ATUALIZAR VENDA (igual à troca)
    final vendaAtualizada = VendaBalcao(
      id: venda.id,
      numero: venda.numero,
      dataVenda: venda.data,
      clienteId: venda.clienteId,
      clienteNome: venda.clienteNome,
      itens: novosItens,
      valorTotal: novoValor,
      tipoPagamento: TipoPagamento.dinheiro,
    );

    // Atualizar ou adicionar na lista de vendasBalcao
    final indexVenda = dataService.vendasBalcao.indexWhere(
      (v) => v.id == venda.id || v.numero == venda.numero,
    );

    if (indexVenda != -1) {
      await dataService.updateVendaBalcao(vendaAtualizada);
    } else {
      // Se não existe na lista, adicionar para manter o registro com itens devolvidos
      await dataService.addVendaBalcao(vendaAtualizada);
    }

    // 5. ATUALIZAR PEDIDO CORRESPONDENTE (se existir)
    final indexPedido = dataService.pedidos.indexWhere(
      (p) => p.numero == venda.numero,
    );

    debugPrint('=== ATUALIZANDO PEDIDO ===');
    debugPrint('indexPedido: $indexPedido');
    debugPrint('venda.numero: ${venda.numero}');
    debugPrint('novoValor: $novoValor');
    debugPrint('_valorTotal (devolvido): $_valorTotal');
    debugPrint('venda.valorTotal (original): ${venda.valorTotal}');

    if (indexPedido != -1) {
      final pedidoOriginal = dataService.pedidos[indexPedido];
      debugPrint('Pedido encontrado: ${pedidoOriginal.numero}');
      debugPrint('Pagamentos: ${pedidoOriginal.pagamentos.length}');

      // Atualizar os pagamentos para refletir a devolução
      // Se novoValor = 0, zerar todos os pagamentos
      final pagamentosAtualizados = pedidoOriginal.pagamentos.map((pag) {
        if (pag.recebido) {
          double novoValorPag;
          if (novoValor <= 0 || venda.valorTotal <= 0) {
            // Devolução total - zerar pagamento
            novoValorPag = 0;
          } else {
            // Devolução parcial - calcular proporção
            final proporcao = novoValor / venda.valorTotal;
            novoValorPag = pag.valor * proporcao;
          }
          debugPrint('Pagamento ${pag.id}: ${pag.valor} -> $novoValorPag');
          return PagamentoPedido(
            id: pag.id,
            tipo: pag.tipo,
            valor: novoValorPag,
            recebido: pag.recebido,
            dataVencimento: pag.dataVencimento,
            dataRecebimento: pag.dataRecebimento,
            parcelas: pag.parcelas,
            numeroParcela: pag.numeroParcela,
            parcelamentoId: pag.parcelamentoId,
            observacao: pag.observacao,
            tipoOriginal: pag.tipoOriginal,
          );
        }
        return pag;
      }).toList();

      final pedidoAtualizado = pedidoOriginal.copyWith(
        total: novoValor,
        pagamentos: pagamentosAtualizados,
      );
      dataService.updatePedido(pedidoAtualizado);
      debugPrint('Pedido atualizado com total: ${pedidoAtualizado.total}');
      debugPrint('totalRecebido será: ${pedidoAtualizado.totalRecebido}');
    } else {
      debugPrint('!!! PEDIDO NÃO ENCONTRADO !!!');
      // Listar todos os pedidos para debug
      for (final p in dataService.pedidos) {
        debugPrint('  - ${p.numero}');
      }
    }

    // 5. CRIAR REGISTRO DA DEVOLUÇÃO
    final troca = TrocaDevolucao(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      pedidoId: venda.id,
      numeroPedido: venda.numero,
      clienteId: venda.clienteId,
      clienteNome: venda.clienteNome,
      dataOperacao: DateTime.now(),
      tipo: TipoOperacao.devolucao,
      itensDevolvidos: itensDevolvidos,
      valorDevolvido: _valorTotal,
      diferenca: -_valorTotal,
      observacao: _motivo.isNotEmpty ? _motivo : null,
      status: 'Concluído',
    );

    await dataService.addTrocaDevolucao(troca);

    // Mostrar confirmação
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.greenAccent,
                size: 60,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Devolução Realizada!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${itensDevolvidos.length} ${itensDevolvidos.length == 1 ? 'item devolvido' : 'itens devolvidos'}\nEstoque atualizado',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Valor a devolver: ${_formatoMoeda.format(_valorTotal)}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Fechar dialog
                Navigator.pop(context); // Voltar para seleção
                Navigator.pop(context); // Voltar para busca
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.withOpacity(0.8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Concluir',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navegarParaTroca(DataService dataService) {
    // Criar lista de itens a devolver
    final itensDevolver = <_ItemVenda>[];
    for (final item in widget.venda.itens) {
      final qtd = _itensSelecionados[item.id] ?? 0;
      if (qtd > 0) {
        itensDevolver.add(
          _ItemVenda(
            id: item.id,
            produtoId: item.produtoId,
            nome: item.nome,
            quantidade: qtd,
            preco: item.preco,
          ),
        );
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _SelecionarNovosProdutosPage(
          vendaOriginal: widget.venda,
          itensDevolver: itensDevolver,
          valorCredito: _valorTotal,
          motivo: _motivo,
        ),
      ),
    );
  }
}

/// Página de seleção de novos produtos para troca
class _SelecionarNovosProdutosPage extends StatefulWidget {
  final _VendaUnificada vendaOriginal;
  final List<_ItemVenda> itensDevolver;
  final double valorCredito;
  final String motivo;

  const _SelecionarNovosProdutosPage({
    required this.vendaOriginal,
    required this.itensDevolver,
    required this.valorCredito,
    required this.motivo,
  });

  @override
  State<_SelecionarNovosProdutosPage> createState() =>
      _SelecionarNovosProdutosPageState();
}

class _SelecionarNovosProdutosPageState
    extends State<_SelecionarNovosProdutosPage> {
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _buscaController = TextEditingController();

  String _termoBusca = '';
  final Map<String, int> _novosProdutos = {}; // produtoId -> quantidade

  double get _valorNovos {
    final dataService = Provider.of<DataService>(context, listen: false);
    double total = 0;
    for (final entry in _novosProdutos.entries) {
      final produto = dataService.produtos.firstWhere((p) => p.id == entry.key);
      total += produto.preco * entry.value;
    }
    return total;
  }

  double get _diferenca => _valorNovos - widget.valorCredito;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);

    // Filtrar produtos
    var produtos = dataService.produtos.where((p) => p.estoque > 0).toList();
    if (_termoBusca.isNotEmpty) {
      final termo = _termoBusca.toLowerCase();
      produtos = produtos
          .where(
            (p) =>
                p.nome.toLowerCase().contains(termo) ||
                (p.codigo?.toLowerCase().contains(termo) ?? false),
          )
          .toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Selecionar Novos Produtos'),
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Crédito disponível
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.green.withOpacity(0.2),
                  Colors.teal.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
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
                    Icons.account_balance_wallet,
                    color: Colors.greenAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Crédito Disponível',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatoMoeda.format(widget.valorCredito),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${widget.itensDevolver.length} itens',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    const Text(
                      'a devolver',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Campo de busca
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _buscaController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '🔍 Buscar produto...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
              onChanged: (value) => setState(() => _termoBusca = value),
            ),
          ),

          const SizedBox(height: 12),

          // Lista de produtos
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: produtos.length,
              itemBuilder: (context, index) {
                final produto = produtos[index];
                final qtdSelecionada = _novosProdutos[produto.id] ?? 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E2E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: qtdSelecionada > 0
                          ? Colors.orange.withOpacity(0.5)
                          : Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.inventory_2,
                        color: Colors.lightBlueAccent,
                      ),
                    ),
                    title: Text(
                      produto.nome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          _formatoMoeda.format(produto.preco),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Estoque: ${produto.estoque}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (qtdSelecionada > 0)
                          IconButton(
                            onPressed: () {
                              setState(() {
                                if (qtdSelecionada > 1) {
                                  _novosProdutos[produto.id] =
                                      qtdSelecionada - 1;
                                } else {
                                  _novosProdutos.remove(produto.id);
                                }
                              });
                            },
                            icon: const Icon(
                              Icons.remove,
                              color: Colors.white70,
                            ),
                          ),
                        if (qtdSelecionada > 0)
                          Container(
                            width: 32,
                            alignment: Alignment.center,
                            child: Text(
                              '$qtdSelecionada',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        IconButton(
                          onPressed: qtdSelecionada < produto.estoque
                              ? () {
                                  setState(() {
                                    _novosProdutos[produto.id] =
                                        qtdSelecionada + 1;
                                  });
                                }
                              : null,
                          icon: Icon(
                            Icons.add,
                            color: qtdSelecionada < produto.estoque
                                ? Colors.orange
                                : Colors.white24,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Resumo e botão confirmar
          if (_novosProdutos.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Resumo de valores
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Novos produtos:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          _formatoMoeda.format(_valorNovos),
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
                        const Text(
                          'Crédito:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '- ${_formatoMoeda.format(widget.valorCredito)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _diferenca >= 0 ? 'A pagar:' : 'A receber:',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _formatoMoeda.format(_diferenca.abs()),
                          style: TextStyle(
                            color: _diferenca >= 0
                                ? Colors.red
                                : Colors.greenAccent,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await _confirmarTroca(dataService);
                          } catch (e, stack) {
                            debugPrint('>>> ERRO NA TROCA: $e');
                            debugPrint('>>> Stack: $stack');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erro: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.withOpacity(0.8),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text(
                          'Confirmar Troca',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmarTroca(DataService dataService) async {
    final venda = widget.vendaOriginal;

    // 1. CALCULAR VALORES
    double valorDevolvido = 0;
    for (final item in widget.itensDevolver) {
      valorDevolvido += item.preco * item.quantidade;
    }

    double valorNovos = 0;
    final nomesNovos = <String>[];
    for (final entry in _novosProdutos.entries) {
      final produto = dataService.produtos.firstWhere((p) => p.id == entry.key);
      valorNovos += produto.preco * entry.value;
      nomesNovos.add('${entry.value}x ${produto.nome}');
    }

    // VALIDAÇÃO: não permitir troca por valor maior
    if (valorNovos > valorDevolvido) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Troca inválida'),
          content: const Text(
            'O valor dos itens novos não pode ser maior que o valor dos itens devolvidos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // 2. CALCULAR NOVO VALOR: (original - devolvido) + novos
    final novoValor = (venda.valorTotal - valorDevolvido) + valorNovos;

    // 3. ATUALIZAR ESTOQUE (devolver item trocado)
    debugPrint('');
    debugPrint('╔════════════════════════════════════════════════╗');
    debugPrint('║  ATUALIZANDO ESTOQUE - DEVOLUÇÃO (TROCA)      ║');
    debugPrint('╚════════════════════════════════════════════════╝');
    for (final item in widget.itensDevolver) {
      try {
        // Tentar buscar pelo ID primeiro (mais confiável), depois pelo nome
        Produto? produto;
        try {
          if (item.produtoId != null && item.produtoId!.isNotEmpty) {
            produto = dataService.produtos.firstWhere(
              (p) => p.id == item.produtoId,
            );
          }
        } catch (_) {}
        
        if (produto == null) {
          produto = dataService.produtos.firstWhere(
            (p) => p.nome == item.nome,
          );
        }
        
        final estoqueAnterior = produto.estoque;
        final novoEstoque = produto.estoque + item.quantidade;
        
        dataService.updateProduto(
          produto.copyWith(
            estoque: novoEstoque,
            updatedAt: DateTime.now(),
          ),
        );
        
        debugPrint('>>> ✓ Item devolvido ao estoque:');
        debugPrint('>>>   Produto: ${produto.nome}');
        debugPrint('>>>   Estoque anterior: $estoqueAnterior');
        debugPrint('>>>   Quantidade devolvida: ${item.quantidade}');
        debugPrint('>>>   Novo estoque: $novoEstoque');
      } catch (e) {
        debugPrint('>>> ERRO ao devolver produto ${item.nome} ao estoque: $e');
      }
    }

    // 4. ATUALIZAR ESTOQUE (retirar novo item)
    debugPrint('');
    debugPrint('╔════════════════════════════════════════════════╗');
    debugPrint('║  ATUALIZANDO ESTOQUE - BAIXA (NOVO ITEM)      ║');
    debugPrint('╚════════════════════════════════════════════════╝');
    for (final entry in _novosProdutos.entries) {
      try {
        final produto = dataService.produtos.firstWhere((p) => p.id == entry.key);
        
        // Verificar se há estoque suficiente
        if (produto.estoque < entry.value) {
          debugPrint('>>> ⚠ ATENÇÃO: Estoque insuficiente para ${produto.nome}');
          debugPrint('>>>   Estoque disponível: ${produto.estoque}');
          debugPrint('>>>   Quantidade solicitada: ${entry.value}');
        }
        
        final estoqueAnterior = produto.estoque;
        final novoEstoque = (produto.estoque - entry.value) < 0 ? 0 : (produto.estoque - entry.value);
        
        dataService.updateProduto(
          produto.copyWith(
            estoque: novoEstoque,
            updatedAt: DateTime.now(),
          ),
        );
        
        debugPrint('>>> ✓ Baixa no estoque:');
        debugPrint('>>>   Produto: ${produto.nome}');
        debugPrint('>>>   Estoque anterior: $estoqueAnterior');
        debugPrint('>>>   Quantidade retirada: ${entry.value}');
        debugPrint('>>>   Novo estoque: $novoEstoque');
      } catch (e) {
        debugPrint('>>> ERRO ao dar baixa no produto ${entry.key}: $e');
      }
    }
    debugPrint('');

    // 5. CRIAR ITENS ATUALIZADOS
    final novosItens = <ItemVendaBalcao>[];
    
    // Criar lista de nomes dos produtos novos formatados
    final produtosNovosList = <String>[]; // Lista de nomes formatados (ex: "2x Produto A, 1x Produto B")
    for (final entry in _novosProdutos.entries) {
      try {
        final produto = dataService.produtos.firstWhere((p) => p.id == entry.key);
        if (entry.value > 1) {
          produtosNovosList.add('${entry.value}x ${produto.nome}');
        } else {
          produtosNovosList.add(produto.nome);
        }
        debugPrint('>>> Produto novo: ${entry.value}x ${produto.nome}');
      } catch (e) {
        debugPrint('>>> ERRO ao buscar produto: $e');
        produtosNovosList.add('Produto não encontrado');
      }
    }
    
    // Criar string combinada de todos os produtos novos
    final todosProdutosNovos = produtosNovosList.join(', ');
    debugPrint('>>> Produtos novos combinados: $todosProdutosNovos');
    debugPrint('>>> Total de itens devolvidos: ${widget.itensDevolver.length}');
    
    // Criar mapa: idItemOriginal -> string com todos os produtos novos
    // Se houver múltiplos itens devolvidos, cada um recebe todos os produtos novos
    final mapaTroca = <String, String>{}; 
    
    // Para cada item devolvido, encontrar o item correspondente na venda original
    for (final itemDevolvido in widget.itensDevolver) {
      // Encontrar o item correspondente na venda original
      for (final itemOriginal in venda.itens) {
        final matchPorId = itemOriginal.id == itemDevolvido.id || 
                           itemOriginal.id == itemDevolvido.produtoId;
        final matchPorNomePreco = itemOriginal.nome == itemDevolvido.nome && 
                                   itemOriginal.preco == itemDevolvido.preco;
        
        if (matchPorId || matchPorNomePreco) {
          // Associar este item original a todos os produtos novos
          mapaTroca[itemOriginal.id] = todosProdutosNovos;
          debugPrint('>>> ASSOCIADO: ${itemOriginal.nome} -> $todosProdutosNovos');
          break;
        }
      }
    }

    debugPrint('>>> Total de associações no mapa: ${mapaTroca.length}');

    // Converter itens da vendaOriginal para ItemVendaBalcao
    for (final item in venda.itens) {
      // Verificar se este item foi trocado
      final itemDevolvido = widget.itensDevolver.firstWhere(
        (d) => d.id == item.id || 
               d.produtoId == item.id ||
               (d.nome == item.nome && d.preco == item.preco),
        orElse: () => _ItemVenda(
          id: '',
          nome: '',
          quantidade: 0,
          preco: 0,
        ),
      );
      
      final foiTrocado = itemDevolvido.id.isNotEmpty;

      if (foiTrocado) {
        // IMPORTANTE: Garantir que sempre temos um valor para trocadoPor
        // Primeiro tentar do mapa, depois usar todosProdutosNovos diretamente
        String trocadoPorNome = mapaTroca[item.id] ?? '';
        
        // Se não encontrou no mapa ou está vazio, usar diretamente a lista completa de produtos novos
        if (trocadoPorNome.isEmpty || trocadoPorNome.trim().isEmpty) {
          if (todosProdutosNovos.isNotEmpty && todosProdutosNovos.trim().isNotEmpty) {
            trocadoPorNome = todosProdutosNovos;
            debugPrint('>>> [FALLBACK] Usando todosProdutosNovos diretamente: "$trocadoPorNome"');
          } else {
            // Se ainda estiver vazio, usar um valor padrão
            trocadoPorNome = 'Produto não informado';
            debugPrint('>>> [AVISO] Campo trocadoPor vazio - usando valor padrão');
          }
        }
        
        // Garantir que o valor final não esteja vazio (trim e verificação final)
        String valorFinal = trocadoPorNome.trim();
        if (valorFinal.isEmpty) {
          valorFinal = todosProdutosNovos.isNotEmpty ? todosProdutosNovos : 'Produto não informado';
        }
        
        debugPrint('');
        debugPrint('>>> ============================================');
        debugPrint('>>> ITEM TROCADO: ${item.nome}');
        debugPrint('>>> Quantidade trocada: ${itemDevolvido.quantidade}');
        debugPrint('>>> Trocado por: "$valorFinal"');
        debugPrint('>>> Tamanho da string: ${valorFinal.length}');
        debugPrint('>>> ============================================');
        debugPrint('');
        
        // Criar o item com trocadoPor garantido
        final itemTrocado = ItemVendaBalcao(
          id: item.id,
          nome: item.nome,
          precoUnitario: 0,
          quantidade: item.quantidade,
          isServico: false,
          quantidadeTrocada: itemDevolvido.quantidade,
          trocadoPor: valorFinal, // SEMPRE preenchido
        );
        
        // Verificar se foi criado corretamente
        debugPrint('>>> ✓ ItemVendaBalcao criado:');
        debugPrint('>>>   - Nome: ${itemTrocado.nome}');
        debugPrint('>>>   - quantidadeTrocada: ${itemTrocado.quantidadeTrocada}');
        debugPrint('>>>   - trocadoPor: "${itemTrocado.trocadoPor}"');
        debugPrint('>>>   - trocadoPor != null: ${itemTrocado.trocadoPor != null}');
        debugPrint('>>>   - trocadoPor.isNotEmpty: ${itemTrocado.trocadoPor?.isNotEmpty ?? false}');
        debugPrint('>>>   - trocadoPor.length: ${itemTrocado.trocadoPor?.length ?? 0}');
        
        novosItens.add(itemTrocado);
      } else {
        // Item não trocado: manter igual
        novosItens.add(
          ItemVendaBalcao(
            id: item.id,
            nome: item.nome,
            precoUnitario: item.preco,
            quantidade: item.quantidade,
            isServico: false,
          ),
        );
      }
    }

    // 6. ADICIONAR NOVOS PRODUTOS
    for (final entry in _novosProdutos.entries) {
      final produto = dataService.produtos.firstWhere((p) => p.id == entry.key);
      novosItens.add(
        ItemVendaBalcao(
          id: '${produto.id}_${DateTime.now().millisecondsSinceEpoch}',
          nome: produto.nome,
          precoUnitario: produto.preco,
          quantidade: entry.value,
          isServico: false,
        ),
      );
    }

    // 7. CRIAR/ATUALIZAR VENDA
    final vendaAtualizada = VendaBalcao(
      id: venda.id,
      numero: venda.numero,
      dataVenda: venda.data,
      clienteId: venda.clienteId,
      clienteNome: venda.clienteNome,
      itens: novosItens,
      valorTotal: novoValor,
      tipoPagamento: TipoPagamento.dinheiro,
    );

    // Tentar atualizar na lista de vendasBalcao
    final indexVenda = dataService.vendasBalcao.indexWhere(
      (v) => v.id == venda.id || v.numero == venda.numero,
    );

    if (indexVenda != -1) {
      // Log dos itens com troca antes de atualizar
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════╗');
      debugPrint('║  ATUALIZANDO VENDA COM TROCA                   ║');
      debugPrint('╚════════════════════════════════════════════════╝');
      debugPrint('>>> Venda: ${venda.numero}');
      debugPrint('>>> Total de itens na venda atualizada: ${vendaAtualizada.itens.length}');
      for (final item in vendaAtualizada.itens) {
        if (item.quantidadeTrocada > 0) {
          debugPrint('>>> ✓ Item trocado: ${item.nome}');
          debugPrint('>>>   - quantidadeTrocada: ${item.quantidadeTrocada}');
          debugPrint('>>>   - trocadoPor: "${item.trocadoPor}"');
          debugPrint('>>>   - trocadoPor é null? ${item.trocadoPor == null}');
          debugPrint('>>>   - trocadoPor está vazio? ${item.trocadoPor?.isEmpty ?? true}');
        }
      }
      
      await dataService.updateVendaBalcao(vendaAtualizada);
      
      // FORÇAR atualização dos listeners
      dataService.forceUpdate();
      
      // Aguardar um pouco para garantir que a atualização foi processada
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Log após atualizar
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════╗');
      debugPrint('║  VERIFICANDO VENDA APÓS ATUALIZAÇÃO            ║');
      debugPrint('╚════════════════════════════════════════════════╝');
      final vendaVerificacao = dataService.getVendaPorNumero(venda.numero);
      if (vendaVerificacao != null) {
        debugPrint('>>> ✓ Venda encontrada! Total de itens: ${vendaVerificacao.itens.length}');
        int countTrocados = 0;
        for (final item in vendaVerificacao.itens) {
          if (item.quantidadeTrocada > 0) {
            countTrocados++;
            debugPrint('>>> ✓ Item trocado (verificação): ${item.nome}');
            debugPrint('>>>   - quantidadeTrocada: ${item.quantidadeTrocada}');
            debugPrint('>>>   - trocadoPor: "${item.trocadoPor}"');
            debugPrint('>>>   - trocadoPor não é null? ${item.trocadoPor != null}');
            debugPrint('>>>   - trocadoPor não está vazio? ${item.trocadoPor?.isNotEmpty ?? false}');
          }
        }
        debugPrint('>>> Total de itens trocados encontrados: $countTrocados');
      } else {
        debugPrint('>>> ❌ ERRO: Venda não encontrada após atualização!');
      }
    }

    // Também tentar atualizar no pedido correspondente (se existir)
    final indexPedido = dataService.pedidos.indexWhere(
      (p) => p.numero == venda.numero,
    );

    if (indexPedido != -1) {
      final pedidoOriginal = dataService.pedidos[indexPedido];

      // Atualizar os pagamentos para refletir a troca
      final pagamentosAtualizados = pedidoOriginal.pagamentos.map((pag) {
        if (pag.recebido) {
          // Calcular nova proporção
          final proporcao = venda.valorTotal > 0
              ? novoValor / venda.valorTotal
              : 0.0;
          final novoValorPag = pag.valor * proporcao;
          return PagamentoPedido(
            id: pag.id,
            tipo: pag.tipo,
            valor: novoValorPag,
            recebido: pag.recebido,
            dataVencimento: pag.dataVencimento,
            dataRecebimento: pag.dataRecebimento,
            parcelas: pag.parcelas,
            numeroParcela: pag.numeroParcela,
            parcelamentoId: pag.parcelamentoId,
            observacao: pag.observacao,
            tipoOriginal: pag.tipoOriginal,
          );
        }
        return pag;
      }).toList();

      final pedidoAtualizado = pedidoOriginal.copyWith(
        total: novoValor,
        pagamentos: pagamentosAtualizados,
      );
      dataService.updatePedido(pedidoAtualizado);
    }

    // 8. CRIAR REGISTRO DA TROCA

    // 1 para 1: associar cada item devolvido ao novo
    final itensNovos = <ItemTrocaDevolucao>[];
    final itensDevolvidos = <ItemTrocaDevolucao>[];
    final novosProdutosEntriesList = _novosProdutos.entries.toList();
    for (int i = 0; i < widget.itensDevolver.length; i++) {
      final item = widget.itensDevolver[i];
      final novoProduto = i < novosProdutosEntriesList.length
          ? dataService.produtos.firstWhere(
              (p) => p.id == novosProdutosEntriesList[i].key,
            )
          : null;
      itensDevolvidos.add(
        ItemTrocaDevolucao(
          produtoId: item.produtoId ?? item.id,
          produtoNome: item.nome,
          quantidade: item.quantidade,
          precoUnitario: item.preco,
          valorTotal: item.quantidade * item.preco,
          motivo: widget.motivo.isNotEmpty ? widget.motivo : null,
          trocadoPor: novoProduto?.nome,
        ),
      );
      if (novoProduto != null) {
        itensNovos.add(
          ItemTrocaDevolucao(
            produtoId: novoProduto.id,
            produtoNome: novoProduto.nome,
            quantidade: novosProdutosEntriesList[i].value,
            precoUnitario: novoProduto.preco,
            valorTotal: novoProduto.preco * novosProdutosEntriesList[i].value,
          ),
        );
      }
    }

    final troca = TrocaDevolucao(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      pedidoId: venda.id,
      numeroPedido: venda.numero,
      clienteId: venda.clienteId,
      clienteNome: venda.clienteNome,
      dataOperacao: DateTime.now(),
      tipo: _novosProdutos.isNotEmpty
          ? TipoOperacao.troca
          : TipoOperacao.devolucao,
      itensDevolvidos: itensDevolvidos,
      itensNovos: itensNovos,
      valorDevolvido: widget.valorCredito,
      valorNovosItens: _valorNovos,
      diferenca: _diferenca,
      observacao: widget.motivo.isNotEmpty ? widget.motivo : null,
      status: 'Concluído',
    );

    await dataService.addTrocaDevolucao(troca);

    // Mostrar confirmação
    final isTroca = _novosProdutos.isNotEmpty;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (isTroca ? Colors.orange : Colors.red).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isTroca ? Icons.swap_horiz : Icons.keyboard_return,
                color: isTroca ? Colors.orange : Colors.red,
                size: 60,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isTroca ? 'Troca Realizada!' : 'Devolução Realizada!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isTroca
                  ? '${itensDevolvidos.length} ${itensDevolvidos.length == 1 ? 'item devolvido' : 'itens devolvidos'}\n'
                        '${itensNovos.length} ${itensNovos.length == 1 ? 'novo item' : 'novos itens'}'
                  : '${itensDevolvidos.length} ${itensDevolvidos.length == 1 ? 'item devolvido' : 'itens devolvidos'}',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_diferenca.abs() > 0.01)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: (_diferenca >= 0 ? Colors.red : Colors.green)
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _diferenca >= 0
                      ? 'Cliente deve pagar: ${_formatoMoeda.format(_diferenca)}'
                      : 'Devolver ao cliente: ${_formatoMoeda.format(_diferenca.abs())}',
                  style: TextStyle(
                    color: _diferenca >= 0
                        ? Colors.redAccent
                        : Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // Voltar para o histórico com valor atualizado
                // Remove todas as páginas e vai direto para o histórico (nova instância)
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const HistoricoVendasPage(),
                  ),
                  (route) => route.isFirst, // Mantém apenas a home
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: (isTroca ? Colors.orange : Colors.red)
                    .withOpacity(0.8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Concluir',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============ Classes auxiliares ============

/// Venda unificada (Pedido ou VendaBalcao)
class _VendaUnificada {
  final String id;
  final String numero;
  final DateTime data;
  final String? clienteId;
  final String? clienteNome;
  final double valorTotal;
  final List<_ItemVenda> itens;
  final bool isPedido;

  _VendaUnificada({
    required this.id,
    required this.numero,
    required this.data,
    this.clienteId,
    this.clienteNome,
    required this.valorTotal,
    required this.itens,
    required this.isPedido,
  });

  factory _VendaUnificada.fromPedido(Pedido pedido) {
    return _VendaUnificada(
      id: pedido.id,
      numero: pedido.numero,
      data: pedido.dataPedido,
      clienteId: pedido.clienteId,
      clienteNome: pedido.clienteNome,
      valorTotal: pedido.totalGeral,
      itens: pedido.produtos
          .map(
            (p) => _ItemVenda(
              id: p.id,
              produtoId: p.id, // No ItemPedido, o id É o produtoId
              nome: p.nome,
              quantidade: p.quantidade,
              preco: p.preco,
            ),
          )
          .toList(),
      isPedido: true,
    );
  }

  factory _VendaUnificada.fromVendaBalcao(VendaBalcao venda) {
    return _VendaUnificada(
      id: venda.id,
      numero: venda.numero,
      data: venda.dataVenda,
      clienteId: venda.clienteId,
      clienteNome: venda.clienteNome,
      valorTotal: venda.valorTotal,
      itens: venda.itens
          .where((i) => !i.isServico) // Só produtos, não serviços
          .map(
            (i) => _ItemVenda(
              id: i.id,
              produtoId: i.id, // No ItemVendaBalcao, o id É o produtoId
              nome: i.nome,
              quantidade: i.quantidade,
              preco: i.precoUnitario,
            ),
          )
          .toList(),
      isPedido: false,
    );
  }
}

/// Item de venda
class _ItemVenda {
  final String id;
  final String? produtoId;
  final String nome;
  final int quantidade;
  final double preco;

  _ItemVenda({
    required this.id,
    this.produtoId,
    required this.nome,
    required this.quantidade,
    required this.preco,
  });
}
