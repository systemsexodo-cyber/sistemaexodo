import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:sistema_exodo_novo/pages/html_helper_stub.dart'
    if (dart.library.html) 'package:sistema_exodo_novo/pages/html_helper_web.dart' as html_helper;
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/services/pacote_contabil_service.dart';
import 'package:sistema_exodo_novo/services/portal_contador_service.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';

const Color _fundo = Color(0xFF0F1319);
const Color _superficie = Color(0xFF1E1E2E);
const Color _destaque = Color(0xFFFF9800);

/// Portal do Contador: o escritório de contabilidade entra com CNPJ + senha e
/// baixa os XMLs das notas da empresa, separados por tipo (NFC-e emitidas,
/// NF-e emitidas e NF-e recebidas).
///
/// Acesso pelo endereço: `https://<site>/portal-contador`
class PortalContadorPage extends StatefulWidget {
  const PortalContadorPage({super.key});

  @override
  State<PortalContadorPage> createState() => _PortalContadorPageState();
}

class _PortalContadorPageState extends State<PortalContadorPage> {
  final TextEditingController _cnpjController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();

  PortalContadorSessao? _sessao;
  String _empresaId = '';

  bool _entrando = false;
  bool _carregando = false;
  String _erro = '';

  DateTime _inicio = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _fim = DateTime.now();

  List<DocumentoFiscalPortal> _documentos = [];

  @override
  void dispose() {
    _cnpjController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // LOGIN
  // ==========================================================================

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _erro = '';
    });

    try {
      final sessao = await PortalContadorService.instance.login(
        cnpj: _cnpjController.text,
        senha: _senhaController.text,
      );
      if (!mounted) return;
      setState(() {
        _sessao = sessao;
        _empresaId = sessao.empresas.first.id;
      });
      await _carregarDocumentos();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  void _sair() {
    setState(() {
      _sessao = null;
      _empresaId = '';
      _documentos = [];
      _erro = '';
      _senhaController.clear();
    });
  }

  // ==========================================================================
  // DADOS
  // ==========================================================================

  Future<void> _carregarDocumentos() async {
    final sessao = _sessao;
    if (sessao == null) return;

    setState(() {
      _carregando = true;
      _erro = '';
    });

    try {
      final documentos = await PortalContadorService.instance.listarDocumentos(
        empresaIds: [_empresaId],
        inicio: _inicio,
        fim: _fim,
      );
      if (!mounted) return;
      setState(() => _documentos = documentos);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = 'Erro ao carregar os XMLs: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _selecionarData({required bool inicial}) async {
    DateTime? escolhida;
    try {
      // ATENÇÃO: não passar `locale:` aqui. O app não declara
      // localizationsDelegates, então pedir um locale sem suporte lança
      // "No MaterialLocalizations found" e a tela fica branca no release.
      escolhida = await showDatePicker(
        context: context,
        initialDate: inicial ? _inicio : _fim,
        firstDate: DateTime(2000),
        lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      );
    } catch (e) {
      // Nunca deixar a tela em branco se o calendário falhar por qualquer motivo.
      debugPrint('>>> [PortalContador] Erro ao abrir o calendário: $e');
      _avisar('Não foi possível abrir o calendário. Tente novamente.');
      return;
    }

    if (escolhida == null || !mounted) return;

    setState(() {
      if (inicial) {
        _inicio = escolhida!;
        // Data inicial depois da final deixaria o período vazio: ajusta junto.
        if (_fim.isBefore(_inicio)) _fim = _inicio;
      } else {
        _fim = escolhida!;
        if (_inicio.isAfter(_fim)) _inicio = _fim;
      }
    });
    await _carregarDocumentos();
  }

  List<DocumentoFiscalPortal> _porTipo(TipoDocumentoPortal tipo) =>
      _documentos.where((d) => d.tipo == tipo).toList();

  // ==========================================================================
  // DOWNLOAD
  // ==========================================================================

  Future<void> _baixarDocumento(DocumentoFiscalPortal documento) async {
    if (!documento.temXml) {
      _avisar('XML não disponível na nuvem para esta nota.');
      return;
    }
    setState(() => _carregando = true);
    try {
      final xml = await PortalContadorService.instance.obterXml(documento);
      if (xml.trim().isEmpty) {
        _avisar('Não foi possível obter o XML desta nota.');
        return;
      }
      final bytes = Uint8List.fromList(utf8.encode(xml));
      await _salvarBytes(bytes, documento.nomeArquivo, 'application/xml');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _baixarZip({
    required List<DocumentoFiscalPortal> documentos,
    required String nomeArquivo,
    bool separarPorTipo = false,
  }) async {
    final comXml = documentos.where((d) => d.temXml).toList();
    if (comXml.isEmpty) {
      _avisar('Nenhum XML disponível no período selecionado.');
      return;
    }

    setState(() => _carregando = true);
    try {
      final archive = Archive();
      var incluidos = 0;
      for (final documento in comXml) {
        // O XML vem da coluna da tabela ou, quando vazia, do bucket do Storage.
        final xml = await PortalContadorService.instance.obterXml(documento);
        if (xml.trim().isEmpty) continue;

        final pasta = separarPorTipo ? '${documento.tipo.titulo}/' : '';
        final nome = '$pasta${documento.identificacao}-nfe.xml';
        final bytes = utf8.encode(xml);
        archive.addFile(ArchiveFile(nome, bytes.length, bytes));
        incluidos++;
      }

      if (incluidos == 0) {
        _avisar('Não foi possível obter nenhum XML. Tente novamente.');
        return;
      }

      final resumo = StringBuffer()
        ..writeln('XMLs - ${_sessao?.nome ?? ''}')
        ..writeln('Período: ${_formatarData(_inicio)} a ${_formatarData(_fim)}')
        ..writeln('Arquivos incluídos: $incluidos')
        ..writeln('Notas sem XML na nuvem: ${documentos.length - comXml.length}')
        ..writeln('Gerado em: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
      final resumoBytes = utf8.encode(resumo.toString());
      archive.addFile(ArchiveFile('LEIA-ME.txt', resumoBytes.length, resumoBytes));

      final zip = ZipEncoder().encode(archive);
      if (zip == null || zip.isEmpty) {
        throw Exception('Falha ao gerar o arquivo ZIP.');
      }

      await _salvarBytes(Uint8List.fromList(zip), nomeArquivo, 'application/zip');
    } catch (e) {
      _avisar('Erro ao gerar o ZIP: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvarBytes(List<int> bytes, String nome, String mime) async {
    if (kIsWeb) {
      html_helper.downloadBytes(bytes, nome, mime);
      _avisar('Download iniciado: $nome');
      return;
    }

    try {
      Directory destino;
      try {
        destino = await getDownloadsDirectory() ?? Directory.current;
      } catch (_) {
        destino = Directory.current;
      }
      final pasta = Directory('${destino.path}${Platform.pathSeparator}XMLs_Portal_Contador');
      if (!pasta.existsSync()) pasta.createSync(recursive: true);

      final arquivo = File('${pasta.path}${Platform.pathSeparator}$nome');
      await arquivo.writeAsBytes(bytes);
      _avisar('Arquivo salvo em ${arquivo.path}');
    } catch (e) {
      _avisar('Erro ao salvar o arquivo: $e');
    }
  }

  // ==========================================================================
  // RELATÓRIOS (o mesmo pacote contábil que o app gera)
  // ==========================================================================

  /// Carrega tudo que os relatórios precisam para o período selecionado.
  Future<_DadosRelatorio> _carregarDadosRelatorio() async {
    final servico = PortalContadorService.instance;

    final empresa = await servico.carregarEmpresa(_empresaId);
    if (empresa == null) {
      throw Exception('Não foi possível carregar os dados da empresa.');
    }

    final nfces = await servico.carregarNfces(
      empresaId: _empresaId,
      inicio: _inicio,
      fim: _fim,
    );
    final vendas = await servico.carregarVendas(
      empresaId: _empresaId,
      inicio: _inicio,
      fim: _fim,
    );
    final produtos = await servico.carregarProdutos(_empresaId);

    return _DadosRelatorio(
      empresa: empresa,
      nfces: nfces,
      vendas: vendas,
      produtos: produtos,
    );
  }

  /// Relatório fiscal agrupado (CFOP/CSOSN) em PDF.
  Future<void> _baixarRelatorioFiscal() async {
    setState(() => _carregando = true);
    try {
      final dados = await _carregarDadosRelatorio();
      if (dados.nfces.isEmpty) {
        _avisar('Nenhuma NFC-e encontrada no período selecionado.');
        return;
      }

      final pdf = await PacoteContabilService.gerarPdfFiscal(
        empresa: dados.empresa,
        nfces: dados.nfces,
        vendas: dados.vendas,
        produtos: dados.produtos,
        mesRef: _inicio,
      );
      await _salvarBytes(
        pdf,
        'relatorio_fiscal_${_tagPeriodo()}.pdf',
        'application/pdf',
      );
    } catch (e) {
      _avisar('Erro ao gerar o relatório fiscal: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Planilha detalhada (itens por nota + resumo de faturamento).
  Future<void> _baixarExcel() async {
    setState(() => _carregando = true);
    try {
      final dados = await _carregarDadosRelatorio();
      final excel = PacoteContabilService.gerarExcel(
        nfces: dados.nfces,
        vendas: dados.vendas,
        produtos: dados.produtos,
        inicio: _inicio,
        fim: _fim,
      );
      if (excel == null) {
        _avisar('Não foi possível gerar a planilha.');
        return;
      }

      await _salvarBytes(
        Uint8List.fromList(excel),
        'detalhado_nfce_${_tagPeriodo()}.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (e) {
      _avisar('Erro ao gerar a planilha: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Pacote contábil completo: XMLs + PDF fiscal + Excel, num ZIP.
  Future<void> _baixarPacoteContabil() async {
    setState(() => _carregando = true);
    try {
      final dados = await _carregarDadosRelatorio();
      if (dados.nfces.isEmpty) {
        _avisar('Nenhuma NFC-e encontrada no período selecionado.');
        return;
      }

      // Mapa chave -> documento, para o serviço buscar cada XML.
      final porChave = <String, DocumentoFiscalPortal>{};
      for (final documento in _documentos) {
        if (documento.chave.isNotEmpty) porChave[documento.chave] = documento;
      }

      final resultado = await PacoteContabilService.gerarPacote(
        empresa: dados.empresa,
        nfces: dados.nfces,
        vendas: dados.vendas,
        produtos: dados.produtos,
        inicio: _inicio,
        fim: _fim,
        obterXml: (nfce) async {
          final documento = porChave[(nfce.chaveAcesso ?? '').trim()];
          if (documento == null) return '';
          return PortalContadorService.instance.obterXml(documento);
        },
      );

      await _salvarBytes(
        resultado.zip,
        'pacote_contabil_nfce_${_tagPeriodo()}.zip',
        'application/zip',
      );
      _avisar(
        'Pacote gerado: ${resultado.xmlCount} XML(s) + relatório fiscal + planilha.',
      );
    } catch (e) {
      _avisar('Erro ao gerar o pacote contábil: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _avisar(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: _superficie),
    );
  }

  // ==========================================================================
  // UI
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final sessao = _sessao;
    if (sessao == null) {
      return Scaffold(backgroundColor: _fundo, body: _construirLogin());
    }

    return DefaultTabController(
      length: TipoDocumentoPortal.values.length,
      child: Scaffold(
        backgroundColor: _fundo,
        appBar: _construirAppBar(sessao),
        body: Column(
          children: [
            _construirFiltroPeriodo(),
            const TabBar(
              labelColor: _destaque,
              unselectedLabelColor: Colors.white54,
              indicatorColor: _destaque,
              tabs: [
                Tab(text: 'NFC-e Emitidas'),
                Tab(text: 'NF-e Emitidas'),
                Tab(text: 'NF-e Recebidas'),
              ],
            ),
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator(color: _destaque))
                  : TabBarView(
                      children: TipoDocumentoPortal.values
                          .map((tipo) => _construirAba(tipo))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirLogin() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _superficie,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ExodoLogo(fontSize: 44, showSubtitle: true, showPhoenix: true),
                const SizedBox(height: 28),
                const Text(
                  'PORTAL DO CONTADOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Baixe os XMLs das notas da empresa',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _cnpjController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_CnpjInputFormatter()],
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoracaoCampo('CNPJ', Icons.badge_outlined),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _senhaController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _entrando ? null : _entrar(),
                  decoration: _decoracaoCampo('Senha', Icons.lock_outline),
                ),
                if (_erro.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Text(
                      _erro,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _entrando ? null : _entrar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _destaque,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _entrando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.black,
                            ),
                          )
                        : const Text(
                            'ENTRAR',
                            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoracaoCampo(String label, IconData icone) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      prefixIcon: Icon(icone, color: _destaque, size: 20),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _destaque),
      ),
    );
  }

  PreferredSizeWidget _construirAppBar(PortalContadorSessao sessao) {
    return AppBar(
      backgroundColor: _superficie,
      titleSpacing: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Portal do Contador',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            _empresaSelecionadaNome(sessao),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
      actions: [
        if (sessao.empresas.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: DropdownButton<String>(
                value: _empresaId,
                dropdownColor: _superficie,
                underline: const SizedBox.shrink(),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: sessao.empresas
                    .map((e) => DropdownMenuItem<String>(
                          value: e.id,
                          child: Text(e.nome),
                        ))
                    .toList(),
                onChanged: (valor) async {
                  if (valor == null) return;
                  setState(() => _empresaId = valor);
                  await _carregarDocumentos();
                },
              ),
            ),
          ),
        IconButton(
          tooltip: 'Sair',
          onPressed: _sair,
          icon: const Icon(Icons.logout, color: Colors.white70),
        ),
      ],
    );
  }

  String _empresaSelecionadaNome(PortalContadorSessao sessao) {
    final encontrada = sessao.empresas.where((e) => e.id == _empresaId).toList();
    if (encontrada.isNotEmpty) return encontrada.first.nome;
    return sessao.empresas.first.nome;
  }

  Widget _construirFiltroPeriodo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _superficie.withOpacity(0.5),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _botaoData('De', _inicio, () => _selecionarData(inicial: true)),
          _botaoData('Até', _fim, () => _selecionarData(inicial: false)),
          OutlinedButton.icon(
            onPressed: _carregando ? null : _carregarDocumentos,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Atualizar'),
          ),
          ElevatedButton.icon(
            onPressed: _carregando
                ? null
                : () => _baixarZip(
                      documentos: _documentos,
                      nomeArquivo: 'xml_contabilidade_${_tagPeriodo()}.zip',
                      separarPorTipo: true,
                    ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _superficie,
              foregroundColor: _destaque,
            ),
            icon: const Icon(Icons.folder_zip_outlined, size: 18),
            label: const Text('BAIXAR XMLs (ZIP)'),
          ),
          _botaoRelatorio(
            icone: Icons.picture_as_pdf,
            rotulo: 'RELATÓRIO FISCAL (PDF)',
            aoClicar: _baixarRelatorioFiscal,
          ),
          _botaoRelatorio(
            icone: Icons.table_chart_outlined,
            rotulo: 'DETALHADO (EXCEL)',
            aoClicar: _baixarExcel,
          ),
          _botaoRelatorio(
            icone: Icons.inventory_2_outlined,
            rotulo: 'PACOTE CONTÁBIL (ZIP)',
            aoClicar: _baixarPacoteContabil,
            principal: true,
          ),
        ],
      ),
    );
  }

  Widget _botaoRelatorio({
    required IconData icone,
    required String rotulo,
    required VoidCallback aoClicar,
    bool principal = false,
  }) {
    return ElevatedButton.icon(
      onPressed: _carregando ? null : aoClicar,
      style: ElevatedButton.styleFrom(
        backgroundColor: principal ? _destaque : _superficie,
        foregroundColor: principal ? Colors.black : Colors.white,
      ),
      icon: Icon(icone, size: 18),
      label: Text(rotulo),
    );
  }

  Widget _botaoData(String label, DateTime valor, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: _carregando ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
      ),
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text('$label ${_formatarData(valor)}'),
    );
  }

  Widget _construirAba(TipoDocumentoPortal tipo) {
    final documentos = _porTipo(tipo);

    if (documentos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhuma nota encontrada no período selecionado.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final comXml = documentos.where((d) => d.temXml).length;
    final total = documentos.fold<double>(0, (soma, d) => soma + d.valor);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${documentos.length} nota(s)  •  $comXml com XML  •  '
                  '${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(total)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _carregando
                    ? null
                    : () => _baixarZip(
                          documentos: documentos,
                          nomeArquivo: '${tipo.name}_${_tagPeriodo()}.zip',
                        ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _superficie,
                  foregroundColor: _destaque,
                ),
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: const Text('Baixar XMLs desta aba'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
            itemCount: documentos.length,
            itemBuilder: (context, index) => _itemDocumento(documentos[index]),
          ),
        ),
      ],
    );
  }

  Widget _itemDocumento(DocumentoFiscalPortal documento) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Nº ${documento.numero.isEmpty ? '-' : documento.numero}'
                      '${documento.serie.isEmpty ? '' : '  •  Série ${documento.serie}'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _chipStatus(documento),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  documento.identificacao,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatarData(documento.data)}'
                  '${documento.participante.isEmpty ? '' : '  •  ${documento.participante}'}'
                  '  •  ${moeda.format(documento.valor)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: documento.temXml ? 'Baixar XML' : 'XML não disponível',
            child: IconButton(
              onPressed: documento.temXml ? () => _baixarDocumento(documento) : null,
              icon: Icon(
                documento.temXml ? Icons.download : Icons.cloud_off,
                color: documento.temXml ? _destaque : Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipStatus(DocumentoFiscalPortal documento) {
    final status = documento.status.toUpperCase();
    final cor = switch (documento.status) {
      'autorizada' || 'autorizado' => Colors.greenAccent,
      'cancelada' || 'cancelado' => Colors.redAccent,
      'rejeitada' || 'denegada' => Colors.orangeAccent,
      _ => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withOpacity(0.5)),
      ),
      child: Text(
        status.isEmpty ? 'SEM STATUS' : status,
        style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatarData(DateTime? data) =>
      data == null ? '--/--/----' : DateFormat('dd/MM/yyyy').format(data);

  String _tagPeriodo() =>
      '${DateFormat('yyyyMMdd').format(_inicio)}_${DateFormat('yyyyMMdd').format(_fim)}';
}

/// Dados necessários para montar os relatórios do período.
class _DadosRelatorio {
  final Empresa empresa;
  final List<NFCe> nfces;
  final List<VendaBalcao> vendas;
  final List<Produto> produtos;

  _DadosRelatorio({
    required this.empresa,
    required this.nfces,
    required this.vendas,
    required this.produtos,
  });
}

/// Aplica a máscara 00.000.000/0000-00 enquanto o contador digita o CNPJ.
class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitado = digitos.length > 14 ? digitos.substring(0, 14) : digitos;

    final buffer = StringBuffer();
    for (var i = 0; i < limitado.length; i++) {
      if (i == 2 || i == 5) buffer.write('.');
      if (i == 8) buffer.write('/');
      if (i == 12) buffer.write('-');
      buffer.write(limitado[i]);
    }

    final texto = buffer.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
