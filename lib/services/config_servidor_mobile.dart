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
  }

}
