// Script temporário: gera o PDF do ticket de TESTE de produção
// (mesmo layout do ProducaoPdfService) para conferência visual.
// Executar: dart run scratch/gerar_ticket_teste.dart
import 'dart:typed_data';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

String _formatarQuantidade(double qtd) {
  if (qtd == qtd.roundToDouble()) {
    return qtd.toInt().toString();
  }
  return qtd.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

Future<void> main() async {
  final formatoData = DateFormat('dd/MM/yyyy HH:mm');

  final linhasCabecalho = <String>[
    'MESA 5',
    'Cliente: Cliente Teste',
    'Fone: (12) 99999-9999',
    'Entrega: Rua Teste, 123 - Centro',
    'Motorista: João (entregador)',
    'Previsão: 30-45 min',
  ];
  final linhaPagamento = 'PIX — PAGO\nTroco: R\$ 5.50';
  const observacoesGerais =
      'TESTE DE IMPRESSÃO — verifique se o ticket saiu correto nesta impressora.';

  final itens = [
    ('X-Burger Completo', 2.0, ['Bacon extra', 'Queijo cheddar'], <String>[], null),
    ('Batata Frita Grande', 1.0, <String>[], <String>[], 'Sem sal'),
    ('Refrigerante Lata 350ml', 1.0, <String>[], ['Coca-Cola'], null),
  ];

  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(
        80 * PdfPageFormat.mm,
        double.infinity,
        marginAll: 0,
      ),
      margin: const pw.EdgeInsets.all(8),
      build: (_) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'É O BICHO PETSHOP',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'TESTE DE PRODUÇÃO',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Nº TESTE-0001',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Data: ${formatoData.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(),
            pw.SizedBox(height: 4),
            for (final linha in linhasCabecalho)
              pw.Text(
                linha,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            pw.SizedBox(height: 2),
            pw.Text(
              linhaPagamento,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green800,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Obs: $observacoesGerais',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 4),
            pw.Divider(),
            pw.SizedBox(height: 4),
            for (var i = 0; i < itens.length; i++) ...[
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${i + 1}.',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(width: 2),
                  pw.Expanded(
                    child: pw.Text(
                      '${_formatarQuantidade(itens[i].$2)}x  ${itens[i].$1}',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (itens[i].$3.isNotEmpty)
                pw.Text('   + ${itens[i].$3.join(', ')}', style: const pw.TextStyle(fontSize: 9)),
              if (itens[i].$4.isNotEmpty)
                pw.Text('   > ${itens[i].$4.join(', ')}', style: const pw.TextStyle(fontSize: 9)),
              if (itens[i].$5 != null)
                pw.Text('   Obs: ${itens[i].$5}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
              pw.SizedBox(height: 3),
            ],
            pw.SizedBox(height: 4),
            pw.Divider(),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Text(
                'SETOR: TERMINAL (PADRÃO)',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        );
      },
    ),
  );

  final Uint8List bytes = await pdf.save();
  final out = File('scratch/ticket_producao_teste.pdf');
  await out.writeAsBytes(bytes);
  stdout.writeln('PDF gerado: ${out.absolute.path}');
  stdout.writeln('Tamanho: ${bytes.length} bytes');
}
