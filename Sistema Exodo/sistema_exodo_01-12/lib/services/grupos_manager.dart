import 'package:flutter/foundation.dart';

class GruposManager extends ChangeNotifier {
  static final GruposManager _instance = GruposManager._internal();

  factory GruposManager() {
    return _instance;
  }

  GruposManager._internal();

  final List<String> _gruposRegistrados = [
    'Periféricos',
    'Hardware',
    'Serviços',
    'Sem Grupo',
  ];

  List<String> get gruposRegistrados => _gruposRegistrados;

  /// Adiciona um novo grupo se não existir
  void adicionarGrupo(String grupo) {
    final grupoNorm = grupo.trim();
    if (grupoNorm.isNotEmpty && !_gruposRegistrados.contains(grupoNorm)) {
      _gruposRegistrados.add(grupoNorm);
      _gruposRegistrados.sort();
      notifyListeners();
    }
  }

  /// Remove um grupo
  void removerGrupo(String grupo) {
    if (grupo != 'Sem Grupo') {
      _gruposRegistrados.remove(grupo);
      notifyListeners();
    }
  }

  /// Verifica se grupo existe
  bool existeGrupo(String grupo) {
    return _gruposRegistrados.contains(grupo);
  }

  /// Obtém sugestões de grupos
  List<String> obterSugestoes(String query) {
    if (query.isEmpty) return _gruposRegistrados;
    final queryLower = query.toLowerCase();
    return _gruposRegistrados
        .where((g) => g.toLowerCase().contains(queryLower))
        .toList();
  }
}
