import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/forma_pagamento.dart';
import '../models/pedido.dart';

/// Diálogo de visualização de um pedido/serviço.
///
/// Mostra cliente, serviços, valores recebidos/em aberto, pagamentos e
/// observações, com atalhos para imprimir, editar e receber.
Future<void> mostrarDetalhesPedido(
  BuildContext context,
  Pedido pedido, {
  VoidCallback? onImprimir,
  VoidCallback? onEditar,
  VoidCallback? onReceber,
  VoidCallback? onAprovar,
  String? rotuloAprovar,
  String? rotuloStatusOverride,
  Color? corStatusOverride,
}) {
  final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
  final formatoData = DateFormat('dd/MM/yyyy HH:mm');

  final isCancelado = pedido.status.toLowerCase() == 'cancelado';
  final isRecebido = !isCancelado && pedido.totalmenteRecebido;
  final falta = pedido.totalGeral - pedido.totalRecebido;

  final corStatus = corStatusOverride ??
      (isCancelado
          ? Colors.redAccent
          : isRecebido
              ? Colors.greenAccent
              : Colors.orangeAccent);
  final labelStatus = rotuloStatusOverride ??
      (isCancelado
          ? 'CANCELADO'
          : isRecebido
              ? 'RECEBIDO'
              : 'EM ABERTO');

  Widget infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    );
  }

  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            isCancelado
                ? Icons.cancel
                : isRecebido
                    ? Icons.check_circle
                    : Icons.schedule,
            color: corStatus,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pedido.numero.isNotEmpty ? pedido.numero : 'Serviço',
              style: const TextStyle(color: Colors.white, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: corStatus.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: corStatus.withValues(alpha: 0.6)),
            ),
            child: Text(
              labelStatus,
              style: TextStyle(
                color: corStatus,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            infoRow(
              Icons.person,
              'Cliente',
              (pedido.clienteNome?.isNotEmpty ?? false)
                  ? pedido.clienteNome!
                  : 'Consumidor final',
            ),
            if (pedido.clienteTelefone?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              infoRow(Icons.phone, 'Telefone', pedido.clienteTelefone!),
            ],
            if (pedido.clienteEndereco?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              infoRow(Icons.location_on, 'Endereço', pedido.clienteEndereco!),
            ],
            const SizedBox(height: 8),
            infoRow(Icons.calendar_today, 'Data', formatoData.format(pedido.dataPedido)),
            if (pedido.operador?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              infoRow(Icons.badge, 'Atendente', pedido.operador!),
            ],
            const Divider(color: Colors.white24, height: 24),
            // Serviços
            ...pedido.servicos.map(
              (servico) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.build, size: 14, color: Colors.lightBlueAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            servico.descricao,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          moeda.format(servico.valor + servico.valorAdicional),
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                    if (servico.valorAdicional > 0.001)
                      Padding(
                        padding: const EdgeInsets.only(left: 20, top: 2),
                        child: Text(
                          'Adicional: ${moeda.format(servico.valorAdicional)}'
                          '${servico.descricaoAdicional != null && servico.descricaoAdicional!.isNotEmpty ? ' — ${servico.descricaoAdicional}' : ''}',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                        ),
                      ),
                    if (servico.dataAgendamento != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 20, top: 2),
                        child: Text(
                          'Agendado: ${formatoData.format(servico.dataAgendamento!)}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    if (servico.tipoEntrega != null && servico.tipoEntrega!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 20, top: 2),
                        child: Text(
                          'Entrega: ${servico.tipoEntrega}'
                          '${(servico.valorTaxiDog ?? 0) > 0 ? ' (${moeda.format(servico.valorTaxiDog!)})' : ''}',
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Produtos (quando o pedido tiver itens junto com o serviço)
            if (pedido.produtos.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...pedido.produtos.map(
                (produto) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2, size: 14, color: Colors.white54),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${produto.quantidade.toStringAsFixed(0)}x ${produto.nome}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      Text(
                        moeda.format(produto.preco * produto.quantidade),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(color: Colors.white24, height: 24),
            infoRow(Icons.attach_money, 'Total', moeda.format(pedido.totalGeral)),
            if (!isCancelado) ...[
              const SizedBox(height: 8),
              infoRow(
                Icons.savings,
                'Recebido',
                moeda.format(pedido.totalRecebido),
              ),
              if (!isRecebido) ...[
                const SizedBox(height: 8),
                infoRow(Icons.error_outline, 'Em aberto', moeda.format(falta)),
              ],
            ],
            if (pedido.pagamentos.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Pagamentos',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              ...pedido.pagamentos.map(
                (pag) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        pag.recebido ? Icons.check_circle : Icons.schedule,
                        size: 14,
                        color: pag.recebido ? Colors.greenAccent : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${pag.tipo.nome}${pag.isParcela ? ' (${pag.descricaoParcela})' : ''}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      Text(
                        moeda.format(pag.valor),
                        style: TextStyle(
                          color: pag.recebido ? Colors.greenAccent : Colors.orangeAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (pedido.observacoes?.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              infoRow(Icons.notes, 'Observações', pedido.observacoes!),
            ],
          ],
        ),
      ),
      actions: [
        if (onImprimir != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              onImprimir();
            },
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Imprimir'),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
          ),
        if (onAprovar != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              onAprovar();
            },
            icon: Icon(
              rotuloAprovar == 'Gerar pedido'
                  ? Icons.receipt_long
                  : Icons.thumb_up,
              size: 18,
            ),
            label: Text(rotuloAprovar ?? 'Aprovar'),
            style: TextButton.styleFrom(foregroundColor: Colors.purpleAccent),
          ),
        if (onReceber != null && !isCancelado && !isRecebido)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              onReceber();
            },
            icon: const Icon(Icons.payments, size: 18),
            label: const Text('Receber'),
            style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
          ),
        if (onEditar != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              onEditar();
            },
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Editar'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
