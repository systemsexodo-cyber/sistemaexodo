import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Log persistente do aplicativo instalado.
///
/// O `flutter run` mostra `print`/`debugPrint` no terminal, mas o executável
/// Windows não tem esse terminal disponível. Este serviço grava os mesmos
/// eventos no perfil do usuário, sem depender de permissões administrativas.
class AppLogService {
  AppLogService._();

  static File? _arquivo;
  static Future<void> _fila = Future<void>.value();
  static bool _hookInstalado = false;

  static String? get caminho => _arquivo?.path;

  static Future<void> inicializar() async {
    if (kIsWeb || _arquivo != null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _arquivo = File(p.join(dir.path, 'app_runtime.log'));
      if (await _arquivo!.exists() && await _arquivo!.length() > 5 * 1024 * 1024) {
        await _arquivo!.writeAsString('');
      }
      await registrar('LOG iniciado; arquivo: ${_arquivo!.path}', nivel: 'BOOT');
    } catch (_) {
      // O log nunca pode impedir o aplicativo de abrir.
    }
  }

  static void instalarHookDebugPrint() {
    if (_hookInstalado || kIsWeb) return;
    _hookInstalado = true;
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message != null && message.isNotEmpty) {
        unawaited(registrar(message, nivel: 'DEBUG'));
      }
    };
  }

  static Future<void> registrar(String mensagem, {String nivel = 'INFO'}) {
    if (kIsWeb) return Future<void>.value();
    final gravar = _fila.then((_) => _gravar(mensagem, nivel));
    _fila = gravar.catchError((_) {});
    return gravar;
  }

  static Future<void> _gravar(String mensagem, String nivel) async {
    try {
      _arquivo ??= File(
        p.join((await getApplicationSupportDirectory()).path, 'app_runtime.log'),
      );
      final arquivo = _arquivo!;
      if (await arquivo.exists() && await arquivo.length() > 5 * 1024 * 1024) {
        await arquivo.writeAsString('');
      }
      final agora = DateTime.now().toIso8601String();
      await arquivo.writeAsString(
        '[$agora] [$nivel] $mensagem\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Falha de log não pode derrubar o aplicativo.
    }
  }
}
