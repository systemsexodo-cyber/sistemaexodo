import 'dart:io';

/// Configuração do Neon lida do arquivo `.env.neon`.
///
/// Este arquivo é gravado pelo comando `neon env pull --file .env.neon` e
/// contém as credenciais dos serviços provisionados no Neon (Postgres, Auth,
/// Object Storage e Functions).
///
/// IMPORTANTE: este leitor mantém o `.env.neon` SEPARADO do `.env` principal.
/// O `.env` do sistema já usa a chave `DATABASE_URL` para outra finalidade
/// (serviços Python/Node), então fazer merge dos dois mapas trocaria o
/// significado dessa variável. Aqui os valores do Neon são resolvidos apenas
/// dentro deste arquivo, com nomes alternativos (`NEON_*`) como prioridade.
///
/// É Dart puro (só `dart:io`), de propósito: assim o mesmo código é exercitado
/// por um script de linha de comando (`dart run tool/neon_e2e.dart`) sem
/// precisar subir o Flutter.
class NeonConfig {
  /// Nome do arquivo com as credenciais do Neon.
  static const String nomeArquivo = '.env.neon';

  /// Bucket padrão criado pelo `neon deploy` quando `neon.ts` não informa outro.
  static const String bucketPadrao = 'assets';

  static Map<String, String>? _cacheArquivo;

  /// Valores aplicados em tempo de execução, com prioridade sobre o arquivo.
  ///
  /// Serve para os testes desligarem a nuvem sem precisar mexer no `.env.neon`
  /// da máquina (o arquivo real continua sendo lido pelo app). Um valor vazio
  /// aqui DESLIGA a chave de propósito — é assim que o teste garante que
  /// nenhuma chamada de rede vai acontecer.
  static final Map<String, String> _overrides = <String, String>{};

  /// Valores vindos do app empacotado (`assets/app.env`) — usado no celular,
  /// onde não existe `.env.neon` no disco. Preenchido por [definirEmbutido].
  static Map<String, String> _embutido = const {};

  /// Aplica (ou substitui) valores de configuração com prioridade sobre o
  /// `.env.neon`. Usado pelos testes e disponível para telas de configuração.
  static void aplicarOverrides(Map<String, String> valores) {
    if (valores.isEmpty) return;
    _overrides.addAll(valores);
    _cacheArquivo = null;
  }

  /// Volta a usar apenas o `.env.neon` (e o app empacotado, no celular).
  static void limparOverrides() {
    _overrides.clear();
    _cacheArquivo = null;
  }

  /// Fornece os valores empacotados no aplicativo (celular).
  static void definirEmbutido(Map<String, String> valores) {
    _embutido = Map.unmodifiable(valores);
  }

  /// Esquece o `.env.neon` já lido: a próxima consulta lê o disco de novo.
  static void recarregar() {
    _cacheArquivo = null;
  }

  static Map<String, String> get _bruto => _cacheArquivo ??= _lerArquivo();

  /// Procura o `.env.neon` na pasta atual e na pasta do executável, subindo
  /// alguns níveis (mesma estratégia do `.env` principal, porque o app roda de
  /// dentro de `build\windows\x64\runner\Debug` quando aberto pelo atalho).
  static File? _acharArquivo() {
    final candidatos = <String>[];
    void adicionarComPais(String caminho) {
      var dir = Directory(caminho);
      for (var nivel = 0; nivel < 5; nivel++) {
        candidatos.add('${dir.path}${Platform.pathSeparator}$nomeArquivo');
        final pai = dir.parent;
        if (pai.path == dir.path) break;
        dir = pai;
      }
    }

    try {
      adicionarComPais(Directory.current.path);
    } catch (_) {}
    try {
      adicionarComPais(File(Platform.resolvedExecutable).parent.path);
    } catch (_) {}

    for (final caminho in candidatos) {
      final arquivo = File(caminho);
      if (arquivo.existsSync()) return arquivo;
    }
    return null;
  }

  static Map<String, String> _lerArquivo() {
    try {
      final arquivo = _acharArquivo();
      if (arquivo == null) return const {};
      return _parseEnv(arquivo.readAsStringSync());
    } catch (_) {
      return const {};
    }
  }

  /// Converte o texto do `.env` num mapa (ignora comentários/linhas vazias e
  /// remove aspas dos valores).
  static Map<String, String> parseEnv(String conteudo) => _parseEnv(conteudo);

  static Map<String, String> _parseEnv(String conteudo) {
    final values = <String, String>{};
    for (var line in conteudo.split(RegExp(r'\r?\n'))) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx == -1) continue;
      final key = line.substring(0, idx).trim();
      var val = line.substring(idx + 1).trim();
      if (val.length >= 2 && val.startsWith('"') && val.endsWith('"')) {
        val = val.substring(1, val.length - 1);
      } else if (val.length >= 2 && val.startsWith("'") && val.endsWith("'")) {
        val = val.substring(1, val.length - 1);
      }
      values[key] = val;
    }
    return values;
  }

  /// Resolve um valor testando os nomes em [chaves] (na ordem) primeiro no
  /// `.env.neon` e depois nos valores empacotados no app.
  static String _resolver(List<String> chaves) {
    for (final chave in chaves) {
      // Override vem primeiro e VALE MESMO VAZIO: é ele que desliga a nuvem
      // num teste, sem depender de existir (ou não) um `.env.neon` na máquina.
      final override = _overrides[chave];
      if (override != null) return override.trim();
      final doNeon = _bruto[chave];
      if (doNeon != null && doNeon.trim().isNotEmpty) return doNeon.trim();
      final doApp = _embutido[chave];
      if (doApp != null && doApp.trim().isNotEmpty) return doApp.trim();
    }
    return '';
  }

  // ==========================================================================
  // Postgres
  // ==========================================================================

  /// String de conexão pooled (recomendada para o app).
  static String get databaseUrl =>
      _resolver(['NEON_DATABASE_URL', 'DATABASE_URL']);

  /// String de conexão direta (sem pooler) — para migrations/pg_dump.
  static String get databaseUrlUnpooled =>
      _resolver(['NEON_DATABASE_URL_UNPOOLED', 'DATABASE_URL_UNPOOLED']);

  static bool get postgresDisponivel => databaseUrl.isNotEmpty;

  /// Host/porta/banco/usuário/senha do Postgres do Neon, já separados para
  /// abrir uma conexão direta (é o que o `pg_dump`/`psql` e a conferência
  /// local × nuvem precisam). Vazio quando o `.env.neon` não tem a string de
  /// conexão.
  ///
  /// A conexão DIRETA (unpooled) vem primeiro: é ela que aceita `pg_dump`,
  /// migração e comandos de sessão. A pooled é o segundo caminho.
  static ({String host, int porta, String banco, String usuario, String senha})
      get postgresNuvem {
    for (final url in [databaseUrlUnpooled, databaseUrl]) {
      final texto = url.trim();
      if (texto.isEmpty) continue;
      try {
        final uri = Uri.parse(texto);
        final host = uri.host.trim();
        if (host.isEmpty) continue;
        final info = uri.userInfo;
        final separador = info.indexOf(':');
        return (
          host: host,
          porta: uri.hasPort ? uri.port : 5432,
          banco: uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty
              ? uri.pathSegments.first
              : 'neondb',
          usuario: Uri.decodeComponent(
              separador == -1 ? info : info.substring(0, separador)),
          senha: separador == -1
              ? ''
              : Uri.decodeComponent(info.substring(separador + 1)),
        );
      } catch (_) {
        // URL malformada: tenta a próxima.
      }
    }
    return (host: '', porta: 5432, banco: '', usuario: '', senha: '');
  }

  /// true quando dá para abrir uma conexão Postgres direta com o Neon.
  static bool get postgresDiretoDisponivel => postgresNuvem.host.isNotEmpty;

  // ==========================================================================
  // Data API (PostgREST) — a "porta REST" usada pelo app no lugar do PostgREST
  // do Supabase. O valor já inclui o sufixo `/rest/v1`.
  // ==========================================================================

  static String get dataApiUrl => _resolver([
        'NEON_DATA_API_URL',
        'NEON_DATA_API_BASE_URL',
      ]);

  static bool get dataApiDisponivel => dataApiUrl.isNotEmpty;

  /// Chave estática da Data API (`NEON_DATA_API_KEY`).
  ///
  /// Quando existe, o cliente NÃO precisa do Neon Auth: a própria chave é usada
  /// como `apikey` e como `Authorization: Bearer`. É o modelo do Supabase (chave
  /// do projeto embutida no cliente), usado quando a nuvem é o **Supabase local**
  /// publicado pelo Tailscale Funnel — o gateway do Supabase exige `apikey` válido
  /// e não tem o endpoint `/token/anonymous` do Neon.
  ///
  /// Vazio = comportamento Neon original, idêntico ao de antes.
  static String get dataApiKey => _resolver(['NEON_DATA_API_KEY']);
  static bool get dataApiKeyDisponivel => dataApiKey.isNotEmpty;

  // ==========================================================================
  // Auth (Neon Auth / Better Auth)
  // ==========================================================================

  static String get authBaseUrl => _resolver(['NEON_AUTH_BASE_URL']);
  static String get authJwksUrl => _resolver(['NEON_AUTH_JWKS_URL']);
  static bool get authDisponivel => authBaseUrl.isNotEmpty;

  // ==========================================================================
  // Functions
  // ==========================================================================

  /// URL base da função `hello` criada pelo scaffold do `neon deploy`.
  static String get functionsHelloUrl =>
      _resolver(['NEON_FUNCTION_HELLO_BASE_URL', 'NEON_FUNCTIONS_URL']);

  static bool get functionsDisponiveis => functionsHelloUrl.isNotEmpty;

  // ==========================================================================
  // Object Storage (S3)
  // ==========================================================================

  static String get storageEndpoint =>
      _resolver(['NEON_AWS_ENDPOINT_URL_S3', 'AWS_ENDPOINT_URL_S3']);
  static String get storageRegion =>
      _resolver(['NEON_AWS_REGION', 'AWS_REGION']);
  static String get storageAccessKey =>
      _resolver(['NEON_AWS_ACCESS_KEY_ID', 'AWS_ACCESS_KEY_ID']);
  static String get storageSecretKey =>
      _resolver(['NEON_AWS_SECRET_ACCESS_KEY', 'AWS_SECRET_ACCESS_KEY']);
  static String get storageBucket =>
      _resolver(['NEON_STORAGE_BUCKET']).isEmpty
          ? bucketPadrao
          : _resolver(['NEON_STORAGE_BUCKET']);

  static bool get storageDisponivel =>
      storageEndpoint.isNotEmpty &&
      storageRegion.isNotEmpty &&
      storageAccessKey.isNotEmpty &&
      storageSecretKey.isNotEmpty;

  // ==========================================================================
  // Realtime (Live SQL API) — push de mudanças por WebSocket
  // ==========================================================================
  //
  // Vem de `neon env pull --service realtime --file .env.neon`:
  //   NEON_REALTIME_URL=wss://<branch>-neonrealtimesocket...
  //   NEON_REALTIME_SECRET=nrt_live_1<32 bytes em base64url>
  //
  // O SEGREDO assina qualquer consulta (equivale a leitura total do banco).
  // Por isso ele entra no `.env.neon` (PC e celular) mas NÃO no pacote do site
  // publicado — ver tool/limpa_segredos_web.ps1.

  /// WebSocket do Neon Realtime. Vazio quando não configurado.
  static String get realtimeUrl => _resolver(['NEON_REALTIME_URL']);

  /// Segredo compartilhado usado para assinar (selar) as consultas ao vivo.
  static String get realtimeSecret => _resolver(['NEON_REALTIME_SECRET']);

  static bool get realtimeDisponivel =>
      realtimeUrl.isNotEmpty && realtimeSecret.isNotEmpty;

  /// Banco que vai dentro do selo (o serviço usa para escolher o database).
  static String get realtimeDatabase {
    final banco = postgresNuvem.banco;
    return banco.isEmpty ? 'neondb' : banco;
  }

  // ==========================================================================
  // Resumo
  // ==========================================================================

  /// true quando ao menos um serviço do Neon está configurado.
  static bool get configurado =>
      postgresDisponivel ||
      dataApiDisponivel ||
      authDisponivel ||
      functionsDisponiveis ||
      storageDisponivel;

  /// Nomes dos serviços configurados (para logs).
  static List<String> get servicosConfigurados {
    final lista = <String>[];
    if (postgresDisponivel) lista.add('postgres');
    if (dataApiDisponivel) lista.add('data-api');
    if (authDisponivel) lista.add('auth');
    if (functionsDisponiveis) lista.add('functions');
    if (storageDisponivel) lista.add('object-storage');
    return lista;
  }
}
