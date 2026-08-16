import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  void _verificarEResetarConexao(Object error) {
    final errStr = error.toString().toLowerCase();
    if (errStr.contains('connection is closing') ||
        errStr.contains('closed') ||
        errStr.contains('socketexception') ||
        errStr.contains('handshake') ||
        errStr.contains('connection refused') ||
        errStr.contains('broken pipe')) {
      debugPrint('>>> [PostgreSQL] ⚠️ Conexão inválida detectada ($error). Resetando cache de conexões...');
      try {
        _pgConnection?.close();
      } catch (_) {}
      _pgConnection = null;
      _pgConnectionFuture = null;
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _dbQueue = _dbQueue.then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        _verificarEResetarConexao(e);
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // Active PostgreSQL Connection
  Future<Connection> get connection async {
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

  bool _colunasInicializadas = false;
  final Map<String, Map<String, String>> _tableColumnTypes = {};

  Future<void> _inicializarColunas(Connection conn) async {
    if (_colunasInicializadas && _tableColumnTypes.isNotEmpty) return;

    if (!_colunasInicializadas) {
      _colunasInicializadas = true;
      try {
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS envia_balanca BOOLEAN DEFAULT FALSE;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS perfil_tributario_id VARCHAR;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS perguntas_selecao JSONB;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS exibir_composicao_pdv BOOLEAN DEFAULT FALSE;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS baixar_estoque_proprio BOOLEAN DEFAULT TRUE;');
        await conn.execute('ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS abertura_caixa_id VARCHAR;');
        await conn.execute('ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS abertura_caixa_id VARCHAR;');
        await conn.execute('ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS numero VARCHAR;');
        await conn.execute('ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS senha VARCHAR;');
        await conn.execute('ALTER TABLE vendas_balcao ADD COLUMN IF NOT EXISTS senha VARCHAR;');
        await conn.execute('ALTER TABLE empresas ADD COLUMN IF NOT EXISTS configuracoes JSONB;');
        await conn.execute('ALTER TABLE empresas ADD COLUMN IF NOT EXISTS perfis_de_preco JSONB;');
        await conn.execute('ALTER TABLE empresas ADD COLUMN IF NOT EXISTS "perfisDePreco" JSONB;');
        await conn.execute('ALTER TABLE clientes ADD COLUMN IF NOT EXISTS perfil_preco VARCHAR;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS precos_por_perfil JSONB;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS regras_quantidade JSONB;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS promocoes JSONB;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS impressora_producao VARCHAR;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS impressora_producao_extra JSONB;');
        await conn.execute("ALTER TABLE produtos ADD COLUMN IF NOT EXISTS unidade_venda VARCHAR DEFAULT 'unidade';");
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS quantidade_baixa NUMERIC DEFAULT 1;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS formas_venda JSONB;');
        await conn.execute('ALTER TABLE produtos ADD COLUMN IF NOT EXISTS departamento_id VARCHAR;');

        // Garantir tabelas de monitoramento
        await _garantirSyncStatus(conn);
        await _garantirSyncLogs(conn);
        await _garantirNfes(conn);
        await _garantirExodoConfig(conn);
        await _garantirLotesProduto(conn);

        // Histórico de estoque: preservar fornecedor/observação/usuario localmente
        await conn.execute('ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS fornecedor_nome TEXT;');
        await conn.execute('ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS fornecedor_id TEXT;');
        await conn.execute('ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS observacao TEXT;');
        await conn.execute('ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS usuario TEXT;');
        // Custo da mercadoria na movimentação (quebras/perdas precisam registrar o valor de custo)
        await conn.execute('ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS custo_unitario NUMERIC;');
        await conn.execute('ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS valor_custo NUMERIC;');

        _tableColumnTypes.clear();

        await conn.execute('CREATE INDEX IF NOT EXISTS idx_produtos_empresa_id ON produtos(empresa_id);');
        await conn.execute('CREATE INDEX IF NOT EXISTS idx_produtos_nome ON produtos(nome);');
        await conn.execute('CREATE INDEX IF NOT EXISTS idx_produtos_codigo ON produtos(codigo);');
        await conn.execute('CREATE INDEX IF NOT EXISTS idx_clientes_empresa_id ON clientes(empresa_id);');
        await conn.execute('CREATE INDEX IF NOT EXISTS idx_clientes_nome ON clientes(nome);');
        await conn.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_empresa_id ON pedidos(empresa_id);');
        await conn.execute('CREATE INDEX IF NOT EXISTS idx_vendas_balcao_empresa_id ON vendas_balcao(empresa_id);');
        await conn.execute('CREATE INDEX IF NOT EXISTS idx_estoque_historico_empresa_id ON estoque_historico(empresa_id);');
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ⚠️ Erro ao executar migrations: $e');
        _colunasInicializadas = false;
      }
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
      debugPrint('>>> [PostgreSQL] ✅ Schema cache carregado para ${_tableColumnTypes.length} tabelas (com colunas novas).');
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

  Future<void> _garantirExodoConfig(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS exodo_config (
          chave TEXT PRIMARY KEY,
          valor TEXT NOT NULL,
          updated_at TIMESTAMP DEFAULT NOW()
        )
      ''');
      await conn.execute('DROP TRIGGER IF EXISTS trg_exodo_sync_log_exodo_config ON exodo_config;');
      await conn.execute('DROP TRIGGER IF EXISTS trg_exodo_sync_log_sync_status ON sync_status;');
      await conn.execute('DROP TRIGGER IF EXISTS trg_exodo_sync_log_configuracoes_locais ON configuracoes_locais;');
      await conn.execute('DROP TRIGGER IF EXISTS trg_exodo_sync_log_sync_logs ON sync_logs;');

      await conn.execute(r'''
        CREATE OR REPLACE FUNCTION public.log_sync_event() RETURNS trigger
        LANGUAGE plpgsql AS $$
        DECLARE
            rec_id text;
        BEGIN
            IF current_setting('exodo.sync_mode', true) = 'on' THEN
                IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
            END IF;

            IF TG_OP = 'UPDATE' AND (NEW IS NOT DISTINCT FROM OLD) THEN
                RETURN NEW;
            END IF;

            IF TG_OP = 'DELETE' THEN
                rec_id := COALESCE(to_jsonb(OLD)->>'id', to_jsonb(OLD)->>'chave', to_jsonb(OLD)->>'key', to_jsonb(OLD)->>'empresa_id');
                IF rec_id IS NOT NULL THEN
                    INSERT INTO _exodo_sync_log (table_name, record_id, operation)
                    VALUES (TG_TABLE_NAME, rec_id, TG_OP)
                    ON CONFLICT (table_name, record_id)
                    DO UPDATE SET operation = EXCLUDED.operation, created_at = NOW();
                    PERFORM pg_notify('exodo_sync_event', TG_TABLE_NAME);
                END IF;
                RETURN OLD;
            ELSE
                rec_id := COALESCE(to_jsonb(NEW)->>'id', to_jsonb(NEW)->>'chave', to_jsonb(NEW)->>'key', to_jsonb(NEW)->>'empresa_id');
                IF rec_id IS NOT NULL THEN
                    INSERT INTO _exodo_sync_log (table_name, record_id, operation)
                    VALUES (TG_TABLE_NAME, rec_id, TG_OP)
                    ON CONFLICT (table_name, record_id)
                    DO UPDATE SET operation = EXCLUDED.operation, created_at = NOW();
                    PERFORM pg_notify('exodo_sync_event', TG_TABLE_NAME);
                END IF;
                RETURN NEW;
            END IF;
        END;
        $$;
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir exodo_config: $e');
    }
  }

  Future<void> _garantirSyncStatus(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS sync_status (
          empresa_id TEXT PRIMARY KEY,
          pc_name TEXT NOT NULL DEFAULT '',
          ultima_sincronizacao TIMESTAMPTZ,
          ultimo_erro TEXT DEFAULT '',
          ultimo_erro_data TIMESTAMPTZ,
          fila_pendente INT DEFAULT 0,
          versao_app TEXT DEFAULT '',
          online BOOLEAN DEFAULT false,
          online_data TIMESTAMPTZ,
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      await conn.execute('''
        CREATE INDEX IF NOT EXISTS idx_sync_status_online ON sync_status(online)
      ''');
      await conn.execute('''
        CREATE INDEX IF NOT EXISTS idx_sync_status_updated ON sync_status(updated_at DESC)
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir sync_status: $e');
    }
  }

  Future<void> _garantirSyncLogs(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS sync_logs (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          empresa_id TEXT NOT NULL DEFAULT '',
          pc_name TEXT NOT NULL DEFAULT '',
          evento TEXT NOT NULL DEFAULT '',
          detalhes TEXT DEFAULT '',
          erro TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      await conn.execute('''
        CREATE INDEX IF NOT EXISTS idx_sync_logs_empresa_id ON sync_logs(empresa_id)
      ''');
      await conn.execute('''
        CREATE INDEX IF NOT EXISTS idx_sync_logs_created_at ON sync_logs(created_at DESC)
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir sync_logs: $e');
    }
  }

  Future<void> _garantirLotesProduto(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS lotes_produto (
          id TEXT PRIMARY KEY,
          produto_id TEXT NOT NULL DEFAULT '',
          numero_lote TEXT DEFAULT '',
          fornecedor_id TEXT DEFAULT '',
          fornecedor_nome TEXT DEFAULT '',
          data_fabricacao TIMESTAMPTZ,
          data_validade TIMESTAMPTZ,
          quantidade NUMERIC DEFAULT 0,
          empresa_id TEXT NOT NULL DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      // Lote atrelado ao fornecedor: garante as colunas em bancos já existentes
      await conn.execute('ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS fornecedor_id TEXT DEFAULT \'\';');
      await conn.execute('ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS fornecedor_nome TEXT DEFAULT \'\';');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_lotes_produto_empresa_id ON lotes_produto(empresa_id);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_lotes_produto_produto_id ON lotes_produto(produto_id);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_lotes_produto_data_validade ON lotes_produto(data_validade);');

      await conn.execute('DROP TRIGGER IF EXISTS trg_exodo_sync_log_lotes_produto ON lotes_produto;');
      await conn.execute('''
        CREATE TRIGGER trg_exodo_sync_log_lotes_produto
        AFTER INSERT OR DELETE OR UPDATE ON public.lotes_produto
        FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir lotes_produto: $e');
    }
  }

  Future<void> _garantirNfes(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS nfes (
          id TEXT PRIMARY KEY,
          numero TEXT,
          serie TEXT,
          data_emissao TIMESTAMPTZ,
          empresa_id TEXT NOT NULL DEFAULT '',
          itens JSONB,
          valor_total NUMERIC,
          cpf_cnpj_consumidor TEXT,
          nome_consumidor TEXT,
          pagamentos JSONB,
          chave_acesso TEXT,
          protocolo TEXT,
          modelo INT DEFAULT 55,
          status TEXT,
          xml_enviado TEXT,
          xml_retorno TEXT,
          qr_code TEXT,
          venda_id TEXT,
          venda_numero TEXT,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_nfes_empresa_id ON nfes(empresa_id);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_nfes_numero ON nfes(numero);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_nfes_chave_acesso ON nfes(chave_acesso);');
      await conn.execute('CREATE INDEX IF NOT EXISTS idx_nfes_created_at ON nfes(created_at DESC);');

      await conn.execute('DROP TRIGGER IF EXISTS trg_exodo_sync_log_nfes ON nfes;');
      await conn.execute('''
        CREATE TRIGGER trg_exodo_sync_log_nfes
        AFTER INSERT OR DELETE OR UPDATE ON public.nfes
        FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir nfes: $e');
    }
  }

  /// Remove caracteres que o Postgres local (encoding WIN1252) não consegue
  /// armazenar — emojis como ✅/⚠️/🚀 (bytes 0xE2 0x9C 0x85...) estouram o
  /// erro 22P05 ao salvar sync_logs. Caracteres Latin-1 (á, ç, ã) são mantidos.
  String _sanitizarWin1252(String texto) {
    final buffer = StringBuffer();
    const indefinidos = {0x81, 0x8D, 0x8F, 0x90, 0x9D};
    for (final rune in texto.runes) {
      final ok = (rune >= 0x20 && rune <= 0x7E) ||
          (rune >= 0x80 && rune <= 0x9F && !indefinidos.contains(rune)) ||
          (rune >= 0xA0 && rune <= 0xFF);
      buffer.writeCharCode(ok ? rune : 0x3F); // '?'
    }
    return buffer.toString();
  }

  Future<void> salvarConfig(String chave, dynamic valor) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _garantirExodoConfig(conn);
        final valorStr = valor is String ? valor : jsonEncode(_jsonSafe(valor));
        final valorSeguro = _sanitizarWin1252(valorStr);
        await conn.execute(
          Sql.named('''
            INSERT INTO exodo_config (chave, valor, updated_at)
            VALUES (@chave, @valor, @now)
            ON CONFLICT (chave) DO UPDATE SET 
              valor = EXCLUDED.valor,
              updated_at = EXCLUDED.updated_at
          '''),
          parameters: <String, Object?>{
            'chave': chave,
            'valor': valorSeguro,
            'now': DateTime.now().toUtc().toIso8601String(),
          }
        );
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao salvar config $chave: $e');
      }
    });
  }

  Future<dynamic> carregarConfig(String chave) async {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _garantirExodoConfig(conn);
        final result = await conn.execute(
          Sql.named('SELECT valor FROM exodo_config WHERE chave = @chave'),
          parameters: <String, Object?>{'chave': chave}
        );
        if (result.isEmpty) return null;
        final valor = result.first[0] as String;
        if (valor.startsWith('[') || valor.startsWith('{')) {
          try {
            return jsonDecode(valor);
          } catch (_) {}
        }
        return valor;
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao carregar config $chave: $e');
        return null;
      }
    });
  }

  Future<void> removerConfig(String chave) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await conn.execute(
          Sql.named('DELETE FROM exodo_config WHERE chave = @chave'),
          parameters: <String, Object?>{'chave': chave}
        );
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao remover config $chave: $e');
      }
    });
  }

  Future<void> salvarSyncLogs(String empresaId, List<String> logs) async {
    await salvarConfig('sync_logs_$empresaId', logs);
  }

  Future<List<String>> carregarSyncLogs(String empresaId) async {
    final valor = await carregarConfig('sync_logs_$empresaId');
    if (valor is List) {
      return valor.map((e) => e.toString()).toList();
    }
    return [];
  }

  dynamic _jsonSafe(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toIso8601String();
    if (value is num || value is String || value is bool) return value;
    if (value is Map) {
      final normalized = <String, dynamic>{};
      for (final entry in value.entries) {
        normalized[entry.key.toString()] = _jsonSafe(entry.value);
      }
      return normalized;
    }
    if (value is List) {
      return value.map(_jsonSafe).toList();
    }
    if (value is Set) {
      return value.map(_jsonSafe).toList();
    }
    return value.toString();
  }

  String? _mapearChaveParaTabela(String chave) {
    // ⚠️ ORDEM IMPORTANTE: 'exodo_lotes_produtos' contém a substring 'produtos'.
    // O check de 'lotes_produtos' DEVE vir antes de 'produtos', senão o lote
    // era gravado na tabela 'produtos' (nome null) e travava o sincronizador
    // (erro 23502 'null value in column nome').
    if (chave.contains('lotes_produtos')) return 'lotes_produto';
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
    if (chave.contains('nfes')) return 'nfes';
    if (chave.contains('comissoes_vendedores')) return 'comissoes_vendedores';
    if (chave.contains('contas_pagar')) return 'contas_pagar';
    if (chave.contains('estoque_historico')) return 'estoque_historico';
    if (chave.contains('aberturas_caixa')) return 'aberturas_caixa';
    if (chave.contains('fechamentos_caixa')) return 'fechamentos_caixa';
    if (chave.contains('sangrias_caixa') || chave.contains('sangrias')) return 'sangrias_caixa';
    if (chave.contains('suprimentos_caixa') || chave.contains('suprimentos')) return 'suprimentos_caixa';
    if (chave.contains('produto_historico')) return 'produto_historico';
    if (chave.contains('links_vendedores')) return 'links_vendedores';
    if (chave == 'empresas') return 'empresas';
    return null;
  }

  Future<void> salvarLista(String chave, List<Map<String, dynamic>> lista, {bool isSync = false}) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(chave);
      try {
        final conn = await connection;
        if (tabela == null) {
          await _salvarCacheDados(conn, chave, lista);
          return;
        }
        await _inicializarColunas(conn);
        await _upsertRows(conn, tabela, lista, isSync: isSync);
        debugPrint('>>> [PostgreSQL] ✅ Dados salvos na tabela $tabela (${lista.length} itens)');
      } catch (e, st) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao salvar lista $chave: $e');
        debugPrint('>>> [PostgreSQL] 🧵 Stack trace: $st');
      }
    });
  }

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
    }
  }

  Future<void> _salvarCacheDados(Connection conn, String chave, List<Map<String, dynamic>> lista) async {
    await _garantirCacheDados(conn);
    final payload = _jsonSafe(lista);
    await conn.execute(
      Sql.named('''
        INSERT INTO cache_dados (chave, valor_json, ultima_atualizacao)
        VALUES (@chave, @valor_json, @ultima_atualizacao)
        ON CONFLICT (chave) DO UPDATE SET 
          valor_json = EXCLUDED.valor_json,
          ultima_atualizacao = EXCLUDED.ultima_atualizacao
      '''),
      parameters: <String, Object?>{
        'chave': chave,
        'valor_json': jsonEncode(payload),
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

    final chunkSize = 100;
    for (var i = 0; i < lista.length; i += chunkSize) {
      final end = (i + chunkSize < lista.length) ? i + chunkSize : lista.length;
      final chunk = lista.sublist(i, end);

      await conn.runTx((session) async {
        await session.execute("SET LOCAL exodo.sync_mode = '${isSync ? 'on' : 'off'}';");

        final normalizedChunk = <Map<String, dynamic>>[];
        final Set<String> allCols = {};

        for (final item in chunk) {
          final rowMap = <String, dynamic>{};
          for (final entry in item.entries) {
            var k = entry.key;
            if (!columns.containsKey(k)) {
              final snake = k.replaceAllMapped(RegExp(r'([A-Z])'), (m) => '_${m.group(1)!.toLowerCase()}');
              if (columns.containsKey(snake)) {
                k = snake;
              } else if (k.contains('_')) {
                final parts = k.split('_');
                final camel = parts[0] + parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
                if (columns.containsKey(camel)) {
                  k = camel;
                }
              }
            }
            if (columns.containsKey(k)) {
              rowMap[k] = entry.value;
            }
          }

          if (!rowMap.containsKey('id') || rowMap['id'] == null) {
            continue;
          }

          // Preencher empresa_id automaticamente, mas NUNCA gravar NULL quando a
          // empresa ainda não estiver definida — senão o registro fica invisível
          // para o app (carregarLista filtra por empresa_id) e vendas/caixas
          // "desaparecem" (era o caso das aberturas de caixa do carlos).
          if (columns.containsKey('empresa_id') && (rowMap['empresa_id'] == null || rowMap['empresa_id'].toString().isEmpty)) {
            if (_empresaId != null && _empresaId!.isNotEmpty) {
              rowMap['empresa_id'] = _empresaId;
            } else {
              rowMap.remove('empresa_id');
            }
          }

          normalizedChunk.add(rowMap);
          allCols.addAll(rowMap.keys);
        }

        if (normalizedChunk.isEmpty) return;

        final colList = allCols.toList();
        final colsSql = colList.map((c) => '\"$c\"').join(', ');
        final valsSqlRows = <String>[];
        final params = <String, Object?>{};

        for (var rowIndex = 0; rowIndex < normalizedChunk.length; rowIndex++) {
          final rowMap = normalizedChunk[rowIndex];
          final rowValsSql = <String>[];

          for (final k in colList) {
            final paramName = 'v_${rowIndex}_$k';
            final type = columns[k] ?? '';
            final val = rowMap[k];

            if (type.contains('JSON')) {
              rowValsSql.add('@$paramName::jsonb');
              // Sanitizar WIN1252: emoji em qualquer campo (ex.: nome de produto
              // com 🐶) faz o Postgres local estourar 22P05 e a LISTA INTEIRA
              // falhar. O caractere nem caberia no encoding de qualquer forma.
              params[paramName] = val == null
                  ? null
                  : _sanitizarWin1252(val is String ? val : jsonEncode(_jsonSafe(val)));
            } else if (type.contains('TIMESTAMP') || type.contains('DATE')) {
              rowValsSql.add('@$paramName');
              if (val == null) {
                params[paramName] = null;
              } else if (val is DateTime) {
                params[paramName] = val.toUtc().toIso8601String();
              } else if (val is num) {
                params[paramName] = DateTime.fromMillisecondsSinceEpoch(val.toInt()).toUtc().toIso8601String();
              } else if (val is String) {
                final parsed = DateTime.tryParse(val);
                params[paramName] = parsed != null ? parsed.toUtc().toIso8601String() : val;
              } else {
                params[paramName] = val;
              }
            } else {
              rowValsSql.add('@$paramName');
              if (val == null) {
                params[paramName] = null;
              } else {
                var finalVal = val;
                if (type.contains('INT') || type.contains('BIGINT')) {
                  if (finalVal is double) finalVal = finalVal.toInt();
                  else if (finalVal is num) finalVal = finalVal.toInt();
                  else if (finalVal is String) finalVal = double.tryParse(finalVal)?.toInt() ?? 0;
                } else if (type.contains('NUMERIC') || type.contains('DECIMAL') || type.contains('DOUBLE')) {
                  if (finalVal is int) finalVal = finalVal.toDouble();
                  else if (finalVal is num) finalVal = finalVal.toDouble();
                  else if (finalVal is String) finalVal = double.tryParse(finalVal) ?? 0.0;
                }

                if (finalVal is List || finalVal is Map) {
                  params[paramName] = _sanitizarWin1252(jsonEncode(_jsonSafe(finalVal)));
                } else if (finalVal is String) {
                  params[paramName] = _sanitizarWin1252(finalVal);
                } else {
                  params[paramName] = finalVal;
                }
              }
            }
          }
          valsSqlRows.add('(${rowValsSql.join(", ")})');
        }

        final updSql = colList
            .where((c) => c != 'id')
            .map((c) => '"$c" = EXCLUDED."$c"')
            .join(', ');

        final sql = '''
          INSERT INTO "$tabela" ($colsSql)
          VALUES ${valsSqlRows.join(", ")}
          ON CONFLICT (id) DO UPDATE SET $updSql
        ''';

        await session.execute(Sql.named(sql), parameters: params);
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

  Future<void> salvarEmpresaLocal(Map<String, dynamic> empresaMap) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _inicializarColunas(conn);

        await conn.execute(
          'ALTER TABLE empresas ADD COLUMN IF NOT EXISTS configuracoes JSONB;'
        );
        await conn.execute(
          'ALTER TABLE empresas ADD COLUMN IF NOT EXISTS perfis_de_preco JSONB;'
        );
        _tableColumnTypes['empresas'] ??= {};
        _tableColumnTypes['empresas']!['configuracoes'] = 'JSONB';
        _tableColumnTypes['empresas']!['perfis_de_preco'] = 'JSONB';

        final id = empresaMap['id']?.toString();
        if (id == null || id.isEmpty) {
          debugPrint('>>> [PostgreSQL] ⚠️ Empresa sem ID, não salvo.');
          return;
        }

        final configJson = empresaMap['configuracoes'] != null
            ? jsonEncode(_jsonSafe(empresaMap['configuracoes']))
            : null;
        final perfisJson = empresaMap['perfisDePreco'] != null
            ? jsonEncode(_jsonSafe(empresaMap['perfisDePreco']))
            : null;

        await _upsertRows(conn, 'empresas', [empresaMap]);

        if (configJson != null) {
          await conn.execute(
            Sql.named(
              'UPDATE empresas SET configuracoes = @config::jsonb WHERE id = @id'
            ),
            parameters: <String, Object?>{'config': configJson, 'id': id},
          );
          debugPrint('>>> [PostgreSQL] ✅ configuracoes da empresa salvas (${configJson.length} chars).');
        }
        if (perfisJson != null) {
          await conn.execute(
            Sql.named(
              'UPDATE empresas SET perfis_de_preco = @perfis::jsonb WHERE id = @id'
            ),
            parameters: <String, Object?>{'perfis': perfisJson, 'id': id},
          );
        }
        debugPrint('>>> [PostgreSQL] ✅ Empresa salva localmente com sucesso.');
      } catch (e, st) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao salvar empresa local: $e');
        debugPrint('>>> [PostgreSQL] Stack: $st');
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
            parameters: <String, Object?>{'chave': chave}
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
        final params = <String, Object?>{};

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
          final rowMap = row.toColumnMap();
          final convertedMap = <String, dynamic>{};
          for (final entry in rowMap.entries) {
            var k = entry.key;
            if (k.contains('_')) {
              final parts = k.split('_');
              k = parts[0] + parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
            }

            var val = entry.value;

            if (val is String && columns != null) {
              final colType = columns[entry.key]?.toUpperCase() ?? '';
              if (colType.contains('NUMERIC') || colType.contains('DECIMAL') || colType.contains('REAL') || colType.contains('DOUBLE')) {
                val = num.tryParse(val) ?? val;
              }
            }

            if (val is String && (val.startsWith('[') || val.startsWith('{'))) {
              try {
                val = jsonDecode(val);
              } catch (_) {}
            }
            if (convertedMap.containsKey(k)) {
              if (val != null) {
                convertedMap[k] = val;
              }
            } else {
              convertedMap[k] = val;
            }
          }
          list.add(convertedMap);
        }
        return list;
      } catch (e, st) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao carregar $tabela: $e');
        try {
          final file = File('crash_db.txt');
          file.writeAsStringSync('Erro na tabela $tabela: $e\\n$st\\n', mode: FileMode.append);
        } catch (_) {}
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
        final params = <String, Object?>{
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
        final params = <String, Object?>{'id': id};

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
        final params = <String, Object?>{'id': id, 'estoque': novoEstoque};

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
        final params = <String, Object?>{};

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
        final params = <String, Object?>{'produtoId': produtoId, 'limite': limite};

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
        final params = <String, Object?>{'limite': limite};

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
        final params = <String, Object?>{'usuarioId': usuarioId, 'limite': limite};

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

  Future<void> marcarHistoricoSincronizado(List<String> ids) async {}

  Future<List<Map<String, dynamic>>> buscarHistoricoNaoSincronizado({int limite = 100}) async {
    return [];
  }

  Future<void> atualizarStatusNFCe(String nfceId, String status) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await conn.execute(
          Sql.named('UPDATE nfces SET status = @status, updated_at = @now WHERE id = @id'),
          parameters: <String, Object?>{
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

  Future<void> removerItemPostgres(String tableKey, String id, String? empresaId, {bool isSync = false}) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(tableKey) ?? tableKey;
      try {
        final conn = await connection;
        await conn.runTx((session) async {
          await session.execute("SET LOCAL exodo.sync_mode = '${isSync ? 'on' : 'off'}';");
          String sql = 'DELETE FROM "$tabela" WHERE id = @id';
          final params = <String, Object?>{'id': id};

          if (empresaId != null && empresaId.isNotEmpty) {
            final columns = _tableColumnTypes[tabela];
            if (columns != null && columns.containsKey('empresa_id')) {
              sql += ' AND empresa_id = @empresaId';
              params['empresaId'] = empresaId;
            }
          }

          await session.execute(Sql.named(sql), parameters: params);
        });
        debugPrint('>>> [PostgreSQL] 🗑️ DELETE local aplicado na tabela $tabela para ID=$id (isSync: $isSync)');
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao remover item da tabela $tabela: $e');
      }
    });
  }
}
