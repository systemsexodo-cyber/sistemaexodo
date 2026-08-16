import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/models/mesa_comanda.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/adicional_produto.dart';
import 'package:sistema_exodo_novo/models/conta_pagar.dart';
import 'package:sistema_exodo_novo/pages/historico_operacoes_page.dart';
import 'package:sistema_exodo_novo/services/mesa_comanda_pdf_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';

const uuid = Uuid();

/// Página simplificada de cozinha/bar e mesas para funcionários
class CozinhaMesasFuncionarioPage extends StatefulWidget {
  final int abaInicial; // 0 para Mesas, 1 para Comandas
  const CozinhaMesasFuncionarioPage({super.key, this.abaInicial = 0});

  @override
  State<CozinhaMesasFuncionarioPage> createState() => _CozinhaMesasFuncionarioPageState();
}

class _CozinhaMesasFuncionarioPageState extends State<CozinhaMesasFuncionarioPage> {
  MesaComanda? _mesaSelecionada;
  late TipoControle _tipoSelecionado;
  final _buscaController = TextEditingController();
  final Set<String> _comandasExpandidas = {}; // Necessário para partes não refatoradas
  String? _hoveredId; // Para efeitos visuais de hover
  bool _atrelarComandaAMesa = false;

  @override
  void initState() {
    super.initState();
    _tipoSelecionado = widget.abaInicial == 1 ? TipoControle.comanda : TipoControle.mesa;
    _carregarConfigAtrelar();
  }

  Future<void> _carregarConfigAtrelar() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _atrelarComandaAMesa = prefs.getBool('atrelar_comanda_mesa') ?? false;
    });
  }

  Future<void> _salvarConfigAtrelar(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('atrelar_comanda_mesa', valor);
    setState(() {
      _atrelarComandaAMesa = valor;
    });
  }

  void _mostrarConfiguracoes(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('Configurações de Controle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Atrelar Comandas às Mesas', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text('Exige vincular a comanda a uma mesa física ao abrir', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  activeColor: Colors.orange,
                  value: _atrelarComandaAMesa,
                  onChanged: (value) async {
                    await _salvarConfigAtrelar(value);
                    setDialogState(() {});
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('FECHAR', style: TextStyle(color: Colors.grey)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true);
    
    return DefaultTabController(
      length: 2,
      initialIndex: widget.abaInicial,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text(
            'Mesas/Comandas',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          leading: _mesaSelecionada != null 
            ? IconButton(
                icon: const Icon(Icons.arrow_back), 
                onPressed: () => setState(() => _mesaSelecionada = null)
              ) 
            : null,
          backgroundColor: const Color(0xFF1E1E2E),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Configurações',
              onPressed: () => _mostrarConfiguracoes(context),
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Histórico de Operações',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoricoOperacoesPage(),
                  ),
                );
              },
            ),
          ],
          bottom: _mesaSelecionada == null ? TabBar(
            onTap: (index) {
              setState(() {
                _tipoSelecionado = index == 0 ? TipoControle.mesa : TipoControle.comanda;
              });
            },
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(icon: Icon(Icons.table_restaurant), text: 'MESAS'),
              Tab(icon: Icon(Icons.receipt_long), text: 'COMANDAS'),
            ],
          ) : null,
        ),
        body: SafeArea(
          child: _mesaSelecionada != null 
            ? _buildDetalhesMesaComanda(_mesaSelecionada!, dataService)
            : _buildListaMesasQuadros(dataService),
        ),
        floatingActionButton: _mesaSelecionada == null ? FloatingActionButton.extended(
          onPressed: () => _tipoSelecionado == TipoControle.mesa 
            ? _abrirNovaMesa(context, dataService) 
            : _abrirNovaComanda(context, dataService),
          icon: const Icon(Icons.add),
          label: Text(_tipoSelecionado == TipoControle.mesa ? 'Nova Mesa' : 'Nova Comanda'),
          backgroundColor: _tipoSelecionado == TipoControle.mesa ? Colors.orange : Colors.purple,
        ) : null,
      ),
    );
  }


  Widget _buildListaMesasQuadros(DataService dataService) {
    final screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = screenWidth > 1200 ? 6 : (screenWidth > 800 ? 5 : 3);
    final double childAspectRatio = screenWidth > 800 ? 1.4 : 1.25;

    // Buscar mesas/comandas abertas filtradas por tipo
    final todosItens = dataService.mesasComandas
        .where((m) => m.status == 'Aberta' && m.tipo == _tipoSelecionado)
        .where((m) => _tipoSelecionado == TipoControle.mesa || m.mesaId == null) // Apenas comandas independentes na aba de comandas
        .toList();
    
    // Filtrar por busca
    final termoBusca = _buscaController.text.toLowerCase().trim();
    List<MesaComanda> filtrados = todosItens;
    
    if (termoBusca.isNotEmpty) {
      filtrados = todosItens.where((m) {
        return m.numero.toLowerCase().contains(termoBusca) ||
               (m.clienteNome != null && m.clienteNome!.toLowerCase().contains(termoBusca));
      }).toList();
    }
    
    // Ordenar mesas e comandas por número
    filtrados.sort((a, b) {
      final numA = _extrairNumero(a.numero) ?? 999999;
      final numB = _extrairNumero(b.numero) ?? 999999;
      return numA.compareTo(numB);
    });

    return Column(
      children: [
        // Campo de busca inteligente
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _buscaController,
            onChanged: (value) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar ${_tipoSelecionado == TipoControle.mesa ? "mesa" : "comanda"}...',
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.search, color: _tipoSelecionado == TipoControle.mesa ? Colors.orange : Colors.purple),
              suffixIcon: _buscaController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        setState(() => _buscaController.clear());
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF1E1E2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        
        Expanded(
          child: filtrados.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _tipoSelecionado == TipoControle.mesa ? Icons.table_restaurant : Icons.receipt_long, 
                        size: 80, 
                        color: Colors.grey.withOpacity(0.3)
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhuma ${_tipoSelecionado == TipoControle.mesa ? "mesa" : "comanda"} aberta',
                        style: const TextStyle(color: Colors.grey, fontSize: 18),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: childAspectRatio,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) {
                    final item = filtrados[index];
                    return _buildQuadroMesaComanda(item, dataService);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildQuadroMesaComanda(MesaComanda item, DataService dataService) {
    final temPendentes = item.temItensPendentes;
    final temProntos = item.temItensProntos;
    final total = item.totalCalculado;
    
    Color accentColor = _tipoSelecionado == TipoControle.mesa ? Colors.orange : Colors.purpleAccent;
    if (temPendentes) accentColor = Colors.redAccent;
    else if (temProntos) accentColor = Colors.greenAccent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredId = item.id),
      onExit: (_) => setState(() => _hoveredId = null),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hoveredId == item.id ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Card(
          elevation: _hoveredId == item.id ? 12 : 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: _hoveredId == item.id ? accentColor : Colors.transparent,
              width: 2,
            ),
          ),
          color: const Color(0xFF1E1E2E),
          shadowColor: accentColor.withOpacity(0.5),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _mesaSelecionada = item),
            hoverColor: accentColor.withOpacity(0.05),
            splashColor: accentColor.withOpacity(0.1),
            child: Stack(
              children: [
                Positioned(
                  left: 0, top: 0, bottom: 0, width: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: accentColor,
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _tipoSelecionado == TipoControle.mesa ? 'Mesa' : 'Comanda',
                              style: TextStyle(
                                color: accentColor, 
                                fontSize: 10, 
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              if (temPendentes)
                                const Icon(Icons.flash_on, color: Colors.redAccent, size: 16),
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: () => _deletarMesaComanda(context, item, dataService),
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 15),
                                tooltip: 'Deletar',
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.numero,
                        style: const TextStyle(
                          color: Colors.white, 
                          fontSize: 22, 
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      if (item.clienteNome != null)
                        Text(
                          item.clienteNome!,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7), 
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.layers_outlined, color: Colors.grey[500], size: 12),
                              const SizedBox(width: 4),
                              Text(
                                '${item.itens.length} it.', 
                                style: TextStyle(color: Colors.grey[500], fontSize: 11),
                              ),
                            ],
                          ),
                          Text(
                            NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(total),
                            style: TextStyle(
                              color: accentColor, 
                              fontWeight: FontWeight.w800, 
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (temProntos)
                  Positioned(
                    right: 8, top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent, 
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.check, color: Colors.black, size: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetalhesMesaComanda(MesaComanda mesa, DataService dataService) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    
    // Buscar comandas vinculadas
    final comandasDaMesa = dataService.mesasComandas
        .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesa.id)
        .toList();
    
    double totalGeral = mesa.totalCalculado;
    for (final c in comandasDaMesa) totalGeral += c.totalCalculado;
    
    double totalPagoGeral = mesa.totalPago;
    for (final c in comandasDaMesa) totalPagoGeral += c.totalPago;
    
    final totalPendente = totalGeral - totalPagoGeral;
    final isComandaIndependente = mesa.tipo == TipoControle.comanda;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Detalhes
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isComandaIndependente ? Icons.receipt_long : Icons.table_restaurant,
                    color: Colors.orange, size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${isComandaIndependente ? "Comanda" : "Mesa"} ${mesa.numero}',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      if (mesa.clienteNome != null)
                        Text('Cliente: ${mesa.clienteNome}', style: const TextStyle(color: Colors.grey)),
                      Text('Abertura: ${formatoData.format(mesa.dataAbertura)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatoMoeda.format(totalGeral), style: const TextStyle(color: Colors.green, fontSize: 20, fontWeight: FontWeight.bold)),
                    if (totalPendente > 0.01)
                      Text('Pendente: ${formatoMoeda.format(totalPendente)}', style: const TextStyle(color: Colors.orange, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Ações Principais
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _adicionarItensMesa(mesa, dataService),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Lançar Itens'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => isComandaIndependente ? _receberComanda(mesa, dataService) : _receberMesa(mesa, dataService),
                  icon: const Icon(Icons.payment),
                  label: const Text('Receber'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => isComandaIndependente 
                        ? _trocarComanda(mesa, dataService) 
                        : _trocarMesa(mesa, dataService),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Trocar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isComandaIndependente ? Colors.purpleAccent : Colors.blue,
                      side: BorderSide(color: isComandaIndependente ? Colors.purpleAccent : Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _transferirItensMesa(mesa, dataService),
                    icon: const Icon(Icons.move_to_inbox),
                    label: const Text('Transf. Itens'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepOrange,
                      side: const BorderSide(color: Colors.deepOrange),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => isComandaIndependente 
                        ? _unirComandas(mesa, dataService) 
                        : _unirMesas(mesa, dataService),
                    icon: const Icon(Icons.merge),
                    label: const Text('Unir'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isComandaIndependente ? Colors.deepPurpleAccent : Colors.teal,
                      side: BorderSide(color: isComandaIndependente ? Colors.deepPurpleAccent : Colors.teal),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _deletarMesaComanda(context, mesa, dataService),
              icon: const Icon(Icons.delete_forever),
              label: const Text('Deletar (registra no histórico)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ),
          
          const Divider(height: 32, color: Colors.white24),
          
          // Lista de Itens
          const Text('ITENS LANÇADOS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),
          
          // Couvert se houver
          if (mesa.valorCouvertCalculado > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.music_note, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Couvert Artístico (${mesa.quantidadePessoasCouvert} pessoas)',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  Text(formatoMoeda.format(mesa.valorCouvertCalculado), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.edit, color: Colors.orange, size: 18), onPressed: () => _editarCouvert(context, mesa, dataService)),
                ],
              ),
            ),
          
          ...mesa.itens.map((item) => Column(
            children: [
              _buildItemMesa(item),
              if (item.status != StatusItem.cancelado)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _cancelarItem(item, mesa, dataService),
                    icon: const Icon(Icons.cancel, size: 14, color: Colors.red),
                    label: const Text('Cancelar', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ),
            ],
          )),
          
          if (!isComandaIndependente && comandasDaMesa.isNotEmpty) ...[
            const Divider(height: 32, color: Colors.white24),
            const Text('COMANDAS VINCULADAS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 12),
            ..._buildComandasDaMesa(mesa, dataService),
          ],
          
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _visualizarConta(mesa, dataService),
                  icon: const Icon(Icons.visibility),
                  label: const Text('Ver Conta'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _imprimirFechamentoConta(mesa, dataService),
                  icon: const Icon(Icons.print),
                  label: const Text('Imprimir'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Deleta uma mesa/comanda mantendo o registro no Histórico de Operações
  /// (auditoria: quem deletou e quando). Não gera venda, apenas registra.
  Future<void> _deletarMesaComanda(
    BuildContext context,
    MesaComanda mesa,
    DataService dataService,
  ) async {
    final isComanda = mesa.tipo == TipoControle.comanda;
    final label = isComanda ? 'comanda' : 'mesa';
    final temItensNaoFinalizados =
        mesa.temItensPendentes || mesa.temItensEmPreparo;
    final total = mesa.totalCalculado;
    final comandasVinculadas = isComanda
        ? 0
        : dataService.mesasComandas
            .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesa.id)
            .length;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Deletar ${isComanda ? "Comanda" : "Mesa"}?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Você está prestes a deletar a $label ${mesa.numero}.',
                style: const TextStyle(color: Colors.white70),
              ),
              if (mesa.clienteNome != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Cliente: ${mesa.clienteNome}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Itens: ${mesa.itens.length} • Total: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(total)}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.history, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'O registro ficará salvo no Histórico de Operações com quem deletou e quando. Esta $label não poderá mais ser usada ou restaurada.',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              if (comandasVinculadas > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple.withOpacity(0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.receipt_long, color: Colors.purple, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Esta mesa tem $comandasVinculadas comanda(s) vinculada(s), que também serão deletadas e registradas no histórico.',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (temItensNaoFinalizados) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Atenção: ainda há itens pendentes ou em preparo. Eles não serão cobrados nem gerarão venda.',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
            child: const Text('Sim, Deletar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await dataService.marcarMesaComandaDeletada(
        mesa.id,
        usuario: authService.usuarioAtual?.nome,
      );

      if (context.mounted) {
        setState(() {
          if (_mesaSelecionada?.id == mesa.id) _mesaSelecionada = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${isComanda ? "Comanda" : "Mesa"} ${mesa.numero} deletada. Registro salvo no Histórico de Operações.',
            ),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao deletar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildListaMesas(DataService dataService) {
    return _buildListaMesasQuadros(dataService);
  }

  /// Extrai número de uma string para ordenação numérica
  int? _extrairNumero(String texto) {
    final match = RegExp(r'\d+').firstMatch(texto);
    return match != null ? int.tryParse(match.group(0) ?? '') : null;
  }

  /// Calcula o total bruto da mesa somando suas comandas vinculadas (valor total sem descontar o que já foi pago)
  double _getTotalMesaComComandas(MesaComanda mesa, DataService dataService) {
    if (mesa.tipo == TipoControle.comanda) return mesa.totalCalculado;
    
    final comandasDaMesa = dataService.mesasComandas
        .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesa.id)
        .toList();
    
    double totalGeral = mesa.totalCalculado;
    for (final c in comandasDaMesa) totalGeral += c.totalCalculado;
    return totalGeral;
  }

  /// Calcula o saldo pendente (o que ainda não foi pago) para a mesa e comandas vinculadas
  double _getSaldoPendenteMesaComComandas(MesaComanda mesa, DataService dataService) {
    double totalDevido = _getTotalMesaComComandas(mesa, dataService);
    
    double totalJaPago = mesa.totalPago;
    final comandasDaMesa = dataService.mesasComandas
        .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesa.id)
        .toList();
    for (final c in comandasDaMesa) totalJaPago += c.totalPago;
    
    return totalDevido - totalJaPago;
  }

  Widget _buildCardMesa(MesaComanda mesa, DataService dataService) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    
    // Buscar comandas vinculadas para calcular totais
    final comandasDaMesa = dataService.mesasComandas
        .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesa.id)
        .toList();
    
    // Calcular total geral (mesa + comandas)
    double totalGeralMesa = mesa.totalCalculado;
    double totalGeralComandas = 0.0;
    for (final comanda in comandasDaMesa) {
      totalGeralComandas += comanda.totalCalculado;
    }
    final totalGeral = totalGeralMesa + totalGeralComandas;
    
    // Calcular total pago (mesa + comandas)
    double totalPagoMesa = mesa.totalPago;
    double totalPagoComandas = 0.0;
    for (final comanda in comandasDaMesa) {
      totalPagoComandas += comanda.totalPago;
    }
    final totalPagoGeral = totalPagoMesa + totalPagoComandas;
    
    // Calcular total pendente
    final totalPendente = totalGeral - totalPagoGeral;
    
    // Verificar se a mesa está disponível (totalmente paga e sem itens)
    final estaDisponivel = totalPendente <= 0.01 && mesa.itens.isEmpty && totalGeral <= 0.01;
    
    final itensPendentes = mesa.itensPendentes.length;
    final itensEmPreparo = mesa.itensEmPreparo.length;
    final itensProntos = mesa.itensProntos.length;
    
    // Verificar se a mesa está selecionada
    final estaSelecionada = _mesaSelecionada?.id == mesa.id;
    
    // Determinar cor de fundo e borda baseado no estado
    Color corFundo;
    Color corBorda;
    double larguraBorda;
    
    if (estaSelecionada) {
      corFundo = Colors.orange.withOpacity(0.15);
      corBorda = Colors.orange;
      larguraBorda = 3;
    } else if (estaDisponivel) {
      corFundo = Colors.green.withOpacity(0.15);
      corBorda = Colors.green;
      larguraBorda = 2;
    } else {
      corFundo = const Color(0xFF1E1E2E);
      corBorda = Colors.transparent;
      larguraBorda = 0;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: corFundo,
      elevation: estaSelecionada ? 8 : (estaDisponivel ? 4 : 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: corBorda,
          width: larguraBorda,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _mesaSelecionada = _mesaSelecionada == mesa ? null : mesa;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: estaDisponivel
                          ? Colors.green.withOpacity(0.3)
                          : (estaSelecionada
                              ? Colors.orange.withOpacity(0.4)
                              : Colors.orange.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(12),
                      border: estaDisponivel
                          ? Border.all(color: Colors.green, width: 2)
                          : (estaSelecionada
                              ? Border.all(color: Colors.orange, width: 2)
                              : null),
                    ),
                    child: Icon(
                      estaDisponivel ? Icons.check_circle : Icons.table_restaurant,
                      color: estaDisponivel
                          ? Colors.green.shade700
                          : (estaSelecionada ? Colors.orange.shade700 : Colors.orange),
                      size: 28,
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
                          'Mesa ${mesa.numero}',
                              style: TextStyle(
                                color: estaDisponivel
                                    ? Colors.green
                                    : (estaSelecionada ? Colors.orange : Colors.white),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                            ),
                            // Verificar se há registro de união de mesas (apenas se não estiver disponível)
                            if (!estaDisponivel && mesa.observacao != null && 
                                (mesa.observacao!.contains('UNIÃO DE MESAS') || 
                                 mesa.observacao!.contains('MESA UNIDA'))) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                message: _extrairMesasUnidas(mesa.observacao!),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.teal, width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.merge,
                                        color: Colors.teal,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'UNIDA',
                                        style: TextStyle(
                                          color: Colors.teal,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (estaDisponivel) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green),
                                ),
                                child: const Text(
                                  'DISPONÍVEL',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ] else if (estaSelecionada) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.check_circle,
                                color: Colors.orange,
                                size: 20,
                              ),
                            ],
                          ],
                        ),
                        if (mesa.clienteNome != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Cliente: ${mesa.clienteNome}',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                        Text(
                          'Aberta: ${formatoData.format(mesa.dataAbertura)}',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatoMoeda.format(totalGeral),
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${mesa.itens.length} item(s)',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      if (totalPagoGeral > 0 || totalPendente > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Pago: ${formatoMoeda.format(totalPagoGeral)}',
                          style: const TextStyle(color: Colors.green, fontSize: 12),
                        ),
                        Text(
                          'Pendente: ${formatoMoeda.format(totalPendente)}',
                          style: TextStyle(
                            color: totalPendente > 0 ? Colors.orange : Colors.green,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (itensPendentes > 0 || itensEmPreparo > 0 || itensProntos > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (itensPendentes > 0)
                      _buildStatusBadge('Pendentes', itensPendentes, Colors.red),
                    if (itensEmPreparo > 0) ...[
                      const SizedBox(width: 8),
                      _buildStatusBadge('Em Preparo', itensEmPreparo, Colors.orange),
                    ],
                    if (itensProntos > 0) ...[
                      const SizedBox(width: 8),
                      _buildStatusBadge('Prontos', itensProntos, Colors.green),
                    ],
                  ],
                ),
              ],
              if (_mesaSelecionada == mesa) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                // Card de Couvert
                if (mesa.quantidadePessoasCouvert != null && mesa.valorCouvertPorPessoa != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note, color: Colors.orange, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Couvert Artístico',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${mesa.quantidadePessoasCouvert} pessoa(s) × ${formatoMoeda.format(mesa.valorCouvertPorPessoa!)} = ${formatoMoeda.format(mesa.valorCouvertCalculado)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.orange),
                          onPressed: () => _adicionarPessoasCouvert(context, mesa, dataService),
                          tooltip: 'Adicionar Pessoas',
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.orange),
                          onPressed: () => _editarCouvert(context, mesa, dataService),
                          tooltip: 'Editar Couvert',
                        ),
                      ],
                    ),
                  ),
                ...mesa.itens.map((item) => Column(
                  children: [
                    _buildItemMesa(item),
                    // Botão para cancelar item (se não estiver cancelado)
                    if (item.status != StatusItem.cancelado)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => _cancelarItem(item, mesa, dataService),
                          icon: const Icon(Icons.cancel, size: 16),
                          label: const Text('Cancelar Item'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            minimumSize: const Size(double.infinity, 36),
                          ),
                        ),
                      ),
                  ],
                )),
                const SizedBox(height: 16),
                // Botão para adicionar itens
                ElevatedButton.icon(
                  onPressed: () => _adicionarItensMesa(mesa, dataService),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Adicionar Itens'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 12),
                // Botão para criar comanda dentro da mesa
                OutlinedButton.icon(
                  onPressed: () => _criarComandaNaMesa(mesa, dataService),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Nova Comanda'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.purple,
                    side: const BorderSide(color: Colors.purple),
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
                const SizedBox(height: 12),
                // Botões de transferência e união
                 Row(
                   children: [
                     Expanded(
                       child: OutlinedButton.icon(
                         onPressed: () => _trocarMesa(mesa, dataService),
                         icon: const Icon(Icons.swap_horiz),
                         label: const Text('Trocar'),
                         style: OutlinedButton.styleFrom(
                           foregroundColor: Colors.blue,
                           side: const BorderSide(color: Colors.blue),
                           minimumSize: const Size(double.infinity, 40),
                         ),
                       ),
                     ),
                     const SizedBox(width: 6),
                     Expanded(
                       child: OutlinedButton.icon(
                         onPressed: () => _transferirItensMesa(mesa, dataService),
                         icon: const Icon(Icons.move_to_inbox),
                         label: const Text('Transf. Itens'),
                         style: OutlinedButton.styleFrom(
                           foregroundColor: Colors.deepOrange,
                           side: const BorderSide(color: Colors.deepOrange),
                           minimumSize: const Size(double.infinity, 40),
                         ),
                       ),
                     ),
                     const SizedBox(width: 6),
                     Expanded(
                       child: OutlinedButton.icon(
                         onPressed: () => _unirMesas(mesa, dataService),
                         icon: const Icon(Icons.merge),
                         label: const Text('Unir'),
                         style: OutlinedButton.styleFrom(
                           foregroundColor: Colors.teal,
                           side: const BorderSide(color: Colors.teal),
                           minimumSize: const Size(double.infinity, 40),
                         ),
                       ),
                     ),
                   ],
                 ),
                const SizedBox(height: 12),
                // Mostrar comandas vinculadas a esta mesa
                ..._buildComandasDaMesa(mesa, dataService),
                const SizedBox(height: 12),
                // Botão para ver histórico completo de operações
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HistoricoOperacoesPage(mesaComanda: mesa),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('Histórico Completo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _visualizarConta(mesa, dataService),
                        icon: const Icon(Icons.visibility),
                        label: const Text('Visualizar Conta'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _imprimirFechamentoConta(mesa, dataService),
                        icon: const Icon(Icons.print),
                        label: const Text('Imprimir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _receberMesa(mesa, dataService),
                        icon: const Icon(Icons.payment),
                        label: const Text('Receber'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String label, int quantidade, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$quantidade',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemMesa(ItemMesaComanda item) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final subtotal = item.subtotal;
    
    Color corStatus;
    String textoStatus;
    
    switch (item.status) {
      case StatusItem.pendente:
        corStatus = Colors.red;
        textoStatus = 'Pendente';
        break;
      case StatusItem.emPreparo:
        corStatus = Colors.orange;
        textoStatus = 'Em Preparo';
        break;
      case StatusItem.pronto:
        corStatus = Colors.green;
        textoStatus = 'Pronto';
        break;
      case StatusItem.entregue:
        corStatus = Colors.blue;
        textoStatus = 'Entregue';
        break;
      case StatusItem.cancelado:
        corStatus = Colors.red.shade700;
        textoStatus = 'CANCELADO';
        break;
    }

    final isCancelado = item.status == StatusItem.cancelado;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCancelado ? Colors.red.shade900.withOpacity(0.3) : Colors.black26,
        borderRadius: BorderRadius.circular(8),
        border: isCancelado ? Border.all(color: Colors.red.shade700, width: 2) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nome,
                  style: TextStyle(
                    color: isCancelado ? Colors.red.shade300 : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: isCancelado ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (item.adicionais.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  ...item.adicionais.map((adicional) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '+ ${adicional.nome} (${formatoMoeda.format(adicional.preco)})',
                      style: TextStyle(color: Colors.greenAccent.withOpacity(0.7), fontSize: 11),
                    ),
                  )),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${item.quantidade}x ${formatoMoeda.format(item.precoUnitarioComAdicionais)}',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: corStatus.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        textoStatus,
                        style: TextStyle(
                          color: corStatus,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            formatoMoeda.format(subtotal),
            style: TextStyle(
              color: isCancelado ? Colors.red.shade300 : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              decoration: isCancelado ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelarItem(ItemMesaComanda item, MesaComanda mesa, DataService dataService) async {
    // Confirmar cancelamento
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Cancelar Item',
          style: TextStyle(color: Colors.red),
        ),
        content: Text(
          'Deseja realmente cancelar o item "${item.nome}"?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final usuarioLogado = authService.usuarioAtual?.nome ?? 'Sistema';
      
      await dataService.atualizarStatusItemMesaComanda(
        mesa.id,
        item.id,
        StatusItem.cancelado,
        usuarioModificou: usuarioLogado,
        acaoRealizada: 'Item cancelado',
      );
      
      // Atualizar a mesa selecionada com os dados atualizados
      final mesaAtualizada = dataService.mesasComandas.firstWhere(
        (m) => m.id == mesa.id,
        orElse: () => mesa,
      );
      
      // Verificar se todos os itens da mesa foram cancelados
      final todosItensCancelados = mesaAtualizada.itens.every(
        (i) => i.status == StatusItem.cancelado,
      );
      
      // Se for uma mesa, verificar também as comandas vinculadas
      bool todasComandasCanceladas = true;
      if (mesaAtualizada.tipo == TipoControle.mesa) {
        final comandasVinculadas = dataService.mesasComandas
            .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesaAtualizada.id)
            .toList();
        
        if (comandasVinculadas.isNotEmpty) {
          // Verificar se todas as comandas têm todos os itens cancelados
          todasComandasCanceladas = comandasVinculadas.every((comanda) {
            return comanda.itens.isEmpty || comanda.itens.every(
              (i) => i.status == StatusItem.cancelado,
            );
          });
        }
      }
      
      // Se todos os itens foram cancelados (mesa e comandas), limpar e liberar mesa
      if (todosItensCancelados && todasComandasCanceladas && mesaAtualizada.tipo == TipoControle.mesa) {
        // Buscar comandas vinculadas para fechar também
        final comandasVinculadas = dataService.mesasComandas
            .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesaAtualizada.id)
            .toList();
        
        // Fechar e limpar comandas vinculadas (preservar histórico)
        for (final comanda in comandasVinculadas) {
          final comandaFechada = comanda.copyWith(
            itens: [],
            itensPagos: [],
            status: 'Fechada',
            dataFechamento: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await dataService.updateMesaComanda(comandaFechada);
        }
        
        // Limpar e liberar mesa (preservar histórico)
        final mesaLiberada = mesaAtualizada.copyWith(
          itens: [],
          itensPagos: [],
          historicoPagamentos: [], // Limpar para nova sessão
          status: 'Aberta',
          dataFechamento: null,
          dataAbertura: DateTime.now(),
          clienteNome: null,
          clienteId: null,
          observacao: null,
          total: 0.0,
          valorCouvert: null,
          quantidadePessoasCouvert: null,
          valorCouvertPorPessoa: null,
          valorGarcom: null,
          garcomRetirado: false,
          updatedAt: DateTime.now(),
        );
        
        await dataService.updateMesaComanda(mesaLiberada);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Todos os itens foram cancelados. Mesa ${mesaAtualizada.numero} liberada e disponível para novo uso.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          setState(() {
            _mesaSelecionada = null; // Limpar seleção
          });
        }
      } else if (todosItensCancelados && mesaAtualizada.tipo == TipoControle.comanda) {
        // Se for uma comanda independente e todos os itens foram cancelados, fechar
        final comandaFechada = mesaAtualizada.copyWith(
          itens: [],
          itensPagos: [],
          historicoPagamentos: [],
          status: 'Fechada',
          dataFechamento: DateTime.now(),
          clienteNome: null,
          clienteId: null,
          observacao: null,
          valorCouvert: null,
          quantidadePessoasCouvert: null,
          valorGarcom: null,
          updatedAt: DateTime.now(),
        );
        
        await dataService.updateMesaComanda(comandaFechada);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Todos os itens foram cancelados. Comanda ${mesaAtualizada.numero} fechada.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
          setState(() {
            _mesaSelecionada = null; // Limpar seleção
          });
        }
      } else {
        // Apenas atualizar a seleção
        setState(() {
          _mesaSelecionada = mesaAtualizada;
        });
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Item "${item.nome}" cancelado. Total atualizado.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cancelar item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _imprimirMesa(MesaComanda mesa, DataService dataService) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      
      if (empresa == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Empresa não encontrada'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final pdfBytes = await _gerarPDFMesa(mesa, empresa);
      
      if (context.mounted) {
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao imprimir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Uint8List> _gerarPDFMesa(MesaComanda mesa, Empresa empresa) async {
    final pdf = pw.Document();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      empresa.nomeExibicao,
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (empresa.cnpj != null && empresa.cnpj!.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'CNPJ: ${empresa.cnpj}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 20),
              
              // Dados da Mesa
              pw.Text(
                'MESA ${mesa.numero}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Abertura: ${formatoData.format(mesa.dataAbertura)}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    'Status: ${mesa.status}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
              if (mesa.clienteNome != null) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  'Cliente: ${mesa.clienteNome}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
              pw.SizedBox(height: 20),
              
              // Itens
              pw.Text(
                'ITENS',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Qtd', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Unit.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Subtotal', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                    ],
                  ),
                  ...mesa.itens.map((item) {
                    final subtotal = item.preco * item.quantidade;
                    String statusTexto;
                    switch (item.status) {
                      case StatusItem.pendente:
                        statusTexto = 'Pendente';
                        break;
                      case StatusItem.emPreparo:
                        statusTexto = 'Em Preparo';
                        break;
                      case StatusItem.pronto:
                        statusTexto = 'Pronto';
                        break;
                      case StatusItem.entregue:
                        statusTexto = 'Entregue';
                        break;
                      case StatusItem.cancelado:
                        statusTexto = 'CANCELADO';
                        break;
                    }
                    
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(item.nome, style: const pw.TextStyle(fontSize: 9)),
                              if (item.observacao != null && item.observacao!.isNotEmpty)
                                pw.Text(
                                  'Obs: ${item.observacao}',
                                  style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                                ),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${item.quantidade}', style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(formatoMoeda.format(item.preco), style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(formatoMoeda.format(subtotal), style: const pw.TextStyle(fontSize: 9)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(statusTexto, style: const pw.TextStyle(fontSize: 9)),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 20),
              
              // Totais
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 2),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'TOTAL DE ITENS:',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          '${mesa.itens.length}',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Divider(),
                    pw.SizedBox(height: 8),
                    // Subtotal dos itens
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Subtotal Itens:',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          formatoMoeda.format(mesa.itens
                              .where((item) => item.status != StatusItem.cancelado)
                              .fold(0.0, (sum, item) => sum + (item.preco * item.quantidade))),
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                    // Couvert
                    if (mesa.valorCouvertCalculado > 0) ...[
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Couvert Artístico:',
                            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            formatoMoeda.format(mesa.valorCouvertCalculado),
                            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                      if (mesa.quantidadePessoasCouvert != null && mesa.valorCouvertPorPessoa != null) ...[
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 8),
                          child: pw.Text(
                            '${mesa.quantidadePessoasCouvert} pessoa(s) × ${formatoMoeda.format(mesa.valorCouvertPorPessoa)}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ),
                      ],
                    ],
                    // Garçom
                    if (mesa.valorGarcom != null && !mesa.garcomRetirado && mesa.valorGarcom! > 0) ...[
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Garçom (10%):',
                            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            formatoMoeda.format(mesa.valorGarcom!),
                            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Divider(),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'TOTAL GERAL:',
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          formatoMoeda.format(mesa.totalCalculado),
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              
              // Resumo de Status
              pw.Text(
                'RESUMO DE STATUS',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Pendentes: ${mesa.itensPendentes.length}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Em Preparo: ${mesa.itensEmPreparo.length}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Prontos: ${mesa.itensProntos.length}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Spacer(),
              
              // Rodapé
              pw.Divider(),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'Impresso em: ${formatoData.format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    return await pdf.save();
  }

  Future<void> _receberMesa(MesaComanda mesa, DataService dataService) async {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    // Buscar comandas vinculadas - incluir todas, independente do status, desde que tenham itens não pagos
    final todasComandasDaMesa = dataService.mesasComandas
        .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesa.id)
        .toList();
    
    // Filtrar apenas comandas que têm itens não pagos
    final comandasDaMesa = todasComandasDaMesa
        .where((c) => c.itensNaoPagos.isNotEmpty)
        .toList();
    
    // Coletar todos os itens não pagos (mesa + comandas) com referência à origem
    final itensComOrigem = <Map<String, dynamic>>[];
    
    // Itens da mesa
    for (final item in mesa.itensNaoPagos) {
      itensComOrigem.add({
        'item': item,
        'origem': 'Mesa ${mesa.numero}',
        'origemId': mesa.id,
        'tipo': 'mesa',
      });
    }
    
    // Itens das comandas vinculadas
    for (final comanda in comandasDaMesa) {
      for (final item in comanda.itensNaoPagos) {
        itensComOrigem.add({
          'item': item,
          'origem': 'Comanda ${comanda.numero}',
          'origemId': comanda.id,
          'tipo': 'comanda',
        });
      }
    }
    
    // Debug: verificar se há itens (considerar também se há couvert pendente)
    if (itensComOrigem.isEmpty && mesa.couvertPendente <= 0.01) {
      // Se não há itens mas a mesa está aberta, perguntar se deseja liberar/limpar a mesa
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Limpar Mesa', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Esta mesa não possui itens pendentes. Deseja limpá-la e deixá-la disponível para o próximo cliente?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Não', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Sim, Limpar Mesa'),
            ),
          ],
        ),
      );

      if (confirmar == true && context.mounted) {
        // Chamar o método de limpar mesa do DataService
        await dataService.limparMesaComanda(mesa.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mesa limpa e disponível!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
      return;
    }
    
    // Calcular total pendente incluindo comandas vinculadas
    double totalPendenteMesa = mesa.totalCalculado - mesa.totalPago;
    double totalPendenteComandas = 0.0;
    
    for (final comanda in comandasDaMesa) {
      final pendenteComanda = comanda.totalCalculado - comanda.totalPago;
      if (pendenteComanda > 0) {
        totalPendenteComandas += pendenteComanda;
      }
    }
    
    final totalDisponivel = totalPendenteMesa + totalPendenteComandas;
    
    if (totalDisponivel <= 0.01) { // Tolerância de 0.01 para arredondamentos
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mesa e comandas vinculadas sem valor pendente para receber'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!context.mounted) return;

    // Itens selecionados para pagamento
    final itensSelecionados = <String>{};
    double quantidadePessoasCouvertSelecionada = 0.0; // Quantidade de pessoas do couvert selecionada para pagar
    double valorItensSelecionados = 0.0; // Valor apenas dos itens (sem couvert)
    double valorSelecionado = 0.0; // Valor total selecionado (itens + couvert)
    final pessoaPagouController = TextEditingController();
    final quantidadeCouvertController = TextEditingController();
    
    // Verificar se há couvert pendente
    final couvertPendente = mesa.couvertPendente;
    final temCouvertPendente = couvertPendente > 0.01;
    final quantidadePessoasPendente = (mesa.quantidadePessoasCouvert ?? 0) - ((mesa.couvertPago / (mesa.valorCouvertPorPessoa ?? 1.0)).round());
    final valorPorPessoa = mesa.valorCouvertPorPessoa ?? 0.0;

    // Mostrar diálogo de seleção de itens e pagamento
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Agrupar itens por origem
          final itensPorOrigem = <String, List<Map<String, dynamic>>>{};
          for (final itemData in itensComOrigem) {
            final origem = itemData['origem'] as String;
            if (!itensPorOrigem.containsKey(origem)) {
              itensPorOrigem[origem] = [];
            }
            itensPorOrigem[origem]!.add(itemData);
          }
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            insetPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            title: const Text(
              'Receber Mesa',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mesa: ${mesa.numero}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
            Text(
                          'Total: ${formatoMoeda.format(_getTotalMesaComComandas(mesa, dataService))}',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Text(
                          'Pago: ${formatoMoeda.format(mesa.totalPago)}',
                          style: const TextStyle(color: Colors.green, fontSize: 14),
                        ),
                      ],
                    ),
                    Text(
                      'Pendente: ${formatoMoeda.format(totalDisponivel)}',
                      style: const TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
                    const Text(
                      'Selecione os itens para receber:',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    // Selecionar Tudo (Global)
                    CheckboxListTile(
                      title: const Text('Selecionar Tudo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      value: itensSelecionados.length == itensComOrigem.length,
                      activeColor: Colors.orange,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                         if (value == null) return;
                         setDialogState(() {
                            if (value) {
                               for (final itemData in itensComOrigem) {
                                  final item = itemData['item'] as ItemMesaComanda;
                                  if (!itensSelecionados.contains(item.id)) {
                                     itensSelecionados.add(item.id);
                                     final itemTotal = item.preco * item.quantidade;
                                     valorItensSelecionados += itemTotal;
                                     valorSelecionado += itemTotal;
                                  }
                               }
                            } else {
                               itensSelecionados.clear();
                               valorItensSelecionados = 0.0;
                               valorSelecionado = 0.0;
                            }
                         });
                      },
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: itensPorOrigem.length,
                        itemBuilder: (context, origemIndex) {
                          final origem = itensPorOrigem.keys.elementAt(origemIndex);
                          final itensOrigem = itensPorOrigem[origem]!;
                          final primeiroItem = itensOrigem.first;
                          final tipoOrigem = primeiroItem['tipo'] as String;
                          
                          // Calcular total da origem
                          double totalOrigem = 0.0;
                          for (final itemData in itensOrigem) {
                            final item = itemData['item'] as ItemMesaComanda;
                            totalOrigem += item.preco * item.quantidade;
                          }
                          
                          // Verificar se todos os itens da origem estão selecionados
                          final todosSelecionados = itensOrigem.every((itemData) {
                            final item = itemData['item'] as ItemMesaComanda;
                            return itensSelecionados.contains(item.id);
                          });
                          
                          return ExpansionTile(
                            title: Text(
                              origem,
                              style: TextStyle(
                                color: tipoOrigem == 'comanda' ? Colors.purple : Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '${itensOrigem.length} item(s) - ${formatoMoeda.format(totalOrigem)}',
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            leading: Checkbox(
                              value: todosSelecionados,
                              activeColor: Colors.orange,
                              onChanged: (value) {
                                if (value == null) return;
                                  setDialogState(() {
                                    for (final itemData in itensOrigem) {
                                      final item = itemData['item'] as ItemMesaComanda;
                                      final itemTotal = item.preco * item.quantidade;
                                      if (value == true) {
                                        if (!itensSelecionados.contains(item.id)) {
                                          itensSelecionados.add(item.id);
                                          valorItensSelecionados += itemTotal;
                                          valorSelecionado += itemTotal;
                                        }
                                      } else {
                                        if (itensSelecionados.contains(item.id)) {
                                          itensSelecionados.remove(item.id);
                                          valorItensSelecionados -= itemTotal;
                                          valorSelecionado -= itemTotal;
                                        }
                                      }
                                    }
                                  });
                              },
                            ),
                            children: itensOrigem.map((itemData) {
                              final item = itemData['item'] as ItemMesaComanda;
                              final itemTotal = item.preco * item.quantidade;
                              final isSelecionado = itensSelecionados.contains(item.id);
                              
                              return CheckboxListTile(
                                title: Text(
                                  '${item.quantidade}x ${item.nome}',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                                subtitle: Text(
                                  formatoMoeda.format(itemTotal),
                                  style: const TextStyle(color: Colors.green, fontSize: 12),
                                ),
                                value: isSelecionado,
                                activeColor: Colors.orange,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    if (value == true) {
                                      itensSelecionados.add(item.id);
                                      valorItensSelecionados += itemTotal;
                                      valorSelecionado += itemTotal;
                                    } else {
                                      itensSelecionados.remove(item.id);
                                      valorItensSelecionados -= itemTotal;
                                      valorSelecionado -= itemTotal;
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                    // Opção de Couvert
                    if (temCouvertPendente) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.music_note, color: Colors.orange, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Couvert Artístico',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total: ${mesa.quantidadePessoasCouvert ?? 0} pessoa(s) × ${formatoMoeda.format(valorPorPessoa)} = ${formatoMoeda.format(mesa.valorCouvertCalculado)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pago: ${formatoMoeda.format(mesa.couvertPago)} | Pendente: $quantidadePessoasPendente pessoa(s) = ${formatoMoeda.format(couvertPendente)}',
                              style: TextStyle(
                                color: couvertPendente > 0 ? Colors.orange : Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: quantidadeCouvertController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Quantidade de pessoas a pagar',
                                      labelStyle: const TextStyle(color: Colors.grey),
                                      hintText: 'Ex: 1, 2, 3...',
                                      hintStyle: const TextStyle(color: Colors.grey),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.1),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Colors.grey),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Colors.grey),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Colors.orange),
                                      ),
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        final quantidade = double.tryParse(value) ?? 0.0;
                                        if (quantidade < 0) {
                                          quantidadePessoasCouvertSelecionada = 0.0;
                                          valorSelecionado = valorItensSelecionados;
                                        } else if (quantidade > quantidadePessoasPendente) {
                                          quantidadePessoasCouvertSelecionada = quantidadePessoasPendente.toDouble();
                                          quantidadeCouvertController.text = quantidadePessoasPendente.toString();
                                          valorSelecionado = valorItensSelecionados + (quantidadePessoasPendente * valorPorPessoa);
                                        } else {
                                          quantidadePessoasCouvertSelecionada = quantidade;
                                          valorSelecionado = valorItensSelecionados + (quantidade * valorPorPessoa);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.add, color: Colors.orange),
                                  onPressed: () {
                                    setDialogState(() {
                                      if (quantidadePessoasCouvertSelecionada < quantidadePessoasPendente) {
                                        quantidadePessoasCouvertSelecionada++;
                                        quantidadeCouvertController.text = quantidadePessoasCouvertSelecionada.toString();
                                        valorSelecionado = valorItensSelecionados + (quantidadePessoasCouvertSelecionada * valorPorPessoa);
                                      }
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove, color: Colors.orange),
                                  onPressed: () {
                                    setDialogState(() {
                                      if (quantidadePessoasCouvertSelecionada > 0) {
                                        quantidadePessoasCouvertSelecionada--;
                                        quantidadeCouvertController.text = quantidadePessoasCouvertSelecionada.toString();
                                        valorSelecionado = valorItensSelecionados + (quantidadePessoasCouvertSelecionada * valorPorPessoa);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (quantidadePessoasCouvertSelecionada > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Valor selecionado: $quantidadePessoasCouvertSelecionada pessoa(s) × ${formatoMoeda.format(valorPorPessoa)} = ${formatoMoeda.format(quantidadePessoasCouvertSelecionada * valorPorPessoa)}',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (itensSelecionados.isNotEmpty || quantidadePessoasCouvertSelecionada > 0) ...[
                      const Divider(),
                      Text(
                        'Valor selecionado: ${formatoMoeda.format(valorSelecionado)}',
                        style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: pessoaPagouController,
                        decoration: InputDecoration(
                          labelText: 'Nome de quem está pagando (opcional)',
                          labelStyle: const TextStyle(color: Colors.grey),
                          hintText: 'Ex: João Silva',
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.grey),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.orange),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          // Nome da pessoa é opcional
                          
                          // Calcular garçom como 10% apenas do valor selecionado (itens)
                          // O valor base é o valor dos itens selecionados (sem garçom e sem couvert)
                          double valorBaseSelecionado = valorItensSelecionados; // Apenas itens, sem couvert
                          final valorCouvertSelecionado = quantidadePessoasCouvertSelecionada * valorPorPessoa;
                          double valorGarcomSelecionado = 0.0;
                          double valorTotalComGarcom = valorSelecionado;
                          
                          if (!mesa.garcomRetirado) {
                            // Garçom é 10% apenas do valor base (itens selecionados)
                            valorGarcomSelecionado = valorBaseSelecionado * 0.10;
                            // Valor total com garçom
                            valorTotalComGarcom = valorSelecionado + valorGarcomSelecionado;
                          }
                          
                          // Mostrar tela de pagamento do PDV (até 2 formas)
                          // Passar o valor total com garçom e o valor base para cálculo correto
                          final pagamentos = await _mostrarTelaPagamentoPDV(
                            context,
                            valorTotalComGarcom,
                            pessoaPagouController.text.trim(),
                            mesaComanda: mesa,
                            valorBase: valorBaseSelecionado, // Passar o valor base (sem garçom e sem couvert) para cálculo correto
                          );
                          
                          if (pagamentos != null && pagamentos.isNotEmpty && context.mounted) {
                            Navigator.pop(context, {
                              'itens': itensSelecionados.toList(),
                              'valor': valorTotalComGarcom, // Retornar o valor total com garçom para validação correta
                              'valorBase': valorSelecionado, // Valor sem garçom (para referência)
                              'pagamentos': pagamentos,
                              'pessoaPagou': pessoaPagouController.text.trim(),
                              'couvertSelecionado': quantidadePessoasCouvertSelecionada > 0,
                              'valorCouvert': valorCouvertSelecionado,
                              'quantidadePessoasCouvert': quantidadePessoasCouvertSelecionada,
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: const Text('Escolher Forma de Pagamento'),
                      ),
                    ],
                  ],
                ),
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
            ],
          );
        },
      ),
    );

    if (resultado == null) return;

    final itensIds = resultado['itens'] as List<String>;
    final valorPago = resultado['valor'] as double;
    final pagamentos = resultado['pagamentos'] as List<Map<String, dynamic>>?;
    final pessoaPagou = resultado['pessoaPagou'] as String?;
    final couvertSelecionadoResult = resultado['couvertSelecionado'] as bool? ?? false;
    final valorCouvert = resultado['valorCouvert'] as double? ?? 0.0;

    if (pagamentos == null || pagamentos.isEmpty) {
      return;
    }

    // Processar pagamento
    try {
      // Recarregar dados atualizados do dataService
      final mesaAtual = dataService.mesasComandas.firstWhere(
        (m) => m.id == mesa.id,
        orElse: () => mesa,
      );
      
      // Buscar comandas vinculadas atualizadas - todas, independente do status
      final comandasDaMesaAtualizadas = dataService.mesasComandas
          .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesa.id)
          .toList();
      
      // Separar itens da mesa e das comandas
      final itensMesa = <String>[];
      final itensComandas = <String, List<String>>{}; // comandaId -> lista de itemIds
      
      // Verificar origem de cada item usando os dados atualizados
      for (final itemData in itensComOrigem) {
        final item = itemData['item'] as ItemMesaComanda;
        if (itensIds.contains(item.id)) {
          final tipo = itemData['tipo'] as String;
          final origemId = itemData['origemId'] as String;
          
          if (tipo == 'mesa') {
            itensMesa.add(item.id);
          } else if (tipo == 'comanda') {
            if (!itensComandas.containsKey(origemId)) {
              itensComandas[origemId] = [];
            }
            itensComandas[origemId]!.add(item.id);
          }
        }
      }
      
      // Criar registros de pagamento (até 2 formas)
      final registrosPagamento = <RegistroPagamento>[];
      double valorTotalPagamentos = 0.0;
      
      for (final pagamentoData in pagamentos) {
        final tipoPagamento = pagamentoData['tipo'] as TipoPagamento;
        final valorPagamento = pagamentoData['valor'] as double;
        final observacaoPagamento = pagamentoData['observacao'] as String?;
        
        valorTotalPagamentos += valorPagamento;
        
        registrosPagamento.add(RegistroPagamento(
          id: uuid.v4(),
          valor: valorPagamento,
          dataPagamento: DateTime.now(),
          formaPagamento: tipoPagamento.nome,
          observacao: observacaoPagamento ?? 'Pagamento - ${itensIds.length} item(ns)',
          itensPagos: itensIds,
          pessoaPagou: pessoaPagou,
        ));
      }
      
      // Verificar se o garçom foi retirado (vem do resultado do pagamento)
      bool garcomFoiRetirado = false;
      if (pagamentos.isNotEmpty) {
        final primeiroPagamento = pagamentos.first;
        garcomFoiRetirado = primeiroPagamento['garcomRetirado'] as bool? ?? false;
      }
      
      // Calcular valor esperado considerando se o garçom foi retirado
      // O valorPago é o valorTotalComGarcom retornado do diálogo de seleção
      // Se o garçom foi retirado, o valor esperado é menor (sem o garçom)
      double valorEsperado = valorPago;
      if (garcomFoiRetirado) {
        // Calcular o valor do garçom (10% dos itens selecionados)
        // O valorBase foi passado no diálogo de pagamento, mas não temos aqui
        // Precisamos calcular: se valorPago = itens + couvert + garçom
        // E garçom = 10% dos itens, então:
        // valorPago = itens + couvert + (itens * 0.10)
        // Não podemos calcular precisamente sem saber o valor dos itens separado do couvert
        // Mas podemos usar o valorBase do resultado se disponível
        final valorBaseDoResultado = resultado['valorBase'] as double?;
        if (valorBaseDoResultado != null) {
          // Garçom é 10% apenas dos itens (valorBase)
          final valorGarcomCalculado = valorBaseDoResultado * 0.10;
          valorEsperado = valorPago - valorGarcomCalculado;
        } else {
          // Fallback: tentar estimar removendo aproximadamente 10% do total
          // Isso não é ideal, mas melhor que nada
          valorEsperado = valorPago / 1.10;
        }
      }
      
      // Verificar se o valor total dos pagamentos corresponde ao valor esperado (com garçom se aplicável)
      if ((valorTotalPagamentos - valorEsperado).abs() > 0.01) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro: O valor total dos pagamentos (${formatoMoeda.format(valorTotalPagamentos)}) não corresponde ao valor esperado (${formatoMoeda.format(valorEsperado)})'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Adicionar itens da mesa aos pagos
      final novosItensPagosMesa = [...mesaAtual.itensPagos, ...itensMesa];

      // Atualizar histórico de pagamentos da mesa (adicionar todos os registros)
      final novoHistoricoMesa = [...mesaAtual.historicoPagamentos, ...registrosPagamento];

      // Atualizar couvert pago se foi selecionado
      double novoCouvertPago = mesaAtual.couvertPago;
      if (couvertSelecionadoResult && valorCouvert > 0) {
        novoCouvertPago = (mesaAtual.couvertPago + valorCouvert).clamp(0.0, mesaAtual.valorCouvertCalculado);
      }
      
      // Atualizar mesa (garcomFoiRetirado já foi definido acima na validação)
      final mesaAtualizada = mesaAtual.copyWith(
        itensPagos: novosItensPagosMesa,
        historicoPagamentos: novoHistoricoMesa,
        couvertPago: novoCouvertPago,
        garcomRetirado: garcomFoiRetirado || mesaAtual.garcomRetirado,
      );
      await dataService.updateMesaComanda(mesaAtualizada);
      
      // Atualizar comandas vinculadas - apenas se houver itens selecionados delas
      if (itensComandas.isNotEmpty) {
        for (final entry in itensComandas.entries) {
          final comandaId = entry.key;
          final itemIdsComanda = entry.value;
          
          // Buscar comanda atualizada
          final comandaAtual = comandasDaMesaAtualizadas.firstWhere(
            (c) => c.id == comandaId,
            orElse: () {
              // Se não encontrar, buscar no dataService
              return dataService.mesasComandas.firstWhere(
                (c) => c.id == comandaId,
                orElse: () => throw Exception('Comanda $comandaId não encontrada'),
              );
            },
          );
          
          // Criar registros de pagamento específicos para a comanda (proporcional)
          final valorComanda = itemIdsComanda.fold<double>(0.0, (sum, itemId) {
            final item = comandaAtual.itens.firstWhere(
              (i) => i.id == itemId,
              orElse: () => throw Exception('Item $itemId não encontrado na comanda'),
            );
            return sum + (item.preco * item.quantidade);
          });
          
          // Distribuir pagamentos proporcionalmente
          final registrosPagamentoComanda = <RegistroPagamento>[];
          for (final pagamentoData in pagamentos) {
            final tipoPagamento = pagamentoData['tipo'] as TipoPagamento;
            final valorPagamento = pagamentoData['valor'] as double;
            final observacaoPagamento = pagamentoData['observacao'] as String?;
            
            // Calcular proporção deste pagamento no total
            final proporcao = valorPagamento / valorTotalPagamentos;
            final valorComandaProporcional = valorComanda * proporcao;
            
            registrosPagamentoComanda.add(RegistroPagamento(
              id: uuid.v4(),
              valor: valorComandaProporcional,
              dataPagamento: DateTime.now(),
              formaPagamento: tipoPagamento.nome,
              observacao: observacaoPagamento ?? 'Pagamento via mesa ${mesa.numero} - ${itemIdsComanda.length} item(ns)',
              itensPagos: itemIdsComanda,
              pessoaPagou: pessoaPagou,
            ));
          }
          
          final novosItensPagosComanda = [...comandaAtual.itensPagos, ...itemIdsComanda];
          final novoHistoricoComanda = [...comandaAtual.historicoPagamentos, ...registrosPagamentoComanda];
          
          final comandaAtualizada = comandaAtual.copyWith(
            itensPagos: novosItensPagosComanda,
            historicoPagamentos: novoHistoricoComanda,
          );
          await dataService.updateMesaComanda(comandaAtualizada);
        }
      }

      // Verificar se está totalmente pago (mesa + comandas)
      // Recalcular total pago incluindo comandas vinculadas
      double totalPagoMesa = mesaAtualizada.totalPago;
      double totalPagoComandas = 0.0;
      
      // Buscar comandas vinculadas atualizadas após o pagamento
      final comandasDaMesaAtualizadasParaVerificacao = dataService.mesasComandas
          .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesaAtualizada.id)
          .toList();
      
      for (final comanda in comandasDaMesaAtualizadasParaVerificacao) {
        totalPagoComandas += comanda.totalPago;
      }
      
      final novoTotalPago = totalPagoMesa + totalPagoComandas;
      
      // Calcular total geral (mesa + comandas) - todos os itens, não apenas pendentes
      double totalGeralMesa = mesaAtualizada.totalCalculado;
      double totalGeralComandas = 0.0;
      for (final comanda in comandasDaMesaAtualizadasParaVerificacao) {
        totalGeralComandas += comanda.totalCalculado;
      }
      final novoTotalGeral = totalGeralMesa + totalGeralComandas;
      
      // Verificar se está totalmente pago (com tolerância de 0.01 para arredondamentos)
      // IMPORTANTE: Só liberar mesa se estiver TOTALMENTE paga
      final estaPago = novoTotalPago >= novoTotalGeral - 0.01;
      
      // IMPORTANTE: Só liberar mesa se estiver TOTALMENTE paga
      // Se totalmente pago, criar venda e liberar mesa
      if (estaPago) {
        // Coletar todos os itens da mesa e comandas vinculadas para a venda
        final todosItensVenda = <ItemVendaBalcao>[];
        
        // Itens da mesa
        for (final item in mesaAtualizada.itens) {
          if (item.status != StatusItem.cancelado) {
            todosItensVenda.add(ItemVendaBalcao(
          id: item.itemId,
          nome: item.nome,
          precoUnitario: item.preco,
          quantidade: item.quantidade.toDouble(),
          isServico: item.isServico,
            ));
          }
        }
        
        // Itens das comandas vinculadas
        final comandasDaMesaParaVenda = dataService.mesasComandas
            .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesaAtualizada.id)
            .toList();
        
        // Incluir apenas itens PAGOS das comandas na venda
        // Itens pendentes das comandas não devem ser incluídos na venda da mesa
        for (final comanda in comandasDaMesaParaVenda) {
          for (final item in comanda.itens) {
            // Incluir apenas itens pagos e não cancelados
            if (item.status != StatusItem.cancelado && comanda.itensPagos.contains(item.id)) {
              todosItensVenda.add(ItemVendaBalcao(
                id: item.itemId,
                nome: item.nome,
                precoUnitario: item.preco,
                quantidade: item.quantidade.toDouble(),
                isServico: item.isServico,
              ));
            }
          }
        }

      // Converter todos os pagamentos (mesa + comandas vinculadas) em PagamentoPedido
      // para preservar TODAS as formas de pagamento no histórico (split/parcial)
      List<PagamentoPedido> converterPagamentosVendaMesa() {
        final lista = <PagamentoPedido>[];
        TipoPagamento _parseForma(String? f) {
          final lower = f?.toLowerCase() ?? '';
          if (lower.contains('pix')) return TipoPagamento.pix;
          if (lower.contains('dinheiro')) return TipoPagamento.dinheiro;
          if (lower.contains('débito') || lower.contains('debito')) return TipoPagamento.cartaoDebito;
          if (lower.contains('crédito') || lower.contains('credito') || lower.contains('cart')) return TipoPagamento.cartaoCredito;
          if (lower.contains('boleto')) return TipoPagamento.boleto;
          if (lower.contains('crediário') || lower.contains('crediario')) return TipoPagamento.crediario;
          if (lower.contains('fiado')) return TipoPagamento.fiado;
          return TipoPagamento.outro;
        }
        for (final rp in mesaAtualizada.historicoPagamentos) {
          lista.add(PagamentoPedido(
            id: rp.id,
            tipo: _parseForma(rp.formaPagamento),
            valor: rp.valor,
            recebido: true,
            dataRecebimento: rp.dataPagamento,
            observacao: rp.observacao,
          ));
        }
        // Comandas recebem cópias PROPORCIONAIS dos mesmos pagamentos já registrados
        // na mesa (registrosPagamentoComanda). Para evitar contagem dupla, incluímos
        // apenas pagamentos das comandas que NÃO correspondem a um pagamento da mesa
        // com a mesma forma e data (mesmo instante de liquidação).
        for (final comanda in comandasDaMesaParaVenda) {
          for (final rp in comanda.historicoPagamentos) {
            final ehCopiaDoPagamentoDaMesa = mesaAtualizada.historicoPagamentos
                .any((m) {
              final mesmaForma = (m.formaPagamento ?? '').toLowerCase() ==
                  (rp.formaPagamento ?? '').toLowerCase();
              final mesmaData = m.dataPagamento
                      .difference(rp.dataPagamento)
                      .inSeconds
                      .abs() <
                  120;
              return mesmaForma && mesmaData;
            });
            if (ehCopiaDoPagamentoDaMesa) continue;
            lista.add(PagamentoPedido(
              id: rp.id,
              tipo: _parseForma(rp.formaPagamento),
              valor: rp.valor,
              recebido: true,
              dataRecebimento: rp.dataPagamento,
              observacao: rp.observacao,
            ));
          }
        }
        if (lista.isEmpty && pagamentos.isNotEmpty) {
          for (final p in pagamentos) {
            lista.add(PagamentoPedido(
              id: uuid.v4(),
              tipo: p['tipo'] as TipoPagamento,
              valor: p['valor'] as double,
              recebido: true,
              dataRecebimento: DateTime.now(),
            ));
          }
        }
        return lista;
      }

      final pagamentosVenda = converterPagamentosVendaMesa();

      final numeroVenda = dataService.getProximoNumeroVenda();
      final vendaBalcao = VendaBalcao(
        id: uuid.v4(),
        numero: numeroVenda,
        dataVenda: DateTime.now(),
          clienteId: mesaAtualizada.clienteId,
          clienteNome: mesaAtualizada.clienteNome,
          itens: todosItensVenda,
          tipoPagamento: pagamentos.first['tipo'] as TipoPagamento, // Usar primeira forma como principal
          pagamentos: pagamentosVenda,
          valorTotal: novoTotalGeral,
          valorRecebido: novoTotalPago,
        troco: null,
          observacoes: 'Mesa ${mesaAtualizada.numero}',
        operador: dataService.responsavelAtivo,
      );

      await dataService.addVendaBalcao(vendaBalcao);

        // Liberar mesa: limpar TUDO para nova utilização
        // IMPORTANTE: Limpar histórico de pagamentos para evitar saldo negativo
        // O histórico completo está preservado na venda criada acima
        final mesaLiberada = mesaAtualizada.copyWith(
          itens: [], // Limpar todos os itens
          itensPagos: [], // Limpar itens pagos
          historicoPagamentos: [], // Limpar histórico de pagamentos para evitar saldo negativo
          status: 'Aberta', // Reabrir mesa
          dataFechamento: null, // Remover data de fechamento
          dataAbertura: DateTime.now(), // Nova data de abertura
          clienteNome: null, // Limpar cliente
          clienteId: null, // Limpar ID do cliente
          observacao: null, // Limpar observações
          total: 0.0, // Zerar total
          valorCouvert: null, // Limpar couvert
          quantidadePessoasCouvert: null,
          valorCouvertPorPessoa: null,
          valorGarcom: null, // Limpar garçom
          garcomRetirado: false, // Resetar retirada do garçom
          updatedAt: DateTime.now(), // Atualizar timestamp
        );
        
        // Atualizar comandas vinculadas - APENAS as que estão totalmente pagas
        // IMPORTANTE: Não fechar comandas que ainda têm itens pendentes
        for (final comanda in comandasDaMesaParaVenda) {
          // Verificar se a comanda está totalmente paga
          final comandaEstaPaga = comanda.totalPago >= comanda.totalCalculado - 0.01;
          
          if (comandaEstaPaga) {
            // Se totalmente paga, manter aberta e limpa (igual a mesa)
            final comandaLiberada = comanda.copyWith(
              itens: [],
              itensPagos: [],
              historicoPagamentos: [],
              status: 'Aberta',
              dataFechamento: null,
              dataAbertura: DateTime.now(),
              clienteNome: null,
              clienteId: null,
              observacao: null, // Limpar observações
              valorCouvert: null,
              quantidadePessoasCouvert: null,
              valorCouvertPorPessoa: null,
              valorGarcom: null,
              garcomRetirado: false,
              updatedAt: DateTime.now(),
            );
            await dataService.updateMesaComanda(comandaLiberada);
          }
          // Se não estiver totalmente paga, manter aberta com seus itens pendentes
        }
        
        await dataService.updateMesaComanda(mesaLiberada);
        
        // Aguardar um pouco para garantir que a atualização foi salva
        await Future.delayed(const Duration(milliseconds: 100));
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Mesa ${mesaAtualizada.numero} totalmente paga! Venda ${numeroVenda} criada. Mesa liberada para novo uso.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
          setState(() {
            _mesaSelecionada = null; // Limpar seleção
            // Forçar rebuild da lista para mostrar mesa disponível
          });
        }
      } else {
        // Pagamento parcial - apenas atualizar
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Pagamento de ${formatoMoeda.format(valorPago)} registrado.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
            // Recarregar mesa atualizada do dataService
            final mesaRecarregada = dataService.mesasComandas.firstWhere(
              (m) => m.id == mesaAtualizada.id,
              orElse: () => mesaAtualizada,
            );
            _mesaSelecionada = mesaRecarregada;
          });
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar pagamento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Recebe pagamento apenas de uma comanda específica (não inclui mesa ou outras comandas)
  Future<void> _receberComanda(MesaComanda comanda, DataService dataService) async {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    // Recarregar comanda atualizada do dataService para garantir dados corretos
    final comandaAtual = dataService.mesasComandas.firstWhere(
      (c) => c.id == comanda.id,
      orElse: () => comanda,
    );
    
    // Coletar apenas os itens não pagos desta comanda
    final itensNaoPagos = comandaAtual.itensNaoPagos;
    
    // Verificar se há couvert pendente
    final couvertPendente = comandaAtual.couvertPendente;
    final totalDisponivel = comandaAtual.totalCalculado - comandaAtual.totalPago;
    final totalComCouvert = totalDisponivel + couvertPendente;
    
    if (itensNaoPagos.isEmpty && couvertPendente <= 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comanda sem valor pendente para receber'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (totalComCouvert <= 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comanda sem valor pendente para receber'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!context.mounted) return;

    // Itens selecionados para pagamento
    final itensSelecionados = <String>{};
    double quantidadePessoasCouvertSelecionada = 0.0; // Quantidade de pessoas do couvert selecionada para pagar
    double valorItensSelecionados = 0.0; // Valor apenas dos itens (sem couvert)
    double valorSelecionado = 0.0;
    final pessoaPagouController = TextEditingController();
    final quantidadeCouvertController = TextEditingController();
    
    final temCouvertPendente = couvertPendente > 0.01;
    final quantidadePessoasPendente = (comandaAtual.quantidadePessoasCouvert ?? 0) - ((comandaAtual.couvertPago / (comandaAtual.valorCouvertPorPessoa ?? 1.0)).round());
    final valorPorPessoa = comandaAtual.valorCouvertPorPessoa ?? 0.0;

    // Mostrar diálogo de seleção de itens e pagamento
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            insetPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            title: const Text(
              'Receber Comanda',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Comanda: ${comandaAtual.numero}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total: ${formatoMoeda.format(comandaAtual.totalCalculado)}',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        Text(
                          'Pago: ${formatoMoeda.format(comandaAtual.totalPago)}',
                          style: const TextStyle(color: Colors.green, fontSize: 14),
                        ),
                      ],
                    ),
                    Text(
                      'Pendente: ${formatoMoeda.format(totalDisponivel)}',
                      style: const TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Selecione os itens para receber:',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    // Selecionar Tudo (Global)
                    CheckboxListTile(
                      title: const Text('Selecionar Tudo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      value: itensSelecionados.length == itensNaoPagos.length,
                      activeColor: Colors.orange,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                         if (value == null) return;
                         setDialogState(() {
                            if (value) {
                               for (final item in itensNaoPagos) {
                                  if (!itensSelecionados.contains(item.id)) {
                                     itensSelecionados.add(item.id);
                                     final itemTotal = item.preco * item.quantidade;
                                     valorItensSelecionados += itemTotal;
                                     valorSelecionado += itemTotal;
                                  }
                               }
                            } else {
                               itensSelecionados.clear();
                               valorItensSelecionados = 0.0;
                               valorSelecionado = 0.0;
                            }
                         });
                      },
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: itensNaoPagos.length,
                        itemBuilder: (context, index) {
                          final item = itensNaoPagos[index];
                          final itemTotal = item.preco * item.quantidade;
                          final isSelecionado = itensSelecionados.contains(item.id);
                          
                          return CheckboxListTile(
                            title: Text(
                              '${item.quantidade}x ${item.nome}',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                            subtitle: Text(
                              formatoMoeda.format(itemTotal),
                              style: const TextStyle(color: Colors.green, fontSize: 12),
                            ),
                            value: isSelecionado,
                            activeColor: Colors.orange,
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {
                                if (value == true) {
                                  itensSelecionados.add(item.id);
                                  valorItensSelecionados += itemTotal;
                                  valorSelecionado = valorItensSelecionados + (quantidadePessoasCouvertSelecionada * valorPorPessoa);
                                } else {
                                  itensSelecionados.remove(item.id);
                                  valorItensSelecionados -= itemTotal;
                                  valorSelecionado = valorItensSelecionados + (quantidadePessoasCouvertSelecionada * valorPorPessoa);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    // Opção de Couvert
                    if (temCouvertPendente) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.music_note, color: Colors.orange, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Couvert Artístico',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total: ${comandaAtual.quantidadePessoasCouvert ?? 0} pessoa(s) × ${formatoMoeda.format(valorPorPessoa)} = ${formatoMoeda.format(comandaAtual.valorCouvertCalculado)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pago: ${formatoMoeda.format(comandaAtual.couvertPago)} | Pendente: $quantidadePessoasPendente pessoa(s) = ${formatoMoeda.format(couvertPendente)}',
                              style: TextStyle(
                                color: couvertPendente > 0 ? Colors.orange : Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: quantidadeCouvertController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Quantidade de pessoas a pagar',
                                      labelStyle: const TextStyle(color: Colors.grey),
                                      hintText: 'Ex: 1, 2, 3...',
                                      hintStyle: const TextStyle(color: Colors.grey),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.1),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Colors.grey),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Colors.grey),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Colors.orange),
                                      ),
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        final quantidade = double.tryParse(value) ?? 0.0;
                                        if (quantidade < 0) {
                                          quantidadePessoasCouvertSelecionada = 0.0;
                                          valorSelecionado = valorItensSelecionados;
                                        } else if (quantidade > quantidadePessoasPendente) {
                                          quantidadePessoasCouvertSelecionada = quantidadePessoasPendente.toDouble();
                                          quantidadeCouvertController.text = quantidadePessoasPendente.toString();
                                          valorSelecionado = valorItensSelecionados + (quantidadePessoasPendente * valorPorPessoa);
                                        } else {
                                          quantidadePessoasCouvertSelecionada = quantidade;
                                          valorSelecionado = valorItensSelecionados + (quantidade * valorPorPessoa);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.add, color: Colors.orange),
                                  onPressed: () {
                                    setDialogState(() {
                                      if (quantidadePessoasCouvertSelecionada < quantidadePessoasPendente) {
                                        quantidadePessoasCouvertSelecionada++;
                                        quantidadeCouvertController.text = quantidadePessoasCouvertSelecionada.toString();
                                        valorSelecionado = valorItensSelecionados + (quantidadePessoasCouvertSelecionada * valorPorPessoa);
                                      }
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove, color: Colors.orange),
                                  onPressed: () {
                                    setDialogState(() {
                                      if (quantidadePessoasCouvertSelecionada > 0) {
                                        quantidadePessoasCouvertSelecionada--;
                                        quantidadeCouvertController.text = quantidadePessoasCouvertSelecionada.toString();
                                        valorSelecionado = valorItensSelecionados + (quantidadePessoasCouvertSelecionada * valorPorPessoa);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (quantidadePessoasCouvertSelecionada > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Valor selecionado: $quantidadePessoasCouvertSelecionada pessoa(s) × ${formatoMoeda.format(valorPorPessoa)} = ${formatoMoeda.format(quantidadePessoasCouvertSelecionada * valorPorPessoa)}',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (itensSelecionados.isNotEmpty || quantidadePessoasCouvertSelecionada > 0) ...[
                      const Divider(),
                      Text(
                        'Valor selecionado: ${formatoMoeda.format(valorSelecionado)}',
                        style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: pessoaPagouController,
                        decoration: InputDecoration(
                          labelText: 'Nome de quem está pagando (opcional)',
                          labelStyle: const TextStyle(color: Colors.grey),
                          hintText: 'Ex: João Silva',
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.grey),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.orange),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              if (itensSelecionados.isNotEmpty || quantidadePessoasCouvertSelecionada > 0)
                ElevatedButton(
                  onPressed: () async {
                    // Nome da pessoa é opcional
                    
                    // Calcular garçom como 10% apenas do valor selecionado (itens)
                    // O valor base é o valor dos itens selecionados (sem garçom e sem couvert)
                    double valorBaseSelecionado = valorItensSelecionados; // Apenas itens, sem couvert
                    final valorCouvertSelecionado = quantidadePessoasCouvertSelecionada * valorPorPessoa;
                    double valorGarcomSelecionado = 0.0;
                    double valorTotalComGarcom = valorSelecionado;
                    
                    if (!comandaAtual.garcomRetirado) {
                      // Garçom é 10% apenas do valor base (itens selecionados)
                      valorGarcomSelecionado = valorBaseSelecionado * 0.10;
                      // Valor total com garçom
                      valorTotalComGarcom = valorSelecionado + valorGarcomSelecionado;
                    }
                    
                    // Mostrar tela de pagamento do PDV (até 2 formas)
                    // Passar o valor total com garçom e o valor base para cálculo correto
                    final pagamentos = await _mostrarTelaPagamentoPDV(
                      context,
                      valorTotalComGarcom,
                      pessoaPagouController.text.trim(),
                      mesaComanda: comandaAtual,
                      valorBase: valorBaseSelecionado, // Passar o valor base (sem garçom e sem couvert) para cálculo correto
                    );
                    
                    if (pagamentos != null && pagamentos.isNotEmpty && context.mounted) {
                      Navigator.pop(context, {
                        'itens': itensSelecionados.toList(),
                        'valor': valorTotalComGarcom, // Retornar o valor total com garçom para validação correta
                        'valorBase': valorSelecionado, // Valor sem garçom (para referência)
                        'pagamentos': pagamentos,
                        'pessoaPagou': pessoaPagouController.text.trim(),
                        'couvertSelecionado': quantidadePessoasCouvertSelecionada > 0,
                        'valorCouvert': valorCouvertSelecionado,
                        'quantidadePessoasCouvert': quantidadePessoasCouvertSelecionada,
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Continuar'),
                ),
            ],
          );
        },
      ),
    );

    if (resultado == null) return;

    final itensIds = resultado['itens'] as List<String>;
    final pagamentos = resultado['pagamentos'] as List<Map<String, dynamic>>?;
    final pessoaPagou = resultado['pessoaPagou'] as String?;
    final couvertSelecionadoResult = resultado['couvertSelecionado'] as bool? ?? false;
    final valorCouvert = resultado['valorCouvert'] as double? ?? 0.0;

    if (pagamentos == null || pagamentos.isEmpty) {
      return;
    }

    // Processar pagamento
    try {
      // Recarregar dados atualizados
      final comandaAtual = dataService.mesasComandas.firstWhere(
        (c) => c.id == comanda.id,
        orElse: () => comanda,
      );
      
      // Criar registros de pagamento
      final registrosPagamento = pagamentos.map((pagamentoData) {
        String observacaoPagamento = 'Pagamento parcial';
        if (itensIds.isNotEmpty && couvertSelecionadoResult) {
          observacaoPagamento = '${itensIds.length} item(ns) + Couvert';
        } else if (itensIds.isNotEmpty) {
          observacaoPagamento = '${itensIds.length} item(ns)';
        } else if (couvertSelecionadoResult) {
          observacaoPagamento = 'Couvert Artístico';
        }
        
        return RegistroPagamento(
          id: uuid.v4(),
          valor: pagamentoData['valor'] as double,
          dataPagamento: DateTime.now(),
          formaPagamento: (pagamentoData['tipo'] as TipoPagamento).nome,
          observacao: observacaoPagamento + (pagamentoData['observacao'] != null ? ' - ${pagamentoData['observacao']}' : ''),
          itensPagos: itensIds,
          pessoaPagou: pessoaPagou,
        );
      }).toList();

      // Adicionar itens aos pagos
      final novosItensPagos = [...comandaAtual.itensPagos, ...itensIds];

      // Atualizar histórico de pagamentos
      final novoHistorico = [...comandaAtual.historicoPagamentos, ...registrosPagamento];

      // Verificar se o garçom foi retirado (vem do resultado do pagamento)
      bool garcomFoiRetirado = false;
      if (pagamentos.isNotEmpty) {
        final primeiroPagamento = pagamentos.first;
        garcomFoiRetirado = primeiroPagamento['garcomRetirado'] as bool? ?? false;
      }

      // Atualizar couvert pago se foi selecionado
      double novoCouvertPago = comandaAtual.couvertPago;
      if (couvertSelecionadoResult && valorCouvert > 0) {
        novoCouvertPago = (comandaAtual.couvertPago + valorCouvert).clamp(0.0, comandaAtual.valorCouvertCalculado);
      }

      // Atualizar comanda
      final comandaAtualizada = comandaAtual.copyWith(
        itensPagos: novosItensPagos,
        historicoPagamentos: novoHistorico,
        couvertPago: novoCouvertPago,
        garcomRetirado: garcomFoiRetirado || comandaAtual.garcomRetirado,
      );
      await dataService.updateMesaComanda(comandaAtualizada);

      // Verificar se está totalmente paga
      final novoTotalPago = comandaAtualizada.totalPago;
      final novoTotal = comandaAtualizada.totalCalculado;
      final estaPago = novoTotalPago >= novoTotal - 0.01;
      
      if (estaPago) {
        // Criar venda balcão e pedido antes de limpar a comanda
        final todosItensVenda = <ItemVendaBalcao>[];
        for (final item in comandaAtualizada.itens) {
          if (item.status != StatusItem.cancelado) {
            todosItensVenda.add(ItemVendaBalcao(
              id: item.itemId,
              nome: item.nome,
              precoUnitario: item.preco,
              quantidade: item.quantidade.toDouble(),
              isServico: item.isServico,
            ));
          }
        }
        
        // Converter todos os pagamentos da comanda em PagamentoPedido
        // para preservar TODAS as formas de pagamento no histórico (split/parcial)
        final pagamentosVenda = <PagamentoPedido>[];
        TipoPagamento _parseForma(String? f) {
          final lower = f?.toLowerCase() ?? '';
          if (lower.contains('pix')) return TipoPagamento.pix;
          if (lower.contains('dinheiro')) return TipoPagamento.dinheiro;
          if (lower.contains('débito') || lower.contains('debito')) return TipoPagamento.cartaoDebito;
          if (lower.contains('crédito') || lower.contains('credito') || lower.contains('cart')) return TipoPagamento.cartaoCredito;
          if (lower.contains('boleto')) return TipoPagamento.boleto;
          if (lower.contains('crediário') || lower.contains('crediario')) return TipoPagamento.crediario;
          if (lower.contains('fiado')) return TipoPagamento.fiado;
          return TipoPagamento.outro;
        }
        for (final rp in comandaAtualizada.historicoPagamentos) {
          pagamentosVenda.add(PagamentoPedido(
            id: rp.id,
            tipo: _parseForma(rp.formaPagamento),
            valor: rp.valor,
            recebido: true,
            dataRecebimento: rp.dataPagamento,
            observacao: rp.observacao,
          ));
        }
        if (pagamentosVenda.isEmpty && pagamentos.isNotEmpty) {
          for (final p in pagamentos) {
            pagamentosVenda.add(PagamentoPedido(
              id: uuid.v4(),
              tipo: p['tipo'] as TipoPagamento,
              valor: p['valor'] as double,
              recebido: true,
              dataRecebimento: DateTime.now(),
            ));
          }
        }

        final numeroVenda = dataService.getProximoNumeroVenda();
        final vendaId = uuid.v4();
        
        final vendaBalcao = VendaBalcao(
          id: vendaId,
          numero: numeroVenda,
          dataVenda: DateTime.now(),
          clienteId: comandaAtualizada.clienteId,
          clienteNome: comandaAtualizada.clienteNome ?? '${comandaAtualizada.numero}',
          itens: todosItensVenda,
          tipoPagamento: pagamentos.first['tipo'] as TipoPagamento,
          pagamentos: pagamentosVenda,
          valorTotal: novoTotal,
          valorRecebido: novoTotalPago,
          troco: null,
          observacoes: 'Originada da Comanda ${comandaAtualizada.numero}',
          origem: 'Mesa/Comanda',
        );

        final pedidoHistorico = Pedido(
          id: vendaId,
          numero: numeroVenda,
          dataPedido: DateTime.now(),
          clienteId: comandaAtualizada.clienteId,
          clienteNome: comandaAtualizada.clienteNome ?? '${comandaAtualizada.numero}',
          produtos: comandaAtualizada.itens.map((i) => ItemPedido(
            id: uuid.v4(),
            nome: i.nome,
            quantidade: i.quantidade,
            preco: i.preco,
          )).toList(),
          servicos: [],
          total: novoTotal,
          status: 'Pago',
          pagamentos: [],
          observacoes: 'Originada da Comanda ${comandaAtualizada.numero}',
          origem: 'Mesa/Comanda',
        );

        await dataService.addPedido(pedidoHistorico);
        await dataService.addVendaBalcao(vendaBalcao);

        final bool isComanda = comandaAtualizada.tipo == TipoControle.comanda;

        if (isComanda) {
          // Se for comanda, definimos status como Fechada (mantendo os itens intactos para histórico)
          final comandaFechada = comandaAtualizada.copyWith(
            status: 'Fechada',
            dataFechamento: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await dataService.updateMesaComanda(comandaFechada);
        } else {
          // Se for mesa física, limpamos os itens e mantemos aberta/disponível
          final mesaLiberada = comandaAtualizada.copyWith(
            status: 'Aberta', 
            dataFechamento: null,
            dataAbertura: DateTime.now(), // Nova data de abertura para novo uso
            itens: [], // Limpar itens
            itensPagos: [],
            historicoPagamentos: [],
            valorCouvert: null,
            quantidadePessoasCouvert: null,
            valorCouvertPorPessoa: null,
            valorGarcom: null,
            garcomRetirado: false,
            clienteNome: null,
            clienteId: null,
            observacao: null, // Limpar observações
            updatedAt: DateTime.now(),
          );
          await dataService.updateMesaComanda(mesaLiberada);
        }
        
        // IMPORTANTE: Não verificar nem fechar a mesa aqui
        // A mesa só deve ser fechada quando o usuário clicar no botão "Receber" da mesa
        // Mesmo que a mesa toda esteja paga, não fechar automaticamente
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Comanda ${comanda.numero} totalmente paga e fechada!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
            _comandasExpandidas.remove(comanda.id);
            // Recarregar mesa atualizada se houver uma selecionada
            if (_mesaSelecionada != null && comanda.mesaId == _mesaSelecionada!.id) {
              final mesaRecarregada = dataService.mesasComandas.firstWhere(
                (m) => m.id == _mesaSelecionada!.id,
                orElse: () => _mesaSelecionada!,
              );
              _mesaSelecionada = mesaRecarregada;
            }
          });
        }
      } else {
        // Pagamento parcial
        if (context.mounted) {
          final valorTotalPago = registrosPagamento.fold<double>(0.0, (sum, p) => sum + p.valor);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Pagamento de ${formatoMoeda.format(valorTotalPago)} registrado na comanda ${comanda.numero}.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          setState(() {
            // Recarregar mesa atualizada se houver uma selecionada
            if (_mesaSelecionada != null && comanda.mesaId == _mesaSelecionada!.id) {
              final mesaRecarregada = dataService.mesasComandas.firstWhere(
                (m) => m.id == _mesaSelecionada!.id,
                orElse: () => _mesaSelecionada!,
              );
              _mesaSelecionada = mesaRecarregada;
            }
          });
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar pagamento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<MesaComanda?> _abrirNovaMesa(BuildContext context, DataService dataService) async {
    final numeroController = TextEditingController();
    final clienteController = TextEditingController();
    final observacaoController = TextEditingController();
    final quantidadePessoasController = TextEditingController();
    final valorPorPessoaController = TextEditingController();
    
    // Calcular próximo número sequencial baseado na última mesa
    final mesasExistentes = dataService.mesasComandas
        .where((m) => m.tipo == TipoControle.mesa)
        .toList();
    
    int proximoNumero = 1;
    if (mesasExistentes.isNotEmpty) {
      // Tentar extrair números das mesas existentes
      final numeros = mesasExistentes.map((m) {
        // Tentar extrair número do formato "MESA1", "1", "MESA-1", etc.
              final match = RegExp(r'\d+').firstMatch(m.numero);
              return match != null ? int.tryParse(match.group(0) ?? '0') ?? 0 : 0;
      }).toList();
      
      if (numeros.isNotEmpty) {
        final maiorNumero = numeros.reduce((a, b) => a > b ? a : b);
        proximoNumero = maiorNumero + 1;
      }
    }
    
    // Preencher com o próximo número sequencial, mas permitir edição
    numeroController.text = proximoNumero.toString();

    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Validar número em tempo real
          final numeroDigitado = numeroController.text.trim();
          final numeroExiste = numeroDigitado.isNotEmpty && 
              dataService.mesasComandas.any(
                (m) => m.numero == numeroDigitado,
              );
          
          // Calcular valor total do couvert em tempo real
          final quantidadePessoas = int.tryParse(quantidadePessoasController.text.trim()) ?? 0;
          final valorPorPessoa = double.tryParse(valorPorPessoaController.text.trim().replaceAll(',', '.')) ?? 0.0;
          final valorTotalCouvert = quantidadePessoas > 0 && valorPorPessoa > 0 
              ? quantidadePessoas * valorPorPessoa 
              : 0.0;
          
          return AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        insetPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        title: const Text(
          'Nova Mesa',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numeroController,
                    onChanged: (value) => setDialogState(() {}),
                    decoration: InputDecoration(
                  labelText: 'Número da Mesa',
                      labelStyle: const TextStyle(color: Colors.grey),
                      hintText: 'Digite o número da mesa',
                      hintStyle: const TextStyle(color: Colors.grey),
                      errorText: numeroExiste ? 'Este número já está em uso!' : null,
                      errorStyle: const TextStyle(color: Colors.red),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: numeroExiste ? Colors.red : Colors.grey,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: numeroExiste ? Colors.red : Colors.orange,
                        ),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: clienteController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Cliente (opcional)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.orange),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 24),
              // Seção de Couvert
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.music_note, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Couvert Artístico (opcional)',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: quantidadePessoasController,
                      keyboardType: TextInputType.number,
                      onChanged: (value) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Quantidade de Pessoas',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.orange),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: valorPorPessoaController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Valor por Pessoa (R\$)',
                        labelStyle: const TextStyle(color: Colors.grey),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.orange),
                        ),
                        suffixText: valorTotalCouvert > 0 
                            ? NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ').format(valorTotalCouvert)
                            : null,
                        suffixStyle: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: observacaoController,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.orange),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
                onPressed: numeroExiste || numeroController.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Criar'),
          ),
        ],
          );
        },
      ),
    );

    if (resultado == true) {
      // Verificar se número já existe (em mesas ou comandas)
      final numeroExiste = dataService.mesasComandas.any(
        (m) => m.numero == numeroController.text.trim(),
      );

      if (numeroExiste) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('O número ${numeroController.text.trim()} já está em uso por uma mesa ou comanda!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }

      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        final usuarioLogado = authService.usuarioAtual?.nome ?? 'Sistema';
        
        // Obter valores do couvert
        final quantidadePessoas = quantidadePessoasController.text.trim().isEmpty
            ? null
            : int.tryParse(quantidadePessoasController.text.trim());
        final valorPorPessoa = valorPorPessoaController.text.trim().isEmpty
            ? null
            : double.tryParse(valorPorPessoaController.text.trim().replaceAll(',', '.'));
        
        final novaMesa = MesaComanda(
          id: uuid.v4(),
          tipo: TipoControle.mesa,
          numero: numeroController.text.trim(),
          clienteNome: clienteController.text.trim().isNotEmpty
              ? clienteController.text.trim()
              : null,
          observacao: observacaoController.text.trim().isNotEmpty
              ? observacaoController.text.trim()
              : null,
          status: 'Aberta',
          usuarioCriou: usuarioLogado,
          quantidadePessoasCouvert: quantidadePessoas,
          valorCouvertPorPessoa: valorPorPessoa,
        );

        await dataService.addMesaComanda(novaMesa);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Mesa ${novaMesa.numero} criada com sucesso!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          setState(() {
            _mesaSelecionada = novaMesa;
          });
        }
        return novaMesa;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao criar mesa: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    return null;
  }

  Future<void> _adicionarPessoasCouvert(BuildContext context, MesaComanda mesa, DataService dataService) async {
    final quantidadeAdicionalController = TextEditingController();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final quantidadeAdicional = int.tryParse(quantidadeAdicionalController.text.trim()) ?? 0;
          final quantidadeAtual = mesa.quantidadePessoasCouvert ?? 0;
          final valorPorPessoa = mesa.valorCouvertPorPessoa ?? 0.0;
          final novaQuantidade = quantidadeAtual + quantidadeAdicional;
          final novoTotal = novaQuantidade * valorPorPessoa;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            insetPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            title: const Row(
              children: [
                Icon(Icons.music_note, color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Text(
                  'Adicionar Pessoas ao Couvert',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            content: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Couvert Atual:',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${quantidadeAtual} pessoa(s) × ${formatoMoeda.format(valorPorPessoa)} = ${formatoMoeda.format(mesa.valorCouvertCalculado)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: quantidadeAdicionalController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    onChanged: (value) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade de Pessoas a Adicionar',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (quantidadeAdicional > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Novo Couvert:',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$novaQuantidade pessoa(s) × ${formatoMoeda.format(valorPorPessoa)} = ${formatoMoeda.format(novoTotal)}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: quantidadeAdicional <= 0
                    ? null
                    : () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Adicionar'),
              ),
            ],
          );
        },
      ),
    );

    if (resultado == true) {
      final quantidadeAdicional = int.tryParse(quantidadeAdicionalController.text.trim()) ?? 0;
      if (quantidadeAdicional > 0) {
        try {
          final quantidadeAtual = mesa.quantidadePessoasCouvert ?? 0;
          final novaQuantidade = quantidadeAtual + quantidadeAdicional;
          final valorPorPessoa = mesa.valorCouvertPorPessoa ?? 0.0;

          final mesaAtualizada = mesa.copyWith(
            quantidadePessoasCouvert: novaQuantidade,
          );

          await dataService.updateMesaComanda(mesaAtualizada);

          if (context.mounted) {
            setState(() {
              _mesaSelecionada = mesaAtualizada;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$quantidadeAdicional pessoa(s) adicionada(s) ao couvert!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao adicionar pessoas: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _editarCouvert(BuildContext context, MesaComanda mesa, DataService dataService) async {
    final quantidadePessoasController = TextEditingController(
      text: mesa.quantidadePessoasCouvert?.toString() ?? '',
    );
    final valorPorPessoaController = TextEditingController(
      text: mesa.valorCouvertPorPessoa != null
          ? mesa.valorCouvertPorPessoa!.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Calcular valor total do couvert em tempo real
          final quantidadePessoas = int.tryParse(quantidadePessoasController.text.trim()) ?? 0;
          final valorPorPessoa = double.tryParse(valorPorPessoaController.text.trim().replaceAll(',', '.')) ?? 0.0;
          final valorTotalCouvert = quantidadePessoas > 0 && valorPorPessoa > 0 
              ? quantidadePessoas * valorPorPessoa 
              : 0.0;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            insetPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            title: const Row(
              children: [
                Icon(Icons.music_note, color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Text(
                  'Editar Couvert',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            content: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: quantidadePessoasController,
                    keyboardType: TextInputType.number,
                    onChanged: (value) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade de Pessoas',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: valorPorPessoaController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Valor por Pessoa (R\$)',
                      labelStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.orange),
                      ),
                      suffixText: valorTotalCouvert > 0 
                          ? formatoMoeda.format(valorTotalCouvert)
                          : null,
                      suffixStyle: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (valorTotalCouvert > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total do Couvert:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            formatoMoeda.format(valorTotalCouvert),
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final quantidadePessoasFinal = quantidadePessoasController.text.trim().isEmpty
                      ? null
                      : int.tryParse(quantidadePessoasController.text.trim());
                  final valorPorPessoaFinal = valorPorPessoaController.text.trim().isEmpty
                      ? null
                      : double.tryParse(valorPorPessoaController.text.trim().replaceAll(',', '.'));

                  // Validar se pelo menos um campo está preenchido
                  if (quantidadePessoasFinal == null && valorPorPessoaFinal == null) {
                    // Se ambos estiverem vazios, remover o couvert
                    try {
                      final mesaAtualizada = mesa.copyWith(
                        quantidadePessoasCouvert: null,
                        valorCouvertPorPessoa: null,
                      );
                      await dataService.updateMesaComanda(mesaAtualizada);
                      if (context.mounted) {
                        Navigator.pop(context);
                        setState(() {
                          _mesaSelecionada = mesaAtualizada;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Couvert removido com sucesso!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro ao atualizar couvert: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                    return;
                  }

                  // Validar que ambos os campos devem estar preenchidos
                  if (quantidadePessoasFinal == null || valorPorPessoaFinal == null || quantidadePessoasFinal <= 0 || valorPorPessoaFinal <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Informe a quantidade de pessoas e o valor por pessoa'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  try {
                    final mesaAtualizada = mesa.copyWith(
                      quantidadePessoasCouvert: quantidadePessoasFinal,
                      valorCouvertPorPessoa: valorPorPessoaFinal,
                    );
                    await dataService.updateMesaComanda(mesaAtualizada);
                    if (context.mounted) {
                      Navigator.pop(context);
                      setState(() {
                        _mesaSelecionada = mesaAtualizada;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Couvert atualizado: $quantidadePessoasFinal pessoa(s) × ${formatoMoeda.format(valorPorPessoaFinal)}'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao atualizar couvert: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _adicionarItensMesa(MesaComanda mesa, DataService dataService) async {
    // Verificar se é uma mesa ou comanda disponível (sem itens, totalmente paga ou valor zero)
    bool estaDisponivel = false;
    
    if (mesa.tipo == TipoControle.mesa) {
      final comandasDaMesa = dataService.mesasComandas
          .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesa.id)
          .toList();
      
      double totalGeralMesa = mesa.totalCalculado;
      double totalGeralComandas = 0.0;
      for (final comanda in comandasDaMesa) {
        totalGeralComandas += comanda.totalCalculado;
      }
      final totalGeral = totalGeralMesa + totalGeralComandas;
      
      double totalPagoMesa = mesa.totalPago;
      double totalPagoComandas = 0.0;
      for (final comanda in comandasDaMesa) {
        totalPagoComandas += comanda.totalPago;
      }
      final totalPagoGeral = totalPagoMesa + totalPagoComandas;
      final totalPendente = totalGeral - totalPagoGeral;
      estaDisponivel = totalPendente <= 0.01 && mesa.itens.isEmpty && totalGeral <= 0.01 && mesa.status != 'Aberta';
    } else {
      // Para comanda, também verificar se está "vazia", paga e se não está ativa (Aberta)
      estaDisponivel = mesa.estaTotalmentePago && mesa.itens.isEmpty && mesa.totalCalculado <= 0.01 && mesa.status != 'Aberta';
    }
    
    if (estaDisponivel) {
      // Quando a mesa está disponível (zerada), estamos iniciando uma NOVA ocupação (sessão).
      // Portanto, devemos limpar os nomes antigos que podem ter ficado no registro.
      // Manter apenas se não houver palavras-chave de união e o usuário preferir (mas por padrão limpar união).
      String obsInicial = '';
      if (mesa.observacao != null) {
        final obsUpper = mesa.observacao!.toUpperCase();
        if (!obsUpper.contains('UNIÃO') && !obsUpper.contains('MESA UNIDA')) {
          obsInicial = mesa.observacao!;
        }
      }

      final quemAbriuController = TextEditingController(text: ''); // Limpar para nova sessão
      final clienteController = TextEditingController(text: ''); // Limpar para nova sessão
      final observacaoController = TextEditingController(text: obsInicial);
      final numeroController = TextEditingController(text: mesa.numero);
      final quantidadePessoasController = TextEditingController();
      final valorPorPessoaController = TextEditingController();
      
      final bool isComanda = mesa.tipo == TipoControle.comanda;
      
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              insetPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              title: Text(
                isComanda ? 'Nova Comanda' : 'Informações da Mesa',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isComanda) ...[
                      TextField(
                        controller: numeroController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Número da Mesa',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.orange),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: quemAbriuController,
                        decoration: const InputDecoration(
                          labelText: 'Nome de quem abriu a mesa (opcional)',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.orange),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: clienteController,
                        decoration: const InputDecoration(
                          labelText: 'Nome do Cliente (opcional)',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.orange),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: observacaoController,
                        decoration: const InputDecoration(
                          labelText: 'Observação (opcional)',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.orange),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.music_note, color: Colors.orange, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Couvert Artístico (opcional)',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: quantidadePessoasController,
                              keyboardType: TextInputType.number,
                              onChanged: (value) => setDialogState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Quantidade de Pessoas',
                                labelStyle: TextStyle(color: Colors.grey),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.orange),
                                ),
                              ),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: valorPorPessoaController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (value) => setDialogState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Valor por Pessoa (R\$)',
                                labelStyle: TextStyle(color: Colors.grey),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.orange),
                                ),
                              ),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: numeroController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Número da Comanda',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.purple),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: clienteController,
                        decoration: const InputDecoration(
                          labelText: 'Cliente (opcional)',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.purple),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: observacaoController,
                        decoration: const InputDecoration(
                          labelText: 'Observação (opcional)',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.purple),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.purple.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.music_note, color: Colors.purple, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Couvert Artístico (opcional)',
                                  style: TextStyle(
                                    color: Colors.purple,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: quantidadePessoasController,
                              keyboardType: TextInputType.number,
                              onChanged: (value) => setDialogState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Quantidade de Pessoas',
                                labelStyle: TextStyle(color: Colors.grey),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.purple),
                                ),
                              ),
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: valorPorPessoaController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (value) => setDialogState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Valor por Pessoa (R\$)',
                                labelStyle: TextStyle(color: Colors.grey),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: Colors.purple),
                                ),
                              ),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: isComanda ? Colors.purple : Colors.orange),
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        ),
      );
      
      if (confirmar != true) {
        return; // Usuário cancelou
      }
      
      // Atualizar mesa com as informações
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        final usuarioLogado = authService.usuarioAtual?.nome ?? 'Sistema';

        final qtePessoas = quantidadePessoasController.text.trim().isEmpty ? null : int.tryParse(quantidadePessoasController.text.trim());
        final vlrPessoa = valorPorPessoaController.text.trim().isEmpty ? null : double.tryParse(valorPorPessoaController.text.trim().replaceAll(',', '.'));

        final mesaAtualizada = mesa.copyWith(
          clienteNome: clienteController.text.trim().isEmpty ? null : clienteController.text.trim(),
          usuarioCriou: isComanda ? usuarioLogado : (quemAbriuController.text.trim().isEmpty ? null : quemAbriuController.text.trim()),
          observacao: observacaoController.text.trim().isEmpty ? null : observacaoController.text.trim(),
          quantidadePessoasCouvert: qtePessoas,
          valorCouvertPorPessoa: vlrPessoa,
          dataAbertura: DateTime.now(),
          status: 'Aberta',
        );
        
        await dataService.updateMesaComanda(mesaAtualizada);
        
        // Atualizar referência da mesa para usar a versão atualizada
        final mesaAtualizadaCompleta = dataService.mesasComandas.firstWhere(
          (m) => m.id == mesa.id,
          orElse: () => mesaAtualizada,
        );
        
        // Continuar com o processo de adicionar itens usando a mesa atualizada
        mesa = mesaAtualizadaCompleta;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao atualizar informações: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    
    final buscaController = TextEditingController();
    final produtosSelecionados = <String, Map<String, dynamic>>{};
    String termoBusca = '';
    
    // Verificar se é uma comanda vinculada à mesa
    final bool eComandaVinculada = mesa.tipo == TipoControle.comanda && mesa.mesaId != null;
    
    // Se for comanda vinculada, adicionar diretamente nela
    final MesaComanda destinoFinal = mesa;
    final bool adicionarNaComanda = eComandaVinculada;
    
    // Buscar comandas da mesa (apenas se for mesa, não comanda)
    final comandasDaMesa = !eComandaVinculada
        ? dataService.mesasComandas
            .where((c) => c.tipo == TipoControle.comanda && 
                          c.mesaId == mesa.id && 
                          c.status == 'Aberta')
            .toList()
        : <MesaComanda>[];
    
    // Variáveis para o seletor (apenas se não for comanda vinculada)
    String destino = 'mesa'; // 'mesa' ou 'comanda'
    MesaComanda? comandaSelecionada;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final produtosFiltrados = termoBusca.isEmpty
              ? dataService.produtos
              : dataService.produtos.where((p) {
                  final buscaLower = termoBusca.toLowerCase();
                  return p.nome.toLowerCase().contains(buscaLower) ||
                      (p.codigo != null && p.codigo!.toLowerCase().contains(buscaLower));
                }).toList();

          // Determinar destino final para exibição
          final destinoFinalExibicao = (adicionarNaComanda || mesa.tipo == TipoControle.comanda)
              ? 'Comanda ${mesa.numero}'
              : (destino == 'comanda' && comandaSelecionada != null)
                  ? 'Comanda ${comandaSelecionada!.numero}'
                  : 'Mesa ${mesa.numero}';
          
          final corDestino = (adicionarNaComanda || mesa.tipo == TipoControle.comanda || (destino == 'comanda' && comandaSelecionada != null))
              ? Colors.purple
              : Colors.orange;
          
          final iconeDestino = (adicionarNaComanda || mesa.tipo == TipoControle.comanda || (destino == 'comanda' && comandaSelecionada != null))
              ? Icons.receipt_long
              : Icons.table_restaurant;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
              'Adicionar Itens',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // Banner destacado mostrando o destino
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: corDestino.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: corDestino, width: 2),
                  ),
                  child: Row(
                    children: [
                      Icon(iconeDestino, color: corDestino, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LANÇANDO EM:',
                              style: TextStyle(
                                color: corDestino,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              destinoFinalExibicao,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // Seletor de destino (Mesa ou Comanda) - apenas se não for comanda vinculada
                  if (!adicionarNaComanda && comandasDaMesa.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Onde deseja adicionar os itens?',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    destino = 'mesa';
                                    comandaSelecionada = null;
                                    setDialogState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: destino == 'mesa' 
                                          ? Colors.orange.withOpacity(0.3)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: destino == 'mesa' 
                                            ? Colors.orange 
                                            : Colors.grey.withOpacity(0.3),
                                        width: destino == 'mesa' ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.table_restaurant,
                                          color: destino == 'mesa' ? Colors.orange : Colors.grey,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Mesa ${mesa.numero}',
                                          style: TextStyle(
                                            color: destino == 'mesa' ? Colors.white : Colors.grey,
                                            fontSize: 14,
                                            fontWeight: destino == 'mesa' ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        if (destino == 'mesa')
                                          const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Icon(Icons.check_circle, color: Colors.orange, size: 20),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    destino = 'comanda';
                                    setDialogState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: destino == 'comanda' 
                                          ? Colors.purple.withOpacity(0.3)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: destino == 'comanda' 
                                            ? Colors.purple 
                                            : Colors.grey.withOpacity(0.3),
                                        width: destino == 'comanda' ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.receipt_long,
                                          color: destino == 'comanda' ? Colors.purple : Colors.grey,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Comanda',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (destino == 'comanda')
                                          const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Icon(Icons.check_circle, color: Colors.purple, size: 20),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (destino == 'comanda') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<MesaComanda>(
                              value: comandaSelecionada,
                              decoration: InputDecoration(
                                labelText: 'Selecione a Comanda',
                                labelStyle: const TextStyle(color: Colors.grey),
                                hintText: 'Escolha uma comanda...',
                                hintStyle: const TextStyle(color: Colors.grey),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: comandaSelecionada == null ? Colors.red : Colors.purple,
                                    width: comandaSelecionada == null ? 2 : 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.purple, width: 2),
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.1),
                              ),
                              dropdownColor: const Color(0xFF2A2A3E),
                              style: const TextStyle(color: Colors.white),
                              items: comandasDaMesa.map((comanda) {
                                return DropdownMenuItem<MesaComanda>(
                                  value: comanda,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.receipt_long, color: Colors.purple, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${comanda.numero}',
                                        style: const TextStyle(color: Colors.white, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                comandaSelecionada = value;
                                setDialogState(() {});
                              },
                            ),
                            if (comandaSelecionada == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '⚠ Selecione uma comanda para continuar',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Campo de busca
                  TextField(
                    controller: buscaController,
                    decoration: InputDecoration(
                      hintText: 'Buscar produto...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.orange),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    onChanged: (value) {
                      termoBusca = value;
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Lista de produtos
                  Container(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: produtosFiltrados.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Text(
                                'Nenhum produto encontrado',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: produtosFiltrados.length,
                            itemBuilder: (context, index) {
                              final produto = produtosFiltrados[index];
                              final isSelecionado = produtosSelecionados.containsKey(produto.id);
                              final itemSelecionado = produtosSelecionados[produto.id];
                              final quantidade = itemSelecionado?['quantidade'] as int? ?? 1;
                              final categoria = itemSelecionado?['categoria'] as String? ?? 'outros';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: isSelecionado
                                    ? Colors.orange.withOpacity(0.2)
                                    : const Color(0xFF2A2A3E),
                                child: ListTile(
                                  title: Text(
                                    produto.nome,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    'R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(produto.precoAtual)}',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                  trailing: isSelecionado
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                                              onPressed: () {
                                                if (quantidade > 1) {
                                                  produtosSelecionados[produto.id] = {
                                                    'produto': produto,
                                                    'quantidade': quantidade - 1,
                                                    'categoria': categoria,
                                                  };
                                                } else {
                                                  produtosSelecionados.remove(produto.id);
                                                }
                                                setDialogState(() {});
                                              },
                                            ),
                                            Text(
                                              '$quantidade',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle, color: Colors.green),
                                              onPressed: () {
                                                produtosSelecionados[produto.id] = {
                                                  ...produtosSelecionados[produto.id]!,
                                                  'quantidade': quantidade + 1,
                                                };
                                                setDialogState(() {});
                                              },
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                itemSelecionado!['observacao'] != null && (itemSelecionado['observacao'] as String).isNotEmpty
                                                    ? Icons.comment
                                                    : Icons.add_comment_outlined,
                                                color: itemSelecionado['observacao'] != null && (itemSelecionado['observacao'] as String).isNotEmpty
                                                    ? Colors.orange
                                                    : Colors.grey,
                                                size: 20,
                                              ),
                                              onPressed: () async {
                                                final obsController = TextEditingController(text: itemSelecionado['observacao'] ?? '');
                                                final result = await showDialog<String>(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    backgroundColor: const Color(0xFF1E1E2E),
                                                    title: Text('Observação: ${produto.nome}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                                                    content: TextField(
                                                      controller: obsController,
                                                      autofocus: true,
                                                      maxLines: 2,
                                                      style: const TextStyle(color: Colors.white),
                                                      decoration: const InputDecoration(
                                                        hintText: 'Ex: Sem gelo...',
                                                        hintStyle: TextStyle(color: Colors.grey),
                                                      ),
                                                    ),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                                                      TextButton(onPressed: () => Navigator.pop(context, obsController.text), child: const Text('Salvar')),
                                                    ],
                                                  ),
                                                );
                                                if (result != null) {
                                                  setDialogState(() {
                                                    produtosSelecionados[produto.id] = {
                                                      ...itemSelecionado,
                                                      'observacao': result.trim().isEmpty ? null : result.trim(),
                                                    };
                                                  });
                                                }
                                              },
                                            ),
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert, color: Colors.white),
                                              onSelected: (value) {
                                                produtosSelecionados[produto.id] = {
                                                  'produto': produto,
                                                  'quantidade': quantidade,
                                                  'categoria': value,
                                                };
                                                setDialogState(() {});
                                              },
                                              itemBuilder: (context) => [
                                                PopupMenuItem(
                                                  value: 'outros',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        categoria == 'outros' ? Icons.check : null,
                                                        color: Colors.white,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Text('Outros'),
                                                    ],
                                                  ),
                                                ),
                                                // Departamentos cadastrados (dinâmicos)
                                                ...dataService.departamentos.map((dep) {
                                                  final ativo = categoria == dep.nome;
                                                  return PopupMenuItem(
                                                    value: dep.nome,
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          ativo ? Icons.check : null,
                                                          color: Colors.white,
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(dep.nome, style: const TextStyle(color: Colors.white)),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          ],
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.add_circle, color: Colors.green),
                                          onPressed: () {
                                            final categoriaInicial = produto.departamentoId != null && produto.departamentoId!.isNotEmpty
                                                ? (dataService.nomeDepartamento(produto.departamentoId).isNotEmpty
                                                    ? dataService.nomeDepartamento(produto.departamentoId)
                                                    : (produto.paraCozinha == true ? 'cozinha' : (produto.paraBar == true ? 'bar' : 'outros')))
                                                : (produto.paraCozinha == true ? 'cozinha' : (produto.paraBar == true ? 'bar' : 'outros'));
                                            if (produto.temAdicionais) {
                                              _exibirDialogoAdicionaisWaiter(context, produto, (selecionados) {
                                                setDialogState(() {
                                                  produtosSelecionados[produto.id] = {
                                                    'produto': produto,
                                                    'quantidade': 1,
                                                    'categoria': categoriaInicial,
                                                    'observacao': produto.observacaoPadrao,
                                                    'adicionais': selecionados,
                                                  };
                                                });
                                              });
                                            } else {
                                              produtosSelecionados[produto.id] = {
                                                'produto': produto,
                                                'quantidade': 1,
                                                'categoria': categoriaInicial,
                                                'observacao': produto.observacaoPadrao,
                                                'adicionais': <AdicionalProduto>[],
                                              };
                                              setDialogState(() {});
                                            }
                                          },
                                        ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Resumo dos produtos selecionados com seletor de departamento
                  if (produtosSelecionados.isNotEmpty) ...[
                    const Divider(color: Colors.grey),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Produtos selecionados:',
                            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ...produtosSelecionados.entries.map((entry) {
                            final item = entry.value;
                            final produto = item['produto'] as Produto;
                            final quantidade = item['quantidade'] as int;
                            final categoria = item['categoria'] as String? ?? 'outros'; // 'cozinha', 'bar', 'outros'
                            final List<AdicionalProduto> adicionais = (item['adicionais'] as List?)?.cast<AdicionalProduto>() ?? [];
                            final total = (produto.precoAtual + adicionais.fold(0.0, (sum, a) => sum + a.preco)) * quantidade;
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$quantidade x ${produto.nome}',
                                          style: const TextStyle(color: Colors.white, fontSize: 12),
                                        ),
                                      ),
                                      Text(
                                        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(total),
                                        style: const TextStyle(color: Colors.green, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                                                    // Seletor de categoria/departamento
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      // Departamentos cadastrados (dinâmicos)
                                      ...dataService.departamentos.map((dep) {
                                        final ativo = categoria == dep.nome;
                                        return GestureDetector(
                                          onTap: () {
                                            setDialogState(() {
                                              produtosSelecionados[entry.key] = {
                                                ...item,
                                                'categoria': dep.nome,
                                              };
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                            decoration: BoxDecoration(
                                              color: ativo
                                                  ? Colors.orange.withOpacity(0.3)
                                                  : Colors.transparent,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: ativo
                                                    ? Colors.orange
                                                    : Colors.grey.withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  dep.icone == 'local_bar'
                                                      ? Icons.local_bar
                                                      : Icons.restaurant,
                                                  size: 14,
                                                  color: ativo ? Colors.orange : Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  dep.nome,
                                                  style: TextStyle(
                                                    color: ativo ? Colors.orange : Colors.grey,
                                                    fontSize: 11,
                                                    fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                      // Opção "Outros" (sem departamento)
                                      GestureDetector(
                                        onTap: () {
                                          setDialogState(() {
                                            produtosSelecionados[entry.key] = {
                                              ...item,
                                              'categoria': 'outros',
                                            };
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                          decoration: BoxDecoration(
                                            color: categoria == 'outros'
                                                ? Colors.grey.withOpacity(0.3)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: categoria == 'outros'
                                                  ? Colors.grey
                                                  : Colors.grey.withOpacity(0.3),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.inventory, size: 14, color: Colors.grey),
                                              SizedBox(width: 4),
                                              Text(
                                                'Outros',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                icon: Icon(
                  adicionarNaComanda || (destino == 'comanda' && comandaSelecionada != null)
                      ? Icons.receipt_long
                      : Icons.table_restaurant,
                ),
                label: Text(
                  'Adicionar em ${destinoFinalExibicao}',
                ),
                onPressed: produtosSelecionados.isEmpty || 
                          (!adicionarNaComanda && destino == 'comanda' && comandaSelecionada == null)
                    ? null
                    : () async {
                        // Se for comanda no seletor, validar seleção
                        if (!adicionarNaComanda && destino == 'comanda' && comandaSelecionada == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selecione uma comanda'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        try {
                          final novosItens = <ItemMesaComanda>[];

                          for (final item in produtosSelecionados.values) {
                            final produto = item['produto'] as Produto;
                             final quantidade = (item['quantidade'] as num).toDouble();
                             final categoria = item['categoria'] as String? ?? 'outros';
                             final observacao = item['observacao'] as String?;
                             final List<AdicionalProduto> adicionais = (item['adicionais'] as List?)?.cast<AdicionalProduto>() ?? [];
                            
                            // Determinar o local baseado na categoria/departamento
                            String? local;
                            if (categoria == 'cozinha') {
                              local = 'Cozinha';
                            } else if (categoria == 'bar') {
                              local = 'Bar';
                            } else if (categoria == 'outros' || categoria == null || categoria.isEmpty) {
                              local = 'Outros';
                            } else {
                              // Nome de departamento cadastrado (ex: Sobremesas)
                              local = categoria;
                            }

                            final authService = Provider.of<AuthService>(context, listen: false);
                            final usuarioLogado = authService.usuarioAtual?.nome ?? 'Sistema';

                            novosItens.add(ItemMesaComanda(
                              id: uuid.v4(),
                              itemId: produto.id,
                              nome: produto.nome,
                              quantidade: quantidade,
                              preco: produto.precoAtual,
                              isServico: false,
                              paraCozinha: categoria == 'cozinha' || local == 'Cozinha',
                              paraBar: categoria == 'bar' || local == 'Bar',
                              local: local,
                              observacao: observacao,
                              adicionais: adicionais,
                              status: StatusItem.pendente,
                              dataHora: DateTime.now(),
                              usuarioCriou: usuarioLogado,
                              acaoRealizada: 'Item lançado',
                              cobrarGarcom: produto.cobrarGarcom,
                            ));
                          }

                          // Se for comanda vinculada, adicionar diretamente nela
                          if (adicionarNaComanda) {
                            // Calcular garçom automaticamente (10% do total com couvert)
                            final totalItens = [...destinoFinal.itens, ...novosItens]
                                .where((item) => item.status != StatusItem.cancelado)
                                .fold(0.0, (sum, item) => sum + item.subtotal);
                            final totalComCouvert = totalItens + (destinoFinal.valorCouvert ?? 0.0);
                            final valorGarcomCalculado = totalComCouvert * 0.10; // 10% de garçom
                            
                            final comandaAtualizada = destinoFinal.copyWith(
                              itens: [...destinoFinal.itens, ...novosItens],
                              valorGarcom: valorGarcomCalculado > 0 ? valorGarcomCalculado : null,
                            );
                            await dataService.updateMesaComanda(comandaAtualizada);
                            
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${novosItens.length} item(ns) adicionado(s) à comanda ${destinoFinal.numero}!'),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              setState(() {
                                _mesaSelecionada = comandaAtualizada;
                              });
                            }
                          } else {
                            // Adicionar na mesa
                            // Calcular garçom automaticamente (10% do total com couvert)
                            final totalItens = [...mesa.itens, ...novosItens]
                                .where((item) => item.status != StatusItem.cancelado)
                                .fold(0.0, (sum, item) => sum + item.subtotal);
                            final totalComCouvert = totalItens + (mesa.valorCouvert ?? 0.0);
                            final valorGarcomCalculado = totalComCouvert * 0.10; // 10% de garçom

                          final mesaAtualizada = mesa.copyWith(
                            itens: [...mesa.itens, ...novosItens],
                              valorGarcom: valorGarcomCalculado > 0 ? valorGarcomCalculado : null,
                          );
                          await dataService.updateMesaComanda(mesaAtualizada);

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${novosItens.length} item(ns) adicionado(s) à mesa!'),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                            setState(() {
                              _mesaSelecionada = mesaAtualizada;
                            });
                            }
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao adicionar itens: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }


  /// Card de comanda
  Widget _buildCardComanda(MesaComanda comanda, DataService dataService) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    final total = comanda.totalCalculado;
    final itensPendentes = comanda.itensPendentes.length;
    final itensEmPreparo = comanda.itensEmPreparo.length;
    final itensProntos = comanda.itensProntos.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1E1E2E),
      child: InkWell(
        onTap: () {
          setState(() {
            _mesaSelecionada = _mesaSelecionada == comanda ? null : comanda;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long, color: Colors.purple, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comanda ${comanda.numero}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (comanda.clienteNome != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Cliente: ${comanda.clienteNome}',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                        Text(
                          'Aberta: ${formatoData.format(comanda.dataAbertura)}',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatoMoeda.format(total),
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${comanda.itens.length} item(s)',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              if (itensPendentes > 0 || itensEmPreparo > 0 || itensProntos > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (itensPendentes > 0)
                      _buildStatusBadge('Pendentes', itensPendentes, Colors.red),
                    if (itensEmPreparo > 0) ...[
                      const SizedBox(width: 8),
                      _buildStatusBadge('Em Preparo', itensEmPreparo, Colors.orange),
                    ],
                    if (itensProntos > 0) ...[
                      const SizedBox(width: 8),
                      _buildStatusBadge('Prontos', itensProntos, Colors.green),
                    ],
                  ],
                ),
              ],
              if (_mesaSelecionada == comanda) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                ...comanda.itens.map((item) => Column(
                  children: [
                    _buildItemMesa(item),
                    if (item.status != StatusItem.cancelado)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => _cancelarItem(item, comanda, dataService),
                          icon: const Icon(Icons.cancel, size: 16),
                          label: const Text('Cancelar Item'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            minimumSize: const Size(double.infinity, 36),
                          ),
                        ),
                      ),
                  ],
                )),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _adicionarItensMesa(comanda, dataService),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Adicionar Itens'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Cria uma nova comanda, vinculando-a a uma mesa física se a configuração estiver ativa
  Future<MesaComanda?> _abrirNovaComanda(BuildContext context, DataService dataService) async {
    final numeroController = TextEditingController();
    final clienteController = TextEditingController();
    final observacaoController = TextEditingController();
    final quantidadePessoasController = TextEditingController();
    final valorPorPessoaController = TextEditingController();
    
    // Gerar número automático
    final comandasExistentes = dataService.mesasComandas
        .where((m) => m.tipo == TipoControle.comanda)
        .toList();
    final ultimoNumero = comandasExistentes.isEmpty
        ? 0
        : comandasExistentes
            .map((m) {
              final match = RegExp(r'\d+').firstMatch(m.numero);
              return match != null ? int.tryParse(match.group(0) ?? '0') ?? 0 : 0;
            })
            .reduce((a, b) => a > b ? a : b);
    
    numeroController.text = 'CMD-${(ultimoNumero + 1).toString().padLeft(3, '0')}';

    // Mesas físicas abertas disponíveis para vincular
    final mesasFisicas = dataService.mesasComandas
        .where((m) => m.tipo == TipoControle.mesa && m.status == 'Aberta')
        .toList()
      ..sort((a, b) {
        final nA = int.tryParse(a.numero) ?? 0;
        final nB = int.tryParse(b.numero) ?? 0;
        return nA.compareTo(nB);
      });
    MesaComanda? mesaVinculadaSelecionada;

    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Validar número em tempo real
          final numeroDigitado = numeroController.text.trim();
          final numeroExiste = numeroDigitado.isNotEmpty && 
              dataService.mesasComandas.any(
                (m) => m.numero == numeroDigitado,
              );

          final mesaObrigatoria = _atrelarComandaAMesa && mesaVinculadaSelecionada == null;
          final podeCriar = !numeroExiste && numeroDigitado.isNotEmpty && !mesaObrigatoria;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            insetPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            title: const Text(
              'Nova Comanda',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: numeroController,
                    onChanged: (value) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Número da Comanda',
                      labelStyle: const TextStyle(color: Colors.grey),
                      errorText: numeroExiste ? 'Este número já está em uso!' : null,
                      errorStyle: const TextStyle(color: Colors.red),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: numeroExiste ? Colors.red : Colors.grey,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: numeroExiste ? Colors.red : Colors.purple,
                        ),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
              const SizedBox(height: 16),
              TextField(
                controller: clienteController,
                decoration: const InputDecoration(
                  labelText: 'Cliente (opcional)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.purple),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: observacaoController,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.purple),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
              ),
              // ---------- Seletor de Mesa (quando atrelar está ativo) ----------
              if (_atrelarComandaAMesa) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: mesaObrigatoria ? Colors.orange : Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.table_restaurant, color: Colors.orange, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            mesaObrigatoria ? 'Mesa Vinculada *' : 'Mesa Vinculada',
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (mesasFisicas.isEmpty)
                        const Text(
                          'Nenhuma mesa física aberta disponível.',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      else
                        DropdownButton<MesaComanda>(
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E1E2E),
                          value: mesaVinculadaSelecionada,
                          hint: const Text('Selecione a mesa...', style: TextStyle(color: Colors.grey)),
                          items: mesasFisicas.map((mesa) {
                            return DropdownMenuItem<MesaComanda>(
                              value: mesa,
                              child: Text(
                                'Mesa ${mesa.numero}${mesa.clienteNome != null ? ' – ${mesa.clienteNome}' : ''}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            );
                          }).toList(),
                          onChanged: (mesa) => setDialogState(() => mesaVinculadaSelecionada = mesa),
                        ),
                      if (mesaObrigatoria && mesasFisicas.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'Selecione uma mesa para vincular a comanda.',
                            style: TextStyle(color: Colors.orange, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.music_note, color: Colors.purple, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Couvert Artístico (opcional)',
                          style: TextStyle(
                            color: Colors.purple,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: quantidadePessoasController,
                      keyboardType: TextInputType.number,
                      onChanged: (value) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Quantidade de Pessoas',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.purple),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final quantidadePessoas = quantidadePessoasController.text.trim().isEmpty
                            ? null
                            : int.tryParse(quantidadePessoasController.text.trim());
                        final valorPorPessoa = valorPorPessoaController.text.trim().isEmpty
                            ? null
                            : double.tryParse(valorPorPessoaController.text.trim().replaceAll(',', '.'));
                        final valorTotalCouvert = (quantidadePessoas != null && valorPorPessoa != null)
                            ? quantidadePessoas * valorPorPessoa
                            : 0.0;
                        
                        return TextField(
                          controller: valorPorPessoaController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Valor por Pessoa (R\$)',
                            labelStyle: const TextStyle(color: Colors.grey),
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.purple),
                            ),
                            suffixText: valorTotalCouvert > 0 
                                ? NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ').format(valorTotalCouvert)
                                : null,
                            suffixStyle: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: podeCriar ? () => Navigator.pop(context, true) : null,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const Text('Criar'),
          ),
        ],
          );
        },
      ),
    );

    if (resultado == true) {
      // Validação final antes de criar (dupla verificação)
      final numeroFinal = numeroController.text.trim();
      if (numeroFinal.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor, informe o número da comanda!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }
      
      final numeroExiste = dataService.mesasComandas.any(
        (m) => m.numero == numeroFinal,
      );

      if (numeroExiste) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('O número $numeroFinal já está em uso por uma mesa ou comanda!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }

      final authService = Provider.of<AuthService>(context, listen: false);
      final usuarioLogado = authService.usuarioAtual?.nome ?? 'Sistema';
      
      // Obter valores do couvert
      final quantidadePessoas = quantidadePessoasController.text.trim().isEmpty
          ? null
          : int.tryParse(quantidadePessoasController.text.trim());
      final valorPorPessoa = valorPorPessoaController.text.trim().isEmpty
          ? null
          : double.tryParse(valorPorPessoaController.text.trim().replaceAll(',', '.'));
      
      final novaComanda = MesaComanda(
        id: uuid.v4(),
        tipo: TipoControle.comanda,
        numero: numeroFinal,
        clienteNome: clienteController.text.trim().isEmpty
            ? null
            : clienteController.text.trim(),
        mesaId: mesaVinculadaSelecionada?.id, // Vincula à mesa física se selecionada
        itens: [],
        status: 'Aberta',
        observacao: observacaoController.text.trim().isEmpty
            ? null
            : observacaoController.text.trim(),
        usuarioCriou: usuarioLogado,
        quantidadePessoasCouvert: quantidadePessoas,
        valorCouvertPorPessoa: valorPorPessoa,
      );

      try {
        await dataService.addMesaComanda(novaComanda);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Comanda ${novaComanda.numero} criada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return novaComanda;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao criar comanda: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    return null;
  }

  /// Cria uma comanda dentro de uma mesa
  Future<void> _criarComandaNaMesa(MesaComanda mesa, DataService dataService) async {
    final numeroController = TextEditingController();
    final clienteController = TextEditingController();
    final quantidadePessoasController = TextEditingController();
    final valorPorPessoaController = TextEditingController();
    
    // Gerar número automático para comandas desta mesa
    final comandasDaMesa = dataService.mesasComandas
        .where((m) => m.tipo == TipoControle.comanda && m.mesaId == mesa.id)
        .toList();
    final ultimoNumero = comandasDaMesa.length;
    
    numeroController.text = 'CMD-${(ultimoNumero + 1).toString().padLeft(2, '0')}';

    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Validar número em tempo real
          final numeroDigitado = numeroController.text.trim();
          final numeroExiste = numeroDigitado.isNotEmpty && 
              dataService.mesasComandas.any(
                (m) => m.numero == numeroDigitado,
              );
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            insetPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            title: const Text(
              'Nova Comanda na Mesa',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Mesa: ${mesa.numero}',
                    style: TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: numeroController,
                    onChanged: (value) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Número da Comanda',
                      labelStyle: const TextStyle(color: Colors.grey),
                      errorText: numeroExiste ? 'Este número já está em uso!' : null,
                      errorStyle: const TextStyle(color: Colors.red),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: numeroExiste ? Colors.red : Colors.grey,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: numeroExiste ? Colors.red : Colors.purple,
                        ),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
              const SizedBox(height: 16),
              TextField(
                controller: clienteController,
                decoration: const InputDecoration(
                  labelText: 'Cliente (opcional)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.purple),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.music_note, color: Colors.purple, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Couvert Artístico (opcional)',
                          style: TextStyle(
                            color: Colors.purple,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: quantidadePessoasController,
                      keyboardType: TextInputType.number,
                      onChanged: (value) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Quantidade de Pessoas',
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.purple),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final quantidadePessoas = quantidadePessoasController.text.trim().isEmpty
                            ? null
                            : int.tryParse(quantidadePessoasController.text.trim());
                        final valorPorPessoa = valorPorPessoaController.text.trim().isEmpty
                            ? null
                            : double.tryParse(valorPorPessoaController.text.trim().replaceAll(',', '.'));
                        final valorTotalCouvert = (quantidadePessoas != null && valorPorPessoa != null)
                            ? quantidadePessoas * valorPorPessoa
                            : 0.0;
                        
                        return TextField(
                          controller: valorPorPessoaController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Valor por Pessoa (R\$)',
                            labelStyle: const TextStyle(color: Colors.grey),
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.purple),
                            ),
                            suffixText: valorTotalCouvert > 0 
                                ? NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ').format(valorTotalCouvert)
                                : null,
                            suffixStyle: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: numeroExiste || numeroController.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const Text('Criar'),
          ),
        ],
          );
        },
      ),
    );

    if (resultado == true) {
      // Validação final antes de criar (dupla verificação)
      final numeroFinal = numeroController.text.trim();
      if (numeroFinal.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor, informe o número da comanda!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      final numeroExiste = dataService.mesasComandas.any(
        (m) => m.numero == numeroFinal,
      );

      if (numeroExiste) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('O número $numeroFinal já está em uso por uma mesa ou comanda!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final authService = Provider.of<AuthService>(context, listen: false);
      final usuarioLogado = authService.usuarioAtual?.nome ?? 'Sistema';
      
      // Obter valores do couvert
      final quantidadePessoas = quantidadePessoasController.text.trim().isEmpty
          ? null
          : int.tryParse(quantidadePessoasController.text.trim());
      final valorPorPessoa = valorPorPessoaController.text.trim().isEmpty
          ? null
          : double.tryParse(valorPorPessoaController.text.trim().replaceAll(',', '.'));
      
      final novaComanda = MesaComanda(
        id: uuid.v4(),
        tipo: TipoControle.comanda,
        numero: numeroFinal,
        clienteNome: clienteController.text.trim().isEmpty
            ? null
            : clienteController.text.trim(),
        mesaId: mesa.id, // Vinculada à mesa
        itens: [],
        status: 'Aberta',
        usuarioCriou: usuarioLogado,
        quantidadePessoasCouvert: quantidadePessoas,
        valorCouvertPorPessoa: valorPorPessoa,
      );

      try {
        await dataService.addMesaComanda(novaComanda);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Comanda ${novaComanda.numero} criada na mesa ${mesa.numero}!'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _mesaSelecionada = mesa; // Manter mesa selecionada para ver a nova comanda
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao criar comanda: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Lista de comandas vinculadas a uma mesa
  List<Widget> _buildComandasDaMesa(MesaComanda mesa, DataService dataService) {
    final comandasDaMesa = dataService.mesasComandas
        .where((c) => c.tipo == TipoControle.comanda && 
                      c.mesaId == mesa.id)
        .toList();

    if (comandasDaMesa.isEmpty) {
      return [];
    }

    return [
      const SizedBox(height: 8),
      const Text(
        'Comandas desta Mesa:',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      ...comandasDaMesa.map((comanda) {
        final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
        final total = comanda.totalCalculado;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.purple.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    if (_comandasExpandidas.contains(comanda.id)) {
                      _comandasExpandidas.remove(comanda.id);
                    } else {
                      _comandasExpandidas.add(comanda.id);
                    }
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      _comandasExpandidas.contains(comanda.id) 
                          ? Icons.expand_less 
                          : Icons.expand_more,
                      color: Colors.purple,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.receipt_long, color: Colors.purple, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comanda.numero,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (comanda.clienteNome != null)
                            Text(
                              comanda.clienteNome!,
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          if (comanda.estaTotalmentePago)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green),
                              ),
                              child: const Text(
                                'Paga',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatoMoeda.format(total),
                          style: TextStyle(
                            color: comanda.estaTotalmentePago ? Colors.grey : Colors.green,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (comanda.totalPago > 0)
                          Text(
                            'Pago: ${formatoMoeda.format(comanda.totalPago)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Mostrar itens quando expandida
              if (_comandasExpandidas.contains(comanda.id)) ...[
                const SizedBox(height: 12),
                const Divider(color: Colors.purple, thickness: 1),
                const SizedBox(height: 8),
                ...comanda.itens.map((item) => Column(
                  children: [
                    _buildItemMesa(item),
                    if (item.status != StatusItem.cancelado)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => _cancelarItem(item, comanda, dataService),
                          icon: const Icon(Icons.cancel, size: 16),
                          label: const Text('Cancelar Item'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            minimumSize: const Size(double.infinity, 36),
                          ),
                        ),
                      ),
                  ],
                )),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _adicionarItensMesa(comanda, dataService),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Adicionar Itens'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _transferirComanda(comanda, dataService),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Mover Comanda'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.purple,
                          side: const BorderSide(color: Colors.purple),
                          minimumSize: const Size(double.infinity, 40),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _transferirItensMesa(comanda, dataService),
                        icon: const Icon(Icons.move_to_inbox),
                        label: const Text('Transf. Itens'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange,
                          side: const BorderSide(color: Colors.deepOrange),
                          minimumSize: const Size(double.infinity, 40),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      }),
    ];
  }

  /// Visualiza conta da mesa/comanda
  void _visualizarConta(MesaComanda mesaComanda, DataService dataService) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    
    // Buscar comandas vinculadas se for uma mesa
    List<MesaComanda>? comandasVinculadas;
    if (mesaComanda.tipo == TipoControle.mesa) {
      comandasVinculadas = dataService.mesasComandas
          .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesaComanda.id)
          .toList();
      if (comandasVinculadas.isEmpty) {
        comandasVinculadas = null;
      }
    }
    
    double totalMesa = mesaComanda.totalCalculado;
    double totalComandas = 0.0;
    if (comandasVinculadas != null) {
      for (final comanda in comandasVinculadas) {
        totalComandas += comanda.totalCalculado;
      }
    }
    final totalGeral = totalMesa + totalComandas;
    
    double totalPagoMesa = mesaComanda.totalPago;
    double totalPagoComandas = 0.0;
    if (comandasVinculadas != null) {
      for (final comanda in comandasVinculadas) {
        totalPagoComandas += comanda.totalPago;
      }
    }
    final totalPagoGeral = totalPagoMesa + totalPagoComandas;
    final totalPendente = totalGeral - totalPagoGeral;
    
    // Coletar todos os pagamentos
    final todosPagamentos = <Map<String, dynamic>>[];
    for (final pagamento in mesaComanda.historicoPagamentos) {
      todosPagamentos.add({
        'pagamento': pagamento,
        'origem': 'Mesa ${mesaComanda.numero}',
      });
    }
    if (comandasVinculadas != null) {
      for (final comanda in comandasVinculadas) {
        for (final pagamento in comanda.historicoPagamentos) {
          todosPagamentos.add({
            'pagamento': pagamento,
            'origem': 'Comanda ${comanda.numero}',
          });
        }
      }
    }
    todosPagamentos.sort((a, b) {
      final pagA = a['pagamento'] as RegistroPagamento;
      final pagB = b['pagamento'] as RegistroPagamento;
      return pagA.dataPagamento.compareTo(pagB.dataPagamento);
    });
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conta - ${mesaComanda.tipo == TipoControle.mesa ? "Mesa" : "Comanda"} ${mesaComanda.numero}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            // Mostrar mesas unidas no título se houver
            if (mesaComanda.observacao != null && 
                (mesaComanda.observacao!.contains('UNIÃO DE MESAS') || 
                 mesaComanda.observacao!.contains('MESA UNIDA'))) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.teal),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.merge, color: Colors.teal, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _extrairResumoMesasUnidas(mesaComanda.observacao!),
                      style: const TextStyle(
                        color: Colors.teal,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Informações gerais
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${mesaComanda.status}',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Abertura: ${formatoData.format(mesaComanda.dataAbertura)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      if (mesaComanda.clienteNome != null && mesaComanda.clienteNome!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Cliente: ${mesaComanda.clienteNome}',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Itens da mesa
                if (mesaComanda.itens.isNotEmpty) ...[
                  const Text(
                    'ITENS DA MESA',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...mesaComanda.itens.map((item) {
                    final itemTotal = item.preco * item.quantidade;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.quantidade}x ${item.nome}',
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  if (item.local != null)
                                    Text(
                                      'Local: ${item.local}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  Text(
                                    'Status: ${_getStatusTextoItem(item.status)}',
                                    style: TextStyle(
                                      color: _getStatusColorItem(item.status),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              formatoMoeda.format(itemTotal),
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
                
                // Itens das comandas vinculadas
                if (comandasVinculadas != null && comandasVinculadas.isNotEmpty)
                  ...comandasVinculadas.map((comanda) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.purple),
                        ),
                        child: Text(
                          'COMANDA: ${comanda.numero}',
                          style: const TextStyle(color: Colors.purple, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...comanda.itens.map((item) {
                        final itemTotal = item.preco * item.quantidade;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${item.quantidade}x ${item.nome}',
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      if (item.local != null)
                                        Text(
                                          'Local: ${item.local}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        ),
                                      Text(
                                        'Status: ${_getStatusTextoItem(item.status)}',
                                        style: TextStyle(
                                          color: _getStatusColorItem(item.status),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatoMoeda.format(itemTotal),
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                    ],
                  )),
                
                // Totais
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Mesa:',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Text(
                            formatoMoeda.format(totalMesa),
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (totalComandas > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Comandas:',
                              style: TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            Text(
                              formatoMoeda.format(totalComandas),
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                      const Divider(color: Colors.white, height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL GERAL:',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            formatoMoeda.format(totalGeral),
                            style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Pago:',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Text(
                            formatoMoeda.format(totalPagoGeral),
                            style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Pendente:',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            formatoMoeda.format(totalPendente),
                            style: TextStyle(
                              color: totalPendente > 0 ? Colors.red : Colors.green,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Observações e histórico de uniões
                if (mesaComanda.observacao != null && mesaComanda.observacao!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  // Verificar se há registro de união de mesas e destacar
                  if (mesaComanda.observacao!.contains('UNIÃO DE MESAS') || 
                      mesaComanda.observacao!.contains('MESA UNIDA')) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal, width: 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.merge, color: Colors.teal, size: 24),
                              SizedBox(width: 8),
                              Text(
                                'MESAS UNIDAS',
                                style: TextStyle(
                                  color: Colors.teal,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Extrair e exibir apenas as linhas de união
                          ...mesaComanda.observacao!.split('\n').where((linha) {
                            return linha.contains('UNIÃO DE MESAS') || linha.contains('MESA UNIDA');
                          }).map((linha) {
                            // Extrair informações da linha
                            String textoExibicao = linha;
                            if (linha.contains('UNIÃO DE MESAS')) {
                              final regex = RegExp(r'Mesa (\d+) foi unida com Mesa (\d+) em (.+)');
                              final match = regex.firstMatch(linha);
                              if (match != null) {
                                final mesaOrigem = match.group(1);
                                final mesaDestino = match.group(2);
                                final dataHora = match.group(3);
                                textoExibicao = 'Mesa $mesaOrigem → Mesa $mesaDestino\n   Data: $dataHora';
                              }
                            } else if (linha.contains('MESA UNIDA')) {
                              final regex = RegExp(r'unida com a Mesa (\d+) em (.+)');
                              final match = regex.firstMatch(linha);
                              if (match != null) {
                                final mesaDestino = match.group(1);
                                final dataHora = match.group(2);
                                textoExibicao = 'Unida com Mesa $mesaDestino\n   Data: $dataHora';
                              }
                            }
                            
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.arrow_forward, color: Colors.teal, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      textoExibicao.replaceAll('🔗 ', '').replaceAll('UNIÃO DE MESAS: ', '').replaceAll('MESA UNIDA: ', ''),
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Outras observações (se houver)
                  if (mesaComanda.observacao!.split('\n').any((linha) => 
                      !linha.contains('UNIÃO DE MESAS') && !linha.contains('MESA UNIDA'))) ...[
                    const Text(
                      'OBSERVAÇÕES',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...mesaComanda.observacao!.split('\n').where((linha) => 
                              !linha.contains('UNIÃO DE MESAS') && !linha.contains('MESA UNIDA')).map((linha) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                linha,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ],
                
                // Pagamentos realizados
                if (todosPagamentos.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'PAGAMENTOS REALIZADOS',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...todosPagamentos.map((pagamentoData) {
                    final pagamento = pagamentoData['pagamento'] as RegistroPagamento;
                    final origem = pagamentoData['origem'] as String;
                    
                    // Buscar itens pagos deste pagamento
                    final itensPagos = <ItemMesaComanda>[];
                    if (pagamento.itensPagos != null && pagamento.itensPagos!.isNotEmpty) {
                      try {
                        // Verificar se é da mesa principal
                        if (origem.startsWith('Mesa')) {
                          for (final itemId in pagamento.itensPagos!) {
                            final item = mesaComanda.itens.firstWhere(
                              (i) => i.id == itemId,
                              orElse: () => ItemMesaComanda(
                                id: itemId,
                                itemId: '',
                                nome: 'Item não encontrado',
                                preco: 0.0,
                                quantidade: 0,
                                status: StatusItem.cancelado,
                                local: null,
                                observacao: null,
                                isServico: false,
                                dataHora: DateTime.now(),
                                usuarioCriou: null,
                                usuarioModificou: null,
                                dataModificacao: null,
                                acaoRealizada: null,
                              ),
                            );
                            if (item.nome != 'Item não encontrado') {
                              itensPagos.add(item);
                            }
                          }
                        } else if (origem.startsWith('Comanda') && comandasVinculadas != null) {
                          // Extrair número da comanda da origem
                          final numeroComanda = origem.replaceAll('Comanda ', '').trim();
                          final comanda = comandasVinculadas.firstWhere(
                            (c) => c.numero == numeroComanda,
                            orElse: () => MesaComanda(
                              id: '',
                              numero: numeroComanda,
                              tipo: TipoControle.comanda,
                              status: 'Fechada',
                              dataAbertura: DateTime.now(),
                              itens: [],
                            ),
                          );
                          if (comanda.id.isNotEmpty) {
                            for (final itemId in pagamento.itensPagos!) {
                              final item = comanda.itens.firstWhere(
                                (i) => i.id == itemId,
                                orElse: () => ItemMesaComanda(
                                  id: itemId,
                                  itemId: '',
                                  nome: 'Item não encontrado',
                                  preco: 0.0,
                                  quantidade: 0,
                                  status: StatusItem.cancelado,
                                  local: null,
                                  observacao: null,
                                  isServico: false,
                                  dataHora: DateTime.now(),
                                  usuarioCriou: null,
                                  usuarioModificou: null,
                                  dataModificacao: null,
                                  acaoRealizada: null,
                                ),
                              );
                              if (item.nome != 'Item não encontrado') {
                                itensPagos.add(item);
                              }
                            }
                          }
                        }
                      } catch (e) {
                        // Se houver erro, apenas não mostra os itens
                        debugPrint('Erro ao buscar itens pagos: $e');
                      }
                    }
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            origem,
                            style: const TextStyle(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                formatoMoeda.format(pagamento.valor),
                                style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                pagamento.formaPagamento ?? 'Não informado',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Data: ${formatoData.format(pagamento.dataPagamento)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                          if (pagamento.pessoaPagou != null && pagamento.pessoaPagou!.isNotEmpty)
                            Text(
                              'Pagou: ${pagamento.pessoaPagou}',
                              style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          // Mostrar itens pagos
                          if (itensPagos.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange.withOpacity(0.5)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.shopping_cart, color: Colors.orange, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Itens Pagos (${itensPagos.length}):',
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ...itensPagos.map((item) {
                                    final itemTotal = item.preco * item.quantidade;
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 8, top: 2),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${item.quantidade}x ${item.nome}',
                                              style: const TextStyle(color: Colors.white, fontSize: 10),
                                            ),
                                          ),
                                          Text(
                                            formatoMoeda.format(itemTotal),
                                            style: const TextStyle(
                                              color: Colors.green,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _imprimirFechamentoConta(mesaComanda, dataService);
            },
            icon: const Icon(Icons.print),
            label: const Text('Imprimir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _receberMesa(mesaComanda, dataService);
            },
            icon: const Icon(Icons.payment),
            label: const Text('Receber'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  String _getStatusTextoItem(StatusItem status) {
    switch (status) {
      case StatusItem.pendente:
        return 'Pendente';
      case StatusItem.emPreparo:
        return 'Em Preparo';
      case StatusItem.pronto:
        return 'Pronto';
      case StatusItem.entregue:
        return 'Entregue';
      case StatusItem.cancelado:
        return 'Cancelado';
    }
  }
  
  Color _getStatusColorItem(StatusItem status) {
    switch (status) {
      case StatusItem.pendente:
        return Colors.red;
      case StatusItem.emPreparo:
        return Colors.orange;
      case StatusItem.pronto:
        return Colors.green;
      case StatusItem.entregue:
        return Colors.blue;
      case StatusItem.cancelado:
        return Colors.grey;
    }
  }

  /// Imprime fechamento de conta da mesa/comanda
  Future<void> _imprimirFechamentoConta(MesaComanda mesaComanda, DataService dataService) async {
    try {
      // Buscar empresa atual do AuthService
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhuma empresa selecionada'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Buscar comandas vinculadas se for uma mesa
      List<MesaComanda>? comandasVinculadas;
      if (mesaComanda.tipo == TipoControle.mesa) {
        comandasVinculadas = dataService.mesasComandas
            .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesaComanda.id)
            .toList();
        if (comandasVinculadas.isEmpty) {
          comandasVinculadas = null;
        }
      }

      // Imprimir PDF térmico
      await MesaComandaPdfService.imprimirPDFTermico(
        mesaComanda: mesaComanda,
        empresa: empresa,
        comandasVinculadas: comandasVinculadas,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fechamento de conta ${mesaComanda.numero} impresso com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao imprimir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Aliases para troca e união (agora usando a mesma lógica)
  Future<void> _trocarComanda(MesaComanda comanda, DataService dataService) => _trocarMesa(comanda, dataService);
  Future<void> _unirComandas(MesaComanda comanda, DataService dataService) => _unirMesas(comanda, dataService);

  /// Troca todos os dados de uma mesa para outra
  Future<void> _trocarMesa(MesaComanda mesaOrigem, DataService dataService) async {
    // Modificar filtro para incluir mesas ou comandas baseadas na origem
    final isComanda = mesaOrigem.tipo == TipoControle.comanda;
    final itensDisponiveis = dataService.mesasComandas
        .where((m) => m.tipo == mesaOrigem.tipo && m.id != mesaOrigem.id && m.status == 'Aberta')
        .toList();
    
    // Mostrar diálogo para selecionar mesa destino ou criar nova
    final mesaDestino = await showDialog<MesaComanda>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(
          isComanda ? 'Trocar Comanda' : 'Trocar Mesa',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transferir ${isComanda ? "Comanda" : "Mesa"} ${mesaOrigem.numero} para:',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (itensDisponiveis.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('Não há outros itens abertos disponíveis.', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: itensDisponiveis.length,
                    itemBuilder: (context, index) {
                      final item = itensDisponiveis[index];
                      return ListTile(
                        leading: Icon(
                          isComanda ? Icons.receipt_long : Icons.table_restaurant,
                          color: isComanda ? Colors.purpleAccent : Colors.orange,
                        ),
                        title: Text(
                          '${isComanda ? "Comanda" : "Mesa"} ${item.numero}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          item.clienteNome ?? 'Sem cliente',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
                ),
              const Divider(color: Colors.white24, height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    MesaComanda? novoItem;
                    if (isComanda) {
                      novoItem = await _abrirNovaComanda(context, dataService);
                    } else {
                      novoItem = await _abrirNovaMesa(context, dataService);
                    }
                    
                    if (novoItem != null && context.mounted) {
                      Navigator.pop(context, novoItem);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text('Criar Nova ${isComanda ? "Comanda" : "Mesa"}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isComanda ? Colors.purple : Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
    
    if (mesaDestino == null) return;
    
    // Confirmar transferência
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Confirmar Transferência',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transferir todos os dados da ${isComanda ? "Comanda" : "Mesa"} ${mesaOrigem.numero} para a ${isComanda ? "Comanda" : "Mesa"} ${mesaDestino.numero}?',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Isso inclui:',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text('• Todos os itens', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Text('• Comandas vinculadas', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Text('• Histórico de pagamentos', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Text('• Dados do cliente', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange),
              ),
              child: Text(
                '⚠ A ${isComanda ? "comanda" : "mesa"} origem será limpa e ficará disponível',
                style: const TextStyle(color: Colors.orange, fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    
    if (confirmar != true) return;
    
    try {
      // Buscar dados atualizados
      final mesaOrigemAtual = dataService.mesasComandas.firstWhere(
        (m) => m.id == mesaOrigem.id,
        orElse: () => mesaOrigem,
      );
      
      final mesaDestinoAtual = dataService.mesasComandas.firstWhere(
        (m) => m.id == mesaDestino.id,
        orElse: () => mesaDestino,
      );
      
      // Buscar comandas vinculadas à mesa origem
      final comandasOrigem = dataService.mesasComandas
          .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesaOrigem.id)
          .toList();
      
      // Transferir itens da mesa origem para destino
      final novosItensDestino = [...mesaDestinoAtual.itens, ...mesaOrigemAtual.itens];
      
      // Transferir histórico de pagamentos
      final novoHistoricoDestino = [...mesaDestinoAtual.historicoPagamentos, ...mesaOrigemAtual.historicoPagamentos];
      
      // Transferir itens pagos
      final novosItensPagosDestino = [...mesaDestinoAtual.itensPagos, ...mesaOrigemAtual.itensPagos];
      
      // Atualizar mesa destino com todos os dados
      final mesaDestinoAtualizada = mesaDestinoAtual.copyWith(
        itens: novosItensDestino,
        historicoPagamentos: novoHistoricoDestino,
        itensPagos: novosItensPagosDestino,
        clienteNome: mesaOrigemAtual.clienteNome ?? mesaDestinoAtual.clienteNome,
        clienteId: mesaOrigemAtual.clienteId ?? mesaDestinoAtual.clienteId,
        observacao: mesaOrigemAtual.observacao ?? mesaDestinoAtual.observacao,
        updatedAt: DateTime.now(),
      );
      
      await dataService.updateMesaComanda(mesaDestinoAtualizada);
      
      // Transferir comandas vinculadas para a mesa destino
      for (final comanda in comandasOrigem) {
        final comandaTransferida = comanda.copyWith(
          mesaId: mesaDestino.id,
          updatedAt: DateTime.now(),
        );
        await dataService.updateMesaComanda(comandaTransferida);
      }
      
      // Limpar mesa origem (mas preservar histórico se necessário)
      final mesaOrigemLimpa = mesaOrigemAtual.copyWith(
        itens: [],
        itensPagos: [],
        clienteNome: null,
        clienteId: null,
        observacao: null,
        total: 0.0,
        status: 'Aberta',
        dataAbertura: DateTime.now(),
        dataFechamento: null,
        updatedAt: DateTime.now(),
      );
      
      await dataService.updateMesaComanda(mesaOrigemLimpa);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isComanda ? "Comanda" : "Mesa"} ${mesaOrigem.numero} transferida para ${isComanda ? "Comanda" : "Mesa"} ${mesaDestino.numero} com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _mesaSelecionada = mesaDestinoAtualizada;
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao transferir ${isComanda ? "comanda" : "mesa"}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Une duas mesas (junta tudo em uma mesa)
  Future<void> _unirMesas(MesaComanda mesaOrigem, DataService dataService) async {
    final isComanda = mesaOrigem.tipo == TipoControle.comanda;
    final itensDisponiveis = dataService.mesasComandas
        .where((m) => m.tipo == mesaOrigem.tipo && m.id != mesaOrigem.id && m.status == 'Aberta')
        .toList();
    
    // Mostrar diálogo para selecionar destino ou criar novo
    final mesaDestino = await showDialog<MesaComanda>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(
          isComanda ? 'Unir Comandas' : 'Unir Mesas',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unir ${isComanda ? "Comanda" : "Mesa"} ${mesaOrigem.numero} com:',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (itensDisponiveis.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('Não há outros itens abertos para unir.', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: itensDisponiveis.length,
                    itemBuilder: (context, index) {
                      final item = itensDisponiveis[index];
                      return ListTile(
                        leading: Icon(
                          isComanda ? Icons.receipt_long : Icons.table_restaurant,
                          color: isComanda ? Colors.purpleAccent : Colors.teal,
                        ),
                        title: Text(
                          '${isComanda ? "Comanda" : "Mesa"} ${item.numero}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          item.clienteNome ?? 'Sem cliente',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
                ),
              const Divider(color: Colors.white24, height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    if (isComanda) {
                      _abrirNovaComanda(context, dataService);
                    } else {
                      _abrirNovaMesa(context, dataService);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text('Criar Nova ${isComanda ? "Comanda" : "Mesa"} e Unir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isComanda ? Colors.deepPurple : Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
    
    if (mesaDestino == null) return;
    
    // Confirmar união
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Confirmar União',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unir ${isComanda ? "Comanda" : "Mesa"} ${mesaOrigem.numero} com ${isComanda ? "Comanda" : "Mesa"} ${mesaDestino.numero}?',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Todos os dados serão juntados na ${isComanda ? "Comanda" : "Mesa"} ${mesaDestino.numero}:',
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('• Todos os itens de ambas as ${isComanda ? "comandas" : "mesas"}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const Text('• Todas as comandas vinculadas', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Text('• Histórico de pagamentos', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.teal),
              ),
              child: Text(
                '⚠ A ${isComanda ? "Comanda" : "Mesa"} ${mesaOrigem.numero} será fechada após a união',
                style: TextStyle(color: isComanda ? Colors.deepPurpleAccent : Colors.teal, fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('Confirmar União'),
          ),
        ],
      ),
    );
    
    if (confirmar != true) return;
    
    try {
      // Buscar dados atualizados
      final mesaOrigemAtual = dataService.mesasComandas.firstWhere(
        (m) => m.id == mesaOrigem.id,
        orElse: () => mesaOrigem,
      );
      
      final mesaDestinoAtual = dataService.mesasComandas.firstWhere(
        (m) => m.id == mesaDestino.id,
        orElse: () => mesaDestino,
      );
      
      // Buscar comandas vinculadas a ambas as mesas
      final comandasOrigem = dataService.mesasComandas
          .where((c) => c.tipo == TipoControle.comanda && c.mesaId == mesaOrigem.id)
          .toList();
      
      // Unir itens
      final todosItens = [...mesaDestinoAtual.itens, ...mesaOrigemAtual.itens];
      
      // Unir histórico de pagamentos
      final todoHistorico = [...mesaDestinoAtual.historicoPagamentos, ...mesaOrigemAtual.historicoPagamentos];
      
      // Unir itens pagos
      final todosItensPagos = [...mesaDestinoAtual.itensPagos, ...mesaOrigemAtual.itensPagos];
      
      // Unir dados do cliente (priorizar o que já existe na mesa destino)
      final clienteNomeFinal = mesaDestinoAtual.clienteNome ?? mesaOrigemAtual.clienteNome;
      final clienteIdFinal = mesaDestinoAtual.clienteId ?? mesaOrigemAtual.clienteId;
      
      // Unir observações
      final observacaoFinal = [
        if (mesaDestinoAtual.observacao != null) mesaDestinoAtual.observacao!,
        if (mesaOrigemAtual.observacao != null) mesaOrigemAtual.observacao!,
      ].join('\n');
      
      // Registrar união na observação
      final formatoDataUniao = DateFormat('dd/MM/yyyy HH:mm');
      final agora = DateTime.now();
      final termoGeral = isComanda ? "COMANDA" : "MESA";
      final registroUniao = '🔗 UNIÃO DE ${termoGeral}S: $termoGeral ${mesaOrigem.numero} foi unida com $termoGeral ${mesaDestino.numero} em ${formatoDataUniao.format(agora)}';
      
      // Verificar se já existem registros de união na mesa destino
      final temRegistroUniao = mesaDestinoAtual.observacao != null && 
          (mesaDestinoAtual.observacao!.contains('UNIÃO DE MESAS') || 
           mesaDestinoAtual.observacao!.contains('MESA UNIDA'));
      
      // Se já tem registro, adicionar nova linha; senão, criar seção
      final observacaoComUniao = temRegistroUniao && mesaDestinoAtual.observacao != null
          ? '${mesaDestinoAtual.observacao}\n$registroUniao'
          : (observacaoFinal.isNotEmpty 
              ? '$registroUniao\n\n$observacaoFinal' 
              : registroUniao);
      
      // Atualizar mesa destino com todos os dados unidos
      final mesaDestinoUnida = mesaDestinoAtual.copyWith(
        itens: todosItens,
        historicoPagamentos: todoHistorico,
        itensPagos: todosItensPagos,
        clienteNome: clienteNomeFinal,
        clienteId: clienteIdFinal,
        observacao: observacaoComUniao,
        usuarioModificou: Provider.of<AuthService>(context, listen: false).usuarioAtual?.nome ?? 'Sistema',
        updatedAt: DateTime.now(),
      );
      
      await dataService.updateMesaComanda(mesaDestinoUnida);
      
      // Transferir comandas da mesa origem para destino
      for (final comanda in comandasOrigem) {
        final comandaTransferida = comanda.copyWith(
          mesaId: mesaDestino.id,
          updatedAt: DateTime.now(),
        );
        await dataService.updateMesaComanda(comandaTransferida);
      }
      
      // Fechar item origem (preservar histórico e registrar união)
      final termoGeralOrigem = isComanda ? "COMANDA" : "MESA";
      final registroUniaoOrigem = '🔗 $termoGeralOrigem UNIDA: Esta ${termoGeralOrigem.toLowerCase()} foi unida com a $termoGeralOrigem ${mesaDestino.numero} em ${formatoDataUniao.format(DateTime.now())}';
      final observacaoOrigemComUniao = [
        registroUniaoOrigem,
        if (mesaOrigemAtual.observacao != null && mesaOrigemAtual.observacao!.isNotEmpty) 
          mesaOrigemAtual.observacao!,
      ].join('\n\n');
      
      final mesaOrigemFechada = mesaOrigemAtual.copyWith(
        itens: [],
        itensPagos: [],
        historicoPagamentos: [], // Limpar quando fechar por união
        status: 'Fechada',
        dataFechamento: DateTime.now(),
        observacao: null, // Limpar observação ao fechar (conforme pedido do usuário)
        clienteNome: null,
        clienteId: null,
        valorCouvert: null,
        quantidadePessoasCouvert: null,
        valorGarcom: null,
        usuarioModificou: Provider.of<AuthService>(context, listen: false).usuarioAtual?.nome ?? 'Sistema',
        updatedAt: DateTime.now(),
      );
      
      await dataService.updateMesaComanda(mesaOrigemFechada);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isComanda ? "Comandas" : "Mesas"} ${mesaOrigem.numero} e ${mesaDestino.numero} unidas com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _mesaSelecionada = mesaDestinoUnida;
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao unir ${isComanda ? "comandas" : "mesas"}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Transfere uma comanda de uma mesa para outra
  Future<void> _transferirComanda(MesaComanda comanda, DataService dataService) async {
    if (comanda.mesaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta comanda não está vinculada a uma mesa'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final mesasDisponiveis = dataService.mesasComandas
        .where((m) => m.tipo == TipoControle.mesa && m.id != comanda.mesaId && m.status == 'Aberta')
        .toList();
    
    if (mesasDisponiveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há outras mesas abertas para transferir a comanda'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Mostrar diálogo para selecionar mesa destino
    final mesaDestino = await showDialog<MesaComanda>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Transferir Comanda',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transferir Comanda ${comanda.numero} para:',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: mesasDisponiveis.length,
                  itemBuilder: (context, index) {
                    final mesa = mesasDisponiveis[index];
                    return ListTile(
                      leading: const Icon(Icons.table_restaurant, color: Colors.orange),
                      title: Text(
                        'Mesa ${mesa.numero}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        mesa.clienteNome ?? 'Sem cliente',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      onTap: () => Navigator.pop(context, mesa),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
    
    if (mesaDestino == null) return;
    
    // Confirmar transferência
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Confirmar Transferência',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transferir Comanda ${comanda.numero} para a Mesa ${mesaDestino.numero}?',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'A comanda será desvinculada da mesa atual e vinculada à nova mesa.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    
    if (confirmar != true) return;
    
    try {
      // Buscar comanda atualizada
      final comandaAtual = dataService.mesasComandas.firstWhere(
        (c) => c.id == comanda.id,
        orElse: () => comanda,
      );
      
      // Transferir comanda para nova mesa
      final comandaTransferida = comandaAtual.copyWith(
        mesaId: mesaDestino.id,
        updatedAt: DateTime.now(),
      );
      
      await dataService.updateMesaComanda(comandaTransferida);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comanda ${comanda.numero} transferida para Mesa ${mesaDestino.numero} com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          // Atualizar seleção se necessário
          if (_mesaSelecionada?.id == comanda.mesaId) {
            final mesaAtualizada = dataService.mesasComandas.firstWhere(
              (m) => m.id == comanda.mesaId,
              orElse: () => _mesaSelecionada!,
            );
            _mesaSelecionada = mesaAtualizada;
          }
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao transferir comanda: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Mostra tela de pagamento padrão do PDV (até 2 formas de pagamento)
  Future<List<Map<String, dynamic>>?> _mostrarTelaPagamentoPDV(
    BuildContext context,
    double valorTotal,
    String pessoaPagou, {
    MesaComanda? mesaComanda,
    double? valorBase, // Valor base (sem garçom) - se fornecido, será usado diretamente
  }) async {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    // Formas de recebimento disponíveis (sem fiado, pois fiado é só para lançamento)
    final formasRecebimento = TipoPagamento.values
        .where((t) => t != TipoPagamento.fiado)
        .toList();
    
    final pagamentos = <Map<String, dynamic>>[];
    
    // Calcular valor do garçom como 10% do valor base (sem garçom)
    bool garcomRetirado = mesaComanda?.garcomRetirado ?? false;
    double valorBaseCalculado;
    double valorGarcom = 0.0;
    
    // Se o valorBase foi fornecido, usar diretamente (é o valor dos itens selecionados sem garçom e sem couvert)
    if (valorBase != null) {
      // O valorBase é apenas dos itens (sem couvert)
      // O valorTotal inclui: itens + couvert + garçom (10% apenas dos itens)
      // Então: valorTotal = valorBase + couvert + (valorBase * 0.10)
      // Para calcular o garçom corretamente: garçom = valorBase * 0.10
      valorBaseCalculado = valorBase;
      if (!garcomRetirado) {
        valorGarcom = valorBaseCalculado * 0.10; // Garçom é 10% apenas dos itens (valorBase)
      }
    } else {
      // Caso contrário, calcular a partir do valorTotal
      // O valorTotal que chega aqui já inclui o garçom (se não foi retirado)
      // Se não foi retirado: valorTotal = valorBase + couvert + 10% do valorBase
      // Como não temos o valorBase separado, precisamos estimar
      // Mas o ideal é sempre passar o valorBase como parâmetro
      valorBaseCalculado = valorTotal;
      if (!garcomRetirado && valorTotal > 0) {
        // Tentar calcular o valor base removendo o garçom
        // Como o garçom é 10% do valorBase, e valorTotal = valorBase + couvert + (valorBase * 0.10)
        // Não podemos calcular precisamente sem saber o couvert
        // Por segurança, vamos assumir que o valorTotal já está correto e calcular o garçom como 10% de uma estimativa
        // Mas o melhor é sempre passar valorBase como parâmetro
        valorBaseCalculado = valorTotal / 1.10; // Aproximação (assumindo que couvert é pequeno)
        valorGarcom = valorBaseCalculado * 0.10;
      }
    }
    
    // Variáveis de estado que precisam persistir entre rebuilds
    TipoPagamento? formaSelecionada1;
    TipoPagamento? formaSelecionada2;
    double valorPagamento1 = 0.0;
    double valorPagamento2 = 0.0;
    double valorTotalPagamentos = 0.0;
    final valorController1 = TextEditingController();
    final valorController2 = TextEditingController();
    final observacaoController1 = TextEditingController();
    final observacaoController2 = TextEditingController();
    bool usarDuasFormas = false;
    
    final resultado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Calcular valor total ajustado (com ou sem garçom)
          double getValorTotalAjustado() {
            return garcomRetirado 
                ? (valorTotal - valorGarcom)
                : valorTotal;
          }
          
          // Calcular valor restante
          void atualizarValores() {
            setDialogState(() {
              // Remover espaços e converter vírgula para ponto
              final texto1 = valorController1.text.trim().replaceAll(',', '.').replaceAll(' ', '').replaceAll('R\$', '').replaceAll('R', '').replaceAll('\$', '');
              final texto2 = valorController2.text.trim().replaceAll(',', '.').replaceAll(' ', '').replaceAll('R\$', '').replaceAll('R', '').replaceAll('\$', '');
              
              valorPagamento1 = double.tryParse(texto1) ?? 0.0;
              valorPagamento2 = double.tryParse(texto2) ?? 0.0;
              valorTotalPagamentos = valorPagamento1 + valorPagamento2;
            });
          }
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.payments, color: Colors.green),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Receber Pagamento',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            insetPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            content: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Valor a receber (ajustado conforme garçom)
                  Builder(
                    builder: (context) {
                      // Calcular valor total a exibir (com ou sem garçom)
                      // Se retirado: remove apenas o garçom (10% dos itens) do valor total
                      // Se não retirado: mostra valor total completo (com garçom)
                      double valorExibir = getValorTotalAjustado();
                      
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Valor Total:',
                                  style: TextStyle(color: Colors.white70, fontSize: 16),
                                ),
                                Text(
                                  formatoMoeda.format(valorExibir),
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (valorGarcom > 0 && !garcomRetirado) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Garçom (10%):',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  Text(
                                    formatoMoeda.format(valorGarcom),
                                    style: const TextStyle(
                                      color: Colors.blueAccent,
                                      fontSize: 14,
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
                  const SizedBox(height: 20),
                  
                  // Checkbox para retirar garçom (se for mesa e tiver garçom calculado)
                  if (mesaComanda != null && mesaComanda.valorGarcomCalculado > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Garçom (10%):',
                                style: TextStyle(color: Colors.white, fontSize: 14),
                              ),
                              Text(
                                formatoMoeda.format(mesaComanda.valorGarcomCalculado),
                                style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Retirar garçom do total',
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                            subtitle: const Text(
                              'O valor do garçom será descontado do total a pagar',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                            value: garcomRetirado,
                            activeColor: Colors.blue,
                            onChanged: (value) {
                              setDialogState(() {
                                garcomRetirado = value ?? false;
                                // Calcular novo valor total (com ou sem garçom)
                                // Se retirar: remove apenas o garçom (10% dos itens) do valor total
                                // Se não retirar: mantém o total com garçom
                                final novoValorTotal = getValorTotalAjustado();
                                
                                // Atualizar campos de valor sempre (mesmo que não estejam preenchidos)
                                if (formaSelecionada1 != null) {
                                  if (usarDuasFormas) {
                                    valorController1.text = (novoValorTotal / 2).toStringAsFixed(2);
                                  } else {
                                    valorController1.text = novoValorTotal.toStringAsFixed(2);
                                  }
                                  atualizarValores();
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Checkbox para usar duas formas
                  CheckboxListTile(
                    title: const Text(
                      'Usar duas formas de pagamento',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: usarDuasFormas,
                    activeColor: Colors.orange,
                    onChanged: (value) {
                      setDialogState(() {
                        usarDuasFormas = value ?? false;
                        if (!usarDuasFormas) {
                          formaSelecionada2 = null;
                          valorController2.clear();
                          observacaoController2.clear();
                          valorPagamento2 = 0.0;
                        }
                        atualizarValores();
                      });
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // PRIMEIRA FORMA DE PAGAMENTO
                  const Text(
                    '1ª Forma de Pagamento',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Botões de forma de recebimento
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: formasRecebimento.map((tipo) {
                      final isSelected = formaSelecionada1 == tipo;
                      final cor = _getCorTipoRecebimento(tipo);
                      
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              formaSelecionada1 = tipo;
                              // Sempre preencher o valor quando selecionar a forma de pagamento
                              // Usar o valor ajustado (com ou sem garçom)
                              final valorAjustado = getValorTotalAjustado();
                              if (usarDuasFormas) {
                                valorController1.text = (valorAjustado / 2).toStringAsFixed(2);
                              } else {
                                valorController1.text = valorAjustado.toStringAsFixed(2);
                              }
                              // Atualizar valores imediatamente
                              valorPagamento1 = double.tryParse(valorController1.text.replaceAll(',', '.')) ?? 0.0;
                              valorTotalPagamentos = valorPagamento1 + valorPagamento2;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cor.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? cor
                                    : Colors.white.withOpacity(0.2),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getIconeTipoRecebimento(tipo),
                                  color: isSelected ? cor : Colors.white54,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tipo.nome,
                                  style: TextStyle(
                                    color: isSelected ? cor : Colors.white70,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  
                  if (formaSelecionada1 != null) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: valorController1,
                      decoration: InputDecoration(
                        labelText: 'Valor',
                        labelStyle: const TextStyle(color: Colors.grey),
                        prefixText: 'R\$ ',
                        prefixStyle: const TextStyle(color: Colors.greenAccent),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => atualizarValores(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: observacaoController1,
                      decoration: InputDecoration(
                        labelText: 'Observação (opcional)',
                        labelStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                  
                  // SEGUNDA FORMA DE PAGAMENTO (se habilitada)
                  if (usarDuasFormas) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      '2ª Forma de Pagamento',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Botões de forma de recebimento (excluindo a primeira selecionada)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: formasRecebimento.where((tipo) => tipo != formaSelecionada1).map((tipo) {
                        final isSelected = formaSelecionada2 == tipo;
                        final cor = _getCorTipoRecebimento(tipo);
                        
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setDialogState(() {
                                formaSelecionada2 = tipo;
                                // Calcular valor restante para segunda forma (usar valor ajustado)
                                final valorAjustado = getValorTotalAjustado();
                                final valorRestante = valorAjustado - valorPagamento1;
                                if (valorRestante > 0) {
                                  valorController2.text = valorRestante.toStringAsFixed(2);
                                } else {
                                  valorController2.text = '0.00';
                                }
                                // Atualizar valores imediatamente
                                valorPagamento2 = double.tryParse(valorController2.text.replaceAll(',', '.')) ?? 0.0;
                                valorTotalPagamentos = valorPagamento1 + valorPagamento2;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? cor.withOpacity(0.3)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? cor
                                      : Colors.white.withOpacity(0.2),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getIconeTipoRecebimento(tipo),
                                    color: isSelected ? cor : Colors.white54,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    tipo.nome,
                                    style: TextStyle(
                                      color: isSelected ? cor : Colors.white70,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    
                    if (formaSelecionada2 != null) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: valorController2,
                        decoration: InputDecoration(
                          labelText: 'Valor',
                          labelStyle: const TextStyle(color: Colors.grey),
                          prefixText: 'R\$ ',
                          prefixStyle: const TextStyle(color: Colors.greenAccent),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.grey),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => atualizarValores(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: observacaoController2,
                        decoration: InputDecoration(
                          labelText: 'Observação (opcional)',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.grey),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ],
                  
                  // Resumo
                  if (formaSelecionada1 != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Builder(
                            builder: (context) {
                  // Calcular valor esperado (com ou sem garçom)
                  // Se retirado: remove apenas o garçom (10% dos itens) do valor total
                  // Se não retirado: espera o valor total (com garçom)
                  final valorEsperado = getValorTotalAjustado();
                              
                              return Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Total lançado:',
                                        style: TextStyle(color: Colors.white70, fontSize: 14),
                                      ),
                                      Text(
                                        formatoMoeda.format(valorTotalPagamentos),
                                        style: TextStyle(
                                          color: (valorTotalPagamentos - valorEsperado).abs() <= 0.01
                                              ? Colors.greenAccent
                                              : Colors.orange,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((valorTotalPagamentos - valorEsperado).abs() > 0.01) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Faltando: ${formatoMoeda.format(valorEsperado - valorTotalPagamentos)}',
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formaSelecionada1 == null) return false;
                  
                  // Calcular valor esperado (com ou sem garçom)
                  // Se retirado: espera apenas o valor base (sem garçom)
                  // Se não retirado: espera o valor total (com garçom)
                  // Se o garçom foi retirado, o valor esperado é o total menos o garçom
                  // Se não foi retirado, o valor esperado é o total completo
                  final valorEsperado = getValorTotalAjustado();
                  
                  return (valorTotalPagamentos - valorEsperado).abs() <= 0.01;
                }()
                    ? () {
                        pagamentos.clear();
                        pagamentos.add({
                          'tipo': formaSelecionada1!,
                          'valor': valorPagamento1,
                          'observacao': observacaoController1.text.trim().isEmpty 
                              ? null 
                              : observacaoController1.text.trim(),
                          'garcomRetirado': garcomRetirado,
                        });
                        
                        if (usarDuasFormas && formaSelecionada2 != null) {
                          pagamentos.add({
                            'tipo': formaSelecionada2!,
                            'valor': valorPagamento2,
                            'observacao': observacaoController2.text.trim().isEmpty 
                                ? null 
                                : observacaoController2.text.trim(),
                            'garcomRetirado': garcomRetirado,
                          });
                        }
                        
                        Navigator.pop(ctx, true);
                      }
                    : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );
    
    // Limpar controllers após o diálogo fechar
    valorController1.dispose();
    valorController2.dispose();
    observacaoController1.dispose();
    observacaoController2.dispose();
    
    if (resultado == true && pagamentos.isNotEmpty) {
      return pagamentos;
    }
    return null;
  }
  
  Color _getCorTipoRecebimento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Colors.green;
      case TipoPagamento.pix:
        return Colors.teal;
      case TipoPagamento.cartaoCredito:
        return Colors.purple;
      case TipoPagamento.cartaoDebito:
        return Colors.blue;
      case TipoPagamento.boleto:
        return Colors.orange;
      case TipoPagamento.crediario:
        return Colors.pink;
      case TipoPagamento.outro:
        return Colors.grey;
      case TipoPagamento.alimentacao:
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getIconeTipoRecebimento(TipoPagamento tipo) {
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
      case TipoPagamento.outro:
        return Icons.more_horiz;
      case TipoPagamento.alimentacao:
        return Icons.restaurant;
      default:
        return Icons.payment;
    }
  }

  /// Extrai informações sobre mesas unidas da observação
  String _extrairMesasUnidas(String observacao) {
    final linhas = observacao.split('\n');
    final mesasUnidas = <String>[];
    
    for (final linha in linhas) {
      if (linha.contains('UNIÃO DE MESAS')) {
        // Extrair números das mesas do padrão: "Mesa X foi unida com Mesa Y"
        final regex = RegExp(r'Mesa (\d+) foi unida com Mesa (\d+)');
        final match = regex.firstMatch(linha);
        if (match != null) {
          final mesaOrigem = match.group(1);
          final mesaDestino = match.group(2);
          if (mesaOrigem != null && mesaDestino != null) {
            mesasUnidas.add('Mesa $mesaOrigem → Mesa $mesaDestino');
          }
        }
      } else if (linha.contains('MESA UNIDA')) {
        // Extrair número da mesa destino do padrão: "Esta mesa foi unida com a Mesa Y"
        final regex = RegExp(r'unida com a Mesa (\d+)');
        final match = regex.firstMatch(linha);
        if (match != null) {
          final mesaDestino = match.group(1);
          if (mesaDestino != null) {
            mesasUnidas.add('Unida com Mesa $mesaDestino');
          }
        }
      }
    }
    
    if (mesasUnidas.isEmpty) {
      return 'Esta mesa foi unida com outras mesas';
    }
    
    return mesasUnidas.join('\n');
  }

  /// Extrai resumo das mesas unidas para exibição compacta
  String _extrairResumoMesasUnidas(String observacao) {
    final linhas = observacao.split('\n');
    final mesasOrigem = <String>[];
    
    for (final linha in linhas) {
      if (linha.contains('UNIÃO DE MESAS')) {
        // Extrair número da mesa origem do padrão: "Mesa X foi unida com Mesa Y"
        final regex = RegExp(r'Mesa (\d+) foi unida com Mesa (\d+)');
        final match = regex.firstMatch(linha);
        if (match != null) {
          final mesaOrigem = match.group(1);
          if (mesaOrigem != null && !mesasOrigem.contains(mesaOrigem)) {
            mesasOrigem.add(mesaOrigem);
          }
        }
      }
    }
    
    if (mesasOrigem.isEmpty) {
      return 'Unida com outras mesas';
    }
    
    if (mesasOrigem.length == 1) {
      return 'Unida com Mesa ${mesasOrigem.first}';
    } else {
      return 'Unida com Mesas: ${mesasOrigem.join(', ')}';
    }
  }


  /// Mostra histórico de pagamentos da mesa
  void _mostrarHistoricoPagamentos(MesaComanda mesa) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    final dataService = Provider.of<DataService>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Histórico de Pagamentos',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${mesa.tipo == TipoControle.comanda ? "Comanda" : "Mesa"}: ${mesa.numero}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total: ${formatoMoeda.format(_getTotalMesaComComandas(mesa, dataService))}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  Text(
                    'Pago: ${formatoMoeda.format(mesa.totalPago)}',
                    style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              if (mesa.historicoPagamentos.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'Nenhum pagamento registrado',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: mesa.historicoPagamentos.length,
                    itemBuilder: (context, index) {
                      final pagamento = mesa.historicoPagamentos[index];
                      
                      // Buscar informações dos itens pagos
                      final itensPagosInfo = <String>[];
                      if (pagamento.itensPagos != null && pagamento.itensPagos!.isNotEmpty) {
                        for (final itemId in pagamento.itensPagos!) {
                          final item = mesa.itens.firstWhere(
                            (i) => i.id == itemId,
                            orElse: () => mesa.itens.first,
                          );
                          itensPagosInfo.add('${item.quantidade}x ${item.nome}');
                        }
                      }
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: const Color(0xFF2A2A3E),
                        child: ExpansionTile(
                          leading: const Icon(Icons.payment, color: Colors.green),
                          title: Text(
                            formatoMoeda.format(pagamento.valor),
                            style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (pagamento.pessoaPagou != null) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.person, size: 14, color: Colors.blue),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Pagou: ${pagamento.pessoaPagou}',
                                      style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                'Forma: ${pagamento.formaPagamento ?? "Não informado"}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                formatoData.format(pagamento.dataPagamento),
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                          children: [
                            if (itensPagosInfo.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Text(
                                  'Itens pagos:',
                                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                              ...itensPagosInfo.map((itemInfo) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle, size: 14, color: Colors.green),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        itemInfo,
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                              const SizedBox(height: 8),
                            ],
                            if (pagamento.observacao != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Text(
                                  pagamento.observacao!,
                                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _exibirDialogoAdicionaisWaiter(BuildContext context, Produto produto, Function(List<AdicionalProduto>) onConfirm) {
    List<AdicionalProduto> selecionados = [];
    final precoBase = produto.precoAtual;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalAdicionais = selecionados.fold(0.0, (sum, a) => sum + a.preco);
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(produto.nome, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Selecione os adicionais:', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 12),
                  Flexible(
                    child: Consumer<DataService>(
                      builder: (context, dataService, _) {
                        final empresa = dataService.empresaAtual;
                        
                        // Combinar adicionais específicos do produto com os globais da empresa
                        final List<AdicionalProduto> listaExibicao = [...produto.adicionais.where((a) => a.ativo)];
                        if (empresa != null && empresa.modelosAdicionais.isNotEmpty) {
                          for (final modelo in empresa.modelosAdicionais) {
                            final nomeNormalizado = modelo.nome.trim().toLowerCase();
                            if (!listaExibicao.any((a) => a.nome.trim().toLowerCase() == nomeNormalizado)) {
                              listaExibicao.add(modelo);
                            }
                          }
                        }

                        if (listaExibicao.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Text('Nenhum adicional disponível', style: TextStyle(color: Colors.white24)),
                            ),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: listaExibicao.length,
                          itemBuilder: (context, index) {
                            final adicional = listaExibicao[index];
                            final qtd = selecionados.where((s) => s.id == adicional.id).length;
                            final estaSelecionado = qtd > 0;
                            
                            return ListTile(
                              dense: true,
                              title: Text(adicional.nome, style: const TextStyle(color: Colors.white, fontSize: 14)),
                              subtitle: Text('+ R\$ ${adicional.preco.toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (estaSelecionado) ...[
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white38),
                                      onPressed: () {
                                        setDialogState(() {
                                          final idx = selecionados.indexWhere((s) => s.id == adicional.id);
                                          if (idx != -1) selecionados.removeAt(idx);
                                        });
                                      },
                                    ),
                                    Text('$qtd', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  ],
                                  IconButton(
                                    icon: Icon(estaSelecionado ? Icons.add_circle : Icons.add_circle_outline, 
                                      color: estaSelecionado ? Colors.orange : Colors.white24),
                                    onPressed: () {
                                      setDialogState(() {
                                        selecionados.add(adicional);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      }
                    ),
                  ),
                  const Divider(color: Colors.white24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(color: Colors.white)),
                      Text('R\$ ${(precoBase + totalAdicionais).toStringAsFixed(2)}', 
                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  onConfirm(List<AdicionalProduto>.from(selecionados));
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('ADICIONAR'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _transferirItensMesa(MesaComanda mesaOrigem, DataService dataService) async {
    final isComandaOrigem = mesaOrigem.tipo == TipoControle.comanda;
    
    // Obter apenas itens não cancelados e não pagos da mesa origem
    final itensDisponiveisParaTransferencia = mesaOrigem.itens
        .where((item) => item.status != StatusItem.cancelado && !mesaOrigem.itensPagos.contains(item.id))
        .toList();
        
    if (itensDisponiveisParaTransferencia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há itens ativos disponíveis para transferência nesta mesa/comanda.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Obter todas as outras mesas e comandas ativas (Abertas)
    final destinosDisponiveis = dataService.todasMesasComandas
        .where((m) => m.id != mesaOrigem.id && m.status == 'Aberta' && m.id != 'carrinho-deletados')
        .toList();

    // Map para armazenar a quantidade selecionada de cada item (inicializado com 0)
    final quantidadesSelecionadas = <String, double>{};
    for (final item in itensDisponiveisParaTransferencia) {
      quantidadesSelecionadas[item.id] = 0;
    }

    MesaComanda? destinoSelecionado;

    // Abrir o diálogo
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final temItensSelecionados = quantidadesSelecionadas.values.any((q) => q > 0);
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: Text(
              'Transferir Itens',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Origem: ${isComandaOrigem ? "Comanda" : "Mesa"} ${mesaOrigem.numero}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Selecione as quantidades a transferir:',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ...itensDisponiveisParaTransferencia.map((item) {
                      final qtdMax = item.quantidade;
                      final qtdSel = quantidadesSelecionadas[item.id] ?? 0;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: qtdSel > 0 ? Colors.deepOrange.withOpacity(0.5) : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          title: Text(item.nome, style: const TextStyle(color: Colors.white, fontSize: 14)),
                          subtitle: Text('R\$ ${item.preco.toStringAsFixed(2)} cada', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                onPressed: qtdSel > 0 
                                  ? () => setDialogState(() => quantidadesSelecionadas[item.id] = (qtdSel - 1).clamp(0, qtdMax))
                                  : null,
                              ),
                              Text(
                                '${qtdSel.toInt()} / ${qtdMax.toInt()}',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 20),
                                onPressed: qtdSel < qtdMax 
                                  ? () => setDialogState(() => quantidadesSelecionadas[item.id] = (qtdSel + 1).clamp(0, qtdMax))
                                  : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const Divider(color: Colors.white24, height: 24),
                    const Text(
                      '2. Selecione a mesa ou comanda de destino:',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (destinoSelecionado != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.deepOrange),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Destino: ${destinoSelecionado!.tipo == TipoControle.mesa ? "Mesa" : "Comanda"} ${destinoSelecionado!.numero} (${destinoSelecionado!.clienteNome ?? 'Sem cliente'})',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setDialogState(() => destinoSelecionado = null),
                              child: const Text('Alterar', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: destinosDisponiveis.isEmpty
                          ? const Center(child: Text('Nenhuma outra mesa/comanda aberta.', style: TextStyle(color: Colors.grey, fontSize: 12)))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: destinosDisponiveis.length,
                              itemBuilder: (context, index) {
                                final dest = destinosDisponiveis[index];
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    dest.tipo == TipoControle.mesa ? Icons.table_restaurant : Icons.receipt_long,
                                    color: dest.tipo == TipoControle.mesa ? Colors.orange : Colors.purpleAccent,
                                    size: 18,
                                  ),
                                  title: Text('${dest.tipo == TipoControle.mesa ? "Mesa" : "Comanda"} ${dest.numero}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  subtitle: Text(dest.clienteNome ?? 'Sem cliente', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                  onTap: () => setDialogState(() => destinoSelecionado = dest),
                                );
                              },
                            ),
                      ),
                      const SizedBox(height: 8),
                      // Botão para criar novo destino
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final novoDest = await showDialog<MesaComanda>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF1E1E2E),
                                title: const Text('Criar Novo Destino', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () async {
                                        final m = await _abrirNovaMesa(context, dataService);
                                        if (m != null && context.mounted) Navigator.pop(context, m);
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size(double.infinity, 40)),
                                      child: const Text('Nova Mesa Física'),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: () async {
                                        final c = await _abrirNovaComanda(context, dataService);
                                        if (c != null && context.mounted) Navigator.pop(context, c);
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, minimumSize: const Size(double.infinity, 40)),
                                      child: const Text('Nova Comanda Virtual'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (novoDest != null) {
                              setDialogState(() {
                                destinosDisponiveis.add(novoDest);
                                destinoSelecionado = novoDest;
                              });
                            }
                          },
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Criar Nova Mesa/Comanda', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: (temItensSelecionados && destinoSelecionado != null)
                  ? () => Navigator.pop(context, {
                      'destino': destinoSelecionado,
                      'quantidades': quantidadesSelecionadas,
                    })
                  : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );

    if (resultado == null) return;
    
    final MesaComanda destino = resultado['destino'] as MesaComanda;
    final Map<String, double> qtds = resultado['quantidades'] as Map<String, double>;
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final usuarioLogado = authService.usuarioAtual?.nome ?? 'Sistema';

      // Buscar cópias atualizadas
      final mesaOrigemAtual = dataService.todasMesasComandas.firstWhere((m) => m.id == mesaOrigem.id);
      final mesaDestinoAtual = dataService.todasMesasComandas.firstWhere((m) => m.id == destino.id);
      
      final novosItensOrigem = <ItemMesaComanda>[];
      final novosItensDestino = [...mesaDestinoAtual.itens];
      
      for (final item in mesaOrigemAtual.itens) {
        final double qtdTransferir = qtds[item.id] ?? 0.0;
        
        if (qtdTransferir <= 0.0) {
          novosItensOrigem.add(item);
        } else if (qtdTransferir >= item.quantidade) {
          // Transferir tudo
          novosItensDestino.add(item.copyWith(
            id: uuid.v4(),
            dataModificacao: DateTime.now(),
            usuarioModificou: usuarioLogado,
            acaoRealizada: 'Transferido de ${mesaOrigemAtual.numero}',
          ));
          // Registra item como cancelado/transferido na origem para fins de auditoria no histórico
          novosItensOrigem.add(item.copyWith(
            status: StatusItem.cancelado,
            quantidade: item.quantidade,
            usuarioModificou: usuarioLogado,
            acaoRealizada: 'Transferido para ${mesaDestinoAtual.numero}',
            dataModificacao: DateTime.now(),
          ));
        } else {
          // Transferência parcial
          final double qtdRestante = item.quantidade - qtdTransferir;
          
          novosItensDestino.add(item.copyWith(
            id: uuid.v4(),
            quantidade: qtdTransferir,
            dataModificacao: DateTime.now(),
            usuarioModificou: usuarioLogado,
            acaoRealizada: 'Transferência parcial de ${mesaOrigemAtual.numero}',
          ));
          
          novosItensOrigem.add(item.copyWith(
            quantidade: qtdRestante,
            dataModificacao: DateTime.now(),
            usuarioModificou: usuarioLogado,
            acaoRealizada: 'Transferido $qtdTransferir para ${mesaDestinoAtual.numero}',
          ));
          
          novosItensOrigem.add(item.copyWith(
            id: uuid.v4(),
            status: StatusItem.cancelado,
            quantidade: qtdTransferir,
            usuarioModificou: usuarioLogado,
            acaoRealizada: 'Transferido para ${mesaDestinoAtual.numero}',
            dataModificacao: DateTime.now(),
          ));
        }
      }
      
      // Atualizar no banco
      await dataService.updateMesaComanda(mesaOrigemAtual.copyWith(
        itens: novosItensOrigem,
        updatedAt: DateTime.now(),
        usuarioModificou: usuarioLogado,
      ));
      
      await dataService.updateMesaComanda(mesaDestinoAtual.copyWith(
        itens: novosItensDestino,
        updatedAt: DateTime.now(),
        usuarioModificou: usuarioLogado,
      ));
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Itens transferidos com sucesso para a ${destino.tipo == TipoControle.mesa ? "Mesa" : "Comanda"} ${destino.numero}!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          if (_mesaSelecionada?.id == mesaOrigem.id) {
            _mesaSelecionada = dataService.todasMesasComandas.firstWhere((m) => m.id == mesaOrigem.id);
          }
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao transferir itens: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

