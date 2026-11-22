import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Endereço do banco (PC da loja) configurado NO CELULAR.
///
/// No PC a configuração fica no `.env` do disco e é o agente/sincronizador que
/// cuida dela. No Android não existe `.env` gravável: o app lê o `.env`
/// empacotado no APK, que traz um IP fixo de fábrica. Para o MESMO APK servir
/// em qualquer loja, a tela "Configurar servidor" grava o IP/porta/usuário/senha
/// aqui (SharedPreferences) e esses valores passam a ter prioridade.
class ConfigServidorMobile {
  ConfigServidorMobile._();

  static const String _chaveHost = 'exodo_db_host';
  static const String _chavePorta = 'exodo_db_porta';
  static const String _chaveBanco = 'exodo_db_banco';
  static const String _chaveUsuario = 'exodo_db_usuario';
  static const String _chaveSenha = 'exodo_db_senha';

  /// Só faz sentido no celular (no PC quem manda é o `.env` do disco).
  static bool get aplicavel {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Lê o que foi salvo. Retorna vazio quando o celular nunca foi configurado
  /// (aí o app usa o `.env` empacotado, como antes).
  static Future<Map<String, String>> carregar() async {
    if (!aplicavel) return <String, String>{};
    try {
      final sp = await SharedPreferences.getInstance();
      final host = (sp.getString(_chaveHost) ?? '').trim();
      if (host.isEmpty) return <String, String>{};

      final porta = (sp.getString(_chavePorta) ?? '').trim();
      final banco = (sp.getString(_chaveBanco) ?? '').trim();
      final usuario = (sp.getString(_chaveUsuario) ?? '').trim();
      final senha = sp.getString(_chaveSenha) ?? '';

      return <String, String>{
        'DB_HOST': host,
        if (porta.isNotEmpty) 'DB_PORT': porta,
        if (banco.isNotEmpty) 'DB_NAME': banco,
        if (usuario.isNotEmpty) 'DB_USER': usuario,
        if (senha.isNotEmpty) 'DB_PASSWORD': senha,
      };
    } catch (e) {
      debugPrint('>>> [ConfigServidor] Erro ao ler configuração: $e');
      return <String, String>{};
    }
  }

  /// Grava a configuração e devolve o mapa no formato do `.env`.
  static Future<Map<String, String>> salvar({
    required String host,
    required int porta,
    required String banco,
    required String usuario,
    required String senha,
  }) async {
    final valores = <String, String>{
      'DB_HOST': host.trim(),
      'DB_PORT': '$porta',
      'DB_NAME': banco.trim(),
      'DB_USER': usuario.trim(),
      'DB_PASSWORD': senha,
    };
    if (!aplicavel) return valores;

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_chaveHost, valores['DB_HOST']!);
    await sp.setString(_chavePorta, valores['DB_PORT']!);
    await sp.setString(_chaveBanco, valores['DB_NAME']!);
    await sp.setString(_chaveUsuario, valores['DB_USER']!);
    await sp.setString(_chaveSenha, valores['DB_PASSWORD']!);
    return valores;
  }

  /// Volta a usar o que veio empacotado no APK.
  static Future<void> limpar() async {
    if (!aplicavel) return;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_chaveHost);
    await sp.remove(_chavePorta);
    await sp.remove(_chaveBanco);
    await sp.remove(_chaveUsuario);
    await sp.remove(_chaveSenha);
    await sp.remove(_chaveModo);
    await sp.remove(_chaveUltimoHost);
    await sp.remove(_chaveUltimoPorta);
  }

  // ── NUVEM (quando o celular está fora da loja) ─────────────────────────────
  //
  // O mesmo APK pode apontar para o PostgreSQL público da nuvem (o Funil do
  // Tailscale publica em TCP 10000 com TLS). Como o endereço do PC, estes
  // valores são digitados no celular e têm prioridade sobre o `app.env`
  // empacotado — é o que evita gerar outro APK por loja.
  static const String _chaveNuvemHost = 'exodo_cloud_host';
  static const String _chaveNuvemPorta = 'exodo_cloud_porta';
  static const String _chaveNuvemBanco = 'exodo_cloud_banco';
  static const String _chaveNuvemUsuario = 'exodo_cloud_usuario';
  static const String _chaveNuvemSenha = 'exodo_cloud_senha';
  static const String _chaveNuvemSsl = 'exodo_cloud_ssl';

  /// Lê a nuvem salva no aparelho. Vazio quando nunca foi configurada (aí vale
  /// o que veio no `app.env` do APK).
  static Future<Map<String, String>> carregarNuvem() async {
    if (!aplicavel) return <String, String>{};
    try {
      final sp = await SharedPreferences.getInstance();
      final host = (sp.getString(_chaveNuvemHost) ?? '').trim();
      if (host.isEmpty) return <String, String>{};

      final porta = (sp.getString(_chaveNuvemPorta) ?? '').trim();
      final banco = (sp.getString(_chaveNuvemBanco) ?? '').trim();
      final usuario = (sp.getString(_chaveNuvemUsuario) ?? '').trim();
      final senha = sp.getString(_chaveNuvemSenha) ?? '';
      final ssl = (sp.getString(_chaveNuvemSsl) ?? '').trim();

      return <String, String>{
        'DB_CLOUD_HOST': host,
        if (porta.isNotEmpty) 'DB_CLOUD_PORT': porta,
        if (banco.isNotEmpty) 'DB_CLOUD_NAME': banco,
        if (usuario.isNotEmpty) 'DB_CLOUD_USER': usuario,
        if (senha.isNotEmpty) 'DB_CLOUD_PASSWORD': senha,
        if (ssl.isNotEmpty) 'DB_CLOUD_SSL': ssl,
      };
    } catch (e) {
      debugPrint('>>> [ConfigServidor] Erro ao ler a nuvem: $e');
      return <String, String>{};
    }
  }

  /// Grava a nuvem. Host vazio desliga o fallback de nuvem no aparelho.
  static Future<Map<String, String>> salvarNuvem({
    required String host,
    required int porta,
    required String banco,
    required String usuario,
    required String senha,
    bool ssl = true,
  }) async {
    final h = host.trim();
    if (!aplicavel) return <String, String>{'DB_CLOUD_HOST': h};

    final sp = await SharedPreferences.getInstance();
    if (h.isEmpty) {
      await limparNuvem();
      return <String, String>{'DB_CLOUD_HOST': ''};
    }

    await sp.setString(_chaveNuvemHost, h);
    await sp.setString(_chaveNuvemPorta, '$porta');
    await sp.setString(_chaveNuvemBanco, banco.trim());
    await sp.setString(_chaveNuvemUsuario, usuario.trim());
    await sp.setString(_chaveNuvemSenha, senha);
    await sp.setString(_chaveNuvemSsl, ssl ? 'true' : 'false');

    return <String, String>{
      'DB_CLOUD_HOST': h,
      'DB_CLOUD_PORT': '$porta',
      'DB_CLOUD_NAME': banco.trim(),
      'DB_CLOUD_USER': usuario.trim(),
      'DB_CLOUD_PASSWORD': senha,
      'DB_CLOUD_SSL': ssl ? 'true' : 'false',
    };
  }

  /// Apaga a nuvem salva no aparelho.
  static Future<void> limparNuvem() async {
    if (!aplicavel) return;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_chaveNuvemHost);
    await sp.remove(_chaveNuvemPorta);
    await sp.remove(_chaveNuvemBanco);
    await sp.remove(_chaveNuvemUsuario);
    await sp.remove(_chaveNuvemSenha);
    await sp.remove(_chaveNuvemSsl);
  }

  // ── MODO DE CONEXÃO (LAN / nuvem / automático) ───────────────────────────
  //
  // Dentro da loja o celular deve falar SÓ com o PC (LAN): assim não perde
  // segundos tentando a nuvem a cada abertura. Fora da loja, o contrário.
  // Em "automático" o app tenta o PC e, se ele não responder, usa a nuvem.
  static const String modoAuto = 'auto';
  static const String modoLan = 'lan';
  static const String modoNuvem = 'nuvem';

  static const String _chaveModo = 'exodo_modo_conexao';

  /// Modo salvo no aparelho (`auto`, `lan` ou `nuvem`).
  static Future<String> carregarModo() async {
    if (!aplicavel) return modoAuto;
    try {
      final sp = await SharedPreferences.getInstance();
      return _modoValido(sp.getString(_chaveModo) ?? modoAuto);
    } catch (e) {
      debugPrint('>>> [ConfigServidor] Erro ao ler o modo de conexão: $e');
      return modoAuto;
    }
  }

  /// Grava o modo de conexão escolhido na tela "Configurar servidor".
  static Future<void> salvarModo(String modo) async {
    if (!aplicavel) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_chaveModo, _modoValido(modo));
    } catch (e) {
      debugPrint('>>> [ConfigServidor] Erro ao salvar o modo de conexão: $e');
    }
  }

  static String _modoValido(String modo) {
    final m = modo.trim().toLowerCase();
    if (m == modoLan) return modoLan;
    if (m == modoNuvem) return modoNuvem;
    return modoAuto;
  }

  // ── ÚLTIMO ENDEREÇO QUE CONECTOU ─────────────────────────────────────────
  //
  // Guardado para o app abrir já no destino certo (PC ou nuvem) em vez de
  // repetir o ciclo de tentativas a cada abertura.
  static const String _chaveUltimoHost = 'exodo_ultimo_host';
  static const String _chaveUltimoPorta = 'exodo_ultimo_porta';

  static Future<(String, int)?> carregarUltimoDestino() async {
    if (!aplicavel) return null;
    try {
      final sp = await SharedPreferences.getInstance();
      final host = (sp.getString(_chaveUltimoHost) ?? '').trim();
      if (host.isEmpty) return null;
      final porta =
          int.tryParse((sp.getString(_chaveUltimoPorta) ?? '').trim()) ?? 5432;
      return (host, porta);
    } catch (e) {
      debugPrint('>>> [ConfigServidor] Erro ao ler o último endereço: $e');
      return null;
    }
  }

  static Future<void> salvarUltimoDestino(String host, int porta) async {
    if (!aplicavel) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_chaveUltimoHost, host);
      await sp.setString(_chaveUltimoPorta, '$porta');
    } catch (_) {}
  }
}
