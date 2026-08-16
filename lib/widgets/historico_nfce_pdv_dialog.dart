import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../models/empresa.dart';
import '../models/nfce.dart';
import '../services/data_service.dart';
import '../services/nfce_service_factory.dart';
import '../services/nfce_backend_service.dart';
import '../services/auth_service.dart';
import '../services/danfe_service.dart';
import '../services/supabase_service.dart';
import 'package:intl/intl.dart';
import '../models/produto.dart';
import '../models/venda_balcao.dart';
import '../models/forma_pagamento.dart';
import 'exodo_cancel_success_dialog.dart';
import '../services/fiscal_pdf_service.dart';
import 'dart:io';
import '../services/nfce_xml_local_service.dart';
import '../services/nfce_contingencia_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:excel/excel.dart' hide Border, Font;
import '../pages/html_helper_stub.dart' if (dart.library.html) '../pages/html_helper_web.dart' as html_helper;

class HistoricoNFCePDVDialog extends StatefulWidget {
  final Empresa empresa;

  const HistoricoNFCePDVDialog({Key? key, required this.empresa}) : super(key: key);

  @override
  _HistoricoNFCePDVDialogState createState() => _HistoricoNFCePDVDialogState();
}

class _HistoricoNFCePDVDialogState extends State<HistoricoNFCePDVDialog> {
  bool _isLoading = true;
  List<NFCe> _todasNfces = [];
  List<NFCe> _nfcesFiltradas = [];

  final TextEditingController _buscaController = TextEditingController();
  DateTimeRange? _periodoFiltro;

  @override
  void initState() {
    super.initState();
    _loadData();
    _buscaController.addListener(_filtrar);
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      
      // 1. Carrega instantaneamente as NFC-es locais da memória/PostgreSQL
      final localNfces = List<NFCe>.from(dataService.nfces);
      localNfces.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
      
      setState(() {
        _todasNfces = localNfces;
        _isLoading = false;
        _filtrar();
      });

      // 2. Busca em background as notas do Supabase para atualizar e sincronizar
      try {
        final results = await SupabaseService.instance.select(
          SupabaseService.tableNFCes,
          filters: {'empresaId': widget.empresa.id},
          orderBy: 'createdAt',
          descending: true,
          limit: 200,
        );
            
        final serverNfces = results.map((map) => NFCe.fromMap(map)).toList();
        
        // Merge das notas locais com as do servidor
        final Map<String, NFCe> mergeMap = {};
        for (final n in localNfces) {
          if (n.id != null) mergeMap[n.id!] = n;
        }
        for (final n in serverNfces) {
          if (n.id != null) {
            mergeMap[n.id!] = n;
          }
        }
        
        final mergedList = mergeMap.values.toList();
        mergedList.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
        
        if (mounted) {
          setState(() {
            _todasNfces = mergedList;
            _filtrar();
          });
        }
      } catch (e) {
        debugPrint('Erro ao buscar NFCes do Supabase (offline?): $e');
      }
    } catch (e) {
      debugPrint('Erro ao carregar NFCes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filtrar() {
    final termo = _buscaController.text.toLowerCase().trim();
    setState(() {
      _nfcesFiltradas = _todasNfces.where((nfce) {
        bool matchTermo = true;
        if (termo.isNotEmpty) {
          final n = nfce.numero?.toLowerCase() ?? '';
          final idVenda = nfce.vendaId?.toLowerCase() ?? nfce.id.toLowerCase();
          final numVenda = nfce.vendaNumero?.toLowerCase() ?? '';
          matchTermo = n.contains(termo) || idVenda.contains(termo) || numVenda.contains(termo);
        }

        bool matchData = true;
        if (_periodoFiltro != null && nfce.createdAt != null) {
          final data = nfce.createdAt!;
          // Normalizar para comparação de datas apenas (sem horas)
          final inicio = DateTime(_periodoFiltro!.start.year, _periodoFiltro!.start.month, _periodoFiltro!.start.day);
          final fim = DateTime(_periodoFiltro!.end.year, _periodoFiltro!.end.month, _periodoFiltro!.end.day, 23, 59, 59);
          matchData = data.isAfter(inicio.subtract(const Duration(seconds: 1))) && 
                      data.isBefore(fim.add(const Duration(seconds: 1)));
        }

        return matchTermo && matchData;
      }).toList();
    });
  }

  Future<void> _selecionarPeriodo() async {
    DateTime? novaDataInicio = _periodoFiltro?.start ?? DateTime.now();
    DateTime? novaDataFim = _periodoFiltro?.end ?? DateTime.now();

    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Selecionar Período', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Escolha o intervalo de datas para o filtro:', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Início', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: novaDataInicio!,
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => novaDataInicio = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16, color: Colors.orange),
                                const SizedBox(width: 8),
                                Text(DateFormat('dd/MM/yyyy').format(novaDataInicio!), style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Fim', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: novaDataFim!,
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setDialogState(() => novaDataFim = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16, color: Colors.orange),
                                const SizedBox(width: 8),
                                Text(DateFormat('dd/MM/yyyy').format(novaDataFim!), style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                if (novaDataFim!.isBefore(novaDataInicio!)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A data final não pode ser anterior à inicial.')));
                  return;
                }
                Navigator.pop(context, DateTimeRange(start: novaDataInicio!, end: novaDataFim!));
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('APLICAR FILTRO'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _periodoFiltro = result;
        _filtrar();
      });
    }
  }

  String _csvField(dynamic value) {
    final v = (value ?? '').toString().replaceAll('"', '""');
    return '"$v"';
  }

  Future<void> _exportarPacoteMensalContador() async {
    if (_todasNfces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há NFC-e para exportar.')),
      );
      return;
    }
    
    DateTimeRange? periodo = _periodoFiltro;
    if (periodo == null) {
      periodo = await showDateRangePicker(
        context: context,
        initialDateRange: DateTimeRange(
          start: DateTime(DateTime.now().year, DateTime.now().month, 1),
          end: DateTime.now(),
        ),
        firstDate: DateTime(2023),
        lastDate: DateTime.now(),
        helpText: 'Selecione o período para exportação',
      );
    }
    if (periodo == null) return;

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final dataService = Provider.of<DataService>(context, listen: false);

      final nfcesNoPeriodo = _todasNfces.where((n) {
        final d = n.createdAt ?? n.dataEmissao;
        final inicio = DateTime(periodo!.start.year, periodo.start.month, periodo.start.day);
        final fim = DateTime(periodo.end.year, periodo.end.month, periodo.end.day, 23, 59, 59);
        return d.isAfter(inicio.subtract(const Duration(seconds: 1))) && 
               d.isBefore(fim.add(const Duration(seconds: 1)));
      }).toList();

      final todasVendasNoPeriodo = dataService.vendasBalcao.where((v) {
        final d = v.dataVenda;
        final inicio = DateTime(periodo!.start.year, periodo.start.month, periodo.start.day);
        final fim = DateTime(periodo.end.year, periodo.end.month, periodo.end.day, 23, 59, 59);
        return d.isAfter(inicio.subtract(const Duration(seconds: 1))) && 
               d.isBefore(fim.add(const Duration(seconds: 1))) &&
               !v.cancelado;
      }).toList();

      // --- CÁLCULO DE FATURAMENTO FISCAL vs NÃO FISCAL ---
      final Set<String> idsVendasFiscais = {};
      for (final n in nfcesNoPeriodo) {
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

      for (final v in todasVendasNoPeriodo) {
        final isFiscal = idsVendasFiscais.contains(v.id) ||
            nfcesNoPeriodo.any((n) => (n.status == 'autorizada' || n.status == 'sucesso') && n.vendaNumero == v.numero);

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

      final archive = Archive();
      int xmlCount = 0;

      final excelDetalhado = Excel.createExcel();
      
      final String sheetName = excelDetalhado.sheets.keys.first;

      final List<String> headers = [
        'Data Emissão', 'Número', 'Série', 'Status', 'Chave de Acesso', 'Venda', 
        'Pagamentos', 'Valor Total NFC-e', 'Código Item', 'Descrição Item', 
        'NCM', 'CFOP', 'CSOSN', 'CST ICMS', 'Origem', 'Aliq. ICMS', 
        'Quantidade', 'V. Unitário', 'V. Total Item'
      ];

      for (int i = 0; i < headers.length; i++) {
        excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), headers[i]);
      }

      int rowIdx = 1;
      for (final n in nfcesNoPeriodo) {
        final dataEmissao = DateFormat('dd/MM/yyyy HH:mm').format(n.dataEmissao);
        final pagamentos = n.pagamentos.map((p) => p.tipoDescricao).join(' + ');
        final chave = n.chaveAcesso ?? '';
        String venda = n.vendaNumero ?? n.vendaId ?? n.id;
        if (n.vendaId != null && (venda == n.vendaId || venda.isEmpty)) {
          try {
            final vObj = dataService.vendasBalcao.firstWhere((v) => v.id == n.vendaId);
            venda = vObj.numero;
          } catch (_) {}
        }

        // Se n.itens estiver vazio, tentar reconstruir a partir da venda correspondente
        List<NFCeItem> itensParaProcessar = n.itens;
        if (itensParaProcessar.isEmpty) {
          VendaBalcao? vendaObj;
          try {
            vendaObj = dataService.vendasBalcao.firstWhere(
              (v) => v.id == n.vendaId || v.numero == n.vendaNumero,
            );
          } catch (_) {}

          if (vendaObj != null) {
            itensParaProcessar = vendaObj.itens.map((vItem) {
              Produto? prod;
              try {
                prod = dataService.produtos.firstWhere((p) => p.id == vItem.id);
              } catch (_) {}
              
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
              );
            }).toList();
          }
        }

        // Se ainda assim vazio (nota sem venda de origem), criar item genérico
        if (itensParaProcessar.isEmpty) {
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
            )
          ];
        }

        for (final item in itensParaProcessar) {
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx), dataEmissao);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx), n.numero ?? '');
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx), n.serie ?? '');
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx), (n.status ?? '').toUpperCase());
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx), chave);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx), venda);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx), pagamentos);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx), n.valorTotal);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx), item.codigo);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIdx), item.descricao);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIdx), item.ncm);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIdx), item.cfop);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIdx), item.csosn ?? '');
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIdx), item.icmsCst ?? '');
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIdx), item.origem ?? '');
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: rowIdx), item.icmsAliquota ?? 0.0);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: rowIdx), item.quantidade);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: rowIdx), item.valorUnitario);
          excelDetalhado.updateCell(sheetName, CellIndex.indexByColumnRow(columnIndex: 18, rowIndex: rowIdx), item.valorTotal);
          rowIdx++;
        }

        var xml = (n.xmlEnviado ?? '').trim();
        final dt = n.createdAt ?? n.dataEmissao;
        final mesDir = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        final cnpj = (widget.empresa.cnpj ?? '').replaceAll(RegExp(r'[^0-9]'), '');

        // Fallback: tentar carregar XML do arquivo local se estiver vazio no banco
        if (xml.isEmpty && chave.isNotEmpty) {
          final pastaNota = 'NFCe_${n.numero}_${n.serie}';
          var localFile = File('C:\\ExodoNFCe\\$cnpj\\$mesDir\\$pastaNota\\$chave-nfe.xml');
          if (!localFile.existsSync()) {
            localFile = File('C:\\ExodoNFCe\\$cnpj\\$mesDir\\$chave-nfe.xml');
          }
          if (localFile.existsSync()) {
            xml = localFile.readAsStringSync();
          }
        }

        if (xml.isNotEmpty) {
          final nomeArquivo = (chave.isNotEmpty ? chave : 'nfce_${n.numero}_${n.id}').replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
          final bytes = utf8.encode(xml);
          archive.addFile(ArchiveFile('xml/$nomeArquivo.xml', bytes.length, bytes));
          xmlCount++;
        }
      }

      // ABA 2: Resumo Faturamento (Contabilidade)
      final String summarySheetName = 'Resumo Faturamento';
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), 'RESUMO DE FATURAMENTO MENSAL');
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1), 'Período: ${DateFormat('dd/MM/yyyy').format(periodo.start)} a ${DateFormat('dd/MM/yyyy').format(periodo.end)}');
      
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3), 'CATEGORIA');
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3), 'QUANTIDADE DE VENDAS');
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 3), 'VALOR TOTAL FATURADO');
      
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4), 'Faturamento Fiscal (Com NFC-e)');
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4), totalVendasComNota);
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 4), totalFiscal);
      
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 5), 'Vendas Sem Emissão');
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 5), totalVendasSemNota);
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 5), totalNaoFiscal);
      
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 6), 'FATURAMENTO TOTAL GERAL');
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 6), totalVendasComNota + totalVendasSemNota);
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 6), totalFiscal + totalNaoFiscal);
      
      // Totais por pagamento - Fiscal
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 8), 'FORMA DE PAGAMENTO (FISCAL)');
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 8), 'VALOR');
      int sRow = 9;
      for (final e in pgtoFiscal.entries) {
        excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: sRow), e.key);
        excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: sRow), e.value);
        sRow++;
      }
      
      // Totais por pagamento - Sem Emissão
      sRow++;
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: sRow), 'FORMA DE PAGAMENTO (SEM EMISSÃO)');
      excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: sRow), 'VALOR');
      sRow++;
      for (final e in pgtoNaoFiscal.entries) {
        excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: sRow), e.key);
        excelDetalhado.updateCell(summarySheetName, CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: sRow), e.value);
        sRow++;
      }

      final periodoTag = '${DateFormat('yyyyMMdd').format(periodo.start)}_${DateFormat('yyyyMMdd').format(periodo.end)}';

      final pdfFiscalBytes = await FiscalPDFService.gerarRelatorioMensal(
        empresa: widget.empresa,
        mesRef: periodo.start,
        nfces: nfcesNoPeriodo,
        vendas: todasVendasNoPeriodo,
        produtos: dataService.produtos,
      );
      archive.addFile(ArchiveFile('relatorio_fiscal_agrupado_$periodoTag.pdf', pdfFiscalBytes.length, pdfFiscalBytes));

      final excelBytes = excelDetalhado.encode();
      if (excelBytes != null) {
        archive.addFile(ArchiveFile('detalhado_dados_nfce_$periodoTag.xlsx', excelBytes.length, excelBytes));
      }

      final resumo = StringBuffer()
        ..writeln('PACOTE CONTÁBIL NFC-e')
        ..writeln('Período: ${DateFormat('dd/MM/yyyy').format(periodo.start)} a ${DateFormat('dd/MM/yyyy').format(periodo.end)}')
        ..writeln('Total de NFC-e no período: ${nfcesNoPeriodo.length}')
        ..writeln('Total de XML incluídos: $xmlCount')
        ..writeln('Faturamento Fiscal (Com NFC-e): ${NumberFormat.currency(locale: "pt_BR", symbol: "R\$").format(totalFiscal)} ($totalVendasComNota notas)')
        ..writeln('Vendas Sem Emissão: ${NumberFormat.currency(locale: "pt_BR", symbol: "R\$").format(totalNaoFiscal)} ($totalVendasSemNota vendas)')
        ..writeln('Faturamento Total Geral: ${NumberFormat.currency(locale: "pt_BR", symbol: "R\$").format(totalFiscal + totalNaoFiscal)}')
        ..writeln('\nArquivos gerados: XMLs individuais, PDF Agrupado (CFOP/CSOSN) e Excel Detalhado.')
        ..writeln('Gerado em: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
      final resumoBytes = utf8.encode(resumo.toString());
      archive.addFile(ArchiveFile('LEIA-ME.txt', resumoBytes.length, resumoBytes));

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null || zipBytes.isEmpty) throw Exception('Falha ao gerar arquivo ZIP.');

      final fileName = 'pacote_contabil_nfce_$periodoTag.zip';

      if (kIsWeb) {
        html_helper.downloadBytes(zipBytes, fileName, 'application/zip');
      } else {
        // ── Desktop: Criar pasta descompactada e salvar arquivos nela
        final pastaDestino = Directory('C:\\ExodoNFCe\\Pacotes\\pacote_contabil_nfce_$periodoTag');
        if (!pastaDestino.existsSync()) pastaDestino.createSync(recursive: true);

        // Salvar Relatório PDF na pasta descompactada
        File('${pastaDestino.path}\\relatorio_fiscal_agrupado_$periodoTag.pdf').writeAsBytesSync(pdfFiscalBytes);

        // Salvar Excel na pasta descompactada
        if (excelBytes != null) {
          File('${pastaDestino.path}\\detalhado_dados_nfce_$periodoTag.xlsx').writeAsBytesSync(excelBytes);
        }

        // Salvar LEIA-ME na pasta descompactada
        File('${pastaDestino.path}\\LEIA-ME.txt').writeAsBytesSync(resumoBytes);

        // Criar pasta de XMLs descompactada
        final pastaXmls = Directory('${pastaDestino.path}\\xml');
        if (!pastaXmls.existsSync()) pastaXmls.createSync(recursive: true);

        // Salvar ZIP no diretório de Pacotes principal
        final arquivoZip = File('C:\\ExodoNFCe\\Pacotes\\$fileName');
        arquivoZip.writeAsBytesSync(zipBytes);

        // Salvar XMLs na pasta descompactada e no arquivo local principal
        for (final n in nfcesNoPeriodo) {
          var xml = (n.xmlEnviado ?? '').trim();
          final dt = n.createdAt ?? n.dataEmissao;
          final mesDir = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
          final cnpj = (widget.empresa.cnpj ?? '').replaceAll(RegExp(r'[^0-9]'), '');
          final chave = n.chaveAcesso ?? '';

          if (xml.isEmpty && chave.isNotEmpty) {
            final pastaNota = 'NFCe_${n.numero}_${n.serie}';
            var localFile = File('C:\\ExodoNFCe\\$cnpj\\$mesDir\\$pastaNota\\$chave-nfe.xml');
            if (!localFile.existsSync()) {
              localFile = File('C:\\ExodoNFCe\\$cnpj\\$mesDir\\$chave-nfe.xml');
            }
            if (localFile.existsSync()) {
              xml = localFile.readAsStringSync();
            }
          }

          if (xml.isNotEmpty && chave.isNotEmpty) {
            // Salva na pasta do contador
            File('${pastaXmls.path}\\$chave-nfe.xml').writeAsStringSync(xml);

            // Garante que está no repositório de XMLs local principal do C:\
            final xmlDir = Directory('C:\\ExodoNFCe\\$cnpj\\$mesDir');
            if (!xmlDir.existsSync()) xmlDir.createSync(recursive: true);
            final xmlFile = File('${xmlDir.path}\\$chave-nfe.xml');
            if (!xmlFile.existsSync()) xmlFile.writeAsStringSync(xml);
          }
        }

        if (!mounted) return;

        // Abrir diálogo de confirmação com opção de abrir pasta e enviar e-mail
        final emailContador = widget.empresa.emailContabilidade;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent),
                SizedBox(width: 10),
                Text('Pacote Salvo!', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Arquivos salvos em:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 4),
                SelectableText(
                  r'C:\ExodoNFCe',
                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Notas: ${nfcesNoPeriodo.length}   |   XMLs incluídos: $xmlCount',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (emailContador != null && emailContador.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Contador: $emailContador', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Abrir pasta no Explorer
                  Process.run('explorer.exe', [r'C:\ExodoNFCe']);
                },
                icon: const Icon(Icons.folder_open, color: Colors.amber),
                label: const Text('ABRIR PASTA', style: TextStyle(color: Colors.amber)),
              ),
              if (emailContador != null && emailContador.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final subject = Uri.encodeComponent('ARQUIVOS FISCAIS - ${widget.empresa.razaoSocial} - $periodoTag');
                    final body = Uri.encodeComponent('Olá,\n\nSegue em anexo o pacote fiscal das NFC-e emitidas entre ${DateFormat('dd/MM/yyyy').format(periodo!.start)} e ${DateFormat('dd/MM/yyyy').format(periodo.end)}.\n\nEmpresa: ${widget.empresa.razaoSocial}\nCNPJ: ${widget.empresa.cnpj ?? "N/D"}\n\nArquivo salvo em: C:\\ExodoNFCe\\Pacotes\\$fileName\n\nGerado pelo Sistema Êxodo.');
                    final url = Uri.parse('mailto:$emailContador?subject=$subject&body=$body');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url);
                    } else {
                      debugPrint('Não foi possível abrir o cliente de email');
                    }
                  },
                  icon: const Icon(Icons.email),
                  label: const Text('ENVIAR E-MAIL'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro na exportação: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 800,
        height: 800,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Histórico de NFC-e', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 20),
            
            // Área de Filtros
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                   Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buscaController,
                          decoration: InputDecoration(
                            hintText: 'Buscar por Nº da NFC-e ou ID da Venda...',
                            hintStyle: const TextStyle(color: Colors.grey),
                            prefixIcon: const Icon(Icons.search, color: Colors.grey),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _exportarPacoteMensalContador,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Exportar / Enviar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.withOpacity(0.85),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Período:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      _buildQuickFilterChip('Hoje', () {
                         final agora = DateTime.now();
                         setState(() {
                           _periodoFiltro = DateTimeRange(start: DateTime(agora.year, agora.month, agora.day), end: agora);
                           _filtrar();
                         });
                      }),
                      _buildQuickFilterChip('7 Dias', () {
                         final agora = DateTime.now();
                         setState(() {
                           _periodoFiltro = DateTimeRange(start: agora.subtract(const Duration(days: 7)), end: agora);
                           _filtrar();
                         });
                      }),
                      _buildQuickFilterChip('Este Mês', () {
                         final agora = DateTime.now();
                         setState(() {
                           _periodoFiltro = DateTimeRange(start: DateTime(agora.year, agora.month, 1), end: agora);
                           _filtrar();
                         });
                      }),
                      _buildQuickFilterChip('Personalizado', _selecionarPeriodo, isCustom: true),
                      const Spacer(),
                      if (_periodoFiltro != null)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _periodoFiltro = null;
                              _filtrar();
                            });
                          },
                          icon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                          label: const Text('LIMPAR', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                        )
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            if (!_isLoading && _nfcesFiltradas.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    _buildSummaryBadge(
                      'TOTAL NOTAS: ${_nfcesFiltradas.length}',
                      Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    _buildSummaryBadge(
                      'VALOR TOTAL: ${NumberFormat.currency(locale: "pt_BR", symbol: "R\$").format(_nfcesFiltradas.where((n) => n.status == "autorizada" || n.status == "sucesso").fold(0.0, (sum, n) => sum + n.valorTotal))}',
                      Colors.green,
                    ),
                    if (_nfcesFiltradas.any((n) => n.status == 'cancelada')) ...[
                      const SizedBox(width: 12),
                      _buildSummaryBadge(
                        'CANCELADAS: ${NumberFormat.currency(locale: "pt_BR", symbol: "R\$").format(_nfcesFiltradas.where((n) => n.status == "cancelada").fold(0.0, (sum, n) => sum + n.valorTotal))}',
                        Colors.redAccent,
                      ),
                    ],
                  ],
                ),
              ),

            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : _nfcesFiltradas.isEmpty 
                  ? const Center(child: Text('Nenhuma NFC-e encontrada com os filtros atuais.', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: _nfcesFiltradas.length,
                      itemBuilder: (context, index) {
                        final nfce = _nfcesFiltradas[index];
                        final isAutorizada = nfce.status == 'autorizada' || nfce.status == 'sucesso';
                        final isErro = nfce.status == 'erro' || nfce.status == 'rejeitada';
                        final dt = nfce.createdAt != null ? DateFormat('dd/MM HH:mm').format(nfce.createdAt!) : '-';
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                               Icon(
                                 nfce.status == 'contingencia'
                                     ? Icons.warning_amber_rounded
                                     : (isAutorizada ? Icons.check_circle : (isErro ? Icons.error : Icons.hourglass_empty)),
                                 color: nfce.status == 'contingencia'
                                     ? Colors.amber
                                     : (isAutorizada ? Colors.green : (isErro ? Colors.redAccent : Colors.orange)),
                                 size: 36,
                               ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Data: $dt  |  Série ${nfce.serie ?? "-"} / Nº ${nfce.numero ?? "-"}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    () {
                                      final dataService = Provider.of<DataService>(context, listen: false);
                                      VendaBalcao? venda;
                                      try {
                                        venda = dataService.vendasBalcao.firstWhere(
                                          (v) => v.id == nfce.vendaId || v.numero == nfce.vendaNumero,
                                        );
                                      } catch (_) {}
                                      final vendaLabel = venda != null ? venda.numero : (nfce.vendaNumero ?? nfce.vendaId ?? nfce.id);
                                      
                                      return InkWell(
                                        onTap: () => _mostrarDetalhesVenda(context, nfce, dataService),
                                        borderRadius: BorderRadius.circular(4),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.receipt_long, color: Colors.cyanAccent, size: 14),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Venda: $vendaLabel',
                                                style: const TextStyle(
                                                  color: Colors.cyanAccent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }(),
                                    if (nfce.chaveAcesso != null && nfce.chaveAcesso!.isNotEmpty)
                                      SelectableText('Chave: ${nfce.chaveAcesso}', style: const TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic)),
                                    if (nfce.nomeConsumidor != null && nfce.nomeConsumidor!.isNotEmpty)
                                      Text('Cliente: ${nfce.nomeConsumidor}', style: const TextStyle(color: Colors.white70)),
                                    if (nfce.pagamentos.isNotEmpty)
                                      Text('Pagamento: ${nfce.pagamentos.map((p) => p.tipoDescricao).join(", ")}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    Text(
                                       'Status: ${nfce.status?.toUpperCase()}',
                                       style: TextStyle(
                                         color: nfce.status == 'contingencia'
                                             ? Colors.amber
                                             : (isAutorizada ? Colors.green : (isErro ? Colors.redAccent : Colors.orange)),
                                         fontWeight: FontWeight.bold,
                                       ),
                                     ),
                                     if (nfce.status?.toUpperCase() == 'ERRO' && nfce.xmlRetorno != null)
                                       Text('${nfce.xmlRetorno}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                     
                                     if (isAutorizada || nfce.status == 'cancelada' || nfce.status == 'sucesso' || isErro || nfce.status == 'contingencia')
                                       Padding(
                                         padding: const EdgeInsets.only(top: 8),
                                         child: Row(
                                           children: [
                                             if (isAutorizada)
                                               TextButton.icon(
                                                 onPressed: () => _confirmarCancelamento(context, nfce),
                                                 icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 18),
                                                 label: const Text('CANCELAR', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                                                 style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                               ),
                                             if (nfce.status == 'contingencia') ...[
                                               TextButton.icon(
                                                 onPressed: () => _transmitirContingenciaIndividual(context, nfce),
                                                 icon: const Icon(Icons.send_rounded, color: Colors.amber, size: 18),
                                                 label: const Text('TRANSMITIR AGORA', style: TextStyle(color: Colors.amber, fontSize: 11)),
                                                 style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                               ),
                                               const SizedBox(width: 8),
                                               TextButton.icon(
                                                 onPressed: () async {
                                                   final dataService = Provider.of<DataService>(context, listen: false);
                                                   // Remove da contingência
                                                   await NfceContingenciaService.instance.removerDaFila(nfce.id);
                                                   // Remove do local
                                                   dataService.vendasBalcao.removeWhere((v) => v.id == nfce.vendaId);
                                                   _loadData();
                                                 },
                                                 icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                                 label: const Text('DESCARTE', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                                                 style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                               ),
                                             ],
                                             const SizedBox(width: 8),
                                             if (isAutorizada || nfce.status == 'sucesso')
                                               TextButton.icon(
                                                 onPressed: () => _reimprimir(context, nfce),
                                                 icon: const Icon(Icons.print, color: Colors.blueAccent, size: 18),
                                                 label: const Text('REIMPRIMIR', style: TextStyle(color: Colors.blueAccent, fontSize: 11)),
                                                 style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                               ),
                                             if (isErro)
                                               TextButton.icon(
                                                 onPressed: () => _reemitirNFCe(context, nfce),
                                                 icon: const Icon(Icons.refresh, color: Colors.orange, size: 18),
                                                 label: const Text('REEMITIR AGORA', style: TextStyle(color: Colors.orange, fontSize: 11)),
                                                 style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                               ),
                                             const SizedBox(width: 8),
                                             if (isAutorizada || nfce.status == 'sucesso')
                                               TextButton.icon(
                                                 onPressed: () => _baixarNFCeIndividual(context, nfce),
                                                 icon: const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 18),
                                                 label: const Text('BAIXAR', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                                                 style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                               ),
                                           ],
                                         ),
                                       ),
                                  ],
                                ),
                              ),
                              Text(
                                NumberFormat.currency(locale: "pt_BR", symbol: "R\$").format(nfce.valorTotal),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarCancelamento(BuildContext context, NFCe nfce) async {
    final justificativaController = TextEditingController(text: 'Cancelamento por erro de emissao ou devolucao de mercadoria');
    
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirmar Cancelamento', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja realmente cancelar esta NFC-e na SEFAZ?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextField(
              controller: justificativaController,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Justificativa (mín. 15 caracteres)',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('VOLTAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (justificativaController.text.length < 15) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A justificativa deve ter pelo menos 15 caracteres.')));
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('CONFIRMAR CANCELAMENTO'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      _cancelarNFCe(nfce, justificativaController.text);
    }
  }

  void _cancelarNFCe(NFCe nfce, String justificativa) async {
    setState(() => _isLoading = true);
    try {
      final nfceService = NFCeServiceFactory.criar();
      
      if (nfceService is! NFCeBackendService) {
         throw Exception('O cancelamento só está disponível no modo Bridge (Python).');
      }

      final resultado = await nfceService.cancelarNFCe(
        nfce: nfce,
        empresa: widget.empresa,
        justificativa: justificativa,
      );

      if (resultado['success'] == true) {
        if (!mounted) return;
        // Atualizar localmente via DataService para garantir atualização do contador de números
        final dataService = Provider.of<DataService>(context, listen: false);
        final nfceCancelada = nfce.copyWith(
          status: 'cancelada',
          updatedAt: DateTime.now(),
        );
        await dataService.atualizarNFCe(nfceCancelada);
        
        if (!mounted) return;
        ExodoCancelSuccessDialog.mostrar(context, nfceCancelada);
        _loadData(); // Recarregar lista
      } else {
        if (!mounted) return;
        _mostrarErro('Erro ao cancelar: ${resultado['message']}');
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarErro('Falha técnica: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _consultarNFCe(NFCe nfce) async {
    setState(() => _isLoading = true);
    try {
      final nfceService = NFCeServiceFactory.criar();
      
      if (nfceService is! NFCeBackendService) {
         throw Exception('A consulta só está disponível no modo Bridge (Python).');
      }

      final resultado = await nfceService.consultar(
        chaveAcesso: nfce.chaveAcesso!,
        empresa: widget.empresa,
      );

      if (resultado['success'] == true) {
        final cStat = resultado['cStat'];
        final xMotivo = resultado['xMotivo'];
        final novoStatus = resultado['status']; // 'cancelada' ou 'autorizada'

        if (!mounted) return;

        // Se o status na SEFAZ for diferente do local, perguntar se quer atualizar
        if (novoStatus != nfce.status && (novoStatus == 'cancelada' || novoStatus == 'autorizada')) {
           final bool? atualizar = await showDialog<bool>(
             context: context,
             builder: (context) => AlertDialog(
               backgroundColor: const Color(0xFF1E1E1E),
               title: const Text('Divergência de Status', style: TextStyle(color: Colors.white)),
               content: Text('Na SEFAZ esta nota consta como: $novoStatus.\nNo sistema local ela está como: ${nfce.status}.\n\nDeseja atualizar o sistema local?', style: const TextStyle(color: Colors.white70)),
               actions: [
                 TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NÃO')),
                 ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('SIM, ATUALIZAR')),
               ],
             ),
           );

           if (atualizar == true) {
              final dataService = Provider.of<DataService>(context, listen: false);
              final nfceAtualizada = nfce.copyWith(
                status: novoStatus,
                updatedAt: DateTime.now(),
              );
              await dataService.atualizarNFCe(nfceAtualizada);
              _loadData();
           }
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Consulta SEFAZ: [$cStat] $xMotivo'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.teal,
        ));
      } else {
        if (!mounted) return;
        _mostrarErro('Erro ao consultar: ${resultado['error']}');
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarErro('Falha técnica: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _reimprimir(BuildContext context, NFCe nfce) async {
    try {
      await DANFEService.imprimir(
        nfce: nfce,
        empresa: widget.empresa,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao imprimir: $e')));
    }
  }

  Future<void> _transmitirContingenciaIndividual(BuildContext context, NFCe nfce) async {
    setState(() => _isLoading = true);
    try {
      final sucessos = await NfceContingenciaService.instance.tentarRetransmitirTudo(
        onSucesso: (novaNfce) async {
          final dataService = Provider.of<DataService>(context, listen: false);
          await dataService.adicionarNFCe(novaNfce);
        },
        onErro: (num, err) {
          _mostrarErro('Erro ao transmitir nota $num: $err');
        },
      );
      if (sucessos > 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nota em contingência transmitida com sucesso!')));
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível transmitir a nota. Verifique se o Bridge está online.'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      _mostrarErro('Erro ao retransmitir: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _baixarNFCeIndividual(BuildContext context, NFCe nfce) async {
    try {
      final dt = nfce.createdAt ?? nfce.dataEmissao;
      final mesDir = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      final cnpj = (widget.empresa.cnpj ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      final nomePasta = 'NFCe_${nfce.numero}_${nfce.serie}';
      final dir = Directory('C:\\ExodoNFCe\\$cnpj\\$mesDir\\$nomePasta');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      // Salvar XML
      final xml = (nfce.xmlEnviado ?? '').trim();
      if (xml.isNotEmpty) {
        final nomeXml = nfce.chaveAcesso != null ? '${nfce.chaveAcesso}-nfe.xml' : 'NFCe_${nfce.numero}-nfe.xml';
        File('${dir.path}\\$nomeXml').writeAsStringSync(xml);
      }

      // Gerar e salvar PDF
      try {
        final pdfBytes = await DANFEService.gerarPDF(nfce: nfce, empresa: widget.empresa);
        final nomePdf = 'NFCe_${nfce.numero}_${nfce.serie}_${DateFormat('yyyyMMdd').format(dt)}.pdf';
        File('${dir.path}\\$nomePdf').writeAsBytesSync(pdfBytes);
      } catch (pdfErr) {
        debugPrint('[PDF] Erro ao gerar PDF: $pdfErr');
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.check_circle, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text('Nota Baixada!', style: TextStyle(color: Colors.white)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('XML e PDF salvos em:', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              SelectableText(
                dir.path,
                style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Process.run('explorer.exe', [dir.path]);
              },
              icon: const Icon(Icons.folder_open, color: Colors.amber),
              label: const Text('ABRIR PASTA', style: TextStyle(color: Colors.amber)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('FECHAR', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao baixar: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _mostrarDetalhesVenda(BuildContext context, NFCe nfce, DataService dataService) {
    VendaBalcao? venda;
    try {
      venda = dataService.vendasBalcao.firstWhere(
        (v) => v.id == nfce.vendaId || v.numero == nfce.vendaNumero,
      );
    } catch (_) {}

    if (venda == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Venda correspondente não encontrada no banco de dados local.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dt = DateFormat('dd/MM/yyyy HH:mm').format(venda.dataVenda);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detalhes da Venda ${venda!.numero}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Data: $dt',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 20),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const Text(
                      'ITENS DA VENDA',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...venda.itens.map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.nome,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (item.fornecedorNome != null)
                                    Text(
                                      'Fornecedor: ${item.fornecedorNome}',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '${item.quantidade.toStringAsFixed(0)}x ${formatoMoeda.format(item.precoUnitario)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const Divider(color: Colors.white10, height: 24),
                    const Text(
                      'RESUMO DO PAGAMENTO',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildRowResumo(
                      'Forma de Pagamento',
                      venda.pagamentos.isNotEmpty
                          ? venda.pagamentos
                              .map((p) =>
                                  '${p.tipo.nome} (${formatoMoeda.format(p.valor)})')
                              .join(' + ')
                          : venda.tipoPagamento.nome,
                    ),
                    if (venda.clienteNome != null)
                      _buildRowResumo('Cliente', venda.clienteNome!),
                    if (venda.operador != null)
                      _buildRowResumo('Operador', venda.operador!),
                    if (venda.vendedorNome != null)
                      _buildRowResumo('Vendedor', venda.vendedorNome!),
                    const Divider(color: Colors.white10, height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL DA VENDA',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          formatoMoeda.format(venda.valorTotal),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRowResumo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _reemitirNFCe(BuildContext context, NFCe nfce) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioAtual = authService.usuarioAtual;
    final proximoNum = dataService.getProximoNumeroNfce(
      serie: usuarioAtual?.serieNfce.toString() ?? '1',
      numeroInicial: usuarioAtual?.numeroInicialNfce ?? 1,
    ).toString();
    final controller = TextEditingController(text: proximoNum);

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Reemitir NFC-e', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja realmente retransmitir esta NFC-e agora?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            const Text('O sistema sugere o próximo número oficial disponível (notas com erro NÃO seguram número):', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Número da Nota',
                labelStyle: TextStyle(color: Colors.orange),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('VOLTAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('REEMITIR AGORA'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() => _isLoading = true);
      try {
        final nfceService = NFCeServiceFactory.criar();
        
        // Reconstruir produtos a partir dos itens da NFC-e falha
        final List<Produto> produtos = nfce.itens.map((item) => Produto(
          id: item.produtoId,
          codigo: item.codigo,
          nome: item.descricao,
          preco: item.valorUnitario,
          unidade: item.unidade,
          ncm: item.ncm,
          cfop: item.cfop,
          estoque: 0,
          grupo: 'Geral', // Campo obrigatório
          createdAt: DateTime.now(), // Campo obrigatório
          updatedAt: DateTime.now(), // Campo obrigatório
        )).toList();

        final Map<String, double> quantidades = {};
        for (final item in nfce.itens) {
          quantidades[item.produtoId] = item.quantidade;
        }

        final novaNfce = await nfceService.emitir(
          empresa: widget.empresa,
          produtos: produtos,
          quantidades: quantidades,
          pagamentos: nfce.pagamentos,
          valorTotal: nfce.valorTotal,
          cpfCnpjConsumidor: nfce.cpfCnpjConsumidor,
          nomeConsumidor: nfce.nomeConsumidor,
          vendaId: nfce.vendaId,
          vendaNumero: controller.text, // NOVO NÚMERO
          ambienteHomologacao: widget.empresa.configuracoes?['ambiente_nfe'] == 'Produção' ? false : true,
        );

        await dataService.adicionarNFCe(novaNfce);

        // Salvar XML automaticamente em C:\ExodoNFCe\
        NfceXmlLocalService.salvarXmlAposEmissao(nfce: novaNfce, empresa: widget.empresa);
        
        if (novaNfce.status == 'autorizada') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('NFC-e reemitida com sucesso!')));
          _loadData();
        } else {
           _mostrarErro('Status da emissão: ${novaNfce.status?.toUpperCase()}\n\nRetorno: ${novaNfce.xmlRetorno ?? "Falha na reemissão"}');
        }
      } catch (e) {
        _mostrarErro('Erro ao reemitir: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _mostrarErro(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Atenção', style: TextStyle(color: Colors.white)),
        content: Text(msg, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickFilterChip(String label, VoidCallback onTap, {bool isCustom = false}) {
    bool selected = false;
    final start = _periodoFiltro?.start;
    final end = _periodoFiltro?.end;
    final agora = DateTime.now();

    if (label == 'Hoje' && start != null && end != null) {
      selected = start.day == agora.day && start.month == agora.month && start.year == agora.year;
    } else if (label == 'Este Mês' && start != null) {
      selected = start.day == 1 && start.month == agora.month && start.year == agora.year;
    } else if (isCustom && _periodoFiltro != null) {
      // Verificamos se não cai nas outras categorias
      final isHoje = start?.day == agora.day && start?.month == agora.month;
      final isMes = start?.day == 1 && start?.month == agora.month;
      selected = !isHoje && !isMes;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          isCustom && selected 
            ? '${DateFormat('dd/MM').format(start!)} - ${DateFormat('dd/MM').format(end!)}' 
            : label, 
          style: TextStyle(color: selected ? Colors.white : Colors.white60, fontSize: 12)
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: Colors.white.withOpacity(0.05),
        selectedColor: Colors.orange.withOpacity(0.4),
        side: BorderSide(color: selected ? Colors.orange : Colors.white10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildSummaryBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}
