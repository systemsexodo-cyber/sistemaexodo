import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/nfce.dart';
import '../models/empresa.dart';
import '../models/venda_balcao.dart';
import '../models/forma_pagamento.dart';
import '../models/produto.dart';

class FiscalPDFService {
  static Future<Uint8List> gerarRelatorioMensal({
    required Empresa empresa,
    required DateTime mesRef,
    required List<NFCe> nfces,
    required List<VendaBalcao> vendas,
    List<Produto> produtos = const [],
  }) async {
    final pdf = pw.Document();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    final mesStr = DateFormat('MM/yyyy').format(mesRef);

    // 1. Identificar vendas com nota fiscal (Fiscal) vs sem nota (Não Fiscal)
    final Set<String> idsVendasFiscais = {};
    for (final n in nfces) {
      if (n.status == 'autorizada' || n.status == 'sucesso') {
        if (n.vendaId != null) idsVendasFiscais.add(n.vendaId!);
      }
    }

    final Map<String, double> pgtoFiscal = {};
    final Map<String, double> pgtoNaoFiscal = {};
    double totalFiscal = 0.0;
    double totalNaoFiscal = 0.0;
    int totalVendasComNota = 0;
    int totalVendasSemNota = 0;

    for (final v in vendas) {
      final isFiscal = idsVendasFiscais.contains(v.id) ||
          nfces.any((n) => (n.status == 'autorizada' || n.status == 'sucesso') && n.vendaNumero == v.numero);

      // Se a venda tem múltiplas formas de pagamento (split), somar cada forma individualmente
      final pagsVenda = v.pagamentos;
      final Map<String, double> valoresPorForma = {};
      if (pagsVenda.isNotEmpty) {
        for (final p in pagsVenda.where((p) => p.recebido)) {
          valoresPorForma[p.tipo.nome] =
              (valoresPorForma[p.tipo.nome] ?? 0.0) + p.valor;
        }
      } else {
        valoresPorForma[v.tipoPagamento.nome] = v.valorTotal;
      }

      for (final entry in valoresPorForma.entries) {
        final nomePgto = entry.key;
        final valor = entry.value;

        if (isFiscal) {
          pgtoFiscal[nomePgto] = (pgtoFiscal[nomePgto] ?? 0.0) + valor;
          totalFiscal += valor;
        } else {
          pgtoNaoFiscal[nomePgto] = (pgtoNaoFiscal[nomePgto] ?? 0.0) + valor;
          totalNaoFiscal += valor;
        }
      }
      // Contador de vendas: incrementa UMA vez por venda (não por forma de pagamento)
      if (isFiscal) {
        totalVendasComNota++;
      } else {
        totalVendasSemNota++;
      }
    }

    // 2. Agrupar por CFOP e Imposto para notas autorizadas
    final Map<String, double> resumoCFOP = {};
    final Map<String, double> resumoImposto = {};

    for (final n in nfces) {
      if (n.status != 'autorizada' && n.status != 'sucesso') continue;
      
      List<NFCeItem> itensParaProcessar = n.itens;
      if (itensParaProcessar.isEmpty && vendas.isNotEmpty) {
        VendaBalcao? vendaObj;
        try {
          vendaObj = vendas.firstWhere((v) => v.id == n.vendaId || v.numero == n.vendaNumero);
        } catch (_) {}
        
        if (vendaObj != null) {
          itensParaProcessar = vendaObj.itens.map((vItem) {
            Produto? prod;
            try {
              prod = produtos.firstWhere((p) => p.id == vItem.id);
            } catch (_) {}

            final isSimplesNacional = empresa.crt == 1 || empresa.crt == null;
            final defaultCst = isSimplesNacional ? null : '00';
            final defaultCsosn = isSimplesNacional ? '102' : null;

            return NFCeItem(
              produtoId: vItem.id,
              codigo: prod?.codigo ?? vItem.id,
              descricao: vItem.nome,
              ncm: prod?.ncm ?? '00000000',
              cfop: '5102',
              unidade: prod?.unidade ?? 'UN',
              quantidade: vItem.quantidade,
              valorUnitario: vItem.precoUnitario,
              valorTotal: vItem.precoUnitario * vItem.quantidade,
              csosn: prod?.csosn ?? defaultCsosn,
              icmsCst: prod?.icmsCst ?? defaultCst,
            );
          }).toList();
        }
      }

      if (itensParaProcessar.isEmpty) {
        final isSimplesNacional = empresa.crt == 1 || empresa.crt == null;
        itensParaProcessar = [
          NFCeItem(
            produtoId: 'GENERICO',
            codigo: '0',
            descricao: 'VENDA FISCAL NFC-E',
            ncm: '00000000',
            cfop: '5102',
            unidade: 'UN',
            quantidade: 1.0,
            valorUnitario: n.valorTotal,
            valorTotal: n.valorTotal,
            csosn: isSimplesNacional ? '102' : null,
            icmsCst: isSimplesNacional ? null : '00',
          )
        ];
      }

      for (final item in itensParaProcessar) {
        final cfop = item.cfop;
        final imposto = item.csosn ?? item.icmsCst ?? 'N/D';
        
        resumoCFOP[cfop] = (resumoCFOP[cfop] ?? 0.0) + item.valorTotal;
        resumoImposto[imposto] = (resumoImposto[imposto] ?? 0.0) + item.valorTotal;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildHeader(empresa, mesStr),
          pw.SizedBox(height: 15),

          // Painel Resumo Geral
          pw.Text('RESUMO DO FATURAMENTO', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                _buildRowResumo('FATURAMENTO FISCAL (Com NFC-e)', totalVendasComNota, totalFiscal, formatoMoeda, bold: true),
                _buildRowResumo('VENDAS SEM EMISSÃO', totalVendasSemNota, totalNaoFiscal, formatoMoeda, bold: true),
                pw.Divider(color: PdfColors.grey400),
                _buildRowResumo('FATURAMENTO TOTAL', totalVendasComNota + totalVendasSemNota, totalFiscal + totalNaoFiscal, formatoMoeda, bold: true, highlight: true),
              ],
            ),
          ),
          pw.SizedBox(height: 15),

          // Meios de Pagamento
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('FISCAL POR PAGAMENTO', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    ...pgtoFiscal.entries.map((e) => _buildRowSimple(e.key, e.value, formatoMoeda)),
                    if (pgtoFiscal.isEmpty) pw.Text('Nenhuma venda fiscal.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('VENDAS SEM EMISSÃO POR PAGAMENTO', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    ...pgtoNaoFiscal.entries.map((e) => _buildRowSimple(e.key, e.value, formatoMoeda)),
                    if (pgtoNaoFiscal.isEmpty) pw.Text('Nenhuma venda sem emissão.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 15),
          pw.Divider(),

          // Resumo Tributário (CFOP/CST)
          _buildResumoTributario(resumoCFOP, resumoImposto, formatoMoeda),
          pw.SizedBox(height: 15),

          // Tabela de Documentos Fiscais
          pw.Text('HISTÓRICO DE DOCUMENTOS FISCAIS (NFC-e)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
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
        pw.Text('RELATÓRIO DE FATURAMENTO E IMPOSTOS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('Mês de Referência: $mesStr'),
        pw.Divider(),
        pw.Text('Empresa: ${empresa.razaoSocial}'),
        pw.Text('CNPJ: ${empresa.cnpj ?? "Não informado"}'),
        pw.SizedBox(height: 5),
      ],
    );
  }

  static pw.Widget _buildRowResumo(String label, int count, double total, NumberFormat fmt, {bool bold = false, bool highlight = false}) {
    final style = pw.TextStyle(
      fontSize: highlight ? 11 : 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: highlight ? PdfColors.blue900 : PdfColors.black,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Row(
            children: [
              pw.Text('($count vendas) ', style: style.copyWith(color: PdfColors.grey700)),
              pw.SizedBox(width: 15),
              pw.Text(fmt.format(total), style: style),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRowSimple(String label, double val, NumberFormat fmt) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)),
          pw.Text(fmt.format(val), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _buildResumoTributario(
    Map<String, double> resumoCFOP,
    Map<String, double> resumoImposto,
    NumberFormat formatoMoeda,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('RESUMO FISCAL (IMPOSTOS / CFOP)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 5),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Por CFOP:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  ...resumoCFOP.entries.map((e) => pw.Text('CFOP ${e.key}: ${formatoMoeda.format(e.value)}', style: const pw.TextStyle(fontSize: 8.5))),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Por CSOSN/CST:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  ...resumoImposto.entries.map((e) => pw.Text('CST/CSOSN ${e.key}: ${formatoMoeda.format(e.value)}', style: const pw.TextStyle(fontSize: 8.5))),
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
    if (nfces.isEmpty) {
      return pw.Text('Nenhuma nota fiscal emitida no período.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600));
    }
    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['Data', 'Nº', 'Série', 'Status', 'Valor Total'],
      data: nfces.map((n) => [
        formatoData.format(n.dataEmissao),
        n.numero ?? '-',
        n.serie ?? '-',
        (n.status ?? '').toUpperCase(),
        formatoMoeda.format(n.valorTotal),
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellHeight: 16,
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
