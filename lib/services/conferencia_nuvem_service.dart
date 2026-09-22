import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';

import '../utils/win1252.dart';
import 'env_config.dart';

/// Uma linha da conferência: quantas linhas existem na tabela, naquela empresa,
/// no banco LOCAL e na NUVEM.
class DiferencaConferencia {
  final String tabela;
  final String empresaId;

  /// `null` = não foi possível contar naquele lado (falha de conexão).
  /// Só entram aqui tabelas que existem nos dois lados.
  final int? local;
  final int? nuvem;

  /// Tabela de telemetria/infraestrutura (logs, status, views de apoio): não é
  /// dado da empresa e costuma sempre divergir, então vem marcada para o
  /// usuário poder esconder do relatório.
  final bool telemetria;

  /// `true` quando a comparação é pelo TOTAL de linhas, porque a tabela não tem
  /// `empresa_id` nos dois lados (ex.: `empresas` e `usuarios`). Sem isso, essas
  /// tabelas eram mostradas como "só na nuvem", o que não é verdade: elas
  /// existem aqui, o que falta é a coluna.
  final bool global;

  const DiferencaConferencia({
    required this.tabela,
    required this.empresaId,
    required this.local,
    required this.nuvem,
    this.telemetria = false,
    this.global = false,
  });

  int get diferenca => (nuvem ?? 0) - (local ?? 0);

  /// Só é possível afirmar "igual" quando os dois lados foram contados.
  bool get igual => local != null && nuvem != null && diferenca == 0;
}

/// Resultado completo da conferência Local × Nuvem.
class ResultadoConferencia {
  /// Todas as contagens comparáveis (tabela + empresa existentes nos dois lados).
  final List<DiferencaConferencia> linhas;

  /// Tabelas que possuem `empresa_id` só no local (não entram na comparação).
  final List<String> somenteNoLocal;

  /// Tabelas que possuem `empresa_id` só na nuvem (não entram na comparação).
  final List<String> somenteNaNuvem;

  /// Tabelas comparadas pelo TOTAL de linhas (existem nos dois lados, mas falta
  /// `empresa_id` em um deles) — `empresas` e `usuarios` são o caso clássico.
  final List<String> comparadasPorTotal;

  /// Tabelas que existem só no computador por definição do app (fila de
  /// sincronização e cache): nunca devem ir para a nuvem.
  final List<String> privadasDoApp;

  /// `empresaId -> nome` para deixar o relatório legível.
  final Map<String, String> nomesDeEmpresas;

  /// Erro de conexão de cada lado (vazio = tudo certo).
  final String? erroLocal;
  final String? erroNuvem;

  const ResultadoConferencia({
    required this.linhas,
    required this.somenteNoLocal,
    required this.somenteNaNuvem,
    required this.nomesDeEmpresas,
    this.comparadasPorTotal = const [],
    this.privadasDoApp = const [],
    this.erroLocal,
    this.erroNuvem,
  });

  List<DiferencaConferencia> get comDiferenca =>
      linhas.where((l) => !l.igual).toList();

  /// Filtra o relatório conforme os interruptores da tela.
  List<DiferencaConferencia> filtrar({
    required bool somenteDiferencas,
    required bool ocultarTelemetria,
  }) {
    return linhas
        .where((l) => !somenteDiferencas || !l.igual)
        .where((l) => !ocultarTelemetria || !l.telemetria)
        .toList();
  }

  /// Quantas linhas divergem, dentro do mesmo filtro da tela.
  int contarDiferencas({bool ocultarTelemetria = true}) => linhas
      .where((l) => !l.igual)
      .where((l) => !ocultarTelemetria || !l.telemetria)
      .length;

  /// true quando as duas pontas responderam e nada ficou diferente.
  bool get tudoIgual =>
      erroLocal == null && erroNuvem == null && comDiferenca.isEmpty;

  int get totalLocal => linhas.fold<int>(0, (s, l) => s + (l.local ?? 0));
  int get totalNuvem => linhas.fold<int>(0, (s, l) => s + (l.nuvem ?? 0));

  String nomeDaEmpresa(String empresaId) =>
      nomesDeEmpresas[empresaId] ?? empresaId;
}

class _Contagens {
  final Map<String, Map<String, int>> porTabela;
  final List<String> tabelas;
  const _Contagens(this.porTabela, this.tabelas);
}

/// O que um banco tem: todas as tabelas base, quais delas têm `empresa_id` e
/// quais são privadas do app (existem só no computador, de propósito).
class _TabelasDoBanco {
  /// Tabelas BASE (relkind = 'r').
  final Set<String> todas;

  /// As que têm a coluna `empresa_id` (dá para contar por empresa).
  final Set<String> comEmpresa;

  /// TODAS as relações do schema: tabela, view, matview, particionada...
  /// Serve para não acusar "só existe de um lado" quando do outro lado o mesmo
  /// nome existe como VIEW.
  final Set<String> relacoes;

  /// Tabelas que existem só no computador, por definição do app.
  final List<String> privadas;

  const _TabelasDoBanco({
    required this.todas,
    required this.comEmpresa,
    required this.relacoes,
    required this.privadas,
  });
}

/// Conta, tabela por tabela e empresa por empresa, quantas linhas existem no
/// banco LOCAL e no banco da NUVEM, e mostra as diferenças.
///
/// É uma leitura pura: não grava, não apaga e não sincroniza nada. Serve para
/// responder "o que falta aqui ou lá?" — especialmente depois de um
/// "Limpar Local" ou de uma troca de empresa.
///
/// A nuvem é acessada pelo Postgres (Session pooler), com as mesmas credenciais
/// já usadas no backup do banco da nuvem — por isso a comparação é exata, sem
/// depender da API REST nem das políticas de RLS.
class ConferenciaNuvemService {
  ConferenciaNuvemService._();
  static final ConferenciaNuvemService instance = ConferenciaNuvemService._();

  static const Duration _tempoLimite = Duration(seconds: 30);

  /// Quantas linhas vão em cada INSERT (menos idas e voltas ao banco).
  static const int _linhasPorLote = 200;

  /// Encoding do SERVIDOR de cada conexão já consultada (ver [_encodingDe]).
  final Map<Connection, String> _encodings = {};

  /// Roda a conferência inteira (local e nuvem em paralelo).
  Future<ResultadoConferencia> conferir() async {
    final leituras = await Future.wait<_TabelasDoBanco>([
      _lerTabelas(nuvem: false),
      _lerTabelas(nuvem: true),
    ]);
    final local = leituras[0];
    final nuvem = leituras[1];

    // Diferença de verdade: o nome não existe DO OUTRO LADO de forma alguma
    // (nem como tabela, nem como view). As privadas do app têm grupo próprio,
    // por isso saem daqui.
    final somenteNoLocal = (local.todas
          .difference(nuvem.relacoes)
          .difference(local.privadas.toSet())
          .toList()
        ..sort());
    final somenteNaNuvem =
        (nuvem.todas.difference(local.relacoes).toList()..sort());

    // Comparação POR EMPRESA: só as tabelas que têm `empresa_id` nos dois lados.
    final comuns = (local.comEmpresa.intersection(nuvem.comEmpresa).toList()..sort());

    // Tabelas que existem DOS DOIS LADOS mas ficariam de fora da comparação por
    // empresa porque falta `empresa_id` em um deles (ex.: `empresas` e
    // `usuarios`, que no banco local não têm essa coluna), ou porque de um lado
    // o objeto é uma VIEW. Antes elas apareciam como "só na nuvem" — o que era
    // falso: a tabela existe aqui, o que falta é a coluna. Aqui elas passam a
    // ser comparadas pelo TOTAL de linhas (que funciona em tabela e em view).
    final porTotal = <String>{
      ...local.todas.intersection(nuvem.relacoes),
      ...nuvem.todas.intersection(local.relacoes),
    }.difference(local.comEmpresa.intersection(nuvem.comEmpresa)).toList()
      ..sort();

    String? erroLocal;
    String? erroNuvem;
    var contagensLocal = const <String, Map<String, int>>{};
    var contagensNuvem = const <String, Map<String, int>>{};
    var totaisLocal = const <String, int>{};
    var totaisNuvem = const <String, int>{};
    var localOk = false;
    var nuvemOk = false;

    try {
      contagensLocal = (await _contarTabelas(comuns, nuvem: false)).porTabela;
      totaisLocal = await _contarTotais(porTotal, nuvem: false);
      localOk = true;
    } catch (e) {
      erroLocal = _mensagem(e, nuvem: false);
      debugPrint('>>> [Conferencia] ❌ Local: $e');
    }
    try {
      contagensNuvem = (await _contarTabelas(comuns, nuvem: true)).porTabela;
      totaisNuvem = await _contarTotais(porTotal, nuvem: true);
      nuvemOk = true;
    } catch (e) {
      erroNuvem = _mensagem(e, nuvem: true);
      debugPrint('>>> [Conferencia] ❌ Nuvem: $e');
    }

    final linhas = <DiferencaConferencia>[];
    for (final tabela in comuns) {
      final doLocal = contagensLocal[tabela] ?? const <String, int>{};
      final daNuvem = contagensNuvem[tabela] ?? const <String, int>{};
      final empresas = <String>{...doLocal.keys, ...daNuvem.keys}.toList()..sort();
      for (final empresa in empresas) {
        linhas.add(DiferencaConferencia(
          tabela: tabela,
          empresaId: empresa,
          // Se o lado foi contado com sucesso, a ausência daquela empresa no
          // GROUP BY significa ZERO linha (e não "desconhecido").
          local: localOk ? (doLocal[empresa] ?? 0) : null,
          nuvem: nuvemOk ? (daNuvem[empresa] ?? 0) : null,
          telemetria: _ehTelemetria(tabela),
        ));
      }
    }

    // Uma linha por tabela comparada pelo total (empresa = "(todas)").
    for (final tabela in porTotal) {
      linhas.add(DiferencaConferencia(
        tabela: tabela,
        empresaId: _rotuloTodas,
        local: localOk ? (totaisLocal[tabela] ?? 0) : null,
        nuvem: nuvemOk ? (totaisNuvem[tabela] ?? 0) : null,
        telemetria: _ehTelemetria(tabela),
        global: true,
      ));
    }

    return ResultadoConferencia(
      linhas: linhas,
      somenteNoLocal: somenteNoLocal,
      somenteNaNuvem: somenteNaNuvem,
      comparadasPorTotal: porTotal,
      privadasDoApp: local.privadas,
      nomesDeEmpresas: await _nomesDeEmpresas(),
      erroLocal: erroLocal,
      erroNuvem: erroNuvem,
    );
  }

  /// Rótulo da linha comparada pelo TOTAL (não tem empresa_id de um lado).
  static const String _rotuloTodas = '(todas as empresas)';

  /// Uma consulta por lado: quais tabelas existem, quais têm `empresa_id` e
  /// quais são privadas do app (existem só no computador, de propósito).
  Future<_TabelasDoBanco> _lerTabelas({required bool nuvem}) async {
    final conn = await _abrir(nuvem: nuvem);
    try {
      final res = await conn.execute(
        "SELECT c.relname, c.relkind::text, "
        "  EXISTS (SELECT 1 FROM information_schema.columns col "
        "          WHERE col.table_schema = 'public' AND col.table_name = c.relname "
        "            AND col.column_name = 'empresa_id') AS tem_empresa "
        "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
        "WHERE n.nspname = 'public' AND c.relkind IN ('r','v','m','p','f') "
        'ORDER BY 1',
      );
      final todas = <String>{};
      final comEmpresa = <String>{};
      final relacoes = <String>{};
      for (final row in res) {
        final nome = row[0].toString();
        final kind = row[1].toString();
        relacoes.add(nome);
        if (kind == 'r') {
          todas.add(nome);
          if (row[2] == true || row[2].toString() == 't') comEmpresa.add(nome);
        }
      }
      return _TabelasDoBanco(
        todas: todas,
        comEmpresa: comEmpresa,
        relacoes: relacoes,
        privadas: todas.where(_ehPrivadaDoApp).toList()..sort(),
      );
    } finally {
      await _fechar(conn);
    }
  }

  /// Tabela que existe SÓ neste computador, por definição do app (fila de
  /// sincronização e cache). Elas nunca devem ir para a nuvem.
  static const Set<String> _tabelasPrivadas = {
    'cache_dados',
    'usuarios_cache',
  };

  static bool _ehPrivadaDoApp(String tabela) =>
      tabela.startsWith('_') || _tabelasPrivadas.contains(tabela);

  /// `COUNT(*)` por tabela (sem filtrar empresa) — para as tabelas que não têm
  /// `empresa_id` nos dois lados, como `empresas` e `usuarios`.
  Future<Map<String, int>> _contarTotais(
    List<String> tabelas, {
    required bool nuvem,
  }) async {
    if (tabelas.isEmpty) return const <String, int>{};
    final conn = await _abrir(nuvem: nuvem);
    try {
      final partes = tabelas.map((t) {
        final nome = t.replaceAll('"', '""');
        final literal = t.replaceAll("'", "''");
        return "SELECT '$literal' AS t, COUNT(*)::int AS n FROM \"$nome\"";
      }).join(' UNION ALL ');

      final res = await conn.execute('SELECT * FROM ($partes) x ORDER BY t');
      final totais = <String, int>{};
      for (final row in res) {
        totais[row[0].toString()] = int.tryParse(row[1].toString()) ?? 0;
      }
      for (final t in tabelas) {
        totais.putIfAbsent(t, () => 0);
      }
      return totais;
    } finally {
      await _fechar(conn);
    }
  }

  /// Tabelas que não são dado da empresa (logs, status e views de apoio).
  /// Elas divergem por natureza e ficam marcadas para poderem ser escondidas.
  static const Set<String> _tabelasTelemetria = {
    'sync_logs',
    'sync_status',
    'exodo_sync_conflitos',
    'bridge_status',
    'bridge_commands',
  };

  static bool _ehTelemetria(String tabela) =>
      _tabelasTelemetria.contains(tabela) ||
      tabela.startsWith('vw_') ||
      tabela.startsWith('view_');

  // ───────────────────────────────────────────────────────────────────────────
  // Consultas
  // ───────────────────────────────────────────────────────────────────────────

  /// Uma única consulta por lado: para cada tabela, quantas linhas por empresa.
  Future<_Contagens> _contarTabelas(List<String> tabelas, {required bool nuvem}) async {
    if (tabelas.isEmpty) return const _Contagens({}, []);
    final conn = await _abrir(nuvem: nuvem);
    try {
      final partes = tabelas.map((t) {
        final nome = t.replaceAll('"', '""');
        final literal = t.replaceAll("'", "''");
        return 'SELECT \'$literal\' AS t, '
            "COALESCE(empresa_id, '(sem empresa)') AS e, "
            'COUNT(*)::int AS n FROM "$nome" GROUP BY 1, 2';
      }).join(' UNION ALL ');

      final res = await conn.execute(
        'SELECT * FROM ($partes) x ORDER BY t, n DESC',
      );

      final porTabela = <String, Map<String, int>>{};
      for (final row in res) {
        final t = row[0].toString();
        final e = row[1].toString();
        final n = int.tryParse(row[2].toString()) ?? 0;
        (porTabela[t] ??= <String, int>{})[e] = n;
      }
      // Garante uma entrada (vazia) para tabelas sem nenhuma linha.
      for (final t in tabelas) {
        porTabela.putIfAbsent(t, () => <String, int>{});
      }
      return _Contagens(porTabela, tabelas);
    } finally {
      await _fechar(conn);
    }
  }

  /// `empresaId -> nome` para deixar o relatório legível.
  ///
  /// Lê o `empresas` dos DOIS lados e junta (o local tem prioridade). Uma
  /// empresa pode existir só na nuvem — no banco local o app reescreve essa
  /// tabela conforme a sessão aberta, e aí a linha comparada da nuvem ficaria
  /// sem nome. Nunca falha a conferência: sem nome, o id é usado como rótulo.
  Future<Map<String, String>> _nomesDeEmpresas() async {
    final nomes = <String, String>{};
    for (final lado in const [true, false]) {
      try {
        final conn = await _abrir(nuvem: lado);
        try {
          final res = await conn.execute('SELECT * FROM empresas');
          for (final row in res) {
            final map = row.toColumnMap();
            final id = map['id']?.toString();
            if (id == null || id.isEmpty) continue;
            if (nomes.containsKey(id)) continue; // o lado local manda
            for (final chave in const [
              'razao_social',
              'nome_fantasia',
              'nome_exibicao',
              'nome',
              'descricao',
            ]) {
              final valor = map[chave]?.toString().trim();
              if (valor != null && valor.isNotEmpty) {
                nomes[id] = valor;
                break;
              }
            }
          }
        } finally {
          await _fechar(conn);
        }
      } catch (e) {
        debugPrint('>>> [Conferencia] ⚠️ Sem nomes de empresas '
            '(${lado ? 'nuvem' : 'local'}): $e');
      }
    }
    return nomes;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Conexões
  // ───────────────────────────────────────────────────────────────────────────

  Future<Connection> _abrir({required bool nuvem}) async {
    if (nuvem && !EnvConfig.backupBancoNuvemConfigurado) {
      throw StateError('Nuvem não configurada no .env '
          '(SUPABASE_POOLER_HOST / SUPABASE_POOLER_PASSWORD).');
    }

    final endpoint = nuvem
        ? Endpoint(
            host: EnvConfig.supabasePoolerHost,
            port: EnvConfig.supabasePoolerPort,
            database: EnvConfig.supabaseDbNameFinal,
            username: EnvConfig.supabasePoolerUser,
            password: EnvConfig.supabasePoolerPassword,
          )
        : Endpoint(
            host: EnvConfig.dbHost.toLowerCase() == 'localhost'
                ? '127.0.0.1'
                : EnvConfig.dbHost,
            port: EnvConfig.dbPort,
            database: EnvConfig.dbName,
            username: EnvConfig.dbUser,
            password: EnvConfig.dbPassword,
          );

    return Connection.open(
      endpoint,
      // A nuvem (Supabase) exige TLS; o banco local do app não usa SSL.
      settings: ConnectionSettings(
        sslMode: nuvem ? SslMode.require : SslMode.disable,
      ),
    ).timeout(_tempoLimite);
  }

  Future<void> _fechar(Connection conn) async {
    try {
      await conn.close();
    } catch (_) {}
    _encodings.remove(conn);
  }

  /// Encoding do SERVIDOR da conexão (cacheado).
  ///
  /// O banco local de algumas instalações foi criado em WIN1252 — ele não
  /// guarda símbolos como → (o Postgres recusa com 22P05). Sabendo o encoding
  /// do DESTINO, a cópia só ajusta o texto quando precisa: em nuvem UTF8 o
  /// valor vai intacto.
  Future<String> _encodingDe(Connection conn) async {
    final cache = _encodings[conn];
    if (cache != null) return cache;
    final res = await conn.execute("SELECT current_setting('server_encoding')");
    final enc = res.first[0].toString().toUpperCase();
    _encodings[conn] = enc;
    return enc;
  }

  String _mensagem(Object erro, {required bool nuvem}) {
    final texto = erro.toString();
    if (texto.toLowerCase().contains('timeout')) {
      return nuvem
          ? 'A nuvem não respondeu (timeout). Confira a internet.'
          : 'O banco local não respondeu (timeout). O PostgreSQL está ligado?';
    }
    return nuvem
        ? 'Falha ao consultar a nuvem: $texto'
        : 'Falha ao consultar o banco local: $texto';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Sincronização de diferenças
  // ───────────────────────────────────────────────────────────────────────────

  /// Sincroniza as diferenças encontradas na conferência.
  ///
  /// Para cada tabela/empresa onde há diferença:
  /// - Se local < nuvem: baixa as linhas que faltam no local
  /// - Se local > nuvem: envia as linhas que faltam na nuvem
  ///
  /// Retorna (sucesso, mensagem, quantas linhas foram sincronizadas).
  Future<(bool, String, int)> sincronizarDiferencas(
    ResultadoConferencia resultado, {
    void Function(String)? onProgress,
    bool simular = false,
    String? empresaAtiva,
  }) async {
    // Só o que dá para corrigir POR EMPRESA: telemetria e as tabelas comparadas
    // pelo total (empresas, usuarios — sem `empresa_id` nos dois lados) ficam de
    // fora da cópia, porque não existe "a empresa desta linha" para decidir o
    // que copiar. Elas continuam no relatório, como aviso.
    final naoCorrigiveis =
        resultado.comDiferenca.where((l) => !l.telemetria && l.global).toList();
    final divergentes =
        resultado.comDiferenca.where((l) => !l.telemetria && !l.global).toList();

    // A base local guarda SOMENTE a empresa aberta no app (o sincronizador da
    // bandeja apaga as outras a cada reinício/troca de empresa). Copiar as
    // outras para cá seria trabalho desfeito sozinho — então elas ficam só no
    // relatório, e a correção acontece na empresa aberta.
    final diferencas = empresaAtiva == null
        ? divergentes
        : divergentes.where((l) => l.empresaId == empresaAtiva).toList();
    final foraDoEscopo = divergentes.length - diferencas.length;

    final avisoGlobais = naoCorrigiveis.isEmpty
        ? ''
        : 'As ${naoCorrigiveis.length} tabela(s) comparada(s) pelo total '
            '(${naoCorrigiveis.map((l) => l.tabela).toSet().join(', ')}) não entram na '
            'correção automática: sem a coluna empresa_id nos dois bancos não dá para '
            'saber de qual empresa é cada linha. Conferir/criar a coluna em '
            '"Saúde dos Bancos" (Backup e Restauração).';

    if (diferencas.isEmpty) {
      return (
        true,
        [
          if (foraDoEscopo == 0)
            'Nenhuma diferença para sincronizar.'
          else
            'Nada a corrigir na empresa aberta: as $foraDoEscopo '
                'divergência(s) são de outras empresas. A base local guarda só '
                'a empresa aberta — carregar as outras aqui seria desfeito no '
                'próximo reinício do sincronizador.',
          if (avisoGlobais.isNotEmpty) avisoGlobais,
        ].join('\n'),
        0,
      );
    }

    int totalSincronizado = 0;
    int totalAjustados = 0;
    final erros = <String>[];
    final colunasIgnoradas = <String>{};

    try {
      final connLocal = await _abrir(nuvem: false);
      final connNuvem = await _abrir(nuvem: true);

      try {
        for (var i = 0; i < diferencas.length; i++) {
          final d = diferencas[i];
          onProgress?.call('Sincronizando ${d.tabela} (${i + 1}/${diferencas.length})...');

          // Quem tem MENOS linhas é o lado que recebe: o que falta nele vem do
          // outro. Empate de contagem não se corrige (não há como saber qual
          // lado mudou por último) — e por isso nem entramos aqui.
          final baixando = (d.local ?? 0) < (d.nuvem ?? 0);
          try {
            final encDestino =
                await _encodingDe(baixando ? connLocal : connNuvem);
            final copia = await _copiarFaltantes(
              origem: baixando ? connNuvem : connLocal,
              destino: baixando ? connLocal : connNuvem,
              tabela: d.tabela,
              empresaId: d.empresaId,
              baixando: baixando,
              simular: simular,
              sanitizarParaWin1252: encDestino != 'UTF8',
            );
            totalSincronizado += copia.linhas;
            totalAjustados += copia.ajustados;
            for (final c in copia.colunasIgnoradas) {
              colunasIgnoradas.add('${d.tabela}.$c');
            }
          } catch (e) {
            erros.add('${d.tabela}/${d.empresaId}: ${_mensagemCurta(e)}');
            debugPrint('>>> [Conferencia] ⚠️ Erro ao sincronizar ${d.tabela}/${d.empresaId}: $e');
          }
        }
      } finally {
        await _fechar(connLocal);
        await _fechar(connNuvem);
      }
    } catch (e) {
      return (false, 'Erro ao conectar nos bancos: $e', totalSincronizado);
    }

    final partes = <String>[
      simular
          ? '$totalSincronizado linha(s) SERIAM copiadas (nada foi gravado ainda).'
          : '$totalSincronizado linha(s) sincronizada(s).',
      if (avisoGlobais.isNotEmpty) avisoGlobais,
    ];

    if (foraDoEscopo > 0) {
      partes.add(
        'As $foraDoEscopo divergência(s) de outras empresas NÃO foram tocadas — '
        'a base local guarda só a empresa aberta.',
      );
    }

    if (colunasIgnoradas.isNotEmpty) {
      final lista = colunasIgnoradas.toList()..sort();
      partes.add(
        'Colunas que existem só de um lado foram ignoradas (${lista.length}): '
        '${lista.take(6).join(', ')}${lista.length > 6 ? '…' : ''}',
      );
    }
    if (totalAjustados > 0) {
      partes.add(
        '$totalAjustados valor(es) foram ajustados para o banco local WIN1252: '
        'símbolos que ele não guarda viram texto ASCII (ex.: → virou "->"). '
        'A nuvem mantém o valor original.',
      );
    }
    if (erros.isNotEmpty) {
      partes.add('${erros.length} tabela(s)/empresa(s) não puderam ser corrigidas:');
      partes.addAll(erros.take(6));
      if (erros.length > 6) partes.add('… e mais ${erros.length - 6}.');
    }

    return (erros.isEmpty, partes.join('\n'), totalSincronizado);
  }

  /// A mensagem que interessa de um erro do Postgres (a PgException vem com
  /// severidade, código, arquivo... e a tela só precisa do motivo).
  static String _mensagemCurta(Object erro) {
    final linhas = erro
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (linhas.isEmpty) return erro.toString();
    final msg = linhas.firstWhere(
      (l) => l.startsWith('Message:'),
      orElse: () => linhas.first,
    );
    return msg.replaceFirst('Message:', '').trim();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Cópia das linhas que faltam
  // ───────────────────────────────────────────────────────────────────────────

  /// Completa a lacuna de uma tabela/empresa: copia de [origem] para [destino]
  /// SOMENTE as linhas que ainda não existem no destino (comparadas pela chave
  /// primária). Linha que já existe dos dois lados não é tocada — a correção
  /// completa o que falta, não sobrescreve o dado de ninguém.
  ///
  /// Só as colunas existentes nos DOIS lados entram (o schema local é mais
  /// antigo que o da nuvem: há nomes de um lado que não existem no outro), e
  /// cada valor é convertido para o tipo da coluna de destino antes de ir.
  Future<_Copia> _copiarFaltantes({
    required Connection origem,
    required Connection destino,
    required String tabela,
    required String empresaId,
    required bool baixando,
    bool simular = false,
    bool sanitizarParaWin1252 = false,
  }) async {
    final nomeSql = _aspas(tabela);
    final est = await _lerEstrutura(destino, tabela);

    // Chave primária real da tabela de destino (cai para "id" se ela não tiver
    // PRIMARY KEY declarada).
    final chave = est.chave.isNotEmpty
        ? est.chave
        : (est.nomes.contains('id') ? const <String>['id'] : const <String>[]);
    if (chave.isEmpty) {
      throw StateError('a tabela não tem chave primária no destino — '
          'não dá para saber o que está faltando');
    }

    final linhas = await origem.execute(
      Sql.named("SELECT * FROM $nomeSql WHERE COALESCE(empresa_id, '') = @emp"),
      parameters: {'emp': empresaId},
    );
    if (linhas.isEmpty) return const _Copia(0, [], 0);

    final colunasOrigem = linhas.first.toColumnMap().keys.toSet();
    final colunas =
        est.colunas.where((c) => colunasOrigem.contains(c.nome)).toList();
    final ignoradas = <String>[
      ...est.colunas
          .where((c) => !colunasOrigem.contains(c.nome))
          .map((c) => c.nome),
      ...colunasOrigem.where((c) => !est.nomes.contains(c)),
    ]..sort();

    for (final k in chave) {
      if (!colunas.any((c) => c.nome == k)) {
        throw StateError('a chave "$k" não existe na origem de "$tabela"');
      }
    }

    // Coluna obrigatória no destino que não vem da origem: sem ela o INSERT
    // nunca passa (ex.: a nuvem exige clientes.nome e o local não tem a coluna).
    final faltandoObrigatorias = est.colunas
        .where((c) => c.obrigatoria && !colunasOrigem.contains(c.nome))
        .map((c) => c.nome)
        .toList();
    if (faltandoObrigatorias.isNotEmpty) {
      throw StateError('o destino exige ${faltandoObrigatorias.join(', ')} '
          '(NOT NULL sem valor padrão) e a origem não tem essa(s) coluna(s)');
    }

    // O que já existe no destino não será tocado: comparamos pelas chaves.
    final chaveSql = chave.map(_aspas).join(', ');
    final existentes = await destino.execute(
      Sql.named(
        "SELECT $chaveSql FROM $nomeSql WHERE COALESCE(empresa_id, '') = @emp",
      ),
      parameters: {'emp': empresaId},
    );
    final jaTem = <String>{};
    for (final r in existentes) {
      jaTem.add(_chaveDoMapa(r.toColumnMap(), chave));
    }

    final novas = <Map<String, Object?>>[];
    for (final r in linhas) {
      final mapa = r.toColumnMap();
      if (jaTem.add(_chaveDoMapa(mapa, chave))) novas.add(mapa);
    }
    if (novas.isEmpty) return _Copia(0, ignoradas, 0);

    // Coluna que vem sempre nula neste lote e tem padrão no destino sai do
    // INSERT: vale mais deixar o padrão do banco agir do que gravar NULL.
    final colunasDoLote = colunas
        .where((c) => c.obrigatoria || novas.any((m) => m[c.nome] != null))
        .toList();
    final colunasSql = colunasDoLote.map((c) => _aspas(c.nome)).join(', ');

    var inseridas = 0;
    var ajustados = 0;
    for (var i = 0; i < novas.length; i += _linhasPorLote) {
      final fim = i + _linhasPorLote > novas.length
          ? novas.length
          : i + _linhasPorLote;
      final lote = novas.sublist(i, fim);
      final parametros = <String, Object?>{};
      final valores = <String>[];

      for (var l = 0; l < lote.length; l++) {
        final partes = <String>[];
        for (var c = 0; c < colunasDoLote.length; c++) {
          final coluna = colunasDoLote[c];
          final nome = 'v${l}_$c';
          var valor = _valorParaParametro(lote[l][coluna.nome], coluna);
          if (sanitizarParaWin1252) {
            final limpo = Win1252.sanitizarValor(valor);
            if (limpo != valor) ajustados++;
            valor = limpo;
          }
          parametros[nome] = valor;
          // O CAST vai explícito no SQL: o parâmetro chega como texto e o
          // Postgres converte para o tipo certo (jsonb, int8, timestamptz...).
          partes.add('@$nome::${coluna.tipo}');
        }
        valores.add('(${partes.join(', ')})');
      }

      if (simular) {
        // Só conta o que seria gravado: nenhum INSERT sai daqui.
        inseridas += lote.length;
        continue;
      }

      final res = await destino.execute(
        Sql.named('INSERT INTO $nomeSql ($colunasSql) '
            'VALUES ${valores.join(', ')} ON CONFLICT DO NOTHING'),
        parameters: parametros,
      );
      inseridas += res.affectedRows;
    }

    debugPrint('>>> [Conferencia] ${simular ? '🧪 simulação' : '✅'}, '
        '${baixando ? '⬇️ nuvem → local' : '⬆️ local → nuvem'} '
        '$tabela/$empresaId: $inseridas linha(s)'
        '${ajustados > 0 ? ' — $ajustados valor(es) ajustado(s) para WIN1252' : ''}');
    return _Copia(inseridas, ignoradas, ajustados);
  }

  /// Nome real da tabela entre aspas (preserva maiúsculas e caracteres raros).
  static String _aspas(String nome) => '"${nome.replaceAll('"', '""')}"';

  static String _chaveDoMapa(Map<String, dynamic> mapa, List<String> chave) =>
      chave.map((k) => mapa[k]?.toString() ?? '').join('\u0001');

  /// Colunas e chave primária de uma tabela do banco de DESTINO.
  Future<_EstruturaTabela> _lerEstrutura(Connection conn, String tabela) async {
    final res = await conn.execute(
      Sql.named(
        'SELECT column_name, data_type, udt_name, is_nullable, '
        "COALESCE(column_default, '') AS padrao "
        'FROM information_schema.columns '
        "WHERE table_schema = 'public' AND table_name = @t "
        'ORDER BY ordinal_position',
      ),
      parameters: {'t': tabela},
    );

    final colunas = <_ColunaDestino>[];
    for (final r in res) {
      final m = r.toColumnMap();
      final udt = m['udt_name']!.toString();
      final dataType = m['data_type']!.toString();
      final padrao = m['padrao']!.toString();
      colunas.add(_ColunaDestino(
        nome: m['column_name']!.toString(),
        tipo: _tipoDeCast(dataType, udt),
        ehJson: udt == 'json' || udt == 'jsonb',
        ehInteiro: _tiposInteiros.contains(udt),
        ehArray: dataType == 'ARRAY',
        obrigatoria: m['is_nullable']!.toString() == 'NO' && padrao.isEmpty,
      ));
    }

    final pk = await conn.execute(
      Sql.named(
        'SELECT kcu.column_name FROM information_schema.table_constraints tc '
        'JOIN information_schema.key_column_usage kcu '
        '  ON kcu.constraint_name = tc.constraint_name '
        ' AND kcu.table_schema = tc.table_schema '
        "WHERE tc.table_schema = 'public' AND tc.table_name = @t "
        "  AND tc.constraint_type = 'PRIMARY KEY' "
        'ORDER BY kcu.ordinal_position',
      ),
      parameters: {'t': tabela},
    );

    return _EstruturaTabela(
      colunas,
      pk.map((r) => r[0].toString()).toList(growable: false),
    );
  }

  /// Nome do tipo para o CAST: arrays vêm como `_int4` no catálogo e precisam
  /// virar `int4[]`.
  static String _tipoDeCast(String dataType, String udt) {
    if (dataType == 'ARRAY') {
      final base = udt.startsWith('_') ? udt.substring(1) : udt;
      return '$base[]';
    }
    return udt;
  }

  static const Set<String> _tiposInteiros = {
    'int2',
    'int4',
    'int8',
    'serial4',
    'serial8',
  };

  /// Converte o valor lido de um banco no que a coluna de destino espera.
  ///
  /// É aqui que morrem os erros que a tela mostrava: `numeric` chega como texto
  /// ("0.0") e não entra em bigint; `jsonb` chega como Map/List e precisa virar
  /// JSON de verdade (o `toString()` de um Map não é JSON válido).
  static Object? _valorParaParametro(Object? v, _ColunaDestino coluna) {
    if (v == null) return null;

    if (coluna.ehJson) {
      if (v is String) {
        try {
          jsonDecode(v);
          return v; // já é JSON em texto: passa como está
        } catch (_) {
          return jsonEncode(v);
        }
      }
      return jsonEncode(v);
    }

    if (coluna.ehInteiro) {
      if (v is num) return v.round().toString();
      final numero = num.tryParse(v.toString());
      return numero == null ? v.toString() : numero.round().toString();
    }

    if (coluna.ehArray) {
      if (v is List) return _literalDeArray(v);
      return v.toString();
    }

    // O pacote devolve `time` como Time, cujo toString() é "Time(10:00:00.000)"
    // — texto que não serve para o Postgres.
    if (v is Time) {
      final us = v.microseconds;
      final falta = Duration(microseconds: us % Duration.microsecondsPerSecond);
      String dois(int n) => n.toString().padLeft(2, '0');
      return '${dois(us ~/ Duration.microsecondsPerHour)}:'
          '${dois((us ~/ Duration.microsecondsPerMinute) % 60)}:'
          '${dois((us ~/ Duration.microsecondsPerSecond) % 60)}.'
          '${falta.inMicroseconds.toString().padLeft(6, '0')}';
    }

    if (v is DateTime) return v.toIso8601String();
    if (v is bool) return v ? 'true' : 'false';
    if (v is Map || v is List) return jsonEncode(v);
    if (v is Uint8List) {
      final hex = v
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      return '\\x$hex';
    }
    return v.toString();
  }

  /// Literal de array do Postgres (`{a,b}`), com aspas em cada elemento.
  static String _literalDeArray(List<dynamic> itens) {
    String elemento(dynamic e) {
      if (e == null) return 'NULL';
      final texto = (e is Map || e is List) ? jsonEncode(e) : e.toString();
      return '"${texto.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    }

    return '{${itens.map(elemento).join(',')}}';
  }
}

/// Coluna da tabela de DESTINO (a que recebe as linhas).
class _ColunaDestino {
  final String nome;

  /// Nome do tipo para o CAST (ex.: `int8`, `jsonb`, `text[]`).
  final String tipo;
  final bool ehJson;
  final bool ehInteiro;
  final bool ehArray;

  /// NOT NULL sem valor padrão: precisa obrigatoriamente vir da origem.
  final bool obrigatoria;

  const _ColunaDestino({
    required this.nome,
    required this.tipo,
    required this.ehJson,
    required this.ehInteiro,
    required this.ehArray,
    required this.obrigatoria,
  });
}

class _EstruturaTabela {
  final List<_ColunaDestino> colunas;
  final List<String> chave;

  late final Set<String> nomes =
      colunas.map((c) => c.nome).toSet();

  _EstruturaTabela(this.colunas, this.chave);
}

/// Resultado de uma cópia: quantas linhas entraram e quais colunas ficaram de
/// fora por não existirem nos dois lados (aparecem na tela para o usuário saber
/// o que não viajou).
class _Copia {
  final int linhas;
  final List<String> colunasIgnoradas;

  /// Quantos valores precisaram ser ajustados porque o banco de destino não
  /// guarda o caractere (ex.: banco local em WIN1252 e o texto tinha →).
  final int ajustados;

  const _Copia(this.linhas, this.colunasIgnoradas, this.ajustados);
}
