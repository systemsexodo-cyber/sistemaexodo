import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../services/data_service.dart';
import '../models/pedido.dart';
import '../models/entrega.dart';
import '../models/forma_pagamento.dart';
import '../models/usuario.dart';
import '../models/link_vendedor.dart';
import '../theme.dart';
import 'lancar_pedido_page.dart';
import '../models/delivery_info.dart';
import 'entregas_page.dart';
import 'pdv_page.dart';
import 'entrega_detalhes_page.dart';
import 'venda_direta_page.dart';
import '../services/pedido_pdf_service.dart';
import '../services/producao_pdf_service.dart';
import '../services/auth_service.dart';
import '../models/empresa.dart';
import '../widgets/sync_status_widget.dart';
import 'criar_romaneio_page.dart';
import 'romaneios_page.dart';


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
  bool _modoSelecao = false;
  final Set<String> _selecionadosIds = {};

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
    // Usar listen: true para atualizar automaticamente quando os dados mudarem
    final dataService = Provider.of<DataService>(context, listen: true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final pedidos = _filtrarPedidos(dataService.pedidos, authService, dataService);

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
            if (_modoSelecao) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    '${_selecionadosIds.length} selecionado(s)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delivery_dining, color: Colors.greenAccent),
                tooltip: 'Gerar Romaneio',
                onPressed: _selecionadosIds.isEmpty ? null : _gerarRomaneio,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _modoSelecao = false;
                    _selecionadosIds.clear();
                  });
                },
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.assignment_outlined),
                tooltip: 'Ver Romaneios',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RomaneiosPage()),
                ),
              ),
              const SyncStatusWidget(),
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
            ],
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
                  MaterialPageRoute(builder: (context) => VendaDiretaPage()),
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
        floatingActionButton: (authService.usuarioAtual?.tipo == TipoUsuario.vendedor)
            ? null // Vendedores não podem criar pedidos manualmente
            : FloatingActionButton.extended(
                onPressed: () => _abrirLancamentoPedido(context),
                backgroundColor: Colors.green,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Novo Pedido'),
              ),
      ),
    );
  }

  List<Pedido> _filtrarPedidos(List<Pedido> pedidos, AuthService authService, DataService dataService) {
    // Se o usuário logado é vendedor, mostrar apenas seus pedidos
    final usuarioAtual = authService.usuarioAtual;
    final isVendedor = usuarioAtual?.tipo == TipoUsuario.vendedor;
    String? funcionarioIdVendedor;
    
    if (isVendedor && usuarioAtual?.funcionarioId != null) {
      funcionarioIdVendedor = usuarioAtual!.funcionarioId;
    }
    
    // Obter links de vendedores se necessário
    LinkVendedor? linkVendedorLogado;
    if (isVendedor && funcionarioIdVendedor != null) {
      linkVendedorLogado = dataService.linksVendedores.firstWhere(
        (l) => l.funcionarioId == funcionarioIdVendedor && l.ativo,
        orElse: () => LinkVendedor(
          id: '',
          funcionarioId: '',
          funcionarioNome: '',
          codigoLink: '',
          urlCompleta: '',
        ),
      );
    }
    
    // Filtrar apenas pedidos tradicionais (PED-), não vendas do PDV (VND-)
    // Incluir pedidos do e-commerce mesmo que tenham serviços
    List<Pedido> resultado = pedidos
        .where(
          (p) {
            // Se for vendedor, mostrar apenas pedidos do e-commerce dele
            if (isVendedor && funcionarioIdVendedor != null && linkVendedorLogado != null) {
              // Só mostrar se o pedido for do e-commerce E do vendedor logado
              if (linkVendedorLogado.id.isEmpty) {
                return false; // Vendedor não tem link, não mostra nada
              }
              
              final isPedidoDoVendedor = p.vendedorId == funcionarioIdVendedor ||
                  p.linkVendedorId == linkVendedorLogado.id ||
                  p.linkVendedorCodigo == linkVendedorLogado.codigoLink;
              
              if (!isPedidoDoVendedor) {
                return false; // Não é pedido deste vendedor
              }
            }
            
            // Incluir apenas pedidos tradicionais (PED-), não vendas do PDV (VND-)
            final isPedidoValido = p.numero.startsWith('PED-') ||
                (!p.numero.startsWith('VND-') && !p.numero.startsWith('VND'));
            
            // Incluir pedidos do e-commerce (identificados pelo campo origemEcommerce OU linkVendedorId/linkVendedorCodigo)
            final isPedidoEcommerce = p.origemEcommerce ||
                (p.linkVendedorId != null && p.linkVendedorId!.isNotEmpty) ||
                (p.linkVendedorCodigo != null && p.linkVendedorCodigo!.isNotEmpty);
            
            // Se for pedido válido
            return isPedidoValido;
          },
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

    // Ordenar por data (mais recentes primeiro) por padrão quando não estiver buscando
    if (_termoBusca.isEmpty) {
      resultado.sort((a, b) => b.dataPedido.compareTo(a.dataPedido));
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

    Pedido pedidoAtualizado = pedido.copyWith(status: novoStatus);
    
    // Se for um delivery e o status for "Entregue", atualizar também o status do delivery
    if (novoStatus.toLowerCase() == 'entregue' && pedido.deliveryInfo != null) {
      pedidoAtualizado = pedidoAtualizado.copyWith(
        deliveryInfo: pedido.deliveryInfo!.copyWith(status: 'entregue'),
      );
    }
    
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

  void _alternarSelecao(String id) {
    setState(() {
      if (_selecionadosIds.contains(id)) {
        _selecionadosIds.remove(id);
        if (_selecionadosIds.isEmpty) {
          _modoSelecao = false;
        }
      } else {
        _selecionadosIds.add(id);
        _modoSelecao = true;
      }
    });
  }

  void _gerarRomaneio() async {
    // Pegar pedidos selecionados
    final dataService = Provider.of<DataService>(context, listen: false);
    final selecionados = dataService.pedidos.where((p) => _selecionadosIds.contains(p.id)).toList();
    
    if (selecionados.isEmpty) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CriarRomaneioPage(pedidosSelecionados: selecionados),
      ),
    );

    if (result == true) {
      setState(() {
        _modoSelecao = false;
        _selecionadosIds.clear();
      });
    }
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
    final isSelecionado = _selecionadosIds.contains(pedido.id);
    
    final cliente = pedido.clienteId != null
        ? dataService.clientes
              .where((c) => c.id == pedido.clienteId)
              .firstOrNull
        : null;
    final telefone = pedido.clienteTelefone ?? cliente?.telefone;
    final endereco = pedido.clienteEndereco ?? cliente?.endereco;
    final entrega = dataService.getEntregaPorPedido(pedido.id);
    final taxaEntrega = entrega?.taxaEntrega;
    // Verificar se é pedido do e-commerce: campo origemEcommerce OU tem link de vendedor
    final isPedidoEcommerce = pedido.origemEcommerce ||
        (pedido.linkVendedorId != null && pedido.linkVendedorId!.isNotEmpty) ||
        (pedido.linkVendedorCodigo != null && pedido.linkVendedorCodigo!.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelecionado
                ? [
                    Colors.blue.shade700.withOpacity(0.4),
                    Colors.blue.shade900.withOpacity(0.3),
                  ]
                : isCancelado
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
        border: isSelecionado
            ? Border.all(color: Colors.blueAccent, width: 3)
            : isCancelado
            ? Border.all(color: Colors.redAccent, width: 2) // Borda vermelha para cancelado
            : isPago
            ? Border.all(color: Colors.greenAccent, width: 2)
            : isParcialmentePago
            ? Border.all(color: Colors.amber, width: 2)
            : null,
      ),
      child: InkWell(
        onLongPress: () {
          if (!_modoSelecao) {
            _alternarSelecao(pedido.id);
          }
        },
        onTap: _modoSelecao 
            ? () => _alternarSelecao(pedido.id)
            : isCancelado
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
                  if (_modoSelecao) ...[
                    Checkbox(
                      value: isSelecionado,
                      onChanged: (_) => _alternarSelecao(pedido.id),
                      activeColor: Colors.blueAccent,
                      side: BorderSide(color: Colors.white.withOpacity(0.4)),
                    ),
                    const SizedBox(width: 8),
                  ],
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
                  // Badge E-commerce
                  if (isPedidoEcommerce)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_cart,
                            color: Colors.white,
                            size: 12,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'E-commerce',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isPedidoEcommerce) const SizedBox(width: 8),

                  
                  // Badge Delivery vs Venda Direta
                  if (pedido.deliveryInfo != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_shipping, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'DELIVERY',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (!isPedidoEcommerce) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'LANÇAMENTO',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Badge PAGO
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'R\$ ${pedido.totalGeral.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      if (isParcialmentePago) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Falta: R\$ ${pedido.valorPendente.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      if (taxaEntrega != null && taxaEntrega > 0) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_shipping,
                              color: Colors.orange,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Taxa: R\$ ${taxaEntrega.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (isParcialmentePago) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (pedido.totalRecebido / pedido.totalGeral).clamp(0.0, 1.0),
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recebido: R\$ ${pedido.totalRecebido.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                    ),
                    Text(
                      '${((pedido.totalRecebido / pedido.totalGeral) * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                    ),
                  ],
                ),
              ],
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
              if (pedido.clienteEndereco != null && pedido.clienteEndereco!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on,
                      color: Colors.orangeAccent.withOpacity(0.8),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        pedido.clienteEndereco!,
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
              ],
              // Linha 3: Vendedor E-commerce (se existir)
              if (isPedidoEcommerce && pedido.vendedorNome != null && pedido.vendedorNome!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      color: Colors.purple[300],
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Vendedor: ${pedido.vendedorNome}',
                        style: TextStyle(
                          color: Colors.purple[300],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (pedido.linkVendedorCodigo != null && pedido.linkVendedorCodigo!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Link: ${pedido.linkVendedorCodigo}',
                          style: TextStyle(
                            color: Colors.purple[200],
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              // Linha 4: Endereço (se existir)
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatarDataCurta(pedido.dataPedido),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                      if (pedido.deliveryInfo?.dataEntrega != null)
                        Row(
                          children: [
                            const Icon(Icons.delivery_dining, size: 10, color: Colors.blueAccent),
                            const SizedBox(width: 4),
                            Text(
                              _formatarDataHora(pedido.deliveryInfo!.dataEntrega!),
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                    ],
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
                                'Entregue',
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
                        size: 18,
                        color: Colors.greenAccent,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      tooltip: 'Receber Pagamento',
                    ),
                  if (!isPago && pedido.status.toLowerCase() != 'cancelado' && (pedido.numero.startsWith('VND-') || pedido.numero.startsWith('VND')))
                    IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => VendaDiretaPage(pedidoParaEditar: pedido),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.shopping_cart_checkout,
                        size: 18,
                        color: Colors.blueAccent,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      tooltip: 'Continuar Venda no PDV',
                    ),
                  if (!isPago && pedido.status.toLowerCase() != 'cancelado') const SizedBox(width: 2),
                  // Botão editar
                  IconButton(
                    onPressed: (isPago || pedido.status.toLowerCase() == 'cancelado')
                        ? null
                        : () {
                            final authService = Provider.of<AuthService>(context, listen: false);
                            final empresa = authService.empresaAtual;
                            final exigirSenha = empresa?.configuracoes?['exigir_senha_alterar_pedido'] ?? false;

                            if (exigirSenha) {
                              _solicitarSenhaAdmin(
                                context: context,
                                titulo: 'Autorização do Administrador',
                                mensagem: 'Digite a senha master para alterar o pedido ${pedido.numero}:',
                                onConfirmar: () => _abrirLancamentoPedido(context, pedido: pedido),
                              );
                            } else {
                              _abrirLancamentoPedido(context, pedido: pedido);
                            }
                          },
                    icon: Icon(
                      Icons.edit,
                      size: 18,
                      color: (isPago || pedido.status.toLowerCase() == 'cancelado')
                          ? Colors.white30
                          : Colors.lightBlueAccent,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    tooltip: isPago
                        ? 'Pedido pago não pode ser editado'
                        : pedido.status.toLowerCase() == 'cancelado'
                            ? 'Pedido cancelado não pode ser editado'
                            : 'Editar',
                  ),
                  const SizedBox(width: 2),
                  // Botão cancelar
                  IconButton(
                    onPressed: (isPago || pedido.status.toLowerCase() == 'cancelado')
                        ? null
                        : () {
                            final authService = Provider.of<AuthService>(context, listen: false);
                            final empresa = authService.empresaAtual;
                            final exigirSenha = empresa?.configuracoes?['exigir_senha_cancelar_pedido'] ?? false;

                            if (exigirSenha) {
                              _solicitarSenhaAdmin(
                                context: context,
                                titulo: 'Autorização do Administrador',
                                mensagem: 'Digite a senha master para cancelar o pedido ${pedido.numero}:',
                                onConfirmar: () => _confirmarCancelamento(context, pedido, dataService),
                              );
                            } else {
                              _confirmarCancelamento(context, pedido, dataService);
                            }
                          },
                    icon: Icon(
                      Icons.cancel_outlined,
                      size: 18,
                      color: (isPago || pedido.status.toLowerCase() == 'cancelado')
                          ? Colors.white30
                          : Colors.orangeAccent,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    tooltip: isPago
                        ? 'Pedido pago não pode ser cancelado'
                        : pedido.status.toLowerCase() == 'cancelado'
                            ? 'Pedido já está cancelado'
                            : 'Cancelar Pedido',
                  ),
                  const SizedBox(width: 2),
                  // Botão imprimir - disponível para todos os pedidos
                  IconButton(
                    onPressed: () => _mostrarDialogoTipoImpressaoPedido(context, pedido),
                    icon: const Icon(
                      Icons.print,
                      size: 18,
                      color: Colors.orange,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    tooltip: 'Imprimir Pedido',
                  ),
                  const SizedBox(width: 2),
                  // Botão reimprimir produção - imprime os tickets nas impressoras dos setores
                  IconButton(
                    onPressed: () => _reimprimirProducao(context, pedido),
                    icon: const Icon(
                      Icons.restaurant,
                      size: 18,
                      color: Colors.deepOrangeAccent,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    tooltip: 'Reimprimir Produção (setores)',
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
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              final authService = Provider.of<AuthService>(context, listen: false);
              final empresa = authService.empresaAtual;
              final senhaDefinida = empresa?.configuracoes?['senha_admin']?.toString() ?? '';

              if (senhaDefinida.trim().isEmpty) {
                // Se não houver senha master configurada na empresa
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Configure uma Senha Master Admin no cadastro da empresa para liberar alterações de pedidos pagos.'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              _solicitarSenhaAdmin(
                context: context,
                titulo: 'Liberar Alteração de Pedido Pago',
                mensagem: 'Insira a Senha Master para permitir a alteração deste pedido pago:',
                onConfirmar: () {
                  _abrirLancamentoPedido(context, pedido: pedido);
                },
              );
            },
            icon: const Icon(Icons.lock_open, size: 18),
            label: const Text('Liberar Alteração'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _mostrarDialogoTipoImpressaoPedido(context, pedido);
            },
            icon: const Icon(Icons.receipt, size: 18),
            label: const Text('Imprimir'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  /// Mostra diálogo para escolher tipo de impressão do pedido
  Future<void> _mostrarDialogoTipoImpressaoPedido(
    BuildContext context,
    Pedido pedido,
  ) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Imprimir Pedido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt, color: Colors.orange, size: 32),
              title: const Text('Impressora Térmica (80mm)'),
              subtitle: const Text('Pedido para impressora térmica'),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              onTap: () {
                Navigator.pop(context);
                _imprimirPDFPedido(context, pedido, termico: true);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.purple, size: 32),
              title: const Text('Romaneio / Separação (80mm)'),
              subtitle: const Text('Apenas itens, sem valores financeiros'),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              onTap: () {
                Navigator.pop(context);
                _imprimirRomaneioPedido(context, pedido);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.blue, size: 32),
              title: const Text('PDF Normal (A4)'),
              subtitle: const Text('Pedido em formato PDF'),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              onTap: () {
                Navigator.pop(context);
                _imprimirPDFPedido(context, pedido, termico: false);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.teal, size: 32),
              title: const Text('Pré-visualizar PDF'),
              subtitle: const Text('Ver o pedido em PDF (A4) antes de imprimir'),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              onTap: () {
                Navigator.pop(context);
                _imprimirPDFPedido(context, pedido, termico: false, forcarPreview: true);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.deepOrange, size: 32),
              title: const Text('Pré-visualizar Térmico (80mm)'),
              subtitle: const Text('Ver a via térmica antes de imprimir'),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              onTap: () {
                Navigator.pop(context);
                _imprimirPDFPedido(context, pedido, termico: true, forcarPreview: true);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  /// Imprime PDF do pedido
  Future<void> _imprimirPDFPedido(
    BuildContext context,
    Pedido pedido, {
    required bool termico,
    bool forcarPreview = false,
  }) async {
    // Obter empresa atual
    final authService = Provider.of<AuthService>(context, listen: false);
    Empresa? empresa = authService.empresaAtual;
    
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

    // Mostrar diálogo de processamento apenas durante a geração do PDF
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(termico ? 'Gerando Pedido (Térmico)...' : 'Gerando Pedido (PDF)...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Fechar diálogo de loading antes de abrir a pré-visualização
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (termico) {
        await PedidoPDFService.imprimirPDFTermico(
          pedido: pedido,
          empresa: empresa,
          context: context,
          forcarPreview: forcarPreview,
        );
      } else {
        await PedidoPDFService.imprimirPDF(
          pedido: pedido,
          empresa: empresa,
          context: context,
          forcarPreview: forcarPreview,
        );
      }
    } catch (e) {
      // Fechar diálogo de loading em caso de erro
      if (context.mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {
          // Ignorar se o diálogo já foi fechado
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Reimprime os tickets de produção do pedido nas impressoras dos setores
  /// (Cozinha, Bar, etc. — conforme configurado em cada produto/departamento).
  Future<void> _reimprimirProducao(BuildContext context, Pedido pedido) async {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhuma empresa selecionada para imprimir a produção'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final inputs = pedido.produtos
          .map((it) => ItemProducaoInput(
                id: it.id,
                nome: it.nome,
                quantidade: it.quantidade,
                observacao: it.observacao,
                adicionais: it.adicionais.map((a) => a.nome).toList(),
              ))
          .toList();

      if (inputs.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhum item para reimprimir neste pedido'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final qtd = await ProducaoPdfService.imprimirTicketsProducao(
        itens: inputs,
        dataService: dataService,
        empresa: empresa,
        numeroDocumento: pedido.numero,
        clienteNome: pedido.clienteNome,
        isDelivery: pedido.deliveryInfo != null,
        detalhes: DetalhesTicketProducao(
          mesaComanda: pedido.origem,
          clienteTelefone: pedido.clienteTelefone,
          enderecoEntrega: pedido.clienteEndereco,
          motorista: pedido.deliveryInfo?.motoristaNome,
          previsaoEntrega: pedido.deliveryInfo?.previsaoEntrega,
          formasPagamento: pedido.pagamentos
              .where((p) => p.valor > 0)
              .map((p) => p.tipo.nome)
              .toList(),
          pagamentoConcluido: pedido.totalmenteRecebido,
          observacoesGerais: pedido.observacoes,
          // Hora do pedido + operador (para a cozinha)
          dataPedido: pedido.dataPedido,
          usuarioCriou: pedido.operador,
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(qtd > 0
                ? '✓ $qtd ticket(s) de produção reimpresso(s) em suas impressoras'
                : 'Nenhum item com impressora de produção configurada'),
            backgroundColor: qtd > 0 ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao reimprimir produção: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Imprime o Romaneio do pedido
  Future<void> _imprimirRomaneioPedido(
    BuildContext context,
    Pedido pedido,
  ) async {
    // Obter empresa atual
    final authService = Provider.of<AuthService>(context, listen: false);
    Empresa? empresa = authService.empresaAtual;
    
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

    // Mostrar diálogo de processamento
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Gerando Romaneio Térmico...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Gerar PDF do romaneio
      Uint8List pdfBytes = await PedidoPDFService.gerarRomaneioPDFTermico(
        pedido: pedido,
        empresa: empresa,
      );

      // Fechar diálogo de loading
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Agora abrir a tela de impressão
      if (context.mounted) {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: 'Romaneio_${pedido.numero}',
        );
        
        // Mostrar mensagem de sucesso
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Romaneio térmico gerado com sucesso'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // Fechar diálogo de loading em caso de erro
      if (context.mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {
          // Ignorar se o diálogo já foi fechado
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar Romaneio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

    // Montar endereço completo do cliente (endereço + número)
    String? enderecoCompleto;
    if (cliente?.endereco != null) {
      enderecoCompleto = cliente!.endereco!;
      if (cliente.numero != null && cliente.numero!.isNotEmpty) {
        enderecoCompleto += ', ${cliente.numero}';
      }
    }
    
    final novaEntrega = Entrega(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      pedidoId: pedido.id,
      pedidoNumero: pedido.numero,
      clienteNome: cliente?.nome ?? pedido.clienteNome ?? 'Cliente',
      clienteTelefone: cliente?.telefone ?? pedido.clienteTelefone,
      enderecoEntrega:
          enderecoCompleto ??
          pedido.clienteEndereco ??
          'Endereço não informado',
      complemento: cliente?.complemento,
      bairro: cliente?.bairro,
      cidade: cliente?.cidade,
      cep: cliente?.cep,
      pontoReferencia: cliente?.pontoReferencia,
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
      case StatusEntrega.romaneioCriado:
        return Colors.blue;
      case StatusEntrega.emEntrega:
        return Colors.deepPurple;
      case StatusEntrega.entregue:
        return Colors.green;
      case StatusEntrega.cancelado:
        return Colors.red;
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

  String _formatarDataHora(DateTime data) {
    final DateFormat formatter = DateFormat('dd/MM HH:mm');
    return formatter.format(data);
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
      case 'Entregue':
        return Colors.teal;
      case 'Pago':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Solicita a senha do administrador antes de executar uma ação crítica
  void _solicitarSenhaAdmin({
    required BuildContext context,
    required VoidCallback onConfirmar,
    required String titulo,
    String? mensagem,
  }) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;
    final senhaDefinida = empresa?.configuracoes?['senha_admin']?.toString() ?? '';

    // Se não tiver senha definida nas configurações da empresa, permite direto
    if (senhaDefinida.trim().isEmpty) {
      onConfirmar();
      return;
    }

    final senhaController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.security, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mensagem != null) ...[
              Text(mensagem, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: senhaController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Senha do Administrador',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              if (senhaController.text == senhaDefinida) {
                Navigator.pop(ctx);
                onConfirmar();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Senha incorreta! Permissão negada.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}
