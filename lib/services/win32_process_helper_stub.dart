import 'dart:async';
import 'dart:io';

/// Versão do helper Win32 usada no **Web**, onde o `dart:ffi` não existe.
///
/// Todos os recursos aqui são exclusivos do app desktop (Windows). Como no Web
/// não existe `Platform.isWindows`, nenhum fluxo chega a chamar estes métodos —
/// eles existem apenas para manter a mesma API e permitir o build web.
class Win32ProcessHelper {
  static int? startProcessHidden(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
  }) {
    throw UnsupportedError(
      'Win32ProcessHelper só está disponível no aplicativo desktop (Windows).',
    );
  }

  static Future<ProcessResult> runProcessHiddenCapture(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) {
    throw UnsupportedError(
      'Win32ProcessHelper só está disponível no aplicativo desktop (Windows).',
    );
  }
}
