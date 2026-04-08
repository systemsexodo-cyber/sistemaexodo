import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/venda_balcao.dart';
import '../models/empresa.dart';
import '../models/forma_pagamento.dart';
import '../models/delivery_info.dart';

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
                  _buildDelivery(venda),
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
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(1),
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
            ...venda.itens.map((item) {
              final subtotal = item.precoUnitario * item.quantidade;
              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      item.nome,
                      style: const pw.TextStyle(fontSize: 9),
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

  /// Constrói seção de descontos
  static pw.Widget _buildDescontos(VendaBalcao venda, NumberFormat formatoMoeda) {
    // Calcular subtotal sem desconto
    final subtotalSemDesconto = venda.itens.fold(
      0.0,
      (sum, item) => sum + (item.precoUnitario * item.quantidade),
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
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey700, width: 2),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(
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
            formatoMoeda.format(venda.valorTotal),
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
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

  /// Constrói seção de entrega
  static pw.Widget _buildDelivery(VendaBalcao venda) {
    if (venda.deliveryInfo == null) return pw.SizedBox.shrink();
    final info = venda.deliveryInfo!;
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.orange, width: 1.5),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'INFORMAÇÕES DE ENTREGA',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.orange,
                ),
              ),
              pw.Text(
                info.status.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.orange,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Endereço: ${info.logradouro}, ${info.numero}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Bairro: ${info.bairro}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            'Cidade/UF: ${info.cidade} - ${info.uf}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          if (info.cep != null && info.cep!.isNotEmpty)
            pw.Text(
              'CEP: ${info.cep}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          if (info.taxaEntrega > 0) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              'Taxa de Entrega: R\$ ${info.taxaEntrega.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green700),
            ),
          ],
          if (info.motoristaNome != null && info.motoristaNome!.isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              'Motorista: ${info.motoristaNome}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
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
                _buildCabecalhoTermico(empresa, fontSizeTitulo, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 2),
                _buildDadosVendaTermico(venda, formatoData, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 2),
                _buildClienteTermico(venda, fontSizeCorpo),
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

  /// Constrói informações do cliente térmico
  static pw.Widget _buildClienteTermico(VendaBalcao venda, double fontSizeCorpo) {
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
    // Calcular subtotal sem desconto
    final subtotalSemDesconto = venda.itens.fold(
      0.0,
      (sum, item) => sum + (item.precoUnitario * item.quantidade),
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
  static pw.Widget _buildDeliveryTermico(VendaBalcao venda, double fontSizeCorpo) {
    final info = venda.deliveryInfo!;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'ENTREGA',
              style: pw.TextStyle(
                fontSize: fontSizeCorpo + 1,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              info.status.toUpperCase(),
              style: pw.TextStyle(
                fontSize: fontSizeCorpo,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Endereço: ${info.logradouro}, ${info.numero}',
          style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Bairro: ${info.bairro}',
          style: pw.TextStyle(fontSize: fontSizeCorpo),
        ),
        pw.Text(
          'Cidade/UF: ${info.cidade} - ${info.uf}',
          style: pw.TextStyle(fontSize: fontSizeCorpo),
        ),
        if (info.taxaEntrega > 0) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            'Taxa: R\$ ${info.taxaEntrega.toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
          ),
        ],
        if (info.motoristaNome != null && info.motoristaNome!.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            'Motorista: ${info.motoristaNome}',
            style: pw.TextStyle(fontSize: fontSizeCorpo),
          ),
        ],
        pw.SizedBox(height: 5),
        pw.Divider(thickness: 1),
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

  /// Imprime o PDF da venda
  static Future<void> imprimirPDF({
    required VendaBalcao venda,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDF(venda: venda, empresa: empresa);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } catch (e) {
      throw Exception('Erro ao imprimir PDF: $e');
    }
  }

  /// Imprime o cupom não fiscal em formato térmico (80mm)
  static Future<void> imprimirPDFTermico({
    required VendaBalcao venda,
    required Empresa empresa,
  }) async {
    try {
      final pdfBytes = await gerarPDFTermico(venda: venda, empresa: empresa);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
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

