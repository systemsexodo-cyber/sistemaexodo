import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/venda_balcao.dart';
import '../models/empresa.dart';
import '../models/forma_pagamento.dart';
import 'impressao_service.dart';

/// Serviço para geração de PDF de venda
class VendaPDFService {
  /// Gera PDF da venda
  static Future<Uint8List> gerarPDF({
    required VendaBalcao venda,
    required Empresa empresa,
  }) async {
    try {
      final pdf = pw.Document();
      final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      final formatoData = DateFormat('dd/MM/yyyy HH:mm');
      final mostrarEnderecoCupom = empresa.configuracoes?['mostrarEnderecoCupom'] != false;

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
                _buildDadosVenda(venda, formatoData),
                pw.SizedBox(height: 20),
                _buildCliente(venda),
                pw.SizedBox(height: 20),
                _buildItens(venda, formatoMoeda),
                pw.SizedBox(height: 20),
                _buildDescontos(venda, formatoMoeda),
                pw.SizedBox(height: 20),
                _buildTotal(venda, formatoMoeda),
                pw.SizedBox(height: 20),
                _buildPagamento(venda, formatoMoeda),
                if (venda.observacoes != null && venda.observacoes!.isNotEmpty) ...[
                  pw.SizedBox(height: 20),
                  _buildObservacoes(venda),
                ],
                if (venda.deliveryInfo != null) ...[
                  pw.SizedBox(height: 20),
                  _buildDelivery(venda, mostrarEndereco: mostrarEnderecoCupom),
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
      throw Exception('Erro ao gerar PDF da venda: $e');
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
            'CUPOM NÃO FISCAL',
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

  /// Constrói dados da venda
  static pw.Widget _buildDadosVenda(VendaBalcao venda, DateFormat formatoData) {
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
                'VENDA',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Nº: ${venda.numero}',
                style: const pw.TextStyle(fontSize: 12),
              ),
              if (venda.senha != null && venda.senha!.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Text(
                  'Senha: ${venda.senha}',
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
                formatoData.format(venda.dataVenda),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Constrói informações do cliente
  static pw.Widget _buildCliente(VendaBalcao venda) {
    if (venda.clienteNome == null || venda.clienteNome!.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Row(
          children: [
            pw.Text(
              'Cliente: ',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'CONSUMIDOR FINAL',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'Cliente: ',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  venda.clienteNome!,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
          if (venda.clienteTelefone != null && venda.clienteTelefone!.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Row(
              children: [
                pw.Text(
                  'Telefone: ',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  venda.clienteTelefone!,
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Formata a quantidade para exibição amigável
  static String _formatarQtdItem(double qty) {
    if (qty == qty.roundToDouble()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  /// Constrói itens da venda
  static pw.Widget _buildItens(VendaBalcao venda, NumberFormat formatoMoeda) {
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
          columnWidths: const {
            0: pw.FlexColumnWidth(3.5),
            1: pw.FlexColumnWidth(1.0),
            2: pw.FlexColumnWidth(1.5),
            3: pw.FlexColumnWidth(1.5),
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
            ...venda.itens.map((item) {
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
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (item.adicionais.isNotEmpty)
                          ...item.adicionais.map((a) => pw.Text(
                            '+ ${a.nome} (${formatoMoeda.format(a.preco)})',
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
                          )),
                        if (item.opcoesCombo.isNotEmpty)
                          ...item.opcoesCombo.map((c) => pw.Text(
                            '• ${c.nome}',
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
                          )),
                        if (item.observacao != null && item.observacao!.trim().isNotEmpty)
                          pw.Text(
                            '* Obs: ${item.observacao}',
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                          ),
                        if (item.descontoPromocionalPercent != null)
                          pw.Text(
                            '${item.descontoPromocionalPercent!.toStringAsFixed(0)}% promocional · -${formatoMoeda.format(item.descontoPromocionalValor!)}',
                            style: pw.TextStyle(fontSize: 8, color: PdfColors.orange),
                          ),
                        if (item.descontoTabelaUnitario > 0)
                          pw.Text(
                            'Desconto tabela: -${formatoMoeda.format(item.descontoTabelaUnitario * item.quantidade)}',
                            style: pw.TextStyle(fontSize: 8, color: PdfColors.green700),
                          ),
                      ],
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      _formatarQtdItem(item.quantidade),
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

  /// Constrói seção de descontos
  static pw.Widget _buildDescontos(VendaBalcao venda, NumberFormat formatoMoeda) {
    // Calcular subtotal sem desconto (usa o preço de tabela quando houver
    // desconto do perfil de preços aplicado no PDV)
    final subtotalSemDesconto = venda.itens.fold(
      0.0,
      (sum, item) =>
          sum + ((item.precoTabela ?? item.precoUnitario) * item.quantidade),
    );
    
    // Calcular desconto total
    final descontoTotal = subtotalSemDesconto - venda.valorTotal;
    
    // Só mostrar se houver desconto
    if (descontoTotal <= 0) {
      return pw.SizedBox.shrink();
    }
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Subtotal:',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Text(
                formatoMoeda.format(subtotalSemDesconto),
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Desconto:',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green700,
                ),
              ),
              pw.Text(
                '- ${formatoMoeda.format(descontoTotal)}',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Constrói totais
  static pw.Widget _buildTotal(VendaBalcao venda, NumberFormat formatoMoeda) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'TOTAL DA VENDA:',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            formatoMoeda.format(venda.valorTotal),
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói formas de pagamento
  static pw.Widget _buildPagamento(VendaBalcao venda, NumberFormat formatoMoeda) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'FORMA DE PAGAMENTO',
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
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    _getNomeTipoPagamento(venda.tipoPagamento),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Text(
                    formatoMoeda.format(venda.valorTotal),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (venda.valorRecebido != null && venda.valorRecebido! > 0) ...[
                pw.SizedBox(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Valor Recebido:',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      formatoMoeda.format(venda.valorRecebido!),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ],
              if (venda.troco != null && venda.troco! > 0) ...[
                pw.SizedBox(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Troco:',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      formatoMoeda.format(venda.troco!),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green700,
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
  static pw.Widget _buildObservacoes(VendaBalcao venda) {
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
            venda.observacoes!,
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  /// Constrói bloco de entrega (A4) com endereço destacado para o entregador
  static pw.Widget _buildDelivery(VendaBalcao venda, {bool mostrarEndereco = true}) {
    if (venda.deliveryInfo == null) return pw.SizedBox.shrink();
    final info = venda.deliveryInfo!;
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
                  'CLIENTE: ${venda.clienteNome ?? "CONSUMIDOR FINAL"}',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                if (venda.clienteTelefone != null && venda.clienteTelefone!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'TEL: ${venda.clienteTelefone!}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                ],
                if (mostrarEndereco) ...[
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
                      DateFormat('HH:mm').format(venda.dataVenda),
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
                if (info.taxaEntrega > 0) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Taxa de Entrega: R\$ ${info.taxaEntrega.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
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

  /// Gera PDF do cupom não fiscal em formato térmico (80mm)
  static Future<Uint8List> gerarPDFTermico({
    required VendaBalcao venda,
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
      final bool mostrarEnderecoCupom = config['mostrarEnderecoCupom'] != false;

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
      
      // Cliente
      alturaEstimada += 60.0;
      if (venda.clienteNome?.isNotEmpty == true && venda.clienteNome != "CONSUMIDOR FINAL") {
        alturaEstimada += 20.0;
      }
      
      // Itens
      if (venda.itens != null) {
        for (final item in venda.itens) {
          alturaEstimada += 25.0; // Nome e total
          if (item.adicionais != null && item.adicionais.isNotEmpty) {
            alturaEstimada += item.adicionais.length * 15.0;
          }
          if (item.descontoPromocionalPercent != null ||
              item.descontoTabelaUnitario > 0) {
            alturaEstimada += 15.0; // Linha extra de desconto
          }
        }
      }
      
      // Totais e pagamentos
      alturaEstimada += 120.0;
      
      // Observações e rodapé
      if (venda.observacoes?.isNotEmpty == true) {
        alturaEstimada += 40.0;
      }
      // Bloco de entrega destacado (faixa + caixa com cliente/telefone/endereço + hora/previsão)
      if (venda.deliveryInfo != null) {
        alturaEstimada += 220.0;
        if (venda.deliveryInfo!.observacoes?.isNotEmpty == true) {
          alturaEstimada += 25.0;
        }
        if (venda.deliveryInfo!.previsaoEntrega?.trim().isNotEmpty == true) {
          alturaEstimada += 25.0;
        }
        if (venda.deliveryInfo!.valorParaTroco > 0) {
          alturaEstimada += 35.0;
        }
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
                _buildDadosVendaTermico(venda, formatoData, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 2),
                _buildClienteTermico(venda, fontSizeCorpo, mostrarEndereco: mostrarEnderecoCupom),
                pw.SizedBox(height: 3),
                _buildItensTermico(venda, formatoMoeda, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 2),
                _buildDescontosTermico(venda, formatoMoeda, fontSizeCorpo),
                pw.SizedBox(height: 2),
                _buildTotalTermico(venda, formatoMoeda, fontSizeCorpo),
                pw.SizedBox(height: 2),
                _buildPagamentoTermico(venda, formatoMoeda, fontSizeCorpo),
                if (venda.observacoes != null && venda.observacoes!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  _buildObservacoesTermico(venda, fontSizeCorpo),
                ],
                if (venda.deliveryInfo != null) ...[
                  pw.SizedBox(height: 2),
                  _buildDeliveryTermico(venda, fontSizeCorpo),
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
      throw Exception('Erro ao gerar cupom não fiscal térmico: $e');
    }
  }

  /// Constrói cabeçalho do cupom não fiscal térmico
  static pw.Widget _buildCabecalhoTermico(Empresa empresa, double fontSizeTitulo, double fontSizeCorpo, bool usarNegrito) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'CUPOM NÃO FISCAL',
          style: pw.TextStyle(
            fontSize: fontSizeTitulo,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1),
        pw.SizedBox(height: 5),
        pw.Text(
          empresa.nomeExibicao,
          style: pw.TextStyle(
            fontSize: fontSizeTitulo + 2,
            fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (empresa.cnpj != null) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            'CNPJ: ${_formatarCNPJ(empresa.cnpj!)}',
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            textAlign: pw.TextAlign.center,
          ),
        ],
        if (empresa.endereco != null && empresa.endereco!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            empresa.endereco!,
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            textAlign: pw.TextAlign.center,
          ),
        ],
        if (empresa.numero != null && empresa.numero!.isNotEmpty) ...[
          pw.Text(
            'Nº ${empresa.numero}',
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            textAlign: pw.TextAlign.center,
          ),
        ],
        if (empresa.bairro != null && empresa.bairro!.isNotEmpty) ...[
          pw.Text(
            empresa.bairro!,
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            textAlign: pw.TextAlign.center,
          ),
        ],
        if (empresa.cidade != null && empresa.cidade!.isNotEmpty) ...[
          pw.Text(
            empresa.estado != null && empresa.estado!.isNotEmpty
                ? '${empresa.cidade} - ${empresa.estado}'
                : empresa.cidade!,
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            textAlign: pw.TextAlign.center,
          ),
        ],
        if (empresa.telefone != null && empresa.telefone!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'Tel: ${empresa.telefone}',
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1),
      ],
    );
  }

  /// Constrói dados da venda no cupom não fiscal térmico
  static pw.Widget _buildDadosVendaTermico(VendaBalcao venda, DateFormat formatoData, double fontSizeCorpo, bool usarNegrito) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          'VENDA',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo + 2,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Nº: ${venda.numero}',
          style: pw.TextStyle(fontSize: fontSizeCorpo + 1),
          textAlign: pw.TextAlign.center,
        ),
        if (venda.senha != null && venda.senha!.isNotEmpty) ...[
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
              'SENHA: ${venda.senha}',
              style: pw.TextStyle(fontSize: fontSizeCorpo + 6, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 4),
        ],
        pw.SizedBox(height: 3),
        pw.Text(
          formatoData.format(venda.dataVenda),
          style: pw.TextStyle(fontSize: fontSizeCorpo),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1),
      ],
    );
  }

  /// Constrói informações do cliente térmico (com endereço de delivery destacado para o entregador)
  static pw.Widget _buildClienteTermico(VendaBalcao venda, double fontSizeCorpo, {bool mostrarEndereco = true}) {
    final info = venda.deliveryInfo;
    final String? previsao = info?.previsaoEntrega?.trim();
    final bool temPrevisao = previsao != null && previsao.isNotEmpty;
    final DateTime dataPedido = venda.dataVenda;

    if (info != null) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
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
                  'CLIENTE: ${venda.clienteNome ?? "CONSUMIDOR FINAL"}',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo + 2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (venda.clienteTelefone != null && venda.clienteTelefone!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'TEL: ${venda.clienteTelefone!}',
                    style: pw.TextStyle(
                      fontSize: fontSizeCorpo + 2,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
                if (mostrarEndereco) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'ENDEREÇO DE ENTREGA',
                    style: pw.TextStyle(
                      fontSize: fontSizeCorpo + 3,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '${info.logradouro}, ${info.numero}',
                    style: pw.TextStyle(
                      fontSize: fontSizeCorpo + 3,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
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
                // Horário do pedido e previsão de entrega para o entregador (sempre visíveis)
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
                          previsao,
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
          pw.SizedBox(height: 4),
          pw.Divider(thickness: 1),
        ],
      );
    }

    // Sem entrega: cliente simples (como antes)
    if (venda.clienteNome == null || venda.clienteNome!.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Cliente: CONSUMIDOR FINAL',
            style: pw.TextStyle(fontSize: fontSizeCorpo),
          ),
          pw.SizedBox(height: 5),
          pw.Divider(thickness: 1),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Cliente: ${venda.clienteNome!}',
          style: pw.TextStyle(fontSize: fontSizeCorpo),
        ),
        if (venda.clienteTelefone != null && venda.clienteTelefone!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'Tel: ${venda.clienteTelefone!}',
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
          ),
        ],
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1),
      ],
    );
  }

  /// Constrói itens da venda térmico
  static pw.Widget _buildItensTermico(VendaBalcao venda, NumberFormat formatoMoeda, double fontSizeCorpo, bool usarNegrito) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ITENS',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo + 1,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        ...venda.itens.map((item) {
          final subtotal = item.precoUnitario * item.quantidade;
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 1.5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  item.nome,
                  style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal),
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${item.quantidade}x ${formatoMoeda.format(item.precoUnitario)}',
                      style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                    ),
                    pw.Text(
                      formatoMoeda.format(subtotal),
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo,
                        fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (item.descontoPromocionalPercent != null)
                  pw.Text(
                    '${item.descontoPromocionalPercent!.toStringAsFixed(0)}% promocional · -${formatoMoeda.format(item.descontoPromocionalValor!)}',
                    style: pw.TextStyle(fontSize: fontSizeCorpo - 1, color: PdfColors.orange),
                  ),
                if (item.descontoTabelaUnitario > 0)
                  pw.Text(
                    'Desconto tabela: -${formatoMoeda.format(item.descontoTabelaUnitario * item.quantidade)}',
                    style: pw.TextStyle(fontSize: fontSizeCorpo - 1, color: PdfColors.green700),
                  ),
              ],
            ),
          );
        }),
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1),
      ],
    );
  }

  /// Constrói seção de descontos térmico
  static pw.Widget _buildDescontosTermico(VendaBalcao venda, NumberFormat formatoMoeda, double fontSizeCorpo) {
    // Calcular subtotal sem desconto (usa o preço de tabela quando houver
    // desconto do perfil de preços aplicado no PDV)
    final subtotalSemDesconto = venda.itens.fold(
      0.0,
      (sum, item) =>
          sum + ((item.precoTabela ?? item.precoUnitario) * item.quantidade),
    );
    
    // Calcular desconto total
    final descontoTotal = subtotalSemDesconto - venda.valorTotal;
    
    // Só mostrar se houver desconto
    if (descontoTotal <= 0) {
      return pw.SizedBox.shrink();
    }
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Subtotal:',
              style: pw.TextStyle(fontSize: fontSizeCorpo),
            ),
            pw.Text(
              formatoMoeda.format(subtotalSemDesconto),
              style: pw.TextStyle(fontSize: fontSizeCorpo),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Desconto:',
              style: pw.TextStyle(
                fontSize: fontSizeCorpo + 1,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              '- ${formatoMoeda.format(descontoTotal)}',
              style: pw.TextStyle(
                fontSize: fontSizeCorpo + 1,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1),
      ],
    );
  }

  /// Constrói totais térmico
  static pw.Widget _buildTotalTermico(VendaBalcao venda, NumberFormat formatoMoeda, double fontSizeCorpo) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'TOTAL',
            style: pw.TextStyle(
              fontSize: fontSizeCorpo + 3,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            formatoMoeda.format(venda.valorTotal),
            style: pw.TextStyle(
              fontSize: fontSizeCorpo + 4,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói formas de pagamento térmico
  static pw.Widget _buildPagamentoTermico(VendaBalcao venda, NumberFormat formatoMoeda, double fontSizeCorpo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 5),
        pw.Text(
          'PAGAMENTO',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo + 1,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                _getNomeTipoPagamento(venda.tipoPagamento),
                style: pw.TextStyle(fontSize: fontSizeCorpo),
              ),
            ),
            pw.Text(
              formatoMoeda.format(venda.valorTotal),
              style: pw.TextStyle(
                fontSize: fontSizeCorpo + 1,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        if (venda.valorRecebido != null && venda.valorRecebido! > 0) ...[
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Recebido:',
                style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
              ),
              pw.Text(
                formatoMoeda.format(venda.valorRecebido!),
                style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
              ),
            ],
          ),
        ],
        if (venda.troco != null && venda.troco! > 0) ...[
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Troco:',
                style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
              ),
              pw.Text(
                formatoMoeda.format(venda.troco!),
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
      ],
    );
  }

  /// Constrói observações térmico
  static pw.Widget _buildObservacoesTermico(VendaBalcao venda, double fontSizeCorpo) {
    if (venda.observacoes == null || venda.observacoes!.trim().isEmpty) return pw.SizedBox.shrink();
    
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
          venda.observacoes!,
          style: pw.TextStyle(fontSize: fontSizeCorpo),
        ),
        pw.SizedBox(height: 2),
      ],
    );
  }

  /// Constrói seção de entrega térmico
  /// Constrói seção de troco da entrega térmico (o endereço destacado vai no bloco do cliente)
  static pw.Widget _buildDeliveryTermico(VendaBalcao venda, double fontSizeCorpo) {
    final info = venda.deliveryInfo!;
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (info.valorParaTroco > 0) ...[
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TROCO PARA:',
                style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                formatoMoeda.format(info.valorParaTroco),
                style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'VALOR DO TROCO:',
                style: pw.TextStyle(fontSize: fontSizeCorpo + 1, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                formatoMoeda.format(info.valorParaTroco - venda.valorTotal),
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

  /// Constrói rodapé térmico
  static pw.Widget _buildRodapeTermico(Empresa empresa, DateFormat formatoData, double fontSizeCorpo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(height: 10),
        pw.Text(
          '--------------------------------',
          style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Obrigado pela preferência!',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo + 1,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 3),
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

  /// Imprime o PDF da venda (A4)
  static Future<void> imprimirPDF({
    required VendaBalcao venda,
    required Empresa empresa,
    BuildContext? context,
    bool forcarPreview = false,
  }) async {
    try {
      final pdfBytes = await gerarPDF(venda: venda, empresa: empresa);
      await ImpressaoService.imprimirPdf(
        bytes: pdfBytes,
        empresa: empresa,
        name: 'Venda_${venda.numero}',
        termico: false,
        context: context,
        forcarPreview: forcarPreview,
      );
    } catch (e) {
      throw Exception('Erro ao imprimir PDF: $e');
    }
  }

  /// Imprime o cupom não fiscal em formato térmico (80mm) — preferência: direto na impressora
  static Future<void> imprimirPDFTermico({
    required VendaBalcao venda,
    required Empresa empresa,
    BuildContext? context,
    bool forcarPreview = false,
  }) async {
    try {
      final pdfBytes = await gerarPDFTermico(venda: venda, empresa: empresa);
      await ImpressaoService.imprimirPdf(
        bytes: pdfBytes,
        empresa: empresa,
        name: 'Cupom_Nao_Fiscal_${venda.numero}',
        termico: true,
        context: context,
        forcarPreview: forcarPreview,
      );
    } catch (e) {
      throw Exception('Erro ao imprimir cupom não fiscal térmico: $e');
    }
  }

  /// Compartilha o PDF da venda
  static Future<void> compartilharPDF({
    required VendaBalcao venda,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDF(venda: venda, empresa: empresa);
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'venda_${venda.numero}.pdf',
      );
    } catch (e) {
      throw Exception('Erro ao compartilhar PDF: $e');
    }
  }
}

