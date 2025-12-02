import 'dart:convert';
import 'package:flutter/foundation.dart';
// Import condicional para Web
import 'local_storage_service_stub.dart'
    if (dart.library.html) 'local_storage_service_web_stub.dart';

/// Serviço de persistência local usando localStorage no Web e shared_preferences em outras plataformas
class LocalStorageService {
  static const String _keyClientes = 'exodo_clientes';
  static const String _keyProdutos = 'exodo_produtos';
  static const String _keyServicos = 'exodo_servicos';
  static const String _keyPedidos = 'exodo_pedidos';
  static const String _keyOrdensServico = 'exodo_ordens_servico';
  static const String _keyEntregas = 'exodo_entregas';
  static const String _keyMotoristas = 'exodo_motoristas';
  static const String _keyVendasBalcao = 'exodo_vendas_balcao';
  static const String _keyTrocasDevolucoes = 'exodo_trocas_devolucoes';
  static const String _keyEstoqueHistorico = 'exodo_estoque_historico';
  static const String _keyUltimoNumeroVenda = 'exodo_ultimo_numero_venda';
  static const String _keyCaixaAberto = 'exodo_caixa_aberto';
  static const String _keyAberturasCaixa = 'exodo_aberturas_caixa';
  static const String _keyFechamentosCaixa = 'exodo_fechamentos_caixa';
  static const String _keyNotasEntrada = 'exodo_notas_entrada';
  
  static String get keyNotasEntrada => _keyNotasEntrada;

  /// Salva uma lista de objetos como JSON no localStorage
  Future<void> salvarLista<T>(String key, List<T> lista) async {
    try {
      if (kIsWeb) {
        // Usar localStorage no Web
        final json = jsonEncode(lista.map((item) => _toMap(item)).toList());
        await _salvarWeb(key, json);
      } else {
        // Usar shared_preferences em outras plataformas
        final json = jsonEncode(lista.map((item) => _toMap(item)).toList());
        await _salvarSharedPreferences(key, json);
      }
      debugPrint('✓ Dados salvos: $key (${lista.length} itens)');
    } catch (e) {
      debugPrint('✗ Erro ao salvar $key: $e');
    }
  }

  /// Carrega uma lista de objetos do localStorage
  Future<List<Map<String, dynamic>>> carregarLista(String key) async {
    try {
      String? json;
      if (kIsWeb) {
        json = await _carregarWeb(key);
      } else {
        json = await _carregarSharedPreferences(key);
      }

      if (json == null || json.isEmpty) {
        return [];
      }

      final decoded = jsonDecode(json) as List;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('✗ Erro ao carregar $key: $e');
      return [];
    }
  }

  /// Salva o último número de venda
  Future<void> salvarUltimoNumeroVenda(int numero) async {
    try {
      if (kIsWeb) {
        await _salvarWeb(_keyUltimoNumeroVenda, numero.toString());
      } else {
        await _salvarSharedPreferences(_keyUltimoNumeroVenda, numero.toString());
      }
    } catch (e) {
      debugPrint('✗ Erro ao salvar último número de venda: $e');
    }
  }

  /// Carrega o último número de venda
  Future<int> carregarUltimoNumeroVenda() async {
    try {
      String? valor;
      if (kIsWeb) {
        valor = await _carregarWeb(_keyUltimoNumeroVenda);
      } else {
        valor = await _carregarSharedPreferences(_keyUltimoNumeroVenda);
      }
      return valor != null ? int.tryParse(valor) ?? 0 : 0;
    } catch (e) {
      debugPrint('✗ Erro ao carregar último número de venda: $e');
      return 0;
    }
  }

  /// Salva o status do caixa (aberto/fechado)
  Future<void> salvarStatusCaixaAberto(bool aberto) async {
    try {
      final valor = aberto ? '1' : '0';
      if (kIsWeb) {
        await _salvarWeb(_keyCaixaAberto, valor);
      } else {
        await _salvarSharedPreferences(_keyCaixaAberto, valor);
      }
    } catch (e) {
      debugPrint('✗ Erro ao salvar status do caixa: $e');
    }
  }

  /// Carrega o status do caixa (true = aberto, false = fechado)
  Future<bool> carregarStatusCaixaAberto() async {
    try {
      String? valor;
      if (kIsWeb) {
        valor = await _carregarWeb(_keyCaixaAberto);
      } else {
        valor = await _carregarSharedPreferences(_keyCaixaAberto);
      }
      return valor == '1';
    } catch (e) {
      debugPrint('✗ Erro ao carregar status do caixa: $e');
      return false;
    }
  }

  /// Salva um objeto genérico como JSON
  Future<void> salvar(String key, dynamic value) async {
    try {
      final json = jsonEncode(value);
      if (kIsWeb) {
        await _salvarWeb(key, json);
      } else {
        await _salvarSharedPreferences(key, json);
      }
      debugPrint('✓ Dados salvos: $key');
    } catch (e) {
      debugPrint('✗ Erro ao salvar $key: $e');
    }
  }

  /// Carrega um objeto genérico do localStorage
  Future<dynamic> carregar(String key) async {
    try {
      String? json;
      if (kIsWeb) {
        json = await _carregarWeb(key);
      } else {
        json = await _carregarSharedPreferences(key);
      }

      if (json == null || json.isEmpty) {
        return null;
      }

      return jsonDecode(json);
    } catch (e) {
      debugPrint('✗ Erro ao carregar $key: $e');
      return null;
    }
  }

  /// Remove um item do localStorage
  Future<void> remover(String key) async {
    try {
      if (kIsWeb) {
        await _removerWeb(key);
      } else {
        await _removerSharedPreferences(key);
      }
      debugPrint('✓ Item removido: $key');
    } catch (e) {
      debugPrint('✗ Erro ao remover $key: $e');
    }
  }

  /// Limpa todos os dados salvos (útil para testes/debug)
  Future<void> limparTudo() async {
    final keys = [
      _keyClientes,
      _keyProdutos,
      _keyServicos,
      _keyPedidos,
      _keyOrdensServico,
      _keyEntregas,
      _keyMotoristas,
      _keyVendasBalcao,
      _keyTrocasDevolucoes,
      _keyEstoqueHistorico,
      _keyUltimoNumeroVenda,
      _keyCaixaAberto,
      _keyAberturasCaixa,
      _keyFechamentosCaixa,
    ];

    for (final key in keys) {
      try {
        if (kIsWeb) {
          await _removerWeb(key);
        } else {
          await _removerSharedPreferences(key);
        }
      } catch (e) {
        debugPrint('✗ Erro ao remover $key: $e');
      }
    }
    debugPrint('✓ Todos os dados foram limpos');
  }

  // ============ Métodos Web (localStorage via dart:html) ============

  Future<void> _salvarWeb(String key, String value) async {
    if (kIsWeb) {
      // Usar conditional import para dart:html apenas no Web
      await _salvarWebImpl(key, value);
    }
  }

  Future<String?> _carregarWeb(String key) async {
    if (kIsWeb) {
      return await _carregarWebImpl(key);
    }
    return null;
  }

  Future<void> _removerWeb(String key) async {
    if (kIsWeb) {
      await _removerWebImpl(key);
    }
  }

  // Implementações Web usando LocalStorageWeb
  Future<void> _salvarWebImpl(String key, String value) async {
    await LocalStorageWeb.salvar(key, value);
  }

  Future<String?> _carregarWebImpl(String key) async {
    return await LocalStorageWeb.carregar(key);
  }

  Future<void> _removerWebImpl(String key) async {
    await LocalStorageWeb.remover(key);
  }

  // ============ Métodos SharedPreferences ============

  Future<void> _salvarSharedPreferences(String key, String value) async {
    // Será implementado quando necessário para outras plataformas
    // Por enquanto, apenas no Web
  }

  Future<String?> _carregarSharedPreferences(String key) async {
    // Será implementado quando necessário para outras plataformas
    // Por enquanto, apenas no Web
    return null;
  }

  Future<void> _removerSharedPreferences(String key) async {
    // Será implementado quando necessário para outras plataformas
    // Por enquanto, apenas no Web
  }

  // ============ Helpers ============

  /// Converte um objeto para Map (assumindo que tem método toMap)
  dynamic _toMap(dynamic item) {
    if (item is Map) {
      return item;
    }
    // Tentar chamar toMap() se existir
    try {
      return (item as dynamic).toMap();
    } catch (e) {
      // Se não tiver toMap, tentar converter manualmente
      debugPrint('⚠ Aviso: objeto não tem toMap(), usando toString(): $e');
      return {'_raw': item.toString()};
    }
  }

  // ============ Getters para as chaves ============

  static String get keyClientes => _keyClientes;
  static String get keyProdutos => _keyProdutos;
  static String get keyServicos => _keyServicos;
  static String get keyPedidos => _keyPedidos;
  static String get keyOrdensServico => _keyOrdensServico;
  static String get keyEntregas => _keyEntregas;
  static String get keyMotoristas => _keyMotoristas;
  static String get keyVendasBalcao => _keyVendasBalcao;
  static String get keyTrocasDevolucoes => _keyTrocasDevolucoes;
  static String get keyEstoqueHistorico => _keyEstoqueHistorico;
  static String get keyCaixaAberto => _keyCaixaAberto;
  static String get keyAberturasCaixa => _keyAberturasCaixa;
  static String get keyFechamentosCaixa => _keyFechamentosCaixa;
}

