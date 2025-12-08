import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/forma_pagamento.dart';

/// Widget para seleção e exibição de formas de pagamento
class PagamentoWidget extends StatefulWidget {
  final double totalPedido;
  final List<PagamentoPedido> pagamentos;
  final Function(List<PagamentoPedido>) onPagamentosChanged;
  final String?
  clienteId; // ID do cliente selecionado (para validação de crediário/fiado)

  const PagamentoWidget({
    super.key,
    required this.totalPedido,
    required this.pagamentos,
    required this.onPagamentosChanged,
    this.clienteId,
  });

  @override
  State<PagamentoWidget> createState() => _PagamentoWidgetState();
}

class _PagamentoWidgetState extends State<PagamentoWidget> {
  final _formatoData = DateFormat('dd/MM/yyyy');
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  double get _totalLancado =>
      widget.pagamentos.fold(0.0, (sum, p) => sum + p.valor);

  double get _valorRestante => widget.totalPedido - _totalLancado;

  bool get _pagamentoCompleto => _valorRestante <= 0.01;

  void _adicionarPagamento(TipoPagamento tipo) {
    // Validação: Crediário e Fiado requerem cliente selecionado
    if ((tipo == TipoPagamento.crediario || tipo == TipoPagamento.fiado) &&
        (widget.clienteId == null || widget.clienteId!.isEmpty)) {
      _mostrarErroSemCliente(tipo);
      return;
    }

    final valorSugerido = _valorRestante > 0 ? _valorRestante : 0.0;
    _mostrarDialogPagamento(tipo, valorSugerido);
  }

  // Mostra mensagem de erro quando tenta usar crediário/fiado sem cliente
  void _mostrarErroSemCliente(TipoPagamento tipo) {
    final tipoNome = tipo == TipoPagamento.crediario ? 'Crediário' : 'Fiado';
    final corTipo = tipo == TipoPagamento.crediario ? Colors.pink : Colors.red;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: corTipo.withOpacity(0.5), width: 2),
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ícone de erro grande e animado
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: corTipo.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: corTipo.withOpacity(0.4), width: 3),
                ),
                child: Icon(Icons.person_off, color: corTipo, size: 60),
              ),
              const SizedBox(height: 24),

              // Título do erro
              Text(
                'CLIENTE OBRIGATÓRIO',
                style: TextStyle(
                  color: corTipo,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Mensagem explicativa
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          tipo == TipoPagamento.crediario
                              ? Icons.calendar_month
                              : Icons.handshake,
                          color: corTipo,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Para lançar venda em $tipoNome, é necessário selecionar um cliente.',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Selecione um cliente antes de escolher esta forma de pagamento.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text(
                'ENTENDI',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: corTipo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogPagamento(
    TipoPagamento tipo,
    double valorSugerido, {
    PagamentoPedido? pagamentoExistente,
  }) {
    // Se não há pagamento existente e o valor sugerido é maior que 0, usar o valor sugerido
    // Caso contrário, usar o valor do pagamento existente ou 0
    final valorInicial = pagamentoExistente != null
        ? pagamentoExistente.valor
        : (valorSugerido > 0 ? valorSugerido : 0.0);
    
    final valorController = TextEditingController(
      text: valorInicial.toStringAsFixed(2),
    );
    final valorRecebidoController = TextEditingController();
    final observacaoController = TextEditingController(
      text: pagamentoExistente?.observacao ?? '',
    );

    int parcelas = 1;
    bool parcelar = false;
    DateTime primeiroVencimento = DateTime.now().add(const Duration(days: 30));
    int intervaloVencimento = 30; // dias entre parcelas
    bool isDinheiro = tipo == TipoPagamento.dinheiro;
    bool isFiado = tipo == TipoPagamento.fiado;
    DateTime dataVencimentoFiado = DateTime.now().add(
      const Duration(days: 7),
    ); // Padrão: 7 dias
    double troco = 0.0;

    // Tipos que suportam parcelamento (cartão de crédito é só à vista)
    final suportaParcelamento = [
      TipoPagamento.boleto,
      TipoPagamento.crediario,
    ].contains(tipo);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Função para calcular troco
          void calcularTroco() {
            final valorPagar =
                double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0.0;
            final valorRecebido =
                double.tryParse(
                  valorRecebidoController.text.replaceAll(',', '.'),
                ) ??
                0.0;
            setDialogState(() {
              // Troco = valor recebido - valor a pagar
              // Se valor recebido for maior que valor a pagar, há troco
              troco = valorRecebido > valorPagar ? valorRecebido - valorPagar : 0.0;
            });
          }

          // Calcular valor da parcela
          double valorTotal =
              double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0;
          double valorParcela = parcelas > 0
              ? valorTotal / parcelas
              : valorTotal;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getCorTipo(tipo).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getIconeTipo(tipo),
                    color: _getCorTipo(tipo),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tipo.nome,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Valor total
                  const Text(
                    'Valor Total',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: valorController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      if (isDinheiro) calcularTroco();
                      setDialogState(() {});
                    },
                    decoration: InputDecoration(
                      prefixText: 'R\$ ',
                      prefixStyle: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 20,
                      ),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  // CALCULADORA DE TROCO - Apenas para Dinheiro
                  if (isDinheiro) ...[
                    const SizedBox(height: 20),
                    _buildCalculadoraTroco(
                      valorController,
                      valorRecebidoController,
                      troco,
                      calcularTroco,
                    ),
                  ],

                  // PARCELAMENTO - Para tipos que suportam
                  if (suportaParcelamento) ...[
                    const SizedBox(height: 20),
                    _buildSecaoParcelamento(
                      parcelar: parcelar,
                      parcelas: parcelas,
                      valorParcela: valorParcela,
                      primeiroVencimento: primeiroVencimento,
                      intervaloVencimento: intervaloVencimento,
                      onParcelarChanged: (value) {
                        setDialogState(() {
                          parcelar = value;
                          if (!parcelar) parcelas = 1;
                        });
                      },
                      onParcelasChanged: (value) {
                        setDialogState(() => parcelas = value);
                      },
                      onPrimeiroVencimentoChanged: (value) {
                        setDialogState(() => primeiroVencimento = value);
                      },
                      onIntervaloChanged: (value) {
                        setDialogState(() => intervaloVencimento = value);
                      },
                    ),
                  ],

                  // FIADO - Data de vencimento
                  if (isFiado) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.event, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Data de Pagamento',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () async {
                              final data = await showDatePicker(
                                context: context,
                                initialDate: dataVencimentoFiado,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.red,
                                        surface: Color(0xFF1E1E2E),
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (data != null) {
                                setDialogState(
                                  () => dataVencimentoFiado = data,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _formatoData.format(dataVencimentoFiado),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.edit,
                                    color: Colors.white38,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'O cliente deverá pagar até esta data',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Observação
                  const SizedBox(height: 16),
                  const Text(
                    'Observação (opcional)',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: observacaoController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: isDinheiro
                          ? 'Ex: Troco conferido...'
                          : parcelar
                          ? 'Ex: Parcelado com cliente...'
                          : 'Ex: Bandeira Visa, NSU 123456...',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  // Info do valor faltando (para pagamentos parciais)
                  if (!isDinheiro && !parcelar && _valorRestante > 0.01) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Faltando para completar: ${_formatoMoeda.format(_valorRestante)}',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final valor =
                      double.tryParse(
                        valorController.text.replaceAll(',', '.'),
                      ) ??
                      0;

                  if (valor <= 0) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Informe um valor válido'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  // Para formas de pagamento diferentes de Dinheiro,
                  // não permitir valor maior que o restante (não há troco)
                  if (!isDinheiro && valor > _valorRestante + 0.01) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Para ${tipo.nome}, o valor não pode ser maior que R\$ ${_valorRestante.toStringAsFixed(2)}',
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  final String? obs = observacaoController.text.isNotEmpty
                      ? observacaoController.text
                      : null;

                  double? valorRecebidoFinal;
                  double? trocoFinal;
                  if (isDinheiro && troco > 0) {
                    valorRecebidoFinal = double.tryParse(
                      valorRecebidoController.text.replaceAll(',', '.'),
                    );
                    trocoFinal = troco;
                  }

                  final novaLista = List<PagamentoPedido>.from(
                    widget.pagamentos,
                  );

                  // Se tiver parcelamento, criar múltiplas parcelas
                  if (parcelar && parcelas > 1) {
                    final parcelamentoId = DateTime.now().millisecondsSinceEpoch
                        .toString();
                    final valorCadaParcela = valor / parcelas;

                    for (int i = 0; i < parcelas; i++) {
                      final dataVenc = primeiroVencimento.add(
                        Duration(days: intervaloVencimento * i),
                      );

                      final parcela = PagamentoPedido(
                        id: '${parcelamentoId}_$i',
                        tipo: tipo,
                        valor: valorCadaParcela,
                        parcelas: parcelas,
                        numeroParcela: i + 1,
                        parcelamentoId: parcelamentoId,
                        dataVencimento: dataVenc,
                        observacao: i == 0 ? obs : null,
                      );
                      novaLista.add(parcela);
                    }
                  } else {
                    // Pagamento único (sem parcelamento)
                    final novoPagamento = PagamentoPedido(
                      id:
                          pagamentoExistente?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      tipo: tipo,
                      valor: valor,
                      observacao: obs,
                      valorRecebido: valorRecebidoFinal,
                      troco: trocoFinal,
                      // Se for fiado, usar a data de vencimento selecionada
                      dataVencimento: isFiado ? dataVencimentoFiado : null,
                    );

                    if (pagamentoExistente != null) {
                      final index = novaLista.indexWhere(
                        (p) => p.id == pagamentoExistente.id,
                      );
                      if (index != -1) {
                        novaLista[index] = novoPagamento;
                      }
                    } else {
                      novaLista.add(novoPagamento);
                    }
                  }

                  widget.onPagamentosChanged(novaLista);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getCorTipo(tipo),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  parcelar && parcelas > 1
                      ? 'Criar $parcelas Parcelas'
                      : (pagamentoExistente != null
                            ? 'Atualizar'
                            : 'Adicionar'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCalculadoraTroco(
    TextEditingController valorController,
    TextEditingController valorRecebidoController,
    double troco,
    VoidCallback calcularTroco,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade800, Colors.green.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calculate, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'CALCULADORA DE TROCO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Cliente entregou:',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: valorRecebidoController,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => calcularTroco(),
            decoration: InputDecoration(
              prefixText: 'R\$ ',
              prefixStyle: const TextStyle(color: Colors.white70, fontSize: 24),
              hintText: '0,00',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: Colors.black.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Valores rápidos:',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [10, 20, 50, 100, 200].map((valor) {
              return InkWell(
                onTap: () {
                  valorRecebidoController.text = valor.toStringAsFixed(2);
                  calcularTroco();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Text(
                    'R\$ $valor',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Calcula valor faltando
          Builder(
            builder: (context) {
              final valorPagar =
                  double.tryParse(valorController.text.replaceAll(',', '.')) ??
                  0.0;
              final valorRecebido =
                  double.tryParse(
                    valorRecebidoController.text.replaceAll(',', '.'),
                  ) ??
                  0.0;
              final faltando = valorPagar > valorRecebido ? valorPagar - valorRecebido : 0.0;

              if (troco > 0) {
                // Mostra troco
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'TROCO',
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'R\$ ${troco.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 32,
                        ),
                      ),
                    ],
                  ),
                );
              } else if (faltando > 0.01 && valorRecebido > 0) {
                // Mostra faltando (apenas se já digitou algo)
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'FALTANDO',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'R\$ ${faltando.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 32,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pagamento parcial - pedido ficará em aberto',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                );
              } else {
                // Estado neutro
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'TROCO',
                        style: TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'R\$ 0,00',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 32,
                        ),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoParcelamento({
    required bool parcelar,
    required int parcelas,
    required double valorParcela,
    required DateTime primeiroVencimento,
    required int intervaloVencimento,
    required Function(bool) onParcelarChanged,
    required Function(int) onParcelasChanged,
    required Function(DateTime) onPrimeiroVencimentoChanged,
    required Function(int) onIntervaloChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade800, Colors.purple.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox para parcelar
          Row(
            children: [
              const Icon(Icons.calendar_month, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'PARCELAMENTO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Switch(
                value: parcelar,
                onChanged: onParcelarChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: Colors.greenAccent,
              ),
            ],
          ),

          if (parcelar) ...[
            const SizedBox(height: 16),

            // Número de parcelas
            const Text(
              'Número de Parcelas',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.redAccent),
                    onPressed: () {
                      if (parcelas > 2) onParcelasChanged(parcelas - 1);
                    },
                  ),
                  Expanded(
                    child: Text(
                      '${parcelas}x',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.greenAccent),
                    onPressed: () {
                      if (parcelas < 24) onParcelasChanged(parcelas + 1);
                    },
                  ),
                ],
              ),
            ),

            // Valor da parcela
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Valor de cada parcela: ',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    _formatoMoeda.format(valorParcela),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Primeiro vencimento
            const Text(
              'Primeiro Vencimento',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final data = await showDatePicker(
                  context: context,
                  initialDate: primeiroVencimento,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  builder: (context, child) {
                    return Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: Colors.purple,
                          surface: Color(0xFF1E1E2E),
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (data != null) {
                  onPrimeiroVencimentoChanged(data);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatoData.format(primeiroVencimento),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.edit, color: Colors.white54, size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Intervalo entre parcelas
            const Text(
              'Intervalo entre Parcelas',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [15, 30, 45, 60].map((dias) {
                final isSelected = intervaloVencimento == dias;
                return InkWell(
                  onTap: () => onIntervaloChanged(dias),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white
                          : Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$dias dias',
                      style: TextStyle(
                        color: isSelected ? Colors.purple : Colors.white70,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            // Preview das parcelas
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Preview das Parcelas:',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(parcelas > 6 ? 6 : parcelas, (i) {
                    final dataVenc = primeiroVencimento.add(
                      Duration(days: intervaloVencimento * i),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text(
                            '${i + 1}ª',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatoData.format(dataVenc),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatoMoeda.format(valorParcela),
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (parcelas > 6)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '... e mais parcelas',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
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
    );
  }

  void _removerPagamento(PagamentoPedido pagamento) {
    List<PagamentoPedido> novaLista;

    // Se for uma parcela, perguntar se quer remover todas
    if (pagamento.isParcela && pagamento.parcelamentoId != null) {
      _confirmarRemocaoParcelamento(pagamento);
      return;
    }

    novaLista = widget.pagamentos.where((p) => p.id != pagamento.id).toList();
    widget.onPagamentosChanged(novaLista);
  }

  void _confirmarRemocaoParcelamento(PagamentoPedido pagamento) {
    final parcelasDoGrupo = widget.pagamentos
        .where((p) => p.parcelamentoId == pagamento.parcelamentoId)
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Remover Parcelamento', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Este pagamento faz parte de um parcelamento de ${parcelasDoGrupo.length}x.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text(
              'O que deseja fazer?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // Remover apenas esta parcela
              final novaLista = widget.pagamentos
                  .where((p) => p.id != pagamento.id)
                  .toList();
              widget.onPagamentosChanged(novaLista);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Só Esta'),
          ),
          ElevatedButton(
            onPressed: () {
              // Remover todas as parcelas do grupo
              final novaLista = widget.pagamentos
                  .where((p) => p.parcelamentoId != pagamento.parcelamentoId)
                  .toList();
              widget.onPagamentosChanged(novaLista);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Todas'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCabecalho(),
        const SizedBox(height: 12),
        _buildBotoesPagamento(),
        if (widget.pagamentos.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildListaPagamentos(),
        ],
        const SizedBox(height: 12),
        _buildResumo(),
      ],
    );
  }

  Widget _buildCabecalho() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.payment, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text(
            'FORMAS DE PAGAMENTO',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (_pagamentoCompleto)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'COMPLETO',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBotoesPagamento() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: TipoPagamento.values.map((tipo) {
        return _buildBotaoTipoPagamento(tipo);
      }).toList(),
    );
  }

  Widget _buildBotaoTipoPagamento(TipoPagamento tipo) {
    final cor = _getCorTipo(tipo);
    final icone = _getIconeTipo(tipo);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _adicionarPagamento(tipo),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cor.withOpacity(0.9), cor.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: cor.withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                tipo.nome,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListaPagamentos() {
    // Agrupar parcelas por parcelamentoId
    final Map<String?, List<PagamentoPedido>> grupos = {};

    for (final pag in widget.pagamentos) {
      if (pag.isParcela && pag.parcelamentoId != null) {
        grupos.putIfAbsent(pag.parcelamentoId, () => []).add(pag);
      } else {
        grupos.putIfAbsent(pag.id, () => []).add(pag);
      }
    }

    return Column(
      children: grupos.entries.map((entry) {
        final pagamentos = entry.value;
        if (pagamentos.length > 1) {
          // É um parcelamento
          return _buildGrupoParcelamento(pagamentos);
        } else {
          // Pagamento único
          return _buildItemPagamento(pagamentos.first);
        }
      }).toList(),
    );
  }

  Widget _buildGrupoParcelamento(List<PagamentoPedido> parcelas) {
    parcelas.sort(
      (a, b) => (a.numeroParcela ?? 0).compareTo(b.numeroParcela ?? 0),
    );

    final totalParcelas = parcelas.length;
    final parcelasPagas = parcelas.where((p) => p.recebido).length;
    final valorTotal = parcelas.fold(0.0, (sum, p) => sum + p.valor);
    final tipo = parcelas.first.tipo;
    final cor = _getCorTipo(tipo);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor.withOpacity(0.25), cor.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withOpacity(0.4)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getIconeTipo(tipo), color: Colors.white, size: 22),
          ),
          title: Row(
            children: [
              Text(
                tipo.nome,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.purple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${totalParcelas}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Text(
                  _formatoMoeda.format(valorTotal),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: parcelasPagas == totalParcelas
                        ? Colors.green.withOpacity(0.3)
                        : Colors.orange.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$parcelasPagas/$totalParcelas pagas',
                    style: TextStyle(
                      color: parcelasPagas == totalParcelas
                          ? Colors.greenAccent
                          : Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent, size: 22),
            onPressed: () => _confirmarRemocaoParcelamento(parcelas.first),
          ),
          children: [...parcelas.map((parcela) => _buildItemParcela(parcela))],
        ),
      ),
    );
  }

  Widget _buildItemParcela(PagamentoPedido parcela) {
    final cor = _getCorTipo(parcela.tipo);
    final isVencida = parcela.isVencida;
    final venceHoje = parcela.venceHoje;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: parcela.recebido
            ? Colors.green.withOpacity(0.15)
            : isVencida
            ? Colors.red.withOpacity(0.15)
            : Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: parcela.recebido
              ? Colors.green.withOpacity(0.5)
              : isVencida
              ? Colors.red.withOpacity(0.5)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          // Número da parcela
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: parcela.recebido ? Colors.green : cor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: parcela.recebido
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : Text(
                      '${parcela.numeroParcela}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Info da parcela
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${parcela.numeroParcela}ª Parcela',
                  style: TextStyle(
                    color: parcela.recebido ? Colors.greenAccent : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (parcela.dataVencimento != null)
                  Row(
                    children: [
                      Icon(
                        venceHoje
                            ? Icons.today
                            : isVencida
                            ? Icons.warning
                            : Icons.calendar_today,
                        size: 12,
                        color: venceHoje
                            ? Colors.orange
                            : isVencida
                            ? Colors.red
                            : Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        venceHoje
                            ? 'Vence HOJE'
                            : isVencida
                            ? 'VENCIDA - ${_formatoData.format(parcela.dataVencimento!)}'
                            : 'Vence ${_formatoData.format(parcela.dataVencimento!)}',
                        style: TextStyle(
                          color: venceHoje
                              ? Colors.orange
                              : isVencida
                              ? Colors.red
                              : Colors.white54,
                          fontSize: 11,
                          fontWeight: isVencida || venceHoje
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                if (parcela.recebido && parcela.dataRecebimento != null)
                  Text(
                    'Pago em ${_formatoData.format(parcela.dataRecebimento!)}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          // Valor
          Text(
            _formatoMoeda.format(parcela.valor),
            style: TextStyle(
              color: parcela.recebido ? Colors.greenAccent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemPagamento(PagamentoPedido pagamento) {
    final cor = _getCorTipo(pagamento.tipo);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor.withOpacity(0.35), cor.withOpacity(0.15)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: cor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: cor.withOpacity(0.5),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              _getIconeTipo(pagamento.tipo),
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pagamento.tipo.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (pagamento.observacao != null &&
                    pagamento.observacao!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      pagamento.observacao!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (pagamento.troco != null && pagamento.troco! > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.currency_exchange,
                            color: Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Recebido: ${_formatoMoeda.format(pagamento.valorRecebido ?? 0)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'TROCO: ${_formatoMoeda.format(pagamento.troco!)}',
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
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _formatoMoeda.format(pagamento.valor),
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _confirmarRemocao(pagamento),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.8),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.delete, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmarRemocao(PagamentoPedido pagamento) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.delete_forever,
                color: Colors.red,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Remover Pagamento',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _getIconeTipo(pagamento.tipo),
                    color: _getCorTipo(pagamento.tipo),
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pagamento.tipo.nome,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _formatoMoeda.format(pagamento.valor),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tem certeza que deseja remover este pagamento?',
              style: TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _removerPagamento(pagamento);
              Navigator.pop(context);
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 10),
                      Text('${pagamento.tipo.nome} removido'),
                    ],
                  ),
                  backgroundColor: Colors.orange,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.delete),
            label: const Text('Remover', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumo() {
    // Verifica se todos os pagamentos são Dinheiro para permitir troco
    final todosDinheiro =
        widget.pagamentos.isNotEmpty &&
        widget.pagamentos.every((p) => p.tipo == TipoPagamento.dinheiro);

    // Calcula se há troco (lançado > total) - MAS SÓ SE TODOS FOREM DINHEIRO
    final temTroco = todosDinheiro && _totalLancado > widget.totalPedido + 0.01;
    final valorTroco = temTroco ? _totalLancado - widget.totalPedido : 0.0;
    final valorFaltando = _valorRestante > 0.01 ? _valorRestante : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildLinhaResumo(
            'Total do Pedido',
            widget.totalPedido,
            Colors.white,
          ),
          const SizedBox(height: 6),
          _buildLinhaResumo('Lançado', _totalLancado, Colors.greenAccent),
          const Divider(color: Colors.white24, height: 16),
          if (temTroco)
            _buildLinhaResumo(
              'Troco',
              valorTroco,
              Colors.amber,
              destaque: true,
              icone: Icons.currency_exchange,
            )
          else if (valorFaltando > 0)
            _buildLinhaResumo(
              'Faltando',
              valorFaltando,
              Colors.orange,
              destaque: true,
              icone: Icons.warning_amber,
            )
          else
            _buildLinhaResumo(
              'Pagamento Completo',
              0,
              Colors.greenAccent,
              destaque: true,
              icone: Icons.check_circle,
              mostrarValor: false,
            ),
        ],
      ),
    );
  }

  Widget _buildLinhaResumo(
    String label,
    double valor,
    Color cor, {
    bool destaque = false,
    IconData? icone,
    bool mostrarValor = true,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[
              Icon(icone, color: cor, size: destaque ? 20 : 16),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: destaque ? Colors.white : Colors.white70,
                fontSize: destaque ? 14 : 13,
                fontWeight: destaque ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        if (mostrarValor)
          Text(
            _formatoMoeda.format(valor),
            style: TextStyle(
              color: cor,
              fontSize: destaque ? 18 : 14,
              fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
            ),
          )
        else
          Icon(Icons.check_circle, color: cor, size: 24),
      ],
    );
  }

  Color _getCorTipo(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Colors.green;
      case TipoPagamento.pix:
        return const Color(0xFF00BFA5);
      case TipoPagamento.cartaoCredito:
        return Colors.purple;
      case TipoPagamento.cartaoDebito:
        return Colors.indigo;
      case TipoPagamento.boleto:
        return Colors.orange;
      case TipoPagamento.crediario:
        return Colors.pink;
      case TipoPagamento.fiado:
        return Colors.red;
      case TipoPagamento.outro:
        return Colors.grey;
    }
  }

  IconData _getIconeTipo(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.attach_money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt_long;
      case TipoPagamento.crediario:
        return Icons.calendar_month;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
    }
  }
}
