import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';
import '../utils/win1252.dart';
import 'env_config.dart';
// No Web a configuração vai para o Hive (mesmo armazenamento das listas);
// nas outras plataformas cai no stub vazio e o PostgreSQL é quem grava.
import 'local_storage_service_stub.dart'
    if (dart.library.html) 'local_storage_service_web_stub.dart';
import 'postgres_local_starter.dart';
import 'process_utils.dart';

/// Motivo da falha do banco local, já classificado.
///
/// Existe para o texto LONGO ([DatabaseService.dicaDoErroLocal], que vai no
/// tooltip e no log) e o rótulo CURTO ([DatabaseService.rotuloCurtoDoErroLocal],
/// que vai no chip do topo) saírem da MESMA classificação — assim os dois nunca
/// dizem coisas diferentes sobre o mesmo erro.
enum _MotivoFalhaLocal {
  semResposta,
  senha,
  desligado,
  lento,
  naoExiste,
  generico,
}

/// Um banco candidato na ordem de tentativa de conexão.
///
/// O celular começa pelo PC da loja (nome), depois o IP e, por último, a
/// nuvem configurada em `DB_CLOUD_*` (usada quando o aparelho está fora da
/// loja). Quem responder primeiro vence.
class _DestinoBanco {
  const _DestinoBanco({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    required this.ssl,
    required this.timeout,
    this.directTls = false,
  });

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final SslMode ssl;

  /// Quando true, o TLS é negociado imediatamente (sem o `SSLRequest` do
  /// PostgreSQL). Necessário para o Funnel, que espera TLS como primeiros bytes.
  final bool directTls;

  /// Quanto esperar por ESTE destino antes de passar para o próximo.
  final Duration timeout;
}

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
      debugPrint(
        '>>> [PostgreSQL] ⚠️ Conexão inválida detectada ($error). Resetando cache de conexões...',
      );
      try {
        _pgConnection?.close();
      } catch (_) {}
      _pgConnection = null;
      _pgConnectionFuture = null;
    }
  }

  /// Fecha e esquece a conexão atual.
  ///
  /// Usado quando o endereço do banco muda (tela "Configurar servidor" no
  /// celular): sem isso, o app continuaria preso à conexão antiga até fechar.
  void resetarConexao() {
    try {
      _pgConnection?.close();
    } catch (_) {}
    _pgConnection = null;
    _pgConnectionFuture = null;
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
      if (_pgConnection!.isOpen) {
        return _pgConnection!;
      } else {
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
        if (conn.isOpen) {
          _pgConnection = conn;
          return conn;
        } else {
          try {
            conn.close();
          } catch (_) {}
          _pgConnection = null;
          _pgConnectionFuture = null;
        }
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
    debugPrint('>>> [PostgreSQL] 🔌 Conectando...');

    // Ordem de tentativa (a primeira que responder vence):
    //   1. DB_HOST           -> nome do PC (ex.: DESKTOP-86UT1R1)
    //   2. DB_HOST_FALLBACK  -> IP do PC (Android não resolve nome sem DNS local)
    //   3. DB_CLOUD_HOST     -> nuvem (quando o celular está fora da loja)
    final destinos = _destinos();

    Future<Connection> abrir() async {
      Object? ultimoErro;
      for (final d in destinos) {
        try {
          return await Connection.open(
            Endpoint(
              host: d.host,
              port: d.port,
              database: d.database,
              username: d.username,
              password: d.password,
            ),
            settings: ConnectionSettings(
              sslMode: d.ssl,
              directTls: d.directTls,
            ),
          ).timeout(d.timeout);
        } catch (e) {
          ultimoErro = e;
          if (destinos.length > 1) {
            debugPrint(
              '>>> [PostgreSQL] "${d.host}:${d.port}" não respondeu '
              '($e). Tentando o próximo...',
            );
          }
        }
      }
      throw ultimoErro ??
          Exception('Nenhum endereço de PostgreSQL configurado');
    }

    Connection conn;
    try {
      conn = await abrir();
    } catch (e) {
      if (_classificarFalhaLocal(e) == _MotivoFalhaLocal.desligado) {
        // SERVIÇO PARADO: "connection refused" significa que o PostgreSQL
        // DESTE computador está desligado. Sem ligar, toda leitura devolve
        // lista vazia e as telas abrem sem os dados locais (principalmente o
        // Fluxo de Caixa). O próprio app tenta subir o serviço e reconectar.
        final (iniciado, mensagem) = await PostgresLocalStarter.tentarIniciar();
        debugPrint('>>> [PostgreSQL] $mensagem');
        if (!iniciado) rethrow;
        conn = await abrir();
      } else if (_erroDeBancoInexistente(e)) {
        // Banco apagado (ou instalação que parou no meio): cria o banco e as
        // tabelas sozinho, em vez de deixar o sistema sem abrir.
        debugPrint(
          '>>> [PostgreSQL] 🏗️ O banco "${EnvConfig.dbName}" não existe. Criando agora...',
        );
        final (criado, _) = await criarBancoLocal();
        if (!criado) rethrow;
        conn = await abrir();
      } else {
        rethrow;
      }
    }

    debugPrint('>>> [PostgreSQL] ✅ Conectado com sucesso.');
    // A conexão voltou: uma nova queda merece nova tentativa de auto-start na
    // hora, sem esperar o intervalo mínimo entre tentativas.
    PostgresLocalStarter.registrarConexaoOk();
    await _inicializarColunas(conn);
    await _aplicarMigracoesNoBoot(conn);
    return conn;
  }

  /// Monta a lista de bancos a tentar, na ordem: PC (nome), PC (IP), nuvem.
  List<_DestinoBanco> _destinos() {
    final lista = <_DestinoBanco>[
      _DestinoBanco(
        host: _hostLocal(),
        port: EnvConfig.dbPort,
        database: EnvConfig.dbName,
        username: EnvConfig.dbUser,
        password: EnvConfig.dbPassword,
        ssl: SslMode.disable,
        timeout: const Duration(seconds: 4),
      ),
    ];

    final ip = _hostFallback();
    if (ip.isNotEmpty && ip != lista.first.host) {
      lista.add(
        _DestinoBanco(
          host: ip,
          port: EnvConfig.dbPort,
          database: EnvConfig.dbName,
          username: EnvConfig.dbUser,
          password: EnvConfig.dbPassword,
          ssl: SslMode.disable,
          timeout: const Duration(seconds: 4),
        ),
      );
    }

    final nuvem = EnvConfig.dbCloudHost;
    if (nuvem.isNotEmpty) {
      lista.add(
        _DestinoBanco(
          host: nuvem,
          port: EnvConfig.dbCloudPort,
          database: EnvConfig.dbCloudName,
          username: EnvConfig.dbCloudUser,
          password: EnvConfig.dbCloudPassword,
          ssl: EnvConfig.dbCloudSsl ? SslMode.require : SslMode.disable,
          directTls: EnvConfig.dbCloudSsl,
          timeout: const Duration(seconds: 15),
        ),
      );
    }

    return lista;
  }

  /// Host do PostgreSQL local. `localhost` vira `127.0.0.1` para o driver não
  /// tentar IPv6 (que não existe neste servidor).
  String _hostLocal() {
    final host = EnvConfig.dbHost;
    return host.toLowerCase() == 'localhost' ? '127.0.0.1' : host;
  }

  /// IP de reserva quando o nome configurado em `DB_HOST` não resolve na rede.
  String _hostFallback() {
    final host = EnvConfig.dbHostFallback;
    return host.toLowerCase() == 'localhost' ? '127.0.0.1' : host;
  }

  /// Nome entre aspas duplas, do jeito que o PostgreSQL aceita.
  static String _aspasIdentificador(String nome) =>
      '"${nome.replaceAll('"', '""')}"';

  /// Banco de manutenção usado para criar o banco do app (sempre existe).
  static const String _bancoManutencao = 'postgres';

  /// true quando o erro é "o banco não existe" (SQLSTATE 3D000).
  ///
  /// O servidor pode responder em inglês ou em português, então além do código
  /// oficial também conferimos o texto da mensagem.
  bool _erroDeBancoInexistente(Object erro) {
    if (erro is ServerException && erro.code == '3D000') return true;
    final texto = erro.toString().toLowerCase();
    final falouDoBanco =
        texto.contains('3d000') ||
        texto.contains('database') ||
        texto.contains('banco de dados');
    final naoExiste =
        texto.contains('does not exist') ||
        texto.contains('não existe') ||
        texto.contains('nao existe');
    return falouDoBanco && naoExiste;
  }

  /// Cria o banco local (`DB_NAME`) e roda o `scripts/init_db.sql` nele.
  ///
  /// É o `reparar_banco.bat` dentro do app: serve para quando o banco do
  /// PostgreSQL foi apagado (ou a instalação parou no meio). O app já chama
  /// isto sozinho quando não consegue conectar por banco inexistente.
  ///
  /// É idempotente: com o banco já existente só garante as tabelas (o
  /// `init_db.sql` cria o que falta e não mexe no que já existe).
  ///
  /// Devolve (sucesso, logs) para a tela mostrar o passo a passo.
  Future<(bool, List<String>)> criarBancoLocal({
    void Function(String)? onProgress,
  }) async {
    final logs = <String>[];
    void log(String mensagem) {
      logs.add(mensagem);
      debugPrint('>>> [PostgreSQL] $mensagem');
      onProgress?.call(mensagem);
    }

    if (kIsWeb) {
      log('⚠️ Criar o banco local não está disponível na versão Web.');
      return (false, logs);
    }

    final host = _hostLocal();
    final banco = EnvConfig.dbName;

    // 1. Criar o banco (só se não existir) pela conexão de manutenção.
    Connection? manutencao;
    try {
      manutencao = await Connection.open(
        Endpoint(
          host: host,
          port: EnvConfig.dbPort,
          database: _bancoManutencao,
          username: EnvConfig.dbUser,
          password: EnvConfig.dbPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );

      final jaExiste = await manutencao.execute(
        Sql.named('SELECT 1 FROM pg_database WHERE datname = @nome'),
        parameters: <String, Object?>{'nome': banco},
      );

      if (jaExiste.isNotEmpty) {
        log('ℹ️ O banco "$banco" já existe.');
      } else {
        // CREATE DATABASE não pode rodar dentro de um bloco de transação; no
        // protocolo simples (o mesmo que o psql usa) isso está garantido.
        await manutencao.execute(
          'CREATE DATABASE ${_aspasIdentificador(banco)} '
          'OWNER ${_aspasIdentificador(EnvConfig.dbUser)}',
          queryMode: QueryMode.simple,
        );
        log('✅ Banco "$banco" criado em $host:${EnvConfig.dbPort}.');
      }
    } on ServerException catch (e) {
      if (e.code == '3D000') {
        log(
          '❌ O banco de manutenção "$_bancoManutencao" não existe neste PostgreSQL.',
        );
      } else if (e.code == '42501' || e.code == '42P01') {
        log(
          '❌ O usuário "${EnvConfig.dbUser}" não tem permissão para criar o banco (CREATEDB).',
        );
      } else {
        log('❌ Erro ao criar o banco "$banco": ${e.message}');
      }
      return (false, logs);
    } catch (e) {
      log(
        '❌ Não foi possível conectar ao PostgreSQL em $host:${EnvConfig.dbPort} '
        'para criar o banco: $e',
      );
      return (false, logs);
    } finally {
      final c = manutencao;
      if (c != null) {
        try {
          await c.close();
        } catch (_) {}
      }
    }

    // 2. Rodar o init_db.sql (cria as tabelas, índices, triggers e migrações).
    final psqlPath = await findPostgresBinary('psql');
    if (psqlPath == null) {
      log('⚠️ psql não encontrado: o banco foi criado, mas sem as tabelas.');
      log('   Rode o reparar_banco.bat da instalação para completar.');
      return (false, logs);
    }

    final arquivoSql = _localizarInitDbSql();
    if (arquivoSql == null) {
      log(
        '⚠️ scripts/init_db.sql não encontrado: o banco foi criado, mas sem as tabelas.',
      );
      log('   Rode o reparar_banco.bat da instalação para completar.');
      return (false, logs);
    }

    log('🏗️ Criando as tabelas (${p.basename(arquivoSql)})...');
    try {
      final ambiente = Map<String, String>.from(Platform.environment);
      ambiente['PGPASSWORD'] = EnvConfig.dbPassword;
      // O init_db.sql é UTF-8 e o banco local pode estar em WIN1252: sem isso os
      // acentos do arquivo chegam errados.
      ambiente['PGCLIENTENCODING'] = 'UTF8';

      final result =
          await runProcessHidden(psqlPath, <String>[
            '-h',
            host,
            '-p',
            '${EnvConfig.dbPort}',
            '-U',
            EnvConfig.dbUser,
            '-d',
            banco,
            '--no-psqlrc',
            '-v',
            'ON_ERROR_STOP=1',
            '-f',
            arquivoSql,
          ], environment: ambiente).timeout(
            const Duration(minutes: 10),
            onTimeout: () => throw TimeoutException(
              'A criação das tabelas excedeu 10 minutos',
            ),
          );

      if (result.exitCode != 0) {
        final erro = '${result.stderr}'.trim().replaceAll(RegExp(r'\s+'), ' ');
        log(
          '❌ Erro ao criar as tabelas: '
          '${erro.isEmpty ? 'código ${result.exitCode}' : erro}',
        );
        return (false, logs);
      }
    } catch (e) {
      log('❌ Erro ao criar as tabelas: $e');
      return (false, logs);
    }

    // 3. Conferir quantas tabelas ficaram no banco.
    final total = await _contarTabelas(host, banco);
    log(
      '✅ Banco "$banco" pronto'
      '${total == null ? '' : ' ($total tabelas)'}.\n'
      '   Os dados são recarregados da nuvem na tela de Backup '
      '("Sincronizar Completo" ou "Restaurar da Nuvem").',
    );
    return (true, logs);
  }

  /// Caminho do `scripts/init_db.sql`: na instalação fica ao lado do executável
  /// do app; rodando pelo projeto, em `scripts/`.
  String? _localizarInitDbSql() {
    final candidatos = <String>[];
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidatos.add(p.join(exeDir, 'scripts', 'init_db.sql'));
      candidatos.add(p.join(exeDir, '..', 'scripts', 'init_db.sql'));
    } catch (_) {}
    candidatos.add(p.join(Directory.current.path, 'scripts', 'init_db.sql'));

    for (final caminho in candidatos) {
      try {
        if (File(caminho).existsSync()) return caminho;
      } catch (_) {}
    }
    return null;
  }

  /// Quantas tabelas existem no schema `public` (null quando não deu para contar).
  Future<int?> _contarTabelas(String host, String banco) async {
    Connection? conn;
    try {
      conn = await Connection.open(
        Endpoint(
          host: host,
          port: EnvConfig.dbPort,
          database: banco,
          username: EnvConfig.dbUser,
          password: EnvConfig.dbPassword,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      final res = await conn.execute(
        "SELECT count(*)::int AS n FROM information_schema.tables "
        "WHERE table_schema = 'public' AND table_type = 'BASE TABLE'",
      );
      return res.first.toColumnMap()['n'] as int?;
    } catch (_) {
      return null;
    } finally {
      final c = conn;
      if (c != null) {
        try {
          await c.close();
        } catch (_) {}
      }
    }
  }

  // ==========================================================================
  // MIGRAÇÕES DE SCHEMA VERSIONADAS (scripts/migrations/*.sql)
  // ==========================================================================

  /// true depois que as migrações foram conferidas nesta execução do app.
  bool _migracoesAplicadas = false;

  /// Última versão de schema que este banco já tem (para o log/status).
  int? ultimaVersaoSchema;

  /// Aplica, no boot, as migrações que faltam — sem travar a abertura do app.
  ///
  /// Chamado de [_connect] logo depois de [_inicializarColunas]. Uma falha aqui
  /// NÃO impede o uso do sistema (as colunas legadas de `_inicializarColunas`
  /// já garantiram o essencial); só fica registrada no log.
  Future<void> _aplicarMigracoesNoBoot(Connection conn) async {
    if (_migracoesAplicadas) return;
    try {
      final (_, logs) = await aplicarMigracoes(conn: conn);
      for (final l in logs) {
        debugPrint('>>> [Migracoes] $l');
      }
    } catch (e) {
      debugPrint('>>> [Migracoes] ⚠️ Não foi possível aplicar migrações: $e');
    }
  }

  /// Localiza a pasta `scripts/migrations`: ao lado do executável (instalação)
  /// ou em `scripts/` (rodando pelo projeto). Devolve null se não existir.
  @visibleForTesting
  String? localizarPastaMigracoes({String? exeDir, String? cwd}) {
    final candidatos = <String>[];
    try {
      final base = exeDir ?? File(Platform.resolvedExecutable).parent.path;
      candidatos.add(p.join(base, 'scripts', 'migrations'));
      candidatos.add(p.join(base, '..', 'scripts', 'migrations'));
    } catch (_) {}
    candidatos.add(
      p.join(cwd ?? Directory.current.path, 'scripts', 'migrations'),
    );

    for (final caminho in candidatos) {
      try {
        if (Directory(caminho).existsSync()) return caminho;
      } catch (_) {}
    }
    return null;
  }

  /// Extrai a versão numérica do nome do arquivo (`005_ajustes...` -> 5).
  @visibleForTesting
  static int? versaoDoArquivoMigracao(String nome) {
    final m = RegExp(r'^(\d+)').firstMatch(p.basename(nome));
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// Aplica as migrações de `scripts/migrations/*.sql` que ainda não rodaram.
  ///
  /// Mantém a tabela `schema_migrations` com a versão de cada arquivo aplicado
  /// e roda só os pendentes, em ordem crescente, cada um numa transação
  /// (`psql --single-transaction`). Idempotente: pode ser chamado a cada boot
  /// ou forçado pela tela de Backup ("Aplicar migrações de schema").
  ///
  /// [conn] evita reabrir conexão quando já temos uma (caminho do boot); sem
  /// ela, usa a conexão padrão do serviço (caminho do botão na tela).
  Future<(bool, List<String>)> aplicarMigracoes({
    Connection? conn,
    bool forcar = false,
    void Function(String)? onProgress,
  }) async {
    final logs = <String>[];
    void log(String mensagem) {
      logs.add(mensagem);
      debugPrint('>>> [Migracoes] $mensagem');
      onProgress?.call(mensagem);
    }

    if (kIsWeb) {
      log('⚠️ Migrações de schema não estão disponíveis na versão Web.');
      return (false, logs);
    }
    if (_migracoesAplicadas && !forcar) return (true, logs);

    final dir = localizarPastaMigracoes();
    if (dir == null) {
      log('ℹ️ Pasta scripts/migrations não encontrada — nada a migrar.');
      _migracoesAplicadas = true;
      return (true, logs);
    }

    // Lista e ordena os .sql por número de versão.
    final arquivos = <({int versao, String caminho, String nome})>[];
    try {
      for (final e in Directory(dir).listSync()) {
        if (e is! File) continue;
        if (!e.path.toLowerCase().endsWith('.sql')) continue;
        final versao = versaoDoArquivoMigracao(e.path);
        if (versao == null) continue;
        arquivos.add((
          versao: versao,
          caminho: e.path,
          nome: p.basename(e.path),
        ));
      }
    } catch (e) {
      log('❌ Não consegui listar $dir: $e');
      return (false, logs);
    }
    arquivos.sort((a, b) => a.versao.compareTo(b.versao));

    if (arquivos.isEmpty) {
      log('ℹ️ Nenhum arquivo de migração encontrado.');
      _migracoesAplicadas = true;
      return (true, logs);
    }

    Connection? conexao = conn;
    try {
      conexao ??= await connection;

      // Garante a tabela de controle.
      await conexao.execute('''
        CREATE TABLE IF NOT EXISTS public.schema_migrations (
          versao integer NOT NULL,
          nome text NOT NULL,
          aplicado_em timestamp with time zone DEFAULT now(),
          CONSTRAINT schema_migrations_pkey PRIMARY KEY (versao)
        )
      ''');

      final aplicadas = <int>{};
      final res = await conexao.execute(
        'SELECT versao FROM public.schema_migrations',
      );
      for (final row in res) {
        final v = row[0];
        if (v is int) {
          aplicadas.add(v);
        } else {
          aplicadas.add(int.tryParse(v.toString()) ?? -1);
        }
      }
      ultimaVersaoSchema = aplicadas.isEmpty
          ? null
          : aplicadas.reduce((a, b) => a > b ? a : b);

      final pendentes = arquivos
          .where((a) => !aplicadas.contains(a.versao))
          .toList();
      if (pendentes.isEmpty) {
        log('✅ Schema em dia (última versão: ${ultimaVersaoSchema ?? 0}).');
        _migracoesAplicadas = true;
        return (true, logs);
      }

      log('🔧 ${pendentes.length} migração(ões) pendente(s) — aplicando...');

      final psqlPath = await findPostgresBinary('psql');
      if (psqlPath == null) {
        log('❌ psql não encontrado: não é possível aplicar as migrações.');
        return (false, logs);
      }

      for (final mig in pendentes) {
        log('▶️ Aplicando ${mig.nome}...');
        final (ok, erro) = await _executarSqlMigracao(psqlPath, mig.caminho);
        if (!ok) {
          log('❌ Falha em ${mig.nome}: $erro');
          return (false, logs);
        }
        await conexao.execute(
          Sql.named(
            'INSERT INTO public.schema_migrations (versao, nome) '
            'VALUES (@versao, @nome) ON CONFLICT (versao) DO NOTHING',
          ),
          parameters: <String, Object?>{'versao': mig.versao, 'nome': mig.nome},
        );
        aplicadas.add(mig.versao);
        ultimaVersaoSchema = mig.versao;
        log('✅ ${mig.nome} aplicada.');
      }

      log(
        '✅ Migrações concluídas. Schema na versão ${ultimaVersaoSchema ?? 0}.',
      );
      _migracoesAplicadas = true;
      return (true, logs);
    } catch (e) {
      log('❌ Erro ao aplicar migrações: $e');
      return (false, logs);
    }
  }

  /// Roda um arquivo de migração no `psql`, numa transação única.
  Future<(bool, String)> _executarSqlMigracao(
    String psqlPath,
    String arquivo,
  ) async {
    try {
      final ambiente = Map<String, String>.from(Platform.environment);
      ambiente['PGPASSWORD'] = EnvConfig.dbPassword;
      ambiente['PGCLIENTENCODING'] = 'UTF8';

      final result =
          await runProcessHidden(psqlPath, <String>[
            '-h',
            _hostLocal(),
            '-p',
            '${EnvConfig.dbPort}',
            '-U',
            EnvConfig.dbUser,
            '-d',
            EnvConfig.dbName,
            '--no-psqlrc',
            '-v',
            'ON_ERROR_STOP=1',
            '--single-transaction',
            '-f',
            arquivo,
          ], environment: ambiente).timeout(
            const Duration(minutes: 10),
            onTimeout: () => throw TimeoutException(
              'A migração ${p.basename(arquivo)} excedeu 10 minutos',
            ),
          );

      if (result.exitCode != 0) {
        final erro = '${result.stderr}'.trim().replaceAll(RegExp(r'\s+'), ' ');
        return (false, erro.isEmpty ? 'código ${result.exitCode}' : erro);
      }
      return (true, '');
    } catch (e) {
      return (false, '$e');
    }
  }

  void setEmpresaId(String empresaId) {
    final empresaAnterior = _empresaId;
    _empresaId = empresaId;
    if (empresaAnterior != null &&
        empresaAnterior.isNotEmpty &&
        empresaAnterior != empresaId) {
      debugPrint(
        '>>> [PostgreSQL] 🔄 Empresa alterada: $empresaAnterior -> '
        '$empresaId. Daqui pra frente só grava dados da nova empresa (a '
        'anterior passa a ser recusada pela trava de empresa).',
      );
    }
    debugPrint('>>> [PostgreSQL] 🏢 Empresa definida: $empresaId');

    // Publica a empresa ABERTA para o sincronizador da bandeja (só quando muda).
    // É essa chave que faz o sincronizador importar somente esta empresa, para a
    // base local conter apenas os dados dela.
    if (empresaId.isNotEmpty && empresaId != _empresaAtivaPublicada) {
      _empresaAtivaPublicada = empresaId;
      unawaited(publicarEmpresaAtiva(empresaId));
    }
  }

  /// Última empresa publicada para o sincronizador (evita writes repetidos).
  String? _empresaAtivaPublicada;

  /// Chave em `cache_dados` que o sincronizador da bandeja lê para saber qual
  /// empresa está aberta no app.
  static const String chaveEmpresaAtivaPonte = 'exodo_empresa_ativa';

  /// Publica a empresa ABERTA no app para o sincronizador da bandeja.
  ///
  /// Grava `exodo_empresa_ativa` em `cache_dados` — tabela LOCAL que fica fora
  /// da lista de sincronização. Com essa chave o `SincronizadorNuvem` importa
  /// somente a empresa aberta, então a base local passa a conter só os dados
  /// dela. Sem a chave (instalação antiga) o sincronizador continua baixando
  /// tudo, como antes.
  Future<void> publicarEmpresaAtiva(String empresaId) {
    return _enqueue(() async {
      if (empresaId.isEmpty) return;
      try {
        final conn = await connection;
        await _garantirCacheDados(conn);
        await conn.execute(
          Sql.named('''
            INSERT INTO cache_dados (chave, valor_json, ultima_atualizacao)
            VALUES (@chave, @valor_json, @ultima_atualizacao)
            ON CONFLICT (chave) DO UPDATE SET
              valor_json = EXCLUDED.valor_json,
              ultima_atualizacao = EXCLUDED.ultima_atualizacao
          '''),
          parameters: <String, Object?>{
            'chave': chaveEmpresaAtivaPonte,
            'valor_json': jsonEncode(empresaId),
            'ultima_atualizacao': DateTime.now().toIso8601String(),
          },
        );
        debugPrint(
          '>>> [PostgreSQL] 📣 Empresa ativa publicada para o '
          'sincronizador da bandeja: $empresaId',
        );
      } catch (e) {
        debugPrint(
          '>>> [PostgreSQL] ⚠️ Não foi possível publicar a empresa ativa: $e',
        );
      }
    });
  }

  /// Tabelas GLOBAIS: não pertencem a uma empresa só — são a lista de empresas e
  /// a lista de usuários do sistema (um usuário pode, inclusive, atender mais de
  /// uma empresa). Elas NUNCA podem ser lidas com `WHERE empresa_id = ...`:
  ///
  ///   1. quem cria empresa/usuário precisa ver TODAS as que existem;
  ///   2. com o filtro, a lista voltaria vazia em qualquer computador em que a
  ///      coluna `empresa_id` exista e esteja nula (foi o que a comparação de
  ///      esquema mostrou: `empresas.empresa_id` vazio nas 4 empresas) — o app
  ///      pareceria ter perdido as empresas, mesmo com as linhas intactas.
  ///
  /// Por isso a leitura por empresa é pulada quando a tabela está aqui, mesmo
  /// que a coluna `empresa_id` exista na estrutura (é o que deixa o banco local
  /// ficar idêntico ao da nuvem sem quebrar a tela).
  static const Set<String> tabelasGlobaisSemFiltroDeEmpresa = {
    'empresas',
    'usuarios',
  };

  /// Tabelas que PERTENCEM a uma empresa — as que o app SEMPRE lê com
  /// `WHERE empresa_id = <aberta>`.
  ///
  /// A lista é fixa de propósito: antes o filtro só era montado quando o
  /// *schema cache* (`information_schema`) dizia que a tabela tinha a coluna
  /// `empresa_id`. Numa base que nasceu de um schema antigo (sem a coluna nas
  /// tabelas de caixa), o cache não trazia a coluna, o `WHERE` era omitido e a
  /// leitura devolvia as linhas de TODAS as empresas — era assim que o Fluxo de
  /// Caixa aparecia misturado. Com a lista canônica o filtro não depende mais do
  /// cache (e a migração em [_inicializarColunas] garante a coluna).
  static const Set<String> tabelasPorEmpresa = {
    'produtos',
    'clientes',
    'pedidos',
    'vendas_balcao',
    'mesas_comandas',
    'servicos',
    'servicos_realizados',
    'orcamentos',
    'ordens_servico',
    'entregas',
    'motoristas',
    'trocas_devolucoes',
    'estoque_historico',
    'ajustes_estoque_lote',
    'lotes_produto',
    'produto_historico',
    'notas_entrada',
    'pedidos_compra',
    'funcionarios',
    'taxas_entrega',
    'contas_pagar',
    'nfces',
    'nfes',
    'agendamentos_servico',
    'links_vendedores',
    'comissoes_vendedores',
    'cash_back_movimentos',
    'romaneios',
    'aberturas_caixa',
    'fechamentos_caixa',
    'sangrias_caixa',
    'suprimentos_caixa',
  };

  /// A leitura desta tabela precisa do filtro por empresa?
  ///
  /// `true` para tabelas da lista canônica (mesmo que o schema cache esteja
  /// vazio/torto) e para qualquer tabela que o schema diga ter `empresa_id`.
  /// `false` para as globais (`empresas`, `usuarios`) e para as tabelas fora da
  /// lista cuja coluna não existe.
  static bool deveFiltrarPorEmpresa(
    String tabela,
    Map<String, String>? colunas,
  ) {
    if (tabelasGlobaisSemFiltroDeEmpresa.contains(tabela)) return false;
    if (tabelasPorEmpresa.contains(tabela)) return true;
    return colunas != null && colunas.containsKey('empresa_id');
  }

  /// Colunas DUPLICADAS (camelCase) que o app IGNORA ao LER uma tabela.
  ///
  /// A mesma informação já chega pela coluna snake_case — `abertura_caixa_id`
  /// vira a chave `aberturaCaixaId` no mapa, e `data_fechamento` vira
  /// `dataFechamento`. Ler as duas deixava o valor final dependendo da ORDEM das
  /// colunas na tabela: numa migração antiga, a coluna `aberturaCaixaId` era
  /// TIMESTAMP e sobrescrevia o id da abertura por uma DATA — o vínculo
  /// fechamento → abertura se perdia e o caixa ficava "sempre aberto".
  ///
  /// As colunas continuam existindo (a nuvem também as tem, e é o que deixa os
  /// dois bancos com a MESMA estrutura), só não alimentam a leitura.
  static const Map<String, Set<String>> colunasIgnoradasNaLeitura = {
    'fechamentos_caixa': {'aberturaCaixaId', 'dataFechamento'},
  };

  /// Lê TODOS os registros de uma tabela SEM filtrar por empresa_id.
  /// Usado para migração local → nuvem, quando queremos enviar absolutamente
  /// tudo do banco local, independente de qual empresa está selecionada.
  Future<List<Map<String, dynamic>>> carregarListaCompleta(String chave) async {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(chave);
      try {
        final conn = await connection;
        if (tabela == null) {
          // Sem tabela mapeada, usa o cache_dados (JSON)
          await _garantirCacheDados(conn);
          final result = await conn.execute(
            Sql.named(
              'SELECT valor_json FROM cache_dados WHERE chave = @chave',
            ),
            parameters: <String, Object?>{'chave': chave},
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
        final result = await conn.execute(Sql.named('SELECT * FROM "$tabela"'));
        final list = <Map<String, dynamic>>[];
        final columns = _tableColumnTypes[tabela];
        for (final row in result) {
          final rowMap = row.toColumnMap();
          final convertedMap = <String, dynamic>{};
          for (final entry in rowMap.entries) {
            var k = entry.key;
            if (k.contains('_')) {
              final parts = k.split('_');
              k =
                  parts[0] +
                  parts
                      .skip(1)
                      .map(
                        (p) => p.isEmpty
                            ? ''
                            : p[0].toUpperCase() + p.substring(1),
                      )
                      .join();
            }
            var val = entry.value;
            if (val is DateTime && !val.isUtc) {
              // Já é local, ok
            } else if (val is DateTime && val.isUtc) {
              val = val.toLocal();
            }
            if (val is String && columns != null) {
              final colType = columns[entry.key]?.toUpperCase() ?? '';
              if (colType.contains('NUMERIC') ||
                  colType.contains('DECIMAL') ||
                  colType.contains('REAL') ||
                  colType.contains('DOUBLE')) {
                val = num.tryParse(val) ?? val;
              }
            }
            if (val is String && (val.startsWith('[') || val.startsWith('{'))) {
              try {
                val = jsonDecode(val);
              } catch (_) {}
            }
            if (convertedMap.containsKey(k)) {
              final atual = convertedMap[k];
              final mantemAtual =
                  atual is String && atual.isNotEmpty && val is! String;
              if (!mantemAtual && val != null) {
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
        debugPrint('>>> [PostgreSQL] ❌ Erro ao carregar completo $tabela: $e');
        return [];
      }
    });
  }

  String? get empresaId => _empresaId;

  bool _colunasInicializadas = false;
  final Map<String, Map<String, String>> _tableColumnTypes = {};

  /// Quantas gravações foram RECUSADAS por pertencerem a outra empresa que não
  /// a aberta. Serve de alarme: se este contador crescer, há dado de empresa
  /// errada circulando — e ele não foi gravado por cima dos dados corretos.
  int _gravacoesBloqueadasPorEmpresa = 0;
  int get gravacoesBloqueadasPorEmpresa => _gravacoesBloqueadasPorEmpresa;

  /// Quantas gravações foram RECUSADAS por chegarem SEM `empresa_id`.
  ///
  /// O carimbo da empresa aberta acontece ANTES do `_upsertRows` (ver
  /// `_carimbarEmpresaId`). Logo, um registro que ainda chega sem carimbo não é
  /// criação desta empresa: adotá-lo era o que misturava os dados. Contador de
  /// alarme — se crescer, há caminho gravando sem carimbar.
  int _gravacoesBloqueadasSemEmpresa = 0;
  int get gravacoesBloqueadasSemEmpresa => _gravacoesBloqueadasSemEmpresa;

  /// CARIMBO DE EMPRESA — aplicado um passo ANTES do `_upsertRows`.
  ///
  /// Preenche `empresa_id` com a empresa aberta nas linhas que chegam sem
  /// carimbo (criação local: o modelo ainda não tem a empresa). Linhas que JÁ
  /// têm carimbo são deixadas como estão — inclusive as de OUTRA empresa, que
  /// o `_upsertRows` recusa.
  ///
  /// Tabelas GLOBAIS (`empresas`, `usuarios`) e tabelas sem a coluna ficam de
  /// fora: carimbá-las escreveria a empresa errada.
  List<Map<String, dynamic>> _carimbarEmpresaId(
    String tabela,
    List<Map<String, dynamic>> lista,
  ) {
    final columns = _tableColumnTypes[tabela];
    if (columns == null || !columns.containsKey('empresa_id')) return lista;
    if (tabelasGlobaisSemFiltroDeEmpresa.contains(tabela)) return lista;
    final empresa = _empresaId;
    if (empresa == null || empresa.isEmpty) return lista;

    for (final row in lista) {
      final snake = row['empresa_id']?.toString();
      final camel = row['empresaId']?.toString();
      final jaCarimbado =
          (snake != null && snake.isNotEmpty) ||
          (camel != null && camel.isNotEmpty);
      if (!jaCarimbado) {
        row['empresa_id'] = empresa;
      }
    }
    return lista;
  }

  Future<void> _inicializarColunas(Connection conn) async {
    if (_colunasInicializadas && _tableColumnTypes.isNotEmpty) return;

    if (!_colunasInicializadas) {
      _colunasInicializadas = true;
      try {
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS envia_balanca BOOLEAN DEFAULT FALSE;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS perfil_tributario_id VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS perguntas_selecao JSONB;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS exibir_composicao_pdv BOOLEAN DEFAULT FALSE;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS baixar_estoque_proprio BOOLEAN DEFAULT TRUE;',
        );
        // Estoques (Loja, Depósito…): saldo do produto por estoque e qual é o
        // estoque padrão dele. A nuvem ganha estas colunas pelo botão
        // "Criar tabelas / colunas" (comparação de esquema) ou pelo SQL do repo.
        await conn.execute(
          "ALTER TABLE produtos ADD COLUMN IF NOT EXISTS estoque_por_estoque JSONB DEFAULT '{}'::jsonb;",
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS estoque_padrao_id VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE sangrias_caixa ADD COLUMN IF NOT EXISTS abertura_caixa_id VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE suprimentos_caixa ADD COLUMN IF NOT EXISTS abertura_caixa_id VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE fechamentos_caixa ADD COLUMN IF NOT EXISTS numero VARCHAR;',
        );
        // COLUNAS DE COMISSÃO DO MOTOBOY.
        //
        // A tabela `motoristas` nasceu só com id/empresa_id/nome/telefone/
        // placa/ativo. O modelo grava também os campos da comissão — e a
        // gravação DESCARTA coluna que não existe no schema. Resultado: a
        // "taxa do motoboy" cadastrada na tela era jogada fora ao salvar e
        // lida de volta como R$ 0,00, então a comissão do entregador nunca
        // contabilizava na tela de Comissões.
        //
        // Bloco com try próprio: se a tabela não existir, o erro não pode
        // abortar as demais migrações abaixo.
        try {
          await conn.execute(
            'ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS cpf TEXT;',
          );
          await conn.execute(
            'ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS cnh TEXT;',
          );
          await conn.execute(
            'ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS veiculo_placa TEXT;',
          );
          await conn.execute(
            'ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS veiculo_modelo TEXT;',
          );
          await conn.execute(
            'ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS tipo_comissao TEXT;',
          );
          await conn.execute(
            'ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS valor_comissao NUMERIC DEFAULT 0;',
          );
          // DIÁRIA: R$ fixo por dia trabalhado, somado ao valor por entrega.
          await conn.execute(
            'ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS valor_diaria NUMERIC DEFAULT 0;',
          );
          await conn.execute(
            'ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS taxa_padrao NUMERIC DEFAULT 0;',
          );
          // TEXT de propósito: o modelo faz `DateTime.parse(map['data_cadastro'])`
          // e as demais datas desta tabela (created_at/updated_at) também são TEXT.
          await conn.execute(
            'ALTER TABLE motoristas ADD COLUMN IF NOT EXISTS data_cadastro TEXT;',
          );
        } catch (e) {
          debugPrint(
            '>>> [PostgreSQL] ⚠️ Não foi possível garantir as colunas de '
            'comissão de motoristas: $e',
          );
        }
        // CORREÇÃO CAIXA "NUNCA FECHA" — agora REPARANDO, e não apagando.
        //
        // A tabela fechamentos_caixa tem colunas duplicadas em camelCase também na
        // NUVEM ("aberturaCaixaId" TEXT com o id da abertura e "dataFechamento"
        // TIMESTAMPTZ com a data). Numa migração antiga elas nasceram AQUI com o
        // tipo errado: o id (13 dígitos) era gravado como TIMESTAMP e, ao carregar,
        // sobrescrevia o id correto — o vínculo fechamento→abertura se perdia e o
        // caixa ficava "sempre aberto".
        //
        // Antes o app simplesmente APAGAVA essas duas colunas. Funcionava para o
        // bug, mas deixava o banco local diferente da nuvem para sempre (a
        // conferência mostrava 2 colunas faltando que o app nunca criava). Agora a
        // correção é: garantir o TIPO da nuvem (só derruba a coluna quando o tipo
        // está errado — aí não há dado bom para perder), criar se faltar e copiar
        // o valor real da coluna snake_case.
        //
        // A leitura das duas é ignorada de propósito
        // (ver `colunasIgnoradasNaLeitura`): quem manda no vínculo é
        // abertura_caixa_id, e ler as duas deixava a linha dependendo da ordem das
        // colunas — foi exatamente assim que o id virou data.
        // O driver recusa MAIS DE UM comando na mesma instrução preparada
        // ("não é possível inserir múltiplos comandos"), então cada comando vai
        // no seu próprio `execute` — e cada um dentro de try, para uma falha
        // aqui não abortar o resto da inicialização (era o que deixava a lista
        // de empresas vazia quando o bloco antigo estourava).
        try {
          await conn.execute(r'''
            DO $$
            BEGIN
              IF EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_schema = 'public' AND table_name = 'fechamentos_caixa'
                           AND column_name = 'aberturaCaixaId' AND data_type <> 'text') THEN
                ALTER TABLE public.fechamentos_caixa DROP COLUMN "aberturaCaixaId";
              END IF;
              IF EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_schema = 'public' AND table_name = 'fechamentos_caixa'
                           AND column_name = 'dataFechamento'
                           AND data_type <> 'timestamp with time zone') THEN
                ALTER TABLE public.fechamentos_caixa DROP COLUMN "dataFechamento";
              END IF;
            END $$;
          ''');
          await conn.execute(r'''
            ALTER TABLE public.fechamentos_caixa
              ADD COLUMN IF NOT EXISTS "aberturaCaixaId" text;
          ''');
          await conn.execute(r'''
            ALTER TABLE public.fechamentos_caixa
              ADD COLUMN IF NOT EXISTS "dataFechamento" timestamp with time zone;
          ''');
        } catch (e) {
          debugPrint(
            '>>> [PostgreSQL] ⚠️ Não foi possível reparar as colunas camelCase de '
            'fechamentos_caixa: $e',
          );
        }
        // Cópia dos valores reais (dentro de uma transação com o gatilho de
        // sincronização DESLIGADO: é reparo local, não pode virar envio para a
        // nuvem. Lá esses dois campos já estão preenchidos.)
        try {
          await conn.runTx((session) async {
            await session.execute("SET LOCAL exodo.sync_mode = 'on';");
            await session.execute(r'''
              UPDATE public.fechamentos_caixa
                 SET "aberturaCaixaId" = abertura_caixa_id
               WHERE COALESCE("aberturaCaixaId", '') = ''
                 AND COALESCE(abertura_caixa_id, '') <> ''
            ''');
            // `data_fechamento` é TEXT e "dataFechamento" é TIMESTAMPTZ: sem o
            // cast o PostgreSQL recusa (42804). O filtro por regex evita
            // derrubar a transação quando a coluna guarda lixo (id/data trocados
            // por uma migração antiga) — só converte o que realmente parece data.
            await session.execute(r'''
              UPDATE public.fechamentos_caixa
                 SET "dataFechamento" = btrim(data_fechamento)::timestamptz
               WHERE "dataFechamento" IS NULL
                 AND data_fechamento IS NOT NULL
                 AND btrim(data_fechamento) <> ''
                 AND btrim(data_fechamento) ~ '^\d{4}-\d{2}-\d{2}'
            ''');
          });
        } catch (e) {
          debugPrint(
            '>>> [PostgreSQL] ⚠️ Não foi possível copiar os valores das colunas '
            'camelCase de fechamentos_caixa: $e',
          );
        }
        // Reparo idempotente de dados já corrompidos: fechamentos cujo
        // abertura_caixa_id foi gravado como DATA (timestamp string) em vez do
        // id da abertura. Casa pela data de abertura e restaura o vínculo real.
        await conn.execute(r'''
          UPDATE fechamentos_caixa f
          SET abertura_caixa_id = a.id
          FROM aberturas_caixa a
          WHERE NOT EXISTS (SELECT 1 FROM aberturas_caixa x WHERE x.id = f.abertura_caixa_id)
            AND replace(substr(f.abertura_caixa_id, 1, 19), ' ', 'T')
              = replace(substr(a.data_abertura::text, 1, 19), ' ', 'T')
        ''');
        await conn.execute(
          'ALTER TABLE pedidos ADD COLUMN IF NOT EXISTS senha VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE vendas_balcao ADD COLUMN IF NOT EXISTS senha VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE empresas ADD COLUMN IF NOT EXISTS configuracoes JSONB;',
        );
        await conn.execute(
          'ALTER TABLE empresas ADD COLUMN IF NOT EXISTS perfis_de_preco JSONB;',
        );
        await conn.execute(
          'ALTER TABLE empresas ADD COLUMN IF NOT EXISTS "perfisDePreco" JSONB;',
        );
        await conn.execute(
          'ALTER TABLE clientes ADD COLUMN IF NOT EXISTS perfil_preco VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS precos_por_perfil JSONB;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS regras_quantidade JSONB;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS promocoes JSONB;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS impressora_producao VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS impressora_producao_extra JSONB;',
        );
        await conn.execute(
          "ALTER TABLE produtos ADD COLUMN IF NOT EXISTS unidade_venda VARCHAR DEFAULT 'unidade';",
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS quantidade_baixa NUMERIC DEFAULT 1;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS formas_venda JSONB;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS departamento_id VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS departamentos_adicionais JSONB;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS subgrupo VARCHAR;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS ativo BOOLEAN DEFAULT TRUE;',
        );
        // Disponibilidade temporária: janela (dia/hora) em que o produto pode
        // ser vendido. Fora dela o produto continua visível, mas a venda é
        // bloqueada. Nulo = sem limite naquele lado.
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS disponivel_de TIMESTAMP WITH TIME ZONE;',
        );
        await conn.execute(
          'ALTER TABLE produtos ADD COLUMN IF NOT EXISTS disponivel_ate TIMESTAMP WITH TIME ZONE;',
        );

        // Colunas de VALOR que ficaram como text no banco local (na nuvem elas
        // sempre foram numéricas) viram numeric/integer.
        await _converterColunasDeValorParaNumerico(conn);

        // Garantir tabelas de monitoramento
        await _garantirSyncStatus(conn);
        await _garantirSyncLogs(conn);
        await _garantirTombstones(conn);
        await _garantirUpdatedAt(conn);
        await _garantirNfes(conn);
        await _garantirExodoConfig(conn);
        await _garantirLotesProduto(conn);
        await _garantirAgendamentosServico(conn);
        await _garantirServicosRealizados(conn);
        await _garantirOrcamentos(conn);
        await _garantirPedidosCompra(conn);
        await _garantirCashBackMovimentos(conn);

        // Histórico de estoque: preservar fornecedor/observação/usuario localmente
        await conn.execute(
          'ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS fornecedor_nome TEXT;',
        );
        await conn.execute(
          'ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS fornecedor_id TEXT;',
        );
        await conn.execute(
          'ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS observacao TEXT;',
        );
        await conn.execute(
          'ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS usuario TEXT;',
        );
        // Custo da mercadoria na movimentação (quebras/perdas precisam registrar o valor de custo)
        await conn.execute(
          'ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS custo_unitario NUMERIC;',
        );
        await conn.execute(
          'ALTER TABLE estoque_historico ADD COLUMN IF NOT EXISTS valor_custo NUMERIC;',
        );

        // ISOLAMENTO POR EMPRESA: garante a coluna `empresa_id` em TODA tabela
        // por empresa. Numa base antiga, as tabelas de caixa não tinham a coluna
        // e a leitura não conseguia filtrar (nem a gravação carimbar) — as telas
        // mostravam os dados de todas as empresas juntos. O `IF NOT EXISTS`
        // torna a migração idempotente.
        for (final tabela in tabelasPorEmpresa) {
          try {
            await conn.execute(
              'ALTER TABLE "$tabela" ADD COLUMN IF NOT EXISTS empresa_id TEXT;',
            );
          } catch (e) {
            // Tabela ausente/criada depois: não pode derrubar as demais.
            debugPrint(
              '>>> [PostgreSQL] ⚠️ empresa_id não garantido em $tabela: $e',
            );
          }
        }

        _tableColumnTypes.clear();

        await conn.execute(
          'CREATE INDEX IF NOT EXISTS idx_produtos_empresa_id ON produtos(empresa_id);',
        );
        await conn.execute(
          'CREATE INDEX IF NOT EXISTS idx_produtos_nome ON produtos(nome);',
        );
        await conn.execute(
          'CREATE INDEX IF NOT EXISTS idx_produtos_codigo ON produtos(codigo);',
        );
        await conn.execute(
          'CREATE INDEX IF NOT EXISTS idx_clientes_empresa_id ON clientes(empresa_id);',
        );
        await conn.execute(
          'CREATE INDEX IF NOT EXISTS idx_clientes_nome ON clientes(nome);',
        );
        await conn.execute(
          'CREATE INDEX IF NOT EXISTS idx_pedidos_empresa_id ON pedidos(empresa_id);',
        );
        await conn.execute(
          'CREATE INDEX IF NOT EXISTS idx_vendas_balcao_empresa_id ON vendas_balcao(empresa_id);',
        );
        await conn.execute(
          'CREATE INDEX IF NOT EXISTS idx_estoque_historico_empresa_id ON estoque_historico(empresa_id);',
        );
        // Índices de empresa_id nas demais tabelas por empresa. Sem eles cada
        // leitura local (`WHERE empresa_id = ?`) fazia varredura completa da
        // tabela. O `IF NOT EXISTS` torna a migração idempotente em bancos que
        // já têm esses índices (instalação nova cria pelo `init_db.sql`).
        const indicesEmpresa = <String>[
          'idx_aberturas_caixa_empresa_id ON aberturas_caixa(empresa_id)',
          'idx_agendamentos_servico_empresa_id ON agendamentos_servico(empresa_id)',
          'idx_comissoes_vendedores_empresa_id ON comissoes_vendedores(empresa_id)',
          'idx_cash_back_movimentos_empresa_id ON cash_back_movimentos(empresa_id)',
          'idx_contas_pagar_empresa_id ON contas_pagar(empresa_id)',
          'idx_entregas_empresa_id ON entregas(empresa_id)',
          'idx_fechamentos_caixa_empresa_id ON fechamentos_caixa(empresa_id)',
          'idx_funcionarios_empresa_id ON funcionarios(empresa_id)',
          'idx_imagens_empresa_id ON imagens(empresa_id)',
          'idx_links_vendedores_empresa_id ON links_vendedores(empresa_id)',
          'idx_mesas_comandas_empresa_id ON mesas_comandas(empresa_id)',
          'idx_motoristas_empresa_id ON motoristas(empresa_id)',
          'idx_nfces_empresa_id ON nfces(empresa_id)',
          'idx_nfes_empresa_id ON nfes(empresa_id)',
          'idx_notas_entrada_empresa_id ON notas_entrada(empresa_id)',
          'idx_pedidos_compra_empresa_id ON pedidos_compra(empresa_id)',
          'idx_pedidos_compra_status ON pedidos_compra(status)',
          'idx_ordens_servico_empresa_id ON ordens_servico(empresa_id)',
          'idx_produto_historico_empresa_id ON produto_historico(empresa_id)',
          'idx_romaneios_empresa_id ON romaneios(empresa_id)',
          'idx_sangrias_caixa_empresa_id ON sangrias_caixa(empresa_id)',
          'idx_servicos_empresa_id ON servicos(empresa_id)',
          'idx_suprimentos_caixa_empresa_id ON suprimentos_caixa(empresa_id)',
          'idx_taxas_entrega_empresa_id ON taxas_entrega(empresa_id)',
          'idx_trocas_devolucoes_empresa_id ON trocas_devolucoes(empresa_id)',
          'idx_exodo_sync_conflitos_empresa_id ON exodo_sync_conflitos(empresa_id)',
          // Leituras ordenadas: `WHERE empresa_id = ? ORDER BY created_at DESC`.
          'idx_vendas_balcao_empresa_created ON vendas_balcao(empresa_id, created_at DESC)',
          'idx_pedidos_empresa_created ON pedidos(empresa_id, created_at DESC)',
        ];
        for (final indice in indicesEmpresa) {
          try {
            await conn.execute('CREATE INDEX IF NOT EXISTS $indice;');
          } catch (e) {
            // Tabela ausente/criada depois: não pode derrubar as demais.
            debugPrint('>>> [PostgreSQL] ⚠️ Índice não criado ($indice): $e');
          }
        }
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ⚠️ Erro ao executar migrations: $e');
        _colunasInicializadas = false;
      }
    }

    if (_tableColumnTypes.isNotEmpty) return;
    try {
      final results = await conn.execute(
        "SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = 'public'",
      );
      for (final row in results) {
        final tableName = row[0] as String;
        final columnName = row[1] as String;
        final dataType = row[2] as String;
        _tableColumnTypes.putIfAbsent(tableName, () => {})[columnName] =
            dataType.toUpperCase();
      }
      debugPrint(
        '>>> [PostgreSQL] ✅ Schema cache carregado para ${_tableColumnTypes.length} tabelas (com colunas novas).',
      );
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao inicializar colunas: $e');
    }
  }

  /// Colunas de VALOR que no banco local foram criadas como `text`, mas que na
  /// nuvem (Supabase) sempre foram numéricas. Enquanto ficam em texto, o próprio
  /// banco não soma/compara os valores e o local fica divergente da nuvem — é o
  /// que o "Comparar tabelas" do Backup reporta como coluna de tipo diferente.
  static const List<({String tabela, String coluna, String tipo})>
  _colunasDeValorNumericas = [
    (tabela: 'mesas_comandas', coluna: 'valor_couvert', tipo: 'numeric'),
    (
      tabela: 'mesas_comandas',
      coluna: 'quantidade_pessoas_couvert',
      tipo: 'integer',
    ),
    (
      tabela: 'mesas_comandas',
      coluna: 'valor_couvert_por_pessoa',
      tipo: 'numeric',
    ),
    (tabela: 'produtos', coluna: 'preco_promocional', tipo: 'numeric'),
    (tabela: 'produtos', coluna: 'icms_aliquota', tipo: 'numeric'),
  ];

  /// Converte texto em número aceitando "10.50", "10,50", "1.234,56" e
  /// "R$ 10,50". Devolve NULL quando não há número nenhum no texto (vazio, "-",
  /// "abc"), para um registro estranho nunca derrubar a migração inteira.
  ///
  /// É a mesma função de `scripts/init_db.sql`.
  static const String _funcaoTextoParaNumeric = r'''
CREATE OR REPLACE FUNCTION public.exodo_texto_para_numeric(valor text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    limpo text;
BEGIN
    IF valor IS NULL THEN
        RETURN NULL;
    END IF;

    -- Tira espaços, "R$", letras e qualquer outro símbolo.
    limpo := regexp_replace(valor, '[^0-9,.-]', '', 'g');

    IF limpo = '' OR limpo = '-' OR limpo = '.' OR limpo = ',' THEN
        RETURN NULL;
    END IF;

    -- Com vírgula e ponto juntos, o último é o separador decimal
    -- ("1.234,56" = pt-BR, "1,234.56" = en-US).
    IF position(',' IN limpo) > 0 AND position('.' IN limpo) > 0 THEN
        IF position(',' IN limpo) > position('.' IN limpo) THEN
            limpo := replace(replace(limpo, '.', ''), ',', '.');
        ELSE
            limpo := replace(limpo, ',', '');
        END IF;
    ELSIF position(',' IN limpo) > 0 THEN
        limpo := replace(limpo, ',', '.');
    END IF;

    RETURN limpo::numeric;
EXCEPTION
    WHEN others THEN
        RETURN NULL;
END;
''';

  /// Migração idempotente: converte para numeric/integer as colunas de
  /// [_colunasDeValorNumericas] que ainda estiverem como `text` no banco local.
  ///
  /// Roda a cada abertura do app, mas só na primeira faz alguma coisa: depois da
  /// conversão a consulta ao catálogo não encontra mais `text` e o método sai.
  ///
  /// Fica separada das outras migrations de propósito — se a conversão falhar, o
  /// resto da inicialização continua e o erro só aparece no log.
  Future<void> _converterColunasDeValorParaNumerico(Connection conn) async {
    try {
      final emTexto = <String>{};
      final resultado = await conn.execute(
        "SELECT table_name || '.' || column_name AS chave "
        'FROM information_schema.columns '
        "WHERE table_schema = 'public' AND data_type = 'text' "
        "AND table_name IN ('mesas_comandas', 'produtos')",
      );
      for (final linha in resultado) {
        emTexto.add(linha[0].toString());
      }

      final pendentes = _colunasDeValorNumericas
          .where((c) => emTexto.contains('${c.tabela}.${c.coluna}'))
          .toList();
      if (pendentes.isEmpty) return;

      await conn.execute(_funcaoTextoParaNumeric);

      for (final c in pendentes) {
        await conn.execute(
          'ALTER TABLE public."${c.tabela}" ALTER COLUMN "${c.coluna}" '
          'TYPE ${c.tipo} '
          'USING public.exodo_texto_para_numeric("${c.coluna}")::${c.tipo}',
        );
        debugPrint(
          '>>> [PostgreSQL] 🔧 ${c.tabela}.${c.coluna} convertida de text para ${c.tipo}.',
        );
      }

      debugPrint(
        '>>> [PostgreSQL] ✅ ${pendentes.length} coluna(s) de valor convertida(s) '
        'de text para número (agora iguais à nuvem).',
      );
    } catch (e) {
      debugPrint(
        '>>> [PostgreSQL] ⚠️ Não foi possível converter as colunas de valor para '
        'número: $e',
      );
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
      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_exodo_config ON exodo_config;',
      );
      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_sync_status ON sync_status;',
      );
      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_configuracoes_locais ON configuracoes_locais;',
      );
      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_sync_logs ON sync_logs;',
      );

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
                    -- Apagado registrado para a sincronizacao LAN: sem isto o
                    -- outro PC nao enxerga o DELETE (a linha nao esta mais na
                    -- tabela) e reenviaria a linha antiga. O to_regclass protege
                    -- instalacoes antigas que ainda nao criaram a tabela.
                    IF to_regclass('public._exodo_deletados') IS NOT NULL THEN
                        INSERT INTO _exodo_deletados (tabela, registro_id, empresa_id, deletado_em)
                        VALUES (TG_TABLE_NAME, rec_id, COALESCE(to_jsonb(OLD)->>'empresa_id', ''), NOW())
                        ON CONFLICT (tabela, registro_id)
                        DO UPDATE SET deletado_em = NOW();
                    END IF;
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

  /// Cria a tabela de APAGADOS (`_exodo_deletados`), usada pela sincronização
  /// entre os PCs da rede local.
  ///
  /// O trigger `log_sync_event` grava aqui todo DELETE feito pelo usuário
  /// (não grava quando `exodo.sync_mode = 'on'` — reparos e downloads são
  /// réplica, não apagamento do usuário). Sem essa tabela, o outro PC não
  /// enxerga o DELETE e reenviaria o registro antigo.
  Future<void> _garantirTombstones(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS _exodo_deletados (
          id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
          tabela TEXT NOT NULL,
          registro_id TEXT NOT NULL,
          empresa_id TEXT DEFAULT '',
          deletado_em TIMESTAMPTZ DEFAULT NOW(),
          CONSTRAINT _exodo_deletados_tabela_registro_id_key UNIQUE (tabela, registro_id)
        )
      ''');
      await conn.execute('''
        CREATE INDEX IF NOT EXISTS idx_exodo_deletados_busca
          ON _exodo_deletados (tabela, deletado_em)
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir _exodo_deletados: $e');
    }
  }

  /// Garante o trigger `set_updated_at` nas tabelas de dados.
  ///
  /// A sincronização entre os PCs (LAN) descobre o que mudou pela coluna de
  /// data (`updated_at`). Vários models do app gravam sem mexer nessa coluna,
  /// então a alteração nunca era vista pelo outro PC e o dado só chegava pela
  /// nuvem. O trigger carimba `updated_at` em toda alteração do usuário.
  ///
  /// Roda uma única vez por processo (a lista de colunas é lida do
  /// information_schema e seriam dezenas de DDL a cada salvamento).
  static bool _updatedAtGarantido = false;

  Future<void> _garantirUpdatedAt(Connection conn) async {
    if (_updatedAtGarantido) return;
    try {
      await conn.execute(r'''
        CREATE OR REPLACE FUNCTION public.set_updated_at() RETURNS trigger
        LANGUAGE plpgsql AS $$
        BEGIN
            IF current_setting('exodo.sync_mode', true) IS DISTINCT FROM 'on' THEN
                NEW.updated_at := NOW();
            END IF;
            RETURN NEW;
        END;
        $$;
      ''');

      final resultado = await conn.execute('''
        SELECT c.table_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema AND t.table_name = c.table_name
        WHERE c.table_schema = 'public' AND c.column_name = 'updated_at'
          AND t.table_type = 'BASE TABLE'
          AND LEFT(c.table_name, 1) <> '_'
          AND LEFT(c.table_name, 3) <> 'vw_'
      ''');

      for (final linha in resultado) {
        final tabela = linha[0].toString();
        final nome = 'trg_exodo_set_updated_at_$tabela';
        final ident = '"${tabela.replaceAll('"', '""')}"';
        await conn.execute('DROP TRIGGER IF EXISTS $nome ON $ident;');
        await conn.execute(
          'CREATE TRIGGER $nome BEFORE UPDATE ON $ident '
          'FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();',
        );
      }
      _updatedAtGarantido = true;
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir trigger updated_at: $e');
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
          produto_nome TEXT DEFAULT '',
          numero_lote TEXT DEFAULT '',
          fornecedor_id TEXT DEFAULT '',
          fornecedor_nome TEXT DEFAULT '',
          estoque_id TEXT DEFAULT '',
          estoque_nome TEXT DEFAULT '',
          data_fabricacao TIMESTAMPTZ,
          data_validade TIMESTAMPTZ,
          quantidade NUMERIC DEFAULT 0,
          custo_unitario NUMERIC DEFAULT 0,
          empresa_id TEXT NOT NULL DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      // Lote atrelado ao fornecedor e ao depósito: garante as colunas em bancos
      // já existentes (ADD COLUMN IF NOT EXISTS é seguro rodar sempre).
      await conn.execute(
        'ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS produto_nome TEXT DEFAULT \'\';',
      );
      await conn.execute(
        'ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS fornecedor_id TEXT DEFAULT \'\';',
      );
      await conn.execute(
        'ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS fornecedor_nome TEXT DEFAULT \'\';',
      );
      await conn.execute(
        'ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS estoque_id TEXT DEFAULT \'\';',
      );
      await conn.execute(
        'ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS estoque_nome TEXT DEFAULT \'\';',
      );
      await conn.execute(
        'ALTER TABLE lotes_produto ADD COLUMN IF NOT EXISTS custo_unitario NUMERIC DEFAULT 0;',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_lotes_produto_empresa_id ON lotes_produto(empresa_id);',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_lotes_produto_produto_id ON lotes_produto(produto_id);',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_lotes_produto_data_validade ON lotes_produto(data_validade);',
      );

      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_lotes_produto ON lotes_produto;',
      );
      await conn.execute('''
        CREATE TRIGGER trg_exodo_sync_log_lotes_produto
        AFTER INSERT OR DELETE OR UPDATE ON public.lotes_produto
        FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir lotes_produto: $e');
    }
  }

  Future<void> _garantirOrcamentos(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS orcamentos (
          id TEXT PRIMARY KEY,
          numero TEXT DEFAULT '',
          cliente_id TEXT DEFAULT '',
          cliente_nome TEXT DEFAULT '',
          cliente_telefone TEXT DEFAULT '',
          cliente_endereco TEXT DEFAULT '',
          cliente_cpf_cnpj TEXT DEFAULT '',
          operador TEXT DEFAULT '',
          data_orcamento TIMESTAMPTZ DEFAULT NOW(),
          validade_orcamento TIMESTAMPTZ,
          status TEXT DEFAULT 'Orçamento',
          total NUMERIC DEFAULT 0,
          desconto_total NUMERIC DEFAULT 0,
          acrescimo_total NUMERIC DEFAULT 0,
          observacoes TEXT DEFAULT '',
          itens JSONB DEFAULT '[]'::jsonb,
          servicos JSONB DEFAULT '[]'::jsonb,
          delivery_info JSONB,
          pedido_gerado_id TEXT DEFAULT '',
          pedido_gerado_numero TEXT DEFAULT '',
          data_aprovacao TIMESTAMPTZ,
          empresa_id TEXT NOT NULL DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_orcamentos_empresa_id ON orcamentos(empresa_id);',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_orcamentos_status ON orcamentos(status);',
      );

      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_orcamentos ON orcamentos;',
      );
      await conn.execute('''
        CREATE TRIGGER trg_exodo_sync_log_orcamentos
        AFTER INSERT OR DELETE OR UPDATE ON public.orcamentos
        FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir orcamentos: $e');
    }
  }

  Future<void> _garantirPedidosCompra(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS pedidos_compra (
          id TEXT PRIMARY KEY,
          empresa_id TEXT NOT NULL DEFAULT '',
          numero TEXT DEFAULT '',
          fornecedor_id TEXT DEFAULT '',
          fornecedor_nome TEXT DEFAULT '',
          fornecedor_cnpj TEXT DEFAULT '',
          fornecedor_telefone TEXT DEFAULT '',
          status TEXT DEFAULT 'rascunho',
          itens JSONB DEFAULT '[]'::jsonb,
          observacao TEXT DEFAULT '',
          usuario TEXT DEFAULT '',
          estoque_destino_id TEXT DEFAULT '',
          estoque_destino_nome TEXT DEFAULT '',
          data_criacao TIMESTAMPTZ DEFAULT NOW(),
          data_envio TIMESTAMPTZ,
          previsao_entrega TIMESTAMPTZ,
          data_recebimento TIMESTAMPTZ,
          data_cancelamento TIMESTAMPTZ,
          motivo_cancelamento TEXT DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      // Bases que já tinham a tabela (versões anteriores do recurso) recebem
      // as colunas que faltarem — a migração é idempotente.
      const colunas = <String>[
        'numero TEXT DEFAULT \'\'',
        'fornecedor_id TEXT DEFAULT \'\'',
        'fornecedor_nome TEXT DEFAULT \'\'',
        'fornecedor_cnpj TEXT DEFAULT \'\'',
        'fornecedor_telefone TEXT DEFAULT \'\'',
        'status TEXT DEFAULT \'rascunho\'',
        'itens JSONB DEFAULT \'[]\'::jsonb',
        'observacao TEXT DEFAULT \'\'',
        'usuario TEXT DEFAULT \'\'',
        'estoque_destino_id TEXT DEFAULT \'\'',
        'estoque_destino_nome TEXT DEFAULT \'\'',
        'data_criacao TIMESTAMPTZ DEFAULT NOW()',
        'data_envio TIMESTAMPTZ',
        'previsao_entrega TIMESTAMPTZ',
        'data_recebimento TIMESTAMPTZ',
        'data_cancelamento TIMESTAMPTZ',
        'motivo_cancelamento TEXT DEFAULT \'\'',
        'created_at TIMESTAMPTZ DEFAULT NOW()',
        'updated_at TIMESTAMPTZ DEFAULT NOW()',
      ];
      for (final coluna in colunas) {
        try {
          await conn.execute(
            'ALTER TABLE pedidos_compra ADD COLUMN IF NOT EXISTS $coluna;',
          );
        } catch (e) {
          debugPrint(
            '>>> [PostgreSQL] ⚠️ Coluna de pedidos_compra não criada '
            '($coluna): $e',
          );
        }
      }
      // A tabela criada pelo scripts/init_db.sql antigo não tinha PK. Sem ela
      // o `ON CONFLICT (id)` do upsert falha e nenhum pedido é gravado.
      try {
        await conn.execute(r'''
          DO $$ BEGIN
            IF NOT EXISTS (
              SELECT 1 FROM pg_constraint
              WHERE conname = 'pedidos_compra_pkey'
                AND connamespace = 'public'::regnamespace
            ) THEN
              ALTER TABLE ONLY public.pedidos_compra
                ADD CONSTRAINT pedidos_compra_pkey PRIMARY KEY (id);
            END IF;
          END $$;
        ''');
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ⚠️ PK de pedidos_compra não criada: $e');
      }
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_pedidos_compra_empresa_id ON pedidos_compra(empresa_id);',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_pedidos_compra_status ON pedidos_compra(status);',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_pedidos_compra_fornecedor ON pedidos_compra(fornecedor_nome);',
      );

      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_pedidos_compra ON pedidos_compra;',
      );
      await conn.execute('''
        CREATE TRIGGER trg_exodo_sync_log_pedidos_compra
        AFTER INSERT OR DELETE OR UPDATE ON public.pedidos_compra
        FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir pedidos_compra: $e');
    }
  }

  /// Extrato de cash back: um lançamento por crédito/débito do saldo do
  /// cliente. Tabela nova do recurso de fidelidade — criada idempotente para
  /// bases antigas ganharem o extrato sem migração manual.
  Future<void> _garantirCashBackMovimentos(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS cash_back_movimentos (
          id TEXT PRIMARY KEY,
          empresa_id TEXT NOT NULL DEFAULT '',
          cliente_id TEXT DEFAULT '',
          tipo TEXT DEFAULT 'credito',
          valor NUMERIC DEFAULT 0,
          saldo_apos NUMERIC DEFAULT 0,
          venda_id TEXT,
          venda_numero TEXT,
          data TIMESTAMPTZ DEFAULT NOW(),
          observacao TEXT,
          expira_em TIMESTAMPTZ,
          consumido NUMERIC DEFAULT 0,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_cash_back_movimentos_cliente_id '
        'ON cash_back_movimentos(cliente_id);',
      );

      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_cash_back_movimentos '
        'ON cash_back_movimentos;',
      );
      await conn.execute('''
        CREATE TRIGGER trg_exodo_sync_log_cash_back_movimentos
        AFTER INSERT OR DELETE OR UPDATE ON public.cash_back_movimentos
        FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir cash_back_movimentos: $e');
    }
  }

  Future<void> _garantirServicosRealizados(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS servicos_realizados (
          id TEXT PRIMARY KEY,
          numero TEXT DEFAULT '',
          cliente_id TEXT DEFAULT '',
          cliente_nome TEXT DEFAULT '',
          cliente_telefone TEXT DEFAULT '',
          cliente_endereco TEXT DEFAULT '',
          pet_id TEXT DEFAULT '',
          pet_nome TEXT DEFAULT '',
          operador TEXT DEFAULT '',
          data_servico TIMESTAMPTZ DEFAULT NOW(),
          data_conclusao TIMESTAMPTZ,
          data_orcamento TIMESTAMPTZ,
          validade_orcamento TIMESTAMPTZ,
          status TEXT DEFAULT 'Em Aberto',
          total NUMERIC DEFAULT 0,
          desconto_total NUMERIC DEFAULT 0,
          acrescimo_total NUMERIC DEFAULT 0,
          observacoes TEXT DEFAULT '',
          servicos JSONB DEFAULT '[]'::jsonb,
          pagamentos JSONB DEFAULT '[]'::jsonb,
          materiais_consumidos JSONB DEFAULT '[]'::jsonb,
          empresa_id TEXT NOT NULL DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_servicos_realizados_empresa_id ON servicos_realizados(empresa_id);',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_servicos_realizados_status ON servicos_realizados(status);',
      );

      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_servicos_realizados ON servicos_realizados;',
      );
      await conn.execute('''
        CREATE TRIGGER trg_exodo_sync_log_servicos_realizados
        AFTER INSERT OR DELETE OR UPDATE ON public.servicos_realizados
        FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir servicos_realizados: $e');
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
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_nfes_empresa_id ON nfes(empresa_id);',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_nfes_numero ON nfes(numero);',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_nfes_chave_acesso ON nfes(chave_acesso);',
      );
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_nfes_created_at ON nfes(created_at DESC);',
      );

      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_nfes ON nfes;',
      );
      await conn.execute('''
        CREATE TRIGGER trg_exodo_sync_log_nfes
        AFTER INSERT OR DELETE OR UPDATE ON public.nfes
        FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
      ''');
    } catch (e) {
      debugPrint('>>> [PostgreSQL] ❌ Erro ao garantir nfes: $e');
    }
  }

  Future<void> _garantirAgendamentosServico(Connection conn) async {
    try {
      await conn.execute('''
        CREATE TABLE IF NOT EXISTS agendamentos_servico (
          id TEXT PRIMARY KEY,
          numero TEXT DEFAULT 'AGD-0000',
          servico_id TEXT,
          servicos_ids JSONB DEFAULT '[]',
          cliente_id TEXT,
          pet_id TEXT,
          data_agendamento TIMESTAMPTZ,
          duracao_minutos INT DEFAULT 60,
          intervalo_minutos INT DEFAULT 0,
          observacoes TEXT,
          status TEXT DEFAULT 'Agendado',
          tipo_entrega TEXT,
          valor_taxi_dog NUMERIC,
          bairro_entrega TEXT,
          pedido_id TEXT,
          numero_pedido TEXT,
          recebido BOOLEAN DEFAULT FALSE,
          data_recebimento TIMESTAMPTZ,
          cliente_nome TEXT,
          cliente_telefone TEXT,
          pet_nome TEXT,
          endereco TEXT,
          numero_endereco TEXT,
          complemento TEXT,
          ponto_referencia TEXT,
          excluido BOOLEAN DEFAULT FALSE,
          travado BOOLEAN DEFAULT FALSE,
          funcionario_id TEXT,
          funcionario_nome TEXT,
          recorrente BOOLEAN DEFAULT FALSE,
          is_pago BOOLEAN DEFAULT FALSE,
          pagamento_info TEXT,
          empresa_id TEXT NOT NULL DEFAULT '',
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW()
        )
      ''');

      // ⚠️ MIGRAÇÃO DE COLUNAS FALTANTES.
      //
      // O CREATE TABLE acima só roda quando a tabela NÃO existe. Bases criadas
      // por `scripts/init_db.sql` (herdado do pg_dump antigo) ficaram com a
      // estrutura de 16 colunas — sem `data_agendamento`, sem `servicos_ids`,
      // sem `materiais` etc. O `_upsertRows` descarta em silêncio qualquer
      // chave do model sem coluna correspondente, e foi exatamente isso que
      // apagou a DATA dos agendamentos: `dataAgendamento` virava
      // `data_agendamento`, a coluna não existia, o valor sumia — e na leitura
      // `DateParser.parse(null)` devolvia `DateTime.now()`, fazendo TODOS os
      // agendamentos aparecerem em "hoje", todo dia.
      //
      // `ADD COLUMN IF NOT EXISTS` torna a migração idempotente. Os tipos
      // seguem o CREATE TABLE acima. Roda antes de `_tableColumnTypes.clear()`
      // em [_inicializarColunas], então o schema cache é recarregado com as
      // colunas novas e a gravação volta a funcionar no mesmo boot.
      const colunasAgendamento = <String, String>{
        'servico_id': 'TEXT',
        'servicos_ids': "JSONB DEFAULT '[]'",
        'data_agendamento': 'TIMESTAMPTZ',
        'duracao_minutos': 'INT DEFAULT 60',
        'intervalo_minutos': 'INT DEFAULT 0',
        'tipo_entrega': 'TEXT',
        'valor_taxi_dog': 'NUMERIC',
        'bairro_entrega': 'TEXT',
        'pedido_id': 'TEXT',
        'numero_pedido': 'TEXT',
        'recebido': 'BOOLEAN DEFAULT FALSE',
        'data_recebimento': 'TIMESTAMPTZ',
        'cliente_telefone': 'TEXT',
        'endereco': 'TEXT',
        'numero_endereco': 'TEXT',
        'complemento': 'TEXT',
        'ponto_referencia': 'TEXT',
        'excluido': 'BOOLEAN DEFAULT FALSE',
        'travado': 'BOOLEAN DEFAULT FALSE',
        'funcionario_id': 'TEXT',
        'funcionario_nome': 'TEXT',
        'recorrente': 'BOOLEAN DEFAULT FALSE',
        'is_pago': 'BOOLEAN DEFAULT FALSE',
        'pagamento_info': 'TEXT',
        'materiais': "JSONB DEFAULT '[]'",
      };
      for (final entry in colunasAgendamento.entries) {
        try {
          await conn.execute(
            'ALTER TABLE agendamentos_servico '
            'ADD COLUMN IF NOT EXISTS ${entry.key} ${entry.value};',
          );
        } catch (e) {
          debugPrint(
            '>>> [PostgreSQL] ⚠️ Coluna ${entry.key} não garantida '
            'em agendamentos_servico: $e',
          );
        }
      }

      // Retropreenche `data_agendamento` a partir do legado `data_hora` quando
      // ele tiver valor (a maioria das bases ficou com NULL, mas se existir
      // data em texto não pode se perder). Bloco com TRY/CATCH: formato
      // inesperado em `data_hora` não pode derrubar o boot.
      await conn.execute(r'''
        DO $$
        BEGIN
          IF EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public'
                       AND table_name = 'agendamentos_servico'
                       AND column_name = 'data_hora') THEN
            UPDATE agendamentos_servico
               SET data_agendamento = data_hora::timestamptz
             WHERE data_agendamento IS NULL
               AND data_hora IS NOT NULL
               AND data_hora <> ''
               AND data_hora ~ '^\d{4}-\d{2}-\d{2}';
          END IF;
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'backfill data_agendamento ignorado: %', SQLERRM;
        END $$;
      ''');

      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_agendamentos_empresa_id ON agendamentos_servico(empresa_id);',
      );
      // `data_agendamento` NÃO existe: o model grava `data_agendamento` como
      // chave, mas o PostgreSQL a converte para `dataAgendamento` (camelCase,
      // coluna criada pelo CREATE TABLE do app). O CREATE INDEX numa coluna
      // inexistente estourava 42703 a cada boot. Como o índice é opcional,
      // só cria se alguma das colunas realmente existir — e some com o índice
      // antigo herdado de instalações onde a coluna existia.
      await conn.execute(r'''
        DO $$
        DECLARE
          col text;
        BEGIN
          SELECT column_name INTO col
            FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'agendamentos_servico'
             AND column_name IN ('dataAgendamento', 'data_agendamento')
           LIMIT 1;
          IF col IS NOT NULL THEN
            EXECUTE format(
              'CREATE INDEX IF NOT EXISTS idx_agendamentos_data ON agendamentos_servico(%I)', col);
          END IF;
        END $$;
      ''');
      await conn.execute(r'''
        DO $$ BEGIN
          IF EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public'
                       AND table_name = 'agendamentos_servico'
                       AND column_name = 'cliente_id') THEN
            CREATE INDEX IF NOT EXISTS idx_agendamentos_cliente
              ON agendamentos_servico(cliente_id);
          END IF;
        END $$;
      ''');
      await conn.execute(
        'CREATE INDEX IF NOT EXISTS idx_agendamentos_status ON agendamentos_servico(status);',
      );

      await conn.execute(
        'DROP TRIGGER IF EXISTS trg_exodo_sync_log_agendamentos_servico ON agendamentos_servico;',
      );
      await conn.execute('''
        CREATE TRIGGER trg_exodo_sync_log_agendamentos_servico
        AFTER INSERT OR DELETE OR UPDATE ON public.agendamentos_servico
        FOR EACH ROW EXECUTE FUNCTION public.log_sync_event();
      ''');
    } catch (e) {
      debugPrint(
        '>>> [PostgreSQL] ❌ Erro ao garantir agendamentos_servico: $e',
      );
    }
  }

  /// Remove caracteres que o Postgres local (encoding WIN1252) não consegue
  /// armazenar — emojis como ✅/⚠️/🚀 (bytes 0xE2 0x9C 0x85...) estouram o
  /// erro 22P05 ao salvar. Símbolos comuns viram equivalente ASCII (→ vira
  /// "->") e o resto vira `?`; caracteres Latin-1 (á, ç, ã) são mantidos.
  /// A regra fica em [Win1252] para o app e a conferência usarem a mesma.
  String _sanitizarWin1252(String texto) => Win1252.sanitizar(texto);

  // ── Configuração no NAVEGADOR ────────────────────────────────────────────
  // Não existe PostgreSQL local no Web: `connection` lança na hora e o valor
  // se perdia (era o caso do nome do caixa, que voltava vazio a cada F5).
  // Aqui a mesma chave/valor do `exodo_config` é gravada no Hive, que é o
  // armazenamento que o Web já usa para as listas.
  Future<void> _salvarConfigWeb(String chave, dynamic valor) {
    final valorStr = valor is String ? valor : jsonEncode(_jsonSafe(valor));
    return LocalStorageWeb.salvar(chave, valorStr);
  }

  Future<dynamic> _carregarConfigWeb(String chave) async {
    final valor = await LocalStorageWeb.carregar(chave);
    if (valor == null) return null;
    if (valor.startsWith('[') || valor.startsWith('{')) {
      try {
        return jsonDecode(valor);
      } catch (_) {}
    }
    return valor;
  }

  Future<void> salvarConfig(
    String chave,
    dynamic valor, {
    bool lancarSeFalhar = false,
  }) {
    if (kIsWeb) return _salvarConfigWeb(chave, valor);
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
          },
        );
      } catch (e, st) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao salvar config $chave: $e');
        _anotarFalhaLocal(chave, e, st, acao: 'gravar');
        if (lancarSeFalhar) rethrow;
      }
    });
  }

  Future<dynamic> carregarConfig(
    String chave, {
    bool lancarSeFalhar = false,
  }) async {
    if (kIsWeb) return _carregarConfigWeb(chave);
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _garantirExodoConfig(conn);
        final result = await conn.execute(
          Sql.named('SELECT valor FROM exodo_config WHERE chave = @chave'),
          parameters: <String, Object?>{'chave': chave},
        );
        if (result.isEmpty) return null;
        final valor = result.first[0] as String;
        if (valor.startsWith('[') || valor.startsWith('{')) {
          try {
            return jsonDecode(valor);
          } catch (_) {}
        }
        return valor;
      } catch (e, st) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao carregar config $chave: $e');
        _anotarFalhaLocal(chave, e, st);
        if (lancarSeFalhar) rethrow;
        return null;
      }
    });
  }

  Future<void> removerConfig(String chave) {
    if (kIsWeb) return LocalStorageWeb.remover(chave);
    return _enqueue(() async {
      try {
        final conn = await connection;
        await conn.execute(
          Sql.named('DELETE FROM exodo_config WHERE chave = @chave'),
          parameters: <String, Object?>{'chave': chave},
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
    // ⚠️ ANTES de 'pedidos': 'exodo_pedidos_compra' contém a substring
    // 'pedidos' e seria gravado na tabela de PEDIDOS DE VENDA.
    if (chave.contains('pedidos_compra')) return 'pedidos_compra';
    // ⚠️ ANTES de 'estoque_historico'-genéricos: os ajustes em lote têm tabela
    // própria desde a migração 005, mas ficavam caindo em `cache_dados` (JSON
    // reescrito inteiro) — e o aparador de memória cortava para ~100 itens,
    // PERDENDO histórico de ajuste no banco local.
    if (chave.contains('ajustes_estoque_lote')) return 'ajustes_estoque_lote';
    // ⚠️ ANTES de 'servicos': 'servicos_realizados' contém a substring
    // 'servicos' e seria gravado na tabela de CATÁLOGO de serviços.
    if (chave.contains('servicos_realizados')) return 'servicos_realizados';
    if (chave.contains('orcamentos')) return 'orcamentos';
    if (chave.contains('produtos')) return 'produtos';
    if (chave.contains('clientes')) return 'clientes';
    if (chave.contains('pedidos')) return 'pedidos';
    if (chave.contains('notas_entrada')) return 'notas_entrada';
    if (chave.contains('ordens_servico')) return 'ordens_servico';
    if (chave.contains('trocas_devolucoes')) return 'trocas_devolucoes';
    if (chave.contains('vendas_balcao') || chave.contains('vendas'))
      return 'vendas_balcao';
    if (chave.contains('mesas_comandas') || chave.contains('mesas'))
      return 'mesas_comandas';
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
    if (chave.contains('cash_back_movimentos')) return 'cash_back_movimentos';
    if (chave.contains('contas_pagar')) return 'contas_pagar';
    if (chave.contains('estoque_historico')) return 'estoque_historico';
    if (chave.contains('aberturas_caixa')) return 'aberturas_caixa';
    if (chave.contains('fechamentos_caixa')) return 'fechamentos_caixa';
    if (chave.contains('sangrias_caixa') || chave.contains('sangrias'))
      return 'sangrias_caixa';
    if (chave.contains('suprimentos_caixa') || chave.contains('suprimentos'))
      return 'suprimentos_caixa';
    if (chave.contains('produto_historico')) return 'produto_historico';
    if (chave.contains('links_vendedores')) return 'links_vendedores';
    if (chave == 'empresas') return 'empresas';
    return null;
  }

  Future<void> salvarLista(
    String chave,
    List<Map<String, dynamic>> lista, {
    bool isSync = false,
  }) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(chave);
      try {
        final conn = await connection;
        if (tabela == null) {
          await _salvarCacheDados(conn, chave, lista);
          return;
        }
        await _inicializarColunas(conn);
        _carimbarEmpresaId(tabela, lista);
        await _upsertRows(conn, tabela, lista, isSync: isSync);
        debugPrint(
          '>>> [PostgreSQL] ✅ Dados salvos na tabela $tabela (${lista.length} itens)',
        );
      } catch (e, st) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao salvar lista $chave: $e');
        debugPrint('>>> [PostgreSQL] 🧵 Stack trace: $st');
        // Gravação falhada conta como falha do banco local: sem isto o erro só
        // ia para o debugPrint e a tela continuava "tudo certo" enquanto a
        // cópia local ficava velha (a alteração só ia para a nuvem).
        _anotarFalhaLocal(chave, e, st, acao: 'gravar');
        rethrow;
      }
    });
  }

  /// A chave corresponde a uma tabela real do PostgreSQL local?
  ///
  /// Usado pela gravação por registro: coleções que caem em `cache_dados`
  /// (sem tabela própria) continuam no caminho antigo, que grava a lista toda.
  bool temTabelaPara(String chave) => _mapearChaveParaTabela(chave) != null;

  Future<void> upsertItem(
    String chave,
    Map<String, dynamic> item, {
    bool lancarSeFalhar = false,
  }) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(chave);
      if (tabela == null) {
        if (lancarSeFalhar) {
          throw StateError('Chave "$chave" não tem tabela no PostgreSQL local');
        }
        return;
      }
      try {
        final conn = await connection.timeout(const Duration(seconds: 5));
        await _inicializarColunas(conn);
        _carimbarEmpresaId(tabela, [item]);
        await _upsertRows(conn, tabela, [item]);
        debugPrint(
          '>>> [PostgreSQL] ⚡ Upsert rápido: $tabela (id=${item['id']})',
        );
      } catch (e, st) {
        debugPrint('>>> [PostgreSQL] ⚠️ Erro no upsert rápido de $chave: $e');
        _anotarFalhaLocal(chave, e, st, acao: 'gravar');
        // Quem grava por registro precisa saber da falha para cair no flush
        // completo (rede de segurança); o resto segue só logando.
        if (lancarSeFalhar) rethrow;
      }
    });
  }

  Future<void> _salvarCacheDados(
    Connection conn,
    String chave,
    List<Map<String, dynamic>> lista,
  ) async {
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
        'ultima_atualizacao': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> _upsertRows(
    Connection conn,
    String tabela,
    List<Map<String, dynamic>> lista, {
    bool isSync = false,
  }) async {
    final columns = _tableColumnTypes[tabela];
    if (columns == null || columns.isEmpty) {
      debugPrint(
        '>>> [PostgreSQL] ⚠️ Tabela $tabela não encontrada no schema cache.',
      );
      return;
    }

    // ⛔ DUPLICATAS DE `id` NO MESMO LOTE — trava do PostgreSQL.
    //
    // O lote vira UM único comando (`INSERT ... VALUES (várias linhas) ON
    // CONFLICT (id) DO UPDATE`). Se a lista trouxer o MESMO id duas vezes, o
    // Postgres recusa o comando inteiro com SQLSTATE 21000 ("ON CONFLICT DO
    // UPDATE command cannot affect row a second time"): ele não pode atualizar a
    // mesma linha duas vezes dentro da mesma instrução. O erro derrubava a
    // gravação de TODO o lote — nenhum produto era salvo.
    //
    // A lista pode vir com id repetido quando a coleção em memória tem o mesmo
    // produto duas vezes (carga da nuvem + edição local, importação etc.).
    // Ficamos com a ÚLTIMA ocorrência de cada id: é exatamente o resultado que
    // teria gravando linha a linha, na ordem da lista.
    final porId = <String, Map<String, dynamic>>{};
    final semId = <Map<String, dynamic>>[];
    for (final item in lista) {
      final id = item['id']?.toString();
      if (id == null || id.isEmpty) {
        semId.add(item); // a normalização logo abaixo já descarta estas linhas
      } else {
        porId[id] = item; // última ocorrência vence
      }
    }
    if (porId.length != lista.length - semId.length) {
      debugPrint(
        '>>> [PostgreSQL] ♻️ $tabela: ${lista.length - porId.length - semId.length} id(s) '
        'repetido(s) no lote — mantida a última versão de cada um.',
      );
    }
    final listaUnica = <Map<String, dynamic>>[...porId.values, ...semId];

    final chunkSize = 100;
    for (var i = 0; i < listaUnica.length; i += chunkSize) {
      final end = (i + chunkSize < listaUnica.length)
          ? i + chunkSize
          : listaUnica.length;
      final chunk = listaUnica.sublist(i, end);

      await conn.runTx((session) async {
        await session.execute(
          "SET LOCAL exodo.sync_mode = '${isSync ? 'on' : 'off'}';",
        );

        final normalizedChunk = <Map<String, dynamic>>[];
        final Set<String> allCols = {};

        for (final item in chunk) {
          final rowMap = <String, dynamic>{};
          for (final entry in item.entries) {
            var k = entry.key;
            if (!columns.containsKey(k)) {
              final snake = k.replaceAllMapped(
                RegExp(r'([A-Z])'),
                (m) => '_${m.group(1)!.toLowerCase()}',
              );
              if (columns.containsKey(snake)) {
                k = snake;
              } else if (k.contains('_')) {
                final parts = k.split('_');
                final camel =
                    parts[0] +
                    parts
                        .skip(1)
                        .map(
                          (p) => p.isEmpty
                              ? ''
                              : p[0].toUpperCase() + p.substring(1),
                        )
                        .join();
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

          // ⛔ TRAVA DE EMPRESA — impede o cruzamento de dados entre empresas.
          //
          // Regras para tabelas que têm empresa_id:
          //   1. sem empresa definida -> NÃO grava (viraria NULL ou iria para a
          //      empresa anterior que ficou no singleton);
          //   2. registro SEM `empresa_id` -> NÃO grava (ver REGRA 0 abaixo);
          //   3. registro com empresa DIFERENTE da aberta -> NÃO grava e avisa.
          //
          // O carimbo da empresa aberta NÃO é feito mais aqui: ele é aplicado
          // antes, no `_carimbarEmpresaId` (criação local). Aqui só se conferem
          // as regras 1/2/3 — nenhuma linha sem carimbo é adotada.
          //
          // Sem as regras 2/3, um registro vindo de outra empresa (ou carregado
          // com `empresa_id` antigo) era gravado assim mesmo e o dado sumia da
          // empresa correta — foi assim que um catálogo inteiro apareceu zerado
          // na empresa que estava aberta.
          // TABELAS GLOBAIS (`empresas`, `usuarios`) ficam FORA desta trava: elas
          // não pertencem a uma empresa só. Carimbar `empresa_id` com a empresa
          // aberta aqui escreveria o id errado (o caso real: editar a empresa B
          // com a A aberta gravava empresa_id = A) e, em `usuarios`, a regra 3
          // chegaria a BLOQUEAR a gravação de um usuário de outra empresa — o
          // usuário simplesmente não seria salvo. A coluna é preservada como veio
          // da linha, que é a informação correta de cada registro.
          if (columns.containsKey('empresa_id') &&
              !tabelasGlobaisSemFiltroDeEmpresa.contains(tabela)) {
            final empresaAberta = _empresaId;
            if (empresaAberta == null || empresaAberta.isEmpty) {
              debugPrint(
                '>>> [PostgreSQL] ⛔ _upsertRows: pulando $tabela '
                '(id=${rowMap['id']}) — nenhuma empresa definida.',
              );
              continue;
            }

            final empresaDoRegistro = rowMap['empresa_id']?.toString();

            // ⛔ REGRA 0 — registro SEM `empresa_id` NÃO é gravado.
            //
            // O carimbo da empresa aberta é feito ANTES de chegar aqui (ver
            // `_carimbarEmpresaId`, chamado por salvarLista/upsertItem/
            // adicionarProdutosLote/salvarHistoricoProduto). Se ainda chegou
            // sem carimbo, não é criação desta empresa: adotá-la era o que
            // misturava os dados (o registro seria gravado como se fosse do
            // negócio aberto). Agora é RECUSADO.
            if (empresaDoRegistro == null || empresaDoRegistro.isEmpty) {
              _gravacoesBloqueadasSemEmpresa++;
              debugPrint(
                '>>> [PostgreSQL] 🛡️ GRAVAÇÃO BLOQUEADA em $tabela '
                '(id=${rowMap['id']}): registro SEM empresa_id. '
                'A empresa aberta é $empresaAberta. Nada foi gravado.',
              );
              continue;
            }

            if (empresaDoRegistro != empresaAberta) {
              _gravacoesBloqueadasPorEmpresa++;
              debugPrint(
                '>>> [PostgreSQL] 🛡️ GRAVAÇÃO BLOQUEADA em $tabela '
                '(id=${rowMap['id']}): o registro é da empresa '
                '$empresaDoRegistro, mas a empresa aberta é $empresaAberta. '
                'Nada foi gravado.',
              );
              continue;
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
                  : _sanitizarWin1252(
                      val is String ? val : jsonEncode(_jsonSafe(val)),
                    );
            } else if (type.contains('TIMESTAMP') || type.contains('DATE')) {
              rowValsSql.add('@$paramName');
              if (val == null) {
                params[paramName] = null;
              } else if (val is DateTime) {
                params[paramName] = val.toUtc().toIso8601String();
              } else if (val is num) {
                params[paramName] = DateTime.fromMillisecondsSinceEpoch(
                  val.toInt(),
                ).toUtc().toIso8601String();
              } else if (val is String) {
                final parsed = DateTime.tryParse(val);
                params[paramName] = parsed != null
                    ? parsed.toUtc().toIso8601String()
                    : val;
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
                  if (finalVal is double)
                    finalVal = finalVal.toInt();
                  else if (finalVal is num)
                    finalVal = finalVal.toInt();
                  else if (finalVal is String)
                    finalVal = double.tryParse(finalVal)?.toInt() ?? 0;
                } else if (type.contains('NUMERIC') ||
                    type.contains('DECIMAL') ||
                    type.contains('DOUBLE')) {
                  if (finalVal is int)
                    finalVal = finalVal.toDouble();
                  else if (finalVal is num)
                    finalVal = finalVal.toDouble();
                  else if (finalVal is String)
                    finalVal = double.tryParse(finalVal) ?? 0.0;
                }

                if (finalVal is List || finalVal is Map) {
                  params[paramName] = _sanitizarWin1252(
                    jsonEncode(_jsonSafe(finalVal)),
                  );
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

        // ⛔ SÓ ATUALIZA QUANDO ALGO MUDOU DE VERDADE.
        //
        // O flush grava a COLEÇÃO INTEIRA (milhares de produtos) mesmo quando o
        // usuário editou um único registro. Sem esta condição, o `ON CONFLICT
        // DO UPDATE` tocava TODAS as linhas e o trigger `set_updated_at`
        // carimbava `updated_at = NOW()` em cada uma. Resultado: depois de
        // qualquer edição local, o catálogo inteiro ficava "mais novo" que a
        // nuvem e as alterações feitas no site eram recusadas para sempre
        // ("Nuvem não é mais nova que o local").
        //
        // Com o WHERE, linha idêntica não é atualizada (trigger não dispara) e
        // o `updated_at` real de cada registro é preservado.
        // 🔒 TRAVA DE EMPRESA NO CONFLITO DE ID: o `ON CONFLICT (id)` casa pela
        // chave primária, que NÃO inclui a empresa. Sem esta condição, gravar um
        // registro cujo `id` já existe em OUTRA empresa atualizava a linha
        // existente (inclusive `empresa_id`) e o dado "mudava de dono". O UPDATE
        // do conflito só roda quando a empresa do registro no banco é a MESMA da
        // linha que chegou.
        final comparacaoLinha =
            '(ROW(${colList.map((c) => '"$tabela"."$c"').join(', ')}) '
            'IS DISTINCT FROM '
            'ROW(${colList.map((c) => 'EXCLUDED."$c"').join(', ')}))';
        final condicoesWhere = <String>[
          if (columns.containsKey('empresa_id') &&
              !tabelasGlobaisSemFiltroDeEmpresa.contains(tabela))
            '"$tabela"."empresa_id" = EXCLUDED."empresa_id"',
          comparacaoLinha,
        ];

        final clausulaWhere = ' WHERE ${condicoesWhere.join(' AND ')}';

        final sql =
            '''
          INSERT INTO "$tabela" ($colsSql)
          VALUES ${valsSqlRows.join(", ")}
          ON CONFLICT (id) DO UPDATE SET $updSql$clausulaWhere
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
        _carimbarEmpresaId('produtos', produtos);
        await _upsertRows(conn, 'produtos', produtos);
        debugPrint(
          '>>> [PostgreSQL] ✅ Lote de ${produtos.length} produtos adicionado.',
        );
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao adicionar lote de produtos: $e');
        rethrow;
      }
    });
  }

  /// Grava um lote de clientes no banco local (usado pelo importador de
  /// clientes). Faz o mesmo upsert por id do lote de produtos, para o
  /// importador não depender do flush debounced para chegar no PostgreSQL.
  Future<void> adicionarClientesLote(List<Map<String, dynamic>> clientes) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _inicializarColunas(conn);
        _carimbarEmpresaId('clientes', clientes);
        await _upsertRows(conn, 'clientes', clientes);
        debugPrint(
          '>>> [PostgreSQL] ✅ Lote de ${clientes.length} clientes adicionado.',
        );
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao adicionar lote de clientes: $e');
        rethrow;
      }
    });
  }

  Future<void> salvarEmpresaLocal(Map<String, dynamic> empresaMap) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _inicializarColunas(conn);

        await conn.execute(
          'ALTER TABLE empresas ADD COLUMN IF NOT EXISTS configuracoes JSONB;',
        );
        await conn.execute(
          'ALTER TABLE empresas ADD COLUMN IF NOT EXISTS perfis_de_preco JSONB;',
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
              'UPDATE empresas SET configuracoes = @config::jsonb WHERE id = @id',
            ),
            parameters: <String, Object?>{'config': configJson, 'id': id},
          );
          debugPrint(
            '>>> [PostgreSQL] ✅ configuracoes da empresa salvas (${configJson.length} chars).',
          );
        }
        if (perfisJson != null) {
          await conn.execute(
            Sql.named(
              'UPDATE empresas SET perfis_de_preco = @perfis::jsonb WHERE id = @id',
            ),
            parameters: <String, Object?>{'perfis': perfisJson, 'id': id},
          );
        }
        debugPrint('>>> [PostgreSQL] ✅ Empresa salva localmente com sucesso.');
      } catch (e, st) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao salvar empresa local: $e');
        debugPrint('>>> [PostgreSQL] Stack: $st');
        rethrow;
      }
    });
  }

  /// Última falha de leitura do banco local (null = tudo certo).
  ///
  /// Existe porque a leitura devolve LISTA VAZIA tanto quando a tabela está
  /// vazia quanto quando a leitura FALHOU — e as duas coisas eram tratadas
  /// igual lá em cima: o sistema concluía que "não há dados no banco local" e
  /// ficava esperando a nuvem para abrir as telas. Com isto a falha pode ser
  /// contada, registrada e repetida.
  String? _ultimaFalhaLocal;
  String? _chaveDaUltimaFalhaLocal;
  bool _leituraLocalConcluida = false;

  /// Mensagem da última falha do banco local (null quando a última leitura deu
  /// certo). Quem chama decide o que mostrar.
  String? get ultimoErroDoBancoLocal => _ultimaFalhaLocal;
  String? get chaveDoUltimoErroLocal => _chaveDaUltimaFalhaLocal;
  bool get bancoLocalFalhou => _ultimaFalhaLocal != null;

  /// O PostgreSQL DESTE computador já respondeu pelo menos uma leitura
  /// (mesmo que a tabela estivesse vazia). É o sinal de independência:
  /// o sistema pode abrir sem esperar a nuvem.
  bool get bancoLocalAtendeu =>
      _leituraLocalConcluida && _ultimaFalhaLocal == null;

  void limparFalhaDoBancoLocal() {
    _ultimaFalhaLocal = null;
    _chaveDaUltimaFalhaLocal = null;
  }

  @visibleForTesting
  void marcarLeituraLocalOkParaTeste() {
    _leituraLocalConcluida = true;
    _ultimaFalhaLocal = null;
    _chaveDaUltimaFalhaLocal = null;
  }

  @visibleForTesting
  void marcarLeituraLocalFalhouParaTeste(String erro) {
    _leituraLocalConcluida = true;
    _ultimaFalhaLocal = erro;
  }

  /// A falha é de CONEXÃO (e não do SQL em si)? Só nesses casos vale repetir:
  /// conexão recusada, timeout, conexão velha/caída ou autenticação recusada.
  static bool falhaDeConexao(Object? erro) {
    if (erro == null) return false;
    final texto = erro.toString().toLowerCase();
    return texto.contains('socketexception') ||
        texto.contains('socket error') ||
        texto.contains('connection timed out') ||
        texto.contains('connection refused') ||
        texto.contains('connection is closing') ||
        texto.contains('broken pipe') ||
        texto.contains('handshake') ||
        texto.contains('missing extension byte') ||
        texto.contains('authentication') ||
        texto.contains('too many clients') ||
        texto.contains('terminating connection');
  }

  /// O erro do PostgreSQL se resolve REPETINDO a consulta?
  ///
  /// Diferente de [falhaDeConexao] (a conexão caiu/foi recusada), estes são
  /// abortos que o PRÓPRIO servidor faz para quebrar uma corrida entre duas
  /// conexões:
  ///
  /// - `40P01` — deadlock ("impasse detectado"): duas transações ficaram
  ///   esperando o lock uma da outra e o servidor mata uma;
  /// - `40001` — falha de serialização;
  /// - `55P03` — lock indisponível.
  ///
  /// Repetir alguns milissegundos depois já não encontra o impasse, porque a
  /// transação que segurava o lock terminou. Sem isto a leitura desistia na
  /// primeira tentativa e a tela mostrava "Falha ao ler o banco local" mesmo
  /// com o dado presente (era o aviso de impasse no Histórico de Vendas).
  static bool erroTransitorioDoBanco(Object? erro) {
    if (erro == null) return false;
    if (erro is ServerException) {
      final codigo = erro.code;
      if (codigo == '40P01' || codigo == '40001' || codigo == '55P03') {
        return true;
      }
    }
    final texto = erro.toString().toLowerCase();
    return texto.contains('40p01') ||
        texto.contains('40001') ||
        texto.contains('55p03') ||
        texto.contains('deadlock') ||
        texto.contains('impasse detectado') ||
        texto.contains('could not serialize') ||
        texto.contains('lock not available');
  }

  /// Quantas tentativas a leitura merece para este erro.
  ///
  /// Impasse/serialização: até 4 (a primeira repetição imediata costuma achar
  /// o mesmo lock, por isso as pausas entre elas crescem). Falha de conexão:
  /// 2, como antes. Qualquer outro erro de SQL: 1 — repetir não adianta.
  static int _tentativasDeLeituraPara(Object erro) {
    if (erroTransitorioDoBanco(erro)) return 4;
    if (falhaDeConexao(erro)) return 2;
    return 1;
  }

  /// Classifica a falha do banco local (o texto longo e o rótulo curto saem
  /// daqui, para não divergirem).
  static _MotivoFalhaLocal _classificarFalhaLocal(Object? erro) {
    if (erro == null) return _MotivoFalhaLocal.semResposta;
    final minusculo = erro.toString().toLowerCase();
    if (minusculo.contains('missing extension byte') ||
        minusculo.contains('authentication') ||
        minusculo.contains('password')) {
      return _MotivoFalhaLocal.senha;
    }
    if (minusculo.contains('connection refused')) {
      return _MotivoFalhaLocal.desligado;
    }
    if (minusculo.contains('timed out') || minusculo.contains('timeout')) {
      return _MotivoFalhaLocal.lento;
    }
    // "Banco não existe" (3D000) só quando a mensagem fala do BANCO: um
    // 'column does not exist' é erro de SQL e cai no texto genérico.
    final falouDoBanco =
        minusculo.contains('database') || minusculo.contains('banco');
    final naoExiste =
        minusculo.contains('does not exist') ||
        minusculo.contains('não existe') ||
        minusculo.contains('nao existe');
    if (falouDoBanco && naoExiste) return _MotivoFalhaLocal.naoExiste;
    return _MotivoFalhaLocal.generico;
  }

  /// Explica a falha do banco local em português, com o próximo passo.
  ///
  /// É o que aparece no log de sincronização do sistema e nos avisos de tela.
  static String dicaDoErroLocal(Object? erro, {String acao = 'ler'}) {
    switch (_classificarFalhaLocal(erro)) {
      case _MotivoFalhaLocal.semResposta:
        return 'O banco local não respondeu.';
      case _MotivoFalhaLocal.senha:
        return 'O banco local recusou a SENHA de conexão — a senha do arquivo '
            '.env (DB_PASSWORD) não é a mesma do PostgreSQL.';
      case _MotivoFalhaLocal.desligado:
        return 'O PostgreSQL local está DESLIGADO (conexão recusada). '
            'O sistema tentou ligar sozinho e não conseguiu. Ligue o serviço '
            'PostgreSQL_Exodo (ou rode iniciar_postgres.bat) que os dados do '
            'banco local voltam.';
      case _MotivoFalhaLocal.lento:
        return 'O banco local não respondeu no tempo esperado (conexão '
            'travada). Pode ser excesso de conexões abertas ou o serviço '
            'reiniciando.';
      case _MotivoFalhaLocal.naoExiste:
        return 'O banco local "${EnvConfig.dbName}" não existe — o sistema '
            'consegue recriá-lo pelas telas de banco de dados.';
      case _MotivoFalhaLocal.generico:
        return 'Falha ao $acao o banco local: $erro';
    }
  }

  /// Rótulo CURTO da falha, para o chip do topo.
  ///
  /// Mesma classificação de [dicaDoErroLocal] (o texto longo vai no tooltip),
  /// mas em poucas palavras: o chip precisa caber na barra de sincronização.
  static String rotuloCurtoDoErroLocal(Object? erro) {
    switch (_classificarFalhaLocal(erro)) {
      case _MotivoFalhaLocal.senha:
        return 'SENHA DO BANCO LOCAL';
      case _MotivoFalhaLocal.desligado:
        return 'BANCO LOCAL DESLIGADO';
      case _MotivoFalhaLocal.lento:
        return 'BANCO LOCAL LENTO';
      case _MotivoFalhaLocal.naoExiste:
        return 'BANCO LOCAL NÃO EXISTE';
      case _MotivoFalhaLocal.semResposta:
      case _MotivoFalhaLocal.generico:
        return 'BANCO LOCAL';
    }
  }

  void _anotarFalhaLocal(
    String chave,
    Object erro,
    StackTrace? st, {
    String acao = 'ler',
  }) {
    _ultimaFalhaLocal = erro.toString();
    _chaveDaUltimaFalhaLocal = chave;
    debugPrint('>>> [PostgreSQL] ❌ Erro ao $acao $chave: $erro');
    debugPrint('>>> [PostgreSQL] 💡 ${dicaDoErroLocal(erro, acao: acao)}');
    try {
      final file = File('crash_db.txt');
      file.writeAsStringSync(
        'Erro na tabela $chave: $erro\n$st\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  /// Carrega UMA lista do banco local, com UMA segunda tentativa quando a
  /// falha for de conexão.
  ///
  /// ⚠️ POR QUE INSISTIR: a conexão do banco local é única e reaproveitada. Se
  /// ela morre (serviço reiniciando, conexão recusada em um pico de conexões),
  /// a PRIMEIRA leitura falhava, o erro era engolido e a resposta virava lista
  /// vazia. O sistema então entendia que o banco local estava vazio e abria as
  /// telas esperando a NUVEM — que é o sintoma "entra na empresa e só carrega
  /// quando sincroniza com a nuvem", mesmo com os dados no PostgreSQL local.
  Future<List<Map<String, dynamic>>> carregarLista(String chave) {
    return _enqueue(() => _lerDoBancoComRetentativa(chave));
  }

  Future<List<Map<String, dynamic>>> _lerDoBancoComRetentativa(
    String chave,
  ) async {
    Object? ultimoErro;
    StackTrace? ultimaPilha;
    for (var tentativa = 1; ; tentativa++) {
      try {
        final dados = await _carregarListaDoBanco(chave);
        if (tentativa > 1) {
          debugPrint(
            '>>> [PostgreSQL] ✅ "$chave" respondeu na '
            '${tentativa}ª tentativa — banco local em uso.',
          );
        }
        _leituraLocalConcluida = true;
        limparFalhaDoBancoLocal();
        return dados;
      } catch (e, st) {
        ultimoErro = e;
        ultimaPilha = st;
        // Joga fora a conexão velha/recusada antes de insistir.
        _verificarEResetarConexao(e);
        // Erro de SQL comum não melhora repetindo — só conexão ou impasse.
        if (tentativa >= _tentativasDeLeituraPara(e)) break;
        // Impasse/serialização: o deadlock só se desfaz quando a OUTRA
        // transação solta o lock — uma pausa curta faz a repetição valer.
        if (erroTransitorioDoBanco(e)) {
          await Future<void>.delayed(Duration(milliseconds: 40 * tentativa));
        }
      }
    }
    _leituraLocalConcluida = true;
    _anotarFalhaLocal(chave, ultimoErro!, ultimaPilha);
    return <Map<String, dynamic>>[];
  }

  /// Corpo da leitura, SEM a fila: quem enfileira é o `carregarLista` (assim a
  /// segunda tentativa não fica presa esperando a primeira na mesma fila).
  Future<List<Map<String, dynamic>>> _carregarListaDoBanco(String chave) async {
    final tabela = _mapearChaveParaTabela(chave);
    try {
      final conn = await connection;
      if (tabela == null) {
        await _garantirCacheDados(conn);
        final result = await conn.execute(
          Sql.named('SELECT valor_json FROM cache_dados WHERE chave = @chave'),
          parameters: <String, Object?>{'chave': chave},
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
      if (deveFiltrarPorEmpresa(tabela, columns)) {
        // Tabela POR EMPRESA: sem empresa definida não pode consultar sem
        // filtro. Sem o WHERE, o SELECT * traria as linhas de TODAS as
        // empresas e o app mostraria dados misturados.
        if (_empresaId == null || _empresaId!.isEmpty) {
          debugPrint(
            '>>> [PostgreSQL] ⛔ carregarLista($tabela) devolvendo vazio: nenhuma empresa '
            'selecionada (sem filtro viriam os dados de todas as empresas).',
          );
          return [];
        }
        sql += ' WHERE empresa_id = @empresaId';
        params['empresaId'] = _empresaId;
      }

      if (tabela == 'vendas_balcao' || tabela == 'pedidos') {
        sql += ' ORDER BY created_at DESC';
      }

      final result = await conn.execute(Sql.named(sql), parameters: params);
      final ignoradas = colunasIgnoradasNaLeitura[tabela] ?? const <String>{};
      final list = <Map<String, dynamic>>[];
      for (final row in result) {
        final rowMap = row.toColumnMap();
        final convertedMap = <String, dynamic>{};
        for (final entry in rowMap.entries) {
          var k = entry.key;
          // Duplicata em camelCase: a informação vem pela coluna snake_case
          // equivalente — ler as duas é o que já quebrou o caixa.
          if (ignoradas.contains(k)) continue;
          if (k.contains('_')) {
            final parts = k.split('_');
            k =
                parts[0] +
                parts
                    .skip(1)
                    .map(
                      (p) =>
                          p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1),
                    )
                    .join();
          }

          var val = entry.value;

          // Garantir que DateTime vindos do PostgreSQL sejam sempre local
          // (TIMESTAMP sem tz pode voltar como UTC pelo driver)
          if (val is DateTime && !val.isUtc) {
            // Já é local, ok
          } else if (val is DateTime && val.isUtc) {
            val = val.toLocal();
          }

          if (val is String && columns != null) {
            final colType = columns[entry.key]?.toUpperCase() ?? '';
            if (colType.contains('NUMERIC') ||
                colType.contains('DECIMAL') ||
                colType.contains('REAL') ||
                colType.contains('DOUBLE')) {
              val = num.tryParse(val) ?? val;
            }
          }

          if (val is String && (val.startsWith('[') || val.startsWith('{'))) {
            try {
              val = jsonDecode(val);
            } catch (_) {}
          }
          if (convertedMap.containsKey(k)) {
            // Nunca deixar uma coluna duplicada (camelCase) sobrescrever um
            // valor string já lido — ex.: fechamentos_caixa tem
            // "aberturaCaixaId" TIMESTAMP (migração antiga, tipo errado) que
            // vinha DEPOIS de abertura_caixa_id TEXT e sobrescrevia o id com
            // uma data, quebrando o vínculo fechamento→abertura (caixa que
            // nunca fechava). Se o atual é uma string não vazia e o novo é
            // DateTime/num, mantém o string (o id real).
            final atual = convertedMap[k];
            final mantemAtual =
                atual is String && atual.isNotEmpty && val is! String;
            if (!mantemAtual && val != null) {
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
      // Quem decide o que fazer com a falha (registrar/insistir) é o
      // `_lerDoBancoComRetentativa`, que chamou este método.
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<List<Map<String, dynamic>>> buscarProdutos(String termo) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _inicializarColunas(conn);

        String whereClause =
            "(nome ILIKE @queryTermo OR codigo ILIKE @queryTermo OR codigo ILIKE @prefixTermo)";
        final params = <String, Object?>{
          'queryTermo': '%$termo%',
          'prefixTermo': 'COD-$termo%',
          'termo': termo,
        };

        if (_empresaId != null && _empresaId!.isNotEmpty) {
          whereClause += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }

        final sql =
            '''
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
          parameters: params,
        );
        if (result.isEmpty) return null;
        return result.first.toColumnMap();
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao obter produto por ID: $e');
        return null;
      }
    });
  }

  /// Grava no PostgreSQL local **somente as colunas informadas** de um produto.
  ///
  /// Existe porque o app guarda o produto em memória e, ao abater estoque de uma
  /// venda, regrava a LINHA INTEIRA com esse objeto. Se o preço foi editado em
  /// outro PC (LAN) e ainda não recarregou aqui, a venda devolvia o preço velho
  /// para o banco — foi assim que um item ficou com o preço antigo num PC e o
  /// novo no outro, sem convergir. Gravando só o que mudou, o resto da linha
  /// continua como está no banco.
  ///
  /// Colunas desconhecidas no schema são ignoradas; se sobrar nenhuma, não há
  /// o que gravar. Roda com `exodo.sync_mode = 'on'` para o gatilho de
  /// sincronização registrar a alteração (é uma alteração real do usuário).
  Future<void> atualizarColunasProduto(
    String id,
    Map<String, dynamic> colunas,
  ) {
    return _enqueue(() async {
      try {
        if (colunas.isEmpty) return;
        final conn = await connection;
        await _inicializarColunas(conn);
        final existentes = _tableColumnTypes['produtos'];
        if (existentes == null || existentes.isEmpty) {
          debugPrint(
            '>>> [PostgreSQL] ⚠️ Tabela produtos sem colunas no cache; '
            'atualização parcial ignorada (id=$id).',
          );
          return;
        }

        final params = <String, Object?>{'id': id};
        final atribuicoes = <String>[];
        for (final entrada in colunas.entries) {
          final nome = nomeDeColunaNoSchema(existentes, entrada.key);
          if (nome == null) continue;
          final parametro = 'v_${atribuicoes.length}';
          params[parametro] = entrada.value;
          atribuicoes.add('$nome = @$parametro');
        }
        if (atribuicoes.isEmpty) return;

        String whereClause = 'id = @id';
        if (_empresaId != null && _empresaId!.isNotEmpty) {
          whereClause += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }

        await conn.runTx((session) async {
          await session.execute("SET LOCAL exodo.sync_mode = 'on';");
          await session.execute(
            Sql.named(
              'UPDATE produtos SET ${atribuicoes.join(', ')} '
              'WHERE $whereClause',
            ),
            parameters: params,
          );
        });
        debugPrint(
          '>>> [PostgreSQL] ✅ Produto $id: colunas atualizadas '
          '(${atribuicoes.length}).',
        );
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao atualizar colunas: $e');
      }
    });
  }

  /// Descobre como a coluna se chama no schema (camel ou snake).
  @visibleForTesting
  static String? nomeDeColunaNoSchema(
    Map<String, dynamic> colunas,
    String chave,
  ) {
    if (colunas.containsKey(chave)) return chave;
    final snake = chave.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (m) => '_${m.group(1)!.toLowerCase()}',
    );
    if (colunas.containsKey(snake)) return snake;
    if (chave.contains('_')) {
      final partes = chave.split('_');
      final camel =
          partes.first +
          partes
              .skip(1)
              .map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1))
              .join();
      if (colunas.containsKey(camel)) return camel;
    }
    return null;
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
          Sql.named(
            'UPDATE produtos SET estoque = @estoque WHERE $whereClause',
          ),
          parameters: params,
        );
        debugPrint(
          '>>> [PostgreSQL] ✅ Estoque do produto $id atualizado para $novoEstoque no PostgreSQL local.',
        );
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao atualizar estoque: $e');
      }
    });
  }

  /// Apaga (DELETE) as linhas da EMPRESA ATUAL na tabela informada, **apenas no
  /// banco local**. Retorna quantas linhas foram removidas.
  ///
  /// PROTEÇÕES (todas obrigatórias para não repetir o acidente de apagar os
  /// dados das outras empresas):
  ///  - exige uma empresa selecionada. Sem `empresa_id` o DELETE não teria
  ///    filtro e levaria as linhas de TODAS as empresas embora — por isso aqui
  ///    ele é abortado em vez de executado;
  ///  - carrega o mapa de colunas antes de decidir, senão `empresa_id` não é
  ///    encontrado e o filtro era omitido silenciosamente;
  ///  - só age em tabelas que realmente têm a coluna `empresa_id`.
  ///
  /// CRÍTICO: roda com `exodo.sync_mode = 'on'` para o trigger `log_sync_event`
  /// NÃO registrar estes DELETEs no `_exodo_sync_log`. Senão o sincronizador de
  /// bandeja (`sincronizar_local_supabase.py`) propaga os DELETEs para o Supabase
  /// e apaga dados da NUVEM — limpar o local NUNCA pode apagar a nuvem.
  Future<int> limparTabela(String tabelaChave) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(tabelaChave) ?? tabelaChave;
      try {
        final conn = await connection;
        await _inicializarColunas(conn);

        final empresaId = _empresaId;
        if (empresaId == null || empresaId.isEmpty) {
          debugPrint(
            '>>> [PostgreSQL] ⛔ limparTabela($tabela) ABORTADO: nenhuma empresa selecionada. '
            'Sem empresa o DELETE apagaria os dados de todas as empresas.',
          );
          return 0;
        }

        // ⛔ TABELAS GLOBAIS (`empresas`, `usuarios`) nunca são limpas por
        // empresa: elas não pertencem a uma empresa só. Como `empresas` tem a
        // coluna `empresa_id`, um "Limpar Local" aqui executava
        // `DELETE FROM empresas WHERE empresa_id = <empresa aberta>` e levava
        // embora as empresas cadastradas — a lista voltava com menos linhas do
        // que a nuvem tem. É a mesma trava usada em [_upsertRows].
        if (tabelasGlobaisSemFiltroDeEmpresa.contains(tabela)) {
          debugPrint(
            '>>> [PostgreSQL] ⛔ limparTabela($tabela) ignorado: tabela GLOBAL '
            '(não pertence a uma empresa só — limpar por empresa apagaria o '
            'cadastro das outras).',
          );
          return 0;
        }

        final columns = _tableColumnTypes[tabela];
        if (columns == null || !columns.containsKey('empresa_id')) {
          debugPrint(
            '>>> [PostgreSQL] ⛔ limparTabela($tabela) ignorado: a tabela não tem coluna empresa_id.',
          );
          return 0;
        }

        var removidas = 0;
        await conn.runTx((session) async {
          await session.execute("SET LOCAL exodo.sync_mode = 'on';");

          // PROVA DE ISOLAMENTO: conta as linhas das OUTRAS empresas antes e
          // depois do DELETE. Se a contagem mudar, o DELETE atingiu quem não
          // devia — lançamos para a transação reverter e NADA é apagado.
          final outrasAntes = await _contarLinhasDeOutrasEmpresas(
            session,
            tabela,
            empresaId,
          );

          final result = await session.execute(
            Sql.named('DELETE FROM "$tabela" WHERE empresa_id = @empresaId'),
            parameters: <String, Object?>{'empresaId': empresaId},
          );
          removidas = result.affectedRows;

          final outrasDepois = await _contarLinhasDeOutrasEmpresas(
            session,
            tabela,
            empresaId,
          );
          if (outrasDepois != outrasAntes) {
            throw StateError(
              'PROTEÇÃO DE ISOLAMENTO: o DELETE em "$tabela" mexeu em '
              '${outrasAntes - outrasDepois} linha(s) de OUTRA empresa. '
              'Transação revertida — nada foi apagado nesta tabela.',
            );
          }
        });
        debugPrint(
          '>>> [PostgreSQL] 🗑️ Tabela $tabela: $removidas linha(s) da empresa $empresaId '
          'apagadas (apenas local, nuvem intacta)',
        );
        return removidas;
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao limpar tabela $tabela: $e');
        return 0;
      }
    });
  }

  /// Quantas linhas de OUTRAS empresas existem numa tabela (a empresa atual
  /// fica de fora). Roda dentro da mesma sessão/transação da limpeza.
  Future<int> _contarLinhasDeOutrasEmpresas(
    Session session,
    String tabela,
    String empresaId,
  ) async {
    final result = await session.execute(
      Sql.named(
        'SELECT count(*)::int AS n FROM "$tabela" '
        'WHERE empresa_id IS DISTINCT FROM @empresaId',
      ),
      parameters: <String, Object?>{'empresaId': empresaId},
    );
    return (result.first.toColumnMap()['n'] as int?) ?? 0;
  }

  /// Total de linhas das OUTRAS empresas nas tabelas informadas.
  ///
  /// Serve de prova visual (e de teste) depois do "Limpar Local": é o número
  /// que tem de continuar intacto. Tabelas sem `empresa_id` são ignoradas.
  Future<int> contarLinhasDeOutrasEmpresas(Iterable<String> tabelasChave) {
    return _enqueue(() async {
      final empresaId = _empresaId;
      if (empresaId == null || empresaId.isEmpty) return 0;
      final conn = await connection;
      await _inicializarColunas(conn);
      var total = 0;
      for (final chave in tabelasChave) {
        final tabela = _mapearChaveParaTabela(chave) ?? chave;
        final columns = _tableColumnTypes[tabela];
        if (columns == null || !columns.containsKey('empresa_id')) continue;
        final result = await conn.execute(
          Sql.named(
            'SELECT count(*)::int AS n FROM "$tabela" '
            'WHERE empresa_id IS DISTINCT FROM @empresaId',
          ),
          parameters: <String, Object?>{'empresaId': empresaId},
        );
        total += (result.first.toColumnMap()['n'] as int?) ?? 0;
      }
      return total;
    });
  }

  /// Snapshot dos ids das OUTRAS empresas nas tabelas informadas.
  ///
  /// Diferente de [contarLinhasDeOutrasEmpresas], que devolve só o total, este
  /// método é imune a escrita concorrente (o sincronizador roda em paralelo e
  /// insere linhas a cada ciclo). Comparar dois snapshots prova o que interessa:
  /// nenhuma linha que JÁ existia foi apagada — mesmo que tenham entrado linhas
  /// novas no meio. Formato de cada item: `"<tabela>|<id>"`.
  Future<Set<String>> idsDeOutrasEmpresas(Iterable<String> tabelasChave) {
    return _enqueue(() async {
      final empresaId = _empresaId;
      if (empresaId == null || empresaId.isEmpty) return <String>{};
      final conn = await connection;
      await _inicializarColunas(conn);
      final ids = <String>{};
      for (final chave in tabelasChave) {
        final tabela = _mapearChaveParaTabela(chave) ?? chave;
        final columns = _tableColumnTypes[tabela];
        if (columns == null || !columns.containsKey('empresa_id')) continue;
        final result = await conn.execute(
          Sql.named(
            'SELECT id::text AS id FROM "$tabela" '
            'WHERE empresa_id IS DISTINCT FROM @empresaId',
          ),
          parameters: <String, Object?>{'empresaId': empresaId},
        );
        for (final row in result) {
          ids.add('$tabela|${row.toColumnMap()['id']}');
        }
      }
      return ids;
    });
  }

  /// Limpa a base local (PostgreSQL) de todas as tabelas por empresa informadas.
  ///
  /// Retorna `tabela -> linhas removidas`, já sem as tabelas que estavam vazias.
  Future<Map<String, int>> limparTabelasDaEmpresa(
    Iterable<String> tabelasChave,
  ) async {
    final removidas = <String, int>{};
    for (final chave in tabelasChave) {
      final tabela = _mapearChaveParaTabela(chave) ?? chave;
      final qtd = await limparTabela(chave);
      if (qtd > 0) removidas[tabela] = qtd;
    }
    return removidas;
  }

  Future<void> salvarHistoricoProduto(Map<String, dynamic> historico) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _inicializarColunas(conn);
        _carimbarEmpresaId('produto_historico', [historico]);
        await _upsertRows(conn, 'produto_historico', [historico]);
      } catch (e) {
        debugPrint(
          '>>> [PostgreSQL] ❌ Erro ao salvar histórico de produto: $e',
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> buscarHistoricoProduto(
    String produtoId, {
    int limite = 50,
  }) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        String sql =
            'SELECT * FROM produto_historico WHERE produto_id = @produtoId';
        final params = <String, Object?>{
          'produtoId': produtoId,
          'limite': limite,
        };

        if (_empresaId != null && _empresaId!.isNotEmpty) {
          sql += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }

        sql += ' ORDER BY data_alteracao DESC LIMIT @limite';
        final result = await conn.execute(Sql.named(sql), parameters: params);
        return result.map((r) => r.toColumnMap()).toList();
      } catch (e) {
        debugPrint(
          '>>> [PostgreSQL] ❌ Erro ao buscar histórico de produto: $e',
        );
        return [];
      }
    });
  }

  Future<List<Map<String, dynamic>>> buscarHistoricoGeral({
    int limite = 100,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) {
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

  Future<List<Map<String, dynamic>>> buscarHistoricoPorUsuario(
    String usuarioId, {
    int limite = 50,
  }) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        String sql =
            'SELECT * FROM produto_historico WHERE usuario_id = @usuarioId';
        final params = <String, Object?>{
          'usuarioId': usuarioId,
          'limite': limite,
        };

        if (_empresaId != null && _empresaId!.isNotEmpty) {
          sql += ' AND empresa_id = @empresaId';
          params['empresaId'] = _empresaId;
        }

        sql += ' ORDER BY data_alteracao DESC LIMIT @limite';
        final result = await conn.execute(Sql.named(sql), parameters: params);
        return result.map((r) => r.toColumnMap()).toList();
      } catch (e) {
        debugPrint(
          '>>> [PostgreSQL] ❌ Erro ao buscar histórico por usuário: $e',
        );
        return [];
      }
    });
  }

  Future<void> marcarHistoricoSincronizado(List<String> ids) async {}

  Future<List<Map<String, dynamic>>> buscarHistoricoNaoSincronizado({
    int limite = 100,
  }) async {
    return [];
  }

  Future<void> atualizarStatusNFCe(String nfceId, String status) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await conn.execute(
          Sql.named(
            'UPDATE nfces SET status = @status, updated_at = @now WHERE id = @id',
          ),
          parameters: <String, Object?>{
            'id': nfceId,
            'status': status,
            'now': DateTime.now().toIso8601String(),
          },
        );
        debugPrint(
          '>>> [PostgreSQL] ✅ Status da NFC-e $nfceId atualizado para $status',
        );
      } catch (e) {
        debugPrint('>>> [PostgreSQL] ❌ Erro ao atualizar status da NFC-e: $e');
      }
    });
  }

  Future<void> removerItemPostgres(
    String tableKey,
    String id,
    String? empresaId, {
    bool isSync = false,
    bool lancarSeFalhar = false,
  }) {
    return _enqueue(() async {
      final tabela = _mapearChaveParaTabela(tableKey) ?? tableKey;
      try {
        final conn = await connection;
        await conn.runTx((session) async {
          await session.execute(
            "SET LOCAL exodo.sync_mode = '${isSync ? 'on' : 'off'}';",
          );
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
        debugPrint(
          '>>> [PostgreSQL] 🗑️ DELETE local aplicado na tabela $tabela para ID=$id (isSync: $isSync)',
        );
      } catch (e) {
        debugPrint(
          '>>> [PostgreSQL] ❌ Erro ao remover item da tabela $tabela: $e',
        );
        if (lancarSeFalhar) rethrow;
      }
    });
  }

  /// Lê os TÚMULOS da empresa (`_exodo_deletados`): ids apagados localmente
  /// que ainda devem barrar a ressurreição vinda da nuvem.
  ///
  /// O trigger de DELETE da tabela preenche `_exodo_deletados` sozinho. Aqui a
  /// leitura é só para o app carregar o túmulo em memória no boot — antes ele
  /// morria junto com o processo (janela de 30 min) e um upsert atrasado de
  /// outro PC trazia o registro apagado de volta depois de reiniciar.
  Future<List<Map<String, dynamic>>> carregarTombstones(
    String empresaId, {
    DateTime? desde,
    int limite = 5000,
  }) {
    return _enqueue(() async {
      try {
        final conn = await connection;
        await _garantirTombstones(conn);
        final params = <String, Object?>{
          'empresaId': empresaId,
          'limite': limite,
        };
        var sql =
            "SELECT registro_id, tabela, deletado_em FROM _exodo_deletados "
            "WHERE (empresa_id = @empresaId OR empresa_id IS NULL OR empresa_id = '')";
        if (desde != null) {
          sql += ' AND deletado_em >= @desde';
          params['desde'] = desde;
        }
        sql += ' ORDER BY deletado_em DESC LIMIT @limite';
        final result = await conn.execute(Sql.named(sql), parameters: params);
        return [for (final row in result) row.toColumnMap()];
      } catch (e) {
        debugPrint(
          '>>> [PostgreSQL] ⚠️ Falha ao ler túmulos (_exodo_deletados): $e',
        );
        return <Map<String, dynamic>>[];
      }
    });
  }
}
