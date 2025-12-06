import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../services/data_service.dart';
import '../models/cliente.dart';
import '../models/pedido.dart';
import '../models/item_servico.dart';
import '../theme.dart';

class ClienteServicoDetalhesPage extends StatelessWidget {
  final Cliente cliente;

  const ClienteServicoDetalhesPage({super.key, required this.cliente});

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final pedidosCliente = dataService.pedidos
        .where((p) => p.clienteId == cliente.id && p.servicos.isNotEmpty)
        .toList();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final formatoData = DateFormat('dd/MM/yyyy');
    final formatoDataHora = DateFormat('dd/MM/yyyy HH:mm');

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(cliente.nome),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card com foto e informações principais
              Card(
                elevation: theme.cardTheme.elevation ?? 2,
                shape: theme.cardTheme.shape,
                color: theme.cardTheme.color,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: colorScheme.primary.withOpacity(0.2),
                        backgroundImage: cliente.fotoPath != null && File(cliente.fotoPath!).existsSync()
                            ? FileImage(File(cliente.fotoPath!))
                            : null,
                        child: cliente.fotoPath == null || !File(cliente.fotoPath!).existsSync()
                            ? Icon(
                                Icons.person,
                                size: 50,
                                color: colorScheme.primary,
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        cliente.nome,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (cliente.telefone.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.phone, size: 18, color: Colors.white70),
                            const SizedBox(width: 8),
                            Text(
                              cliente.telefone,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      if (cliente.email != null && cliente.email!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.email, size: 18, color: Colors.white70),
                            const SizedBox(width: 8),
                            Text(
                              cliente.email!,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                            const SizedBox(width: 6),
                            Text(
                              'Cadastrado em ${formatoData.format(cliente.createdAt)}',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Observações
              if (cliente.observacoes != null && cliente.observacoes!.isNotEmpty) ...[
                Card(
                  elevation: theme.cardTheme.elevation ?? 2,
                  shape: theme.cardTheme.shape,
                  color: theme.cardTheme.color,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.note, color: Colors.white70),
                            const SizedBox(width: 8),
                            Text(
                              'Observações',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          cliente.observacoes!,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Dados Extras
              if (cliente.dadosExtras != null && cliente.dadosExtras!.isNotEmpty) ...[
                Card(
                  elevation: theme.cardTheme.elevation ?? 2,
                  shape: theme.cardTheme.shape,
                  color: theme.cardTheme.color,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info, color: Colors.white70),
                            const SizedBox(width: 8),
                            Text(
                              'Dados Extras',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...cliente.dadosExtras!.entries.map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${entry.key}: ${entry.value}',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Histórico de Serviços
              Card(
                elevation: theme.cardTheme.elevation ?? 2,
                shape: theme.cardTheme.shape,
                color: theme.cardTheme.color,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.work, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            'Histórico de Serviços',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${pedidosCliente.length} serviço${pedidosCliente.length != 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (pedidosCliente.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'Nenhum serviço realizado',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      else
                        ...pedidosCliente.map((pedido) {
                          final totalServicos = pedido.servicos.fold(
                            0.0,
                            (sum, item) => sum + item.valor + item.valorAdicional,
                          );
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E2E),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        formatoDataHora.format(pedido.dataPedido),
                                        style: TextStyle(
                                          color: colorScheme.onSurface,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'R\$ ${totalServicos.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...pedido.servicos.map((servico) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              servico.descricao,
                                              style: TextStyle(
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            'R\$ ${(servico.valor + servico.valorAdicional).toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: colorScheme.onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                if (pedido.status.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getCorStatus(pedido.status).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      pedido.status,
                                      style: TextStyle(
                                        color: _getCorStatus(pedido.status),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCorStatus(String status) {
    switch (status) {
      case 'Pendente':
        return Colors.orange;
      case 'Em Andamento':
        return Colors.blue;
      case 'Concluído':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}


