import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/empresa.dart';
import '../models/pedido_compra.dart';
import '../utils/units.dart' as units;

/// Gera o PDF e o texto de compartilhamento dos pedidos de compra salvos.
///
/// O pedido que chega aqui é sempre o pedido persistido (tem número, status e
/// quantidades recebidas), diferente do antigo PDF avulso do relatório.
class PedidoCompraPdfService {
  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  static final DateFormat _dataHora = DateFormat('dd/MM/yyyy HH:mm');
  static final DateFormat _data = DateFormat('dd/MM/yyyy');

  static Future<Uint8List> gerarPdf({
    required PedidoCompra pedido,
    Empresa? empresa,
  }) async {
    final documento = pw.Document();
    final agora = DateTime.now();

    documento.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _cabecalho(pedido, empresa),
        footer: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Divider(color: PdfColors.grey400),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Sistema Éxodo - Gestão Inteligente',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  'Gerado em ${_dataHora.format(agora)}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ],
        ),
        build: (context) => [
          _resumo(pedido),
          pw.SizedBox(height: 14),
          _itens(pedido),
          pw.SizedBox(height: 14),
          _totais(pedido),
          if ((pedido.observacao ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _observacao(pedido),
          ],
          pw.SizedBox(height: 32),
          _assinaturas(),
        ],
      ),
    );

    return documento.save();
  }

  /// Abre a janela de impressão do sistema com o PDF do pedido.
  static Future<void> imprimir({
    required PedidoCompra pedido,
    Empresa? empresa,
  }) async {
    final bytes = await gerarPdf(pedido: pedido, empresa: empresa);
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name:
          'pedido_compra_${pedido.numero.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_')}',
    );
  }

  /// Texto para copiar e enviar por WhatsApp/e-mail.
  static String textoParaCompartilhar(PedidoCompra pedido) {
    final buffer = StringBuffer()
      ..writeln('*PEDIDO DE COMPRA ${pedido.numero}*')
      ..writeln('Fornecedor: ${pedido.fornecedorNome}')
      ..writeln('Data: ${_data.format(pedido.dataCriacao)}')
      ..writeln('Situação: ${pedido.statusRotulo}');
    if (pedido.previsaoEntrega != null) {
      buffer.writeln(
        'Previsão de entrega: ${_data.format(pedido.previsaoEntrega!)}',
      );
    }
    buffer
      ..writeln()
      ..writeln('*ITENS*');
    for (final item in pedido.itens) {
      buffer.writeln(
        '• ${item.produtoNome}: '
        '${units.formatarNumero(item.quantidade)} ${item.unidade} '
        'x ${_moeda.format(item.precoCusto)} '
        '= ${_moeda.format(item.valorTotal)}',
      );
    }
    buffer
      ..writeln()
      ..writeln('*TOTAL: ${_moeda.format(pedido.valorTotal)}*');
    if ((pedido.observacao ?? '').trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Observação: ${pedido.observacao!.trim()}');
    }
    return buffer.toString();
  }

  // ==================== Blocos do PDF ====================

  static pw.Widget _cabecalho(PedidoCompra pedido, Empresa? empresa) {
    final nomeEmpresa = (empresa?.nomeExibicao ?? '').trim();
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey900,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'PEDIDO DE COMPRA',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (nomeEmpresa.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    nomeEmpresa,
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
                if ((empresa?.cnpj ?? '').trim().isNotEmpty)
                  pw.Text(
                    'CNPJ: ${empresa!.cnpj}',
                    style: const pw.TextStyle(
                      color: PdfColors.grey300,
                      fontSize: 8,
                    ),
                  ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                pedido.numero,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                pedido.statusRotulo.toUpperCase(),
                style: const pw.TextStyle(
                  color: PdfColors.grey300,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _resumo(PedidoCompra pedido) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              _campo('Fornecedor', pedido.fornecedorNome, flex: 3),
              _campo('Pedido em', _data.format(pedido.dataCriacao), flex: 2),
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Row(
            children: [
              _campo(
                'Previsão de entrega',
                pedido.previsaoEntrega == null
                    ? '-'
                    : _data.format(pedido.previsaoEntrega!),
                flex: 2,
              ),
              _campo(
                'Estoque de destino',
                (pedido.estoqueDestinoNome ?? '').trim().isEmpty
                    ? 'Estoque principal'
                    : pedido.estoqueDestinoNome!,
                flex: 2,
              ),
              _campo(
                'Comprador',
                (pedido.usuario ?? '').trim().isEmpty ? '-' : pedido.usuario!,
                flex: 2,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _campo(String rotulo, String valor, {int flex = 1}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            rotulo.toUpperCase(),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            valor,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _itens(PedidoCompra pedido) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      headers: [
        'Produto',
        'Código',
        'Un.',
        'Qtd.',
        'Recebida',
        'Custo unit.',
        'Total',
      ],
      data: pedido.itens
          .map(
            (item) => [
              item.produtoNome,
              (item.codigo ?? '').trim().isEmpty ? '-' : item.codigo!,
              item.unidade,
              units.formatarNumero(item.quantidade),
              units.formatarNumero(item.quantidadeRecebida),
              _moeda.format(item.precoCusto),
              _moeda.format(item.valorTotal),
            ],
          )
          .toList(),
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(1.4),
        2: const pw.FlexColumnWidth(0.8),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1),
        5: const pw.FlexColumnWidth(1.4),
        6: const pw.FlexColumnWidth(1.5),
      },
    );
  }

  static pw.Widget _totais(PedidoCompra pedido) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Container(
          width: 230,
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            children: [
              _linhaTotal(
                'Quantidade pedida',
                units.formatarNumero(pedido.quantidadeTotal),
              ),
              _linhaTotal(
                'Quantidade recebida',
                units.formatarNumero(pedido.quantidadeRecebida),
              ),
              pw.Divider(color: PdfColors.grey500),
              _linhaTotal(
                'TOTAL DO PEDIDO',
                _moeda.format(pedido.valorTotal),
                destaque: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _linhaTotal(
    String rotulo,
    String valor, {
    bool destaque = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            rotulo,
            style: pw.TextStyle(
              fontSize: destaque ? 9 : 8,
              fontWeight: destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: destaque ? 11 : 8,
              fontWeight: pw.FontWeight.bold,
              color: destaque ? PdfColors.blueGrey900 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _observacao(PedidoCompra pedido) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'OBSERVAÇÃO',
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            pedido.observacao!.trim(),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _assinaturas() {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Container(height: 1, color: PdfColors.grey600),
              pw.SizedBox(height: 3),
              pw.Text(
                'Comprador',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 40),
        pw.Expanded(
          child: pw.Column(
            children: [
              pw.Container(height: 1, color: PdfColors.grey600),
              pw.SizedBox(height: 3),
              pw.Text(
                'Fornecedor',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
