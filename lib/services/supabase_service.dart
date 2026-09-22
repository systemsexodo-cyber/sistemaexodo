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
import 'package:postgres/postgres.dart';
import 'env_config.dart';

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
  static const String tableServicosRealizados = 'servicos_realizados';
  static const String tableOrcamentos = 'orcamentos';
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
        tableServicosRealizados: 'servicos_realizados',
        tableOrcamentos: 'orcamentos',
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

      // Tabelas de CATÁLOGO: SEMPRE baixadas por completo (sem filtro delta).
      // Um catálogo incompleto no cliente é pior que um sync mais pesado — evita
      // que produtos/clientes antigos (nunca alterados) fiquem para sempre fora
      // do cliente por causa de delta sync / relógio / lastSync desatualizado.
      const tabelasSempreCompletas = {
        tableProdutos,
        tableClientes,
        tableServicos,
        tableFuncionarios,
        tableMotoristas,
        tableTaxasEntrega,
        tableLotesProdutos,
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
            
            if (lastSync != null && !tabelasSempreCompletas.contains(tableName)) {
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

  /// Prepara um mapa de vendas_balcao para o Supabase.
  /// Deriva numero_venda do 'numero' textual ('VND-0405' -> 405); se não
  /// houver dígitos, usa um hash estável do id.
  static Map<String, dynamic> _prepararVendaBalcao(Map<String, dynamic> m) {
    if (m.containsKey('numero_venda') && m['numero_venda'] != null && m['numero_venda'] != 0) return m;
    final numero = m['numero'];
    if (numero != null) {
      final match = RegExp(r'(\d+)').firstMatch(numero.toString());
      final nv = match != null ? int.tryParse(match.group(1)!) : null;
      if (nv != null) {
        m['numero_venda'] = nv;
        return m;
      }
    }
    final id = m['id']?.toString() ?? '';
    m['numero_venda'] = id.hashCode & 0x7fffffff;
    return m;
  }

  /// Faz upsert em lote de uma lista de registros.
  /// Filtra automaticamente as colunas que não existem na tabela real do
  /// Supabase (via OpenAPI), eliminando o erro PGRST204 de uma vez por todas.
  /// [onConflict] permite escolher a(s) coluna(s) do conflito (ex:
  /// 'empresa_id,numero_venda' quando a tabela tem uma unique constraint além
  /// da PK). Para vendas_balcao o numero_venda é derivado automaticamente.
  Future<void> upsertBatch(String table, List<Map<String, dynamic>> data,
      {String? onConflict}) async {
    if (!isAvailable || data.isEmpty) return;
    try {
      final colunas = await _detectarColunasTabela(table);
      var lista = data.map((m) => _toSafeMap(m)).toList();
      if (table == 'vendas_balcao') {
        lista = lista.map(_prepararVendaBalcao).toList();
      }
      if (colunas != null && colunas.isNotEmpty) {
        final descartadas = <String>{};
        lista = lista
            .map((m) => _filtrarParaColunasReais(m, colunas, colunasDescartadas: descartadas))
            .toList();
        if (descartadas.isNotEmpty) {
          debugPrint('>>> [Supabase] 🔧 Colunas descartadas em $table: ${descartadas.join(', ')}');
        }
      }
      final query = _client.from(table).upsert(lista, onConflict: onConflict);
      await query.timeout(const Duration(seconds: 60));
      debugPrint('>>> [Supabase] ✅ upsertBatch: ${data.length} itens em $table');
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro no upsertBatch em $table: $e');
      rethrow;
    }
  }

  /// Conta quantos registros de uma tabela existem no Supabase para a empresa.
  /// Retorna -1 se a tabela não existe.
  Future<int> contarRegistrosNaNuvem(String table, String empresaId) async {
    if (!isAvailable) return -1;
    try {
      final countResp = await _client
          .from(table)
          .select('id')
          .eq('empresa_id', empresaId)
          .count()
          .timeout(const Duration(seconds: 30));
      return countResp.count;
    } catch (e) {
      debugPrint('>>> [Supabase] ⚠️ Não foi possível contar $table: $e');
      return -1;
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
  ///
  /// `filtrosDiferentes` aplica `<>` (útil para "tudo menos vazio", como os
  /// eventos com erro em `sync_logs`), sem precisar baixar a tabela inteira.
  Future<List<Map<String, dynamic>>> select(String table, {Map<String, dynamic>? filters, Map<String, dynamic>? filtrosDiferentes, String? orderBy, bool descending = true, int? limit}) async {
    try {
      if (!isAvailable) return [];
      dynamic builder = _client.from(table).select();
      
      if (filters != null) {
        filters.forEach((key, value) {
          builder = builder.eq(key, value);
        });
      }

      if (filtrosDiferentes != null) {
        filtrosDiferentes.forEach((key, value) {
          builder = builder.neq(key, value);
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

  /// Deleta todos os registros de uma tabela para uma empresa específica.
  /// Retorna quantos registros foram removidos (0 se nada foi encontrado).
  Future<int> deleteByEmpresa(String table, String empresaId) async {
    try {
      if (!isAvailable) return 0;
      if (empresaId.isEmpty) {
        debugPrint('>>> [Supabase] ❌ ERRO: empresaId vazio, abortando delete em $table');
        return 0;
      }
      // Contar ANTES de apagar: só apaga o que realmente pertence à empresa
      final countResp = await _client
          .from(table)
          .select('id')
          .eq('empresa_id', empresaId)
          .count()
          .timeout(const Duration(seconds: 15));
      final count = countResp.count;
      if (count > 0) {
        await _client.from(table).delete().eq('empresa_id', empresaId).timeout(const Duration(seconds: 15));
        debugPrint('>>> [Supabase] 🗑️ $table: $count registro(s) removidos da empresa $empresaId');
      } else {
        debugPrint('>>> [Supabase] ⏭️ $table: 0 registros da empresa, pulando...');
      }
      return count;
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
      // Somente colunas que comprovadamente NÃO existem no schema do Supabase
      // (verificado via OpenAPI /rest/v1/). envia_balanca, precos_por_perfil e
      // regras_quantidade EXISTEM no Supabase e agora são preservadas — o
      // filtro genérico (_filtrarParaColunasReais) cuida do resto.
      m.remove('cobrar_garcom');
      m.remove('cobrarGarcom');
      m.remove('perguntas_selecao');
      m.remove('perguntasSelecao');
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

      // vendas_balcao: derivar numero_venda para consistência.
      String? onConflict;
      if (table == 'vendas_balcao') {
        dataToUpsert = _prepararVendaBalcao(dataToUpsert);
      }

      // Filtro genérico: envia SOMENTE colunas que existem na tabela real
      // (via OpenAPI, em cache). Elimina PGRST204 para qualquer tabela,
      // inclusive as legadas com colunas camelCase (temAcesso, linkVendedorId,
      // etc.). Se a detecção falhar, mantém o comportamento antigo.
      final colunas = await _detectarColunasTabela(table);
      if (colunas != null && colunas.isNotEmpty) {
        final descartadas = <String>{};
        dataToUpsert = _filtrarParaColunasReais(dataToUpsert, colunas, colunasDescartadas: descartadas);
        if (descartadas.isNotEmpty) {
          debugPrint('>>> [Supabase] 🔧 Colunas descartadas em $table: ${descartadas.join(', ')}');
        }
      }

      final safeData = _toSafeMap(dataToUpsert);
      await _client
          .from(table)
          .upsert(safeData, onConflict: onConflict)
          .timeout(const Duration(seconds: 8));
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

  /// ============================================================
  /// DETECÇÃO GENÉRICA DE COLUNAS VIA OPENAPI (/rest/v1/)
  /// ============================================================
  /// Busca UMA única vez as colunas reais de TODAS as tabelas do Supabase e
  /// guarda em cache. Usada no upsert/upsertBatch para enviar SOMENTE colunas
  /// que existem de verdade — elimina permanentemente o erro PGRST204
  /// ("Could not find the 'xxx' column") para qualquer tabela/coluna, inclusive
  /// as que aparecerem no futuro. Se a detecção falhar, retorna null (sem
  /// filtro) e o fluxo continua com o comportamento antigo.
  Map<String, Set<String>>? _colunasTodasTabelasCache;
  Future<Map<String, Set<String>>>? _detectandoColunasTodasTabelas;

  Future<Map<String, Set<String>>> _detectarColunasTodasTabelas() async {
    final cached = _colunasTodasTabelasCache;
    if (cached != null) return cached;
    final emAndamento = _detectandoColunasTodasTabelas;
    if (emAndamento != null) return emAndamento;

    final futuro = _detectarColunasTodasTabelasInterno();
    _detectandoColunasTodasTabelas = futuro;
    try {
      final colunas = await futuro;
      _colunasTodasTabelasCache = colunas;
      return colunas;
    } finally {
      _detectandoColunasTodasTabelas = null;
    }
  }

  Future<Map<String, Set<String>>> _detectarColunasTodasTabelasInterno() async {
    final resultado = <String, Set<String>>{};
    try {
      final resp = await http.get(
        Uri.parse('${SupabaseConfig.url}/rest/v1/'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          final definitions = decoded['definitions'];
          if (definitions is Map<String, dynamic>) {
            definitions.forEach((nome, def) {
              if (def is Map<String, dynamic>) {
                final properties = def['properties'];
                if (properties is Map<String, dynamic>) {
                  resultado[nome] = properties.keys.toSet();
                }
              }
            });
            debugPrint('>>> [Supabase] ℹ️ Colunas reais detectadas via OpenAPI (${resultado.length} tabelas)');
          }
        }
      } else {
        debugPrint('>>> [Supabase] ⚠️ Falha ao detectar colunas via OpenAPI (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      debugPrint('>>> [Supabase] ⚠️ Falha ao detectar colunas via OpenAPI: $e');
    }
    return resultado;
  }

  /// Retorna as colunas reais de uma tabela (ou null se não foi possível
  /// detectar — nesse caso o chamador não filtra e segue como antes).
  Future<Set<String>?> _detectarColunasTabela(String table) async {
    final todas = await _detectarColunasTodasTabelas();
    if (todas.isEmpty) return null;
    final colunas = todas[table];
    if (colunas == null) {
      // Tabela não existe no Supabase
      debugPrint('>>> [Supabase] ℹ️ Tabela "$table" não encontrada no schema (OpenAPI)');
      return const {};
    }
    return colunas;
  }

  /// Converte snake_case para camelCase (tem_acesso -> temAcesso).
  static String _snakeParaCamel(String chave) {
    final partes = chave.split('_');
    if (partes.length <= 1) return chave;
    return partes.first +
        partes.skip(1).map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join();
  }

  /// Filtra um mapa para conter SOMENTE colunas que existem na tabela real do
  /// Supabase. Se a chave local (ex: tem_acesso) não existir mas a versão
  /// camelCase (temAcesso) existir, RENOMEIA preservando o dado. Se não existir
  /// de nenhuma forma, descarta a chave (evita PGRST204).
  ///
  /// [colunasDescartadas] é um set acumulativo (por tabela) usado para logar
  /// colunas descartadas apenas uma vez, evitando spam no console (5683 produtos
  /// × 3 colunas = 17.000 linhas de log inúteis).
  Map<String, dynamic> _filtrarParaColunasReais(
      Map<String, dynamic> map, Set<String> colunas,
      {Set<String>? colunasDescartadas}) {
    final resultado = <String, dynamic>{};
    map.forEach((chave, valor) {
      if (colunas.contains(chave)) {
        resultado[chave] = valor;
        return;
      }
      // Tenta o twin camelCase (tabelas legadas criadas com camelCase)
      final camel = _snakeParaCamel(chave);
      if (camel != chave && colunas.contains(camel)) {
        resultado[camel] = valor;
        return;
      }
      // Tenta o twin snake_case (chave veio camelCase e a tabela é snake_case)
      final snake = chave.replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (m) => '${m.group(1)}_${m.group(2)!.toLowerCase()}',
      );
      if (snake != chave && colunas.contains(snake)) {
        resultado[snake] = valor;
        return;
      }
      // Não existe de nenhuma forma -> descartar (log apenas na 1ª ocorrência)
      if (colunasDescartadas != null && colunasDescartadas.add(chave)) {
        debugPrint('>>> [Supabase] 🔧 Coluna "$chave" descartada (não existe na tabela)');
      }
    });
    return resultado;
  }

  Set<String>? _colunasEmpresasCache;
  Future<Set<String>>? _detectandoColunasEmpresas;

  /// Detecta (uma única vez) as colunas reais da tabela 'empresas' consultando
  /// o endpoint OpenAPI do PostgREST (/rest/v1/), igual à detecção de 'usuarios'.
  /// O Empresa.toMap() envia ~40 chaves (razaoSocial, email, whatsapp*,
  /// modelosAdicionais, etc.) mas a tabela real só tem algumas — sem filtrar,
  /// o upsert falhava com PGRST204 e o 'configuracoes' (OK de mensalidade,
  /// perfis de preço, NFC-e) nunca chegava à nuvem.
  Future<Set<String>> _detectarColunasEmpresas() async {
    final cached = _colunasEmpresasCache;
    if (cached != null) return cached;
    final emAndamento = _detectandoColunasEmpresas;
    if (emAndamento != null) return emAndamento;
    final futuro = _detectarColunasEmpresasInterno();
    _detectandoColunasEmpresas = futuro;
    try {
      final colunas = await futuro;
      _colunasEmpresasCache = colunas;
      return colunas;
    } finally {
      _detectandoColunasEmpresas = null;
    }
  }

  Future<Set<String>> _detectarColunasEmpresasInterno() async {
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
            final empresas = definitions['empresas'];
            if (empresas is Map<String, dynamic>) {
              final properties = empresas['properties'];
              if (properties is Map<String, dynamic>) {
                final colunas = properties.keys.toSet();
                debugPrint('>>> [Supabase] ℹ️ Colunas reais de empresas detectadas (${colunas.length}): ${colunas.join(', ')}');
                return colunas;
              }
            }
          }
        }
      } else {
        debugPrint('>>> [Supabase] ⚠️ Falha ao detectar colunas de empresas (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      debugPrint('>>> [Supabase] ⚠️ Falha ao detectar colunas de empresas: $e');
    }
    // Fallback conservador: colunas conhecidas do schema
    // (ADICIONAR_CONFIGURACOES_EMPRESA.sql / SUPABASE_FIX_ALL.sql).
    return const {
      'id', 'empresa_id', 'razao_social', 'nome_fantasia', 'cnpj', 'slug',
      'ativo', 'created_at', 'updated_at', 'configuracoes', 'perfis_de_preco',
      'perfisDePreco',
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
      if (table == SupabaseService.tableEstoqueHistorico) {
        final colunas = await _detectarColunasEstoqueHistorico();
        enrichedData = enrichedData
            .map((m) => m..removeWhere((k, _) => !colunas.contains(k)))
            .toList();
      }

      // empresas: mesma proteção do upsert individual
      if (table == SupabaseService.tableEmpresas) {
        final colunas = await _detectarColunasEmpresas();
        enrichedData = enrichedData
            .map((m) => m..removeWhere((k, _) => !colunas.contains(k)))
            .toList();
      }

      final typedData = enrichedData.map((m) => _toSafeMap(m)).toList();
      
      // Retry com backoff para erros de quota/rate limit
      const int maxRetries = 3;
      
      if (typedData.length > batchSize) {
        debugPrint('>>> [Supabase] 📦 Fracionando upsert de ${typedData.length} itens em lotes de $batchSize...');
        for (int i = 0; i < typedData.length; i += batchSize) {
          final end = (i + batchSize < typedData.length) ? i + batchSize : typedData.length;
          final chunk = typedData.sublist(i, end);
          
          for (int retry = 0; retry < maxRetries; retry++) {
            try {
              await _client.from(table).upsert(chunk).timeout(const Duration(seconds: 30));
              break; // Sucesso, sair do retry
            } catch (e) {
              final isQuotaError = e.toString().contains('quota') || 
                  e.toString().contains('rate limit') ||
                  e.toString().contains('429') ||
                  e.toString().contains('503');
              if (isQuotaError && retry < maxRetries - 1) {
                final delay = Duration(seconds: (retry + 1) * 5);
                debugPrint('>>> [Supabase] ⏳ Quota/rate limit atingido, aguardando ${delay.inSeconds}s antes de retry...');
                await Future.delayed(delay);
              } else {
                rethrow;
              }
            }
          }
        }
      } else {
        for (int retry = 0; retry < maxRetries; retry++) {
          try {
            await _client.from(table).upsert(typedData).timeout(const Duration(seconds: 30));
            break;
          } catch (e) {
            final isQuotaError = e.toString().contains('quota') || 
                e.toString().contains('rate limit') ||
                e.toString().contains('429') ||
                e.toString().contains('503');
            if (isQuotaError && retry < maxRetries - 1) {
              final delay = Duration(seconds: (retry + 1) * 5);
              debugPrint('>>> [Supabase] ⏳ Quota/rate limit atingido, aguardando ${delay.inSeconds}s antes de retry...');
              await Future.delayed(delay);
            } else {
              rethrow;
            }
          }
        }
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

  /// Remove TODOS os registros de uma empresa em todas as tabelas do Supabase.
  /// Usado quando se tem CERTEZA de que o upload sera feito em seguida.
  /// IMPORTANTE: Isso e destrutivo! Nao usar sem upload confirmado.
  Future<int> limparDadosEmpresa(String empresaId) async {
    if (!isAvailable) return 0;
    if (empresaId.isEmpty) {
      debugPrint('>>> [Supabase] ❌ ERRO: empresaId vazio, abortando limpeza!');
      return 0;
    }
    
    debugPrint('>>> [Supabase] 🧹 Limpando dados da empresa $empresaId...');
    
    // Tabelas com empresa_id (ordem: filhas primeiro, depois pais)
    final tabelas = [
      tableComissoesVendedores,
      tableLinksVendedores,
      tableSangrias,
      tableSuprimentos,
      tableNFCes,
      tableNFEs,
      tableContasPagar,
      tableRomaneios,
      tableFuncionarios,
      tableNotasEntrada,
      tableAgendamentosServico,
      tableLotesProdutos,
      tableEstoqueHistorico,
      tableTrocasDevolucoes,
      tableVendasBalcao,
      tableOrdensServico,
      tableEntregas,
      tablePedidos,
      tableServicosRealizados,
      tableOrcamentos,
      tableMesasComandas,
      tableFechamentosCaixa,
      tableAberturasCaixa,
      tableMotoristas,
      tableTaxasEntrega,
      tableServicos,
      tableProdutos,
      tableClientes,
    ];
    
    int totalRemovidos = 0;
    int totalRegistros = 0;
    for (final tabela in tabelas) {
      try {
        // Primeiro contar quantos registros existem para esta empresa
        final countResp = await _client
            .from(tabela)
            .select('id')
            .eq('empresa_id', empresaId)
            .count();
        final count = countResp.count;
        totalRegistros += count;
        
        if (count > 0) {
          await _client.from(tabela).delete().eq('empresa_id', empresaId);
          debugPrint('>>> [Supabase] 🗑️ $tabela: $count registros removidos da empresa $empresaId');
          totalRemovidos++;
        } else {
          debugPrint('>>> [Supabase] ⏭️ $tabela: 0 registros da empresa, pulando...');
        }
      } catch (e) {
        debugPrint('>>> [Supabase] ⚠️ Erro ao limpar $tabela: $e');
      }
    }
    
    debugPrint('>>> [Supabase] ✅ Limpeza concluida: $totalRemovidos tabelas afetadas, $totalRegistros registros removidos da empresa $empresaId');
    return totalRegistros;
  }

  // ============================================================
  // CRIAR TABELAS NO SUPABASE VIA CONEXÃO DIRETA AO POSTGRESQL
  // ============================================================
  /// Conecta diretamente ao PostgreSQL do Supabase (não ao local) e cria todas
  /// as tabelas que o app precisa. Requer que as variáveis SUPABASE_DB_HOST e
  /// SUPABASE_DB_PASSWORD estejam configuradas no .env.
  ///
  /// Retorna (sucesso, mensagens de log).
  /// Cria tabelas no Supabase usando a Management API do Supabase
  /// Requer um Personal Access Token (PAT) do Supabase configurado no .env
  Future<(bool, List<String>)> criarTabelasNoSupabase() async {
    final logs = <String>[];
    final supabaseUrl = SupabaseConfig.url;
    final apiKey = SupabaseConfig.anonKey;

    logs.add('🔌 Verificando e criando tabelas no Supabase...');

    final sqlStatements = _getSqlCriarTabelas();
    int tabelasExistentes = 0;
    int tabelasCriadas = 0;
    int tabelasComErro = 0;
    final List<String> tabelasFaltando = [];

    // Primeiro: verificar quais tabelas já existem
    for (final entry in sqlStatements.entries) {
      final nomeTabela = entry.key;
      try {
        final response = await http.get(
          Uri.parse('$supabaseUrl/rest/v1/$nomeTabela?select=id&limit=1'),
          headers: {
            'apikey': apiKey,
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          tabelasExistentes++;
          logs.add('✅ $nomeTabela: já existe');
        } else {
          tabelasFaltando.add(nomeTabela);
        }
      } catch (e) {
        tabelasFaltando.add(nomeTabela);
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    logs.add('');
    logs.add('📊 $tabelasExistentes tabelas já existem, ${tabelasFaltando.length} precisam ser criadas');

    if (tabelasFaltando.isEmpty) {
      logs.add('✅ Todas as tabelas já existem no Supabase!');
      return (true, logs);
    }

    logs.add('');
    logs.add('🔨 Tentando criar ${tabelasFaltando.length} tabela(s) faltante(s) via RPC...');

    // Tentar criar tabelas faltantes via RPC (executar_sql)
    // Primeiro verificar se a função RPC existe
    bool rpcDisponivel = false;
    try {
      final testResponse = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/rpc/executar_sql'),
        headers: {
          'apikey': apiKey,
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'sql_query': 'SELECT 1'}),
      ).timeout(const Duration(seconds: 5));
      rpcDisponivel = testResponse.statusCode == 200;
    } catch (e) {
      rpcDisponivel = false;
    }

    if (!rpcDisponivel) {
      logs.add('⚠️ Função RPC "executar_sql" não encontrada no Supabase');
      logs.add('');
      logs.add('📋 Para criar tabelas automaticamente, execute UMA ÚNICA VEZ:');
      logs.add('   1. Abra Supabase Dashboard → SQL Editor');
      logs.add('   2. Cole o conteúdo do arquivo CRIAR_FUNCAO_EXECUTAR_SQL.sql');
      logs.add('   3. Clique em Run');
      logs.add('   4. Depois volte aqui e clique novamente neste botão');
      logs.add('');
      logs.add('💡 Enquanto isso, as tabelas faltantes podem ser criadas manualmente:');
      logs.add('   Abra o script CRIAR_TODAS_TABELAS_SUPABASE.sql no SQL Editor');
      return (false, logs);
    }

    logs.add('✅ Função RPC "executar_sql" encontrada! Criando tabelas...');

    for (final nomeTabela in tabelasFaltando) {
      final sql = sqlStatements[nomeTabela];
      if (sql == null) continue;

      try {
        // Dividir SQL em comandos individuais
        final comandos = sql.split(';').where((c) => c.trim().isNotEmpty).toList();
        int ok = 0;
        int erros = 0;

        for (final cmd in comandos) {
          final sqlLimpo = cmd.trim();
          if (sqlLimpo.isEmpty) continue;

          final response = await http.post(
            Uri.parse('$supabaseUrl/rest/v1/rpc/executar_sql'),
            headers: {
              'apikey': apiKey,
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'sql_query': sqlLimpo}),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final body = response.body;
            if (body.contains('ERRO')) {
              erros++;
            } else {
              ok++;
            }
          } else {
            erros++;
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }

        if (ok > 0) {
          tabelasCriadas++;
          logs.add('✅ $nomeTabela: criada ($ok comandos OK' +
              (erros > 0 ? ', $erros ignorados' : '') + ')');
        } else {
          tabelasComErro++;
          logs.add('❌ $nomeTabela: falhou');
        }
      } catch (e) {
        tabelasComErro++;
        logs.add('❌ $nomeTabela: erro — $e');
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    logs.add('');
    logs.add('📊 Resultado: $tabelasExistentes existiam + $tabelasCriadas criadas, $tabelasComErro com erro');

    if (tabelasComErro > 0) {
      logs.add('');
      logs.add('💡 Se alguma tabela falhou, execute o script');
      logs.add('   CRIAR_TODAS_TABELAS_SUPABASE.sql no SQL Editor do Supabase.');
    }

    return (tabelasComErro == 0, logs);
  }

  /// Verifica quais tabelas existem no Supabase
  Future<(bool, Set<String>, List<String>)> verificarTabelasSupabase() async {
    final logs = <String>[];
    final tabelasExistentes = <String>{};

    if (!EnvConfig.supabaseDbAvailable) {
      return (false, tabelasExistentes, ['❌ Variáveis SUPABASE_DB_* não configuradas no .env']);
    }

    Connection? conn;
    try {
      conn = await Connection.open(
        Endpoint(
          host: EnvConfig.supabaseDbHost,
          port: EnvConfig.supabaseDbPort,
          database: EnvConfig.supabaseDbName,
          username: EnvConfig.supabaseDbUser,
          password: EnvConfig.supabaseDbPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.require),
      );

      final result = await conn.execute(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'",
      );

      for (final row in result) {
        tabelasExistentes.add(row[0] as String);
      }

      final tabelasNecessarias = _getSqlCriarTabelas().keys;
      final faltando = tabelasNecessarias.where((t) => !tabelasExistentes.contains(t)).toList();

      if (faltando.isEmpty) {
        logs.add('✅ Todas as ${tabelasNecessarias.length} tabelas necessárias existem no Supabase');
      } else {
        logs.add('⚠️ ${faltando.length} tabela(s) faltando no Supabase: ${faltando.join(', ')}');
      }

      return (true, tabelasExistentes, logs);
    } catch (e) {
      return (false, tabelasExistentes, ['❌ Erro ao verificar tabelas: $e']);
    } finally {
      try { conn?.close(); } catch (_) {}
    }
  }

  /// Mapa de SQL para criar todas as tabelas necessárias no Supabase
  /// Nomes das tabelas que o app usa na nuvem (as mesmas de
  /// [_getSqlCriarTabelas], sem o SQL). Usado pela comparação de esquema que cria
  /// na nuvem as tabelas que só existem no banco local.
  Set<String> get tabelasDoApp => _getSqlCriarTabelas().keys.toSet();

  Map<String, String> _getSqlCriarTabelas() {
    return {
      'produtos': """
        CREATE TABLE IF NOT EXISTS public.produtos (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', nome TEXT DEFAULT '',
          codigo TEXT DEFAULT '', codigo_barras TEXT DEFAULT '', descricao TEXT DEFAULT '',
          preco NUMERIC(15,2) DEFAULT 0, preco_custo NUMERIC(15,2) DEFAULT 0, custo NUMERIC(15,2) DEFAULT 0,
          estoque NUMERIC(15,3) DEFAULT 0, estoque_minimo NUMERIC(15,3) DEFAULT 0,
          unidade TEXT DEFAULT 'UN', ncm TEXT DEFAULT '', cest TEXT DEFAULT '',
          cfop TEXT DEFAULT '', csosn TEXT DEFAULT '', cst TEXT DEFAULT '', origem TEXT DEFAULT '',
          ibpt TEXT DEFAULT '', tipo TEXT DEFAULT 'produto', ativo BOOLEAN DEFAULT true,
          envia_balanca BOOLEAN DEFAULT false, codigo_balanca TEXT DEFAULT '',
          perfil_tributario_id TEXT DEFAULT '',
          precos_por_perfil JSONB DEFAULT '[]'::jsonb, regras_quantidade JSONB DEFAULT '[]'::jsonb,
          departamentos_adicionais JSONB DEFAULT '[]'::jsonb,
          foto_url TEXT DEFAULT '', observacao TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS empresa_id TEXT NOT NULL DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS nome TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS codigo TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS codigo_barras TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS descricao TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS preco NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS preco_custo NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS custo NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS estoque NUMERIC(15,3) DEFAULT 0;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS estoque_minimo NUMERIC(15,3) DEFAULT 0;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS unidade TEXT DEFAULT 'UN';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS ncm TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS cfop TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS csosn TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS cst TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS origem TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS ibpt TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS tipo TEXT DEFAULT 'produto';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS ativo BOOLEAN DEFAULT true;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS envia_balanca BOOLEAN DEFAULT false;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS codigo_balanca TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS perfil_tributario_id TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS precos_por_perfil JSONB DEFAULT '[]'::jsonb;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS regras_quantidade JSONB DEFAULT '[]'::jsonb;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS departamentos_adicionais JSONB DEFAULT '[]'::jsonb;
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS foto_url TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS observacao TEXT DEFAULT '';
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE public.produtos ADD COLUMN IF NOT EXISTS cest TEXT DEFAULT '';
        CREATE INDEX IF NOT EXISTS idx_produtos_empresa ON public.produtos(empresa_id);
        CREATE INDEX IF NOT EXISTS idx_produtos_codigo ON public.produtos(codigo);
        ALTER TABLE public.produtos ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_produtos ON public.produtos;
        CREATE POLICY service_role_produtos ON public.produtos FOR ALL USING (auth.role() = 'service_role');
      """,

      'clientes': """
        CREATE TABLE IF NOT EXISTS public.clientes (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', nome TEXT DEFAULT '',
          cpf_cnpj TEXT DEFAULT '', tipo_pessoa TEXT DEFAULT 'F', email TEXT DEFAULT '',
          telefone TEXT DEFAULT '', celular TEXT DEFAULT '', endereco TEXT DEFAULT '',
          numero TEXT DEFAULT '', complemento TEXT DEFAULT '', bairro TEXT DEFAULT '',
          cidade TEXT DEFAULT '', estado TEXT DEFAULT '', cep TEXT DEFAULT '',
          observacao TEXT DEFAULT '', ativo BOOLEAN DEFAULT true,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_clientes_empresa ON public.clientes(empresa_id);
        ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_clientes ON public.clientes;
        CREATE POLICY service_role_clientes ON public.clientes FOR ALL USING (auth.role() = 'service_role');
      """,

      'orcamentos': """
        CREATE TABLE IF NOT EXISTS public.orcamentos (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', numero TEXT DEFAULT '',
          cliente_id TEXT DEFAULT '', cliente_nome TEXT DEFAULT '',
          cliente_telefone TEXT DEFAULT '', cliente_endereco TEXT DEFAULT '',
          cliente_cpf_cnpj TEXT DEFAULT '', operador TEXT DEFAULT '',
          data_orcamento TIMESTAMPTZ DEFAULT NOW(), validade_orcamento TIMESTAMPTZ,
          status TEXT DEFAULT 'Orçamento', total NUMERIC(15,2) DEFAULT 0,
          desconto_total NUMERIC(15,2) DEFAULT 0, acrescimo_total NUMERIC(15,2) DEFAULT 0,
          observacoes TEXT DEFAULT '', itens JSONB DEFAULT '[]'::jsonb,
          servicos JSONB DEFAULT '[]'::jsonb, delivery_info JSONB,
          pedido_gerado_id TEXT DEFAULT '', pedido_gerado_numero TEXT DEFAULT '',
          data_aprovacao TIMESTAMPTZ,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_orcamentos_empresa ON public.orcamentos(empresa_id);
        CREATE INDEX IF NOT EXISTS idx_orcamentos_status ON public.orcamentos(status);
        ALTER TABLE public.orcamentos ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_orcamentos ON public.orcamentos;
        CREATE POLICY service_role_orcamentos ON public.orcamentos FOR ALL USING (auth.role() = 'service_role');
        GRANT ALL ON TABLE public.orcamentos TO anon, authenticated, service_role;
      """,

      'servicos_realizados': """
        CREATE TABLE IF NOT EXISTS public.servicos_realizados (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', numero TEXT DEFAULT '',
          cliente_id TEXT DEFAULT '', cliente_nome TEXT DEFAULT '',
          cliente_telefone TEXT DEFAULT '', cliente_endereco TEXT DEFAULT '',
          pet_id TEXT DEFAULT '', pet_nome TEXT DEFAULT '', operador TEXT DEFAULT '',
          data_servico TIMESTAMPTZ DEFAULT NOW(), data_conclusao TIMESTAMPTZ,
          data_orcamento TIMESTAMPTZ, validade_orcamento TIMESTAMPTZ,
          status TEXT DEFAULT 'Em Aberto', total NUMERIC(15,2) DEFAULT 0,
          desconto_total NUMERIC(15,2) DEFAULT 0, acrescimo_total NUMERIC(15,2) DEFAULT 0,
          observacoes TEXT DEFAULT '', servicos JSONB DEFAULT '[]'::jsonb,
          pagamentos JSONB DEFAULT '[]'::jsonb,
          materiais_consumidos JSONB DEFAULT '[]'::jsonb,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_servicos_realizados_empresa ON public.servicos_realizados(empresa_id);
        CREATE INDEX IF NOT EXISTS idx_servicos_realizados_status ON public.servicos_realizados(status);
        ALTER TABLE public.servicos_realizados ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_servicos_realizados ON public.servicos_realizados;
        CREATE POLICY service_role_servicos_realizados ON public.servicos_realizados FOR ALL USING (auth.role() = 'service_role');
        GRANT ALL ON TABLE public.servicos_realizados TO anon, authenticated, service_role;
      """,

      'servicos': """
        CREATE TABLE IF NOT EXISTS public.servicos (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', nome TEXT DEFAULT '',
          descricao TEXT DEFAULT '', preco NUMERIC(15,2) DEFAULT 0,
          duracao_minutos INTEGER DEFAULT 30, ativo BOOLEAN DEFAULT true,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_servicos_empresa ON public.servicos(empresa_id);
        ALTER TABLE public.servicos ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_servicos ON public.servicos;
        CREATE POLICY service_role_servicos ON public.servicos FOR ALL USING (auth.role() = 'service_role');
      """,

      'pedidos': """
        CREATE TABLE IF NOT EXISTS public.pedidos (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', numero_pedido INTEGER DEFAULT 0,
          cliente_id TEXT DEFAULT '', cliente_nome TEXT DEFAULT '', mesa_comanda_id TEXT DEFAULT '',
          itens JSONB DEFAULT '[]'::jsonb, subtotal NUMERIC(15,2) DEFAULT 0,
          desconto NUMERIC(15,2) DEFAULT 0, acrescimo NUMERIC(15,2) DEFAULT 0,
          total NUMERIC(15,2) DEFAULT 0, valor_recebido NUMERIC(15,2) DEFAULT 0,
          troco NUMERIC(15,2) DEFAULT 0, forma_pagamento TEXT DEFAULT '',
          status TEXT DEFAULT 'aberto', tipo TEXT DEFAULT 'balcao',
          observacao TEXT DEFAULT '', vendedor TEXT DEFAULT '', operador TEXT DEFAULT '',
          data_pedido TIMESTAMPTZ DEFAULT NOW(), data_recebimento TIMESTAMPTZ,
          data_cancelamento TIMESTAMPTZ, motivo_cancelamento TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS empresa_id TEXT NOT NULL DEFAULT '';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS numero_pedido INTEGER DEFAULT 0;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS cliente_id TEXT DEFAULT '';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS cliente_nome TEXT DEFAULT '';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS mesa_comanda_id TEXT DEFAULT '';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS itens JSONB DEFAULT '[]'::jsonb;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS subtotal NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS desconto NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS acrescimo NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS total NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS valor_recebido NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS troco NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS forma_pagamento TEXT DEFAULT '';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'aberto';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS tipo TEXT DEFAULT 'balcao';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS observacao TEXT DEFAULT '';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS vendedor TEXT DEFAULT '';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS operador TEXT DEFAULT '';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS data_pedido TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS data_recebimento TIMESTAMPTZ;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS data_cancelamento TIMESTAMPTZ;
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS motivo_cancelamento TEXT DEFAULT '';
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
        CREATE INDEX IF NOT EXISTS idx_pedidos_empresa ON public.pedidos(empresa_id);
        CREATE INDEX IF NOT EXISTS idx_pedidos_numero ON public.pedidos(numero_pedido);
        ALTER TABLE public.pedidos ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_pedidos ON public.pedidos;
        CREATE POLICY service_role_pedidos ON public.pedidos FOR ALL USING (auth.role() = 'service_role');
      """,

      'vendas_balcao': """
        CREATE TABLE IF NOT EXISTS public.vendas_balcao (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', numero_venda INTEGER DEFAULT 0,
          cliente_id TEXT DEFAULT '', cliente_nome TEXT DEFAULT '',
          itens JSONB DEFAULT '[]'::jsonb, subtotal NUMERIC(15,2) DEFAULT 0,
          desconto NUMERIC(15,2) DEFAULT 0, acrescimo NUMERIC(15,2) DEFAULT 0,
          total NUMERIC(15,2) DEFAULT 0, valor_recebido NUMERIC(15,2) DEFAULT 0,
          troco NUMERIC(15,2) DEFAULT 0, forma_pagamento TEXT DEFAULT '',
          status TEXT DEFAULT 'finalizada', tipo TEXT DEFAULT 'balcao',
          observacao TEXT DEFAULT '', vendedor TEXT DEFAULT '', operador TEXT DEFAULT '',
          data_venda TIMESTAMPTZ DEFAULT NOW(),
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS empresa_id TEXT NOT NULL DEFAULT '';
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS numero_venda INTEGER DEFAULT 0;
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS cliente_id TEXT DEFAULT '';
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS cliente_nome TEXT DEFAULT '';
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS itens JSONB DEFAULT '[]'::jsonb;
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS subtotal NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS desconto NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS acrescimo NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS total NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS valor_recebido NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS troco NUMERIC(15,2) DEFAULT 0;
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS forma_pagamento TEXT DEFAULT '';
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'finalizada';
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS tipo TEXT DEFAULT 'balcao';
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS observacao TEXT DEFAULT '';
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS vendedor TEXT DEFAULT '';
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS operador TEXT DEFAULT '';
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS data_venda TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE public.vendas_balcao ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
        CREATE INDEX IF NOT EXISTS idx_vendas_balcao_empresa ON public.vendas_balcao(empresa_id);
        ALTER TABLE public.vendas_balcao ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_vendas ON public.vendas_balcao;
        CREATE POLICY service_role_vendas ON public.vendas_balcao FOR ALL USING (auth.role() = 'service_role');
      """,

      'agendamentos_servico': """
        CREATE TABLE IF NOT EXISTS public.agendamentos_servico (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          cliente_id TEXT DEFAULT '', cliente_nome TEXT DEFAULT '', cliente_telefone TEXT DEFAULT '',
          servico_id TEXT DEFAULT '', servico_nome TEXT DEFAULT '',
          funcionario_id TEXT DEFAULT '', funcionario_nome TEXT DEFAULT '',
          data_agendamento TIMESTAMPTZ DEFAULT NOW(), hora_inicio TEXT DEFAULT '',
          hora_fim TEXT DEFAULT '', status TEXT DEFAULT 'agendado',
          valor NUMERIC(15,2) DEFAULT 0, observacao TEXT DEFAULT '',
          pet_id TEXT DEFAULT '', pet_nome TEXT DEFAULT '', notificado BOOLEAN DEFAULT false,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_agendamentos_empresa ON public.agendamentos_servico(empresa_id);
        ALTER TABLE public.agendamentos_servico ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_agendamentos ON public.agendamentos_servico;
        CREATE POLICY service_role_agendamentos ON public.agendamentos_servico FOR ALL USING (auth.role() = 'service_role');
      """,

      'notas_entrada': """
        CREATE TABLE IF NOT EXISTS public.notas_entrada (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', numero_nota TEXT DEFAULT '',
          serie TEXT DEFAULT '', fornecedor_id TEXT DEFAULT '', fornecedor_nome TEXT DEFAULT '',
          fornecedor_cnpj TEXT DEFAULT '', data_entrada TIMESTAMPTZ DEFAULT NOW(),
          data_emissao TIMESTAMPTZ, valor_total NUMERIC(15,2) DEFAULT 0,
          valor_icms NUMERIC(15,2) DEFAULT 0, valor_ipi NUMERIC(15,2) DEFAULT 0,
          valor_pis NUMERIC(15,2) DEFAULT 0, valor_cofins NUMERIC(15,2) DEFAULT 0,
          itens JSONB DEFAULT '[]'::jsonb, status TEXT DEFAULT 'recebida',
          observacao TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_notas_entrada_empresa ON public.notas_entrada(empresa_id);
        ALTER TABLE public.notas_entrada ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_notas_entrada ON public.notas_entrada;
        CREATE POLICY service_role_notas_entrada ON public.notas_entrada FOR ALL USING (auth.role() = 'service_role');
      """,

      'ordens_servico': """
        CREATE TABLE IF NOT EXISTS public.ordens_servico (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', numero_os INTEGER DEFAULT 0,
          cliente_id TEXT DEFAULT '', cliente_nome TEXT DEFAULT '', cliente_telefone TEXT DEFAULT '',
          equipamento TEXT DEFAULT '', defeito TEXT DEFAULT '', observacao TEXT DEFAULT '',
          valor_total NUMERIC(15,2) DEFAULT 0, valor_pago NUMERIC(15,2) DEFAULT 0,
          status TEXT DEFAULT 'aberta', prioridade TEXT DEFAULT 'normal',
          responsavel TEXT DEFAULT '', data_abertura TIMESTAMPTZ DEFAULT NOW(),
          data_previsao TIMESTAMPTZ, data_entrega TIMESTAMPTZ,
          itens JSONB DEFAULT '[]'::jsonb,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_ordens_servico_empresa ON public.ordens_servico(empresa_id);
        ALTER TABLE public.ordens_servico ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_ordens ON public.ordens_servico;
        CREATE POLICY service_role_ordens ON public.ordens_servico FOR ALL USING (auth.role() = 'service_role');
      """,

      'trocas_devolucoes': """
        CREATE TABLE IF NOT EXISTS public.trocas_devolucoes (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          pedido_id TEXT DEFAULT '', venda_id TEXT DEFAULT '', numero_pedido TEXT DEFAULT '',
          cliente_id TEXT DEFAULT '', cliente_nome TEXT DEFAULT '',
          tipo TEXT DEFAULT 'devolucao', motivo TEXT DEFAULT '',
          valor_total NUMERIC(15,2) DEFAULT 0, valor_devolvido NUMERIC(15,2) DEFAULT 0,
          valor_troca NUMERIC(15,2) DEFAULT 0,
          itens_devolvidos JSONB DEFAULT '[]'::jsonb, itens_novos JSONB DEFAULT '[]'::jsonb,
          status TEXT DEFAULT 'finalizada', data_operacao TIMESTAMPTZ DEFAULT NOW(),
          operador TEXT DEFAULT '', observacao TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_trocas_empresa ON public.trocas_devolucoes(empresa_id);
        ALTER TABLE public.trocas_devolucoes ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_trocas ON public.trocas_devolucoes;
        CREATE POLICY service_role_trocas ON public.trocas_devolucoes FOR ALL USING (auth.role() = 'service_role');
      """,

      'funcionarios': """
        CREATE TABLE IF NOT EXISTS public.funcionarios (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '', nome TEXT DEFAULT '',
          cpf TEXT DEFAULT '', cargo TEXT DEFAULT '', email TEXT DEFAULT '',
          telefone TEXT DEFAULT '', comissao_percentual NUMERIC(5,2) DEFAULT 0,
          salario NUMERIC(15,2) DEFAULT 0, ativo BOOLEAN DEFAULT true,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_funcionarios_empresa ON public.funcionarios(empresa_id);
        ALTER TABLE public.funcionarios ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_funcionarios ON public.funcionarios;
        CREATE POLICY service_role_funcionarios ON public.funcionarios FOR ALL USING (auth.role() = 'service_role');
      """,

      'contas_pagar': """
        CREATE TABLE IF NOT EXISTS public.contas_pagar (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          descricao TEXT DEFAULT '', fornecedor TEXT DEFAULT '', categoria TEXT DEFAULT '',
          valor NUMERIC(15,2) DEFAULT 0, data_vencimento TIMESTAMPTZ DEFAULT NOW(),
          data_pagamento TIMESTAMPTZ, status TEXT DEFAULT 'pendente',
          forma_pagamento TEXT DEFAULT '', observacao TEXT DEFAULT '',
          recorrente BOOLEAN DEFAULT false, periodicidade TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_contas_pagar_empresa ON public.contas_pagar(empresa_id);
        ALTER TABLE public.contas_pagar ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_contas ON public.contas_pagar;
        CREATE POLICY service_role_contas ON public.contas_pagar FOR ALL USING (auth.role() = 'service_role');
      """,

      'entregas': """
        CREATE TABLE IF NOT EXISTS public.entregas (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          pedido_id TEXT DEFAULT '', cliente_id TEXT DEFAULT '', cliente_nome TEXT DEFAULT '',
          endereco TEXT DEFAULT '', enderecoEntrega TEXT DEFAULT '',
          bairro TEXT DEFAULT '', cidade TEXT DEFAULT '', complemento TEXT DEFAULT '',
          numero TEXT DEFAULT '', referencia TEXT DEFAULT '',
          latitude NUMERIC(10,7) DEFAULT 0, longitude NUMERIC(10,7) DEFAULT 0,
          motorista_id TEXT DEFAULT '', motorista_nome TEXT DEFAULT '',
          taxa_entrega NUMERIC(15,2) DEFAULT 0, status TEXT DEFAULT 'pendente',
          data_saida TIMESTAMPTZ, data_entrega TIMESTAMPTZ, observacao TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_entregas_empresa ON public.entregas(empresa_id);
        ALTER TABLE public.entregas ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_entregas ON public.entregas;
        CREATE POLICY service_role_entregas ON public.entregas FOR ALL USING (auth.role() = 'service_role');
      """,

      'motoristas': """
        CREATE TABLE IF NOT EXISTS public.motoristas (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          nome TEXT DEFAULT '', cpf TEXT DEFAULT '', telefone TEXT DEFAULT '',
          veiculo TEXT DEFAULT '', placa TEXT DEFAULT '', ativo BOOLEAN DEFAULT true,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_motoristas_empresa ON public.motoristas(empresa_id);
        ALTER TABLE public.motoristas ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_motoristas ON public.motoristas;
        CREATE POLICY service_role_motoristas ON public.motoristas FOR ALL USING (auth.role() = 'service_role');
      """,

      'taxas_entrega': """
        CREATE TABLE IF NOT EXISTS public.taxas_entrega (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          nome TEXT DEFAULT '', bairro TEXT DEFAULT '', valor NUMERIC(15,2) DEFAULT 0,
          tempo_estimado_minutos INTEGER DEFAULT 30, ativo BOOLEAN DEFAULT true,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_taxas_entrega_empresa ON public.taxas_entrega(empresa_id);
        ALTER TABLE public.taxas_entrega ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_taxas ON public.taxas_entrega;
        CREATE POLICY service_role_taxas ON public.taxas_entrega FOR ALL USING (auth.role() = 'service_role');
      """,

      'aberturas_caixa': """
        CREATE TABLE IF NOT EXISTS public.aberturas_caixa (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          responsavel TEXT DEFAULT '', "valorInicial" NUMERIC(15,2) DEFAULT 0,
          "dataAbertura" TIMESTAMPTZ DEFAULT NOW(), observacao TEXT DEFAULT '',
          caixa_numero INTEGER DEFAULT 1,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_aberturas_empresa ON public.aberturas_caixa(empresa_id);
        ALTER TABLE public.aberturas_caixa ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_aberturas ON public.aberturas_caixa;
        CREATE POLICY service_role_aberturas ON public.aberturas_caixa FOR ALL USING (auth.role() = 'service_role');
      """,

      'fechamentos_caixa': """
        CREATE TABLE IF NOT EXISTS public.fechamentos_caixa (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          "aberturaCaixaId" TEXT DEFAULT '', abertura_caixa_id TEXT DEFAULT '',
          responsavel TEXT DEFAULT '', "valorEsperado" NUMERIC(15,2) DEFAULT 0,
          "valorReal" NUMERIC(15,2) DEFAULT 0, diferenca NUMERIC(15,2) DEFAULT 0,
          "dataFechamento" TIMESTAMPTZ DEFAULT NOW(), data_fechamento TIMESTAMPTZ,
          observacao TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_fechamentos_empresa ON public.fechamentos_caixa(empresa_id);
        ALTER TABLE public.fechamentos_caixa ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_fechamentos ON public.fechamentos_caixa;
        CREATE POLICY service_role_fechamentos ON public.fechamentos_caixa FOR ALL USING (auth.role() = 'service_role');
      """,

      'sangrias_caixa': """
        CREATE TABLE IF NOT EXISTS public.sangrias_caixa (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          abertura_caixa_id TEXT DEFAULT '', valor NUMERIC(15,2) DEFAULT 0,
          motivo TEXT DEFAULT '', responsavel TEXT DEFAULT '',
          data_sangria TIMESTAMPTZ DEFAULT NOW(),
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_sangrias_empresa ON public.sangrias_caixa(empresa_id);
        ALTER TABLE public.sangrias_caixa ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_sangrias ON public.sangrias_caixa;
        CREATE POLICY service_role_sangrias ON public.sangrias_caixa FOR ALL USING (auth.role() = 'service_role');
      """,

      'suprimentos_caixa': """
        CREATE TABLE IF NOT EXISTS public.suprimentos_caixa (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          abertura_caixa_id TEXT DEFAULT '', valor NUMERIC(15,2) DEFAULT 0,
          motivo TEXT DEFAULT '', responsavel TEXT DEFAULT '',
          data_suprimento TIMESTAMPTZ DEFAULT NOW(),
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_suprimentos_empresa ON public.suprimentos_caixa(empresa_id);
        ALTER TABLE public.suprimentos_caixa ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_suprimentos ON public.suprimentos_caixa;
        CREATE POLICY service_role_suprimentos ON public.suprimentos_caixa FOR ALL USING (auth.role() = 'service_role');
      """,

      'mesas_comandas': """
        CREATE TABLE IF NOT EXISTS public.mesas_comandas (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          numero TEXT DEFAULT '', nome TEXT DEFAULT '', tipo TEXT DEFAULT 'mesa',
          status TEXT DEFAULT 'Aberta', itens JSONB DEFAULT '[]'::jsonb,
          total NUMERIC(15,2) DEFAULT 0, pessoa_sentada INTEGER DEFAULT 0,
          data_abertura TIMESTAMPTZ DEFAULT NOW(), data_fechamento TIMESTAMPTZ,
          garcom TEXT DEFAULT '', observacao TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_mesas_empresa ON public.mesas_comandas(empresa_id);
        ALTER TABLE public.mesas_comandas ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_mesas ON public.mesas_comandas;
        CREATE POLICY service_role_mesas ON public.mesas_comandas FOR ALL USING (auth.role() = 'service_role');
      """,

      'nfces': """
        CREATE TABLE IF NOT EXISTS public.nfces (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          numero INTEGER DEFAULT 0, serie INTEGER DEFAULT 1,
          chave_acesso TEXT DEFAULT '', protocolo TEXT DEFAULT '',
          data_emissao TIMESTAMPTZ DEFAULT NOW(), valor_total NUMERIC(15,2) DEFAULT 0,
          status TEXT DEFAULT 'pendente', xml TEXT DEFAULT '', recibo TEXT DEFAULT '',
          motivo TEXT DEFAULT '', tipo TEXT DEFAULT 'entrada',
          pedido_id TEXT DEFAULT '', cliente_id TEXT DEFAULT '',
          consumidor_nome TEXT DEFAULT '', consumidor_cpf TEXT DEFAULT '',
          consumidor_cnpj TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_nfces_empresa ON public.nfces(empresa_id);
        ALTER TABLE public.nfces ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_nfces ON public.nfces;
        CREATE POLICY service_role_nfces ON public.nfces FOR ALL USING (auth.role() = 'service_role');
      """,

      'nfes': """
        CREATE TABLE IF NOT EXISTS public.nfes (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          numero INTEGER DEFAULT 0, serie INTEGER DEFAULT 1,
          chave_acesso TEXT DEFAULT '', protocolo TEXT DEFAULT '',
          data_emissao TIMESTAMPTZ DEFAULT NOW(), valor_total NUMERIC(15,2) DEFAULT 0,
          valor_icms NUMERIC(15,2) DEFAULT 0, valor_ipi NUMERIC(15,2) DEFAULT 0,
          valor_pis NUMERIC(15,2) DEFAULT 0, valor_cofins NUMERIC(15,2) DEFAULT 0,
          status TEXT DEFAULT 'pendente', xml TEXT DEFAULT '', recibo TEXT DEFAULT '',
          motivo TEXT DEFAULT '', tipo TEXT DEFAULT 'saida',
          pedido_id TEXT DEFAULT '', cliente_id TEXT DEFAULT '',
          destinatario_nome TEXT DEFAULT '', destinatario_cpf_cnpj TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_nfes_empresa ON public.nfes(empresa_id);
        CREATE INDEX IF NOT EXISTS idx_nfes_chave ON public.nfes(chave_acesso);
        ALTER TABLE public.nfes ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_nfes ON public.nfes;
        CREATE POLICY service_role_nfes ON public.nfes FOR ALL USING (auth.role() = 'service_role');
      """,

      'romaneios': """
        CREATE TABLE IF NOT EXISTS public.romaneios (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          numero_romaneio INTEGER DEFAULT 0, motorista_id TEXT DEFAULT '',
          motorista_nome TEXT DEFAULT '', veiculo TEXT DEFAULT '', placa TEXT DEFAULT '',
          itens JSONB DEFAULT '[]'::jsonb, total_itens INTEGER DEFAULT 0,
          status TEXT DEFAULT 'pendente', data_romaneio TIMESTAMPTZ DEFAULT NOW(),
          data_entrega TIMESTAMPTZ, observacao TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_romaneios_empresa ON public.romaneios(empresa_id);
        ALTER TABLE public.romaneios ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_romaneios ON public.romaneios;
        CREATE POLICY service_role_romaneios ON public.romaneios FOR ALL USING (auth.role() = 'service_role');
      """,

      'comissoes_vendedores': """
        CREATE TABLE IF NOT EXISTS public.comissoes_vendedores (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          vendedor_id TEXT DEFAULT '', vendedor_nome TEXT DEFAULT '',
          venda_id TEXT DEFAULT '', pedido_id TEXT DEFAULT '',
          valor_venda NUMERIC(15,2) DEFAULT 0, percentual_comissao NUMERIC(5,2) DEFAULT 0,
          valor_comissao NUMERIC(15,2) DEFAULT 0, status TEXT DEFAULT 'pendente',
          data_venda TIMESTAMPTZ DEFAULT NOW(), data_pagamento TIMESTAMPTZ,
          observacao TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_comissoes_empresa ON public.comissoes_vendedores(empresa_id);
        ALTER TABLE public.comissoes_vendedores ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_comissoes ON public.comissoes_vendedores;
        CREATE POLICY service_role_comissoes ON public.comissoes_vendedores FOR ALL USING (auth.role() = 'service_role');
      """,

      'links_vendedores': """
        CREATE TABLE IF NOT EXISTS public.links_vendedores (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          vendedor_id TEXT DEFAULT '', vendedor_nome TEXT DEFAULT '',
          link TEXT DEFAULT '', codigo TEXT DEFAULT '', ativo BOOLEAN DEFAULT true,
          cliques INTEGER DEFAULT 0, pedidos_gerados INTEGER DEFAULT 0,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_links_vendedores_empresa ON public.links_vendedores(empresa_id);
        ALTER TABLE public.links_vendedores ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_links ON public.links_vendedores;
        CREATE POLICY service_role_links ON public.links_vendedores FOR ALL USING (auth.role() = 'service_role');
      """,

      'estoque_historico': """
        CREATE TABLE IF NOT EXISTS public.estoque_historico (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          produto_id TEXT DEFAULT '', produto_nome TEXT DEFAULT '',
          tipo_operacao TEXT DEFAULT '', quantidade NUMERIC(15,3) DEFAULT 0,
          estoque_anterior NUMERIC(15,3) DEFAULT 0, estoque_atual NUMERIC(15,3) DEFAULT 0,
          custo_unitario NUMERIC(15,2) DEFAULT 0, valor_total NUMERIC(15,2) DEFAULT 0,
          documento TEXT DEFAULT '', observacao TEXT DEFAULT '',
          data TIMESTAMPTZ DEFAULT NOW(),
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_estoque_historico_empresa ON public.estoque_historico(empresa_id);
        ALTER TABLE public.estoque_historico ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_estoque ON public.estoque_historico;
        CREATE POLICY service_role_estoque ON public.estoque_historico FOR ALL USING (auth.role() = 'service_role');
      """,

      'lotes_produto': """
        CREATE TABLE IF NOT EXISTS public.lotes_produto (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          produto_id TEXT DEFAULT '', produto_nome TEXT DEFAULT '',
          numero_lote TEXT DEFAULT '', quantidade NUMERIC(15,3) DEFAULT 0,
          data_fabricacao TIMESTAMPTZ, data_validade TIMESTAMPTZ,
          fornecedor_id TEXT DEFAULT '', fornecedor_nome TEXT DEFAULT '',
          custo_unitario NUMERIC(15,2) DEFAULT 0, status TEXT DEFAULT 'ativo',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_lotes_empresa ON public.lotes_produto(empresa_id);
        CREATE INDEX IF NOT EXISTS idx_lotes_produto ON public.lotes_produto(produto_id);
        ALTER TABLE public.lotes_produto ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_lotes ON public.lotes_produto;
        CREATE POLICY service_role_lotes ON public.lotes_produto FOR ALL USING (auth.role() = 'service_role');
      """,

      'produto_historico': """
        CREATE TABLE IF NOT EXISTS public.produto_historico (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          produto_id TEXT DEFAULT '', produto_nome TEXT DEFAULT '',
          tipo_operacao TEXT DEFAULT 'UPDATE',
          dados_anteriores JSONB DEFAULT '{}'::jsonb, dados_novos JSONB DEFAULT '{}'::jsonb,
          usuario_id TEXT DEFAULT '', usuario_nome TEXT DEFAULT '',
          data_alteracao TIMESTAMPTZ DEFAULT NOW(),
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_produto_historico_empresa ON public.produto_historico(empresa_id);
        ALTER TABLE public.produto_historico ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_produto_historico ON public.produto_historico;
        CREATE POLICY service_role_produto_historico ON public.produto_historico FOR ALL USING (auth.role() = 'service_role');
      """,

      'perfis_tributarios': """
        CREATE TABLE IF NOT EXISTS public.perfis_tributarios (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          nome TEXT DEFAULT '', descricao TEXT DEFAULT '',
          icms NUMERIC(5,2) DEFAULT 0, icms_st NUMERIC(5,2) DEFAULT 0,
          ipi NUMERIC(5,2) DEFAULT 0, pis NUMERIC(5,2) DEFAULT 0,
          cofins NUMERIC(5,2) DEFAULT 0, cfop TEXT DEFAULT '',
          csosn TEXT DEFAULT '', cst TEXT DEFAULT '', origem TEXT DEFAULT '',
          mva NUMERIC(5,2) DEFAULT 0, fcp NUMERIC(5,2) DEFAULT 0,
          ativo BOOLEAN DEFAULT true,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_perfis_tributarios_empresa ON public.perfis_tributarios(empresa_id);
        ALTER TABLE public.perfis_tributarios ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_perfis ON public.perfis_tributarios;
        CREATE POLICY service_role_perfis ON public.perfis_tributarios FOR ALL USING (auth.role() = 'service_role');
      """,

      'departamentos': """
        CREATE TABLE IF NOT EXISTS public.departamentos (
          id TEXT PRIMARY KEY, empresa_id TEXT NOT NULL DEFAULT '',
          nome TEXT DEFAULT '', descricao TEXT DEFAULT '',
          cor TEXT DEFAULT '', icone TEXT DEFAULT '', ordem INTEGER DEFAULT 0,
          ativo BOOLEAN DEFAULT true,
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_departamentos_empresa ON public.departamentos(empresa_id);
        ALTER TABLE public.departamentos ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS service_role_departamentos ON public.departamentos;
        CREATE POLICY service_role_departamentos ON public.departamentos FOR ALL USING (auth.role() = 'service_role');
      """,
    };
  }
}

