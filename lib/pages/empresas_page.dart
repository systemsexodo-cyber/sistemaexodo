import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/excel_import_service.dart';
import '../services/cliente_import_service.dart';
import '../models/empresa.dart';
import '../theme.dart';
import 'adicionar_empresa_page.dart';
import 'login_page.dart';
import '../services/google_drive_service.dart';
import '../services/bridge_management_service.dart';
import 'google_drive_backup_page.dart';
import '../services/supabase_service.dart';
import '../services/app_update_service.dart';
import 'bloqueio_mensalidade_page.dart';
import 'monitor_page.dart';
import 'backup_restore_page.dart';
// ─────────────────────────────────────────────────────────────────────────────
// Publicação de atualização: escolha do destino
// ─────────────────────────────────────────────────────────────────────────────

/// Destino escolhido para publicar a atualização do app.
class _DestinoAtualizacao {
  /// Vazio = todos os clientes (`app_latest`).
  final List<Empresa> empresas;

  const _DestinoAtualizacao.todos() : empresas = const [];
  const _DestinoAtualizacao.paraEmpresas(this.empresas);

  bool get global => empresas.isEmpty;
}

/// Pergunta para quem vai a atualização: TODOS os clientes (`app_latest`) ou
/// uma/várias empresas (`app_update_<id>`, um registro por empresa).
class _DialogoDestinoAtualizacao extends StatefulWidget {
  final List<Empresa> empresas;

  const _DialogoDestinoAtualizacao({required this.empresas});

  @override
  State<_DialogoDestinoAtualizacao> createState() =>
      _DialogoDestinoAtualizacaoState();
}

class _DialogoDestinoAtualizacaoState
    extends State<_DialogoDestinoAtualizacao> {
  bool _global = true;
  final Set<String> _marcadas = <String>{};

  @override
  void initState() {
    super.initState();
    // Já vem com todas marcadas: publicar para as empresas de uma vez é o caso
    // mais comum depois do global.
    _marcadas.addAll(widget.empresas.map((e) => e.id));
  }

  String _idCurto(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Text(
        'Publicar Atualização',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Para quem vai a versão que você vai publicar?',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _buildOpcao(
                selecionado: _global,
                icone: Icons.public,
                cor: Colors.teal,
                titulo: 'TODOS os clientes (global)',
                descricao: 'app_latest — todo cliente sem versão direcionada '
                    'baixa esta.',
                onTap: () => setState(() => _global = true),
              ),
              const SizedBox(height: 8),
              _buildOpcao(
                selecionado: !_global,
                icone: Icons.business,
                cor: Colors.cyan,
                titulo: 'Uma ou mais empresas',
                descricao: 'app_update_<id> — só os computadores das empresas '
                    'marcadas; as outras continuam como estão.',
                onTap: () => setState(() => _global = false),
              ),
              if (!_global) ...[
                const SizedBox(height: 12),
                if (widget.empresas.isEmpty)
                  const Text(
                    'Nenhuma empresa cadastrada para escolher. '
                    'Use a publicação global.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  )
                else ...[
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _marcadas
                            ..clear()
                            ..addAll(widget.empresas.map((e) => e.id));
                        }),
                        icon: const Icon(Icons.done_all, size: 16),
                        label: const Text('Marcar todas'),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _marcadas.clear()),
                        icon: const Icon(Icons.remove_done, size: 16),
                        label: const Text('Limpar'),
                      ),
                      const Spacer(),
                      Text(
                        '${_marcadas.length} marcada(s)',
                        style:
                            const TextStyle(color: Colors.cyan, fontSize: 12),
                      ),
                    ],
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: widget.empresas
                          .map((empresa) => CheckboxListTile(
                                dense: true,
                                value: _marcadas.contains(empresa.id),
                                activeColor: Colors.cyan,
                                title: Text(
                                  empresa.nomeExibicao,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                                subtitle: Text(
                                  _idCurto(empresa.id),
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11),
                                ),
                                onChanged: (marcado) => setState(() {
                                  if (marcado == true) {
                                    _marcadas.add(empresa.id);
                                  } else {
                                    _marcadas.remove(empresa.id);
                                  }
                                }),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              const Text(
                'A versão e o pacote são confirmados na próxima tela.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton.icon(
          onPressed: () {
            if (_global) {
              Navigator.pop(context, const _DestinoAtualizacao.todos());
              return;
            }
            final escolhidas = widget.empresas
                .where((e) => _marcadas.contains(e.id))
                .toList();
            if (escolhidas.isEmpty) return; // nenhuma empresa marcada
            Navigator.pop(
                context, _DestinoAtualizacao.paraEmpresas(escolhidas));
          },
          icon: const Icon(Icons.cloud_upload, size: 18),
          label: const Text('Continuar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _global ? Colors.teal : Colors.cyan,
          ),
        ),
      ],
    );
  }

  Widget _buildOpcao({
    required bool selecionado,
    required IconData icone,
    required Color cor,
    required String titulo,
    required String descricao,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cor.withOpacity(selecionado ? 0.14 : 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selecionado ? cor : Colors.white12,
            width: selecionado ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icone, color: cor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      color: selecionado ? cor : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descricao,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              selecionado
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selecionado ? cor : Colors.white24,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Assistente "Gerar versão".
///
/// Existe porque publicar exigia, fora do sistema: subir o número no código,
/// rodar `flutter build windows --release` e só depois abrir a publicação.
/// Aqui isso vira um caminho só — e os detalhes do que mudou ficam guardados
/// junto da versão (o cliente lê na tela de atualização e o projeto ganha o
/// HISTORICO_VERSOES.md).
class _DialogoGerarVersao extends StatefulWidget {
  const _DialogoGerarVersao();

  @override
  State<_DialogoGerarVersao> createState() => _DialogoGerarVersaoState();
}

class _DialogoGerarVersaoState extends State<_DialogoGerarVersao> {
  final TextEditingController _notas = TextEditingController();
  final List<String> _log = [];
  String? _pasta;
  String? _versaoNoCodigo;
  TipoIncrementoVersao _tipo = TipoIncrementoVersao.correcao;
  bool _carregando = true;
  bool _compilando = false;
  /// Etapa atual da barra de progresso (o texto na tela é o rótulo dela).
  EtapaGeracaoVersao _etapa = EtapaGeracaoVersao.gravandoCodigo;
  /// Quanto tempo já passou na etapa atual — é o que faz a barra andar nos
  /// minutos em que o compilador não imprime nada.
  final Stopwatch _tempoNaEtapa = Stopwatch();
  /// Tempo total desta geração, mostrado ao lado da barra.
  final Stopwatch _tempoTotal = Stopwatch();
  /// Redesenha a barra enquanto a versão está sendo gerada (o tique só serve
  /// para o tempo andar; o trabalho de verdade é assíncrono).
  Timer? _tiqueDaBarra;
  String? _erro;
  String? _versaoGerada;
  PacoteAtualizacao? _pacote;

  @override
  void initState() {
    super.initState();
    _detectar();
  }

  @override
  void dispose() {
    _tiqueDaBarra?.cancel();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _detectar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    final pasta = AppUpdateService.pastaDoProjeto();
    final versao =
        pasta == null ? null : await AppUpdateService.lerVersaoDoCodigo(pasta);
    if (!mounted) return;
    setState(() {
      _pasta = pasta;
      _versaoNoCodigo = versao;
      _carregando = false;
      _erro = pasta == null
          ? 'Não achei o código do projeto nesta máquina. Escolha a pasta onde '
              'está o pubspec.yaml para eu conseguir compilar.'
          : null;
    });
  }

  String get _novaVersao => AppUpdateService.proximaVersao(
      _versaoNoCodigo ?? '0.0.0', _tipo);

  String _rotulo(TipoIncrementoVersao tipo) => switch (tipo) {
        TipoIncrementoVersao.correcao => 'Correção',
        TipoIncrementoVersao.versaoNova => 'Versão nova',
        TipoIncrementoVersao.versaoGrande => 'Versão grande',
      };

  Future<void> _escolherPasta() async {
    final escolhida = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Pasta do projeto (onde está o pubspec.yaml)');
    if (escolhida == null) return;
    final versao = await AppUpdateService.lerVersaoDoCodigo(escolhida);
    if (!mounted) return;
    setState(() {
      _pasta = escolhida;
      _versaoNoCodigo = versao;
      _erro = versao == null
          ? 'Não achei a linha currentAppVersion nessa pasta — confira se é a pasta do projeto.'
          : null;
    });
  }

  /// Entra numa etapa da barra: zera o cronômetro dela (é o que dá ritmo ao
  /// percentual enquanto o compilador está mudo).
  void _entrarNaEtapa(EtapaGeracaoVersao etapa) {
    _tempoNaEtapa
      ..reset()
      ..start();
    _etapa = etapa;
  }

  /// Liga o redesenho periódico da barra e o cronômetro total.
  void _ligarTiqueDaBarra() {
    _tiqueDaBarra?.cancel();
    _tempoTotal
      ..reset()
      ..start();
    _tiqueDaBarra = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() {
        // Se a saída do compilador não trouxer nenhum marco conhecido (muda
        // conforme a versão do Flutter/MSBuild), a etapa avança por tempo.
        final proxima = AppUpdateService.proximaEtapaPorTempo(
          _etapa,
          _tempoNaEtapa.elapsed,
        );
        if (proxima != null) _entrarNaEtapa(proxima);
      });
    });
  }

  void _pararTiqueDaBarra() {
    _tiqueDaBarra?.cancel();
    _tiqueDaBarra = null;
    _tempoNaEtapa.stop();
    _tempoTotal.stop();
  }

  /// Sai do estado "gerando": desliga a barra e mostra o motivo do erro.
  void _encerrarGeracao(String erro) {
    _pararTiqueDaBarra();
    setState(() {
      _compilando = false;
      _erro = erro;
    });
  }

  String get _tempoLegivel {
    final segundos = _tempoTotal.elapsed.inSeconds;
    if (segundos < 60) return '${segundos}s';
    final minutos = segundos ~/ 60;
    final resto = segundos % 60;
    return resto == 0 ? '${minutos}min' : '${minutos}min ${resto}s';
  }

  double get _percentualDaBarra =>
      AppUpdateService.percentualDaEtapa(_etapa, _tempoNaEtapa.elapsed);

  /// Barra de progresso da geração: a etapa, o quanto já andou e há quanto
  /// tempo. Fica no lugar do antigo "rodinha + frase", que não dizia se o
  /// programa estava trabalhando ou travado.
  Widget _buildProgressoDaVersao() {
    final percentual = _percentualDaBarra;
    final trabalhando = _etapa.numero <= EtapaGeracaoVersao.totalDeTrabalho;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigoAccent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigoAccent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _etapa.rotulo,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(percentual * 100).round()}%',
                style: const TextStyle(
                  color: Colors.indigoAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percentual,
              minHeight: 10,
              backgroundColor: Colors.white12,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.indigoAccent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$_tempoLegivel nesta versão',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Spacer(),
              Text(
                trabalhando
                    ? 'etapa ${_etapa.numero} de ${EtapaGeracaoVersao.totalDeTrabalho}'
                    : 'concluída',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _gerarECompilar() async {
    final pasta = _pasta;
    if (pasta == null || _versaoNoCodigo == null) return;
    final nova = _novaVersao;
    setState(() {
      _compilando = true;
      _erro = null;
      _pacote = null;
      _log
        ..clear()
        ..add('>>> Gerando a versão $nova...');
      _entrarNaEtapa(EtapaGeracaoVersao.gravandoCodigo);
    });
    _ligarTiqueDaBarra();

    final (gravou, mensagemGravacao) =
        await AppUpdateService.gravarVersaoNoCodigo(pasta, nova);
    if (!mounted) return;
    if (!gravou) {
      _encerrarGeracao(mensagemGravacao);
      return;
    }
    setState(() {
      _log.add('>>> $mensagemGravacao');
      _entrarNaEtapa(EtapaGeracaoVersao.preparandoCompilacao);
    });

    final (compilou, resultado) = await AppUpdateService.compilarProjeto(
      pasta: pasta,
      onLinha: (linha) {
        if (!mounted) return;
        setState(() {
          _log.add(linha);
          if (_log.length > 400) _log.removeAt(0);
          // Os marcos do `flutter build` dizem em que ponto a compilação está.
          final etapa = AppUpdateService.etapaDaLinhaDeCompilacao(linha);
          if (etapa != null && etapa != _etapa) _entrarNaEtapa(etapa);
        });
      },
    );
    if (!mounted) return;
    if (!compilou) {
      _encerrarGeracao(resultado);
      return;
    }

    setState(() => _entrarNaEtapa(EtapaGeracaoVersao.empacotando));
    final pacote = await AppUpdateService.empacotarAtualizacao(
        pasta: p.join(
            pasta, 'build', 'windows', 'x64', 'runner', 'Release'));
    if (!mounted) return;
    setState(() {
      _compilando = false;
      _entrarNaEtapa(EtapaGeracaoVersao.pronta);
      _versaoGerada = nova;
      _pacote = pacote;
      _erro = pacote == null
          ? 'Compilou, mas não achei o programa em build/windows/x64/runner/Release para montar o pacote.'
          : null;
    });
    _pararTiqueDaBarra();
  }

  Future<void> _publicar() async {
    final versao = _versaoGerada;
    final pacote = _pacote;
    if (versao == null || pacote == null) return;

    final empresas = Provider.of<AuthService>(context, listen: false)
        .getEmpresasDoUsuario();
    final destino = await showDialog<_DestinoAtualizacao>(
      context: context,
      builder: (context) => _DialogoDestinoAtualizacao(empresas: empresas),
    );
    if (destino == null || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => _DialogoPublicarAtualizacao(
        destino: destino,
        versaoInicial: versao,
        notasIniciais: _notas.text,
        pacoteInicial: pacote,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Row(
        children: [
          Icon(Icons.rocket_launch, color: Colors.indigoAccent),
          SizedBox(width: 12),
          Text('Gerar versão', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_carregando)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Colors.indigoAccent)),
                )
              else ...[
                _buildPasta(),
                const SizedBox(height: 12),
                if (_versaoNoCodigo != null) _buildNumeracao(),
                const SizedBox(height: 12),
                TextField(
                  controller: _notas,
                  enabled: !_compilando && _pacote == null,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Detalhes desta atualização ("o que mudou")',
                    labelStyle: const TextStyle(color: Colors.white70),
                    helperText:
                        'Aparece para o cliente na tela de atualização.',
                    helperStyle: const TextStyle(color: Colors.white38),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                  ),
                ),
                if (_compilando) ...[
                  const SizedBox(height: 12),
                  _buildProgressoDaVersao(),
                ],
                if (_log.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    height: 140,
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: ListView(
                      reverse: true,
                      children: _log.reversed
                          .take(60)
                          .map((linha) => Text(
                                linha,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11),
                              ))
                          .toList(),
                    ),
                  ),
                ],
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                    ),
                    child: Text(_erro!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                  ),
                ],
                if (_pacote != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Versão $_versaoGerada compilada e pacote pronto.',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_pacote!.tamanhoLegivel}  •  ${_pacote!.conteudo.join(", ")}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'A versão só chega nos clientes quando você publicar.',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _compilando ? null : () => Navigator.pop(context),
          child: Text(_pacote == null ? 'Cancelar' : 'Publicar depois',
              style: const TextStyle(color: Colors.white54)),
        ),
        if (_pacote == null)
          ElevatedButton.icon(
            onPressed: (_compilando || _pasta == null || _versaoNoCodigo == null)
                ? null
                : _gerarECompilar,
            icon: _compilando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.build, size: 18),
            label: Text(_compilando ? 'Gerando...' : 'Gerar e compilar'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigoAccent),
          )
        else
          ElevatedButton.icon(
            onPressed: _publicar,
            icon: const Icon(Icons.cloud_upload, size: 18),
            label: const Text('Publicar agora'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          ),
      ],
    );
  }

  Widget _buildPasta() {
    final pasta = _pasta;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Código do projeto',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            pasta ?? 'não encontrado nesta máquina',
            style: TextStyle(
                color: pasta == null ? Colors.orangeAccent : Colors.white54,
                fontSize: 11),
          ),
          if (_versaoNoCodigo != null)
            Text(
              'versão no código: $_versaoNoCodigo',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _compilando ? null : _escolherPasta,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Escolher pasta'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumeracao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Que tipo de versão é esta?',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        ...TipoIncrementoVersao.values.map((tipo) {
          final escolhido = _tipo == tipo;
          final previa = AppUpdateService.proximaVersao(
              _versaoNoCodigo ?? '0.0.0', tipo);
          return InkWell(
            onTap: _compilando ? null : () => setState(() => _tipo = tipo),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (escolhido ? Colors.indigoAccent : Colors.white)
                    .withOpacity(escolhido ? 0.14 : 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: escolhido ? Colors.indigoAccent : Colors.white12,
                    width: escolhido ? 2 : 1),
              ),
              child: Row(
                children: [
                  Icon(
                    escolhido
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color:
                        escolhido ? Colors.indigoAccent : Colors.white24,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _rotulo(tipo),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ),
                  Text(
                    '→ $previa',
                    style: TextStyle(
                      color: escolhido ? Colors.indigoAccent : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const Text(
          'Correção: 1.0.36 → 1.0.37  •  Versão nova: 1.0.36 → 1.1.0  •  '
          'Versão grande: 1.0.36 → 2.0.0',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}

/// Confirmação da publicação: mostra a versão, quem vai receber e qual pacote
/// sobe de verdade (arquivo, tamanho e data) ANTES de enviar para a nuvem.
///
/// O pacote é montado aqui, não no cartão: publicar o `.exe` sozinho (como era
/// antes) não atualizava nada — o programa está no `data/app.so`./// De onde vem a versão que a publicação vai mandar para o cliente.
///
/// Publicar não é sempre "a versão que acabei de compilar": às vezes é repetir
/// uma versão antiga numa empresa (o pacote já está na nuvem e nem precisa
/// subir de novo) e às vezes é deixar o sistema achar o próximo número.
///
/// As três opções que sobem arquivo gravam a versão **no código e compilam**
/// quando é preciso: o número que o cliente compara é o que está COMPILADO no
/// `data/app.so` dele. Publicar um número novo com o pacote antigo faz o cliente
/// baixar e continuar na mesma versão.
enum _FonteVersao {
  /// Compilada agora pelo assistente "Gerar versão" (pacote pronto aqui).
  gerada,

  /// Numeração automática: parte da maior versão conhecida (código × nuvem),
  /// grava o número novo no código e compila antes de enviar.
  automatica,

  /// Pacote que JÁ está na nuvem: só muda quem recebe (não envia arquivo).
  naNuvem,

  /// Pacote compilado nesta máquina, com o número que estiver no campo.
  local,
}

class _DialogoPublicarAtualizacao extends StatefulWidget {
  final _DestinoAtualizacao destino;

  /// Já vem preenchida quando a publicação segue o assistente de gerar versão.
  final String? versaoInicial;
  final String? notasIniciais;

  /// Pacote já compilado pelo assistente (não remonta de novo).
  final PacoteAtualizacao? pacoteInicial;

  /// Versão escolhida no painel "Versões publicadas" (reaproveitar o pacote
  /// que já está na nuvem, sem compilar e sem enviar nada).
  final String? versaoNaNuvemInicial;

  const _DialogoPublicarAtualizacao({
    required this.destino,
    this.versaoInicial,
    this.notasIniciais,
    this.pacoteInicial,
    this.versaoNaNuvemInicial,
  });

  @override
  State<_DialogoPublicarAtualizacao> createState() =>
      _DialogoPublicarAtualizacaoState();
}

class _DialogoPublicarAtualizacaoState
    extends State<_DialogoPublicarAtualizacao> {
  late final TextEditingController _versao = TextEditingController(
      text: widget.versaoInicial ?? AppUpdateService.currentAppVersion);
  late final TextEditingController _notas =
      TextEditingController(text: widget.notasIniciais ?? '');
  bool _forcar = false;
  bool _montandoPacote = true;
  PacoteAtualizacao? _pacote;
  String? _erroPacote;
  bool _publicando = false;
  String _etapa = '';
  String? _resultado;
  bool _sucesso = false;

  /// Como a versão desta publicação é escolhida (as quatro opções da tela).
  _FonteVersao _fonte = _FonteVersao.local;

  /// Numeração automática: que tipo de número novo (correção/versão nova/grande).
  TipoIncrementoVersao _tipoAutomatico = TipoIncrementoVersao.correcao;

  /// Código do projeto nesta máquina — é dele que sai a numeração automática.
  String? _pastaDoProjeto;
  String? _versaoNoCodigo;

  /// Versões cujo pacote já está na nuvem (podem ser reapontadas).
  List<VersaoNaNuvem> _versoesNaNuvem = const [];
  bool _carregandoNuvem = true;
  String? _versaoNaNuvemEscolhida;

  /// Saída da compilação quando a publicação é pela numeração automática.
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    // A versão digitada muda o aviso de "compilou antes de mudar a versão?"
    _versao.addListener(_aoMudarVersao);
    if (widget.versaoNaNuvemInicial != null) {
      // Veio do painel de versões publicadas: reaproveitar o pacote da nuvem.
      _versaoNaNuvemEscolhida = widget.versaoNaNuvemInicial;
      _fonte = _FonteVersao.naNuvem;
    } else if (widget.pacoteInicial != null) {
      // Veio do assistente: o pacote acabou de ser compilado lá.
      _pacote = widget.pacoteInicial;
      _montandoPacote = false;
      _fonte = _FonteVersao.gerada;
    } else {
      _montarPacote();
    }
    _carregarContexto();
  }

  /// Lê o que já está na nuvem (para reaproveitar pacote) e o código do projeto
  /// (para a numeração automática). Roda em paralelo com o pacote local.
  Future<void> _carregarContexto() async {
    final pasta = AppUpdateService.pastaDoProjeto();
    final versaoDoCodigo =
        pasta == null ? null : await AppUpdateService.lerVersaoDoCodigo(pasta);
    final versoes = await AppUpdateService.listarVersoesNaNuvem();
    if (!mounted) return;
    setState(() {
      _pastaDoProjeto = pasta;
      _versaoNoCodigo = versaoDoCodigo;
      _versoesNaNuvem = versoes;
      _carregandoNuvem = false;
      // A escolha só vale se o pacote dela ainda estiver na nuvem (o painel de
      // versões publicadas pode estar um pouco atrás do Storage).
      final escolhida = versoes.any((v) => v.versao == _versaoNaNuvemEscolhida)
          ? _versaoNaNuvemEscolhida
          : (versoes.isEmpty ? null : versoes.first.versao);
      _versaoNaNuvemEscolhida = escolhida;
    });
  }

  void _aoMudarVersao() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _versao.removeListener(_aoMudarVersao);
    _versao.dispose();
    _notas.dispose();
    super.dispose();
  }

  /// A maior versão conhecida: o que está no código × o que já subiu para a
  /// nuvem. A numeração automática parte daqui para nunca repetir um número
  /// (mesmo que o código esteja atrás do que foi publicado).
  String get _versaoBase {
    final maior = AppUpdateService.maiorVersao([
      if (_versaoNoCodigo != null) _versaoNoCodigo!,
      ..._versoesNaNuvem.map((v) => v.versao),
    ]);
    return maior.isEmpty ? AppUpdateService.currentAppVersion : maior;
  }

  String get _versaoAutomatica =>
      AppUpdateService.proximaVersao(_versaoBase, _tipoAutomatico);

  /// A versão que vai ser publicada, conforme a opção escolhida na tela.
  String get _versaoEscolhida {
    switch (_fonte) {
      case _FonteVersao.gerada:
        return widget.versaoInicial ?? AppUpdateService.currentAppVersion;
      case _FonteVersao.automatica:
        return _versaoAutomatica;
      case _FonteVersao.naNuvem:
        return _versaoNaNuvemEscolhida ?? '';
      case _FonteVersao.local:
        return _versao.text.trim().replaceAll('!', '');
    }
  }

  /// Numeração automática só funciona com o código do projeto nesta máquina.
  bool get _podeAutomatica =>
      _pastaDoProjeto != null && _versaoNoCodigo != null;

  bool get _podePublicar {
    switch (_fonte) {
      case _FonteVersao.gerada:
        return widget.pacoteInicial != null;
      case _FonteVersao.automatica:
        return _podeAutomatica;
      case _FonteVersao.naNuvem:
        return (_versaoNaNuvemEscolhida ?? '').isNotEmpty;
      case _FonteVersao.local:
        return !_montandoPacote && _pacote != null;
    }
  }

  /// Só estes dois caminhos usam o pacote montado/compilado nesta máquina.
  bool get _precisaPacoteLocal =>
      _fonte == _FonteVersao.local || _fonte == _FonteVersao.gerada;

  /// A versão que os clientes comparam é a que está COMPILADA no `data/app.so`
  /// (`currentAppVersion`), não a digitada aqui. Publicar um número novo sem
  /// compilar de novo faz o cliente baixar e continuar na mesma versão (e tentar
  /// baixar de novo em cada abertura). Vale só para o pacote desta máquina: os
  /// outros caminhos compilam ou reaproveitam o pacote já certo.
  bool get _versaoDiferenteDaCompilada =>
      _fonte == _FonteVersao.local &&
      widget.pacoteInicial == null &&
      _versao.text.trim().replaceAll('!', '') !=
          AppUpdateService.currentAppVersion;

  Future<void> _montarPacote() async {
    setState(() {
      _montandoPacote = true;
      _erroPacote = null;
    });
    final pacote = await AppUpdateService.empacotarAtualizacao();
    if (!mounted) return;
    setState(() {
      _pacote = pacote;
      _montandoPacote = false;
      _erroPacote = pacote == null
          ? 'Não encontrei o programa compilado (data/app.so + sistema_exodo_novo.exe).\n'
              'Rode "flutter build windows --release" antes de publicar.'
          : null;
    });
  }

  Future<void> _publicar() async {
    setState(() {
      _publicando = true;
      _resultado = null;
      _etapa = 'Preparando...';
      _log.clear();
    });

    final versao = _versaoEscolhida;

    // Pacote que vai subir (só usado nos caminhos que enviam arquivo).
    PacoteAtualizacao? pacote = switch (_fonte) {
      _FonteVersao.gerada => widget.pacoteInicial,
      _FonteVersao.local => _pacote,
      _ => null,
    };

    if (_fonte == _FonteVersao.automatica) {
      // A numeração automática precisa do programa COMPILADO com o número novo:
      // grava no código, compila e monta o pacote aqui, antes de publicar.
      final preparado = await _compilarNaVersaoAutomatica(versao);
      if (preparado == null) return; // o erro já está na tela
      pacote = preparado;
    }

    setState(() => _etapa = 'Publicando...');
    final (sucesso, mensagem) = await AppUpdateService.publicarAtualizacao(
      versao: versao,
      empresaIds: widget.destino.empresas.map((e) => e.id).toList(),
      force: _forcar,
      pacote: pacote,
      usarPacoteDaNuvem: _fonte == _FonteVersao.naNuvem,
      notas: _notas.text,
      onEtapa: (etapa) {
        if (mounted) setState(() => _etapa = etapa);
      },
    );

    // Histórico de versões no projeto (quando o publicador roda do código).
    var historico = false;
    if (sucesso) {
      final destino = widget.destino.global
          ? 'TODOS os clientes'
          : 'empresas: ${widget.destino.empresas.map((e) => e.nomeExibicao).join(', ')}';
      historico = await AppUpdateService.registrarNoHistorico(
        versao: versao,
        detalhes: _notas.text,
        destino: destino,
      );
    }

    if (!mounted) return;
    setState(() {
      _publicando = false;
      _etapa = '';
      _resultado = historico
          ? '$mensagem\n\nAnotado em HISTORICO_VERSOES.md no projeto.'
          : mensagem;
      _sucesso = sucesso;
    });
  }

  /// Grava o número automático no código, compila o programa e monta o pacote.
  ///
  /// É o passo que faz o número publicado ser o MESMO que o cliente enxerga
  /// depois de atualizar. Devolve `null` (deixando o motivo na tela) quando
  /// alguma etapa falha — nesse caso nada é publicado.
  Future<PacoteAtualizacao?> _compilarNaVersaoAutomatica(String versao) async {
    final pasta = _pastaDoProjeto;

    void erro(String mensagem) {
      if (!mounted) return;
      setState(() {
        _publicando = false;
        _etapa = '';
        _sucesso = false;
        _resultado = mensagem;
      });
    }

    if (pasta == null) {
      erro('Não achei o código do projeto nesta máquina para gerar a versão '
          '$versao. Publique pelo pacote compilado aqui ou destrave a pasta do '
          'projeto no assistente "Gerar versão".');
      return null;
    }

    setState(() => _etapa = 'Gravando a versão $versao no código...');
    final (gravou, mensagemGravacao) =
        await AppUpdateService.gravarVersaoNoCodigo(pasta, versao);
    if (!mounted) return null;
    if (!gravou) {
      erro(mensagemGravacao);
      return null;
    }
    setState(() {
      _log.add('>>> $mensagemGravacao');
      _etapa = 'Compilando a versão $versao (pode levar alguns minutos)...';
    });

    final (compilou, resultado) = await AppUpdateService.compilarProjeto(
      pasta: pasta,
      onLinha: (linha) {
        if (!mounted) return;
        setState(() {
          _log.add(linha);
          if (_log.length > 300) _log.removeAt(0);
        });
      },
    );
    if (!mounted) return null;
    if (!compilou) {
      erro(resultado);
      return null;
    }

    setState(() => _etapa = 'Montando o pacote da versão $versao...');
    final pacote = await AppUpdateService.empacotarAtualizacao(
      pasta: p.join(pasta, 'build', 'windows', 'x64', 'runner', 'Release'),
    );
    if (!mounted) return null;
    if (pacote == null) {
      erro('Compilou, mas não achei o programa em '
          'build/windows/x64/runner/Release para montar o pacote.');
      return null;
    }
    setState(() => _log.add('>>> Pacote pronto: ${pacote.tamanhoLegivel}'));
    return pacote;
  }

  @override
  Widget build(BuildContext context) {
    final destino = widget.destino;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: Row(
        children: [
          Icon(destino.global ? Icons.public : Icons.business,
              color: destino.global ? Colors.teal : Colors.cyan),
          const SizedBox(width: 12),
          Text(
            destino.global ? 'Publicar para TODOS' : 'Publicar para empresas',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDestino(destino),
              const SizedBox(height: 16),
              _buildEscolhaVersao(),
              const SizedBox(height: 16),
              TextField(
                controller: _notas,
                enabled: !_publicando,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Detalhes desta atualização ("o que mudou")',
                  labelStyle: const TextStyle(color: Colors.white70),
                  helperText:
                      'Aparece para o cliente na tela de atualização.',
                  helperStyle: const TextStyle(color: Colors.white38),
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_precisaPacoteLocal) _buildPacote(),
              if (_fonte == _FonteVersao.naNuvem) _buildPacoteDaNuvem(),
              if (_fonte == _FonteVersao.automatica) _buildPreparoAutomatico(),
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                value: _forcar,
                activeColor: Colors.orange,
                onChanged: _publicando
                    ? null
                    : (v) => setState(() => _forcar = v ?? false),
                title: const Text(
                  'Forçar (quem já está numa versão mais nova também baixa)',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: const Text(
                  'Use para voltar atrás de uma versão com problema. Sem isto, '
                  'só baixa quem estiver atrasado.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
              if (_publicando) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_etapa,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ],
              if (_resultado != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_sucesso ? Colors.green : Colors.red).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: (_sucesso ? Colors.green : Colors.red)
                            .withOpacity(0.4)),
                  ),
                  child: Text(
                    _resultado!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _publicando ? null : () => Navigator.pop(context),
          child: Text(_resultado == null ? 'Cancelar' : 'Fechar',
              style: const TextStyle(color: Colors.white54)),
        ),
        if (_resultado == null)
          ElevatedButton.icon(
            onPressed: (_publicando || !_podePublicar) ? null : _publicar,
            icon: Icon(
              _fonte == _FonteVersao.automatica
                  ? Icons.auto_awesome
                  : Icons.cloud_upload,
              size: 18,
            ),
            label: Text(
              _fonte == _FonteVersao.automatica
                  ? 'Gerar, compilar e publicar'
                  : 'Publicar',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.destino.global ? Colors.teal : Colors.cyan,
            ),
          ),
      ],
    );
  }

  Widget _buildDestino(_DestinoAtualizacao destino) {
    final cor = destino.global ? Colors.teal : Colors.cyan;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: destino.global
          ? const Text(
              'TODOS os clientes que não têm versão direcionada vão baixar esta '
              'quando abrirem o app.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${destino.empresas.length} empresa(s) vão baixar esta versão:',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                ...destino.empresas.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• ${e.nomeExibicao}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    )),
                const SizedBox(height: 6),
                const Text(
                  'As outras empresas não são afetadas.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
    );
  }

  /// A escolha da versão que vai para o cliente: a que acabou de ser gerada,
  /// a numeração automática, um pacote que já está na nuvem, ou o pacote
  /// pronto nesta máquina (com o número digitado).
  Widget _buildEscolhaVersao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Qual versão vai para o cliente?',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        const Text(
          'O cliente compara o número que está COMPILADO no programa dele com o '
          'publicado aqui.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 10),
        if (widget.pacoteInicial != null)
          _opcaoVersao(
            fonte: _FonteVersao.gerada,
            icone: Icons.rocket_launch,
            cor: Colors.teal,
            titulo: 'A que acabei de gerar — ${widget.versaoInicial}',
            descricao: 'Pacote compilado nesta máquina agora '
                '(${widget.pacoteInicial!.tamanhoLegivel}) — é ele que sobe.',
          ),
        _opcaoVersao(
          fonte: _FonteVersao.automatica,
          icone: Icons.auto_awesome,
          cor: Colors.indigoAccent,
          titulo: 'Numeração automática — $_versaoAutomatica',
          descricao: _podeAutomatica
              ? 'Grava o número no código e compila antes de publicar, então o '
                  'cliente recebe exatamente a $_versaoAutomatica.'
              : 'Não achei o código do projeto nesta máquina para numerar '
                  'sozinho (use o assistente "Gerar versão" ou a pasta do '
                  'projeto).',
          habilitado: _podeAutomatica,
          extra:
              _fonte == _FonteVersao.automatica ? _buildTipoAutomatico() : null,
        ),
        _opcaoVersao(
          fonte: _FonteVersao.naNuvem,
          icone: Icons.cloud_done,
          cor: Colors.cyan,
          titulo: 'Pacote que já está na nuvem',
          descricao: _carregandoNuvem
              ? 'Lendo as versões publicadas...'
              : _versoesNaNuvem.isEmpty
                  ? 'Nenhum pacote publicado ainda.'
                  : 'Não compila e não envia arquivo: só direciona uma versão '
                      'que já subiu para quem você escolher (é assim que se '
                      'volta atrás).',
          habilitado: _versoesNaNuvem.isNotEmpty,
          extra: _fonte == _FonteVersao.naNuvem ? _buildListaNaNuvem() : null,
        ),
        _opcaoVersao(
          fonte: _FonteVersao.local,
          icone: Icons.build,
          cor: Colors.blueGrey,
          titulo:
              'Pacote pronto nesta máquina — ${_versao.text.trim().isEmpty ? AppUpdateService.currentAppVersion : _versao.text.trim()}',
          descricao: 'Usa o programa já compilado aqui e envia o número que '
              'estiver no campo.',
          extra: _fonte == _FonteVersao.local ? _buildCampoVersao() : null,
        ),
        if (_fonte == _FonteVersao.local && _versaoDiferenteDaCompilada)
          _buildAvisoCompilada(),
      ],
    );
  }

  Widget _opcaoVersao({
    required _FonteVersao fonte,
    required IconData icone,
    required Color cor,
    required String titulo,
    required String descricao,
    bool habilitado = true,
    Widget? extra,
  }) {
    final selecionado = _fonte == fonte;
    final ativo = habilitado && !_publicando;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: ativo ? () => setState(() => _fonte = fonte) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  cor.withOpacity(selecionado ? 0.14 : (habilitado ? 0.04 : 0.02)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selecionado ? cor : Colors.white12,
                width: selecionado ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icone, color: habilitado ? cor : Colors.white24, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          color: habilitado
                              ? (selecionado ? cor : Colors.white)
                              : Colors.white38,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        descricao,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selecionado
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selecionado ? cor : Colors.white24,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (selecionado && extra != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8, right: 12, bottom: 2),
            child: extra,
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// O campo do número quando o pacote é o desta máquina.
  Widget _buildCampoVersao() {
    return TextField(
      controller: _versao,
      enabled: !_publicando,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Número da versão',
        labelStyle: const TextStyle(color: Colors.white70),
        helperText: 'A compilada nesta máquina é a '
            '${AppUpdateService.currentAppVersion}.',
        helperStyle: const TextStyle(color: Colors.white38),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
      ),
    );
  }

  Widget _buildAvisoCompilada() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
        ),
        child: Text(
          'Atenção: a versão que os clientes comparam é a que está COMPILADA no '
          'programa (a desta máquina é a '
          '${AppUpdateService.currentAppVersion}). Se você mudou o código, '
          'ajuste currentAppVersion e rode "flutter build windows --release" '
          'ANTES de publicar — senão o cliente baixa e continua na mesma '
          'versão.',
          style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
        ),
      ),
    );
  }

  /// Que tipo de número novo a numeração automática vai criar.
  Widget _buildTipoAutomatico() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Que tipo de número novo?',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TipoIncrementoVersao.values.map((tipo) {
            final escolhido = _tipoAutomatico == tipo;
            return InkWell(
              onTap: _publicando
                  ? null
                  : () => setState(() => _tipoAutomatico = tipo),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: escolhido
                      ? Colors.indigoAccent.withOpacity(0.2)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color:
                          escolhido ? Colors.indigoAccent : Colors.white12),
                ),
                child: Text(
                  '${_rotuloTipo(tipo)} → '
                  '${AppUpdateService.proximaVersao(_versaoBase, tipo)}',
                  style: TextStyle(
                    color: escolhido ? Colors.indigoAccent : Colors.white54,
                    fontSize: 12,
                    fontWeight:
                        escolhido ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'Partindo da maior versão conhecida ($_versaoBase): no código '
          '${_versaoNoCodigo ?? "—"}'
          '${_versoesNaNuvem.isEmpty ? '' : ' • a mais nova na nuvem é a ${_versoesNaNuvem.first.versao}'}.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  String _rotuloTipo(TipoIncrementoVersao tipo) => switch (tipo) {
        TipoIncrementoVersao.correcao => 'Correção',
        TipoIncrementoVersao.versaoNova => 'Versão nova',
        TipoIncrementoVersao.versaoGrande => 'Versão grande',
      };

  /// A lista das versões que já têm pacote na nuvem (reaproveitar sem enviar).
  Widget _buildListaNaNuvem() {
    if (_carregandoNuvem) {
      return const Row(
        children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Lendo as versões publicadas...',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      );
    }
    if (_versoesNaNuvem.isEmpty) {
      return const Text(
        'Nenhum pacote publicado ainda — publique uma versão pelo assistente '
        '"Gerar versão" para começar a lista.',
        style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
      );
    }
    // O valor do DropdownButton tem que existir na lista (senão o Flutter
    // recusa montar o widget): se a escolha não estiver aqui, cai na primeira.
    final selecionada = _versoesNaNuvem
            .any((v) => v.versao == _versaoNaNuvemEscolhida)
        ? _versaoNaNuvemEscolhida
        : _versoesNaNuvem.first.versao;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          value: selecionada,
          isExpanded: true,
          dropdownColor: const Color(0xFF1E1E2E),
          underline: const SizedBox.shrink(),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: _versoesNaNuvem
              .map((v) => DropdownMenuItem<String>(
                    value: v.versao,
                    child: Text(
                      '${v.versao}  •  ${v.tamanhoLegivel}  •  enviado em '
                      '${v.quandoLegivel}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ))
              .toList(),
          onChanged: _publicando
              ? null
              : (v) => setState(() => _versaoNaNuvemEscolhida = v),
        ),
        const SizedBox(height: 4),
        Text(
          '${_versoesNaNuvem.length} versão(ões) com pacote na nuvem. Escolher '
          'uma delas não envia nada: só quem recebe muda.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  /// Cartão do que vai acontecer quando o pacote vem da nuvem.
  Widget _buildPacoteDaNuvem() {
    final escolhidas =
        _versoesNaNuvem.where((v) => v.versao == _versaoNaNuvemEscolhida);
    final escolhida = escolhidas.isEmpty ? null : escolhidas.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyan.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            escolhida == null
                ? 'Nenhum pacote escolhido'
                : '♻️ Nada será enviado — o pacote da versão '
                    '${escolhida.versao} já está na nuvem '
                    '(${escolhida.tamanhoLegivel}, enviado em '
                    '${escolhida.quandoLegivel}).',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'A nuvem só passa a apontar esta versão para o destino escolhido. '
            'Os computadores baixam no próximo "Verificar atualização".',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// Cartão do que a numeração automática vai fazer antes de publicar.
  Widget _buildPreparoAutomatico() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigoAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.indigoAccent.withOpacity(0.3)),
          ),
          child: Text(
            'Ao publicar: grava a versão $_versaoAutomatica no código, roda '
            '"flutter build windows --release" nesta máquina (alguns minutos) '
            'e só então envia o pacote para a nuvem.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            height: 130,
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: ListView(
              reverse: true,
              children: _log.reversed
                  .take(60)
                  .map((linha) => Text(
                        linha,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPacote() {
    if (_montandoPacote) {
      return const Row(
        children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Montando o pacote do programa...',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      );
    }
    if (_erroPacote != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _erroPacote!,
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
          ),
          TextButton.icon(
            onPressed: _montarPacote,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Tentar de novo'),
          ),
        ],
      );
    }
    final pacote = _pacote!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pacote que vai subir',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            '${pacote.tamanhoLegivel}  •  ${pacote.conteudo.join(", ")}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            'Montado de: ${pacote.caminho}',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          Text(
            'Última alteração do app.so: ${pacote.modificadoEm}',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _montandoPacote ? null : _montarPacote,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Montar de novo'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Painel do que está publicado na nuvem: a versão de TODOS os clientes e as
/// direcionadas por empresa, com opção de tirar o direcionamento.
class _DialogoPublicacoes extends StatefulWidget {
  final List<Empresa> empresas;

  const _DialogoPublicacoes({required this.empresas});

  @override
  State<_DialogoPublicacoes> createState() => _DialogoPublicacoesState();
}

class _DialogoPublicacoesState extends State<_DialogoPublicacoes> {
  bool _carregando = true;
  List<PublicacaoVersao> _publicacoes = const [];

  /// Pacotes por versão que estão no Storage: é o que permite reapontar uma
  /// versão sem compilar e sem enviar arquivo de novo.
  List<VersaoNaNuvem> _versoesNaNuvem = const [];
  bool _mexendo = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final lista = await AppUpdateService.listarPublicacoes();
    final versoes = await AppUpdateService.listarVersoesNaNuvem();
    if (!mounted) return;
    setState(() {
      _publicacoes = lista;
      _versoesNaNuvem = versoes;
      _carregando = false;
    });
  }

  VersaoNaNuvem? _pacoteNaNuvem(String versao) {
    final achadas = _versoesNaNuvem.where((v) => v.versao == versao);
    return achadas.isEmpty ? null : achadas.first;
  }

  /// Manda uma versão que JÁ está na nuvem para um destino (sem enviar arquivo).
  /// É o caminho para voltar uma empresa a uma versão anterior.
  Future<void> _direcionar(VersaoNaNuvem versao) async {
    final destino = await showDialog<_DestinoAtualizacao>(
      context: context,
      builder: (context) => _DialogoDestinoAtualizacao(
        empresas: widget.empresas,
      ),
    );
    if (destino == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _DialogoPublicarAtualizacao(
        destino: destino,
        versaoNaNuvemInicial: versao.versao,
      ),
    );
    if (!mounted) return;
    await _carregar();
  }

  String _nomeDoDestino(PublicacaoVersao p) {
    if (p.global) return 'TODOS os clientes';
    final achadas =
        widget.empresas.where((e) => e.id == p.empresaId).toList();
    return achadas.isEmpty
        ? 'Empresa ${p.empresaId}'
        : achadas.first.nomeExibicao;
  }

  Future<void> _remover(PublicacaoVersao p) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Remover esta publicação?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          p.global
              ? 'Nenhum cliente vai receber atualização automática até você '
                  'publicar de novo.'
              : '${_nomeDoDestino(p)} volta a seguir a versão de TODOS os '
                  'clientes. Os computadores dela não são alterados agora.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _mexendo = true);
    final (ok, mensagem) =
        await AppUpdateService.removerPublicacao(p.empresaId);
    if (!mounted) return;
    setState(() => _mexendo = false);
    if (ok) {
      await _carregar();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensagem),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  /// As versões que já têm pacote na nuvem, com o botão de direcionar: escolher
  /// uma delas não compila nada e não envia arquivo — só muda quem recebe.
  Widget _buildPacotesNaNuvem() {
    if (_carregando) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Divider(color: Colors.white12),
        const Text(
          '📦 Pacotes na nuvem (dá para direcionar sem enviar de novo)',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),
        const Text(
          'Use para voltar uma empresa a uma versão anterior ou repetir a mesma '
          'versão em outra empresa.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 8),
        if (_versoesNaNuvem.isEmpty)
          const Text(
            'Nenhum pacote encontrado no Storage. Publique uma versão pelo app '
            'para começar a lista.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
          )
        else
          ..._versoesNaNuvem.map((v) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.archive_outlined,
                        size: 18, color: Colors.cyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${v.versao}  •  ${v.tamanhoLegivel}  •  enviado em '
                        '${v.quandoLegivel}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _mexendo ? null : () => _direcionar(v),
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Direcionar'),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Row(
        children: [
          Icon(Icons.cloud_done, color: Colors.cyan),
          SizedBox(width: 12),
          Text('Versões publicadas', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O que está na nuvem agora. Empresa sem direcionamento segue a '
                'versão de TODOS os clientes.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 12),
              if (_carregando)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.cyan)),
                )
              else if (_publicacoes.isEmpty)
                const Text(
                  'Nada publicado ainda (nem a versão global).',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                )
              else
                ..._publicacoes.map((p) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (p.global ? Colors.teal : Colors.cyan)
                            .withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (p.global ? Colors.teal : Colors.cyan)
                              .withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(p.global ? Icons.public : Icons.business,
                              color: p.global ? Colors.teal : Colors.cyan,
                              size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _nomeDoDestino(p),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                Text(
                                  'versão ${p.versao}'
                                  '${p.forcada ? " (forçada)" : ""}'
                                  '${p.url.isEmpty ? "  •  sem link (não atualiza)" : ""}'
                                  '${_pacoteNaNuvem(p.versao) != null ? "  •  📦 pacote na nuvem" : (p.url.isEmpty ? "" : "  •  ⚠️ pacote não encontrado na nuvem")}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11),
                                ),
                                if (p.atualizadoEm != null)
                                  Text(
                                    'publicada em ${p.atualizadoEm}',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 10),
                                  ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed:
                                _mexendo ? null : () => _remover(p),
                            icon: const Icon(Icons.delete_outline,
                                size: 16, color: Colors.red),
                            label: const Text('Remover',
                                style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    )),
              _buildPacotesNaNuvem(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _carregando ? null : _carregar,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Atualizar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

/// Classe para armazenar o progresso da importação
class ImportProgress {
  final int processados;
  final int total;
  final String etapa;
  final List<String> mensagens;

  ImportProgress({
    required this.processados,
    required this.total,
    required this.etapa,
    required this.mensagens,
  });
}

/// Página de gerenciamento de empresas
class EmpresasPage extends StatefulWidget {
  const EmpresasPage({super.key});

  @override
  State<EmpresasPage> createState() => _EmpresasPageState();
}

class _EmpresasPageState extends State<EmpresasPage> {
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuarioAtual = authService.usuarioAtual;
    
    // Verificar se o usuário é "user" (único que pode acessar configuração da empresa)
    final podeAcessar = usuarioAtual?.email.toLowerCase() == 'user';
    
    if (!podeAcessar) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Gerenciar Empresas'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Acesso Restrito',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Apenas o usuário "user" pode acessar a configuração de empresas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Gerenciar Empresas'),
          actions: [
            // Botão de importar Excel - SEMPRE VISÍVEL
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: const Icon(Icons.file_upload, color: Colors.green, size: 24),
                ),
                tooltip: 'Importar Produtos do Excel',
                onPressed: () => _importarProdutosExcel(context),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Adicionar Empresa',
              onPressed: () async {
                final resultado = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdicionarEmpresaPage(),
                  ),
                );
                if (resultado == true && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Empresa adicionada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Voltar para Login',
              onPressed: () async {
                final confirmar = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E2E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text(
                      'Confirmar Saída',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      'Deseja realmente sair e voltar para a tela de login?',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Sair'),
                      ),
                    ],
                  ),
                );

                if (confirmar == true && mounted) {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  final dataService = Provider.of<DataService>(context, listen: false);
                  
                  await authService.logout();
                  await dataService.definirEmpresaAtual(null);
                  
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginPage(),
                      ),
                      (route) => false,
                    );
                  }
                }
              },
            ),
          ],
        ),
        body: Consumer<AuthService>(
          builder: (context, authService, child) {
            return RefreshIndicator(
              onRefresh: () async {
                await authService.carregarEmpresas();
              },
              child: Builder(
                builder: (context) {
                  // Cards das empresas (apenas empresas permitidas)
                  final empresasPermitidas = authService.getEmpresasDoUsuario();
                  return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Card de importação SEMPRE no topo (sempre visível)
                  _buildCardImportacao(context),
                  // Card de importação de CLIENTES (com saldo devedor/fiado)
                  _buildCardImportacaoClientes(context),
                  // NOVO: Card de Sincronização Supabase (Roxo)
                  if (podeAcessar)
                    _buildCardSupabaseSync(context),
                  // NOVO: Card de Diagnóstico Supabase (Laranja)
                  if (podeAcessar)
                    _buildCardSupabaseDiagnostico(context),
                  // Card do Google Drive - BACKUP (Azul)
                  _buildCardGoogleDriveBackup(context),
                  // NOVO: Card do Google Drive - RESTAURAR (Verde)
                  _buildCardGoogleDriveRestore(context),
                  // NOVO: Card de Backup e Restauracao Local (Vermelho)
                  _buildCardBackupRestore(context),
                  // NOVO: Card de Gerar Versão (numera, compila e publica)
                  if (podeAcessar)
                    _buildCardGerarVersao(context),
                  // NOVO: Card de Publicar Atualização Global
                  if (podeAcessar)
                    _buildCardPublicarAtualizacaoGlobal(context),
                  // NOVO: Card de Gerenciamento do Emissor NFC-e
                  if (podeAcessar)
                    _buildCardBridgeManagement(context),
                  // Card de Monitor de Sincronizacao (Ciano)
                  if (podeAcessar)
                    _buildCardMonitorSync(context),
                  // Cards das empresas
                      if (empresasPermitidas.isEmpty)
                    _buildEmptyState()
                  else
                        ...empresasPermitidas.map((empresa) => _buildEmpresaCard(context, empresa, authService)),
                ],
                  );
                },
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _importarProdutosExcel(context),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.file_upload, color: Colors.white, size: 28),
          label: const Text(
            'IMPORTAR EXCEL',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  /// Card do Monitor de Sincronizacao
  Widget _buildCardMonitorSync(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.cyan.withOpacity(0.3), Colors.cyan.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyan, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MonitorPage()),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.cyan,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyan.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.monitor_heart,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📡 MONITOR DE SINCRONIZACAO',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Status de sync em tempo real de todos os clientes: online, fila, erros e logs.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Realiza o backup de todas as empresas para o Google Drive
  Future<void> _realizarBackupGoogleDrive(BuildContext context) async {
    final driveService = GoogleDriveService.instance;
    
    // Mostrar diálogo de progresso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Backup Google Drive', style: TextStyle(color: Colors.white)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.orange),
            SizedBox(height: 24),
            Text(
              'Realizando exportação e upload de todas as empresas...\nIsso pode levar alguns minutos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );

    try {
      final resultado = await driveService.realizarBackupTodasEmpresas();
      
      if (mounted) {
        Navigator.pop(context); // Fechar loading

        if (resultado['sucesso'] == true) {
          final detalhes = resultado['detalhes'];
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Text('Backup Concluído', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('Total de empresas: ${detalhes['total']}', style: const TextStyle(color: Colors.white70)),
                   Text('Sucesso: ${detalhes['sucesso']}', style: const TextStyle(color: Colors.white)),
                   if (detalhes['falha'] > 0)
                    Text('Falhas: ${detalhes['falha']}', style: const TextStyle(color: Colors.redAccent)),
                   const SizedBox(height: 16),
                   Text('Pasta no Drive: ${detalhes['pasta']}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro no backup: ${resultado['mensagem']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro inesperado: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Card para publicar atualização GLOBAL (afeta todos os clientes)
  Widget _buildCardPublicarAtualizacaoGlobal(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.withOpacity(0.3), Colors.teal.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _publicarAtualizacao(),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.teal,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.teal.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.cloud_upload,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📤 PUBLICAR ATUALIZAÇÃO',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Escolher a versão (a que você acabou de gerar, o próximo '
                        'número automático ou uma que já está na nuvem) e para '
                        'quem vai: TODOS os clientes ou só as empresas marcadas.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.public,
                  color: Colors.white,
                  size: 24,
                ),
              ],
                ),
                const Divider(color: Colors.white12, height: 20),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _verPublicacoes,
                      icon: const Icon(Icons.cloud_done,
                          size: 18, color: Colors.cyan),
                      label: const Text('Ver versões publicadas',
                          style: TextStyle(color: Colors.cyan)),
                    ),
                    const Spacer(),
                    Text(
                      'compila ou reaproveita o pacote da nuvem',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ponto de entrada do cartão de publicação: pergunta o destino (todos os
  /// clientes ou uma empresa) e segue para o fluxo correspondente.
  ///
  /// Os dois fluxos já existiam, mas o destino de uma empresa só estava
  /// acessível escondido no menu de cada empresa — quem clicava no cartão
  /// publicava sempre global, sem escolha.
  Future<void> _publicarAtualizacao() async {
    // Mesma fonte de empresas da lista desta tela: respeita a permissão de
    // quem está publicando.
    final empresas = Provider.of<AuthService>(context, listen: false)
        .getEmpresasDoUsuario()
      ..sort((a, b) =>
          a.nomeExibicao.toLowerCase().compareTo(b.nomeExibicao.toLowerCase()));

    final destino = await showDialog<_DestinoAtualizacao>(
      context: context,
      builder: (context) => _DialogoDestinoAtualizacao(empresas: empresas),
    );

    if (destino == null) return;
    if (!mounted) return;

    await _abrirConfirmacaoDePublicacao(destino);
  }

  /// Abre a confirmação (versão + pacote que vai subir) para o destino escolhido.
  Future<void> _abrirConfirmacaoDePublicacao(
      _DestinoAtualizacao destino) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _DialogoPublicarAtualizacao(destino: destino),
    );
  }

  /// Abre o assistente que numera a versão, compila e publica.
  Future<void> _gerarVersao() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => const _DialogoGerarVersao(),
    );
  }

  /// Card do assistente "Gerar versão" (numeração + compilação + detalhes).
  Widget _buildCardGerarVersao(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.indigoAccent.withOpacity(0.3),
            Colors.indigoAccent.withOpacity(0.1)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigoAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.indigoAccent.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _gerarVersao,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.indigoAccent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.indigoAccent.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.rocket_launch,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🚀 GERAR VERSÃO',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Numera a versão, grava no código, compila e publica — '
                        'com os detalhes do que mudou.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Painel do que está publicado na nuvem (global e por empresa).
  Future<void> _verPublicacoes() async {
    final empresas = Provider.of<AuthService>(context, listen: false)
        .getEmpresasDoUsuario();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _DialogoPublicacoes(empresas: empresas),
    );
  }

  Widget _buildCardBridgeManagement(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.withOpacity(0.3), Colors.orange.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _mostrarDialogoGerenciamentoBridge(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.terminal,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🖥️ GERENCIAR EMISSOR (BRIDGE)',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Atualizar softwares, reiniciar serviços e identificar computadores de emissão remotamente.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.settings_remote,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildBridgeAction_Divider() {
    return Container(
      height: 1,
      color: Colors.white.withOpacity(0.05),
    );
  }

  void _mostrarDialogoGerenciamentoBridge(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.terminal, color: Colors.orange),
            SizedBox(width: 12),
            Text('Comandos do Emissor', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Estes comandos serão enviados para TODOS os computadores que estão rodando o Bridge NFC-e.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _buildBridgeActionTile(
              context,
              icon: Icons.play_arrow,
              color: Colors.orange,
              title: 'Iniciar Forçado (Watchdog)',
              subtitle: 'Aciona o monitor para abrir o emissor se estiver fechado.',
              onTap: () => _selecionarPCEDispararComando(context, 'start', 'Iniciar'),
            ),
            const SizedBox(height: 12),
            _buildBridgeAction_Divider(),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.system_update,
              color: Colors.green,
              title: 'Atualizar Software (Git Pull)',
              subtitle: 'Baixa as correções de código mais recentes.',
              onTap: () => _selecionarPCEDispararComando(context, 'update', 'Atualizar'),
            ),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.restart_alt,
              color: Colors.blue,
              title: 'Reiniciar Serviços',
              subtitle: 'Força o reinício do emissor.',
              onTap: () => _selecionarPCEDispararComando(context, 'restart', 'Reiniciar'),
            ),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.info_outline,
              color: Colors.purple,
              title: 'Identificar Máquinas',
              subtitle: 'Solicita nome do PC e versão do Windows.',
              onTap: () => _selecionarPCEDispararComando(context, 'identify', 'Identificar'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildBridgeActionTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  void _selecionarPCEDispararComando(BuildContext context, String comando, String acaoTitulo, {Map<String, dynamic>? extraData}) {
    // Primeiro traz a UI com a lista de computadores
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('Selecione o PC para $acaoTitulo', style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: SupabaseService.instance.getBridgeStatus(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
              }

              final docs = snapshot.data ?? [];
              
              if (docs.isEmpty) {
                return const Center(
                  child: Text('Nenhum emissor online encontrado.', style: TextStyle(color: Colors.white54)),
                );
              }

              return ListView(
                children: [
                  // Opção de enviar para todos
                  ListTile(
                    leading: const Icon(Icons.computer, color: Colors.white),
                    title: const Text('TODOS OS COMPUTADORES', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context); // Fecha popup
                      _confirmarComandoBridge(context, comando, 'Deseja $acaoTitulo em TODOS os emissores simultaneamente?', targetPc: null, extraData: extraData);
                    },
                  ),
                  const Divider(color: Colors.white24),
                  // Lista de Pcs Específicos
                  ...docs.where((data) => !(data['id']?.toString() ?? '').startsWith('watchdog_')).map((data) {
                    final String pcName = (data['pc_name'] ?? data['id'] ?? 'Desconhecido').toString();
                    final bool isOnline = data['online'] == true;
                    
                    // Busca o watchdog de forma manual
                    bool watchdogOnline = false;
                    for (var d in docs) {
                      if (d['id'] == 'watchdog_$pcName') {
                        if (d['online'] == true) {
                          watchdogOnline = true;
                        }
                        break;
                      }
                    }

                    return ListTile(
                      leading: Icon(
                        Icons.desktop_windows, 
                        color: isOnline ? Colors.green : (watchdogOnline ? Colors.orange : Colors.white12)
                      ),
                      title: Text(pcName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isOnline ? 'Bridge Online' : (watchdogOnline ? 'Proteção Ativa' : 'Offline total'),
                            style: TextStyle(color: isOnline ? Colors.green : (watchdogOnline ? Colors.orange : Colors.white24), fontSize: 11),
                          ),
                          if (data['versao_software'] != null || data['versao_windows'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 2),
                              child: Text(
                                'Versão: ${data['versao_software'] ?? "Desconhecida"} (${data['versao_windows'] ?? "Windows"})',
                                style: const TextStyle(color: Colors.white38, fontSize: 10),
                              ),
                            ),
                          if (data['ultima_empresa'] != null)
                            Text(
                              '🏢 ${data['ultima_empresa']}',
                              style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                      trailing: Icon(Icons.send, color: (isOnline || watchdogOnline) ? Colors.blue : Colors.white10, size: 16),
                      onTap: () {
                        if (!watchdogOnline && comando == 'start') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('❌ Comando "Iniciar" impossível: A Proteção (Watchdog) não está ativa neste PC. Inicie manualmente uma vez para instalar.'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 4),
                            ),
                          );
                          return;
                        }
                        
                        if (!isOnline && !watchdogOnline) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('⚠️ Este PC está totalmente offline.')),
                          );
                          return;
                        }
                        Navigator.pop(context); // Fecha popup
                        _confirmarComandoBridge(context, comando, 'Deseja $acaoTitulo no PC: $pcName?', targetPc: pcName, extraData: extraData);
                      },
                    );
                  }).toList(),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _confirmarComandoBridge(BuildContext context, String comando, String pergunta, {String? targetPc, Map<String, dynamic>? extraData}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2E2E3E),
        title: const Text('Confirmar Comando', style: TextStyle(color: Colors.white)),
        content: Text(pergunta, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('NÃO'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Fecha confirmação
              try {
                debugPrint('>>> [BridgeManager] Enviando comando "$comando" para PC: ${targetPc ?? "Todos"}');
                await BridgeManagementService.instance.enviarComando(comando, targetPc: targetPc, extraData: extraData);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Comando "$comando" enviado com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('>>> [BridgeManager] Erro ao enviar comando: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Erro: $e'), 
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 10),
                      action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('SIM, ENVIAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSupabaseSync(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.withOpacity(0.3), Colors.purple.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _sincronizarComSupabase(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.purple,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.sync, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🗄️ SINCRONIZAR COM SUPABASE',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Enviar dados locais (produtos, clientes, vendas) para nuvem.',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.cloud_sync, color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sincronizarComSupabase(BuildContext context) async {
    if (!SupabaseService.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Supabase não está disponível'), backgroundColor: Colors.red),
      );
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final empresas = authService.getEmpresasDoUsuario();

    if (empresas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Nenhuma empresa encontrada'), backgroundColor: Colors.red),
      );
      return;
    }

    // Mostrar diálogo para selecionar empresa
    String? empresaSelecionadaId;
    
    if (mounted) {
      empresaSelecionadaId = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Selecione a Empresa', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: empresas.length,
              itemBuilder: (context, index) {
                final empresa = empresas[index];
                return ListTile(
                  title: Text(
                    empresa.nomeFantasia ?? empresa.razaoSocial ?? 'Empresa',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    empresa.cnpj ?? '',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () => Navigator.pop(context, empresa.id),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
    }

    if (empresaSelecionadaId == null) return;

    // Carregar dados da empresa selecionada
    final empresaSelecionada = empresas.firstWhere((e) => e.id == empresaSelecionadaId);
    
    // Trocar para a empresa temporariamente para sincronizar
    final dataService = Provider.of<DataService>(context, listen: false);
    await authService.selecionarEmpresa(empresaSelecionada);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF1E1E2E),
        title: Text('Sincronizando...', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(height: 24),
            Text(
              'Enviando dados para o Supabase...\nIsso pode levar alguns minutos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );

    try {
      await dataService.publicarSincronizacaoTotal();
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('Sincronizado!', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              'Dados de "${empresaSelecionada.nomeFantasia ?? empresaSelecionada.razaoSocial ?? 'Empresa'}" sincronizados com sucesso.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Erro ao sincronizar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildCardSupabaseDiagnostico(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.withOpacity(0.3), Colors.orange.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _testarSupabase(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.bug_report, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🔍 TESTAR SUPABASE',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Diagnóstico: verificar se consegue inserir dados.',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.network_check, color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testarSupabase(BuildContext context) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresaId = dataService.currentEmpresaId;
    
    if (empresaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Selecione uma empresa primeiro'), backgroundColor: Colors.red),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF1E1E2E),
        title: Text('Testando...', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.orange),
            SizedBox(height: 24),
            Text(
              'Testando conexão com Supabase...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );

    try {
      final resultado = await SupabaseService.instance.testarInsercao(empresaId);
      
      if (mounted) Navigator.pop(context);
      
      if (resultado['sucesso'] == true) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('Teste OK!', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: const Text(
              'Consegui inserir um registro de teste no Supabase.\n\nA conexão está funcionando!',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 12),
                Text('FALHA!', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              'Não consegui inserir dados:\n\n${resultado['erro']}',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildCardGoogleDriveBackup(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.withOpacity(0.3), Colors.blue.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue, width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _realizarBackupGoogleDrive(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.cloud_upload, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '☁️ BACKUP GLOBAL DRIVE',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Salvar o banco de dados de todas as empresas no Google Drive.',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardBackupRestore(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.withOpacity(0.3), Colors.red.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const BackupRestorePage()),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.storage, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🗄️ BACKUP & RESTAURAÇÃO (LOCAL)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Backup JSON local, restaurar dumps PostgreSQL (.dump/.sql).',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardGoogleDriveRestore(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.withOpacity(0.3), Colors.green.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const GoogleDriveBackupPage()),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.settings_backup_restore, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📥 RESTAURAR DADOS (CLOUDRIVER)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Recuperar dados do Google Drive para o sistema (Individual ou Todas).',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.history, color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhuma empresa cadastrada',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white70,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Toque no botão + para adicionar uma empresa',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white54,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardImportacao(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        final empresaAtual = authService.empresaAtual;
        final empresasPermitidas = authService.getEmpresasDoUsuario();
        final podeImportar = empresaAtual != null || empresasPermitidas.length == 1;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: podeImportar
                ? LinearGradient(
                    colors: [Colors.green.withOpacity(0.3), Colors.green.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [Colors.orange.withOpacity(0.3), Colors.orange.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: podeImportar ? Colors.green : Colors.orange,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (podeImportar ? Colors.green : Colors.orange).withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _importarProdutosExcel(context),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: podeImportar ? Colors.green : Colors.orange,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (podeImportar ? Colors.green : Colors.orange).withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        podeImportar ? Icons.file_upload : Icons.warning,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            podeImportar 
                                ? '📊 IMPORTAR PRODUTOS EXCEL'
                                : '⚠️ Selecione uma empresa para importar',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            podeImportar
                                ? empresaAtual != null
                                    ? 'Empresa: ${empresaAtual.nomeExibicao}\nClique para selecionar arquivo Excel'
                                    : 'Clique para importar produtos de um arquivo Excel'
                                : 'Clique no botão "Selecionar" da empresa primeiro',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      podeImportar ? Icons.arrow_forward_ios : Icons.info_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardImportacaoClientes(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        final empresaAtual = authService.empresaAtual;
        final empresasPermitidas = authService.getEmpresasDoUsuario();
        final podeImportar = empresaAtual != null || empresasPermitidas.length == 1;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.cyanAccent.withOpacity(0.3),
                Colors.blueAccent.withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.cyanAccent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _importarClientesExcel(context),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.people_alt,
                        color: Colors.black87,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '👥 IMPORTAR CLIENTES EXCEL',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            podeImportar
                                ? empresaAtual != null
                                    ? 'Empresa: ${empresaAtual.nomeExibicao}\n'
                                        'Importa clientes e saldo devedor (fiado)'
                                    : 'Importa clientes e saldo devedor (fiado)'
                                : 'Selecione uma empresa antes de importar',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpresaCard(
    BuildContext context,
    Empresa empresa,
    AuthService authService,
  ) {
    final isEmpresaAtual = authService.empresaAtual?.id == empresa.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () async {
          final resultado = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdicionarEmpresaPage(empresa: empresa),
            ),
          );
          if (resultado == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Empresa atualizada com sucesso!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Ícone da empresa
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isEmpresaAtual
                      ? Colors.green.withOpacity(0.2)
                      : Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.business,
                  color: isEmpresaAtual ? Colors.green : Colors.blueAccent,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Informações da empresa
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            empresa.nomeExibicao,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Bridge Status Badge
                        Consumer<DataService>(
                          builder: (context, dataService, _) {
                            final bool isBridgeOnline = dataService.isEmpresaBridgeOnline(empresa.cnpj);
                            if (!isBridgeOnline) return const SizedBox.shrink();
                            
                            return Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withOpacity(0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, color: Colors.green, size: 6),
                                  SizedBox(width: 4),
                                  Text('ONLINE', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            );
                          },
                        ),
                        if (isEmpresaAtual)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Atual',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (empresa.razaoSocial != empresa.nomeExibicao) ...[
                      const SizedBox(height: 4),
                      Text(
                        empresa.razaoSocial,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                    if (empresa.cnpj != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'CNPJ: ${empresa.cnpj}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                    if (empresa.cidade != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${empresa.cidade}${empresa.estado != null ? ' - ${empresa.estado}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: empresa.id));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ ID copiado: ${empresa.id}'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'ID: …${empresa.idFinal}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.4),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.copy_rounded, size: 11, color: Colors.white.withOpacity(0.3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Botão de selecionar (se não for a atual)
              if (!isEmpresaAtual)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Validar acesso antes de selecionar
                      final empresasPermitidas = authService.getEmpresasDoUsuario();
                      if (!empresasPermitidas.any((e) => e.id == empresa.id)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Você não tem permissão para acessar esta empresa'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      await authService.selecionarEmpresa(empresa);
                      final dataService = Provider.of<DataService>(context, listen: false);
                      final empAtualizada = authService.empresaAtual ?? empresa;
                      dataService.setEmpresaAtual(empAtualizada);

                      final motivo = empAtualizada.verificarMotivoBloqueio(
                        ultimaValidacaoOnline: dataService.ultimaValidacaoOnline,
                        ultimaDataExecucao: dataService.ultimaDataExecucao,
                        limiteDiasOffline: 5,
                      );

                      if (mounted) {
                        if (motivo != MotivoBloqueioEmpresa.nenhum && !dataService.liberacaoProvisoriaAtiva) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BloqueioMensalidadePage(
                                configs: empAtualizada.configuracoes ?? {},
                                motivoBloqueio: motivo,
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ Empresa ${empresa.nomeExibicao} selecionada!'),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          setState(() {});
                        }
                      }
                    },
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Selecionar', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              // Menu de ações
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                onSelected: (value) async {
                  if (value == 'editar') {
                    final resultado = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdicionarEmpresaPage(empresa: empresa),
                      ),
                    );
                    if (resultado == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Empresa atualizada com sucesso!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else if (value == 'selecionar') {
                    // Validar acesso antes de selecionar
                    final empresasPermitidas = authService.getEmpresasDoUsuario();
                    if (!empresasPermitidas.any((e) => e.id == empresa.id)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Você não tem permissão para acessar esta empresa'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    await authService.selecionarEmpresa(empresa);
                    final dataService = Provider.of<DataService>(context, listen: false);
                    final empAtualizada = authService.empresaAtual ?? empresa;
                    dataService.setEmpresaAtual(empAtualizada);

                    final motivo = empAtualizada.verificarMotivoBloqueio(
                      ultimaValidacaoOnline: dataService.ultimaValidacaoOnline,
                      ultimaDataExecucao: dataService.ultimaDataExecucao,
                      limiteDiasOffline: 5,
                    );

                    if (mounted) {
                      if (motivo != MotivoBloqueioEmpresa.nenhum && !dataService.liberacaoProvisoriaAtiva) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BloqueioMensalidadePage(
                              configs: empAtualizada.configuracoes ?? {},
                              motivoBloqueio: motivo,
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Empresa ${empresa.nomeExibicao} selecionada'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  } else if (value == 'importar_produtos') {
                    // Verificar se a empresa está selecionada
                    if (!isEmpresaAtual) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Selecione a empresa antes de importar produtos'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    _importarProdutosExcel(context);
                  } else if (value == 'excluir') {
                    _confirmarExclusao(context, empresa, authService);
                  } else if (value == 'vincular_bridge') {
                    _selecionarPCEDispararComando(
                      context, 
                      'set_identity', 
                      'Vincular Computador',
                      extraData: {
                        'cnpj': empresa.cnpj,
                        'nome': empresa.nomeExibicao,
                      }
                    );
                  } else if (value == 'reiniciar_bridge') {
                    _selecionarPCEDispararComando(
                      context, 
                      'restart', 
                      'Reiniciar Emissor',
                    );
                  } else if (value == 'outros_bridge') {
                    _mostrarDialogoGerenciamentoBridge(context);
                  } else if (value == 'publicar_atualizacao') {
                    _publicarAtualizacaoParaEmpresa(context, empresa);
                  }
                },
                itemBuilder: (context) {
                  final usuarioAtual = authService.usuarioAtual;
                  final isUsuarioMaster = usuarioAtual?.email.toLowerCase() == 'user';
                  final podeImportarDeletar = isUsuarioMaster || usuarioAtual?.isMaster == true;
                  
                  return [
                    const PopupMenuItem(
                      value: 'editar',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    if (!isEmpresaAtual)
                      const PopupMenuItem(
                        value: 'selecionar',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, size: 20),
                            SizedBox(width: 8),
                            Text('Selecionar'),
                          ],
                        ),
                      ),
                    if (isEmpresaAtual && podeImportarDeletar)
                      const PopupMenuItem(
                        value: 'importar_produtos',
                        child: Row(
                          children: [
                            Icon(Icons.file_upload, size: 20, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Importar Produtos Excel', style: TextStyle(color: Colors.green)),
                          ],
                        ),
                      ),
                    if (podeImportarDeletar)
                      const PopupMenuItem(
                        value: 'excluir',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Excluir', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    
                    // Opção de Vínculo do Bridge (Apenas ADMIN "user")
                    if (isUsuarioMaster) ...[
                      const PopupMenuItem(
                        value: 'reiniciar_bridge',
                        child: Row(
                          children: [
                            Icon(Icons.restart_alt, color: Colors.blue, size: 20),
                            SizedBox(width: 12),
                            Text('Reiniciar Emissor', style: TextStyle(color: Colors.blue)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'vincular_bridge',
                        child: Row(
                          children: [
                            Icon(Icons.settings_remote, color: Colors.orange, size: 20),
                            SizedBox(width: 12),
                            Text('Vincular Bridge', style: TextStyle(color: Colors.orange)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'outros_bridge',
                        child: Row(
                          children: [
                            Icon(Icons.more_horiz, color: Colors.white70, size: 20),
                            SizedBox(width: 12),
                            Text('Outros Comandos'),
                          ],
                        ),
                      ),
                      // Separador visual
                      PopupMenuDivider(),
                      // NOVO: Publicar Atualização para esta empresa
                      const PopupMenuItem(
                        value: 'publicar_atualizacao',
                        child: Row(
                          children: [
                            Icon(Icons.cloud_upload, color: Colors.cyan, size: 20),
                            SizedBox(width: 12),
                            Text('📤 Publicar Atualização', style: TextStyle(color: Colors.cyan)),
                          ],
                        ),
                      ),
                    ],
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Publica uma atualização do app direcionada para esta empresa no Supabase
  Future<void> _publicarAtualizacaoParaEmpresa(
      BuildContext context, Empresa empresa) async {
    await _abrirConfirmacaoDePublicacao(
        _DestinoAtualizacao.paraEmpresas(<Empresa>[empresa]));
  }

  void _confirmarExclusao(
    BuildContext context,
    Empresa empresa,
    AuthService authService,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Confirmar Exclusão',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja realmente excluir a empresa "${empresa.nomeExibicao}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              await authService.removerEmpresa(empresa.id);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Empresa excluída com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  /// Importa produtos de um arquivo Excel
  Future<void> _importarProdutosExcel(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);

    // Se não há empresa selecionada, tentar selecionar automaticamente
    if (authService.empresaAtual == null) {
      final empresasPermitidas = authService.getEmpresasDoUsuario();
      // Se houver apenas uma empresa permitida, selecionar automaticamente
      if (empresasPermitidas.length == 1) {
        await authService.selecionarEmpresa(empresasPermitidas.first);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Empresa ${empresasPermitidas.first.nomeExibicao} selecionada automaticamente'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (empresasPermitidas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma empresa cadastrada. Adicione uma empresa primeiro.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      } else {
        // Se houver múltiplas empresas, pedir para selecionar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione uma empresa antes de importar produtos (menu da empresa → Selecionar)'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    // Mostrar diálogo de instruções
    final continuar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Importar Produtos do Excel',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Formato esperado do Excel:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Coluna A: Código (opcional)\n'
                'Coluna B: Nome (obrigatório)\n'
                'Coluna C: Descrição (opcional)\n'
                'Coluna D: Unidade (padrão: UN)\n'
                'Coluna E: Grupo (padrão: Sem Grupo)\n'
                'Coluna F: Preço (obrigatório)\n'
                'Coluna G: Preço de Custo (opcional)\n'
                'Coluna H: Estoque (padrão: 0)\n'
                'Coluna I: Código de Barras (opcional)',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠️ A primeira linha será ignorada (cabeçalho).\n'
                  '⚠️ Produtos duplicados serão ignorados.\n'
                  '⚠️ Produtos existentes serão atualizados.',
                  style: TextStyle(color: Colors.orange, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (continuar != true) return;

    // Selecionar arquivo
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true, // IMPORTANTE: precisa dos bytes na web
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar arquivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (result == null || result.files.isEmpty) {
      return; // Usuário cancelou
    }

    final platformFile = result.files.single;
    
    // Verificar se tem bytes (web) ou path (desktop/mobile)
    if (platformFile.bytes == null && platformFile.path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: não foi possível ler o arquivo'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Mostrar diálogo de progresso com atualização em tempo real
    final progressNotifier = ValueNotifier<ImportProgress>(
      ImportProgress(processados: 0, total: 0, etapa: 'Iniciando...', mensagens: []),
    );
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<ImportProgress>(
        valueListenable: progressNotifier,
        builder: (context, progress, child) {
          final percentual = progress.total > 0 
              ? (progress.processados / progress.total * 100).toStringAsFixed(1)
              : '0.0';
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text(
              'Importando Produtos',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // Barra de progresso
                LinearProgressIndicator(
                  value: progress.total > 0 ? progress.processados / progress.total : 0,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  minHeight: 8,
                ),
                const SizedBox(height: 16),
                // Texto do progresso
                Text(
                  '${progress.processados} de ${progress.total} (${percentual}%)',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                // Etapa atual
                Text(
                  progress.etapa,
                  style: const TextStyle(color: Colors.blueAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Lista de mensagens (últimas 5)
                if (progress.mensagens.isNotEmpty) ...[
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      reverse: true,
                      itemCount: progress.mensagens.length > 5 ? 5 : progress.mensagens.length,
                      itemBuilder: (context, index) {
                        final msgIndex = progress.mensagens.length - 1 - index;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text(
                            progress.mensagens[msgIndex],
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );

    // Callback de progresso
    void onProgress(int processados, int total, String etapa) {
      progressNotifier.value = ImportProgress(
        processados: processados,
        total: total,
        etapa: etapa,
        mensagens: [...progressNotifier.value.mensagens, etapa].take(20).toList(),
      );
    }

    // Importar produtos
    try {
      // Usar bytes se disponível (web), senão usar path (desktop/mobile)
      final resultado = platformFile.bytes != null
          ? await ExcelImportService.importarProdutosDeBytes(
              platformFile.bytes!,
              dataService,
              onProgress: onProgress,
            )
          : await ExcelImportService.importarProdutos(
              File(platformFile.path!),
              dataService,
              onProgress: onProgress,
            );

      if (mounted) {
        Navigator.pop(context); // Fechar diálogo de progresso

        // Mostrar resultado
        final mensagem = resultado['mensagens'] as List<String>;
        final sucesso = resultado['sucesso'] as int;
        final atualizados = resultado['atualizados'] as int;
        final duplicados = resultado['duplicados'] as int;
        final erros = resultado['erros'] as int;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text(
              'Resultado da Importação',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✅ Novos: $sucesso\n'
                    '🔄 Atualizados: $atualizados\n'
                    '⚠️ Duplicados ignorados: $duplicados\n'
                    '❌ Erros: $erros',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (mensagem.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Detalhes:',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...mensagem.take(10).map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            m,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        )),
                    if (mensagem.length > 10)
                      Text(
                        '... e mais ${mensagem.length - 10} mensagens',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (sucesso > 0 || atualizados > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ ${sucesso + atualizados} produtos processados com sucesso!',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          
          // Aguardar Firebase sincronizar e salvar localmente
          await Future.delayed(const Duration(seconds: 2));
          await dataService.salvarImediatamente();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Fechar loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao importar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Importa CLIENTES (com saldo devedor/fiado) de um arquivo Excel.
  Future<void> _importarClientesExcel(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);

    // Garantir empresa selecionada (mesma regra do importador de produtos).
    if (authService.empresaAtual == null) {
      final empresasPermitidas = authService.getEmpresasDoUsuario();
      if (empresasPermitidas.length == 1) {
        await authService.selecionarEmpresa(empresasPermitidas.first);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Empresa ${empresasPermitidas.first.nomeExibicao} selecionada automaticamente',
              ),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (empresasPermitidas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma empresa cadastrada. Adicione uma empresa primeiro.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione uma empresa antes de importar clientes'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    bool lancarFiadoEmAberto = true;

    // Diálogo de instruções + opção de lançar o fiado inicial.
    final continuar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text(
            'Importar Clientes do Excel',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Formato esperado (qualquer ordem, o sistema detecta pelo cabeçalho):',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nome (obrigatório)\n'
                  'CPF/CNPJ (opcional)\n'
                  'Telefone / Celular / WhatsApp\n'
                  'E-mail, Endereço, Número, Bairro, Cidade, UF, CEP\n'
                  'Limite de Crédito (opcional)\n'
                  'Saldo Devedor / Fiado (opcional)\n'
                  'Observações (opcional)',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'O saldo devedor é gravado no cadastro do cliente e fica '
                    'disponível para recebimento.',
                    style: TextStyle(color: Colors.cyanAccent, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: lancarFiadoEmAberto,
                  onChanged: (v) =>
                      setStateDialog(() => lancarFiadoEmAberto = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.cyanAccent,
                  title: const Text(
                    'Lançar o saldo como FIADO em aberto',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Cria um lançamento pendente por cliente, para aparecer na '
                    'aba FIADO/CREDIÁRIO do PDV e nos extratos.',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '⚠️ A primeira linha é o cabeçalho.\n'
                    '⚠️ Clientes já cadastrados têm o cadastro completado, mas o '
                    'saldo devedor existente NÃO é alterado (evita cobrar em dobro).',
                    style: TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );

    if (continuar != true) return;

    // Selecionar arquivo.
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar arquivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (result == null || result.files.isEmpty) return; // cancelado
    final platformFile = result.files.single;
    if (platformFile.bytes == null && platformFile.path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: não foi possível ler o arquivo'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Diálogo de progresso.
    final progressNotifier = ValueNotifier<ImportProgress>(
      ImportProgress(processados: 0, total: 0, etapa: 'Iniciando...', mensagens: []),
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<ImportProgress>(
        valueListenable: progressNotifier,
        builder: (context, progress, child) {
          final percentual = progress.total > 0
              ? (progress.processados / progress.total * 100).toStringAsFixed(1)
              : '0.0';
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text(
              'Importando Clientes',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress.total > 0
                        ? progress.processados / progress.total
                        : 0,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyan),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    progress.total > 0
                        ? '${progress.processados} de ${progress.total} ($percentual%)'
                        : 'Processando...',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress.etapa,
                    style: const TextStyle(color: Colors.cyan, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    void onProgress(int processados, int total, String etapa) {
      final atual = progressNotifier.value;
      progressNotifier.value = ImportProgress(
        processados: processados,
        total: total > 0 ? total : atual.total,
        etapa: etapa,
        mensagens: [...atual.mensagens, etapa].take(20).toList(),
      );
    }

    try {
      final resultado = platformFile.bytes != null
          ? await ClienteImportService.importarClientesDeBytes(
              platformFile.bytes!,
              dataService,
              lancarFiadoEmAberto: lancarFiadoEmAberto,
              onProgress: onProgress,
            )
          : await ClienteImportService.importarClientes(
              File(platformFile.path!),
              dataService,
              lancarFiadoEmAberto: lancarFiadoEmAberto,
              onProgress: onProgress,
            );

      if (!mounted) return;
      Navigator.pop(context); // fecha progresso
      progressNotifier.dispose();

      final mensagens = (resultado['mensagens'] as List).cast<String>();
      final sucesso = resultado['sucesso'] as int;
      final atualizados = resultado['atualizados'] as int;
      final ignorados = resultado['ignorados'] as int;
      final erros = resultado['erros'] as int;
      final fiados = resultado['fiados'] as int;
      final saldoTotal = (resultado['saldoTotal'] as num).toDouble();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text(
            'Resultado da Importação',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✅ Novos clientes: $sucesso\n'
                  '💰 Saldo devedor total: R\$ ${saldoTotal.toStringAsFixed(2)}\n'
                  '🧾 Fiados em aberto criados: $fiados\n'
                  '🔄 Atualizados: $atualizados\n'
                  '⚠️ Ignorados: $ignorados\n'
                  '❌ Erros: $erros',
                  style: const TextStyle(color: Colors.white70),
                ),
                if (mensagens.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Detalhes:',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...mensagens.take(10).map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        m,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                  ),
                  if (mensagens.length > 10)
                    Text(
                      '... e mais ${mensagens.length - 10} mensagens',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (sucesso > 0 || atualizados > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${sucesso + atualizados} clientes processados com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        await dataService.salvarImediatamente();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // fecha loading
        progressNotifier.dispose();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao importar clientes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

