import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import 'env_config.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Connection? _pgConnection;
  Future<Connection>? _pgConnectionFuture;
  String? _empresaId;

  Future<void> _dbQueue = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _dbQueue = _dbQueue.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // Active PostgreSQL Connection
  Future<Connection> get connection async {
    // 1. Se já temos uma conexão ativa que passa no teste, usamos ela.
    if (_pgConnection != null) {
      try {
        await _pgConnection!.execute('SELECT 1');
        return _pgConnection!;
      } catch (_) {
        try {
          _pgConnection!.close();
        } catch (_) {}
        _pgConnection = null;
        _pgConnectionFuture = null;
      }
    }

    // 2. Se já há uma tentativa de conexão em andamento, aguardamos ela.
    if (_pgConnectionFuture != null) {
      try {
        final conn = await _pgConnectionFuture!;
        await conn.execute('SELECT 1');
        _pgConnection = conn;
        return conn;
      } catch (_) {
        try {
          final conn = await _pgConnectionFuture!;
          conn.close();
        } catch (_) {}
        _pgConnection = null;
        _pgConnectionFuture = null;
      }
    }

    // 3. Caso contrário, iniciamos uma nova tentativa de conexão.
    _pgConnectionFuture = _connect();
    try {
      final conn = await _pgConnectionFuture!;
      _pgConnection = conn;
      return conn;
    } catch (e) {
      try {
        final conn = await _pgConnectionFuture!;
        conn.close();
      } catch (_) {}
      _pgConnection = null;
      _pgConnectionFuture = null;
      rethrow;
    }
  }

  Future<Connection> _connect() async {
    debugPrint('>>> [PostgreSQL] 🔌 Conectando ao PostgreSQL local...');
    
    // Auto-mapeamento de localhost para 127.0.0.1 para evitar falhas de DNS quando offline no Windows
    String host = EnvConfig.dbHost;
    if (host.toLowerCase() == 'localhost') {
      host = '127.0.0.1';
    }
    
    final conn = await Connection.open(
      Endpoint(
        host: host,
        port: EnvConfig.dbPort,
        database: EnvConfig.dbName,
        username: EnvConfig.dbUser,
        password: EnvConfig.dbPassword,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    debugPrint('>>> [PostgreSQL] ✅ Conectado com sucesso.');
    await _inicializarColunas(conn);
    return conn;
  }

  void setEmpresaId(String empresaId) {
    _empresaId = empresaId;
    debugPrint('>>> [PostgreSQL] 🏢 Empresa definida: $empresaId');
  }

  String? get empresaId => _empresaId;

  // Cache de Colunas e Tipos do Banco
  final Map<String, Map<String, String>> _tableColumnTypes = {};

  Future<void> _inicializarColunas(Connection conn) async {
    try {
      await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS envia_balanca BOOLEAN DEFAULT FALSE;');
      // Garantir que a coluna esteja no cache local caso o cache já tenha sido carregado
      if (_tableColumnTypes.containsKey('produtos')) {
        _tableColumnTypes['produtos']!['envia_balanca'] = 'BOOLEAN';
      }
      
      // ÍNDICES DE ALTO DESEMPENHO (Otimização para grandes volumes de dados)
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_produtos_empresa_id ON produtos(empresa_id);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_produtos_nome ON produtos(nome);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_produtos_codigo ON produtos(codigo);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_clientes_empresa_id ON clientes(empresa_id);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_clientes_nome ON clientes(nome);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_empresa_id ON pedidos(empresa_id);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_vendas_balcao_empresa_id ON vendas_balcao(empresa_id);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_estoque_historico_empresa_id ON estoque_historico(empresa_id);');
      
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ⚠️ Erro ao executar migrations de performance/balança: $e');
    }

    if (_tableColumnTypes.isNotEmpty) return;
    try {
      final results = await conn.execute(
        "SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = 'public'"
      );
      for (final row in results) {
        final tableName = row[0] as String;
        final columnName = row[1] as String;
        final dataType = row[2] as String;
        _tableColumnTypes.putIfAbsent(tableName, () => {})[columnName] = dataType.toUpperCase();
      }
      debugPrint('>>> [PostgreSQL] ✅ Schema cache carregado para ${_tableColumnTypes.length} tabelas.');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao inicializar colunas: $e');
    }
  }

  Future<void> _garantirCacheDados(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS cache_dados (
          chave TEXT PRIMARY KEY,
          valor_json TEXT,
          ultima_atualizacao TEXT
        )
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir cache_dados: $e');
    }
  }

  String? _mapearChaveParaTabela(String chave) {
    if (chave.contains('produtos')) return 'produtos';
    if (chave.contains('clientes')) return 'clientes';
    if (chave.contains('pedidos')) return 'pedidos';
    if (chave.contains('notas_entrada')) return 'notas_entrada';
    if (chave.contains('ordens_servico')) return 'ordens_servico';
    if (chave.contains('trocas_devolucoes')) return 'trocas_devolucoes';
    if (chave.contains('vendas_balcao') || chave.contains('vendas')) return 'vendas_balcao';
    if (chave.contains('mesas_comandas') || chave.contains('mesas')) return 'mesas_comandas';
    if (chave.contains('agendamentos')) return 'agendamentos_servico';
    if (chave.contains('servicos')) return 'servicos';
    if (chave.contains('funcionarios')) return 'funcionarios';
    if (chave.contains('motoristas')) return 'motoristas';
    if (chave.contains('entregas')) return 'entregas';
    if (chave.contains('romaneios')) return 'romaneios';
    if (chave.contains('taxas_entrega')) return 'taxas_entrega';
    if (chave.contains('nfces')) return 'nfces';
    if (chave.contains('comissoes_vendedores')) return 'comissoes_vendedores';
    if (chave.contains('contas_pagar')) return 'contas_pagar';
    if (chave.contains('estoque_historico')) return 'estoque_historico';
    if (chave.contains('aberturas_caixa')) return 'aberturas_caixa';
    if (chave.contains('fechamentos_caixa')) return 'fechamentos_caixa';
    if (chave.contains('sangrias_caixa') || chave.contains('sangrias')) return 'sangrias_caixa';
    if (chave.contains('suprimentos_caixa') || chave.contains('suprimentos')) return 'suprimentos_caixa';
    if (chave.contains('produto_historico')) return 'produto_historico';
    if (chave.contains('links_vendedores')) return 'links_vendedores';
    return null;
  }

  Future<void> salvarLista(String chave, List<Map<String, dynamic>> lista, {bool isSync = false}) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(chave);
      try {
        final conn = await connection;
        if (tabela == null) {
          // Chave genérica: salvar no cache_dados
          await _salvarCacheDados(conn, chave, lista);
          return;
        }

        await _inicializarColunas(conn);
        
        // PERF FIX: Removido o DELETE completo da tabela antes do upsert.
        // O ON CONFLICT (id) DO UPDATE já lida com atualizações de registros existentes.
        // Exclusões devem ser tratadas via removerItemPostgres() individualmente.
        // O DELETE completo causava lentidão severa (deletava e re-inseria centenas de linhas
        // a cada operação de save, inclusive na finalização de venda).

        await _upsertRows(conn, tabela, lista, isSync: isSync);
        debugPrint('>>> [PostgreSQL] ✅ Dados salvos na tabela $tabela (${lista.length} itens)');
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao salvar lista $chave: $e');
      }
    });
  }

  /// Upsert rápido de um único item (sem fila, com timeout).
  /// Usado na finalização de venda para não bloquear a UI.
  Future<void> upsertItem(String chave, Map<String, dynamic> item) async {
    final tabela = _mapearChaveParaTabela(chave);
    if (tabela == null) return;
    try {
      final conn = await connection.timeout(const Duration(seconds: 5));
      await _inicializarColunas(conn);
      await _upsertRows(conn, tabela, [item]);
      debugPrint('>>> [PostgreSQL] ⚡ Upsert rápido: $tabela (id=${item['id']})');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ⚠️ Erro no upsert rápido de $chave: $e');
      // Não relançar: o salvarLista via debounce vai garantir consistência
    }
  }

  Future<void> _salvarCacheDados(Connection conn, String chave, List<Map<String, dynamic>> lista) async {
    await _garantirCacheDados(conn);
    await conn.execute(
      Sql.named('''
        INSERT INTO cache_dados (chave, valor_json, ultima_atualizacao)
        VALUES (@chave, @valor_json, @ultima_atualizacao)
        ON CONFLICT (chave) DO UPDATE SET 
          valor_json = EXCLUDED.valor_json,
          ultima_atualizacao = EXCLUDED.ultima_atualizacao
      '''),
      parameters: {
        'chave': chave,
        'valor_json': jsonEncode(lista),
        'ultima_atualizacao': DateTime.now().toIso8601String()
      }
    );
  }

  Future<void> _upsertRows(Connection conn, String tabela, List<Map<String, dynamic>> lista, {bool isSync = false}) async {
    final columns = _tableColumnTypes[tabela];
    if (columns == null || columns.isEmpty) {
      debugPrint('>>> [PostgreSQL] ⚠️ Tabela $tabela não encontrada no schema cache.');
      return;
    }

    final chunkSize = 200;
    for (var i = 0; i < lista.length; i += chunkSize) {
      final end = (i + chunkSize < lista.length) ? i + chunkSize : lista.length;
      final chunk = lista.sublist(i, end);

      await conn.runTx((session) async {
        await session.execute("SET LOCAL exodo.sync_mode = '${isSync ? 'on' : 'off'}';");
        for (final item in chunk) {
          // Filtrar apenas chaves que existem na tabela (com fallback camelCase -> snake_case)
          final rowMap = <String, dynamic>{};
          for (final entry in item.entries) {
            var k = entry.key;
            if (!columns.containsKey(k)) {
              final snake = k.replaceAllMapped(RegExp(r'([A-Z])'), (m) => '_${m.group(1)!.toLowerCase()}');
              if (columns.containsKey(snake)) {
                k = snake;
              }
            }
            if (columns.containsKey(k)) {
              rowMap[k] = entry.value;
            }
          }

          if (!rowMap.containsKey('id') || rowMap['id'] == null) {
            continue;
          }

          // Se empresa_id estiver no schema e não preenchido, preenchemos
          if (columns.containsKey('empresa_id') && (rowMap['empresa_id'] == null || rowMap['empresa_id'].toString().isEmpty)) {
            rowMap['empresa_id'] = _empresaId;
          }

          final colNames = rowMap.keys.toList();
          final colsSql = colNames.map((c) => '"$c"').join(', ');
          
          final valsSqlList = <String>[];
          final params = <String, dynamic>{};
          for (final k in colNames) {
            final type = columns[k] ?? '';
            if (type.contains('JSON')) {
              valsSqlList.add('@$k::jsonb');
              params[k] = rowMap[k] is String ? rowMap[k] : jsonEncode(rowMap[k]);
            } else if (type.contains('TIMESTAMP') || type.contains('DATE')) {
              valsSqlList.add('@$k');
              var val = rowMap[k];
              if (val is DateTime) {
                params[k] = val.toIso8601String();
              } else if (val is num) {
                params[k] = DateTime.fromMillisecondsSinceEpoch(val.toInt()).toIso8601String();
              } else {
                params[k] = val;
              }
            } else {
              valsSqlList.add('@$k');
              params[k] = rowMap[k];
            }
          }
          
          final valsSql = valsSqlList.join(', ');
          final updSql = colNames
              .where((c) => c != 'id')
              .map((c) => '"$c" = EXCLUDED."$c"')
              .join(', ');

          final sql = '''
            INSERT INTO "$tabela" ($colsSql)
            VALUES ($valsSql)
            ON CONFLICT (id) DO UPDATE SET $updSql
          ''';

          await session.execute(Sql.named(sql), parameters: params);
        }
      });
    }
  }

  Future<void> adicionarProdutosLote(List<Map<String, dynamic>> produtos) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _inicializarColunas(conn);
        await _upsertRows(conn, 'produtos', produtos);
        debugPrint('>>> [PostgreSQL] ✅ Lote de ${produtos.length} produtos adicionado.');
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao adicionar lote de produtos: $e');
      }
    });
  }

  Future<List<Map<String, dynamic>>> carregarLista(String chave) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(chave);
      try {
        final conn = await connection;
        if (tabela == null) {
          await _garantirCacheDados(conn);
          final result = await conn.execute(
            Sql.named('SELECT valor_json FROM cache_dados WHERE chave = @chave'),
            parameters: {'chave': chave}
          );
          if (result.isEmpty) return [];
          final valorJson = result.first[0] as String?;
          if (valorJson == null || valorJson.isEmpty) return [];
          final decoded = jsonDecode(valorJson);
          if (decoded is List) {
            return decoded.cast<Map<String, dynamic>>();
          }
          return [];
        }

        await _inicializarColunas(conn);
        String sql = 'SELECT * FROM "$tabela"';
        final params = <String, dynamic>{};
        
        final columns = _tableColumnTypes[tabela];
        if (_empresaId != null && _empresaId!.isNotEmpty && columns != null && columns.containsKey('empresa_id')) {
          sql += ' WHERE empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }
        
        if (tabela == 'vendas_balcao' || tabela == 'pedidos') {
          sql += ' ORDER BY created_at DESC';
        }

        final result = await conn.execute(Sql.named(sql), parameters: params);
        final list = <Map<String, dynamic>>[];
        for (final row in result) {
          list.add(row.toColumnMap());
        }
        return list;
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao carregar $chave: $e');
        return [];
      }
    });
  }

  Future<List<Map<String, dynamic>>> buscarProdutos(String termo) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _inicializarColunas(conn);
        
        String whereClause = "(nome ILIKE @queryTermo OR codigo ILIKE @queryTermo OR codigo ILIKE @prefixTermo)";
        final params = <String, dynamic>{
          'queryTermo': '%$termo%',
          'prefixTermo': 'COD-$termo%',
          'termo': termo,
        };

        if (_empresaId != null && _empresaId!.isNotEmpty) {
          whereClause += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }

        final sql = '''
          SELECT * FROM produtos
          WHERE $whereClause
          ORDER BY 
            CASE 
              WHEN codigo = @termo THEN 1
              WHEN codigo = 'COD-' || @termo THEN 1
              WHEN codigo LIKE @termo || '%' THEN 2
              WHEN codigo LIKE 'COD-' || @termo || '%' THEN 2
              WHEN nome ILIKE @termo || ' %' THEN 3
              ELSE 4
            END, nome ASC
          LIMIT 100
        ''';

        final result = await conn.execute(Sql.named(sql), parameters: params);
        return result.map((r) => r.toColumnMap()).toList();
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro na busca de produtos: $e');
        return [];
      }
    });
  }

  Future<Map<String, dynamic>?> obterProdutoPorId(String id) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _inicializarColunas(conn);
        
        String whereClause = 'id = @id';
        final params = <String, dynamic>{'id': id};
        
        if (_empresaId != null && _empresaId!.isNotEmpty) {
          whereClause += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }
        
        final result = await conn.execute(
          Sql.named('SELECT * FROM produtos WHERE $whereClause LIMIT 1'),
          parameters: params
        );
        if (result.isEmpty) return null;
        return result.first.toColumnMap();
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao obter produto por ID: $e');
        return null;
      }
    });
  }

  Future<void> atualizarEstoqueLocal(String id, double novoEstoque) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        String whereClause = 'id = @id';
        final params = <String, dynamic>{'id': id, 'estoque': novoEstoque};
        
        if (_empresaId != null && _empresaId!.isNotEmpty) {
          whereClause += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }
        
        await conn.execute(
          Sql.named('UPDATE produtos SET estoque = @estoque WHERE $whereClause'),
          parameters: params
        );
        debugPrint('>>> [PostgreSQL] ✅ Estoque do produto $id atualizado para $novoEstoque no PostgreSQL local.');
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao atualizar estoque: $e');
      }
    });
  }

  Future<void> limparTabela(String tabelaChave) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(tabelaChave) ?? tabelaChave;
      try {
        final conn = await connection;
        String sql = 'DELETE FROM "$tabela"';
        final params = <String, dynamic>{};
        
        final columns = _tableColumnTypes[tabela];
        if (_empresaId != null && _empresaId!.isNotEmpty && columns != null && columns.containsKey('empresa_id')) {
          sql += ' WHERE empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }
        
        await conn.execute(Sql.named(sql), parameters: params);
        debugPrint('>>> [PostgreSQL] 🗑️ Tabela $tabela limpa');
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao limpar tabela $tabela: $e');
      }
    });
  }

  // --- MÉTODOS DE HISTÓRICO DE PRODUTOS ---

  Future<void> salvarHistoricoProduto(Map<String, dynamic> historico) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _inicializarColunas(conn);
        await _upsertRows(conn, 'produto_historico', [historico]);
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao salvar histórico de produto: $e');
      }
    });
  }

  Future<List<Map<String, dynamic>>> buscarHistoricoProduto(String produtoId, {int limite = 50}) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        String sql = 'SELECT * FROM produto_historico WHERE produto_id = @produtoId';
        final params = <String, dynamic>{'produtoId': produtoId, 'limite': limite};
        
        if (_empresaId != null && _empresaId!.isNotEmpty) {
          sql += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }
        
        sql += ' ORDER BY data_alteracao DESC LIMIT @limite';
        final result = await conn.execute(Sql.named(sql), parameters: params);
        return result.map((r) => r.toColumnMap()).toList();
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao buscar histórico de produto: $e');
        return [];
      }
    });
  }

  Future<List<Map<String, dynamic>>> buscarHistoricoGeral({int limite = 100, DateTime? dataInicio, DateTime? dataFim}) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        String sql = 'SELECT * FROM produto_historico WHERE 1=1';
        final params = <String, dynamic>{'limite': limite};
        
        if (_empresaId != null && _empresaId!.isNotEmpty) {
          sql += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }
        if (dataInicio != null) {
          sql += ' AND data_alteracao >= @dataInicio';
          params['dataInicio'] = dataInicio.toIso8601String();
        }
        if (dataFim != null) {
          sql += ' AND data_alteracao <= @dataFim';
          params['dataFim'] = dataFim.toIso8601String();
        }
        
        sql += ' ORDER BY data_alteracao DESC LIMIT @limite';
        final result = await conn.execute(Sql.named(sql), parameters: params);
        return result.map((r) => r.toColumnMap()).toList();
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao buscar histórico geral: $e');
        return [];
      }
    });
  }

  Future<List<Map<String, dynamic>>> buscarHistoricoPorUsuario(String usuarioId, {int limite = 50}) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        String sql = 'SELECT * FROM produto_historico WHERE usuario_id = @usuarioId';
        final params = <String, dynamic>{'usuarioId': usuarioId, 'limite': limite};
        
        if (_empresaId != null && _empresaId!.isNotEmpty) {
          sql += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }
        
        sql += ' ORDER BY data_alteracao DESC LIMIT @limite';
        final result = await conn.execute(Sql.named(sql), parameters: params);
        return result.map((r) => r.toColumnMap()).toList();
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao buscar histórico por usuário: $e');
        return [];
      }
    });
  }

  Future<void> marcarHistoricoSincronizado(List<String> ids) async {
    // Tratado nativamente no PostgreSQL local pelas triggers da fila de sincronia
  }

  Future<List<Map<String, dynamic>>> buscarHistoricoNaoSincronizado({int limite = 100}) async {
    // Tratado nativamente no PostgreSQL local pela tabela _exodo_sync_log
    return [];
  }

  // --- MÉTODOS DE SUPORTE NFC-E ---

  Future<void> atualizarStatusNFCe(String nfceId, String status) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await conn.execute(
          Sql.named('UPDATE nfces SET status = @status, updated_at = @now WHERE id = @id'),
          parameters: {
            'id': nfceId,
            'status': status,
            'now': DateTime.now().toIso8601String()
          }
        );
        debugPrint('>>> [PostgreSQL] ✅ Status da NFC-e $nfceId atualizado para $status');
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao atualizar status da NFC-e: $e');
      }
    });
  }

  // --- MÉTODOS DE SUPORTE REALTIME ---

  Future<void> removerItemPostgres(String tableKey, String id, String? empresaId) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(tableKey) ?? tableKey;
      try {
        final conn = await connection;
        String sql = 'DELETE FROM "$tabela" WHERE id = @id';
        final params = <String, dynamic>{'id': id};
        
        if (empresaId != null && empresaId.isNotEmpty) {
          final columns = _tableColumnTypes[tabela];
          if (columns != null && columns.containsKey('empresa_id')) {
            sql += ' AND empresa_id = @empresaId';
            params['empresaId'] = empresaId;
          }
        }
        
        await conn.execute(Sql.named(sql), parameters: params);
        debugPrint('>>> [PostgreSQL] 🗑️ DELETE local aplicado na tabela $tabela para ID=$id');
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao remover item da tabela $tabela: $e');
      }
    });
  }
}
