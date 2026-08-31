// Simple replacement: just cut out old method and paste new one
const fs = require('fs');
const f = 'lib/pages/contas_receber_page.dart';
let c = fs.readFileSync(f, 'utf8');

// Find the method
const markers = [
  '  void _mostrarDialogoPagamento(BuildContext context, ContaPagar conta) {\n',
  '  void _estornarPagamento(BuildContext context, ContaPagar conta, RegistroPagamento pagamento) {\n'
];

const i0 = c.indexOf(markers[0]);
const i1 = c.indexOf(markers[1]);

if (i0 < 0 || i1 < 0) { console.log('NOT FOUND', i0, i1); process.exit(1); }

// Find start of line before first marker
let start = i0;
while (start > 0 && c[start-1] === '\n') start--;

const newContent = c.substring(0, start) + '\n' + 
`  void _mostrarDialogoPagamento(BuildContext context, ContaPagar conta) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    final valorPendente = conta.valorPendente;
    final acrescimoController = TextEditingController(text: '0,00');
    final descontoController = TextEditingController(text: '0,00');
    final valorController = TextEditingController(
      text: valorPendente.toStringAsFixed(2).replaceAll('.', ','),
    );
    TipoPagamento? formaSelecionada;

    String tipoCreditoLabel = 'Fiado';
    if (conta.id.startsWith('pedido_')) {
      final idReal = conta.id.replaceFirst('pedido_', '');
      try {
        final pedido = dataService.pedidos.firstWhere((p) => p.id == idReal);
        for (final pag in pedido.pagamentos) {
          if (pag.tipo == TipoPagamento.crediario) {
            tipoCreditoLabel = 'Credito';
            break;
          }
        }
      } catch (_) {}
    } else if (conta.id.contains('crediario') || conta.id.contains('credito')) {
      tipoCreditoLabel = 'Credito';
    }

    final corPrincipal = tipoCreditoLabel == 'Fiado' ? const Color(0xFFD84315) : const Color(0xFFE91E63);

    final formasRecebimento = TipoPagamento.values
        .where((t) => t != TipoPagamento.fiado && t != TipoPagamento.crediario)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final acrescimo = double.tryParse(acrescimoController.text.replaceAll(',', '.')) ?? 0.0;
          final desconto = double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0;
          final totalComAcerto = valorPendente + acrescimo - desconto;
          final valorDigitado = double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0.0;
          final isParcial = valorDigitado > 0 && valorDigitado < totalComAcerto - 0.01;
          final valorRestante = totalComAcerto - valorDigitado;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: corPrincipal.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.payments, color: corPrincipal, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Receber ' + tipoCreditoLabel, style: const TextStyle(color: Colors.white, fontSize: 18)),
                      Text(
                        conta.fornecedorNome ?? 'Cliente',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: corPrincipal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: corPrincipal.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Pendente', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                            Text('1 venda(s)', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                          ],
                        ),
                        Text(formatoMoeda.format(valorPendente), style: TextStyle(color: corPrincipal, fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Acrecimo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: acrescimoController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                prefixText: 'R\\$ ',
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                              onChanged: (_) {
                                final a = double.tryParse(acrescimoController.text.replaceAll(',', '.')) ?? 0.0;
                                final d = double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0;
                                valorController.text = (valorPendente + a - d).toStringAsFixed(2).replaceAll('.', ',');
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Desconto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: descontoController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                prefixText: 'R\\$ ',
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                              onChanged: (_) {
                                final a = double.tryParse(acrescimoController.text.replaceAll(',', '.')) ?? 0.0;
                                final d = double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0;
                                valorController.text = (valorPendente + a - d).toStringAsFixed(2).replaceAll('.', ',');
                                setDialogState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Valor a receber', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: valorController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      prefixText: 'R\\$ ',
                      prefixStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 24, fontWeight: FontWeight.bold),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: corPrincipal)),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (isParcial) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pagamento parcial: restara R\\$' + valorRestante.toStringAsFixed(2).replaceAll('.', ','),
                              style: const TextStyle(color: Colors.blue, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text('Forma de recebimento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: formasRecebimento.map((tipo) {
                      final isSelected = formaSelecionada == tipo;
                      final cor = _getCorTipoRecebimento(tipo);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setDialogState(() => formaSelecionada = tipo),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? cor.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isSelected ? cor : Colors.white.withOpacity(0.2), width: isSelected ? 2 : 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getIconeTipoRecebimento(tipo), color: isSelected ? cor : Colors.white54, size: 18),
                                const SizedBox(width: 6),
                                Text(tipo.nome, style: TextStyle(color: isSelected ? cor : Colors.white70, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: (formaSelecionada == null || valorDigitado <= 0 || valorDigitado > totalComAcerto + 0.01)
                    ? null
                    : () async {
                        final forma = formaSelecionada!;
                        final acrescimoVal = double.tryParse(acrescimoController.text.replaceAll(',', '.')) ?? 0.0;
                        final descontoVal = double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0;
                        final hoje = DateTime.now();
                        final totalReceber = valorDigitado - acrescimoVal + descontoVal;

                        if (conta.id.startsWith('venda_')) {
                          final idReal = conta.id.replaceFirst('venda_', '');
                          try {
                            final vendaOriginal = dataService.vendasBalcao.firstWhere((v) => v.id == idReal);
                            final novoRecebido = (vendaOriginal.valorRecebido ?? 0.0) + totalReceber;
                            await dataService.updateVendaBalcao(vendaOriginal.copyWith(
                              tipoPagamento: (vendaOriginal.valorRecebido != null && vendaOriginal.valorRecebido! > 0) ? vendaOriginal.tipoPagamento : forma,
                              valorRecebido: novoRecebido,
                              updatedAt: hoje,
                            ));
                            if (vendaOriginal.tipoPagamento == TipoPagamento.fiado && vendaOriginal.clienteId != null) {
                              final cliente = dataService.clientes.firstWhere((c) => c.id == vendaOriginal.clienteId, orElse: () => Cliente(id: '', nome: '', telefone: '', createdAt: hoje, updatedAt: hoje));
                              if (cliente.id.isNotEmpty) {
                                final novoSaldo = (cliente.saldoDevedor - totalReceber).clamp(0.0, double.infinity);
                                await dataService.updateCliente(cliente.copyWith(saldoDevedor: novoSaldo, updatedAt: hoje));
                              }
                            }
                          } catch (e) {
                            debugPrint('Erro ao atualizar venda: ' + e.toString());
                          }
                        } else if (conta.id.startsWith('pedido_')) {
                          final idReal = conta.id.replaceFirst('pedido_', '');
                          try {
                            final pedido = dataService.pedidos.firstWhere((p) => p.id == idReal);
                            TipoPagamento? tipoCredito;
                            for (final pag in pedido.pagamentos) {
                              if (pag.tipo == TipoPagamento.fiado || pag.tipo == TipoPagamento.crediario) {
                                tipoCredito = pag.tipo;
                                break;
                              }
                            }
                            if (tipoCredito != null) {
                              double valorRest = valorDigitado - acrescimoVal + descontoVal;
                              final novosPagamentos = <PagamentoPedido>[];
                              bool aplicouTaxas = false;
                              for (final pag in pedido.pagamentos) {
                                if (pag.tipo == tipoCredito && !pag.recebido && valorRest > 0) {
                                  if (!aplicouTaxas) {
                                    if (acrescimoVal > 0) {
                                      novosPagamentos.add(PagamentoPedido(
                                        id: 'acrescimo_' + DateTime.now().millisecondsSinceEpoch.toString(),
                                        tipo: forma, tipoOriginal: tipoCredito,
                                        valor: acrescimoVal, recebido: true,
                                        dataRecebimento: hoje, observacao: 'Acrecimo recebimento',
                                      ));
                                    }
                                    if (descontoVal > 0) {
                                      novosPagamentos.add(PagamentoPedido(
                                        id: 'desconto_' + DateTime.now().millisecondsSinceEpoch.toString(),
                                        tipo: forma, tipoOriginal: tipoCredito,
                                        valor: -descontoVal, recebido: true,
                                        dataRecebimento: hoje, observacao: 'Desconto recebimento',
                                      ));
                                    }
                                    aplicouTaxas = true;
                                  }
                                  if (valorRest >= pag.valor) {
                                    novosPagamentos.add(PagamentoPedido(
                                      id: pag.id, tipo: forma, tipoOriginal: tipoCredito,
                                      valor: pag.valor, recebido: true,
                                      dataRecebimento: hoje, dataVencimento: pag.dataVencimento,
                                      observacao: 'Recebido do ' + (tipoCredito == TipoPagamento.fiado ? 'fiado' : 'credito'),
                                    ));
                                    valorRest -= pag.valor;
                                  } else {
                                    novosPagamentos.add(PagamentoPedido(
                                      id: pag.id + '_pago', tipo: forma, tipoOriginal: tipoCredito,
                                      valor: valorRest, recebido: true,
                                      dataRecebimento: hoje, observacao: 'Recebimento parcial',
                                    ));
                                    novosPagamentos.add(PagamentoPedido(
                                      id: pag.id + '_resto', tipo: tipoCredito,
                                      valor: pag.valor - valorRest, recebido: false,
                                      dataVencimento: pag.dataVencimento,
                                      observacao: 'Restante do ' + (tipoCredito == TipoPagamento.fiado ? 'fiado' : 'credito'),
                                    ));
                                    valorRest = 0;
                                  }
                                } else {
                                  novosPagamentos.add(pag);
                                }
                              }
                              final todosRecebidos = novosPagamentos.every((p) => p.recebido);
                              await dataService.updatePedido(pedido.copyWith(
                                total: aplicouTaxas ? (pedido.total + acrescimoVal - descontoVal) : pedido.total,
                                status: todosRecebidos ? 'Pago' : pedido.status,
                                pagamentos: novosPagamentos,
                                updatedAt: hoje,
                              ));
                            }
                            if (tipoCredito == TipoPagamento.fiado && pedido.clienteId != null) {
                              final cliente = dataService.clientes.firstWhere((c) => c.id == pedido.clienteId, orElse: () => Cliente(id: '', nome: '', telefone: '', createdAt: hoje, updatedAt: hoje));
                              if (cliente.id.isNotEmpty) {
                                final novoSaldo = (cliente.saldoDevedor - totalReceber).clamp(0.0, double.infinity);
                                await dataService.updateCliente(cliente.copyWith(saldoDevedor: novoSaldo, updatedAt: hoje));
                              }
                            }
                          } catch (e) {
                            debugPrint('Erro ao atualizar pedido: ' + e.toString());
                          }
                        } else {
                          final novoValorPago = (conta.valorPago ?? 0.0) + totalReceber;
                          final novoStatus = (novoValorPago >= conta.valor - 0.01) ? StatusContaPagar.pago : conta.status;
                          final novoRegistro = RegistroPagamento(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            valor: totalReceber,
                            dataPagamento: hoje,
                            formaPagamento: forma.nome,
                          );
                          final novoHistorico = List<RegistroPagamento>.from(conta.historicoPagamentos)..add(novoRegistro);
                          final contaAtualizada = conta.copyWith(
                            valorPago: novoValorPago,
                            dataPagamento: novoStatus == StatusContaPagar.pago ? hoje : conta.dataPagamento,
                            status: novoStatus,
                            formaPagamento: forma.nome,
                            historicoPagamentos: novoHistorico,
                            updatedAt: hoje,
                          );
                          await dataService.updateContaPagar(contaAtualizada);
                        }

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});

                        final msg = (valorDigitado >= totalComAcerto - 0.01)
                            ? 'Recebimento concluido com sucesso!'
                            : 'Pagamento parcial de R\\$' + valorDigitado.toStringAsFixed(2).replaceAll('.', ',') + ' registrado. Restante: R\\$' + (totalComAcerto - valorDigitado).toStringAsFixed(2).replaceAll('.', ',');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green, duration: const Duration(seconds: 3)));
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (formaSelecionada != null && valorDigitado > 0) ? corPrincipal : Colors.grey,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

` + c.substring(i1);

fs.writeFileSync(f, newContent, 'utf8');
console.log('SUCCESS. New length:', newContent.length);
