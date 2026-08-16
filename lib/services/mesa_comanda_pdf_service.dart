import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/mesa_comanda.dart';
import '../models/empresa.dart';
import '../models/conta_pagar.dart';
import '../services/impressao_service.dart';

/// Serviço para geração de PDF térmico (80mm) de Mesa/Comanda
class MesaComandaPdfService {
  /// Gera PDF do fechamento de conta em formato térmico (80mm)
  static Future<Uint8List> gerarPDFTermico({
    required MesaComanda mesaComanda,
    required Empresa empresa,
    List<MesaComanda>? comandasVinculadas,
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
      final double fontSizeTitulo = config['comandaFonteTitulo']?.toDouble() ?? 14.0;
      final double fontSizeCorpo = config['comandaFonteCorpo']?.toDouble() ?? 9.0;
      final double fontSizeStatus = config['comandaFonteStatus']?.toDouble() ?? 8.0;
      final bool usarNegrito = config['comandaNegrito'] ?? true;

      // Cálculo de largura útil (mm -> pt) com compensação de segurança
      final double pageWidth = (larguraBobina - 2) * 2.83465; // Desconto de 2mm para segurança

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidth, 2000), // Usando altura grande para permitir rolo contínuo
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
                _buildCabecalhoTermico(empresa, fontSizeTitulo, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 8),
                _buildDadosMesaComandaTermico(mesaComanda, formatoData, fontSizeCorpo, fontSizeStatus, usarNegrito),
                pw.SizedBox(height: 8),
                _buildClienteTermico(mesaComanda, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 8),
                _buildItensTermico(mesaComanda, formatoMoeda, fontSizeCorpo, usarNegrito),
                // Itens das comandas vinculadas
                if (comandasVinculadas != null && comandasVinculadas.isNotEmpty)
                  ...comandasVinculadas.map((comanda) => pw.Column(
                    children: [
                      pw.SizedBox(height: 8),
                      _buildSeparadorComanda(comanda, fontSizeCorpo, usarNegrito),
                      pw.SizedBox(height: 4),
                      _buildItensTermico(comanda, formatoMoeda, fontSizeCorpo, usarNegrito),
                    ],
                  )),
                pw.SizedBox(height: 8),
                _buildTotalTermico(mesaComanda, comandasVinculadas, formatoMoeda, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 8),
                _buildPagamentosTermico(mesaComanda, comandasVinculadas, formatoMoeda, formatoData, fontSizeCorpo, usarNegrito),
                pw.SizedBox(height: 8),
                _buildResumoTermico(mesaComanda, comandasVinculadas, formatoMoeda, fontSizeCorpo, usarNegrito),
                if (mesaComanda.observacao != null && mesaComanda.observacao!.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  _buildObservacoesTermico(mesaComanda, fontSizeCorpo, usarNegrito),
                ],
                pw.SizedBox(height: 8),
                _buildRodapeTermico(empresa, formatoData, fontSizeCorpo, usarNegrito),
              ],
            );
          },
        ),
      );

      return await pdf.save();
    } catch (e) {
      throw Exception('Erro ao gerar PDF térmico da mesa/comanda: $e');
    }
  }

  /// Constrói cabeçalho do recibo térmico
  static pw.Widget _buildCabecalhoTermico(Empresa empresa, double fontSizeTitulo, double fontSizeCorpo, bool usarNegrito) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          empresa.nomeFantasia ?? empresa.razaoSocial,
          style: pw.TextStyle(
            fontSize: fontSizeTitulo,
            fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
          textAlign: pw.TextAlign.center,
        ),
        if (empresa.cnpj != null && empresa.cnpj!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'CNPJ: ${_formatarCpfCnpj(empresa.cnpj!)}',
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
        if (empresa.telefone != null && empresa.telefone!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'Tel: ${empresa.telefone!}',
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 4),
        pw.Divider(),
        pw.SizedBox(height: 4),
        pw.Text(
          'FECHAMENTO DE CONTA',
          style: pw.TextStyle(
            fontSize: fontSizeTitulo - 2,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  /// Constrói dados da mesa/comanda
  static pw.Widget _buildDadosMesaComandaTermico(
    MesaComanda mesaComanda,
    DateFormat formatoData,
    double fontSizeCorpo,
    double fontSizeStatus,
    bool usarNegrito,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                '${mesaComanda.tipo == TipoControle.mesa ? "MESA" : "COMANDA"}: ${mesaComanda.numero}',
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 1,
                  fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.SizedBox(width: 4),
            pw.Text(
              'Status: ${mesaComanda.status}',
              style: pw.TextStyle(
                fontSize: fontSizeStatus,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Abertura: ${formatoData.format(mesaComanda.dataAbertura)}',
          style: pw.TextStyle(fontSize: fontSizeCorpo),
        ),
        if (mesaComanda.usuarioCriou != null && mesaComanda.usuarioCriou!.isNotEmpty)
          pw.Text(
            'Aberto por: ${mesaComanda.usuarioCriou}',
            style: pw.TextStyle(fontSize: fontSizeCorpo),
          ),
        if (mesaComanda.dataFechamento != null)
          pw.Text(
            'Fechamento: ${formatoData.format(mesaComanda.dataFechamento!)}',
            style: pw.TextStyle(fontSize: fontSizeCorpo),
          ),
      ],
    );
  }

  /// Constrói dados do cliente
  static pw.Widget _buildClienteTermico(MesaComanda mesaComanda, double fontSizeCorpo, bool usarNegrito) {
    if (mesaComanda.clienteNome == null || mesaComanda.clienteNome!.isEmpty) {
      return pw.SizedBox.shrink();
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CLIENTE',
            style: pw.TextStyle(
              fontSize: fontSizeCorpo,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            mesaComanda.clienteNome!,
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
          ),
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

  /// Constrói lista de itens
  static pw.Widget _buildItensTermico(
    MesaComanda mesaComanda,
    NumberFormat formatoMoeda,
    double fontSizeCorpo,
    bool usarNegrito,
  ) {
    if (mesaComanda.itens.isEmpty) {
      return pw.Text(
        'Nenhum item lançado',
        style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
        textAlign: pw.TextAlign.center,
      );
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
        ...mesaComanda.itens.map((item) {
          final indexStr = (itemIndex++).toString().padLeft(2, '0');
          final itemTotal = item.subtotal; // Subtotal inclui adicionais
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
                        '$qtdFormatted UN  x  ${formatoMoeda.format(item.preco)}',
                        style: pw.TextStyle(
                          fontSize: fontSizeCorpo,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Text(
                      formatoMoeda.format(itemTotal),
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

  /// Constrói separador de comanda
  static pw.Widget _buildSeparadorComanda(MesaComanda comanda, double fontSizeCorpo, bool usarNegrito) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey, width: 1),
          bottom: pw.BorderSide(color: PdfColors.grey, width: 1),
        ),
      ),
      child: pw.Text(
        'COMANDA: ${comanda.numero}',
        style: pw.TextStyle(
          fontSize: fontSizeCorpo,
          fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Constrói totais
  static pw.Widget _buildTotalTermico(
    MesaComanda mesaComanda,
    List<MesaComanda>? comandasVinculadas,
    NumberFormat formatoMoeda,
    double fontSizeCorpo,
    bool usarNegrito,
  ) {
    // Calcular subtotal dos itens (sem couvert e garçom)
    double subtotalItensMesa = mesaComanda.itens
        .where((item) => item.status != StatusItem.cancelado)
        .fold(0.0, (sum, item) => sum + item.subtotal);
    
    // Valor do couvert
    double valorCouvertMesa = mesaComanda.valorCouvertCalculado;
    
    // Valor do garçom (Taxa de serviço)
    double valorGarcomMesa = mesaComanda.valorTaxaServicoCalculado;
    
    double totalMesa = mesaComanda.totalCalculado;
    double totalComandas = 0.0;
    double subtotalItensComandas = 0.0;
    double valorCouvertComandas = 0.0;
    double valorGarcomComandas = 0.0;
    
    if (comandasVinculadas != null) {
      for (final comanda in comandasVinculadas) {
        totalComandas += comanda.totalCalculado;
        subtotalItensComandas += comanda.itens
            .where((item) => item.status != StatusItem.cancelado)
            .fold(0.0, (sum, item) => sum + item.subtotal);
        valorCouvertComandas += comanda.valorCouvertCalculado;
        valorGarcomComandas += comanda.valorTaxaServicoCalculado;
      }
    }
    
    final subtotalItensGeral = subtotalItensMesa + subtotalItensComandas;
    final valorCouvertGeral = valorCouvertMesa + valorCouvertComandas;
    final valorGarcomGeral = valorGarcomMesa + valorGarcomComandas;
    final totalGeral = totalMesa + totalComandas;

    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Subtotal dos itens
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Subtotal Itens:',
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo,
                  fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
              pw.Text(
                formatoMoeda.format(subtotalItensGeral),
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo,
                  fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ],
          ),
          // Couvert
          if (valorCouvertGeral > 0) ...[
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Couvert Artístico:',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo,
                    fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
                pw.Text(
                  formatoMoeda.format(valorCouvertGeral),
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo,
                    fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
              ],
            ),
            // Detalhes do couvert
            if (mesaComanda.quantidadePessoasCouvert != null && mesaComanda.valorCouvertPorPessoa != null) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8),
                child: pw.Text(
                  '${mesaComanda.quantidadePessoasCouvert} pessoa(s) × ${formatoMoeda.format(mesaComanda.valorCouvertPorPessoa)}',
                  style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                ),
              ),
            ],
          ],
          // Garçom
          if (valorGarcomGeral > 0) ...[
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Garçom (10%):',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo,
                    fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
                pw.Text(
                  formatoMoeda.format(valorGarcomGeral),
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo,
                    fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
          pw.SizedBox(height: 4),
          pw.Divider(),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Total Mesa:',
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo,
                  fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
              pw.Text(
                formatoMoeda.format(totalMesa),
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo,
                  fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ],
          ),
          // Mostrar valores individuais de cada comanda
          if (comandasVinculadas != null && comandasVinculadas.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Comandas Vinculadas:',
              style: pw.TextStyle(
                fontSize: fontSizeCorpo - 1,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            ...comandasVinculadas.map((comanda) {
              final totalComanda = comanda.totalCalculado;
              final pagoComanda = comanda.totalPago;
              final pendenteComanda = totalComanda - pagoComanda;
              
              return pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8, top: 2),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Comanda ${comanda.numero}:',
                          style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                        ),
                        pw.Text(
                          formatoMoeda.format(totalComanda),
                          style: pw.TextStyle(
                            fontSize: fontSizeCorpo - 1,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (pagoComanda > 0) ...[
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            '  Pago:',
                            style: pw.TextStyle(fontSize: fontSizeCorpo - 2),
                          ),
                          pw.Text(
                            formatoMoeda.format(pagoComanda),
                            style: pw.TextStyle(
                              fontSize: fontSizeCorpo - 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (pendenteComanda > 0) ...[
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            '  Pendente:',
                            style: pw.TextStyle(fontSize: fontSizeCorpo - 2),
                          ),
                          pw.Text(
                            formatoMoeda.format(pendenteComanda),
                            style: pw.TextStyle(
                              fontSize: fontSizeCorpo - 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
            pw.SizedBox(height: 2),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Comandas:',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo,
                    fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
                pw.Text(
                  formatoMoeda.format(totalComandas),
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo,
                    fontWeight: usarNegrito ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
          pw.SizedBox(height: 4),
          pw.Divider(),
          pw.SizedBox(height: 4),
          // TOTAIS GERAIS
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL GERAL:',
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo + 4,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  formatoMoeda.format(totalGeral),
                  style: pw.TextStyle(
                    fontSize: fontSizeCorpo + 4,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói histórico de pagamentos
  static pw.Widget _buildPagamentosTermico(
    MesaComanda mesaComanda,
    List<MesaComanda>? comandasVinculadas,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
    double fontSizeCorpo,
    bool usarNegrito,
  ) {
    final todosPagamentos = <Map<String, dynamic>>[];
    
    // Pagamentos da mesa
    for (final pagamento in mesaComanda.historicoPagamentos) {
      todosPagamentos.add({
        'pagamento': pagamento,
        'origem': 'Mesa ${mesaComanda.numero}',
        'mesaComanda': mesaComanda,
      });
    }
    
    // Pagamentos das comandas vinculadas
    if (comandasVinculadas != null) {
      for (final comanda in comandasVinculadas) {
        for (final pagamento in comanda.historicoPagamentos) {
          todosPagamentos.add({
            'pagamento': pagamento,
            'origem': 'Comanda ${comanda.numero}',
            'mesaComanda': comanda,
          });
        }
      }
    }
    
    if (todosPagamentos.isEmpty) {
      return pw.Text(
        'Nenhum pagamento registrado',
        style: const pw.TextStyle(fontSize: 8),
        textAlign: pw.TextAlign.center,
      );
    }

    // Ordenar por data
    todosPagamentos.sort((a, b) {
      final pagA = a['pagamento'] as RegistroPagamento;
      final pagB = b['pagamento'] as RegistroPagamento;
      return pagA.dataPagamento.compareTo(pagB.dataPagamento);
    });

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'PAGAMENTOS REALIZADOS',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Divider(),
        ...todosPagamentos.map((pagamentoData) {
          final pagamento = pagamentoData['pagamento'] as RegistroPagamento;
          final origem = pagamentoData['origem'] as String;
          final mesaComandaOrigem = pagamentoData['mesaComanda'] as MesaComanda;
          
          // Buscar itens pagos neste pagamento
          final itensPagosNestePagamento = <ItemMesaComanda>[];
          if (pagamento.itensPagos != null && pagamento.itensPagos!.isNotEmpty) {
            for (final itemId in pagamento.itensPagos!) {
              try {
                final item = mesaComandaOrigem.itens.firstWhere(
                  (i) => i.id == itemId,
                );
                itensPagosNestePagamento.add(item);
              } catch (e) {
                // Item não encontrado - ignorar
              }
            }
          }
          
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    origem,
                    style: pw.TextStyle(
                      fontSize: fontSizeCorpo + 1,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        formatoMoeda.format(pagamento.valor),
                        style: pw.TextStyle(
                          fontSize: fontSizeCorpo + 2,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        pagamento.formaPagamento ?? 'Não informado',
                        style: pw.TextStyle(fontSize: fontSizeCorpo),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Data: ${formatoData.format(pagamento.dataPagamento)}',
                    style: pw.TextStyle(fontSize: fontSizeCorpo),
                  ),
                  if (pagamento.pessoaPagou != null && pagamento.pessoaPagou!.isNotEmpty)
                    pw.Text(
                      'Pagou: ${pagamento.pessoaPagou}',
                      style: pw.TextStyle(
                        fontSize: fontSizeCorpo + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    // Mostrar itens pagos
                    if (itensPagosNestePagamento.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Itens pagos:',
                        style: pw.TextStyle(
                          fontSize: fontSizeCorpo,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      ...itensPagosNestePagamento.map((item) {
                        final itemTotal = item.subtotal; // Usar subtotal
                        return pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Expanded(
                                child: pw.Text(
                                  '${item.quantidade}x ${item.nome}',
                                  style: pw.TextStyle(fontSize: fontSizeCorpo),
                                ),
                              ),
                              pw.Text(
                                formatoMoeda.format(itemTotal),
                                style: pw.TextStyle(
                                  fontSize: fontSizeCorpo,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  if (pagamento.observacao != null && pagamento.observacao!.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Obs: ${pagamento.observacao}',
                      style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Constrói resumo (pago e pendente)
  static pw.Widget _buildResumoTermico(
    MesaComanda mesaComanda,
    List<MesaComanda>? comandasVinculadas,
    NumberFormat formatoMoeda,
    double fontSizeCorpo,
    bool usarNegrito,
  ) {
    double totalPagoMesa = mesaComanda.totalPago;
    double totalPagoComandas = 0.0;
    double totalGeral = mesaComanda.totalCalculado;
    
    if (comandasVinculadas != null) {
      for (final comanda in comandasVinculadas) {
        totalPagoComandas += comanda.totalPago;
        totalGeral += comanda.totalCalculado;
      }
    }
    
    final totalPagoGeral = totalPagoMesa + totalPagoComandas;
    final totalPendente = totalGeral - totalPagoGeral;

    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 2),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL PAGO:',
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 1,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                formatoMoeda.format(totalPagoGeral),
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 1,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL PENDENTE:',
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 1,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                formatoMoeda.format(totalPendente),
                style: pw.TextStyle(
                  fontSize: fontSizeCorpo + 1,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Constrói observações
  static pw.Widget _buildObservacoesTermico(MesaComanda mesaComanda, double fontSizeCorpo, bool usarNegrito) {
    if (mesaComanda.observacao == null || mesaComanda.observacao!.isEmpty) {
      return pw.SizedBox.shrink();
    }
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'OBSERVAÇÕES',
            style: pw.TextStyle(
              fontSize: fontSizeCorpo,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            mesaComanda.observacao!,
            style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
          ),
        ],
      ),
    );
  }

  /// Constrói rodapé
  static pw.Widget _buildRodapeTermico(Empresa empresa, DateFormat formatoData, double fontSizeCorpo, bool usarNegrito) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Divider(),
        pw.SizedBox(height: 4),
        pw.Text(
          'Impresso em: ${formatoData.format(DateTime.now())}',
          style: pw.TextStyle(fontSize: fontSizeCorpo - 2),
          textAlign: pw.TextAlign.center,
        ),
        if (empresa.configuracoes != null && empresa.configuracoes!['observacoes'] != null) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            empresa.configuracoes!['observacoes'].toString(),
            style: pw.TextStyle(fontSize: fontSizeCorpo - 2),
            textAlign: pw.TextAlign.center,
          ),
        ],
        pw.SizedBox(height: 8),
        pw.Text(
          '--- FIM DO RECIBO ---',
          style: pw.TextStyle(
            fontSize: fontSizeCorpo - 1,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  /// Retorna texto do status
  static String _getStatusTexto(StatusItem status) {
    switch (status) {
      case StatusItem.pendente:
        return 'Pendente';
      case StatusItem.emPreparo:
        return 'Em Preparo';
      case StatusItem.pronto:
        return 'Pronto';
      case StatusItem.entregue:
        return 'Entregue';
      case StatusItem.cancelado:
        return 'Cancelado';
    }
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

  /// Imprime o PDF do fechamento de conta em formato térmico (80mm)
  static Future<void> imprimirPDFTermico({
    required MesaComanda mesaComanda,
    required Empresa empresa,
    List<MesaComanda>? comandasVinculadas,
  }) async {
    try {
      final pdfBytes = await gerarPDFTermico(
        mesaComanda: mesaComanda,
        empresa: empresa,
        comandasVinculadas: comandasVinculadas,
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } catch (e) {
      throw Exception('Erro ao imprimir PDF térmico: $e');
    }
  }
}

