import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import 'bot_perguntas_page.dart';

/// Conversa direta com o atendente virtual (sem passar pelo WhatsApp) e
/// controle de pausa. Cada resposta mostra a origem: dado do cadastro,
/// IA ou bloqueio — é assim que se percebe o que precisa ser treinado.
class BotTestePage extends StatefulWidget {
  const BotTestePage({super.key, this.textoInicial});

  /// Pergunta já escrita no campo — vem da tela "Perguntas dos clientes".
  final String? textoInicial;

  @override
  State<BotTestePage> createState() => _BotTestePageState();
}

class _MensagemBot {
  _MensagemBot({
    required this.texto,
    required this.daIA,
    this.origem,
    this.regra,
    this.ms,
    this.erro = false,
  });

  final String texto;
  final bool daIA;
  final String? origem;
  final String? regra;
  final int? ms;
  final bool erro;

  String? get rotuloOrigem {
    switch (origem) {
      case 'config':
        return 'Cadastro (sem IA)';
      case 'modelo':
        return 'IA';
      case 'fallback_preco':
        return 'Bloqueio: preço';
      case 'fallback_valor':
        return 'Bloqueio: valor na resposta';
      case 'fallback_fato':
        return 'Bloqueio: dado inventado';
      case 'erro_ollama':
        return 'IA indisponível';
      case 'vazio':
        return 'Sem resposta';
      default:
        return null;
    }
  }
}

class _BotTestePageState extends State<BotTestePage> {
  static const _prefUrl = 'bot_admin_url';
  static const _prefToken = 'bot_admin_token';
  static const _urlPadrao = 'http://127.0.0.1:8097';

  final _urlController = TextEditingController(text: _urlPadrao);
  final _tokenController = TextEditingController();
  final _textoController = TextEditingController();
  final _scrollController = ScrollController();

  final List<_MensagemBot> _mensagens = [];
  Map<String, dynamic>? _saude;
  bool _carregando = false;
  bool _enviando = false;
  bool _tokenRejeitado = false;
  /// true = o HTTP do bot respondeu (mesmo que o corpo tenha vindo ilegivel).
  bool _respondeu = false;
  String? _erroConexao;

  @override
  void initState() {
    super.initState();
    if (widget.textoInicial != null) {
      _textoController.text = widget.textoInicial!;
    }
    _carregarPreferencias();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _textoController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _carregarPreferencias() async {
    final prefs = await SharedPreferences.getInstance();
    _urlController.text = prefs.getString(_prefUrl) ?? _urlPadrao;
    _tokenController.text = prefs.getString(_prefToken) ?? '';
    if (!mounted) return;
    await _atualizarStatus();
  }

  Future<void> _salvarPreferencias() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUrl, _urlController.text.trim());
    await prefs.setString(_prefToken, _tokenController.text.trim());
  }

  String get _baseUrl {
    final url = _urlController.text.trim();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_tokenController.text.trim().isNotEmpty)
          'x-bot-token': _tokenController.text.trim(),
      };

  Future<void> _atualizarStatus() async {
    setState(() {
      _carregando = true;
      _erroConexao = null;
    });
    try {
      final resposta = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 10));
      if (resposta.statusCode != 200) {
        throw Exception('HTTP ${resposta.statusCode}');
      }
      final dados = _statusDoCorpo(utf8.decode(resposta.bodyBytes));
      if (!mounted) return;
      setState(() {
        _saude = dados;
        _respondeu = true;
        _erroConexao = dados == null
            ? 'O bot respondeu, mas o status veio num formato que o app não '
                'entendeu. Pausar e Retomar continuam funcionando.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saude = null;
        _respondeu = false;
        _erroConexao = 'Não consegui falar com o bot em $_baseUrl.\n'
            'A loja/VM está ligada e o atendimento iniciado?';
      });
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// `Infinity`/`NaN` não existem em JSON. Quando o bot estava pausado "até
  /// retomar" ele mandava `"paused_until": Infinity`, o jsonDecode do Dart
  /// recusava o corpo inteiro e a tela dizia "Bot não localizado" com o bot no
  /// ar — daí o botão Retomar ficava desabilitado e o bot não voltava nunca.
  static String _jsonTolerante(String corpo) => corpo
      .replaceAll('-Infinity', 'null')
      .replaceAll('Infinity', 'null')
      .replaceAll('NaN', 'null');

  /// Status do /health; null = corpo ilegível (bot respondeu, mas não entendi).
  Map<String, dynamic>? _statusDoCorpo(String corpo) {
    try {
      final dados = jsonDecode(_jsonTolerante(corpo));
      return dados is Map<String, dynamic> ? dados : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pausar({int minutos = 0}) async {
    await _salvarPreferencias();
    try {
      final resposta = await http
          .post(
            Uri.parse('$_baseUrl/admin/pause'),
            headers: _headers,
            body: jsonEncode({'minutes': minutos}),
          )
          .timeout(const Duration(seconds: 20));
      if (resposta.statusCode == 401) {
        _marcarTokenRejeitado();
        return;
      }
      if (resposta.statusCode != 200) {
        _avisar('Falha ao pausar (HTTP ${resposta.statusCode}).');
        return;
      }
      _avisar(minutos > 0
          ? 'Bot pausado por $minutos min.'
          : 'Bot pausado até você retomar.');
      await _atualizarStatus();
    } catch (e) {
      _avisar('Erro ao pausar: $e');
    }
  }

  Future<void> _retomar() async {
    await _salvarPreferencias();
    try {
      final resposta = await http
          .post(
            Uri.parse('$_baseUrl/admin/resume'),
            headers: _headers,
            body: '{}',
          )
          .timeout(const Duration(seconds: 20));
      if (resposta.statusCode == 401) {
        _marcarTokenRejeitado();
        return;
      }
      if (resposta.statusCode != 200) {
        _avisar('Falha ao retomar (HTTP ${resposta.statusCode}).');
        return;
      }
      _avisar('Bot respondendo novamente.');
      await _atualizarStatus();
    } catch (e) {
      _avisar('Erro ao retomar: $e');
    }
  }

  Future<void> _enviar() async {
    final texto = _textoController.text.trim();
    if (texto.isEmpty || _enviando) return;
    await _salvarPreferencias();
    setState(() {
      _mensagens.add(_MensagemBot(texto: texto, daIA: false));
      _enviando = true;
    });
    _textoController.clear();
    _rolarParaFim();
    try {
      final resposta = await http
          .post(
            Uri.parse('$_baseUrl/chat'),
            headers: _headers,
            body: jsonEncode({'text': texto}),
          )
          .timeout(const Duration(seconds: 120));
      if (resposta.statusCode == 401) {
        _marcarTokenRejeitado();
        _adicionarResposta(
          _MensagemBot(
            texto: 'O bot recusou o token, então não respondeu.',
            daIA: true,
            erro: true,
          ),
        );
        return;
      }
      if (resposta.statusCode != 200) {
        _adicionarResposta(
          _MensagemBot(
            texto: 'O bot respondeu HTTP ${resposta.statusCode}.',
            daIA: true,
            erro: true,
          ),
        );
        return;
      }
      final dados = jsonDecode(utf8.decode(resposta.bodyBytes))
          as Map<String, dynamic>;
      final reply = (dados['reply'] as String?)?.trim() ?? '';
      _adicionarResposta(
        _MensagemBot(
          texto: reply.isEmpty
              ? 'O bot ficou sem resposta para essa mensagem (IA indisponível?).'
              : reply,
          daIA: true,
          origem: dados['source'] as String?,
          regra: dados['rule'] as String?,
          ms: dados['ms'] is int ? dados['ms'] as int : null,
          erro: reply.isEmpty,
        ),
      );
      if (dados['paused'] == true) {
        _avisar('Atenção: o bot está pausado — ele não responderia no WhatsApp.');
      }
    } catch (e) {
      _adicionarResposta(
        _MensagemBot(
          texto: 'Não consegui falar com o bot: $e',
          daIA: true,
          erro: true,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _adicionarResposta(_MensagemBot mensagem) {
    if (!mounted) return;
    setState(() => _mensagens.add(mensagem));
    _rolarParaFim();
  }

  void _rolarParaFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _marcarTokenRejeitado() {
    if (!mounted) return;
    setState(() => _tokenRejeitado = true);
    _avisar(
      _tokenController.text.trim().isEmpty
          ? 'Nenhum token informado: toque em "Informar token" e cole o BOT_ADMIN_TOKEN da VM.'
          : 'Token recusado pelo bot. Confira o BOT_ADMIN_TOKEN da VM.',
    );
  }

  void _avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Conversar com o bot'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.forum_outlined),
              tooltip: 'Perguntas dos clientes',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BotPerguntasPage()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar status',
              onPressed: _atualizarStatus,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildStatusCard(),
            if (_tokenRejeitado) _buildAvisoToken(),
            Expanded(child: _buildConversa()),
            _buildEntrada(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final pausado = _saude?['paused'] == true;
    final empresa = (_saude?['empresa'] as String?) ?? '—';
    final fatos = _saude?['config_facts'] ?? 0;
    final cor = _saude == null
        ? Colors.orange
        : (pausado ? Colors.orange : Colors.green);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 12, color: cor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _saude != null
                      ? (pausado ? 'Bot pausado' : 'Bot respondendo')
                      : (_respondeu
                          ? 'Bot respondeu (status ilegível)'
                          : 'Bot não localizado'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (_carregando)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (_erroConexao != null) ...[
            const SizedBox(height: 6),
            Text(_erroConexao!,
                style: const TextStyle(fontSize: 12, color: Colors.orange)),
          ] else if (_saude != null) ...[
            const SizedBox(height: 4),
            Text(
              '$empresa · $fatos dado(s) do cadastro no bot',
              style: const TextStyle(fontSize: 12),
            ),
            if (_tokenController.text.trim().isEmpty)
              Text(
                'Sem token: só o status está sendo lido. Toque na engrenagem.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                ),
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: pausado ? null : () => _pausar(minutos: 0),
                icon: const Icon(Icons.pause, size: 18),
                label: const Text('Pausar'),
              ),
              OutlinedButton.icon(
                onPressed: pausado ? null : () => _pausar(minutos: 60),
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: const Text('Pausar 1h'),
              ),
              OutlinedButton.icon(
                // Sem status (bot antigo/ilegível) o app não sabe se está
                // pausado: Retomar fica liberado para nunca deixar o bot preso.
                onPressed: pausado || _saude == null ? _retomar : null,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Retomar'),
              ),
              IconButton(
                tooltip: 'Configuração de conexão',
                onPressed: _abrirConfigConexao,
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoToken() {
    final semToken = _tokenController.text.trim().isEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.key_off, size: 18, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              semToken
                  ? 'Falta o token para o app mandar mensagens ao bot e pausá-lo.'
                  : 'O bot recusou o token salvo. Ele mudou na VM?',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _abrirConfigConexao,
            child: const Text('Informar token'),
          ),
        ],
      ),
    );
  }

  Widget _buildConversa() {
    if (_mensagens.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Pergunte como um cliente perguntaria.\n\n'
            'A etiqueta de cada resposta mostra de onde ela veio:\n'
            '• Cadastro — veio do negocio.json (sem IA)\n'
            '• IA — texto livre do modelo\n'
            '• Bloqueio — o bot recusou um dado que não confere\n\n'
            'Nada aqui é enviado no WhatsApp.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).hintColor,
              height: 1.5,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _mensagens.length,
      itemBuilder: (context, index) {
        final m = _mensagens[index];
        final alinhamento =
            m.daIA ? CrossAxisAlignment.start : CrossAxisAlignment.end;
        final cor = m.erro
            ? Colors.red.withValues(alpha: 0.12)
            : m.daIA
                ? Theme.of(context).cardColor
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: alinhamento,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  m.texto,
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ),
              if (m.daIA && m.rotuloOrigem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4),
                  child: Text(
                    '${m.rotuloOrigem}${m.ms != null ? ' · ${m.ms} ms' : ''}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEntrada() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textoController,
                enabled: !_enviando,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _enviar(),
                decoration: const InputDecoration(
                  hintText: 'Ex.: quanto custa o banho?',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _enviando ? null : _enviar,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirConfigConexao() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conexão com o bot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Endereço',
                helperText: 'Padrão: $_urlPadrao',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Token',
                helperText: 'BOT_ADMIN_TOKEN do .env da VM',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await _salvarPreferencias();
              if (!context.mounted) return;
              Navigator.pop(context);
              setState(() => _tokenRejeitado = false);
              await _atualizarStatus();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
