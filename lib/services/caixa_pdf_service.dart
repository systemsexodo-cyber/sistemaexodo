import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/caixa.dart';
import '../models/empresa.dart';
import '../models/venda_balcao.dart';
import '../models/forma_pagamento.dart';

/// Serviço para geração de PDF de fechamento de caixa inteligente
class CaixaPDFService {
  static final NumberFormat _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final DateFormat _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  /// Gera PDF térmico do fechamento de caixa
  static Future<Uint8List> gerarPDFTermico({
    required AberturaCaixa abertura,
    required FechamentoCaixa fechamento,
    required Empresa empresa,
    required List<VendaBalcao> vendas,
  }) async {
    final pdf = pw.Document();

    // Configurações de impressão dinâmicas
    final config = empresa.configuracoes ?? {};
    final double larguraBobina = config['comandaLarguraBobina']?.toDouble() ?? 80.0;
    final double margemEsq = config['comandaMargemEsq']?.toDouble() ?? 10.0;
    final double margemDir = config['comandaMargemDir']?.toDouble() ?? 15.0;
    final double margemV = config['comandaMargemV']?.toDouble() ?? 10.0;
    final double fontSizeTitulo = config['comandaFonteTitulo']?.toDouble() ?? 12.0;
    final double fontSizeCorpo = config['comandaFonteCorpo']?.toDouble() ?? 9.0;
    final bool usarNegrito = config['comandaNegrito'] ?? true;

    // Cálculo de largura útil (mm -> pt)
    final double pageWidth = (larguraBobina - 2) * 2.83465;

    // Calcular resumo por forma de pagamento
    final resumoPagamentos = <TipoPagamento, double>{};
    int totalItensVendidos = 0;
    double valorTotalItens = 0.0;

    for (final venda in vendas) {
      if (venda.cancelado) continue;
      
      // Somar itens
      for (final item in venda.itens) {
        totalItensVendidos += item.quantidade;
        valorTotalItens += item.precoUnitario * item.quantidade;
      }

      // Somar pagamentos (VendaBalcao possui apenas um tipo principal)
      final tipo = venda.tipoPagamento;
      resumoPagamentos[tipo] = (resumoPagamentos[tipo] ?? 0.0) + venda.valorTotal;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, double.infinity),
        margin: pw.EdgeInsets.only(
          left: margemEsq,
          right: margemDir,
          top: margemV,
          bottom: margemV,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Cabeçalho Empresa
              pw.Text(
                empresa.nomeExibicao.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: fontSizeTitulo,
                  fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
                textAlign: pw.TextAlign.center,
              ),
              if (empresa.cnpj != null)
                pw.Text(
                  'CNPJ: ${empresa.cnpj}',
                  style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                ),
              pw.SizedBox(height: 10),
              
              // Título do Documento
              pw.Text(
                'RESUMO DE FECHAMENTO',
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 2,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'CAIXA: ${abertura.numero}',
                style: pw.TextStyle(fontSize: fontSizeCorpo),
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 0.5),

              // Informações do Período
              _buildInfoLinha('Início:', _formatoData.format(abertura.dataAbertura), fontSizeCorpo),
              _buildInfoLinha('Fim:', _formatoData.format(fechamento.dataFechamento), fontSizeCorpo),
              if (fechamento.responsavel != null && fechamento.responsavel!.isNotEmpty)
                _buildInfoLinha('Responsável:', fechamento.responsavel!, fontSizeCorpo),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 0.5),

              // Vendas por Forma de Pagamento
              pw.SizedBox(height: 5),
              pw.Text(
                'VENDAS POR PAGAMENTO',
                style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              ...resumoPagamentos.entries.map((e) {
                return _buildValorLinha(_getNomeTipoPagamento(e.key), e.value, fontSizeCorpo);
              }),
              pw.Divider(thickness: 0.5, indent: 20, endIndent: 20),
              _buildValorLinha('TOTAL VENDAS:', resumoPagamentos.values.fold(0.0, (a, b) => a + b), fontSizeCorpo, bold: true),
              pw.SizedBox(height: 10),

              // Resumo de Itens
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 5),
              pw.Text(
                'RESUMO DE ITENS',
                style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              _buildInfoLinha('Total de Itens:', totalItensVendidos.toString(), fontSizeCorpo),
              _buildValorLinha('Valor dos Itens:', valorTotalItens, fontSizeCorpo),
              pw.SizedBox(height: 10),

              // Movimentações Operacionais (Sangrias/Suprimentos)
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 5),
              pw.Text(
                'MOVIMENTAÇÕES',
                style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              _buildValorLinha('Fundo Inicial:', abertura.valorInicial, fontSizeCorpo),
              _buildValorLinha('Total Suprimentos:', fechamento.totalSuprimentos, fontSizeCorpo),
              _buildValorLinha('Total Sangrias:', -fechamento.totalSangrias, fontSizeCorpo),
              pw.SizedBox(height: 10),

              // Reconciliação Final
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 5),
              _buildValorLinha('VALOR ESPERADO:', fechamento.valorEsperado, fontSizeCorpo, bold: true),
              _buildValorLinha('VALOR REAL:', fechamento.valorReal, fontSizeCorpo, bold: true),
              pw.SizedBox(height: 5),
              _buildValorLinha(
                'DIFERENÇA:', 
                fechamento.diferenca, 
                fontSizeCorpo + 1, 
                bold: true,
                color: fechamento.diferenca < 0 ? PdfColors.red : PdfColors.green,
              ),
              pw.SizedBox(height: 10),

              if (fechamento.observacao != null && fechamento.observacao!.isNotEmpty) ...[
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 5),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    'OBSERVAÇÕES:',
                    style: pw.TextStyle(fontSize: fontSizeCorpo - 1, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    fechamento.observacao!,
                    style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                  ),
                ),
                pw.SizedBox(height: 10),
              ],

              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 10),
              pw.Text(
                'Gerado em: ${_formatoData.format(DateTime.now())}',
                style: pw.TextStyle(fontSize: fontSizeCorpo - 2, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 20),
              pw.Text('.', style: const pw.TextStyle(color: PdfColors.white)), // Espaço extra bottom
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildInfoLinha(String label, String value, double fontSize) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: fontSize, color: PdfColors.grey800)),
          pw.Text(value, style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _buildValorLinha(String label, double valor, double fontSize, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(
            _formatoMoeda.format(valor),
            style: pw.TextStyle(
              fontSize: fontSize, 
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static String _getNomeTipoPagamento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro: return 'Dinheiro';
      case TipoPagamento.pix: return 'PIX';
      case TipoPagamento.cartaoCredito: return 'Cartão Crédito';
      case TipoPagamento.cartaoDebito: return 'Cartão Débito';
      case TipoPagamento.crediario: return 'Crediário';
      case TipoPagamento.boleto: return 'Boleto';
      case TipoPagamento.fiado: return 'Fiado';
      case TipoPagamento.outro: return 'Outro';
      case TipoPagamento.alimentacao: return 'Ticket/Aliment.';
    }
  }
}
