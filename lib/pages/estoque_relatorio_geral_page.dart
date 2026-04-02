import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/estoque_historico.dart';
import '../models/produto.dart';
import '../theme.dart';
import '../custom_app_bar.dart';

class EstoqueRelatorioGeralPage extends StatefulWidget {
  const EstoqueRelatorioGeralPage({super.key});

  @override
  State<EstoqueRelatorioGeralPage> createState() => _EstoqueRelatorioGeralPageState();
}

class _EstoqueRelatorioGeralPageState extends State<EstoqueRelatorioGeralPage> {
  DateTime? _dataInicial;
  DateTime? _dataFinal;
  String? _tipoFiltro; // null = todos, 'entrada', 'saida', 'ajuste'
  String? _fornecedorFiltro;
  String _buscaProduto = '';
  final _buscaController = TextEditingController();
  bool _agruparPorFornecedor = false;

  @override
  void initState() {
    super.initState();
    // Iniciar com o mês atual por padrão
    final agora = DateTime.now();
    _dataInicial = DateTime(agora.year, agora.month, 1);
    _dataFinal = DateTime(agora.year, agora.month, agora.day, 23, 59, 59);
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final historico = service.estoqueHistorico;
    final produtos = service.produtos;

    // Extrair fornecedores únicos para o filtro
    final fornecedores = historico
        .map((h) => h.fornecedorNome)
        .where((f) => f != null && f.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    fornecedores.sort();

    // Aplicar filtros
    List<EstoqueHistorico> filtrado = historico.where((h) {
      // 1. Filtro de Data
      if (_dataInicial != null && h.data.isBefore(_dataInicial!)) return false;
      if (_dataFinal != null && h.data.isAfter(_dataFinal!)) return false;

      // 2. Filtro de Tipo
      if (_tipoFiltro != null && h.tipo != _tipoFiltro) return false;

      // 3. Filtro de Fornecedor
      if (_fornecedorFiltro != null && h.fornecedorNome != _fornecedorFiltro) return false;

      // 4. Filtro de Produto (Busca)
      if (_buscaProduto.isNotEmpty) {
        final prod = produtos.firstWhere(
          (p) => p.id == h.produtoId, 
          orElse: () => Produto(
            id: '', 
            nome: 'Produto Excluído', 
            preco: 0, 
            estoque: 0,
            unidade: 'un',
            grupo: 'Geral',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        if (!prod.nome.toLowerCase().contains(_buscaProduto.toLowerCase()) &&
            !(prod.codigo?.toLowerCase().contains(_buscaProduto.toLowerCase()) ?? false)) {
          return false;
        }
      }

      return true;
    }).toList();

    // Ordenar por data decrescente
    filtrado.sort((a, b) => b.data.compareTo(a.data));

    // Totais
    final totalEntradas = filtrado.where((h) => h.tipo == 'entrada').fold<int>(0, (p, e) => p + e.quantidade);
    final totalSaidas = filtrado.where((h) => h.tipo == 'saida').fold<int>(0, (p, e) => p + e.quantidade);

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: const CustomAppBar(title: 'Relatório Geral de Estoque'),
        body: Column(
          children: [
            _buildFiltros(fornecedores),
            _buildResumo(totalEntradas, totalSaidas),
            _buildToolbar(),
            Expanded(
              child: filtrado.isEmpty
                  ? _buildEmptyState()
                  : _agruparPorFornecedor 
                      ? _buildListaAgrupada(filtrado, produtos)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtrado.length,
                          itemBuilder: (context, index) {
                            final h = filtrado[index];
                            final prod = produtos.firstWhere(
                              (p) => p.id == h.produtoId,
                              orElse: () => Produto(
                                id: h.produtoId, 
                                nome: 'Produto não encontrado', 
                                preco: 0, 
                                estoque: 0,
                                unidade: 'un',
                                grupo: 'Geral',
                                createdAt: DateTime.now(),
                                updatedAt: DateTime.now(),
                              ),
                            );
                            return _buildItemRelatorio(h, prod);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltros(List<String> fornecedores) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Busca de Produto
          TextField(
            controller: _buscaController,
            onChanged: (v) => setState(() => _buscaProduto = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar por produto ou código...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.3), size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Intervalo de Datas
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: _selecionarPeriodo,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month, color: Colors.blueAccent.withOpacity(0.7), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _dataInicial == null
                                ? 'Todo o período'
                                : '${DateFormat('dd/MM').format(_dataInicial!)} - ${DateFormat('dd/MM/yy').format(_dataFinal!)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Filtro Tipo
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _tipoFiltro,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      hint: const Text('Tipo', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Todos')),
                        DropdownMenuItem(value: 'entrada', child: Text('Entrada')),
                        DropdownMenuItem(value: 'saida', child: Text('Saída')),
                      ],
                      onChanged: (v) => setState(() => _tipoFiltro = v),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Filtro Fornecedor
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _fornecedorFiltro,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      hint: const Text('Fornecedor', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Todos Forn.')),
                        ...fornecedores.map((f) => DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => setState(() => _fornecedorFiltro = v),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResumo(int entradas, int saidas) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildCardResumo('ENTRADAS', entradas, Colors.greenAccent),
          const SizedBox(width: 12),
          _buildCardResumo('SAÍDAS', saidas, Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildCardResumo(String label, int valor, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: cor.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(
              valor.toString(),
              style: TextStyle(color: cor, fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRelatorio(EstoqueHistorico h, Produto p) {
    final isEntrada = h.tipo == 'entrada';
    final cor = isEntrada ? Colors.greenAccent : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          // Ícone/Indicador
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isEntrada ? Icons.add_business_outlined : Icons.file_upload_outlined,
              color: cor,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          // Info Produto e Fornecedor
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.nome,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon( Icons.business, color: Colors.blueAccent.withOpacity(0.5), size: 12),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        h.fornecedorNome ?? 'Geral',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 2, height: 2, color: Colors.white10,
                    ),
                    Text(
                      DateFormat('dd/MM/yy HH:mm').format(h.data),
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Quantidade
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isEntrada ? "+" : "-"}${h.quantidade}',
                style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                p.unidade.isNotEmpty ? p.unidade : 'un',
                style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text(
            'Nenhuma movimentação encontrada\nno período selecionado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.3)),
          ),
        ],
      ),
    );
  }

  Future<void> _selecionarPeriodo() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: _dataInicial ?? DateTime.now(),
        end: _dataFinal ?? DateTime.now(),
      ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E2E),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0F172A),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dataInicial = picked.start;
        _dataFinal = picked.end.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      });
    }
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          const Spacer(),
          const Text('Agrupar por Fornecedor', style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 8),
          Switch(
            value: _agruparPorFornecedor,
            onChanged: (v) => setState(() => _agruparPorFornecedor = v),
            activeColor: Colors.blueAccent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildListaAgrupada(List<EstoqueHistorico> filtrado, List<Produto> produtos) {
    // Agrupar por fornecedor
    final Map<String, List<EstoqueHistorico>> grupos = {};
    for (var h in filtrado) {
      final nome = h.fornecedorNome ?? 'Geral';
      if (!grupos.containsKey(nome)) grupos[nome] = [];
      grupos[nome]!.add(h);
    }

    final listaGrupos = grupos.entries.toList();
    listaGrupos.sort((a, b) => a.key.compareTo(b.key));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: listaGrupos.length,
      itemBuilder: (context, index) {
        final grupo = listaGrupos[index];
        final ent = grupo.value.where((h) => h.tipo == 'entrada').fold<int>(0, (p, e) => p + e.quantidade);
        final sai = grupo.value.where((h) => h.tipo == 'saida').fold<int>(0, (p, e) => p + e.quantidade);

        return Theme(
          data: ThemeData.dark().copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.business, color: Colors.blueAccent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(grupo.key, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('${grupo.value.length} operações no período', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('+$ent / -$sai', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            children: grupo.value.map((h) {
              final prod = produtos.firstWhere(
                (p) => p.id == h.produtoId,
                orElse: () => Produto(
                  id: h.produtoId, 
                  nome: 'Produto não encontrado', 
                  preco: 0, 
                  estoque: 0,
                  unidade: 'un',
                  grupo: 'Geral',
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              );
              return _buildItemRelatorio(h, prod);
            }).toList(),
          ),
        );
      },
    );
  }
}
