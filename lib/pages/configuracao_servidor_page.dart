import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';

import '../services/config_servidor_mobile.dart';
import '../services/database_service.dart';
import '../services/env_config.dart';

/// Tela do CELULAR para informar onde está o banco da loja.
///
/// Existe porque o APK é o mesmo para todas as lojas: o IP do PC não pode vir
/// fixo no build. O que for salvo aqui passa a valer no lugar do `.env`
/// empacotado (ver `EnvConfig.aplicarOverrides`).
///
/// São DOIS endereços:
///   1. o PC da loja, na rede local (rápido, é o usado no dia a dia);
///   2. a NUVEM, usada quando o celular está fora da loja (dados móveis).
///      Ela vem do Funil do Tailscale em TCP 10000, com TLS — por isso o teste
///      da nuvem usa `directTls`, igual ao `DatabaseService`.
class ConfiguracaoServidorPage extends StatefulWidget {
  const ConfiguracaoServidorPage({super.key});

  @override
  State<ConfiguracaoServidorPage> createState() =>
      _ConfiguracaoServidorPageState();
}

class _ConfiguracaoServidorPageState extends State<ConfiguracaoServidorPage> {
  static const Color _fundo = Color(0xFF0F172A);
  static const Color _card = Color(0xFF1E293B);
  static const Color _azul = Color(0xFF38BDF8);
  static const Color _verde = Color(0xFF4CAF50);
  static const Color _vermelho = Color(0xFFEF5350);

  /// Endereço oficial da nuvem Neon na AWS.
  static const String _nuvemHostSugerido = 'ep-cold-math-b5sateo2-pooler.c-7.us-east-2.aws.neon.tech';
  static const int _nuvemPortaSugerida = 5432;
  static const String _nuvemBancoSugerido = 'neondb';
  static const String _nuvemUsuarioSugerido = 'neondb_owner';
  static const String _nuvemSenhaSugerida = 'npg_P3KS8dTXcZrW';

  bool _detectando = false;

  late final TextEditingController _host;
  late final TextEditingController _porta;
  late final TextEditingController _banco;
  late final TextEditingController _usuario;
  late final TextEditingController _senha;

  late final TextEditingController _nuvemHost;
  late final TextEditingController _nuvemPorta;
  late final TextEditingController _nuvemBanco;
  late final TextEditingController _nuvemUsuario;
  late final TextEditingController _nuvemSenha;

  bool _mostrarSenha = false;
  bool _mostrarSenhaNuvem = false;
  bool _nuvemSsl = true;

  /// Modo de conexão escolhido: automático, somente LAN ou somente nuvem.
  String _modo = ConfigServidorMobile.modoAuto;
  bool _testando = false;
  bool _testandoNuvem = false;
  bool _salvando = false;
  String? _status;
  bool _ok = false;
  String? _statusNuvem;
  bool _okNuvem = false;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: EnvConfig.dbHost);
    _porta = TextEditingController(text: '${EnvConfig.dbPort}');
    _banco = TextEditingController(text: EnvConfig.dbName);
    _usuario = TextEditingController(text: EnvConfig.dbUser);
    _senha = TextEditingController(text: EnvConfig.dbPassword);

    final cloudHost = EnvConfig.dbCloudHost;
    _nuvemHost = TextEditingController(
      text: cloudHost.isEmpty ? _nuvemHostSugerido : cloudHost,
    );
    _nuvemPorta = TextEditingController(
      text: '${cloudHost.isEmpty ? _nuvemPortaSugerida : EnvConfig.dbCloudPort}',
    );
    _nuvemBanco = TextEditingController(text: EnvConfig.dbCloudName);
    _nuvemUsuario = TextEditingController(text: EnvConfig.dbCloudUser);
    _nuvemSenha = TextEditingController(
      text: cloudHost.isEmpty ? '' : EnvConfig.dbCloudPassword,
    );
    _nuvemSsl = EnvConfig.dbCloudSsl;
    _carregarModo();
  }

  @override
  void dispose() {
    _host.dispose();
    _porta.dispose();
    _banco.dispose();
    _usuario.dispose();
    _senha.dispose();
    _nuvemHost.dispose();
    _nuvemPorta.dispose();
    _nuvemBanco.dispose();
    _nuvemUsuario.dispose();
    _nuvemSenha.dispose();
    super.dispose();
  }

  /// Lê o modo de conexão salvo no aparelho.
  Future<void> _carregarModo() async {
    final modo = await ConfigServidorMobile.carregarModo();
    if (!mounted) return;
    setState(() => _modo = modo);
  }

  int _paraPorta(TextEditingController c, int padrao) =>
      int.tryParse(c.text.trim()) ??
      int.tryParse(c.text.trim().replaceAll(RegExp(r'[^0-9]'), '')) ??
      padrao;

  int get _portaNum => _paraPorta(_porta, 5432);
  int get _nuvemPortaNum => _paraPorta(_nuvemPorta, _nuvemPortaSugerida);

  String _limparErro(Object e) {
    var texto = e.toString();
    texto = texto.replaceAll('Exception: ', '').trim();
    if (texto.length > 260) texto = '${texto.substring(0, 260)}...';
    return texto;
  }

  Future<void> _testar() async {
    final host = _host.text.trim();
    if (host.isEmpty) {
      setState(() {
        _ok = false;
        _status = 'Informe o IP do computador da loja.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _testando = true;
      _ok = false;
      _status = 'Conectando em $host:$_portaNum...';
    });

    Connection? conn;
    try {
      conn = await Connection.open(
        Endpoint(
          host: host,
          port: _portaNum,
          database: _banco.text.trim(),
          username: _usuario.text.trim(),
          password: _senha.text,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      ).timeout(const Duration(seconds: 12));

      final resultado = await conn.execute('SELECT current_database()');
      final banco = resultado.isNotEmpty
          ? '${resultado.first.first}'
          : _banco.text.trim();

      if (!mounted) return;
      setState(() {
        _ok = true;
        _status = 'Conectou no banco "$banco". Pode salvar.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _status = 'Não conectou: ${_limparErro(e)}';
      });
    } finally {
      try {
        await conn?.close();
      } catch (_) {}
      if (mounted) setState(() => _testando = false);
    }
  }

  /// Testa a nuvem com TLS (é o mesmo caminho que o app usa fora da loja).
  Future<void> _testarNuvem() async {
    final host = _nuvemHost.text.trim();
    if (host.isEmpty) {
      setState(() {
        _okNuvem = false;
        _statusNuvem =
            'Informe o endereço da nuvem (ou deixe em branco para não usar).';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _testandoNuvem = true;
      _okNuvem = false;
      _statusNuvem = 'Conectando na nuvem $host:$_nuvemPortaNum...';
    });

    Connection? conn;
    try {
      conn = await Connection.open(
        Endpoint(
          host: host,
          port: _nuvemPortaNum,
          database: _nuvemBanco.text.trim(),
          username: _nuvemUsuario.text.trim(),
          password: _nuvemSenha.text,
        ),
        settings: ConnectionSettings(
          sslMode: _nuvemSsl ? SslMode.require : SslMode.disable,
          directTls: _nuvemSsl,
        ),
      ).timeout(const Duration(seconds: 20));

      final resultado = await conn.execute('SELECT current_database()');
      final banco = resultado.isNotEmpty
          ? '${resultado.first.first}'
          : _nuvemBanco.text.trim();

      if (!mounted) return;
      setState(() {
        _okNuvem = true;
        _statusNuvem = 'Nuvem respondeu (banco "$banco"). Pode salvar.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _okNuvem = false;
        _statusNuvem = 'Nuvem não conectou: ${_limparErro(e)}';
      });
    } finally {
      try {
        await conn?.close();
      } catch (_) {}
      if (mounted) setState(() => _testandoNuvem = false);
    }
  }

  void _preencherNuvemOficial() {
    setState(() {
      _nuvemHost.text = _nuvemHostSugerido;
      _nuvemPorta.text = '$_nuvemPortaSugerida';
      _nuvemBanco.text = _nuvemBancoSugerido;
      _nuvemUsuario.text = _nuvemUsuarioSugerido;
      _nuvemSenha.text = _nuvemSenhaSugerida;
      _nuvemSsl = true;
      _statusNuvem = 'Dados oficiais do Neon preenchidos. Clique em "Testar nuvem".';
      _okNuvem = false;
    });
  }

  Future<void> _detectarCaixaNaRede() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _detectando = true;
      _status = 'Escaneando rede Wi-Fi para localizar o computador do Caixa...';
      _ok = false;
    });

    // Lista de candidatos prioritários: IP atual, IPs clássicos da subrede
    final candidatos = <String>{
      '192.168.0.102',
      '192.168.0.117',
      '192.168.0.100',
      '192.168.0.105',
      '192.168.1.102',
      '192.168.1.100',
      '100.108.25.60',
      _host.text.trim(),
    }..removeWhere((ip) => ip.isEmpty);

    String? encontrado;
    for (final ip in candidatos) {
      try {
        final conn = await Connection.open(
          Endpoint(
            host: ip,
            port: _portaNum,
            database: _banco.text.trim(),
            username: _usuario.text.trim(),
            password: _senha.text,
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        ).timeout(const Duration(milliseconds: 1200));

        final res = await conn.execute('SELECT current_database()');
        await conn.close();
        if (res.isNotEmpty) {
          encontrado = ip;
          break;
        }
      } catch (_) {
        // Tenta o próximo candidato
      }
    }

    if (!mounted) return;
    setState(() {
      _detectando = false;
      if (encontrado != null) {
        _host.text = encontrado;
        _ok = true;
        _status = '✅ Caixa localizado em $encontrado! Conexão verificada.';
      } else {
        _ok = false;
        _status = 'Caixa não encontrado automaticamente. Verifique se o celular está no mesmo Wi-Fi do computador da loja.';
      }
    });
  }

  Future<void> _salvar() async {
    final host = _host.text.trim();
    final nuvemHost = _nuvemHost.text.trim();
    if (_modo == ConfigServidorMobile.modoNuvem && nuvemHost.isEmpty) {
      setState(() {
        _ok = false;
        _status =
            'O modo "Somente nuvem" precisa do endereço da nuvem. Informe e '
            'teste a nuvem antes de salvar.';
      });
      return;
    }
    if (_modo == ConfigServidorMobile.modoLan && host.isEmpty) {
      setState(() {
        _ok = false;
        _status = 'O modo "Somente LAN" precisa do IP do computador da loja.';
      });
      return;
    }
    if (host.isEmpty && nuvemHost.isEmpty) {
      setState(() {
        _ok = false;
        _status = 'Informe o IP do computador da loja ou o endereço da nuvem.';
      });
      return;
    }

    setState(() {
      _salvando = true;
      _status = null;
    });

    try {
      final valores = <String, String>{};
      if (host.isNotEmpty) {
        valores.addAll(
          await ConfigServidorMobile.salvar(
            host: host,
            porta: _portaNum,
            banco: _banco.text.trim(),
            usuario: _usuario.text.trim(),
            senha: _senha.text,
          ),
        );
      }
      valores.addAll(
        await ConfigServidorMobile.salvarNuvem(
          host: nuvemHost,
          porta: _nuvemPortaNum,
          banco: _nuvemBanco.text.trim(),
          usuario: _nuvemUsuario.text.trim(),
          senha: _nuvemSenha.text,
          ssl: _nuvemSsl,
        ),
      );
      EnvConfig.aplicarOverrides(valores);
      await ConfigServidorMobile.salvarModo(_modo);
      EnvConfig.definirModoConexao(_modo);
      DatabaseService().resetarConexao();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _status = 'Não foi possível salvar: ${_limparErro(e)}';
      });
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _restaurarPadrao() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Restaurar padrão?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'O celular volta a usar os endereços que vieram dentro do APK '
          '(PC e nuvem). Se eles não servirem para esta loja, o sistema não '
          'conecta.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restaurar', style: TextStyle(color: _vermelho)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    await ConfigServidorMobile.limpar();
    await ConfigServidorMobile.limparNuvem();
    EnvConfig.limparOverrides();
    EnvConfig.definirModoConexao(EnvConfig.modoAuto);
    DatabaseService().resetarConexao();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fundo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Configurar servidor'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _azul.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _azul.withOpacity(0.3)),
                ),
                child: const Text(
                  'Informe o IP do computador que roda o Sistema Êxodo nesta '
                  'loja. O celular precisa estar na MESMA rede Wi-Fi desse '
                  'computador (ou usar Tailscale).\n\n'
                  'Exemplo: 192.168.0.107',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
                ),
              ),
              const SizedBox(height: 20),
              _tituloSecao('Modo de conexão'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _opcaoModo(
                      valor: ConfigServidorMobile.modoAuto,
                      titulo: 'Automático',
                      descricao:
                          'Tenta o computador da loja e, se ele não '
                          'responder, usa a nuvem.',
                    ),
                    _opcaoModo(
                      valor: ConfigServidorMobile.modoLan,
                      titulo: 'Somente LAN (Wi-Fi da loja)',
                      descricao:
                          'Fala só com o computador da loja. Mais rápido '
                          'dentro da loja.',
                    ),
                    _opcaoModo(
                      valor: ConfigServidorMobile.modoNuvem,
                      titulo: 'Somente nuvem (4G)',
                      descricao:
                          'Fala só com a nuvem, sem esperar pelo computador. '
                          'Use fora da loja.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _tituloSecao('Computador da loja (Wi-Fi da loja)'),
              const SizedBox(height: 12),
              _campo(
                controller: _host,
                rotulo: 'IP do computador',
                dica: '192.168.0.107',
                teclado: TextInputType.text,
              ),
              const SizedBox(height: 14),
              _campo(
                controller: _porta,
                rotulo: 'Porta',
                dica: '5432',
                teclado: TextInputType.number,
              ),
              const SizedBox(height: 14),
              _campo(
                controller: _banco,
                rotulo: 'Banco de dados',
                dica: 'exodo_db',
              ),
              const SizedBox(height: 14),
              _campo(
                controller: _usuario,
                rotulo: 'Usuário',
                dica: 'exodo_user',
              ),
              const SizedBox(height: 14),
              _campo(
                controller: _senha,
                rotulo: 'Senha',
                dica: '••••••••',
                senha: true,
              ),
              const SizedBox(height: 14),
              if (_status != null) ...[
                _avisoStatus(_status!, _ok),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_detectando || _testando || _salvando)
                          ? null
                          : _detectarCaixaNaRede,
                      icon: _detectando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent),
                            )
                          : const Icon(Icons.search),
                      label: Text(
                        _detectando ? 'Localizando...' : 'Localizar Caixa Wi-Fi',
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orangeAccent,
                        side: BorderSide(color: Colors.orangeAccent.withOpacity(0.6)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_testando || _salvando) ? null : _testar,
                      icon: _testando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      label: Text(_testando ? 'Testando...' : 'Testar conexão', overflow: TextOverflow.ellipsis),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _azul,
                        side: BorderSide(color: _azul.withOpacity(0.6)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _tituloSecao('Nuvem (fora da loja / 4G)'),
                  TextButton.icon(
                    onPressed: _preencherNuvemOficial,
                    icon: const Icon(Icons.cloud_download, size: 16, color: Colors.tealAccent),
                    label: const Text('Carregar Nuvem Neon', style: TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Usada só quando o PC da loja não responde (dados móveis). '
                'Deixe o endereço em branco para desligar.',
                style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              _campo(
                controller: _nuvemHost,
                rotulo: 'Endereço da nuvem',
                dica: _nuvemHostSugerido,
                teclado: TextInputType.url,
              ),
              const SizedBox(height: 14),
              _campo(
                controller: _nuvemPorta,
                rotulo: 'Porta da nuvem',
                dica: '$_nuvemPortaSugerida',
                teclado: TextInputType.number,
              ),
              const SizedBox(height: 14),
              _campo(
                controller: _nuvemBanco,
                rotulo: 'Banco da nuvem',
                dica: 'postgres',
              ),
              const SizedBox(height: 14),
              _campo(
                controller: _nuvemUsuario,
                rotulo: 'Usuário da nuvem',
                dica: 'postgres',
              ),
              const SizedBox(height: 14),
              _campo(
                controller: _nuvemSenha,
                rotulo: 'Senha da nuvem',
                dica: '••••••••',
                senha: true,
                nuvem: true,
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _nuvemSsl,
                onChanged: (v) => setState(() => _nuvemSsl = v),
                title: const Text(
                  'Conexão segura (TLS)',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                subtitle: const Text(
                  'O Funil do Tailscale usa TLS. Só desligue se a nuvem for '
                  'um PostgreSQL local sem TLS.',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
                activeColor: _azul,
              ),
              const SizedBox(height: 14),
              if (_statusNuvem != null) ...[
                _avisoStatus(_statusNuvem!, _okNuvem),
                const SizedBox(height: 14),
              ],
              OutlinedButton.icon(
                onPressed:
                    (_testandoNuvem || _salvando) ? null : _testarNuvem,
                icon: _testandoNuvem
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_outlined),
                label: Text(
                  _testandoNuvem ? 'Testando nuvem...' : 'Testar nuvem',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _azul,
                  side: BorderSide(color: _azul.withOpacity(0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: (_testando || _testandoNuvem || _salvando)
                    ? null
                    : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_salvando ? 'Salvando...' : 'Salvar e usar'),
                style: FilledButton.styleFrom(
                  backgroundColor: _azul,
                  foregroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: (_testando || _testandoNuvem || _salvando)
                    ? null
                    : _restaurarPadrao,
                child: const Text(
                  'Restaurar endereços padrão do APK',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _opcaoModo({
    required String valor,
    required String titulo,
    required String descricao,
  }) {
    final selecionado = _modo == valor;
    return InkWell(
      onTap: () => setState(() => _modo = valor),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selecionado ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selecionado ? _azul : Colors.white24,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      color: selecionado ? Colors.white : Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descricao,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tituloSecao(String texto) {
    return Text(
      texto.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _avisoStatus(String texto, bool ok) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? _verde : _vermelho).withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (ok ? _verde : _vermelho).withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            color: ok ? _verde : _vermelho,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: ok ? _verde : _vermelho,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String rotulo,
    String? dica,
    TextInputType? teclado,
    bool senha = false,
    bool nuvem = false,
  }) {
    final visivel = nuvem ? _mostrarSenhaNuvem : _mostrarSenha;
    return TextField(
      controller: controller,
      keyboardType: teclado,
      obscureText: senha && !visivel,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: rotulo,
        hintText: dica,
        labelStyle: const TextStyle(color: Colors.white60),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: _card,
        suffixIcon: senha
            ? IconButton(
                icon: Icon(
                  visivel ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () => setState(() {
                  if (nuvem) {
                    _mostrarSenhaNuvem = !_mostrarSenhaNuvem;
                  } else {
                    _mostrarSenha = !_mostrarSenha;
                  }
                }),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _azul, width: 1.4),
        ),
      ),
    );
  }
}
