import 'dart:io';
import 'package:flutter/foundation.dart';

class EnvConfig {
  static Map<String, String>? _cachedEnv;

  static Map<String, String> get env {
    if (_cachedEnv != null) return _cachedEnv!;
    _cachedEnv = _loadEnv();
    return _cachedEnv!;
  }

  static Map<String, String> _loadEnv() {
    final values = <String, String>{};
    try {
      var file = File('.env');
      
      if (!file.existsSync() && !kIsWeb) {
        try {
          final exeDir = File(Platform.resolvedExecutable).parent;
          final fallbackFile = File('${exeDir.path}${Platform.pathSeparator}.env');
          if (fallbackFile.existsSync()) {
            file = fallbackFile;
          }
        } catch (_) {}
      }

      if (file.existsSync()) {
        final lines = file.readAsLinesSync();
        for (var line in lines) {
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
        debugPrint('>>> [EnvConfig] ✅ Arquivo .env carregado com sucesso (${values.length} variáveis)');
      } else {
        debugPrint('>>> [EnvConfig] ⚠️ Arquivo .env não encontrado no diretório atual (${Directory.current.path})');
      }
    } catch (e) {
      debugPrint('>>> [EnvConfig] ❌ Erro ao ler arquivo .env: $e');
    }
    return values;
  }

  // Getters para PostgreSQL local
  static String get dbHost => env['DB_HOST'] ?? 'localhost';
  static int get dbPort => int.tryParse(env['DB_PORT'] ?? '') ?? 5432;
  static String get dbName => env['DB_NAME'] ?? 'exodo_db';
  static String get dbUser => env['DB_USER'] ?? 'exodo_user';
  static String get dbPassword => env['DB_PASSWORD'] ?? 'senha123';

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
  /// A conexão DIRETA do Supabase (db.<ref>.supabase.co) só responde em IPv6 e
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

  /// true quando há host de pooler + senha para gerar o backup do banco da nuvem.
  static bool get backupBancoNuvemConfigurado =>
      supabasePoolerHost.isNotEmpty && supabasePoolerPassword.isNotEmpty;

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
}
