import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/pedido.dart';
import '../models/empresa.dart';
import '../models/forma_pagamento.dart';
import '../models/adicional_produto.dart';
import '../models/romaneio.dart';
import 'impressao_service.dart';

/// Serviço para geração de PDF de pedido
class PedidoPDFService {
  /// Gera PDF do pedido
  static Future<Uint8List> gerarPDF({
    required Pedido pedido,
    required Empresa empresa,
  }) async {
    try {
      final pdf = pw.Document();
      final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      final formatoData = DateFormat('dd/MM/yyyy HH:mm');

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildCabecalho(empresa),
                pw.SizedBox(height: 20),
                _buildDadosPedido(pedido, formatoData),
                pw.SizedBox(height: 20),
                _buildCliente(pedido),
                if (pedido.deliveryInfo != null) ...[
                  pw.SizedBox(height: 20),
                  _buildDeliveryA4(pedido),
                ],
                pw.SizedBox(height: 20),
                _buildItens(pedido, formatoMoeda),
                pw.SizedBox(height: 20),
                _buildTotal(pedido, formatoMoeda),
                pw.SizedBox(height: 20),
                _buildPagamentos(pedido, formatoMoeda),
                if (pedido.observacoes != null && pedido.observacoes!.isNotEmpty) ...[
                  pw.SizedBox(height: 20),
                  _buildObservacoes(pedido),
                ],
                pw.Spacer(),
                _buildRodape(empresa, formatoData),
              ],
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar PDF do pedido: $e');
    }
  }

  /// Constrói cabeçalho do PDF
  static pw.Widget _buildCabecalho(Empresa empresa) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            'PEDIDO',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 10),
          pw.Center(
            child: pw.Text(
              empresa.nomeExibicao,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          if (empresa.cnpj != null) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              'CNPJ: ${_formatarCNPJ(empresa.cnpj!)}',
              style: const pw.TextStyle(fontSize: 10),
              textAlign: pw.TextAlign.center,
            ),
          ],
          if (empresa.enderecoCompleto.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              empresa.enderecoCompleto,
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ],
          if (empresa.telefone != null && empresa.telefone!.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              'Tel: ${empresa.telefone}',
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// Constrói dados do pedido
  static pw.Widget _buildDadosPedido(Pedido pedido, DateFormat formatoData) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey700),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'PEDIDO',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Nº: ${pedido.numero}',
                style: const pw.TextStyle(fontSize: 12),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Status: ${pedido.status}',
                style: const pw.TextStyle(fontSize: 11),
              ),
              if (pedido.senha != null && pedido.senha!.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'Senha: ${pedido.senha}',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Data/Hora',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                formatoData.format(pedido.dataPedido),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Constrói informações do cliente
  static pw.Widget _buildCliente(Pedido pedido) {
    if (pedido.clienteNome == null || pedido.clienteNome!.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
          borderRadius: pw.BorderRadius.circular(5),
          color: PdfColors.grey100,
        ),
        child: pw.Row(
          children: [
            pw.Text(
              'Cliente: ',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'CONSUMIDOR FINAL',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
        borderRadius: pw.BorderRadius.circular(5),
        color: PdfColors.grey100,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'Cliente: ',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  pedido.clienteNome!,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (pedido.clienteCpfCnpj != null && pedido.clienteCpfCnpj!.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Row(
              children: [
                pw.Text(
                  pedido.clienteCpfCnpj!.replaceAll(RegExp(r'[^\d]'), '').length == 11 ? 'CPF: ' : 'CNPJ: ',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _formatarCpfCnpj(pedido.clienteCpfCnpj!),
                  style: pw.TextStyle(
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
          if (pedido.clienteTelefone != null && pedido.clienteTelefone!.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Row(
              children: [
                pw.Text(
                  'Telefone: ',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  pedido.clienteTelefone!,
                  style: pw.TextStyle(
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
          if (pedido.clienteEndereco != null && pedido.clienteEndereco!.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Endereço: ',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    pedido.clienteEndereco!,
                    style: const pw.TextStyle(
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Constrói bloco de entrega (A4) com endereço destacado para o entregador
  static pw.Widget _buildDeliveryA4(Pedido pedido) {
    final info = pedido.deliveryInfo!;
    final String? previsao =
        info.previsaoEntrega?.trim().isNotEmpty == true ? info.previsaoEntrega!.trim() : null;

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.black,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ENTREGA / DELIVERY',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Cliente + telefone bem visíveis para o motoboy
                pw.Text(
                  'CLIENTE: ${pedido.clienteNome ?? "CONSUMIDOR FINAL"}',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                if (pedido.clienteTelefone != null && pedido.clienteTelefone!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'TEL: ${pedido.clienteTelefone!}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                ],
                pw.SizedBox(height: 6),
                pw.Text(
                  'ENDEREÇO DE ENTREGA',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${info.logradouro}, ${info.numero}',
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.Text(
                  '${info.bairro} - ${info.cidade}/${info.uf}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                if (info.cep != null && info.cep!.isNotEmpty)
                  pw.Text(
                    'CEP: ${info.cep}',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                if (info.observacoes != null && info.observacoes!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Obs.: ${info.observacoes}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                  ),
                ],
                pw.SizedBox(height: 6),
                pw.Divider(color: PdfColors.grey500),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'HORA DO PEDIDO:',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                    ),
                    pw.Text(
                      DateFormat('HH:mm').format(pedido.dataPedido),
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                    ),
                  ],
                ),
                if (previsao != null) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'PREVISÃO DE ENTREGA:',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                      ),
                      pw.Text(
                        previsao,
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                      ),
                    ],
                  ),
                ],
                if (info.motoristaNome != null && info.motoristaNome!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Motorista: ${info.motoristaNome}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói itens do pedido
  static pw.Widget _buildItens(Pedido pedido, NumberFormat formatoMoeda) {
    final todosItens = <_ItemLinha>[];
    
    // Adicionar produtos
    for (final produto in pedido.produtos) {
      todosItens.add(_ItemLinha(
        nome: produto.nome,
        quantidade: produto.quantidade,
        precoUnitario: produto.preco,
        tipo: 'Produto',
        adicionais: produto.adicionais,
      ));
    }
    
    // Adicionar serviços
    for (final servico in pedido.servicos) {
      todosItens.add(_ItemLinha(
        nome: servico.descricao,
        quantidade: 1.0,
        precoUnitario: servico.valor + servico.valorAdicional,
        tipo: 'Serviço',
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ITENS',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(0.5),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1),
          },
          children: [
            // Cabeçalho
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    'Descrição',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    'Qtd',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    'Unit.',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(
                    'Total',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
            // Itens
            ...todosItens.map((item) {
              final subtotal = item.precoUnitario * item.quantidade;
              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          item.nome,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        if (item.adicionais.isNotEmpty)
                          ...item.adicionais.map((a) => pw.Text(
                            '+ ${a.nome} (${formatoMoeda.format(a.preco)})',
                            style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                          )),
                        pw.Text(
                          '(${item.tipo})',
                          style: pw.TextStyle(
                            fontSize: 7,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      item.quantidade.toString(),
                      style: const pw.TextStyle(fontSize: 9),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      formatoMoeda.format(item.precoUnitario),
                      style: const pw.TextStyle(fontSize: 9),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      formatoMoeda.format(subtotal),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  /// Constrói totais
  static pw.Widget _buildTotal(Pedido pedido, NumberFormat formatoMoeda) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey700, width: 2),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total Produtos:',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Text(
                formatoMoeda.format(pedido.totalProdutos),
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total Serviços:',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Text(
                formatoMoeda.format(pedido.totalServicos),
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                formatoMoeda.format(pedido.totalGeral),
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Constrói formas de pagamento
  static pw.Widget _buildPagamentos(Pedido pedido, NumberFormat formatoMoeda) {
    if (pedido.pagamentos.isEmpty) {
      return pw.SizedBox.shrink();
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'PAGAMENTOS',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Column(
            children: [
              ...pedido.pagamentos.map((pagamento) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            _getNomeTipoPagamento(pagamento.tipo),
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                          pw.Text(
                            formatoMoeda.format(pagamento.valor),
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (pagamento.isParcela) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Parcela ${pagamento.numeroParcela}/${pagamento.parcelas}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                      if (pagamento.dataVencimento != null) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Vencimento: ${DateFormat('dd/MM/yyyy').format(pagamento.dataVencimento!)}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                      pw.SizedBox(height: 2),
                      pw.Text(
                        pagamento.recebido ? 'Status: Pago' : 'Status: Pendente',
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: pagamento.recebido ? PdfColors.green700 : PdfColors.orange700,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              pw.SizedBox(height: 5),
              pw.Divider(),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Total Recebido:',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    formatoMoeda.format(pedido.totalRecebido),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green700,
                    ),
                  ),
                ],
              ),
              if (pedido.valorPendente > 0) ...[
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Pendente:',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      formatoMoeda.format(pedido.valorPendente),
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.orange700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Constrói observações
  static pw.Widget _buildObservacoes(Pedido pedido) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'OBSERVAÇÕES',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            pedido.observacoes!,
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  /// Constrói rodapé
  static pw.Widget _buildRodape(Empresa empresa, DateFormat formatoData) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'Documento gerado em ${formatoData.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            textAlign: pw.TextAlign.center,
          ),
          if (empresa.email != null && empresa.email!.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'E-mail: ${empresa.email}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// Formata CNPJ
  static String _formatarCNPJ(String cnpj) {
    final apenasNumeros = cnpj.replaceAll(RegExp(r'[^0-9]'), '');
    if (apenasNumeros.length != 14) return cnpj;
    return '${apenasNumeros.substring(0, 2)}.${apenasNumeros.substring(2, 5)}.${apenasNumeros.substring(5, 8)}/${apenasNumeros.substring(8, 12)}-${apenasNumeros.substring(12)}';
  }

  /// Retorna nome do tipo de pagamento
  static String _getNomeTipoPagamento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return 'Dinheiro';
      case TipoPagamento.pix:
        return 'PIX';
      case TipoPagamento.cartaoCredito:
        return 'Cartão de Crédito';
      case TipoPagamento.cartaoDebito:
        return 'Cartão de Débito';
      case TipoPagamento.crediario:
        return 'Crediário';
      case TipoPagamento.boleto:
        return 'Boleto';
      case TipoPagamento.fiado:
        return 'Fiado';
      case TipoPagamento.outro:
        return 'Outro';
      case TipoPagamento.alimentacao:
        return 'Ticket/Alimentação';
      case TipoPagamento.transferencia:
        return 'Transferência';
    }
  }

  /// Gera PDF do pedido em formato térmico (80mm)
  static Future<Uint8List> gerarPDFTermico({
    required Pedido pedido,
    required Empresa empresa,
  }) async {
    try {
      final pdf = pw.Document();
      final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      final formatoData = DateFormat('dd/MM/yyyy HH:mm');

      // Configurações de impressão dinâmicas
      final config = empresa.configuracoes ?? {};
      final double larguraBobina = config['comandaLarguraBobina']?.toDouble() ?? 80.0;
      final double margemEsq = config['comandaMargemEsq']?.toDouble() ?? config['comandaMargemH']?.toDouble() ?? 10.0;
      final double margemDir = config['comandaMargemDir']?.toDouble() ?? config['comandaMargemH']?.toDouble() ?? 15.0;
      final double margemV = config['comandaMargemV']?.toDouble() ?? 10.0;
      final double fontSizeTitulo = config['comandaFonteTitulo']?.toDouble() ?? 10.5;
      final double fontSizeCorpo = config['comandaFonteCorpo']?.toDouble() ?? 7.8;
      final bool usarNegrito = config['comandaNegrito'] ?? true;

      // Cálculo de largura útil (mm -> pt) com compensação de segurança
      final double pageWidth = (larguraBobina - 2) * 2.83465;

      // Calcular altura dinâmica estimada em pontos (pt)
      // 1 mm = 2.83 pt
      // Cabeçalho/Logo/Dados: ~180pt
      // Cliente: ~60pt (mais ~30pt se tiver telefone/entrega)
      // Cada item: ~25pt (mais ~15pt para cada adicional)
      // Total/Pagamentos: ~120pt
      // Rodapé: ~60pt
      double alturaEstimada = 180.0;
      
      // Cliente + bloco de entrega destacado
      alturaEstimada += 60.0;
      if (pedido.clienteTelefone?.isNotEmpty == true) alturaEstimada += 20.0;
      final temEnderecoEntrega =
          (pedido.deliveryInfo?.enderecoCompleto ?? pedido.clienteEndereco)?.isNotEmpty == true;
      if (temEnderecoEntrega || pedido.deliveryInfo != null) {
        alturaEstimada += 220.0; // caixa ENTREGA destacada (cliente + telefone + endereço)
        if (pedido.deliveryInfo?.observacoes?.isNotEmpty == true) alturaEstimada += 25.0;
        if (pedido.deliveryInfo?.previsaoEntrega?.trim().isNotEmpty == true) alturaEstimada += 25.0;
        if ((pedido.deliveryInfo?.valorParaTroco ?? 0) > 0) alturaEstimada += 35.0;
      }
      
      // Itens
      for (final p in pedido.produtos) {
        alturaEstimada += 25.0; // Nome e total
        if (p.adicionais.isNotEmpty) {
          alturaEstimada += p.adicionais.length * 15.0;
        }
      }
      alturaEstimada += pedido.servicos.length * 25.0;
      
      // Totais e pagamentos
      alturaEstimada += 120.0;
      alturaEstimada += (pedido.pagamentos?.length ?? 0) * 15.0;
      
      // Observações e rodapé
      if (pedido.observacoes?.isNotEmpty == true) {
        alturaEstimada += 40.0;
      }
      alturaEstimada += 60.0; // Rodapé final
      
      // Margem de segurança (mínimo de 350pt)
      if (alturaEstimada < 350) alturaEstimada = 350;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidth, alturaEstimada),
          margin: pw.EdgeInsets.only(
            left: margemEsq,
            right: margemDir,
            top: 2,
            bottom: 2,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                _buildCabecalhoTermico(empresa, fontSizeTitulo, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 2),
                _buildDadosPedidoTermico(pedido, formatoData, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 2),
                _buildClienteTermico(pedido, fontSizeCorpo),
                pw.SizedBox(height: 3),
                _buildItensTermico(pedido, formatoMoeda, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 2),
                _buildTotalTermico(pedido, formatoMoeda, fontSizeCorpo),
                pw.SizedBox(height: 2),
                _buildPagamentosTermico(pedido, formatoMoeda, fontSizeCorpo),
                if (pedido.observacoes != null && pedido.observacoes!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  _buildObservacoesTermico(pedido, fontSizeCorpo),
                ],
                pw.SizedBox(height: 4),
                _buildRodapeTermico(empresa, formatoData, fontSizeCorpo),
              ],
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar PDF térmico do pedido: $e');
    }
  }

  /// Constrói cabeçalho do pedido térmico
  static pw.Widget _buildCabecalhoTermico(Empresa empresa, double fontSizeTitulo, double fontSizeCorpo, bool usarNegrito) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 3),
        pw.Text(
          empresa.nomeExibicao,
          style: pw.TextStyle(
            fontSize: fontSizeTitulo,
            fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.Text(
          'CNPJ: ${_formatarCNPJ(empresa.cnpj ?? "")} - Tel: ${empresa.telefone ?? ""}',
          style: pw.TextStyle(fontSize: fontSizeCorpo - 2),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.Divider(thickness: 0.5),
      ],
    );
  }

  /// Constrói dados do pedido térmico
  static pw.Widget _buildDadosPedidoTermico(Pedido pedido, DateFormat formatoData, double fontSizeCorpo, bool usarNegrito) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'PEDIDO Nº: ${pedido.numero}',
          style: pw.TextStyle(fontSize: fontSizeCorpo + 1, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        if (pedido.senha != null && pedido.senha!.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(width: 1),
                bottom: pw.BorderSide(width: 1),
                left: pw.BorderSide(width: 1),
                right: pw.BorderSide(width: 1),
              ),
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              'SENHA: ${pedido.senha}',
              style: pw.TextStyle(fontSize: fontSizeCorpo + 6, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 4),
        ],
        pw.SizedBox(height: 3),
        pw.Text(
          '${pedido.status} - ${formatoData.format(pedido.dataPedido)}',
          style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3),
        pw.Divider(thickness: 0.5),
      ],
    );
  }

  /// Constrói informações do cliente térmico (com endereço de delivery destacado para o entregador)
  static pw.Widget _buildClienteTermico(Pedido pedido, double fontSizeCorpo) {
    final info = pedido.deliveryInfo;
    final String? enderecoLinha = info != null
        ? '${info.logradouro}, ${info.numero}'
        : (pedido.clienteEndereco?.isNotEmpty == true ? pedido.clienteEndereco : null);
    final bool temEntrega = info != null || (enderecoLinha != null && enderecoLinha.isNotEmpty);
    final String? previsao = info?.previsaoEntrega?.trim();
    final bool temPrevisao = previsao != null && previsao.isNotEmpty;
    final DateTime dataPedido = pedido.dataPedido;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (temEntrega) ...[
          // Faixa destacada para o entregador (preto, alto contraste)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            decoration: const pw.BoxDecoration(color: PdfColors.black),
            child: pw.Text(
              ' *** ENTREGA / DELIVERY ***',
              style: pw.TextStyle(
                fontSize: fontSizeCorpo + 2,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 2),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Cliente + telefone bem visíveis para o motoboy
                pw.Text(
                  'CLIENTE: ${pedido.clienteNome ?? "CONSUMIDOR FINAL"}',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo + 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (pedido.clienteTelefone != null && pedido.clienteTelefone!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'TEL: ${pedido.clienteTelefone!}',
                    style: pw.TextStyle(
                      fontSize: fontSizeCorpo + 2,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
                pw.SizedBox(height: 4),
                pw.Text(
                  'ENDEREÇO DE ENTREGA',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo + 3,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                if (enderecoLinha != null && enderecoLinha.isNotEmpty)
                  pw.Text(
                    enderecoLinha,
                    style: pw.TextStyle(
                      fontSize: fontSizeCorpo + 3,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                if (info != null) ...[
                  if (info.bairro.isNotEmpty)
                    pw.Text(
                      'Bairro: ${info.bairro}',
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  if (info.cidade.isNotEmpty)
                    pw.Text(
                      info.uf.isNotEmpty ? '${info.cidade} - ${info.uf}' : info.cidade,
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  if (info.cep != null && info.cep!.isNotEmpty)
                    pw.Text(
                      'CEP: ${info.cep}',
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  if (info.observacoes != null && info.observacoes!.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Obs.: ${info.observacoes}',
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                  if (info.taxaEntrega > 0) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Taxa entrega: R\$ ${info.taxaEntrega.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                  if (info.motoristaNome != null && info.motoristaNome!.isNotEmpty)
                    pw.Text(
                      'Motorista: ${info.motoristaNome}',
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                ],
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 3),
                // Horário do pedido e previsão de entrega para o entregador
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'HORA DO PEDIDO:',
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      DateFormat('HH:mm').format(dataPedido),
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 2,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (temPrevisao) ...[
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'PREVISÃO ENTREGA:',
                        style: pw.TextStyle(
                          fontSize: fontSizeCorpo + 1,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        previsao!,
                        style: pw.TextStyle(
                          fontSize: fontSizeCorpo + 2,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          pw.Text(
            'CLIENTE: ${pedido.clienteNome ?? "CONSUMIDOR FINAL"}',
            style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
          ),
          if (pedido.clienteTelefone != null && pedido.clienteTelefone!.isNotEmpty)
            pw.Text(
              'TEL: ${pedido.clienteTelefone!}',
              style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
            ),
        ],
        pw.SizedBox(height: 2),
        pw.Divider(thickness: 0.5),
      ],
    );
  }

  /// Formata a quantidade para exibição amigável
  static String _formatarQtdItem(double qty) {
    if (qty == qty.roundToDouble()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  /// Constrói itens do pedido térmico com visualização clara e legível
  static pw.Widget _buildItensTermico(Pedido pedido, NumberFormat formatoMoeda, double fontSizeCorpo, bool usarNegrito) {
    final todosItens = <_ItemLinha>[];
    
    // Adicionar produtos
    for (final produto in pedido.produtos) {
      todosItens.add(_ItemLinha(
        nome: produto.nome,
        quantidade: produto.quantidade,
        precoUnitario: produto.preco,
        tipo: 'Produto',
        observacao: produto.observacao,
        adicionais: produto.adicionais,
      ));
    }
    
    // Adicionar serviços
    for (final servico in pedido.servicos) {
      todosItens.add(_ItemLinha(
        nome: servico.descricao,
        quantidade: 1.0,
        precoUnitario: servico.valor + servico.valorAdicional,
        tipo: 'Serviço',
      ));
    }

    int itemIndex = 1;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.black, width: 1),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'ITEM  DESCRIÇÃO',
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 0.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'TOTAL (R\$)',
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 0.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        ...todosItens.map((item) {
          final indexStr = (itemIndex++).toString().padLeft(2, '0');
          final subtotal = item.precoUnitario * item.quantidade;
          final qtdFormatted = _formatarQtdItem(item.quantidade);

          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 4),
            padding: const pw.EdgeInsets.only(bottom: 3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Nome do item em destaque
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '$indexStr. ',
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 0.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        item.nome,
                        style: pw.TextStyle(
                          fontSize: fontSizeCorpo + 0.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),

                // Qtd x Preço Unitário | Subtotal Alinhado
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 14),
                      child: pw.Text(
                        '$qtdFormatted UN  x  ${formatoMoeda.format(item.precoUnitario)}',
                        style: pw.TextStyle(
                          fontSize: fontSizeCorpo,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Text(
                      formatoMoeda.format(subtotal),
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 0.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                // Adicionais
                if (item.adicionais.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  ...item.adicionais.map(
                    (adicional) => pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 14, top: 1),
                      child: pw.Text(
                        '+ ${adicional.nome} (${formatoMoeda.format(adicional.preco)})',
                        style: pw.TextStyle(
                          fontSize: fontSizeCorpo - 0.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],

                // Observação do item
                if (item.observacao != null && item.observacao!.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 14, top: 1),
                    child: pw.Text(
                      '* OBS: ${item.observacao}',
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo - 0.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
        pw.SizedBox(height: 3),
        pw.Divider(thickness: 1),
      ],
    );
  }

  /// Constrói totais térmico
  static pw.Widget _buildTotalTermico(Pedido pedido, NumberFormat formatoMoeda, double fontSizeCorpo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'PRODUTOS:',
              style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            ),
            pw.Text(
              formatoMoeda.format(pedido.totalProdutos),
              style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            ),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'SERVIÇOS:',
              style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            ),
            pw.Text(
              formatoMoeda.format(pedido.totalServicos),
              style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            ),
          ],
        ),
        if (pedido.deliveryInfo?.taxaEntrega != null && pedido.deliveryInfo!.taxaEntrega > 0)
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'ENTREGA:',
              style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            ),
            pw.Text(
              formatoMoeda.format(pedido.deliveryInfo!.taxaEntrega),
              style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            ),
          ],
        ),
        pw.SizedBox(height: 1),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL GERAL',
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 1,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                formatoMoeda.format(pedido.totalGeral),
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 1,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Constrói formas de pagamento térmico
  static pw.Widget _buildPagamentosTermico(Pedido pedido, NumberFormat formatoMoeda, double fontSizeCorpo) {
    if (pedido.pagamentos.isEmpty) {
      return pw.SizedBox.shrink();
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 5),
        pw.Text(
          'PAGAMENTOS',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo + 1,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        ...pedido.pagamentos.map((pagamento) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        _getNomeTipoPagamento(pagamento.tipo),
                        style: pw.TextStyle(fontSize: fontSizeCorpo),
                      ),
                    ),
                    pw.Text(
                      formatoMoeda.format(pagamento.valor),
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (pagamento.isParcela) ...[
                  pw.Text(
                    'Parcela ${pagamento.numeroParcela}/${pagamento.parcelas}',
                    style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                  ),
                ],
                if (pagamento.dataVencimento != null) ...[
                  pw.Text(
                    'Venc: ${DateFormat('dd/MM/yyyy').format(pagamento.dataVencimento!)}',
                    style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                  ),
                ],
                pw.Text(
                  pagamento.recebido ? 'Pago' : 'Pendente',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo - 1,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }),
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Recebido:',
              style: pw.TextStyle(fontSize: fontSizeCorpo),
            ),
            pw.Text(
              formatoMoeda.format(pedido.totalRecebido),
              style: pw.TextStyle(
                fontSize: fontSizeCorpo,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        if (pedido.valorPendente > 0) ...[
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Pendente:',
                style: pw.TextStyle(fontSize: fontSizeCorpo),
              ),
              pw.Text(
                formatoMoeda.format(pedido.valorPendente),
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1),
        if (pedido.deliveryInfo != null && pedido.deliveryInfo!.valorParaTroco > 0) ...[
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Troco para:',
                style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                formatoMoeda.format(pedido.deliveryInfo!.valorParaTroco),
                style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'VALOR TROCO:',
                style: pw.TextStyle(fontSize: fontSizeCorpo + 1, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                formatoMoeda.format(pedido.deliveryInfo!.valorParaTroco - pedido.totalGeral),
                style: pw.TextStyle(fontSize: fontSizeCorpo + 1, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Divider(thickness: 1),
        ],
      ],
    );
  }

  /// Constrói observações térmico
  static pw.Widget _buildObservacoesTermico(Pedido pedido, double fontSizeCorpo) {
    if (pedido.observacoes == null || pedido.observacoes!.trim().isEmpty) return pw.SizedBox.shrink();
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 1),
        pw.Text(
          'OBSERVAÇÕES:',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          pedido.observacoes!,
          style: pw.TextStyle(fontSize: fontSizeCorpo),
        ),
        pw.SizedBox(height: 2),
      ],
    );
  }

  /// Constrói rodapé térmico
  static pw.Widget _buildRodapeTermico(Empresa empresa, DateFormat formatoData, double fontSizeCorpo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 4),
        pw.Text(
          '--------------------------------',
          style: pw.TextStyle(fontSize: fontSizeCorpo - 2),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Obrigado pela preferência!',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          'Documento gerado em ${formatoData.format(DateTime.now())}',
          style: pw.TextStyle(fontSize: fontSizeCorpo - 2),
          textAlign: pw.TextAlign.center,
        ),
        if (empresa.email != null && empresa.email!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'E-mail: ${empresa.email}',
            style: pw.TextStyle(fontSize: fontSizeCorpo - 2),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 10),
        pw.Text(
          '--------------------------------',
          style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  /// Formata CPF ou CNPJ
  static String _formatarCpfCnpj(String cpfCnpj) {
    final apenasNumeros = cpfCnpj.replaceAll(RegExp(r'[^\d]'), '');
    
    if (apenasNumeros.length == 11) {
      // CPF: 000.000.000-00
      return '${apenasNumeros.substring(0, 3)}.${apenasNumeros.substring(3, 6)}.${apenasNumeros.substring(6, 9)}-${apenasNumeros.substring(9)}';
    } else if (apenasNumeros.length == 14) {
      // CNPJ: 00.000.000/0000-00
      return '${apenasNumeros.substring(0, 2)}.${apenasNumeros.substring(2, 5)}.${apenasNumeros.substring(5, 8)}/${apenasNumeros.substring(8, 12)}-${apenasNumeros.substring(12)}';
    }
    
    return cpfCnpj; // Retorna original se não for CPF nem CNPJ válido
  }

  /// Imprime o PDF do pedido (A4)
  static Future<void> imprimirPDF({
    required Pedido pedido,
    required Empresa empresa,
    BuildContext? context,
    bool forcarPreview = false,
  }) async {
    try {
      final pdfBytes = await gerarPDF(pedido: pedido, empresa: empresa);
      await ImpressaoService.imprimirPdf(
        bytes: pdfBytes,
        empresa: empresa,
        name: 'Pedido_${pedido.numero}',
        termico: false,
        context: context,
        forcarPreview: forcarPreview,
      );
    } catch (e) {
      throw Exception('Erro ao imprimir PDF: $e');
    }
  }

  /// Imprime o PDF do pedido em formato térmico (80mm) — preferência: direto na impressora
  static Future<void> imprimirPDFTermico({
    required Pedido pedido,
    required Empresa empresa,
    BuildContext? context,
    bool forcarPreview = false,
  }) async {
    try {
      final pdfBytes = await gerarPDFTermico(pedido: pedido, empresa: empresa);
      await ImpressaoService.imprimirPdf(
        bytes: pdfBytes,
        empresa: empresa,
        name: 'Pedido_Termico_${pedido.numero}',
        termico: true,
        context: context,
        forcarPreview: forcarPreview,
      );
    } catch (e) {
      throw Exception('Erro ao imprimir PDF térmico: $e');
    }
  }

  /// Abre pré-visualização em diálogo para os documentos de pedido
  static Future<void> _showPdfPreview(BuildContext context, Uint8List pdfBytes, String fileName, {bool isTermico = false}) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.9,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              AppBar(
                title: const Text('Pré-visualização de Impressão', style: TextStyle(color: Colors.white)),
                backgroundColor: const Color(0xFF1E1E2E),
                iconTheme: const IconThemeData(color: Colors.white),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) async => pdfBytes,
                  pdfFileName: '$fileName.pdf',
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  allowPrinting: true,
                  allowSharing: true,
                  maxPageWidth: isTermico ? 320.0 : null,
                  dpi: isTermico ? 200.0 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Gera um único PDF contínuo contendo a via térmica de VÁRIOS pedidos
  static Future<Uint8List> gerarLotePDFTermico({
    required List<Pedido> pedidos,
    required Empresa empresa,
  }) async {
    try {
      final pdf = pw.Document();
      final formatoData = DateFormat('dd/MM/yyyy HH:mm');
      final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

      // Configurações de impressão
      final config = empresa.configuracoes ?? {};
      final double larguraBobina = config['comandaLarguraBobina']?.toDouble() ?? 80.0;
      final double margemEsq = config['comandaMargemEsq']?.toDouble() ?? config['comandaMargemH']?.toDouble() ?? 10.0;
      final double margemDir = config['comandaMargemDir']?.toDouble() ?? config['comandaMargemH']?.toDouble() ?? 15.0;
      final double fontSizeTitulo = config['comandaFonteTitulo']?.toDouble() ?? 10.5;
      final double fontSizeCorpo = config['comandaFonteCorpo']?.toDouble() ?? 7.8;
      final bool usarNegrito = config['comandaNegrito'] ?? true;

      final double pageWidth = (larguraBobina - 2) * 2.83465;

      for (final pedido in pedidos) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(pageWidth, 2000), // Altura grande para não quebrar no meio
            margin: pw.EdgeInsets.only(
              left: margemEsq,
              right: margemDir,
              top: 2,
              bottom: 10,
            ),
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildCabecalhoTermico(empresa, fontSizeTitulo, fontSizeCorpo, usarNegrito),
                  pw.SizedBox(height: 2),
                  _buildDadosPedidoTermico(pedido, formatoData, fontSizeCorpo, usarNegrito),
                  pw.SizedBox(height: 2),
                  _buildClienteTermico(pedido, fontSizeCorpo),
                  pw.SizedBox(height: 3),
                  _buildItensTermico(pedido, formatoMoeda, fontSizeCorpo, usarNegrito),
                  _buildTotalTermico(pedido, formatoMoeda, fontSizeCorpo),
                  _buildPagamentosTermico(pedido, formatoMoeda, fontSizeCorpo),
                  _buildObservacoesTermico(pedido, fontSizeCorpo),
                  _buildRodapeTermico(empresa, formatoData, fontSizeCorpo),
                  pw.SizedBox(height: 20), // Espaço para corte entre cupons
                  pw.Text('- - - - - - CORTE AQUI - - - - - -', style: pw.TextStyle(fontSize: fontSizeCorpo - 1)),
                ],
              );
            },
          ),
        );
      }

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar PDF térmico em lote: $e');
    }
  }

  /// Imprime as vias térmicas de VÁRIOS pedidos de uma só vez (sem abrir várias janelas de print)
  static Future<void> imprimirLotePedidosTermico({
    required List<Pedido> pedidos,
    required Empresa empresa,
    BuildContext? context,
  }) async {
    if (pedidos.isEmpty) return;
    
    try {
      final pdfBytes = await gerarLotePDFTermico(pedidos: pedidos, empresa: empresa);
      if (context != null) {
        await _showPdfPreview(context, pdfBytes, 'Lote_Pedidos_Termico');
      } else {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: 'Lote_Pedidos_Termico',
        );
      }
    } catch (e) {
      throw Exception('Erro ao imprimir lote de pedidos térmico: $e');
    }
  }

  /// Gera PDF de Romaneio em formato térmico (80mm) - Sem valores financeiros
  static Future<Uint8List> gerarRomaneioPDFTermico({
    required Pedido pedido,
    required Empresa empresa,
  }) async {
    try {
      final pdf = pw.Document();
      final formatoData = DateFormat('dd/MM/yyyy HH:mm');

      // Configurações de impressão dinâmicas
      final config = empresa.configuracoes ?? {};
      final double larguraBobina = config['comandaLarguraBobina']?.toDouble() ?? 80.0;
      final double margemEsq = config['comandaMargemEsq']?.toDouble() ?? config['comandaMargemH']?.toDouble() ?? 10.0;
      final double margemDir = config['comandaMargemDir']?.toDouble() ?? config['comandaMargemH']?.toDouble() ?? 15.0;
      final double fontSizeTitulo = config['comandaFonteTitulo']?.toDouble() ?? 10.5;
      final double fontSizeCorpo = config['comandaFonteCorpo']?.toDouble() ?? 7.8;
      final bool usarNegrito = config['comandaNegrito'] ?? true;

      // Cálculo de largura útil (mm -> pt) com compensação de segurança
      final double pageWidth = (larguraBobina - 2) * 2.83465;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidth, 2000),
          margin: pw.EdgeInsets.only(
            left: margemEsq,
            right: margemDir,
            top: 2,
            bottom: 2,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'ROMANEIO / SEPARAÇÃO',
                  style: pw.TextStyle(
                    fontSize: fontSizeTitulo + 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 5),
                _buildCabecalhoTermico(empresa, fontSizeTitulo, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 2),
                _buildDadosPedidoTermico(pedido, formatoData, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 2),
                _buildClienteTermico(pedido, fontSizeCorpo),
                pw.SizedBox(height: 3),
                _buildItensRomaneioTermico(pedido, fontSizeCorpo, usarNegrito),
                if (pedido.observacoes != null && pedido.observacoes!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  _buildObservacoesTermico(pedido, fontSizeCorpo),
                ],
                pw.SizedBox(height: 4),
                pw.Text(
                  '--------------------------------',
                  style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar PDF de romaneio térmico: $e');
    }
  }

  /// Constrói itens do romaneio térmico (sem preços)
  static pw.Widget _buildItensRomaneioTermico(Pedido pedido, double fontSizeCorpo, bool usarNegrito) {
    final todosItens = <_ItemLinha>[];
    
    // Adicionar produtos
    for (final produto in pedido.produtos) {
      todosItens.add(_ItemLinha(
        nome: produto.nome,
        quantidade: produto.quantidade,
        precoUnitario: 0,
        tipo: 'Produto',
        adicionais: produto.adicionais,
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ITENS PARA SEPARAÇÃO',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo + 1,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        ...todosItens.map((item) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2.5),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 30,
                  child: pw.Text(
                    '${item.quantidade}x',
                    style: pw.TextStyle(
                      fontSize: fontSizeCorpo + 1,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        item.nome,
                        style: pw.TextStyle(
                          fontSize: fontSizeCorpo + 1,
                          fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                        ),
                      ),
                      if (item.adicionais.isNotEmpty)
                        ...item.adicionais.map((a) => pw.Text(
                          '+ ${a.nome}',
                          style: pw.TextStyle(fontSize: fontSizeCorpo, color: PdfColors.grey700),
                        )),
                    ],
                  ),
                ),
                pw.Container(
                  width: 20,
                  height: 15,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1),
                  ),
                )
              ],
            ),
          );
        }),
        pw.SizedBox(height: 3),
        pw.Divider(thickness: 0.5),
      ],
    );
  }

  /// Imprime o PDF do romaneio em formato térmico (80mm)
  static Future<void> imprimirRomaneioTermico({
    required Pedido pedido,
    required Empresa empresa,
    BuildContext? context,
  }) async {
    try {
      final pdfBytes = await gerarRomaneioPDFTermico(pedido: pedido, empresa: empresa);
      if (context != null) {
        await _showPdfPreview(context, pdfBytes, 'Romaneio_Pedido_${pedido.numero}');
      } else {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: 'Romaneio_Pedido_${pedido.numero}',
        );
      }
    } catch (e) {
      throw Exception('Erro ao imprimir Romaneio térmico: $e');
    }
  }

  /// Gera PDF do Romaneio Completo com Vários Pedidos (Térmico ou A4)
  static Future<void> imprimirDocumentoRomaneio({
    required Romaneio romaneio,
    required List<Pedido> pedidos,
    required Empresa empresa,
    BuildContext? context,
  }) async {
    try {
      final pdf = pw.Document();
      final formatoData = DateFormat('dd/MM/yyyy HH:mm');
      final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

      // Vamos gerar em A4 para caber mais informações num formato de prancheta
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('ROMANEIO DE ENTREGA #${romaneio.numero}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Empresa: ${empresa.nomeFantasia}', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Data: ${formatoData.format(romaneio.dataCriacao)}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Status: ${romaneio.status.name.toUpperCase()}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Motorista: ${romaneio.motoristaNome ?? "Não informado"}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('Veículo/Placa: ${romaneio.veiculoPlaca ?? "Não informado"}'),
                    pw.Text('Total de Entregas: ${pedidos.length}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text('ROTA DE ENTREGA', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.SizedBox(height: 10),
              ...pedidos.asMap().entries.map((entry) {
                final index = entry.key;
                final pedido = entry.value;
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 15),
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: index % 2 == 0 ? PdfColors.grey100 : PdfColors.white,
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('${index + 1}. Pedido: ${pedido.numero}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text('Valor a Receber: ${formatoMoeda.format(pedido.totalGeral - pedido.totalRecebido)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text('Cliente: ${pedido.clienteNome ?? "Não informado"} (Tel: ${pedido.clienteTelefone ?? "N/A"})'),
                      pw.Text('Endereço: ${pedido.clienteEndereco ?? "Não informado"}'),
                      if (pedido.produtos.isNotEmpty) ...[
                        pw.SizedBox(height: 5),
                        pw.Text('Produtos:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        ...pedido.produtos.map((p) => pw.Text('- ${p.quantidade}x ${p.nome}', style: const pw.TextStyle(fontSize: 9))),
                      ],
                      if (pedido.observacoes != null && pedido.observacoes!.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 5),
                          child: pw.Text('Obs do Pedido: ${pedido.observacoes}', style: pw.TextStyle(color: PdfColors.grey700, fontSize: 9, fontStyle: pw.FontStyle.italic)),
                        ),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        children: [
                          pw.Container(width: 15, height: 15, decoration: pw.BoxDecoration(border: pw.Border.all())),
                          pw.SizedBox(width: 5),
                          pw.Text('Entregue'),
                          pw.SizedBox(width: 20),
                          pw.Container(width: 15, height: 15, decoration: pw.BoxDecoration(border: pw.Border.all())),
                          pw.SizedBox(width: 5),
                          pw.Text('Ausente/Falha'),
                          pw.Spacer(),
                          pw.Text('Assinatura: ___________________________'),
                        ]
                      ),
                    ],
                  ),
                );
              }).toList(),
              if (romaneio.observacoes != null && romaneio.observacoes!.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text('Observações do Romaneio:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(romaneio.observacoes!),
              ],
            ];
          },
        ),
      );

      final pdfBytes = await pdf.save();
      if (context != null) {
        await _showPdfPreview(context, pdfBytes, 'Romaneio_Geral_${romaneio.numero}');
      } else {
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name: 'Romaneio_Geral_${romaneio.numero}',
        );
      }
    } catch (e) {
      throw Exception('Erro ao imprimir Romaneio Geral: $e');
    }
  }

  /// Gera PDF do extrato de fiado para uma lista de pedidos/vendas selecionadas
  static Future<Uint8List> gerarExtratoFiadoPDF({
    required List<Pedido> pedidos,
    required String clienteNome,
    required String? clienteCodigo,
    required Empresa empresa,
    bool mostrarItens = false,
  }) async {
    try {
      final pdf = pw.Document();
      final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      final formatoData = DateFormat('dd/MM/yyyy HH:mm');
      
      // Calcular valores gerais
      double totalGeral = 0.0;
      double totalPago = 0.0;
      double totalPendente = 0.0;
      
      for (final p in pedidos) {
        final valorCredito = p.pagamentos
            .where((pag) => 
                pag.tipo == TipoPagamento.fiado || 
                pag.tipoOriginal == TipoPagamento.fiado ||
                pag.tipo == TipoPagamento.crediario ||
                pag.tipoOriginal == TipoPagamento.crediario)
            .fold(0.0, (sum, pag) => sum + pag.valor);
        
        final valorPago = p.pagamentos
            .where((pag) => pag.recebido && 
                (pag.tipo == TipoPagamento.fiado || 
                 pag.tipoOriginal == TipoPagamento.fiado ||
                 pag.tipo == TipoPagamento.crediario ||
                 pag.tipoOriginal == TipoPagamento.crediario))
            .fold(0.0, (sum, pag) => sum + pag.valor);
            
        totalGeral += valorCredito;
        totalPago += valorPago;
        totalPendente += (valorCredito - valorPago);
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          header: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      (empresa.nomeFantasia ?? empresa.razaoSocial).toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
                    ),
                    pw.Text(
                      'EXTRATO DE FIADO / CREDIÁRIO',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Divider(thickness: 1, color: PdfColors.grey300),
                pw.SizedBox(height: 10),
              ],
            );
          },
          build: (pw.Context context) {
            return [
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text(
                          'Cliente: ',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                        ),
                        pw.Text(
                          clienteNome,
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                        if (clienteCodigo != null && clienteCodigo.isNotEmpty) ...[
                          pw.Text(
                            '   |   Cód. Cliente: ',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                          ),
                          pw.Text(
                            clienteCodigo,
                            style: const pw.TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Total Geral: ${formatoMoeda.format(totalGeral)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                        ),
                        pw.Text(
                          'Total Pago: ${formatoMoeda.format(totalPago)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.green700),
                        ),
                        pw.Text(
                          'Saldo Devedor: ${formatoMoeda.format(totalPendente)}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.red700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),
              pw.Text(
                'Detalhamento das Vendas Selecionadas:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blueGrey800),
              ),
              pw.SizedBox(height: 8),
              
              pw.TableHelper.fromTextArray(
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(width: 0.5, color: PdfColors.grey300),
                  bottom: pw.BorderSide(width: 1, color: PdfColors.grey400),
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headers: <dynamic>['Venda/Pedido', 'Data', 'Status', 'Valor Original', 'Valor Pago', 'Restante'],
                data: pedidos.expand((p) {
                  final isCancelado = p.status.toLowerCase() == 'cancelado';
                  
                  final valorCredito = p.pagamentos
                      .where((pag) => 
                          pag.tipo == TipoPagamento.fiado || 
                          pag.tipoOriginal == TipoPagamento.fiado ||
                          pag.tipo == TipoPagamento.crediario ||
                          pag.tipoOriginal == TipoPagamento.crediario)
                      .fold(0.0, (sum, pag) => sum + pag.valor);
                  
                  final valorPago = p.pagamentos
                      .where((pag) => pag.recebido && 
                          (pag.tipo == TipoPagamento.fiado || 
                           pag.tipoOriginal == TipoPagamento.fiado ||
                           pag.tipo == TipoPagamento.crediario ||
                           pag.tipoOriginal == TipoPagamento.crediario))
                      .fold(0.0, (sum, pag) => sum + pag.valor);
                      
                  final valorPendente = valorCredito - valorPago;
                  
                  List<List<dynamic>> rows = [];
                  rows.add([
                    p.numero,
                    formatoData.format(p.dataPedido),
                    isCancelado ? 'Cancelado' : 'Ativo',
                    formatoMoeda.format(valorCredito),
                    formatoMoeda.format(valorPago),
                    formatoMoeda.format(valorPendente),
                  ]);

                  if (mostrarItens && (p.produtos.isNotEmpty || p.servicos.isNotEmpty)) {
                    for (final item in p.produtos) {
                      final itemTotal = (item.preco * item.quantidade) + item.adicionais.fold(0.0, (s, a) => s + (a.preco * item.quantidade));
                      rows.add([
                        '   - ${item.quantidade}x ${item.nome}',
                        '',
                        '',
                        '',
                        '',
                        formatoMoeda.format(itemTotal)
                      ]);
                    }
                    for (final servico in p.servicos) {
                      final servTotal = servico.valor + servico.valorAdicional + (servico.valorTaxiDog ?? 0.0);
                      rows.add([
                        '   - Serviço: ${servico.descricao}',
                        '',
                        '',
                        '',
                        '',
                        formatoMoeda.format(servTotal)
                      ]);
                    }
                  }
                  return rows;
                }).toList(),
              ),
            ];
          },
          footer: (pw.Context context) {
            return pw.Column(
              children: [
                pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Emitido em: ${formatoData.format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      'Página ${context.pageNumber} de ${context.pagesCount}',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar extrato do fiado: $e');
    }
  }

  /// Imprime o extrato de fiado
  static Future<void> imprimirExtratoFiado({
    required BuildContext context,
    required List<Pedido> pedidos,
    required String clienteNome,
    required String? clienteCodigo,
    required Empresa empresa,
    bool mostrarItens = false,
  }) async {
    try {
      final pdfBytes = await gerarExtratoFiadoPDF(
        pedidos: pedidos,
        clienteNome: clienteNome,
        clienteCodigo: clienteCodigo,
        empresa: empresa,
        mostrarItens: mostrarItens,
      );
      await _showPdfPreview(context, pdfBytes, 'Extrato_Fiado_${clienteNome.replaceAll(' ', '_')}');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar extrato: $e')),
      );
    }
  }

  /// Gera PDF do extrato de fiado em formato térmico (80mm)
  static Future<Uint8List> gerarExtratoFiadoPDFTermico({
    required List<Pedido> pedidos,
    required String clienteNome,
    required String? clienteCodigo,
    required Empresa empresa,
    bool mostrarItens = false,
  }) async {
    try {
      final pdf = pw.Document();
      final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      final formatoData = DateFormat('dd/MM/yyyy HH:mm');

      // Configurações de impressão dinâmicas
      final config = empresa.configuracoes ?? {};
      final double larguraBobina = config['comandaLarguraBobina']?.toDouble() ?? 80.0;
      final double margemEsq = config['comandaMargemEsq']?.toDouble() ?? config['comandaMargemH']?.toDouble() ?? 10.0;
      final double margemDir = config['comandaMargemDir']?.toDouble() ?? config['comandaMargemH']?.toDouble() ?? 15.0;
      final double margemV = config['comandaMargemV']?.toDouble() ?? 10.0;
      final double fontSizeTitulo = config['comandaFonteTitulo']?.toDouble() ?? 10.5;
      final double fontSizeCorpo = config['comandaFonteCorpo']?.toDouble() ?? 7.8;
      final bool usarNegrito = config['comandaNegrito'] ?? true;

      final double pageWidth = (larguraBobina - 2) * 2.83465;

      // Calcular altura estimada
      double alturaEstimada = 180.0;
      alturaEstimada += 50.0; // Totais
      alturaEstimada += pedidos.length * 30.0; // Itens
      alturaEstimada += 40.0; // Rodapé

      // Calcular valores gerais
      double totalGeral = 0.0;
      double totalPago = 0.0;
      double totalPendente = 0.0;

      for (final p in pedidos) {
        final valorCredito = p.pagamentos
            .where((pag) => 
                pag.tipo == TipoPagamento.fiado || 
                pag.tipoOriginal == TipoPagamento.fiado ||
                pag.tipo == TipoPagamento.crediario ||
                pag.tipoOriginal == TipoPagamento.crediario)
            .fold(0.0, (sum, pag) => sum + pag.valor);
        
        final valorPago = p.pagamentos
            .where((pag) => pag.recebido && 
                (pag.tipo == TipoPagamento.fiado || 
                 pag.tipoOriginal == TipoPagamento.fiado ||
                 pag.tipo == TipoPagamento.crediario ||
                 pag.tipoOriginal == TipoPagamento.crediario))
            .fold(0.0, (sum, pag) => sum + pag.valor);
            
        totalGeral += valorCredito;
        totalPago += valorPago;
        totalPendente += (valorCredito - valorPago);
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidth, alturaEstimada, marginAll: 0),
          margin: pw.EdgeInsets.only(
            left: margemEsq * 2.83465,
            right: margemDir * 2.83465,
            top: margemV * 2.83465,
            bottom: margemV * 2.83465,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    (empresa.nomeFantasia ?? empresa.razaoSocial).toUpperCase(),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSizeTitulo),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Center(
                  child: pw.Text(
                    'EXTRATO DE FIADO / CREDIÁRIO',
                    style: pw.TextStyle(fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: fontSizeCorpo),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 1, color: PdfColors.black),
                
                // Cliente
                pw.Text(
                  'Cliente: $clienteNome',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSizeCorpo),
                ),
                if (clienteCodigo != null && clienteCodigo.isNotEmpty)
                  pw.Text(
                    'Cód: $clienteCodigo',
                    style: pw.TextStyle(fontSize: fontSizeCorpo),
                  ),
                
                pw.Divider(thickness: 0.5, color: PdfColors.black),
                
                // Totais
                pw.Text(
                  'Total Geral: ${formatoMoeda.format(totalGeral)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSizeCorpo),
                ),
                pw.Text(
                  'Total Pago: ${formatoMoeda.format(totalPago)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSizeCorpo),
                ),
                pw.Text(
                  'Saldo Devedor: ${formatoMoeda.format(totalPendente)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSizeTitulo),
                ),

                pw.Divider(thickness: 0.5, color: PdfColors.black),
                
                // Lista de pedidos
                pw.Text(
                  'Detalhamento das Vendas:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSizeCorpo),
                ),
                pw.SizedBox(height: 3),
                
                ...pedidos.map((p) {
                  final isCancelado = p.status.toLowerCase() == 'cancelado';
                  
                  final valorCredito = p.pagamentos
                      .where((pag) => 
                          pag.tipo == TipoPagamento.fiado || 
                          pag.tipoOriginal == TipoPagamento.fiado ||
                          pag.tipo == TipoPagamento.crediario ||
                          pag.tipoOriginal == TipoPagamento.crediario)
                      .fold(0.0, (sum, pag) => sum + pag.valor);
                  
                  final valorPago = p.pagamentos
                      .where((pag) => pag.recebido && 
                          (pag.tipo == TipoPagamento.fiado || 
                           pag.tipoOriginal == TipoPagamento.fiado ||
                           pag.tipo == TipoPagamento.crediario ||
                           pag.tipoOriginal == TipoPagamento.crediario))
                      .fold(0.0, (sum, pag) => sum + pag.valor);
                      
                  final valorPendente = valorCredito - valorPago;
                  
                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Ped: ${p.numero}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSizeCorpo)),
                            pw.Text(formatoData.format(p.dataPedido), style: pw.TextStyle(fontSize: fontSizeCorpo - 1)),
                          ],
                        ),
                        if (isCancelado) 
                          pw.Text('Status: Cancelado', style: pw.TextStyle(fontSize: fontSizeCorpo - 1)),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Original: ${formatoMoeda.format(valorCredito)}', style: pw.TextStyle(fontSize: fontSizeCorpo - 1)),
                            pw.Text('Pago: ${formatoMoeda.format(valorPago)}', style: pw.TextStyle(fontSize: fontSizeCorpo - 1)),
                          ],
                        ),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            pw.Text('Restante: ${formatoMoeda.format(valorPendente)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSizeCorpo - 1)),
                          ],
                        ),
                        if (mostrarItens && (p.produtos.isNotEmpty || p.servicos.isNotEmpty)) ...[
                          pw.SizedBox(height: 3),
                          ...p.produtos.map((it) {
                            final itTotal = (it.preco * it.quantidade) + it.adicionais.fold(0.0, (s, a) => s + (a.preco * it.quantidade));
                            return pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Expanded(child: pw.Text('- ${it.quantidade}x ${it.nome}', style: pw.TextStyle(fontSize: fontSizeCorpo - 2, color: PdfColors.grey800))),
                                pw.Text(formatoMoeda.format(itTotal), style: pw.TextStyle(fontSize: fontSizeCorpo - 2, color: PdfColors.grey800)),
                              ],
                            );
                          }).toList(),
                          ...p.servicos.map((sv) {
                            final svTotal = sv.valor + sv.valorAdicional + (sv.valorTaxiDog ?? 0.0);
                            return pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Expanded(child: pw.Text('- Serviço: ${sv.descricao}', style: pw.TextStyle(fontSize: fontSizeCorpo - 2, color: PdfColors.grey800))),
                                pw.Text(formatoMoeda.format(svTotal), style: pw.TextStyle(fontSize: fontSizeCorpo - 2, color: PdfColors.grey800)),
                              ],
                            );
                          }).toList(),
                          pw.SizedBox(height: 2),
                        ],
                        pw.Divider(thickness: 0.2, color: PdfColors.grey700),
                      ],
                    ),
                  );
                }).toList(),

                pw.Spacer(),
                
                // Footer
                pw.Center(
                  child: pw.Text(
                    'Emitido em: ${formatoData.format(DateTime.now())}',
                    style: pw.TextStyle(fontSize: fontSizeCorpo - 2),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar extrato do fiado térmico: $e');
    }
  }

  /// Imprime o extrato de fiado térmico
  static Future<void> imprimirExtratoFiadoTermico({
    required BuildContext context,
    required List<Pedido> pedidos,
    required String clienteNome,
    required String? clienteCodigo,
    required Empresa empresa,
    bool mostrarItens = false,
  }) async {
    try {
      final pdfBytes = await gerarExtratoFiadoPDFTermico(
        pedidos: pedidos,
        clienteNome: clienteNome,
        clienteCodigo: clienteCodigo,
        empresa: empresa,
        mostrarItens: mostrarItens,
      );
      await _showPdfPreview(context, pdfBytes, 'Extrato_Fiado_Termico_${clienteNome.replaceAll(' ', '_')}');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar extrato térmico: $e')),
      );
    }
  }

  static Future<Uint8List> gerarReciboPagamentoFiadoPDFTermico({
    required String clienteNome,
    required double valorPago,
    required double acrescimo,
    required double desconto,
    required double saldoRestante,
    required Empresa empresa,
  }) async {
    final pdf = pw.Document();

    // 80mm = ~226 pontos
    const double pageWidth = 226.0;
    
    // Altura estimada
    final double alturaEstimada = 400.0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, alturaEstimada, marginAll: 10),
        build: (pw.Context context) {
          final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
          final dataHora = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Cabeçalho da Empresa
              pw.Text(
                empresa.nomeExibicao.toUpperCase(),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              if (empresa.cnpj != null && empresa.cnpj!.isNotEmpty)
                pw.Text(
                  'CNPJ: ${empresa.cnpj}',
                  style: const pw.TextStyle(fontSize: 10),
                  textAlign: pw.TextAlign.center,
                ),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 5),
              
              // Título
              pw.Text(
                'RECIBO DE PAGAMENTO',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 10),

              // Cliente
              pw.Container(
                width: double.infinity,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('CLIENTE: $clienteNome', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('DATA: $dataHora', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 10),

              // Valores
              pw.Container(
                width: double.infinity,
                child: pw.Column(
                  children: [
                    if (acrescimo > 0)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Acréscimo:', style: const pw.TextStyle(fontSize: 10)),
                          pw.Text(formatoMoeda.format(acrescimo), style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    if (desconto > 0)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Desconto:', style: const pw.TextStyle(fontSize: 10)),
                          pw.Text(formatoMoeda.format(desconto), style: const pw.TextStyle(fontSize: 10)),
                        ],
                      ),
                    if (acrescimo > 0 || desconto > 0)
                      pw.SizedBox(height: 5),
                      
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('VALOR PAGO:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Text(formatoMoeda.format(valorPago), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('SALDO RESTANTE:', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(formatoMoeda.format(saldoRestante), style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 15),
              pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 15),

              // Assinatura
              pw.Text(
                'Assinatura do Cliente',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                width: 150,
                height: 1,
                color: PdfColors.black,
              ),
              
              pw.SizedBox(height: 20),
              pw.Text(
                'Obrigado pela preferência!',
                style: const pw.TextStyle(fontSize: 10),
                textAlign: pw.TextAlign.center,
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> imprimirReciboPagamentoFiadoTermico({
    required BuildContext context,
    required String clienteNome,
    required double valorPago,
    required double acrescimo,
    required double desconto,
    required double saldoRestante,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarReciboPagamentoFiadoPDFTermico(
        clienteNome: clienteNome,
        valorPago: valorPago,
        acrescimo: acrescimo,
        desconto: desconto,
        saldoRestante: saldoRestante,
        empresa: empresa,
      );
      await _showPdfPreview(context, pdfBytes, 'Recibo_Pagamento_${clienteNome.replaceAll(' ', '_')}');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao gerar recibo térmico: $e')),
      );
    }
  }
}

/// Classe auxiliar para itens
class _ItemLinha {
  final String nome;
  final double quantidade;
  final double precoUnitario;
  final String tipo;
  final String? observacao;
  final List<AdicionalProduto> adicionais;

  _ItemLinha({
    required this.nome,
    required this.quantidade,
    required this.precoUnitario,
    required this.tipo,
    this.observacao,
    this.adicionais = const [],
  });
}



