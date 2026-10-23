import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  bool get bancoLocalFalhou => false;

  Future<void> salvarLista(String chave, List<Map<String, dynamic>> lista, {bool isSync = false}) async {
    // Stub - Web
  }

  Future<List<Map<String, dynamic>>> carregarLista(String chave) async {
    return [];
  }

  Future<void> salvarConfig(String chave, dynamic valor, {bool lancarSeFalhar = false}) async {
    // Stub - Web
  }

  Future<dynamic> carregarConfig(String chave, {bool lancarSeFalhar = false}) async {
    return null;
  }

  Future<void> removerConfig(String chave) async {
    // Stub - Web
  }
}
