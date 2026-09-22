import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/empresa.dart';
import '../models/forma_pagamento.dart';
import '../models/nfce.dart';
import '../models/produto.dart';
import '../models/venda_balcao.dart';
import 'fiscal_pdf_service.dart';

/// Resumo de faturamento do período (fiscal x não fiscal), usado pelos
/// relatórios do contador.
class ResumoFaturamento {
  final Map<String, double> pgtoFiscal;
  final Map<String, double> pgtoNaoFiscal;
  final double totalFiscal;
  final double totalNaoFiscal;
  final int totalVendasComNota;
  final int totalVendasSemNota;

  ResumoFaturamento({
    required this.pgtoFiscal,
    required this.pgtoNaoFiscal,
    required this.totalFiscal,
    required this.totalNaoFiscal,
    required this.totalVendasComNota,
    required this.totalVendasSemNota,
  });

  double get faturamentoTotal => totalFiscal + totalNaoFiscal;
  int get totalVendas => totalVendasComNota + totalVendasSemNota;
}

/// Tudo o que o pacote contábil gera, pronto para ser gravado em disco
/// (app desktop) ou baixado no navegador (portal do contador).
class ResultadoPacoteContabil {
  final Uint8List zip;
  final Uint8List pdfFiscal;
  final List<int>? excel;
  final String leiaMe;

  /// XMLs por chave de acesso, para o app desktop gravar cada arquivo solto.
  final Map<String, String> xmls;

  ResultadoPacoteContabil({
    required this.zip,
    required this.pdfFiscal,
    required this.excel,
    required this.leiaMe,
    required this.xmls,
  });

  int get xmlCount => xmls.length;
}

/// Gera o "pacote contábil" das NFC-e: XMLs, relatório fiscal em PDF (agrupado
/// por CFOP/CSOSN) e planilha Excel detalhada.
///
/// É usado em dois lugares, pela mesma implementação:
///  - `historico_nfce_pdv_dialog.dart` (app desktop, grava em C:\ExodoNFCe\Pacotes)
///  - `portal_contador_page.dart` (web, baixa pelo navegador)
class PacoteContabilService {
  PacoteContabilService._();

  /// Nome da aba com o resumo de faturamento na planilha.
  static const String abaResumo = 'Resumo Faturamento';

  /// Etiqueta do período usada nos nomes de arquivo: `20260101_20260131`.
  static String tagPeriodo(DateTime inicio, DateTime fim) =>
      '${DateFormat('yyyyMMdd').format(inicio)}_${DateFormat('yyyyMMdd').format(fim)}';

  /// Separa as vendas do período em fiscais (com NFC-e) e não fiscais,
  /// somando por forma de pagamento.
  static ResumoFaturamento calcularResumo({
    required List<NFCe> nfces,
    required List<VendaBalcao> vendas,
  }) {
    final idsVendasFiscais = <String>{};
    for (final n in nfces) {
      if (_autorizada(n) && n.vendaId != null) idsVendasFiscais.add(n.vendaId!);
    }

    final pgtoFiscal = <String, double>{};
    final pgtoNaoFiscal = <String, double>{};
    var totalFiscal = 0.0;
    var totalNaoFiscal = 0.0;
    var totalVendasComNota = 0;
    var totalVendasSemNota = 0;

    for (final v in vendas) {
      final isFiscal = idsVendasFiscais.contains(v.id) ||
          nfces.any((n) => _autorizada(n) && n.vendaNumero == v.numero);

      // Se a venda tem múltiplas formas de pagamento (split), somar cada forma.
      final valoresPorForma = <String, double>{};
      final pagsVenda = v.pagamentos;
      if (pagsVenda.isNotEmpty) {
        for (final p in pagsVenda.where((p) => p.recebido)) {
          valoresPorForma[p.tipo.nome] = (valoresPorForma[p.tipo.nome] ?? 0.0) + p.valor;
        }
      } else {
        valoresPorForma[v.tipoPagamento.nome] = v.valorTotal;
      }

      for (final entry in valoresPorForma.entries) {
        if (isFiscal) {
          pgtoFiscal[entry.key] = (pgtoFiscal[entry.key] ?? 0.0) + entry.value;
          totalFiscal += entry.value;
        } else {
          pgtoNaoFiscal[entry.key] = (pgtoNaoFiscal[entry.key] ?? 0.0) + entry.value;
          totalNaoFiscal += entry.value;
        }
      }

      // Contador de vendas: incrementa UMA vez por venda (não por pagamento).
      if (isFiscal) {
        totalVendasComNota++;
      } else {
        totalVendasSemNota++;
      }
    }

    return ResumoFaturamento(
      pgtoFiscal: pgtoFiscal,
      pgtoNaoFiscal: pgtoNaoFiscal,
      totalFiscal: totalFiscal,
      totalNaoFiscal: totalNaoFiscal,
      totalVendasComNota: totalVendasComNota,
      totalVendasSemNota: totalVendasSemNota,
    );
  }

  /// Relatório fiscal em PDF, agrupado por CFOP/CSOSN.
  static Future<Uint8List> gerarPdfFiscal({
    required Empresa empresa,
    required List<NFCe> nfces,
    required List<VendaBalcao> vendas,
    required List<Produto> produtos,
    required DateTime mesRef,
  }) {
    return FiscalPDFService.gerarRelatorioMensal(
      empresa: empresa,
      mesRef: mesRef,
      nfces: nfces,
      vendas: vendas,
      produtos: produtos,
    );
  }

  /// Planilha Excel com duas abas: os itens detalhados de cada NFC-e e o
  /// resumo de faturamento (fiscal x não fiscal).
  static List<int>? gerarExcel({
    required List<NFCe> nfces,
    required List<VendaBalcao> vendas,
    required List<Produto> produtos,
    required DateTime inicio,
    required DateTime fim,
  }) {
    final resumo = calcularResumo(nfces: nfces, vendas: vendas);
    final excel = Excel.createExcel();
    final aba = excel.sheets.keys.first;

    const headers = [
      'Data Emissão', 'Número', 'Série', 'Status', 'Chave de Acesso', 'Venda',
      'Pagamentos', 'Valor Total NFC-e', 'Código Item', 'Descrição Item',
      'NCM', 'CFOP', 'CSOSN', 'CST ICMS', 'Origem', 'Aliq. ICMS',
      'Quantidade', 'V. Unitário', 'V. Total Item',
    ];
    for (var i = 0; i < headers.length; i++) {
      excel.updateCell(aba, CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), headers[i]);
    }

    var linha = 1;
    for (final n in nfces) {
      // Só notas emitidas entram na planilha: rascunhos de emissão do app
      // (`pend-`) e notas rejeitadas não são documentos fiscais e apareceriam
      // como linhas "PENDENTE" sem chave de acesso, inflando o relatório.
      if (!_autorizada(n)) continue;

      final dataEmissao = DateFormat('dd/MM/yyyy HH:mm').format(n.dataEmissao);
      final pagamentos = n.pagamentos.map((p) => p.tipoDescricao).join(' + ');
      final chave = n.chaveAcesso ?? '';
      final venda = _numeroDaVenda(n, vendas);
      final itens = _itensDaNota(n, vendas, produtos);

      for (final item in itens) {
        final valores = <dynamic>[
          dataEmissao,
          n.numero,
          n.serie,
          (n.status ?? '').toUpperCase(),
          chave,
          venda,
          pagamentos,
          n.valorTotal,
          item.codigo,
          item.descricao,
          item.ncm,
          item.cfop,
          item.csosn ?? '',
          item.icmsCst ?? '',
          item.origem ?? '',
          item.icmsAliquota ?? 0.0,
          item.quantidade,
          item.valorUnitario,
          item.valorTotal,
        ];
        for (var c = 0; c < valores.length; c++) {
          excel.updateCell(aba, CellIndex.indexByColumnRow(columnIndex: c, rowIndex: linha), valores[c]);
        }
        linha++;
      }
    }

    _preencherAbaResumo(excel, inicio: inicio, fim: fim, resumo: resumo);
    return excel.encode();
  }

  /// Pacote completo: XMLs + PDF fiscal + Excel + LEIA-ME, num ZIP.
  ///
  /// [obterXml] devolve o XML de cada nota. No app desktop ele lê do disco
  /// (com fallback para o banco) e no portal ele baixa do bucket `xmls`.
  static Future<ResultadoPacoteContabil> gerarPacote({
    required Empresa empresa,
    required List<NFCe> nfces,
    required List<VendaBalcao> vendas,
    required List<Produto> produtos,
    required DateTime inicio,
    required DateTime fim,
    required Future<String> Function(NFCe nfce) obterXml,
  }) async {
    final resumo = calcularResumo(nfces: nfces, vendas: vendas);
    final tag = tagPeriodo(inicio, fim);
    final archive = Archive();

    // 1. XMLs individuais de cada nota
    final xmls = <String, String>{};
    for (final n in nfces) {
      final xml = (await obterXml(n)).trim();
      if (xml.isEmpty) continue;

      final chave = (n.chaveAcesso ?? '').trim();
      final nomeBase =
          (chave.isNotEmpty ? chave : 'nfce_${n.numero}_${n.id}')
              .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile('xml/$nomeBase.xml', bytes.length, bytes));
      xmls[chave] = xml;
    }

    // 2. Relatório fiscal em PDF (agrupado por CFOP/CSOSN)
    final pdfFiscal = await gerarPdfFiscal(
      empresa: empresa,
      nfces: nfces,
      vendas: vendas,
      produtos: produtos,
      mesRef: inicio,
    );
    archive.addFile(ArchiveFile(
        'relatorio_fiscal_agrupado_$tag.pdf', pdfFiscal.length, pdfFiscal));

    // 3. Planilha Excel detalhada
    final excelBytes = gerarExcel(
      nfces: nfces,
      vendas: vendas,
      produtos: produtos,
      inicio: inicio,
      fim: fim,
    );
    if (excelBytes != null) {
      archive.addFile(
          ArchiveFile('detalhado_dados_nfce_$tag.xlsx', excelBytes.length, excelBytes));
    }

    // 4. LEIA-ME com o resumo do pacote
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final leiaMe = StringBuffer()
      ..writeln('PACOTE CONTÁBIL NFC-e')
      ..writeln('Empresa: ${empresa.nomeExibicao}')
      ..writeln('CNPJ: ${empresa.cnpj ?? "N/D"}')
      ..writeln('Período: ${DateFormat('dd/MM/yyyy').format(inicio)} a ${DateFormat('dd/MM/yyyy').format(fim)}')
      ..writeln('Total de NFC-e no período: ${nfces.length}')
      ..writeln('Total de XML incluídos: ${xmls.length}')
      ..writeln('Faturamento Fiscal (Com NFC-e): ${moeda.format(resumo.totalFiscal)} (${resumo.totalVendasComNota} notas)')
      ..writeln('Vendas Sem Emissão: ${moeda.format(resumo.totalNaoFiscal)} (${resumo.totalVendasSemNota} vendas)')
      ..writeln('Faturamento Total Geral: ${moeda.format(resumo.faturamentoTotal)}')
      ..writeln('')
      ..writeln('Arquivos gerados: XMLs individuais, PDF Agrupado (CFOP/CSOSN) e Excel Detalhado.')
      ..writeln('Gerado em: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
    final leiaMeTexto = leiaMe.toString();
    final leiaMeBytes = utf8.encode(leiaMeTexto);
    archive.addFile(ArchiveFile('LEIA-ME.txt', leiaMeBytes.length, leiaMeBytes));

    final zip = ZipEncoder().encode(archive);
    if (zip == null || zip.isEmpty) {
      throw Exception('Falha ao gerar o arquivo ZIP.');
    }

    return ResultadoPacoteContabil(
      zip: Uint8List.fromList(zip),
      pdfFiscal: pdfFiscal,
      excel: excelBytes,
      leiaMe: leiaMeTexto,
      xmls: xmls,
    );
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  static bool _autorizada(NFCe n) {
    final status = n.status?.toLowerCase() ?? '';
    return status == 'autorizada' || status == 'sucesso';
  }

  /// Número da venda da nota, buscando na lista quando só houver o id.
  static String _numeroDaVenda(NFCe n, List<VendaBalcao> vendas) {
    var venda = n.vendaNumero ?? n.vendaId ?? n.id;
    if (n.vendaId != null && (venda == n.vendaId || venda.isEmpty)) {
      for (final v in vendas) {
        if (v.id == n.vendaId) return v.numero;
      }
    }
    return venda;
  }

  /// Itens da nota; quando a NFC-e não trouxe os itens, reconstrói pela venda
  /// de origem e, em último caso, cria uma linha genérica para não perder a nota.
  static List<NFCeItem> _itensDaNota(
    NFCe n,
    List<VendaBalcao> vendas,
    List<Produto> produtos,
  ) {
    if (n.itens.isNotEmpty) return n.itens;

    VendaBalcao? venda;
    for (final v in vendas) {
      if (v.id == n.vendaId || v.numero == n.vendaNumero) {
        venda = v;
        break;
      }
    }

    if (venda != null) {
      return venda.itens.map((item) {
        Produto? prod;
        for (final p in produtos) {
          if (p.id == item.id) {
            prod = p;
            break;
          }
        }
        return NFCeItem(
          produtoId: item.id,
          codigo: prod?.codigo ?? item.id,
          descricao: item.nome,
          ncm: prod?.ncm ?? '00000000',
          cfop: '5102',
          unidade: prod?.unidade ?? 'UN',
          quantidade: item.quantidade,
          valorUnitario: item.precoUnitario,
          valorTotal: item.precoUnitario * item.quantidade,
        );
      }).toList();
    }

    return [
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
      ),
    ];
  }

  /// Segunda aba da planilha: resumo de faturamento fiscal x não fiscal.
  static void _preencherAbaResumo(
    Excel excel, {
    required DateTime inicio,
    required DateTime fim,
    required ResumoFaturamento resumo,
  }) {
    void escrever(int coluna, int linha, dynamic valor) {
      excel.updateCell(abaResumo, CellIndex.indexByColumnRow(columnIndex: coluna, rowIndex: linha), valor);
    }

    escrever(0, 0, 'RESUMO DE FATURAMENTO MENSAL');
    escrever(0, 1,
        'Período: ${DateFormat('dd/MM/yyyy').format(inicio)} a ${DateFormat('dd/MM/yyyy').format(fim)}');

    escrever(0, 3, 'CATEGORIA');
    escrever(1, 3, 'QUANTIDADE DE VENDAS');
    escrever(2, 3, 'VALOR TOTAL FATURADO');

    escrever(0, 4, 'Faturamento Fiscal (Com NFC-e)');
    escrever(1, 4, resumo.totalVendasComNota);
    escrever(2, 4, resumo.totalFiscal);

    escrever(0, 5, 'Vendas Sem Emissão');
    escrever(1, 5, resumo.totalVendasSemNota);
    escrever(2, 5, resumo.totalNaoFiscal);

    escrever(0, 6, 'FATURAMENTO TOTAL GERAL');
    escrever(1, 6, resumo.totalVendas);
    escrever(2, 6, resumo.faturamentoTotal);

    var linhaAtual = 8;
    escrever(0, linhaAtual, 'FORMA DE PAGAMENTO (FISCAL)');
    escrever(1, linhaAtual, 'VALOR');
    linhaAtual++;
    for (final entry in resumo.pgtoFiscal.entries) {
      escrever(0, linhaAtual, entry.key);
      escrever(1, linhaAtual, entry.value);
      linhaAtual++;
    }

    linhaAtual++;
    escrever(0, linhaAtual, 'FORMA DE PAGAMENTO (SEM EMISSÃO)');
    escrever(1, linhaAtual, 'VALOR');
    linhaAtual++;
    for (final entry in resumo.pgtoNaoFiscal.entries) {
      escrever(0, linhaAtual, entry.key);
      escrever(1, linhaAtual, entry.value);
      linhaAtual++;
    }
  }
}
