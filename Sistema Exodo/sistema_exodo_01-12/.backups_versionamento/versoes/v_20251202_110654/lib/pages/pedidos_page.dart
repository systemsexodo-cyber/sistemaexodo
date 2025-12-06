import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/pedido.dart';
import '../models/entrega.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';
import 'lancar_pedido_page.dart';
import 'entregas_page.dart';
import 'pdv_page.dart';
import 'entrega_detalhes_page.dart';
import 'venda_direta_page.dart';

class PedidosPage extends StatefulWidget {
  const PedidosPage({super.key});

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage> {
  String _filtroStatus = 'Todos';
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';
  bool _mostrarBusca = false;
  DateTime? _dataInicioFiltro; // Filtro de data inicial
  DateTime? _dataFimFiltro; // Filtro de data final

  final List<String> _statusDisponiveis = [
    'Todos',
    'Pendente',
    'Parcialmente Pago',
    'Em Andamento',
    'Pago',
    'Cancelado',
  ];

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final pedidos = _filtrarPedidos(dataService.pedidos);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Pedidos'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          actions: [
            // Botão de busca
            IconButton(
              icon: Icon(
                _mostrarBusca ? Icons.search_off : Icons.search,
                color: _mostrarBusca
                    ? Colors.greenAccent
                    : Theme.of(context).colorScheme.onPrimary,
              ),
              tooltip: _mostrarBusca ? 'Fechar busca' : 'Buscar pedidos',
              onPressed: () {
                setState(() {
                  _mostrarBusca = !_mostrarBusca;
                  if (!_mostrarBusca) {
                    _termoBusca = '';
                    _buscaController.clear();
                  }
                });
              },
            ),
            // Filtro por status
            PopupMenuButton<String>(
              icon: Stack(
                children: [
                  Icon(
                    Icons.filter_list,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  if (_filtroStatus != 'Todos')
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _getCorStatus(_filtroStatus),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: 'Filtrar por status',
              onSelected: (status) {
                setState(() {
                  _filtroStatus = status;
                });
              },
              itemBuilder: (context) => _statusDisponiveis
                  .map(
                    (status) => PopupMenuItem(
                      value: status,
                      child: Row(
                        children: [
                          Icon(
                            _filtroStatus == status
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: _getCorStatus(status),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(status),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
            // Botão controle de entregas
            IconButton(
              icon: Icon(Icons.local_shipping, color: Colors.blue.shade800),
              tooltip: 'Controle de Entregas',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EntregasPage()),
                );
              },
            ),
            // Botão PDV
            IconButton(
              icon: const Icon(Icons.point_of_sale, color: Colors.greenAccent),
              tooltip: 'Abrir PDV - Venda Direta',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const VendaDiretaPage()),
                );
              },
            ),
            // Botão adicionar
            IconButton(
              icon: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
              tooltip: 'Novo Pedido',
              onPressed: () => _abrirLancamentoPedido(context),
            ),
          ],
        ),
        body: Column(
          children: [
            // Barra de busca inteligente
            _buildBarraBusca(),

            // Filtro de Data
            _buildFiltroData(),

            // Indicador de resultados
            if (_termoBusca.isNotEmpty || _filtroStatus != 'Todos' || _dataInicioFiltro != null || _dataFimFiltro != null)
              _buildIndicadorResultados(
                pedidos.length,
                dataService.pedidos.length,
              ),

            // Lista de pedidos
            Expanded(
              child: pedidos.isEmpty
                  ? _buildEmptyState()
                  : _buildListaPedidos(context, pedidos, dataService),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _abrirLancamentoPedido(context),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('Novo Pedido'),
        ),
      ),
    );
  }

  List<Pedido> _filtrarPedidos(List<Pedido> pedidos) {
    // Filtrar apenas pedidos tradicionais (PED-), não vendas do PDV (VND-)
    List<Pedido> resultado = pedidos
        .where(
          (p) =>
              p.numero.startsWith('PED-') ||
              (!p.numero.startsWith('VND-') && !p.numero.startsWith('VND')),
        )
        .toList();

    // Filtro por status
    if (_filtroStatus != 'Todos') {
      resultado = resultado.where((p) => p.status == _filtroStatus).toList();
    }

    // Filtro por data (data do pedido)
    if (_dataInicioFiltro != null) {
      resultado = resultado.where((p) {
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
        return !dataPedido.isBefore(dataInicio);
      }).toList();
    }

    if (_dataFimFiltro != null) {
      resultado = resultado.where((p) {
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
        return !dataPedido.isAfter(dataFim);
      }).toList();
    }

    // Busca inteligente e precisa
    if (_termoBusca.isNotEmpty) {
      final termo = _termoBusca.trim();
      final termoLower = termo.toLowerCase();
      
      // Extrair números do termo
      final numerosNoTermo = termo.replaceAll(RegExp(r'[^0-9]'), '');
      
      resultado = resultado.where((pedido) {
        final numeroPedido = pedido.numero.toLowerCase();
        final numeroPedidoLimpo = pedido.numero.replaceAll(RegExp(r'[^0-9]'), '');
        final clienteNome = (pedido.clienteNome ?? '').toLowerCase();
        
        // 1. Match exato do número do pedido (maior prioridade)
        if (numeroPedido == termoLower || numeroPedidoLimpo == numerosNoTermo) {
          return true;
        }
        
        // 2. Match exato do número sem prefixo (ex: "0001" encontra "PED-0001")
        if (numerosNoTermo.isNotEmpty && numeroPedidoLimpo == numerosNoTermo) {
          return true;
        }
        
        // 3. Número do pedido começa com o termo (ex: "PED-00" encontra "PED-0001")
        if (numeroPedido.startsWith(termoLower) || numeroPedidoLimpo.startsWith(numerosNoTermo)) {
          return true;
        }
        
        // 4. Número do pedido termina com o termo (ex: "01" encontra "PED-0001")
        if (numeroPedidoLimpo.endsWith(numerosNoTermo) && numerosNoTermo.length >= 2) {
          return true;
        }
        
        // 5. Match exato do nome do cliente
        if (clienteNome == termoLower) {
          return true;
        }
        
        // 6. Nome do cliente começa com o termo
        if (clienteNome.startsWith(termoLower)) {
          return true;
        }
        
        // 7. Busca por palavras no nome do cliente (split por espaços)
        final palavrasTermo = termoLower.split(' ').where((p) => p.isNotEmpty).toList();
        if (palavrasTermo.isNotEmpty) {
          final palavrasCliente = clienteNome.split(' ');
          final todasPalavrasEncontradas = palavrasTermo.every((palavra) =>
              palavrasCliente.any((pc) => pc.startsWith(palavra) || pc.contains(palavra)));
          if (todasPalavrasEncontradas) {
            return true;
          }
        }
        
        // 8. Nome do cliente contém o termo
        if (clienteNome.contains(termoLower)) {
          return true;
        }
        
        // 9. Número do pedido contém o termo
        if (numeroPedido.contains(termoLower) || numeroPedidoLimpo.contains(numerosNoTermo)) {
          return true;
        }
        
        // 10. Busca por valor exato
        final valorTermo = double.tryParse(termo.replaceAll(',', '.'));
        if (valorTermo != null) {
          final valorFormatado = pedido.totalGeral.toStringAsFixed(2);
          if (valorFormatado == termo.replaceAll(',', '.') ||
              valorFormatado.contains(termo.replaceAll(',', '.'))) {
            return true;
          }
        }
        
        return false;
      }).toList();
      
      // Ordenar por relevância: matches exatos primeiro
      resultado.sort((a, b) {
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
    }

    return resultado;
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

  void _abrirLancamentoPedido(BuildContext context, {Pedido? pedido}) {
    // Não permitir editar pedidos cancelados
    if (pedido != null && pedido.status.toLowerCase() == 'cancelado') {
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
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LancarPedidoPage(pedidoExistente: pedido),
      ),
    );
  }

  void _alterarStatus(
    Pedido pedido,
    String novoStatus,
    DataService dataService,
  ) {
    if (pedido.status == novoStatus) return;

    final pedidoAtualizado = pedido.copyWith(status: novoStatus);
    dataService.updatePedido(pedidoAtualizado);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Status alterado para "$novoStatus"'),
        backgroundColor: _getCorStatus(novoStatus),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 100,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            _termoBusca.isNotEmpty
                ? 'Nenhum pedido encontrado para "$_termoBusca"'
                : _filtroStatus == 'Todos'
                ? 'Nenhum pedido cadastrado'
                : 'Nenhum pedido "$_filtroStatus"',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _termoBusca.isNotEmpty
                ? 'Tente buscar por outro termo'
                : 'Clique no botão abaixo para criar um novo pedido',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          if (_termoBusca.isNotEmpty) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _termoBusca = '';
                  _buscaController.clear();
                });
              },
              icon: const Icon(Icons.clear),
              label: const Text('Limpar busca'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBarraBusca() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _mostrarBusca ? 80 : 0,
      child: _mostrarBusca
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Container(
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
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _buscaController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Ex: "001", "João", "PED-0005"...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white70,
                          ),
                          suffixIcon: _termoBusca.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _termoBusca = '';
                                      _buscaController.clear();
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        onChanged: (valor) {
                          setState(() {
                            _termoBusca = valor;
                          });
                        },
                      ),
                    ),
                    // Dicas de busca
                    if (_termoBusca.isEmpty)
                      Container(
                        padding: const EdgeInsets.only(right: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildChipDica('Nº'),
                            const SizedBox(width: 4),
                            _buildChipDica('Cliente'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildChipDica(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        texto,
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
      ),
    );
  }

  Widget _buildFiltroData() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_today,
            size: 18,
            color: Colors.orange,
          ),
          const SizedBox(width: 8),
          const Text(
            'Período:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          // Data Inicial
          GestureDetector(
            onTap: () => _selecionarDataFiltro(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    size: 16,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _dataInicioFiltro != null
                        ? DateFormat('dd/MM/yyyy').format(_dataInicioFiltro!)
                        : 'Data inicial',
                    style: TextStyle(
                      color: _dataInicioFiltro != null
                          ? Colors.white
                          : Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'até',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          // Data Final
          GestureDetector(
            onTap: () => _selecionarDataFiltro(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    size: 16,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _dataFimFiltro != null
                        ? DateFormat('dd/MM/yyyy').format(_dataFimFiltro!)
                        : 'Data final',
                    style: TextStyle(
                      color: _dataFimFiltro != null
                          ? Colors.white
                          : Colors.white54,
                      fontSize: 13,
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
    );
  }

  Widget _buildIndicadorResultados(int encontrados, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.white.withOpacity(0.6),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                ),
                children: [
                  if (_termoBusca.isNotEmpty) ...[
                    const TextSpan(text: 'Buscando por '),
                    TextSpan(
                      text: '"$_termoBusca"',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const TextSpan(text: ' • '),
                  ],
                  TextSpan(
                    text: '$encontrados',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: ' de $total ${total == 1 ? 'pedido' : 'pedidos'}',
                  ),
                  if (_filtroStatus != 'Todos') ...[
                    const TextSpan(text: ' • '),
                    TextSpan(
                      text: _filtroStatus,
                      style: TextStyle(
                        color: _getCorStatus(_filtroStatus),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (_dataInicioFiltro != null || _dataFimFiltro != null) ...[
                    const TextSpan(text: ' • '),
                    TextSpan(
                      text: 'Período: ${_dataInicioFiltro != null ? DateFormat('dd/MM/yyyy').format(_dataInicioFiltro!) : '...'} até ${_dataFimFiltro != null ? DateFormat('dd/MM/yyyy').format(_dataFimFiltro!) : '...'}',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_termoBusca.isNotEmpty || _filtroStatus != 'Todos' || _dataInicioFiltro != null || _dataFimFiltro != null)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _termoBusca = '';
                  _buscaController.clear();
                  _filtroStatus = 'Todos';
                  _dataInicioFiltro = null;
                  _dataFimFiltro = null;
                });
              },
              icon: const Icon(Icons.clear_all, size: 16),
              label: const Text('Limpar'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildListaPedidos(
    BuildContext context,
    List<Pedido> pedidos,
    DataService dataService,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: pedidos.length,
      itemBuilder: (context, index) {
        final pedido = pedidos[index];
        return _buildCardPedido(context, pedido, dataService);
      },
    );
  }

  Widget _buildCardPedido(
    BuildContext context,
    Pedido pedido,
    DataService dataService,
  ) {
    final isCancelado = pedido.status.toLowerCase() == 'cancelado';
    // Pedidos cancelados não são considerados como pagos, mesmo que tenham recebido
    final isPago = !isCancelado && pedido.totalmenteRecebido;
    final isParcialmentePago = !isCancelado && pedido.totalRecebido > 0 && !isPago;
    final cliente = pedido.clienteId != null
        ? dataService.clientes
              .where((c) => c.id == pedido.clienteId)
              .firstOrNull
        : null;
    final telefone = pedido.clienteTelefone ?? cliente?.telefone;
    final endereco = pedido.clienteEndereco ?? cliente?.endereco;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCancelado
              ? [
                  Colors.red.shade900,
                  Colors.red.shade800,
                ] // Vermelho escuro para cancelado
              : isParcialmentePago
              ? [
                  const Color(0xFF5D4037),
                  const Color(0xFF795548),
                ] // Bege/marrom para parcialmente pago
              : [const Color(0xFF2C3E50), const Color(0xFF34495E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: isCancelado
            ? Border.all(color: Colors.redAccent, width: 2) // Borda vermelha para cancelado
            : isPago
            ? Border.all(color: Colors.greenAccent, width: 2)
            : isParcialmentePago
            ? Border.all(color: Colors.amber, width: 2)
            : null,
      ),
      child: InkWell(
        onTap: isCancelado
            ? null // Pedidos cancelados não são clicáveis
            : isPago
            ? () => _mostrarDetalhesPedidoPago(context, pedido, dataService)
            : () => _abrirLancamentoPedido(context, pedido: pedido),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha 1: Número, Status e Valor
              Row(
                children: [
                  // Número do pedido
                  Text(
                    pedido.numero.isNotEmpty
                        ? pedido.numero
                        : '#${pedido.id.substring(pedido.id.length > 6 ? pedido.id.length - 6 : 0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Badge PAGO
                  if (isPago)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Color(0xFF1B5E20),
                            size: 12,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'PAGO',
                            style: TextStyle(
                              color: Color(0xFF1B5E20),
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Badge EM ABERTO (Parcialmente Pago)
                  if (isParcialmentePago)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.hourglass_bottom,
                            color: Color(0xFF795548),
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'EM ABERTO - Falta R\$ ${(pedido.totalGeral - pedido.totalRecebido).toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF795548),
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  // Valor total
                  Text(
                    'R\$ ${pedido.totalGeral.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Linha 2: Cliente e Telefone
              Row(
                children: [
                  Icon(
                    Icons.person,
                    color: Colors.white.withOpacity(0.6),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pedido.clienteNome ?? 'Venda Balcão',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (telefone != null && telefone.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(
                      Icons.phone,
                      color: Colors.blue.withOpacity(0.8),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      telefone,
                      style: TextStyle(
                        color: Colors.blue.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              // Linha 3: Endereço (se existir)
              if (endereco != null && endereco.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: Colors.orange.withOpacity(0.7),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        endereco,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              // Linha 4: Data, Itens, Status e Ações de edição
              Row(
                children: [
                  // Data
                  Text(
                    _formatarDataCurta(pedido.dataPedido),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Itens
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${pedido.quantidadeItens} ${pedido.quantidadeItens == 1 ? 'item' : 'itens'}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  if (!isPago)
                    PopupMenuButton<String>(
                      onSelected: (novoStatus) =>
                          _alterarStatus(pedido, novoStatus, dataService),
                      padding: EdgeInsets.zero,
                      itemBuilder: (context) =>
                          [
                                'Pendente',
                                'Parcialmente Pago',
                                'Em Andamento',
                                'Pago',
                                'Cancelado',
                              ]
                              .map(
                                (status) => PopupMenuItem(
                                  value: status,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _getCorStatus(status),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        status,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _getCorStatus(pedido.status),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          pedido.status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  // Ações de edição - sempre visíveis
                  // Botão receber pagamento
                  if (!isPago && pedido.status.toLowerCase() != 'cancelado')
                    IconButton(
                      onPressed: () => _abrirRecebimento(context, pedido),
                      icon: const Icon(
                        Icons.attach_money,
                        size: 20,
                        color: Colors.greenAccent,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      tooltip: 'Receber Pagamento',
                    ),
                  if (!isPago && pedido.status.toLowerCase() != 'cancelado') const SizedBox(width: 4),
                  // Botão editar
                  IconButton(
                    onPressed: (isPago || pedido.status.toLowerCase() == 'cancelado')
                        ? null
                        : () => _abrirLancamentoPedido(context, pedido: pedido),
                    icon: Icon(
                      Icons.edit,
                      size: 20,
                      color: (isPago || pedido.status.toLowerCase() == 'cancelado')
                          ? Colors.white30
                          : Colors.lightBlueAccent,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    tooltip: isPago
                        ? 'Pedido pago não pode ser editado'
                        : pedido.status.toLowerCase() == 'cancelado'
                            ? 'Pedido cancelado não pode ser editado'
                            : 'Editar',
                  ),
                  const SizedBox(width: 4),
                  // Botão cancelar
                  IconButton(
                    onPressed: (isPago || pedido.status.toLowerCase() == 'cancelado')
                        ? null
                        : () =>
                              _confirmarCancelamento(context, pedido, dataService),
                    icon: Icon(
                      Icons.cancel_outlined,
                      size: 20,
                      color: (isPago || pedido.status.toLowerCase() == 'cancelado')
                          ? Colors.white30
                          : Colors.orangeAccent,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    tooltip: isPago
                        ? 'Pedido pago não pode ser cancelado'
                        : pedido.status.toLowerCase() == 'cancelado'
                            ? 'Pedido já está cancelado'
                            : 'Cancelar Pedido',
                  ),
                ],
              ),
              // Linha 5: Botão de Receber em destaque (para pedidos não pagos e não cancelados)
              if (!isPago && pedido.status.toLowerCase() != 'cancelado') ...[
                const SizedBox(height: 10),
                _buildBotaoReceberDestacado(pedido),
              ],
              // Linha 6: Botão de Entrega em destaque (para pedidos não pagos e não cancelados)
              if (!isPago && pedido.status.toLowerCase() != 'cancelado') ...[
                const SizedBox(height: 8),
                _buildBotaoEntregaDestacado(pedido, dataService),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _abrirRecebimento(BuildContext context, Pedido pedido) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PdvPage(pedidoInicial: pedido)),
    );
  }

  Widget _buildBotaoReceberDestacado(Pedido pedido) {
    final isCancelado = pedido.status.toLowerCase() == 'cancelado';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isCancelado ? null : () => _abrirRecebimento(context, pedido),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4CAF50).withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.point_of_sale, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text(
                'RECEBER PAGAMENTO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBotaoEntregaDestacado(Pedido pedido, DataService dataService) {
    final entrega = dataService.getEntregaPorPedido(pedido.id);

    if (entrega != null) {
      // Entrega já existe - mostrar status
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EntregasPage()),
          ),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getCorStatusEntrega(entrega.status).withOpacity(0.3),
                  _getCorStatusEntrega(entrega.status).withOpacity(0.1),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _getCorStatusEntrega(entrega.status).withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_shipping,
                  color: _getCorStatusEntrega(entrega.status),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  'ENTREGA: ${entrega.status.nome.toUpperCase()}',
                  style: TextStyle(
                    color: _getCorStatusEntrega(entrega.status),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  color: _getCorStatusEntrega(entrega.status),
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Sem entrega - mostrar botão para criar
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _criarEntrega(pedido, dataService),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2196F3).withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_shipping, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text(
                'CRIAR ENTREGA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.add_circle_outline, color: Colors.white, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDetalhesPedidoPago(
    BuildContext context,
    Pedido pedido,
    DataService dataService,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent),
            const SizedBox(width: 8),
            Text(pedido.numero, style: const TextStyle(color: Colors.white)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.greenAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'PAGO',
                style: TextStyle(
                  color: Color(0xFF1B5E20),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pedido.clienteNome != null) ...[
              _buildInfoRow(Icons.person, 'Cliente', pedido.clienteNome!),
              const SizedBox(height: 8),
            ],
            if (pedido.clienteTelefone != null) ...[
              _buildInfoRow(Icons.phone, 'Telefone', pedido.clienteTelefone!),
              const SizedBox(height: 8),
            ],
            if (pedido.clienteEndereco != null) ...[
              _buildInfoRow(
                Icons.location_on,
                'Endereço',
                pedido.clienteEndereco!,
              ),
              const SizedBox(height: 8),
            ],
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.shopping_bag,
              'Itens',
              '${pedido.quantidadeItens}',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.calendar_today,
              'Data',
              _formatarData(pedido.dataPedido),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.attach_money,
              'Total',
              'R\$ ${pedido.totalGeral.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.greenAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Este pedido já foi pago e não pode ser alterado.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatarDataCurta(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
  }

  void _criarEntrega(Pedido pedido, DataService dataService) {
    // Buscar cliente do pedido — usar somente se existir correspondência clara
    Cliente? cliente;
    if (pedido.clienteId != null) {
      final encontrados = dataService.clientes
          .where((c) => c.id == pedido.clienteId)
          .toList();
      if (encontrados.isNotEmpty) cliente = encontrados.first;
    }

    final novaEntrega = Entrega(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      pedidoId: pedido.id,
      pedidoNumero: pedido.numero,
      clienteNome: cliente?.nome ?? pedido.clienteNome ?? 'Cliente',
      clienteTelefone: cliente?.telefone ?? pedido.clienteTelefone,
      enderecoEntrega:
          cliente?.endereco ??
          pedido.clienteEndereco ??
          'Endereço não informado',
      dataCriacao: DateTime.now(),
      dataPrevisao: DateTime.now().add(const Duration(days: 1)),
      quantidadeVolumes: pedido.quantidadeItens,
      historico: [
        EventoEntrega(
          id: '1',
          dataHora: DateTime.now(),
          status: StatusEntrega.aguardando,
          descricao: 'Entrega criada a partir do pedido ${pedido.numero}',
        ),
      ],
    );

    // Salvar a entrega
    dataService.addEntrega(novaEntrega);

    // Navegar para a página de detalhes da entrega para editar os dados
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EntregaDetalhesPage(entrega: novaEntrega),
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Text('Entrega criada! Preencha os dados de entrega.'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
      ),
    );
  }

  Color _getCorStatusEntrega(StatusEntrega status) {
    switch (status) {
      case StatusEntrega.aguardando:
        return Colors.orange;
      case StatusEntrega.entregue:
        return Colors.green;
    }
  }

  // Confirmar cancelamento de pedido
  void _confirmarCancelamento(
    BuildContext context,
    Pedido pedido,
    DataService dataService,
  ) {
    final motivoController = TextEditingController();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final valorPendente = pedido.totalGeral - pedido.totalRecebido;

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
            const Expanded(
              child: Text(
                'Cancelar Pedido',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pedido: ${pedido.numero.isNotEmpty ? pedido.numero : '#${pedido.id.substring(pedido.id.length > 6 ? pedido.id.length - 6 : 0)}'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (pedido.clienteNome != null) ...[
              const SizedBox(height: 8),
              Text(
                'Cliente: ${pedido.clienteNome}',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Valor pendente: ${formatoMoeda.format(valorPendente)}',
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Motivo do cancelamento:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: motivoController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Informe o motivo...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
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
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ Esta ação irá cancelar o pedido e remover o valor pendente.',
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
              _processarCancelamento(pedido, dataService, motivo);
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

  // Processar cancelamento de pedido
  void _processarCancelamento(
    Pedido pedido,
    DataService dataService,
    String motivo,
  ) {
    // Criar novos pagamentos marcando como cancelados (mas NÃO como recebidos)
    // Apenas adicionar observação de cancelamento nos pagamentos pendentes
    final novosPagamentos = pedido.pagamentos.map((pag) {
      if (!pag.recebido) {
        // Não marcar como recebido, apenas adicionar observação de cancelamento
        return PagamentoPedido(
          id: pag.id,
          tipo: pag.tipo,
          valor: pag.valor,
          recebido: false, // NÃO marcar como recebido
          dataRecebimento: null, // Não tem data de recebimento
          dataVencimento: pag.dataVencimento,
          parcelas: pag.parcelas,
          numeroParcela: pag.numeroParcela,
          parcelamentoId: pag.parcelamentoId,
          observacao:
              '❌ CANCELADO: $motivo (${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())})',
        );
      }
      // Pagamentos já recebidos mantêm como estão
      return pag;
    }).toList();

    // Se não tem pagamentos, criar um pagamento cancelado com o valor total (mas não recebido)
    if (novosPagamentos.isEmpty && pedido.totalGeral > 0) {
      novosPagamentos.add(
        PagamentoPedido(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          tipo: TipoPagamento.outro,
          valor: pedido.totalGeral,
          recebido: false, // NÃO marcar como recebido
          dataRecebimento: null,
          observacao:
              '❌ CANCELADO: $motivo (${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())})',
        ),
      );
    }

    // Atualizar pedido com status cancelado (garantir que seja "Cancelado")
    final pedidoAtualizado = pedido.copyWith(
      status: 'Cancelado', // Status explícito de cancelado
      observacoes: '${pedido.observacoes ?? ''}\n[PEDIDO CANCELADO] $motivo'
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
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Pedido ${pedido.numero.isNotEmpty ? pedido.numero : '#'} cancelado com sucesso',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
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

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year} às ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
  }

  Color _getCorStatus(String status) {
    switch (status) {
      case 'Pendente':
        return Colors.orange;
      case 'Parcialmente Pago':
        return Colors.amber;
      case 'Em Andamento':
        return Colors.blue;
      case 'Pago':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
