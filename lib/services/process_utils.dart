import 'dart:io';
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

  // No Windows, usar Win32 API para iniciar sem janela de console
  final pid = Win32ProcessHelper.startProcessHidden(
    executable,
    arguments: arguments,
    workingDirectory: workingDirectory,
  );

  if (pid != null) {
    // Processo iniciado com sucesso via Win32, aguardar conclusão
    // Como não temos stdout/stderr, retornar resultado vazio
    return ProcessResult(pid, 0, '', '');
  }

  // Fallback: Process.start com inherit (conecta stdio ao processo pai)
  // NOTA: detached NÃO conecta stdio, causando 'Bad state: stdio is not connected'
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.normal,
    workingDirectory: workingDirectory,
    environment: environment,
  );

  // Ler stdout e stderr para obter o resultado
  final stdoutBytes = await process.stdout.fold<List<int>>(
    <int>[],
    (previous, element) => previous..addAll(element),
  );
  final stderrBytes = await process.stderr.fold<List<int>>(
    <int>[],
    (previous, element) => previous..addAll(element),
  );

  final exitCode = await process.exitCode;

  return ProcessResult(
    process.pid,
    exitCode,
    String.fromCharCodes(stdoutBytes),
    String.fromCharCodes(stderrBytes),
  );
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
