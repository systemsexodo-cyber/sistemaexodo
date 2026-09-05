import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/produto.dart';
import '../models/empresa.dart';
import 'impressao_service.dart';

/// Serviço para gerar e imprimir PDF de inventário para contagem física.
///
/// Gera uma lista formatada com código, nome, unidade, estoque atual e
/// espaço em branco para o funcionário preencher a quantidade contada.
class InventarioPrintService {
  /// Gera o PDF do inventário para contagem.
  ///
  /// [produtos] — lista de produtos a incluir no inventário
  /// [empresa] — dados da empresa para cabeçalho
  /// [filtroGrupo] — nome do grupo filtrado (null = todos)
  /// [mostrarEstoque] — se true, mostra o estoque atual (conferência); se false, deixa em branco
  static Future<Uint8List> gerarPDFInventario({
    required List<Produto> produtos,
    required Empresa empresa,
    String? filtroGrupo,
    bool mostrarEstoque = true,
  }) async {
    final pdf = pw.Document();
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');

    // Ordenar por grupo e depois por nome
    final ordenados = List<Produto>.from(produtos)
      ..sort((a, b) {
        final gc = a.grupo.compareTo(b.grupo);
        if (gc != 0) return gc;
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });

    // Agrupar por grupo
    final Map<String, List<Produto>> porGrupo = {};
    for (final p in ordenados) {
      final g = p.grupo.isNotEmpty ? p.grupo : 'Sem Grupo';
      porGrupo.putIfAbsent(g, () => []).add(p);
    }

    const format = PdfPageFormat(
      210 * PdfPageFormat.mm,
      double.infinity,
      marginTop: 15 * PdfPageFormat.mm,
      marginBottom: 15 * PdfPageFormat.mm,
      marginLeft: 12 * PdfPageFormat.mm,
      marginRight: 12 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        header: (context) => _buildCabecalho(empresa, formatoData, filtroGrupo, produtos.length),
        footer: (context) => _buildRodape(context),
        build: (context) {
          final List<pw.Widget> widgets = [];

          for (final entry in porGrupo.entries) {
            // Cabeçalho do grupo
            widgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  children: [
                    pw.Text(
                      entry.key.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      '(${entry.value.length} itens)',
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
            );

            // Tabela de produtos do grupo
            widgets.add(
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerAlignment: pw.Alignment.centerLeft,
                cellAlignment: pw.Alignment.centerLeft,
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                cellHeight: 22,
                headerHeight: 20,
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),  // Código
                  1: const pw.FlexColumnWidth(5),    // Nome
                  2: const pw.FlexColumnWidth(1),    // Un.
                  3: const pw.FlexColumnWidth(1.5),  // Sistema (estoque)
                  4: const pw.FlexColumnWidth(1.8),  // Contado
                },
                headers: ['CÓDIGO', 'PRODUTO', 'UND.', mostrarEstoque ? 'SISTEMA' : 'PREÇO', 'CONTADO'],
                data: entry.value.map((p) {
                  return [
                    p.codigo?.replaceAll('COD-', '') ?? '-',
                    _truncar(p.nome, 45),
                    p.unidade,
                    mostrarEstoque
                        ? (p.estoque % 1 == 0 ? p.estoque.toInt().toString() : p.estoque.toStringAsFixed(2))
                        : (p.preco > 0 ? 'R\$ ${p.preco.toStringAsFixed(2)}' : '-'),
                    '', // Espaço para preencher
                  ];
                }).toList(),
                border: pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.3),
                  verticalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.3),
                ),
                oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
              ),
            );

            // Espaço entre grupos
            widgets.add(pw.SizedBox(height: 8));
          }

          // Resumo final
          widgets.add(pw.SizedBox(height: 10));
          widgets.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RESUMO DA CONTAGEM',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total de produtos: ${produtos.length}', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Grupos: ${porGrupo.length}', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    children: [
                      pw.Expanded(child: _campoAssinatura('Responsável pela contagem')),
                      pw.SizedBox(width: 20),
                      pw.Expanded(child: _campoAssinatura('Conferido por')),
                      pw.SizedBox(width: 20),
                      pw.Expanded(child: _campoAssinatura('Data / Hora')),
                    ],
                  ),
                ],
              ),
            ),
          );

          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildCabecalho(Empresa empresa, DateFormat formatoData, String? filtroGrupo, int totalProdutos) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    empresa.nomeFantasia ?? empresa.razaoSocial ?? 'Estoque',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'INVENTÁRIO DE ESTOQUE — CONTAGEM FÍSICA',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Data: ${formatoData.format(DateTime.now())}',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                  if (filtroGrupo != null)
                    pw.Text(
                      'Grupo: $filtroGrupo',
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                  pw.Text(
                    'Produtos: $totalProdutos',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Divider(color: PdfColors.grey400, height: 1),
        ],
      ),
    );
  }

  static pw.Widget _buildRodape(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Página ${context.pageNumber} de ${context.pagesCount}',
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
      ),
    );
  }

  static pw.Widget _campoAssinatura(String label) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          height: 30,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 1)),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(label, style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ],
    );
  }

  static String _truncar(String texto, int max) {
    if (texto.length <= max) return texto;
    return '${texto.substring(0, max - 3)}...';
  }

  /// Imprime o inventário usando o serviço de impressão central.
  static Future<void> imprimirInventario({
    required List<Produto> produtos,
    required Empresa empresa,
    required BuildContext context,
    String? filtroGrupo,
    bool mostrarEstoque = true,
  }) async {
    final bytes = await gerarPDFInventario(
      produtos: produtos,
      empresa: empresa,
      filtroGrupo: filtroGrupo,
      mostrarEstoque: mostrarEstoque,
    );

    await ImpressaoService.imprimirPdf(
      bytes: bytes,
      empresa: empresa,
      name: 'Inventario_Estoque',
      termico: false,
      context: context,
    );
  }
}
