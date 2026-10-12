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
    List<String>? itensDeletadosExtra,
    // Recebimentos de pedidos/mesas por forma de pagamento (DataService),
    // para o papel mostrar o mesmo que o diálogo de fechamento.
    Map<TipoPagamento, double> recebimentosPedidos = const {},
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

    // Calcular resumo por forma de pagamento e detalhe de itens
    double totalItensVendidos = 0.0;
    double valorTotalItens = 0.0;

    final itemQuantities = <String, double>{};
    final itemTotals = <String, double>{};
    final itensDeletadosMesa = <String>[];
    if (itensDeletadosExtra != null) {
      itensDeletadosMesa.addAll(itensDeletadosExtra);
    }

    for (final venda in vendas) {
      // Coleta de itens deletados das observações de todas as vendas (ativas ou não)
      if (venda.observacoes != null && venda.observacoes!.contains('CANCELADOS:')) {
        final parts = venda.observacoes!.split('CANCELADOS:');
        if (parts.length > 1) {
          final orig = venda.observacoes!.split('|').first.replaceAll('[VIP-MC] originado de ', '').trim();
          itensDeletadosMesa.add('$orig: ${parts[1].trim()}');
        }
      }

      if (venda.cancelado) continue;
      
      // Somar itens
      for (final item in venda.itens) {
        totalItensVendidos += item.quantidade;
        valorTotalItens += item.precoUnitario * item.quantidade;
        itemQuantities[item.nome] = (itemQuantities[item.nome] ?? 0.0) + item.quantidade;
        itemTotals[item.nome] = (itemTotals[item.nome] ?? 0.0) + (item.precoUnitario * item.quantidade);
      }
    }

    // Resumo por forma de pagamento com a MESMA regra do card do caixa:
    // vendas com pagamento dividido entram por cada parte (venda.pagamentos).
    final resumoPagamentos = resumoPorForma(vendas);
    final totalPagamentos = resumoPagamentos.fold<double>(0.0, (a, b) => a + b.valor);

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
              ...resumoPagamentos.map((r) {
                return _buildValorLinha(r.rotulo, r.valor, fontSizeCorpo);
              }),
              pw.Divider(thickness: 0.5, indent: 20, endIndent: 20),
              _buildValorLinha('TOTAL VENDAS:', totalPagamentos, fontSizeCorpo, bold: true),
              pw.SizedBox(height: 10),

              // Recebimentos de pedidos/mesas (mesma fonte do fechamento na tela)
              if (recebimentosPedidos.values.any((v) => v > 0)) ...[
                pw.Text(
                  'RECEBIMENTOS DE PEDIDOS/MESAS',
                  style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 5),
                ...recebimentosPedidos.entries
                    .where((e) => e.value > 0)
                    .map((e) => _buildValorLinha(
                          _getNomeTipoPagamento(e.key),
                          e.value,
                          fontSizeCorpo,
                        )),
                pw.SizedBox(height: 10),
              ],

              // Resumo de Itens Vendidos Detalhado
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 5),
              pw.Text(
                'ITENS VENDIDOS',
                style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 5),
              ...itemQuantities.entries.map((e) {
                final nome = e.key;
                final qtd = e.value;
                final totalVal = itemTotals[nome] ?? 0.0;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${qtd.toStringAsFixed(0)}x $nome',
                          style: pw.TextStyle(fontSize: fontSizeCorpo - 1),
                        ),
                      ),
                      pw.Text(
                        _formatoMoeda.format(totalVal),
                        style: pw.TextStyle(fontSize: fontSizeCorpo - 1, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }),
              pw.SizedBox(height: 10),

              // Vendas Canceladas (Auditoria)
              if (vendas.any((v) => v.cancelado)) ...[
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 5),
                pw.Text(
                  'VENDAS CANCELADAS',
                  style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold, color: PdfColors.red),
                ),
                pw.SizedBox(height: 5),
                ...vendas.where((v) => v.cancelado).map((v) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '${v.numero} - ${v.clienteNome ?? "Consumidor"}',
                          style: pw.TextStyle(fontSize: fontSizeCorpo - 1, color: PdfColors.red),
                        ),
                        pw.Text(
                          _formatoMoeda.format(v.valorTotal),
                          style: pw.TextStyle(fontSize: fontSizeCorpo - 1, fontWeight: pw.FontWeight.bold, color: PdfColors.red),
                        ),
                      ],
                    ),
                  );
                }),
                pw.SizedBox(height: 10),
              ],

              // Itens Deletados/Cancelados de Mesas/Comandas
              if (itensDeletadosMesa.isNotEmpty) ...[
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 5),
                pw.Text(
                  'ITENS DELETADOS (CARRINHO/MESAS)',
                  style: pw.TextStyle(fontSize: fontSizeCorpo, fontWeight: pw.FontWeight.bold, color: PdfColors.orange),
                ),
                pw.SizedBox(height: 5),
                ...itensDeletadosMesa.map((text) {
                  return pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      text,
                      style: pw.TextStyle(fontSize: fontSizeCorpo - 1, color: PdfColors.orange),
                    ),
                  );
                }),
                pw.SizedBox(height: 10),
              ],

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
              // Detalhamento (motivo + valor) de cada sangria/suprimento — sem
              // isso o gestor só via o total impresso.
              ...fechamento.suprimentos.map((s) => _buildInfoLinha(
                    '  + ${s.motivo.isEmpty ? "Suprimento" : s.motivo}',
                    _formatoMoeda.format(s.valor),
                    fontSizeCorpo - 1,
                  )),
              ...fechamento.sangrias.map((s) => _buildInfoLinha(
                    '  - ${s.motivo.isEmpty ? "Sangria" : s.motivo}',
                    _formatoMoeda.format(s.valor),
                    fontSizeCorpo - 1,
                  )),
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

  /// Resumo do valor vendido por forma de pagamento para a impressão.
  ///
  /// Usa a MESMA regra de `DataService.calcularResumoFormaPagamentoDoCaixa`:
  /// vendas com pagamento dividido somam cada parte ([VendaBalcao.pagamentos]);
  /// as demais entram pela forma principal. Assim o papel não diverge do card
  /// "Entradas por Forma de Pagamento" da tela.
  static List<ResumoFormaPagamento> resumoPorForma(List<VendaBalcao> vendas) {
    final acumulado = <String, ResumoFormaPagamento>{};

    void acumular(TipoPagamento tipo, String? nomeForma, double valor) {
      if (valor <= 0) return;
      final nome = nomeForma?.trim();
      final rotulo = (nome != null && nome.isNotEmpty) ? nome : _getNomeTipoPagamento(tipo);
      final chave = '${tipo.name}|${rotulo.toLowerCase()}';
      final atual = acumulado[chave];
      acumulado[chave] = ResumoFormaPagamento(
        rotulo: rotulo,
        tipo: tipo,
        valor: (atual?.valor ?? 0.0) + valor,
        quantidade: (atual?.quantidade ?? 0) + 1,
      );
    }

    for (final venda in vendas) {
      if (venda.cancelado) continue;
      if (venda.pagamentos.isNotEmpty) {
        for (final pag in venda.pagamentos) {
          acumular(pag.tipo, pag.nomeForma, pag.valor);
        }
      } else {
        acumular(venda.tipoPagamento, null, venda.valorTotal);
      }
    }

    return acumulado.values.toList()
      ..sort((a, b) => b.valor.compareTo(a.valor));
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
      case TipoPagamento.transferencia: return 'Transferência';
    }
  }
}
