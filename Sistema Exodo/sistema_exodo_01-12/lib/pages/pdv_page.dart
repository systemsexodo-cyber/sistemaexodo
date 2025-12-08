import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/pedido.dart';
import '../models/cliente.dart';
import '../models/forma_pagamento.dart';
import '../models/produto.dart';
import '../theme.dart';
import '../widgets/pagamento_widget.dart';
import 'venda_direta_page.dart';
import 'cliente_detalhes_page.dart';

/// Página do PDV - Ponto de Venda com abas
/// Receber Pedidos, Venda Direta e Consulta Cliente
class PdvPage extends StatefulWidget {
  final Pedido? pedidoInicial;
  final int? abaInicial; // 0 = Receber, 1 = Venda, 2 = Cliente
  final bool? esconderAbaVenda; // Se true, esconde a aba de Venda

  const PdvPage({super.key, this.pedidoInicial, this.abaInicial, this.esconderAbaVenda});

  @override
  State<PdvPage> createState() => _PdvPageState();
}

class _PdvPageState extends State<PdvPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _buscaController = TextEditingController();
  String _termoBusca = '';
  Pedido? _pedidoSelecionado;
  bool _pedidosPagosExpandido = false;
  Pedido? _pedidoParaEditar; // Venda salva para editar na aba Venda
  int _vendaPageKey = 0; // Key para forçar rebuild da página de venda
  Cliente? _clienteParaNovaVenda; // Cliente selecionado para nova venda
  
  // Filtros para Contas a Receber
  bool _mostrarPedidosPagos = false;
  bool _mostrarPedidosCancelados = false; // Desmarcado por padrão
  DateTime? _dataInicioFiltro; // Filtro de data inicial
  DateTime? _dataFimFiltro; // Filtro de data final

  // Para consulta de cliente
  Cliente? _clienteConsulta;
  final _buscaClienteController = TextEditingController();
  String _termoBuscaCliente = '';
  String _filtroStatusCliente = 'Todos'; // Todos, Ativos, Inativos, Bloqueados

  @override
  void initState() {
    super.initState();
    // Se esconder aba Venda, teremos apenas 2 abas (Receber e Cliente)
    final numTabs = (widget.esconderAbaVenda == true) ? 2 : 3;
    _tabController = TabController(length: numTabs, vsync: this);
    // Se foi passado um pedido inicial, seleciona ele
    if (widget.pedidoInicial != null) {
      _pedidoSelecionado = widget.pedidoInicial;
      _termoBusca = widget.pedidoInicial!.numero;
      _buscaController.text = widget.pedidoInicial!.numero;
    }
    // Selecionar aba inicial se especificada
    if (widget.abaInicial != null) {
      int abaParaIr = widget.abaInicial!;
      // Se esconder Venda e a aba inicial for Venda (1), ajustar para Receber (0)
      if (widget.esconderAbaVenda == true && abaParaIr == 1) {
        abaParaIr = 0;
      }
      // Ajustar índice se esconder Venda: Cliente (2) vira (1)
      if (widget.esconderAbaVenda == true && abaParaIr == 2) {
        abaParaIr = 1;
      }
      if (abaParaIr >= 0 && abaParaIr < numTabs) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _tabController.animateTo(abaParaIr);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    _buscaClienteController.dispose();
    super.dispose();
  }

  List<Pedido> _buscarPedidos(List<Pedido> pedidos) {
    if (_termoBusca.isEmpty) return [];

    final termo = _termoBusca.trim();
    final termoLower = termo.toLowerCase();
    final numerosNoTermo = termo.replaceAll(RegExp(r'[^0-9]'), '');

    final resultados = pedidos.where((pedido) {
      // IGNORAR pedidos com valor zero (devoluções totais)
      if (pedido.totalRecebido <= 0 && pedido.valorPendente <= 0) {
        return false;
      }

      // Aplicar filtro de data
      if (_dataInicioFiltro != null) {
        final dataPedido = DateTime(
          pedido.dataPedido.year,
          pedido.dataPedido.month,
          pedido.dataPedido.day,
        );
        final dataInicio = DateTime(
          _dataInicioFiltro!.year,
          _dataInicioFiltro!.month,
          _dataInicioFiltro!.day,
        );
        if (dataPedido.isBefore(dataInicio)) return false;
      }
      
      if (_dataFimFiltro != null) {
        final dataPedido = DateTime(
          pedido.dataPedido.year,
          pedido.dataPedido.month,
          pedido.dataPedido.day,
        );
        final dataFim = DateTime(
          _dataFimFiltro!.year,
          _dataFimFiltro!.month,
          _dataFimFiltro!.day,
        ).add(const Duration(days: 1));
        if (dataPedido.isAfter(dataFim)) return false;
      }

      final numeroPedido = pedido.numero.toLowerCase();
      final numeroPedidoLimpo = pedido.numero.replaceAll(RegExp(r'[^0-9]'), '');
      final clienteNome = (pedido.clienteNome ?? '').toLowerCase();

      // 1. Match exato do número do pedido
      if (numeroPedido == termoLower || numeroPedidoLimpo == numerosNoTermo) {
        return true;
      }
      
      // 2. Número do pedido começa com o termo
      if (numeroPedido.startsWith(termoLower) || numeroPedidoLimpo.startsWith(numerosNoTermo)) {
        return true;
      }
      
      // 3. Número do pedido termina com o termo (ex: "01" encontra "PED-0001")
      if (numeroPedidoLimpo.endsWith(numerosNoTermo) && numerosNoTermo.length >= 2) {
        return true;
      }
      
      // 4. Match exato do nome do cliente
      if (clienteNome == termoLower) {
        return true;
      }
      
      // 5. Nome do cliente começa com o termo
      if (clienteNome.startsWith(termoLower)) {
        return true;
      }
      
      // 6. Busca por palavras no nome do cliente
      final palavrasTermo = termoLower.split(' ').where((p) => p.isNotEmpty).toList();
      if (palavrasTermo.isNotEmpty) {
        final palavrasCliente = clienteNome.split(' ');
        final todasPalavrasEncontradas = palavrasTermo.every((palavra) =>
            palavrasCliente.any((pc) => pc.startsWith(palavra) || pc.contains(palavra)));
        if (todasPalavrasEncontradas) {
          return true;
        }
      }
      
      // 7. Nome do cliente contém o termo
      if (clienteNome.contains(termoLower)) {
        return true;
      }
      
      // 8. Número do pedido contém o termo
      if (numeroPedido.contains(termoLower) || numeroPedidoLimpo.contains(numerosNoTermo)) {
        return true;
      }

      return false;
    }).toList();
    
    // Ordenar por relevância: matches exatos primeiro
    resultados.sort((a, b) {
      final aNumero = a.numero.toLowerCase();
      final bNumero = b.numero.toLowerCase();
      final aCliente = (a.clienteNome ?? '').toLowerCase();
      final bCliente = (b.clienteNome ?? '').toLowerCase();
      
      // Priorizar matches exatos
      final aExato = aNumero == termoLower || aCliente == termoLower;
      final bExato = bNumero == termoLower || bCliente == termoLower;
      if (aExato != bExato) return aExato ? -1 : 1;
      
      // Depois matches que começam com o termo
      final aComeca = aNumero.startsWith(termoLower) || aCliente.startsWith(termoLower);
      final bComeca = bNumero.startsWith(termoLower) || bCliente.startsWith(termoLower);
      if (aComeca != bComeca) return aComeca ? -1 : 1;
      
      // Por último, ordenar por data (mais recente primeiro)
      return b.dataPedido.compareTo(a.dataPedido);
    });
    
    return resultados;
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final pedidosEncontrados = _buscarPedidos(dataService.pedidos);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('PDV'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.greenAccent,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: widget.esconderAbaVenda == true
                ? const [
                    Tab(icon: Icon(Icons.receipt_long), text: 'Receber'),
                    Tab(icon: Icon(Icons.person_search), text: 'Cliente'),
                  ]
                : const [
                    Tab(icon: Icon(Icons.receipt_long), text: 'Receber'),
                    Tab(icon: Icon(Icons.shopping_cart), text: 'Venda'),
                    Tab(icon: Icon(Icons.person_search), text: 'Cliente'),
                  ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: widget.esconderAbaVenda == true
              ? [
                  // Aba 1: Receber Pedidos
                  _buildAbaReceberPedidos(dataService, pedidosEncontrados),
                  // Aba 2: Consulta Cliente
                  _buildAbaConsultaCliente(dataService),
                ]
              : [
                  // Aba 1: Receber Pedidos
                  _buildAbaReceberPedidos(dataService, pedidosEncontrados),
                  // Aba 2: Venda Direta
                  VendaDiretaPage(
                    key: ValueKey(_vendaPageKey),
                    pedidoParaEditar: _pedidoParaEditar,
                    clienteInicial: _clienteParaNovaVenda,
                    onVendaFinalizada: () {
                      setState(() {
                        _pedidoParaEditar = null;
                        _clienteParaNovaVenda = null; // Limpa cliente após venda
                        _vendaPageKey++; // Força rebuild para limpar
                      });
                    },
                  ),
                  // Aba 3: Consulta Cliente
                  _buildAbaConsultaCliente(dataService),
                ],
        ),
      ),
    );
  }

  Widget _buildAbaReceberPedidos(
    DataService dataService,
    List<Pedido> pedidosEncontrados,
  ) {
    return Column(
      children: [
        _buildBarraBusca(),
        Expanded(
          child: _pedidoSelecionado != null
              ? _buildPedidoDetalhes(_pedidoSelecionado!, dataService)
              : _termoBusca.isEmpty
              ? _buildEstadoInicial()
              : pedidosEncontrados.isEmpty
              ? _buildNenhumResultado()
              : _buildListaResultados(pedidosEncontrados, dataService),
        ),
      ],
    );
  }

  Widget _buildAbaConsultaCliente(DataService dataService) {
    final clientesFiltrados = _filtrarClientesTab(dataService.clientes);
    final estatisticas = _calcularEstatisticasClientes(dataService.clientes);

    // Se há cliente selecionado para detalhes, mostra detalhes
    if (_clienteConsulta != null) {
      return Column(
        children: [
          // Botão voltar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _clienteConsulta = null),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.arrow_back,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Voltar para lista',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildDetalhesCliente(dataService, _clienteConsulta!),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Dashboard igual à tela principal
        _buildDashboardClientes(estatisticas),

        // Campo de busca
        _buildCampoBuscaClientes(),

        // Lista de clientes
        Expanded(
          child: clientesFiltrados.isEmpty
              ? _buildListaVaziaClientes()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: clientesFiltrados.length,
                  itemBuilder: (context, index) {
                    return _buildCardClientePDV(
                      dataService,
                      clientesFiltrados[index],
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<Cliente> _filtrarClientesTab(List<Cliente> clientes) {
    var resultado = clientes.toList();

    // Filtro por status
    if (_filtroStatusCliente == 'Ativos') {
      resultado = resultado.where((c) => c.ativo && !c.bloqueado).toList();
    } else if (_filtroStatusCliente == 'Inativos') {
      resultado = resultado.where((c) => !c.ativo).toList();
    } else if (_filtroStatusCliente == 'Bloqueados') {
      resultado = resultado.where((c) => c.bloqueado).toList();
    }

    // Filtro por busca
    if (_termoBuscaCliente.isNotEmpty) {
      final termo = _termoBuscaCliente.toLowerCase();
      resultado = resultado.where((c) {
        return c.nome.toLowerCase().contains(termo) ||
            c.telefone.contains(termo) ||
            (c.cpfCnpj?.contains(termo) ?? false) ||
            (c.email?.toLowerCase().contains(termo) ?? false) ||
            (c.cidade?.toLowerCase().contains(termo) ?? false);
      }).toList();
    }

    // Ordenar por nome
    resultado.sort((a, b) => a.nome.compareTo(b.nome));

    return resultado;
  }

  Map<String, int> _calcularEstatisticasClientes(List<Cliente> clientes) {
    return {
      'total': clientes.length,
      'ativos': clientes.where((c) => c.ativo && !c.bloqueado).length,
      'inativos': clientes.where((c) => !c.ativo).length,
      'bloqueados': clientes.where((c) => c.bloqueado).length,
    };
  }

  Widget _buildDashboardClientes(Map<String, int> stats) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a237e).withOpacity(0.8),
            const Color(0xFF283593).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.people, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Clientes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Cadastro e consulta de clientes',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              // Botão cadastrar cliente
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _abrirCadastroCliente(
                    Provider.of<DataService>(context, listen: false),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_add,
                      color: Colors.greenAccent,
                      size: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Botão filtros
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _mostrarFiltrosClientes,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.filter_list,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCardCliente(
                  'Total',
                  stats['total'].toString(),
                  Colors.blue,
                  Icons.people,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCardCliente(
                  'Ativos',
                  stats['ativos'].toString(),
                  Colors.green,
                  Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCardCliente(
                  'Inativos',
                  stats['inativos'].toString(),
                  Colors.grey,
                  Icons.cancel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCardCliente(
                  'Bloqueados',
                  stats['bloqueados'].toString(),
                  Colors.red,
                  Icons.block,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardCliente(
    String label,
    String valor,
    Color cor,
    IconData icone,
  ) {
    final isSelected =
        (_filtroStatusCliente == label) ||
        (label == 'Total' && _filtroStatusCliente == 'Todos');

    return GestureDetector(
      onTap: () {
        setState(() {
          _filtroStatusCliente = label == 'Total' ? 'Todos' : label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: cor.withOpacity(isSelected ? 0.3 : 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cor.withOpacity(isSelected ? 0.8 : 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icone, color: cor, size: 24),
            const SizedBox(height: 6),
            Text(
              valor,
              style: TextStyle(
                color: cor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampoBuscaClientes() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _buscaClienteController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Buscar por nome, telefone, CPF/CNPJ, e-mail...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          suffixIcon: _termoBuscaCliente.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54),
                  onPressed: () {
                    setState(() {
                      _buscaClienteController.clear();
                      _termoBuscaCliente = '';
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
        onChanged: (value) => setState(() => _termoBuscaCliente = value),
      ),
    );
  }

  Widget _buildCardClientePDV(DataService dataService, Cliente cliente) {
    final isPJ = cliente.tipoPessoa == TipoPessoa.juridica;
    final isBloqueado = cliente.bloqueado;
    final isInativo = !cliente.ativo;

    Color corStatus = Colors.green;
    String statusLabel = 'Ativo';
    if (isBloqueado) {
      corStatus = Colors.red;
      statusLabel = 'Bloqueado';
    } else if (isInativo) {
      corStatus = Colors.grey;
      statusLabel = 'Inativo';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isBloqueado
              ? [Colors.red.shade900.withOpacity(0.3), const Color(0xFF2C3E50)]
              : [const Color(0xFF2C3E50), const Color(0xFF34495E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: isBloqueado
            ? Border.all(color: Colors.red.withOpacity(0.5))
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => setState(() => _clienteConsulta = cliente),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              Row(
                children: [
                  // Avatar
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isPJ
                          ? Colors.purple.withOpacity(0.2)
                          : Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isPJ ? Icons.business : Icons.person,
                      color: isPJ ? Colors.purple : Colors.blue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Nome e tipo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente.nome,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (cliente.nomeFantasia != null &&
                            cliente.nomeFantasia!.isNotEmpty)
                          Text(
                            cliente.nomeFantasia!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isPJ
                                    ? Colors.purple.withOpacity(0.3)
                                    : Colors.blue.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isPJ ? 'PJ' : 'PF',
                                style: TextStyle(
                                  color: isPJ ? Colors.purple : Colors.blue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: corStatus.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                statusLabel,
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

                  // CPF/CNPJ
                  if (cliente.cpfCnpjFormatado != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        cliente.cpfCnpjFormatado!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Contato
              Row(
                children: [
                  // Telefone
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.phone,
                          color: Colors.greenAccent.withOpacity(0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          cliente.telefone,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Email
                  if (cliente.email != null && cliente.email!.isNotEmpty)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.email,
                            color: Colors.blue.withOpacity(0.7),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              cliente.email!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              // Endereço
              if (cliente.endereco != null && cliente.endereco!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.white.withOpacity(0.5),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cliente.enderecoCompleto,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Limite de crédito e Saldo devedor
              if ((cliente.limiteCredito != null &&
                      cliente.limiteCredito! > 0) ||
                  cliente.saldoDevedor > 0) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (cliente.saldoDevedor > 0) ...[
                      Icon(
                        Icons.warning,
                        color: Colors.red.withOpacity(0.7),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Deve: R\$ ${cliente.saldoDevedor.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.red.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (cliente.limiteCredito != null &&
                        cliente.limiteCredito! > 0) ...[
                      Icon(
                        Icons.account_balance_wallet,
                        color: Colors.amber.withOpacity(0.7),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Limite: R\$ ${cliente.limiteCredito!.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.amber.withOpacity(0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListaVaziaClientes() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 24),
          Text(
            _termoBuscaCliente.isNotEmpty
                ? 'Nenhum cliente encontrado'
                : 'Nenhum cliente cadastrado',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _termoBuscaCliente.isNotEmpty
                ? 'Tente buscar por outro termo'
                : 'Clique no botão + para cadastrar',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
          ),
          if (_termoBuscaCliente.isNotEmpty) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _abrirCadastroCliente(
                Provider.of<DataService>(context, listen: false),
              ),
              icon: const Icon(Icons.person_add, size: 20),
              label: const Text('Cadastrar Cliente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.withOpacity(0.3),
                foregroundColor: Colors.greenAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _mostrarFiltrosClientes() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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
            const Text(
              'Filtrar por Status',
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
                _buildChipFiltroCliente(
                  'Todos',
                  Icons.all_inclusive,
                  Colors.blue,
                ),
                _buildChipFiltroCliente(
                  'Ativos',
                  Icons.check_circle,
                  Colors.green,
                ),
                _buildChipFiltroCliente('Inativos', Icons.cancel, Colors.grey),
                _buildChipFiltroCliente('Bloqueados', Icons.block, Colors.red),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildChipFiltroCliente(String label, IconData icone, Color cor) {
    final isSelected = _filtroStatusCliente == label;
    return GestureDetector(
      onTap: () {
        setState(() => _filtroStatusCliente = label);
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

  void _abrirCadastroCliente(DataService dataService) async {
    final resultado = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (context) => const ClienteDetalhesPage(cliente: null),
      ),
    );

    if (resultado != null) {
      setState(() {
        _clienteConsulta = resultado;
        _buscaClienteController.text = resultado.nome;
        _termoBuscaCliente = resultado.nome;
      });
    }
  }

  void _editarCliente(DataService dataService, Cliente cliente) async {
    final resultado = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (context) => ClienteDetalhesPage(cliente: cliente),
      ),
    );

    if (resultado != null) {
      setState(() {
        _clienteConsulta = resultado;
      });
    } else {
      // Pode ter sido excluído, verifica se ainda existe
      final existe = dataService.clientes.any((c) => c.id == cliente.id);
      if (!existe) {
        setState(() {
          _clienteConsulta = null;
        });
      }
    }
  }

  Widget _buildDetalhesCliente(DataService dataService, Cliente cliente) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    // Buscar pedidos do cliente
    final pedidosCliente =
        dataService.pedidos.where((p) => p.clienteId == cliente.id).toList()
          ..sort((a, b) => b.dataPedido.compareTo(a.dataPedido));

    // Calcular estatísticas financeiras
    final estatisticas = _calcularEstatisticasFinanceirasCliente(
      pedidosCliente,
    );

    // Separar pagamentos pendentes e recebidos
    final pagamentosPendentes = <_PagamentoPendenteInfoPDV>[];
    final pagamentosRecebidos = <_PagamentoPendenteInfoPDV>[];

    for (final pedido in pedidosCliente) {
      for (final pag in pedido.pagamentos) {
        final info = _PagamentoPendenteInfoPDV(pedido: pedido, pagamento: pag);
        if (pag.recebido) {
          pagamentosRecebidos.add(info);
        } else {
          pagamentosPendentes.add(info);
        }
      }
    }

    // Ordenar pendentes por vencimento
    pagamentosPendentes.sort((a, b) {
      final dataA = a.pagamento.dataVencimento ?? DateTime.now();
      final dataB = b.pagamento.dataVencimento ?? DateTime.now();
      return dataA.compareTo(dataB);
    });

    // Ordenar recebidos por data de recebimento (mais recentes primeiro)
    pagamentosRecebidos.sort((a, b) {
      final dataA = a.pagamento.dataRecebimento ?? a.pedido.dataPedido;
      final dataB = b.pagamento.dataRecebimento ?? b.pedido.dataPedido;
      return dataB.compareTo(dataA);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card do cliente
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade900, Colors.purple.shade700],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: Text(
                        cliente.nome.isNotEmpty
                            ? cliente.nome[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cliente.nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (cliente.email != null &&
                              cliente.email!.isNotEmpty)
                            Text(
                              cliente.email!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          if (cliente.cpfCnpj != null &&
                              cliente.cpfCnpj!.isNotEmpty)
                            Text(
                              'CPF/CNPJ: ${cliente.cpfCnpj}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoCliente(Icons.phone, cliente.telefone),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoCliente(
                        Icons.location_on,
                        cliente.enderecoCompleto,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Botões de ação
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _editarCliente(dataService, cliente),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.edit,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Editar',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            // Ir para aba de venda com cliente selecionado
                            setState(() {
                              _clienteParaNovaVenda = cliente;
                              _vendaPageKey++; // Força rebuild da VendaDiretaPage
                            });
                            _tabController.animateTo(1); // Vai para aba Venda
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.shopping_cart,
                                  color: Colors.greenAccent,
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Nova Venda',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Dashboard Financeiro
          _buildDashboardFinanceiroCliente(estatisticas, formatoMoeda),

          const SizedBox(height: 20),

          // Análise de Crédito
          _buildAnaliseCreditoCliente(cliente, estatisticas, formatoMoeda),

          const SizedBox(height: 20),

          // Pagamentos Pendentes (A Receber)
          if (pagamentosPendentes.isNotEmpty) ...[
            _buildSecaoTituloCliente(
              'Pagamentos Pendentes',
              Icons.pending_actions,
            ),
            const SizedBox(height: 12),
            ...pagamentosPendentes.map(
              (info) => _buildCardPagamentoPendentePDV(
                info,
                formatoMoeda,
                formatoData,
                dataService,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Histórico de Pagamentos Recebidos
          _buildSecaoTituloCliente('Histórico de Pagamentos', Icons.history),
          const SizedBox(height: 12),
          if (pagamentosRecebidos.isEmpty)
            _buildSemHistoricoPDV()
          else
            ...pagamentosRecebidos
                .take(20)
                .map(
                  (info) => _buildCardPagamentoRecebidoPDV(
                    info,
                    formatoMoeda,
                    formatoData,
                  ),
                ),

          const SizedBox(height: 20),

          // Histórico de Pedidos
          _buildSecaoTituloCliente('Histórico de Pedidos', Icons.receipt_long),
          const SizedBox(height: 12),
          if (pedidosCliente.isEmpty)
            _buildSemHistoricoPDV()
          else
            ...pedidosCliente
                .take(10)
                .map(
                  (pedido) => _buildCardPedidoHistoricoPDV(
                    pedido,
                    formatoMoeda,
                    formatoData,
                  ),
                ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Map<String, dynamic> _calcularEstatisticasFinanceirasCliente(
    List<Pedido> pedidos,
  ) {
    double totalCompras = 0;
    double totalPago = 0;
    double totalPendente = 0;
    double totalVencido = 0;
    int qtdPedidos = pedidos.length;
    int qtdPagamentosPendentes = 0;
    int qtdPagamentosVencidos = 0;
    int diasMaiorAtraso = 0;
    DateTime? ultimaCompra;

    for (final pedido in pedidos) {
      totalCompras += pedido.totalGeral;
      if (ultimaCompra == null || pedido.dataPedido.isAfter(ultimaCompra)) {
        ultimaCompra = pedido.dataPedido;
      }

      for (final pag in pedido.pagamentos) {
        if (pag.recebido) {
          totalPago += pag.valor;
        } else {
          totalPendente += pag.valor;
          qtdPagamentosPendentes++;

          if (pag.dataVencimento != null &&
              pag.dataVencimento!.isBefore(DateTime.now())) {
            totalVencido += pag.valor;
            qtdPagamentosVencidos++;
            final diasAtraso = DateTime.now()
                .difference(pag.dataVencimento!)
                .inDays;
            if (diasAtraso > diasMaiorAtraso) {
              diasMaiorAtraso = diasAtraso;
            }
          }
        }
      }
    }

    // Score de crédito baseado no histórico
    int scoreCredito = 100;
    if (qtdPagamentosVencidos > 0) {
      scoreCredito -= (qtdPagamentosVencidos * 10).clamp(0, 40);
    }
    if (diasMaiorAtraso > 30) scoreCredito -= 20;
    if (diasMaiorAtraso > 60) scoreCredito -= 20;
    if (totalVencido > 500) scoreCredito -= 10;
    scoreCredito = scoreCredito.clamp(0, 100);

    return {
      'totalCompras': totalCompras,
      'totalPago': totalPago,
      'totalPendente': totalPendente,
      'totalVencido': totalVencido,
      'qtdPedidos': qtdPedidos,
      'qtdPagamentosPendentes': qtdPagamentosPendentes,
      'qtdPagamentosVencidos': qtdPagamentosVencidos,
      'diasMaiorAtraso': diasMaiorAtraso,
      'ultimaCompra': ultimaCompra,
      'scoreCredito': scoreCredito,
      'ticketMedio': qtdPedidos > 0 ? totalCompras / qtdPedidos : 0.0,
    };
  }

  Widget _buildDashboardFinanceiroCliente(
    Map<String, dynamic> stats,
    NumberFormat formatoMoeda,
  ) {
    final totalCompras = stats['totalCompras'] as double;
    final totalPago = stats['totalPago'] as double;
    final totalPendente = stats['totalPendente'] as double;
    final totalVencido = stats['totalVencido'] as double;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a237e).withOpacity(0.8),
            const Color(0xFF283593).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatFinanceiroCliente(
                  'Total Compras',
                  formatoMoeda.format(totalCompras),
                  Icons.shopping_cart,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatFinanceiroCliente(
                  'Total Pago',
                  formatoMoeda.format(totalPago),
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatFinanceiroCliente(
                  'Pendente',
                  formatoMoeda.format(totalPendente),
                  Icons.schedule,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatFinanceiroCliente(
                  'Vencido',
                  formatoMoeda.format(totalVencido),
                  Icons.warning,
                  totalVencido > 0 ? Colors.red : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatFinanceiroCliente(
    String label,
    String valor,
    IconData icon,
    Color cor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor, size: 24),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnaliseCreditoCliente(
    Cliente cliente,
    Map<String, dynamic> stats,
    NumberFormat formatoMoeda,
  ) {
    final scoreCredito = stats['scoreCredito'] as int;
    final qtdPedidos = stats['qtdPedidos'] as int;
    final ticketMedio = stats['ticketMedio'] as double;
    final diasMaiorAtraso = stats['diasMaiorAtraso'] as int;
    final qtdVencidos = stats['qtdPagamentosVencidos'] as int;
    final ultimaCompra = stats['ultimaCompra'] as DateTime?;

    Color corScore;
    String statusCredito;
    IconData iconeStatus;

    if (scoreCredito >= 80) {
      corScore = Colors.green;
      statusCredito = 'Excelente';
      iconeStatus = Icons.verified;
    } else if (scoreCredito >= 60) {
      corScore = Colors.lightGreen;
      statusCredito = 'Bom';
      iconeStatus = Icons.thumb_up;
    } else if (scoreCredito >= 40) {
      corScore = Colors.orange;
      statusCredito = 'Regular';
      iconeStatus = Icons.warning;
    } else {
      corScore = Colors.red;
      statusCredito = 'Atenção';
      iconeStatus = Icons.error;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corScore.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: corScore.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconeStatus, color: corScore, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Análise de Crédito',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Row(
                      children: [
                        Text(
                          statusCredito,
                          style: TextStyle(
                            color: corScore,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: corScore.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$scoreCredito pts',
                            style: TextStyle(
                              color: corScore,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Barra de progresso do score
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: scoreCredito / 100,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(corScore),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          // Informações de crédito
          if (cliente.limiteCredito != null && cliente.limiteCredito! > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDetalheCreditoPDV(
                  Icons.account_balance_wallet,
                  'Limite: ${formatoMoeda.format(cliente.limiteCredito)}',
                  Colors.amber,
                ),
                _buildDetalheCreditoPDV(
                  Icons.money_off,
                  'Deve: ${formatoMoeda.format(cliente.saldoDevedor)}',
                  cliente.saldoDevedor > 0 ? Colors.red : Colors.grey,
                ),
                _buildDetalheCreditoPDV(
                  Icons.check_circle,
                  'Disp: ${formatoMoeda.format(cliente.creditoDisponivel)}',
                  Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // Detalhes
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildDetalheCreditoPDV(
                Icons.receipt,
                '$qtdPedidos pedidos',
                Colors.blue,
              ),
              _buildDetalheCreditoPDV(
                Icons.trending_up,
                'Ticket: ${formatoMoeda.format(ticketMedio)}',
                Colors.green,
              ),
              if (qtdVencidos > 0)
                _buildDetalheCreditoPDV(
                  Icons.warning,
                  '$qtdVencidos vencidos',
                  Colors.red,
                ),
              if (diasMaiorAtraso > 0)
                _buildDetalheCreditoPDV(
                  Icons.timer_off,
                  'Maior atraso: $diasMaiorAtraso dias',
                  Colors.orange,
                ),
              if (ultimaCompra != null)
                _buildDetalheCreditoPDV(
                  Icons.calendar_today,
                  'Última: ${DateFormat('dd/MM/yy').format(ultimaCompra)}',
                  Colors.purple,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetalheCreditoPDV(IconData icon, String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cor),
          const SizedBox(width: 6),
          Text(texto, style: TextStyle(color: cor, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSecaoTituloCliente(String titulo, IconData icone) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icone, color: Colors.blue, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          titulo,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCardPagamentoPendentePDV(
    _PagamentoPendenteInfoPDV info,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
    DataService dataService,
  ) {
    final pag = info.pagamento;
    final pedido = info.pedido;
    final isVencido =
        pag.dataVencimento != null &&
        pag.dataVencimento!.isBefore(DateTime.now());
    final diasAtraso = isVencido
        ? DateTime.now().difference(pag.dataVencimento!).inDays
        : 0;

    Color corTipo;
    IconData iconeTipo;

    switch (pag.tipo) {
      case TipoPagamento.crediario:
        corTipo = Colors.purple;
        iconeTipo = Icons.credit_score;
        break;
      case TipoPagamento.boleto:
        corTipo = Colors.orange;
        iconeTipo = Icons.receipt_long;
        break;
      case TipoPagamento.fiado:
        corTipo = Colors.red;
        iconeTipo = Icons.handshake;
        break;
      default:
        corTipo = Colors.blue;
        iconeTipo = Icons.payment;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isVencido
              ? Colors.red.withOpacity(0.5)
              : corTipo.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: corTipo.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconeTipo, color: corTipo, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            pag.tipo.nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (pag.isParcela) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: corTipo.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${pag.numeroParcela}/${pag.parcelas}',
                                style: TextStyle(
                                  color: corTipo,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Pedido ${pedido.numero.isNotEmpty ? pedido.numero : 'Sem número'}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            isVencido ? Icons.warning : Icons.event,
                            size: 12,
                            color: isVencido ? Colors.red : Colors.white54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            pag.dataVencimento != null
                                ? 'Venc: ${formatoData.format(pag.dataVencimento!)}'
                                : 'Sem vencimento',
                            style: TextStyle(
                              color: isVencido ? Colors.red : Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          if (isVencido) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$diasAtraso dias',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  formatoMoeda.format(pag.valor),
                  style: TextStyle(
                    color: isVencido ? Colors.red : Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          // Botão para marcar como recebido
          Container(
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _marcarComoRecebidoPDV(dataService, pedido, pag),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green.withOpacity(0.8),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Marcar como Recebido',
                        style: TextStyle(
                          color: Colors.green.withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _marcarComoRecebidoPDV(
    DataService dataService,
    Pedido pedido,
    PagamentoPedido pagamento,
  ) {
    // Formas de recebimento disponíveis (sem fiado, pois fiado é só para lançamento)
    final formasRecebimento = TipoPagamento.values
        .where((t) => t != TipoPagamento.fiado)
        .toList();

    TipoPagamento? formaSelecionada;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
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
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Valor a receber
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Valor:',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        Text(
                          'R\$ ${pagamento.valor.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tipo original
                  Text(
                    'Forma original: ${pagamento.tipo.nome}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Label
                  const Text(
                    'Como o cliente está pagando?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botões de forma de recebimento
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: formasRecebimento.map((tipo) {
                      final isSelected = formaSelecionada == tipo;
                      final cor = _getCorTipoRecebimento(tipo);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              formaSelecionada = tipo;
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: formaSelecionada == null
                    ? null
                    : () {
                        // Atualizar o pagamento com a nova forma de recebimento
                        final novosPagamentos = pedido.pagamentos.map((p) {
                          if (p.id == pagamento.id) {
                            return PagamentoPedido(
                              id: p.id,
                              tipo: formaSelecionada!,
                              tipoOriginal: p.tipo, // Guardar tipo original
                              valor: p.valor,
                              recebido: true,
                              dataRecebimento: DateTime.now(),
                              dataVencimento: p.dataVencimento,
                              parcelas: p.parcelas,
                              numeroParcela: p.numeroParcela,
                              parcelamentoId: p.parcelamentoId,
                              observacao: p.observacao,
                            );
                          }
                          return p;
                        }).toList();

                        // Atualizar status do pedido
                        final todosRecebidos = novosPagamentos.every(
                          (p) => p.recebido,
                        );

                        final pedidoAtualizado = Pedido(
                          id: pedido.id,
                          numero: pedido.numero,
                          clienteId: pedido.clienteId,
                          clienteNome: pedido.clienteNome,
                          clienteTelefone: pedido.clienteTelefone,
                          clienteEndereco: pedido.clienteEndereco,
                          dataPedido: pedido.dataPedido,
                          status: todosRecebidos ? 'Pago' : pedido.status,
                          produtos: pedido.produtos,
                          servicos: pedido.servicos,
                          pagamentos: novosPagamentos,
                        );

                        dataService.updatePedido(pedidoAtualizado);

                        // Se era fiado, atualizar saldo devedor do cliente
                        if (pagamento.tipo == TipoPagamento.fiado &&
                            pedido.clienteId != null) {
                          final cliente = dataService.clientes.firstWhere(
                            (c) => c.id == pedido.clienteId,
                            orElse: () => Cliente(
                              id: '',
                              nome: '',
                              telefone: '',
                              createdAt: DateTime.now(),
                              updatedAt: DateTime.now(),
                            ),
                          );
                          if (cliente.id.isNotEmpty) {
                            final novoSaldo =
                                (cliente.saldoDevedor - pagamento.valor).clamp(
                                  0.0,
                                  double.infinity,
                                );
                            final clienteAtualizado = cliente.copyWith(
                              saldoDevedor: novoSaldo,
                              updatedAt: DateTime.now(),
                            );
                            dataService.updateCliente(clienteAtualizado);
                          }
                        }

                        Navigator.pop(ctx);
                        setState(() {}); // Refresh

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✓ Recebido via ${formaSelecionada!.nome}!',
                            ),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            margin: EdgeInsets.only(
                              bottom: MediaQuery.of(context).size.height - 150,
                              left: 16,
                              right: 16,
                            ),
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: formaSelecionada != null
                      ? Colors.green
                      : Colors.grey,
                ),
                child: const Text('Confirmar Recebimento'),
              ),
            ],
          );
        },
      ),
    );
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
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
    }
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
      case TipoPagamento.fiado:
        return Colors.red;
      case TipoPagamento.outro:
        return Colors.grey;
    }
  }

  Widget _buildCardPagamentoRecebidoPDV(
    _PagamentoPendenteInfoPDV info,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    final pag = info.pagamento;
    final pedido = info.pedido;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check, color: Colors.green, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pag.tipo.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Pedido ${pedido.numero.isNotEmpty ? pedido.numero : 'Sem número'} • ${formatoData.format(pag.dataRecebimento ?? pedido.dataPedido)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatoMoeda.format(pag.valor),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPedidoHistoricoPDV(
    Pedido pedido,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    final isPago = pedido.totalmenteRecebido;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            pedido.numero.isNotEmpty ? pedido.numero : 'Sem número',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatoData.format(pedido.dataPedido),
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isPago
                  ? Colors.green.withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isPago ? 'Pago' : 'Pendente',
              style: TextStyle(
                color: isPago ? Colors.greenAccent : Colors.orange,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatoMoeda.format(pedido.totalGeral),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemHistoricoPDV() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox, size: 40, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              'Nenhum registro encontrado',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCliente(IconData icon, String texto) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            texto,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildCardEstatistica(
    String titulo,
    String valor,
    IconData icon,
    Color cor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor, size: 24),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            titulo,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraBusca() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1a237e).withOpacity(0.9),
              const Color(0xFF283593).withOpacity(0.9),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.withOpacity(0.3),
                          Colors.teal.withOpacity(0.2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.3),
                      ),
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
                        Row(
                          children: [
                            const Text(
                              'Contas a Receber',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.greenAccent.withOpacity(0.3),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.monetization_on,
                                    color: Colors.greenAccent,
                                    size: 12,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'PDV',
                                    style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Busque pelo número do pedido ou cliente',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_pedidoSelecionado != null)
                    IconButton(
                      onPressed: () =>
                          setState(() => _pedidoSelecionado = null),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _buscaController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Ex: 1, 0001, PED-0001, João...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.greenAccent,
                    size: 28,
                  ),
                  suffixIcon: _termoBusca.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white54),
                          onPressed: () {
                            _buscaController.clear();
                            setState(() {
                              _termoBusca = '';
                              _pedidoSelecionado = null;
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() {
                  _termoBusca = value;
                  _pedidoSelecionado = null;
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEstadoInicial() {
    final dataService = Provider.of<DataService>(context);

    // Pedidos pendentes (a receber) - Crediário, Boleto, parcelados
    // Também incluir pedidos cancelados para mostrar com visual de cancelamento
    // Incluir também pedidos de vendas que têm valor a receber (mesmo sem pagamentos lançados)
    final pedidosPendentes =
        dataService.pedidos
            .where(
              (p) {
                final isCancelado = p.status.toLowerCase() == 'cancelado';
                final isPago = p.totalmenteRecebido;
                
                // Aplicar filtros de status primeiro
                if (isCancelado && !_mostrarPedidosCancelados) return false;
                if (isPago && !_mostrarPedidosPagos) return false;
                
                // Filtrar por data (data do pedido)
                if (_dataInicioFiltro != null) {
                  final dataPedido = DateTime(
                    p.dataPedido.year,
                    p.dataPedido.month,
                    p.dataPedido.day,
                  );
                  final dataInicio = DateTime(
                    _dataInicioFiltro!.year,
                    _dataInicioFiltro!.month,
                    _dataInicioFiltro!.day,
                  );
                  if (dataPedido.isBefore(dataInicio)) return false;
                }
                
                if (_dataFimFiltro != null) {
                  final dataPedido = DateTime(
                    p.dataPedido.year,
                    p.dataPedido.month,
                    p.dataPedido.day,
                  );
                  final dataFim = DateTime(
                    _dataFimFiltro!.year,
                    _dataFimFiltro!.month,
                    _dataFimFiltro!.day,
                  ).add(const Duration(days: 1));
                  if (dataPedido.isAfter(dataFim)) return false;
                }
                
                // Lógica de inclusão - verificar se deve incluir baseado no status
                // Pedidos pagos: só incluir se o filtro permitir (já verificado acima)
                if (isPago) {
                  return true; // Já passou pela verificação do filtro acima
                }
                
                // Pedidos cancelados: só incluir se o filtro permitir (já verificado acima)
                if (isCancelado) {
                  return true; // Já passou pela verificação do filtro acima
                }
                
                // Para pedidos não pagos e não cancelados (pendentes):
                // Incluir se tem pagamentos não totalmente recebidos
                if (p.pagamentos.isNotEmpty && !p.totalmenteRecebido) {
                  return true;
                }
                
                // Verificar se tem fiado ou crediário (mesmo que já pago parcialmente)
                final temFiado = p.pagamentos.any((pag) => 
                  pag.tipo == TipoPagamento.fiado || 
                  pag.tipoOriginal == TipoPagamento.fiado
                );
                final temCrediario = p.pagamentos.any((pag) => 
                  pag.tipo == TipoPagamento.crediario || 
                  pag.tipoOriginal == TipoPagamento.crediario
                );
                
                // SEMPRE incluir pedidos com fiado ou crediário que não estão totalmente recebidos
                if ((temFiado || temCrediario) && !p.totalmenteRecebido) {
                  return true;
                }
                
                // Incluir vendas salvas:
                // 1. Pedidos sem pagamentos (vendas salvas sem pagamento definido)
                // 2. Pedidos com tipo "outro" sem recebimento (vendas salvas antigas)
                // Venda salva: sem pagamentos OU tipo "outro" sem recebimento
                if (p.status == 'Pendente' && !temFiado && !temCrediario) {
                  if (p.pagamentos.isEmpty) {
                    // Pedido sem pagamentos = venda salva sem pagamento definido
                    return true;
                  } else {
                    // Verificar se é tipo "outro" e nenhum recebido
                    final nenhumRecebido = p.pagamentos.every((pag) => !pag.recebido);
                    final tipoPagamento = p.pagamentos.first.tipo;
                    if (tipoPagamento == TipoPagamento.outro && nenhumRecebido) {
                      return true;
                    }
                  }
                }
                
                // Incluir se tem valor a receber (mesmo sem pagamentos lançados ainda)
                if (p.totalGeral > p.totalRecebido) {
                  return true;
                }
                
                // Não incluir por padrão
                return false;
              },
            )
            .toList()
          ..sort((a, b) {
            // Cancelados vão para o final
            final aCancel = a.status.toLowerCase() == 'cancelado' ? 1 : 0;
            final bCancel = b.status.toLowerCase() == 'cancelado' ? 1 : 0;
            if (aCancel != bCancel) return aCancel - bCancel;

            // Ordenar por data de vencimento mais próxima
            final vencA = a.pagamentos
                .where((pag) => !pag.recebido && pag.dataVencimento != null)
                .map((pag) => pag.dataVencimento!)
                .fold<DateTime?>(
                  null,
                  (min, d) => min == null || d.isBefore(min) ? d : min,
                );
            final vencB = b.pagamentos
                .where((pag) => !pag.recebido && pag.dataVencimento != null)
                .map((pag) => pag.dataVencimento!)
                .fold<DateTime?>(
                  null,
                  (min, d) => min == null || d.isBefore(min) ? d : min,
                );
            // Se ambos têm vencimento, ordenar por vencimento
            if (vencA != null && vencB != null) return vencA.compareTo(vencB);
            // Se um tem vencimento e outro não, o com vencimento vem primeiro
            if (vencA != null && vencB == null) return -1;
            if (vencA == null && vencB != null) return 1;
            // Se nenhum tem vencimento, ordenar por data do pedido (mais recente primeiro)
            return b.dataPedido.compareTo(a.dataPedido);
          });

    // Separar fiados e crediário dos outros tipos (ambos agrupam por cliente)
    // Vendas canceladas não entram no agrupamento
    // Incluir também vendas que FORAM fiado/crediário mas já foram pagas (tipoOriginal)
    final pedidosFiadoOuCrediario = pedidosPendentes
        .where(
          (p) =>
              p.status.toLowerCase() != 'cancelado' &&
              p.pagamentos.any(
                (pag) =>
                    (pag.tipo == TipoPagamento.fiado ||
                    pag.tipo == TipoPagamento.crediario ||
                    pag.tipoOriginal == TipoPagamento.fiado ||
                    pag.tipoOriginal == TipoPagamento.crediario),
              ),
        )
        .toList();

    // Outros incluem vendas normais e canceladas (para mostrar com visual de cancelamento)
    final pedidosOutros = pedidosPendentes
        .where(
          (p) =>
              p.status.toLowerCase() == 'cancelado' ||
              !p.pagamentos.any(
                (pag) =>
                    (pag.tipo == TipoPagamento.fiado ||
                    pag.tipo == TipoPagamento.crediario ||
                    pag.tipoOriginal == TipoPagamento.fiado ||
                    pag.tipoOriginal == TipoPagamento.crediario),
              ),
        )
        .toList();

    // Agrupar fiados/crediário por cliente e tipo
    final Map<String, List<Pedido>> fiadosPorCliente = {};
    final Map<String, List<Pedido>> crediariosPorCliente = {};

    for (final pedido in pedidosFiadoOuCrediario) {
      final clienteKey = pedido.clienteId ?? 'sem_cliente';
      // Verificar se tem fiado (pendente ou já pago com tipoOriginal)
      final temFiado = pedido.pagamentos.any(
        (p) =>
            p.tipo == TipoPagamento.fiado ||
            p.tipoOriginal == TipoPagamento.fiado,
      );
      // Verificar se tem crediário (pendente ou já pago com tipoOriginal)
      final temCrediario = pedido.pagamentos.any(
        (p) =>
            p.tipo == TipoPagamento.crediario ||
            p.tipoOriginal == TipoPagamento.crediario,
      );

      if (temFiado) {
        fiadosPorCliente.putIfAbsent(clienteKey, () => []).add(pedido);
      } else if (temCrediario) {
        crediariosPorCliente.putIfAbsent(clienteKey, () => []).add(pedido);
      }
    }

    // Criar lista mista: fiados agrupados + crediários agrupados + outros pedidos
    final List<dynamic> itensLista = [];

    // Adicionar grupos de fiados
    fiadosPorCliente.forEach((clienteId, pedidos) {
      itensLista.add(
        _GrupoCreditoCliente(
          clienteId: clienteId,
          clienteNome: pedidos.first.clienteNome ?? 'Cliente não identificado',
          pedidos: pedidos,
          tipoCredito: TipoPagamento.fiado,
        ),
      );
    });

    // Adicionar grupos de crediário
    crediariosPorCliente.forEach((clienteId, pedidos) {
      itensLista.add(
        _GrupoCreditoCliente(
          clienteId: clienteId,
          clienteNome: pedidos.first.clienteNome ?? 'Cliente não identificado',
          pedidos: pedidos,
          tipoCredito: TipoPagamento.crediario,
        ),
      );
    });

    // Adicionar outros pedidos
    itensLista.addAll(pedidosOutros);

    // Calcular total a receber considerando apenas pedidos não pagos e não cancelados
    // (ou que estão sendo mostrados pelos filtros)
    final totalAReceber = pedidosPendentes.fold<double>(
      0.0,
      (sum, p) {
        final isCancelado = p.status.toLowerCase() == 'cancelado';
        final isPago = p.totalmenteRecebido;
        
        // Se está pago ou cancelado e o filtro não permite mostrar, não conta
        if (isCancelado && !_mostrarPedidosCancelados) return sum;
        if (isPago && !_mostrarPedidosPagos) return sum;
        
        // Para pedidos pagos ou cancelados, retornar 0 no total
        if (isPago || isCancelado) return sum;
        
        // Para pedidos pendentes, somar o valor pendente
        // Se não tem pagamentos, usar totalGeral; senão usar totalPagamentos
        final valorPendente = p.pagamentos.isEmpty
            ? p.totalGeral - p.totalRecebido
            : p.totalPagamentos - p.totalRecebido;
        return sum + valorPendente;
      },
    );

    final pedidosPagosHoje =
        dataService.pedidos
            .where((p) => p.totalmenteRecebido)
            .where((p) => p.status.toLowerCase() != 'cancelado') // Excluir pedidos cancelados
            .where((p) {
          final hoje = DateTime.now();
          if (p.pagamentos.isEmpty) return false;
          final ultimoRecebimento = p.pagamentos
              .where((pag) => pag.recebido && pag.dataRecebimento != null)
              .map((pag) => pag.dataRecebimento!)
              .fold<DateTime?>(
                null,
                (max, d) => max == null || d.isAfter(max) ? d : max,
              );
          if (ultimoRecebimento == null) return false;
          return ultimoRecebimento.day == hoje.day &&
              ultimoRecebimento.month == hoje.month &&
              ultimoRecebimento.year == hoje.year;
        }).toList()..sort((a, b) => b.dataPedido.compareTo(a.dataPedido));

    final totalRecebidoHoje = pedidosPagosHoje.fold<double>(
      0.0,
      (sum, p) => sum + p.totalRecebido,
    );

    // Calcular total recebido/pago considerando os filtros aplicados
    final pedidosPagosFiltrados = dataService.pedidos
        .where((p) => p.totalmenteRecebido)
        .where((p) => p.status.toLowerCase() != 'cancelado')
        .where((p) {
          // Aplicar filtro de data se estiver definido
          if (_dataInicioFiltro != null) {
            final dataPedido = DateTime(
              p.dataPedido.year,
              p.dataPedido.month,
              p.dataPedido.day,
            );
            final dataInicio = DateTime(
              _dataInicioFiltro!.year,
              _dataInicioFiltro!.month,
              _dataInicioFiltro!.day,
            );
            if (dataPedido.isBefore(dataInicio)) return false;
          }
          
          if (_dataFimFiltro != null) {
            final dataPedido = DateTime(
              p.dataPedido.year,
              p.dataPedido.month,
              p.dataPedido.day,
            );
            final dataFim = DateTime(
              _dataFimFiltro!.year,
              _dataFimFiltro!.month,
              _dataFimFiltro!.day,
            ).add(const Duration(days: 1));
            if (dataPedido.isAfter(dataFim)) return false;
          }
          
          return true;
        })
        .toList();

    final totalRecebidoFiltrado = pedidosPagosFiltrados.fold<double>(
      0.0,
      (sum, p) => sum + p.totalRecebido,
    );

    return Column(
      children: [
        // Cabeçalho com resumo
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF1a1a2e), const Color(0xFF16213e)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  color: Colors.orange.shade300,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contas a Receber',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${pedidosPendentes.length} pendente${pedidosPendentes.length != 1 ? 's' : ''}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'R\$ ${totalAReceber.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.orange.shade300,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'a receber',
                    style: TextStyle(
                      color: Colors.orange.shade400,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Resumo de valores recebidos/pagos
        Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.withOpacity(0.2), Colors.teal.withOpacity(0.15)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.greenAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Recebido/Pago',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${pedidosPagosFiltrados.length} pedido${pedidosPagosFiltrados.length != 1 ? 's' : ''} ${_dataInicioFiltro != null || _dataFimFiltro != null ? '(filtrado)' : ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'R\$ ${totalRecebidoFiltrado.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'recebido',
                      style: TextStyle(
                        color: Colors.greenAccent.withOpacity(0.8),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Filtros de Data
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today,
                size: 16,
                color: Colors.orange,
              ),
              const SizedBox(width: 6),
              const Text(
                'Período:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              // Data Inicial
              GestureDetector(
                onTap: () => _selecionarDataFiltro(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _dataInicioFiltro != null
                            ? DateFormat('dd/MM/yyyy').format(_dataInicioFiltro!)
                            : 'Data inicial',
                        style: TextStyle(
                          color: _dataInicioFiltro != null
                              ? Colors.white
                              : Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'até',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              // Data Final
              GestureDetector(
                onTap: () => _selecionarDataFiltro(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _dataFimFiltro != null
                            ? DateFormat('dd/MM/yyyy').format(_dataFimFiltro!)
                            : 'Data final',
                        style: TextStyle(
                          color: _dataFimFiltro != null
                              ? Colors.white
                              : Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Botão Limpar Filtro
              if (_dataInicioFiltro != null || _dataFimFiltro != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _dataInicioFiltro = null;
                      _dataFimFiltro = null;
                    });
                  },
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Limpar'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ),

        // Filtros
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              // Filtro Pedidos Pagos
              FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _mostrarPedidosPagos ? Icons.check_circle : Icons.circle_outlined,
                      size: 14,
                      color: _mostrarPedidosPagos ? Colors.green : Colors.white54,
                    ),
                    const SizedBox(width: 4),
                    const Text('Pagos', style: TextStyle(fontSize: 12)),
                  ],
                ),
                selected: _mostrarPedidosPagos,
                onSelected: (selected) {
                  setState(() {
                    _mostrarPedidosPagos = selected;
                  });
                },
                selectedColor: Colors.green.withOpacity(0.2),
                checkmarkColor: Colors.green,
                labelStyle: TextStyle(
                  color: _mostrarPedidosPagos ? Colors.green : Colors.white54,
                  fontWeight: _mostrarPedidosPagos ? FontWeight.bold : FontWeight.normal,
                ),
                side: BorderSide(
                  color: _mostrarPedidosPagos ? Colors.green : Colors.white24,
                ),
              ),
              const SizedBox(width: 8),
              // Filtro Pedidos Cancelados
              FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _mostrarPedidosCancelados ? Icons.check_circle : Icons.circle_outlined,
                      size: 14,
                      color: _mostrarPedidosCancelados ? Colors.red : Colors.white54,
                    ),
                    const SizedBox(width: 4),
                    const Text('Cancelados', style: TextStyle(fontSize: 12)),
                  ],
                ),
                selected: _mostrarPedidosCancelados,
                onSelected: (selected) {
                  setState(() {
                    _mostrarPedidosCancelados = selected;
                  });
                },
                selectedColor: Colors.red.withOpacity(0.2),
                checkmarkColor: Colors.red,
                labelStyle: TextStyle(
                  color: _mostrarPedidosCancelados ? Colors.red : Colors.white54,
                  fontWeight: _mostrarPedidosCancelados ? FontWeight.bold : FontWeight.normal,
                ),
                side: BorderSide(
                  color: _mostrarPedidosCancelados ? Colors.red : Colors.white24,
                ),
              ),
            ],
          ),
        ),

        // Lista de pedidos pendentes
        Expanded(
          child: pedidosPendentes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green.withOpacity(0.2),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhum valor pendente',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Todas as contas estão quitadas!',
                        style: TextStyle(
                          color: Colors.green.withOpacity(0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: itensLista.length,
                  itemBuilder: (context, index) {
                    final item = itensLista[index];
                    if (item is _GrupoCreditoCliente) {
                      return _buildCardGrupoCredito(item, dataService);
                    } else if (item is Pedido) {
                      return _buildItemPedidoPendente(item, dataService);
                    }
                    return const SizedBox.shrink();
                  },
                ),
        ),

        // Seção Pedidos Pagos Hoje (no canto inferior)
        if (pedidosPagosHoje.isNotEmpty)
          Align(
            alignment: Alignment.bottomLeft,
            child: _pedidosPagosExpandido
                ? Container(
                    margin: const EdgeInsets.only(
                      left: 20,
                      right: 20,
                      bottom: 20,
                    ),
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                      maxWidth: 350,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Cabeçalho clicável
                        GestureDetector(
                          onTap: () =>
                              setState(() => _pedidosPagosExpandido = false),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(15),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.greenAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Pagos Hoje (${pedidosPagosHoje.length})',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  'R\$ ${totalRecebidoHoje.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.greenAccent,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Lista compacta
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(8),
                            itemCount: pedidosPagosHoje.length,
                            itemBuilder: (context, index) {
                              final pedido = pedidosPagosHoje[index];
                              return _buildItemPedidoPagoCompacto(pedido);
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                : // Versão recolhida (pequena)
                  GestureDetector(
                    onTap: () => setState(() => _pedidosPagosExpandido = true),
                    child: Container(
                      margin: const EdgeInsets.only(left: 20, bottom: 20),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${pedidosPagosHoje.length} pagos',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'R\$ ${totalRecebidoHoje.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_up,
                            color: Colors.greenAccent,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _buildItemPedidoPagoCompacto(Pedido pedido) {
    return GestureDetector(
      onTap: () => setState(() => _pedidoSelecionado = pedido),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.check, color: Colors.green, size: 16),
            const SizedBox(width: 8),
            Text(
              pedido.numero.isNotEmpty && pedido.numero.startsWith('VND-')
                  ? pedido.numero
                  : pedido.numero.isNotEmpty
                  ? pedido.numero
                  : 'Sem número',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pedido.clienteNome ?? 'Sem cliente',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'R\$ ${pedido.totalRecebido.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Card para grupo de crédito por cliente (fiado ou crediário) - Design simplificado
  Widget _buildCardGrupoCredito(
    _GrupoCreditoCliente grupo,
    DataService dataService,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    // Cores baseadas no tipo e status
    final isFiado = grupo.tipoCredito == TipoPagamento.fiado;
    final estaPago = grupo.estaPago;
    final corPrincipal = estaPago
        ? Colors.green
        : (isFiado ? Colors.deepOrange : Colors.pink);
    final icone = estaPago
        ? Icons.check_circle
        : (isFiado ? Icons.handshake : Icons.credit_score);
    final tipoTexto = estaPago ? 'PAGO' : (isFiado ? 'Fiado' : 'Crediário');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: estaPago ? const Color(0xFF1B2E1B) : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: corPrincipal.withOpacity(estaPago ? 0.5 : 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho compacto
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: corPrincipal.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icone, color: corPrincipal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            grupo.clienteNome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
                            tipoTexto,
                            style: TextStyle(
                              color: corPrincipal,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${grupo.quantidadeVendas} venda${grupo.quantidadeVendas > 1 ? 's' : ''} • Desde ${formatoData.format(grupo.dataVendaMaisAntiga)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Mostrar total recebido se pago, senão mostrar pendente
                  Text(
                    formatoMoeda.format(
                      estaPago ? grupo.totalRecebido : grupo.totalPendente,
                    ),
                    style: TextStyle(
                      color: corPrincipal,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (!estaPago && grupo.totalRecebido > 0)
                    Text(
                      'Pago: ${formatoMoeda.format(grupo.totalRecebido)}',
                      style: TextStyle(
                        color: Colors.greenAccent.withOpacity(0.7),
                        fontSize: 10,
                      ),
                    ),
                  if (estaPago)
                    Text(
                      'Total quitado',
                      style: TextStyle(
                        color: Colors.greenAccent.withOpacity(0.7),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Barra de progresso simples (se houver pagamentos e não estiver 100% pago)
          if (grupo.totalRecebido > 0 && !estaPago) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: grupo.totalVendas > 0
                    ? grupo.totalRecebido / grupo.totalVendas
                    : 0,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.greenAccent,
                ),
                minHeight: 4,
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Botões de ação
          Row(
            children: [
              // Botão Ver Vendas
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _mostrarVendasCreditoCliente(grupo, dataService),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text(
                    'Ver Vendas',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              // Botão Receber (só mostra se não está totalmente pago)
              if (!estaPago) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => isFiado
                        ? _abrirRecebimentoParcialCredito(grupo, dataService)
                        : _abrirRecebimentoParcelasCrediario(
                            grupo,
                            dataService,
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: corPrincipal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(
                      isFiado ? Icons.payments : Icons.checklist,
                      size: 16,
                    ),
                    label: Text(
                      isFiado ? 'Receber' : 'Receber Parcelas',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Mostrar vendas do crédito (fiado/crediário) do cliente em um dialog
  void _mostrarVendasCreditoCliente(
    _GrupoCreditoCliente grupo,
    DataService dataService,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    final isFiado = grupo.tipoCredito == TipoPagamento.fiado;
    final corPrincipal = isFiado ? Colors.deepOrange : Colors.pink;
    final icone = isFiado ? Icons.handshake : Icons.credit_score;
    final tipoTexto = isFiado ? 'Fiado' : 'Crediário';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: corPrincipal.withOpacity(0.2),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icone, color: corPrincipal),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  grupo.clienteNome,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: corPrincipal.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tipoTexto,
                                  style: TextStyle(
                                    color: corPrincipal,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Total pendente: ${formatoMoeda.format(grupo.totalPendente)}',
                            style: TextStyle(color: corPrincipal, fontSize: 13),
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

              // Lista de vendas
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: grupo.pedidos.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12),
                  itemBuilder: (context, index) {
                    final pedido = grupo.pedidos[index];
                    final isCancelado =
                        pedido.status.toLowerCase() == 'cancelado';
                    final valorCredito = pedido.pagamentos
                        .where((p) => p.tipo == grupo.tipoCredito)
                        .fold(0.0, (sum, p) => sum + p.valor);
                    final valorPago = pedido.pagamentos
                        .where((p) => p.tipo == grupo.tipoCredito && p.recebido)
                        .fold(0.0, (sum, p) => sum + p.valor);
                    final valorPendente = valorCredito - valorPago;
                    final isPago = valorPendente <= 0;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isCancelado
                              ? Colors.red.withOpacity(0.2)
                              : isPago
                              ? Colors.green.withOpacity(0.2)
                              : corPrincipal.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isCancelado
                              ? Icons.cancel
                              : isPago
                              ? Icons.check
                              : Icons.pending,
                          color: isCancelado
                              ? Colors.redAccent
                              : isPago
                              ? Colors.greenAccent
                              : corPrincipal,
                          size: 20,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            pedido.numero.isNotEmpty
                                ? pedido.numero
                                : 'Sem número',
                            style: TextStyle(
                              color: isCancelado
                                  ? Colors.red.withOpacity(0.5)
                                  : Colors.white,
                              fontWeight: FontWeight.w500,
                              decoration: isCancelado
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatoData.format(pedido.dataPedido),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11,
                            ),
                          ),
                          if (isCancelado) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'CANCELADO',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        isCancelado
                            ? 'Venda cancelada'
                            : isPago
                            ? 'Pago: ${formatoMoeda.format(valorCredito)}'
                            : 'Pendente: ${formatoMoeda.format(valorPendente)} de ${formatoMoeda.format(valorCredito)}',
                        style: TextStyle(
                          color: isCancelado
                              ? Colors.red.withOpacity(0.5)
                              : isPago
                              ? Colors.greenAccent.withOpacity(0.7)
                              : corPrincipal.withOpacity(0.7),
                          fontSize: 12,
                          decoration: isCancelado
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      trailing: !isPago && !isCancelado
                          ? IconButton(
                              icon: const Icon(
                                Icons.cancel_outlined,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              tooltip: 'Cancelar venda',
                              onPressed: () {
                                Navigator.pop(context);
                                _confirmarCancelamentoCredito(
                                  pedido,
                                  dataService,
                                  grupo,
                                );
                              },
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Confirmar cancelamento de venda crédito (fiado/crediário)
  void _confirmarCancelamentoCredito(
    Pedido pedido,
    DataService dataService,
    _GrupoCreditoCliente grupo,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final isFiado = grupo.tipoCredito == TipoPagamento.fiado;
    final tipoTexto = isFiado ? 'Fiado' : 'Crediário';

    final valorCredito = pedido.pagamentos
        .where((p) => p.tipo == grupo.tipoCredito)
        .fold(0.0, (sum, p) => sum + p.valor);
    final valorPago = pedido.pagamentos
        .where((p) => p.tipo == grupo.tipoCredito && p.recebido)
        .fold(0.0, (sum, p) => sum + p.valor);
    final valorPendente = valorCredito - valorPago;

    final motivoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.cancel,
                color: Colors.redAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Cancelar Venda $tipoTexto',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Venda: ${pedido.numero.isNotEmpty ? pedido.numero : 'Sem número'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Cliente: ${grupo.clienteNome}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Valor pendente: ${formatoMoeda.format(valorPendente)}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  if (valorPago > 0)
                    Text(
                      'Já foi pago: ${formatoMoeda.format(valorPago)}',
                      style: TextStyle(
                        color: Colors.greenAccent.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Motivo do cancelamento',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                hintText: 'Ex: Cliente desistiu, produto devolvido...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ Esta ação irá cancelar a venda e remover o valor pendente da dívida do cliente.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Voltar',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final motivo = motivoController.text.trim();
              if (motivo.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Por favor, informe o motivo do cancelamento',
                    ),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(
                      top: 50,
                      left: 20,
                      right: 20,
                      bottom: 20,
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context);
              await _processarCancelamentoCredito(
                pedido,
                dataService,
                grupo,
                motivo,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.cancel, size: 18),
            label: const Text('Confirmar Cancelamento'),
          ),
        ],
      ),
    );
  }

  // Processar o cancelamento do crédito (fiado/crediário)
  Future<void> _processarCancelamentoCredito(
    Pedido pedido,
    DataService dataService,
    _GrupoCreditoCliente grupo,
    String motivo,
  ) async {
    try {
      final formatoMoeda = NumberFormat.currency(
        locale: 'pt_BR',
        symbol: 'R\$',
      );
      final tipoTexto = grupo.tipoCredito == TipoPagamento.fiado
          ? 'FIADO'
          : 'CREDIÁRIO';

      // Calcular valor pendente que será cancelado
      final valorPendente = pedido.pagamentos
          .where((p) => p.tipo == grupo.tipoCredito && !p.recebido)
          .fold(0.0, (sum, p) => sum + p.valor);

      // Criar novos pagamentos marcando como cancelados
      final novosPagamentos = pedido.pagamentos.map((pag) {
        if (pag.tipo == grupo.tipoCredito && !pag.recebido) {
          return PagamentoPedido(
            id: pag.id,
            tipo: pag.tipo,
            valor: pag.valor,
            recebido: true,
            dataRecebimento: DateTime.now(),
            dataVencimento: pag.dataVencimento,
            observacao:
                '❌ CANCELADO: $motivo (${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())})',
          );
        }
        return pag;
      }).toList();

      // Atualizar pedido com status cancelado
      final pedidoAtualizado = pedido.copyWith(
        status: 'Cancelado',
        observacoes:
            '${pedido.observacoes ?? ''}\n[$tipoTexto CANCELADO] $motivo'
                .trim(),
        pagamentos: novosPagamentos,
        updatedAt: DateTime.now(),
      );

      dataService.updatePedido(pedidoAtualizado);

      // Atualizar saldo devedor do cliente
      if (pedido.clienteId != null &&
          grupo.tipoCredito == TipoPagamento.fiado) {
        final cliente = dataService.clientes.firstWhere(
          (c) => c.id == pedido.clienteId,
          orElse: () => Cliente(
            id: '',
            nome: '',
            telefone: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        if (cliente.id.isNotEmpty) {
          final novoSaldo = (cliente.saldoDevedor - valorPendente).clamp(
            0.0,
            double.infinity,
          );
          final clienteAtualizado = cliente.copyWith(
            saldoDevedor: novoSaldo,
            updatedAt: DateTime.now(),
          );
          dataService.updateCliente(clienteAtualizado);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Venda ${pedido.numero.isNotEmpty ? pedido.numero : 'Sem número'} cancelada. ${formatoMoeda.format(valorPendente)} removido da dívida.',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(
              top: 50,
              left: 20,
              right: 20,
              bottom: 20,
            ),
          ),
        );
        setState(() {}); // Atualizar a lista
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cancelar venda: $e'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(
              top: 50,
              left: 20,
              right: 20,
              bottom: 20,
            ),
          ),
        );
      }
    }
  }

  // Dialog para receber parcelas de crediário (selecionar parcelas específicas)
  void _abrirRecebimentoParcelasCrediario(
    _GrupoCreditoCliente grupo,
    DataService dataService,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    // Coletar todas as parcelas pendentes de crediário
    final List<_ParcelaCrediario> parcelasPendentes = [];

    for (final pedido in grupo.pedidos) {
      for (int i = 0; i < pedido.pagamentos.length; i++) {
        final pag = pedido.pagamentos[i];
        if (pag.tipo == TipoPagamento.crediario && !pag.recebido) {
          parcelasPendentes.add(
            _ParcelaCrediario(
              pedido: pedido,
              pagamento: pag,
              indicePagamento: i,
              numeroParcela: pag.numeroParcela ?? (i + 1),
              totalParcelas:
                  pag.parcelas ??
                  pedido.pagamentos
                      .where(
                        (p) =>
                            p.tipo == TipoPagamento.crediario ||
                            p.parcelamentoId == pag.parcelamentoId,
                      )
                      .length,
            ),
          );
        }
      }
    }

    // Ordenar por data de vencimento
    parcelasPendentes.sort((a, b) {
      final dataA = a.pagamento.dataVencimento ?? DateTime.now();
      final dataB = b.pagamento.dataVencimento ?? DateTime.now();
      return dataA.compareTo(dataB);
    });

    // Set para controlar parcelas selecionadas
    final Set<String> parcelasSelecionadas = {};
    TipoPagamento? formaSelecionada;

    // Formas de recebimento disponíveis
    final formasRecebimento = TipoPagamento.values
        .where(
          (t) =>
              t != TipoPagamento.fiado &&
              t != TipoPagamento.crediario &&
              t != TipoPagamento.boleto,
        )
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Calcular total das parcelas selecionadas
          double totalSelecionado = 0;
          for (final parcela in parcelasPendentes) {
            if (parcelasSelecionadas.contains(parcela.id)) {
              totalSelecionado += parcela.pagamento.valor;
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.pink.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.checklist,
                    color: Colors.pink,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Receber Parcelas',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      Text(
                        grupo.clienteNome,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Resumo
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.pink.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.pink.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Parcelas Selecionadas',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '${parcelasSelecionadas.length} de ${parcelasPendentes.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Total a Receber',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              formatoMoeda.format(totalSelecionado),
                              style: const TextStyle(
                                color: Colors.pink,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Botão selecionar todas
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            if (parcelasSelecionadas.length ==
                                parcelasPendentes.length) {
                              parcelasSelecionadas.clear();
                            } else {
                              parcelasSelecionadas.clear();
                              for (final p in parcelasPendentes) {
                                parcelasSelecionadas.add(p.id);
                              }
                            }
                          });
                        },
                        icon: Icon(
                          parcelasSelecionadas.length ==
                                  parcelasPendentes.length
                              ? Icons.deselect
                              : Icons.select_all,
                          size: 18,
                        ),
                        label: Text(
                          parcelasSelecionadas.length ==
                                  parcelasPendentes.length
                              ? 'Desmarcar Todas'
                              : 'Selecionar Todas',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Lista de parcelas
                  const Text(
                    'Parcelas Pendentes',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: parcelasPendentes.length,
                      itemBuilder: (context, index) {
                        final parcela = parcelasPendentes[index];
                        final isSelected = parcelasSelecionadas.contains(
                          parcela.id,
                        );
                        final dataVenc = parcela.pagamento.dataVencimento;
                        final isVencida =
                            dataVenc != null &&
                            dataVenc.isBefore(DateTime.now());

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.pink.withOpacity(0.2)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.pink
                                  : isVencida
                                  ? Colors.red.withOpacity(0.5)
                                  : Colors.white.withOpacity(0.1),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: CheckboxListTile(
                            value: isSelected,
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  parcelasSelecionadas.add(parcela.id);
                                } else {
                                  parcelasSelecionadas.remove(parcela.id);
                                }
                              });
                            },
                            activeColor: Colors.pink,
                            checkColor: Colors.white,
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 0,
                            ),
                            title: Row(
                              children: [
                                Text(
                                  'Parcela ${parcela.numeroParcela}/${parcela.totalParcelas}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                if (isVencida) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'VENCIDA',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                Text(
                                  formatoMoeda.format(parcela.pagamento.valor),
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.pink
                                        : Colors.white70,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Row(
                              children: [
                                Text(
                                  parcela.pedido.numero.isNotEmpty
                                      ? parcela.pedido.numero
                                      : 'Sem número',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                                ),
                                if (dataVenc != null) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.event,
                                    size: 12,
                                    color: isVencida
                                        ? Colors.red
                                        : Colors.white38,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    formatoData.format(dataVenc),
                                    style: TextStyle(
                                      color: isVencida
                                          ? Colors.red
                                          : Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Forma de recebimento
                  const Text(
                    'Forma de recebimento',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: formasRecebimento.map((tipo) {
                      final isSelected = formaSelecionada == tipo;
                      final cor = _getCorTipoRecebimento(tipo);

                      return GestureDetector(
                        onTap: () =>
                            setDialogState(() => formaSelecionada = tipo),
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
                                size: 16,
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
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                onPressed:
                    (formaSelecionada == null || parcelasSelecionadas.isEmpty)
                    ? null
                    : () => _processarRecebimentoParcelasCrediario(
                        ctx,
                        parcelasPendentes
                            .where((p) => parcelasSelecionadas.contains(p.id))
                            .toList(),
                        formaSelecionada!,
                        dataService,
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      (formaSelecionada != null &&
                          parcelasSelecionadas.isNotEmpty)
                      ? Colors.pink
                      : Colors.grey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(Icons.check, size: 18),
                label: Text(
                  parcelasSelecionadas.isEmpty
                      ? 'Selecione parcelas'
                      : 'Receber ${parcelasSelecionadas.length} Parcela(s)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Processa o recebimento das parcelas selecionadas de crediário
  void _processarRecebimentoParcelasCrediario(
    BuildContext ctx,
    List<_ParcelaCrediario> parcelasSelecionadas,
    TipoPagamento formaRecebimento,
    DataService dataService,
  ) {
    // Agrupar parcelas por pedido
    final Map<String, List<_ParcelaCrediario>> parcelasPorPedido = {};
    for (final parcela in parcelasSelecionadas) {
      parcelasPorPedido.putIfAbsent(parcela.pedido.id, () => []).add(parcela);
    }

    double totalRecebido = 0;

    // Processar cada pedido
    for (final entry in parcelasPorPedido.entries) {
      final pedidoId = entry.key;
      final parcelasDoPedido = entry.value;

      // Buscar pedido atualizado
      final pedido = dataService.pedidos.firstWhere(
        (p) => p.id == pedidoId,
        orElse: () => parcelasDoPedido.first.pedido,
      );

      final novosPagamentos = <PagamentoPedido>[];

      for (final pag in pedido.pagamentos) {
        // Verificar se esta parcela foi selecionada para recebimento
        final parcelaSelecionada = parcelasDoPedido
            .where((p) => p.pagamento.id == pag.id)
            .firstOrNull;

        if (parcelaSelecionada != null) {
          // Marcar como recebida com a forma de pagamento selecionada
          novosPagamentos.add(
            PagamentoPedido(
              id: pag.id,
              tipo: formaRecebimento,
              tipoOriginal: TipoPagamento.crediario,
              valor: pag.valor,
              recebido: true,
              dataRecebimento: DateTime.now(),
              dataVencimento: pag.dataVencimento,
              parcelas: pag.parcelas,
              numeroParcela: pag.numeroParcela,
              parcelamentoId: pag.parcelamentoId,
              observacao: 'Parcela recebida do crediário',
            ),
          );
          totalRecebido += pag.valor;
        } else {
          novosPagamentos.add(pag);
        }
      }

      // Atualizar status do pedido
      final todosRecebidos = novosPagamentos.every((p) => p.recebido);
      final algumRecebido = novosPagamentos.any((p) => p.recebido);

      String novoStatus;
      if (todosRecebidos) {
        novoStatus = 'Pago';
      } else if (algumRecebido) {
        novoStatus = 'Parcialmente Pago';
      } else {
        novoStatus = pedido.status;
      }

      final pedidoAtualizado = pedido.copyWith(
        status: novoStatus,
        pagamentos: novosPagamentos,
        updatedAt: DateTime.now(),
      );

      // ATUALIZAR ESTOQUE - Se pedido passou de Pendente para Pago
      final estavaPendente = pedido.status == 'Pendente' || 
                            pedido.totalRecebido <= 0;
      if (novoStatus == 'Pago' && estavaPendente) {
        debugPrint('');
        debugPrint('╔════════════════════════════════════════════════╗');
        debugPrint('║  ATUALIZANDO ESTOQUE - PEDIDO RECEBIDO        ║');
        debugPrint('╚════════════════════════════════════════════════╝');
        
        for (final produtoItem in pedido.produtos) {
          try {
            final produto = dataService.produtos.firstWhere(
              (p) => p.id == produtoItem.id,
            );
            
            final estoqueAnterior = produto.estoque;
            final novoEstoque = (produto.estoque - produtoItem.quantidade) < 0 
                ? 0 
                : (produto.estoque - produtoItem.quantidade);
            
            dataService.updateProduto(
              produto.copyWith(
                estoque: novoEstoque,
                updatedAt: DateTime.now(),
              ),
            );
            
            debugPrint('>>> ✓ Baixa no estoque (pedido recebido):');
            debugPrint('>>>   Produto: ${produto.nome}');
            debugPrint('>>>   Estoque anterior: $estoqueAnterior');
            debugPrint('>>>   Quantidade vendida: ${produtoItem.quantidade}');
            debugPrint('>>>   Novo estoque: $novoEstoque');
          } catch (e) {
            debugPrint('>>> ERRO ao dar baixa no produto ${produtoItem.nome}: $e');
          }
        }
        debugPrint('');
      }

      dataService.updatePedido(pedidoAtualizado);
    }

    Navigator.pop(ctx);

    // Mostrar sucesso
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${parcelasSelecionadas.length} parcela(s) recebida(s) - ${formatoMoeda.format(totalRecebido)}',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );

    // Atualizar tela
    setState(() {});
  }

  // Dialog para receber pagamento parcial de crédito (fiado/crediário)
  void _abrirRecebimentoParcialCredito(
    _GrupoCreditoCliente grupo,
    DataService dataService,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final valorController = TextEditingController(
      text: grupo.totalPendente.toStringAsFixed(2),
    );
    TipoPagamento? formaSelecionada;

    final isFiado = grupo.tipoCredito == TipoPagamento.fiado;
    final corPrincipal = isFiado ? Colors.deepOrange : Colors.pink;
    final tipoTexto = isFiado ? 'Fiado' : 'Crediário';

    // Formas de recebimento disponíveis (sem fiado nem crediario)
    final formasRecebimento = TipoPagamento.values
        .where((t) => t != TipoPagamento.fiado && t != TipoPagamento.crediario)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valorDigitado =
              double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0.0;
          final isParcial =
              valorDigitado > 0 && valorDigitado < grupo.totalPendente;
          final valorRestante = grupo.totalPendente - valorDigitado;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: corPrincipal.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.payments, color: corPrincipal, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receber $tipoTexto',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        grupo.clienteNome,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Total pendente
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: corPrincipal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: corPrincipal.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Pendente',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '${grupo.quantidadeVendas} venda(s)',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          formatoMoeda.format(grupo.totalPendente),
                          style: TextStyle(
                            color: corPrincipal,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Campo de valor
                  const Text(
                    'Valor a receber',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: valorController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      prefixText: 'R\$ ',
                      prefixStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: corPrincipal),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),

                  if (isParcial) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pagamento parcial: restará ${formatoMoeda.format(valorRestante)}',
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Forma de recebimento
                  const Text(
                    'Forma de recebimento',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: formasRecebimento.map((tipo) {
                      final isSelected = formaSelecionada == tipo;
                      final cor = _getCorTipoRecebimento(tipo);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              setDialogState(() => formaSelecionada = tipo),
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: (formaSelecionada == null || valorDigitado <= 0)
                    ? null
                    : () => _processarRecebimentoCredito(
                        ctx,
                        grupo,
                        valorDigitado,
                        formaSelecionada!,
                        dataService,
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      (formaSelecionada != null && valorDigitado > 0)
                      ? corPrincipal
                      : Colors.grey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Confirmar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Processa o recebimento parcial de crédito (fiado/crediário)
  void _processarRecebimentoCredito(
    BuildContext ctx,
    _GrupoCreditoCliente grupo,
    double valorReceber,
    TipoPagamento formaRecebimento,
    DataService dataService,
  ) {
    double valorRestante = valorReceber;
    final tipoCredito = grupo.tipoCredito;

    // Ordenar pedidos por data (mais antigos primeiro - FIFO)
    final pedidosOrdenados = [...grupo.pedidos]
      ..sort((a, b) => a.dataPedido.compareTo(b.dataPedido));

    // Processar cada pedido até esgotar o valor
    for (final pedido in pedidosOrdenados) {
      if (valorRestante <= 0) break;

      final pagamentosCreditoPendentes = pedido.pagamentos
          .where((p) => p.tipo == tipoCredito && !p.recebido)
          .toList();

      if (pagamentosCreditoPendentes.isEmpty) continue;

      final novosPagamentos = <PagamentoPedido>[];

      for (final pag in pedido.pagamentos) {
        if (pag.tipo == tipoCredito && !pag.recebido && valorRestante > 0) {
          if (valorRestante >= pag.valor) {
            // Paga totalmente esta parcela
            novosPagamentos.add(
              PagamentoPedido(
                id: pag.id,
                tipo: formaRecebimento,
                tipoOriginal: tipoCredito,
                valor: pag.valor,
                recebido: true,
                dataRecebimento: DateTime.now(),
                dataVencimento: pag.dataVencimento,
                observacao:
                    'Recebido do ${tipoCredito == TipoPagamento.fiado ? "fiado" : "crediário"}',
              ),
            );
            valorRestante -= pag.valor;
          } else {
            // Paga parcialmente - divide em dois pagamentos
            novosPagamentos.add(
              PagamentoPedido(
                id: '${pag.id}_pago',
                tipo: formaRecebimento,
                tipoOriginal: tipoCredito,
                valor: valorRestante,
                recebido: true,
                dataRecebimento: DateTime.now(),
                observacao:
                    'Recebido parcial do ${tipoCredito == TipoPagamento.fiado ? "fiado" : "crediário"}',
              ),
            );
            novosPagamentos.add(
              PagamentoPedido(
                id: '${pag.id}_resto',
                tipo: tipoCredito,
                valor: pag.valor - valorRestante,
                recebido: false,
                dataVencimento: pag.dataVencimento,
                observacao:
                    'Restante do ${tipoCredito == TipoPagamento.fiado ? "fiado" : "crediário"}',
              ),
            );
            valorRestante = 0;
          }
        } else {
          novosPagamentos.add(pag);
        }
      }

      // Atualizar pedido
      final todosRecebidos = novosPagamentos.every((p) => p.recebido);
      final pedidoAtualizado = pedido.copyWith(
        status: todosRecebidos ? 'Pago' : pedido.status,
        pagamentos: novosPagamentos,
        updatedAt: DateTime.now(),
      );

      dataService.updatePedido(pedidoAtualizado);
    }

    // Atualizar saldo devedor do cliente (apenas para fiado)
    if (grupo.clienteId != 'sem_cliente' &&
        tipoCredito == TipoPagamento.fiado) {
      final cliente = dataService.clientes.firstWhere(
        (c) => c.id == grupo.clienteId,
        orElse: () => Cliente(
          id: '',
          nome: '',
          telefone: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      if (cliente.id.isNotEmpty) {
        final novoSaldo = (cliente.saldoDevedor - valorReceber).clamp(
          0.0,
          double.infinity,
        );
        final clienteAtualizado = cliente.copyWith(
          saldoDevedor: novoSaldo,
          updatedAt: DateTime.now(),
        );
        dataService.updateCliente(clienteAtualizado);
      }
    }

    Navigator.pop(ctx);
    setState(() {});

    // Mostrar sucesso
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '✓ Recebido ${formatoMoeda.format(valorReceber)} de ${grupo.clienteNome}',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 150,
          left: 16,
          right: 16,
        ),
      ),
    );
  }

  Widget _buildItemPedidoPendente(Pedido pedido, DataService dataService) {
    // Se não tem pagamentos, usar o total geral do pedido
    // Se tem pagamentos, usar a diferença entre pagamentos e recebido
    final valorPendente = pedido.pagamentos.isEmpty
        ? pedido.totalGeral - pedido.totalRecebido
        : pedido.totalPagamentos - pedido.totalRecebido;
    final parcelasPendentes = pedido.pagamentos
        .where((p) => !p.recebido)
        .toList();
    final proximoVencimento = parcelasPendentes
        .where((p) => p.dataVencimento != null)
        .map((p) => p.dataVencimento!)
        .fold<DateTime?>(
          null,
          (min, d) => min == null || d.isBefore(min) ? d : min,
        );

    final hoje = DateTime.now();
    final diasParaVencer = proximoVencimento
        ?.difference(DateTime(hoje.year, hoje.month, hoje.day))
        .inDays;

    final bool vencido = diasParaVencer != null && diasParaVencer < 0;
    final bool venceHoje = diasParaVencer == 0;
    final bool venceBreve =
        diasParaVencer != null && diasParaVencer > 0 && diasParaVencer <= 3;

    // Verificar se está cancelado
    final bool isCancelado = pedido.status.toLowerCase() == 'cancelado';

    Color corStatus = Colors.orange;
    String textoVencimento = '';
    if (isCancelado) {
      corStatus = Colors.red.shade800;
      textoVencimento = 'CANCELADO';
    } else if (vencido) {
      corStatus = Colors.red;
      textoVencimento =
          'Vencido há ${-diasParaVencer} dia${diasParaVencer != -1 ? 's' : ''}';
    } else if (venceHoje) {
      corStatus = Colors.amber;
      textoVencimento = 'Vence hoje!';
    } else if (venceBreve) {
      corStatus = Colors.amber;
      textoVencimento =
          'Vence em $diasParaVencer dia${diasParaVencer != 1 ? 's' : ''}';
    } else if (proximoVencimento != null) {
      textoVencimento =
          'Vence ${DateFormat('dd/MM').format(proximoVencimento)}';
    }

    // Verificar se é venda salva (sem pagamentos OU tipo "outro" sem recebimento)
    final nenhumRecebido = pedido.pagamentos.isEmpty || pedido.pagamentos.every((p) => !p.recebido);
    final temFiado = pedido.pagamentos.any(
      (p) => p.tipo == TipoPagamento.fiado,
    );
    
    // Tipo de pagamento
    final tipoPagamento = parcelasPendentes.isNotEmpty
        ? parcelasPendentes.first.tipo
        : (pedido.pagamentos.isNotEmpty ? pedido.pagamentos.first.tipo : null);
    
    // Venda salva: sem pagamentos OU (status Pendente, não é fiado, tipo é "outro" e não recebido)
    final isVendaSalva = pedido.status == 'Pendente' && !temFiado && (
      pedido.pagamentos.isEmpty || 
      (tipoPagamento == TipoPagamento.outro && nenhumRecebido)
    );
    
    final isFiado = temFiado && nenhumRecebido;
    
    String tipoTexto = '';
    IconData tipoIcone = Icons.receipt;

    // Cor específica para cada tipo
    Color corCard = corStatus;
    if (isCancelado) {
      tipoTexto = 'CANCELADO';
      tipoIcone = Icons.cancel;
      corCard = Colors.red.shade800;
    } else if (isFiado) {
      tipoTexto = 'Fiado';
      tipoIcone = Icons.handshake;
      corCard = Colors.deepOrange; // Cor diferente para fiado
    } else if (isVendaSalva) {
      // Venda Salva - cor azul escuro
      tipoTexto = 'Venda Salva';
      tipoIcone = Icons.save;
      corCard = const Color(0xFF0A1929); // Azul muito escuro quase preto
    } else if (tipoPagamento == TipoPagamento.crediario) {
      tipoTexto = 'Crediário';
      tipoIcone = Icons.credit_score;
      corCard = const Color(0xFF1A1A2E); // Cor muito escura para pedidos normais
    } else if (tipoPagamento == TipoPagamento.boleto) {
      tipoTexto = 'Boleto';
      tipoIcone = Icons.receipt_long;
      corCard = const Color(0xFF1A1A2E); // Cor muito escura para pedidos normais
    } else {
      // Pedido normal (não venda salva) - cor muito escura
      tipoTexto = ''; // Não mostrar badge para pedidos normais
      tipoIcone = Icons.receipt;
      corCard = const Color(0xFF1A1A2E); // Cor muito escura (não verde)
    }

    return GestureDetector(
      onTap: isCancelado
          ? null
          : () => setState(() => _pedidoSelecionado = pedido),
      child: Opacity(
        opacity: 1.0, // Manter opacidade total para legibilidade
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isCancelado
                  ? [
                      Colors.red.shade900.withOpacity(0.2),
                      Colors.red.shade800.withOpacity(0.1),
                    ]
                  : isFiado
                  ? [
                      Colors.deepOrange.shade900.withOpacity(0.3),
                      Colors.deepOrange.shade800.withOpacity(0.2),
                    ]
                  : isVendaSalva
                  ? [const Color(0xFF0A1929), const Color(0xFF0D2137)]
                  : [
                      // Cor muito escura para pedidos normais (não vendas salvas)
                      const Color(0xFF1A1A2E),
                      const Color(0xFF16213E),
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCancelado
                  ? Colors.red.shade800.withOpacity(0.4)
                  : (isFiado
                            ? corCard
                            : isVendaSalva
                            ? corCard
                            : Colors.white.withOpacity(0.15)), // Borda clara para pedidos normais
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha 1: Número e Cliente
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCancelado
                          ? corCard.withOpacity(0.15)
                          : isVendaSalva
                          ? const Color(0xFF1565C0).withOpacity(0.3)
                          : isFiado
                          ? corCard.withOpacity(0.15)
                          : Colors.white.withOpacity(0.1), // Fundo claro para pedidos normais
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      tipoIcone,
                      color: isCancelado
                          ? corCard.withOpacity(0.8)
                          : isVendaSalva
                          ? const Color(0xFF42A5F5)
                          : isFiado
                          ? corCard.withOpacity(0.8)
                          : Colors.white70, // Cor clara para pedidos normais
                      size: 20,
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
                              pedido.numero.isNotEmpty &&
                                      pedido.numero.startsWith('VND-')
                                  ? pedido.numero
                                  : pedido.numero.isNotEmpty
                                  ? pedido.numero
                                  : 'Sem número',
                              style: TextStyle(
                                color: isCancelado
                                    ? Colors.white70
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                decoration: isCancelado
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: Colors.red,
                                decorationThickness: 1.5,
                              ),
                            ),
                            if (tipoTexto.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isCancelado
                                      ? Colors.red.shade800.withOpacity(0.15)
                                      : isVendaSalva
                                      ? const Color(0xFF1565C0).withOpacity(0.3)
                                      : isFiado
                                      ? corCard.withOpacity(0.15)
                                      : Colors.white.withOpacity(0.1), // Fundo claro para pedidos normais
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tipoTexto,
                                  style: TextStyle(
                                    color: isCancelado
                                        ? Colors.red.shade400.withOpacity(0.8)
                                        : isVendaSalva
                                        ? const Color(0xFF42A5F5)
                                        : isFiado
                                        ? corCard.withOpacity(0.8)
                                        : Colors.white70, // Cor clara para pedidos normais
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        // Nome do cliente - editável se for venda salva sem cliente
                        GestureDetector(
                          onTap: isVendaSalva && pedido.clienteId == null && !isCancelado
                              ? () => _editarNomeClienteVendaSalva(pedido, dataService)
                              : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  pedido.clienteNome ?? 'Sem cliente',
                                  style: TextStyle(
                                    color: isCancelado
                                        ? Colors.white60
                                        : Colors.white.withOpacity(0.9),
                                    fontSize: 16,
                                    fontWeight: isVendaSalva && pedido.clienteId == null 
                                        ? FontWeight.w600 
                                        : FontWeight.normal,
                                    decoration: isCancelado
                                        ? TextDecoration.lineThrough
                                        : null,
                                    decorationColor: Colors.red.withOpacity(0.7),
                                    decorationThickness: 1,
                                  ),
                                ),
                              ),
                              if (isVendaSalva && pedido.clienteId == null && !isCancelado) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: Colors.orange,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'R\$ ${valorPendente.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isCancelado
                              ? Colors.white70
                              : Colors.white, // Cor branca para pedidos normais
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          decoration: isCancelado
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: Colors.red,
                          decorationThickness: 1.5,
                        ),
                      ),
                      if (parcelasPendentes.length > 1 && !isCancelado)
                        Text(
                          '${parcelasPendentes.length} parcelas',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              // Linha 2: Vencimento e botão receber
              // Sempre mostrar se não está cancelado (para mostrar o botão receber)
              // Ou se tem vencimento/parcelas/cancelado (para mostrar informações)
              if (!isCancelado || 
                  textoVencimento.isNotEmpty ||
                  parcelasPendentes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      if (textoVencimento.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (isVendaSalva || isFiado || isCancelado)
                                ? corCard.withOpacity(0.12)
                                : Colors.white.withOpacity(0.1), // Fundo claro para pedidos normais
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCancelado
                                    ? Icons.cancel
                                    : vencido
                                    ? Icons.warning
                                    : Icons.schedule,
                                color: (isVendaSalva || isFiado || isCancelado)
                                    ? corCard.withOpacity(0.8)
                                    : Colors.white70, // Cor clara para pedidos normais
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                textoVencimento,
                                style: TextStyle(
                                  color: (isVendaSalva || isFiado || isCancelado)
                                      ? corCard.withOpacity(0.8)
                                      : Colors.white70, // Cor clara para pedidos normais
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer(),
                      // Se cancelado, não mostra botões de ação
                      if (!isCancelado) ...[
                        // Verificar se é uma venda salva (tipo "outro" e nenhum recebido)
                        // Fiado vai direto para receber, venda salva vai para editar/continuar
                        Builder(
                          builder: (context) {
                            final nenhumRecebido = pedido.pagamentos.isEmpty || 
                                pedido.pagamentos.every((p) => !p.recebido);
                            final temFiadoPendente = pedido.pagamentos.any(
                              (p) =>
                                  p.tipo == TipoPagamento.fiado && !p.recebido,
                            );
                            
                            // Venda salva: sem pagamentos OU (nenhum recebido, status Pendente, não é fiado, tipo "outro")
                            final tipoPag = pedido.pagamentos.isNotEmpty 
                                ? pedido.pagamentos.first.tipo 
                                : null;
                            final isVendaSalvaLocal = pedido.status == 'Pendente' &&
                                !temFiadoPendente &&
                                (pedido.pagamentos.isEmpty || 
                                 (nenhumRecebido && tipoPag == TipoPagamento.outro));

                            if (isVendaSalvaLocal) {
                              // Venda Salva - abre para editar/continuar
                              return ElevatedButton.icon(
                                onPressed: () =>
                                    _abrirVendaSalvaParaEditar(pedido),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1565C0),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(
                                      color: Color(0xFF42A5F5),
                                    ),
                                  ),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.edit, size: 18),
                                label: const Text(
                                  'Continuar',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              );
                            } else {
                              // Pedidos normais (Fiado/Crediário/Boleto/outros) - apenas receber
                              return ElevatedButton.icon(
                                onPressed: () =>
                                    setState(() => _pedidoSelecionado = pedido),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: temFiadoPendente
                                      ? Colors.deepOrange.withOpacity(0.2)
                                      : Colors.green.withOpacity(0.2), // Verde apenas no botão
                                  foregroundColor: temFiadoPendente
                                      ? Colors.deepOrange
                                      : Colors.green, // Verde apenas no botão
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: temFiadoPendente
                                          ? Colors.deepOrange.withOpacity(0.4)
                                          : Colors.green.withOpacity(0.4), // Verde apenas no botão
                                    ),
                                  ),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.payments, size: 18),
                                label: const Text(
                                  'Receber',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        // Botão de cancelar
                        ElevatedButton.icon(
                          onPressed: () => _confirmarCancelamentoPedido(pedido, dataService),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.withOpacity(0.2),
                            foregroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: Colors.red.withOpacity(0.4),
                              ),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.cancel, size: 18),
                          label: const Text(
                            'Cancelar',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Confirmar cancelamento de pedido
  Future<void> _confirmarCancelamentoPedido(Pedido pedido, DataService dataService) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Pedido'),
        content: Text(
          'Tem certeza que deseja cancelar o pedido ${pedido.numero}?\n\n'
          'Esta ação não pode ser desfeita e o pedido não será contabilizado em nenhum relatório.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await dataService.cancelarPedido(pedido.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido ${pedido.numero} cancelado e produtos devolvidos ao estoque'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _pedidoSelecionado = null;
        });
      }
    }
  }

  // Confirmar cancelamento de venda pendente (não agrupada)
  void _confirmarCancelamentoVendaPendente(
    Pedido pedido,
    DataService dataService,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final motivoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.cancel,
                color: Colors.redAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Cancelar Venda', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Venda: ${pedido.numero.isNotEmpty ? pedido.numero : 'Sem número'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (pedido.clienteNome != null)
                    Text(
                      'Cliente: ${pedido.clienteNome}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Valor: ${formatoMoeda.format(pedido.totalGeral)}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Motivo do cancelamento',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                hintText: 'Ex: Cliente desistiu, produto devolvido...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ Esta ação não pode ser desfeita.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Voltar',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final motivo = motivoController.text.trim();
              if (motivo.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Por favor, informe o motivo do cancelamento',
                    ),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(
                      top: 50,
                      left: 20,
                      right: 20,
                      bottom: 20,
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context);
              _processarCancelamentoVendaPendente(pedido, dataService, motivo);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.cancel, size: 18),
            label: const Text('Confirmar Cancelamento'),
          ),
        ],
      ),
    );
  }

  // Processar cancelamento de venda pendente
  void _processarCancelamentoVendaPendente(
    Pedido pedido,
    DataService dataService,
    String motivo,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    // Criar novos pagamentos marcando como cancelados
    final novosPagamentos = pedido.pagamentos.map((pag) {
      if (!pag.recebido) {
        return PagamentoPedido(
          id: pag.id,
          tipo: pag.tipo,
          valor: pag.valor,
          recebido: true,
          dataRecebimento: DateTime.now(),
          dataVencimento: pag.dataVencimento,
          observacao:
              '❌ CANCELADO: $motivo (${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())})',
        );
      }
      return pag;
    }).toList();

    // Atualizar pedido com status cancelado
    final pedidoAtualizado = pedido.copyWith(
      status: 'Cancelado',
      observacoes: '${pedido.observacoes ?? ''}\n[VENDA CANCELADA] $motivo'
          .trim(),
      pagamentos: novosPagamentos,
      updatedAt: DateTime.now(),
    );

    dataService.updatePedido(pedidoAtualizado);

    // Atualizar saldo devedor do cliente se for fiado
    final valorFiadoPendente = pedido.pagamentos
        .where((p) => p.tipo == TipoPagamento.fiado && !p.recebido)
        .fold(0.0, (sum, p) => sum + p.valor);

    if (valorFiadoPendente > 0 && pedido.clienteId != null) {
      final cliente = dataService.clientes.firstWhere(
        (c) => c.id == pedido.clienteId,
        orElse: () => Cliente(
          id: '',
          nome: '',
          telefone: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      if (cliente.id.isNotEmpty) {
        final novoSaldo = (cliente.saldoDevedor - valorFiadoPendente).clamp(
          0.0,
          double.infinity,
        );
        final clienteAtualizado = cliente.copyWith(
          saldoDevedor: novoSaldo,
          updatedAt: DateTime.now(),
        );
        dataService.updateCliente(clienteAtualizado);
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Venda ${pedido.numero.isNotEmpty ? pedido.numero : 'Sem número'} cancelada com sucesso.',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 20),
      ),
    );

    setState(() {
      if (_pedidoSelecionado?.id == pedido.id) {
        _pedidoSelecionado = null;
      }
    });
  }

  // Editar nome do cliente em venda salva sem cliente
  void _editarNomeClienteVendaSalva(Pedido pedido, DataService dataService) {
    final controller = TextEditingController(text: pedido.clienteNome ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Editar Nome do Cliente',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
        ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
          controller: controller,
          autofocus: true,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          decoration: InputDecoration(
            labelText: 'Nome do Cliente',
              labelStyle: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            hintText: 'Digite o nome do cliente',
              hintStyle: TextStyle(
                color: Colors.white30,
                fontSize: 16,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.orange.withOpacity(0.5),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(
                  color: Colors.orange,
                  width: 2,
            ),
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final novoNome = controller.text.trim();
              if (novoNome.isNotEmpty) {
                final pedidoAtualizado = pedido.copyWith(
                  clienteNome: novoNome,
                  updatedAt: DateTime.now(),
                );
                dataService.updatePedido(pedidoAtualizado);
                
                // Se o pedido está selecionado, atualizar também
                if (_pedidoSelecionado?.id == pedido.id) {
                  setState(() {
                    _pedidoSelecionado = pedidoAtualizado;
                  });
                }
                
                Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 8),
                        Text('Nome do cliente atualizado: $novoNome'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(
                      top: 50,
                      left: 20,
                      right: 20,
                      bottom: 20,
                    ),
                  ),
                );
              } else {
                // Se o nome estiver vazio, remover o nome do cliente
                final pedidoAtualizado = pedido.copyWith(
                  clienteNome: null,
                  updatedAt: DateTime.now(),
                );
                dataService.updatePedido(pedidoAtualizado);
                
                if (_pedidoSelecionado?.id == pedido.id) {
                  setState(() {
                    _pedidoSelecionado = pedidoAtualizado;
                  });
                }
                
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // Abre a venda salva para edição na aba Venda
  void _abrirVendaSalvaParaEditar(Pedido pedido) {
    // Não permitir editar pedidos cancelados
    if (pedido.status.toLowerCase() == 'cancelado') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Pedidos cancelados não podem ser editados'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(
            top: 50,
            left: 20,
            right: 20,
            bottom: 20,
          ),
        ),
      );
      return;
    }
    
    // Se a aba Venda está escondida (foi aberto pela tela de venda direta),
    // navegar para a VendaDiretaPage diretamente
    if (widget.esconderAbaVenda == true) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VendaDiretaPage(
            pedidoParaEditar: pedido,
          ),
        ),
      );
      return;
    }
    
    // Se está dentro do PdvPage com abas, mudar para a aba de Venda
    setState(() {
      _pedidoParaEditar = pedido;
      _vendaPageKey++; // Força rebuild para carregar o novo pedido
    });
    // Muda para a aba de Venda (índice 1)
    _tabController.animateTo(1);
  }

  Widget _buildNenhumResultado() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhum pedido encontrado',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'para "$_termoBusca"',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaResultados(List<Pedido> pedidos, DataService dataService) {
    // Separar pedidos por tipo: fiado/crediário vs outros
    final pedidosFiadoOuCrediario = pedidos
        .where(
          (p) =>
              p.status.toLowerCase() != 'cancelado' &&
              p.pagamentos.any(
                (pag) =>
                    pag.tipo == TipoPagamento.fiado ||
                    pag.tipo == TipoPagamento.crediario ||
                    pag.tipoOriginal == TipoPagamento.fiado ||
                    pag.tipoOriginal == TipoPagamento.crediario,
              ),
        )
        .toList();

    final pedidosOutros = pedidos
        .where(
          (p) =>
              p.status.toLowerCase() == 'cancelado' ||
              !p.pagamentos.any(
                (pag) =>
                    pag.tipo == TipoPagamento.fiado ||
                    pag.tipo == TipoPagamento.crediario ||
                    pag.tipoOriginal == TipoPagamento.fiado ||
                    pag.tipoOriginal == TipoPagamento.crediario,
              ),
        )
        .toList();

    // Agrupar fiados/crediário por cliente
    final Map<String, List<Pedido>> fiadosPorCliente = {};
    final Map<String, List<Pedido>> crediariosPorCliente = {};

    for (final pedido in pedidosFiadoOuCrediario) {
      final clienteKey = pedido.clienteId ?? 'sem_cliente';
      final temFiado = pedido.pagamentos.any(
        (p) =>
            p.tipo == TipoPagamento.fiado ||
            p.tipoOriginal == TipoPagamento.fiado,
      );
      final temCrediario = pedido.pagamentos.any(
        (p) =>
            p.tipo == TipoPagamento.crediario ||
            p.tipoOriginal == TipoPagamento.crediario,
      );

      if (temFiado) {
        fiadosPorCliente.putIfAbsent(clienteKey, () => []).add(pedido);
      } else if (temCrediario) {
        crediariosPorCliente.putIfAbsent(clienteKey, () => []).add(pedido);
      }
    }

    // Criar lista mista de itens para exibição
    final List<dynamic> itensLista = [];

    // Adicionar grupos de fiados
    fiadosPorCliente.forEach((clienteId, pedidosGrupo) {
      itensLista.add(
        _GrupoCreditoCliente(
          clienteId: clienteId,
          clienteNome:
              pedidosGrupo.first.clienteNome ?? 'Cliente não identificado',
          pedidos: pedidosGrupo,
          tipoCredito: TipoPagamento.fiado,
        ),
      );
    });

    // Adicionar grupos de crediário
    crediariosPorCliente.forEach((clienteId, pedidosGrupo) {
      itensLista.add(
        _GrupoCreditoCliente(
          clienteId: clienteId,
          clienteNome:
              pedidosGrupo.first.clienteNome ?? 'Cliente não identificado',
          pedidos: pedidosGrupo,
          tipoCredito: TipoPagamento.crediario,
        ),
      );
    });

    // Adicionar outros pedidos
    itensLista.addAll(pedidosOutros);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: itensLista.length,
      itemBuilder: (context, index) {
        final item = itensLista[index];
        if (item is _GrupoCreditoCliente) {
          return _buildCardGrupoCredito(item, dataService);
        } else {
          return _buildCardPedido(item as Pedido);
        }
      },
    );
  }

  Widget _buildCardPedido(Pedido pedido) {
    final isRecebido = pedido.totalmenteRecebido;
    final temPagamentos = pedido.pagamentos.isNotEmpty;
    final parcelas = pedido.pagamentos.where((p) => p.isParcela).toList();
    final temParcelas = parcelas.isNotEmpty;
    final parcelasVencidas = parcelas.where((p) => p.isVencida).toList();
    final temParcelasVencidas = parcelasVencidas.isNotEmpty;

    // Verificar se tem fiado pendente
    final pagamentosFiado = pedido.pagamentos
        .where((p) => p.tipo == TipoPagamento.fiado && !p.recebido)
        .toList();
    final temFiadoPendente = pagamentosFiado.isNotEmpty;
    final valorFiadoPendente = pagamentosFiado.fold(
      0.0,
      (sum, p) => sum + p.valor,
    );

    // Verificar se tem crediário pendente
    final pagamentosCrediario = pedido.pagamentos
        .where((p) => p.tipo == TipoPagamento.crediario && !p.recebido)
        .toList();
    final temCrediarioPendente = pagamentosCrediario.isNotEmpty;
    final valorCrediarioPendente = pagamentosCrediario.fold(
      0.0,
      (sum, p) => sum + p.valor,
    );

    return GestureDetector(
      onTap: () => setState(() => _pedidoSelecionado = pedido),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isRecebido
                ? [
                    Colors.green.shade900.withOpacity(0.4),
                    Colors.green.shade800.withOpacity(0.3),
                  ]
                : temParcelasVencidas
                ? [
                    Colors.red.shade900.withOpacity(0.4),
                    Colors.red.shade800.withOpacity(0.3),
                  ]
                : temFiadoPendente
                ? [
                    Colors.orange.shade900.withOpacity(0.4),
                    Colors.orange.shade800.withOpacity(0.3),
                  ]
                : temCrediarioPendente
                ? [
                    Colors.pink.shade900.withOpacity(0.4),
                    Colors.pink.shade800.withOpacity(0.3),
                  ]
                : [const Color(0xFF1E1E2E), const Color(0xFF2D2D44)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRecebido
                ? Colors.green.withOpacity(0.4)
                : temParcelasVencidas
                ? Colors.red.withOpacity(0.5)
                : temFiadoPendente
                ? Colors.orange.withOpacity(0.5)
                : temCrediarioPendente
                ? Colors.pink.withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isRecebido
                      ? Colors.green.withOpacity(0.2)
                      : temParcelasVencidas
                      ? Colors.red.withOpacity(0.2)
                      : temFiadoPendente
                      ? Colors.orange.withOpacity(0.2)
                      : temCrediarioPendente
                      ? Colors.pink.withOpacity(0.2)
                      : temPagamentos
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isRecebido
                      ? Icons.check_circle
                      : temParcelasVencidas
                      ? Icons.warning
                      : temFiadoPendente
                      ? Icons.handshake
                      : temCrediarioPendente
                      ? Icons.calendar_month
                      : temPagamentos
                      ? Icons.pending_actions
                      : Icons.receipt,
                  color: isRecebido
                      ? Colors.green
                      : temParcelasVencidas
                      ? Colors.red
                      : temFiadoPendente
                      ? Colors.orange
                      : temCrediarioPendente
                      ? Colors.pink
                      : temPagamentos
                      ? Colors.orange
                      : Colors.blue,
                  size: 24,
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
                          pedido.numero.isNotEmpty &&
                                  pedido.numero.startsWith('VND-')
                              ? pedido.numero
                              : pedido.numero.isNotEmpty
                              ? pedido.numero
                              : 'Sem número',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (isRecebido) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'PAGO',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ] else if (temParcelasVencidas) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${parcelasVencidas.length} VENCIDA(S)',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ] else if (temParcelas) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${parcelas.where((p) => p.recebido).length}/${parcelas.length}x',
                              style: const TextStyle(
                                color: Colors.purpleAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ] else if (temFiadoPendente) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.handshake,
                                  color: Colors.orangeAccent,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'FIADO',
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (temCrediarioPendente) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.pink.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.calendar_month,
                                  color: Colors.pinkAccent,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'CREDIÁRIO',
                                  style: TextStyle(
                                    color: Colors.pinkAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Nome do cliente - editável se for venda salva sem cliente
                    Builder(
                      builder: (context) {
                        final nenhumRecebido = pedido.pagamentos.every((p) => !p.recebido);
                        final tipoPag = pedido.pagamentos.isNotEmpty 
                            ? pedido.pagamentos.first.tipo 
                            : null;
                        final temFiado = pedido.pagamentos.any(
                          (p) => p.tipo == TipoPagamento.fiado,
                        );
                        final isVendaSalvaDetalhes = nenhumRecebido &&
                            pedido.status == 'Pendente' &&
                            !temFiado &&
                            pedido.pagamentos.isNotEmpty &&
                            tipoPag == TipoPagamento.outro;
                        final podeEditar = isVendaSalvaDetalhes && 
                            pedido.clienteId == null && 
                            !isRecebido;
                        
                        return GestureDetector(
                          onTap: podeEditar
                              ? () {
                                  final dataService = Provider.of<DataService>(
                                    context,
                                    listen: false,
                                  );
                                  _editarNomeClienteVendaSalva(pedido, dataService);
                                }
                              : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  pedido.clienteNome ?? 'Sem cliente',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 17,
                                    fontWeight: podeEditar 
                                        ? FontWeight.w600 
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (podeEditar) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: Colors.orange,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    Text(
                      '${pedido.quantidadeItens} itens',
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
                    'R\$ ${pedido.totalGeral.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (temFiadoPendente)
                    Text(
                      'Fiado: R\$ ${valorFiadoPendente.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else if (temCrediarioPendente)
                    Text(
                      'Crediário: R\$ ${valorCrediarioPendente.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.pinkAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else if (temPagamentos && !isRecebido)
                    Text(
                      'Pendente: R\$ ${pedido.valorPendente.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPedidoDetalhes(Pedido pedido, DataService dataService) {
    final isRecebido = pedido.totalmenteRecebido;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Cabeçalho
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isRecebido
                    ? [
                        Colors.green.shade900.withOpacity(0.5),
                        Colors.green.shade800.withOpacity(0.4),
                      ]
                    : [const Color(0xFF1E1E2E), const Color(0xFF2D2D44)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isRecebido
                    ? Colors.green.withOpacity(0.5)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isRecebido
                            ? Colors.green.withOpacity(0.3)
                            : Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isRecebido ? Icons.check_circle : Icons.receipt_long,
                        color: isRecebido ? Colors.greenAccent : Colors.blue,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pedido.numero,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                          Text(
                            pedido.clienteNome ?? 'Sem cliente',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isRecebido)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check,
                              color: Colors.greenAccent,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'PAGO',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildValorResumo(
                        'Total',
                        pedido.totalGeral,
                        Colors.white,
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white24),
                    Expanded(
                      child: _buildValorResumo(
                        'Recebido',
                        pedido.totalRecebido,
                        Colors.greenAccent,
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white24),
                    Expanded(
                      child: _buildValorResumo(
                        'Pendente',
                        pedido.valorPendente,
                        pedido.valorPendente > 0
                            ? Colors.orange
                            : Colors.greenAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Itens
          _buildSecaoItens(pedido),
          const SizedBox(height: 20),

          // Pagamentos
          _buildSecaoPagamentos(pedido, dataService),
          const SizedBox(height: 20),

          // Botões de ação
          if (!pedido.totalmenteRecebido) ...[
            // Botão Receber Todos (se já tem pagamentos não recebidos)
            if (pedido.pagamentos.isNotEmpty &&
                pedido.pagamentos.any((p) => !p.recebido))
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _receberTodosPagamentos(pedido, dataService),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: Text(
                    'Receber Todos (R\$ ${(pedido.totalPagamentos - pedido.totalRecebido).toStringAsFixed(2)})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 4,
                    shadowColor: const Color(0xFF00C853),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (pedido.pagamentos.isNotEmpty &&
                pedido.pagamentos.any((p) => !p.recebido))
              const SizedBox(height: 12),

            // Botão adicionar mais pagamento (se ainda falta valor)
            if (pedido.valorRestante > 0.01)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _abrirDialogPagamento(pedido, dataService),
                  icon: const Icon(Icons.add_card, size: 18),
                  label: Text(
                    'Adicionar Pagamento (Falta R\$ ${pedido.valorRestante.toStringAsFixed(2)})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 4,
                    shadowColor: const Color(0xFF2196F3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildValorResumo(String label, double valor, Color cor) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          'R\$ ${valor.toStringAsFixed(2)}',
          style: TextStyle(
            color: cor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildSecaoItens(Pedido pedido) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag, color: Colors.white54, size: 20),
              const SizedBox(width: 8),
              Text(
                'Itens (${pedido.quantidadeItens})',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 24),
          ...pedido.produtos.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${item.quantidade}x',
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.nome,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Text(
                    'R\$ ${(item.preco * item.quantidade).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w500,
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

  Widget _buildSecaoPagamentos(Pedido pedido, DataService dataService) {
    if (pedido.pagamentos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nenhum pagamento adicionado',
                style: TextStyle(color: Colors.orange, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    // Separar parcelas e pagamentos normais
    final parcelas = pedido.pagamentos.where((p) => p.isParcela).toList()
      ..sort((a, b) => (a.numeroParcela ?? 0).compareTo(b.numeroParcela ?? 0));
    final pagamentosNormais = pedido.pagamentos
        .where((p) => !p.isParcela)
        .toList();

    // Agrupar parcelas por parcelamentoId
    final Map<String, List<PagamentoPedido>> parcelasAgrupadas = {};
    for (final parcela in parcelas) {
      final id = parcela.parcelamentoId ?? 'sem-id';
      parcelasAgrupadas.putIfAbsent(id, () => []);
      parcelasAgrupadas[id]!.add(parcela);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments, color: Colors.white54, size: 20),
              const SizedBox(width: 8),
              Text(
                'Pagamentos (${pedido.pagamentos.length})',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              // Mostrar info de parcelas se houver
              if (parcelas.isNotEmpty) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${parcelas.where((p) => p.recebido).length}/${parcelas.length} parcelas pagas',
                    style: const TextStyle(
                      color: Colors.purpleAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const Divider(color: Colors.white12, height: 24),

          // Pagamentos normais
          ...pagamentosNormais.map(
            (pag) => _buildItemPagamento(pedido, pag, dataService),
          ),

          // Parcelamentos (agrupados)
          ...parcelasAgrupadas.entries.map((entry) {
            final parcelasGrupo = entry.value;
            final totalParcelas =
                parcelasGrupo.first.parcelas ?? parcelasGrupo.length;
            final parcelasPagas = parcelasGrupo.where((p) => p.recebido).length;
            final valorTotal = parcelasGrupo.fold(
              0.0,
              (sum, p) => sum + p.valor,
            );
            final valorPago = parcelasGrupo
                .where((p) => p.recebido)
                .fold(0.0, (sum, p) => sum + p.valor);
            final temVencidas = parcelasGrupo.any((p) => p.isVencida);

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: temVencidas
                      ? Colors.red.withOpacity(0.5)
                      : Colors.purple.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho do parcelamento
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.2),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(11),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_month,
                          color: Colors.purpleAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Parcelamento em ${totalParcelas}x',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Total: R\$ ${valorTotal.toStringAsFixed(2)} | Pago: R\$ ${valorPago.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: parcelasPagas == totalParcelas
                                ? Colors.green.withOpacity(0.3)
                                : temVencidas
                                ? Colors.red.withOpacity(0.3)
                                : Colors.orange.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            parcelasPagas == totalParcelas
                                ? 'QUITADO'
                                : temVencidas
                                ? 'VENCIDA'
                                : '$parcelasPagas/$totalParcelas',
                            style: TextStyle(
                              color: parcelasPagas == totalParcelas
                                  ? Colors.greenAccent
                                  : temVencidas
                                  ? Colors.redAccent
                                  : Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Lista de parcelas
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: parcelasGrupo
                          .map(
                            (parcela) =>
                                _buildItemParcela(pedido, parcela, dataService),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildItemParcela(
    Pedido pedido,
    PagamentoPedido parcela,
    DataService dataService,
  ) {
    final vencida = parcela.isVencida;
    final hoje = DateTime.now();
    final vencimento = parcela.dataVencimento;

    String statusVencimento = '';
    if (vencimento != null && !parcela.recebido) {
      final diasRestantes = vencimento.difference(hoje).inDays;
      if (diasRestantes < 0) {
        statusVencimento = 'Vencida há ${-diasRestantes} dia(s)';
      } else if (diasRestantes == 0) {
        statusVencimento = 'Vence hoje';
      } else {
        statusVencimento = 'Vence em $diasRestantes dia(s)';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: parcela.recebido
            ? Colors.green.withOpacity(0.15)
            : vencida
            ? Colors.red.withOpacity(0.15)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: parcela.recebido
              ? Colors.green.withOpacity(0.3)
              : vencida
              ? Colors.red.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          // Número da parcela
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: parcela.recebido
                  ? Colors.green.withOpacity(0.3)
                  : vencida
                  ? Colors.red.withOpacity(0.3)
                  : Colors.purple.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${parcela.numeroParcela ?? 1}',
                style: TextStyle(
                  color: parcela.recebido
                      ? Colors.greenAccent
                      : vencida
                      ? Colors.redAccent
                      : Colors.purpleAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Informações da parcela
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      parcela.tipo.nome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    if (parcela.recebido) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 14,
                      ),
                    ],
                  ],
                ),
                if (vencimento != null)
                  Text(
                    'Venc: ${vencimento.day.toString().padLeft(2, '0')}/${vencimento.month.toString().padLeft(2, '0')}/${vencimento.year}',
                    style: TextStyle(
                      color: vencida
                          ? Colors.redAccent
                          : Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                if (!parcela.recebido && statusVencimento.isNotEmpty)
                  Text(
                    statusVencimento,
                    style: TextStyle(
                      color: vencida ? Colors.redAccent : Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (parcela.recebido && parcela.dataRecebimento != null)
                  Text(
                    'Pago em ${_formatarDataHora(parcela.dataRecebimento!)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),

          // Valor
          Text(
            'R\$ ${parcela.valor.toStringAsFixed(2)}',
            style: TextStyle(
              color: parcela.recebido
                  ? Colors.greenAccent
                  : vencida
                  ? Colors.redAccent
                  : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),

          // Botão confirmar/estornar
          IconButton(
            onPressed: () => _toggleRecebimento(pedido, parcela, dataService),
            icon: Icon(
              parcela.recebido ? Icons.undo : Icons.check_circle,
              color: parcela.recebido ? Colors.orange : Colors.green,
              size: 20,
            ),
            tooltip: parcela.recebido ? 'Estornar' : 'Receber parcela',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildItemPagamento(
    Pedido pedido,
    PagamentoPedido pag,
    DataService dataService,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pag.recebido
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pag.recebido
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(_getIconeTipo(pag.tipo), color: _getCorTipo(pag.tipo), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pag.tipo.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (pag.recebido && pag.dataRecebimento != null)
                  Text(
                    'Recebido em ${_formatarDataHora(pag.dataRecebimento!)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                if (pag.tipo == TipoPagamento.dinheiro &&
                    pag.troco != null &&
                    pag.troco! > 0)
                  Text(
                    'Troco: R\$ ${pag.troco!.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.amber, fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(
            'R\$ ${pag.valor.toStringAsFixed(2)}',
            style: TextStyle(
              color: pag.recebido ? Colors.greenAccent : Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 4),
          // Botão confirmar/estornar
          IconButton(
            onPressed: () => _toggleRecebimento(pedido, pag, dataService),
            icon: Icon(
              pag.recebido ? Icons.undo : Icons.check_circle,
              color: pag.recebido ? Colors.orange : Colors.green,
              size: 20,
            ),
            tooltip: pag.recebido ? 'Estornar' : 'Confirmar recebimento',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  void _receberTodosPagamentos(Pedido pedido, DataService dataService) {
    final pagamentosPendentes = pedido.pagamentos
        .where((p) => !p.recebido)
        .toList();
    final valorPendente = pedido.totalPagamentos - pedido.totalRecebido;

    // Tipo original do primeiro pagamento pendente (ou dinheiro se não houver)
    final tipoOriginal = pagamentosPendentes.isNotEmpty
        ? pagamentosPendentes.first.tipo
        : TipoPagamento.dinheiro;

    String valorDigitado = '';
    double valorRecebido = valorPendente;
    double troco = 0;
    bool mostrarCalculadora = false;
    TipoPagamento tipoSelecionado = tipoOriginal; // Permite mudar a forma

    double digitosParaValor(String digitos) {
      if (digitos.isEmpty) return 0;
      final numero = int.tryParse(digitos) ?? 0;
      return numero / 100.0;
    }

    String formatarValor(String digitos) {
      final valor = digitosParaValor(digitos);
      return valor.toStringAsFixed(2);
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valorRestante = valorPendente - valorRecebido;
          final isParcial = valorRestante > 0.01;
          // Troco só é válido para pagamento em Dinheiro
          final temTroco =
              troco > 0.01 && tipoSelecionado == TipoPagamento.dinheiro;
          final isDinheiro = tipoSelecionado == TipoPagamento.dinheiro;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.attach_money,
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Receber Pagamentos',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pagamentosPendentes.length} pagamento(s) pendente(s)',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  // Valor total pendente
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total pendente:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'R\$ ${valorPendente.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.lightBlueAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Mostrar forma de pagamento original
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getIconeTipo(tipoOriginal),
                          color: Colors.purpleAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Original: ${tipoOriginal.nome}',
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Seletor de forma de pagamento
                  const Text(
                    'Receber como:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TipoPagamento.values.map((tipo) {
                      final isSelected = tipoSelecionado == tipo;
                      final isOriginal = tipo == tipoOriginal;
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            tipoSelecionado = tipo;
                            // Se mudou para não-Dinheiro, resetar troco
                            if (tipo != TipoPagamento.dinheiro) {
                              troco = 0;
                              // Limitar valor ao máximo pendente
                              if (valorRecebido > valorPendente) {
                                valorRecebido = valorPendente;
                                valorDigitado = (valorPendente * 100)
                                    .toInt()
                                    .toString();
                              }
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _getCorTipo(tipo).withOpacity(0.3)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? _getCorTipo(tipo)
                                  : isOriginal
                                  ? Colors.purpleAccent.withOpacity(0.5)
                                  : Colors.white24,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getIconeTipo(tipo),
                                color: isSelected
                                    ? _getCorTipo(tipo)
                                    : Colors.white54,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tipo.nome,
                                style: TextStyle(
                                  color: isSelected
                                      ? _getCorTipo(tipo)
                                      : Colors.white54,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Botões de valor rápido
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Botão valor exato
                      GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            valorDigitado = (valorPendente * 100)
                                .toInt()
                                .toString();
                            valorRecebido = valorPendente;
                            troco = 0;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.greenAccent),
                          ),
                          child: const Text(
                            'Valor exato',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // Botões de valor rápido - só mostra maiores que pendente se isDinheiro
                      ...[
                        10,
                        20,
                        50,
                        100,
                        200,
                      ].where((v) => isDinheiro || v <= valorPendente).map((
                        valor,
                      ) {
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              // Para não-dinheiro, limita ao valor pendente
                              final valorFinal = isDinheiro
                                  ? valor.toDouble()
                                  : (valor.toDouble() > valorPendente
                                        ? valorPendente
                                        : valor.toDouble());
                              valorDigitado = (valorFinal * 100)
                                  .toInt()
                                  .toString();
                              valorRecebido = valorFinal;
                              if (isDinheiro && valorRecebido > valorPendente) {
                                troco = valorRecebido - valorPendente;
                              } else {
                                troco = 0;
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'R\$ $valor',
                              style: const TextStyle(
                                color: Colors.lightBlueAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  // Calculadora para digitar valor (todos os tipos podem receber parcial)
                  const SizedBox(height: 16),
                  // Calculadora expansível
                  GestureDetector(
                    onTap: () {
                      setDialogState(() {
                        mostrarCalculadora = !mostrarCalculadora;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calculate,
                            color: Colors.greenAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              mostrarCalculadora
                                  ? 'Digitar valor: R\$ ${formatarValor(valorDigitado)}'
                                  : 'Digitar outro valor',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Icon(
                            mostrarCalculadora
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.greenAccent,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (mostrarCalculadora) ...[
                    const SizedBox(height: 12),
                    // Teclado numérico compacto usando Wrap
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            '1',
                            '2',
                            '3',
                            'C',
                            '4',
                            '5',
                            '6',
                            '⌫',
                            '7',
                            '8',
                            '9',
                            '00',
                            '.',
                            '0',
                            '00',
                            'OK',
                          ].map((tecla) {
                            return SizedBox(
                              width: 50,
                              height: 40,
                              child: GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    if (tecla == 'C') {
                                      valorDigitado = '';
                                      valorRecebido = valorPendente;
                                      troco = 0;
                                    } else if (tecla == '⌫') {
                                      if (valorDigitado.isNotEmpty) {
                                        valorDigitado = valorDigitado.substring(
                                          0,
                                          valorDigitado.length - 1,
                                        );
                                        final novoValor = digitosParaValor(
                                          valorDigitado,
                                        );
                                        valorRecebido = novoValor > 0
                                            ? novoValor
                                            : valorPendente;
                                        // Troco só para Dinheiro
                                        if (isDinheiro &&
                                            valorRecebido > valorPendente) {
                                          troco = valorRecebido - valorPendente;
                                        } else {
                                          troco = 0;
                                          // Não-Dinheiro: limitar ao valor pendente
                                          if (!isDinheiro &&
                                              valorRecebido > valorPendente) {
                                            valorRecebido = valorPendente;
                                            valorDigitado =
                                                (valorPendente * 100)
                                                    .toInt()
                                                    .toString();
                                          }
                                        }
                                      }
                                    } else if (tecla == 'OK') {
                                      mostrarCalculadora = false;
                                    } else if (tecla != '.') {
                                      if (valorDigitado.length < 10) {
                                        valorDigitado += tecla;
                                        final novoValor = digitosParaValor(
                                          valorDigitado,
                                        );
                                        // Não-Dinheiro: limitar ao valor pendente
                                        if (!isDinheiro &&
                                            novoValor > valorPendente) {
                                          valorRecebido = valorPendente;
                                          valorDigitado = (valorPendente * 100)
                                              .toInt()
                                              .toString();
                                          troco = 0;
                                        } else {
                                          valorRecebido = novoValor;
                                          // Troco só para Dinheiro
                                          if (isDinheiro &&
                                              valorRecebido > valorPendente) {
                                            troco =
                                                valorRecebido - valorPendente;
                                          } else {
                                            troco = 0;
                                          }
                                        }
                                      }
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: tecla == 'C'
                                        ? Colors.red.withOpacity(0.3)
                                        : tecla == 'OK'
                                        ? Colors.green.withOpacity(0.3)
                                        : tecla == '⌫'
                                        ? Colors.orange.withOpacity(0.3)
                                        : Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Center(
                                    child: Text(
                                      tecla,
                                      style: TextStyle(
                                        color: tecla == 'C'
                                            ? Colors.red
                                            : tecla == 'OK'
                                            ? Colors.greenAccent
                                            : tecla == '⌫'
                                            ? Colors.orange
                                            : Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Mostrar troco (só aparece se for Dinheiro - via temTroco)
                  if (temTroco)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.currency_exchange,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Troco: R\$ ${troco.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isParcial)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Faltando: R\$ ${valorRestante.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Parcelas não quitadas ficarão em aberto',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                            ),
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
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton.icon(
                onPressed: valorRecebido > 0
                    ? () {
                        Navigator.pop(context);
                        _processarRecebimentoTodos(
                          pedido,
                          pagamentosPendentes,
                          valorRecebido,
                          troco,
                          tipoSelecionado,
                          dataService,
                        );
                      }
                    : null,
                icon: const Icon(Icons.check),
                label: Text(isParcial ? 'Receber Parcial' : 'Receber Todos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isParcial ? Colors.orange : Colors.green,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _processarRecebimentoTodos(
    Pedido pedido,
    List<PagamentoPedido> pagamentosPendentes,
    double valorRecebido,
    double troco,
    TipoPagamento novoTipo,
    DataService dataService,
  ) {
    double valorRestanteTotal = valorRecebido;
    List<PagamentoPedido> novosPagamentos = [];

    for (final p in pedido.pagamentos) {
      if (p.recebido) {
        // Já recebido, manter
        novosPagamentos.add(p);
      } else {
        // Salvar tipo original se mudou
        final tipoOriginalParaSalvar = novoTipo != p.tipo
            ? (p.tipoOriginal ?? p.tipo)
            : p.tipoOriginal;

        // Pendente - verificar quanto podemos receber
        if (valorRestanteTotal >= p.valor) {
          // Pode pagar integralmente - atualiza tipo se mudou
          novosPagamentos.add(
            p.copyWith(
              tipo: novoTipo,
              tipoOriginal: tipoOriginalParaSalvar,
              recebido: true,
              dataRecebimento: DateTime.now(),
            ),
          );
          valorRestanteTotal -= p.valor;
        } else if (valorRestanteTotal > 0.01) {
          // Pagamento parcial desta parcela
          final valorParcial = valorRestanteTotal;
          final valorFaltante = p.valor - valorParcial;

          // Parcela recebida parcialmente - atualiza tipo
          novosPagamentos.add(
            p.copyWith(
              tipo: novoTipo,
              tipoOriginal: tipoOriginalParaSalvar,
              valor: valorParcial,
              recebido: true,
              dataRecebimento: DateTime.now(),
              valorRecebido: valorParcial,
            ),
          );

          // Nova parcela com o restante (mantém tipo original)
          novosPagamentos.add(
            PagamentoPedido(
              id: '${p.id}_resto_${DateTime.now().millisecondsSinceEpoch}',
              tipo: p.tipo, // Mantém tipo original para o restante
              valor: valorFaltante,
              recebido: false,
              dataVencimento: DateTime.now(),
              parcelas: p.parcelas,
              numeroParcela: p.numeroParcela,
              parcelamentoId: p.parcelamentoId,
            ),
          );

          valorRestanteTotal = 0;
        } else {
          // Não tem mais dinheiro, manter parcela pendente
          novosPagamentos.add(p);
        }
      }
    }

    // Buscar dados do cliente
    final cliente = pedido.clienteId != null
        ? dataService.clientes
              .where((c) => c.id == pedido.clienteId)
              .firstOrNull
        : null;

    // Verificar se ficará totalmente pago
    final totalRecebidoNovo = novosPagamentos
        .where((p) => p.recebido)
        .fold(0.0, (sum, p) => sum + p.valor);
    final todasParcelasRecebidas = novosPagamentos.every((p) => p.recebido);
    final ficaTotalmentePago =
        totalRecebidoNovo >= pedido.totalGeral && todasParcelasRecebidas;

    // Determinar status correto
    String novoStatus;
    if (ficaTotalmentePago) {
      novoStatus = 'Pago';
    } else if (totalRecebidoNovo > 0) {
      novoStatus = 'Parcialmente Pago';
    } else {
      novoStatus = 'Pendente';
    }

    final pedidoAtualizado = pedido.copyWith(
      pagamentos: novosPagamentos,
      clienteTelefone: cliente?.telefone ?? pedido.clienteTelefone,
      clienteEndereco: cliente?.endereco ?? pedido.clienteEndereco,
      status: novoStatus,
    );

    // ATUALIZAR ESTOQUE - Se pedido passou de Pendente para Pago
    // Dar baixa no estoque apenas na primeira vez que fica totalmente pago
    final estavaPendente = pedido.status == 'Pendente' || 
                          (pedido.totalRecebido <= 0 && pedido.pagamentos.any((p) => !p.recebido));
    if (ficaTotalmentePago && estavaPendente) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════╗');
      debugPrint('║  ATUALIZANDO ESTOQUE - PEDIDO RECEBIDO        ║');
      debugPrint('╚════════════════════════════════════════════════╝');
      
      for (final produtoItem in pedido.produtos) {
        try {
          final produto = dataService.produtos.firstWhere(
            (p) => p.id == produtoItem.id,
          );
          
          final estoqueAnterior = produto.estoque;
          final novoEstoque = (produto.estoque - produtoItem.quantidade) < 0 
              ? 0 
              : (produto.estoque - produtoItem.quantidade);
          
          dataService.updateProduto(
            produto.copyWith(
              estoque: novoEstoque,
              updatedAt: DateTime.now(),
            ),
          );
          
          debugPrint('>>> ✓ Baixa no estoque (pedido recebido):');
          debugPrint('>>>   Produto: ${produto.nome}');
          debugPrint('>>>   Estoque anterior: $estoqueAnterior');
          debugPrint('>>>   Quantidade vendida: ${produtoItem.quantidade}');
          debugPrint('>>>   Novo estoque: $novoEstoque');
        } catch (e) {
          debugPrint('>>> ERRO ao dar baixa no produto ${produtoItem.nome} (id: ${produtoItem.id}): $e');
        }
      }
      debugPrint('');
    }

    dataService.updatePedido(pedidoAtualizado);
    setState(() => _pedidoSelecionado = pedidoAtualizado);

    final valorRealmenteRecebido =
        valorRecebido > (pedido.totalPagamentos - pedido.totalRecebido)
        ? (pedido.totalPagamentos - pedido.totalRecebido)
        : valorRecebido;

    if (ficaTotalmentePago) {
      _mostrarSucessoRecebimento(
        valorRealmenteRecebido,
        pagamentosPendentes.length,
      );
    } else {
      final faltando = pedido.totalGeral - totalRecebidoNovo;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Recebido R\$ ${valorRealmenteRecebido.toStringAsFixed(2)} - Falta R\$ ${faltando.toStringAsFixed(2)}',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150,
            left: 16,
            right: 16,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Função para selecionar data do filtro
  Future<void> _selecionarDataFiltro(bool isInicio) async {
    final dataAtual = isInicio ? _dataInicioFiltro : _dataFimFiltro;
    final data = await showDatePicker(
      context: context,
      initialDate: dataAtual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.orange,
              surface: Color(0xFF1E1E2E),
            ),
          ),
          child: child!,
        );
      },
    );

    if (data != null) {
      setState(() {
        if (isInicio) {
          _dataInicioFiltro = data;
          // Se a data inicial for depois da final, ajustar a final
          if (_dataFimFiltro != null && _dataInicioFiltro!.isAfter(_dataFimFiltro!)) {
            _dataFimFiltro = _dataInicioFiltro;
          }
        } else {
          _dataFimFiltro = data;
          // Se a data final for antes da inicial, ajustar a inicial
          if (_dataInicioFiltro != null && _dataFimFiltro!.isBefore(_dataInicioFiltro!)) {
            _dataInicioFiltro = _dataFimFiltro;
          }
        }
      });
    }
  }

  void _mostrarSucessoRecebimento(double valor, int qtdPagamentos) {
    // Usa o popup animado com dinheiro caindo
    PopupSucessoVenda.mostrar(
      context,
      valor: valor,
      titulo: 'RECEBIDO COM SUCESSO!',
      subtitulo: '$qtdPagamentos pagamento(s)',
      onDismiss: () {
        // Limpar seleção e voltar para tela inicial
        if (mounted) {
          setState(() {
            _pedidoSelecionado = null;
            _termoBusca = '';
            _buscaController.clear();
          });
        }
      },
    );
  }

  void _toggleRecebimento(
    Pedido pedido,
    PagamentoPedido pagamento,
    DataService dataService,
  ) {
    if (pagamento.recebido) {
      // Estornar recebimento
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Estornar Recebimento',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Deseja estornar o recebimento de R\$ ${pagamento.valor.toStringAsFixed(2)}?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _atualizarRecebimento(pedido, pagamento, false, dataService);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Estornar'),
            ),
          ],
        ),
      );
    } else {
      // Receber - mostrar dialog com valor
      _mostrarDialogRecebimentoParcela(pedido, pagamento, dataService);
    }
  }

  void _mostrarDialogRecebimentoParcela(
    Pedido pedido,
    PagamentoPedido pagamento,
    DataService dataService,
  ) {
    String valorDigitado = ''; // Armazena os dígitos digitados
    double valorRecebido = pagamento.valor;
    double troco = 0;
    bool mostrarCalculadora = false; // Calculadora minimizada por padrão
    TipoPagamento tipoSelecionado = pagamento.tipo; // Permite mudar a forma

    // Função para converter dígitos em valor monetário (estilo PDV)
    double digitosParaValor(String digitos) {
      if (digitos.isEmpty) return 0;
      final numero = int.tryParse(digitos) ?? 0;
      return numero / 100.0;
    }

    // Função para formatar valor para exibição
    String formatarValor(String digitos) {
      final valor = digitosParaValor(digitos);
      return valor.toStringAsFixed(2);
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valorRestante = pagamento.valor - valorRecebido;
          final isParcial = valorRestante > 0.01;
          // Troco só é válido para pagamento em Dinheiro
          final temTroco =
              troco > 0.01 && tipoSelecionado == TipoPagamento.dinheiro;
          final isDinheiro = tipoSelecionado == TipoPagamento.dinheiro;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.attach_money,
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Receber Pagamento',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Valor da parcela
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Valor da parcela:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          'R\$ ${pagamento.valor.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.lightBlueAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Mostrar forma de pagamento original
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getIconeTipo(pagamento.tipoOriginalOuAtual),
                          color: Colors.purpleAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Original: ${pagamento.tipoOriginalOuAtual.nome}',
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (pagamento.tipoOriginal != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(Atual: ${pagamento.tipo.nome})',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Seletor de forma de pagamento
                  const Text(
                    'Receber como:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TipoPagamento.values.map((tipo) {
                      final isSelected = tipoSelecionado == tipo;
                      final isOriginal = tipo == pagamento.tipoOriginalOuAtual;
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            tipoSelecionado = tipo;
                            // Se mudou para não-Dinheiro, resetar troco
                            if (tipo != TipoPagamento.dinheiro) {
                              troco = 0;
                              // Limitar valor ao máximo da parcela
                              if (valorRecebido > pagamento.valor) {
                                valorRecebido = pagamento.valor;
                                valorDigitado = (pagamento.valor * 100)
                                    .toInt()
                                    .toString();
                              }
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.green.withOpacity(0.3)
                                : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.greenAccent
                                  : isOriginal
                                  ? Colors.purpleAccent.withOpacity(0.5)
                                  : Colors.transparent,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getIconeTipo(tipo),
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tipo.nome,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Botões de valor rápido
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Botão valor exato
                      GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            valorDigitado = (pagamento.valor * 100)
                                .toInt()
                                .toString();
                            valorRecebido = pagamento.valor;
                            troco = 0;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.greenAccent),
                          ),
                          child: Text(
                            'Valor exato',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // Botões de valor rápido - só mostra maiores que a parcela se for Dinheiro
                      ...[
                        5,
                        10,
                        20,
                        50,
                        100,
                      ].where((v) => isDinheiro || v <= pagamento.valor).map((
                        valor,
                      ) {
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              // Para não-dinheiro, limita ao valor da parcela
                              final valorFinal = isDinheiro
                                  ? valor.toDouble()
                                  : (valor.toDouble() > pagamento.valor
                                        ? pagamento.valor
                                        : valor.toDouble());
                              valorDigitado = (valorFinal * 100)
                                  .toInt()
                                  .toString();
                              valorRecebido = valorFinal;
                              if (isDinheiro &&
                                  valorRecebido > pagamento.valor) {
                                troco = valorRecebido - pagamento.valor;
                              } else {
                                troco = 0;
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'R\$ $valor',
                              style: const TextStyle(
                                color: Colors.lightBlueAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  // Calculadora para digitar valor (todos os tipos podem receber parcial)
                  const SizedBox(height: 16),
                  // Calculadora expansível
                  GestureDetector(
                    onTap: () {
                      setDialogState(() {
                        mostrarCalculadora = !mostrarCalculadora;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calculate,
                            color: Colors.greenAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              mostrarCalculadora
                                  ? 'Digitar valor: R\$ ${formatarValor(valorDigitado)}'
                                  : 'Digitar outro valor',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Icon(
                            mostrarCalculadora
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: Colors.greenAccent,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (mostrarCalculadora) ...[
                    const SizedBox(height: 12),
                    // Teclado numérico compacto usando Wrap
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            '1',
                            '2',
                            '3',
                            'C',
                            '4',
                            '5',
                            '6',
                            '⌫',
                            '7',
                            '8',
                            '9',
                            '00',
                            '.',
                            '0',
                            '00',
                            'OK',
                          ].map((tecla) {
                            return SizedBox(
                              width: 50,
                              height: 40,
                              child: GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    if (tecla == 'C') {
                                      valorDigitado = '';
                                      valorRecebido = pagamento.valor;
                                      troco = 0;
                                    } else if (tecla == '⌫') {
                                      if (valorDigitado.isNotEmpty) {
                                        valorDigitado = valorDigitado.substring(
                                          0,
                                          valorDigitado.length - 1,
                                        );
                                        final novoValor = digitosParaValor(
                                          valorDigitado,
                                        );
                                        valorRecebido = novoValor > 0
                                            ? novoValor
                                            : pagamento.valor;
                                        // Troco só para Dinheiro
                                        if (isDinheiro &&
                                            valorRecebido > pagamento.valor) {
                                          troco =
                                              valorRecebido - pagamento.valor;
                                        } else {
                                          troco = 0;
                                          // Não-Dinheiro: limitar ao valor da parcela
                                          if (!isDinheiro &&
                                              valorRecebido > pagamento.valor) {
                                            valorRecebido = pagamento.valor;
                                            valorDigitado =
                                                (pagamento.valor * 100)
                                                    .toInt()
                                                    .toString();
                                          }
                                        }
                                      }
                                    } else if (tecla == 'OK') {
                                      mostrarCalculadora = false;
                                    } else if (tecla != '.') {
                                      if (valorDigitado.length < 10) {
                                        valorDigitado += tecla;
                                        final novoValor = digitosParaValor(
                                          valorDigitado,
                                        );
                                        // Não-Dinheiro: limitar ao valor da parcela
                                        if (!isDinheiro &&
                                            novoValor > pagamento.valor) {
                                          valorRecebido = pagamento.valor;
                                          valorDigitado =
                                              (pagamento.valor * 100)
                                                  .toInt()
                                                  .toString();
                                          troco = 0;
                                        } else {
                                          valorRecebido = novoValor;
                                          // Troco só para Dinheiro
                                          if (isDinheiro &&
                                              valorRecebido > pagamento.valor) {
                                            troco =
                                                valorRecebido - pagamento.valor;
                                          } else {
                                            troco = 0;
                                          }
                                        }
                                      }
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: tecla == 'C'
                                        ? Colors.red.withOpacity(0.3)
                                        : tecla == 'OK'
                                        ? Colors.green.withOpacity(0.3)
                                        : tecla == '⌫'
                                        ? Colors.orange.withOpacity(0.3)
                                        : Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Center(
                                    child: Text(
                                      tecla,
                                      style: TextStyle(
                                        color: tecla == 'C'
                                            ? Colors.red
                                            : tecla == 'OK'
                                            ? Colors.greenAccent
                                            : tecla == '⌫'
                                            ? Colors.orange
                                            : Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Mostrar troco (só se for Dinheiro via temTroco)
                  if (temTroco)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.currency_exchange,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Troco: R\$ ${troco.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isParcial)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Faltando: R\$ ${valorRestante.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Será criada nova parcela com o valor restante',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                            ),
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
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton.icon(
                onPressed: valorRecebido > 0
                    ? () {
                        Navigator.pop(context);
                        _processarRecebimentoParcela(
                          pedido,
                          pagamento,
                          valorRecebido,
                          troco,
                          tipoSelecionado,
                          dataService,
                        );
                      }
                    : null,
                icon: const Icon(Icons.check),
                label: Text(isParcial ? 'Receber Parcial' : 'Receber'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isParcial ? Colors.orange : Colors.green,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _processarRecebimentoParcela(
    Pedido pedido,
    PagamentoPedido pagamento,
    double valorRecebido,
    double troco,
    TipoPagamento novoTipo,
    DataService dataService,
  ) {
    final valorRestante = pagamento.valor - valorRecebido;
    final isParcial = valorRestante > 0.01;
    // Salvar tipo original se mudou e ainda não tinha original salvo
    final tipoOriginalParaSalvar = novoTipo != pagamento.tipo
        ? (pagamento.tipoOriginal ?? pagamento.tipo)
        : pagamento.tipoOriginal;

    List<PagamentoPedido> novosPagamentos = [];

    for (final p in pedido.pagamentos) {
      if (p.id == pagamento.id) {
        if (isParcial) {
          // Pagamento parcial: atualiza valor, tipo e marca como recebido
          novosPagamentos.add(
            p.copyWith(
              tipo: novoTipo,
              tipoOriginal: tipoOriginalParaSalvar,
              valor: valorRecebido,
              recebido: true,
              dataRecebimento: DateTime.now(),
              valorRecebido: valorRecebido,
            ),
          );
          // Criar nova parcela com valor restante (mantém tipo original)
          novosPagamentos.add(
            PagamentoPedido(
              id: '${p.id}_resto_${DateTime.now().millisecondsSinceEpoch}',
              tipo: pagamento.tipo, // Mantém tipo original para o restante
              valor: valorRestante,
              recebido: false,
              dataVencimento: DateTime.now(), // Vence hoje
              parcelas: p.parcelas,
              numeroParcela: p.numeroParcela,
              parcelamentoId: p.parcelamentoId,
            ),
          );
        } else {
          // Pagamento total: marca como recebido
          // Troco só é registrado para pagamento em Dinheiro
          final salvarTroco = troco > 0 && novoTipo == TipoPagamento.dinheiro;
          novosPagamentos.add(
            p.copyWith(
              tipo: novoTipo,
              tipoOriginal: tipoOriginalParaSalvar,
              recebido: true,
              dataRecebimento: DateTime.now(),
              valorRecebido: salvarTroco ? valorRecebido : null,
              troco: salvarTroco ? troco : null,
            ),
          );
        }
      } else {
        novosPagamentos.add(p);
      }
    }

    // Buscar dados do cliente
    final cliente = pedido.clienteId != null
        ? dataService.clientes
              .where((c) => c.id == pedido.clienteId)
              .firstOrNull
        : null;

    // Verificar se ficará totalmente pago
    final totalRecebidoNovo = novosPagamentos
        .where((p) => p.recebido)
        .fold(0.0, (sum, p) => sum + p.valor);
    final todasParcelasRecebidas = novosPagamentos.every((p) => p.recebido);
    final ficaTotalmentePago =
        totalRecebidoNovo >= pedido.totalGeral && todasParcelasRecebidas;

    // Determinar status correto
    String novoStatus;
    if (ficaTotalmentePago) {
      novoStatus = 'Pago';
    } else if (totalRecebidoNovo > 0) {
      novoStatus = 'Parcialmente Pago';
    } else {
      novoStatus = 'Pendente';
    }

    final pedidoAtualizado = pedido.copyWith(
      pagamentos: novosPagamentos,
      clienteTelefone: cliente?.telefone ?? pedido.clienteTelefone,
      clienteEndereco: cliente?.endereco ?? pedido.clienteEndereco,
      status: novoStatus,
    );

    dataService.updatePedido(pedidoAtualizado);
    setState(() => _pedidoSelecionado = pedidoAtualizado);

    if (ficaTotalmentePago) {
      _mostrarSucessoRecebimento(valorRecebido, 1);
    } else if (isParcial) {
      // Mostrar mensagem de pagamento parcial
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.schedule, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Recebido R\$ ${valorRecebido.toStringAsFixed(2)} - Falta R\$ ${valorRestante.toStringAsFixed(2)}',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150,
            left: 16,
            right: 16,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✓ Recebimento confirmado!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150,
            left: 16,
            right: 16,
          ),
        ),
      );
    }
  }

  void _atualizarRecebimento(
    Pedido pedido,
    PagamentoPedido pagamento,
    bool recebido,
    DataService dataService,
  ) {
    final novosPagamentos = pedido.pagamentos.map((p) {
      if (p.id == pagamento.id) {
        return p.copyWith(
          recebido: recebido,
          dataRecebimento: recebido ? DateTime.now() : null,
        );
      }
      return p;
    }).toList();

    // Buscar dados do cliente para salvar no pedido quando receber
    final cliente = recebido && pedido.clienteId != null
        ? dataService.clientes
              .where((c) => c.id == pedido.clienteId)
              .firstOrNull
        : null;

    // Verificar se ficará totalmente pago para atualizar status
    // Precisa: 1) Total recebido >= total do pedido E 2) Todas as parcelas recebidas
    final totalRecebidoNovo = novosPagamentos
        .where((p) => p.recebido)
        .fold(0.0, (sum, p) => sum + p.valor);
    final todasParcelasRecebidas = novosPagamentos.every((p) => p.recebido);
    final ficaTotalmentePago =
        totalRecebidoNovo >= pedido.totalGeral && todasParcelasRecebidas;

    // Se estornando e estava pago, volta para Pendente
    String novoStatus = pedido.status;
    if (recebido && ficaTotalmentePago) {
      novoStatus = 'Pago';
    } else if (!recebido && pedido.status == 'Pago') {
      novoStatus = 'Pendente';
    }

    final pedidoAtualizado = pedido.copyWith(
      pagamentos: novosPagamentos,
      clienteTelefone: recebido
          ? (cliente?.telefone ?? pedido.clienteTelefone)
          : pedido.clienteTelefone,
      clienteEndereco: recebido
          ? (cliente?.endereco ?? pedido.clienteEndereco)
          : pedido.clienteEndereco,
      status: novoStatus,
    );

    // ATUALIZAR ESTOQUE - Se pedido passou de Pendente para Pago
    final estavaPendente = pedido.status == 'Pendente' || 
                          pedido.totalRecebido <= 0;
    if (recebido && pedidoAtualizado.totalmenteRecebido && estavaPendente) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════════════╗');
      debugPrint('║  ATUALIZANDO ESTOQUE - PEDIDO RECEBIDO        ║');
      debugPrint('╚════════════════════════════════════════════════╝');
      
      for (final produtoItem in pedido.produtos) {
        try {
          final produto = dataService.produtos.firstWhere(
            (p) => p.id == produtoItem.id,
          );
          
          final estoqueAnterior = produto.estoque;
          final novoEstoque = (produto.estoque - produtoItem.quantidade) < 0 
              ? 0 
              : (produto.estoque - produtoItem.quantidade);
          
          dataService.updateProduto(
            produto.copyWith(
              estoque: novoEstoque,
              updatedAt: DateTime.now(),
            ),
          );
          
          debugPrint('>>> ✓ Baixa no estoque (pedido recebido):');
          debugPrint('>>>   Produto: ${produto.nome}');
          debugPrint('>>>   Estoque anterior: $estoqueAnterior');
          debugPrint('>>>   Quantidade vendida: ${produtoItem.quantidade}');
          debugPrint('>>>   Novo estoque: $novoEstoque');
        } catch (e) {
          debugPrint('>>> ERRO ao dar baixa no produto ${produtoItem.nome}: $e');
        }
      }
      debugPrint('');
    }

    dataService.updatePedido(pedidoAtualizado);
    setState(() => _pedidoSelecionado = pedidoAtualizado);

    // Se agora está totalmente recebido, mostrar sucesso
    if (recebido && pedidoAtualizado.totalmenteRecebido) {
      _mostrarSucessoRecebimento(pagamento.valor, 1);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            recebido ? '✓ Recebimento confirmado!' : 'Recebimento estornado',
          ),
          backgroundColor: recebido ? Colors.green : Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150,
            left: 16,
            right: 16,
          ),
        ),
      );
    }
  }

  void _abrirDialogPagamento(Pedido pedido, DataService dataService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: PagamentoWidget(
          totalPedido: pedido.totalGeral,
          pagamentos: pedido.pagamentos,
          clienteId: pedido
              .clienteId, // Passa o clienteId para validação de crediário/fiado
          onPagamentosChanged: (novosPagamentos) {
            final pedidoAtualizado = pedido.copyWith(
              pagamentos: novosPagamentos,
            );
            dataService.updatePedido(pedidoAtualizado);
            setState(() => _pedidoSelecionado = pedidoAtualizado);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('✓ Pagamento adicionado!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(
                  bottom: MediaQuery.of(context).size.height - 150,
                  left: 16,
                  right: 16,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatarDataHora(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
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

  Color _getCorTipo(TipoPagamento tipo) {
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
      case TipoPagamento.fiado:
        return Colors.red;
      case TipoPagamento.outro:
        return Colors.grey;
    }
  }
}

// Classe auxiliar para agrupar créditos (fiado ou crediário) por cliente
class _GrupoCreditoCliente {
  final String clienteId;
  final String clienteNome;
  final List<Pedido> pedidos;
  final TipoPagamento tipoCredito; // fiado ou crediario

  _GrupoCreditoCliente({
    required this.clienteId,
    required this.clienteNome,
    required this.pedidos,
    required this.tipoCredito,
  });

  // Total de todas as vendas do tipo de crédito do cliente
  double get totalVendas {
    double total = 0.0;
    for (final pedido in pedidos) {
      for (final pag in pedido.pagamentos) {
        // Considerar pagamentos do tipo ou que originalmente eram do tipo
        if (pag.tipo == tipoCredito || pag.tipoOriginal == tipoCredito) {
          total += pag.valor;
        }
      }
    }
    return total;
  }

  // Total pendente (não recebido) do tipo de crédito
  double get totalPendente {
    double total = 0.0;
    for (final pedido in pedidos) {
      for (final pag in pedido.pagamentos) {
        if ((pag.tipo == tipoCredito || pag.tipoOriginal == tipoCredito) &&
            !pag.recebido) {
          total += pag.valor;
        }
      }
    }
    return total;
  }

  // Total já recebido
  double get totalRecebido {
    double total = 0.0;
    for (final pedido in pedidos) {
      for (final pag in pedido.pagamentos) {
        if ((pag.tipo == tipoCredito || pag.tipoOriginal == tipoCredito) &&
            pag.recebido) {
          total += pag.valor;
        }
      }
    }
    return total;
  }

  // Verifica se está totalmente pago
  bool get estaPago => totalPendente <= 0.01 && totalRecebido > 0;

  // Data da venda mais antiga
  DateTime get dataVendaMaisAntiga =>
      pedidos.map((p) => p.dataPedido).reduce((a, b) => a.isBefore(b) ? a : b);

  // Número de vendas
  int get quantidadeVendas => pedidos.length;
}

// Classe auxiliar para informações de pagamento pendente no PDV
class _PagamentoPendenteInfoPDV {
  final Pedido pedido;
  final PagamentoPedido pagamento;

  _PagamentoPendenteInfoPDV({required this.pedido, required this.pagamento});
}

// Classe auxiliar para parcelas de crediário
class _ParcelaCrediario {
  final Pedido pedido;
  final PagamentoPedido pagamento;
  final int indicePagamento;
  final int numeroParcela;
  final int totalParcelas;

  _ParcelaCrediario({
    required this.pedido,
    required this.pagamento,
    required this.indicePagamento,
    required this.numeroParcela,
    required this.totalParcelas,
  });

  // ID único para identificar a parcela
  String get id => '${pedido.id}_${pagamento.id}';
}
