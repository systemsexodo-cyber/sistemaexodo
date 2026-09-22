import 'dart:io';
import 'package:path/path.dart' as p;
import 'win32_process_helper.dart';

/// Utilitário para executar processos no Windows sem abrir janela CMD.
///
/// No Windows, Process.run() cria uma janela CMD visível toda vez que é chamado.
/// Esta função usa a API Win32 CreateProcessW com CREATE_NO_WINDOW para
/// garantir que nenhum console seja exibido.
Future<ProcessResult> runProcessHidden(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration? timeout,
}) async {
  if (!Platform.isWindows) {
    // No Linux/Mac, Process.run não cria janela visível
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  // No Windows: CreateProcessW + CREATE_NO_WINDOW, com stdout/stderr
  // redirecionados para arquivos temporários (sem janela CMD e com saída real).
  return Win32ProcessHelper.runProcessHiddenCapture(
    executable,
    arguments: arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    timeout: timeout,
  );
}

/// Procura um binário do PostgreSQL (psql, pg_dump, pg_restore, createdb...).
///
/// Procura nesta ordem:
///  1. PATH do sistema;
///  2. o PostgreSQL embutido que acompanha o app (`postgresql/bin` e
///     `postgresql/pgsql/bin`), relativo ao diretório atual e à pasta do
///     executável;
///  3. o próprio diretório do executável.
///
/// Devolve null quando não encontrar em nenhum lugar.
Future<String?> findPostgresBinary(String nome) async {
  final nomeExe = Platform.isWindows ? '$nome.exe' : nome;

  // 1) PATH do sistema
  try {
    final result = await runProcessHidden(
      Platform.isWindows ? 'where' : 'which',
      [nome],
    );
    if (result.exitCode == 0) {
      final linhas = result.stdout.toString().trim().split(RegExp(r'\r?\n'));
      if (linhas.isNotEmpty && linhas.first.trim().isNotEmpty) {
        return linhas.first.trim();
      }
    }
  } catch (_) {}

  // 2) e 3) instalação que acompanha o app
  final candidatos = <String>[];
  void adicionarAoRedorDe(String base) {
    candidatos.add(p.join(base, 'postgresql', 'bin', nomeExe));
    candidatos.add(p.join(base, 'postgresql', 'pgsql', 'bin', nomeExe));
  }

  adicionarAoRedorDe(Directory.current.path);
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    adicionarAoRedorDe(exeDir);
    candidatos.add(p.join(exeDir, nomeExe));
  } catch (_) {}

  for (final caminho in candidatos) {
    try {
      if (File(caminho).existsSync()) return caminho;
    } catch (_) {}
  }

  return null;
}

/// Executa um processo sem esperar resultado e sem criar janela CMD.
/// Útil para comandos como taskkill onde não precisamos do output.
Future<void> runProcessDetached(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  if (!Platform.isWindows) {
    await Process.run(executable, arguments, workingDirectory: workingDirectory);
    return;
  }

  // Usar Win32 API para iniciar sem janela de console
  final pid = Win32ProcessHelper.startProcessHidden(
    executable,
    arguments: arguments,
    workingDirectory: workingDirectory,
  );

  if (pid == null) {
    // Fallback: Process.start com detached (sem janela CMD)
    // NOTA: não usar ProcessStartMode.normal pois cria janela CMD visível
    await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
      workingDirectory: workingDirectory,
    );
  }
}
