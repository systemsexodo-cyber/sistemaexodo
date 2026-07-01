import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'database_service_stub.dart'
    if (dart.library.io) 'database_service.dart';
// Import condicional para Web (Hive)
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
  static const String _keyAgendamentosServico = 'exodo_agendamentos_servico';
  static const String _keyFuncionarios = 'exodo_funcionarios';
  static const String _keyTaxasEntrega = 'exodo_taxas_entrega';
  static const String _keyContasPagar = 'exodo_contas_pagar';
  static const String _keyNFCes = 'exodo_nfces';
  static const String _keyMesasComandas = 'exodo_mesas_comandas';
  static const String _keyLinksVendedores = 'exodo_links_vendedores';
  static const String _keyComissoesVendedores = 'exodo_comissoes_vendedores';
  static const String _keySangrias = 'exodo_sangrias';
  static const String _keySuprimentos = 'exodo_suprimentos';
  static const String _keyRomaneios = 'exodo_romaneios';
  
  static String get keyNotasEntrada => _keyNotasEntrada;
  static String get keyLinksVendedores => _keyLinksVendedores;
  static String get keyComissoesVendedores => _keyComissoesVendedores;
  static String get keyAgendamentosServico => _keyAgendamentosServico;
  static String get keyMesasComandas => _keyMesasComandas;
  static String get keySangrias => _keySangrias;
  static String get keySuprimentos => _keySuprimentos;

  Future<void> salvarLista<T>(String key, List<T> lista, {bool isSync = false}) async {
    try {
      if (kIsWeb) {
        // Usar localStorage no Web via HIVE
        final json = jsonEncode(lista.map((item) => _toMap(item)).toList());
        await _salvarWeb(key, json);
        debugPrint('✓ Dados salvos (Web/Hive): $key (${lista.length} itens)');
      } else {
        // Usar PostgreSQL em Desktop/Mobile para performance (6k+ itens)
        final data = lista.map((item) => _toMap(item) as Map<String, dynamic>).toList();
        
        // Chamada direta ao DatabaseService que agora tem lógica específica por tabela
        await DatabaseService().salvarLista(key, data, isSync: isSync);
        debugPrint('✓ Dados salvos (Local/PostgreSQL): $key (${lista.length} itens)');
        
        // Cópia em shared_preferences APENAS para chaves críticas pequenas (configurações)
        if (lista.length < 100 && !key.contains('produtos') && !key.contains('vendas')) {
          final json = jsonEncode(data);
          await _salvarSharedPreferences(key, json);
        }
      }
    } catch (e) {
      debugPrint('✗ Erro ao salvar $key: $e');
    }
  }

  /// Carrega uma lista de objetos do local
  Future<List<Map<String, dynamic>>> carregarLista(String key) async {
    try {
      if (kIsWeb) {
        final json = await _carregarWeb(key);
        if (json == null || json.isEmpty) return [];
        final decoded = jsonDecode(json) as List;
        return decoded.cast<Map<String, dynamic>>();
      } else {
        // Tentar PostgreSQL primeiro (Novo padrão Nativo)
        final dados = await DatabaseService().carregarLista(key);
        if (dados.isNotEmpty) return dados;
        
        // Fallback para shared_preferences (Migração)
        final json = await _carregarSharedPreferences(key);
        if (json == null || json.isEmpty) return [];
        final decoded = jsonDecode(json) as List;
        return decoded.cast<Map<String, dynamic>>();
      }
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
      _keySangrias,
      _keySuprimentos,
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

  /// Verifica se a sessão atual é ativa (survive F5 no Web)
  bool isSessaoAtiva() {
    if (kIsWeb) return LocalStorageWeb.isSessaoAtiva();
    // No Desktop (Windows), a sessão persiste entre reinicializações do app.
    // O logout só ocorre se o usuário clicar explicitamente em Sair.
    return true; 
  }

  // ============ Métodos SharedPreferences ============

  Future<void> _salvarSharedPreferences(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<String?> _carregarSharedPreferences(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> _removerSharedPreferences(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
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
  static String get keyFuncionarios => _keyFuncionarios;
  static String get keyTaxasEntrega => _keyTaxasEntrega;
  static String get keyContasPagar => _keyContasPagar;
  static String get keyNFCes => _keyNFCes;
  static String get keySangriasField => _keySangrias;
  static String get keySuprimentosField => _keySuprimentos;
  static String get keyRomaneios => _keyRomaneios;

  /// Exporta todos os dados locais para um arquivo JSON (Backup)
  Future<String?> exportarBackupJSON() async {
    try {
      final chaves = [
        _keyClientes, _keyProdutos, _keyServicos, _keyPedidos,
        _keyOrdensServico, _keyEntregas, _keyVendasBalcao, _keyAberturasCaixa,
        _keyFechamentosCaixa, _keyNotasEntrada, _keyAgendamentosServico,
        _keyFuncionarios, _keyTaxasEntrega, _keyContasPagar, _keyNFCes
      ];

      final Map<String, dynamic> backup = {};
      for (final chave in chaves) {
        backup[chave] = await carregarLista(chave);
      }

      final jsonString = jsonEncode(backup);
      
      if (!kIsWeb) {
        // Obter diretório apenas em plataformas nativas (Windows/Mobile)
        final directory = await getApplicationDocumentsDirectory();
        final file = File(join(directory.path, 'exodo_backup_${DateTime.now().millisecondsSinceEpoch}.json'));
        await file.writeAsString(jsonString);
        return file.path;
      }
      return 'backup_web_json';
    } catch (e) {
      debugPrint('✗ Erro ao gerar backup JSON: $e');
      return null;
    }
  }
}

