import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/empresa.dart';
import '../models/nfce.dart';
import 'dart:typed_data';

class FiscalPDFService {
  static Future<Uint8List> gerarRelatorioMensal({
    required Empresa empresa,
    required DateTime mesRef,
    required List<NFCe> nfces,
  }) async {
    final pdf = pw.Document();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    final mesStr = DateFormat('MM/yyyy').format(mesRef);

    // Agrupar por CFOP e CSOSN/CST
    final Map<String, double> resumoCFOP = {};
    final Map<String, double> resumoImposto = {}; // CSOSN ou CST

    for (final n in nfces) {
      if (n.status != 'autorizada' && n.status != 'sucesso') continue;
      for (final item in n.itens) {
        final cfop = item.cfop;
        final imposto = item.csosn ?? item.icmsCst ?? 'N/D';
        
        resumoCFOP[cfop] = (resumoCFOP[cfop] ?? 0) + item.valorTotal;
        resumoImposto[imposto] = (resumoImposto[imposto] ?? 0) + item.valorTotal;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(empresa, mesStr),
          pw.SizedBox(height: 20),
          _buildResumo(resumoCFOP, resumoImposto, formatoMoeda),
          pw.SizedBox(height: 20),
          _buildTableVendas(nfces, formatoMoeda, formatoData),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(Empresa empresa, String mesStr) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('RELATÓRIO FISCAL DE VENDAS (NFC-e)', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('Mês de Referência: $mesStr'),
        pw.Divider(),
        pw.Text('Empresa: ${empresa.razaoSocial}'),
        pw.Text('CNPJ: ${empresa.cnpj ?? "Não informado"}'),
        pw.SizedBox(height: 10),
      ],
    );
  }

  static pw.Widget _buildResumo(
    Map<String, double> resumoCFOP,
    Map<String, double> resumoImposto,
    NumberFormat formatoMoeda,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('RESUMO FISCAL', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Por CFOP:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ...resumoCFOP.entries.map((e) => pw.Text('CFOP ${e.key}: ${formatoMoeda.format(e.value)}')),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Por CSOSN/CST:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ...resumoImposto.entries.map((e) => pw.Text('CST/CSOSN ${e.key}: ${formatoMoeda.format(e.value)}')),
                ],
              ),
            ),
          ],
        ),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _buildTableVendas(
    List<NFCe> nfces,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Data', 'Nº', 'Série', 'Status', 'Valor Total'],
      data: nfces.map((n) => [
        formatoData.format(n.dataEmissao),
        n.numero,
        n.serie,
        (n.status ?? '').toUpperCase(),
        formatoMoeda.format(n.valorTotal),
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellHeight: 20,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.centerRight,
      },
    );
  }
}
