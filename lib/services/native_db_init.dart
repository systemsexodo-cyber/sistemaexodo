import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class NativeDbInit {
  static void initialize() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      print('>>> [APLICATIVO] SQLite FFI inicializado para Desktop');
    }
  }
}
