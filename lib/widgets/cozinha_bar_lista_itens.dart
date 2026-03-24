import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/mesa_comanda.dart';
import 'cozinha_bar_card_item.dart';

/// Widget compartilhado para lista de itens da cozinha/bar
class CozinhaBarListaItens extends StatelessWidget {
  final String setor;
  final Function(ItemMesaComanda, MesaComanda)? onMarcarEmPreparo;
  final Function(ItemMesaComanda, MesaComanda)? onMarcarPronto;
  final Function(ItemMesaComanda, MesaComanda)? onDesmarcarPronto;

  const CozinhaBarListaItens({
    super.key,
    required this.setor,
    this.onMarcarEmPreparo,
    this.onMarcarPronto,
    this.onDesmarcarPronto,
  });

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true);
    
    // Buscar todas as mesas/comandas abertas
    final mesasComandasAbertas = dataService.mesasComandas
        .where((m) => m.status == 'Aberta')
        .toList();

    // Coletar todos os itens de todas as mesas
    final todosItens = <Map<String, dynamic>>[];
    
    for (final mesaComanda in mesasComandasAbertas) {
      List<ItemMesaComanda> itensFiltrados;
      
      if (setor == 'Cozinha') {
        itensFiltrados = mesaComanda.itensCozinha;
      } else if (setor == 'Bar') {
        itensFiltrados = mesaComanda.itensBar;
      } else {
        itensFiltrados = mesaComanda.itens;
      }

      for (final item in itensFiltrados) {
        // Incluir itens pendentes, em preparo, prontos ou cancelados
        if (item.status == StatusItem.pendente || 
            item.status == StatusItem.emPreparo || 
            item.status == StatusItem.pronto ||
            item.status == StatusItem.cancelado) {
          todosItens.add({
            'item': item,
            'mesaComanda': mesaComanda,
          });
        }
      }
    }

    // Ordenar por horário de pedido (mais antigo primeiro - FIFO)
    todosItens.sort((a, b) {
      final itemA = a['item'] as ItemMesaComanda;
      final itemB = b['item'] as ItemMesaComanda;
      return itemA.dataHora.compareTo(itemB.dataHora);
    });

    if (todosItens.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              setor == 'Cozinha'
                  ? Icons.restaurant
                  : setor == 'Bar'
                      ? Icons.local_bar
                      : Icons.inventory,
              size: 80,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              setor == 'Todos'
                  ? 'Nenhum item pendente'
                  : 'Nenhum item pendente para $setor',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Força rebuild do widget
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: todosItens.length,
        itemBuilder: (context, index) {
          final item = todosItens[index]['item'] as ItemMesaComanda;
          final mesaComanda = todosItens[index]['mesaComanda'] as MesaComanda;
          return CozinhaBarCardItem(
            item: item,
            mesaComanda: mesaComanda,
            dataService: dataService,
            onMarcarEmPreparo: onMarcarEmPreparo,
            onMarcarPronto: onMarcarPronto,
            onDesmarcarPronto: onDesmarcarPronto,
          );
        },
      ),
    );
  }
}





