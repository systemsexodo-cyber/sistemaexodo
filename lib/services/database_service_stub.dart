import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Future<void> salvarLista(String chave, List<Map<String, dynamic>> lista, {bool isSync = false}) async {
    // Stub - Não faz nada no Web
  }

  Future<List<Map<String, dynamic>>> carregarLista(String chave) async {
    // Stub - Retorna vazio no Web
    return [];
  }
}
