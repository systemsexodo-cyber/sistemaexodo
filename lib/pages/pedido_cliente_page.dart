import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'package:sistema_exodo_novo/models/link_vendedor.dart';
import "package:sistema_exodo_novo/models/forma_pagamento.dart";
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:intl/intl.dart';

/// Página para cliente acompanhar seu pedido via link único
/// Acessada através de /pedido/cliente/:linkCliente
class PedidoClientePage extends StatefulWidget {
  final String linkCliente;

  const PedidoClientePage({
    required this.linkCliente,
    super.key,
  });

  @override
  State<PedidoClientePage> createState() => _PedidoClientePageState();
}

class _PedidoClientePageState extends State<PedidoClientePage> {
  Pedido? _pedido;
  bool _carregando = true;
  String _erro = '';
  bool _mostrarHistorico = false;


  Timer? _timerAtualizacao;

  @override
  void initState() {
    super.initState();
    _carregarPedido();
    _timerAtualizacao = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _carregando || _pedido == null) return;
      final status = _pedido!.status.toLowerCase();
      if (status == 'entregue' || status == 'cancelado') return;
      _carregarPedido(silencioso: true);
    });
  }

  @override
  void dispose() {
    _timerAtualizacao?.cancel();
    super.dispose();
  }

  Future<void> _carregarPedido({bool silencioso = false}) async {
    final codigo = widget.linkCliente.trim();
    if (codigo.isEmpty) {
      setState(() {
        _carregando = false;
        _erro = 'Link invalido';
      });
      return;
    }

    if (!silencioso) {
      setState(() {
        _carregando = true;
        _erro = '';
      });
    }

    try {
      final dataService = DataService();
      Pedido? encontrado;
      for (final p in dataService.pedidos) {
        if (p.linkCliente == codigo || p.numero == codigo || p.id == codigo) {
          encontrado = p;
          break;
        }
      }

      if (encontrado == null) {
        final dados =
            await SupabaseService.instance.buscarPedidoPublicoPorCodigo(codigo);
        if (dados != null) {
          encontrado = Pedido.fromMap(dados);
        }
      }

      if (!mounted) return;
      setState(() {
        _pedido = encontrado;
        _carregando = false;
        _erro = encontrado == null
            ? 'Pedido nao encontrado para este link.'
            : '';
      });
    } catch (e) {
      debugPrint('>>> [PedidoClientePage] Erro ao carregar pedido: $e');
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Erro ao carregar pedido: $e';
      });
    }
  }

  Color _getStatusColor(String status) {
    final lower = status.toLowerCase();
    switch (lower) {
      case 'concluído':
      case 'pago':
        return Colors.greenAccent!;
      case 'em preparo':
      case 'preparando':
        return Colors.orange[300]!;
      case 'em andamento':
        return Colors.blue[300]!;
      case 'parcialmente pago':
        return Colors.amber[300]!;
      case 'pronto':
        return Colors.amber[300]!;
      case 'saiu para entrega':
      case 'em trânsito':
      case 'em entrega':
      case 'em_entrega':
      case 'em rota':
        return Colors.purple[300]!;
      case 'entregue':
        return Colors.blue[300]!;
      case 'cancelado':
        return Colors.red[300]!;
      case 'pendente':
        return Colors.amber[300]!;
      default:
        return Colors.grey.shade300;
    }
  }

  IconData _getStatusIcon(String status) {
    final lower = status.toLowerCase();
    switch (lower) {
      case 'concluído':
      case 'pago':
        return Icons.check_circle;
      case 'em preparo':
      case 'preparando':
        return Icons.schedule;
      case 'em andamento':
        return Icons.schedule;
      case 'parcialmente pago':
        return Icons.payments;
      case 'pronto':
        return Icons.done;
      case 'saiu para entrega':
      case 'em trânsito':
      case 'em entrega':
      case 'em_entrega':
      case 'em rota':
        return Icons.local_shipping;
      case 'entregue':
        return Icons.check_circle;
      case 'cancelado':
        return Icons.cancel;
      case 'pendente':
        return Icons.hourglass_empty;
      default:
        return Icons.help_outline;
    }
  }

  String _getStatusText(String status) {
    final lower = status.toLowerCase();
    switch (lower) {
      case 'concluído':
      case 'pago':
        return 'Concluído';
      case 'em preparo':
      case 'preparando':
        return 'Em Preparo';
      case 'em andamento':
        return 'Em Andamento';
      case 'parcialmente pago':
        return 'Parcialmente Pago';
      case 'pronto':
        return 'Pronto';
      case 'saiu para entrega':
      case 'em trânsito':
      case 'em entrega':
      case 'em_entrega':
      case 'em rota':
        return 'Saiu para Entrega';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      case 'pendente':
        return 'Pendente';
      default:
        return status;
    }
  }

  String _getTempoDecorrido(DateTime dataPedido) {
    final agora = DateTime.now();
    final diferenca = agora.difference(dataPedido);

    if (diferenca.inDays > 0) {
      return '${diferenca.inDays} dia${diferenca.inDays > 1 ? 's' : ''} atrás';
    } else if (diferenca.inHours > 0) {
      return '${diferenca.inHours} hora${diferenca.inHours > 1 ? 's' : ''} atrás';
    } else if (diferenca.inMinutes > 0) {
      return '${diferenca.inMinutes} minuto${diferenca.inMinutes > 1 ? 's' : ''} atrás';
    } else {
      return 'Agora';
    }
  }

  String _formatarStatusComTempo(String status, DateTime dataPedido) {
    final tempo = _getTempoDecorrido(dataPedido);
    final statusText = _getStatusText(status);
    return '$statusText ($tempo)';
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_pedido == null || _pedido!.id.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pedido não encontrado'),
          backgroundColor: Colors.red,
        ),
        body: Center(
          child: Text('Não foi possível encontrar o pedido com este link.'),
        ),
      );
    }

    final pedido = _pedido!;
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${pedido.numero}'),
        backgroundColor: _getStatusColor(pedido.status),
        foregroundColor: Colors.white,
        actions: [
          if (pedido.status != 'Concluído' && pedido.status != 'Cancelado')
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar status',
              onPressed: _carregarPedido,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status principal com tempo decorrido
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStatusColor(pedido.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getStatusColor(pedido.status),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getStatusIcon(pedido.status),
                    color: _getStatusColor(pedido.status),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatarStatusComTempo(pedido.status, pedido.dataPedido),
                    style: TextStyle(
                      color: _getStatusColor(pedido.status),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Informações do pedido
            _buildInfoRow(
              icon: Icons.receipt,
              label: 'Número do Pedido',
              value: pedido.numero,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.person,
              label: 'Cliente',
              value: pedido.clienteNome ?? 'Convidado',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.phone,
              label: 'Telefone',
              value: pedido.clienteTelefone ?? 'Não informado',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.location_on,
              label: 'Forma de Entrega',
              value: (pedido.origem ?? 'E-commerce')
                  .replaceFirst('E-commerce - ', ''),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.money,
              label: 'Total',
              value: moeda.format(pedido.totalGeral),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.calendar_today,
              label: 'Data do Pedido',
              value: DateFormat('dd/MM/yyyy - HH:mm').format(pedido.dataPedido),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              icon: Icons.receipt,
              label: 'Forma de Pagamento',
              value: pedido.pagamentos.isNotEmpty
                  ? pedido.pagamentos.first.tipo.nome
                  : 'Não informado',
            ),
            const SizedBox(height: 24),

            // Itens do pedido
            if (pedido.produtos.isNotEmpty || pedido.servicos.isNotEmpty) ...[
              const Text(
                'Itens do Pedido',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...pedido.produtos.map(
                (item) => _buildItemRow(
                  icon: Icons.shopping_bag,
                  title: item.nome,
                  quantity: '${item.quantidade.toStringAsFixed(item.quantidade % 1 == 0 ? 0 : 1)}x',
                  price: moeda.format(item.preco * item.quantidade),
                ),
              ),
              ...pedido.servicos.map(
                (item) => _buildItemRow(
                  icon: Icons.shopping_bag,
                  title: item.descricao,
                  quantity: '1x',
                  price: moeda.format(item.valor + item.valorAdicional),
                ),
              ),
              const Divider(height: 24, color: Colors.grey),
            ],

            // Histórico de status (se tiver pagamentos)
            if (pedido.pagamentos.isNotEmpty || _mostrarHistorico) ...[
              const Text(
                'Histórico',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...pedido.pagamentos.map(
                (pag) => _buildPagamentoRow(pag),
              ),
            ],
            const SizedBox(height: 32),

            // Ações
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _enviarNoWhatsApp(pedido),
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                label: const Text('Compartilhar no WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyan[300], size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildItemRow({
    required IconData icon,
    required String title,
    required String quantity,
    required String price,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyan[300], size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white))),
          Text(
            quantity,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            price,
            style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPagamentoRow(PagamentoPedido pag) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            Icons.payment,
            color: pag.recebido ? Colors.greenAccent : Colors.amber[300],
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${pag.tipo.nome} - ${DateFormat('dd/MM').format(pag.dataVencimento ?? DateTime.now())}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Text(
            pag.recebido ? 'Recebido' : 'Pendente',
            style: TextStyle(
              color: pag.recebido ? Colors.greenAccent : Colors.amber[300],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarNoWhatsApp(Pedido pedido) async {
    final telefone = _telefoneLoja();
    if (telefone == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp da loja não configurado.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final linhas = <String>[
      'Olá! Quero conferir o status do meu pedido.',
      'Pedido: ${pedido.numero}',
      'Link de rastreamento: ${pedido.linkCliente}',
      '',
      'Itens:',
      ...pedido.produtos.map(
        (item) => '- ${item.quantidade}x ${item.nome}',
      ),
      if (pedido.servicos.isNotEmpty)
        ...pedido.servicos.map((item) => '- ${item.descricao}'),
      '',
      'Total: ${moeda.format(pedido.totalGeral)}',
    ];

    final uri = Uri.parse(
      'https://wa.me/$telefone?text=${Uri.encodeComponent(linhas.join('\n'))}',
    );
    try {
      final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abriu && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir o WhatsApp.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível abrir o WhatsApp: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  String? _telefoneLoja() {
    final authService = AuthService();
    final empresa = authService.empresaAtual;
    if (empresa != null && empresa.telefone?.isNotEmpty == true) {
      return empresa.telefone!.replaceAll(RegExp(r'[^\\d]'), '');
    }
    // Fallback: tentar do dataService
    return null;
  }
}

/// Widget que envolve a página com o link cliente
Widget pedidoClientePageBuilder(String linkCliente) {
  return PedidoClientePage(linkCliente: linkCliente);
}