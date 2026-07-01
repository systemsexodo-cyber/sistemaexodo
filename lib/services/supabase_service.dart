import 'dart:async';
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
  final _client = Supabase.instance.client;

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
      debugPrint('>>> [Supabase] ✅ Inicializado com sucesso.');
      
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
  static const String tableAberturasCaixa = 'aberturas_caixa';
  static const String tableFechamentosCaixa = 'fechamentos_caixa';
  static const String tableMotoristas = 'motoristas';
  static const String tableAgendamentosServico = 'agendamentos_servico';
  static const String tableNotasEntrada = 'notas_entrada';
  static const String tableFuncionarios = 'funcionarios';
  static const String tableTaxasEntrega = 'taxas_entrega';
  static const String tableContasPagar = 'contas_pagar';
  static const String tableNFCes = 'nfces';
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
        tableAberturasCaixa: 'aberturas_caixa',
        tableFechamentosCaixa: 'fechamentos_caixa',
        tableMotoristas: 'motoristas',
        tableAgendamentosServico: 'agendamentos_servico',
        tableNotasEntrada: 'notas_entrada',
        tableFuncionarios: 'funcionarios',
        tableTaxasEntrega: 'taxas_entrega',
        tableContasPagar: 'contas_pagar',
        tableNFCes: 'nfces',
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
            } else if (tableName == tablePedidos || tableName == tableVendasBalcao) {
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
          debugPrint('>>> [Supabase] ❌ Erro ao carregar $tableName: $e');
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
    required List<AberturaCaixa> aberturasCaixa,
    required List<FechamentoCaixa> fechamentosCaixa,
    required List<Motorista> motoristas,
    required List<AgendamentoServico> agendamentosServico,
    required List<NotaEntrada> notasEntrada,
    required List<Funcionario> funcionarios,
    required List<TaxaEntrega> taxasEntrega,
    required List<ContaPagar> contasPagar,
    required List<NFCe> nfces,
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
        tableAberturasCaixa: aberturasCaixa,
        tableFechamentosCaixa: fechamentosCaixa,
        tableMotoristas: motoristas,
        tableAgendamentosServico: agendamentosServico,
        tableNotasEntrada: notasEntrada,
        tableFuncionarios: funcionarios,
        tableTaxasEntrega: taxasEntrega,
        tableContasPagar: contasPagar,
        tableNFCes: nfces,
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
            await _client.from(table).upsert(chunk);
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
      await _client.from(table).upsert(data);
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
      
      final testData = {
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
      
      final response = await _client.from(tableProdutos).upsert([testData]).select();
      
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
      
      final response = await _client.from(table).insert(dataToInsert).select().single().timeout(const Duration(seconds: 8));
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
      
      Map<String, dynamic> dataToUpsert = Map<String, dynamic>.from(data);
      if (table == tableEmpresas) {
        dataToUpsert.remove('telas_permitidas');
        dataToUpsert.remove('observacao');
        dataToUpsert.remove('cor_primaria');
        dataToUpsert.remove('cor_secundaria');
      }
      
      await _client.from(table).upsert(dataToUpsert).timeout(const Duration(seconds: 8));
      debugPrint('>>> [Supabase] ✅ Upsert concluído em $table');
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao fazer upsert em $table: $e');
      rethrow;
    }
  }

  /// Realiza upsert de múltiplos itens em uma tabela (Batch)
  Future<void> upsertLote(String table, List<Map<String, dynamic>> data) async {
    try {
      if (!isAvailable || data.isEmpty) return;
      
      // OTIMIZAÇÃO: Batching para grandes volumes
      const int batchSize = 500;
      
      List<Map<String, dynamic>> enrichedData = data.map((map) {
        if (table == tableEmpresas) {
          final m = Map<String, dynamic>.from(map);
          m.remove('telas_permitidas');
          m.remove('observacao');
          m.remove('cor_primaria');
          m.remove('cor_secundaria');
          return m;
        }
        return map;
      }).toList();
      
      if (enrichedData.length > batchSize) {
        debugPrint('>>> [Supabase] 📦 Fracionando upsert de ${enrichedData.length} itens em lotes de $batchSize...');
        for (int i = 0; i < enrichedData.length; i += batchSize) {
          final end = (i + batchSize < enrichedData.length) ? i + batchSize : enrichedData.length;
          final chunk = enrichedData.sublist(i, end);
          await _client.from(table).upsert(chunk).timeout(const Duration(seconds: 15));
        }
      } else {
        await _client.from(table).upsert(enrichedData).timeout(const Duration(seconds: 15));
      }
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao fazer upsertLote em $table: $e');
      rethrow;
    }
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
