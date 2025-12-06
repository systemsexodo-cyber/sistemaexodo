import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/nota_entrada.dart';
import '../services/data_service.dart';
import '../custom_app_bar.dart';
import '../theme.dart';
import 'package:intl/intl.dart';

class NotasEntradaPage extends StatelessWidget {
  const NotasEntradaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Notas de Entrada',
        ),
        body: Consumer<DataService>(
          builder: (context, service, _) {
            final notas = service.notasEntrada
              ..sort((a, b) => b.dataHora.compareTo(a.dataHora));

            if (notas.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma nota de entrada registrada',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: notas.length,
              itemBuilder: (context, index) {
                final nota = notas[index];
                return _NotaCard(nota: nota);
              },
            );
          },
        ),
      ),
    );
  }
}

class _NotaCard extends StatelessWidget {
  final NotaEntrada nota;
  final NumberFormat _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  _NotaCard({required this.nota});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context, listen: false);
    final isCancelada = nota.isCancelada;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: isCancelada ? Colors.grey[200] : null,
      child: ExpansionTile(
        leading: Icon(
          isCancelada ? Icons.cancel : Icons.receipt,
          color: isCancelada ? Colors.red : Colors.green,
        ),
        title: Text(
          nota.numeroNota,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: isCancelada ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nota.numeroNotaReal != null && nota.numeroNotaReal!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Text(
                  'NF: ${nota.numeroNotaReal}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ),
            Text(_formatoData.format(nota.dataHora)),
            Text(
              '${nota.itens.length} item(ns) | ${nota.tipo.toUpperCase()}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (isCancelada)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'CANCELADA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        trailing: !isCancelada
            ? IconButton(
                icon: const Icon(Icons.cancel, color: Colors.red),
                tooltip: 'Cancelar Nota',
                onPressed: () => _mostrarDialogoCancelamento(context, service),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Resumo
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumo da Nota',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.blue[900],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow('Data/Hora', _formatoData.format(nota.dataHora)),
                      _buildInfoRow('Tipo', nota.tipo.toUpperCase()),
                      _buildInfoRow('Itens', '${nota.itens.length}'),
                      if (nota.observacao != null)
                        _buildInfoRow('Observação', nota.observacao!),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Itens
                Text(
                  'Itens da Nota',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                ...nota.itens.map((item) => _ItemNotaCard(item: item, formatoMoeda: _formatoMoeda)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoCancelamento(
    BuildContext context,
    DataService service,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir e Reverter Nota de Entrada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja realmente excluir a nota ${nota.numeroNota} e desfazer todas as alterações?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Esta ação irá:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Reverter todas as alterações nos produtos'),
            const Text('• Remover produtos criados nesta nota'),
            const Text('• Restaurar valores anteriores (preço, estoque)'),
            const Text('• Diminuir estoque adicionado pela nota'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta ação não pode ser desfeita!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Excluir e Reverter'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await service.cancelarNotaEntrada(nota.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nota ${nota.numeroNota} excluída e todas as alterações foram revertidas!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao cancelar nota: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

class _ItemNotaCard extends StatelessWidget {
  final ItemNotaEntrada item;
  final NumberFormat formatoMoeda;

  _ItemNotaCard({required this.item, required this.formatoMoeda});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.produtoNome,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (item.produtoNovo)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'NOVO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildInfoRow('Código', item.produtoCodigo),
            _buildInfoRow('Quantidade', '${item.quantidade}'),
            if (item.precoCustoAnterior != item.precoCustoNovo ||
                item.precoVendaAnterior != item.precoVendaNovo ||
                item.estoqueAnterior != item.estoqueNovo) ...[
              const Divider(),
              const Text(
                'Alterações:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              if (item.precoCustoAnterior != item.precoCustoNovo)
                _buildInfoRow(
                  'Custo',
                  '${formatoMoeda.format(item.precoCustoAnterior)} → ${formatoMoeda.format(item.precoCustoNovo)}',
                ),
              if (item.precoVendaAnterior != item.precoVendaNovo)
                _buildInfoRow(
                  'Preço Venda',
                  '${formatoMoeda.format(item.precoVendaAnterior)} → ${formatoMoeda.format(item.precoVendaNovo)}',
                ),
              if (item.estoqueAnterior != item.estoqueNovo)
                _buildInfoRow(
                  'Estoque',
                  '${item.estoqueAnterior} → ${item.estoqueNovo}',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

