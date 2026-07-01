import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/produto_historico.dart';
import '../services/data_service.dart';

/// Página para visualizar o histórico de alterações de produtos
class ProdutoHistoricoPage extends StatefulWidget {
  final String? produtoId; // Se null, mostra histórico geral
  final String? produtoNome;

  const ProdutoHistoricoPage({
    super.key,
    this.produtoId,
    this.produtoNome,
  });

  @override
  State<ProdutoHistoricoPage> createState() => _ProdutoHistoricoPageState();
}

class _ProdutoHistoricoPageState extends State<ProdutoHistoricoPage> {
  List<ProdutoHistorico> _historico = [];
  bool _carregando = true;
  DateTime? _dataInicio;
  DateTime? _dataFim;
  String _filtroAtual = 'TODOS';

  List<ProdutoHistorico> get _historicoFiltrado {
    if (_filtroAtual == 'TODOS') return _historico;
    return _historico.where((item) {
      final isVenda = item.valoresNovos != null && 
          item.valoresNovos!['_motivo'] != null && 
          item.valoresNovos!['_motivo'].toString().startsWith('venda');

      if (_filtroAtual == 'VENDA') {
        return isVenda;
      }
      if (_filtroAtual == 'ESTOQUE') {
        return !isVenda && item.camposAlterados.contains('estoque');
      }
      if (_filtroAtual == 'IMPOSTOS') {
        return item.camposAlterados.any((c) => c.contains('aliquota') || c.contains('cst') || c.contains('ncm') || c.contains('cfop'));
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    // Definir período padrão: últimos 30 dias
    _dataFim = DateTime.now();
    _dataInicio = DateTime.now().subtract(const Duration(days: 30));
    _carregarHistorico();
  }

  Future<void> _carregarHistorico() async {
    setState(() => _carregando = true);
    
    final dataService = Provider.of<DataService>(context, listen: false);
    
    try {
      if (widget.produtoId != null) {
        // Histórico de um produto específico
        _historico = await dataService.buscarHistoricoProduto(
          widget.produtoId!,
          limite: 100,
        );
      } else {
        // Histórico geral da empresa
        _historico = await dataService.buscarHistoricoGeral(
          limite: 100,
          dataInicio: _dataInicio,
          dataFim: _dataFim,
        );
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico: $e');
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  bool _isVenda(ProdutoHistorico item) {
    return item.valoresNovos != null && 
        item.valoresNovos!['_motivo'] != null && 
        item.valoresNovos!['_motivo'].toString().startsWith('venda');
  }

  Color _getCorOperacao(ProdutoHistorico item) {
    if (_isVenda(item)) return Colors.purple;
    switch (item.tipoOperacao) {
      case 'CREATE':
        return Colors.green;
      case 'UPDATE':
        return Colors.blue;
      case 'DELETE':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getIconeOperacao(ProdutoHistorico item) {
    if (_isVenda(item)) return Icons.shopping_cart;
    switch (item.tipoOperacao) {
      case 'CREATE':
        return Icons.add_circle;
      case 'UPDATE':
        return Icons.edit;
      case 'DELETE':
        return Icons.delete;
      default:
        return Icons.help;
    }
  }

  String _getTextoOperacao(ProdutoHistorico item) {
    if (_isVenda(item)) return 'Venda';
    switch (item.tipoOperacao) {
      case 'CREATE':
        return 'Criação';
      case 'UPDATE':
        return 'Atualização';
      case 'DELETE':
        return 'Exclusão';
      default:
        return item.tipoOperacao;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.produtoNome != null 
        ? 'Histórico: ${widget.produtoNome}' 
        : 'Histórico de Produtos';

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarHistorico,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFiltroChip('TODOS', 'Todos'),
                  const SizedBox(width: 8),
                  _buildFiltroChip('VENDA', 'Vendas'),
                  const SizedBox(width: 8),
                  _buildFiltroChip('ESTOQUE', 'Estoque'),
                  const SizedBox(width: 8),
                  _buildFiltroChip('IMPOSTOS', 'Impostos'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _historico.isEmpty
              ? _buildEmptyState()
              : _buildListaHistorico(),
    );
  }

  Widget _buildFiltroChip(String valor, String label) {
    final isSelected = _filtroAtual == valor;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _filtroAtual = valor);
        }
      },
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      checkmarkColor: Theme.of(context).primaryColor,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum histórico encontrado',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'As alterações nos produtos serão registradas aqui',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaHistorico() {
    final lista = _historicoFiltrado;
    if (lista.isEmpty) {
      return const Center(child: Text('Nenhum registro encontrado para este filtro.'));
    }
    return ListView.builder(
      itemCount: lista.length,
      itemBuilder: (context, index) {
        final item = lista[index];
        return _buildItemHistorico(item);
      },
    );
  }

  Widget _buildItemHistorico(ProdutoHistorico item) {
    final dataFormatada = DateFormat('dd/MM/yyyy HH:mm').format(item.dataAlteracao);
    final cor = _getCorOperacao(item);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: cor.withOpacity(0.2),
          child: Icon(
            _getIconeOperacao(item),
            color: cor,
          ),
        ),
        title: Text(
          item.produtoNome,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: cor.withOpacity(0.3)),
                  ),
                  child: Text(
                    _getTextoOperacao(item),
                    style: TextStyle(
                      fontSize: 12,
                      color: cor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dataFormatada,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (item.usuarioNome.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Por: ${item.usuarioNome}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Resumo das mudanças
                if (item.resumoMudancas != null && item.resumoMudancas!.isNotEmpty) ...[
                  const Text(
                    'Resumo das alterações:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                    child: Text(
                      item.resumoMudancas!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const Divider(height: 24),
                ],

                // Campos alterados
                if (item.camposAlterados.isNotEmpty) ...[
                  const Text(
                    'Campos alterados:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.camposAlterados.map((campo) {
                      return Chip(
                        label: Text(campo),
                        backgroundColor: Colors.orange.withOpacity(0.1),
                        side: BorderSide(color: Colors.orange.withOpacity(0.3)),
                        labelStyle: const TextStyle(fontSize: 12),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Detalhes técnicos
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Detalhes técnicos',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  children: [
                    if (item.valoresAnteriores != null) ...[
                      const Text(
                        'Valores anteriores (JSON):',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatJson(item.valoresAnteriores!),
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (item.valoresNovos != null) ...[
                      const Text(
                        'Valores novos (JSON):',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatJson(item.valoresNovos!),
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatJson(Map<String, dynamic> json) {
    return json.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }
}
