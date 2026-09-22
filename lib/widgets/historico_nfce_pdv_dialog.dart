import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../services/pacote_contabil_service.dart';
import 'dart:io';
import '../services/nfce_xml_local_service.dart';
import '../services/nfce_contingencia_service.dart';
import 'package:url_launcher/url_launcher.dart';
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

  /// Quantas NF-e (DANFE) foram deixadas de fora deste histórico. A tabela
  /// `nfces` chegou a guardar notas modelo 55, e elas apareciam misturadas aqui.
  int _nfesOcultas = 0;

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
      
      // 1. Carrega instantaneamente as NFC-es locais da memória/PostgreSQL.
      //    Só NFC-e: NF-e (DANFE, modelo 55) tem a sua própria tela.
      final localTodas = List<NFCe>.from(dataService.nfces);
      final localNfces = localTodas.where((n) => n.ehNFCe).toList();
      localNfces.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
      
      setState(() {
        _todasNfces = localNfces;
        _nfesOcultas = localTodas.where((n) => n.ehNFe).length;
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
            
        final serverTodas = results.map((map) => NFCe.fromMap(map)).toList();
        
        // Merge das notas locais com as do servidor (4. todas, 5. depois separa)
        final Map<String, NFCe> mergeMap = {};
        for (final n in localTodas) {
          mergeMap[n.id] = n;
        }
        for (final n in serverTodas) {
          mergeMap[n.id] = n;
        }
        
        final todasMerged = mergeMap.values.toList();
        final mergedList = todasMerged.where((n) => n.ehNFCe).toList();
        mergedList.sort((a, b) => (b.createdAt ?? DateTime.now()).compareTo(a.createdAt ?? DateTime.now()));
        
        if (mounted) {
          setState(() {
            _todasNfces = mergedList;
            _nfesOcultas = todasMerged.where((n) => n.ehNFe).length;
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
      final inicio = periodo.start;
      final fim = periodo.end;

      final nfcesNoPeriodo =
          _todasNfces.where((n) => _dentroDoPeriodo(n.createdAt, inicio, fim)).toList();

      final todasVendasNoPeriodo = dataService.vendasBalcao
          .where((v) => !v.cancelado && _dentroDoPeriodo(v.dataVenda, inicio, fim))
          .toList();

      // Os relatórios (PDF fiscal + Excel detalhado) e os XMLs vêm do
      // PacoteContabilService — a MESMA implementação usada no Portal do
      // Contador, para os dois nunca divergirem.
      final resultado = await PacoteContabilService.gerarPacote(
        empresa: widget.empresa,
        nfces: nfcesNoPeriodo,
        vendas: todasVendasNoPeriodo,
        produtos: dataService.produtos,
        inicio: inicio,
        fim: fim,
        obterXml: (nfce) async => _xmlDaNota(nfce),
      );

      final periodoTag = PacoteContabilService.tagPeriodo(inicio, fim);
      final fileName = 'pacote_contabil_nfce_$periodoTag.zip';

      if (kIsWeb) {
        html_helper.downloadBytes(resultado.zip, fileName, 'application/zip');
      } else {
        // ── Desktop: pasta descompactada + ZIP em C:\ExodoNFCe\Pacotes
        final pastaPacotes = Directory(r'C:\ExodoNFCe\Pacotes');
        if (!pastaPacotes.existsSync()) pastaPacotes.createSync(recursive: true);

        final pastaDestino =
            Directory('${pastaPacotes.path}\\pacote_contabil_nfce_$periodoTag');
        if (!pastaDestino.existsSync()) pastaDestino.createSync(recursive: true);

        // Relatório fiscal agrupado (PDF)
        File('${pastaDestino.path}\\relatorio_fiscal_agrupado_$periodoTag.pdf')
            .writeAsBytesSync(resultado.pdfFiscal);

        // Planilha detalhada (Excel)
        final excelBytes = resultado.excel;
        if (excelBytes != null) {
          File('${pastaDestino.path}\\detalhado_dados_nfce_$periodoTag.xlsx')
              .writeAsBytesSync(excelBytes);
        }

        // LEIA-ME com o resumo do pacote
        File('${pastaDestino.path}\\LEIA-ME.txt')
            .writeAsStringSync(resultado.leiaMe);

        // ZIP completo na pasta de Pacotes
        File('${pastaPacotes.path}\\$fileName').writeAsBytesSync(resultado.zip);

        // XMLs na pasta do contador e no repositório local do C:\
        final pastaXmls = Directory('${pastaDestino.path}\\xml');
        if (!pastaXmls.existsSync()) pastaXmls.createSync(recursive: true);

        final cnpj = (widget.empresa.cnpj ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        for (final n in nfcesNoPeriodo) {
          final chave = (n.chaveAcesso ?? '').trim();
          final xml = resultado.xmls[chave];
          if (chave.isEmpty || xml == null) continue;

          File('${pastaXmls.path}\\$chave-nfe.xml').writeAsStringSync(xml);

          final dt = n.createdAt;
          final mesDir = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
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
                'Notas: ${nfcesNoPeriodo.length}   |   XMLs incluídos: ${resultado.xmlCount}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                'Inclui: XMLs, relatório fiscal (PDF) e Excel detalhado.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
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
                  final body = Uri.encodeComponent('Olá,\n\nSegue em anexo o pacote fiscal das NFC-e emitidas entre ${DateFormat('dd/MM/yyyy').format(inicio)} e ${DateFormat('dd/MM/yyyy').format(fim)}.\n\nEmpresa: ${widget.empresa.razaoSocial}\nCNPJ: ${widget.empresa.cnpj ?? "N/D"}\n\nArquivo salvo em: C:\\ExodoNFCe\\Pacotes\\$fileName\n\nGerado pelo Sistema Êxodo.');
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
    } catch (e) {
      debugPrint('Erro na exportação: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// true quando [data] cai dentro do período informado (inclusive os extremos).
  bool _dentroDoPeriodo(DateTime data, DateTime inicio, DateTime fim) {
    final de = DateTime(inicio.year, inicio.month, inicio.day);
    final ate = DateTime(fim.year, fim.month, fim.day, 23, 59, 59);
    return data.isAfter(de.subtract(const Duration(seconds: 1))) &&
        data.isBefore(ate.add(const Duration(seconds: 1)));
  }

  /// XML da nota para o pacote: usa o que estiver no banco e, quando vazio,
  /// o arquivo que o sistema salvou em C:\ExodoNFCe.
  String _xmlDaNota(NFCe nfce) {
    var xml = (nfce.xmlEnviado ?? '').trim();
    if (xml.isNotEmpty) return xml;

    final chave = (nfce.chaveAcesso ?? '').trim();
    if (chave.isEmpty) return '';

    final dt = nfce.createdAt;
    final mesDir = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    final cnpj = (widget.empresa.cnpj ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final pastaNota = 'NFCe_${nfce.numero}_${nfce.serie}';

    var localFile = File('C:\\ExodoNFCe\\$cnpj\\$mesDir\\$pastaNota\\$chave-nfe.xml');
    if (!localFile.existsSync()) {
      localFile = File('C:\\ExodoNFCe\\$cnpj\\$mesDir\\$chave-nfe.xml');
    }
    if (localFile.existsSync()) {
      xml = localFile.readAsStringSync();
    }
    return xml;
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
                Row(
                  children: [
                    if (_todasNfces.any((n) => n.status == 'contingencia' || n.status == 'pendente'))
                      TextButton.icon(
                        onPressed: _reenviarTodasPendentes,
                        icon: const Icon(Icons.send_rounded, color: Colors.amber, size: 18),
                        label: Text('REENVIAR PENDENTES (${_todasNfces.where((n) => n.status == "contingencia" || n.status == "pendente").length})',
                          style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.amber.withOpacity(0.15),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                  ],
                ),
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
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSummaryBadge(
                      'TOTAL: ${_nfcesFiltradas.length}',
                      Colors.blue,
                    ),
                    _buildSummaryBadge(
                      'FISCAL: R\$ ${NumberFormat.currency(locale: "pt_BR", symbol: "").format(_nfcesFiltradas.where((n) => n.status == "autorizada" || n.status == "sucesso").fold(0.0, (sum, n) => sum + n.valorTotal))}',
                      Colors.green,
                    ),
                    if (_nfcesFiltradas.any((n) => n.status == 'contingencia' || n.status == 'pendente'))
                      _buildSummaryBadge(
                        'PENDENTES: ${_nfcesFiltradas.where((n) => n.status == "contingencia" || n.status == "pendente").length}',
                        Colors.orange,
                      ),
                    if (_nfcesFiltradas.any((n) => n.status == 'erro' || n.status == 'rejeitada'))
                      _buildSummaryBadge(
                        'ERRO: ${_nfcesFiltradas.where((n) => n.status == "erro" || n.status == "rejeitada").length}',
                        Colors.redAccent,
                      ),
                    if (_nfcesFiltradas.any((n) => n.status == 'cancelada'))
                      _buildSummaryBadge(
                        'CANCELADAS: ${_nfcesFiltradas.where((n) => n.status == "cancelada").length}',
                        Colors.grey,
                      ),
                  ],
                ),
              ),

            if (!_isLoading && _nfesOcultas > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Colors.white38),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$_nfesOcultas NF-e (DANFE, modelo 55) desta empresa não entram neste histórico — veja em "Emissor NF-e".',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
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
                                             : (nfce.status == 'inutilizada'
                                                 ? Colors.purpleAccent
                                                 : (nfce.status == 'substituida'
                                                     ? Colors.blueGrey
                                                     : (isAutorizada ? Colors.green : (isErro ? Colors.redAccent : Colors.orange)))),
                                         fontWeight: FontWeight.bold,
                                       ),
                                     ),
                                     if (nfce.xmlRetorno != null &&
                                         nfce.xmlRetorno!.isNotEmpty &&
                                         (nfce.status?.toUpperCase() == 'ERRO' ||
                                             nfce.status == 'pendente' ||
                                             nfce.status == 'contingencia'))
                                       Text('${nfce.xmlRetorno}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                     
                                     if (isAutorizada || nfce.status == 'cancelada' || nfce.status == 'sucesso' || isErro || nfce.status == 'contingencia' || nfce.status == 'pendente')
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
                                             if (nfce.status == 'contingencia' || nfce.status == 'pendente') ...[
                                               TextButton.icon(
                                                 onPressed: () => _transmitirContingenciaIndividual(context, nfce),
                                                 icon: const Icon(Icons.send_rounded, color: Colors.amber, size: 18),
                                                 label: const Text('TRANSMITIR AGORA', style: TextStyle(color: Colors.amber, fontSize: 11)),
                                                 style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                               ),
                                               const SizedBox(width: 8),
                                               TextButton.icon(
                                                 onPressed: () => _reemitirNFCe(context, nfce),
                                                 icon: const Icon(Icons.edit_note, color: Colors.orange, size: 18),
                                                 label: const Text('CORRIGIR E REEMITIR', style: TextStyle(color: Colors.orange, fontSize: 11)),
                                                 style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                               ),
                                               const SizedBox(width: 8),
                                               TextButton.icon(
                                                 onPressed: () => _confirmarInutilizacao(context, nfce),
                                                 icon: const Icon(Icons.block, color: Colors.purpleAccent, size: 18),
                                                 label: const Text('INUTILIZAR Nº', style: TextStyle(color: Colors.purpleAccent, fontSize: 11)),
                                                 style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                               ),
                                               const SizedBox(width: 8),
                                               TextButton.icon(
                                                 onPressed: () => _descartarPendente(context, nfce),
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

  /// Descarta uma nota pendente: sai da fila de reenvio e do histórico de
  /// pendentes, sem transmitir nada para a SEFAZ.
  ///
  /// A VENDA continua no histórico de vendas (registro operacional do caixa).
  /// Se o número já foi enviado à SEFAZ, o caminho correto é INUTILIZAR Nº.
  Future<void> _descartarPendente(BuildContext context, NFCe nfce) async {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Descartar NFC-e pendente?', style: TextStyle(color: Colors.white)),
        content: Text(
          'NFC-e Nº ${nfce.numero} (série ${nfce.serie}) — ${formatoMoeda.format(nfce.valorTotal)}\n\n'
          'A nota sai da fila de reenvio e não será mais transmitida.\n'
          'Se o número já foi enviado à SEFAZ, use INUTILIZAR Nº para queimá-lo.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('DESCARTAR'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _isLoading = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);

      // O `id` do registro NÃO é o `id` da fila: a remoção por número encontra
      // a entrada do reenvio automático (antes a nota reaparecia).
      final removidas = await NfceContingenciaService.instance.removerDaFilaPorNumero(nfce.numero);

      // Sai da lista de pendentes (mantém o registro para auditoria).
      await dataService.atualizarNFCe(nfce.copyWith(
        status: 'descartada',
        updatedAt: DateTime.now(),
      ));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(removidas > 0
            ? 'NFC-e ${nfce.numero} descartada (removida da fila de reenvio).'
            : 'NFC-e ${nfce.numero} descartada (não estava mais na fila de reenvio).'),
        backgroundColor: Colors.orange,
      ));
      _loadData();
    } catch (e) {
      _mostrarErro('Erro ao descartar: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Pede a justificativa e confirma a INUTILIZAÇÃO do número da nota.
  Future<void> _confirmarInutilizacao(BuildContext context, NFCe nfce) async {
    final numero = int.tryParse(nfce.numero.trim()) ?? 0;
    if (numero <= 0) {
      _mostrarErro('Número inválido para inutilização ("${nfce.numero}").');
      return;
    }

    final justificativaController = TextEditingController(
      text: 'Quebra de sequencia de numeracao por falha na emissao da NFC-e ${nfce.numero}',
    );

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final justicaTexto = justificativaController.text.trim();
          final justificativaValida = justicaTexto.length >= 15;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.block, color: Colors.purpleAccent, size: 26),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Inutilizar numeração', style: TextStyle(color: Colors.white, fontSize: 18)),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NFC-e (modelo ${nfce.modelo ?? 65}) | Série ${nfce.serie} | Nº ${nfce.numero}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'O número é enviado ao serviço NFeInutilizacao4 da SEFAZ e fica "queimado": '
                    'nenhuma nota poderá ser emitida com ele depois.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: justificativaController,
                    maxLength: 255,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Justificativa (mínimo 15 caracteres)',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const Text(
                    'Use esta opção só quando a nota NÃO existe na SEFAZ. Se ela foi autorizada, use CANCELAR.',
                    style: TextStyle(color: Colors.amber, fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                onPressed: justificativaValida ? () => Navigator.pop(context, true) : null,
                icon: const Icon(Icons.block, size: 18),
                label: Text('INUTILIZAR Nº ${nfce.numero}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmar != true) return;
    await _inutilizarNFCe(context, nfce, justificativaController.text.trim());
  }

  /// Envia a inutilização ao bridge (SEFAZ) e, se homologada, tira a nota da
  /// fila de reenvio e marca o registro como 'inutilizada'.
  Future<void> _inutilizarNFCe(BuildContext context, NFCe nfce, String justificativa) async {
    setState(() => _isLoading = true);
    try {
      final nfceService = NFCeServiceFactory.criar();

      if (nfceService is! NFCeBackendService) {
        throw Exception('A inutilização só está disponível no modo Bridge (Python).');
      }

      final resultado = await nfceService.inutilizarNFCe(
        nfce: nfce,
        empresa: widget.empresa,
        justificativa: justificativa,
      );

      final dataService = Provider.of<DataService>(context, listen: false);

      if (resultado['success'] == true) {
        // O número foi queimado na SEFAZ: sai da fila de reenvio automático.
        await NfceContingenciaService.instance.removerDaFilaPorNumero(nfce.numero);

        final protocolo = resultado['protocolo']?.toString();
        await dataService.atualizarNFCe(nfce.copyWith(
          status: 'inutilizada',
          protocolo: protocolo,
          xmlRetorno: 'Inutilização homologada (cStat ${resultado['cStat']}): ${resultado['message']}',
          updatedAt: DateTime.now(),
        ));

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            resultado['ja_inutilizada'] == true
                ? 'O número ${nfce.numero} já estava inutilizado na SEFAZ.'
                : 'Número ${nfce.numero} inutilizado na SEFAZ${protocolo != null && protocolo.isNotEmpty ? ' (protocolo $protocolo)' : ''}.',
          ),
          backgroundColor: Colors.purple,
        ));
        _loadData();
      } else {
        _mostrarErro('A SEFAZ recusou a inutilização:\n\n${resultado['message']}');
      }
    } catch (e) {
      _mostrarErro('Erro ao inutilizar numeração: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _reenviarTodasPendentes() async {
    final pendentes = _todasNfces.where((n) => n.status == 'contingencia' || n.status == 'pendente').toList();
    if (pendentes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma NFC-e pendente para reenviar.')),
      );
      return;
    }

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Reenviar Pendentes', style: TextStyle(color: Colors.white)),
        content: Text(
          'Deseja reenviar ${pendentes.length} NFC-e pendente(s)?\n\nTotal: R\$ ${NumberFormat.currency(locale: "pt_BR", symbol: "").format(pendentes.fold(0.0, (sum, n) => sum + n.valorTotal))}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('REENVIAR TODAS'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _isLoading = true);
    try {
      int sucessos = 0;
      int falhas = 0;
      
      for (final nfce in pendentes) {
        try {
          if (nfce.status == 'contingencia') {
            // Para contingência, usar o método de retransmissão existente
            await NfceContingenciaService.instance.tentarRetransmitirTudo(
              onSucesso: (novaNfce) async {
                final dataService = Provider.of<DataService>(context, listen: false);
                await dataService.adicionarNFCe(novaNfce);
                sucessos++;
              },
            );
          } else {
            // Para pendente, reemitir via service
            final nfceService = NFCeServiceFactory.criar();
            final List<Produto> produtos = nfce.itens.map((item) => Produto(
              id: item.produtoId,
              codigo: item.codigo,
              nome: item.descricao,
              preco: item.valorUnitario,
              unidade: item.unidade,
              ncm: item.ncm,
              cfop: item.cfop,
              estoque: 0,
              grupo: 'Geral',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
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
              vendaNumero: nfce.vendaNumero,
              ambienteHomologacao: widget.empresa.configuracoes?['ambiente_nfe'] == 'Produção' ? false : true,
            );
            
            final dataService = Provider.of<DataService>(context, listen: false);
            if (novaNfce.status == 'autorizada') {
              await dataService.adicionarNFCe(novaNfce);
              sucessos++;
            } else {
              // Continua pendente (rejeitada de novo): atualiza o registro
              // existente em vez de criar um duplicado a cada tentativa.
              await dataService.atualizarNFCe(novaNfce.copyWith(id: nfce.id));
              falhas++;
            }
          }
        } catch (e) {
          debugPrint('[Reenviar] Erro ao reenviar nota ${nfce.numero}: $e');
          falhas++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reenvio concluído: $sucessos sucesso(s), $falhas falha(s)'),
          backgroundColor: sucessos > 0 ? Colors.green : Colors.orange,
        ));
        _loadData();
      }
    } catch (e) {
      _mostrarErro('Erro ao reenviar pendentes: $e');
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
    // Abrir diálogo de correção + reenvio
    await _corrigirReemitirNFCe(context, nfce);
  }

  /// Diálogo completo para corrigir dados e reenviar NFC-e
  Future<void> _corrigirReemitirNFCe(BuildContext context, NFCe nfce) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioAtual = authService.usuarioAtual;
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    // Controladores editáveis
    final numController = TextEditingController(
      text: dataService.getProximoNumeroNfce(
        serie: usuarioAtual?.serieNfce.toString() ?? '1',
        numeroInicial: usuarioAtual?.numeroInicialNfce ?? 1,
      ).toString(),
    );
    final cpfController = TextEditingController(text: nfce.cpfCnpjConsumidor ?? '');
    final nomeController = TextEditingController(text: nfce.nomeConsumidor ?? '');
    
    // Itens editáveis
    final itensEditados = nfce.itens.map((item) => _ItemEditavel(
      produtoId: item.produtoId,
      codigo: item.codigo,
      descricao: item.descricao,
      ncm: item.ncm,
      cfop: item.cfop,
      unidade: item.unidade,
      quantidadeController: TextEditingController(text: item.quantidade.toStringAsFixed(item.quantidade == item.quantidade.roundToDouble() ? 0 : 2)),
      valorUnitarioController: TextEditingController(text: item.valorUnitario.toStringAsFixed(2)),
    )).toList();
    
    // Pagamentos editáveis
    final pagamentosEditaveis = nfce.pagamentos.map((p) => _PagamentoEditavel(
      tipo: p.tipo,
      valorController: TextEditingController(text: p.valor.toStringAsFixed(2)),
    )).toList();
    
    // Calcular total
    double calcularTotal() {
      double total = 0;
      for (final item in itensEditados) {
        final qty = double.tryParse(item.quantidadeController.text) ?? 0;
        final preco = double.tryParse(item.valorUnitarioController.text) ?? 0;
        total += qty * preco;
      }
      return total;
    }
    
    final totalAtual = ValueNotifier<double>(calcularTotal());
    
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.edit_note, color: Colors.orange, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Corrigir e Reenviar NFC-e', style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ],
          ),
          content: Container(
            width: 550,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ═══ DADOS DO CONSUMIDOR ═══
                  const Text('DADOS DO CONSUMIDOR', style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: cpfController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'CPF/CNPJ',
                            labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                            hintText: 'Somente números',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: nomeController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Nome do Consumidor',
                            labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // ═══ NÚMERO DA NOTA ═══
                  Row(
                    children: [
                      const Text('Nº ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: numController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.orange.withOpacity(0.1),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text('Série ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(nfce.serie, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // ═══ ITENS ═══
                  const Text('ITENS DA NOTA', style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: itensEditados.length,
                      itemBuilder: (context, index) {
                        final item = itensEditados[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.descricao, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  // Quantidade
                                  Expanded(
                                    child: TextField(
                                      controller: item.quantidadeController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      decoration: InputDecoration(
                                        labelText: 'Qtd',
                                        labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.05),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      ),
                                      onChanged: (_) {
                                        totalAtual.value = calcularTotal();
                                        setDialogState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Valor unitário
                                  Expanded(
                                    child: TextField(
                                      controller: item.valorUnitarioController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                                      decoration: InputDecoration(
                                        labelText: 'V. Unitário',
                                        labelStyle: const TextStyle(color: Colors.white54, fontSize: 10),
                                        prefixText: 'R\$ ',
                                        prefixStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.05),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      ),
                                      onChanged: (_) {
                                        totalAtual.value = calcularTotal();
                                        setDialogState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Subtotal
                                  SizedBox(
                                    width: 90,
                                    child: ValueListenableBuilder<double>(
                                      valueListenable: totalAtual,
                                      builder: (_, total, __) {
                                        final qty = double.tryParse(item.quantidadeController.text) ?? 0;
                                        final preco = double.tryParse(item.valorUnitarioController.text) ?? 0;
                                        final subtotal = qty * preco;
                                        return Text(
                                          formatoMoeda.format(subtotal),
                                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                          textAlign: TextAlign.right,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // ═══ PAGAMENTOS ═══
                  const Text('FORMAS DE PAGAMENTO', style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  const SizedBox(height: 8),
                  ...List.generate(pagamentosEditaveis.length, (index) {
                    final pgto = pagamentosEditaveis[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          // Tipo (somente leitura)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              pgto.tipoDescricao,
                              style: const TextStyle(color: Colors.blueAccent, fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Valor editável
                          Expanded(
                            child: TextField(
                              controller: pgto.valorController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                prefixText: 'R\$ ',
                                prefixStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onChanged: (_) {
                                totalAtual.value = calcularTotal();
                                setDialogState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  
                  // ═══ TOTAL ═══
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.withOpacity(0.2), Colors.teal.withOpacity(0.15)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL DA NOTA', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                        ValueListenableBuilder<double>(
                          valueListenable: totalAtual,
                          builder: (_, total, __) => Text(
                            formatoMoeda.format(total),
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('CORRIGIR E REENVIAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmar == true) {
      setState(() => _isLoading = true);
      try {
        final nfceService = NFCeServiceFactory.criar();
        
        // Reconstruir produtos a partir dos dados editados
        final List<Produto> produtos = itensEditados.map((item) => Produto(
          id: item.produtoId,
          codigo: item.codigo,
          nome: item.descricao,
          preco: double.tryParse(item.valorUnitarioController.text) ?? 0,
          unidade: item.unidade,
          ncm: item.ncm,
          cfop: item.cfop,
          estoque: 0,
          grupo: 'Geral',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        )).toList();

        final Map<String, double> quantidades = {};
        for (int i = 0; i < itensEditados.length; i++) {
          quantidades[itensEditados[i].produtoId] = double.tryParse(itensEditados[i].quantidadeController.text) ?? 0;
        }
        
        // Pagamentos editados
        final pagamentos = pagamentosEditaveis.map((p) => NFCePagamento(
          tipo: p.tipo,
          valor: double.tryParse(p.valorController.text) ?? 0,
        )).toList();
        
        final totalNota = calcularTotal();

        final novaNfce = await nfceService.emitir(
          empresa: widget.empresa,
          produtos: produtos,
          quantidades: quantidades,
          pagamentos: pagamentos,
          valorTotal: totalNota,
          cpfCnpjConsumidor: cpfController.text.isNotEmpty ? cpfController.text : null,
          nomeConsumidor: nomeController.text.isNotEmpty ? nomeController.text : null,
          vendaId: nfce.vendaId,
          vendaNumero: numController.text,
          ambienteHomologacao: widget.empresa.configuracoes?['ambiente_nfe'] == 'Produção' ? false : true,
        );

        final eraPendente = nfce.status == 'pendente' || nfce.status == 'contingencia';

        await dataService.adicionarNFCe(novaNfce);

        // A nota ANTIGA foi reemitida com outro número: precisa sair da fila de
        // reenvio automático, senão o timer continuaria transmitindo o número
        // velho em paralelo com a reemissão (e ela nunca sairia dos pendentes).
        if (eraPendente) {
          await NfceContingenciaService.instance.removerDaFilaPorNumero(nfce.numero);
          if (novaNfce.status == 'autorizada') {
            await dataService.atualizarNFCe(nfce.copyWith(
              status: 'substituida',
              updatedAt: DateTime.now(),
            ));
          }
        }

        // Salvar XML automaticamente em C:\ExodoNFCe\
        NfceXmlLocalService.salvarXmlAposEmissao(nfce: novaNfce, empresa: widget.empresa);
        
        if (novaNfce.status == 'autorizada') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('NFC-e corrigida e emitida com sucesso!'), backgroundColor: Colors.green),
          );
          _loadData();
        } else {
          _mostrarErro('Status da emissão: ${novaNfce.status?.toUpperCase()}\n\nRetorno: ${novaNfce.xmlRetorno ?? "Falha na emissão"}');
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

/// Modelo auxiliar para itens editáveis na correção de NFC-e
class _ItemEditavel {
  final String produtoId;
  final String codigo;
  final String descricao;
  final String ncm;
  final String cfop;
  final String unidade;
  final TextEditingController quantidadeController;
  final TextEditingController valorUnitarioController;

  _ItemEditavel({
    required this.produtoId,
    required this.codigo,
    required this.descricao,
    required this.ncm,
    required this.cfop,
    required this.unidade,
    required this.quantidadeController,
    required this.valorUnitarioController,
  });
}

/// Modelo auxiliar para pagamentos editáveis na correção de NFC-e
class _PagamentoEditavel {
  final String tipo;
  final TextEditingController valorController;

  _PagamentoEditavel({
    required this.tipo,
    required this.valorController,
  });

  String get tipoDescricao {
    switch (tipo) {
      case '01': return 'Dinheiro';
      case '02': return 'Cheque';
      case '03': return 'Cartão Crédito';
      case '04': return 'Cartão Débito';
      case '05': return 'Crédito Loja';
      case '10': return 'Vale Alimentação';
      case '11': return 'Vale Refeição';
      case '15': return 'Boleto Bancário';
      case '90': return 'Sem pagamento';
      case '99': return 'Outros';
      default: return 'Desconhecido';
    }
  }
}
