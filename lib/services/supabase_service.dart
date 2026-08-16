import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/servico.dart';
import '../models/pedido.dart';
import '../models/ordem_servico.dart';
import '../models/entrega.dart';
import '../models/venda_balcao.dart';
import '../models/troca_devolucao.dart';
import '../models/estoque_historico.dart';
import '../models/lote_produto.dart';
import '../models/caixa.dart';
import 'package:sistema_exodo_novo/models/motorista.dart';
import '../models/empresa.dart';
import '../models/usuario.dart';
import '../models/agendamento_servico.dart';
import '../models/nota_entrada.dart';
import '../models/funcionario.dart';
import '../models/taxa_entrega.dart';
import '../models/conta_pagar.dart';
import '../models/nfce.dart';
import '../models/mesa_comanda.dart';
import '../models/link_vendedor.dart';
import '../models/comissao_vendedor.dart';
import 'package:sistema_exodo_novo/models/romaneio.dart';
import '../supabase_config.dart';

/// Serviço para sincronizar todos os dados com Supabase (PostgreSQL)
class SupabaseService {
  SupabaseService._(); // Construtor privado para singleton
  
  static final SupabaseService instance = SupabaseService._();
  // late final: so acessa Supabase.instance.client QUANDO FOR USADO, nao no
  // construtor. Se o Supabase ainda nao inicializou (ex: maquina nova sem
  // internet - timeout no boot), construir DataService/AuthService lancava
  // excecao aqui e o app NAO ABRIA. Agora o acesso e adiado para quando os
  // metodos sao realmente chamados (e todos ja tratam isAvailable/erro).
  late final SupabaseClient _client = Supabase.instance.client;

  SupabaseClient get client => _client;

  /// Verifica se o Supabase está disponível (inicializado)
  static bool get isAvailable {
    try {
      // Verificar se o Supabase foi inicializado (tem acesso via anon key)
      final client = Supabase.instance.client;
      // Se conseguimos acessar o client, Supabase está disponível
      // mesmo sem usuário autenticado (anon key permite acesso)
      return client != null;
    } catch (e) {
      return false;
    }
  }

  /// Alias de instância para isAvailable
  bool get connected => isAvailable;

  /// Inicializa o Supabase
  static Future<void> initialize() async {
    try {
      if (SupabaseConfig.url == 'YOUR_SUPABASE_URL') {
        debugPrint('>>> [Supabase] ⚠️ Supabase URL não configurada.');
        return;
      }
      
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
        debug: kDebugMode,
      );
      // Verificar conectividade real
      try {
        final response = await Supabase.instance.client
            .from('empresas')
            .select('id')
            .limit(1)
            .timeout(const Duration(seconds: 5));
        debugPrint('>>> [Supabase] ✅ Conectividade verificada: ${response.length} empresas acessíveis');
      } catch (e) {
        debugPrint('>>> [Supabase] ⚠️ Erro na verificação de conectividade: $e');
        debugPrint('>>> [Supabase] ℹ️ Isso pode ser normal se não houver empresas ou problema de CORS');
      }
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao inicializar: $e');
    }
  }
  

  
  // Nomes das tabelas (PostgreSQL)
  static const String tableEmpresas = 'empresas';
  static const String tableUsuarios = 'usuarios';
  static const String tableClientes = 'clientes';
  static const String tableProdutos = 'produtos';
  static const String tableServicos = 'servicos';
  static const String tablePedidos = 'pedidos';
  static const String tableOrdensServico = 'ordens_servico';
  static const String tableEntregas = 'entregas';
  static const String tableVendasBalcao = 'vendas_balcao';
  static const String tableTrocasDevolucoes = 'trocas_devolucoes';
  static const String tableEstoqueHistorico = 'estoque_historico';
  static const String tableLotesProdutos = 'lotes_produto';
  static const String tableAberturasCaixa = 'aberturas_caixa';
  static const String tableFechamentosCaixa = 'fechamentos_caixa';
  static const String tableMotoristas = 'motoristas';
  static const String tableAgendamentosServico = 'agendamentos_servico';
  static const String tableNotasEntrada = 'notas_entrada';
  static const String tableFuncionarios = 'funcionarios';
  static const String tableTaxasEntrega = 'taxas_entrega';
  static const String tableContasPagar = 'contas_pagar';
  static const String tableNFCes = 'nfces';
  static const String tableNFEs = 'nfes';
  static const String tableRomaneios = 'romaneios';

  static const String tableSangrias = 'sangrias_caixa';
  static const String tableSuprimentos = 'suprimentos_caixa';
  static const String tableMesasComandas = 'mesas_comandas';
  static const String tableLinksVendedores = 'links_vendedores';
  static const String tableComissoesVendedores = 'comissoes_vendedores';
  
  /// Obtém dados filtrados por empresa_id
  SupabaseQueryBuilder _from(String table) {
    return _client.from(table);
  }

  // ============ MÉTODOS DE SINCRONIZAÇÃO COMPLETA ============

  /// Carrega todos os dados do Supabase para uma empresa específica
  Future<Map<String, dynamic>> carregarTudoDoSupabase(String empresaId, {
    DateTime? lastSync,
    int mesesRetroativos = 3,
  }) async {
    try {
      if (!isAvailable) {
        debugPrint('>>> [Supabase] ⚠️ Abortando carga total: Supabase não disponível.');
        return {};
      }
      if (empresaId.isEmpty) throw ArgumentError('empresaId não pode ser vazio');
      
      debugPrint('>>> [Supabase] 🚀 CARREGANDO DADOS DO SUPABASE (Delta: ${lastSync != null})');
      
      final dados = <String, dynamic>{};
      final dataLimite = DateTime.now().subtract(Duration(days: 30 * mesesRetroativos));
      final dataLimiteIso = dataLimite.toIso8601String();

      // Mapeamento de tabelas para chaves de dados
      final tabelasMap = {
        tableClientes: 'clientes',
        tableProdutos: 'produtos',
        tableServicos: 'servicos',
        tablePedidos: 'pedidos',
        tableOrdensServico: 'ordens_servico',
        tableEntregas: 'entregas',
        tableVendasBalcao: 'vendas_balcao',
        tableTrocasDevolucoes: 'trocas_devolucoes',
        tableEstoqueHistorico: 'estoque_historico',
        tableLotesProdutos: 'lotes_produto',
        tableAberturasCaixa: 'aberturas_caixa',
        tableFechamentosCaixa: 'fechamentos_caixa',
        tableMotoristas: 'motoristas',
        tableAgendamentosServico: 'agendamentos_servico',
        tableNotasEntrada: 'notas_entrada',
        tableFuncionarios: 'funcionarios',
        tableTaxasEntrega: 'taxas_entrega',
        tableContasPagar: 'contas_pagar',
        tableNFCes: 'nfces',
        tableNFEs: 'nfes',
        tableSangrias: 'sangrias',
        tableSuprimentos: 'suprimentos',
        tableMesasComandas: 'mesas_comandas',
        tableLinksVendedores: 'links_vendedores',
        tableComissoesVendedores: 'comissoes_vendedores',
        tableRomaneios: 'romaneios',
      };

      for (var tableEntry in tabelasMap.entries) {
        final tableName = tableEntry.key;
        final dataKey = tableEntry.value;
        
        try {
          // Busca paginada para garantir que trazemos TUDO (especialmente produtos e clientes)
          final List<dynamic> allRows = [];
          bool hasMore = true;
          int offset = 0;
          const int batchSize = 1000;

          while (hasMore) {
            var query = _from(tableName).select().eq('empresa_id', empresaId);
            
            if (lastSync != null) {
              query = query.gte('updated_at', lastSync.toUtc().toIso8601String());
            } else if (tableName == tablePedidos || tableName == tableVendasBalcao || tableName == tableMesasComandas) {
              query = query.gte('created_at', dataLimiteIso);
            }

            final List<dynamic> result = await query
                .range(offset, offset + batchSize - 1)
                .order('id', ascending: true);

            allRows.addAll(result);
            
            if (result.length < batchSize) {
              hasMore = false;
            } else {
              offset += batchSize;
            }
          }
          
          dados[dataKey] = allRows;
          if (allRows.isNotEmpty) {
            debugPrint('>>> [Supabase] ⬇️ Baixado ${allRows.length} itens da tabela $tableName');
          }
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          if (tableName == tableNFCes && (errorStr.contains('empresaid') || errorStr.contains('empresa_id'))) {
            debugPrint('>>> [Supabase] ⚠️ Aviso: A tabela nfces está com erro de coluna/RLS no Supabase. Ignorando temporariamente: $e');
          } else {
            debugPrint('>>> [Supabase] ❌ Erro ao carregar $tableName: $e');
          }
          dados[dataKey] = [];
        }
      }

      return {'data': dados};
    } catch (e) {
      debugPrint('>>> [Supabase] ERRO CRÍTICO ao carregar: $e');
      rethrow;
    }
  }

  /// Salva dados em lote (Upsert)
  Future<void> salvarTudoNoSupabase({
    required String empresaId,
    required List<Cliente> clientes,
    required List<Produto> produtos,
    required List<Servico> servicos,
    required List<Pedido> pedidos,
    required List<OrdemServico> ordensServico,
    required List<Entrega> entregas,
    required List<VendaBalcao> vendasBalcao,
    required List<TrocaDevolucao> trocasDevolucoes,
    required List<EstoqueHistorico> estoqueHistorico,
    List<LoteProduto>? lotesProdutos,
    required List<AberturaCaixa> aberturasCaixa,
    required List<FechamentoCaixa> fechamentosCaixa,
    required List<Motorista> motoristas,
    required List<AgendamentoServico> agendamentosServico,
    required List<NotaEntrada> notasEntrada,
    required List<Funcionario> funcionarios,
    required List<TaxaEntrega> taxasEntrega,
    required List<ContaPagar> contasPagar,
    required List<NFCe> nfces,
    List<NFCe>? nfes,
    required List<SangriaCaixa> sangrias,
    required List<SuprimentoCaixa> suprimentos,
    List<LinkVendedor>? linksVendedores,
    List<ComissaoVendedor>? comissoesVendedores,
    List<Romaneio>? romaneios,
    List<MesaComanda>? mesasComandas,
    Empresa? empresa,
  }) async {
    try {
      debugPrint('>>> [Supabase] 🚀 INICIANDO SALVAMENTO EM LOTES...');
      
      // 1. PRIMEIRO PASSO: Garantir que a empresa existe (Evita Erro 23503 / Foreing Key)
      if (empresa != null) {
        try {
          debugPrint('>>> [Supabase] 🏢 Sincronizando dados da empresa: ${empresa.razaoSocial}');
          await upsertLote(tableEmpresas, [empresa.toMap()]);
        } catch (e) {
          debugPrint('>>> [Supabase] ⚠️ Aviso: Nao foi possivel atualizar os dados da empresa no Supabase (RLS/Permissao). Continuando sincronizacao: $e');
        }
      }
      
      final Map<String, List<dynamic>> colecoes = {
        tableClientes: clientes,
        tableProdutos: produtos,
        tableServicos: servicos,
        tablePedidos: pedidos,
        tableOrdensServico: ordensServico,
        tableEntregas: entregas,
        tableVendasBalcao: vendasBalcao,
        tableTrocasDevolucoes: trocasDevolucoes,
        tableEstoqueHistorico: estoqueHistorico,
        tableLotesProdutos: lotesProdutos ?? [],
        tableAberturasCaixa: aberturasCaixa,
        tableFechamentosCaixa: fechamentosCaixa,
        tableMotoristas: motoristas,
        tableAgendamentosServico: agendamentosServico,
        tableNotasEntrada: notasEntrada,
        tableFuncionarios: funcionarios,
        tableTaxasEntrega: taxasEntrega,
        tableContasPagar: contasPagar,
        tableNFCes: nfces,
        tableNFEs: nfes ?? [],
        tableSangrias: sangrias,
        tableSuprimentos: suprimentos,
        tableLinksVendedores: linksVendedores ?? [],
        tableComissoesVendedores: comissoesVendedores ?? [],
        tableRomaneios: romaneios ?? [],
        tableMesasComandas: mesasComandas ?? [],
      };

      for (var entry in colecoes.entries) {
        final table = entry.key;
        final lista = entry.value;

        if (lista.isEmpty) {
          debugPrint('>>> [Supabase] ⏭️ $table: vazio, pulando...');
          continue;
        }
        
        debugPrint('>>> [Supabase] 📤 Enviando ${lista.length} itens para $table...');
        
        final List<Map<String, dynamic>> maps = lista.map((item) {
          final map = (item as dynamic).toMap() as Map<String, dynamic>;
          map['empresa_id'] = empresaId; // Garantir empresa_id
          
          // Tratar problema PGRST204 - Coluna não existe no Supabase
          if (table == tableProdutos) {
            map.remove('composicao');
            map.remove('eh_composto');
          } else if (table == tableMesasComandas) {
            // 'total' é campo calculado (getter), não existe como coluna no Supabase
            map.remove('total');
          } else if (table == tableFechamentosCaixa) {
            // Campos agora são mapeados para camelCase no DataService
          }
          
          return map;
        }).toList();

        // Log do primeiro item para debug
        if (maps.isNotEmpty) {
          debugPrint('>>> [Supabase] 📝 Primeiro item de $table: ${maps.first.keys.take(5).toList()}...');
        }

        try {
          // OTIMIZAÇÃO: Enviar em sub-lotes de 500 para evitar timeout/limite de payload
          const int batchSize = 500;
          for (int i = 0; i < maps.length; i += batchSize) {
            final end = (i + batchSize < maps.length) ? i + batchSize : maps.length;
            final chunk = maps.sublist(i, end);
            
            debugPrint('>>> [Supabase]    -> Enviando lote ${ (i ~/ batchSize) + 1 } (${chunk.length} itens)...');
            final typedChunk = chunk.map((m) => _toSafeMap(m)).toList();
            await _client.from(table).upsert(typedChunk);
          }
          
          debugPrint('>>> [Supabase] ✅ $table: ${lista.length} itens sincronizados.');
        } catch (tableError) {
          debugPrint('>>> [Supabase] ❌ ERRO em $table: $tableError');
          // Continua com as outras tabelas mesmo se uma falhar
        }
      }
      
      debugPrint('>>> [Supabase] 🎉 Sincronização de TODAS as tabelas concluída!');
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ FALHA GERAL na sincronização: $e');
      rethrow;
    }
  }

  /// Faz upsert em lote de uma lista de registros (para restauração de emergência)
  Future<void> upsertBatch(String table, List<Map<String, dynamic>> data) async {
    if (!isAvailable || data.isEmpty) return;
    try {
      final typedData = data.map((m) => _toSafeMap(m)).toList();
      await _client.from(table).upsert(typedData);
      debugPrint('>>> [Supabase] ✅ upsertBatch: ${data.length} itens em $table');
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro no upsertBatch em $table: $e');
      rethrow;
    }
  }

  /// Testa se consegue inserir um registro de teste no Supabase
  Future<Map<String, dynamic>> testarInsercao(String empresaId) async {
    try {
      debugPrint('>>> [Supabase] 🧪 TESTANDO inserção na tabela produtos...');
      
      final testData = <String, Object?>{
        'id': 'test-${DateTime.now().millisecondsSinceEpoch}',
        'empresa_id': empresaId,
        'nome': 'Produto Teste',
        'codigo': 'TEST001',
        'preco': 1.99,
        'estoque': 10,
        'unidade': 'UN',
        'grupo': 'Teste',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      debugPrint('>>> [Supabase] 📤 Enviando dados de teste: $testData');
      
      final response = await _client.from(tableProdutos).upsert([_toSafeMap(testData)]).select();
      
      debugPrint('>>> [Supabase] ✅ Teste de inserção OK! Resposta: $response');
      return {'sucesso': true, 'resposta': response};
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ FALHA no teste de inserção: $e');
      return {'sucesso': false, 'erro': e.toString()};
    }
  }

  // ============ MÉTODOS DE AUTH ============

  Future<AuthResponse> login(String email, String password) async {
    return await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp(String email, String password) async {
    return await _client.auth.signUp(email: email, password: password);
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }

  /// Carrega todas as empresas cadastradas no Supabase
  Future<List<Empresa>> carregarEmpresas() async {
    try {
      final List<dynamic> result = await _client.from(tableEmpresas).select().order('razao_social');
      return result.map((map) => Empresa.fromMap(map)).toList();
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao carregar empresas: $e');
      return [];
    }
  }

  /// Carrega todos os usuários cadastrados no Supabase
  Future<List<Usuario>> carregarUsuarios() async {
    try {
      if (!isAvailable) return [];
      final List<dynamic> result = await _client.from(tableUsuarios).select().order('nome');
      return result.map((map) => Usuario.fromMap(map)).toList();
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao carregar usuários: $e');
      return [];
    }
  }

  /// Busca uma empresa pelo seu slug no Supabase
  Future<Empresa?> buscarEmpresaPorSlug(String slug) async {
    try {
      if (!isAvailable) return null;
      final List<dynamic> result = await _client
          .from(tableEmpresas)
          .select()
          .eq('slug', slug)
          .limit(1);
      
      if (result.isEmpty) return null;
      return Empresa.fromMap(result.first);
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao buscar empresa por slug ($slug): $e');
      return null;
    }
  }

  // ============ MÉTODOS GENÉRICOS DE CRUD ============

  /// Consulta registros de uma tabela com filtros opcionais
  Future<List<Map<String, dynamic>>> select(String table, {Map<String, dynamic>? filters, String? orderBy, bool descending = true, int? limit}) async {
    try {
      if (!isAvailable) return [];
      dynamic builder = _client.from(table).select();
      
      if (filters != null) {
        filters.forEach((key, value) {
          builder = builder.eq(key, value);
        });
      }
      
      // Builder final para ordenação e limite
      dynamic finalQuery = builder;
      
      if (orderBy != null) {
        finalQuery = finalQuery.order(orderBy, ascending: !descending);
      }
      
      if (limit != null) {
        finalQuery = finalQuery.limit(limit);
      }
      
      final response = await finalQuery;
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao buscar de $table: $e');
      return [];
    }
  }

  /// Insere um novo registro em uma tabela e retorna o dado inserido
  Future<Map<String, dynamic>> insert(String table, Map<String, dynamic> data) async {
    try {
      if (!isAvailable) return {};
      
      Map<String, dynamic> dataToInsert = data;
      final safeInsert = _toSafeMap(dataToInsert);
      final response = await _client.from(table).insert(safeInsert).select().single().timeout(const Duration(seconds: 8));
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao inserir em $table: $e');
      rethrow;
    }
  }

  /// Deleta todos os registros de uma tabela para uma empresa específica
  Future<void> deleteByEmpresa(String table, String empresaId) async {
    try {
      if (!isAvailable) return;
      await _client.from(table).delete().eq('empresa_id', empresaId).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao deletar por empresa em $table: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _filtrarCamposLocais(String table, Map<String, dynamic> map) {
    final m = <String, dynamic>{};
    
    // Normalizar datas locais para UTC com indicador 'Z'
    final isoPattern = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}');
    for (final entry in map.entries) {
      var val = entry.value;
      if (val is String && isoPattern.hasMatch(val)) {
        if (!val.endsWith('Z') && !val.contains(RegExp(r'[+-]\d{2}:?\d{2}$'))) {
          final parsed = DateTime.tryParse(val);
          if (parsed != null) {
            val = parsed.toUtc().toIso8601String();
          }
        }
      }
      m[entry.key] = val;
    }

    if (table.contains('produtos')) {
      m.remove('envia_balanca');
      m.remove('enviaBalanca');
      m.remove('cobrar_garcom');
      m.remove('cobrarGarcom');
      m.remove('perguntas_selecao');
      m.remove('perguntasSelecao');
      m.remove('precos_por_perfil');
      m.remove('precosPorPerfil');
      m.remove('regras_quantidade');
      m.remove('regrasQuantidade');
      m.remove('exibir_composicao_pdv');
      m.remove('exibirComposicaoPdv');
    }
    if (table.contains('pedidos')) {
      m.remove('acrescimoTotal');
      m.remove('descontoTotal');
    }
    if (table.contains('entregas')) {
      m.remove('dataCriacao');
      m.remove('historico');
      m.remove('ordemRota');
    }
    // estoque_historico: as colunas de custo (custo_unitario/valor_custo) e a
    // coluna 'sync' NÃO existem no Supabase até rodar o SUPABASE_FIX_ALL.sql —
    // enviá-las causa PGRST204 e descarta a entrada inteira da nuvem. A
    // filtragem dinâmica no upsert() (_detectarColunasEstoqueHistorico) cuida
    // disso; aqui removemos apenas a variação camel (que nunca existe).
    if (table.contains('estoque_historico')) {
      m.remove('fornecedorNome');
    }
    if (table.contains('empresas')) {
      m.remove('telas_permitidas');
      m.remove('observacao');
      m.remove('cor_primaria');
      m.remove('cor_secundaria');
    }
    if (table.contains('usuarios')) {
      // A tabela 'usuarios' do Supabase só tem 8 colunas (id, email, nome,
      // empresa_id, perfil, ativo, created_at, updated_at). O toMap() do app
      // envia campos adicionais (senha, tipo, is_master, serie_nfce, etc.) que
      // NÃO existem lá — isso fazia o upsert falhar silenciosamente e o perfil
      // nunca chegar à nuvem (usuários 'sumiam'). Aqui filtramos e mapeamos
      // 'tipo' -> 'perfil' para a gravação funcionar de verdade.
      final perfil = m['tipo']?.toString() ?? 'operador';
      m.removeWhere((k, _) => !const {
        'id', 'email', 'nome', 'empresa_id', 'perfil', 'ativo',
        'created_at', 'updated_at',
      }.contains(k));
      m['perfil'] = perfil;
    }
    return m;
  }

  /// Realiza upsert (insert or update) de um item em uma tabela
  Future<void> upsert(String table, Map<String, dynamic> data) async {
    try {
      if (!isAvailable) {
        debugPrint('>>> [Supabase] ⏭️ upsert ignorado: Supabase não disponível');
        return;
      }
      debugPrint('>>> [Supabase] 📤 Executando upsert em $table...');
      debugPrint('>>> [Supabase]    ID: ${data['id']}');
      debugPrint('>>> [Supabase]    Empresa: ${data['empresa_id']}');
      
      Map<String, dynamic> dataToUpsert = _filtrarCamposLocais(table, data);

      // estoque_historico: envia SOMENTE as colunas que existem na tabela real
      // (evita PGRST204 por custo_unitario/valor_custo quando o schema ainda não
      // foi migrado). Com o schema migrado, o custo da quebra passa a subir.
      if (table == SupabaseService.tableEstoqueHistorico) {
        final colunas = await _detectarColunasEstoqueHistorico();
        dataToUpsert.removeWhere((k, _) => !colunas.contains(k));
      }

      final safeData = _toSafeMap(dataToUpsert);
      await _client.from(table).upsert(safeData).timeout(const Duration(seconds: 8));
      debugPrint('>>> [Supabase] ✅ Upsert concluído em $table');
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao fazer upsert em $table: $e');
      rethrow;
    }
  }

  /// Cache das colunas reais da tabela 'usuarios' no Supabase. Detectadas uma
  /// única vez via OpenAPI (/rest/v1/) e reutilizadas em todos os salvamentos.
  Set<String>? _colunasUsuariosCache;
  Future<Set<String>>? _detectandoColunasUsuarios;

  /// Detecta (uma única vez) as colunas reais da tabela 'usuarios' consultando
  /// o endpoint OpenAPI do PostgREST (/rest/v1/). A chave do app (service_role)
  /// tem acesso a esse endpoint — confirmado em teste. Com a lista de colunas em
  /// mãos, o upsert envia SOMENTE o que existe na tabela: quando o schema está
  /// antigo (8 colunas), isso elimina o erro PGRST204 ("Could not find the
  /// 'is_master' column...") que era logado a cada salvamento de usuário.
  /// Se a detecção falhar (offline/erro), retorna o fallback das 8 colunas
  /// conhecidas do schema antigo — nunca bloqueia o fluxo de salvamento.
  Future<Set<String>> _detectarColunasUsuarios() async {
    final cached = _colunasUsuariosCache;
    if (cached != null) return cached;
    final emAndamento = _detectandoColunasUsuarios;
    if (emAndamento != null) return emAndamento;

    final futuro = _detectarColunasUsuariosInterno();
    _detectandoColunasUsuarios = futuro;
    try {
      final colunas = await futuro;
      _colunasUsuariosCache = colunas;
      return colunas;
    } finally {
      _detectandoColunasUsuarios = null;
    }
  }

  Future<Set<String>> _detectarColunasUsuariosInterno() async {
    try {
      final resp = await http.get(
        Uri.parse('${SupabaseConfig.url}/rest/v1/'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          final definitions = decoded['definitions'];
          if (definitions is Map<String, dynamic>) {
            final usuarios = definitions['usuarios'];
            if (usuarios is Map<String, dynamic>) {
              final properties = usuarios['properties'];
              if (properties is Map<String, dynamic>) {
                final colunas = properties.keys.toSet();
                debugPrint('>>> [Supabase] ℹ️ Colunas reais de usuarios detectadas (${colunas.length}): ${colunas.join(', ')}');
                return colunas;
              }
            }
          }
        }
      } else {
        debugPrint('>>> [Supabase] ⚠️ Falha ao detectar colunas de usuarios (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      debugPrint('>>> [Supabase] ⚠️ Falha ao detectar colunas de usuarios: $e');
    }
    return const {
      'id', 'email', 'nome', 'empresa_id', 'perfil', 'ativo',
      'created_at', 'updated_at',
    };
  }

  /// Upsert resiliente de um usuário no Supabase.
  ///
  /// Detecta (uma vez, em cache) as colunas reais da tabela 'usuarios' e envia
  /// APENAS os campos que existem no banco. Assim, no schema antigo (8 colunas)
  /// o salvamento funciona de primeira, sem tentar gravar is_master/senha/tipo
  /// (que geravam o erro PGRST204 logado a cada usuário). Se a tabela for
  /// migrada para o schema novo, o app passa automaticamente a enviar o perfil
  /// completo. Só NÃO lança exceção quando o upsert falhar por outro motivo —
  /// nesse caso o chamador registra a falha de forma persistente para nunca
  /// mais "sumir" um usuário silenciosamente.
  Future<void> upsertUsuario(Map<String, dynamic> dados) async {
    if (!isAvailable) {
      debugPrint('>>> [Supabase] ⏭️ upsertUsuario ignorado: Supabase não disponível');
      throw Exception('Supabase não disponível');
    }
    if (dados['empresa_id'] == null || dados['empresa_id'].toString().isEmpty) {
      throw Exception('Usuário sem empresa_id não pode ir para a nuvem');
    }

    // Filtra os dados para conter somente colunas que existem na tabela.
    final colunas = await _detectarColunasUsuarios();
    final dadosFiltrados = _toSafeMap(dados)
      ..removeWhere((k, _) => !colunas.contains(k));

    // O app usa 'tipo' (nome do enumerado); a coluna do banco é 'perfil'.
    if (colunas.contains('perfil') && dados.containsKey('tipo')) {
      dadosFiltrados['perfil'] = dados['tipo'].toString();
    }

    try {
      await _client
          .from(SupabaseService.tableUsuarios)
          .upsert(dadosFiltrados)
          .timeout(const Duration(seconds: 8));
      debugPrint('>>> [Supabase] ✅ Usuário ${dados['id']} sincronizado (${dadosFiltrados.length} colunas existentes).');
      return;
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ ERRO GRAVE: usuário ${dados['id']} NÃO sincronizou: $e');
      rethrow;
    }
  }

  /// Colunas reais da tabela 'estoque_historico' no Supabase. Detectadas uma
  /// única vez via OpenAPI (/rest/v1/). Enquanto o schema antigo não tiver as
  /// colunas de custo (custo_unitario/valor_custo), o upsert envia só o que
  /// existe — sem PGRST204. Quando o SUPABASE_FIX_ALL.sql for rodado, o custo
  /// da quebra passa automaticamente a ser sincronizado.
  Set<String>? _colunasEstoqueHistoricoCache;
  Future<Set<String>>? _detectandoColunasEstoqueHistorico;

  Future<Set<String>> _detectarColunasEstoqueHistorico() async {
    final cached = _colunasEstoqueHistoricoCache;
    if (cached != null) return cached;
    final emAndamento = _detectandoColunasEstoqueHistorico;
    if (emAndamento != null) return emAndamento;

    final futuro = _detectarColunasEstoqueHistoricoInterno();
    _detectandoColunasEstoqueHistorico = futuro;
    try {
      final colunas = await futuro;
      _colunasEstoqueHistoricoCache = colunas;
      return colunas;
    } finally {
      _detectandoColunasEstoqueHistorico = null;
    }
  }

  Future<Set<String>> _detectarColunasEstoqueHistoricoInterno() async {
    try {
      final resp = await http.get(
        Uri.parse('${SupabaseConfig.url}/rest/v1/'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          final definitions = decoded['definitions'];
          if (definitions is Map<String, dynamic>) {
            final tabela = definitions['estoque_historico'];
            if (tabela is Map<String, dynamic>) {
              final properties = tabela['properties'];
              if (properties is Map<String, dynamic>) {
                final colunas = properties.keys.toSet();
                debugPrint('>>> [Supabase] ℹ️ Colunas reais de estoque_historico detectadas (${colunas.length}): ${colunas.join(', ')}');
                return colunas;
              }
            }
          }
        }
      } else {
        debugPrint('>>> [Supabase] ⚠️ Falha ao detectar colunas de estoque_historico (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      debugPrint('>>> [Supabase] ⚠️ Falha ao detectar colunas de estoque_historico: $e');
    }
    // Fallback conservador: colunas conhecidas do schema (sem custo_unitario/
    // valor_custo — que ainda não existem até rodar o SUPABASE_FIX_ALL.sql).
    return const {
      'id', 'empresa_id', 'produto_id', 'produto_nome', 'tipo', 'quantidade',
      'motivo', 'operador', 'data_operacao', 'created_at', 'data',
      'updated_at', 'fornecedor_nome', 'fornecedor_id', 'observacao', 'usuario',
    };
  }

  /// Realiza upsert de múltiplos itens em uma tabela (Batch)
  Future<void> upsertLote(String table, List<Map<String, dynamic>> data) async {
    try {
      if (!isAvailable || data.isEmpty) return;
      
      // OTIMIZAÇÃO: Batching para grandes volumes
      const int batchSize = 500;
      
      List<Map<String, dynamic>> enrichedData = data.map((map) => _filtrarCamposLocais(table, map)).toList();

      // estoque_historico: envia apenas colunas que existem no schema real
      // (mesma proteção do upsert individual — evita PGRST204 pelas colunas
      // de custo que ainda não existem até rodar o SUPABASE_FIX_ALL.sql).
      if (table == SupabaseService.tableEstoqueHistorico) {
        final colunas = await _detectarColunasEstoqueHistorico();
        enrichedData = enrichedData
            .map((m) => m..removeWhere((k, _) => !colunas.contains(k)))
            .toList();
      }

      final typedData = enrichedData.map((m) => _toSafeMap(m)).toList();
      
      if (typedData.length > batchSize) {
        debugPrint('>>> [Supabase] 📦 Fracionando upsert de ${typedData.length} itens em lotes de $batchSize...');
        for (int i = 0; i < typedData.length; i += batchSize) {
          final end = (i + batchSize < typedData.length) ? i + batchSize : typedData.length;
          final chunk = typedData.sublist(i, end);
          await _client.from(table).upsert(chunk).timeout(const Duration(seconds: 15));
        }
      } else {
        await _client.from(table).upsert(typedData).timeout(const Duration(seconds: 15));
      }
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao fazer upsertLote em $table: $e');
      rethrow;
    }
  }

  /// Normaliza uma string ISO que representa hora LOCAL (sem fuso) para UTC.
  ///
  /// O app grava datas locais como `2026-08-14T22:41:56.938650` (sem sufixo de
  /// fuso). As colunas do Supabase são `timestamptz`: o Postgres interpreta a
  /// string "naive" como UTC, deslocando tudo em -3h (horário de Brasília).
  /// Esta normalização anexa o fuso correto (Z) ANTES de enviar, preservando o
  /// instante real. Strings que já têm fuso (Z ou +hh:mm) são mantidas.
  static String? _normalizarDataParaUtc(dynamic val) {
    if (val is! String) return null;
    final isoPattern = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}');
    if (!isoPattern.hasMatch(val)) return null;
    if (val.endsWith('Z') || val.contains(RegExp(r'[+-]\d{2}:?\d{2}$'))) {
      return null; // já tem fuso explícito, não mexer
    }
    final parsed = DateTime.tryParse(val);
    if (parsed == null) return null;
    return parsed.toUtc().toIso8601String();
  }

  Map<String, dynamic> _toSafeMap(Map<String, dynamic> map) {
    final safe = Map<String, dynamic>.from(map)
      ..removeWhere((key, value) => value == null);
    // Normalizar datas locais para UTC em TODAS as escritas (incluindo o
    // sincronizador em lote, que antes pulava _filtrarCamposLocais e gravava
    // a hora local "naive" no timestamptz do Supabase, deslocando caixas,
    // sangrias e fechamentos em -3h a cada ciclo de sincronização).
    for (final key in safe.keys.toList()) {
      final novo = _normalizarDataParaUtc(safe[key]);
      if (novo != null) safe[key] = novo;
    }
    return safe;
  }

  /// Remove um item de uma tabela por ID ou Filtros
  Future<void> delete(String table, dynamic idOrFilters) async {
    try {
      if (!isAvailable) return;
      var query = _client.from(table).delete();
      
      if (idOrFilters is Map<String, dynamic>) {
        idOrFilters.forEach((key, value) {
          query = query.eq(key, value);
        });
      } else {
        query = query.eq('id', idOrFilters.toString());
      }
      
      await query.timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao deletar de $table: $e');
      rethrow;
    }
  }

  /// Remove itens de uma tabela filtrando por campos
  Future<void> deleteFiltered(String table, Map<String, dynamic> filters) async {
    try {
      if (!isAvailable) return;
      var query = _client.from(table).delete();
      filters.forEach((key, value) {
        query = query.eq(key, value);
      });
      await query.timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao deletar filtrado de $table: $e');
      rethrow;
    }
  }

  /// Carrega uma coleção de forma paginada para o Supabase
  Future<List<Map<String, dynamic>>> carregarColecaoPaginada(
    String empresaId,
    String table, {
    int page = 0,
    int pageSize = 50,
    String orderBy = 'created_at',
    bool descending = true,
  }) async {
    try {
      if (!isAvailable) return [];
      
      final from = page * pageSize;
      final to = from + pageSize - 1;
      
      final List<dynamic> result = await _client
          .from(table)
          .select()
          .eq('empresa_id', empresaId)
          .order(orderBy, ascending: !descending)
          .range(from, to);
          
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao carregar coleção paginada ($table): $e');
      return [];
    }
  }

  // ============ MÉTODOS DE BRIDGE ============

  /// Busca o status de todos os bridges (computadores de emissão)
  Future<List<Map<String, dynamic>>> getBridgeStatus() async {
    try {
      if (!isAvailable) return [];
      
      final response = await _client
          .from('bridge_status')
          .select()
          .order('pc_name', ascending: true);
          
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('>>> [Supabase Bridge] ❌ Erro ao buscar status: $e');
      return [];
    }
  }

  // ============ MÉTODOS DE MONITORAMENTO DE SYNC ============

  /// Busca o status de sincronização mais recente de uma empresa (tabela sync_status)
  Future<Map<String, dynamic>?> getSyncStatus(String empresaId) async {
    try {
      if (!isAvailable) return null;
      final response = await _client
          .from('sync_status')
          .select()
          .eq('empresa_id', empresaId)
          .limit(1);
      if (response.isEmpty) return null;
      return Map<String, dynamic>.from(response.first);
    } catch (e) {
      debugPrint('>>> [Supabase SyncStatus] ❌ Erro ao buscar sync_status: $e');
      return null;
    }
  }

  /// Busca os últimos logs de sincronização de uma empresa (tabela sync_logs)
  Future<List<Map<String, dynamic>>> getSyncLogs(String empresaId, {int limit = 50}) async {
    try {
      if (!isAvailable) return [];
      final response = await _client
          .from('sync_logs')
          .select()
          .eq('empresa_id', empresaId)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('>>> [Supabase SyncLogs] ❌ Erro ao buscar sync_logs: $e');
      return [];
    }
  }

  // ============ MÉTODOS DE STORAGE ============

  /// Faz upload de um arquivo para o Supabase Storage
  Future<String?> uploadFile(String bucket, String path, dynamic file, {String? contentType}) async {
    try {
      if (!isAvailable) return null;

      final extension = path.split('.').last.toLowerCase();
      String finalContentType = contentType ?? 'application/octet-stream';
      
      if (contentType == null) {
        if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(extension)) {
          finalContentType = 'image/$extension';
        } else if (extension == 'pdf') {
          finalContentType = 'application/pdf';
        }
      }

      if (kIsWeb) {
        // No Web, o 'file' deve ser Uint8List ou File do package:web
        await _client.storage.from(bucket).uploadBinary(
          path,
          file,
          fileOptions: FileOptions(contentType: finalContentType, upsert: true),
        );
      } else {
        // No Nativo, o 'file' é o objeto File de dart:io
        await _client.storage.from(bucket).upload(
          path,
          file,
          fileOptions: FileOptions(contentType: finalContentType, upsert: true),
        );
      }

      final String publicUrl = _client.storage.from(bucket).getPublicUrl(path);
      debugPrint('>>> [Supabase Storage] ✅ Upload concluído: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('>>> [Supabase Storage] ❌ Erro no upload: $e');
      return null;
    }
  }

  /// Remove um arquivo do Supabase Storage
  Future<void> deleteFile(String bucket, String path) async {
    try {
      if (!isAvailable) return;
      await _client.storage.from(bucket).remove([path]);
      debugPrint('>>> [Supabase Storage] ✅ Arquivo removido: $path');
    } catch (e) {
      debugPrint('>>> [Supabase Storage] ❌ Erro ao remover arquivo: $e');
    }
  }

  /// Alias para manter compatibilidade
  Future<String?> uploadImage(String bucket, String path, dynamic file, {String? contentType}) =>
      uploadFile(bucket, path, file, contentType: contentType);

  /// Faz upload de uma imagem usando bytes diretamente
  Future<String?> uploadImageFromBytes({
    required Uint8List imageBytes,
    required String storagePath,
    String contentType = 'image/jpeg',
    Function(double)? onProgress,
    Map<String, String>? metadata,
  }) async {
    // Para simplificar, usamos o bucket 'imagens' por padrão
    const bucket = 'imagens';
    
    if (onProgress != null) onProgress(0.1);
    
    final url = await uploadFile(
      bucket, 
      storagePath, 
      imageBytes, 
      contentType: contentType
    );
    
    if (onProgress != null) onProgress(1.0);
    return url;
  }
}

