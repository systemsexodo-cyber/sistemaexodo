import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ============================================================
// Structs Win32 (nível superior — Dart não permite aninhamento)
// ============================================================

/// STARTUPINFOW — parâmetros de inicialização do processo
/// Campos após cbFlags até hStdError são ignorados por CreateProcess;
/// apenas cb (tamanho) é essencial.
final class StartupInfoW extends Struct {
  @Uint32()
  external int cb;
  external Pointer<Utf16> lpReserved;
  external Pointer<Utf16> lpDesktop;
  external Pointer<Utf16> lpTitle;
  @Int32()
  external int dwX;
  @Int32()
  external int dwY;
  @Int32()
  external int dwXSize;
  @Int32()
  external int dwYSize;
  @Int32()
  external int dwXCountChars;
  @Int32()
  external int dwYCountChars;
  @Uint32()
  external int dwFillAttribute;
  @Uint32()
  external int dwFlags;
  @Uint16()
  external int wShowWindow;
  @Uint16()
  external int cbReserved2;
  external Pointer<Uint8> lpReserved2;
  @IntPtr()
  external int hStdInput;
  @IntPtr()
  external int hStdOutput;
  @IntPtr()
  external int hStdError;
}

/// PROCESS_INFORMATION — handles e IDs do processo criado
final class ProcessInformation extends Struct {
  @IntPtr()
  external int hProcess;
  @IntPtr()
  external int hThread;
  @Uint32()
  external int dwProcessId;
  @Uint32()
  external int dwThreadId;
}

// ============================================================
// Typedefs das funções Win32 (nível superior)
// ============================================================

// ATENÇÃO: o `Bool` do dart:ffi é o `bool` do C (1 byte), NÃO o `BOOL` do
// Win32 (int de 4 bytes). Usar `Bool` aqui desalinha a pilha e o Windows
// responde ERROR_INVALID_PARAMETER (87) em toda chamada.
typedef CreateProcessWNative = Int32 Function(
  Pointer<Utf16> lpApplicationName,
  Pointer<Utf16> lpCommandLine,
  Pointer<Void> lpProcessAttributes,
  Pointer<Void> lpThreadAttributes,
  Int32 bInheritHandles,
  Uint32 dwCreationFlags,
  Pointer<Void> lpEnvironment,
  Pointer<Utf16> lpCurrentDirectory,
  Pointer<StartupInfoW> lpStartupInfo,
  Pointer<ProcessInformation> lpProcessInformation,
);

typedef CreateProcessWDart = int Function(
  Pointer<Utf16> lpApplicationName,
  Pointer<Utf16> lpCommandLine,
  Pointer<Void> lpProcessAttributes,
  Pointer<Void> lpThreadAttributes,
  int bInheritHandles,
  int dwCreationFlags,
  Pointer<Void> lpEnvironment,
  Pointer<Utf16> lpCurrentDirectory,
  Pointer<StartupInfoW> lpStartupInfo,
  Pointer<ProcessInformation> lpProcessInformation,
);

typedef CloseHandleNative = Int32 Function(IntPtr hObject);
typedef CloseHandleDart = int Function(int hObject);

/// SECURITY_ATTRIBUTES — usado para criar handles herdáveis pelo filho
final class SecurityAttributes extends Struct {
  @Uint32()
  external int nLength;
  external Pointer<Void> lpSecurityDescriptor;
  @Int32()
  external int bInheritHandle;
}

typedef CreateFileWNative = IntPtr Function(
  Pointer<Utf16> lpFileName,
  Uint32 dwDesiredAccess,
  Uint32 dwShareMode,
  Pointer<SecurityAttributes> lpSecurityAttributes,
  Uint32 dwCreationDisposition,
  Uint32 dwFlagsAndAttributes,
  IntPtr hTemplateFile,
);

typedef CreateFileWDart = int Function(
  Pointer<Utf16> lpFileName,
  int dwDesiredAccess,
  int dwShareMode,
  Pointer<SecurityAttributes> lpSecurityAttributes,
  int dwCreationDisposition,
  int dwFlagsAndAttributes,
  int hTemplateFile,
);

typedef WaitForSingleObjectNative = Uint32 Function(
    IntPtr hHandle, Uint32 dwMilliseconds);
typedef WaitForSingleObjectDart = int Function(int hHandle, int dwMilliseconds);

typedef GetExitCodeProcessNative = Int32 Function(
    IntPtr hProcess, Pointer<Uint32> lpExitCode);
typedef GetExitCodeProcessDart = int Function(
    int hProcess, Pointer<Uint32> lpExitCode);

typedef TerminateProcessNative = Int32 Function(
    IntPtr hProcess, Uint32 uExitCode);
typedef TerminateProcessDart = int Function(int hProcess, int uExitCode);

typedef GetLastErrorNative = Uint32 Function();
typedef GetLastErrorDart = int Function();

// ============================================================
// Win32ProcessHelper
// ============================================================

/// Helper para iniciar processos no Windows sem criar janela de console.
///
/// Usa a API Win32 CreateProcessW com a flag CREATE_NO_WINDOW (0x08000000)
/// para evitar que executáveis de console (como o Bridge) abram uma janela
/// CMD/system32 visível.
class Win32ProcessHelper {
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');

  /// Flag CREATE_NO_WINDOW — impede a criação de janela de console.
  static const int _createNoWindow = 0x08000000;

  /// Flag CREATE_UNICODE_ENVIRONMENT — obrigatória quando o bloco de
  /// ambiente passado em lpEnvironment é Unicode (senão o Windows devolve
  /// ERROR_INVALID_PARAMETER/87).
  static const int _createUnicodeEnvironment = 0x00000400;

  static final _createProcessW = _kernel32
      .lookupFunction<CreateProcessWNative, CreateProcessWDart>(
          'CreateProcessW');

  static final _closeHandleNative =
      _kernel32.lookupFunction<CloseHandleNative, CloseHandleDart>(
          'CloseHandle');

  static final _createFileW =
      _kernel32.lookupFunction<CreateFileWNative, CreateFileWDart>(
          'CreateFileW');

  static final _waitForSingleObject =
      _kernel32.lookupFunction<WaitForSingleObjectNative,
          WaitForSingleObjectDart>('WaitForSingleObject');

  static final _getExitCodeProcess =
      _kernel32.lookupFunction<GetExitCodeProcessNative, GetExitCodeProcessDart>(
          'GetExitCodeProcess');

  static final _terminateProcess =
      _kernel32.lookupFunction<TerminateProcessNative, TerminateProcessDart>(
          'TerminateProcess');

  static final _getLastError =
      _kernel32.lookupFunction<GetLastErrorNative, GetLastErrorDart>(
          'GetLastError');

  // Constantes usadas na execução com saída redirecionada
  static const int _startfUseStdHandles = 0x00000100;
  static const int _genericRead = 0x80000000;
  static const int _genericWrite = 0x40000000;
  static const int _fileShareRead = 0x00000001;
  static const int _fileShareWrite = 0x00000002;
  static const int _createAlways = 2;
  static const int _openExisting = 3;
  static const int _fileAttributeNormal = 0x00000080;
  static const int _waitObject0 = 0x00000000;
  static const int _invalidHandle = -1;

  /// Inicia um processo no Windows sem criar janela de console.
  ///
  /// [executable] — caminho completo do executável.
  /// [arguments]  — argumentos de linha de comando.
  /// [workingDirectory] — diretório de trabalho (opcional).
  ///
  /// Retorna o PID do processo ou `null` se falhar.
  static int? startProcessHidden(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
  }) {
    final caminho = resolverExecutavel(executable);
    final argsStr = arguments.isEmpty
        ? ''
        : ' ${arguments.map(quoteArgument).join(' ')}';
    final commandLine = '"$caminho"$argsStr';
    return _startProcessNative(caminho, commandLine,
        workingDirectory: workingDirectory);
  }

  /// Monta a linha de argumentos respeitando as regras de escape do Windows
  /// (aspas só quando necessário).
  static String montarArgumentos(List<String> arguments) =>
      arguments.map(quoteArgument).join(' ');

  /// Coloca aspas em um argumento apenas quando ele precisa.
  static String quoteArgument(String argumento) {
    if (argumento.isEmpty) return '""';
    if (!argumento.contains(RegExp(r'[\s"]'))) return argumento;
    final sb = StringBuffer('"');
    var barras = 0;
    for (final ch in argumento.codeUnits) {
      if (ch == 0x5C) {
        barras++;
        sb.writeCharCode(ch);
        continue;
      }
      if (ch == 0x22) {
        sb.write('\\' * (barras * 2 + 1));
        sb.writeCharCode(ch);
        barras = 0;
        continue;
      }
      barras = 0;
      sb.writeCharCode(ch);
    }
    sb.write('\\' * barras);
    sb.write('"');
    return sb.toString();
  }

  /// Resolve o caminho de um executável.
  ///
  /// O CreateProcessW **não** localiza um nome simples ("taskkill") como o
  /// `Process.run` faz quando ele não é um caminho completo — por isso
  /// procuramos na pasta do Windows e nas pastas do PATH.
  static String resolverExecutavel(String executable) {
    if (!Platform.isWindows) return executable;
    if (executable.contains('\\') || executable.contains('/')) {
      return executable;
    }

    final pastas = <String>[
      r'C:\Windows\System32',
      r'C:\Windows',
      r'C:\Windows\System32\WindowsPowerShell\v1.0',
    ];
    final pathEnv = Platform.environment['PATH'] ?? '';
    for (final pasta in pathEnv.split(';')) {
      final limpa = pasta.trim().replaceAll('"', '');
      if (limpa.isNotEmpty) pastas.add(limpa);
    }

    final nomes = <String>[
      executable,
      if (!executable.toLowerCase().endsWith('.exe')) '$executable.exe',
      if (!executable.toLowerCase().endsWith('.cmd')) '$executable.cmd',
      if (!executable.toLowerCase().endsWith('.bat')) '$executable.bat',
    ];

    for (final nome in nomes) {
      for (final pasta in pastas) {
        final candidato = '$pasta\\$nome';
        try {
          if (File(candidato).existsSync()) return candidato;
        } catch (_) {}
      }
    }
    return executable;
  }

  /// Executa um processo no Windows **sem janela de console**, capturando
  /// stdout/stderr.
  ///
  /// Substitui `Process.run` em apps GUI (Flutter desktop): como o app roda sem
  /// console, qualquer executável de console (psql, pg_dump, where, tasklist…)
  /// iniciado sem CREATE_NO_WINDOW ganha uma janela CMD visível.
  ///
  /// [timeout] encerra o processo e lança [TimeoutException] se estourar.
  static Future<ProcessResult> runProcessHiddenCapture(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    // Fora do Windows, Process.run não abre janela.
    if (!Platform.isWindows) {
      final future = Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
      return timeout == null ? future : future.timeout(timeout);
    }

    var executavel = executable;
    final tempDir = await Directory.systemTemp.createTemp('exodo_proc_');
    final outPath = '${tempDir.path}\\stdout.txt';
    final errPath = '${tempDir.path}\\stderr.txt';

    final startupInfo = calloc<StartupInfoW>();
    final processInfo = calloc<ProcessInformation>();
    var outHandle = _invalidHandle;
    var errHandle = _invalidHandle;
    var inHandle = _invalidHandle;
    Pointer<Utf16> exePtr = nullptr;
    Pointer<Utf16> cmdPtr = nullptr;
    Pointer<Utf16> dirPtr = nullptr;
    Pointer<Utf16> envPtr = nullptr;

    try {
      outHandle = _abrirHandle(outPath, _genericWrite, _fileShareRead, true);
      errHandle = _abrirHandle(errPath, _genericWrite, _fileShareRead, true);
      inHandle = _abrirHandle(
          r'\\.\NUL', _genericRead, _fileShareRead | _fileShareWrite, false);

      if (outHandle == _invalidHandle ||
          errHandle == _invalidHandle ||
          inHandle == _invalidHandle) {
        throw ProcessException(executable, arguments,
            'Não foi possível redirecionar a saída do processo', 0);
      }

      executavel = resolverExecutavel(executable);
      exePtr = executavel.toNativeUtf16();
      final argsStr = arguments.isEmpty
          ? ''
          : ' ${montarArgumentos(arguments)}';
      cmdPtr = '"$executavel"$argsStr'.toNativeUtf16();
      if (workingDirectory != null && workingDirectory.isNotEmpty) {
        dirPtr = workingDirectory.toNativeUtf16();
      }
      if (environment != null && environment.isNotEmpty) {
        envPtr = _montarBlocoAmbiente(environment);
      }

      startupInfo.ref.cb = sizeOf<StartupInfoW>();
      startupInfo.ref.dwFlags = _startfUseStdHandles;
      startupInfo.ref.hStdInput = inHandle;
      startupInfo.ref.hStdOutput = outHandle;
      startupInfo.ref.hStdError = errHandle;

      final ok = _createProcessW(
        exePtr,                    // lpApplicationName
        cmdPtr,                    // lpCommandLine
        nullptr,                   // lpProcessAttributes
        nullptr,                   // lpThreadAttributes
        1,                         // bInheritHandles (BOOL de 4 bytes)
        _createNoWindow | _createUnicodeEnvironment, // ← sem janela de CMD
        envPtr == nullptr ? nullptr : envPtr.cast<Void>(),
        dirPtr,                    // lpCurrentDirectory
        startupInfo,               // lpStartupInfo
        processInfo,               // lpProcessInformation
      );

      if (ok == 0) {
        final codigo = _getLastError();
        throw ProcessException(executable, arguments,
            'CreateProcessW falhou (código $codigo)', codigo);
      }

      final pid = processInfo.ref.dwProcessId;
      final cronometro = Stopwatch()..start();
      var estourou = false;

      // Espera assíncrona (não bloqueia a UI) — o handle do processo continua
      // sinalizado depois que ele termina, então dá para sondar.
      while (_waitForSingleObject(processInfo.ref.hProcess, 0) != _waitObject0) {
        if (timeout != null && cronometro.elapsed > timeout) {
          estourou = true;
          _terminateProcess(processInfo.ref.hProcess, 1);
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      var exitCode = -1;
      final exitCodePtr = calloc<Uint32>();
      try {
        if (_getExitCodeProcess(processInfo.ref.hProcess, exitCodePtr) != 0) {
          exitCode = exitCodePtr.value;
        }
      } finally {
        calloc.free(exitCodePtr);
      }

      _closeHandleNative(processInfo.ref.hProcess);
      _closeHandleNative(processInfo.ref.hThread);

      if (estourou) {
        throw TimeoutException(
            'O processo $executable excedeu o tempo limite', timeout);
      }

      final saida = await _lerTexto(outPath);
      final erro = await _lerTexto(errPath);
      return ProcessResult(pid, exitCode, saida, erro);
    } finally {
      if (outHandle != _invalidHandle) _closeHandleNative(outHandle);
      if (errHandle != _invalidHandle) _closeHandleNative(errHandle);
      if (inHandle != _invalidHandle) _closeHandleNative(inHandle);
      if (exePtr != nullptr) calloc.free(exePtr);
      if (cmdPtr != nullptr) calloc.free(cmdPtr);
      if (dirPtr != nullptr) calloc.free(dirPtr);
      if (envPtr != nullptr) calloc.free(envPtr);
      calloc.free(startupInfo);
      calloc.free(processInfo);
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Abre um handle de arquivo herdável (usado como stdin/stdout/stderr).
  static int _abrirHandle(
    String caminho,
    int acesso,
    int compartilhamento,
    bool criarSempre,
  ) {
    final pathPtr = caminho.toNativeUtf16();
    final sa = calloc<SecurityAttributes>();
    sa.ref.nLength = sizeOf<SecurityAttributes>();
    sa.ref.bInheritHandle = 1;
    sa.ref.lpSecurityDescriptor = nullptr;
    try {
      return _createFileW(
        pathPtr,
        acesso,
        compartilhamento,
        sa,
        criarSempre ? _createAlways : _openExisting,
        _fileAttributeNormal,
        0,
      );
    } finally {
      calloc.free(pathPtr);
      calloc.free(sa);
    }
  }

  /// Monta o bloco de variáveis de ambiente (UTF-16, terminado em \0\0).
  static Pointer<Utf16> _montarBlocoAmbiente(Map<String, String> environment) {
    final buffer = StringBuffer();
    // As variáveis cujo nome começa com '=' (ex.: "=C:") precisam vir primeiro.
    final chaves = environment.keys.toList()
      ..sort((a, b) {
        final aEspecial = a.startsWith('=');
        final bEspecial = b.startsWith('=');
        if (aEspecial != bEspecial) return aEspecial ? -1 : 1;
        return a.toUpperCase().compareTo(b.toUpperCase());
      });
    for (final chave in chaves) {
      buffer.write('$chave=${environment[chave]}');
      buffer.writeCharCode(0);
    }
    buffer.writeCharCode(0);
    return buffer.toString().toNativeUtf16();
  }

  static Future<String> _lerTexto(String caminho) async {
    try {
      final bytes = await File(caminho).readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  static int? _startProcessNative(
    String executable,
    String commandLine, {
    String? workingDirectory,
  }) {
    final exePtr = executable.toNativeUtf16();
    final cmdPtr = commandLine.toNativeUtf16();
    final dirPtr = workingDirectory?.toNativeUtf16() ?? nullptr;

    final startupInfo = calloc<StartupInfoW>();
    startupInfo.ref.cb = sizeOf<StartupInfoW>();

    final processInfo = calloc<ProcessInformation>();

    try {
      final result = _createProcessW(
        exePtr,           // lpApplicationName
        cmdPtr,           // lpCommandLine
        nullptr,          // lpProcessAttributes
        nullptr,          // lpThreadAttributes
        0,                // bInheritHandles (BOOL do Win32, 4 bytes)
        _createNoWindow,  // dwCreationFlags ← CREATE_NO_WINDOW
        nullptr,          // lpEnvironment (herda do pai)
        dirPtr,           // lpCurrentDirectory
        startupInfo,      // lpStartupInfo
        processInfo,      // lpProcessInformation
      );

      if (result != 0) {
        final pid = processInfo.ref.dwProcessId;
        _closeHandleNative(processInfo.ref.hProcess);
        _closeHandleNative(processInfo.ref.hThread);
        return pid;
      } else {
        return null;
      }
    } finally {
      calloc.free(exePtr);
      calloc.free(cmdPtr);
      if (dirPtr != nullptr) calloc.free(dirPtr);
      calloc.free(startupInfo);
      calloc.free(processInfo);
    }
  }
}
