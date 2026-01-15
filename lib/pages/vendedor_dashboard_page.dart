import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/comissao_vendedor.dart';
import 'package:sistema_exodo_novo/models/usuario.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:intl/intl.dart';

class VendedorDashboardPage extends StatefulWidget {
  final String? funcionarioId; // Se null, mostra todos os vendedores

  const VendedorDashboardPage({super.key, this.funcionarioId});

  @override
  State<VendedorDashboardPage> createState() => _VendedorDashboardPageState();
}

class _VendedorDashboardPageState extends State<VendedorDashboardPage> {
  String _filtroStatus = 'Todos'; // Todos, Pendente, Paga, Cancelada
  String _filtroPeriodo = '30'; // 7, 30, 90, 365, Todos

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    // Filtrar comissões
    List<ComissaoVendedor> comissoes = dataService.comissoesVendedores;
    
    // Se o usuário logado é vendedor, mostrar apenas suas comissões
    final usuarioAtual = authService.usuarioAtual;
    final isVendedor = usuarioAtual?.tipo == TipoUsuario.vendedor;
    String? funcionarioIdLogado;
    
    if (isVendedor && usuarioAtual?.funcionarioId != null) {
      funcionarioIdLogado = usuarioAtual!.funcionarioId;
    }
    
    // Filtrar por vendedor se especificado ou se for vendedor logado
    final funcionarioIdFiltro = widget.funcionarioId ?? funcionarioIdLogado;
    if (funcionarioIdFiltro != null) {
      comissoes = comissoes.where((c) => c.funcionarioId == funcionarioIdFiltro).toList();
    }

    // Filtrar por status
    if (_filtroStatus != 'Todos') {
      comissoes = comissoes.where((c) => c.status == _filtroStatus).toList();
    }

    // Filtrar por período
    final agora = DateTime.now();
    DateTime dataInicio;
    switch (_filtroPeriodo) {
      case '7':
        dataInicio = agora.subtract(const Duration(days: 7));
        break;
      case '30':
        dataInicio = agora.subtract(const Duration(days: 30));
        break;
      case '90':
        dataInicio = agora.subtract(const Duration(days: 90));
        break;
      case '365':
        dataInicio = agora.subtract(const Duration(days: 365));
        break;
      default:
        dataInicio = DateTime(2000);
    }
    if (_filtroPeriodo != 'Todos') {
      comissoes = comissoes.where((c) => c.createdAt.isAfter(dataInicio)).toList();
    }

    // Calcular estatísticas
    final totalVendas = comissoes.length;
    final totalComissao = comissoes.fold(0.0, (sum, c) => sum + c.valorComissao);
    final totalComissaoPendente = comissoes
        .where((c) => c.status == 'Pendente')
        .fold(0.0, (sum, c) => sum + c.valorComissao);
    final totalValorVendas = comissoes.fold(0.0, (sum, c) => sum + c.valorPedido);

    // Agrupar por vendedor (se não especificado)
    Map<String, List<ComissaoVendedor>> comissoesPorVendedor = {};
    if (widget.funcionarioId == null) {
      for (final comissao in comissoes) {
        if (!comissoesPorVendedor.containsKey(comissao.funcionarioId)) {
          comissoesPorVendedor[comissao.funcionarioId] = [];
        }
        comissoesPorVendedor[comissao.funcionarioId]!.add(comissao);
      }
    }

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.funcionarioId == null 
              ? 'Dashboard de Vendedores' 
              : 'Meu Dashboard'),
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
        ),
        body: Column(
        children: [
          // Filtros
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF23272A).withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: ['Todos', 'Pendente', 'Paga', 'Cancelada']
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
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroPeriodo,
                    decoration: const InputDecoration(
                      labelText: 'Período',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      DropdownMenuItem(value: '7', child: Text('7 dias')),
                      DropdownMenuItem(value: '30', child: Text('30 dias')),
                      DropdownMenuItem(value: '90', child: Text('90 dias')),
                      DropdownMenuItem(value: '365', child: Text('1 ano')),
                      DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _filtroPeriodo = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Estatísticas
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total de Vendas',
                    totalVendas.toString(),
                    Icons.shopping_cart,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'Valor Total',
                    formatoMoeda.format(totalValorVendas),
                    Icons.attach_money,
                    Colors.green,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Comissão Total',
                    formatoMoeda.format(totalComissao),
                    Icons.account_balance_wallet,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'Comissão Pendente',
                    formatoMoeda.format(totalComissaoPendente),
                    Icons.pending,
                    Colors.red,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Lista de comissões
          Expanded(
            child: widget.funcionarioId == null && comissoesPorVendedor.isNotEmpty
                ? _buildListaPorVendedor(comissoesPorVendedor, formatoMoeda, formatoData)
                : _buildListaComissoes(comissoes, formatoMoeda, formatoData),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaPorVendedor(
    Map<String, List<ComissaoVendedor>> comissoesPorVendedor,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: comissoesPorVendedor.length,
      itemBuilder: (context, index) {
        final vendedorId = comissoesPorVendedor.keys.elementAt(index);
        final comissoes = comissoesPorVendedor[vendedorId]!;
        final vendedorNome = comissoes.first.funcionarioNome;
        final totalComissao = comissoes.fold(0.0, (sum, c) => sum + c.valorComissao);
        final totalVendas = comissoes.length;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ExpansionTile(
            leading: CircleAvatar(
              child: Text(vendedorNome[0].toUpperCase()),
            ),
            title: Text(vendedorNome),
            subtitle: Text('$totalVendas vendas • ${formatoMoeda.format(totalComissao)}'),
            children: comissoes.map((comissao) {
              return ListTile(
                title: Text('Pedido ${comissao.pedidoNumero}'),
                subtitle: Text(formatoData.format(comissao.createdAt)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatoMoeda.format(comissao.valorComissao),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Chip(
                      label: Text(comissao.status),
                      backgroundColor: _getStatusColor(comissao.status),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildListaComissoes(
    List<ComissaoVendedor> comissoes,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    if (comissoes.isEmpty) {
      return Center(
        child: Text(
          'Nenhuma comissão encontrada',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: comissoes.length,
      itemBuilder: (context, index) {
        final comissao = comissoes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(comissao.status),
              child: Icon(
                comissao.status == 'Paga' ? Icons.check : Icons.pending,
                color: Colors.white,
              ),
            ),
            title: Text('Pedido ${comissao.pedidoNumero}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${formatoData.format(comissao.createdAt)} • ${comissao.funcionarioNome}'),
                Text(
                  'Pedido: ${formatoMoeda.format(comissao.valorPedido)} • ${comissao.percentualComissao}%',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatoMoeda.format(comissao.valorComissao),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Chip(
                  label: Text(comissao.status),
                  backgroundColor: _getStatusColor(comissao.status),
                  labelStyle: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ],
            ),
            onTap: () {
              _mostrarDetalhesComissao(comissao, formatoMoeda, formatoData);
            },
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Paga':
        return Colors.green;
      case 'Pendente':
        return Colors.orange;
      case 'Cancelada':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _mostrarDetalhesComissao(
    ComissaoVendedor comissao,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF10151B),
        title: Text(
          'Comissão - Pedido ${comissao.pedidoNumero}',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Vendedor', comissao.funcionarioNome),
            _buildInfoRow('Pedido', comissao.pedidoNumero),
            _buildInfoRow('Valor do Pedido', formatoMoeda.format(comissao.valorPedido)),
            _buildInfoRow('Percentual', '${comissao.percentualComissao}%'),
            _buildInfoRow('Comissão', formatoMoeda.format(comissao.valorComissao)),
            _buildInfoRow('Status', comissao.status),
            _buildInfoRow('Data', formatoData.format(comissao.createdAt)),
            if (comissao.dataPagamento != null)
              _buildInfoRow('Data Pagamento', formatoData.format(comissao.dataPagamento!)),
          ],
        ),
        actions: [
          if (comissao.status == 'Pendente')
            TextButton(
              onPressed: () {
                _marcarComissaoComoPaga(comissao);
                Navigator.pop(context);
              },
              child: const Text('Marcar como Paga'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  void _marcarComissaoComoPaga(ComissaoVendedor comissao) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final comissaoAtualizada = comissao.copyWith(
      status: 'Paga',
      dataPagamento: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    dataService.updateComissaoVendedor(comissaoAtualizada);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Comissão marcada como paga')),
    );
  }
}

