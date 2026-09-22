import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/conferencia_nuvem_service.dart';

/// Tela de conferência: mostra, POR EMPRESA, a diferença de contagem entre a
/// base LOCAL e a NUVEM, tabela por tabela.
///
/// Só lê: não grava, não apaga e não sincroniza nada. Depois de um
/// "Limpar Local" ou de uma troca de empresa, é aqui que dá para ver o que
/// ficou faltando de um lado ou do outro antes de decidir o que fazer.
class ConferenciaLocalNuvemPage extends StatefulWidget {
  const ConferenciaLocalNuvemPage({
    super.key,
    this.carregar,
    this.empresaAberta,
    this.empresaAbertaId,
    this.planejarEmpresas,
    this.restaurarEmpresas,
  });

  /// Injeção usada pelos testes. Em produção fica nulo e a tela chama
  /// [ConferenciaNuvemService.conferir].
  final Future<ResultadoConferencia> Function()? carregar;

  /// Nome da empresa aberta no app, mostrado no cabeçalho do relatório.
  final String? empresaAberta;

  /// Id da empresa aberta: só as divergências DELA são corrigidas no botão
  /// sincronizar (a base local guarda somente a empresa aberta).
  final String? empresaAbertaId;

  /// Injeções do botão "restaurar as empresas que faltam no local" (testes).
  final Future<ResumoEmpresasFaltantes> Function()? planejarEmpresas;
  final Future<(bool, String, int)> Function({bool simular})?
      restaurarEmpresas;

  @override
  State<ConferenciaLocalNuvemPage> createState() =>
      _ConferenciaLocalNuvemPageState();
}

class _ConferenciaLocalNuvemPageState extends State<ConferenciaLocalNuvemPage> {
  static const Color _fundo = Color(0xFF0F0F1E);
  static const Color _card = Color(0xFF1E1E2E);

  bool _carregando = true;
  bool _somenteDiferencas = true;
  bool _ocultarTelemetria = true;
  bool _sincronizando = false;
  String _mensagemProgresso = '';
  String? _erroFatal;
  ResultadoConferencia? _resultado;

  @override
  void initState() {
    super.initState();
    _conferir();
  }

  Future<void> _conferir() async {
    setState(() {
      _carregando = true;
      _erroFatal = null;
    });
    try {
      final carregar =
          widget.carregar ?? ConferenciaNuvemService.instance.conferir;
      final resultado = await carregar();
      if (!mounted) return;
      setState(() {
        _resultado = resultado;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroFatal = '$e';
        _carregando = false;
      });
    }
  }

  Future<void> _sincronizar({bool simular = false}) async {
    if (_resultado == null) return;

    // Só conta a empresa aberta: as divergências das outras ficam no relatório
    // como esperadas (a base local guarda somente a empresa aberta).
    final divergentes =
        _resultado!.comDiferenca.where((l) => !l.telemetria).toList();
    final daEmpresa = widget.empresaAbertaId == null
        ? divergentes
        : divergentes
            .where((l) => l.empresaId == widget.empresaAbertaId)
            .toList();
    final outras = divergentes.length - daEmpresa.length;

    if (daEmpresa.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outras == 0
              ? 'Nenhuma diferença para sincronizar'
              : 'Nada a corrigir na empresa aberta — as $outras divergências '
                  'são de outras empresas'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    // A simulação é só leitura: não precisa de confirmação.
    if (!simular &&
        !await _confirmarSincronizacao(daEmpresa.length, outras)) {
      return;
    }

    setState(() {
      _sincronizando = true;
      _mensagemProgresso = simular ? 'Simulando...' : 'Iniciando...';
    });

    try {
      final (ok, msg, total) = await ConferenciaNuvemService.instance.sincronizarDiferencas(
        _resultado!,
        simular: simular,
        empresaAtiva: widget.empresaAbertaId,
        onProgress: (m) {
          if (mounted) setState(() => _mensagemProgresso = m);
        },
      );

      if (!mounted) return;

      await _mostrarResultado(ok, msg);
      if (!mounted) return;

      // Só recarrega quando algo foi gravado (a simulação não muda contagem).
      if (!simular) await _conferir();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sincronizando = false;
          _mensagemProgresso = '';
        });
      }
    }
  }

  /// Restaura no banco LOCAL as empresas que existem na nuvem e não existem
  /// aqui — depois de mostrar um RESUMO e só com a confirmação do usuário.
  ///
  /// O botão de sincronizar NÃO faz isso sozinho: `empresas` não tem
  /// `empresa_id` confiável nos dois bancos, então nenhuma cópia automática
  /// pode decidir o que é "da empresa aberta". Aqui a decisão é explícita e
  /// reversível na leitura: só ENTRA o que falta (nada é apagado) e a nuvem
  /// não é tocada.
  Future<void> _restaurarEmpresas({bool simular = false}) async {
    setState(() {
      _sincronizando = true;
      _mensagemProgresso = 'Lendo as empresas do banco local e da nuvem...';
    });

    ResumoEmpresasFaltantes resumo;
    try {
      final planejar = widget.planejarEmpresas ??
          ConferenciaNuvemService.instance.planejarEmpresasFaltantesNoLocal;
      resumo = await planejar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sincronizando = false;
        _mensagemProgresso = '';
      });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _card,
          title: const Text('Não foi possível ler as empresas',
              style: TextStyle(color: Colors.white)),
          content: Text('$e',
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Fechar', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _sincronizando = false;
      _mensagemProgresso = '';
    });

    // O resumo JÁ é a simulação: é o mesmo texto que a tela mostra antes de
    // aplicar (aqui nada foi gravado, só lido).
    if (!resumo.temOQueRestaurar) {
      await _mostrarResumoEmpresas(
        titulo: 'Nada a restaurar',
        texto: resumo.texto,
        icone: Icons.verified,
        cor: Colors.greenAccent,
        botao: null,
      );
      return;
    }

    final confirmar = await _mostrarResumoEmpresas(
      titulo: '⬇️  Restaurar ${resumo.quantasEntram} empresa(s) no banco local?',
      texto: resumo.texto,
      icone: resumo.podeRestaurar
          ? Icons.download_for_offline_outlined
          : Icons.block,
      cor: resumo.podeRestaurar ? Colors.lightBlueAccent : Colors.redAccent,
      botao: resumo.podeRestaurar
          ? 'Restaurar ${resumo.quantasEntram}'
          : null,
    );
    if (confirmar != true) return;

    setState(() {
      _sincronizando = true;
      _mensagemProgresso = simular
          ? 'Simulando a restauração das empresas...'
          : 'Restaurando as empresas no banco local...';
    });
    try {
      final restaurar = widget.restaurarEmpresas ??
          ConferenciaNuvemService.instance.restaurarEmpresasFaltantesNoLocal;
      final (ok, msg, _) = await restaurar(simular: simular);
      if (!mounted) return;
      await _mostrarResultado(ok, msg);
      if (!mounted) return;
      await _conferir();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erro: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sincronizando = false;
          _mensagemProgresso = '';
        });
      }
    }
  }

  /// Diálogo do resumo (é o que o usuário vê ANTES de aplicar). [botao] nulo =
  /// só informa (nada a fazer ou restauração bloqueada pela estrutura).
  Future<bool?> _mostrarResumoEmpresas({
    required String titulo,
    required String texto,
    required IconData icone,
    required Color cor,
    required String? botao,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Row(
          children: [
            Icon(icone, color: cor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(titulo,
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(
              texto,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          if (botao != null)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlueAccent),
              child: Text(botao, style: const TextStyle(color: Colors.black)),
            ),
        ],
      ),
    );
  }

  /// Confirmação antes de gravar (a simulação não passa por aqui).
  Future<bool> _confirmarSincronizacao(int diferencas, int outras) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Sincronizar diferenças?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Empresa aberta: ${widget.empresaAberta ?? '(nenhuma)'}\n\n'
          '• $diferencas divergência(s) DELA serão corrigidas: o que falta no '
          'local desce da nuvem e o que falta na nuvem sobe do local.\n'
          '• O que já existe dos dois lados NÃO é alterado — a correção só '
          'completa o que está faltando.\n'
          '${outras == 0 ? '' : '• As $outras divergência(s) de outras empresas não '
              'serão tocadas: a base local guarda só a empresa aberta.\n'}\n'
          'Continuar?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
            child:
                const Text('Sincronizar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    return confirmar == true;
  }

  /// Resultado da sincronização.
  ///
  /// Quando dá tudo certo, um aviso rápido basta. Quando há erro, o relatório
  /// é longo (uma linha por tabela/empresa) e o SnackBar corta: aí vai um
  /// diálogo com o texto inteiro, rolável e selecionável — foi assim que os
  /// erros de tipo/coluna passaram batido antes.
  Future<void> _mostrarResultado(bool ok, String mensagem) async {
    if (ok && !mensagem.contains('\n')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $mensagem'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.error_outline,
                color: ok ? Colors.green : Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ok ? 'Sincronização concluída' : 'Sincronização com erros',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: SelectableText(
              mensagem,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        title: const Text(
          'Conferir: Local × Nuvem',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Copiar o relatório',
            icon: const Icon(Icons.copy_all, color: Colors.lightBlueAccent),
            onPressed: _resultado == null ? null : _copiar,
          ),
          IconButton(
            tooltip: 'Simular: mostra o que seria copiado, sem gravar nada',
            icon: const Icon(Icons.science_outlined, color: Colors.purpleAccent),
            onPressed: (_resultado == null || _carregando || _sincronizando)
                ? null
                : () => _sincronizar(simular: true),
          ),
          IconButton(
            tooltip: 'Sincronizar diferenças',
            icon: const Icon(Icons.sync, color: Colors.orangeAccent),
            onPressed: (_resultado == null || _carregando || _sincronizando)
                ? null
                : _sincronizar,
          ),
          IconButton(
            tooltip: 'Conferir de novo',
            icon: const Icon(Icons.refresh, color: Colors.greenAccent),
            onPressed: _carregando ? null : _conferir,
          ),
        ],
      ),
      body: _corpo(widget.empresaAberta),
    );
  }

  Widget _corpo(String? empresaAberta) {
    if (_carregando) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Contando as linhas do banco local e da nuvem...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_sincronizando) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.orangeAccent),
            const SizedBox(height: 16),
            Text(
              _mensagemProgresso.isEmpty ? 'Sincronizando...' : _mensagemProgresso,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              'Não feche o aplicativo.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      );
    }

    if (_erroFatal != null) {
      return _aviso(
        icone: Icons.error_outline,
        cor: Colors.redAccent,
        titulo: 'Não foi possível conferir',
        texto: _erroFatal!,
      );
    }

    final r = _resultado!;
    final linhas = r.filtrar(
      somenteDiferencas: _somenteDiferencas,
      ocultarTelemetria: _ocultarTelemetria,
    );
    final diferencas = r.contarDiferencas(ocultarTelemetria: _ocultarTelemetria);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _resumo(r, empresaAberta),
        if (r.erroLocal != null)
          _aviso(
            icone: Icons.warning_amber_rounded,
            cor: Colors.orangeAccent,
            titulo: 'Banco LOCAL não respondeu',
            texto: '${r.erroLocal}\n\nOs números do local ficam vazios (—) '
                'até a conferência funcionar.',
          ),
        if (r.erroNuvem != null)
          _aviso(
            icone: Icons.warning_amber_rounded,
            cor: Colors.orangeAccent,
            titulo: 'NUVEM não respondeu',
            texto: '${r.erroNuvem}\n\nOs números da nuvem ficam vazios (—) '
                'até a conferência funcionar.',
          ),
        if (r.erroLocal == null && r.erroNuvem == null) ...[
          SwitchListTile(
            value: _somenteDiferencas,
            onChanged: (v) => setState(() => _somenteDiferencas = v),
            activeThumbColor: Colors.lightBlueAccent,
            title: const Text(
              'Mostrar somente as diferenças',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _somenteDiferencas
                  ? '$diferencas divergência(s) · ${linhas.length} linha(s) no relatório'
                  : 'mostrando ${linhas.length} de ${r.linhas.length} linhas',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          SwitchListTile(
            value: _ocultarTelemetria,
            onChanged: (v) => setState(() => _ocultarTelemetria = v),
            activeThumbColor: Colors.lightBlueAccent,
            title: const Text(
              'Esconder logs e views (sync_logs, sync_status...)',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Essas tabelas não são dados da empresa e divergem por natureza.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
        if (linhas.isEmpty)
          _aviso(
            icone: diferencas == 0 ? Icons.verified : Icons.filter_alt_off,
            cor: diferencas == 0 ? Colors.greenAccent : Colors.white54,
            titulo: diferencas == 0
                ? 'Nenhuma diferença nos dados das empresas'
                : 'Nenhuma diferença com os filtros atuais',
            texto: diferencas == 0
                ? 'Todas as tabelas por empresa têm exatamente a mesma '
                    'quantidade de linhas nos dois bancos.'
                : 'Desligue "Mostrar somente as diferenças" ou o filtro de '
                    'telemetria para ver as outras linhas.',
          )
        else
          ...linhas.map(_linha),
        if (r.somenteNoLocal.isNotEmpty ||
            r.somenteNaNuvem.isNotEmpty ||
            r.comparadasPorTotal.isNotEmpty ||
            r.privadasDoApp.isNotEmpty)
          _tabelasNaoComparadas(r),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _resumo(ResultadoConferencia r, String? empresaAberta) {
    final diferencas = r.contarDiferencas(ocultarTelemetria: _ocultarTelemetria);
    final cor = diferencas == 0 ? Colors.greenAccent : Colors.orangeAccent;
    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  diferencas == 0 ? Icons.verified : Icons.compare_arrows,
                  color: cor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diferencas == 0
                        ? 'Tudo igual entre local e nuvem'
                        : '$diferencas diferença(s) encontrada(s)',
                    style: TextStyle(
                      color: cor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Empresa aberta agora: ${empresaAberta ?? '(nenhuma)'}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              'Linhas somadas — local: ${_milhares(r.totalLocal)} · '
              'nuvem: ${_milhares(r.totalNuvem)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              'Comparação de leitura: nada é gravado, apagado ou sincronizado.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            if (widget.empresaAbertaId != null &&
                r.linhas.any((l) =>
                    !l.igual &&
                    !l.telemetria &&
                    l.empresaId != widget.empresaAbertaId)) ...[
              const SizedBox(height: 6),
              Text(
                'As divergências marcadas como “esperado” são de outras '
                'empresas: a base local guarda só a empresa aberta, então só ela '
                'é corrigida ao sincronizar.',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linha(DiferencaConferencia l) {
    final igual = l.igual;
    final deOutraEmpresa = widget.empresaAbertaId != null &&
        l.empresaId != widget.empresaAbertaId &&
        l.empresaId != '(sem empresa)';
    final cor = igual ? Colors.greenAccent : Colors.orangeAccent;
    final delta = l.diferenca;
    final textoDelta = igual
        ? 'igual'
        : '${delta > 0 ? '+' : ''}$delta';

    final subtitulo = l.global
        ? 'TOTAL das empresas — tabela sem empresa_id nos dois bancos '
            '(comparada pelo total)'.toString()
        : l.empresaId == '(sem empresa)'
            ? 'registros sem empresa definida'
            : _nomeEmpresa(l.empresaId) +
                (deOutraEmpresa
                    ? '\nEsperado: a base local guarda só a empresa aberta'
                    : '');

    return Card(
      color: _card,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(
          deOutraEmpresa
              ? Icons.info_outline
              : (igual ? Icons.check_circle_outline : Icons.priority_high),
          color: deOutraEmpresa ? Colors.blueGrey : cor,
        ),
        title: Text(
          l.tabela,
          style: TextStyle(
            color: deOutraEmpresa ? Colors.white70 : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitulo,
          style: TextStyle(
            color: deOutraEmpresa ? Colors.white30 : Colors.white54,
            fontSize: 12,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'local ${l.local ?? '—'}  ·  nuvem ${l.nuvem ?? '—'}',
              style: TextStyle(
                color: deOutraEmpresa ? Colors.white38 : Colors.white70,
                fontSize: 12,
              ),
            ),
            Text(
              textoDelta,
              style: TextStyle(
                color: deOutraEmpresa ? Colors.blueGrey : cor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nomeEmpresa(String id) {
    final nome = _resultado!.nomesDeEmpresas[id];
    if (nome == null || nome.isEmpty) return id;
    return '$nome  ($id)';
  }

  Widget _tabelasNaoComparadas(ResultadoConferencia r) {
    return Card(
      color: _card,
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tabelas sem comparação por empresa',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            if (r.comparadasPorTotal.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '⚠️  Comparadas pelo TOTAL de linhas (entes acima, juntas): '
                '${r.comparadasPorTotal.join(', ')}',
                style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12),
              ),
              const SizedBox(height: 2),
              const Text(
                'Estas tabelas aparecem na lista acima com a empresa "(todas as '
                'empresas)": elas não têm a coluna empresa_id nos dois bancos (no local '
                'geralmente falta), então a contagem por empresa não se aplica — mas a '
                'diferença de TOTAL continua sendo comparada.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            if (r.comparadasPorTotal.contains('empresas')) ...[
              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 10),
              const Text(
                '🏢  Empresas cadastradas',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Quando a nuvem tem uma empresa que o banco local não tem, dá '
                'para trazer só ela para cá. O resumo aparece antes de aplicar, '
                'nada é apagado ou alterado (só entra o que falta) e a nuvem não '
                'é tocada.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              if (widget.empresaAberta != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Vale para TODAS as empresas, não só a aberta '
                  '(${widget.empresaAberta}) — a lista de empresas é global no app.',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ElevatedButton.icon(
                    onPressed: (_carregando || _sincronizando)
                        ? null
                        : () => _restaurarEmpresas(),
                    icon: const Icon(Icons.download_for_offline_outlined,
                        size: 18),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.lightBlueAccent),
                    label: const Text('Restaurar empresas que faltam no local',
                        style: TextStyle(color: Colors.black)),
                  ),
                  OutlinedButton.icon(
                    onPressed: (_carregando || _sincronizando)
                        ? null
                        : () => _restaurarEmpresas(simular: true),
                    icon: const Icon(Icons.science_outlined,
                        color: Colors.purpleAccent, size: 18),
                    label: const Text('Simular antes',
                        style: TextStyle(color: Colors.purpleAccent)),
                  ),
                ],
              ),
            ],
            if (r.somenteNoLocal.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '🏠  Existem SÓ no banco local (${r.somenteNoLocal.length}): '
                '${r.somenteNoLocal.join(', ')}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            if (r.somenteNaNuvem.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '☁️  Existem SÓ na nuvem (${r.somenteNaNuvem.length}): '
                '${r.somenteNaNuvem.join(', ')}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            if (r.privadasDoApp.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '🔒  Privadas do app (é assim de propósito, nunca vão para a nuvem): '
                '${r.privadasDoApp.join(', ')}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _aviso({
    required IconData icone,
    required Color cor,
    required String titulo,
    required String texto,
  }) {
    return Card(
      color: _card,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: cor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      color: cor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    texto,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _milhares(int valor) {
    final texto = valor.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < texto.length; i++) {
      if (i > 0 && (texto.length - i) % 3 == 0) buffer.write('.');
      buffer.write(texto[i]);
    }
    return buffer.toString();
  }

  Future<void> _copiar() async {
    final r = _resultado;
    if (r == null) return;

    final linhas = r.filtrar(
      somenteDiferencas: _somenteDiferencas,
      ocultarTelemetria: _ocultarTelemetria,
    );
    final buffer = StringBuffer()
      ..writeln('CONFERÊNCIA LOCAL × NUVEM — ${DateTime.now()}')
      ..writeln('Empresa aberta: ${widget.empresaAberta ?? '(nenhuma)'}')
      ..writeln('Linhas — local: ${r.totalLocal} · nuvem: ${r.totalNuvem} · '
          'diferenças: ${r.contarDiferencas(ocultarTelemetria: _ocultarTelemetria)}')
      ..writeln('');
    for (final l in linhas) {
      buffer.writeln('${l.tabela} | ${l.empresaId} | '
          'local=${l.local ?? '?'} nuvem=${l.nuvem ?? '?'} '
          'delta=${l.igual ? 0 : l.diferenca}');
    }
    if (r.somenteNoLocal.isNotEmpty) {
      buffer.writeln('\nSó no local: ${r.somenteNoLocal.join(', ')}');
    }
    if (r.somenteNaNuvem.isNotEmpty) {
      buffer.writeln('Só na nuvem: ${r.somenteNaNuvem.join(', ')}');
    }
    if (r.comparadasPorTotal.isNotEmpty) {
      buffer.writeln('Comparadas pelo total (sem empresa_id de um lado): '
          '${r.comparadasPorTotal.join(', ')}');
    }
    if (r.privadasDoApp.isNotEmpty) {
      buffer.writeln('Privadas do app (só no computador, de propósito): '
          '${r.privadasDoApp.join(', ')}');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 Relatório copiado para a área de transferência.')),
    );
  }
}
