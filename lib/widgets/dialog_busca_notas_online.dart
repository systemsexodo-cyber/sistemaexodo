import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/empresa.dart';
import '../models/nota_entrada.dart';
import '../services/nfce_backend_service.dart';
import '../services/data_service.dart';

/// Diálogo moderno para buscar notas fiscais online via SEFAZ (DF-e Distribuição)
/// ou buscar entre as notas de entrada já cadastradas no sistema.
class DialogBuscaNotasOnline extends StatefulWidget {
  final Empresa? empresa;
  final List<NotaEntrada> notasEntradaLocais;
  final void Function(String xmlContent) onImportarXML;
  final void Function(NotaEntrada nota) onCarregarNotaEntrada;

  const DialogBuscaNotasOnline({
    super.key,
    required this.empresa,
    required this.notasEntradaLocais,
    required this.onImportarXML,
    required this.onCarregarNotaEntrada,
  });

  @override
  State<DialogBuscaNotasOnline> createState() => _DialogBuscaNotasOnlineState();
}

class _DialogBuscaNotasOnlineState extends State<DialogBuscaNotasOnline>
    with SingleTickerProviderStateMixin {
  late TabController _tabDialogoController;
  final TextEditingController _chaveController = TextEditingController();
  final TextEditingController _cnpjFornecedorController = TextEditingController();
  final TextEditingController _buscaLocalController = TextEditingController();

  final NumberFormat _formatoMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  bool _carregandoSefaz = false;
  String? _statusMensagem;
  String? _erroMensagem;
  List<Map<String, dynamic>> _notasSefaz = [];
  String? _chaveEmProcesso;

  @override
  void initState() {
    super.initState();
    _tabDialogoController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabDialogoController.dispose();
    _chaveController.dispose();
    _cnpjFornecedorController.dispose();
    _buscaLocalController.dispose();
    super.dispose();
  }

  bool get _emHomologacao => widget.empresa?.ambienteHomologacao ?? true;

  /// Chave de persistência do NSU: separada por CNPJ e por ambiente, porque a
  /// SEFAZ mantém sequências de NSU diferentes em homologação e produção.
  String get _sufixoNsu {
    final cnpj = (widget.empresa?.cnpj ?? 'sem_cnpj')
        .replaceAll(RegExp(r'[^0-9]'), '');
    return '${cnpj}_${_emHomologacao ? 'hom' : 'prod'}';
  }

  Future<String?> _lerUltimoNsu() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nsu = prefs.getString('dfe_ult_nsu_$_sufixoNsu');
      return (nsu == null || nsu.trim().isEmpty) ? null : nsu.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _salvarUltimoNsu(dynamic ultNsu) async {
    final valor = ultNsu?.toString().trim() ?? '';
    if (valor.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dfe_ult_nsu_$_sufixoNsu', valor);
    } catch (_) {
      // Sem persistência o app apenas volta a consultar do NSU 0.
    }
  }

  /// Extrai a mensagem de erro mais específica que o Bridge retornou.
  String _extrairMensagemErro(Map<String, dynamic> resultado) {
    for (final chave in const [
      'mensagem',
      'message',
      'error',
      'detail',
      'xMotivo',
    ]) {
      final valor = resultado[chave];
      if (valor != null && valor.toString().trim().isNotEmpty) {
        return valor.toString();
      }
    }
    final status = resultado['http_status'];
    return status != null
        ? 'Erro ao consultar SEFAZ (HTTP $status).'
        : 'Erro ao consultar SEFAZ.';
  }

  /// Verifica se o erro é "Consumo Indevido" (cStat 656) da SEFAZ
  bool _isConsumoIndevido(Map<String, dynamic> resultado) {
    final cStat = resultado['cStat']?.toString() ?? '';
    final mensagem = resultado['mensagem']?.toString() ?? '';
    return cStat == '656' ||
        mensagem.contains('Consumo Indevido') ||
        mensagem.contains('consumo indevido');
  }

  /// Executa consulta com retry automático para "Consumo Indevido" (cStat 656)
  Future<Map<String, dynamic>> _consultarComRetry({
    required Empresa empresa,
    String? chaveAcesso,
    String? nsu,
    bool consultaNsuEspecifico = false,
    int maxTentativas = 3,
  }) async {
    final backend = NFCeBackendService.instance;
    int tentativas = 0;
    const tempoEsperaInicial = Duration(seconds: 5); // 5s, 15s, 45s
    Map<String, dynamic> resultado = {};

    while (tentativas < maxTentativas) {
      resultado = await backend.consultarDistribuicaoDFe(
        empresa: empresa,
        chaveAcesso: chaveAcesso,
        nsu: nsu,
        consultaNsuEspecifico: consultaNsuEspecifico,
      );

      if (!mounted) return resultado;

      // Sucesso ou erro diferente de "Consumo Indevido" - não tentar novamente
      if (resultado['success'] == true || !_isConsumoIndevido(resultado)) {
        break;
      }

      tentativas++;
      if (tentativas < maxTentativas) {
        final tempoEspera = tempoEsperaInicial * (3 * tentativas); // 5s, 15s, 45s
        setState(() {
          _statusMensagem = 'SEFAZ retornou "Consumo Indevido" (cStat 656). '
              'Aguardando ${tempoEspera.inSeconds}s antes de tentar novamente... '
              '(Tentativa ${tentativas + 1}/$maxTentativas)';
        });
        await Future.delayed(tempoEspera);
      }
    }

    return resultado;
  }

  Future<void> _consultarSefaz() async {
    final emp = widget.empresa;
    if (emp == null || emp.cnpj == null || emp.cnpj!.isEmpty) {
      setState(() {
        _erroMensagem = 'Nenhuma empresa selecionada ou CNPJ não configurado.';
        _statusMensagem = null;
      });
      return;
    }

    final cert = emp.configuracoes?['certificadoDigitalBytes'] ??
        emp.configuracoes?['certificado_base64'] ??
        emp.certificadoDigitalUrl;

    if (cert == null || cert.toString().isEmpty) {
      setState(() {
        _erroMensagem =
            'O Certificado Digital A1 não está configurado nesta empresa. Configure o certificado no cadastro da empresa para consultar notas na SEFAZ.';
        _statusMensagem = null;
      });
      return;
    }

    final cnpjFiltrar = _cnpjFornecedorController.text.trim();
    setState(() {
      _carregandoSefaz = true;
      _erroMensagem = null;
      _statusMensagem = 'Consultando WebService SEFAZ (DF-e Distribuição)...';
    });

    try {
      final chave = _chaveController.text.trim();

      // Continua do último NSU já consumido: a SEFAZ rejeita (cStat 656)
      // consultas repetidas ao mesmo NSU por até 1 hora.
      final nsuSalvo = chave.isEmpty ? await _lerUltimoNsu() : null;

      // Consulta com retry automático para "Consumo Indevido" (cStat 656)
      final resultado = await _consultarComRetry(
        empresa: emp,
        chaveAcesso: chave.isNotEmpty ? chave : null,
        nsu: nsuSalvo,
      );

      if (!mounted) return;

      if (resultado['success'] == true) {
        if (chave.isEmpty) {
          await _salvarUltimoNsu(resultado['ultNSU']);
        }

        final listaRaw = resultado['notas'];
        List<Map<String, dynamic>> lista = [];
        if (listaRaw is List) {
          for (var item in listaRaw) {
            if (item is Map) {
              lista.add(Map<String, dynamic>.from(item));
            }
          }
        }

        // Filtrar por CNPJ do fornecedor se informado
        if (cnpjFiltrar.isNotEmpty) {
          lista = lista.where((n) {
            final emitCnpj = (n['emitente_cnpj'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
            return emitCnpj.contains(cnpjFiltrar.replaceAll(RegExp(r'[^0-9]'), ''));
          }).toList();
        }

        // Calcular próximo número livre da sequência considering notas já usadas
        final numerosUsados = <int>{};
        for (final n in lista) {
          final num = int.tryParse((n['numero'] ?? '').toString());
          if (num != null) numerosUsados.add(num);
        }
        final proximo = DataService.menorNumeroLivreNfce(
          numerosUsados: numerosUsados,
          numeroInicial: 1,
        );

        setState(() {
          _carregandoSefaz = false;
          _notasSefaz = lista;
          if (lista.isEmpty && _emHomologacao) {
            _statusMensagem =
                'Nenhuma nota localizada. Esta empresa está configurada no ambiente de HOMOLOGAÇÃO: '
                'a SEFAZ não disponibiliza as notas reais dos fornecedores nesse ambiente. '
                'Altere para Produção no cadastro da empresa para baixar as notas reais.';
          } else {
            _statusMensagem = resultado['mensagem'] ??
                (lista.isEmpty
                    ? 'Nenhuma nova nota fiscal localizada na SEFAZ para este CNPJ no momento.'
                    : '${lista.length} documento(s) retornado(s) pela SEFAZ. Próximo nº livre da sequência: $proximo');
          }
        });
      } else {
        setState(() {
          _carregandoSefaz = false;
          _erroMensagem = _extrairMensagemErro(resultado);
          _statusMensagem = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregandoSefaz = false;
        _erroMensagem = 'Falha na comunicação com o Bridge local ou SEFAZ: $e';
        _statusMensagem = null;
      });
    }
  }

  Future<void> _manifestarCiencia(Map<String, dynamic> nota) async {
    final emp = widget.empresa;
    if (emp == null) return;
    final chave = nota['chave']?.toString() ?? '';
    if (chave.isEmpty) return;

    setState(() {
      _chaveEmProcesso = chave;
      _erroMensagem = null;
    });

    try {
      final backend = NFCeBackendService.instance;
      final resManif = await backend.manifestarDFe(
        empresa: emp,
        chaveAcesso: chave,
        tipoEvento: '210210', // Ciência da Emissão
      );

      if (!mounted) return;

      if (resManif['success'] == true) {
        // Busca novamente a nota por chave para puxar o XML completo que a SEFAZ agora libera
        // Usa retry para evitar erro "Consumo Indevido" (cStat 656)
        final resBusca = await _consultarComRetry(
          empresa: emp,
          chaveAcesso: chave,
        );

        if (!mounted) return;

        if (resBusca['success'] == true && resBusca['notas'] is List) {
          final novasNotas = List<Map<String, dynamic>>.from(
            (resBusca['notas'] as List).map((x) => Map<String, dynamic>.from(x)),
          );
          final notaCompleta = novasNotas.firstWhere(
            (n) => n['chave'] == chave && n['tem_xml_completo'] == true,
            orElse: () => <String, dynamic>{},
          );

          if (notaCompleta.isNotEmpty && notaCompleta['xml'] != null) {
            setState(() {
              nota['tem_xml_completo'] = true;
              nota['xml'] = notaCompleta['xml'];
              nota['tipo'] = 'completo';
              _statusMensagem =
                  'Ciência registrada e XML completo baixado da SEFAZ com sucesso!';
              _chaveEmProcesso = null;
            });
            return;
          }
        }

        setState(() {
          _statusMensagem =
              'Ciência da Emissão registrada com sucesso na SEFAZ. A SEFAZ pode levar alguns segundos para liberar o XML completo.';
          _chaveEmProcesso = null;
        });
      } else {
        setState(() {
          _erroMensagem = _extrairMensagemErro(resManif);
          _chaveEmProcesso = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroMensagem = 'Erro na manifestação: $e';
        _chaveEmProcesso = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.empresa;
    final cnpjFormatado = emp?.cnpj ?? 'Não informado';
    final nomeEmpresa = emp?.nomeFantasia ?? emp?.razaoSocial ?? 'Empresa';
    final estadoEmpresa = emp?.estado ?? 'SP';

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 820,
        height: 640,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Topo do Dialog
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.cloud_download,
                    color: Colors.blueAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Buscar Notas Fiscais Online (DF-e / SEFAZ)',
                        style: TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$nomeEmpresa • CNPJ: $cnpjFormatado • UF: $estadoEmpresa',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Fechar',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Abas
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabDialogoController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.blueAccent,
                ),
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF94A3B8),
                tabs: [
                  const Tab(
                    icon: Icon(Icons.cloud_sync, size: 18),
                    text: 'SEFAZ Online (Notas Emitidas)',
                  ),
                  Tab(
                    icon: const Icon(Icons.inventory_2, size: 18),
                    text:
                        'Notas Salvas no Sistema (${widget.notasEntradaLocais.where((n) => !n.isCancelada).length})',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Conteúdo das Abas
            Expanded(
              child: TabBarView(
                controller: _tabDialogoController,
                children: [
                  _buildAbaSefazOnline(),
                  _buildAbaNotasLocais(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAbaSefazOnline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Barra de busca SEFAZ
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cnpjFornecedorController,
                  style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'CNPJ do fornecedor para filtrar (apenas números ou deixe vazio para todas as notas)',
                    hintStyle:
                        TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    prefixIcon:
                        Icon(Icons.business, color: Color(0xFF64748B), size: 18),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _consultarSefaz(),
                ),
              ),
              const SizedBox(width: 8),
              if (_cnpjFornecedorController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear,
                      size: 18, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    setState(() => _cnpjFornecedorController.clear());
                  },
                ),
              Expanded(
                child: TextField(
                  controller: _chaveController,
                  style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText:
                        'Chave de Acesso (44 dígitos) ou deixe vazio para puxar as notas recentes...',
                    hintStyle:
                        TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    prefixIcon:
                        Icon(Icons.vpn_key, color: Color(0xFF64748B), size: 18),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _consultarSefaz(),
                ),
              ),
              const SizedBox(width: 8),
              if (_chaveController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear,
                      size: 18, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    setState(() => _chaveController.clear());
                  },
                ),
              ElevatedButton.icon(
                onPressed: _carregandoSefaz ? null : _consultarSefaz,
                icon: _carregandoSefaz
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.travel_explore, size: 18),
                label: Text(
                  _carregandoSefaz ? 'Consultando...' : 'Buscar na SEFAZ',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Avisos de Mensagem / Erro
        if (_erroMensagem != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _erroMensagem!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_statusMensagem != null && _erroMensagem == null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: Colors.blueAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMensagem!,
                    style: const TextStyle(
                      color: Color(0xFF93C5FD),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Lista de Notas da SEFAZ
        Expanded(
          child: _carregandoSefaz
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.blueAccent),
                      SizedBox(height: 16),
                      Text(
                        'Conectando ao WebService de Distribuição DF-e da SEFAZ...',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : _notasSefaz.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 60,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Nenhuma nota fiscal carregada da SEFAZ',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Clique em "Buscar na SEFAZ" para consultar as notas emitidas contra o seu CNPJ',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _notasSefaz.length,
                      itemBuilder: (context, index) {
                        final n = _notasSefaz[index];
                        final numero = n['numero']?.toString() ?? 'S/N';
                        final serie = n['serie']?.toString() ?? '';
                        final emitente =
                            n['emitente_nome']?.toString() ?? 'Fornecedor';
                        final emitCnpj = n['emitente_cnpj']?.toString() ?? '';
                        final valorTotal = double.tryParse(
                                n['valor_total']?.toString() ?? '0') ??
                            0.0;
                        final dataEmi = n['data_emissao']?.toString() ?? '';
                        final chave = n['chave']?.toString() ?? '';
                        final temXmlCompleto = n['tem_xml_completo'] == true &&
                            (n['xml']?.toString().isNotEmpty ?? false);
                        final situacao =
                            n['situacao']?.toString() ?? 'autorizada';
                        final estaProcessando = _chaveEmProcesso == chave;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          color: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: temXmlCompleto
                                  ? Colors.green.withValues(alpha: 0.4)
                                  : Colors.blueAccent.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blueAccent
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'NF-e $numero ${serie.isNotEmpty ? "Série $serie" : ""}',
                                        style: const TextStyle(
                                          color: Colors.blueAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        emitente,
                                        style: const TextStyle(
                                          color: Color(0xFFE2E8F0),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: situacao == 'cancelada'
                                            ? Colors.red.withValues(alpha: 0.2)
                                            : (temXmlCompleto
                                                ? Colors.green
                                                    .withValues(alpha: 0.2)
                                                : Colors.orange
                                                    .withValues(alpha: 0.2)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        situacao == 'cancelada'
                                            ? 'CANCELADA'
                                            : (temXmlCompleto
                                                ? 'XML PRONTO'
                                                : 'RESUMO (CIÊNCIA PENDENTE)'),
                                        style: TextStyle(
                                          color: situacao == 'cancelada'
                                              ? Colors.redAccent
                                              : (temXmlCompleto
                                                  ? Colors.greenAccent
                                                  : Colors.orangeAccent),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      'CNPJ: $emitCnpj',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (dataEmi.isNotEmpty) ...[
                                      const SizedBox(width: 12),
                                      Text(
                                        'Emissão: ${dataEmi.length >= 10 ? dataEmi.substring(0, 10) : dataEmi}',
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    Text(
                                      'Valor: ${_formatoMoeda.format(valorTotal)}',
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                if (chave.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Chave: $chave',
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 10,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy,
                                            size: 14, color: Color(0xFF64748B)),
                                        tooltip: 'Copiar Chave',
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(text: chave),
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Chave copiada para a área de transferência!',
                                              ),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                                const Divider(
                                  color: Color(0xFF334155),
                                  height: 16,
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (temXmlCompleto)
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          widget.onImportarXML(
                                            n['xml'].toString(),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.download_done,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'Importar para Entrada',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                      )
                                    else
                                      ElevatedButton.icon(
                                        onPressed: estaProcessando
                                            ? null
                                            : () => _manifestarCiencia(n),
                                        icon: estaProcessando
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.visibility,
                                                size: 16,
                                              ),
                                        label: Text(
                                          estaProcessando
                                              ? 'Manifestando...'
                                              : 'Manifestar Ciência & Baixar XML',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.orange.shade800,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildAbaNotasLocais() {
    final todasNotas = widget.notasEntradaLocais
        .where((n) => !n.isCancelada)
        .toList()
      ..sort((a, b) => b.dataCriacao.compareTo(a.dataCriacao));

    final t = _buscaLocalController.text.trim().toLowerCase();
    final filtradas = todasNotas.where((n) {
      if (t.isEmpty) return true;
      final num = (n.numeroNota ?? '').toLowerCase();
      final chave = (n.chaveNFe ?? '').toLowerCase();
      final forn = (n.fornecedorNome ?? '').toLowerCase();
      final cnpj = (n.fornecedorCNPJ ?? '').toLowerCase();
      return num.contains(t) ||
          chave.contains(t) ||
          forn.contains(t) ||
          cnpj.contains(t);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _buscaLocalController,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Filtrar por nº da nota, fornecedor, CNPJ ou chave...',
            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            prefixIcon:
                const Icon(Icons.search, color: Color(0xFF64748B), size: 18),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filtradas.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhuma nota local encontrada.',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                )
              : ListView.builder(
                  itemCount: filtradas.length,
                  itemBuilder: (context, index) {
                    final nota = filtradas[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        title: Text(
                          '${nota.numeroNota ?? 'S/N'} - ${nota.fornecedorNome ?? 'Sem Fornecedor'}',
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'CNPJ: ${nota.fornecedorCNPJ ?? 'N/D'} • ${nota.itens.length} itens • ${_formatoMoeda.format(nota.valorTotal ?? 0)}',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => widget.onCarregarNotaEntrada(nota),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Carregar'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
