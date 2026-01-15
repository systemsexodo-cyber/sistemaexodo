import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../services/data_service.dart';
import '../models/conta_pagar.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';

class AgendaContasPage extends StatefulWidget {
  const AgendaContasPage({super.key});

  @override
  State<AgendaContasPage> createState() => _AgendaContasPageState();
}

class _AgendaContasPageState extends State<AgendaContasPage> {
  DateTime _dataInicioSemana = DateTime.now();
  DateFormat? _formatoData;
  DateFormat? _formatoDiaSemana;
  final NumberFormat _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  bool _localeInicializado = false;

  @override
  void initState() {
    super.initState();
    // Ajustar para início da semana (segunda-feira)
    _ajustarParaInicioSemana();
    // Inicializar locale
    _inicializarLocale();
  }

  Future<void> _inicializarLocale() async {
    await initializeDateFormatting('pt_BR', null);
    if (mounted) {
      setState(() {
        _formatoData = DateFormat('dd/MM/yyyy', 'pt_BR');
        _formatoDiaSemana = DateFormat('EEEE', 'pt_BR');
        _localeInicializado = true;
      });
    }
  }

  void _ajustarParaInicioSemana() {
    final hoje = DateTime.now();
    final diasDesdeSegunda = hoje.weekday - 1; // 1 = segunda, 7 = domingo
    _dataInicioSemana = hoje.subtract(Duration(days: diasDesdeSegunda));
    _dataInicioSemana = DateTime(_dataInicioSemana.year, _dataInicioSemana.month, _dataInicioSemana.day);
  }

  List<DateTime> _getDiasDaSemana() {
    final dias = <DateTime>[];
    for (int i = 0; i < 7; i++) {
      dias.add(_dataInicioSemana.add(Duration(days: i)));
    }
    return dias;
  }

  List<ContaPagar> _getContasDoDia(DateTime dia, List<ContaPagar> todasContas) {
    final inicioDia = DateTime(dia.year, dia.month, dia.day);
    final fimDia = DateTime(dia.year, dia.month, dia.day, 23, 59, 59);
    
    return todasContas.where((conta) {
      if (conta.status == StatusContaPagar.pago || 
          conta.status == StatusContaPagar.cancelado) {
        return false;
      }
      
      final dataVencimento = DateTime(
        conta.dataVencimento.year,
        conta.dataVencimento.month,
        conta.dataVencimento.day,
      );
      
      return dataVencimento.isAtSameMomentAs(inicioDia) ||
             (dataVencimento.isAfter(inicioDia) && dataVencimento.isBefore(fimDia));
    }).toList()
      ..sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));
  }

  void _irParaSemanaAnterior() {
    setState(() {
      _dataInicioSemana = _dataInicioSemana.subtract(const Duration(days: 7));
    });
  }

  void _irParaSemanaAtual() {
    setState(() {
      _ajustarParaInicioSemana();
    });
  }

  void _irParaProximaSemana() {
    setState(() {
      _dataInicioSemana = _dataInicioSemana.add(const Duration(days: 7));
    });
  }

  String _getTituloSemana() {
    if (!_localeInicializado || _formatoData == null) {
      final fimSemana = _dataInicioSemana.add(const Duration(days: 6));
      return '${_dataInicioSemana.day}/${_dataInicioSemana.month}/${_dataInicioSemana.year} - ${fimSemana.day}/${fimSemana.month}/${fimSemana.year}';
    }
    final fimSemana = _dataInicioSemana.add(const Duration(days: 6));
    return '${_formatoData!.format(_dataInicioSemana)} - ${_formatoData!.format(fimSemana)}';
  }

  Color _getCorDia(DateTime dia) {
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    final diaSemHora = DateTime(dia.year, dia.month, dia.day);
    
    if (diaSemHora.isAtSameMomentAs(hojeSemHora)) {
      return Colors.blue;
    } else if (diaSemHora.isBefore(hojeSemHora)) {
      return Colors.red;
    } else {
      return Colors.green;
    }
  }

  String _getNomeDia(int weekday) {
    const dias = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
    return dias[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (!_localeInicializado) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Agenda de Contas'),
            backgroundColor: Colors.transparent,
          ),
          body: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final dataService = Provider.of<DataService>(context);
    final todasContas = dataService.contasPagar;
    
    final diasSemana = _getDiasDaSemana();
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Agenda de Contas'),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_today),
              tooltip: 'Semana Atual',
              onPressed: _irParaSemanaAtual,
            ),
          ],
        ),
        body: Column(
          children: [
            // Cabeçalho da semana
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[700]!, Colors.blue[600]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: _irParaSemanaAnterior,
                ),
                Expanded(
                  child: Text(
                    _getTituloSemana(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: _irParaProximaSemana,
                ),
              ],
            ),
          ),
          
          // Lista de dias da semana
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: diasSemana.length,
              itemBuilder: (context, index) {
                final dia = diasSemana[index];
                final contasDoDia = _getContasDoDia(dia, todasContas);
                final diaSemHora = DateTime(dia.year, dia.month, dia.day);
                final isHoje = diaSemHora.isAtSameMomentAs(hojeSemHora);
                final corDia = _getCorDia(dia);
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isHoje ? Colors.blue : Colors.grey.withOpacity(0.3),
                      width: isHoje ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cabeçalho do dia
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: corDia.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: corDia,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                dia.day.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatoDiaSemana?.format(dia) ?? _getNomeDia(dia.weekday),
                                    style: TextStyle(
                                      color: corDia,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    _formatoData?.format(dia) ?? '${dia.day}/${dia.month}/${dia.year}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: corDia,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${contasDoDia.length} ${contasDoDia.length == 1 ? 'conta' : 'contas'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Lista de contas do dia
                      if (contasDoDia.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'Nenhuma conta para este dia',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      else
                        ...contasDoDia.asMap().entries.map((entry) {
                          final index = entry.key;
                          final conta = entry.value;
                          final isVencida = conta.isVencida;
                          final valorPendente = conta.valorPendente;
                          
                          return Container(
                            margin: EdgeInsets.only(
                              bottom: index < contasDoDia.length - 1 ? 12 : 0,
                            ),
                            child: InkWell(
                              onTap: () => _mostrarDialogoPagamento(context, conta),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isVencida 
                                    ? Colors.red.withOpacity(0.1)
                                    : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isVencida 
                                      ? Colors.red.withOpacity(0.5)
                                      : Colors.grey.withOpacity(0.3),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Ícone e número da conta
                                    Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isVencida 
                                              ? Colors.red.withOpacity(0.2)
                                              : Colors.blue.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            isVencida ? Icons.warning : Icons.payment,
                                            color: isVencida ? Colors.red : Colors.blue,
                                            size: 24,
                                          ),
                                        ),
                                        if (conta.numero != null) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              conta.numero!,
                                              style: TextStyle(
                                                color: Colors.grey[700],
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(width: 14),
                                    // Informações da conta
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            conta.descricao,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          if (conta.categoria != null) ...[
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.category,
                                                  size: 14,
                                                  color: Colors.grey[600],
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  conta.categoria!,
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                          ],
                                          if (conta.fornecedorNome != null) ...[
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.business,
                                                  size: 14,
                                                  color: Colors.grey[600],
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    conta.fornecedorNome!,
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                          ],
                                          if (conta.notaEntradaNumero != null) ...[
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.receipt,
                                                  size: 14,
                                                  color: Colors.orange[700],
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Nota: ${conta.notaEntradaNumero}',
                                                  style: TextStyle(
                                                    color: Colors.orange[700],
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                          ],
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today,
                                                size: 14,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Vence: ${_formatoData?.format(conta.dataVencimento) ?? '${conta.dataVencimento.day}/${conta.dataVencimento.month}/${conta.dataVencimento.year}'}',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Valor e status
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatoMoeda.format(valorPendente),
                                          style: TextStyle(
                                            color: isVencida ? Colors.red : Colors.green[700],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                        if (isVencida) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'VENCIDA',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ] else ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'PENDENTE',
                                              style: TextStyle(
                                                color: Colors.blue[700],
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
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

  void _mostrarDialogoPagamento(BuildContext context, ContaPagar conta) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = _formatoData ?? DateFormat('dd/MM/yyyy');
    
    final valorPendente = conta.valorPendente;
    final valorController = TextEditingController(
      text: valorPendente.toStringAsFixed(2).replaceAll('.', ','),
    );
    final observacaoController = TextEditingController();
    DateTime dataPagamento = DateTime.now();
    TipoPagamento? formaPagamento;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.payment, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Registrar Pagamento'),
                    Text(
                      conta.descricao,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card informativo da conta
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.description,
                            color: Colors.blue[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              conta.descricao,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.blue[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (conta.categoria != null) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.category,
                              size: 16,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Categoria: ${conta.categoria}',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (conta.fornecedorNome != null) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.business,
                              size: 16,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Fornecedor: ${conta.fornecedorNome}',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Vencimento: ${formatoData.format(conta.dataVencimento)}',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Valor Total',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                formatoMoeda.format(conta.valor),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.blue[900],
                                ),
                              ),
                            ],
                          ),
                          if (conta.valorPago != null && conta.valorPago! > 0) ...[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Já Pago',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  formatoMoeda.format(conta.valorPago!),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Valor Pendente:',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              formatoMoeda.format(valorPendente),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.green[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Valor a pagar
                TextFormField(
                  controller: valorController,
                  decoration: InputDecoration(
                    labelText: 'Valor a Pagar (pode ser parcial)',
                    prefixText: 'R\$ ',
                    border: const OutlineInputBorder(),
                    helperText: 'Valor pendente: ${formatoMoeda.format(valorPendente)}',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                
                // Data de pagamento
                InkWell(
                  onTap: () async {
                    final data = await showDatePicker(
                      context: context,
                      initialDate: dataPagamento,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (data != null) {
                      setState(() {
                        dataPagamento = data;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data de Pagamento',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(formatoData.format(dataPagamento)),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Forma de pagamento
                DropdownButtonFormField<TipoPagamento>(
                  decoration: const InputDecoration(
                    labelText: 'Forma de Pagamento',
                    border: OutlineInputBorder(),
                  ),
                  value: formaPagamento,
                  items: TipoPagamento.values.map((tipo) {
                    return DropdownMenuItem(
                      value: tipo,
                      child: Text(tipo.nome),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      formaPagamento = value;
                    });
                  },
                  hint: const Text('Selecione a forma de pagamento'),
                ),
                const SizedBox(height: 16),
                
                // Observações
                TextFormField(
                  controller: observacaoController,
                  decoration: const InputDecoration(
                    labelText: 'Observações (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                // Processar valor
                String valorTexto = valorController.text.trim();
                valorTexto = valorTexto.replaceAll(RegExp(r'[^\d,.]'), '');
                
                if (valorTexto.contains(',')) {
                  valorTexto = valorTexto.replaceAll('.', '');
                  valorTexto = valorTexto.replaceAll(',', '.');
                }
                
                if (!valorTexto.contains('.')) {
                  valorTexto = '$valorTexto.00';
                }
                
                final valorPago = double.tryParse(valorTexto);
                
                if (valorPago == null || valorPago <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor, informe um valor válido maior que zero'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                if (valorPago > valorPendente + 0.01) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('O valor não pode ser maior que o pendente (${formatoMoeda.format(valorPendente)})'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                // Calcular novo valor pago
                final novoValorPago = (conta.valorPago ?? 0.0) + valorPago;
                final novoStatus = (novoValorPago >= conta.valor - 0.01)
                  ? StatusContaPagar.pago 
                  : conta.status;
                
                // Criar registro de pagamento
                final novoRegistro = RegistroPagamento(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  valor: valorPago,
                  dataPagamento: dataPagamento,
                  formaPagamento: formaPagamento?.nome,
                  observacao: observacaoController.text.isEmpty ? null : observacaoController.text,
                );
                
                // Adicionar ao histórico
                final novoHistorico = List<RegistroPagamento>.from(conta.historicoPagamentos)
                  ..add(novoRegistro);
                
                // Criar conta atualizada
                final contaAtualizada = ContaPagar(
                  id: conta.id,
                  numero: conta.numero,
                  tipo: conta.tipo,
                  categoria: conta.categoria,
                  descricao: conta.descricao,
                  observacoes: observacaoController.text.isEmpty 
                    ? conta.observacoes 
                    : '${conta.observacoes ?? ''}\n${observacaoController.text}'.trim(),
                  valor: conta.valor,
                  valorPago: novoValorPago,
                  dataVencimento: conta.dataVencimento,
                  dataPagamento: novoStatus == StatusContaPagar.pago ? dataPagamento : conta.dataPagamento,
                  dataCriacao: conta.dataCriacao,
                  updatedAt: DateTime.now(),
                  notaEntradaId: conta.notaEntradaId,
                  notaEntradaNumero: conta.notaEntradaNumero,
                  fornecedorId: conta.fornecedorId,
                  fornecedorNome: conta.fornecedorNome,
                  status: novoStatus,
                  formaPagamento: formaPagamento?.nome ?? conta.formaPagamento,
                  historicoPagamentos: novoHistorico,
                  recorrente: conta.recorrente,
                  intervaloRecorrencia: conta.intervaloRecorrencia,
                  proximaDataRecorrencia: conta.proximaDataRecorrencia,
                  ativo: conta.ativo,
                  usuarioCriacao: conta.usuarioCriacao,
                  usuarioPagamento: conta.usuarioPagamento,
                );
                
                // Salvar
                dataService.updateContaPagar(contaAtualizada);
                
                Navigator.pop(context);
                
                // Atualizar a agenda
                if (mounted) {
                  setState(() {});
                }
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          novoStatus == StatusContaPagar.pago
                            ? '✓ Conta paga com sucesso!'
                            : '✓ Pagamento parcial registrado!',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Conta: ${conta.descricao}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        Text(
                          'Valor pago: ${formatoMoeda.format(valorPago)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 4),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar Pagamento'),
            ),
          ],
        ),
      ),
    );
  }
}

