import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'neon_config.dart';

class EnvConfig {
  static Map<String, String>? _cachedEnv;

  /// Caminho do `.env` EMPACOTADO junto do aplicativo (asset).
  ///
  /// No PC o `.env` fica no disco, ao lado do sistema. No celular não existe
  /// esse arquivo, então a MESMA configuração vai embutida no app e é lida
  /// daqui (ver [carregarDoAsset]).
  static const String caminhoEnvEmpacotado = 'assets/app.env';

  /// Conteúdo do `.env` empacotado, lido uma vez no boot.
  static Map<String, String>? _assetEnv;

  static Map<String, String> get env {
    if (_cachedEnv != null) return _cachedEnv!;
    _cachedEnv = _loadEnv();
    return _cachedEnv!;
  }

  /// Lê o `.env` empacotado no app (asset).
  ///
  /// Deve ser chamado UMA vez no boot (ver `main()`), antes de qualquer uso
  /// de [env]. Se o arquivo não existir, não faz nada e o app segue com os
  /// valores padrão.
  static Future<void> carregarDoAsset() async {
    try {
      final bruto = await rootBundle.loadString(caminhoEnvEmpacotado);
      final valores = _parseEnv(bruto);
      if (valores.isNotEmpty) {
        _assetEnv = valores;
        // No celular não existe `.env.neon` no disco: as credenciais do Neon
        // vêm empacotadas aqui, no mesmo arquivo de configuração do app.
        NeonConfig.definirEmbutido(valores);
        debugPrint('>>> [EnvConfig] ✅ .env empacotado carregado '
            '(${valores.length} variáveis)');
      }
    } catch (e) {
      debugPrint('>>> [EnvConfig] ℹ️ .env empacotado não encontrado ($e). '
          'Usando valores padrão.');
    }
  }

  /// Converte o texto do `.env` num mapa de chave/valor (ignora comentários e
  /// linhas vazias, e tira aspas dos valores).
  static Map<String, String> _parseEnv(String conteudo) {
    final values = <String, String>{};
    for (var line in conteudo.split('\n')) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx == -1) continue;
      final key = line.substring(0, idx).trim();
      var val = line.substring(idx + 1).trim();
      // Remover aspas se existirem
      if (val.startsWith('"') && val.endsWith('"')) {
        val = val.substring(1, val.length - 1);
      } else if (val.startsWith("'") && val.endsWith("'")) {
        val = val.substring(1, val.length - 1);
      }
      values[key] = val;
    }
    return values;
  }

  /// Arquivo `.env` em uso neste computador (null quando não existe em
  /// nenhum dos locais procurados).
  ///
  /// É por aqui que o app GRAVA configurações que o sincronizador de bandeja
  /// também precisa ler — as duas partes leem o mesmo `.env`.
  static File? get arquivoEnv => _acharArquivoEnv();

  /// Esquece o que foi lido: a próxima consulta lê o `.env` do disco de novo.
  ///
  /// Necessário depois de gravar no `.env` pela tela de configuração, senão o
  /// app continuaria usando os valores antigos até ser reiniciado.
  static void recarregar() {
    _cachedEnv = null;
  }

  /// Procura o `.env` onde ele realmente costuma estar.
  ///
  /// Além da pasta atual e da pasta do executável, sobe alguns níveis a partir
  /// das duas (o app rodando de `build\windows\x64\runner\Debug` — comum ao
  /// abrir o executável compilado direto ou por atalho — achava `.env` só lá, não
  /// achava e caía nas credenciais PADRÃO). Com a senha errada o PostgreSQL local
  /// recusa a conexão em SILÊNCIO (a leitura devolve lista vazia) e o sistema só
  /// mostra dados depois de sincronizar com a nuvem.
  static File? _acharArquivoEnv() {
    final candidatos = <String>[];
    void adicionarComPais(String caminho) {
      var dir = Directory(caminho);
      for (var nivel = 0; nivel < 5; nivel++) {
        candidatos.add('${dir.path}${Platform.pathSeparator}.env');
        final pai = dir.parent;
        if (pai.path == dir.path) break;
        dir = pai;
      }
    }

    try {
      adicionarComPais(Directory.current.path);
    } catch (_) {}
    if (!kIsWeb) {
      try {
        adicionarComPais(File(Platform.resolvedExecutable).parent.path);
      } catch (_) {}
    }

    for (final caminho in candidatos) {
      final arquivo = File(caminho);
      if (arquivo.existsSync()) return arquivo;
    }
    return null;
  }

  /// Valores definidos pelo usuário NA TELA DO CELULAR ("Configurar servidor").
  ///
  /// No Android não existe `.env` no disco para editar, então o IP do PC da
  /// loja fica salvo nas preferências do aparelho ([ConfigServidorMobile]).
  /// Estes valores têm prioridade sobre o `.env` empacotado no APK — assim o
  /// MESMO APK serve em qualquer loja.
  static final Map<String, String> _overrides = <String, String>{};

  /// Aplica (ou substitui) os valores vindos da tela de configuração.
  ///
  /// Limpa o cache para a próxima leitura já usar o endereço novo.
  static void aplicarOverrides(Map<String, String> valores) {
    if (valores.isEmpty) return;
    _overrides.addAll(valores);
    _cachedEnv = null;
  }

  /// Volta a usar apenas o `.env` (disco no PC, empacotado no celular).
  static void limparOverrides() {
    _overrides.clear();
    _cachedEnv = null;
  }

  static Map<String, String> _loadEnv() {
    final values = _loadBase();
    if (_overrides.isNotEmpty) {
      values.addAll(_overrides);
      debugPrint('>>> [EnvConfig] ℹ️ Configuração do servidor aplicada pelo '
          'celular (${_overrides.length} variáveis).');
    }
    return values;
  }

  static Map<String, String> _loadBase() {
    // 1º) PC: o `.env` do disco tem prioridade (é onde o usuário configura).
    try {
      final file = _acharArquivoEnv();
      if (file != null && file.existsSync()) {
        final values = _parseEnv(file.readAsStringSync());
        debugPrint('>>> [EnvConfig] ✅ Arquivo .env carregado de ${file.path} '
            '(${values.length} variáveis)');
        return values;
      }
    } catch (e) {
      debugPrint('>>> [EnvConfig] ❌ Erro ao ler arquivo .env do disco: $e');
    }

    // 2º) Celular (ou PC sem .env no disco): usa o `.env` EMPACOTADO no app.
    if (_assetEnv != null && _assetEnv!.isNotEmpty) {
      debugPrint('>>> [EnvConfig] ✅ Usando o .env empacotado no aplicativo '
          '(${_assetEnv!.length} variáveis).');
      return Map<String, String>.of(_assetEnv!);
    }

    debugPrint('>>> [EnvConfig] ⚠️ Nenhum .env encontrado (nem no disco nem '
        'empacotado). Usando os valores padrão — o banco NÃO vai conectar '
        'com eles.');
    return <String, String>{};
  }

  // Getters para PostgreSQL local
  static String get dbHost => env['DB_HOST'] ?? 'localhost';

  /// Endereço alternativo quando [dbHost] é um NOME que a rede não resolve.
  ///
  /// O Android não usa NetBIOS/mDNS no resolvedor do sistema: um nome como
  /// `DESKTOP-86UT1R1` só funciona se o roteador tiver DNS local. Quando não
  /// resolve, o app tenta este IP automaticamente (ver `DatabaseService`).
  static String get dbHostFallback => (env['DB_HOST_FALLBACK'] ?? '').trim();

  static int get dbPort => int.tryParse(env['DB_PORT'] ?? '') ?? 5432;
  static String get dbName => env['DB_NAME'] ?? 'exodo_db';
  static String get dbUser => env['DB_USER'] ?? 'exodo_user';
  static String get dbPassword => env['DB_PASSWORD'] ?? 'senha123';

  // ── NUVEM (fallback quando o celular está fora da loja) ──────────────────
  //
  // Deixe DB_CLOUD_HOST vazio enquanto não existir um endereço público para a
  // nuvem local. Quando existir (VPS/relay), basta preencher no `app.env` e
  // gerar o APK de novo: o app tenta o PC primeiro e a nuvem em seguida.

  /// Host público da nuvem (vazio = sem fallback de nuvem).
  static String get dbCloudHost => (env['DB_CLOUD_HOST'] ?? '').trim();

  static int get dbCloudPort =>
      int.tryParse((env['DB_CLOUD_PORT'] ?? '').trim()) ?? dbPort;

  static String get dbCloudName {
    final valor = (env['DB_CLOUD_NAME'] ?? '').trim();
    return valor.isEmpty ? dbName : valor;
  }

  static String get dbCloudUser {
    final valor = (env['DB_CLOUD_USER'] ?? '').trim();
    return valor.isEmpty ? dbUser : valor;
  }

  static String get dbCloudPassword {
    final valor = (env['DB_CLOUD_PASSWORD'] ?? '').trim();
    return valor.isEmpty ? dbPassword : valor;
  }

  /// TLS na nuvem. Padrão ligado (Neon e relays com stunnel exigem).
  static bool get dbCloudSsl =>
      (env['DB_CLOUD_SSL'] ?? 'true').trim().toLowerCase() != 'false';

  // Getters para Supabase PostgreSQL (conexão direta para criar tabelas etc.)
  static String get supabaseDbHost => env['SUPABASE_DB_HOST'] ?? '';
  static int get supabaseDbPort => int.tryParse(env['SUPABASE_DB_PORT'] ?? '') ?? 5432;
  static String get supabaseDbName => env['SUPABASE_DB_NAME'] ?? 'postgres';
  static String get supabaseDbUser => env['SUPABASE_DB_USER'] ?? 'postgres';
  static String get supabaseDbPassword => env['SUPABASE_DB_PASSWORD'] ?? '';
  static bool get supabaseDbAvailable => supabaseDbHost.isNotEmpty && supabaseDbPassword.isNotEmpty;

  // Getter para Personal Access Token (PAT) do Supabase Management API
  static String get supabaseAccessToken => env['SUPABASE_ACCESS_TOKEN'] ?? '';
  static bool get supabaseAccessTokenAvailable => supabaseAccessToken.isNotEmpty;

  // ==========================================================================
  // BACKUP DO BANCO INTEIRO DA NUVEM (Supabase PostgreSQL)
  // ==========================================================================
  //
  // IMPORTANTE: o host DIRETO do Supabase (db.<ref>.supabase.co) só responde em
  // IPv6 — em muitos PCs o nome nem resolve, e o pg_dump falha. Para funcionar no
  // IPv4 é preciso usar o "Session pooler". Copie o host em:
  //   Supabase Dashboard -> botão "Connect" (ou Project Settings -> Database)
  //   -> Connection string -> Session pooler
  // e coloque no .env:
  //   SUPABASE_POOLER_HOST=aws-0-<regiao>.pooler.supabase.com
  // (a senha é a mesma já usada em SUPABASE_DB_PASSWORD)

  /// Ref do projeto Supabase, extraído de SUPABASE_URL (ex.: febffvlpvxtiihvnfuts).
  static String get supabaseProjectRef {
    final match = RegExp(r'https?://([a-z0-9]+)\.supabase\.co')
        .firstMatch(env['SUPABASE_URL'] ?? '');
    return match?.group(1) ?? '';
  }

  /// Região do "Session pooler" (IPv4) do projeto Supabase do Sistema Êxodo.
  ///
  /// O prefixo `aws-1-` é a geração atual do pooler do Supabase e `us-west-2`
  /// é a região onde este projeto está hospedado (confirmado consultando o
  /// banco). Isto é só o padrão: para apontar para outro projeto/região basta
  /// definir SUPABASE_POOLER_HOST no .env.
  static const String _regiaoPoolerPadrao = 'aws-1-us-west-2';

  /// Host do pooler (IPv4) do banco da nuvem.
  ///
  /// A conexão DIRETA do Supabase (`db.<ref>.supabase.co`) só responde em IPv6 e
  /// não funciona na maioria dos PCs, então o padrão já é o pooler — assim o
  /// backup do banco da nuvem funciona sem precisar configurar nada.
  static String get supabasePoolerHost {
    final informado = (env['SUPABASE_POOLER_HOST'] ?? '').trim();
    if (informado.isNotEmpty) return informado;
    return '$_regiaoPoolerPadrao.pooler.supabase.com';
  }

  /// Senha usada na conexão do pooler.
  ///
  /// Usa SUPABASE_POOLER_PASSWORD quando existir e, para compatibilidade, cai
  /// para SUPABASE_DB_PASSWORD. Atenção: a senha do BANCO (a mesma do painel do
  /// Supabase, em "Database password") é diferente das chaves de API
  /// `sb_secret_*` usadas em SUPABASE_ANON_KEY/SUPABASE_ACCESS_TOKEN.
  static String get supabasePoolerPassword {
    final pooler = (env['SUPABASE_POOLER_PASSWORD'] ?? '').trim();
    if (pooler.isNotEmpty) return pooler;
    return (env['SUPABASE_DB_PASSWORD'] ?? '').trim();
  }

  /// Porta do pooler. Precisa ser a porta de SESSÃO (5432), não a de transação.
  static int get supabasePoolerPort =>
      int.tryParse(env['SUPABASE_POOLER_PORT'] ?? '') ?? 5432;

  /// Usuário do pooler. No Supabase ele tem o formato `postgres.<ref>`,
  /// que é derivado automaticamente quando não informado no .env.
  static String get supabasePoolerUser {
    final informado = (env['SUPABASE_POOLER_USER'] ?? '').trim();
    if (informado.isNotEmpty) return informado;
    final ref = supabaseProjectRef;
    return ref.isEmpty ? 'postgres' : 'postgres.$ref';
  }

  /// Nome do banco na nuvem (no Supabase é sempre `postgres`).
  static String get supabaseDbNameFinal =>
      (env['SUPABASE_DB_NAME'] ?? '').trim().isEmpty ? 'postgres' : env['SUPABASE_DB_NAME']!.trim();

  /// true quando há como abrir uma conexão direta com o banco da NUVEM.
  ///
  /// O Neon é o provedor PRINCIPAL (`DATABASE_URL` no `.env.neon`); o Supabase
  /// (pooler IPv4) entra só como SEGUNDA OPÇÃO. Sem essa ordem, um PC com o
  /// `.env.neon` completo continuaria dizendo "nuvem não configurada" porque o
  /// Supabase não responde mais.
  static bool get backupBancoNuvemConfigurado =>
      NeonConfig.postgresDiretoDisponivel ||
      (supabasePoolerHost.isNotEmpty && supabasePoolerPassword.isNotEmpty);

  /// Intervalo, em horas, entre os backups COMPLETOS do banco da nuvem
  /// (a cópia de TODAS as empresas arquivada na própria nuvem).
  ///
  /// Padrão: 24 (igual aos outros backups automáticos). Configure no .env com
  /// `BACKUP_COMPLETO_NUVEM_HORAS=168` para semanal, por exemplo. Use 0 (ou um
  /// valor negativo) para DESLIGAR o backup completo automático — o botão na
  /// tela continua funcionando.
  static int get backupCompletoNuvemHoras {
    final bruto = (env['BACKUP_COMPLETO_NUVEM_HORAS'] ?? '').trim();
    if (bruto.isEmpty) return 24;
    final valor = int.tryParse(bruto);
    if (valor == null) return 24;
    return valor < 0 ? 0 : valor;
  }

  /// true quando o backup COMPLETO automático está ligado.
  static bool get backupCompletoNuvemAtivo => backupCompletoNuvemHoras > 0;

  // ==========================================================================
  // NEON (substituindo o Supabase)
  // ==========================================================================
  //
  // As credenciais do Neon ficam no arquivo `.env.neon` (gravado por
  // `neon env pull --file .env.neon`) — separadas do `.env` principal de
  // propósito, porque lá a chave `DATABASE_URL` já é usada por outros
  // serviços. No celular os mesmos valores vêm de `assets/app.env`.
  //
  // Toda a lógica de leitura e acesso está em `NeonConfig` e `NeonService`.

  /// Conexão pooled do Postgres do Neon (vazia quando não configurado).
  static String get neonDatabaseUrl => NeonConfig.databaseUrl;

  /// true quando existe ao menos um serviço do Neon configurado.
  static bool get neonDisponivel => NeonConfig.configurado;

  /// Serviços do Neon com credenciais presentes.
  static List<String> get neonServicos => NeonConfig.servicosConfigurados;

  /// URL base do Neon Auth (Better Auth).
  static String get neonAuthBaseUrl => NeonConfig.authBaseUrl;

  /// Bucket padrão do Neon Object Storage.
  static String get neonStorageBucket => NeonConfig.storageBucket;
}
