import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/empresa.dart';

/// Serviço central de impressão.
///
/// Permite selecionar e salvar a impressora padrão do sistema, além de
/// oferecer alternância simples antes da impressão ou através da pré-visualização.
class ImpressaoService {
  /// Imprime bytes de PDF.
  ///
  /// Ordem:
  /// 1. Se `mostrarDialogoImpressora` = true OU se nenhuma impressora foi configurada ainda:
  ///    Abre o diálogo visual de seleção para o usuário escolher a impressora e salvá-la como padrão.
  /// 2. Se `mostrarPreviewImpressao` = true → abre a tela de preview.
  /// 3. Se `imprimirDireto` = true (padrão) → envia direto para a impressora padrão escolhida.
  /// 4. Fallback → diálogo nativo de impressão.
  static Future<void> imprimirPdf({
    required Uint8List bytes,
    required Empresa empresa,
    String name = 'Documento',
    bool termico = true,
    BuildContext? context,
    bool forcarPreview = false,
  }) async {
    final config = empresa.configuracoes ?? {};
    final bool mostrarPreview = forcarPreview || (config['mostrarPreviewImpressao'] == true);
    final bool imprimirDireto = config['imprimirDireto'] != false; // padrão: true
    // 'Sempre perguntar a impressora' é individualizado por TERMINAL (local da máquina).
    // A preferência local tem prioridade; se não definida, usa a config da empresa (Portal).
    final bool semprePerguntarLocal = await _semprePerguntarLocal();
    final bool mostrarDialogoImpressora =
        semprePerguntarLocal || config['mostrarDialogoImpressora'] == true;

    // Prioridade de Impressora:
    // 1º Impressora Padrão Local deste Terminal (salva em SharedPreferences da máquina)
    // 2º Impressora Padrão da Empresa (salva no banco/empresa)
    // 3º Nome de impressora térmica genérico
    final String? ultimaSalva = await _ultimaImpressora(empresaId: empresa.id);
    final String? sel = (config['impressoraSelecionada'] as String?)?.trim();
    final String? termica = (config['impressoraTermicaNome'] as String?)?.trim();

    String? nomeConfigurado = (ultimaSalva != null && ultimaSalva.isNotEmpty)
        ? ultimaSalva
        : ((sel != null && sel.isNotEmpty)
            ? sel
            : termica);

    // Se 'mostrarDialogoImpressora' estiver ativo OU se nenhuma impressora padrão tiver sido definida:
    final bool semImpressoraSalva = (nomeConfigurado == null || nomeConfigurado.isEmpty);
    final bool deveExibirDialogo = (mostrarDialogoImpressora || semImpressoraSalva) &&
        !kIsWeb &&
        context != null &&
        context.mounted;

    if (deveExibirDialogo) {
      final String? escolhida = await exibirDialogoSelecaoImpressora(
        context,
        empresa: empresa,
        impressoraAtual: nomeConfigurado,
        somenteLocal: true,
      );

      if (escolhida == null) {
        // Usuário cancelou o diálogo de impressão
        debugPrint('[Impressao] Seleção cancelada pelo usuário.');
        return;
      }
      nomeConfigurado = escolhida;
    }

    final PdfPageFormat format = termico
        ? const PdfPageFormat(
            80 * PdfPageFormat.mm,
            double.infinity,
            marginAll: 0,
          )
        : PdfPageFormat.a4;

    // 1) Preview explícito (quando o usuário solicitou pré-visualizar)
    if (mostrarPreview && context != null && context.mounted) {
      await _showPdfPreview(context, bytes, name, empresa: empresa, isTermico: termico);
      return;
    }

    // 2) Impressão direta (desktop Windows / macOS / Linux)
    if (imprimirDireto && !kIsWeb) {
      try {
        final printer = await _resolverImpressora(nomeConfigurado, empresaId: empresa.id);
        if (printer != null) {
          debugPrint('[Impressao] Impressão Direta → ${printer.name}');
          final ok = await Printing.directPrintPdf(
            printer: printer,
            onLayout: (_) async => bytes,
            name: name,
            format: format,
            usePrinterSettings: true,
            dynamicLayout: false,
          );
          if (ok) return;
          debugPrint('[Impressao] directPrint retornou false, tentando fallback');
        } else {
          debugPrint('[Impressao] Nenhuma impressora resolvida (config: $nomeConfigurado)');
        }
      } catch (e) {
        debugPrint('[Impressao] Falha na impressão direta: $e — acionando fallback');
      }
    }

    // 3) Fallback: diálogo nativo de impressão
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: name,
      format: format,
      usePrinterSettings: true,
      dynamicLayout: false,
    );
  }

  /// Imprime bytes de PDF em uma impressora ESPECÍFICA (pelo nome).
  ///
  /// Usado pelos tickets de produção: cada setor (Cozinha, Bar, ...) tem a sua
  /// impressora, então o documento vai direto para a impressora indicada.
  /// Se a impressora não for encontrada, tenta a padrão do sistema e, em último
  /// caso, cai no diálogo nativo de impressão (sem bloquear a venda).
  static Future<void> imprimirPdfNaImpressora({
    required Uint8List bytes,
    required String nomeImpressora,
    String name = 'Documento',
    bool termico = true,
  }) async {
    if (kIsWeb) {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: name,
        usePrinterSettings: true,
        dynamicLayout: false,
      );
      return;
    }

    final PdfPageFormat format = termico
        ? const PdfPageFormat(
            80 * PdfPageFormat.mm,
            double.infinity,
            marginAll: 0,
          )
        : PdfPageFormat.a4;

    try {
      // 1. Tenta a impressora indicada pelo nome (ex.: "Cozinha")
      Printer? printer = await _resolverImpressora(nomeImpressora);
      // 2. Se não achou, usa a padrão do sistema
      printer ??= await _resolverImpressora(null);
      if (printer != null) {
        debugPrint('[Impressao] Ticket de produção → ${printer.name}');
        final ok = await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => bytes,
          name: name,
          format: format,
          usePrinterSettings: true,
          dynamicLayout: false,
        );
        if (ok) return;
      }
    } catch (e) {
      debugPrint('[Impressao] Falha na impressão em "$nomeImpressora": $e — fallback');
    }

    // 3. Fallback: diálogo nativo de impressão
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: name,
      format: format,
      usePrinterSettings: true,
      dynamicLayout: false,
    );
  }

  /// Lista impressoras do sistema (vazio na web).
  static Future<List<Printer>> listarImpressoras() async {
    if (kIsWeb) return [];
    try {
      final info = await Printing.info();
      if (!info.canListPrinters) return [];
      return await Printing.listPrinters();
    } catch (e) {
      debugPrint('[Impressao] listarImpressoras: $e');
      return [];
    }
  }

  /// Imprime uma página de teste na impressora indicada (ou na padrão do terminal).
  ///
  /// Útil para o caixa confirmar, direto do PDV, que a impressora selecionada
  /// está funcionando sem precisar emitir um documento real.
  static Future<bool> testarImpressora(String nomeImpressora, {Empresa? empresa}) async {
    try {
      final agora = DateTime.now();
      final dataHora = '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} '
          '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';

      final format = const PdfPageFormat(
        80 * PdfPageFormat.mm,
        200 * PdfPageFormat.mm,
        marginAll: 0,
      );

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(8),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'TESTE DE IMPRESSÃO',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(),
              pw.SizedBox(height: 6),
              pw.Text('Impressora: $nomeImpressora', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Empresa: ${empresa?.nomeFantasia ?? empresa?.razaoSocial ?? '-'}', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Data/Hora: $dataHora', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'Se você está vendo esta página,\na impressora está funcionando corretamente.',
                  style: const pw.TextStyle(fontSize: 11),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );

      final bytes = await doc.save();

      final printer = await _resolverImpressora(nomeImpressora, empresaId: empresa?.id);
      if (printer != null) {
        final ok = await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => bytes,
          name: 'Teste_Impressao',
          format: format,
          usePrinterSettings: true,
          dynamicLayout: false,
        );
        if (ok) return true;
      }

      // Fallback: diálogo nativo de impressão
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Teste_Impressao',
        format: format,
        usePrinterSettings: true,
        dynamicLayout: false,
      );
      return true;
    } catch (e) {
      debugPrint('[Impressao] testarImpressora: $e');
      return false;
    }
  }

  /// Exibe o diálogo visual para seleção de impressora.
  ///
  /// Por padrão ([somenteLocal] = true) a escolha fica salva APENAS na máquina
  /// local (SharedPreferences) e NÃO altera a configuração compartilhada da
  /// empresa no banco — cada terminal (PDV) guarda a SUA própria impressora.
  /// Passe [somenteLocal] = false apenas no Portal/Configurações, quando o
  /// objetivo for alterar a impressora padrão da EMPRESA para todas as máquinas.
  static Future<String?> selecionarImpressoraPadrao(
    BuildContext context, {
    Empresa? empresa,
    bool somenteLocal = true,
  }) async {
    try {
      return await exibirDialogoSelecaoImpressora(
        context,
        empresa: empresa,
        somenteLocal: somenteLocal,
      );
    } catch (e) {
      debugPrint('[Impressao] selecionarImpressoraPadrao: $e');
      return null;
    }
  }

  /// Abre o modal de seleção de impressora padrão.
  ///
  /// Padrão seguro por máquina: com [somenteLocal] = true (padrão) a escolha
  /// é salva APENAS nas SharedPreferences desta máquina, sem tocar na
  /// configuração compartilhada da empresa no banco.
  static Future<String?> exibirDialogoSelecaoImpressora(
    BuildContext context, {
    Empresa? empresa,
    String? impressoraAtual,
    bool somenteLocal = true,
  }) async {
    final impressoras = await listarImpressoras();
    if (!context.mounted) return null;

    final String? salva = impressoraAtual ??
        await _ultimaImpressora(empresaId: empresa?.id) ??
        (empresa?.configuracoes?['impressoraSelecionada'] as String?) ??
        (empresa?.configuracoes?['impressoraTermicaNome'] as String?);

    Printer? selecionada;
    if (salva != null && salva.isNotEmpty && impressoras.isNotEmpty) {
      selecionada = impressoras.firstWhere(
        (p) => p.name.toLowerCase() == salva.toLowerCase(),
        orElse: () => impressoras.firstWhere(
          (p) => p.name.toLowerCase().contains(salva.toLowerCase()),
          orElse: () => impressoras.firstWhere((p) => p.isDefault, orElse: () => impressoras.first),
        ),
      );
    } else if (impressoras.isNotEmpty) {
      selecionada = impressoras.firstWhere((p) => p.isDefault, orElse: () => impressoras.first);
    }

    // Preferência local do terminal tem prioridade sobre a config da empresa
    final bool semprePerguntarLocal = await _semprePerguntarLocal();
    final bool semprePerguntar =
        semprePerguntarLocal || empresa?.configuracoes?['mostrarDialogoImpressora'] == true;

    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return _DialogoSelecaoImpressoraWidget(
          impressoras: impressoras,
          selecionadaInicial: selecionada,
          salvarComoPadraoInicial: true,
          semprePerguntarInicial: semprePerguntar,
          empresa: empresa,
          somenteLocal: somenteLocal,
        );
      },
    );
  }

  /// Chave da impressora padrão LOCAL deste terminal/máquina.
  ///
  /// O SharedPreferences é armazenado fisicamente na máquina local, então
  /// cada terminal (PDV A, PDV B, etc.) guarda a SUA própria impressora padrão
  /// sem sobrescrever as configurações da empresa no banco de dados.
  static const _chaveTerminalPadrao = 'terminal_impressora_padrao';

  /// Chave local de 'sempre perguntar a impressora ao imprimir' (por terminal).
  /// Guardada na máquina local para não alterar a config compartilhada da empresa.
  static const _chaveTerminalSemprePerguntar = 'terminal_sempre_perguntar_impressora';

  /// Salva a preferência 'sempre perguntar' local deste terminal.
  static Future<void> salvarSemprePerguntar(bool valor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_chaveTerminalSemprePerguntar, valor);
    } catch (e) {
      debugPrint('[Impressao] salvarSemprePerguntar: $e');
    }
  }

  /// Recupera a preferência 'sempre perguntar' local deste terminal.
  static Future<bool> _semprePerguntarLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_chaveTerminalSemprePerguntar) ?? false;
    } catch (e) {
      debugPrint('[Impressao] _semprePerguntarLocal: $e');
      return false;
    }
  }

  /// Salva a última impressora escolhida pelo usuário (local, por terminal).
  static Future<void> salvarUltimaImpressora(String nome, {String? empresaId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 1º: preferência LOCAL do terminal — tem prioridade máxima na impressão
      await prefs.setString(_chaveTerminalPadrao, nome);
      // Compatibilidade com versões anteriores (por empresa / global)
      if (empresaId != null && empresaId.isNotEmpty) {
        await prefs.setString('ultima_impressora_escolhida_$empresaId', nome);
      }
      await prefs.setString('ultima_impressora_escolhida_global', nome);
    } catch (e) {
      debugPrint('[Impressao] salvarUltimaImpressora: $e');
    }
  }

  /// Recupera o nome da última impressora salva como padrão.
  static Future<String?> getUltimaImpressora({String? empresaId}) async {
    return await _ultimaImpressora(empresaId: empresaId);
  }

  /// Recupera a última impressora escolhida pelo usuário (se houver).
  ///
  /// Ordem de prioridade:
  /// 1º Impressora padrão deste TERMINAL (máquina local)
  /// 2º Preferência por empresa (legado)
  /// 3º Preferência global (legado)
  static Future<String?> _ultimaImpressora({String? empresaId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 1º: impressora padrão deste terminal (local da máquina)
      final terminal = prefs.getString(_chaveTerminalPadrao);
      if (terminal != null && terminal.isNotEmpty) return terminal;
      // 2º: preferência por empresa (legado)
      if (empresaId != null && empresaId.isNotEmpty) {
        final especifica = prefs.getString('ultima_impressora_escolhida_$empresaId');
        if (especifica != null && especifica.isNotEmpty) return especifica;
      }
      // 3º: preferência global (legado)
      return prefs.getString('ultima_impressora_escolhida_global');
    } catch (e) {
      debugPrint('[Impressao] _ultimaImpressora: $e');
      return null;
    }
  }

  /// Resolve impressora: última escolhida → nome configurado → default → primeira disponível.
  static Future<Printer?> _resolverImpressora(String? nomeConfigurado, {String? empresaId}) async {
    final printers = await listarImpressoras();
    if (printers.isEmpty) return null;

    final disponiveis = printers.where((p) => p.isAvailable).toList();
    final pool = disponiveis.isNotEmpty ? disponiveis : printers;

    // 1. Prioriza o nome configurado / passado como parâmetro
    if (nomeConfigurado != null && nomeConfigurado.isNotEmpty) {
      final needle = nomeConfigurado.toLowerCase();
      final match = pool.cast<Printer?>().firstWhere(
        (p) =>
            p!.name.toLowerCase() == needle ||
            p.name.toLowerCase().contains(needle) ||
            p.url.toLowerCase().contains(needle),
        orElse: () => null,
      );
      if (match != null) return match;
    }

    // 2. Tenta a última impressora salva em SharedPreferences
    final String? ultima = await _ultimaImpressora(empresaId: empresaId);
    if (ultima != null && ultima.isNotEmpty) {
      final match = pool.cast<Printer?>().firstWhere(
        (p) =>
            p!.name.toLowerCase() == ultima.toLowerCase() ||
            p.name.toLowerCase().contains(ultima.toLowerCase()),
        orElse: () => null,
      );
      if (match != null) return match;
    }

    // 3. Tenta impressora padrão do Windows
    final padrao = pool.where((p) => p.isDefault).toList();
    if (padrao.isNotEmpty) return padrao.first;

    // 4. Heurística: impressoras térmicas comuns
    const keywords = [
      'thermal',
      'termica',
      'térmica',
      'pos',
      'epson',
      'bematech',
      'elgin',
      'daruma',
      'tanca',
      'print i',
      'printi',
      'mp-',
      'tm-',
      'cupom',
      'receipt',
      '80mm',
      '58mm',
    ];
    for (final p in pool) {
      final n = p.name.toLowerCase();
      if (keywords.any((k) => n.contains(k))) return p;
    }

    return pool.first;
  }

  static Future<void> _showPdfPreview(
    BuildContext context,
    Uint8List pdfBytes,
    String fileName, {
    required Empresa empresa,
    bool isTermico = false,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.9,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              AppBar(
                title: Text(
                  'Pré-visualização ($fileName)',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                backgroundColor: const Color(0xFF1E1E2E),
                iconTheme: const IconThemeData(color: Colors.white),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () async {
                      final escolhida = await exibirDialogoSelecaoImpressora(
                        context,
                        empresa: empresa,
                        somenteLocal: true, // troca feita na hora da impressão é local do terminal
                      );
                      if (escolhida != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Impressora padrão alterada para: $escolhida'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.settings_suggest, color: Colors.amberAccent),
                    label: const Text('Trocar Impressora', style: TextStyle(color: Colors.amberAccent)),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check, color: Colors.white70),
                    label: const Text('Fechar', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) async => pdfBytes,
                  pdfFileName: '$fileName.pdf',
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  allowPrinting: true,
                  allowSharing: true,
                  maxPageWidth: isTermico ? 320.0 : null,
                  dpi: isTermico ? 200.0 : null,
                  initialPageFormat: isTermico
                      ? const PdfPageFormat(
                          80 * PdfPageFormat.mm,
                          double.infinity,
                          marginAll: 0,
                        )
                      : PdfPageFormat.a4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget modal para seleção e alteração da impressora padrão do sistema.
class _DialogoSelecaoImpressoraWidget extends StatefulWidget {
  final List<Printer> impressoras;
  final Printer? selecionadaInicial;
  final bool salvarComoPadraoInicial;
  final bool semprePerguntarInicial;
  final Empresa? empresa;
  final bool somenteLocal; // true quando chamado do PDV (não altera config da empresa)

  const _DialogoSelecaoImpressoraWidget({
    Key? key,
    required this.impressoras,
    this.selecionadaInicial,
    this.salvarComoPadraoInicial = true,
    this.semprePerguntarInicial = false,
    this.empresa,
    this.somenteLocal = true,
  }) : super(key: key);

  @override
  State<_DialogoSelecaoImpressoraWidget> createState() => _DialogoSelecaoImpressoraWidgetState();
}

class _DialogoSelecaoImpressoraWidgetState extends State<_DialogoSelecaoImpressoraWidget> {
  late Printer? _impressoraSelecionada;
  late bool _salvarComoPadrao;
  late bool _semprePerguntar;
  late List<Printer> _listaImpressoras;
  bool _carregando = false;

  @override
  void initState() {
    super.initState();
    _listaImpressoras = List.from(widget.impressoras);
    _impressoraSelecionada = widget.selecionadaInicial ??
        (_listaImpressoras.isNotEmpty ? _listaImpressoras.first : null);
    _salvarComoPadrao = widget.salvarComoPadraoInicial;
    _semprePerguntar = widget.semprePerguntarInicial;
  }

  Future<void> _recarregarImpressoras() async {
    setState(() => _carregando = true);
    final novas = await ImpressaoService.listarImpressoras();
    if (!mounted) return;
    setState(() {
      _listaImpressoras = novas;
      if (_listaImpressoras.isNotEmpty) {
        final existe = _listaImpressoras.any((p) => p.name == _impressoraSelecionada?.name);
        if (!existe) {
          _impressoraSelecionada = _listaImpressoras.firstWhere(
            (p) => p.isDefault,
            orElse: () => _listaImpressoras.first,
          );
        }
      } else {
        _impressoraSelecionada = null;
      }
      _carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.print_rounded, color: Colors.blueAccent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Selecionar Impressora Padrão',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Escolha a impressora desejada e altere quando quiser',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  tooltip: 'Atualizar impressoras do Windows',
                  onPressed: _recarregarImpressoras,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),

            // Dropdown de seleção de impressoras
            const Text(
              'Impressora:',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
              )
            else if (_listaImpressoras.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nenhuma impressora instalada foi encontrada no Windows.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Printer>(
                    value: _listaImpressoras.contains(_impressoraSelecionada)
                        ? _impressoraSelecionada
                        : _listaImpressoras.first,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2D3E),
                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.blueAccent),
                    items: _listaImpressoras.map((printer) {
                      final isCurrentSelected = widget.selecionadaInicial?.name == printer.name;
                      final isWinDefault = printer.isDefault;
                      return DropdownMenuItem<Printer>(
                        value: printer,
                        child: Row(
                          children: [
                            Icon(
                              Icons.print,
                              size: 18,
                              color: isCurrentSelected ? Colors.greenAccent : Colors.white70,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                printer.name,
                                style: TextStyle(
                                  color: isCurrentSelected ? Colors.greenAccent : Colors.white,
                                  fontWeight: isCurrentSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCurrentSelected) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Padrão Atual',
                                  style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ] else if (isWinDefault) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Windows',
                                  style: TextStyle(color: Colors.blueAccent, fontSize: 10),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (novo) {
                      if (novo != null) {
                        setState(() => _impressoraSelecionada = novo);
                      }
                    },
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Opção 1: Salvar como impressora padrão
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: CheckboxListTile(
                title: const Text(
                  'Salvar como impressora padrão',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Guarda a escolha para não precisar configurar sempre',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: _salvarComoPadrao,
                activeColor: Colors.blueAccent,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                dense: true,
                onChanged: (val) => setState(() => _salvarComoPadrao = val ?? true),
              ),
            ),
            const SizedBox(height: 8),

            // Opção 2: Sempre perguntar ao imprimir
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: CheckboxListTile(
                title: const Text(
                  'Sempre perguntar ao imprimir',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Exibe esta janela em cada impressão para você confirmar ou trocar a impressora',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                value: _semprePerguntar,
                activeColor: Colors.blueAccent,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                dense: true,
                onChanged: (val) => setState(() => _semprePerguntar = val ?? false),
              ),
            ),

            const SizedBox(height: 24),

            // Botões de Ação
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _impressoraSelecionada == null
                      ? null
                      : () async {
                          final nome = _impressoraSelecionada!.name;
                          if (_salvarComoPadrao) {
                            await ImpressaoService.salvarUltimaImpressora(
                              nome,
                              empresaId: widget.empresa?.id,
                            );
                            // Config compartilhada da empresa (banco): só é alterada quando
                            // o diálogo vem do Portal. Pelo PDV (somenteLocal) a escolha fica
                            // apenas na máquina local — cada terminal tem a sua impressora.
                            if (!widget.somenteLocal && widget.empresa?.configuracoes != null) {
                              widget.empresa!.configuracoes!['impressoraSelecionada'] = nome;
                            }
                          }
                          // 'Sempre perguntar' também é individualizado por terminal.
                          await ImpressaoService.salvarSemprePerguntar(_semprePerguntar);
                          if (!widget.somenteLocal && widget.empresa?.configuracoes != null) {
                            widget.empresa!.configuracoes!['mostrarDialogoImpressora'] = _semprePerguntar;
                          }
                          if (mounted) {
                            Navigator.pop(context, nome);
                          }
                        },
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Imprimir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
