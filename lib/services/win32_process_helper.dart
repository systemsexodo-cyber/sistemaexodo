import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Helper para iniciar processos no Windows sem criar janela de console.
///
/// Usa a API Win32 CreateProcessW com a flag CREATE_NO_WINDOW (0x08000000)
/// para evitar que executáveis de console (como o Bridge) abram uma janela
/// CMD/system32 visível.
class Win32ProcessHelper {
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');

  /// Flag CREATE_NO_WINDOW - impede a criação de janela de console
  static const int _createNoWindow = 0x08000000;

  // ---- Structs Win32 ----

  /// STARTUPINFOW - parâmetros de inicialização do processo
  @ffi.Packed(4)
  final class _StartupInfoW extends Struct {
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

  /// PROCESS_INFORMATION - informações do processo criado
  final class _ProcessInformation extends Struct {
    @IntPtr()
    external int hProcess;
    @IntPtr()
    external int hThread;
    @Uint32()
    external int dwProcessId;
    @Uint32()
    external int dwThreadId;
  }

  // ---- Typedefs das funções Win32 ----

  typedef _CreateProcessWNative = Bool Function(
    Pointer<Utf16> lpApplicationName,
    Pointer<Utf16> lpCommandLine,
    Pointer<Void> lpProcessAttributes,
    Pointer<Void> lpThreadAttributes,
    Bool bInheritHandles,
    Uint32 dwCreationFlags,
    Pointer<Void> lpEnvironment,
    Pointer<Utf16> lpCurrentDirectory,
    Pointer<_StartupInfoW> lpStartupInfo,
    Pointer<_ProcessInformation> lpProcessInformation,
  );

  typedef _CreateProcessDart = bool Function(
    Pointer<Utf16> lpApplicationName,
    Pointer<Utf16> lpCommandLine,
    Pointer<Void> lpProcessAttributes,
    Pointer<Void> lpThreadAttributes,
    bool bInheritHandles,
    int dwCreationFlags,
    Pointer<Void> lpEnvironment,
    Pointer<Utf16> lpCurrentDirectory,
    Pointer<_StartupInfoW> lpStartupInfo,
    Pointer<_ProcessInformation> lpProcessInformation,
  );

  static final _createProcessW = _kernel32
      .lookupFunction<_CreateProcessWNative, _CreateProcessDart>('CreateProcessW');

  /// Fecha um handle do Windows
  static void _closeHandle(int handle) {
    final closeHandleNative = _kernel32.lookupFunction<
        Bool Function(IntPtr hObject),
        bool Function(int hObject)>('CloseHandle');
    closeHandleNative(handle);
  }

  /// Inicia um processo no Windows sem criar janela de console.
  ///
  /// [executable] - caminho completo do executável
  /// [arguments] - argumentos de linha de comando
  /// [workingDirectory] - diretório de trabalho (opcional)
  ///
  /// Retorna o PID do processo ou null se falhar.
  static int? startProcessHidden(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
  }) {
    // Construir linha de comando: "executable" arg1 arg2 ...
    final argsStr = arguments.isEmpty
        ? ''
        : ' ${arguments.map((a) => '"$a"').join(' ')}';
    final commandLine = '"$executable"$argsStr';

    return _startProcessNative(
      executable,
      commandLine,
      workingDirectory: workingDirectory,
    );
  }

  static int? _startProcessNative(
    String executable,
    String commandLine, {
    String? workingDirectory,
  }) {
    final exePtr = executable.toNativeUtf16();
    final cmdPtr = commandLine.toNativeUtf16();
    final dirPtr = workingDirectory?.toNativeUtf16() ?? nullptr;

    final startupInfo = calloc<_StartupInfoW>();
    startupInfo.ref.cb = sizeOf<_StartupInfoW>();

    final processInfo = calloc<_ProcessInformation>();

    try {
      final result = _createProcessW(
        exePtr,           // lpApplicationName
        cmdPtr,           // lpCommandLine
        nullptr,          // lpProcessAttributes
        nullptr,          // lpThreadAttributes
        false,            // bInheritHandles
        _createNoWindow,  // dwCreationFlags ← CREATE_NO_WINDOW
        nullptr,          // lpEnvironment (herda do pai)
        dirPtr,           // lpCurrentDirectory
        startupInfo,      // lpStartupInfo
        processInfo,      // lpProcessInformation
      );

      if (result) {
        final pid = processInfo.ref.dwProcessId;
        // Fechar handles para evitar memory leak
        _closeHandle(processInfo.ref.hProcess);
        _closeHandle(processInfo.ref.hThread);
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
