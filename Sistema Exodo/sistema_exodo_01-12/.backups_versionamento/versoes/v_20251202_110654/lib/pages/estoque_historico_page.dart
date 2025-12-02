import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/produto.dart';

class EstoqueHistoricoPage extends StatelessWidget {
  final Produto produto;
  const EstoqueHistoricoPage({super.key, required this.produto});

  @override
  Widget build(BuildContext context) {
    final historicoCompleto =
        Provider.of<DataService>(
            context,
            listen: false,
          ).estoqueHistorico.where((h) => h.produtoId == produto.id).toList()
          ..sort((a, b) => b.data.compareTo(a.data));
    // Soma das saídas com número de venda
    final totalVendido = historicoCompleto
        .where(
          (h) =>
              h.tipo == 'saida' &&
              h.observacao != null &&
              RegExp(r'VND-\d+').hasMatch(h.observacao!),
        )
        .fold<int>(0, (sum, h) => sum + h.quantidade);
    // ...continuação do método...
    final tipos = ['todos', 'entrada', 'saida', 'ajuste'];
    ValueNotifier<String> tipoSelecionado = ValueNotifier<String>('todos');
    ValueNotifier<DateTime?> dataInicial = ValueNotifier<DateTime?>(null);
    ValueNotifier<DateTime?> dataFinal = ValueNotifier<DateTime?>(null);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Movimentação de Estoque'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.shopping_cart, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    'Total vendido: ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$totalVendido',
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: tipoSelecionado,
                    builder: (context, value, _) {
                      return DropdownButton<String>(
                        value: value,
                        dropdownColor: Colors.blue.shade900,
                        style: const TextStyle(color: Colors.white),
                        items: tipos
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  t[0].toUpperCase() + t.substring(1),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) tipoSelecionado.value = val;
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  ValueListenableBuilder<DateTime?>(
                    valueListenable: dataInicial,
                    builder: (context, value, _) {
                      return InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: value ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) dataInicial.value = picked;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade800,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.date_range,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                value == null
                                    ? 'Data inicial'
                                    : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<DateTime?>(
                    valueListenable: dataFinal,
                    builder: (context, value, _) {
                      return InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: value ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) dataFinal.value = picked;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade800,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.date_range,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                value == null
                                    ? 'Data final'
                                    : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: tipoSelecionado,
                builder: (context, tipo, _) {
                  return ValueListenableBuilder<DateTime?>(
                    valueListenable: dataInicial,
                    builder: (context, ini, _) {
                      return ValueListenableBuilder<DateTime?>(
                        valueListenable: dataFinal,
                        builder: (context, fim, _) {
                          var historico = historicoCompleto;
                          if (tipo != 'todos') {
                            historico = historico
                                .where((h) => h.tipo == tipo)
                                .toList();
                          }
                          if (ini != null) {
                            historico = historico
                                .where(
                                  (h) => h.data.isAfter(
                                    ini.subtract(const Duration(days: 1)),
                                  ),
                                )
                                .toList();
                          }
                          if (fim != null) {
                            historico = historico
                                .where(
                                  (h) => h.data.isBefore(
                                    fim.add(const Duration(days: 1)),
                                  ),
                                )
                                .toList();
                          }
                          if (historico.isEmpty) {
                            return const Center(
                              child: Text(
                                'Nenhuma movimentação encontrada',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: historico.length,
                            itemBuilder: (context, i) {
                              final h = historico[i];
                              String? numeroVenda;
                              if (h.tipo == 'saida' && h.observacao != null) {
                                final match = RegExp(
                                  r'VND-\d+',
                                ).firstMatch(h.observacao!);
                                if (match != null) {
                                  numeroVenda = match.group(0);
                                }
                              }
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: h.tipo == 'entrada'
                                      ? Colors.green.shade900.withOpacity(0.25)
                                      : h.tipo == 'saida'
                                      ? Colors.red.shade900.withOpacity(0.25)
                                      : Colors.orange.shade900.withOpacity(
                                          0.25,
                                        ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: h.tipo == 'entrada'
                                        ? Colors.green.shade400
                                        : h.tipo == 'saida'
                                        ? Colors.red.shade400
                                        : Colors.orange.shade400,
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.12),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  leading: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: h.tipo == 'entrada'
                                            ? [
                                                Colors.green.shade400,
                                                Colors.green.shade700,
                                              ]
                                            : h.tipo == 'saida'
                                            ? [
                                                Colors.red.shade400,
                                                Colors.red.shade700,
                                              ]
                                            : [
                                                Colors.orange.shade400,
                                                Colors.orange.shade700,
                                              ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      h.tipo == 'entrada'
                                          ? Icons.arrow_downward
                                          : h.tipo == 'saida'
                                          ? Icons.arrow_upward
                                          : Icons.sync,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  title: Text(
                                    '${h.tipo[0].toUpperCase()}${h.tipo.substring(1)} de estoque',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 17,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.calendar_today,
                                              size: 14,
                                              color: Colors.white70,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              ' ${h.data.day.toString().padLeft(2, '0')}/${h.data.month.toString().padLeft(2, '0')}/${h.data.year} ${h.data.hour.toString().padLeft(2, '0')}:${h.data.minute.toString().padLeft(2, '0')}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.numbers,
                                              size: 14,
                                              color: Colors.white70,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              ' Quantidade: ${h.quantidade}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (h.observacao != null &&
                                            h.observacao!.isNotEmpty)
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.info_outline,
                                                size: 14,
                                                color: Colors.white54,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  'Obs: ${h.observacao}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white54,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        if (h.usuario != null &&
                                            h.usuario!.isNotEmpty)
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.person,
                                                size: 14,
                                                color: Colors.white54,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Usuário: ${h.usuario}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        if (h.tipo == 'saida' &&
                                            numeroVenda != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.receipt_long,
                                                  size: 18,
                                                  color: Colors.blueAccent,
                                                ),
                                                const SizedBox(width: 6),
                                                Chip(
                                                  label: Text(
                                                    numeroVenda,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      letterSpacing: 1.2,
                                                    ),
                                                  ),
                                                  backgroundColor:
                                                      Colors.blueAccent,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 2,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
