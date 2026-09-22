// Fachada do helper de processos Win32.
//
// O código real (FFI + CreateProcessW) fica em `win32_process_helper_io.dart`
// e só é compilado onde o `dart:ffi` existe (Windows/Linux/macOS). No Web o
// `dart:ffi` não existe, então o build escolhe o stub — sem isso o build web
// falhava com "Dart library 'dart:ffi' is not available on this platform".
export 'win32_process_helper_stub.dart'
    if (dart.library.ffi) 'win32_process_helper_io.dart';
