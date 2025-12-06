import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/funcionario.dart';
import '../models/pedido.dart';
import '../theme.dart';

class ComissoesPage extends StatefulWidget {
  const ComissoesPage({super.key});

  @override
  State<ComissoesPage> createState() => _ComissoesPageState();
}

class _ComissoesPageState extends State<ComissoesPage> {
  DateTime? _dataInicio;
  DateTime? _dataFim;
  Funcionario? _funcionarioFiltro;

  @override
  void dispose() {
    super.dispose();
  }

  List<Pedido> _filtrarPedidos(List<Pedido> pedidos) {
    var resultado = pedidos.where((p) => p.servicos.isNotEmpty).toList();
    
    // Filtro por funcionário
    if (_funcionarioFiltro != null) {
      resultado = resultado.where((p) {
        return p.servicos.any((s) => s.funcionarioId == _funcionarioFiltro!.id);
      }).toList();
    }
    
    // Filtro por data
    if (_dataInicio != null) {
      resultado = resultado.where((p) => p.dataPedido.isAfter(_dataInicio!.subtract(const Duration(days: 1)))).toList();
    }
    if (_dataFim != null) {
      resultado = resultado.where((p) => p.dataPedido.isBefore(_dataFim!.add(const Duration(days: 1)))).toList();
    }
    
    return resultado;
  }

  Map<String, double> _calcularComissoesPorFuncionario(List<Pedido> pedidos) {
    final comissoes = <String, double>{};
    
    for (final pedido in pedidos) {
      for (final servico in pedido.servicos) {
        if (servico.funcionarioId != null && servico.valorComissao > 0) {
          comissoes[servico.funcionarioId!] = 
              (comissoes[servico.funcionarioId] ?? 0.0) + servico.valorComissao;
        }
      }
    }
    
    return comissoes;
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final pedidos = _filtrarPedidos(dataService.pedidos);
    final comissoesPorFuncionario = _calcularComissoesPorFuncionario(pedidos);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final formatoData = DateFormat('dd/MM/yyyy');
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    // Calcular total geral
    final totalGeral = comissoesPorFuncionario.values.fold(0.0, (sum, valor) => sum + valor);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Consulta de Comissões'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            // Filtros
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E).withOpacity(0.8),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Column(
                children: [
                  // Filtro por funcionário
                  DropdownButtonFormField<Funcionario?>(
                    value: _funcionarioFiltro,
                    decoration: InputDecoration(
                      labelText: 'Filtrar por Funcionário',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF181A1B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    dropdownColor: const Color(0xFF23272A),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      const DropdownMenuItem<Funcionario?>(
                        value: null,
                        child: Text('Todos os funcionários', style: TextStyle(color: Colors.white70)),
                      ),
                      ...dataService.funcionarios.where((f) => f.ativo).map((funcionario) {
                        return DropdownMenuItem(
                          value: funcionario,
                          child: Text(funcionario.nome),
                        );
                      }),
                    ],
                    onChanged: (funcionario) {
                      setState(() {
                        _funcionarioFiltro = funcionario;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  // Filtro por data
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final data = await showDatePicker(
                              context: context,
                              initialDate: _dataInicio ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (data != null) {
                              setState(() {
                                _dataInicio = data;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF181A1B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                                const SizedBox(width: 8),
                                Text(
                                  _dataInicio == null
                                      ? 'Data Início'
                                      : formatoData.format(_dataInicio!),
                                  style: TextStyle(
                                    color: _dataInicio == null ? Colors.white54 : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final data = await showDatePicker(
                              context: context,
                              initialDate: _dataFim ?? DateTime.now(),
                              firstDate: _dataInicio ?? DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (data != null) {
                              setState(() {
                                _dataFim = data;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF181A1B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
                                const SizedBox(width: 8),
                                Text(
                                  _dataFim == null
                                      ? 'Data Fim'
                                      : formatoData.format(_dataFim!),
                                  style: TextStyle(
                                    color: _dataFim == null ? Colors.white54 : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Resumo
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                border: Border(
                  bottom: BorderSide(color: Colors.orange.withOpacity(0.3)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total de Comissões:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    formatoMoeda.format(totalGeral),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Lista de comissões
            Expanded(
              child: comissoesPorFuncionario.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.money_off,
                            size: 64,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma comissão encontrada',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: comissoesPorFuncionario.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final funcionarioId = comissoesPorFuncionario.keys.elementAt(index);
                        final totalComissao = comissoesPorFuncionario[funcionarioId]!;
                        final funcionario = dataService.funcionarios.firstWhere(
                          (f) => f.id == funcionarioId,
                          orElse: () => Funcionario(
                            id: funcionarioId,
                            nome: 'Funcionário não encontrado',
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          ),
                        );
                        
                        // Contar serviços deste funcionário
                        final servicosFuncionario = pedidos.expand((p) => p.servicos)
                            .where((s) => s.funcionarioId == funcionarioId && s.valorComissao > 0)
                            .toList();
                        
                        return Card(
                          elevation: theme.cardTheme.elevation ?? 2,
                          shape: theme.cardTheme.shape,
                          color: theme.cardTheme.color,
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.withOpacity(0.2),
                              child: const Icon(Icons.person, color: Colors.orange),
                            ),
                            title: Text(
                              funcionario.nome,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${servicosFuncionario.length} serviço${servicosFuncionario.length != 1 ? 's' : ''}',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Text(
                              formatoMoeda.format(totalComissao),
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Serviços:',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...servicosFuncionario.map((servico) {
                                      final pedido = pedidos.firstWhere(
                                        (p) => p.servicos.contains(servico),
                                      );
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E2E),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    servico.descricao,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    formatoData.format(pedido.dataPedido),
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(0.6),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Text(
                                              formatoMoeda.format(servico.valorComissao),
                                              style: const TextStyle(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                          ),
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

