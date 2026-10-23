import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';

import '../services/config_servidor_mobile.dart';
import '../services/database_service.dart';
import '../services/env_config.dart';

/// Tela do CELULAR para informar em qual computador está o banco da loja.
///
/// Existe porque o APK é o mesmo para todas as lojas: o IP do PC não pode vir
/// fixo no build. O que for salvo aqui passa a valer no lugar do `.env`
/// empacotado (ver `EnvConfig.aplicarOverrides`).
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

  late final TextEditingController _host;
  late final TextEditingController _porta;
  late final TextEditingController _banco;
  late final TextEditingController _usuario;
  late final TextEditingController _senha;

  bool _mostrarSenha = false;
  bool _testando = false;
  bool _salvando = false;
  String? _status;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: EnvConfig.dbHost);
    _porta = TextEditingController(text: '${EnvConfig.dbPort}');
    _banco = TextEditingController(text: EnvConfig.dbName);
    _usuario = TextEditingController(text: EnvConfig.dbUser);
    _senha = TextEditingController(text: EnvConfig.dbPassword);
  }

  @override
  void dispose() {
    _host.dispose();
    _porta.dispose();
    _banco.dispose();
    _usuario.dispose();
    _senha.dispose();
    super.dispose();
  }

  int get _portaNum =>
      int.tryParse(_porta.text.trim()) ??
      int.tryParse(_porta.text.trim().replaceAll(RegExp(r'[^0-9]'), '')) ??
      5432;

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

  Future<void> _salvar() async {
    final host = _host.text.trim();
    if (host.isEmpty) {
      setState(() {
        _ok = false;
        _status = 'Informe o IP do computador da loja.';
      });
      return;
    }

    setState(() {
      _salvando = true;
      _status = null;
    });

    try {
      final valores = await ConfigServidorMobile.salvar(
        host: host,
        porta: _portaNum,
        banco: _banco.text.trim(),
        usuario: _usuario.text.trim(),
        senha: _senha.text,
      );
      EnvConfig.aplicarOverrides(valores);
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
          'O celular volta a usar o endereço que veio dentro do APK. '
          'Se esse endereço não for o do PC desta loja, o sistema não conecta.',
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
    EnvConfig.limparOverrides();
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
              const SizedBox(height: 22),
              if (_status != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_ok ? _verde : _vermelho).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (_ok ? _verde : _vermelho).withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _ok ? Icons.check_circle_outline : Icons.error_outline,
                        color: _ok ? _verde : _vermelho,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _status!,
                          style: TextStyle(
                            color: _ok ? _verde : _vermelho,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              OutlinedButton.icon(
                onPressed: (_testando || _salvando) ? null : _testar,
                icon: _testando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_testando ? 'Testando...' : 'Testar conexão'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _azul,
                  side: BorderSide(color: _azul.withOpacity(0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: (_testando || _salvando) ? null : _salvar,
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
                onPressed: (_testando || _salvando) ? null : _restaurarPadrao,
                child: const Text(
                  'Restaurar endereço padrão do APK',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String rotulo,
    String? dica,
    TextInputType? teclado,
    bool senha = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: teclado,
      obscureText: senha && !_mostrarSenha,
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
                  _mostrarSenha ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () => setState(() => _mostrarSenha = !_mostrarSenha),
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
