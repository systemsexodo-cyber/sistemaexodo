import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../models/mesa_comanda.dart';
import '../models/produto.dart';
import 'venda_direta_page.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

/// Página de controle de mesas e comandas
class ControleMesasComandasPage extends StatefulWidget {
  const ControleMesasComandasPage({super.key});

  @override
  State<ControleMesasComandasPage> createState() => _ControleMesasComandasPageState();
}

class _ControleMesasComandasPageState extends State<ControleMesasComandasPage> {
  TipoControle _tipoSelecionado = TipoControle.mesa;
  String _filtroStatus = 'Todas'; // Todas, Abertas, Fechadas
  String _filtroSetor = 'Todos'; // Todos, Cozinha, Bar
  MesaComanda? _mesaComandaSelecionada;
  String _termoBusca = '';
  final _buscaController = TextEditingController();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true);
    
    // Por enquanto, vamos usar uma lista em memória (depois integrar com DataService)
    // TODO: Adicionar gerenciamento de mesas/comandas no DataService
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E2E),
          elevation: 0,
          title: const Text(
            'Controle de Mesas e Comandas',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          bottom: TabBar(
            onTap: (index) {
              setState(() {
                _tipoSelecionado = index == 0 ? TipoControle.mesa : TipoControle.comanda;
                _mesaComandaSelecionada = null;
              });
            },
            indicatorColor: Colors.orange,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(
                icon: Icon(Icons.table_restaurant),
                text: 'MESAS',
              ),
              Tab(
                icon: Icon(Icons.receipt_long),
                text: 'COMANDAS',
              ),
            ],
          ),
        ),
        body: _mesaComandaSelecionada != null
            ? _buildDetalhesMesaComanda(_mesaComandaSelecionada!, dataService)
            : Column(
                children: [
                  _buildFiltros(),
                  Expanded(
                    child: _buildMapaInteligente(dataService),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _abrirNovaMesaComanda(context, dataService),
          icon: const Icon(Icons.add),
          label: Text(_tipoSelecionado == TipoControle.mesa ? 'Nova Mesa' : 'Nova Comanda'),
          backgroundColor: _tipoSelecionado == TipoControle.mesa ? Colors.orange : Colors.purple,
        ),
      ),
    );
  }

  // Removido _buildHeader pois agora usamos AppBar com TabBar

  Widget _buildFiltros() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1E1E2E),
      child: Column(
        children: [
          // Barra de Busca
          TextField(
            controller: _buscaController,
            onChanged: (value) {
              setState(() {
                _termoBusca = value.toLowerCase();
              });
            },
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar mesa ou comanda...',
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.orange),
              suffixIcon: _termoBusca.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _buscaController.clear();
                        setState(() {
                          _termoBusca = '';
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF2A2A3E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Filtro de Status
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A3E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filtroStatus,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2A2A3E),
                      style: const TextStyle(color: Colors.white),
                      icon: const Icon(Icons.filter_list, color: Colors.orange, size: 18),
                      items: ['Todas', 'Abertas', 'Fechadas']
                          .map((status) => DropdownMenuItem(
                                value: status,
                                child: Text(status),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _filtroStatus = value!;
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Filtro de Setor
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A3E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filtroSetor,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2A2A3E),
                      style: const TextStyle(color: Colors.white),
                      icon: const Icon(Icons.restaurant_menu, color: Colors.orange, size: 18),
                      items: ['Todos', 'Cozinha', 'Bar']
                          .map((setor) => DropdownMenuItem(
                                value: setor,
                                child: Text(setor),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _filtroSetor = value!;
                        });
                      },
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

  Widget _buildMapaInteligente(DataService dataService) {
    // Buscar mesas/comandas do DataService
    final todasMesasComandas = dataService.mesasComandas;
    
    // Filtrar por tipo (Mesa ou Comanda)
    var mesasComandas = todasMesasComandas.where((m) => m.tipo == _tipoSelecionado).toList();
    
    // Filtrar por status
    if (_filtroStatus == 'Abertas') {
      mesasComandas = mesasComandas.where((m) => m.status == 'Aberta').toList();
    } else if (_filtroStatus == 'Fechadas') {
      mesasComandas = mesasComandas.where((m) => m.status == 'Fechada').toList();
    }
    
    // Filtrar por setor (Cozinha, Bar)
    if (_filtroSetor == 'Cozinha') {
      mesasComandas = mesasComandas.where((m) => m.itensCozinha.isNotEmpty).toList();
    } else if (_filtroSetor == 'Bar') {
      mesasComandas = mesasComandas.where((m) => m.itensBar.isNotEmpty).toList();
    }
    
    // Filtrar por busca
    if (_termoBusca.isNotEmpty) {
      mesasComandas = mesasComandas.where((m) {
        return m.numero.toLowerCase().contains(_termoBusca) ||
               (m.clienteNome?.toLowerCase().contains(_termoBusca) ?? false);
      }).toList();
    }
    
    // Ordenar: abertas primeiro, depois por número
    mesasComandas.sort((a, b) {
      if (a.status == 'Aberta' && b.status != 'Aberta') return -1;
      if (a.status != 'Aberta' && b.status == 'Aberta') return 1;
      
      // Tentar ordenar numericamente se possível
      final numA = int.tryParse(a.numero.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1000000;
      final numB = int.tryParse(b.numero.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1000000;
      if (numA != numB) return numA.compareTo(numB);
      
      return a.numero.compareTo(b.numero);
    });
    
    if (mesasComandas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _tipoSelecionado == TipoControle.mesa
                  ? Icons.table_restaurant
                  : Icons.receipt_long,
              size: 80,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhuma ${_tipoSelecionado == TipoControle.mesa ? "mesa" : "comanda"} encontrada',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    // Tanto Mesa quanto Comanda agora usam GridView (Quadros)
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: mesasComandas.length,
      itemBuilder: (context, index) {
        return _buildQuadroMesaComanda(mesasComandas[index]);
      },
    );
  }

  Widget _buildQuadroMesaComanda(MesaComanda mesaComanda) {
    final temPendentes = mesaComanda.temItensPendentes;
    final temProntos = mesaComanda.temItensProntos;
    final pendente = mesaComanda.totalPendente;
    final estaPago = mesaComanda.estaTotalmentePago;
    final isComanda = mesaComanda.tipo == TipoControle.comanda;
    
    Color accentColor = isComanda ? const Color(0xFF9C27B0) : const Color(0xFFFF9800);
    if (temPendentes) accentColor = Colors.redAccent;
    else if (temProntos) accentColor = Colors.greenAccent;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A2A3E),
            const Color(0xFF1E1E2E).withOpacity(0.9),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.15),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: accentColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _mesaComandaSelecionada = mesaComanda),
            child: Stack(
              children: [
                // Detalhe decorativo de fundo
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isComanda ? 'COMANDA' : 'MESA',
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          if (temProntos)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, color: Colors.black, size: 10),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        mesaComanda.numero,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (mesaComanda.clienteNome != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            mesaComanda.clienteNome!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${mesaComanda.itens.length} itens',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 11,
                                ),
                              ),
                              if (estaPago)
                                const Text(
                                  'QUITADO',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            estaPago ? 'PAID' : NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(pendente),
                            style: TextStyle(
                              color: estaPago ? Colors.greenAccent : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
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
        ),
      ),
    );
  }

  Widget _buildCardMesaComanda(MesaComanda mesaComanda) {
    final temPendentes = mesaComanda.temItensPendentes;
    final temProntos = mesaComanda.temItensProntos;
    final estaPago = mesaComanda.estaTotalmentePago;
    final isComanda = mesaComanda.tipo == TipoControle.comanda;
    
    Color accentColor = isComanda ? const Color(0xFF9C27B0) : const Color(0xFFFF9800);
    if (temPendentes) accentColor = Colors.redAccent;
    else if (temProntos) accentColor = Colors.greenAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: () => setState(() => _mesaComandaSelecionada = mesaComanda),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    mesaComanda.numero.replaceAll(RegExp(r'[^0-9]'), ''),
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isComanda ? 'COMANDA' : 'MESA',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (estaPago)
                          const Text(
                            '• PAGO',
                            style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mesaComanda.clienteNome ?? 'Sem Cliente',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(mesaComanda.totalPendente),
                    style: TextStyle(
                      color: estaPago ? Colors.greenAccent : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${mesaComanda.itens.length} itens',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetalhesMesaComanda(MesaComanda mesaComanda, DataService dataService) {
    final itensCozinha = mesaComanda.itensCozinha;
    final itensBar = mesaComanda.itensBar;
    final itensOutros = mesaComanda.itens
        .where((i) => i.paraCozinha != true && i.paraBar != true)
        .toList();

    return Column(
      children: [
        // Header com botão voltar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _mesaComandaSelecionada = null;
                  });
                },
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mesaComanda.numero,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (mesaComanda.clienteNome != null)
                      Text(
                        mesaComanda.clienteNome!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.greenAccent),
                    onPressed: () => _adicionarProdutosAMesaComanda(context, mesaComanda, dataService),
                    tooltip: 'Adicionar Produtos',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    color: const Color(0xFF2A2A3E),
                    onSelected: (value) async {
                      if (value == 'fechar') {
                        _fecharMesaComanda(context, mesaComanda, dataService);
                      } else if (value == 'editarCouvert') {
                        _editarCouvert(context, mesaComanda, dataService);
                      } else if (value == 'limpar') {
                        _limparMesaComanda(context, mesaComanda, dataService);
                      } else if (value == 'receber') {
                        _navegarParaReceber(context, mesaComanda);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'editarCouvert',
                        child: Row(
                          children: [
                            Icon(Icons.music_note, color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Text('Editar Couvert', style: TextStyle(color: Colors.orange)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'fechar',
                        child: Row(
                          children: [
                            Icon(Icons.close, color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Text('Fechar', style: TextStyle(color: Colors.orange)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'receber',
                        child: Row(
                          children: [
                            Icon(Icons.monetization_on, color: Colors.greenAccent, size: 20),
                            SizedBox(width: 8),
                            Text('Receber / Finalizar', style: TextStyle(color: Colors.greenAccent)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'limpar',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep, color: Colors.redAccent, size: 20),
                            SizedBox(width: 8),
                            Text('Limpar Mesa (Histórico)', style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        // Card de Couvert
        if (mesaComanda.quantidadePessoasCouvert != null && mesaComanda.valorCouvertPorPessoa != null)
          Container(
            margin: const EdgeInsets.all(16),
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
                        '${mesaComanda.quantidadePessoasCouvert} pessoa(s) × ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(mesaComanda.valorCouvertPorPessoa)} = ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(mesaComanda.valorCouvertCalculado)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.orange),
                  onPressed: () => _editarCouvert(context, mesaComanda, dataService),
                  tooltip: 'Editar Couvert',
                ),
              ],
            ),
          ),
        // Tabs para Cozinha, Bar e Outros
        Expanded(
          child: DefaultTabController(
            length: 3,
            child: Column(
              children: [
                TabBar(
                  labelColor: Colors.orange,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.orange,
                  tabs: const [
                    Tab(text: 'Cozinha', icon: Icon(Icons.restaurant)),
                    Tab(text: 'Bar', icon: Icon(Icons.local_bar)),
                    Tab(text: 'Outros', icon: Icon(Icons.inventory)),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildListaItens(itensCozinha, mesaComanda, dataService),
                      _buildListaItens(itensBar, mesaComanda, dataService),
                      _buildListaItens(itensOutros, mesaComanda, dataService),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Rodapé de Ações Rápidas
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _navegarParaReceber(context, mesaComanda),
                  icon: const Icon(Icons.monetization_on),
                  label: const Text('RECEBER / FINALIZAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: ElevatedButton.icon(
                  onPressed: () => _limparMesaComanda(context, mesaComanda, dataService),
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('LIMPAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListaItens(
    List<ItemMesaComanda> itens,
    MesaComanda mesaComanda,
    DataService dataService,
  ) {
    if (itens.isEmpty) {
      return Center(
        child: Text(
          'Nenhum item para ${itens == mesaComanda.itensCozinha ? "cozinha" : itens == mesaComanda.itensBar ? "bar" : "outros"}',
          style: TextStyle(
            color: Colors.grey.withOpacity(0.7),
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: itens.length,
      itemBuilder: (context, index) {
        final item = itens[index];
        return _buildCardItem(item, mesaComanda, dataService);
      },
    );
  }

  Widget _buildCardItem(
    ItemMesaComanda item,
    MesaComanda mesaComanda,
    DataService dataService,
  ) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (item.status) {
      case StatusItem.pendente:
        statusColor = Colors.red;
        statusIcon = Icons.access_time;
        statusText = 'Pendente';
        break;
      case StatusItem.emPreparo:
        statusColor = Colors.orange;
        statusIcon = Icons.restaurant_menu;
        statusText = 'Em Preparo';
        break;
      case StatusItem.pronto:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Pronto';
        break;
      case StatusItem.entregue:
        statusColor = Colors.blue;
        statusIcon = Icons.done_all;
        statusText = 'Entregue';
        break;
      case StatusItem.cancelado:
        statusColor = Colors.red.shade700;
        statusIcon = Icons.cancel;
        statusText = 'CANCELADO';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1E1E2E),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Qtd: ${item.quantidade} x ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.preco)}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (item.status == StatusItem.pendente)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _marcarEmPreparo(item, mesaComanda, dataService),
                      icon: const Icon(Icons.restaurant_menu, size: 18),
                      label: const Text('Em Preparo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                if (item.status == StatusItem.emPreparo) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _marcarPronto(item, mesaComanda, dataService),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Pronto'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                if (item.status == StatusItem.pronto) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _marcarEntregue(item, mesaComanda, dataService),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Entregue'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                if (item.status == StatusItem.entregue)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.done_all, color: Colors.blue, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Entregue',
                            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _marcarEmPreparo(ItemMesaComanda item, MesaComanda mesaComanda, DataService dataService) async {
    try {
      await dataService.atualizarStatusItemMesaComanda(
        mesaComanda.id,
        item.id,
        StatusItem.emPreparo,
      );
      setState(() {
        _mesaComandaSelecionada = dataService.mesasComandas.firstWhere((m) => m.id == mesaComanda.id);
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _marcarPronto(ItemMesaComanda item, MesaComanda mesaComanda, DataService dataService) async {
    try {
      await dataService.atualizarStatusItemMesaComanda(
        mesaComanda.id,
        item.id,
        StatusItem.pronto,
      );
      setState(() {
        _mesaComandaSelecionada = dataService.mesasComandas.firstWhere((m) => m.id == mesaComanda.id);
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.nome} marcado como pronto!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _marcarEntregue(ItemMesaComanda item, MesaComanda mesaComanda, DataService dataService) async {
    try {
      await dataService.atualizarStatusItemMesaComanda(
        mesaComanda.id,
        item.id,
        StatusItem.entregue,
      );
      setState(() {
        _mesaComandaSelecionada = dataService.mesasComandas.firstWhere((m) => m.id == mesaComanda.id);
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _abrirNovaMesaComanda(BuildContext context, DataService dataService) {
    final numeroController = TextEditingController();
    final clienteController = TextEditingController();
    final observacaoController = TextEditingController();
    final quantidadePessoasController = TextEditingController();
    final valorCouvertPorPessoaController = TextEditingController();

    showDialog(
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
          final valorPorPessoa = double.tryParse(valorCouvertPorPessoaController.text.trim().replaceAll(',', '.')) ?? 0.0;
          final valorTotalCouvert = quantidadePessoas > 0 && valorPorPessoa > 0 
              ? quantidadePessoas * valorPorPessoa 
              : 0.0;
          
          return AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(
          'Nova ${_tipoSelecionado == TipoControle.mesa ? "Mesa" : "Comanda"}',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: numeroController,
                    onChanged: (value) => setDialogState(() {}),
                    decoration: InputDecoration(
                  labelText: 'Número',
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
                      controller: valorCouvertPorPessoaController,
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: numeroExiste || numeroController.text.trim().isEmpty
                ? null
                : () async {
                    // Validação final antes de criar (dupla verificação)
                    final numeroFinal = numeroController.text.trim();
                    if (numeroFinal.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Por favor, informe o número'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

                    // Verificar se número já existe (em mesas ou comandas)
                    final numeroExisteFinal = dataService.mesasComandas.any(
                      (m) => m.numero == numeroFinal,
              );

                    if (numeroExisteFinal) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                          content: Text('O número $numeroFinal já está em uso por uma mesa ou comanda!'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Obter valores do couvert
              final quantidadePessoasFinal = quantidadePessoasController.text.trim().isEmpty
                  ? null
                  : int.tryParse(quantidadePessoasController.text.trim());
              final valorPorPessoaFinal = valorCouvertPorPessoaController.text.trim().isEmpty
                  ? null
                  : double.tryParse(valorCouvertPorPessoaController.text.trim().replaceAll(',', '.'));

              final novaMesaComanda = MesaComanda(
                id: uuid.v4(),
                tipo: _tipoSelecionado,
                numero: numeroFinal,
                clienteNome: clienteController.text.trim().isEmpty
                    ? null
                    : clienteController.text.trim(),
                itens: [],
                status: 'Aberta',
                observacao: observacaoController.text.trim().isEmpty
                    ? null
                    : observacaoController.text.trim(),
                quantidadePessoasCouvert: quantidadePessoasFinal,
                valorCouvertPorPessoa: valorPorPessoaFinal,
              );

              try {
                await dataService.addMesaComanda(novaMesaComanda);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${_tipoSelecionado == TipoControle.mesa ? "Mesa" : "Comanda"} ${novaMesaComanda.numero} criada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao criar: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Criar'),
          ),
        ],
          );
        },
      ),
    );
  }

  Future<void> _editarCouvert(BuildContext context, MesaComanda mesaComanda, DataService dataService) async {
    final quantidadePessoasController = TextEditingController(
      text: mesaComanda.quantidadePessoasCouvert?.toString() ?? '',
    );
    final valorCouvertPorPessoaController = TextEditingController(
      text: mesaComanda.valorCouvertPorPessoa != null
          ? mesaComanda.valorCouvertPorPessoa!.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Calcular valor total do couvert em tempo real
          final quantidadePessoas = int.tryParse(quantidadePessoasController.text.trim()) ?? 0;
          final valorPorPessoa = double.tryParse(valorCouvertPorPessoaController.text.trim().replaceAll(',', '.')) ?? 0.0;
          final valorTotalCouvert = quantidadePessoas > 0 && valorPorPessoa > 0 
              ? quantidadePessoas * valorPorPessoa 
              : 0.0;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
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
                    controller: valorCouvertPorPessoaController,
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
                            NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valorTotalCouvert),
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
                  final valorPorPessoaFinal = valorCouvertPorPessoaController.text.trim().isEmpty
                      ? null
                      : double.tryParse(valorCouvertPorPessoaController.text.trim().replaceAll(',', '.'));

                  // Validar se pelo menos um campo está preenchido
                  if (quantidadePessoasFinal == null && valorPorPessoaFinal == null) {
                    // Se ambos estiverem vazios, remover o couvert
                    try {
                      final mesaAtualizada = mesaComanda.copyWith(
                        quantidadePessoasCouvert: null,
                        valorCouvertPorPessoa: null,
                      );
                      await dataService.updateMesaComanda(mesaAtualizada);
                      if (context.mounted) {
                        Navigator.pop(context);
                        setState(() {
                          _mesaComandaSelecionada = dataService.mesasComandas.firstWhere((m) => m.id == mesaComanda.id);
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
                    final mesaAtualizada = mesaComanda.copyWith(
                      quantidadePessoasCouvert: quantidadePessoasFinal,
                      valorCouvertPorPessoa: valorPorPessoaFinal,
                    );
                    await dataService.updateMesaComanda(mesaAtualizada);
                    if (context.mounted) {
                      Navigator.pop(context);
                      setState(() {
                        _mesaComandaSelecionada = dataService.mesasComandas.firstWhere((m) => m.id == mesaComanda.id);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Couvert atualizado: ${quantidadePessoasFinal} pessoa(s) × ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valorPorPessoaFinal)}'),
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

  Future<void> _fecharMesaComanda(BuildContext context, MesaComanda mesaComanda, DataService dataService) async {
    // Verificar se há itens pendentes
    if (mesaComanda.temItensPendentes || mesaComanda.temItensEmPreparo) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text(
            'Atenção!',
            style: TextStyle(color: Colors.orange),
          ),
          content: Text(
            '${mesaComanda.numero} ainda tem itens pendentes ou em preparo.\n\nDeseja fechar mesmo assim?',
            style: const TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Fechar Mesmo Assim'),
            ),
          ],
        ),
      );

      if (result != true) return;
    }

    try {
      // IMPORTANTE: Usar limparMesaComanda para salvar o histórico de consumo
      // antes de fechar. Isso garante que a venda apareça no Histórico de Vendas.
      final authService = Provider.of<AuthService>(context, listen: false);
      await dataService.limparMesaComanda(
        mesaComanda.id,
        usuario: authService.usuarioAtual?.nome,
      );

      if (context.mounted) {
        setState(() {
          _mesaComandaSelecionada = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${mesaComanda.numero} fechada com sucesso! Histórico salvo.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fechar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navegarParaReceber(BuildContext context, MesaComanda mesaComanda) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VendaDiretaPage(mesaComanda: mesaComanda),
      ),
    );
  }

  Future<void> _limparMesaComanda(BuildContext context, MesaComanda mesaComanda, DataService dataService) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Limpar Mesa?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Deseja limpar a ${mesaComanda.numero}?\n\nO consumo atual será salvo no histórico de pedidos, e a mesa ficará disponível novamente.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Limpar e Salvar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        await dataService.limparMesaComanda(
          mesaComanda.id, 
          usuario: authService.usuarioAtual?.nome,
        );
        
        if (context.mounted) {
          setState(() {
            _mesaComandaSelecionada = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${mesaComanda.numero} limpa com sucesso! Histórico salvo.'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao limpar mesa: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _adicionarProdutosAMesaComanda(
    BuildContext context,
    MesaComanda mesaComanda,
    DataService dataService,
  ) async {
    final buscaController = TextEditingController();
    final produtosSelecionados = <String, Map<String, dynamic>>{};
    String termoBusca = '';

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

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text(
              'Adicionar Produtos',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Campo de busca
                  TextField(
                    controller: buscaController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Buscar produto...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.orange),
                      suffixIcon: termoBusca.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                buscaController.clear();
                                setDialogState(() {
                                  termoBusca = '';
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF2A2A3E),
                      border: OutlineInputBorder(
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
                        termoBusca = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Lista de produtos
                  Flexible(
                    child: produtosFiltrados.isEmpty
                        ? Center(
                            child: Text(
                              termoBusca.isEmpty
                                  ? 'Nenhum produto cadastrado'
                                  : 'Nenhum produto encontrado',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: produtosFiltrados.length,
                            itemBuilder: (context, index) {
                              final produto = produtosFiltrados[index];
                              final quantidade = produtosSelecionados[produto.id]?['quantidade'] ?? 0;
                              final isSelected = quantidade > 0;

                              return Card(
                                color: isSelected
                                    ? Colors.orange.withOpacity(0.2)
                                    : const Color(0xFF2A2A3E),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(
                                    produto.nome,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (produto.codigo != null)
                                        Text(
                                          'Código: ${produto.codigo}',
                                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                                        ),
                                      Text(
                                        'Preço: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(produto.precoAtual)}',
                                        style: const TextStyle(color: Colors.green, fontSize: 12),
                                      ),
                                      if (produto.paraCozinha == true || produto.paraBar == true)
                                        Row(
                                          children: [
                                            if (produto.paraCozinha == true)
                                              Container(
                                                margin: const EdgeInsets.only(top: 4, right: 4),
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Cozinha',
                                                  style: TextStyle(color: Colors.orange, fontSize: 10),
                                                ),
                                              ),
                                            if (produto.paraBar == true)
                                              Container(
                                                margin: const EdgeInsets.only(top: 4),
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Bar',
                                                  style: TextStyle(color: Colors.blue, fontSize: 10),
                                                ),
                                              ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isSelected) ...[
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                                          onPressed: () {
                                            setDialogState(() {
                                              if (quantidade > 1) {
                                                produtosSelecionados[produto.id] = {
                                                  'produto': produto,
                                                  'quantidade': quantidade - 1,
                                                };
                                              } else {
                                                produtosSelecionados.remove(produto.id);
                                              }
                                            });
                                          },
                                        ),
                                        Text(
                                          '$quantidade',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                      IconButton(
                                        icon: Icon(
                                          isSelected ? Icons.add_circle : Icons.add_circle_outline,
                                          color: Colors.greenAccent,
                                        ),
                                        onPressed: () {
                                          setDialogState(() {
                                            final quantidadeAtual = produtosSelecionados[produto.id]?['quantidade'] ?? 0;
                                            // Usar categoria padrão do produto ou 'outros' se não tiver
                                            final categoriaPadrao = produto.paraCozinha == true
                                                ? 'cozinha'
                                                : produto.paraBar == true
                                                    ? 'bar'
                                                    : 'outros';
                                            produtosSelecionados[produto.id] = {
                                              'produto': produto,
                                              'quantidade': quantidadeAtual + 1,
                                              'categoria': produtosSelecionados[produto.id]?['categoria'] ?? categoriaPadrao,
                                            };
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Resumo dos produtos selecionados
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
                            final total = produto.precoAtual * quantidade;
                            
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
                                  // Seletor de categoria
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setDialogState(() {
                                              produtosSelecionados[entry.key] = {
                                                ...item,
                                                'categoria': 'cozinha',
                                              };
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                            decoration: BoxDecoration(
                                              color: categoria == 'cozinha'
                                                  ? Colors.orange.withOpacity(0.3)
                                                  : Colors.transparent,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: categoria == 'cozinha'
                                                    ? Colors.orange
                                                    : Colors.grey.withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.restaurant,
                                                  size: 14,
                                                  color: categoria == 'cozinha'
                                                      ? Colors.orange
                                                      : Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Cozinha',
                                                  style: TextStyle(
                                                    color: categoria == 'cozinha'
                                                        ? Colors.orange
                                                        : Colors.grey,
                                                    fontSize: 11,
                                                    fontWeight: categoria == 'cozinha'
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setDialogState(() {
                                              produtosSelecionados[entry.key] = {
                                                ...item,
                                                'categoria': 'bar',
                                              };
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                            decoration: BoxDecoration(
                                              color: categoria == 'bar'
                                                  ? Colors.blue.withOpacity(0.3)
                                                  : Colors.transparent,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: categoria == 'bar'
                                                    ? Colors.blue
                                                    : Colors.grey.withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.local_bar,
                                                  size: 14,
                                                  color: categoria == 'bar'
                                                      ? Colors.blue
                                                      : Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Bar',
                                                  style: TextStyle(
                                                    color: categoria == 'bar'
                                                        ? Colors.blue
                                                        : Colors.grey,
                                                    fontSize: 11,
                                                    fontWeight: categoria == 'bar'
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setDialogState(() {
                                              produtosSelecionados[entry.key] = {
                                                ...item,
                                                'categoria': 'outros',
                                              };
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.inventory,
                                                  size: 14,
                                                  color: categoria == 'outros'
                                                      ? Colors.grey
                                                      : Colors.grey.withOpacity(0.5),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Outros',
                                                  style: TextStyle(
                                                    color: categoria == 'outros'
                                                        ? Colors.white
                                                        : Colors.grey,
                                                    fontSize: 11,
                                                    fontWeight: categoria == 'outros'
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Divider(color: Colors.grey),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total:',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(
                                  produtosSelecionados.values.fold<double>(
                                    0.0,
                                    (sum, item) => sum + ((item['produto'] as Produto).precoAtual * (item['quantidade'] as int)),
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
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
                onPressed: produtosSelecionados.isEmpty
                    ? null
                    : () async {
                        try {
                          final novosItens = <ItemMesaComanda>[];

                          for (final item in produtosSelecionados.values) {
                            final produto = item['produto'] as Produto;
                            final quantidade = item['quantidade'] as int;
                            final categoria = item['categoria'] as String? ?? 'outros';

                            novosItens.add(ItemMesaComanda(
                              id: uuid.v4(),
                              itemId: produto.id,
                              nome: produto.nome,
                              quantidade: quantidade,
                              preco: produto.precoAtual,
                              isServico: false,
                              paraCozinha: categoria == 'cozinha',
                              paraBar: categoria == 'bar',
                              status: StatusItem.pendente,
                              dataHora: DateTime.now(),
                            ));
                          }

                          final mesaComandaAtualizada = mesaComanda.copyWith(
                            itens: [...mesaComanda.itens, ...novosItens],
                          );

                          await dataService.updateMesaComanda(mesaComandaAtualizada);

                          if (context.mounted) {
                            Navigator.pop(context);
                            setState(() {
                              _mesaComandaSelecionada = mesaComandaAtualizada;
                            });

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${novosItens.length} produto(s) adicionado(s) à ${mesaComanda.numero}'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao adicionar produtos: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: Text('Adicionar (${produtosSelecionados.values.fold<int>(0, (sum, item) => sum + (item['quantidade'] as int))})'),
              ),
            ],
          );
        },
      ),
    );
  }
}

