import 'dart:async';

import 'package:flutter/material.dart';

import '../services/env_config.dart';
import '../services/lan_config_service.dart';

/// Configuração da REDE LOCAL entre os PCs da mesma loja — feita toda pelo app.
///
/// Antes isso era editar o `.env` à mão e rodar um script do PowerShell como
/// Administrador, sabendo o IP do outro computador. Aqui o usuário só:
///   1. deixa o interruptor ligado;
///   2. toca em "Procurar PCs na rede" e escolhe o outro computador (o app varre
///      a rede e confirma qual deles tem o banco do Êxodo);
///   3. toca em "Liberar este PC na rede" (o Windows pede a senha de
///      Administrador) — e faz o MESMO no outro computador;
///   4. salva e reinicia o sincronizador.
///
/// Nada aqui fala com a nuvem: a LAN é só um atalho a mais entre os dois PCs, e
/// a nuvem continua sendo o caminho principal.
class ConfiguracaoLanPage extends StatefulWidget {
  const ConfiguracaoLanPage({
    super.key,
    this.configInicial,
    this.buscar,
    this.testar,
    this.salvar,
    this.preparar,
    this.reiniciar,
    this.lerLog,
    this.ipLocal,
    this.nomeLocal,
    this.caminhoDoEnv,
  });

  /// Injeções usadas pelos testes. Em produção ficam nulas e a tela usa o
  /// [RedeLocalService].
  final ConfigRedeLocal? configInicial;
  final Future<ResultadoBuscaRede> Function(
    void Function(String etapa, int feitos, int total) progresso,
  )? buscar;
  final Future<(bool, String)> Function(String host, int porta)? testar;
  final Future<(bool, String)> Function(ConfigRedeLocal cfg)? salvar;
  final Future<(bool, String)> Function(String host)? preparar;
  final Future<bool> Function()? reiniciar;
  final Future<List<String>> Function()? lerLog;
  final String? ipLocal;

  /// Nome deste computador — é o que o OUTRO PC deve informar no campo.
  final String? nomeLocal;

  /// Caminho do `.env` gravado — só para teste. Sem ele, a tela lê o real via
  /// [EnvConfig]. Mostrar isso é o que explica o caso em que a configuração
  /// "salva" mas não vale para o sincronizador instalado.
  final String? caminhoDoEnv;

  @override
  State<ConfiguracaoLanPage> createState() => _ConfiguracaoLanPageState();
}

class _ConfiguracaoLanPageState extends State<ConfiguracaoLanPage> {
  static const Color _fundo = Color(0xFF0F0F1E);
  static const Color _card = Color(0xFF1E1E2E);
  static const Color _verde = Color(0xFF4CAF50);
  static const Color _amarelo = Colors.amberAccent;
  static const Color _azul = Colors.lightBlueAccent;

  late ConfigRedeLocal _cfg;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portaCtrl;
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _diasCtrl;

  bool _ligado = false;
  bool _inicialCompleto = false;
  String _ipLocal = '';
  String _nomeLocal = '';

  bool _buscando = false;
  String _progresso = '';
  ResultadoBuscaRede? _busca;

  bool _testando = false;
  String? _resultadoTeste;
  bool _testeOk = false;

  bool _preparando = false;
  bool _salvando = false;
  bool _reiniciando = false;

  List<String> _log = const <String>[];

  @override
  void initState() {
    super.initState();
    _cfg = widget.configInicial ?? ConfigRedeLocal.ler();
    _ligado = _cfg.ligado;
    _inicialCompleto = _cfg.inicialCompleto;
    _hostCtrl = TextEditingController(text: _cfg.host);
    _portaCtrl = TextEditingController(text: '${_cfg.porta}');
    _nomeCtrl = TextEditingController(text: _cfg.nome);
    _diasCtrl = TextEditingController(text: '${_cfg.diasTombstone}');
    _ipLocal = widget.ipLocal ?? '';
    _nomeLocal = widget.nomeLocal ?? RedeLocalService.nomeProvavel();
    if (widget.ipLocal == null) {
      // Descobrir o próprio IP não é indispensável: a tela funciona sem ele.
      RedeLocalService.ipProvavel().then((ip) {
        if (mounted && ip.isNotEmpty) setState(() => _ipLocal = ip);
      });
    }
    _carregarLog();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portaCtrl.dispose();
    _nomeCtrl.dispose();
    _diasCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Ações
  // ───────────────────────────────────────────────────────────────────────────

  ConfigRedeLocal _montarConfig() {
    return ConfigRedeLocal(
      ligado: _ligado,
      host: _hostCtrl.text.trim(),
      porta: int.tryParse(_portaCtrl.text.trim()) ?? 5432,
      nome: _nomeCtrl.text.trim(),
      diasTombstone: int.tryParse(_diasCtrl.text.trim()) ?? 30,
      inicialCompleto: _inicialCompleto,
    );
  }

  Future<void> _carregarLog() async {
    final ler = widget.lerLog ?? RedeLocalService.ultimasLinhasLan;
    try {
      final linhas = await ler();
      if (!mounted) return;
      setState(() => _log = linhas);
    } catch (_) {}
  }

  Future<void> _procurar() async {
    setState(() {
      _buscando = true;
      _progresso = 'Procurando...';
      _busca = null;
    });
    final buscar = widget.buscar ?? _buscarPadrao;
    try {
      final resultado = await buscar((etapa, feitos, total) {
        if (!mounted) return;
        setState(() => _progresso = _textoDaEtapa(etapa, feitos, total));
      });
      if (!mounted) return;
      setState(() {
        _busca = resultado;
        if (resultado.pares.length == 1) {
          // Grava o NOME do par (e não o IP): é ele que não muda quando o
          // DHCP troca o endereço da máquina.
          final par = resultado.pares.first;
          _hostCtrl.text = par.nome ?? par.host;
          _portaCtrl.text = '${par.porta}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busca = null);
      _avisar('❌ Não consegui procurar na rede: $e', erro: true);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<ResultadoBuscaRede> _buscarPadrao(
    void Function(String etapa, int feitos, int total) progresso,
  ) {
    return RedeLocalService.procurarPares(progresso: progresso);
  }

  String _textoDaEtapa(String etapa, int feitos, int total) {
    switch (etapa) {
      case 'testando':
        return 'Entrando no banco dos PCs encontrados... ($feitos/$total)';
      case 'procurando_pcs':
        return 'Procurando computadores na rede... ($feitos/$total)';
      default:
        return 'Procurando o PostgreSQL na rede... ($feitos/$total)';
    }
  }

  Future<void> _testar() async {
    final host = _hostCtrl.text.trim();
    final porta = int.tryParse(_portaCtrl.text.trim()) ?? 5432;
    setState(() {
      _testando = true;
      _resultadoTeste = null;
    });
    final testar = widget.testar ?? RedeLocalService.testarConexao;
    try {
      final (ok, mensagem) = await testar(host, porta);
      if (!mounted) return;
      setState(() {
        _testeOk = ok;
        _resultadoTeste = mensagem;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testeOk = false;
        _resultadoTeste = 'Erro ao testar: $e';
      });
    } finally {
      if (mounted) setState(() => _testando = false);
    }
  }

  Future<void> _preparar() async {
    // Campo vazio = liberar a REDE LOCAL inteira (o padrão). É o que permite
    // montar uma loja com vários PCs sem cruzar IP a IP.
    final host = _hostCtrl.text.trim();
    final redeToda = host.isEmpty;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Liberar este PC na rede?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'O Windows vai pedir a senha de Administrador.\n\n'
          '${redeToda ? 'Vou liberar os computadores da SUA REDE LOCAL no banco deste PC.' : 'Vou liberar o acesso do PC $host ao banco deste PC.'} '
          'O acesso continua exigindo usuário e senha do banco.\n\n'
          'O PostgreSQL local vai REINICIAR (por alguns segundos o sistema pode '
          'mostrar "sem conexão" e volta sozinho).\n\n'
          '${redeToda ? 'Nos outros computadores da loja, faça o mesmo: também não precisa informar IP.' : 'Faça o mesmo preparo no outro computador, apontando para o IP deste PC: ${_ipLocal.isEmpty ? '(veja o IP na rede)' : _ipLocal}.'}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar', style: TextStyle(color: _verde)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _preparando = true);
    final preparar = widget.preparar ?? RedeLocalService.prepararEstePc;
    try {
      final (ok, mensagem) = await preparar(host);
      if (!mounted) return;
      _avisar('${ok ? '✅' : '⚠️'} $mensagem', erro: !ok);
      if (ok) {
        // O script grava PAR_HOST no .env: a tela mostra o que ficou salvo.
        _reLerDoArquivo();
        await _carregarLog();
      }
    } catch (e) {
      if (!mounted) return;
      _avisar('⚠️ Não consegui preparar este PC: $e', erro: true);
    } finally {
      if (mounted) setState(() => _preparando = false);
    }
  }

  /// Recarrega o que está no `.env` para os campos da tela.
  void _reLerDoArquivo() {
    final lido = ConfigRedeLocal.ler();
    if (!mounted) return;
    setState(() {
      _cfg = lido;
      _ligado = lido.ligado;
      _inicialCompleto = lido.inicialCompleto;
      _hostCtrl.text = lido.host;
      _portaCtrl.text = '${lido.porta}';
      _nomeCtrl.text = lido.nome;
      _diasCtrl.text = '${lido.diasTombstone}';
    });
  }

  Future<void> _salvar({bool reiniciarDepois = false}) async {
    setState(() => _salvando = true);
    final cfg = _montarConfig();
    final salvar = widget.salvar ?? RedeLocalService.salvar;
    try {
      final (ok, mensagem) = await salvar(cfg);
      if (!mounted) return;
      if (ok) setState(() => _cfg = cfg);
      _avisar('${ok ? '✅' : '❌'} $mensagem', erro: !ok);
    } catch (e) {
      if (!mounted) return;
      _avisar('❌ Não consegui salvar: $e', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
    if (reiniciarDepois) await _reiniciarSincronizador();
  }

  Future<void> _reiniciarSincronizador() async {
    setState(() => _reiniciando = true);
    final reiniciar = widget.reiniciar ?? RedeLocalService.reiniciarSincronizador;
    try {
      final ok = await reiniciar();
      if (!mounted) return;
      _avisar(
        ok
            ? '✅ Sincronizador reiniciado com a nova configuração.'
            : '⚠️ Não consegui reiniciar o sincronizador. Feche pelo ícone da '
                'bandeja e abra de novo.',
        erro: !ok,
      );
    } catch (e) {
      if (!mounted) return;
      _avisar('⚠️ Não consegui reiniciar o sincronizador: $e', erro: true);
    } finally {
      if (mounted) setState(() => _reiniciando = false);
      await _carregarLog();
    }
  }

  void _avisar(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Tela
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: _card,
        title: const Text('Rede local entre os PCs'),
        actions: [
          IconButton(
            tooltip: 'Atualizar o log',
            onPressed: _carregarLog,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _cartao(
            titulo: 'Sincronizar com o outro PC',
            icone: Icons.lan_outlined,
            filhos: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: _verde,
                value: _ligado,
                onChanged: (valor) => setState(() => _ligado = valor),
                title: const Text('Ligar a rede local',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Os dois computadores da loja passam a atualizar os bancos '
                  'direto pela rede. A nuvem continua funcionando normalmente.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              if (_nomeLocal.isNotEmpty)
                _linha('Este computador se chama ', _nomeLocal, cor: _verde),
              if (_ipLocal.isNotEmpty)
                _linha('Agora o IP dele na rede é ', _ipLocal, cor: _azul),
              if (_nomeLocal.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'No OUTRO PC, use ESTE nome no campo abaixo. O nome não muda '
                    'quando o IP muda.',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
            ],
          ),
          _cartao(
            titulo: 'Qual é o outro computador?',
            icone: Icons.computer,
            filhos: [
              const Text(
                'Toque em procurar: eu varro a rede da loja e mostro os '
                'computadores encontrados. Você só escolhe o outro.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                'Prefira o NOME do computador ao IP: o IP da loja vem do roteador '
                'e muda de tempos em tempos; o nome acompanha a máquina. O nome '
                'exato aparece no outro PC em Configurações > Sistema > Sobre.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _buscando ? null : _procurar,
                      icon: _buscando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: Text(_buscando ? 'Procurando...' : 'Procurar PCs'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _testando ? null : _testar,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Testar'),
                  ),
                ],
              ),
              if (_buscando && _progresso.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_progresso,
                    style: const TextStyle(color: _azul, fontSize: 12)),
              ],
              if (_resultadoTeste != null) ...[
                const SizedBox(height: 12),
                _faixa(
                  _resultadoTeste!,
                  cor: _testeOk ? _verde : Colors.orangeAccent,
                  icone: _testeOk ? Icons.check_circle : Icons.error_outline,
                ),
              ],
              ..._resultadoDaBusca(),
              const SizedBox(height: 12),
              TextField(
                controller: _hostCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nome do outro computador (ou IP)',
                  hintText: 'ex.: PC-CAIXA-2',
                  helperText:
                      'Use o nome do computador. O IP também funciona, mas muda.',
                  helperStyle: TextStyle(color: Colors.white38, fontSize: 11),
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _portaCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Porta',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nomeCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Apelido do par (opcional)',
                        hintText: 'ex.: Caixa 2',
                        helperText: 'Só para o log; não afeta a conexão.',
                        helperStyle:
                            TextStyle(color: Colors.white38, fontSize: 11),
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          _cartao(
            titulo: 'Liberar este PC para a rede',
            icone: Icons.verified_user_outlined,
            filhos: [
              const Text(
                'Enquanto isso não é feito, nenhum outro PC consegue entrar no '
                'banco daqui. Faça em CADA computador da loja — e não precisa '
                'informar IP: o padrão libera a sua rede local inteira (o acesso '
                'continua exigindo usuário e senha). O Windows vai pedir a senha '
                'de Administrador.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _preparando ? null : _preparar,
                icon: _preparando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shield_outlined),
                label: Text(_preparando
                    ? 'Preparando este PC...'
                    : 'Liberar este PC na rede'),
              ),
            ],
          ),
          _cartao(
            titulo: 'Avançado',
            icone: Icons.tune,
            filhos: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: _verde,
                value: _inicialCompleto,
                onChanged: (valor) =>
                    setState(() => _inicialCompleto = valor ?? false),
                title: const Text('Puxar o histórico inteiro no 1º contato',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text(
                  'Normalmente deixe desligado: o histórico já vem pela nuvem, '
                  'e ligar isso faz um download grande de graça.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _diasCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Guardar apagados (dias)',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          _cartao(
            titulo: 'O que o sincronizador está fazendo',
            icone: Icons.receipt_long,
            filhos: _log.isEmpty
                ? const <Widget>[
                    Text(
                      'Nada registrado ainda. Depois de salvar, as linhas [LAN] '
                      'aparecem aqui.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ]
                : _log
                    .map<Widget>((linha) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            linha,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ))
                    .toList(),
          ),
          const SizedBox(height: 4),
          _avisoDoArquivoEnv(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _salvando ? null : () => _salvar(),
                  icon: _salvando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Salvar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _salvando
                      ? null
                      : () => _salvar(reiniciarDepois: true),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Salvar e reiniciar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _reiniciando ? null : _reiniciarSincronizador,
            icon: _reiniciando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: const Text('Só reiniciar o sincronizador'),
          ),
          const SizedBox(height: 16),
          if (_cfg.pronto)
            _faixa(
              'Rede local ATIVA com ${_cfg.host}:${_cfg.porta} '
              '(salvo neste computador).'
              '${_cfg.hostEhNome ? ' Informado pelo NOME: se o IP do outro PC '
                  'mudar, a rede se ajusta sozinha.' : ' Atenção: informado pelo '
                  'IP. Se o outro PC trocar de endereço, a rede para — prefira o '
                  'nome do computador.'}',
              cor: _verde,
              icone: Icons.check_circle,
            )
          else
            _faixa(
              _cfg.ligado
                  ? 'Ainda falta escolher o outro computador e salvar.'
                  : 'Rede local desligada: só a nuvem sincroniza.',
              cor: _amarelo,
              icone: Icons.info_outline,
            ),
        ],
      ),
    );
  }

  /// Resumo de uma linha do estado da rede: quantos PCs já estão prontos.
  ///
  /// O que o dono da loja precisa saber é uma coisa só — quais computadores já
  /// aceitam conexão. Com muitos PCs, contar isso no topo evita ter de ler três
  /// blocos de texto para descobrir quem falta.
  String _resumoDaRede(ResultadoBuscaRede busca) {
    final liberados = busca.pares.length;
    final semAcesso = busca.postgresSemAcesso.length;
    final faltam = busca.computadoresSemPostgres.length;
    final total = liberados + semAcesso + faltam;
    final partes = <String>['$liberados de $total já liberados'];
    if (semAcesso > 0) partes.add('$semAcesso com senha diferente');
    if (faltam > 0) partes.add('$faltam sem liberar');
    return partes.join(' • ');
  }

  List<Widget> _resultadoDaBusca() {
    final busca = _busca;
    if (busca == null) return const <Widget>[];

    final selecionado = _hostCtrl.text.trim();
    final filhos = <Widget>[];

    // O veredito vem ANTES de tudo: quantos PCs (de todos os encontrados) já
    // aceitam conexão. Vale mesmo quando nenhum foi liberado ainda.
    if (busca.pares.isNotEmpty ||
        busca.postgresSemAcesso.isNotEmpty ||
        busca.computadoresSemPostgres.isNotEmpty) {
      filhos.add(const SizedBox(height: 12));
      filhos.add(Text(
        _resumoDaRede(busca),
        style: TextStyle(
            color: busca.computadoresSemPostgres.isEmpty ? _verde : _amarelo,
            fontSize: 12,
            fontWeight: FontWeight.w600),
      ));
    }

    if (busca.pares.isNotEmpty) {
      for (final par in busca.pares) {
        // O NOME é o que fica no campo: é ele que sobrevive à troca de IP.
        final escolhido = par.nome ?? par.host;
        final detalhe = <String>[
          '✔ JÁ LIBERADO',
          if (par.nome != null && par.nome!.isNotEmpty) 'IP agora: ${par.host}',
          'banco do Êxodo',
          '${par.tabelas} tabela(s)',
          if (par.versao != null && par.versao!.isNotEmpty)
            'PostgreSQL ${par.versao}',
          if (par.empresaAberta != null && par.empresaAberta!.isNotEmpty)
            'empresa aberta: ${par.empresaAberta}',
        ].join(' • ');
        filhos.add(InkWell(
          onTap: () => setState(() {
            _hostCtrl.text = escolhido;
            _portaCtrl.text = '${par.porta}';
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  selecionado == escolhido
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selecionado == escolhido ? _verde : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(escolhido,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                      Text(
                        detalhe,
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
      }
    }

    for (final outro in busca.postgresSemAcesso) {
      filhos.add(_faixa(
        '🔒 ${outro.host}: já tem PostgreSQL na rede, mas não entrou — em geral '
        'a senha (ou o usuário) do banco é diferente entre os PCs. '
        '${outro.erro ?? 'acesso negado'}.',
        cor: Colors.orangeAccent,
        icone: Icons.lock_outline,
      ));
    }

    if (busca.computadoresSemPostgres.isNotEmpty) {
      filhos.add(_faixa(
        '⚠ AINDA FALTA LIBERAR em ${busca.computadoresSemPostgres.length} '
        'computador(es). Nesses PCs, abra o sistema e toque em "Liberar este PC '
        'na rede" NAQUELE computador (não precisa informar IP).',
        cor: _amarelo,
        icone: Icons.info_outline,
      ));
      for (final ip in busca.computadoresSemPostgres) {
        filhos.add(InkWell(
          onTap: () => setState(() => _hostCtrl.text = ip),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: _amarelo, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(ip,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                ),
                const Text('usar',
                    style: TextStyle(color: _azul, fontSize: 12)),
              ],
            ),
          ),
        ));
      }
    }

    if (busca.pares.isEmpty &&
        busca.postgresSemAcesso.isEmpty &&
        busca.computadoresSemPostgres.isEmpty) {
      filhos.add(_faixa(
        'Não achei ninguém na rede ${busca.redes.isEmpty ? '' : '(${busca.redes.join(', ')})'}. '
        'Confira se o outro PC está ligado e na mesma rede.',
        cor: Colors.orangeAccent,
        icone: Icons.wifi_off,
      ));
    }

    return filhos;
  }

  /// Diz em QUAL `.env` esta tela vai gravar, e avisa quando ela não é a que o
  /// sincronizador instalado lê.
  ///
  /// É o erro mais fácil de cometer: rodar um build de desenvolvimento grava no
  /// `.env` do PROJETO, enquanto o `SincronizadorNuvem` instalado (ao lado do
  /// `.exe`) lê outro arquivo. A tela avisa "salvo", a busca encontra o PC,
  /// analisa tudo, e a LAN não sobe em lugar nenhum — sem ninguém entender
  /// por quê. Por isso o caminho fica visível.
  Widget _avisoDoArquivoEnv() {
    final caminho = widget.caminhoDoEnv ?? EnvConfig.arquivoEnv?.path;
    if (caminho == null || caminho.isEmpty) {
      return const SizedBox.shrink();
    }
    final normal = caminho.replaceAll('\\', '/').toLowerCase();
    final emBuild = normal.contains('/build/');
    final alvo = emBuild ? Colors.orangeAccent : Colors.white70;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: alvo.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: alvo.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Esta configuração é gravada em: $caminho',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          if (emBuild) ...[
            const SizedBox(height: 6),
            const Text(
              '⚠ Isso é um build de desenvolvimento (pasta build). O '
              'SincronizadorNuvem INSTALADO lê o .env que fica ao lado do '
              'próprio programa. Se você configurar por aqui, a LAN fica só '
              'neste arquivo e o sincronizador continuará desligado. '
              'Configure pelo app instalado e use "Salvar e reiniciar".',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cartao({
    required String titulo,
    required IconData icone,
    required List<Widget> filhos,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: _azul, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...filhos,
        ],
      ),
    );
  }

  Widget _faixa(
    String texto, {
    required Color cor,
    required IconData icone,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: cor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linha(String rotulo, String valor, {required Color cor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: rotulo,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            TextSpan(
              text: valor,
              style: TextStyle(color: cor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
