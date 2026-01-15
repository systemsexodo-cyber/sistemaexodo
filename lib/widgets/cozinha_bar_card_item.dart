import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/mesa_comanda.dart';
import '../services/data_service.dart';

/// Widget compartilhado para exibir itens da cozinha/bar
class CozinhaBarCardItem extends StatelessWidget {
  final ItemMesaComanda item;
  final MesaComanda mesaComanda;
  final DataService dataService;
  final Function(ItemMesaComanda, MesaComanda)? onMarcarEmPreparo;
  final Function(ItemMesaComanda, MesaComanda)? onMarcarPronto;

  const CozinhaBarCardItem({
    super.key,
    required this.item,
    required this.mesaComanda,
    required this.dataService,
    this.onMarcarEmPreparo,
    this.onMarcarPronto,
  });

  @override
  Widget build(BuildContext context) {
    final tempoDecorrido = DateTime.now().difference(item.dataHora);
    final minutosDecorridos = tempoDecorrido.inMinutes;
    final horasDecorridos = tempoDecorrido.inHours;
    
    String tempoTexto;
    if (horasDecorridos > 0) {
      tempoTexto = '${horasDecorridos}h ${minutosDecorridos % 60}min';
    } else {
      tempoTexto = '${minutosDecorridos}min';
    }

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (item.status) {
      case StatusItem.cancelado:
        statusColor = Colors.red.shade700;
        statusIcon = Icons.cancel;
        statusText = 'CANCELADO';
        break;
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
    }
    
    final isCancelado = item.status == StatusItem.cancelado;
    final isUrgente = minutosDecorridos > 30;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isCancelado
          ? Colors.red.shade900.withOpacity(0.3)
          : isUrgente 
              ? const Color(0xFF2E1E1E).withOpacity(0.8)
              : const Color(0xFF1E1E2E),
      elevation: (isUrgente || isCancelado) ? 4 : 1,
      shape: isCancelado
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red.shade700, width: 2),
            )
          : isUrgente
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.red, width: 2),
                )
              : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Mesa/Comanda e Status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    mesaComanda.numero,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (mesaComanda.clienteNome != null)
                  Expanded(
                    child: Text(
                      mesaComanda.clienteNome!,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            // Informações do item
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nome,
                        style: TextStyle(
                          color: isCancelado ? Colors.red.shade300 : Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          decoration: isCancelado ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Qtd: ${item.quantidade} x ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.preco)}',
                        style: TextStyle(
                          color: isCancelado ? Colors.red.shade300 : Colors.grey,
                          fontSize: 14,
                          decoration: isCancelado ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (item.observacao != null && item.observacao!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.withOpacity(0.5)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.note,
                                size: 16,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.observacao!,
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: minutosDecorridos > 30
                              ? Colors.red
                              : minutosDecorridos > 15
                                  ? Colors.orange
                                  : Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          tempoTexto,
                          style: TextStyle(
                            color: minutosDecorridos > 30
                                ? Colors.red
                                : minutosDecorridos > 15
                                    ? Colors.orange
                                    : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('HH:mm').format(item.dataHora),
                      style: TextStyle(
                        color: isUrgente ? Colors.red.shade300 : Colors.grey,
                        fontSize: 11,
                        fontWeight: isUrgente ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Botões de ação (não mostrar para itens cancelados)
            if (!isCancelado) ...[
              Row(
                children: [
                  if (item.status == StatusItem.pendente && onMarcarEmPreparo != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => onMarcarEmPreparo!(item, mesaComanda),
                        icon: const Icon(Icons.restaurant_menu, size: 18),
                        label: const Text('Iniciar Preparo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (item.status == StatusItem.emPreparo && onMarcarPronto != null) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => onMarcarPronto!(item, mesaComanda),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Marcar Pronto'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                  if (item.status == StatusItem.pronto)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Aguardando Entrega',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}





