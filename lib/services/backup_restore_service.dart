import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, BucketOptions, SupabaseClient;
import '../supabase_config.dart';
import 'data_service.dart';
import 'database_service.dart';
import 'env_config.dart';
import 'process_utils.dart';
import 'supabase_service.dart';
import '../pages/html_helper_stub.dart'
    if (dart.library.html) '../pages/html_helper_web.dart' as html_helper;

/// Serviço para gerenciar Backup e Restauração por empresa
/// 
/// - Backup: Exporta todos os dados da empresa para um arquivo .json
/// - Restore: Importa dados de um arquivo .json de volta para o sistema
/// - Listar backups salvos
class BackupRestoreService {
  final DataService _dataService;

  BackupRestoreService(this._dataService);

  /// Cliente de STORAGE com a chave service_role (passa por cima do RLS).
  /// O cliente principal (Supabase.instance.client) usa o token do usuário
  /// logado — e os buckets de backup/dump podem não ter políticas de RLS para
  /// o papel 'authenticated', o que causa erro 42501 ("row-level security") no
  /// upload. Com a chave service_role (sem sessão), buckets e arquivos são
  /// acessados livremente — é a MESMA chave que o app já usa para sincronizar
  /// as tabelas (ver supabase_config.dart).
  SupabaseClient? _storageAdmin;
  SupabaseClient get _storageAdminClient => _storageAdmin ??= SupabaseClient(
    SupabaseConfig.url,
    SupabaseConfig.anonKey,
  );

  // ============================================================
  // BACKUP - Exportar dados da empresa para JSON
  // ============================================================

  /// Gera o backup completo da empresa atual e retorna como Map
  Map<String, dynamic> gerarBackup() {
    return _dataService.exportarBackupCompleto();
  }

  /// Gera backup e salva em arquivo - retorna caminho do arquivo
  Future<String?> salvarBackupEmArquivo() async {
    try {
      final backup = gerarBackup();
      final json = const JsonEncoder.withIndent('  ').convert(backup);
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final empresaNome = _dataService.empresaAtual?.nomeExibicao?.replaceAll(RegExp(r'[^\w\s]'), '_') ?? 'empresa';
      final fileName = 'backup_${empresaNome}_$timestamp.json';

      if (kIsWeb) {
        html_helper.downloadFile(json, fileName, 'application/json');
        return fileName;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final backupDir = Directory(p.join(dir.path, 'exodo_backups'));
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }
        final file = File(p.join(backupDir.path, fileName));
        await file.writeAsString(json, flush: true);
        await _registrarNoHistorico(fileName, file.lengthSync());
        debugPrint('>>> [BackupRestore] ✅ Backup salvo: ${file.path}');
        return file.path;
      }
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro: $e');
      return null;
    }
  }

  /// Salva backup automaticamente na pasta C:\ExodoBackups.
  /// Usado pelo timer diário. Mantém apenas os últimos 30 backups.
  /// Retorna o caminho do arquivo ou null se falhar.
  Future<String?> salvarBackupLocalAutomatico() async {
    try {
      final empresaId = _dataService.currentEmpresaId;
      if (empresaId == null) return null;

      final empresaNome = _dataService.empresaAtual?.nomeExibicao?.replaceAll(RegExp(r'[^\w\s]'), '_') ?? 'empresa';
      final now = DateTime.now();
      final dataStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final horaStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'backup_${empresaNome}_${dataStr}_${horaStr}.json';

      // Pasta fixa: C:\ExodoBackups\{empresaId}\
      final backupDir = Directory('C:\\ExodoBackups\\$empresaId');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Gerar backup
      final backup = gerarBackup();
      final json = const JsonEncoder.withIndent('  ').convert(backup);
      final file = File(p.join(backupDir.path, fileName));
      await file.writeAsString(json, flush: true);

      debugPrint('>>> [BackupRestore] 💾 Backup local automático: ${file.path} (${(file.lengthSync() / 1024).toStringAsFixed(0)} KB)');

      // Limpar backups antigos (manter apenas últimos 30)
      await _limparBackupsAntigos(backupDir, maxBackups: 30);

      return file.path;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro no backup local automático: $e');
      return null;
    }
  }

  /// Remove backups antigos, mantendo apenas os mais recentes
  Future<void> _limparBackupsAntigos(Directory dir, {int maxBackups = 30}) async {
    try {
      final files = await dir.list()
          .where((f) => f is File && f.path.endsWith('.json'))
          .cast<File>()
          .toList();

      if (files.length <= maxBackups) return;

      // Ordenar por data de modificação (mais antigo primeiro)
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      // Remover os mais antigos
      final paraRemover = files.length - maxBackups;
      for (int i = 0; i < paraRemover; i++) {
        await files[i].delete();
        debugPrint('>>> [BackupRestore] 🗑️ Backup antigo removido: ${p.basename(files[i].path)}');
      }
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Erro ao limpar backups antigos: $e');
    }
  }

  Future<void> _registrarNoHistorico(String fileName, int tamanho) async {
    if (kIsWeb || _dataService.currentEmpresaId == null) return;
    try {
      final chave = 'backups_${_dataService.currentEmpresaId}';
      final db = DatabaseService();
      final existente = await db.carregarConfig(chave);
      List<Map<String, dynamic>> historico = [];
      if (existente is List) {
        historico = existente.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      historico.insert(0, {
        'arquivo': fileName,
        'data': DateTime.now().toIso8601String(),
        'tamanho': tamanho,
        'empresa': _dataService.empresaAtual?.nomeExibicao ?? '',
      });
      if (historico.length > 20) historico = historico.sublist(0, 20);
      await db.salvarConfig(chave, historico);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ $e');
    }
  }

  /// Lista o histórico de backups da empresa
  Future<List<Map<String, dynamic>>> listarHistoricoBackups() async {
    if (kIsWeb || _dataService.currentEmpresaId == null) return [];
    try {
      final chave = 'backups_${_dataService.currentEmpresaId}';
      final valor = await DatabaseService().carregarConfig(chave);
      if (valor is List) return valor.map((e) => Map<String, dynamic>.from(e)).toList();
      return [];
    } catch (e) {
      return [];
    }
  }

  // ============================================================
  // BACKUP EM NUVEM (Supabase Storage)
  // ============================================================

  /// Faz upload do backup JSON para o Supabase Storage.
  /// Nome do arquivo: backup_{empresa}_{data}.json
  /// Retorna (sucesso, mensagem, caminho_do_arquivo)
  Future<(bool, String, String?)> uploadBackupNaNuvem() async {
    try {
      final empresaId = _dataService.currentEmpresaId;
      if (empresaId == null) return (false, 'Empresa não selecionada', null);

      final empresaNome = _dataService.empresaAtual?.nomeExibicao?.replaceAll(RegExp(r'[^\w\s]'), '_') ?? 'empresa';
      final now = DateTime.now();
      final dataStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final horaStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'backup_${empresaNome}_${dataStr}_${horaStr}.json';
      final storagePath = 'backups/$empresaId/$fileName';

      debugPrint('>>> [BackupRestore] ☁️ Preparando backup para nuvem: $fileName');

      // 1. Gerar backup
      final backup = gerarBackup();
      final json = const JsonEncoder.withIndent('  ').convert(backup);
      final bytes = Uint8List.fromList(utf8.encode(json));

      debugPrint('>>> [BackupRestore] 📏 Tamanho: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB');

      // 2. Upload para Supabase Storage
      const bucketName = 'backups';
      try {
        await _storageAdminClient.storage
            .from(bucketName)
            .uploadBinary(storagePath, bytes,
                fileOptions: const FileOptions(upsert: true));
      } catch (e) {
        // Se o bucket não existe, tentar criá-lo
        debugPrint('>>> [BackupRestore] ⚠️ Erro no upload, tentando criar bucket...');
        try {
          await _storageAdminClient.storage.createBucket(
            bucketName,
            const BucketOptions(public: false),
          );
          await _storageAdminClient.storage
              .from(bucketName)
              .uploadBinary(storagePath, bytes,
                  fileOptions: const FileOptions(upsert: true));
        } catch (e2) {
          return (false, 'Erro ao criar bucket ou fazer upload: ${_mensagemErroStorage(e2)}', null);
        }
      }

      debugPrint('>>> [BackupRestore] ✅ Backup enviado para nuvem: $storagePath');

      // 3. Registrar no histórico
      await _registrarNoHistorico('☁️ $fileName', bytes.length);

      // 4. Manter apenas os últimos backups desta empresa (a nuvem não deve crescer sem limite)
      await _limparBackupsNuvemAntigos(empresaId, maxBackups: _maxBackupsNuvemPorEmpresa);

      return (true, 'Backup enviado para a nuvem com sucesso!', storagePath);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao enviar backup para nuvem: $e');
      return (false, 'Erro ao enviar backup: ${_mensagemErroStorage(e)}', null);
    }
  }

  /// Converte erros de Storage do Supabase em mensagens amigáveis, com dica
  /// quando o problema for de permissão/RLS do bucket.
  String _mensagemErroStorage(Object erro) {
    final msg = erro.toString();
    final mais = msg.replaceAll('Exception: ', '').replaceAll('StorageException: ', '');
    if (msg.contains('42501') ||
        msg.toLowerCase().contains('row-level security') ||
        msg.toLowerCase().contains('policy') ||
        msg.toLowerCase().contains('permission denied')) {
      return '$mais. → Permissão de Storage no Supabase: crie os buckets "backups" e "dumps" e as políticas de acesso no SQL Editor (veja o arquivo CRIAR_BUCKETS_STORAGE_SUPABASE.sql).';
    }
    return mais;
  }

  /// Quantos backups JSON de cada empresa são mantidos na nuvem.
  static const int _maxBackupsNuvemPorEmpresa = 30;

  /// Mantém apenas os [maxBackups] backups JSON mais recentes da empresa no
  /// bucket 'backups'. Cada empresa tem sua própria pasta (`backups/{empresaId}/`),
  /// então a limpeza nunca afeta outras empresas.
  Future<void> _limparBackupsNuvemAntigos(String empresaId, {int maxBackups = 30}) async {
    try {
      const bucketName = 'backups';
      final prefix = 'backups/$empresaId/';

      final files = await _storageAdminClient.storage
          .from(bucketName)
          .list(path: prefix);

      if (files.length <= maxBackups) return;

      // Mais recente primeiro
      final ordenados = files.toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a.createdAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final db = DateTime.tryParse(b.createdAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

      final antigos = ordenados.sublist(maxBackups);
      final caminhos = antigos.map((f) => '$prefix${f.name}').toList();
      if (caminhos.isEmpty) return;

      await _storageAdminClient.storage.from(bucketName).remove(caminhos);
      debugPrint('>>> [BackupRestore] 🗑️ ${caminhos.length} backup(s) JSON antigo(s) removido(s) da nuvem (empresa $empresaId)');
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Erro ao limpar backups JSON antigos: $e');
    }
  }

  /// Lista backups salvos na nuvem para a empresa atual
  Future<List<Map<String, dynamic>>> listarBackupsNuvem() async {
    try {
      final empresaId = _dataService.currentEmpresaId;
      if (empresaId == null) return [];

      const bucketName = 'backups';
      final prefix = 'backups/$empresaId/';

      final files = await _storageAdminClient.storage
          .from(bucketName)
          .list(path: prefix);

      return files.map((f) => {
        'name': f.name,
        'path': '$prefix${f.name}',
        'size': (f.metadata?['size'] as num?)?.toInt() ?? 0,
        'createdAt': f.createdAt ?? '',
      }).toList();
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Erro ao listar backups da nuvem: $e');
      return [];
    }
  }

  /// Baixa um backup da nuvem e restaura os dados
  Future<(bool, String)> restaurarBackupDaNuvem(String storagePath) async {
    try {
      const bucketName = 'backups';

      debugPrint('>>> [BackupRestore] ☁️ Baixando backup da nuvem: $storagePath');

      // 1. Baixar o arquivo
      final bytes = await _storageAdminClient.storage
          .from(bucketName)
          .download(storagePath);

      if (bytes.isEmpty) return (false, 'Arquivo vazio ou não encontrado');

      // 2. Decodificar JSON
      final jsonStr = utf8.decode(bytes);
      final backup = jsonDecode(jsonStr) as Map<String, dynamic>;

      debugPrint('>>> [BackupRestore] 📥 Backup baixado: ${(bytes.length / 1024).toStringAsFixed(0)} KB');

      // 3. Restaurar dados
      await _dataService.importarBackup(backup);

      debugPrint('>>> [BackupRestore] ✅ Backup da nuvem restaurado com sucesso!');
      return (true, 'Backup restaurado da nuvem com sucesso!');
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao restaurar backup da nuvem: $e');
      return (false, 'Erro ao restaurar backup da nuvem: $e');
    }
  }

  /// Remove um backup da nuvem
  Future<bool> removerBackupNuvem(String storagePath) async {
    try {
      await _storageAdminClient.storage
          .from('backups')
          .remove([storagePath]);
      return true;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao remover backup: $e');
      return false;
    }
  }

  // ============================================================
  // RESTORE
  // ============================================================

  /// Abre o seletor de arquivos e retorna o backup decodificado
  Future<Map<String, dynamic>?> selecionarArquivoBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      String jsonString;

      if (kIsWeb && file.bytes != null) {
        jsonString = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        jsonString = await File(file.path!).readAsString();
      } else {
        return null;
      }

      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao selecionar: $e');
      return null;
    }
  }

  /// Valida o backup
  String? validarBackup(Map<String, dynamic> backup) {
    if (!backup.containsKey('versao_schema')) return 'Versão do schema não encontrada.';
    if (!backup.containsKey('colecoes')) return 'Dados das coleções não encontrados.';
    if (backup['colecoes'] is! Map) return 'Formato das coleções incorreto.';
    return null;
  }

  /// Restaura o backup usando DataService.importarBackup
  Future<bool> restaurarBackup(Map<String, dynamic> backup) async {
    final erro = validarBackup(backup);
    if (erro != null) {
      debugPrint('>>> [BackupRestore] ❌ $erro');
      return false;
    }
    return await _dataService.importarBackup(backup);
  }

  // ============================================================
  // RESTORE FROM POSTGRESQL DUMP
  // ============================================================

  /// Abre o seletor de arquivos para dumps PostgreSQL (.dump, .sql, .pg_dump)
  Future<File?> selecionarArquivoDump() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dump', 'sql', 'pg_dump', 'bak'],
      );
      if (result == null || result.files.isEmpty) return null;

      final filePath = result.files.first.path;
      if (filePath == null) return null;

      return File(filePath);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao selecionar dump: $e');
      return null;
    }
  }

  /// Remove todos os dados das tabelas do app no PostgreSQL local.
  /// Usado antes de restaurar dump para evitar duplicatas.
  Future<void> limparDadosLocais() async {
    final env = EnvConfig.env;
    final dbHost = env['DB_HOST'] ?? '127.0.0.1';
    final dbPort = env['DB_PORT'] ?? '5432';
    final dbName = env['DB_NAME'] ?? 'exodo_db';
    final dbUser = env['DB_USER'] ?? 'exodo_user';
    final dbPass = env['DB_PASSWORD'] ?? '';

    final psqlPath = await _findExecutable('psql');
    if (psqlPath == null) {
      throw Exception('psql não encontrado. Não é possível limpar dados.');
    }

    // Lista de todas as tabelas do app
    final tabelas = [
      'produtos', 'clientes', 'pedidos', 'servicos',
      'ordens_servico', 'entregas', 'motoristas',
      'vendas_balcao', 'trocas_devolucoes', 'estoque_historico',
      'lotes_produto', 'aberturas_caixa', 'fechamentos_caixa',
      'agendamentos_servico', 'notas_entrada', 'funcionarios',
      'taxas_entrega', 'contas_pagar', 'nfces', 'nfes',
      'sangrias_caixa', 'suprimentos_caixa', 'links_vendedores',
      'comissoes_vendedores', 'romaneios', 'mesas_comandas',
      'sync_status', 'sync_logs', 'exodo_config',
    ];

    // Montar SQL TRUNCATE para todas as tabelas
    final sql = tabelas.map((t) => 'TRUNCATE TABLE $t CASCADE;').join('\n');
    final tempFile = File(p.join(Directory.systemTemp.path, 'limpar_dados.sql'));
    await tempFile.writeAsString(sql);

    try {
      final environment = Map<String, String>.from(Platform.environment);
      environment['PGPASSWORD'] = dbPass;

      final result = await runProcessHidden(
        psqlPath,
        ['-h', dbHost, '-p', dbPort, '-U', dbUser, '-d', dbName, '-f', tempFile.path],
        environment: environment,
      ).timeout(const Duration(seconds: 30));

      if (result.exitCode != 0) {
        debugPrint('>>> [BackupRestore] ⚠️ Aviso ao limpar: ${result.stderr}');
      } else {
        debugPrint('>>> [BackupRestore] ✅ Dados locais limpos com sucesso');
      }
    } finally {
      await tempFile.delete();
    }
  }

  /// Restaura o banco de dados PostgreSQL a partir de um arquivo dump
  /// Retorna (sucesso, mensagem)
  Future<(bool, String)> restaurarDumpPostgres(File dumpFile) async {
    try {
      // Ler configuração do banco de dados do .env
      final env = EnvConfig.env;
      final dbHost = env['DB_HOST'] ?? '127.0.0.1';
      final dbPort = env['DB_PORT'] ?? '5432';
      final dbName = env['DB_NAME'] ?? 'exodo_db';
      final dbUser = env['DB_USER'] ?? 'exodo_user';
      final dbPass = env['DB_PASSWORD'] ?? '';

      final fileName = p.basename(dumpFile.path).toLowerCase();
      final isSql = fileName.endsWith('.sql');
      final isDump = fileName.endsWith('.dump') || fileName.endsWith('.pg_dump') || fileName.endsWith('.bak');

      if (!isSql && !isDump) {
        return (false, 'Formato de arquivo não reconhecido. Use arquivos .sql ou .dump');
      }

      debugPrint('>>> [BackupRestore] 🔄 Restaurando dump PostgreSQL: ${dumpFile.path}');
      debugPrint('>>> [BackupRestore] 📋 Banco: $dbName@$dbHost:$dbPort (user: $dbUser)');

      // Verificar se pg_restore ou psql existem
      final psqlPath = await _findExecutable('psql');
      final pgRestorePath = await _findExecutable('pg_restore');

      // 1. O arquivo tem conteúdo? Um dump cortado/0 byte substituiria o banco
      // inteiro por nada — aqui ele é recusado antes.
      final tamanho = await dumpFile.length();
      if (tamanho == 0) {
        await registrarAuditoria('⛔ Restauração do banco inteiro BLOQUEADA: '
            '${p.basename(dumpFile.path)} está vazio (0 byte).');
        return (false, 'O arquivo está vazio (0 byte). Restauração bloqueada.');
      }
      if (isDump && pgRestorePath != null) {
        final listagem = await runProcessHidden(
          pgRestorePath,
          ['--list', dumpFile.path],
          environment: Platform.environment,
        ).timeout(const Duration(minutes: 5));
        final totalItens = (listagem.stdout as String)
            .split(RegExp(r'\r?\n'))
            .where((l) => l.isNotEmpty && !l.startsWith(';'))
            .length;
        if (listagem.exitCode != 0 || totalItens == 0) {
          await registrarAuditoria('⛔ Restauração do banco inteiro BLOQUEADA: '
              '${p.basename(dumpFile.path)} não pôde ser lido pelo pg_restore.');
          return (
            false,
            'O arquivo de dump não pôde ser lido (incompleto ou corrompido): '
                '${(listagem.stderr as String).trim()}',
          );
        }
        debugPrint('>>> [BackupRestore] 📦 Dump com $totalItens objeto(s) — arquivo legível.');
      }

      // 2. Rede de segurança OBRIGATÓRIA: dump COMPLETO do banco local atual.
      final (okSnap, msgSnap, caminhoSnap) = await backupAntesDeRestaurarBancoInteiro(
        motivo: 'banco_inteiro',
      );
      if (!okSnap) {
        await registrarAuditoria('⛔ Restauração do banco inteiro CANCELADA (sem backup '
            'de segurança): $msgSnap');
        return (
          false,
          'Não guardei o banco local atual, então NÃO restaurei\n\n'
              'A restauração do banco inteiro só roda com o backup de segurança salvo em '
              '$pastaAntesDeRestaurar\\_banco_inteiro. Motivo da falha: $msgSnap',
        );
      }
      final caminhoDesfazer = caminhoSnap;
      ultimoBackupAntesDeRestaurar = caminhoSnap;
      debugPrint('>>> [BackupRestore] 🛡️ Banco local de antes guardado: $caminhoSnap');

      List<String> args;
      String executable;

      if (isDump && pgRestorePath != null) {
        // Usar pg_restore para arquivos .dump
        executable = pgRestorePath;
        args = [
          '-h', dbHost,
          '-p', dbPort,
          '-U', dbUser,
          '-d', dbName,
          '--clean',
          '--if-exists',
          '--no-owner',
          '--no-privileges',
          dumpFile.path,
        ];
      } else if (psqlPath != null) {
        // Usar psql para arquivos .sql ou fallback
        executable = psqlPath;
        args = [
          '-h', dbHost,
          '-p', dbPort,
          '-U', dbUser,
          '-d', dbName,
          '-f', dumpFile.path,
        ];
      } else {
        return (false, 'Nem psql nem pg_restore encontrados. Instale o PostgreSQL client tools e adicione ao PATH do sistema.');
      }

      debugPrint('>>> [BackupRestore] 🖥️ Executando: $executable ${args.join(' ')}');

      // Executar o comando com a senha via variável de ambiente — e com o
      // trigger de fila de envio desligado, senão a restauração do banco
      // inteiro viraria uma fila gigante e o sincronizador subiria tudo para a
      // nuvem no próximo ciclo.
      final environment = Map<String, String>.from(Platform.environment);
      environment['PGPASSWORD'] = dbPass;
      environment['PGOPTIONS'] = '-c exodo.sync_mode=on';

      // A fila de envio INTEIRA fica obsoleta: o banco local foi substituído.
      final psqlParaLimpeza = await _findExecutable('psql');
      if (psqlParaLimpeza != null) {
        final (argsLocal, ambienteLocal) = _conexaoPsql();
        await _limparTodasAsPendenciasDeEnvio(
          psqlPath: psqlParaLimpeza,
          baseArgs: argsLocal,
          ambiente: _ambienteRestauroLocal(ambienteLocal),
        );
      }

      final result = await runProcessHidden(
        executable,
        args,
        environment: environment,
      ).timeout(
        const Duration(minutes: 30),
        onTimeout: () {
          throw TimeoutException('Restauração excedeu o tempo limite de 30 minutos');
        },
      );

      if (result.exitCode == 0) {
        debugPrint('>>> [BackupRestore] ✅ Dump restaurado com sucesso (a nuvem não foi tocada)!');
        await registrarAuditoria('✅ Restauração do BANCO INTEIRO concluída '
            '(${p.basename(dumpFile.path)}) — desfazer: '
            '${caminhoDesfazer == null ? 'não gerado' : p.basename(caminhoDesfazer)}');
        return (
          true,
          'Dump restaurado SOMENTE no banco local. A nuvem não foi alterada. '
              'Reinicie o app para carregar os dados.\n'
              '${caminhoDesfazer == null ? '' : 'Para desfazer: o estado anterior do banco ficou em ${p.basename(caminhoDesfazer)}.'}',
        );
      } else {
        await registrarAuditoria('❌ Falha na restauração do BANCO INTEIRO '
            '(${p.basename(dumpFile.path)}) — o banco não foi alterado pelo app. ${result.stderr}');
        final stderr = result.stderr.toString().trim();
        final stdout = result.stdout.toString().trim();
        debugPrint('>>> [BackupRestore] ❌ Erro na restauração (exitCode: ${result.exitCode})');
        debugPrint('>>> [BackupRestore] STDERR: $stderr');
        debugPrint('>>> [BackupRestore] STDOUT: $stdout');

        // Mensagens de erro amigáveis
        if (stderr.contains('could not connect') || stderr.contains('connection refused')) {
          return (false, 'Não foi possível conectar ao PostgreSQL. Verifique se o serviço está rodando.');
        }
        if (stderr.contains('does not exist') && stderr.contains('database')) {
          return (false, 'Banco de dados "$dbName" não existe. Crie-o primeiro com: createdb $dbName');
        }
        if (stderr.contains('authentication failed') || stderr.contains('password authentication')) {
          return (false, 'Falha de autenticação. Verifique DB_USER e DB_PASSWORD no arquivo .env');
        }
        if (stderr.contains('permission denied') || result.exitCode == 127) {
          return (false, 'Permissão negada ou executável não encontrado. Verifique se o PostgreSQL está no PATH.');
        }

        return (false, 'Erro na restauração: ${stderr.isNotEmpty ? stderr : stdout}');
      }
    } on TimeoutException {
      return (false, 'Restauração excedeu o tempo limite (30 min). Arquivo pode ser muito grande.');
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro inesperado: $e');
      return (false, 'Erro inesperado: $e');
    }
  }

  /// Procura um executável no PATH do sistema OU na pasta de binários do
  /// PostgreSQL embutido que acompanha o app (postgresql/pgsql/bin).
  Future<String?> _findExecutable(String name) async {
    // 1) PATH do sistema
    try {
      final result = await runProcessHidden(
        Platform.isWindows ? 'where' : 'which',
        [name],
      );
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        final lines = output.split(Platform.isWindows ? '\r\n' : '\n');
        if (lines.isNotEmpty && lines.first.isNotEmpty) {
          return lines.first;
        }
      }
    } catch (_) {}

    // 2) PostgreSQL embutido que acompanha o app (comum nesta instalação)
    final nomeExe = Platform.isWindows ? '$name.exe' : name;
    final candidatos = <String>[
      p.join(Directory.current.path, 'postgresql', 'pgsql', 'bin', nomeExe),
      p.join(Directory.current.path, 'postgresql', 'bin', nomeExe),
    ];

    // 3) Ao lado do executável do app (quando instalado/compilado)
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidatos.addAll([
        p.join(exeDir, 'postgresql', 'pgsql', 'bin', nomeExe),
        p.join(exeDir, 'postgresql', 'bin', nomeExe),
        p.join(exeDir, nomeExe),
      ]);
    } catch (_) {}

    for (final caminho in candidatos) {
      try {
        if (await File(caminho).exists()) {
          debugPrint('>>> [BackupRestore] ✅ Binário encontrado: $caminho');
          return caminho;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Gera um backup (dump) do banco PostgreSQL LOCAL usando pg_dump.
  /// - formatoSql = false  → arquivo .dump compactado (formato custom, recomendado)
  /// - formatoSql = true   → arquivo .sql (texto puro, compatível com psql)
  /// Retorna (sucesso, mensagem, caminho_do_arquivo).
  Future<(bool, String, String?)> criarBackupDumpLocal({
    String? destinoArquivo,
    bool formatoSql = false,
  }) async {
    try {
      final env = EnvConfig.env;
      final dbHost = env['DB_HOST'] ?? '127.0.0.1';
      final dbPort = env['DB_PORT'] ?? '5432';
      final dbName = env['DB_NAME'] ?? 'exodo_db';
      final dbUser = env['DB_USER'] ?? 'exodo_user';
      final dbPass = env['DB_PASSWORD'] ?? '';

      final pgDumpPath = await _findExecutable('pg_dump');
      if (pgDumpPath == null) {
        return (false, 'pg_dump não encontrado. Instale o PostgreSQL client tools ou use o PostgreSQL que acompanha o app.', null);
      }

      // Definir o caminho de destino (com diálogo para o usuário escolher)
      var caminho = destinoArquivo ?? '';
      if (caminho.isEmpty) {
        if (kIsWeb) return (false, 'Gerar dump PostgreSQL não está disponível na versão Web.', null);
        final extensao = formatoSql ? 'sql' : 'dump';
        final empresaNome = _dataService.empresaAtual?.nomeExibicao?.replaceAll(RegExp(r'[^\w\s]'), '_') ?? 'empresa';
        final agora = DateTime.now();
        final sufixo = '${agora.year}${agora.month.toString().padLeft(2, '0')}${agora.day.toString().padLeft(2, '0')}_${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';
        final nomeSugerido = 'backup_${empresaNome}_$sufixo.$extensao';

        final salvo = await FilePicker.platform.saveFile(
          dialogTitle: 'Salvar backup dump PostgreSQL',
          fileName: nomeSugerido,
          type: FileType.custom,
          allowedExtensions: [extensao],
        );
        if (salvo == null || salvo.isEmpty) {
          return (false, 'Geração de dump cancelada.', null);
        }
        caminho = salvo;
      }

      debugPrint('>>> [BackupRestore] 🗄️ Gerando dump do banco $dbName@$dbHost:$dbPort → $caminho');

      final args = <String>[
        '-h', dbHost,
        '-p', dbPort,
        '-U', dbUser,
        '-d', dbName,
      ];
      if (formatoSql) {
        args.addAll(['--no-owner', '--no-privileges', '-f', caminho]);
      } else {
        args.addAll(['-Fc', '-f', caminho]);
      }

      final environment = Map<String, String>.from(Platform.environment);
      environment['PGPASSWORD'] = dbPass;

      final result = await runProcessHidden(
        pgDumpPath,
        args,
        environment: environment,
      ).timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw TimeoutException('Geração do dump excedeu o tempo limite de 30 minutos'),
      );

      if (result.exitCode == 0) {
        final tamanhoMb = (await File(caminho).length() / 1024 / 1024).toStringAsFixed(2);
        debugPrint('>>> [BackupRestore] ✅ Dump gerado com sucesso ($tamanhoMb MB): $caminho');
        return (true, 'Dump gerado com sucesso ($tamanhoMb MB)!', caminho);
      }

      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      debugPrint('>>> [BackupRestore] ❌ Erro no pg_dump (exitCode: ${result.exitCode})');
      debugPrint('>>> [BackupRestore] STDERR: $stderr');

      if (stderr.contains('could not connect') || stderr.contains('connection refused')) {
        return (false, 'Não foi possível conectar ao PostgreSQL local. Verifique se o serviço está rodando.', null);
      }
      if (stderr.contains('authentication failed') || stderr.contains('password authentication')) {
        return (false, 'Falha de autenticação. Verifique DB_USER e DB_PASSWORD no arquivo .env.', null);
      }
      if (stderr.contains('does not exist') && stderr.contains('database')) {
        return (false, 'Banco de dados "$dbName" não existe no PostgreSQL local.', null);
      }
      return (false, 'Erro ao gerar dump: ${stderr.isNotEmpty ? stderr : stdout}', null);
    } on TimeoutException {
      return (false, 'Geração do dump excedeu o tempo limite (30 min).', null);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro inesperado ao gerar dump: $e');
      return (false, 'Erro inesperado ao gerar dump: $e', null);
    }
  }

  // ============================================================
  // BACKUP POSTGRESQL SOMENTE DE UMA EMPRESA (.sql filtrado por empresa_id)
  // ============================================================

  /// Envolve um identificador em aspas duplas, com escaping correto.
  static String _ident(String nome) => '"${nome.replaceAll('"', '""')}"';

  /// Executa uma consulta SQL no PostgreSQL local e devolve o stdout (UTF-8).
  Future<ProcessResult> _executarPsql({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    String? comando,
    String? arquivo,
  }) {
    final args = <String>[...baseArgs];
    if (comando != null) args.addAll(['-c', comando]);
    if (arquivo != null) args.addAll(['-f', arquivo]);

    return runProcessHidden(
      psqlPath,
      args,
      environment: ambiente,
    );
  }

  /// Nome do banco PostgreSQL LOCAL (configurado no .env).
  String get _bancoLocal => EnvConfig.env['DB_NAME'] ?? 'exodo_db';

  /// Executa um SQL de ESTRUTURA por ARQUIVO (`psql -f`), com
  /// `SET client_encoding = 'UTF8';` no topo — nunca por `-c`.
  ///
  /// Motivo (erro real, visto em produção no banco local): no Windows o `-c` passa
  /// pela linha de comando, que é convertida para a página de código ANSI. Um
  /// comentário com acento ("sensível", "NÃO") virou bytes latin1 e o PostgreSQL
  /// recusou com "sequência de bytes é inválida para codificação UTF8" — a tabela
  /// `usuarios` ficava inteira sem ser ajustada, em silêncio. O arquivo é lido
  /// byte a byte, sem essa conversão.
  Future<ProcessResult> _executarSqlViaArquivo({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    required String sql,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('exodo_ddl_');
    final arquivo = File(p.join(tempDir.path, 'ddl.sql'));
    try {
      await arquivo.writeAsString(
        "SET client_encoding = 'UTF8';\n$sql\n",
        flush: true,
      );
      return await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        arquivo: arquivo.path,
      );
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Nome de exibição de uma empresa pelo id (tabela `empresas`), caindo para o
  /// próprio id se não encontrar.
  ///
  /// É preciso buscar pelo id — e não usar `empresaAtual` — porque o backup
  /// diário percorre TODAS as empresas: antes, o arquivo (e o cabeçalho) do
  /// backup das outras empresas saía com o nome da empresa aberta na tela, o
  /// que confundia na hora de escolher qual backup restaurar.
  Future<String> _nomeDaEmpresa(String empresaId) async {
    final daSessao = _nomeDaEmpresaDaSessao(empresaId);
    try {
      final empresas = await DatabaseService().carregarListaCompleta('empresas');
      for (final e in empresas) {
        if (e['id']?.toString() != empresaId) continue;
        final nome = (e['nome_fantasia'] ?? e['razao_social'])?.toString().trim();
        if (nome != null && nome.isNotEmpty) return nome;
      }
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível ler o nome da empresa $empresaId: $e');
    }
    // Último recurso: a empresa aberta na sessão do app (só quando é a mesma).
    if (daSessao != null && daSessao.isNotEmpty) return daSessao;
    return empresaId;
  }

  /// Nome da empresa que está aberta no app — usado só quando a tabela
  /// `empresas` do banco local não tem a linha (aí o backup sairia com o id).
  String? _nomeDaEmpresaDaSessao(String empresaId) {
    try {
      final atual = _dataService.empresaAtual;
      if (atual == null || atual.id != empresaId) return null;
      final nome = atual.nomeExibicao.trim();
      return nome.isEmpty ? null : nome;
    } catch (_) {
      return null;
    }
  }

  /// Nome de exibição de uma empresa lido do banco DA NUVEM (para o backup por
  /// empresa tirado do Supabase). Retorna `null` se não achar ou falhar.
  Future<String?> _nomeDaEmpresaNaNuvem({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    required String empresaId,
  }) async {
    try {
      final idSql = empresaId.replaceAll("'", "''");
      final result = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: 'SELECT coalesce(nullif(trim(nome_fantasia), \'\'), '
            'nullif(trim(razao_social), \'\'), nullif(trim(nome_exibicao), \'\'), id) '
            'FROM public.empresas WHERE id = \'$idSql\' LIMIT 1;',
      );
      if (result.exitCode != 0) return null;
      final valor = (result.stdout as String? ?? '').trim();
      return valor.isEmpty ? null : valor;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível ler o nome da empresa $empresaId na nuvem: $e');
      return null;
    }
  }

  /// Monta o ambiente e os argumentos base de conexão do psql.
  /// [banco] permite apontar para outra base (ex.: uma base temporária de
  /// restauração) em vez do banco local do .env.
  (List<String>, Map<String, String>) _conexaoPsql({String? banco}) {
    final env = EnvConfig.env;
    final dbHost = env['DB_HOST'] ?? '127.0.0.1';
    final dbPort = env['DB_PORT'] ?? '5432';
    final dbName = banco ?? env['DB_NAME'] ?? 'exodo_db';
    final dbUser = env['DB_USER'] ?? 'exodo_user';
    final dbPass = env['DB_PASSWORD'] ?? '';

    final ambiente = Map<String, String>.from(Platform.environment);
    ambiente['PGPASSWORD'] = dbPass;
    ambiente['PGCLIENTENCODING'] = 'UTF8';

    final args = <String>[
      '-h', dbHost,
      '-p', dbPort,
      '-U', dbUser,
      '-d', dbName,
      '--no-psqlrc',
      '-v', 'ON_ERROR_STOP=1',
      '-A',
      '-t',
    ];
    return (args, ambiente);
  }

  /// Cópia do ambiente do psql/pg_restore com `exodo.sync_mode = 'on'` na
  /// conexão (`PGOPTIONS`).
  ///
  /// É o que torna a restauração INVISÍVEL para o sincronizador: com esse modo
  /// ligado o trigger `log_sync_event` NÃO registra os `DELETE`/`COPY` no
  /// `_exodo_sync_log`. Sem isso, restaurar um backup local deixava a fila de
  /// envio cheia e o sincronizador de bandeja subia tudo para o Supabase no
  /// ciclo seguinte — ou seja, a restauração local **sobrescrevia a nuvem** (e
  /// os DELETE ainda apagavam lá registro que existia só na nuvem).
  ///
  /// Confirmado no PostgreSQL local: `PGOPTIONS='-c exodo.sync_mode=on'` faz
  /// `SHOW exodo.sync_mode` responder `on` na sessão inteira (psql e
  /// pg_restore usam libpq, então vale para os dois).
  Map<String, String> _ambienteRestauroLocal(Map<String, String> ambiente) {
    final copia = Map<String, String>.from(ambiente);
    final atual = copia['PGOPTIONS']?.trim() ?? '';
    copia['PGOPTIONS'] =
        atual.isEmpty ? '-c exodo.sync_mode=on' : '$atual -c exodo.sync_mode=on';
    return copia;
  }

  /// Esvazia a fila de envio (`_exodo_sync_log`) dos registros desta empresa.
  ///
  /// Precisa rodar ANTES da restauração: apagar/reescrever as linhas desta
  /// empresa com a fila cheia faria o sincronizador propagar para a NUVEM tanto
  /// o conteúdo antigo do backup quanto os `DELETE` da restauração.
  ///
  /// Só mexe em pendências de registros que HOJE pertencem a [empresaId] — o
  /// envio pendente das outras empresas (mesma tabela) fica intacto.
  ///
  /// Melhor esforço: qualquer falha aqui é registrada e ignorada, porque a
  /// restauração em si já roda com o trigger desligado.
  Future<void> _limparPendenciasDeEnvioDaEmpresa({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    required String empresaId,
  }) async {
    try {
      final tabelas = await _tabelasDaEmpresa(psqlPath, baseArgs, ambiente);
      final comId = tabelas.where((t) => t.colunas.contains('id')).toList();
      if (comId.isEmpty) return;

      final idSql = empresaId.replaceAll("'", "''");

      // Auditoria: guarda o que estava PENDENTE de envio antes de limpar, para
      // que não exista alteração local sumindo sem rastro.
      try {
        final pendentes = await _executarPsql(
          psqlPath: psqlPath,
          baseArgs: baseArgs,
          ambiente: ambiente,
          comando: "SELECT table_name || '|' || record_id || '|' || operation "
              'FROM public._exodo_sync_log ORDER BY id;',
        );
        final texto = (pendentes.stdout as String? ?? '').trim();
        if (pendentes.exitCode == 0 && texto.isNotEmpty) {
          final dir = Directory(p.join(
            pastaAntesDeRestaurar,
            empresaId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_'),
          ));
          if (!await dir.exists()) await dir.create(recursive: true);
          final carimbo = DateTime.now()
              .toIso8601String()
              .replaceAll(RegExp(r'[:.]'), '-')
              .substring(0, 19);
          final arquivo = File(p.join(dir.path, 'fila_de_envio_$carimbo.txt'));
          await arquivo.writeAsString(
            'Envios que estavam pendentes para a nuvem quando a restauração começou.\n'
            'Formato: tabela|registro|operação\n\n$texto\n',
            flush: true,
          );
          debugPrint('>>> [BackupRestore] 🧾 Fila de envio salva para auditoria: ${arquivo.path}');
        }
      } catch (e) {
        debugPrint('>>> [BackupRestore] ⚠️ Não foi possível auditar a fila de envio: $e');
      }

      final buffer = StringBuffer();
      buffer.writeln(r'DO $exodo$');
      buffer.writeln('BEGIN');
      buffer.writeln(
          "  IF to_regclass('public._exodo_sync_log') IS NULL THEN RETURN; END IF;");
      for (final t in comId) {
        final tabelaSql = t.tabela.replaceAll("'", "''");
        buffer.writeln("  DELETE FROM public._exodo_sync_log l "
            "WHERE l.table_name = '$tabelaSql' AND EXISTS (SELECT 1 "
            'FROM public.${_ident(t.tabela)} x '
            "WHERE x.id::text = l.record_id AND x.empresa_id = '$idSql');");
      }
      buffer.writeln('EXCEPTION WHEN OTHERS THEN NULL;');
      buffer.writeln('END');
      buffer.writeln(r'$exodo$;');

      final result = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: buffer.toString(),
      );
      if (result.exitCode == 0) {
        debugPrint('>>> [BackupRestore] 🧹 Fila de envio limpa (${comId.length} tabelas) — a nuvem não será tocada por esta restauração.');
      } else {
        debugPrint('>>> [BackupRestore] ⚠️ Não foi possível limpar a fila de envio: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Falha ao limpar a fila de envio: $e');
    }
  }

  /// Esvazia a fila de envio INTEIRA — usado só na restauração do banco
  /// inteiro, que substitui todas as empresas do computador.
  Future<void> _limparTodasAsPendenciasDeEnvio({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
  }) async {
    try {
      final result = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: "DO \$exodo\$ BEGIN "
            "IF to_regclass('public._exodo_sync_log') IS NULL THEN RETURN; END IF; "
            'DELETE FROM public._exodo_sync_log; '
            'EXCEPTION WHEN OTHERS THEN NULL; END \$exodo\$;',
      );
      debugPrint(result.exitCode == 0
          ? '>>> [BackupRestore] 🧹 Fila de envio esvaziada por completo (banco inteiro restaurado).'
          : '>>> [BackupRestore] ⚠️ Falha ao esvaziar a fila de envio: ${result.stderr}');
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Falha ao esvaziar a fila de envio: $e');
    }
  }

  /// Pasta dos backups AUTOMÁTICOS feitos imediatamente antes de cada
  /// restauração. É o "estado de antes" — sem ele não existe desfazer.
  static String get pastaAntesDeRestaurar => 'C:\\ExodoBackups\\_antes_de_restaurar';

  /// Trilha de auditoria (append-only): registra toda restauração/alteração de
  /// dados, com o arquivo usado e o arquivo de desfazer.
  static String get arquivoAuditoria => 'C:\\ExodoBackups\\restauracoes.log';

  /// Último backup de segurança gerado por uma restauração (é o caminho para
  /// DESFAZER a última restauração aplicada).
  String? ultimoBackupAntesDeRestaurar;

  Future<void> registrarAuditoria(String mensagem) async {
    try {
      final arquivo = File(arquivoAuditoria);
      if (!await arquivo.parent.exists()) await arquivo.parent.create(recursive: true);
      final usuario = Platform.environment['USERNAME'] ??
          Platform.environment['USER'] ??
          'desconhecido';
      final linha =
          '${DateTime.now().toIso8601String()} | $usuario | ${p.basename(Platform.resolvedExecutable)} | $mensagem';
      await arquivo.writeAsString('$linha\n', mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível escrever a auditoria: $e');
    }
  }

  /// Confere se um `.sql` por empresa está COMPLETO antes de aplicar.
  ///
  /// Um arquivo cortado (cópia interrompida, disco cheio, download pela metade)
  /// é o pior cenário possível numa restauração: ele apaga as linhas da empresa
  /// e recarrega só uma parte. Aqui isso é detectado ANTES de encostar no banco:
  ///
  ///  - o arquivo tem `BEGIN;` e `COMMIT;`;
  ///  - a quantidade de tabelas e de registros bate com o cabeçalho;
  ///  - nenhum bloco `COPY` ficou aberto no fim (sinal clássico de truncamento).
  ///
  /// Sem contagem no cabeçalho (arquivo de outra origem), só as outras checagens
  /// valem.
  Future<
      ({
        bool ok,
        String mensagem,
        int tabelas,
        int? registros,
        int? registrosCabecalho,
        String? empresaId,
        List<String> listaTabelas,
      })> verificarIntegridadeScriptEmpresa(File arquivo) async {
    try {
      if (!await arquivo.exists()) {
        return (
          ok: false,
          mensagem: 'Arquivo não encontrado: ${arquivo.path}',
          tabelas: 0,
          registros: null,
          registrosCabecalho: null,
          empresaId: null,
          listaTabelas: const <String>[],
        );
      }

      final cabecalho = await lerCabecalhoScriptEmpresa(arquivo);
      var tabelas = 0;
      var registros = 0;
      var blocoAberto = false;
      var temBegin = false;
      var temCommit = false;
      final listaTabelas = <String>[];

      final linhas = arquivo
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final linha in linhas) {
        final t = linha.trimRight();
        if (t == 'BEGIN;') {
          temBegin = true;
          continue;
        }
        if (t == 'COMMIT;') {
          temCommit = true;
          continue;
        }
        if (t.startsWith('COPY public.')) {
          tabelas++;
          blocoAberto = true;
          final trecho = t.substring('COPY public.'.length);
          final fim = trecho.indexOf(RegExp(r'[\s(]'));
          final nome = (fim < 0 ? trecho : trecho.substring(0, fim))
              .replaceAll('"', '')
              .trim();
          if (nome.isNotEmpty) listaTabelas.add(nome);
          continue;
        }
        if (blocoAberto) {
          if (t == r'\.') {
            blocoAberto = false;
          } else if (t.isNotEmpty) {
            registros++;
          }
        }
      }

      final cabecalhoRegistros = cabecalho.registros;
      if (tabelas == 0) {
        return (
          ok: false,
          mensagem: 'O arquivo não tem nenhum bloco de dados (COPY) — não é um backup válido.',
          tabelas: 0,
          registros: registros,
          registrosCabecalho: cabecalhoRegistros,
          empresaId: cabecalho.empresaId,
          listaTabelas: listaTabelas,
        );
      }
      if (!temBegin || !temCommit) {
        return (
          ok: false,
          mensagem: 'O arquivo está sem BEGIN/COMMIT — provavelmente incompleto (não seria '
              'aplicado de forma atômica). Restauração bloqueada.',
          tabelas: tabelas,
          registros: registros,
          registrosCabecalho: cabecalhoRegistros,
          empresaId: cabecalho.empresaId,
          listaTabelas: listaTabelas,
        );
      }
      if (blocoAberto) {
        return (
          ok: false,
          mensagem: 'O arquivo termina no meio de uma tabela (bloco COPY aberto) — cópia '
              'truncada. Restauração bloqueada para não deixar a empresa pela metade.',
          tabelas: tabelas,
          registros: registros,
          registrosCabecalho: cabecalhoRegistros,
          empresaId: cabecalho.empresaId,
          listaTabelas: listaTabelas,
        );
      }
      if (cabecalho.tabelas != null && cabecalho.tabelas != tabelas) {
        return (
          ok: false,
          mensagem: 'O cabeçalho promete ${cabecalho.tabelas} tabela(s) e o arquivo tem $tabelas. '
              'Arquivo inconsistente — restauração bloqueada.',
          tabelas: tabelas,
          registros: registros,
          registrosCabecalho: cabecalhoRegistros,
          empresaId: cabecalho.empresaId,
          listaTabelas: listaTabelas,
        );
      }
      if (cabecalhoRegistros != null && cabecalhoRegistros != registros) {
        return (
          ok: false,
          mensagem: 'O cabeçalho promete $cabecalhoRegistros registro(s) e o arquivo tem '
              '$registros. Arquivo inconsistente ou cortado — restauração bloqueada.',
          tabelas: tabelas,
          registros: registros,
          registrosCabecalho: cabecalhoRegistros,
          empresaId: cabecalho.empresaId,
          listaTabelas: listaTabelas,
        );
      }

      return (
        ok: true,
        mensagem: 'Arquivo íntegro: $registros registro(s) em $tabelas tabela(s), '
            'em uma única transação.',
        tabelas: tabelas,
        registros: registros,
        registrosCabecalho: cabecalhoRegistros,
        empresaId: cabecalho.empresaId,
        listaTabelas: listaTabelas,
      );
    } catch (e) {
      return (
        ok: false,
        mensagem: 'Não foi possível conferir o arquivo: $e',
        tabelas: 0,
        registros: null,
        registrosCabecalho: null,
        empresaId: null,
        listaTabelas: const <String>[],
      );
    }
  }

  /// Confere, DEPOIS de aplicar, se o banco local tem exatamente a quantidade de
  /// linhas que o arquivo trazia para esta empresa.
  ///
  /// É a última linha de defesa: se por qualquer motivo a carga não chegou
  /// inteira (ou alguém escreveu no meio), o número não bate e a tela avisa na
  /// hora, em vez de o problema aparecer semanas depois.
  /// Retorna `null` quando não foi possível medir.
  Future<int?> _contarLinhasCarregadas({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    required List<String> tabelas,
    required String empresaId,
  }) async {
    if (tabelas.isEmpty) return null;
    try {
      final idSql = empresaId.replaceAll("'", "''");
      final partes = tabelas.map((t) {
        final nome = t.replaceAll('"', '');
        return 'SELECT count(*) AS c FROM public.${_ident(nome)} WHERE empresa_id = \'$idSql\'';
      }).join(' UNION ALL ');

      final result = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: 'SELECT coalesce(sum(c), 0) FROM ($partes) x;',
      );
      if (result.exitCode != 0) {
        debugPrint('>>> [BackupRestore] ⚠️ Não foi possível conferir as linhas carregadas: ${result.stderr}');
        return null;
      }
      return int.tryParse((result.stdout as String? ?? '').trim());
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Erro ao conferir as linhas carregadas: $e');
      return null;
    }
  }

  /// Guarda uma cópia do arquivo APLICADO numa restauração (trilha do que
  /// exatamente entrou no banco). Retorna o caminho da cópia.
  Future<String?> _guardarCopiaDoAplicado({
    required File origem,
    required String empresaId,
    required String carimbo,
  }) async {
    try {
      final dir = Directory(p.join(
        pastaAntesDeRestaurar,
        empresaId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_'),
      ));
      if (!await dir.exists()) await dir.create(recursive: true);
      final destino = p.join(dir.path, 'APLICADO_${carimbo}_${p.basename(origem.path)}');
      await origem.copy(destino);
      return destino;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível guardar cópia do arquivo aplicado: $e');
      return null;
    }
  }

  /// Ciclo "antes de restaurar": salva o estado ATUAL desta empresa para poder
  /// desfazer. Sem esse arquivo a restauração não roda — perder o estado atual
  /// não pode ser efeito colateral de um clique.
  Future<(bool, String, String?)> backupAntesDeRestaurarEmpresa({
    required String empresaId,
    required String motivo,
  }) async {
    try {
      final agora = DateTime.now();
      final carimbo = '${agora.year}${agora.month.toString().padLeft(2, '0')}'
          '${agora.day.toString().padLeft(2, '0')}_${agora.hour.toString().padLeft(2, '0')}'
          '${agora.minute.toString().padLeft(2, '0')}${agora.second.toString().padLeft(2, '0')}';
      final dir = Directory(p.join(pastaAntesDeRestaurar, empresaId));
      if (!await dir.exists()) await dir.create(recursive: true);
      final motivoLimpo = motivo.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final destino = p.join(dir.path, 'ANTES_${carimbo}_$motivoLimpo.sql');

      final (ok, msg, caminho) = await criarBackupSqlDaEmpresa(
        empresaId: empresaId,
        destinoArquivo: destino,
      );
      if (!ok) return (false, msg, null);
      return (true, 'Estado atual guardado em ${p.basename(caminho ?? destino)}.', caminho);
    } catch (e) {
      return (false, 'Erro ao guardar o estado atual: $e', null);
    }
  }

  /// Mesma ideia, para a restauração do banco INTEIRO: guarda um dump completo
  /// do banco local antes de substituí-lo.
  Future<(bool, String, String?)> backupAntesDeRestaurarBancoInteiro({
    required String motivo,
  }) async {
    try {
      final agora = DateTime.now();
      final carimbo = '${agora.year}${agora.month.toString().padLeft(2, '0')}'
          '${agora.day.toString().padLeft(2, '0')}_${agora.hour.toString().padLeft(2, '0')}'
          '${agora.minute.toString().padLeft(2, '0')}${agora.second.toString().padLeft(2, '0')}';
      final dir = Directory(p.join(pastaAntesDeRestaurar, '_banco_inteiro'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final motivoLimpo = motivo.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final destino = p.join(dir.path, 'ANTES_${carimbo}_$motivoLimpo.dump');

      final (ok, msg, caminho) = await criarBackupDumpLocal(destinoArquivo: destino);
      if (!ok) return (false, msg, null);
      return (true, 'Banco local inteiro guardado em ${p.basename(caminho ?? destino)}.', caminho);
    } catch (e) {
      return (false, 'Erro ao guardar o banco local: $e', null);
    }
  }

  /// Tabelas do schema `public` que possuem a coluna `empresa_id`, com a lista
  /// de colunas na ordem real do banco (usada para o COPY explícito).
  ///
  /// - Ignora VIEWS (`relkind <> 'r'`), senão o COPY falharia.
  /// - Ignora `sync_logs` e `sync_status` (telemetria de sincronização, não é
  ///   dado da empresa e só inflaria o backup).
  Future<List<({String tabela, List<String> colunas})>> _tabelasDaEmpresa(
    String psqlPath,
    List<String> baseArgs,
    Map<String, String> ambiente,
  ) async {
    const sql = '''
SELECT c.relname || '|' || string_agg(a.attname, ',' ORDER BY a.attnum)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND EXISTS (
    SELECT 1 FROM pg_attribute e
    WHERE e.attrelid = c.oid AND e.attname = 'empresa_id'
      AND e.attnum > 0 AND NOT e.attisdropped
  )
  AND c.relname NOT IN ('sync_logs', 'sync_status')
GROUP BY c.relname
ORDER BY c.relname;
''';

    final result = await _executarPsql(
      psqlPath: psqlPath,
      baseArgs: baseArgs,
      ambiente: ambiente,
      comando: sql,
    );
    if (result.exitCode != 0) {
      throw Exception('Não foi possível listar as tabelas: ${result.stderr}');
    }

    final lista = <({String tabela, List<String> colunas})>[];
    for (final linha in (result.stdout as String).split(RegExp(r'\r?\n'))) {
      final linhaLimpa = linha.trim();
      if (linhaLimpa.isEmpty) continue;
      final partes = linhaLimpa.split('|');
      if (partes.length != 2 || partes[0].isEmpty) continue;
      final colunas = partes[1].split(',').where((c) => c.isNotEmpty).toList();
      if (colunas.isEmpty) continue;
      lista.add((tabela: partes[0], colunas: colunas));
    }
    return lista;
  }

  /// Gera um backup PostgreSQL (.sql) SOMENTE com os dados de UMA empresa.
  ///
  /// O arquivo gerado é um script SQL nativo do PostgreSQL (não JSON): para cada
  /// tabela que possui `empresa_id`, ele apaga APENAS as linhas daquela empresa
  /// e recarrega via `COPY ... FROM stdin`. As outras empresas não são tocadas.
  ///
  /// Retorna (sucesso, mensagem, caminho do arquivo).
  Future<(bool, String, String?)> criarBackupSqlDaEmpresa({
    String? destinoArquivo,
    String? empresaId,
  }) async {
    if (kIsWeb) {
      return (false, 'Backup PostgreSQL não está disponível na versão Web.', null);
    }

    final idEmpresa = empresaId ?? _dataService.currentEmpresaId;
    if (idEmpresa == null || idEmpresa.isEmpty) {
      return (false, 'Empresa não selecionada', null);
    }

    try {
      // Nome da empresa DONO do backup (não o da empresa aberta na tela)
      final nomeEmpresa = await _nomeDaEmpresa(idEmpresa);

      var caminho = destinoArquivo ?? '';
      if (caminho.isEmpty) {
        final agora = DateTime.now();
        final dataStr = '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
        final horaStr = '${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';
        final dir = Directory('C:\\ExodoBackups\\$idEmpresa');
        if (!await dir.exists()) await dir.create(recursive: true);
        final nomeLimpo = nomeEmpresa
            .replaceAll(RegExp(r'[^a-zA-Z0-9À-ú]'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .trim();
        caminho = p.join(dir.path, '${nomeLimpo}_empresa_${dataStr}_$horaStr.sql');
      }

      final (ok, msg, _, linhas) = await _gerarScriptSqlDaEmpresa(
        banco: _bancoLocal,
        empresaId: idEmpresa,
        nomeEmpresa: nomeEmpresa,
        caminho: caminho,
      );
      if (!ok) return (false, msg, null);

      final tamanhoKb = (await File(caminho).length() / 1024).toStringAsFixed(0);
      debugPrint('>>> [BackupRestore] ✅ Backup PostgreSQL da empresa gerado ($tamanhoKb KB, $linhas registros): $caminho');
      return (true, 'Backup PostgreSQL da empresa gerado ($tamanhoKb KB, $linhas registros).', caminho);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao gerar backup SQL da empresa: $e');
      return (false, 'Erro ao gerar backup PostgreSQL da empresa: $e', null);
    }
  }

  /// Pasta local das fotografias do banco DA NUVEM, por empresa.
  ///
  /// É diferente de `C:\ExodoBackups\<empresaId>` (backups tirados do banco
  /// LOCAL) e de [criarBackupBancoNuvem] (foto do banco inteiro da nuvem):
  /// aqui é uma foto da NUVEM, só desta empresa.
  static String get _pastaBackupEmpresaNuvem => '$_pastaBackupNuvem\\empresas';

  /// Caminho da pasta das fotos da nuvem desta empresa.
  String pastaBackupEmpresaNuvem(String empresaId) =>
      p.join(_pastaBackupEmpresaNuvem, empresaId);

  /// Tira uma fotografia dos dados DESTA EMPRESA direto do banco da NUVEM
  /// (Supabase) e grava um `.sql` em `C:\ExodoBackups\nuvem\empresas\<id>`.
  ///
  /// Por que isso é diferente do backup por empresa que já existe: aquele é
  /// gerado a partir do banco LOCAL e depois arquivado na nuvem. Se o que está
  /// errado for justamente o local (ou se o local estiver desatualizado), ele não
  /// serve para reverter a nuvem. Esta foto é do estado real do Supabase.
  ///
  /// Só lê: nunca altera o banco da nuvem.
  Future<(bool, String, String?)> criarBackupSqlDaEmpresaNaNuvem({
    String? destinoArquivo,
    String? empresaId,
    void Function(String)? onProgress,
  }) async {
    if (kIsWeb) {
      return (false, 'Backup da nuvem não está disponível na versão Web.', null);
    }

    final idEmpresa = empresaId ?? _dataService.currentEmpresaId;
    if (idEmpresa == null || idEmpresa.isEmpty) {
      return (false, 'Empresa não selecionada', null);
    }

    final host = EnvConfig.supabasePoolerHost.trim();
    final porta = EnvConfig.supabasePoolerPort;
    final usuario = EnvConfig.supabasePoolerUser;
    final senha = EnvConfig.supabasePoolerPassword;
    if (host.isEmpty) {
      return (false, 'Conexão do banco da nuvem não configurada (SUPABASE_POOLER_HOST no .env).', null);
    }
    if (senha.isEmpty) {
      return (false, 'Senha do banco da nuvem não configurada (SUPABASE_POOLER_PASSWORD no .env).', null);
    }

    try {
      final psqlPath = await _findExecutable('psql');
      if (psqlPath == null) {
        return (false, 'psql não encontrado. Não é possível gerar o backup da nuvem.', null);
      }

      onProgress?.call('Conectando ao banco da nuvem...');
      final (argsNuvem, ambienteNuvem) = _conexaoPsqlNuvem(
        host: host,
        porta: porta,
        usuario: usuario,
        senha: senha,
        banco: EnvConfig.supabaseDbNameFinal,
      );

      final teste = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: argsNuvem,
        ambiente: ambienteNuvem,
        comando: 'SELECT 1;',
      );
      if (teste.exitCode != 0) {
        final err = (teste.stderr as String? ?? '').trim();
        return (false, _mensagemErroConexaoNuvem(err, host, porta, usuario), null);
      }

      var nomeEmpresa = await _nomeDaEmpresa(idEmpresa);
      // O banco local pode não ter a empresa (ou ter só o id); a nuvem sempre
      // tem o nome, e é ela a origem deste backup.
      if (nomeEmpresa == idEmpresa) {
        final nomeNuvem = await _nomeDaEmpresaNaNuvem(
          psqlPath: psqlPath,
          baseArgs: argsNuvem,
          ambiente: ambienteNuvem,
          empresaId: idEmpresa,
        );
        if (nomeNuvem != null && nomeNuvem.isNotEmpty) nomeEmpresa = nomeNuvem;
      }
      var caminho = destinoArquivo ?? '';
      if (caminho.isEmpty) {
        final agora = DateTime.now();
        final dataStr = '${agora.year}-${agora.month.toString().padLeft(2, '0')}'
            '-${agora.day.toString().padLeft(2, '0')}';
        final horaStr = '${agora.hour.toString().padLeft(2, '0')}'
            '${agora.minute.toString().padLeft(2, '0')}';
        final dir = Directory(pastaBackupEmpresaNuvem(idEmpresa));
        if (!await dir.exists()) await dir.create(recursive: true);
        final nomeLimpo = nomeEmpresa
            .replaceAll(RegExp(r'[^a-zA-Z0-9À-ú]'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .trim();
        caminho = p.join(dir.path, 'NUVEM_${nomeLimpo}_${dataStr}_$horaStr.sql');
      } else {
        final dir = Directory(p.dirname(caminho));
        if (!await dir.exists()) await dir.create(recursive: true);
      }

      onProgress?.call('Lendo os dados de $nomeEmpresa na nuvem...');
      final (ok, msg, tabelas, linhas) = await _gerarScriptSqlDaEmpresa(
        banco: EnvConfig.supabaseDbNameFinal,
        empresaId: idEmpresa,
        nomeEmpresa: nomeEmpresa,
        caminho: caminho,
        argsConexao: argsNuvem,
        ambienteConexao: ambienteNuvem,
        origem: 'NUVEM (Supabase)',
      );
      if (!ok) return (false, msg, null);

      final tamanhoKb = (await File(caminho).length() / 1024).toStringAsFixed(0);
      debugPrint('>>> [BackupRestore] ✅ Foto da NUVEM de "$nomeEmpresa" gerada '
          '($tamanhoKb KB, $linhas registros em $tabelas tabelas): $caminho');
      return (
        true,
        'Foto da nuvem de "$nomeEmpresa" baixada ($linhas registros em $tabelas tabelas, $tamanhoKb KB).',
        caminho,
      );
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao gerar backup da empresa a partir da nuvem: $e');
      return (false, 'Erro ao gerar backup da empresa a partir da nuvem: $e', null);
    }
  }

  /// Aplica um `.sql` (foto da nuvem, de UMA empresa) de volta no banco DA NUVEM.
  ///
  /// É a única operação desta tela que altera o banco do Supabase para uma
  /// empresa só. Antes de aplicar, tira automaticamente uma nova foto dessa
  /// empresa e guarda em `C:\ExodoBackups\nuvem\empresas\<id>` — se o arquivo
  /// aplicado for o errado, a foto anterior permite voltar.
  ///
  /// Travas: o arquivo precisa ser de UMA empresa (`-- empresa_id:` no
  /// cabeçalho) e dessa empresa selecionada. Um dump do banco inteiro é
  /// RECUSADO aqui.
  ///
  /// Retorna (sucesso, mensagem, caminho da foto de segurança).
  Future<(bool, String, String?)> restaurarBackupSqlDaEmpresaNaNuvem(
    File sqlFile, {
    String? empresaId,
    void Function(String)? onProgress,
  }) async {
    if (kIsWeb) {
      return (false, 'Restauração na nuvem não está disponível na versão Web.', null);
    }

    final idEmpresa = empresaId ?? _dataService.currentEmpresaId;
    if (idEmpresa == null || idEmpresa.isEmpty) {
      return (false, 'Empresa não selecionada', null);
    }
    if (!await sqlFile.exists()) {
      return (false, 'Arquivo não encontrado: ${sqlFile.path}', null);
    }

    final integridade = await verificarIntegridadeScriptEmpresa(sqlFile);
    if (!integridade.ok) {
      await registrarAuditoria('⛔ Restauração NA NUVEM bloqueada (arquivo inválido: '
          '${p.basename(sqlFile.path)}) — ${integridade.mensagem}');
      return (false, 'Restauração na nuvem bloqueada: ${integridade.mensagem}', null);
    }

    final cabecalho = await lerCabecalhoScriptEmpresa(sqlFile);
    if (cabecalho.empresaId == null) {
      return (
        false,
        'Este arquivo não é um backup de UMA empresa (sem "empresa_id" no cabeçalho). '
            'Aplicar um dump do banco inteiro aqui seria perigoso — recusado.',
        null,
      );
    }
    if (cabecalho.empresaId != idEmpresa) {
      return (
        false,
        'Este backup é da empresa ${cabecalho.empresaId}, não da empresa selecionada. '
            'Selecione aquela empresa para aplicar na nuvem.',
        null,
      );
    }

    final host = EnvConfig.supabasePoolerHost.trim();
    final porta = EnvConfig.supabasePoolerPort;
    final usuario = EnvConfig.supabasePoolerUser;
    final senha = EnvConfig.supabasePoolerPassword;
    if (host.isEmpty || senha.isEmpty) {
      return (false, 'Conexão do banco da nuvem não configurada no .env.', null);
    }

    try {
      final psqlPath = await _findExecutable('psql');
      if (psqlPath == null) {
        return (false, 'psql não encontrado. Não é possível restaurar na nuvem.', null);
      }

      // 1. Rede de segurança: foto do estado ATUAL da nuvem para esta empresa.
      onProgress?.call('Guardando o estado atual da nuvem (rede de segurança)...');
      final agora = DateTime.now();
      final carimbo = '${agora.year}${agora.month.toString().padLeft(2, '0')}'
          '${agora.day.toString().padLeft(2, '0')}_${agora.hour.toString().padLeft(2, '0')}'
          '${agora.minute.toString().padLeft(2, '0')}';
      final dir = Directory(pastaBackupEmpresaNuvem(idEmpresa));
      if (!await dir.exists()) await dir.create(recursive: true);
      final (okFoto, msgFoto, caminhoFoto) = await criarBackupSqlDaEmpresaNaNuvem(
        empresaId: idEmpresa,
        destinoArquivo: p.join(dir.path, 'ANTES_DE_RESTAURAR_$carimbo.sql'),
        onProgress: onProgress,
      );
      if (!okFoto) {
        return (
          false,
          'Não segurei o estado atual da nuvem, então não restaurei\n\n'
              'A restauração na nuvem só roda com a foto de segurança já salva. Motivo: $msgFoto',
          null,
        );
      }

      final (argsNuvem, ambienteNuvem) = _conexaoPsqlNuvem(
        host: host,
        porta: porta,
        usuario: usuario,
        senha: senha,
        banco: EnvConfig.supabaseDbNameFinal,
      );

      // 2. Aplicar o arquivo (o próprio script apaga e recarrega só esta empresa).
      onProgress?.call('Aplicando ${p.basename(sqlFile.path)} na nuvem...');
      final result = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: argsNuvem,
        ambiente: ambienteNuvem,
        arquivo: sqlFile.path,
      ).timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw TimeoutException('Restauração na nuvem excedeu 30 minutos'),
      );

      final stderr = (result.stderr as String? ?? '').trim();
      final stdout = (result.stdout as String? ?? '').trim();
      if (result.exitCode == 0) {
        debugPrint('>>> [BackupRestore] ✅ Empresa $idEmpresa restaurada NA NUVEM. Foto anterior: $caminhoFoto');
        await registrarAuditoria('✅ Restauração NA NUVEM concluída (${p.basename(sqlFile.path)}; '
            '${integridade.registros} registro(s) em ${integridade.tabelas} tabela(s); '
            'empresa $idEmpresa) — foto anterior: '
            '${caminhoFoto == null ? 'não gerada' : p.basename(caminhoFoto)}');
        return (
          true,
          'Empresa restaurada NA NUVEM. A foto do estado anterior ficou em '
              '${caminhoFoto == null ? 'C:\\ExodoBackups\\nuvem\\empresas' : p.basename(caminhoFoto)}.',
          caminhoFoto,
        );
      }

      debugPrint('>>> [BackupRestore] ❌ Erro ao restaurar na nuvem (${result.exitCode}): $stderr');
      await registrarAuditoria('❌ Falha na restauração NA NUVEM (${p.basename(sqlFile.path)}) — '
          'a nuvem não foi alterada pelo app. $stderr');
      return (
        false,
        'Erro ao restaurar na nuvem: ${stderr.isNotEmpty ? stderr : stdout}',
        caminhoFoto,
      );
    } on TimeoutException {
      return (false, 'A restauração na nuvem excedeu o tempo limite (30 min).', null);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro inesperado ao restaurar na nuvem: $e');
      return (false, 'Erro inesperado ao restaurar na nuvem: $e', null);
    }
  }

  /// Monta um script .sql com os dados de UMA empresa lidos de [banco] e grava
  /// em [caminho].
  ///
  /// É o núcleo compartilhado de [criarBackupSqlDaEmpresa] (que lê do banco
  /// local) e da restauração de um dump do banco inteiro (que lê de uma base
  /// temporária).
  ///
  /// Retorna (sucesso, mensagem, quantidade de tabelas, quantidade de registros).
  /// [argsConexao]/[ambienteConexao] permitem ler de OUTRO servidor (é assim que
  /// o backup da empresa é tirado direto da NUVEM); sem eles, lê do banco local
  /// com [banco] como nome do banco. [origem] só descreve de onde vieram os dados
  /// no cabeçalho do arquivo.
  Future<(bool, String, int, int)> _gerarScriptSqlDaEmpresa({
    required String banco,
    required String empresaId,
    required String nomeEmpresa,
    required String caminho,
    List<String>? argsConexao,
    Map<String, String>? ambienteConexao,
    String origem = 'banco local',
  }) async {
    try {
      final psqlPath = await _findExecutable('psql');
      if (psqlPath == null) {
        return (false, 'psql não encontrado. Não é possível montar o backup PostgreSQL.', 0, 0);
      }

      final (baseArgs, ambiente) = argsConexao != null && ambienteConexao != null
          ? (argsConexao, ambienteConexao)
          : _conexaoPsql(banco: banco);
      final tabelas = await _tabelasDaEmpresa(psqlPath, baseArgs, ambiente);
      if (tabelas.isEmpty) {
        return (false, 'Nenhuma tabela com empresa_id encontrada em "$banco".', 0, 0);
      }

      final idSql = empresaId.replaceAll("'", "''");

      debugPrint('>>> [BackupRestore] 🗄️ Lendo $banco — empresa $nomeEmpresa ($empresaId): ${tabelas.length} tabelas');

      // 1. Coletar os dados de cada tabela no formato COPY (texto) do PostgreSQL
      final blocos = <({String tabela, String colunasSql, String dados, int linhas})>[];
      for (final t in tabelas) {
        final colunasSql = t.colunas.map(_ident).join(', ');
        final comando = '\\copy (SELECT $colunasSql FROM public.${_ident(t.tabela)} '
            "WHERE empresa_id = '$idSql') TO STDOUT";

        final result = await _executarPsql(
          psqlPath: psqlPath,
          baseArgs: baseArgs,
          ambiente: ambiente,
          comando: comando,
        );
        if (result.exitCode != 0) {
          return (false, 'Falha ao exportar a tabela ${t.tabela}: ${result.stderr}', 0, 0);
        }

        final dados = (result.stdout as String).replaceAll('\r\n', '\n');
        final linhas = dados.isEmpty ? 0 : dados.split('\n').where((l) => l.isNotEmpty).length;
        blocos.add((tabela: t.tabela, colunasSql: colunasSql, dados: dados, linhas: linhas));
      }

      final totalLinhas = blocos.fold<int>(0, (soma, b) => soma + b.linhas);
      final agora = DateTime.now();

      // 2. Montar o script SQL (cabeçalho + deletes + COPYs)
      final buffer = StringBuffer();
      buffer.writeln('-- ============================================================');
      buffer.writeln('-- Backup PostgreSQL — SOMENTE a empresa: $nomeEmpresa');
      buffer.writeln('-- empresa_id: $empresaId');
      buffer.writeln('-- Origem: $origem');
      buffer.writeln('-- Gerado em ${agora.toIso8601String()} pelo Sistema Êxodo');
      buffer.writeln('-- Tabelas: ${blocos.length} | Registros: $totalLinhas');
      buffer.writeln('-- ============================================================');
      buffer.writeln('-- RESTAURAR este backup:');
      buffer.writeln('--   psql -h <host> -p <porta> -U <usuario> -d <banco> -f "<este arquivo>"');
      buffer.writeln('-- O script apaga e recarrega APENAS as linhas desta empresa.');
      buffer.writeln('-- As demais empresas do banco permanecem intactas.');
      buffer.writeln('--');
      buffer.writeln('-- NUVEM: este script NAO altera o Supabase. Ele roda com');
      buffer.writeln("--   SET exodo.sync_mode = 'on', que desliga o trigger de fila de envio --");
      buffer.writeln('--   por isso o sincronizador de bandeja nao propaga estas linhas.');
      buffer.writeln('-- ============================================================');
      buffer.writeln("SET client_encoding = 'UTF8';");
      // Mantém a restauração INVISÍVEL para o sincronizador: com este modo
      // ligado o trigger `log_sync_event` não registra nada no
      // `_exodo_sync_log`, então nem o sincronizador de bandeja nem qualquer
      // outro cliente propagam este arquivo para a nuvem.
      buffer.writeln("SET exodo.sync_mode = 'on';");
      buffer.writeln('BEGIN;');
      buffer.writeln();

      for (final b in blocos) {
        buffer.writeln('DELETE FROM public.${_ident(b.tabela)} WHERE empresa_id = \'$idSql\';');
      }
      buffer.writeln();

      for (final b in blocos) {
        buffer.writeln('-- Tabela public.${b.tabela} (${b.linhas} registro(s))');
        buffer.writeln('COPY public.${_ident(b.tabela)} (${b.colunasSql}) FROM stdin;');
        if (b.dados.isNotEmpty) {
          buffer.write(b.dados);
          // O terminador `\.` PRECISA estar sozinho em uma linha nova
          if (!b.dados.endsWith('\n')) buffer.writeln();
        }
        buffer.writeln('\\.');
        buffer.writeln();
      }

      buffer.writeln('COMMIT;');

      // 3. Salvar o arquivo
      final arquivo = File(caminho);
      await arquivo.writeAsString(buffer.toString(), flush: true);

      debugPrint('>>> [BackupRestore] ✅ Script .sql da empresa gerado ($caminho — ${blocos.length} tabelas, $totalLinhas registros)');
      return (true, 'Script .sql da empresa gerado.', blocos.length, totalLinhas);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao montar o SQL da empresa: $e');
      return (false, 'Erro ao montar o SQL da empresa: $e', 0, 0);
    }
  }

  /// Lê o cabeçalho de um backup .sql por empresa (gerado por
  /// [criarBackupSqlDaEmpresa]) sem carregar o arquivo inteiro.
  ///
  /// É o que permite à tela mostrar de QUAL empresa é cada arquivo antes de
  /// restaurar — o nome do arquivo pode estar enganoso (backups antigos saíam com
  /// o nome da empresa aberta na tela), mas o `empresa_id` do cabeçalho é sempre
  /// o dono real dos dados.
  ///
  /// Campos ficam nulos quando o arquivo não é um desses scripts.
  Future<({String? empresaId, String? empresaNome, int? tabelas, int? registros})>
      lerCabecalhoScriptEmpresa(File arquivo) async {
    String texto = '';
    try {
      final raf = await arquivo.open();
      try {
        texto = utf8.decode(await raf.read(4096), allowMalformed: true);
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível ler ${arquivo.path}: $e');
    }

    final id = RegExp(r'^--\s*empresa_id:\s*(\S+)', multiLine: true).firstMatch(texto)?.group(1)?.trim();
    final nome = RegExp(r'^--\s*Backup PostgreSQL[^:]*:\s*(.+)$', multiLine: true)
        .firstMatch(texto)
        ?.group(1)
        ?.trim();
    final contagem = RegExp(r'^--\s*Tabelas:\s*(\d+)\s*\|\s*Registros:\s*(\d+)', multiLine: true)
        .firstMatch(texto);

    return (
      empresaId: id,
      empresaNome: nome,
      tabelas: int.tryParse(contagem?.group(1) ?? ''),
      registros: int.tryParse(contagem?.group(2) ?? ''),
    );
  }

  /// Quantas linhas cada tabela tem DENTRO de um `.sql` por empresa (blocos
  /// `COPY`).
  ///
  /// É a mesma leitura que [verificarIntegridadeScriptEmpresa] faz para contar o
  /// total do arquivo — aqui separada por tabela, para comparar com o banco.
  Future<Map<String, int>> contarLinhasDoScriptEmpresa(File arquivo) async {
    final porTabela = <String, int>{};
    if (!await arquivo.exists()) return porTabela;

    var tabelaAtual = '';
    var dentro = false;
    final linhas =
        arquivo.openRead().transform(utf8.decoder).transform(const LineSplitter());
    await for (final linha in linhas) {
      final t = linha.trimRight();
      if (t.startsWith('COPY public.')) {
        final trecho = t.substring('COPY public.'.length);
        final fim = trecho.indexOf(RegExp(r'[\s(]'));
        tabelaAtual =
            (fim < 0 ? trecho : trecho.substring(0, fim)).replaceAll('"', '').trim();
        porTabela.putIfAbsent(tabelaAtual, () => 0);
        dentro = true;
        continue;
      }
      if (!dentro) continue;
      if (t == r'\.') {
        dentro = false;
        tabelaAtual = '';
        continue;
      }
      if (t.isNotEmpty) {
        porTabela[tabelaAtual] = (porTabela[tabelaAtual] ?? 0) + 1;
      }
    }
    return porTabela;
  }

  /// Simula (SEM alterar nada) a restauração de um `.sql` por empresa.
  ///
  /// Como o script apaga e recarrega somente os dados da empresa dele, dá para
  /// prever o resultado sem aplicar: conta as linhas de cada tabela dentro do
  /// ARQUIVO e compara com o que existe hoje no banco LOCAL, tabela por tabela.
  ///
  /// É a versão rápida e exata do 🔎 — não cria base temporária, não escreve
  /// nada e responde em segundos, porque este arquivo já é filtrado por
  /// `empresa_id`. Funciona igual para o arquivo da pasta local e para o que foi
  /// baixado da nuvem (é o mesmo conteúdo).
  ///
  /// Tabelas que não têm `empresa_id` no banco local (ex.: `empresas`, que
  /// guarda a própria empresa) ficam fora: a contagem por empresa não se aplica
  /// a elas, e inventar número ali só confundiria.
  Future<(bool, String, Map<String, ({int antes, int depois, int delta})>?)>
      simularRestauracaoBackupSqlDaEmpresa(
    File sqlFile, {
    String? empresaId,
  }) async {
    try {
      if (!await sqlFile.exists()) {
        return (false, 'Arquivo não encontrado: ${sqlFile.path}', null);
      }

      // 1. O arquivo é válido/completo? (mesma conferência da restauração)
      final integridade = await verificarIntegridadeScriptEmpresa(sqlFile);
      if (!integridade.ok) {
        return (false, 'Arquivo recusado: ${integridade.mensagem}', null);
      }

      final id = (integridade.empresaId ?? empresaId ?? _dataService.currentEmpresaId)
          ?.trim();
      if (id == null || id.isEmpty) {
        return (
          false,
          'Não sei de qual empresa é este arquivo (o cabeçalho não tem empresa_id).',
          null,
        );
      }

      final doArquivo = await contarLinhasDoScriptEmpresa(sqlFile);
      if (doArquivo.isEmpty) {
        return (false, 'O arquivo não tem nenhuma linha de dados para comparar.', null);
      }

      final psqlPath = await _findExecutable('psql');
      if (psqlPath == null) {
        return (false, 'psql não encontrado. Não é possível simular esta restauração.', null);
      }

      final (argsLocal, ambienteLocal) = _conexaoPsql();
      final comEmpresa = await _tabelasComEmpresaIdNoLocal(psqlPath, argsLocal, ambienteLocal);
      final idSql = id.replaceAll("'", "''");

      final comparativo = <String, ({int antes, int depois, int delta})>{};
      final semEmpresaId = <String>[];
      for (final entry in doArquivo.entries) {
        if (!comEmpresa.contains(entry.key)) {
          semEmpresaId.add(entry.key);
          continue;
        }
        final antes = await _contarLinhasDaEmpresa(
          psqlPath: psqlPath,
          baseArgs: argsLocal,
          ambiente: ambienteLocal,
          tabela: entry.key,
          empresaIdSql: idSql,
        );
        final qtdAntes = antes ?? 0;
        comparativo[entry.key] = (
          antes: qtdAntes,
          depois: entry.value,
          delta: entry.value - qtdAntes,
        );
      }

      if (comparativo.isEmpty) {
        return (false, 'Não foi possível comparar os registros deste arquivo.', null);
      }

      final somaAntes = comparativo.values.fold<int>(0, (s, v) => s + v.antes);
      final somaDepois = comparativo.values.fold<int>(0, (s, v) => s + v.depois);
      final perdem = comparativo.values.where((v) => v.delta < 0).length;
      final ganham = comparativo.values.where((v) => v.delta > 0).length;
      final iguais = comparativo.values.where((v) => v.delta == 0).length;

      debugPrint('>>> [BackupRestore] 🔎 Simulação (empresa $id): $somaAntes → $somaDepois '
          'registros ($perdem tabelas com perda, $ganham com ganho, $iguais iguais)');

      final partes = <String>[
        'Arquivo da empresa $id: ${comparativo.length} tabela(s) comparada(s), '
            '$somaDepois registro(s) no arquivo no lugar de $somaAntes que existem hoje.',
        '$perdem tabela(s) perderiam registros, $ganham ganhariam e $iguais não mudariam.',
        'NADA foi alterado no banco local.',
      ];
      if (semEmpresaId.isNotEmpty) {
        partes.add('Fora da conta (não têm empresa_id): ${semEmpresaId.take(6).join(', ')}'
            '${semEmpresaId.length > 6 ? '…' : ''}');
      }

      return (true, partes.join('\n'), comparativo);
    } catch (e) {
      return (false, 'Erro ao simular a restauração: $e', null);
    }
  }

  /// Nomes das tabelas do banco LOCAL que possuem a coluna `empresa_id`.
  Future<Set<String>> _tabelasComEmpresaIdNoLocal(
    String psqlPath,
    List<String> baseArgs,
    Map<String, String> ambiente,
  ) async {
    try {
      final res = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: "SELECT table_name FROM information_schema.columns "
            "WHERE table_schema = 'public' AND column_name = 'empresa_id'",
      );
      return (res.stdout as String? ?? '')
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível listar as tabelas com empresa_id: $e');
      return <String>{};
    }
  }

  /// Restaura um backup .sql gerado por [criarBackupSqlDaEmpresa].
  ///
  /// O próprio arquivo contém os `DELETE ... WHERE empresa_id = '<id>'`, então
  /// somente os dados da empresa do backup são substituídos.
  /// Retorna (sucesso, mensagem).
  Future<(bool, String)> restaurarBackupSqlDaEmpresa(
    File sqlFile, {
    String motivo = 'manual',
  }) async {
    try {
      if (!await sqlFile.exists()) {
        return (false, 'Arquivo de backup não encontrado: ${sqlFile.path}');
      }

      // 1. O arquivo está COMPLETO? (arquivo cortado apaga e recarrega pela
      // metade — é o pior cenário; aqui ele é recusado antes de encostar no banco)
      final integridade = await verificarIntegridadeScriptEmpresa(sqlFile);
      if (!integridade.ok) {
        await registrarAuditoria('⛔ Restauração BLOQUEADA (arquivo inválido: '
            '${p.basename(sqlFile.path)}) — ${integridade.mensagem}');
        return (false, 'Restauração bloqueada: ${integridade.mensagem}');
      }

      // 2. Trava de segurança: se o arquivo declara o empresa_id dele, ele só pode
      // ser aplicado naquela empresa (evita restaurar o backup de outra empresa
      // por engano quando o arquivo está na pasta errada).
      final idArquivo = integridade.empresaId;
      final idAtual = _dataService.currentEmpresaId;
      if (idArquivo != null && idAtual != null && idAtual.isNotEmpty && idArquivo != idAtual) {
        await registrarAuditoria('⛔ Restauração BLOQUEADA (empresa do arquivo: $idArquivo, '
            'empresa aberta: $idAtual) — ${p.basename(sqlFile.path)}');
        return (
          false,
          'Este backup é da empresa $idArquivo, não da empresa selecionada. '
              'Selecione essa empresa para restaurá-lo.',
        );
      }

      final psqlPath = await _findExecutable('psql');
      if (psqlPath == null) {
        return (false, 'psql não encontrado. Não é possível restaurar o backup PostgreSQL.');
      }

      // 3. Rede de segurança OBRIGATÓRIA: guarda o estado atual desta empresa.
      // Se isto falhar, não restaura — perder o estado atual não pode ser efeito
      // colateral de um clique.
      String? caminhoDesfazer;
      if (idAtual != null && idAtual.isNotEmpty) {
        final (okSnap, msgSnap, caminhoSnap) = await backupAntesDeRestaurarEmpresa(
          empresaId: idAtual,
          motivo: motivo,
        );
        if (!okSnap) {
          await registrarAuditoria('⛔ Restauração CANCELADA (sem backup de segurança): $msgSnap');
          return (
            false,
            'Não guardei o estado atual, então NÃO restaurei\n\n'
                'A restauração só roda com o backup de segurança já salvo em '
                '$pastaAntesDeRestaurar. Motivo da falha: $msgSnap',
          );
        }
        caminhoDesfazer = caminhoSnap;
        ultimoBackupAntesDeRestaurar = caminhoSnap;
        debugPrint('>>> [BackupRestore] 🛡️ Estado de antes guardado: $caminhoSnap');
      }

      final (baseArgs, ambiente) = _conexaoPsql();

      // 4. O banco local responde? Melhor descobrir agora, com uma mensagem
      // clara, do que no meio da carga.
      final ping = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: 'SELECT 1;',
      );
      if (ping.exitCode != 0) {
        await registrarAuditoria('⛔ Restauração CANCELADA (PostgreSQL local não respondeu): '
            '${(ping.stderr as String? ?? '').trim()}');
        return (
          false,
          'Não consegui falar com o PostgreSQL local, então nada foi feito. '
              'Confira se o serviço está rodando. Detalhe: ${(ping.stderr as String? ?? '').trim()}',
        );
      }

      // Restauração SÓ no banco local: roda com o trigger de fila desligado e,
      // antes de apagar/reescrever as linhas, limpa o que estava pendente de
      // envio para esta empresa. Assim a nuvem não é sobrescrita nem apagada.
      final ambienteSeguro = _ambienteRestauroLocal(ambiente);
      final idLimpeza = idArquivo ?? idAtual;
      if (idLimpeza != null && idLimpeza.isNotEmpty) {
        await _limparPendenciasDeEnvioDaEmpresa(
          psqlPath: psqlPath,
          baseArgs: baseArgs,
          ambiente: ambienteSeguro,
          empresaId: idLimpeza,
        );
      }

      debugPrint('>>> [BackupRestore] 🔄 Restaurando backup SQL por empresa (só local): ${sqlFile.path}');

      final result = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambienteSeguro,
        arquivo: sqlFile.path,
      ).timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw TimeoutException('Restauração excedeu o tempo limite de 30 minutos'),
      );

      final stderr = (result.stderr as String? ?? '').trim();
      final stdout = (result.stdout as String? ?? '').trim();

      if (result.exitCode == 0) {
        debugPrint('>>> [BackupRestore] ✅ Backup SQL restaurado com sucesso (a nuvem não foi tocada)!');

        // Confirmação pós-carga: o banco tem exatamente o que o arquivo trazia?
        final carregadas = idLimpeza == null
            ? null
            : await _contarLinhasCarregadas(
                psqlPath: psqlPath,
                baseArgs: baseArgs,
                ambiente: ambienteSeguro,
                tabelas: integridade.listaTabelas,
                empresaId: idLimpeza,
              );
        final conferencia = (carregadas == null || integridade.registros == null)
            ? 'Conferência pós-carga: não foi possível medir (o arquivo continua aplicado).'
            : carregadas == integridade.registros
                ? 'Conferência pós-carga: ✅ o banco local tem exatamente '
                    '${integridade.registros} registro(s) desta empresa, igual ao arquivo.'
                : '⚠️ ATENÇÃO: o arquivo trazia ${integridade.registros} registro(s) e o banco '
                    'local ficou com $carregadas. Confira os dados desta empresa.';

        // Trilha: guarda o arquivo exatamente como foi aplicado.
        final carimbo = DateTime.now()
            .toIso8601String()
            .replaceAll(RegExp(r'[:.]'), '-')
            .substring(0, 19);
        final copia = await _guardarCopiaDoAplicado(
          origem: sqlFile,
          empresaId: idLimpeza ?? 'desconhecida',
          carimbo: carimbo,
        );

        await registrarAuditoria('✅ Restauração LOCAL concluída (${p.basename(sqlFile.path)}; '
            '${integridade.registros} registro(s) em ${integridade.tabelas} tabela(s); '
            'empresa ${idArquivo ?? '?'}) — desfazer: '
            '${caminhoDesfazer == null ? 'não gerado' : p.basename(caminhoDesfazer)}; '
            'cópia do aplicado: ${copia == null ? 'não guardada' : p.basename(copia)}; '
            '$conferencia');
        return (
          true,
          'Backup restaurado SOMENTE no banco local '
              '(${integridade.registros} registro(s) em ${integridade.tabelas} tabela(s)).\n'
              '$conferencia\n'
              'A nuvem não foi alterada — nada foi sobrescrito nem apagado lá.\n'
              '${caminhoDesfazer == null ? '' : 'Para desfazer: o estado anterior ficou em ${p.basename(caminhoDesfazer)}.'}',
        );
      }

      debugPrint('>>> [BackupRestore] ❌ Erro na restauração SQL (exitCode: ${result.exitCode})');
      debugPrint('>>> [BackupRestore] STDERR: $stderr');
      await registrarAuditoria('❌ Falha na restauração LOCAL (${p.basename(sqlFile.path)}) — '
          'o banco não foi alterado (transação revertida). ${stderr.isEmpty ? stdout : stderr}');

      if (stderr.contains('could not connect') || stderr.contains('connection refused')) {
        return (false, 'Não foi possível conectar ao PostgreSQL. Verifique se o serviço está rodando.');
      }
      if (stderr.contains('authentication failed') || stderr.contains('password authentication')) {
        return (false, 'Falha de autenticação. Verifique DB_USER e DB_PASSWORD no arquivo .env');
      }
      return (
        false,
        'Erro ao restaurar backup (o banco local NÃO foi alterado — a transação foi '
            'revertida): ${stderr.isNotEmpty ? stderr : stdout}',
      );
    } on TimeoutException {
      return (false, 'Restauração excedeu o tempo limite (30 min).');
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro inesperado ao restaurar backup SQL: $e');
      return (false, 'Erro inesperado ao restaurar backup: $e');
    }
  }

  // ============================================================
  // RESTAURAR UM DUMP (BANCO INTEIRO) SÓ NA EMPRESA SELECIONADA
  // ============================================================

  /// Restaura SOMENTE os dados da empresa [empresaId] a partir de um dump
  /// PostgreSQL (.dump/.sql) — mesmo que o dump contenha os dados de VÁRIAS
  /// empresas.
  ///
  /// Como o dump é do banco inteiro, ele é carregado primeiro numa base
  /// TEMPORÁRIA (`exodo_restore_tmp_...`, apagada no final) e, a partir dela, é
  /// montado um script .sql com APENAS as linhas da empresa escolhida (mesmo
  /// formato de [criarBackupSqlDaEmpresa], com `DELETE ... WHERE empresa_id` +
  /// `COPY`). Esse script é então aplicado no banco
  /// LOCAL: só as linhas dessa empresa são substituídas — as demais empresas
  /// do computador ficam intactas.
  ///
  /// O banco local NÃO é alterado se o dump não puder ser carregado ou se ele
  /// não tiver nenhum dado desta empresa.
  ///
  /// Retorna (sucesso, mensagem).
  Future<(bool, String)> restaurarDumpSomenteEmpresa({
    required File dumpFile,
    String? empresaId,
    void Function(String)? onProgress,
  }) async {
    if (kIsWeb) {
      return (false, 'Restauração não está disponível na versão Web.');
    }

    final idEmpresa = empresaId ?? _dataService.currentEmpresaId;
    if (idEmpresa == null || idEmpresa.isEmpty) {
      return (false, 'Empresa não selecionada');
    }
    if (!await dumpFile.exists()) {
      return (false, 'Arquivo não encontrado: ${dumpFile.path}');
    }

    final arquivoMin = p.basename(dumpFile.path).toLowerCase();
    final isSql = arquivoMin.endsWith('.sql');
    final isDump = arquivoMin.endsWith('.dump') ||
        arquivoMin.endsWith('.pg_dump') ||
        arquivoMin.endsWith('.bak');
    if (!isSql && !isDump) {
      return (false, 'Formato de arquivo não reconhecido. Use arquivos .sql ou .dump');
    }

    final psqlPath = await _findExecutable('psql');
    if (psqlPath == null) {
      return (false, 'psql não encontrado. Não é possível restaurar este dump.');
    }

    final nomeEmpresa = _dataService.empresaAtual?.nomeExibicao ?? idEmpresa;
    final pastaTemp = Directory(p.join(Directory.systemTemp.path, 'exodo_restore'));
    File? scriptEmpresa;

    void progresso(String mensagem) {
      debugPrint('>>> [BackupRestore] $mensagem');
      onProgress?.call(mensagem);
    }

    try {
      if (!await pastaTemp.exists()) await pastaTemp.create(recursive: true);
      scriptEmpresa = File(p.join(pastaTemp.path, 'empresa_${idEmpresa}_${DateTime.now().millisecondsSinceEpoch}.sql'));

      // 1-2. Base temporária com o dump carregado
      return await _lerDumpNaBaseTemporaria(
        dumpFile: dumpFile,
        psqlPath: psqlPath,
        isSql: isSql,
        progresso: progresso,
        acao: (bancoTemp) async {
          // 3. Separar apenas as linhas da empresa selecionada
          progresso('Separando os dados de $nomeEmpresa...');
          final (okScript, msgScript, qtdTabelas, qtdLinhas) = await _gerarScriptSqlDaEmpresa(
            banco: bancoTemp,
            empresaId: idEmpresa,
            nomeEmpresa: nomeEmpresa,
            caminho: scriptEmpresa!.path,
          );
          if (!okScript) return (false, msgScript);

          // Segurança: sem registros desta empresa, nada é apagado no banco local
          if (qtdLinhas == 0) {
            return (false, 'O backup não tem nenhum dado de "$nomeEmpresa". Nada foi alterado no banco local.');
          }

          // 4. Aplicar no banco LOCAL — apaga e recarrega SOMENTE esta empresa
          progresso('Aplicando no banco local (somente $nomeEmpresa)...');
          final (ok, msg) = await restaurarBackupSqlDaEmpresa(scriptEmpresa);
          if (!ok) return (false, msg);

          debugPrint('>>> [BackupRestore] ✅ Restauração por empresa concluída: $qtdLinhas registros em $qtdTabelas tabelas');
          return (
            true,
            'Restaurados $qtdLinhas registro(s) de $qtdTabelas tabela(s) — SOMENTE de "$nomeEmpresa". '
                'As outras empresas deste computador não foram alteradas.',
          );
        },
      );
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao restaurar somente a empresa: $e');
      return (false, 'Erro ao restaurar somente a empresa: $e');
    } finally {
      // 5. Limpeza: script intermediário (a base temporária sai em
      // _lerDumpNaBaseTemporaria)
      try {
        if (scriptEmpresa != null && await scriptEmpresa.exists()) {
          await scriptEmpresa.delete();
        }
      } catch (_) {}
    }
  }

  // ============================================================
  // SIMULAÇÃO ("ENSAIO") DA RESTAURAÇÃO — NÃO ALTERA NADA
  // ============================================================

  /// SIMULA a restauração de um dump na empresa selecionada: compara, tabela por
  /// tabela, quantos registros a empresa tem HOJE e quantos passaria a ter com o
  /// backup. **Nada é alterado no banco local.**
  ///
  /// Serve para responder "o que eu perco se restaurar isto?" antes de aplicar.
  /// O dump é lido na mesma base temporária usada pela restauração de verdade,
  /// então as contagens são exatamente as que a restauração produziria.
  ///
  /// Retorna (sucesso, mensagem, comparativo por tabela).
  Future<(bool, String, Map<String, ({int antes, int depois, int delta})>?)>
      simularRestauracaoDumpSomenteEmpresa({
    required File dumpFile,
    String? empresaId,
    void Function(String)? onProgress,
  }) async {
    if (kIsWeb) {
      return (false, 'Simulação não está disponível na versão Web.', null);
    }

    final idEmpresa = empresaId ?? _dataService.currentEmpresaId;
    if (idEmpresa == null || idEmpresa.isEmpty) {
      return (false, 'Empresa não selecionada', null);
    }
    if (!await dumpFile.exists()) {
      return (false, 'Arquivo não encontrado: ${dumpFile.path}', null);
    }

    final arquivoMin = p.basename(dumpFile.path).toLowerCase();
    final isSql = arquivoMin.endsWith('.sql');
    final isDump = arquivoMin.endsWith('.dump') ||
        arquivoMin.endsWith('.pg_dump') ||
        arquivoMin.endsWith('.bak');
    if (!isSql && !isDump) {
      return (false, 'Formato de arquivo não reconhecido. Use arquivos .sql ou .dump', null);
    }

    final psqlPath = await _findExecutable('psql');
    if (psqlPath == null) {
      return (false, 'psql não encontrado. Não é possível simular esta restauração.', null);
    }

    final nomeEmpresa = _dataService.empresaAtual?.nomeExibicao ?? idEmpresa;
    Map<String, ({int antes, int depois, int delta})>? comparativo;

    void progresso(String mensagem) {
      debugPrint('>>> [BackupRestore] $mensagem');
      onProgress?.call(mensagem);
    }

    final (ok, msg) = await _lerDumpNaBaseTemporaria(
      dumpFile: dumpFile,
      psqlPath: psqlPath,
      isSql: isSql,
      progresso: progresso,
      acao: (bancoTemp) async {
        progresso('Comparando os registros de $nomeEmpresa...');
        final (okComparacao, msgComparacao, comparacao) =
            await _compararContagensDaEmpresa(bancoBackup: bancoTemp, empresaId: idEmpresa);
        if (!okComparacao || comparacao == null) return (false, msgComparacao);
        comparativo = comparacao;
        return (true, 'Comparação concluída.');
      },
    );

    if (!ok || comparativo == null) {
      return (false, msg, null);
    }

    final valores = comparativo!.values;
    final somaAntes = valores.fold<int>(0, (soma, v) => soma + v.antes);
    final somaDepois = valores.fold<int>(0, (soma, v) => soma + v.depois);
    final perdem = valores.where((v) => v.delta < 0).length;
    final ganham = valores.where((v) => v.delta > 0).length;
    final iguais = valores.where((v) => v.delta == 0).length;

    debugPrint('>>> [BackupRestore] 🔎 Simulação: $somaAntes → $somaDepois registros '
        '($perdem tabelas com perda, $ganham com ganho, $iguais iguais)');

    return (
      true,
      'Simulação de "$nomeEmpresa": $somaDepois registros no lugar de $somaAntes. '
          '$perdem tabela(s) perdem registros, $ganham ganham e $iguais não mudam. '
          'NADA foi alterado no banco local.',
      comparativo,
    );
  }

  /// Compara as contagens da empresa [empresaId] entre o banco do backup
  /// ([bancoBackup]) e o banco LOCAL, tabela por tabela.
  ///
  /// As tabelas consideradas são as do BACKUP — exatamente as que o script de
  /// restauração apaga e recarrega. Tabela que só existe no banco local não é
  /// tocada pela restauração, então fica fora da comparação.
  ///
  /// Retorna (sucesso, mensagem, comparativo).
  Future<(bool, String, Map<String, ({int antes, int depois, int delta})>?)>
      _compararContagensDaEmpresa({
    required String bancoBackup,
    required String empresaId,
  }) async {
    final psqlPath = await _findExecutable('psql');
    if (psqlPath == null) {
      return (false, 'psql não encontrado. Não é possível comparar os registros.', null);
    }

    final (argsBackup, ambienteBackup) = _conexaoPsql(banco: bancoBackup);
    final tabelas = await _tabelasDaEmpresa(psqlPath, argsBackup, ambienteBackup);
    if (tabelas.isEmpty) {
      return (false, 'Nenhuma tabela com empresa_id encontrada no dump.', null);
    }

    final (argsLocal, ambienteLocal) = _conexaoPsql();
    final idSql = empresaId.replaceAll("'", "''");
    final comparativo = <String, ({int antes, int depois, int delta})>{};

    for (final tabela in tabelas) {
      final depois = await _contarLinhasDaEmpresa(
        psqlPath: psqlPath,
        baseArgs: argsBackup,
        ambiente: ambienteBackup,
        tabela: tabela.tabela,
        empresaIdSql: idSql,
      );
      final antes = await _contarLinhasDaEmpresa(
        psqlPath: psqlPath,
        baseArgs: argsLocal,
        ambiente: ambienteLocal,
        tabela: tabela.tabela,
        empresaIdSql: idSql,
      );
      if (depois == null && antes == null) continue;
      final qtdAntes = antes ?? 0;
      final qtdDepois = depois ?? 0;
      comparativo[tabela.tabela] = (
        antes: qtdAntes,
        depois: qtdDepois,
        delta: qtdDepois - qtdAntes,
      );
    }

    if (comparativo.isEmpty) {
      return (false, 'Não foi possível comparar os registros deste backup.', null);
    }
    return (true, 'Comparação concluída.', comparativo);
  }

  /// Quantos registros a empresa tem em [tabela] no banco conectado por
  /// [baseArgs]. Devolve null quando a tabela não existe naquele banco.
  Future<int?> _contarLinhasDaEmpresa({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    required String tabela,
    required String empresaIdSql,
  }) async {
    final result = await _executarPsql(
      psqlPath: psqlPath,
      baseArgs: baseArgs,
      ambiente: ambiente,
      comando: "SELECT count(*) FROM public.${_ident(tabela)} WHERE empresa_id = '$empresaIdSql';",
    );
    if (result.exitCode != 0) return null;
    return int.tryParse((result.stdout as String? ?? '').trim());
  }

  /// Cria a base temporária, carrega [dumpFile] nela e executa [acao] com o nome
  /// dessa base. A base temporária é SEMPRE removida no final — este método
  /// nunca altera o banco local, é só leitura do dump.
  ///
  /// Retorna o que [acao] devolver.
  Future<(bool, String)> _lerDumpNaBaseTemporaria({
    required File dumpFile,
    required String psqlPath,
    required bool isSql,
    required void Function(String) progresso,
    required Future<(bool, String)> Function(String bancoTemp) acao,
  }) async {
    final bancoTemp = 'exodo_restore_tmp_${DateTime.now().millisecondsSinceEpoch}';
    try {
      // 1. Base temporária — o banco local não é tocado neste passo
      progresso('Criando base temporária para ler o dump...');
      final (okBase, msgBase) = await _criarBaseTemporaria(psqlPath, bancoTemp);
      if (!okBase) return (false, msgBase);

      // 2. Carregar o dump (todas as empresas) dentro da base temporária
      progresso('Lendo o dump (conteúdo de todas as empresas)...');
      final (okDump, msgDump) = await _restaurarArquivoNaBase(
        arquivo: dumpFile,
        banco: bancoTemp,
        psqlPath: psqlPath,
        isSql: isSql,
      );
      if (!okDump) return (false, msgDump);

      return await acao(bancoTemp);
    } finally {
      try {
        await _removerBaseTemporaria(psqlPath, bancoTemp);
      } catch (_) {}
    }
  }

  /// Cria uma base PostgreSQL vazia e temporária para ler um dump sem mexer no
  /// banco local. Retorna (sucesso, mensagem).
  ///
  /// A base temporária é criada com a MESMA codificação/locale do banco local:
  /// é nela que o dump é carregado e depois lido de volta, então uma codificação
  /// diferente (ex.: banco local em UTF8 e base temporária em WIN1252) quebraria
  /// acentos e símbolos no COPY.
  Future<(bool, String)> _criarBaseTemporaria(String psqlPath, String bancoTemp) async {
    String? comandoComEncoding;
    try {
      final (argsLocal, ambienteLocal) = _conexaoPsql();
      final info = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: argsLocal,
        ambiente: ambienteLocal,
        comando: "SELECT pg_encoding_to_char(encoding) || '|' || datcollate || '|' || datctype "
            'FROM pg_database WHERE datname = current_database();',
      );
      final partes = (info.stdout as String? ?? '').trim().split('|');
      if (info.exitCode == 0 && partes.length == 3 && partes[0].isNotEmpty) {
        comandoComEncoding = 'CREATE DATABASE ${_ident(bancoTemp)} WITH TEMPLATE template0 '
            "ENCODING '${partes[0]}' LC_COLLATE '${partes[1]}' LC_CTYPE '${partes[2]}';";
      }
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível ler a codificação do banco local: $e');
    }

    final (argsPostgres, ambientePostgres) = _conexaoPsql(banco: 'postgres');
    var ultimoErro = '';

    for (final comando in [
      if (comandoComEncoding != null) comandoComEncoding,
      'CREATE DATABASE ${_ident(bancoTemp)};',
    ]) {
      final result = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: argsPostgres,
        ambiente: ambientePostgres,
        comando: comando,
      );
      if (result.exitCode == 0) return (true, 'Base temporária criada.');

      ultimoErro = (result.stderr as String? ?? '').trim();
      debugPrint('>>> [BackupRestore] ⚠️ Falha ao criar a base temporária: $ultimoErro');
      if (ultimoErro.toLowerCase().contains('permission denied') ||
          ultimoErro.toLowerCase().contains('createdb')) {
        final usuario = EnvConfig.env['DB_USER'] ?? 'exodo_user';
        return (
          false,
          'O usuário do banco não tem permissão para criar a base temporária usada para separar '
              'uma empresa. Rode uma vez no psql (como postgres):  ALTER ROLE $usuario CREATEDB;',
        );
      }
    }
    return (false, 'Não foi possível criar a base temporária: $ultimoErro');
  }

  /// Apaga a base temporária. Falhas aqui são só limpeza — nunca interrompem a
  /// restauração.
  Future<void> _removerBaseTemporaria(String psqlPath, String bancoTemp) async {
    final (baseArgs, ambiente) = _conexaoPsql(banco: 'postgres');
    for (final sql in [
      'DROP DATABASE IF EXISTS ${_ident(bancoTemp)};',
      'DROP DATABASE IF EXISTS ${_ident(bancoTemp)} WITH (FORCE);',
    ]) {
      try {
        final result = await _executarPsql(
          psqlPath: psqlPath,
          baseArgs: baseArgs,
          ambiente: ambiente,
          comando: sql,
        );
        if (result.exitCode == 0) return;
      } catch (_) {}
    }
    debugPrint('>>> [BackupRestore] ⚠️ Base temporária $bancoTemp não pôde ser removida.');
  }

  /// Carrega [arquivo] dentro da base [banco] (normalmente a temporária).
  ///
  /// `.dump` vai pelo `pg_restore`; `.sql` (texto) pelo `psql -f`.
  /// Retorna (sucesso, mensagem).
  Future<(bool, String)> _restaurarArquivoNaBase({
    required File arquivo,
    required String banco,
    required String psqlPath,
    required bool isSql,
  }) async {
    final env = EnvConfig.env;
    final dbHost = env['DB_HOST'] ?? '127.0.0.1';
    final dbPort = env['DB_PORT'] ?? '5432';
    final dbUser = env['DB_USER'] ?? 'exodo_user';
    final dbPass = env['DB_PASSWORD'] ?? '';

    final ambiente = Map<String, String>.from(Platform.environment);
    ambiente['PGPASSWORD'] = dbPass;
    ambiente['PGCLIENTENCODING'] = 'UTF8';

    String executavel;
    List<String> args;

    if (isSql) {
      executavel = psqlPath;
      args = ['--no-psqlrc', '-h', dbHost, '-p', dbPort, '-U', dbUser, '-d', banco, '-f', arquivo.path];
    } else {
      final pgRestorePath = await _findExecutable('pg_restore');
      if (pgRestorePath == null) {
        return (false, 'pg_restore não encontrado. Não é possível abrir um arquivo .dump.');
      }
      executavel = pgRestorePath;
      args = [
        '-h', dbHost,
        '-p', dbPort,
        '-U', dbUser,
        '-d', banco,
        '--no-owner',
        '--no-privileges',
        arquivo.path,
      ];
    }

    final result = await runProcessHidden(
      executavel,
      args,
      environment: ambiente,
    ).timeout(
      const Duration(minutes: 60),
      onTimeout: () => throw TimeoutException('Leitura do dump excedeu o tempo limite de 60 minutos'),
    );

    final stderr = (result.stderr as String? ?? '').trim();
    if (result.exitCode == 0) return (true, 'Dump carregado na base temporária.');

    // O pg_restore devolve 1 quando houve avisos (ex.: dono/permissão do
    // schema) mas os dados foram carregados. Quem decide se o dump serviu é o
    // passo seguinte: se a base temporária não tiver dados da empresa, nada é
    // aplicado e o banco local continua intacto.
    if (result.exitCode == 1 && !isSql) {
      debugPrint('>>> [BackupRestore] ⚠️ pg_restore terminou com avisos: $stderr');
      return (true, 'Dump carregado com avisos.');
    }

    debugPrint('>>> [BackupRestore] ❌ Falha ao carregar o dump: $stderr');
    if (stderr.contains('could not connect') || stderr.contains('connection refused')) {
      return (false, 'Não foi possível conectar ao PostgreSQL local. Verifique se o serviço está rodando.');
    }
    if (stderr.contains('authentication failed') || stderr.contains('password authentication')) {
      return (false, 'Falha de autenticação. Verifique DB_USER e DB_PASSWORD no arquivo .env');
    }
    if (stderr.contains('server version mismatch')) {
      return (false, 'A versão do pg_restore deste computador não é compatível com a do dump. Use o PostgreSQL que acompanha o app.');
    }
    return (false, 'Não foi possível ler o dump: ${stderr.isEmpty ? 'erro ${result.exitCode}' : stderr}');
  }

  // ============================================================
  // BACKUP DO BANCO INTEIRO DA NUVEM (Supabase PostgreSQL)
  // ============================================================

  /// Pasta local onde ficam os backups do banco da nuvem.
  static String get _pastaBackupNuvem => 'C:\\ExodoBackups\\nuvem';

  /// Quantos backups do banco da nuvem são mantidos no disco.
  static const int _maxBackupsNuvemLocais = 30;

  /// Gera um backup COMPLETO do banco da NUVEM (Supabase) — todas as empresas,
  /// todo o banco `postgres` — salvando o arquivo no computador.
  ///
  /// Usa o `pg_dump` quando ele é compatível com a versão do servidor da nuvem e,
  /// quando não é (caso do pg_dump 16.4 contra o Supabase 17), cai
  /// automaticamente para [criarBackupSqlBancoNuvem], que gera um `.sql`
  /// completo pelo `psql`.
  ///
  /// Usa a conexão pelo POOLER (IPv4): a conexão direta do Supabase
  /// (db.<ref>.supabase.co) só responde em IPv6 e não funciona em muitas máquinas.
  ///
  /// Os parâmetros de conexão existem para permitir testar/redirecionar a
  /// conexão; em uso normal tudo vem do .env.
  /// Retorna (sucesso, mensagem, caminho do arquivo).
  Future<(bool, String, String?)> criarBackupBancoNuvem({
    String? destinoArquivo,
    String? host,
    int? porta,
    String? usuario,
    String? senha,
    String? banco,
    void Function(String)? onProgress,
  }) async {
    if (kIsWeb) {
      return (false, 'Backup do banco da nuvem não está disponível na versão Web.', null);
    }

    final hostFinal = (host ?? EnvConfig.supabasePoolerHost).trim();
    if (hostFinal.isEmpty) {
      return (
        false,
        'Conexão do banco da nuvem não configurada.\n\n'
        'A conexão DIRETA do Supabase (db.<ref>.supabase.co) só funciona em IPv6, por '
        'isso o backup usa o "Session pooler" (IPv4).\n\n'
        'Confira no arquivo .env:\n'
        'SUPABASE_POOLER_HOST=aws-1-us-west-2.pooler.supabase.com\n'
        'SUPABASE_POOLER_PASSWORD=senha_do_banco',
        null,
      );
    }

    final portaFinal = porta ?? EnvConfig.supabasePoolerPort;
    final usuarioFinal = usuario ?? EnvConfig.supabasePoolerUser;
    final senhaFinal = senha ?? EnvConfig.supabasePoolerPassword;
    final bancoFinal = banco ?? EnvConfig.supabaseDbNameFinal;

    if (senhaFinal.isEmpty) {
      return (
        false,
        'Senha do banco da nuvem não configurada.\n\n'
        'Coloque no .env a senha do BANCO do Supabase (a mesma de "Database password", '
        'no painel do projeto):\n\n'
        'SUPABASE_POOLER_PASSWORD=sua_senha\n\n'
        'Atenção: as chaves de API que começam com "sb_secret_" NÃO são a senha do banco.',
        null,
      );
    }

    try {
      final psqlPath = await _findExecutable('psql');
      if (psqlPath == null) {
        return (false, 'psql não encontrado. Use o PostgreSQL que acompanha o app para gerar o backup da nuvem.', null);
      }

      final (argsNuvem, ambienteNuvem) = _conexaoPsqlNuvem(
        host: hostFinal,
        porta: portaFinal,
        usuario: usuarioFinal,
        senha: senhaFinal,
        banco: bancoFinal,
      );

      // O pg_dump SÓ lê um servidor de versão igual ou MENOR que a dele. Como o
      // Supabase está na versão 17 e o PostgreSQL que acompanha o app na 16, na
      // maioria dos PCs o pg_dump recusa o trabalho ("aborting because of server
      // version mismatch"). Nesse caso o backup é gerado pelo psql, que funciona
      // em qualquer versão.
      final versaoResult = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: argsNuvem,
        ambiente: ambienteNuvem,
        comando: "SELECT current_setting('server_version_num');",
      );

      if (versaoResult.exitCode != 0) {
        final err = (versaoResult.stderr as String? ?? '').trim();
        debugPrint('>>> [BackupRestore] ❌ Falha ao conectar no banco da nuvem: $err');
        return (false, _mensagemErroConexaoNuvem(err, hostFinal, portaFinal, usuarioFinal), null);
      }

      final versaoServidor = int.tryParse(
              (versaoResult.stdout as String? ?? '').replaceAll(RegExp(r'\s'), '')) ??
          0;
      final maiorServidor = versaoServidor ~/ 10000;

      final pgDumpPath = await _findExecutable('pg_dump');
      final maiorPgDump = pgDumpPath == null ? null : await _versaoMaiorExecutavel(pgDumpPath);

      final usarPgDump = pgDumpPath != null &&
          maiorPgDump != null &&
          maiorServidor > 0 &&
          maiorPgDump >= maiorServidor;

      if (!usarPgDump) {
        debugPrint('>>> [BackupRestore] ℹ️ pg_dump ${maiorPgDump ?? '?'} x servidor da nuvem $maiorServidor: '
            'gerando o backup completo com psql (.sql).');
        return criarBackupSqlBancoNuvem(
          destinoArquivo: destinoArquivo,
          host: hostFinal,
          porta: portaFinal,
          usuario: usuarioFinal,
          senha: senhaFinal,
          banco: bancoFinal,
          onProgress: onProgress,
        );
      }

      final agora = DateTime.now();
      final dataStr = '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
      final horaStr = '${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';

      var caminho = destinoArquivo ?? '';
      if (caminho.isEmpty) {
        final dir = Directory(_pastaBackupNuvem);
        if (!await dir.exists()) await dir.create(recursive: true);
        caminho = p.join(dir.path, 'nuvem_${dataStr}_$horaStr.dump');
      }

      debugPrint('>>> [BackupRestore] ☁️ Backup do banco da NUVEM: $usuarioFinal@$hostFinal:$portaFinal/$bancoFinal → $caminho');

      final args = <String>[
        '-h', hostFinal,
        '-p', '$portaFinal',
        '-U', usuarioFinal,
        '-d', bancoFinal,
        '-Fc',
        '--no-owner',
        '--no-privileges',
        '-f', caminho,
      ];

      final ambiente = Map<String, String>.from(Platform.environment);
      ambiente['PGPASSWORD'] = senhaFinal;
      ambiente['PGCLIENTENCODING'] = 'UTF8';

      final result = await runProcessHidden(
        pgDumpPath,
        args,
        environment: ambiente,
      ).timeout(
        const Duration(minutes: 60),
        onTimeout: () => throw TimeoutException('Backup da nuvem excedeu o tempo limite de 60 minutos'),
      );

      if (result.exitCode != 0) {
        final stderr = result.stderr.toString().trim();
        debugPrint('>>> [BackupRestore] ❌ Erro no pg_dump da nuvem (exitCode: ${result.exitCode}): $stderr');

        if (stderr.contains('could not translate host') || stderr.contains('Name or service not known')) {
          return (false, 'Não foi possível resolver o host "$hostFinal". Confira SUPABASE_POOLER_HOST no .env (veja o Session pooler no painel do Supabase).', null);
        }
        if (stderr.contains('tenant/user') && stderr.contains('not found')) {
          return (false, 'Usuário/região incorretos no pooler ("$usuarioFinal"). Copie a string do Session pooler no painel do Supabase e ajuste SUPABASE_POOLER_HOST no .env.', null);
        }
        if (stderr.contains('authentication failed') || stderr.contains('password authentication')) {
          return (false, 'Falha de autenticação. Confira a senha do banco (SUPABASE_POOLER_PASSWORD) no .env.', null);
        }
        if (stderr.contains('server version mismatch')) {
          return (false, 'A versão do pg_dump deste computador é mais antiga que a do banco da nuvem. Use o PostgreSQL que acompanha o app.', null);
        }
        if (stderr.contains('could not connect') || stderr.contains('Connection refused') || stderr.contains('timeout expired')) {
          return (false, 'Não foi possível conectar ao banco da nuvem em $hostFinal:$portaFinal.', null);
        }
        return (false, 'Erro no backup do banco da nuvem: ${stderr.isNotEmpty ? stderr : result.stdout.toString().trim()}', null);
      }

      final arquivo = File(caminho);
      if (!await arquivo.exists()) {
        return (false, 'O pg_dump terminou sem gerar o arquivo esperado.', null);
      }

      final tamanhoMb = (await arquivo.length() / 1024 / 1024).toStringAsFixed(2);
      debugPrint('>>> [BackupRestore] ✅ Backup do banco da nuvem gerado ($tamanhoMb MB): $caminho');

      await _limparBackupsNuvemLocais();

      return (true, 'Backup completo da nuvem gerado ($tamanhoMb MB).', caminho);
    } on TimeoutException {
      return (false, 'Backup do banco da nuvem excedeu o tempo limite (60 min).', null);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro inesperado no backup da nuvem: $e');
      return (false, 'Erro inesperado no backup do banco da nuvem: $e', null);
    }
  }

  // ============================================================
  // CRIAR NA NUVEM O QUE SÓ EXISTE NO BANCO LOCAL
  // ============================================================

  /// Tabelas que são SÓ do banco local (controle/cache interno), que não fazem
  /// sentido na nuvem. Tabelas com nome começando em `_` também ficam de fora.
  static const Set<String> _tabelasSomenteLocais = {'cache_dados'};

  /// Nomes de tabelas que a nuvem deve ter mesmo sem coluna `empresa_id`
  /// (cadastros globais usados pelo app).
  static const Set<String> _tabelasGlobais = {'empresas', 'usuarios'};

  /// Compara o esquema do banco LOCAL com o da NUVEM (Supabase) e **cria o que
  /// falta lá**: tabelas que existem só aqui e colunas que faltam nas tabelas
  /// de lá. Nada é apagado nem alterado em nada que já existe.
  ///
  /// Usa a conexão DIRETA com o banco do Supabase (as mesmas variáveis
  /// SUPABASE_POOLER_* usadas pelo backup da nuvem) — não depende da função RPC
  /// `executar_sql`, que na maioria dos projetos não existe.
  ///
  /// Devolve (sucesso, logs) para a tela mostrar o passo a passo.
  /// Com [somenteComparar] o método faz tudo menos executar: apenas descobre o
  /// que falta, mostra o resultado e salva o SQL em disco ("nada foi criado").
  Future<(bool, List<String>)> criarTabelasFaltantesNaNuvem({
    void Function(String)? onProgress,
    bool somenteComparar = false,
  }) async {
    final logs = <String>[];
    void log(String mensagem) {
      logs.add(mensagem);
      debugPrint('>>> [BackupRestore] $mensagem');
    }

    void progresso(String mensagem) {
      log(mensagem);
      onProgress?.call(mensagem);
    }

    if (kIsWeb) {
      log('⚠️ A criação de tabelas não está disponível na versão Web.');
      return (false, logs);
    }

    final psqlPath = await _findExecutable('psql');
    if (psqlPath == null) {
      log('❌ psql não encontrado. Use o PostgreSQL que acompanha o app para comparar as tabelas.');
      return (false, logs);
    }

    // 1. Esquema do banco LOCAL (a referência: é aqui que o app roda)
    progresso('🔎 Lendo as tabelas e colunas do banco local...');
    final Map<String, List<_ColunaEsquema>> esquemaLocal;
    Set<String> relacoesLocal = const <String>{};
    try {
      final (argsLocal, ambienteLocal) = _conexaoPsql();
      esquemaLocal = await _lerEsquema(psqlPath, argsLocal, ambienteLocal);
      relacoesLocal = await _lerRelacoes(psqlPath, argsLocal, ambienteLocal);
    } catch (e) {
      log('❌ Não foi possível ler o banco local: $e');
      return (false, logs);
    }

    // 2. Conexão com o banco da nuvem
    final host = EnvConfig.supabasePoolerHost.trim();
    final senha = EnvConfig.supabasePoolerPassword.trim();
    if (host.isEmpty || senha.isEmpty) {
      log('');
      log('⚠️ Conexão com o banco da nuvem não configurada.');
      log('   No arquivo .env, preencha (a senha é a do BANCO, em Supabase → Project Settings → Database):');
      log('   SUPABASE_POOLER_HOST=aws-1-us-west-2.pooler.supabase.com');
      log('   SUPABASE_POOLER_PASSWORD=senha_do_banco');
      return (false, logs);
    }

    final porta = EnvConfig.supabasePoolerPort;
    final usuario = EnvConfig.supabasePoolerUser;
    final banco = EnvConfig.supabaseDbNameFinal;
    final (argsNuvem, ambienteNuvem) = _conexaoPsqlNuvem(
      host: host,
      porta: porta,
      usuario: usuario,
      senha: senha,
      banco: banco,
    );

    progresso('☁️ Lendo as tabelas e colunas da nuvem ($host)...');
    final Map<String, List<_ColunaEsquema>> esquemaNuvem;
    final Set<String> relacoesNuvem;
    try {
      esquemaNuvem = await _lerEsquema(psqlPath, argsNuvem, ambienteNuvem);
      relacoesNuvem = await _lerRelacoes(psqlPath, argsNuvem, ambienteNuvem);
    } catch (e) {
      final erro = e.toString().replaceFirst('Exception: ', '');
      log('❌ Não foi possível ler o banco da nuvem: ${_mensagemErroConexaoNuvem(erro, host, porta, usuario)}');
      return (false, logs);
    }
    // A mesma conta usada pelo painel "Saúde dos Bancos": os dois sentidos, as
    // mesmas exclusões. Assim o número aqui NUNCA difere do que a tela mostra.
    final diag = _compararEsquemas(
      esquemaLocal: esquemaLocal,
      esquemaNuvem: esquemaNuvem,
      relacoesLocal: relacoesLocal,
      relacoesNuvem: relacoesNuvem,
    );

    log('📊 Banco local: ${esquemaLocal.length} tabela(s) — '
        '${diag.tabelasDeNegocioLocal} de negócio + ${diag.privadasDoApp.length} '
        'privada(s) do app (fora da conta).');
    log('📊 Nuvem: ${esquemaNuvem.length} tabela(s) — '
        '${diag.tabelasDeNegocioNuvem} de negócio.');

    // 3. O que falta na nuvem
    progresso('🧮 Comparando o banco local com a nuvem...');
    final tabelasConhecidas = <String>{
      ...SupabaseService.instance.tabelasDoApp,
      ..._tabelasGlobais,
    };

    final tabelasParaCriar = <String>[];
    final colunasParaAdicionar = <String, List<_ColunaEsquema>>{};
    final tiposDiferentes = <String>[];
    final jaExistemComoView = <String>[];

    for (final entry in esquemaLocal.entries) {
      final tabela = entry.key;
      if (tabela.startsWith('_') || _tabelasSomenteLocais.contains(tabela)) continue;

      final naNuvem = esquemaNuvem[tabela];
      if (naNuvem == null) {
        // Existe na nuvem com outro tipo de relação (ex.: view) — não dá para
        // criar tabela com o mesmo nome.
        if (relacoesNuvem.contains(tabela)) {
          jaExistemComoView.add(tabela);
          continue;
        }
        final temEmpresaId = entry.value.any((c) => c.nome == 'empresa_id');
        if (!temEmpresaId && !tabelasConhecidas.contains(tabela)) continue;
        tabelasParaCriar.add(tabela);
        continue;
      }

      final colunasNuvem = {for (final c in naNuvem) c.nome: c};
      final faltando = entry.value.where((c) => !colunasNuvem.containsKey(c.nome)).toList();
      if (faltando.isNotEmpty) {
        colunasParaAdicionar[tabela] = faltando;
      }

      // Tipos diferentes são só avisados — mexer no tipo de uma coluna com dados
      // pode dar prejuízo, então isso fica para o usuário decidir.
      for (final c in entry.value) {
        final daNuvem = colunasNuvem[c.nome];
        if (daNuvem == null) continue;
        final tipoLocal = _tipoParaNuvem(c);
        if (!_tiposCompativeis(tipoLocal, daNuvem.tipo)) {
          tiposDiferentes.add('$tabela.${c.nome}: local $tipoLocal × nuvem ${daNuvem.tipo}');
        }
      }
    }

    final totalAlteracoes = tabelasParaCriar.length +
        colunasParaAdicionar.values.fold<int>(0, (soma, lista) => soma + lista.length);

    if (totalAlteracoes == 0) {
      log('');
      log('✅ Nada a criar NA NUVEM: as ${diag.tabelasDeNegocioLocal} tabela(s) de negócio '
          'deste computador já existem lá e nenhuma coluna está faltando.');
      if (jaExistemComoView.isNotEmpty) {
        log('ℹ️ Já existem na nuvem como view (não criadas): ${jaExistemComoView.join(', ')}');
      }
      if (tiposDiferentes.isNotEmpty) {
        log('');
        log('ℹ️ ${tiposDiferentes.length} coluna(s) com tipo diferente (NÃO alteradas):');
        for (final t in tiposDiferentes.take(5)) {
          log('   • $t');
        }
      }
      logs.addAll(_linhasDiagnosticoEsquema(diag));
      return (true, logs);
    }

    // 4. Montar o SQL (tabelas novas + colunas faltantes)
    final agora = DateTime.now();
    final dataStr = '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
    final horaStr = '${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';
    final sqlPorTabela = <String, String>{
      for (final tabela in tabelasParaCriar)
        tabela: _sqlCriarTabela(tabela, esquemaLocal[tabela]!),
      for (final entry in colunasParaAdicionar.entries)
        entry.key: _sqlAdicionarColunas(entry.key, entry.value),
    };

    log('');
    log('🔨 Para criar: ${tabelasParaCriar.length} tabela(s)' +
        (colunasParaAdicionar.isNotEmpty
            ? ' e ${colunasParaAdicionar.values.fold<int>(0, (s, l) => s + l.length)} coluna(s) em '
                '${colunasParaAdicionar.length} tabela(s) que já existem'
            : ''));

    // Arquivo completo com todo o SQL (serve de rede de segurança: dá para rodar
    // no SQL Editor do Supabase se algo falhar aqui).
    final pastaBackups = Directory('C:\\ExodoBackups');
    String? caminhoArquivo;
    try {
      if (!await pastaBackups.exists()) await pastaBackups.create(recursive: true);
      final arquivo = File(p.join(pastaBackups.path, 'CRIAR_TABELAS_NUVEM_${dataStr}_$horaStr.sql'));
      final buffer = StringBuffer()
        ..writeln('-- Sistema Êxodo — tabelas/colunas que existem no banco local e faltavam na nuvem')
        ..writeln('-- Gerado em ${agora.toIso8601String()}')
        ..writeln('-- Rode este arquivo no SQL Editor do Supabase, se quiser fazer manualmente.')
        ..writeln();
      for (final sql in sqlPorTabela.values) {
        buffer.writeln(sql);
        buffer.writeln();
      }
      await arquivo.writeAsString(buffer.toString(), flush: true);
      caminhoArquivo = arquivo.path;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível salvar o SQL em disco: $e');
    }

    if (somenteComparar) {
      log('');
      log('🔎 MODO COMPARAÇÃO: nada foi criado na nuvem.');
      for (final tabela in tabelasParaCriar) {
        log('   • criar tabela $tabela (${esquemaLocal[tabela]!.length} colunas)');
      }
      for (final entry in colunasParaAdicionar.entries) {
        log('   • adicionar em ${entry.key}: ${entry.value.map((c) => c.nome).join(', ')}');
      }
      if (tiposDiferentes.isNotEmpty) {
        log('');
        log('ℹ️ ${tiposDiferentes.length} coluna(s) com tipo diferente (NÃO alteradas):');
        for (final t in tiposDiferentes.take(5)) {
          log('   • $t');
        }
      }
      logs.addAll(_linhasDiagnosticoEsquema(diag));
      return (true, logs);
    }

    // 5. Executar cada tabela separadamente (assim um erro não derruba as outras)
    var criadas = 0;
    var alteradas = 0;
    final comErro = <String>[];

    for (final entry in sqlPorTabela.entries) {
      final tabela = entry.key;
      final novaTabela = tabelasParaCriar.contains(tabela);
      progresso(novaTabela ? '🏗️ Criando tabela $tabela...' : '🔧 Ajustando tabela $tabela...');

      // Por ARQUIVO também aqui: um DEFAULT acentuado copiado do banco local
      // quebraria igual ao caso do `usuarios` no Windows.
      final result = await _executarSqlViaArquivo(
        psqlPath: psqlPath,
        baseArgs: argsNuvem,
        ambiente: ambienteNuvem,
        sql: entry.value,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('Criação da tabela $tabela excedeu 60s'),
      );

      if (result.exitCode == 0) {
        if (novaTabela) {
          criadas++;
          log('✅ $tabela: tabela criada (${esquemaLocal[tabela]!.length} colunas)');
        } else {
          alteradas++;
          log('✅ $tabela: ${colunasParaAdicionar[tabela]!.length} coluna(s) criada(s)' +
              ' — ${colunasParaAdicionar[tabela]!.map((c) => c.nome).join(', ')}');
        }
      } else {
        final erro = (result.stderr as String? ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
        comErro.add(tabela);
        log('❌ $tabela: $erro');
      }
    }

    log('');
    log('📊 Resultado: $criadas tabela(s) criada(s), $alteradas tabela(s) ajustada(s), ${comErro.length} com erro.');
    if (jaExistemComoView.isNotEmpty) {
      log('ℹ️ Já existem na nuvem como view (não criadas): ${jaExistemComoView.join(', ')}');
    }
    if (caminhoArquivo != null) {
      log('📄 SQL completo salvo em: $caminhoArquivo');
      log('   (rode esse arquivo no SQL Editor do Supabase se preferir fazer manualmente)');
    }
    if (comErro.isEmpty) {
      log('');
      log('✅ Pronto! Se alguma tela ainda reclamar de tabela inexistente, aguarde ~1 minuto');
      log('   (o Supabase recarrega o cache do PostgREST sozinho) e tente de novo.');
      logs.addAll(_linhasDiagnosticoEsquema(diag));
    } else {
      log('');
      log('⚠️ Tabelas com erro: ${comErro.join(', ')}');
      log('   O SQL de cada uma está no arquivo acima — rode-o no SQL Editor para ver o erro detalhado.');
    }
    if (tiposDiferentes.isNotEmpty) {
      log('');
      log('ℹ️ ${tiposDiferentes.length} coluna(s) com tipo diferente (NÃO alteradas):');
      for (final t in tiposDiferentes.take(5)) {
        log('   • $t');
      }
    }

    return (comErro.isEmpty, logs);
  }

  // ============================================================
  // SAÚDE DOS BANCOS — LOCAL × NUVEM (estrutura, só leitura)
  // ============================================================

  /// Onde fica o retrato da última conferência de estrutura: a tela lê este
  /// arquivo ao abrir, então o usuário vê como estavam os dois bancos da última
  /// vez — mesmo depois de fechar o app.
  static String get arquivoConferenciaEsquema =>
      'C:\\ExodoBackups\\esquema_local_x_nuvem.json';

  /// A mesma conferência em texto (para abrir, imprimir ou mandar para o
  /// suporte).
  static String get arquivoConferenciaEsquemaTxt =>
      'C:\\ExodoBackups\\esquema_local_x_nuvem.txt';

  /// Retrato da estrutura dos DOIS bancos: quantas tabelas cada um tem, o que
  /// existe só de um lado e quais colunas faltam em cada ponta.
  ///
  /// É a resposta a "como estão o banco local e o banco da nuvem?" — só lê o
  /// catálogo (`pg_class`/`pg_attribute`) das duas pontas, não grava, não cria
  /// e não apaga nada.
  Future<ConferenciaEsquema> conferirEsquemaBancos({
    void Function(String)? onProgress,
  }) async {
    final quando = DateTime.now();
    final psqlPath = await _findExecutable('psql');
    if (psqlPath == null) {
      const erro = 'psql não encontrado neste computador — instale o PostgreSQL '
          'que acompanha o app para comparar as estruturas.';
      return ConferenciaEsquema(
        quando: quando,
        erroLocal: erro,
        erroNuvem: erro,
      );
    }

    onProgress?.call('🏠 Lendo as tabelas e colunas do banco LOCAL...');
    var esquemaLocal = const <String, List<_ColunaEsquema>>{};
    var relacoesLocal = const <String>{};
    String? erroLocal;
    try {
      final (argsLocal, ambienteLocal) = _conexaoPsql();
      esquemaLocal = await _lerEsquema(psqlPath, argsLocal, ambienteLocal);
      relacoesLocal = await _lerRelacoes(psqlPath, argsLocal, ambienteLocal);
    } catch (e) {
      erroLocal = 'Banco local: ${_mensagemCurtaErro(e)}';
      debugPrint('>>> [BackupRestore] ⚠️ Conferência — local: $e');
    }

    onProgress?.call('☁️ Lendo as tabelas e colunas do banco da NUVEM...');
    var esquemaNuvem = const <String, List<_ColunaEsquema>>{};
    var relacoesNuvem = const <String>{};
    String? erroNuvem;
    try {
      final (argsNuvem, ambienteNuvem) = _conexaoNuvemDoEnv();
      esquemaNuvem = await _lerEsquema(psqlPath, argsNuvem, ambienteNuvem);
      relacoesNuvem = await _lerRelacoes(psqlPath, argsNuvem, ambienteNuvem);
    } catch (e) {
      erroNuvem = e is StateError
          ? e.message
          : 'Banco da nuvem: ${_mensagemCurtaErro(e)}';
      debugPrint('>>> [BackupRestore] ⚠️ Conferência — nuvem: $e');
    }

    onProgress?.call('🧮 Comparando as duas estruturas...');

    final diag = _compararEsquemas(
      esquemaLocal: esquemaLocal,
      esquemaNuvem: esquemaNuvem,
      relacoesLocal: relacoesLocal,
      relacoesNuvem: relacoesNuvem,
    );

    final resultado = ConferenciaEsquema(
      quando: quando,
      totalLocal: diag.tabelasDeNegocioLocal,
      totalNuvem: diag.tabelasDeNegocioNuvem,
      somenteNoLocal: diag.somenteNoLocal,
      somenteNaNuvem: diag.somenteNaNuvem,
      colunasFaltandoNoLocal: diag.colunasFaltandoNoLocal,
      colunasFaltandoNaNuvem: diag.colunasFaltandoNaNuvem,
      tiposDiferentes: diag.tiposDiferentes,
      privadasDoApp: diag.privadasDoApp,
      objetoDiferenteNaNuvem: diag.tabelaAquiEhViewNaNuvem,
      objetoDiferenteNoLocal: diag.tabelaNaNuvemEhViewAqui,
      erroLocal: erroLocal,
      erroNuvem: erroNuvem,
    );

    await salvarConferenciaEsquema(resultado);
    debugPrint('>>> [BackupRestore] 🩺 ${resultado.resumo} • ${resultado.veredito}');
    return resultado;
  }

  /// Linhas do diagnóstico dos DOIS sentidos, para o diálogo nunca deixar dúvida
  /// sobre "onde está o problema" (é a pergunta que o usuário sempre faz).
  List<String> _linhasDiagnosticoEsquema(_ComparacaoEsquemas diag) {
    final colunasAqui = diag.colunasFaltandoNoLocal.length -
        diag.sensiveisFaltando.length -
        diag.decisaoFaltando.length;
    final linhas = <String>[
      '',
      '🧭 DIAGNÓSTICO (os dois sentidos):',
      '   • Faltam NA NUVEM: ${diag.somenteNoLocal.length} tabela(s) e '
          '${diag.colunasFaltandoNaNuvem.length} coluna(s).',
      '   • Faltam NO LOCAL: ${diag.somenteNaNuvem.length} tabela(s) e $colunasAqui '
          'coluna(s)'
          '${diag.sensiveisFaltando.isNotEmpty ? ' — ${diag.sensiveisFaltando.length} sensível(is) fora da conta' : ''}'
          '${diag.decisaoFaltando.isNotEmpty ? ' — ${diag.decisaoFaltando.length} precisa(m) de decisão' : ''}.',
    ];
    if (diag.decisaoFaltando.isNotEmpty) {
      linhas.add('   • Coluna(s) que precisam de decisão (o app não cria sozinho): '
          '${diag.decisaoFaltando.join(', ')} — dá para criar no diálogo do botão '
          '"⬇️ Criar NO LOCAL", marcando a opção.');
    }
    if (diag.sensiveisFaltando.isNotEmpty || diag.decisaoFaltando.isNotEmpty) {
      linhas.add('   • Coluna(s) que só entram com a SUA autorização (o app não cria '
          'sozinho): ${[...diag.sensiveisFaltando, ...diag.decisaoFaltando].join(', ')} '
          '— dá para criar no diálogo do botão "⬇️ Criar NO LOCAL", marcando a opção.');
    }

    if (diag.tabelaAquiEhViewNaNuvem.isNotEmpty) {
      linhas.add('   • Mesmo nome com tipo diferente (NÃO é tabela faltando): '
          '${diag.tabelaAquiEhViewNaNuvem.join(', ')} é TABELA aqui e VIEW na nuvem.');
    }
    if (diag.tabelaNaNuvemEhViewAqui.isNotEmpty) {
      linhas.add('   • Mesmo nome com tipo diferente: '
          '${diag.tabelaNaNuvemEhViewAqui.join(', ')} é VIEW aqui e TABELA na nuvem.');
    }

    // O que ainda pede ação é só tabela/coluna a criar. Se não há nada disso, as
    // diferenças (se sobraram) são de TIPO — e aí NÃO existe lado atrasado: dizer
    // "use o botão da nuvem" seria mentira, porque nenhum dos dois botões cria
    // nem altera tipo de coluna.
    final pendentesLocal = diag.somenteNaNuvem.length + colunasAqui;
    final pendentesNuvem = diag.somenteNoLocal.length + diag.colunasFaltandoNaNuvem.length;
    if (pendentesLocal == 0 && pendentesNuvem == 0) {
      linhas.add(diag.tiposDiferentes.isEmpty
          ? '   ✅ Nada atrasado: os dois bancos estão equivalentes na estrutura.'
          : '   ✅ Nada a criar: as tabelas e as colunas dos dois bancos batem. '
              'Sobram ${diag.tiposDiferentes.length} coluna(s) com TIPO diferente — '
              'o app não altera tipo automaticamente, para não estragar dado existente.');
    } else if (pendentesLocal > 0) {
      linhas.add('   ⚠️ Quem está atrasado é o LOCAL — use o botão "⬇️ Criar NO LOCAL '
          'o que falta" aqui no painel da tela.');
    } else {
      linhas.add('   ⚠️ Quem está atrasado é a NUVEM — use o botão "⬆️ Criar NA NUVEM '
          'o que falta aqui" aqui no painel da tela.');
    }
    return linhas;
  }

  /// Compara os dois esquemas de uma vez e devolve o que falta de CADA lado.
  ///
  /// É o único lugar que decide essas listas — assim os dois sentidos de criação
  /// (nuvem ← local e local ← nuvem) e o painel da tela mostram SEMPRE os mesmos
  /// números, com as mesmas exclusões:
  ///
  ///  • tabelas privadas do app (`_exodo_sync_log`, `cache_dados`...) ficam fora;
  ///  • um nome que é TABELA de um lado e VIEW do outro não é "tabela faltando" —
  ///    vai para [tabelaAquiEhViewNaNuvem]/[tabelaNaNuvemEhViewAqui] (é só aviso:
  ///    não dá para criar tabela com um nome que já existe como view);
  ///  • colunas sensíveis (senha) são marcadas à parte.
  _ComparacaoEsquemas _compararEsquemas({
    required Map<String, List<_ColunaEsquema>> esquemaLocal,
    required Map<String, List<_ColunaEsquema>> esquemaNuvem,
    Set<String> relacoesLocal = const <String>{},
    Set<String> relacoesNuvem = const <String>{},
  }) {
    bool contavel(String t) =>
        !t.startsWith('_') && !_tabelasSomenteLocais.contains(t);

    final tabelasLocal = esquemaLocal.keys.where(contavel).toSet();
    final tabelasNuvem = esquemaNuvem.keys.where(contavel).toSet();
    final privadasDoApp = esquemaLocal.keys.where((t) => !contavel(t)).toList()
      ..sort();

    final somenteNoLocal = <String>[];
    final somenteNaNuvem = <String>[];
    final aquiEhViewNaNuvem = <String>[];
    final nuvemEhViewAqui = <String>[];

    for (final t in (tabelasLocal.difference(tabelasNuvem).toList()..sort())) {
      if (relacoesNuvem.contains(t)) {
        aquiEhViewNaNuvem.add(t);
      } else {
        somenteNoLocal.add(t);
      }
    }
    for (final t in (tabelasNuvem.difference(tabelasLocal).toList()..sort())) {
      if (relacoesLocal.contains(t)) {
        nuvemEhViewAqui.add(t);
      } else {
        somenteNaNuvem.add(t);
      }
    }

    final colunasFaltandoNoLocal = <ColunaDivergente>[];
    final colunasFaltandoNaNuvem = <ColunaDivergente>[];
    final tiposDiferentes = <String>[];

    for (final tabela in (tabelasLocal.intersection(tabelasNuvem).toList()..sort())) {
      final daNuvem = esquemaNuvem[tabela]!;
      final nomesNuvem = {for (final c in daNuvem) c.nome};
      final doLocal = esquemaLocal[tabela]!;
      final porNomeLocal = {for (final c in doLocal) c.nome: c};

      for (final c in daNuvem) {
        final noLocal = porNomeLocal[c.nome];
        if (noLocal == null) {
          colunasFaltandoNoLocal.add(ColunaDivergente(
            tabela: tabela,
            coluna: c.nome,
            tipoNuvem: c.tipo,
          ));
        } else if (!_tiposCompativeis(_tipoParaNuvem(noLocal), c.tipo)) {
          tiposDiferentes.add('$tabela.${c.nome}: local ${noLocal.tipo} × nuvem ${c.tipo}');
        }
      }

      for (final c in doLocal) {
        if (!nomesNuvem.contains(c.nome)) {
          colunasFaltandoNaNuvem.add(ColunaDivergente(
            tabela: tabela,
            coluna: c.nome,
            tipoLocal: c.tipo,
          ));
        }
      }
    }

    return _ComparacaoEsquemas(
      somenteNoLocal: somenteNoLocal,
      somenteNaNuvem: somenteNaNuvem,
      colunasFaltandoNoLocal: colunasFaltandoNoLocal,
      colunasFaltandoNaNuvem: colunasFaltandoNaNuvem,
      tiposDiferentes: tiposDiferentes,
      privadasDoApp: privadasDoApp,
      tabelaAquiEhViewNaNuvem: aquiEhViewNaNuvem,
      tabelaNaNuvemEhViewAqui: nuvemEhViewAqui,
      tabelasDeNegocioLocal: tabelasLocal.length,
      tabelasDeNegocioNuvem: tabelasNuvem.length,
    );
  }

  /// Grava o retrato em disco: JSON (que a tela relê) e texto (legível).
  ///
  /// Nunca lança: se não conseguir gravar, a conferência continua valendo para
  /// a sessão atual — só o histórico é que não fica salvo.
  Future<List<String>> salvarConferenciaEsquema(ConferenciaEsquema c) async {
    final gravados = <String>[];
    try {
      final pasta = Directory('C:\\ExodoBackups');
      if (!await pasta.exists()) await pasta.create(recursive: true);

      final json = File(arquivoConferenciaEsquema);
      await json.writeAsString(
        const JsonEncoder.withIndent('  ').convert(c.toJson()),
        flush: true,
      );
      gravados.add(json.path);

      final txt = File(arquivoConferenciaEsquemaTxt);
      await txt.writeAsString(c.relatorioTexto, flush: true);
      gravados.add(txt.path);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível salvar a conferência: $e');
    }
    return gravados;
  }

  /// Última conferência salva (lida ao abrir a tela, sem reconectar em nada).
  Future<ConferenciaEsquema?> lerUltimaConferenciaEsquema() async {
    try {
      final arquivo = File(arquivoConferenciaEsquema);
      if (!await arquivo.exists()) return null;
      final conteudo = jsonDecode(await arquivo.readAsString());
      if (conteudo is! Map<String, dynamic>) return null;
      return ConferenciaEsquema.fromJson(conteudo);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Conferência salva ilegível: $e');
      return null;
    }
  }

  /// Trabalho que o botão "⬇️ Criar NO LOCAL" vai fazer, já separado para o
  /// diálogo da tela: as tabelas que faltam e, tabela por tabela, as colunas que
  /// faltam naquelas que já existem.
  ///
  /// Colunas sensíveis (senha) NÃO entram — elas ficam comentadas no SQL salvo.
  ///
  /// Existe para a tela (e o diálogo) nunca decidirem isso por conta própria:
  /// quando o local tem 0 tabela faltando e 100 colunas faltando, é AQUI que
  /// fica claro que ainda há trabalho a fazer (era o caso que deixava o botão
  /// parado dizendo "nada a criar").
  static ({List<String> tabelasNovas, Map<String, List<String>> colunasPorTabela})
      trabalhosParaIgualarLocal(ConferenciaEsquema c) {
    final colunas = <String, List<String>>{};
    for (final col in c.colunasFaltandoNoLocal) {
      if (_naoCriarSozinho(col.rotulo)) continue;
      (colunas[col.tabela] ??= <String>[]).add(col.coluna);
    }
    for (final lista in colunas.values) {
      lista.sort();
    }
    return (
      tabelasNovas: [...c.somenteNaNuvem],
      colunasPorTabela: colunas,
    );
  }

  /// Nomes de TODAS as tabelas que o botão "⬇️ Criar NO LOCAL" precisa tocar:
  /// as que vão nascer e as que só vão ganhar coluna.
  static List<String> tabelasParaIgualarLocal(ConferenciaEsquema c) {
    final t = trabalhosParaIgualarLocal(c);
    return (<String>{...t.tabelasNovas, ...t.colunasPorTabela.keys}.toList()
      ..sort());
  }

  /// Cria no banco LOCAL as tabelas e colunas que existem na NUVEM e não aqui.
  ///
  /// É o caminho inverso de [criarTabelasFaltantesNaNuvem]: quando o Supabase
  /// tem uma tabela que este computador não tem (instalação mais antiga, ou
  /// tabela que só nasceu na nuvem), dá para igualar a estrutura por aqui.
  ///
  /// Nada é apagado nem alterado: só `CREATE TABLE IF NOT EXISTS` (tabela nova,
  /// vazia) e `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` (coluna nova, nula —
  /// as linhas que já existem ficam como estão).
  ///
  /// Criar estrutura no banco local NÃO envia nada para a nuvem: o gatilho de
  /// sincronização só olha linhas de tabelas que já existem, e tabela nova
  /// nasce sem gatilho.
  ///
  /// [tabelas] limita o que criar (quando nulo, cria tudo o que falta).
  /// Com [somenteComparar] só mostra o que seria feito e salva o SQL em disco.
  ///
  /// [criarColunasAutorizadas] (desligado por padrão) também cria as colunas de
  /// [colunasSensiveis] (senha) e de [colunasQueExigemDecisao]
  /// (`empresas.empresa_id`). São as que o app não cria sozinho porque mudam como
  /// ele LÊ a tabela ou como o usuário entra no sistema — só entram com a
  /// autorização explícita do usuário no diálogo da tela. Sem a flag, elas saem
  /// COMENTADAS no SQL em disco.
  Future<(bool, List<String>)> criarEstruturaFaltanteNoLocal({
    void Function(String)? onProgress,
    Set<String>? tabelas,
    bool somenteComparar = false,
    bool criarColunasAutorizadas = false,
  }) async {
    final logs = <String>[];
    void log(String mensagem) {
      logs.add(mensagem);
      debugPrint('>>> [BackupRestore] $mensagem');
    }

    void progresso(String mensagem) {
      log(mensagem);
      onProgress?.call(mensagem);
    }

    if (kIsWeb) {
      log('⚠️ A criação de tabelas não está disponível na versão Web.');
      return (false, logs);
    }

    final psqlPath = await _findExecutable('psql');
    if (psqlPath == null) {
      log('❌ psql não encontrado. Use o PostgreSQL que acompanha o app para igualar as tabelas.');
      return (false, logs);
    }

    progresso('🏠 Lendo as tabelas e colunas do banco LOCAL...');
    final (argsLocal, ambienteLocal) = _conexaoPsql();
    Map<String, List<_ColunaEsquema>> esquemaLocal;
    Set<String> relacoesLocal;
    try {
      esquemaLocal = await _lerEsquema(psqlPath, argsLocal, ambienteLocal);
      relacoesLocal = await _lerRelacoes(psqlPath, argsLocal, ambienteLocal);
    } catch (e) {
      log('❌ Não foi possível ler o banco local: ${_mensagemCurtaErro(e)}');
      return (false, logs);
    }

    progresso('☁️ Lendo as tabelas e colunas da nuvem...');
    final List<String> argsNuvem;
    final Map<String, String> ambienteNuvem;
    Map<String, List<_ColunaEsquema>> esquemaNuvem;
    var relacoesNuvem = const <String>{};
    try {
      final (args, ambiente) = _conexaoNuvemDoEnv();
      argsNuvem = args;
      ambienteNuvem = ambiente;
      esquemaNuvem = await _lerEsquema(psqlPath, argsNuvem, ambienteNuvem);
      relacoesNuvem = await _lerRelacoes(psqlPath, argsNuvem, ambienteNuvem);
    } catch (e) {
      log('❌ Não foi possível ler o banco da nuvem: ${_mensagemCurtaErro(e)}');
      return (false, logs);
    }

    // Mesma conta do painel "Saúde dos Bancos" (os dois sentidos, as mesmas
    // exclusões), para os números desta tela nunca diferirem do painel.
    final diag = _compararEsquemas(
      esquemaLocal: esquemaLocal,
      esquemaNuvem: esquemaNuvem,
      relacoesLocal: relacoesLocal,
      relacoesNuvem: relacoesNuvem,
    );
    log('📊 Banco local: ${esquemaLocal.length} tabela(s) — '
        '${diag.tabelasDeNegocioLocal} de negócio + ${diag.privadasDoApp.length} '
        'privada(s) do app (fora da conta).');
    log('📊 Nuvem: ${esquemaNuvem.length} tabela(s) — '
        '${diag.tabelasDeNegocioNuvem} de negócio.');

    // 1. O que a nuvem tem e o banco local não tem.
    progresso('🧮 Comparando o banco da nuvem com o local...');
    final tabelasParaCriar = <String>[];
    final colunasParaAdicionar = <String, List<_ColunaEsquema>>{};
    final jaExistemComoView = <String>[];

    for (final entry in esquemaNuvem.entries) {
      final tabela = entry.key;
      if (tabela.startsWith('_')) continue;
      if (tabelas != null && !tabelas.contains(tabela)) continue;

      final local = esquemaLocal[tabela];
      if (local != null) {
        final colunasLocal = {for (final c in local) c.nome};
        final faltando =
            entry.value.where((c) => !colunasLocal.contains(c.nome)).toList();
        if (faltando.isNotEmpty) colunasParaAdicionar[tabela] = faltando;
        continue;
      }

      // Existe aqui como view/view materializada: criar tabela com o mesmo nome
      // falharia — fica como aviso.
      if (relacoesLocal.contains(tabela)) {
        jaExistemComoView.add(tabela);
        continue;
      }

      tabelasParaCriar.add(tabela);
    }

    // Colunas sensíveis (senha): aparecem no relatório, mas o app não as cria
    // sozinho — o SQL salvo em disco as leva COMENTADAS.
    final sensiveisPuladas = <String>[
      for (final e in colunasParaAdicionar.entries)
        for (final c in e.value)
          if (colunasSensiveis.contains('${e.key}.${c.nome}')) '${e.key}.${c.nome}',
    ];
    // Colunas que exigem a autorização do usuário (senha e as que mudam a
    // LEITURA da tabela): ficam comentadas no SQL e de fora da contagem.
    final decisaoPuladas = <String>[
      if (!criarColunasAutorizadas)
        for (final e in colunasParaAdicionar.entries)
          for (final c in e.value)
            if (colunasSensiveis.contains('${e.key}.${c.nome}') ||
                colunasQueExigemDecisao.contains('${e.key}.${c.nome}')) '${e.key}.${c.nome}',
    ];

    final totalColunas = colunasParaAdicionar.values
        .fold<int>(0, (s, l) => s + l.length);
    final totalAlteracoes = tabelasParaCriar.length + totalColunas;

    if (totalAlteracoes == 0) {
      log('');
      log('✅ Nada a fazer: o banco local já tem as ${diag.tabelasDeNegocioNuvem} tabela(s) '
          'de negócio da nuvem e nenhuma coluna faltando.');
      if (jaExistemComoView.isNotEmpty) {
        log('ℹ️ Já existem aqui como view (não criadas): ${jaExistemComoView.join(', ')}');
      }
      logs.addAll(_linhasDiagnosticoEsquema(diag));
      return (true, logs);
    }

    // 2. PostgreSQL 13+ tem gen_random_uuid() embutido — antes disso o default
    //    do id (que a nuvem usa) não pode ser trazido.
    final uuidNativo = await _uuidNativoNoLocal(psqlPath, argsLocal, ambienteLocal);

    final sqlPorTabela = <String, String>{
      for (final t in tabelasParaCriar)
        t: _sqlCriarTabelaNoLocal(t, esquemaNuvem[t]!, uuidNativo: uuidNativo),
      for (final e in colunasParaAdicionar.entries)
        e.key: _sqlAdicionarColunasNoLocal(e.key, e.value,
            uuidNativo: uuidNativo, criarColunasAutorizadas: criarColunasAutorizadas),
    };

    log('');
    log('🔨 Para criar no LOCAL: ${tabelasParaCriar.length} tabela(s)' +
        (colunasParaAdicionar.isNotEmpty
            ? ' e ${totalColunas - sensiveisPuladas.length - decisaoPuladas.length} '
                'coluna(s) em ${colunasParaAdicionar.length} tabela(s) que já existem'
            : ''));
    if (sensiveisPuladas.isNotEmpty) {
      log('🔒 Colunas sensíveis que o app NÃO cria sozinho (ficam comentadas no SQL): '
          '${sensiveisPuladas.join(', ')}');
    }
    if (decisaoPuladas.isNotEmpty) {
      log('⚖️ Coluna(s) que só entram com a sua autorização (ficam comentadas no SQL '
          'e vêm desmarcadas no diálogo): ${decisaoPuladas.join(', ')}');
    }

    // 3. O SQL completo em disco (rede de segurança: dá para rodar no pgAdmin).
    final agora = DateTime.now();
    final dataStr =
        '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
    final horaStr =
        '${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';
    String? caminhoArquivo;
    try {
      final pasta = Directory('C:\\ExodoBackups');
      if (!await pasta.exists()) await pasta.create(recursive: true);
      final arquivo =
          File(p.join(pasta.path, 'CRIAR_TABELAS_LOCAL_${dataStr}_$horaStr.sql'));
      final buffer = StringBuffer()
        ..writeln('-- Sistema Êxodo — tabelas/colunas que existem na NUVEM e faltavam no banco LOCAL')
        ..writeln('-- Gerado em ${agora.toIso8601String()}')
        ..writeln('-- Rode este arquivo no pgAdmin/psql do computador, se preferir fazer manualmente.')
        ..writeln('-- É só estrutura: cria tabela nova (vazia) e coluna nova. Não apaga nada.')
        // O arquivo é gravado em UTF-8: sem esta linha, um psql com cliente em
        // WIN1252 (o padrão desta máquina) leria os acentos como bytes inválidos.
        ..writeln("SET client_encoding = 'UTF8';")
        ..writeln();
      for (final sql in sqlPorTabela.values) {
        buffer.writeln(sql);
        buffer.writeln();
      }
      await arquivo.writeAsString(buffer.toString(), flush: true);
      caminhoArquivo = arquivo.path;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível salvar o SQL em disco: $e');
    }

    if (somenteComparar) {
      log('');
      log('🔎 MODO COMPARAÇÃO: nada foi criado no banco local.');
      for (final t in tabelasParaCriar) {
        log('   • criar tabela $t (${esquemaNuvem[t]!.length} colunas)');
      }
      for (final e in colunasParaAdicionar.entries) {
        log('   • adicionar em ${e.key}: ${e.value.map((c) => c.nome).join(', ')}');
      }
      if (caminhoArquivo != null) {
        log('📄 SQL salvo em: $caminhoArquivo');
      }
      logs.addAll(_linhasDiagnosticoEsquema(diag));
      return (true, logs);
    }

    // 4. Executa tabela por tabela (um erro não derruba as outras).
    var criadas = 0;
    var alteradas = 0;
    final comErro = <String>[];

    for (final entry in sqlPorTabela.entries) {
      final tabela = entry.key;
      final novaTabela = tabelasParaCriar.contains(tabela);
      progresso(novaTabela
          ? '🏗️ Criando a tabela $tabela no banco local...'
          : '🔧 Ajustando $tabela no banco local...');

      // Por ARQUIVO (não por -c): o SQL leva comentário com acento e no Windows a
      // linha de comando converteria para ANSI, quebrando o comando inteiro.
      final result = await _executarSqlViaArquivo(
        psqlPath: psqlPath,
        baseArgs: argsLocal,
        ambiente: ambienteLocal,
        sql: entry.value,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('A tabela $tabela excedeu 60s'),
      );

      if (result.exitCode == 0) {
        if (novaTabela) {
          criadas++;
          log('✅ $tabela: tabela criada no banco local '
              '(${esquemaNuvem[tabela]!.length} colunas, vazia)');
        } else {
          alteradas++;
          // Só conta o que REALMENTE entrou: as colunas sensíveis e as que
          // precisam de decisão saem comentadas e não são criadas. Antes o log
          // dizia "2 coluna(s)" para `usuarios` mesmo criando só uma.
          final todas = colunasParaAdicionar[tabela]!;
          final entraram = todas
              .where((c) =>
                  !naoCriarSozinho('$tabela.${c.nome}') || criarColunasAutorizadas)
              .toList();
          final ficaram = todas
              .where((c) => !entraram.any((e) => e.nome == c.nome))
              .map((c) => c.nome)
              .toList();
          log('✅ $tabela: ${entraram.length} coluna(s) criada(s) — '
              '${entraram.map((c) => c.nome).join(', ')}'
              '${ficaram.isNotEmpty ? ' • NÃO criada(s): ${ficaram.join(', ')}' : ''}');
        }
      } else {
        final erro =
            (result.stderr as String? ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
        comErro.add(tabela);
        log('❌ $tabela: $erro');
      }
    }

    // 5. Confere o resultado (quantas tabelas o local tem agora).
    try {
      final depois = await _lerEsquema(psqlPath, argsLocal, ambienteLocal);
      log('');
      log('📊 Banco local agora: ${depois.length} tabela(s) '
          '(antes: ${esquemaLocal.length}).');
    } catch (_) {}

    log('');
    log('📊 Resultado: $criadas tabela(s) criada(s), $alteradas ajustada(s), '
        '${comErro.length} com erro.');
    if (jaExistemComoView.isNotEmpty) {
      log('ℹ️ Já existem aqui como view (não criadas): ${jaExistemComoView.join(', ')}');
    }
    if (caminhoArquivo != null) {
      log('📄 SQL completo salvo em: $caminhoArquivo');
    }
    if (comErro.isNotEmpty) {
      log('⚠️ Tabelas com erro: ${comErro.join(', ')}');
      log('   O SQL de cada uma está no arquivo acima — rode-o no pgAdmin para ver o erro detalhado.');
    } else {
      log('');
      log('ℹ️ As tabelas novas nascem VAZIAS e ficam só neste computador. Nada foi enviado para a nuvem.');
      logs.addAll(_linhasDiagnosticoEsquema(diag));
    }

    return (comErro.isEmpty, logs);
  }

  // ============================================================
  // MESMO NOME, OBJETO DIFERENTE (TABELA aqui × VIEW na nuvem)
  // ============================================================

  /// Iguala os nomes que neste computador são TABELA e na nuvem são VIEW.
  ///
  /// É o caso da `vw_historico_recente`: aqui ficou uma TABELA antiga do
  /// `scripts/init_db.sql`, VAZIA e sem uso (o app nunca a lê nem a escreve), e
  /// na nuvem ela é uma VIEW de verdade —
  /// `SELECT * FROM produto_historico WHERE data_alteracao >= now() - 30 days`.
  /// Como TABELA e VIEW contam de formas diferentes na conferência, esse nome
  /// sozinho fazia o banco local aparecer com 1 tabela a mais (49 × 48).
  ///
  /// O que faz, para cada nome:
  ///   1. lê a definição da VIEW na nuvem (`pg_get_viewdef`);
  ///   2. confere que aqui é TABELA e que está **VAZIA**;
  ///   3. escrita uma cópia de segurança em `C:\ExodoBackups\` com o DDL da
  ///      tabela local e o comando para voltar atrás;
  ///   4. numa única transação: apaga a tabela local e cria a VIEW com a MESMA
  ///      definição da nuvem. Se algo falhar, a transação reverte e a tabela
  ///      continua exatamente como estava.
  ///
  /// RECUSA (sem tocar no banco): tabela com linha dentro, nome que não é
  /// TABELA aqui, nome que não é VIEW na nuvem, ou algo que dependa da tabela
  /// local (outra view/chave estrangeira).
  Future<(bool, List<String>)> igualarTabelasQueSaoViewNaNuvem({
    required Set<String> objetos,
    bool somenteComparar = false,
    void Function(String)? onProgress,
  }) async {
    final logs = <String>[];
    void log(String m) {
      logs.add(m);
      debugPrint('>>> [BackupRestore] $m');
    }

    void progresso(String m) {
      log(m);
      onProgress?.call(m);
    }

    if (kIsWeb) {
      log('⚠️ Isto não está disponível na versão Web.');
      return (false, logs);
    }
    if (objetos.isEmpty) {
      log('✅ Nada a igualar: nenhum nome é TABELA aqui e VIEW na nuvem.');
      return (true, logs);
    }

    final psqlPath = await _findExecutable('psql');
    if (psqlPath == null) {
      log('❌ psql não encontrado.');
      return (false, logs);
    }
    final (argsLocal, ambienteLocal) = _conexaoPsql();
    final (argsNuvem, ambienteNuvem) = _conexaoNuvemDoEnv();

    final sqlAplicado = <String>[];
    final recusados = <String, String>{};
    var iguais = 0;
    var comErro = 0;

    for (final objeto in objetos.toList()..sort()) {
      progresso('🔎 Conferindo $objeto...');

      // 1. Na nuvem precisa ser VIEW, e precisamos da definição dela.
      final naNuvem = await _lerObjeto(
        psqlPath: psqlPath,
        baseArgs: argsNuvem,
        ambiente: ambienteNuvem,
        nome: objeto,
        comDefinicao: true,
      );
      if (naNuvem == null) {
        recusados[objeto] = 'não encontrei esse nome na nuvem';
        continue;
      }
      if (naNuvem.relkind != 'v') {
        recusados[objeto] = 'na nuvem não é VIEW (é ${naNuvem.tipoLegivel})';
        continue;
      }
      // `pg_get_viewdef` já devolve a definição terminando em ';' — sem tirar,
      // o CREATE VIEW sairia com ';;' e o PostgreSQL recusaria (erro de sintaxe).
      final definicao = _semPontoEVirgulaFinal(naNuvem.definicao ?? '');
      if (definicao.isEmpty) {
        recusados[objeto] = 'não consegui ler a definição da view na nuvem';
        continue;
      }

      // 2. Aqui precisa ser TABELA e estar vazia.
      final aqui = await _lerObjeto(
        psqlPath: psqlPath,
        baseArgs: argsLocal,
        ambiente: ambienteLocal,
        nome: objeto,
        contarLinhas: true,
      );
      if (aqui == null) {
        recusados[objeto] = 'não existe neste computador';
        continue;
      }
      if (aqui.relkind != 'r') {
        recusados[objeto] = 'aqui já não é TABELA (é ${aqui.tipoLegivel}) — nada a fazer';
        continue;
      }
      if ((aqui.linhas ?? 0) > 0) {
        recusados[objeto] = 'tem ${aqui.linhas} linha(s) DENTRO — não apago tabela com '
            'dado; esvazie ou copie o conteúdo antes';
        continue;
      }

      // 3. Ninguém pode depender dela (outra view, chave estrangeira...).
      final dependentes = await _contarDependentesNoLocal(
        psqlPath: psqlPath,
        baseArgs: argsLocal,
        ambiente: ambienteLocal,
        nome: objeto,
      );
      if (dependentes > 0) {
        recusados[objeto] = 'tem $dependentes objeto(s) dependendo dela — trocar agora '
            'quebraria quem usa';
        continue;
      }

      // 4. Cópia de segurança com o DDL atual e como voltar atrás.
      String? arquivo;
      try {
        final pasta = Directory('C:\\ExodoBackups');
        if (!await pasta.exists()) await pasta.create(recursive: true);
        final agora = DateTime.now();
        final carimbo = '${agora.year}-${agora.month.toString().padLeft(2, '0')}-'
            '${agora.day.toString().padLeft(2, '0')}_'
            '${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';
        final f = File(p.join(pasta.path,
            'IGUALAR_VIEW_${objeto.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}_$carimbo.sql'));
        await f.writeAsString(
          '-- Sistema Êxodo — igualar "$objeto": TABELA (local) → VIEW (nuvem)\n'
          '-- Gerado em ${agora.toIso8601String()}\n'
          '-- Esta tabela local tem ${aqui.linhas ?? 0} linha(s) e nenhum dependente.\n'
          '--\n'
          '-- PARA VOLTAR ATRÁS (copie as DUAS linhas abaixo e rode no pgAdmin/psql;\n'
          '-- se havia dados, eles estão no backup do banco desta empresa):\n'
          '--   DROP VIEW IF EXISTS public.${_ident(objeto)};\n'
          '--   ${_sqlRecriarTabelaLocal(objeto, aqui.colunas)}\n'
          '--\n'
          '-- O que foi aplicado:\n'
          '-- DROP TABLE IF EXISTS public.${_ident(objeto)};\n'
          '-- CREATE VIEW public.${_ident(objeto)} AS\n${_identar(definicao)}\n',
          flush: true,
        );
        arquivo = f.path;
      } catch (e) {
        debugPrint('>>> [BackupRestore] ⚠️ Não foi possível salvar a cópia: $e');
      }

      final sql = 'BEGIN;\n'
          'DROP TABLE IF EXISTS public.${_ident(objeto)};\n'
          'CREATE VIEW public.${_ident(objeto)} AS\n$definicao\n;\n'
          'COMMIT;\n';

      if (somenteComparar) {
        log('🔎 $objeto: seria apagada a tabela vazia e criada a VIEW da nuvem.'
            '${arquivo != null ? ' Cópia do estado atual: $arquivo' : ''}');
        sqlAplicado.add(sql);
        continue;
      }

      progresso('🧩 $objeto: trocando a tabela vazia pela VIEW da nuvem...');
      final res = await _executarSqlViaArquivo(
        psqlPath: psqlPath,
        baseArgs: argsLocal,
        ambiente: ambienteLocal,
        sql: sql,
      );
      if (res.exitCode != 0) {
        comErro++;
        log('❌ $objeto falhou: ${_mensagemCurtaErro(res.stderr as String? ?? '')}');
        log('   A transação foi revertida — a tabela continua como estava.');
        continue;
      }

      iguais++;
      log('✅ $objeto: agora é VIEW, igual à nuvem.'
          '${arquivo != null ? ' (voltar atrás: $arquivo)' : ''}');
      sqlAplicado.add(sql);
    }

    log('');
    if (recusados.isNotEmpty) {
      log('⛔ Recusado(s) (NÃO alterados): ');
      recusados.forEach((nome, motivo) => log('   • $nome: $motivo'));
    }
    if (somenteComparar) {
      log('🔎 MODO COMPARAÇÃO: nada foi alterado no banco local.');
      logs.addAll(await _linhasDiagnosticoEsquemaLocal());
      return (recusados.isEmpty, logs);
    }

    log(iguais > 0
        ? '📊 Resultado: $iguais nome(s) agora são VIEW nos dois bancos'
            '${comErro > 0 ? ' • $comErro com erro' : ''}.'
        : '📊 Nada foi alterado.');
    log('ℹ️ A nuvem NÃO foi tocada: só a estrutura deste computador foi ajustada.');
    logs.addAll(await _linhasDiagnosticoEsquemaLocal());
    // Recusa também é resultado negativo: a tela precisa dizer que nem tudo foi
    // igualado (e o diálogo mostra o motivo de cada recusa).
    return (comErro == 0 && recusados.isEmpty, logs);
  }

  // ============================================================
  // MESMO NOME, TIPO DIFERENTE (text aqui × numeric na nuvem)
  // ============================================================

  /// Iguala o TIPO das colunas que existem nos DOIS bancos com tipos diferentes.
  ///
  /// É o caso das 9 colunas de `produtos` (`altura_cm`, `largura_cm`,
  /// `profundidade_cm`, `peso_gramas` e as 5 alíquotas): aqui são `text` e na
  /// nuvem são `numeric`/`integer`. O app nunca faz isso sozinho porque mudar
  /// tipo de coluna COM DADO DENTRO pode dar prejuízo — então este caminho:
  ///
  ///   1. lê o tipo EXATO da nuvem (`format_type`, com precisão e escala);
  ///   2. confere TODOS os valores que existem aqui: se algum não converter, a
  ///      coluna é RECUSADA e NADA é alterado (nenhum valor vira NULL calado);
  ///   3. grava em `C:\ExodoBackups\IGUALAR_TIPO_*.sql` o comando de volta ao
  ///      tipo antigo E os valores que existiam (para reverter de verdade);
  ///   4. aplica `ALTER TABLE ... ALTER COLUMN ... TYPE ... USING ...` dentro de
  ///      uma transação, com o gatilho de sincronização DESLIGADO (é reparo
  ///      local: não pode virar fila de envio para a nuvem).
  ///
  /// Tipos aceitos como destino: os textuais (sempre seguro) e os numéricos/booleano
  /// (com os valores todos validados antes). Tipo exótico é recusado.
  Future<(bool, List<String>)> igualarTiposDeColunaNoLocal({
    required Set<String> colunas,
    bool somenteComparar = false,
    void Function(String)? onProgress,
  }) async {
    final logs = <String>[];
    void log(String m) {
      logs.add(m);
      debugPrint('>>> [BackupRestore] $m');
    }

    void progresso(String m) {
      log(m);
      onProgress?.call(m);
    }

    if (kIsWeb) {
      log('⚠️ Isto não está disponível na versão Web.');
      return (false, logs);
    }
    if (colunas.isEmpty) {
      log('✅ Nada a igualar: nenhuma coluna com tipo diferente.');
      return (true, logs);
    }

    final psqlPath = await _findExecutable('psql');
    if (psqlPath == null) {
      log('❌ psql não encontrado.');
      return (false, logs);
    }
    final (argsLocal, ambienteLocal) = _conexaoPsql();
    final (argsNuvem, ambienteNuvem) = _conexaoNuvemDoEnv();

    progresso('🏠 Lendo as colunas do banco local...');
    final esquemaLocal = await _lerEsquema(psqlPath, argsLocal, ambienteLocal);
    progresso('☁️ Lendo as colunas da nuvem...');
    final esquemaNuvem = await _lerEsquema(psqlPath, argsNuvem, ambienteNuvem);

    var iguais = 0;
    var comErro = 0;
    final recusados = <String, String>{};
    final reversao = <String>[];

    for (final rotuloBruto in colunas.toList()..sort()) {
      // Aceita as duas formas: `produtos.altura_cm` e o texto legível da
      // conferência (`produtos.altura_cm: local text × nuvem numeric`).
      final rotulo = rotuloSimplesDeTipoDiferente(rotuloBruto);
      final partes = rotulo.split('.');
      if (partes.length != 2) {
        recusados[rotuloBruto] = 'nome inesperado (esperado tabela.coluna)';
        continue;
      }
      final tabela = partes[0];
      final coluna = partes[1];

      final naNuvem =
          esquemaNuvem[tabela]?.where((c) => c.nome == coluna).firstOrNull;
      final aqui = esquemaLocal[tabela]?.where((c) => c.nome == coluna).firstOrNull;
      if (naNuvem == null || aqui == null) {
        recusados[rotuloBruto] = 'não existe nos dois bancos';
        continue;
      }
      if (naNuvem.tipo == aqui.tipo) {
        log('✅ $rotulo: já está igual ($aqui.tipo).');
        continue;
      }

      final destino = naNuvem.tipo.toLowerCase().trim();
      final operacao = _conversaoDeTipo(
        origem: aqui.tipo,
        destino: destino,
        col: _ident(coluna),
      );
      if (operacao == null) {
        recusados[rotuloBruto] = 'conversão de ${aqui.tipo} para $destino não está '
            'na lista segura (o app não arrisca)';
        continue;
      }

      progresso('🔎 $rotulo: conferindo os valores antes de converter...');
      final (ok, quantos, naoConvertem, exemplo) = await _conferirValoresDaColuna(
        psqlPath: psqlPath,
        baseArgs: argsLocal,
        ambiente: ambienteLocal,
        tabela: tabela,
        coluna: coluna,
        operacao: operacao,
      );
      if (!ok) {
        recusados[rotuloBruto] =
            'tem valor que NÃO converte para $destino ($naoConvertem de $quantos'
            '${exemplo == null ? '' : '; ex.: "$exemplo"'})';
        continue;
      }

      // Valores que existem hoje, para conseguir voltar atrás de verdade.
      final valores = await _lerValoresDaColuna(
        psqlPath: psqlPath,
        baseArgs: argsLocal,
        ambiente: ambienteLocal,
        tabela: tabela,
        coluna: coluna,
      );
      reversao.add(
        '-- $rotulo: de ${aqui.tipo} para $destino ($quantos valor(es) preenchido(s))\n'
        'ALTER TABLE public.${_ident(tabela)} ALTER COLUMN ${_ident(coluna)} '
        'TYPE text USING ${_ident(coluna)}::text;',
      );
      reversao.addAll(valores);

      final sql = 'BEGIN;\n'
          "SET LOCAL exodo.sync_mode = 'on';\n"
          'ALTER TABLE public.${_ident(tabela)} ALTER COLUMN ${_ident(coluna)} '
          'TYPE $destino USING ${operacao};\n'
          'COMMIT;\n';
      if (somenteComparar) {
        log('🔎 $rotulo: seria convertida de ${aqui.tipo} para $destino '
            '($quantos valor(es) preenchido(s), todos convertem).');
        continue;
      }

      progresso('🔧 $rotulo: convertendo de ${aqui.tipo} para $destino...');
      final res = await _executarSqlViaArquivo(
        psqlPath: psqlPath,
        baseArgs: argsLocal,
        ambiente: ambienteLocal,
        sql: sql,
      );
      if (res.exitCode != 0) {
        comErro++;
        log('❌ $rotulo falhou: ${_mensagemCurtaErro(res.stderr as String? ?? '')}');
        log('   A transação foi revertida — a coluna continua como estava.');
        continue;
      }
      iguais++;
      log('✅ $rotulo: agora é $destino, igual à nuvem.');
    }

    // Cópia para voltar atrás (só quando algo seria mesmo alterado).
    String? caminho;
    if (reversao.isNotEmpty) {
      try {
        final pasta = Directory('C:\\ExodoBackups');
        if (!await pasta.exists()) await pasta.create(recursive: true);
        final agora = DateTime.now();
        final carimbo = '${agora.year}-${agora.month.toString().padLeft(2, '0')}-'
            '${agora.day.toString().padLeft(2, '0')}_'
            '${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';
        final f = File(p.join(pasta.path, 'IGUALAR_TIPO_$carimbo.sql'));
        await f.writeAsString(
          '-- Sistema Êxodo — voltar os TIPOS das colunas ao que eram antes\n'
          '-- Gerado em ${agora.toIso8601String()}\n'
          '-- Rode no pgAdmin/psql SÓ se precisar desfazer a igualação de tipos.\n'
          "SET client_encoding = 'UTF8';\n\n"
          'BEGIN;\n'
          "SET LOCAL exodo.sync_mode = 'on';\n"
          '${reversao.join('\n')}\n'
          'COMMIT;\n',
          flush: true,
        );
        caminho = f.path;
      } catch (e) {
        debugPrint('>>> [BackupRestore] ⚠️ Não foi possível salvar a cópia: $e');
      }
    }

    log('');
    if (recusados.isNotEmpty) {
      log('⛔ Recusado(s) (NÃO alterados): ');
      recusados.forEach((nome, motivo) => log('   • $nome: $motivo'));
    }
    if (somenteComparar) {
      log('🔎 MODO COMPARAÇÃO: nada foi alterado no banco local.');
      return (recusados.isEmpty, logs);
    }
    log(iguais > 0
        ? '📊 Resultado: $iguais coluna(s) agora com o tipo da nuvem'
            '${comErro > 0 ? ' • $comErro com erro' : ''}.'
        : '📊 Nada foi alterado.');
    if (caminho != null) {
      log('📄 Para voltar atrás: $caminho');
    }
    log('ℹ️ A nuvem NÃO foi tocada: só a estrutura deste computador foi ajustada.');
    logs.addAll(await _linhasDiagnosticoEsquemaLocal());
    return (comErro == 0 && recusados.isEmpty, logs);
  }

  /// `produtos.altura_cm: local text × nuvem numeric` → `produtos.altura_cm`.
  ///
  /// A conferência descreve o tipo diferente como texto legível (é o que a tela
  /// mostra); para igualar precisamos só do nome `tabela.coluna` — as duas formas
  /// são aceitas.
  static String rotuloSimplesDeTipoDiferente(String texto) =>
      texto.split(':').first.trim();

  /// Como converter [origem] para [destino] sem perder dado, ou `null` quando a
  /// conversão não está na lista segura.
  ///
  /// Devolve a EXPRESSÃO `USING` do `ALTER TABLE`, já com a coluna [col] no lugar
  /// certo. Textual vira número/booleano (com validação prévia dos valores);
  /// qualquer tipo vira textual (converter para texto nunca perde valor).
  String? _conversaoDeTipo({
    required String origem,
    required String destino,
    required String col,
  }) {
    final o = origem.toLowerCase().trim();
    final d = destino.toLowerCase().trim();
    if (_tiposTextuais.contains(o)) {
      if (d.startsWith('numeric') ||
          d.startsWith('decimal') ||
          d.startsWith('real') ||
          d.startsWith('double')) {
        // Vazio vira NULL (não zero) e a vírgula decimal pt-BR é normalizada.
        return "NULLIF(translate(btrim($col::text), ',', '.'), '')::numeric";
      }
      if (d == 'smallint' || d == 'integer' || d == 'bigint' ||
          d == 'int' || d == 'int2' || d == 'int4' || d == 'int8') {
        return "NULLIF(btrim($col::text), '')::bigint";
      }
      if (d == 'boolean' || d == 'bool') {
        return "CASE WHEN btrim(lower($col::text)) IN ('true','t','1','sim','s','y') "
            "THEN true WHEN btrim(lower($col::text)) = '' THEN NULL ELSE false END";
      }
      return null;
    }
    if (_tiposTextuais.contains(d)) return '$col::text';
    return null;
  }

  /// Tipos tratados como TEXTO (a origem que dá para converter com validação).
  static const Set<String> _tiposTextuais = {
    'text', 'character varying', 'character', 'varchar', 'char', 'bpchar',
    'citext', 'name',
  };

  /// Confere os valores da coluna contra o destino: devolve
  /// `(podeConverter, quantosPreenchidos, quantosNaoConvertem, exemploRuim)`.
  Future<(bool, int, int, String?)> _conferirValoresDaColuna({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    required String tabela,
    required String coluna,
    required String operacao,
  }) async {
    final alvo = _ident(coluna);
    final expr = operacao.replaceAll(
      _ident(coluna),
      'public.${_ident(tabela)}.$alvo',
    );
    final consulta = '''
SELECT count(*) FILTER (WHERE btrim($alvo::text) <> '')
     || chr(31) || count(*) FILTER (WHERE btrim($alvo::text) <> '' AND NOT ($expr IS NOT NULL))
     || chr(31) || COALESCE((SELECT $alvo::text FROM public.${_ident(tabela)}
WHERE btrim($alvo::text) <> '' AND NOT ($expr IS NOT NULL) LIMIT 1), '')
FROM public.${_ident(tabela)};
''';
    try {
      final res = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: consulta,
      );
      if (res.exitCode != 0) {
        return (false, 0, 0, _mensagemCurtaErro(res.stderr as String? ?? ''));
      }
      final partes = (res.stdout as String? ?? '').trim().split('\u001f');
      final quantos = int.tryParse(partes.isNotEmpty ? partes[0].trim() : '') ?? 0;
      final ruins = int.tryParse(partes.length > 1 ? partes[1].trim() : '') ?? 0;
      final exemplo = partes.length > 2 ? partes[2].trim() : '';
      return (ruins == 0, quantos, ruins, exemplo.isEmpty ? null : exemplo);
    } catch (e) {
      return (false, 0, 0, _mensagemCurtaErro(e));
    }
  }

  /// Linhas para desfazer a conversão: devolve a coluna de volta ao valor de
  /// texto que ela tinha (só as que têm valor).
  Future<List<String>> _lerValoresDaColuna({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    required String tabela,
    required String coluna,
  }) async {
    final alvo = _ident(coluna);
    try {
      final res = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: 'SELECT id::text || chr(31) || $alvo::text FROM public.${_ident(tabela)} '
            "WHERE $alvo IS NOT NULL AND btrim($alvo::text) <> '' LIMIT 2000;",
      );
      if (res.exitCode != 0) return const [];
      return (res.stdout as String? ?? '')
          .split(RegExp(r'\r?\n'))
          .where((l) => l.contains('\u001f'))
          .map((l) {
            final p = l.split('\u001f');
            final id = p[0].trim().replaceAll("'", "''");
            final valor = p[1].trim().replaceAll("'", "''");
            return 'UPDATE public.${_ident(tabela)} SET $alvo = \'$valor\' '
                'WHERE id = \'$id\';';
          })
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// DDL aproximado para recriar a tabela local como ela estava (usado só na
  /// cópia de segurança em disco — não é executado pelo app).
  String _sqlRecriarTabelaLocal(String nome, List<_ColunaEsquema> colunas) {
    final corpo = colunas
        .map((c) => '${_ident(c.nome)} ${c.tipo}'
            '${c.obrigatoria ? ' NOT NULL' : ''}'
            '${c.padrao.isEmpty ? '' : ' DEFAULT ${c.padrao}'}')
        .join(', ');
    final pk = colunas.where((c) => c.chavePrimaria).map((c) => _ident(c.nome)).toList();
    return 'CREATE TABLE IF NOT EXISTS public.${_ident(nome)} ($corpo'
        '${pk.isEmpty ? '' : ', PRIMARY KEY (${pk.join(', ')})'});';
  }

  /// Tira espaços e o ponto e vírgula final da definição da view (o
  /// `pg_get_viewdef` inclui o `;`, e nós o colocamos de novo no CREATE VIEW).
  String _semPontoEVirgulaFinal(String texto) {
    var t = texto.trim();
    while (t.endsWith(';')) {
      t = t.substring(0, t.length - 1).trimRight();
    }
    return t;
  }

  /// Indenta um SELECT de várias linhas para leitura no arquivo de cópia.
  String _identar(String texto) => texto
      .split(RegExp(r'\r?\n'))
      .map((l) => '--   ${l.trimRight()}')
      .join('\n');

  /// Quantos objetos dependem desta tabela no banco local (views, FKs...).
  Future<int> _contarDependentesNoLocal({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    required String nome,
  }) async {
    final alvo = _ident(nome);
    final sql = 'SELECT ('
        "SELECT count(*) FROM information_schema.view_table_usage "
        "WHERE table_schema = 'public' AND table_name = '$nome'"
        ') + ('
        "SELECT count(*) FROM pg_constraint "
        "WHERE confrelid = 'public.$alvo'::regclass"
        ')::text || chr(31) || ('
        "SELECT count(*) FROM pg_views WHERE schemaname = 'public' "
        "AND definition ILIKE '%$nome%'"
        ')::text;';
    try {
      final res = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: sql,
      );
      if (res.exitCode != 0) return 0;
      final partes = (res.stdout as String? ?? '').trim().split('\u001f');
      final fks = int.tryParse(partes.isNotEmpty ? partes[0].trim() : '') ?? 0;
      // A contagem por texto pode achar o próprio nome em si mesma: só conta se
      // houver ALGUMA view citando o nome e ela não for o próprio objeto.
      final viewsTexto = int.tryParse(partes.length > 1 ? partes[1].trim() : '') ?? 0;
      return fks + (viewsTexto > 1 ? viewsTexto - 1 : 0);
    } catch (_) {
      return 0;
    }
  }

  /// Lê um objeto (`relkind`, tipo legível, colunas e — quando pedido — a
  /// definição da view ou a contagem de linhas). `null` quando não existe.
  Future<_ObjetoBanco?> _lerObjeto({
    required String psqlPath,
    required List<String> baseArgs,
    required Map<String, String> ambiente,
    required String nome,
    bool comDefinicao = false,
    bool contarLinhas = false,
  }) async {
    final sql = '''
SELECT c.relkind::text || chr(31) || COALESCE(pg_get_viewdef(c.oid, true), '')
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = '$nome';
''';
    final res = await _executarPsql(
      psqlPath: psqlPath,
      baseArgs: baseArgs,
      ambiente: ambiente,
      comando: sql,
    );
    if (res.exitCode != 0) return null;
    // A definição da view vem em VÁRIAS linhas: separar por linha cortaria o
    // SELECT no primeiro `,` e o CREATE VIEW sairia inválido. Por isso o corte
    // é pelo separador, não pela quebra de linha.
    final saida = (res.stdout as String? ?? '').replaceAll('\r\n', '\n');
    if (saida.trim().isEmpty) return null;
    final separador = saida.indexOf('\u001f');
    final relkind = (separador >= 0 ? saida.substring(0, separador) : saida).trim();
    final definicaoBruta = separador >= 0 ? saida.substring(separador + 1) : '';

    var linhas = 0;
    var colunas = const <_ColunaEsquema>[];
    if (contarLinhas) {
      final r = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: 'SELECT count(*) FROM public.${_ident(nome)};',
      );
      linhas = int.tryParse((r.stdout as String? ?? '').trim()) ?? 0;
      try {
        colunas = await _lerEsquema(psqlPath, baseArgs, ambiente)
            .then((e) => e[nome] ?? const <_ColunaEsquema>[]);
      } catch (_) {}
    }

    return _ObjetoBanco(
      relkind: relkind,
      definicao: comDefinicao ? definicaoBruta : null,
      linhas: contarLinhas ? linhas : null,
      colunas: colunas,
    );
  }

  /// Diagnóstico dos dois bancos lido na hora (usado no fim das trocas acima,
  /// para o diálogo já mostrar o número novo de tabelas de cada lado).
  Future<List<String>> _linhasDiagnosticoEsquemaLocal() async {
    try {
      final psqlPath = await _findExecutable('psql');
      if (psqlPath == null) return const [];
      final (argsLocal, ambienteLocal) = _conexaoPsql();
      final (argsNuvem, ambienteNuvem) = _conexaoNuvemDoEnv();
      final esquemaLocal = await _lerEsquema(psqlPath, argsLocal, ambienteLocal);
      final esquemaNuvem = await _lerEsquema(psqlPath, argsNuvem, ambienteNuvem);
      final relacoesLocal = await _lerRelacoes(psqlPath, argsLocal, ambienteLocal);
      final relacoesNuvem = await _lerRelacoes(psqlPath, argsNuvem, ambienteNuvem);
      final diag = _compararEsquemas(
        esquemaLocal: esquemaLocal,
        esquemaNuvem: esquemaNuvem,
        relacoesLocal: relacoesLocal,
        relacoesNuvem: relacoesNuvem,
      );
      return [
        '',
        '📊 Agora: banco local ${diag.tabelasDeNegocioLocal} tabela(s) de negócio '
            '(${diag.privadasDoApp.length} privada(s) do app fora da conta) × '
            'nuvem ${diag.tabelasDeNegocioNuvem} tabela(s).',
        ..._linhasDiagnosticoEsquema(diag),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// `true` quando o PostgreSQL local tem `gen_random_uuid()` embutido
  /// (13+). Antes disso o DEFAULT de id que a nuvem usa é descartado.
  Future<bool> _uuidNativoNoLocal(
    String psqlPath,
    List<String> baseArgs,
    Map<String, String> ambiente,
  ) async {
    try {
      final res = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: "SELECT current_setting('server_version_num')",
      );
      final versao = int.tryParse((res.stdout as String? ?? '').trim()) ?? 0;
      return versao >= 130000;
    } catch (_) {
      return false;
    }
  }

  /// Argumentos e ambiente do psql para o banco da NUVEM, a partir do `.env`
  /// (as mesmas variáveis do backup da nuvem). Lança [StateError] com uma
  /// mensagem legível quando não estiver configurado.
  (List<String>, Map<String, String>) _conexaoNuvemDoEnv() {
    final host = EnvConfig.supabasePoolerHost.trim();
    final senha = EnvConfig.supabasePoolerPassword.trim();
    if (host.isEmpty || senha.isEmpty) {
      throw StateError('Conexão com o banco da nuvem não configurada no .env '
          '(SUPABASE_POOLER_HOST / SUPABASE_POOLER_PASSWORD).');
    }
    return _conexaoPsqlNuvem(
      host: host,
      porta: EnvConfig.supabasePoolerPort,
      usuario: EnvConfig.supabasePoolerUser,
      senha: senha,
      banco: EnvConfig.supabaseDbNameFinal,
    );
  }

  /// A primeira linha útil de um erro (os erros do psql vêm com várias linhas
  /// de contexto que não cabem na tela).
  static String _mensagemCurtaErro(Object erro) {
    final texto = erro.toString().replaceFirst('Exception: ', '').trim();
    final linhas = texto
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (linhas.isEmpty) return 'erro desconhecido';
    return linhas.first;
  }

  /// Lê tabelas e colunas de um banco (local ou nuvem) pelo psql.
  ///
  /// Uma linha por coluna, com os campos separados por `chr(31)`:
  /// tabela, coluna, tipo, tipo_kind, obrigatória, default, chave-primária.
  Future<Map<String, List<_ColunaEsquema>>> _lerEsquema(
    String psqlPath,
    List<String> baseArgs,
    Map<String, String> ambiente,
  ) async {
    const sql = '''
SELECT c.relname || chr(31) || a.attname || chr(31) || format_type(a.atttypid, a.atttypmod)
     || chr(31) || t.typtype::text || chr(31) || a.attnotnull::text || chr(31)
     || COALESCE(pg_get_expr(d.adbin, d.adrelid), '') || chr(31)
     || CASE WHEN pk.attnum IS NULL THEN 'f' ELSE 't' END
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
JOIN pg_type t ON t.oid = a.atttypid
LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
LEFT JOIN (SELECT conrelid, unnest(conkey) AS attnum FROM pg_constraint WHERE contype = 'p') pk
       ON pk.conrelid = c.oid AND pk.attnum = a.attnum
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname, a.attnum;
''';

    final result = await _executarPsql(
      psqlPath: psqlPath,
      baseArgs: baseArgs,
      ambiente: ambiente,
      comando: sql,
    ).timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw TimeoutException('Leitura do esquema excedeu 90s'),
    );

    if (result.exitCode != 0) {
      throw Exception((result.stderr as String? ?? '').trim());
    }

    final esquema = <String, List<_ColunaEsquema>>{};
    for (final linha in (result.stdout as String? ?? '').split(RegExp(r'\r?\n'))) {
      if (linha.trim().isEmpty) continue;
      final partes = linha.split('\u001f');
      if (partes.length < 7) continue;
      final tabela = partes[0].trim();
      if (tabela.isEmpty) continue;
      esquema.putIfAbsent(tabela, () => []).add(
            _ColunaEsquema(
              nome: partes[1].trim(),
              tipo: partes[2].trim(),
              tipoKind: partes[3].trim(),
              obrigatoria: partes[4].trim() == 't',
              padrao: partes[5].trim(),
              chavePrimaria: partes[6].trim() == 't',
            ),
          );
    }
    return esquema;
  }

  /// Nomes de TODAS as relações do schema `public` (tabelas, views, matviews).
  ///
  /// Serve para não tentar criar uma tabela que já existe na nuvem como view —
  /// o CREATE TABLE falharia por nome duplicado.
  Future<Set<String>> _lerRelacoes(
    String psqlPath,
    List<String> baseArgs,
    Map<String, String> ambiente,
  ) async {
    const sql = 'SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace '
        "WHERE n.nspname = 'public' AND c.relkind IN ('r','v','m','p','f');";

    final result = await _executarPsql(
      psqlPath: psqlPath,
      baseArgs: baseArgs,
      ambiente: ambiente,
      comando: sql,
    ).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException('Leitura das relações excedeu 60s'),
    );

    if (result.exitCode != 0) {
      throw Exception((result.stderr as String? ?? '').trim());
    }

    return (result.stdout as String? ?? '')
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toSet();
  }

  /// Traduz o tipo do PostgreSQL local para um tipo aceito na nuvem.
  ///
  /// Listas viram `jsonb` (é como o app guarda listas no Supabase), enum/domínio
  /// viram `text` (os tipos personalizados não existem na nuvem).
  String _tipoParaNuvem(_ColunaEsquema coluna) {
    if (coluna.tipoKind == 'e' || coluna.tipoKind == 'd') return 'text';

    final tipo = coluna.tipo.trim();
    final baixo = tipo.toLowerCase();
    if (baixo.endsWith('[]')) return 'jsonb';
    if (baixo == 'user-defined' || baixo == 'oid' || baixo == 'name' || baixo == 'unknown') {
      return 'text';
    }
    if (baixo.startsWith('timestamp without time zone')) return 'timestamp';
    if (baixo.startsWith('timestamp with time zone')) return 'timestamptz';
    if (baixo == 'character varying') return 'text';
    if (baixo.startsWith('character varying(')) {
      return 'varchar${tipo.substring('character varying'.length)}';
    }
    if (baixo == 'character') return 'text';
    if (baixo.startsWith('character(')) return 'char${tipo.substring('character'.length)}';
    if (baixo == 'time without time zone') return 'time';
    if (baixo == 'time with time zone') return 'timetz';
    return tipo;
  }

  /// DEFAULT do banco local que pode ser copiado para a nuvem.
  ///
  /// Sequências (`nextval`) são descartadas (não existem na nuvem) e casts para
  /// tipos que podem não existir lá também. Sem isso, o CREATE TABLE falharia.
  String? _defaultParaNuvem(String padrao) {
    final p = padrao.trim();
    if (p.isEmpty) return null;
    final baixo = p.toLowerCase();
    if (baixo.contains('nextval(') || baixo.contains('regclass')) return null;

    const tiposOk = {
      'text', 'jsonb', 'json', 'numeric', 'integer', 'bigint', 'boolean', 'date',
      'timestamp', 'timestamp without time zone', 'timestamptz',
      'timestamp with time zone', 'double precision', 'character varying',
      'smallint', 'real',
    };
    for (final m in RegExp(r'::\s*([a-zA-Z_][a-zA-Z0-9_ ]*)').allMatches(p)) {
      final tipo = m.group(1)!.trim().toLowerCase();
      if (!tiposOk.contains(tipo)) return null;
    }
    return p;
  }

  /// Compara dois tipos de forma tolerante (para o aviso de tipos diferentes).
  ///
  /// O app manda datas como texto ISO e listas como JSON, então as famílias
  /// abaixo são todas compatíveis na prática — o objetivo do aviso é pegar
  /// diferenças esquisitas (ex.: uma coluna numérica que virou texto), não
  /// encher a tela com as diferenças normais entre este banco local e a nuvem.
  bool _tiposCompativeis(String tipoLocal, String tipoNuvem) {
    String normalizar(String t) {
      var s = t.toLowerCase().trim();
      if (s == 'timestamp without time zone') s = 'timestamp';
      if (s == 'timestamp with time zone') s = 'timestamptz';
      if (s == 'character varying') s = 'varchar';
      if (s.startsWith('character varying(')) s = 'varchar';
      if (s == 'character' || s.startsWith('character(')) s = 'bpchar';

      // Texto, datas, json e uuid: o PostgREST converte sozinho (e o app envia
      // esses valores como string).
      const flexiveis = {
        'text', 'varchar', 'bpchar', 'json', 'jsonb', 'uuid', 'date', 'time',
        'timetz', 'timestamp', 'timestamptz',
      };
      if (flexiveis.contains(s)) return 'flexivel';

      if (s == 'double precision' || s == 'real') return 'decimal';
      if (s.startsWith('numeric') || s.startsWith('decimal')) return 'decimal';
      if (s == 'integer' || s == 'bigint' || s == 'smallint' || s == 'numero') return 'decimal';
      return s;
    }

    return normalizar(tipoLocal) == normalizar(tipoNuvem);
  }

  /// SQL que cria uma tabela na nuvem igual à do banco local (colunas, tipo,
  /// NOT NULL, DEFAULT quando é seguro copiar e a chave primária).
  String _sqlCriarTabela(String tabela, List<_ColunaEsquema> colunas) {
    final partes = <String>[];
    for (final c in colunas) {
      final buffer = StringBuffer('  ${_ident(c.nome)} ${_tipoParaNuvem(c)}');
      final padrao = _defaultParaNuvem(c.padrao);
      if (c.obrigatoria && (padrao != null || c.chavePrimaria)) buffer.write(' NOT NULL');
      if (padrao != null) buffer.write(' DEFAULT $padrao');
      partes.add(buffer.toString());
    }

    final pk = colunas.where((c) => c.chavePrimaria).map((c) => _ident(c.nome)).toList();
    if (pk.isNotEmpty) partes.add('  PRIMARY KEY (${pk.join(', ')})');

    return 'CREATE TABLE IF NOT EXISTS public.${_ident(tabela)} (\n'
        '${partes.join(',\n')}\n'
        ');';
  }

  /// SQL que adiciona na nuvem as colunas que faltam em uma tabela existente.
  String _sqlAdicionarColunas(String tabela, List<_ColunaEsquema> colunas) {
    final partes = <String>[];
    for (final c in colunas) {
      final buffer = StringBuffer('ALTER TABLE public.${_ident(tabela)} ADD COLUMN IF NOT EXISTS '
          '${_ident(c.nome)} ${_tipoParaNuvem(c)}');
      final padrao = _defaultParaNuvem(c.padrao);
      if (padrao != null) {
        buffer.write(' DEFAULT $padrao');
        // Só mantém NOT NULL quando há DEFAULT — senão a tabela com dados recusaria.
        if (c.obrigatoria) buffer.write(' NOT NULL');
      }
      partes.add('$buffer;');
    }
    return partes.join('\n');
  }

  /// Colunas que NÃO são criadas automaticamente no banco local: mexer nelas
  /// muda como o app entra (login) e como ele guarda segredo. Elas aparecem no
  /// relatório marcadas, saem COMENTADAS no SQL salvo em disco e só entram se o
  /// usuário rodar o arquivo na mão.
  static const Set<String> colunasSensiveis = {
    'usuarios.senha',
    'usuarios.senha_hash',
    'usuarios.hash_senha',
    'empresas.senha_certificado',
    'empresas.certificado_senha',
    'configuracoes.senha_certificado',
  };

  /// Colunas que existem na nuvem, faltam aqui, mas que o app NÃO cria sozinho
  /// porque criá-las muda o comportamento de LEITURA do próprio app.
  ///
  /// O caso é `empresas.empresa_id`: o carregador genérico do PostgreSQL
  /// (`DatabaseService.carregarLista`) aplica `WHERE empresa_id = <empresa aberta>`
  /// automática e obrigatoriamente **quando a tabela tem a coluna**. Hoje
  /// `empresas` não tem, e é assim que a lista de empresas é lida
  /// (`AuthService.carregarEmpresas` → `LocalStorageService.carregarLista`).
  /// Criando a coluna aqui — e ela nasce VAZIA, porque a nuvem também não tem
  /// dado confiável nela (lá a empresa 1 aponta para o id de OUTRA empresa) —
  /// a leitura passaria a filtrar por um valor nulo e a lista de empresas
  /// voltaria vazia: o app pareceria ter perdido as empresas, mesmo com as
  /// linhas intactas no banco.
  ///
  /// Por isso ela fica de fora da criação automática: aparece no relatório e no
  /// SQL salvo em disco (comentada), para o usuário decidir com a estrutura na
  /// mão. Ver [colunasSensiveis] para o outro motivo de exclusão (segredo).
  static const Set<String> colunasQueExigemDecisao = {
    'empresas.empresa_id',
  };

  /// Coluna que o app NÃO cria por conta própria: segredo (login/certificado) ou
  /// coluna cuja existência muda como o app LÊ a tabela. Ela aparece no relatório
  /// e entra só quando o usuário autoriza no diálogo da tela (ou rodando à mão o
  /// SQL comentado em disco).
  static bool naoCriarSozinho(String tabelaColuna) =>
      colunasSensiveis.contains(tabelaColuna) ||
      colunasQueExigemDecisao.contains(tabelaColuna);

  static bool _naoCriarSozinho(String tabelaColuna) =>
      naoCriarSozinho(tabelaColuna);

  // ── Nuvem → Local (o caminho inverso) ──────────────────────────────────────

  /// Tipos de cast que qualquer PostgreSQL 13+ entende. Um DEFAULT que faz cast
  /// para algo fora desta lista (ex.: `::citext`, `::auth.role`) não é trazido,
  /// senão o CREATE TABLE daqui falharia.
  static const Set<String> _tiposDeCastSeguros = {
    'text', 'varchar', 'character varying', 'char', 'character', 'bpchar',
    'numeric', 'decimal', 'integer', 'int', 'int2', 'int4', 'int8', 'bigint',
    'smallint', 'boolean', 'bool', 'json', 'jsonb', 'date', 'time', 'timestamp',
    'timestamptz', 'timestamp without time zone', 'timestamp with time zone',
    'time without time zone', 'time with time zone', 'uuid',
    'double precision', 'real',
  };

  /// Funções usadas em DEFAULT que existem no PostgreSQL local (a nuvem também
  /// usa `auth.*`/`extensions.*`, que não existem aqui — essas são descartadas).
  static const Set<String> _funcoesDefaultSeguras = {
    'now',
    'timezone',
    'current_timestamp',
    'current_date',
    'current_time',
    'localtimestamp',
    'transaction_timestamp',
    'statement_timestamp',
    'gen_random_uuid',
  };

  /// Traduz o tipo da NUVEM para um tipo que o banco local entende.
  ///
  /// Enums e domínios viram `text` (os tipos personalizados do Supabase não
  /// existem aqui) e qualquer tipo de outro schema (`extensions.citext`,
  /// `auth.uid`) também.
  String _tipoParaLocal(_ColunaEsquema coluna) {
    if (coluna.tipoKind == 'e' || coluna.tipoKind == 'd') return 'text';
    final tipo = coluna.tipo.trim();
    if (tipo.isEmpty) return 'text';
    final baixo = tipo.toLowerCase();
    if (baixo == 'user-defined' || baixo == 'oid' || baixo == 'name' || baixo == 'unknown') {
      return 'text';
    }
    // Tipo de outro schema (auth.users, extensions.citext...).
    if (baixo.replaceAll('[]', '').contains('.')) return 'text';
    return tipo;
  }

  /// DEFAULT da nuvem que pode ser copiado para o banco local.
  ///
  /// Só passam literais (`0`, `''`, `true`, `'[]'::jsonb`) e funções universais
  /// (`now()`, `timezone(...)`). Sequências (`nextval`) e chamadas do Supabase
  /// (`auth.uid()`) são descartadas — sem isso o CREATE TABLE falharia aqui.
  String? _defaultParaLocal(String padrao, {required bool uuidNativo}) {
    final original = padrao.trim();
    if (original.isEmpty) return null;

    final baixoOriginal = original.toLowerCase();
    if (baixoOriginal.contains('nextval(') || baixoOriginal.contains('regclass')) {
      return null;
    }
    if (!_castsSeguros(original)) return null;

    // Tira o cast externo e os parênteses: '(gen_random_uuid())::text' vira
    // 'gen_random_uuid()'.
    var p = original.replaceFirst(RegExp(r'::\s*[A-Za-z_][\w. ]*(\[\])?\s*$'), '').trim();
    while (p.startsWith('(') && p.endsWith(')')) {
      p = p.substring(1, p.length - 1).trim();
    }
    if (p.isEmpty) return original;
    final b = p.toLowerCase();

    // Literais.
    if (b == 'true' || b == 'false' || b == 'null') return original;
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(b)) return original;
    if (b.startsWith("'") && b.endsWith("'")) return original;

    // Função: só as universais.
    final nome = RegExp(r'^[a-z_][a-z0-9_]*').firstMatch(b)?.group(0) ?? '';
    if (nome.isEmpty || !_funcoesDefaultSeguras.contains(nome)) return null;
    if (nome == 'gen_random_uuid' && !uuidNativo) return null;
    return original;
  }

  /// Todo cast presente na expressão aponta para um tipo que o local tem.
  static bool _castsSeguros(String padrao) {
    for (final m in RegExp(r'::\s*([A-Za-z_][A-Za-z0-9_ ]*(?:\[\])?)').allMatches(padrao)) {
      var tipo = m.group(1)!.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      tipo = tipo.replaceAll(RegExp(r'\(\d+(,\s*\d+)?\)$'), '').trim();
      if (!_tiposDeCastSeguros.contains(tipo)) return false;
    }
    return true;
  }

  /// SQL que cria no banco LOCAL uma tabela igual à da nuvem.
  ///
  /// A tabela nasce VAZIA, então o NOT NULL é mantido como está lá: não há
  /// linha nenhuma para violar a regra.
  String _sqlCriarTabelaNoLocal(
    String tabela,
    List<_ColunaEsquema> colunas, {
    required bool uuidNativo,
  }) {
    final partes = <String>[];
    for (final c in colunas) {
      final buffer = StringBuffer('  ${_ident(c.nome)} ${_tipoParaLocal(c)}');
      final padrao = _defaultParaLocal(c.padrao, uuidNativo: uuidNativo);
      if (c.obrigatoria) buffer.write(' NOT NULL');
      if (padrao != null) buffer.write(' DEFAULT $padrao');
      partes.add(buffer.toString());
    }

    final pk = colunas.where((c) => c.chavePrimaria).map((c) => _ident(c.nome)).toList();
    if (pk.isNotEmpty) partes.add('  PRIMARY KEY (${pk.join(', ')})');

    return 'CREATE TABLE IF NOT EXISTS public.${_ident(tabela)} (\n'
        '${partes.join(',\n')}\n'
        ');';
  }

  /// Linha COMENTADA do SQL que "reserva" uma coluna que o app não cria sozinho
  /// ([colunasSensiveis] e [colunasQueExigemDecisao]).
  ///
  /// Ela vai no arquivo salvo em disco (dá para rodar à mão), mas o app NÃO a
  /// executa: sem autorização explícita a coluna continua de fora do banco.
  ///
  /// O texto é ASCII puro DE PROPÓSITO: no Windows, acento em SQL já derrubou
  /// um comando inteiro ("sequência de bytes é inválida para codificação UTF8").
  ///
  /// Exposta para teste — é a MESMA função que monta o arquivo de verdade.
  @visibleForTesting
  static String linhaComentadaDeColunaQueNaoCriaSozinho(
      String rotulo, String sql) {
    final motivo = colunasSensiveis.contains(rotulo)
        ? 'sensivel: o app NAO cria esta coluna sozinho'
        : 'precisa de decisao: cria-la faria o app filtrar a leitura por ela';
    return '-- ($motivo) $sql;';
  }

  /// SQL que adiciona no banco LOCAL as colunas que faltam em uma tabela que já
  /// existe aqui.
  ///
  /// Numa tabela com dados, NOT NULL só entra quando há DEFAULT — senão as
  /// linhas que já existem recusariam a coluna.
  ///
  /// [criarColunasAutorizadas] faz as colunas de [colunasSensiveis] e de
  /// [colunasQueExigemDecisao] saírem executáveis em vez de comentadas (é a
  /// escolha explícita do usuário no diálogo da tela).
  String _sqlAdicionarColunasNoLocal(
    String tabela,
    List<_ColunaEsquema> colunas, {
    required bool uuidNativo,
    bool criarColunasAutorizadas = false,
  }) {
    final partes = <String>[];
    for (final c in colunas) {
      final buffer = StringBuffer(
          'ALTER TABLE public.${_ident(tabela)} ADD COLUMN IF NOT EXISTS '
          '${_ident(c.nome)} ${_tipoParaLocal(c)}');
      final padrao = _defaultParaLocal(c.padrao, uuidNativo: uuidNativo);

      // Coluna sensível (senha) ou que muda a leitura do app (empresas.empresa_id):
      // fica COMENTADA no arquivo e o app não executa — a não ser que o usuário
      // tenha autorizado esta rodada (opção marcada no diálogo).
      if (naoCriarSozinho('$tabela.${c.nome}') && !criarColunasAutorizadas) {
        if (padrao != null) buffer.write(' DEFAULT $padrao');
        partes.add(linhaComentadaDeColunaQueNaoCriaSozinho(
            '$tabela.${c.nome}', buffer.toString().trim()));
        continue;
      }
      if (padrao != null) {
        buffer.write(' DEFAULT $padrao');
        if (c.obrigatoria) buffer.write(' NOT NULL');
      }
      partes.add('$buffer;');
    }
    return partes.join('\n');
  }

  // ============================================================
  // BACKUP COMPLETO DO BANCO DA NUVEM VIA PSQL (.sql)
  // ============================================================

  /// Argumentos base e ambiente de conexão do psql para o banco da NUVEM,
  /// sempre pelo pooler IPv4.
  (List<String>, Map<String, String>) _conexaoPsqlNuvem({
    required String host,
    required int porta,
    required String usuario,
    required String senha,
    required String banco,
  }) {
    final ambiente = Map<String, String>.from(Platform.environment);
    ambiente['PGPASSWORD'] = senha;
    ambiente['PGCLIENTENCODING'] = 'UTF8';
    ambiente['PGCONNECT_TIMEOUT'] = '30';

    final args = <String>[
      '-h', host,
      '-p', '$porta',
      '-U', usuario,
      '-d', banco,
      '--no-psqlrc',
      '-v', 'ON_ERROR_STOP=1',
      '-A',
      '-t',
    ];
    return (args, ambiente);
  }

  /// Versão MAIOR de um executável do PostgreSQL (ex.: `pg_dump ... 16.4` → 16).
  Future<int?> _versaoMaiorExecutavel(String caminho) async {
    try {
      final res = await runProcessHidden(caminho, const ['--version'],
              environment: Platform.environment)
          .timeout(const Duration(seconds: 20));
      final texto = '${res.stdout}${res.stderr}';
      final m = RegExp(r'(\d+)(\.\d+)?').firstMatch(texto);
      return m == null ? null : int.tryParse(m.group(1)!);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível ler a versão de "$caminho": $e');
      return null;
    }
  }

  /// Converte o stderr de uma falha de conexão com a nuvem em uma mensagem
  /// clara para o usuário.
  String _mensagemErroConexaoNuvem(
    String stderr,
    String host,
    int porta,
    String usuario,
  ) {
    final s = stderr.toLowerCase();
    if (s.contains('translate host') || s.contains('name or service not known') || s.contains('traduzir')) {
      return 'Não foi possível resolver o host "$host". Confira SUPABASE_POOLER_HOST no .env.';
    }
    if (s.contains('tenant/user') && s.contains('not found')) {
      return 'Usuário/região incorretos no pooler ("$usuario" em "$host").\n\n'
          'Confira SUPABASE_POOLER_HOST (ex.: aws-1-us-west-2.pooler.supabase.com) e SUPABASE_POOLER_USER no .env.';
    }
    if (s.contains('authentication failed') || s.contains('password authentication') || s.contains('autentica')) {
      return 'Falha de autenticação no banco da nuvem.\n\n'
          'A senha em SUPABASE_POOLER_PASSWORD precisa ser a senha do BANCO do Supabase '
          '(a mesma de "Database password", no painel do projeto).\n\n'
          'Atenção: as chaves de API que começam com "sb_secret_" NÃO são a senha do banco.';
    }
    if (s.contains('timeout') || s.contains('connection refused') || s.contains('could not connect') || s.contains('recus')) {
      return 'Não foi possível conectar ao banco da nuvem em $host:$porta (conexão recusada ou tempo esgotado).';
    }
    if (s.contains('version mismatch')) {
      return 'A versão do pg_dump deste computador é mais antiga que a do banco da nuvem.';
    }
    return 'Não foi possível conectar ao banco da nuvem: ${stderr.isEmpty ? 'erro desconhecido' : stderr}';
  }

  /// Tabelas base (com as colunas na ordem real) do schema `public`, INCLUINDO
  /// todas as empresas. Views ficam de fora (`relkind <> 'r'`), senão o COPY
  /// falharia.
  Future<List<({String tabela, List<String> colunas})>> _tabelasBaseDoPublico(
    String psqlPath,
    List<String> baseArgs,
    Map<String, String> ambiente,
  ) async {
    const sql = '''
SELECT c.relname || '|' || string_agg(a.attname, ',' ORDER BY a.attnum)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
GROUP BY c.relname
ORDER BY c.relname;
''';

    final result = await _executarPsql(
      psqlPath: psqlPath,
      baseArgs: baseArgs,
      ambiente: ambiente,
      comando: sql,
    );
    if (result.exitCode != 0) {
      throw Exception((result.stderr as String? ?? '').trim());
    }

    final lista = <({String tabela, List<String> colunas})>[];
    for (final linha in (result.stdout as String).split(RegExp(r'\r?\n'))) {
      final linhaLimpa = linha.trim();
      if (linhaLimpa.isEmpty) continue;
      final partes = linhaLimpa.split('|');
      if (partes.length != 2 || partes[0].isEmpty) continue;
      final colunas = partes[1].split(',').where((c) => c.isNotEmpty).toList();
      if (colunas.isEmpty) continue;
      lista.add((tabela: partes[0], colunas: colunas));
    }
    return lista;
  }

  /// Relações de chave estrangeira entre as tabelas base do schema `public`
  /// (filho → pai).
  Future<List<(String, String)>> _dependenciasFk(
    String psqlPath,
    List<String> baseArgs,
    Map<String, String> ambiente,
  ) async {
    const sql = '''
SELECT c.relname || '>' || rc.relname
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_class rc ON rc.oid = con.confrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE con.contype = 'f' AND n.nspname = 'public'
GROUP BY 1;
''';

    final lista = <(String, String)>[];
    try {
      final result = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        comando: sql,
      );
      if (result.exitCode != 0) return lista;

      for (final linha in (result.stdout as String).split(RegExp(r'\r?\n'))) {
        final partes = linha.trim().split('>');
        if (partes.length != 2 || partes[0].isEmpty || partes[1].isEmpty) continue;
        lista.add((partes[0], partes[1]));
      }
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível ler as chaves estrangeiras: $e');
    }
    return lista;
  }

  /// Ordena as tabelas para que toda tabela PAI venha antes das tabelas que
  /// dependem dela. É isso que permite recarregar os dados com as chaves
  /// estrangeiras ligadas: sem essa ordem, inserir uma tabela filha antes do
  /// pai viola a FK (foi o que acontecia com `aberturas_caixa → empresas`).
  List<String> _ordemPorDependencia(List<String> tabelas, List<(String, String)> fks) {
    final paisDe = <String, Set<String>>{for (final t in tabelas) t: <String>{}};
    for (final (filho, pai) in fks) {
      if (paisDe.containsKey(filho) && paisDe.containsKey(pai)) {
        paisDe[filho]!.add(pai);
      }
    }

    final ordenado = <String>[];
    final visitados = <String>{};
    void visitar(String tabela) {
      if (!visitados.add(tabela)) return;
      for (final pai in paisDe[tabela]!) {
        visitar(pai);
      }
      ordenado.add(tabela);
    }

    for (final t in tabelas) {
      visitar(t);
    }
    return ordenado;
  }

  /// Bloco que reajusta as sequences para o maior id existente em cada tabela
  /// (senão o próximo INSERT tentaria um id que já existe).
  static const String _blocoReajusteSequences = r'''
-- Reajusta as sequences para o maior id de cada tabela
DO $$
DECLARE
  r record;
  mx bigint;
BEGIN
  FOR r IN
    SELECT n.nspname AS sch,
           c.relname AS tab,
           a.attname AS col,
           pg_get_serial_sequence(format('%I.%I', n.nspname, c.relname), a.attname) AS seq
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND pg_get_serial_sequence(format('%I.%I', n.nspname, c.relname), a.attname) IS NOT NULL
  LOOP
    EXECUTE format('SELECT COALESCE(MAX(%I), 0) FROM %I.%I', r.col, r.sch, r.tab) INTO mx;
    PERFORM setval(r.seq, GREATEST(mx, 1), mx > 0);
  END LOOP;
END $$;
''';

  /// Gera um backup PostgreSQL (.sql) COMPLETO do banco da NUVEM (Supabase):
  /// TODAS as tabelas do schema `public` com TODOS os registros, de TODAS as
  /// empresas.
  ///
  /// É usado quando o `pg_dump` do computador é mais antigo que o servidor da
  /// nuvem — o que é o caso comum, já que o Supabase está na versão 17 e o
  /// PostgreSQL que acompanha o app na 16 —, situação em que o `pg_dump` se
  /// recusa a rodar ("aborting because of server version mismatch"). O `psql`
  /// não tem essa limitação.
  ///
  /// Retorna (sucesso, mensagem, caminho do arquivo).
  Future<(bool, String, String?)> criarBackupSqlBancoNuvem({
    String? destinoArquivo,
    String? host,
    int? porta,
    String? usuario,
    String? senha,
    String? banco,
    void Function(String)? onProgress,
  }) async {
    if (kIsWeb) {
      return (false, 'Backup do banco da nuvem não está disponível na versão Web.', null);
    }

    final hostFinal = (host ?? EnvConfig.supabasePoolerHost).trim();
    final portaFinal = porta ?? EnvConfig.supabasePoolerPort;
    final usuarioFinal = usuario ?? EnvConfig.supabasePoolerUser;
    final senhaFinal = senha ?? EnvConfig.supabasePoolerPassword;
    final bancoFinal = banco ?? EnvConfig.supabaseDbNameFinal;

    if (hostFinal.isEmpty || senhaFinal.isEmpty) {
      return (
        false,
        'Conexão do banco da nuvem não configurada.\n\n'
        'Confira no .env: SUPABASE_POOLER_HOST e SUPABASE_POOLER_PASSWORD.',
        null,
      );
    }

    try {
      final psqlPath = await _findExecutable('psql');
      if (psqlPath == null) {
        return (false, 'psql não encontrado. Use o PostgreSQL que acompanha o app para gerar o backup da nuvem.', null);
      }

      final (baseArgs, ambiente) = _conexaoPsqlNuvem(
        host: hostFinal,
        porta: portaFinal,
        usuario: usuarioFinal,
        senha: senhaFinal,
        banco: bancoFinal,
      );

      final tabelas = await _tabelasBaseDoPublico(psqlPath, baseArgs, ambiente);
      if (tabelas.isEmpty) {
        return (false, 'Nenhuma tabela encontrada no banco da nuvem.', null);
      }

      debugPrint('>>> [BackupRestore] ☁️ Gerando backup .sql COMPLETO da nuvem '
          '($usuarioFinal@$hostFinal:$portaFinal/$bancoFinal) — ${tabelas.length} tabelas');

      // 1. Exportar TODAS as linhas de TODAS as tabelas no formato COPY do PostgreSQL
      final blocos = <({String tabela, String colunasSql, String dados, int linhas})>[];
      for (var i = 0; i < tabelas.length; i++) {
        final t = tabelas[i];
        onProgress?.call('Lendo tabela ${t.tabela} (${i + 1}/${tabelas.length})...');
        final colunasSql = t.colunas.map(_ident).join(', ');
        final comando = '\\copy (SELECT $colunasSql FROM public.${_ident(t.tabela)}) TO STDOUT';

        final result = await _executarPsql(
          psqlPath: psqlPath,
          baseArgs: baseArgs,
          ambiente: ambiente,
          comando: comando,
        ).timeout(
          const Duration(minutes: 20),
          onTimeout: () => throw TimeoutException('Exportação da tabela ${t.tabela} excedeu o tempo limite'),
        );

        if (result.exitCode != 0) {
          final err = (result.stderr as String? ?? '').trim();
          debugPrint('>>> [BackupRestore] ❌ Falha ao exportar ${t.tabela}: $err');
          return (false, 'Falha ao exportar a tabela ${t.tabela} do banco da nuvem: $err', null);
        }

        final dados = (result.stdout as String).replaceAll('\r\n', '\n');
        final linhas = dados.isEmpty ? 0 : dados.split('\n').where((l) => l.isNotEmpty).length;
        blocos.add((tabela: t.tabela, colunasSql: colunasSql, dados: dados, linhas: linhas));
      }

      final totalLinhas = blocos.fold<int>(0, (soma, b) => soma + b.linhas);

      // 2. Ordenar as tabelas pelas chaves estrangeiras: as tabelas PAI são
      // recarregadas primeiro (e apagadas por último). Sem isso o banco da
      // nuvem rejeita a carga: todas as tabelas apontam para `empresas`.
      onProgress?.call('Todas as ${tabelas.length} tabelas lidas — montando script SQL...');
      final fks = await _dependenciasFk(psqlPath, baseArgs, ambiente);
      final ordem = _ordemPorDependencia(blocos.map((b) => b.tabela).toList(), fks);
      final porTabela = {for (final b in blocos) b.tabela: b};
      final blocosOrdenados = [for (final t in ordem) porTabela[t]!];

      final agora = DateTime.now();
      final dataStr = '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
      final horaStr = '${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';

      // 3. Montar o script SQL
      final buffer = StringBuffer();
      buffer.writeln('-- ============================================================');
      buffer.writeln('-- Backup PostgreSQL COMPLETO do banco da NUVEM (Supabase)');
      buffer.writeln('-- TODAS as tabelas e TODOS os registros (todas as empresas).');
      buffer.writeln('-- Gerado em ${agora.toIso8601String()} pelo Sistema Êxodo');
      buffer.writeln('-- Servidor: $hostFinal:$portaFinal/$bancoFinal');
      buffer.writeln('-- Tabelas: ${blocos.length} | Registros: $totalLinhas');
      buffer.writeln('-- A carga respeita a ordem das chaves estrangeiras (tabela pai primeiro)');
      buffer.writeln('-- ============================================================');
      buffer.writeln('-- COMO RESTAURAR:');
      buffer.writeln('--   psql -h <host> -p <porta> -U <usuario> -d <banco> -f "<este arquivo>"');
      buffer.writeln('-- ATENÇÃO: a restauração APAGA e recarrega TODAS as tabelas, de TODAS');
      buffer.writeln('-- as empresas. O esquema (as tabelas) precisa existir no destino — para um');
      buffer.writeln('-- projeto Supabase novo, rode antes o CRIAR_TODAS_TABELAS_SUPABASE.sql');
      buffer.writeln('-- ============================================================');
      buffer.writeln("SET client_encoding = 'UTF8';");
      // Se este arquivo for aplicado em um banco LOCAL, esta linha impede que a
      // restauração inteira entre na fila de envio e acabe subindo para a nuvem.
      // No Supabase é apenas um parâmetro de sessão sem efeito — inofensivo.
      buffer.writeln("SET exodo.sync_mode = 'on';");
      buffer.writeln('BEGIN;');
      buffer.writeln();

      // Apagar primeiro as tabelas FILHAS (ordem inversa da carga)
      for (final b in blocosOrdenados.reversed) {
        buffer.writeln('DELETE FROM public.${_ident(b.tabela)};');
      }
      buffer.writeln();

      // Recarregar primeiro as tabelas PAI
      for (final b in blocosOrdenados) {
        buffer.writeln('-- Tabela public.${b.tabela} (${b.linhas} registro(s))');
        buffer.writeln('COPY public.${_ident(b.tabela)} (${b.colunasSql}) FROM stdin;');
        if (b.dados.isNotEmpty) {
          buffer.write(b.dados);
          if (!b.dados.endsWith('\n')) buffer.writeln();
        }
        buffer.writeln('\\.');
        buffer.writeln();
      }

      buffer.writeln(_blocoReajusteSequences);
      buffer.writeln('COMMIT;');

      // 4. Salvar o arquivo
      var caminho = destinoArquivo ?? '';
      if (caminho.isEmpty) {
        final dir = Directory(_pastaBackupNuvem);
        if (!await dir.exists()) await dir.create(recursive: true);
        caminho = p.join(dir.path, 'nuvem_completo_${dataStr}_$horaStr.sql');
      } else if (caminho.toLowerCase().endsWith('.dump')) {
        caminho = '${caminho.substring(0, caminho.length - 5)}.sql';
      }

      onProgress?.call('Salvando arquivo no disco...');
      final arquivo = File(caminho);
      await arquivo.writeAsString(buffer.toString(), flush: true);

      final tamanhoMb = (arquivo.lengthSync() / 1024 / 1024).toStringAsFixed(2);
      onProgress?.call('Backup gerado: $tamanhoMb MB — $totalLinhas registros em ${blocos.length} tabelas');
      debugPrint('>>> [BackupRestore] ✅ Backup .sql completo da nuvem gerado '
          '($tamanhoMb MB, $totalLinhas registros, ${blocos.length} tabelas): $caminho');

      await _limparBackupsNuvemLocais();

      return (
        true,
        'Backup PostgreSQL COMPLETO da nuvem gerado ($tamanhoMb MB, $totalLinhas registros de ${blocos.length} tabelas).',
        caminho,
      );
    } on TimeoutException {
      return (false, 'Backup do banco da nuvem excedeu o tempo limite.', null);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao gerar backup .sql da nuvem: $e');
      return (false, 'Erro ao gerar o backup do banco da nuvem: $e', null);
    }
  }

  /// Mantém apenas os [_maxBackupsNuvemLocais] arquivos mais recentes da pasta
  /// de backups do banco da nuvem.
  Future<void> _limparBackupsNuvemLocais() async {
    try {
      final dir = Directory(_pastaBackupNuvem);
      if (!await dir.exists()) return;

      final files = await dir
          .list()
          .where((f) =>
              f is File && (f.path.endsWith('.dump') || f.path.endsWith('.sql')))
          .cast<File>()
          .toList();
      if (files.length <= _maxBackupsNuvemLocais) return;

      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final antigo in files.take(files.length - _maxBackupsNuvemLocais)) {
        await antigo.delete();
        debugPrint('>>> [BackupRestore] 🗑️ Backup antigo da nuvem removido: ${p.basename(antigo.path)}');
      }
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Erro ao limpar backups antigos da nuvem: $e');
    }
  }

  // ============================================================
  // DUMP POSTGRESQL NA NUVEM (Supabase Storage)
  // ============================================================

  /// Bucket usado para armazenar dumps PostgreSQL na nuvem
  static const String _bucketDumps = 'dumps';

  /// Quantos arquivos de backup (dump/empresa) são mantidos por empresa no bucket 'dumps'.
  static const int _maxDumpsNuvemPorEmpresa = 30;

  /// Garante que o bucket de dumps existe, criando-o se necessário
  Future<void> _garantirBucketDumps() async {
    try {
      final buckets = await _storageAdminClient.storage.listBuckets();
      if (!buckets.any((b) => b.id == _bucketDumps)) {
        debugPrint('>>> [BackupRestore] 🔄 Criando bucket "$_bucketDumps"...');
        await _storageAdminClient.storage.createBucket(
          _bucketDumps,
          const BucketOptions(public: false),
        );
        debugPrint('>>> [BackupRestore] ✅ Bucket "$_bucketDumps" criado!');
      }
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Não foi possível verificar/criar bucket: $e');
    }
  }

  /// Faz upload de um arquivo dump PostgreSQL (.dump/.sql) para o Supabase Storage
  /// Retorna (sucesso, mensagem)
  Future<(bool, String)> uploadDumpNaNuvem(File dumpFile) async {
    try {
      final empresaId = _dataService.currentEmpresaId;
      if (empresaId == null) return (false, 'Empresa não selecionada');
      if (!SupabaseService.isAvailable) return (false, 'Supabase não disponível');

      // Obter nome da empresa para incluir no nome do arquivo
      final nomeEmpresa = _dataService.empresaAtual?.nomeExibicao ?? empresaId;
      final nomeLimpo = nomeEmpresa.replaceAll(RegExp(r'[^a-zA-Z0-9À-ú]'), '_').replaceAll(RegExp(r'_+'), '_').trim();

      final fileName = p.basename(dumpFile.path);
      final fileBytes = await dumpFile.readAsBytes();
      final fileSize = fileBytes.length;

      debugPrint('>>> [BackupRestore] 📤 Enviando dump para nuvem: $fileName (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      await _garantirBucketDumps();

      final now = DateTime.now();
      final dataStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final horaStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      // Preserva a extensão do arquivo de origem (.sql = backup SÓ da empresa,
      // .dump = banco inteiro). Antes o nome era sempre fixado em .dump, o que
      // rotulava errado um backup .sql enviado para a nuvem.
      final extOrigem = p.extension(dumpFile.path).replaceFirst('.', '').toLowerCase();
      final ext = extOrigem.isEmpty ? 'dump' : extOrigem;
      final tipo = ext == 'sql' ? 'empresa' : 'dump';
      final nomeArquivo = '${nomeLimpo}_${tipo}_${dataStr}_$horaStr.$ext';
      final storagePath = '$empresaId/$nomeArquivo';

      try {
        await _storageAdminClient.storage
            .from(_bucketDumps)
            .uploadBinary(storagePath, fileBytes,
                fileOptions: const FileOptions(upsert: true));
      } catch (e) {
        debugPrint('>>> [BackupRestore] ⚠️ Erro no upload, tentando novamente após garantir bucket...');
        await _garantirBucketDumps();
        await _storageAdminClient.storage
            .from(_bucketDumps)
            .uploadBinary(storagePath, fileBytes,
                fileOptions: const FileOptions(upsert: true));
      }

      debugPrint('>>> [BackupRestore] ✅ Dump enviado para nuvem: $_bucketDumps/$storagePath');

      // Mantém apenas os últimos arquivos desta empresa na nuvem (evita crescer sem limite)
      await _limparDumpsNuvemAntigos(empresaId, maxArquivos: _maxDumpsNuvemPorEmpresa);

      return (true, 'Dump enviado com sucesso!');
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao enviar dump: $e');
      return (false, 'Erro ao enviar dump: ${_mensagemErroStorage(e)}');
    }
  }

  /// Mantém apenas os [maxArquivos] arquivos mais recentes da empresa no bucket
  /// 'dumps'. Cada empresa tem sua própria pasta (`{empresaId}/`), então a
  /// limpeza nunca afeta outras empresas.
  Future<void> _limparDumpsNuvemAntigos(String empresaId, {int maxArquivos = 30}) async {
    try {
      final prefix = '$empresaId/';
      final files = await _storageAdminClient.storage
          .from(_bucketDumps)
          .list(path: prefix);

      if (files.length <= maxArquivos) return;

      final ordenados = files.toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a.createdAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final db = DateTime.tryParse(b.createdAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

      final antigos = ordenados.sublist(maxArquivos);
      final caminhos = antigos.map((f) => '$prefix${f.name}').toList();
      if (caminhos.isEmpty) return;

      await _storageAdminClient.storage.from(_bucketDumps).remove(caminhos);
      debugPrint('>>> [BackupRestore] 🗑️ ${caminhos.length} arquivo(s) de backup antigo(s) removido(s) da nuvem (empresa $empresaId)');
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Erro ao limpar backups antigos da nuvem: $e');
    }
  }

  /// Lista dumps PostgreSQL salvos na nuvem para a empresa atual
  Future<List<Map<String, dynamic>>> listarDumpsNuvem() async {
    try {
      final empresaId = _dataService.currentEmpresaId;
      if (empresaId == null || !SupabaseService.isAvailable) return [];

      await _garantirBucketDumps();
      final prefix = '$empresaId/';

      final files = await _storageAdminClient.storage
          .from(_bucketDumps)
          .list(path: prefix);

      return files.map((f) => {
        'name': f.name,
        'path': '$prefix${f.name}',
        'size': f.metadata?['size'] ?? 0,
        'createdAt': f.createdAt,
      }).toList();
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Erro ao listar dumps nuvem: $e');
      return [];
    }
  }

  /// Pasta onde ficam os arquivos BAIXADOS da nuvem para restauração.
  ///
  /// É separada de `C:\ExodoBackups\<empresaId>` de propósito: assim o arquivo
  /// que veio da nuvem não se mistura com os backups gerados aqui (a lista local
  /// mostra só o que é do computador).
  static String get pastaNuvemBaixados => 'C:\\ExodoBackups\\nuvem\\baixados';

  /// Faz download de um arquivo da nuvem e salva localmente.
  ///
  /// [destino] permite guardar fora da pasta da empresa (ex.:
  /// [pastaNuvemBaixados], para o arquivo da nuvem não se misturar com os
  /// backups gerados neste computador).
  Future<(bool, String, String?)> downloadDumpDaNuvem(
    String storagePath, {
    String? destino,
  }) async {
    try {
      if (!SupabaseService.isAvailable) return (false, 'Supabase não disponível', null);

      debugPrint('>>> [BackupRestore] 📥 Baixando dump da nuvem: $storagePath');

      final bytes = await _storageAdminClient.storage
          .from(_bucketDumps)
          .download(storagePath);

      // Salvar em C:\ExodoBackups\{empresaId}\ (ou na pasta indicada)
      final empresaId = _dataService.currentEmpresaId ?? 'default';
      final backupDir = Directory(destino ?? 'C:\\ExodoBackups\\$empresaId');
      await backupDir.create(recursive: true);

      final localPath = p.join(backupDir.path, p.basename(storagePath));
      await File(localPath).writeAsBytes(bytes);

      debugPrint('>>> [BackupRestore] ✅ Dump salvo localmente: $localPath');
      return (true, 'Dump baixado com sucesso!', localPath);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao baixar dump: $e');
      return (false, 'Erro ao baixar dump: $e', null);
    }
  }

  /// Remove um dump da nuvem
  Future<bool> removerDumpNuvem(String storagePath) async {
    try {
      if (!SupabaseService.isAvailable) return false;
      await _storageAdminClient.storage
          .from(_bucketDumps)
          .remove([storagePath]);
      debugPrint('>>> [BackupRestore] 🗑️ Dump removido da nuvem: $storagePath');
      return true;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao remover dump: $e');
      return false;
    }
  }

  // ============================================================
  // BACKUP COMPLETO DO BANCO DA NUVEM — GUARDADO NA PRÓPRIA NUVEM
  // ============================================================
  //
  // Os dumps por empresa ficam em 'dumps/{empresaId}/'. Um backup COMPLETO do
  // banco da nuvem contém TODAS as empresas, então não pertence a nenhuma
  // delas: por isso ele vive em 'dumps/_banco_completo/', fora das pastas por
  // empresa. Além de ficar claro no bucket, isso garante que a limpeza
  // automática de dumps por empresa nunca apague um backup completo.

  /// Pasta (prefixo) dentro do bucket 'dumps' dos backups COMPLETOS da nuvem.
  static const String _pastaBackupCompletoNuvem = '_banco_completo';

  /// Quantos backups completos do banco da nuvem são mantidos na nuvem.
  static const int _maxBackupsCompletosNuvem = 10;

  /// Gera o backup COMPLETO do banco da nuvem (todas as tabelas, registros de
  /// TODAS as empresas) e guarda o arquivo DENTRO da própria nuvem.
  ///
  /// É o "backup da nuvem para a nuvem": não exige empresa selecionada e não
  /// depende de outra máquina. Uma cópia também fica no computador
  /// (C:\ExodoBackups\nuvem) como rede de segurança, caso o envio falhe.
  ///
  /// Retorna (sucesso, mensagem, caminho do arquivo local).
  ///
  /// [arquivoLocal] permite arquivar um backup que já está no disco (ex.: o
  /// arquivo gerado ontem) sem gerar tudo de novo. Em uso normal é omitido.
  Future<(bool, String, String?)> enviarBackupCompletoParaNuvem({
    String? arquivoLocal,
    void Function(String)? onProgress,
  }) async {
    if (kIsWeb) {
      return (false, 'Backup completo da nuvem não está disponível na versão Web.', null);
    }
    if (!SupabaseService.isAvailable) {
      return (false, 'Supabase não disponível no momento — não há como enviar o backup.', null);
    }

    // 1. Gerar o backup completo (todas as empresas) no disco — ou usar o
    // arquivo já existente, quando informado.
    String caminho;
    if (arquivoLocal != null && arquivoLocal.trim().isNotEmpty) {
      caminho = arquivoLocal.trim();
      onProgress?.call('Usando backup existente no disco...');
    } else {
      onProgress?.call('Lendo banco da nuvem e gerando backup completo...');
      final (okGerou, msgGerou, gerado) = await criarBackupBancoNuvem(
        onProgress: onProgress,
      );
      if (!okGerou || gerado == null) return (false, msgGerou, null);
      caminho = gerado;
    }
    final arquivo = File(caminho);
    if (!await arquivo.exists()) {
      return (false, 'O backup foi gerado, mas o arquivo não foi encontrado em $caminho.', null);
    }

    // 2. Enviar para a nuvem, em dumps/_banco_completo/<arquivo>
    final nomeArquivo = p.basename(arquivo.path);
    final storagePath = '$_pastaBackupCompletoNuvem/$nomeArquivo';

    try {
      final bytes = await arquivo.readAsBytes();
      final tamanhoMb = (bytes.length / 1024 / 1024).toStringAsFixed(2);
      onProgress?.call('Enviando $tamanhoMb MB para a nuvem...');
      debugPrint('>>> [BackupRestore] 📤 Enviando backup COMPLETO do banco da nuvem '
          '($tamanhoMb MB) para $_bucketDumps/$storagePath');

      await _garantirBucketDumps();

      final ext = p.extension(arquivo.path).replaceFirst('.', '').toLowerCase();
      await _storageAdminClient.storage.from(_bucketDumps).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: ext == 'sql' ? 'application/sql' : 'application/octet-stream',
              upsert: true,
            ),
          );

      await _limparBackupsCompletosNuvemAntigos();

      debugPrint('>>> [BackupRestore] ✅ Backup completo salvo na nuvem: '
          '$_bucketDumps/$storagePath');
      return (
        true,
        'Backup COMPLETO do banco da nuvem salvo na nuvem ($tamanhoMb MB — $nomeArquivo). '
            'Uma cópia também ficou em $caminho.',
        caminho,
      );
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Falha ao enviar o backup completo: $e');
      return (
        false,
        'O backup foi gerado em $caminho, mas o envio para a nuvem falhou: ${_mensagemErroStorage(e)}',
        caminho,
      );
    }
  }

  /// Lista os backups COMPLETOS do banco da nuvem guardados na nuvem, do mais
  /// recente para o mais antigo. Não depende de empresa selecionada.
  Future<List<Map<String, dynamic>>> listarBackupsCompletosNuvem() async {
    try {
      if (!SupabaseService.isAvailable) return [];

      final prefix = '$_pastaBackupCompletoNuvem/';
      final files = await _storageAdminClient.storage
          .from(_bucketDumps)
          .list(path: prefix);

      final lista = files
          .where((f) =>
              f.name.toLowerCase().endsWith('.sql') ||
              f.name.toLowerCase().endsWith('.dump'))
          .map((f) => {
                'name': f.name,
                'path': '$prefix${f.name}',
                'size': f.metadata?['size'] ?? 0,
                'createdAt': f.createdAt,
              })
          .toList();

      lista.sort((a, b) {
        final da = DateTime.tryParse(a['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final db = DateTime.tryParse(b['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });

      return lista;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Erro ao listar backups completos da nuvem: $e');
      return [];
    }
  }

  /// Baixa um backup completo da nuvem para C:\ExodoBackups\nuvem.
  ///
  /// Baixar não restaura nada: a restauração do banco inteiro é uma operação
  /// separada (e perigosa), feita no lugar certo e com confirmação própria.
  Future<(bool, String, String?)> baixarBackupCompletoDaNuvem(
      String storagePath) async {
    try {
      if (!SupabaseService.isAvailable) {
        return (false, 'Supabase não disponível', null);
      }
      if (!storagePath.startsWith('$_pastaBackupCompletoNuvem/')) {
        return (false, 'Caminho de backup completo inválido: $storagePath', null);
      }

      debugPrint('>>> [BackupRestore] 📥 Baixando backup completo da nuvem: $storagePath');
      final bytes = await _storageAdminClient.storage
          .from(_bucketDumps)
          .download(storagePath);
      if (bytes.isEmpty) {
        return (false, 'Arquivo vazio ou não encontrado na nuvem', null);
      }

      final dir = Directory(_pastaBackupNuvem);
      if (!await dir.exists()) await dir.create(recursive: true);
      final destino = p.join(dir.path, p.basename(storagePath));
      await File(destino).writeAsBytes(bytes, flush: true);

      final tamanhoMb = (bytes.length / 1024 / 1024).toStringAsFixed(2);
      debugPrint('>>> [BackupRestore] ✅ Backup completo baixado: $destino');
      return (
        true,
        'Backup completo baixado ($tamanhoMb MB).',
        destino,
      );
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao baixar backup completo: $e');
      return (false, 'Erro ao baixar backup completo: $_mensagemErroStorage(e)', null);
    }
  }

  /// Remove um backup completo da nuvem.
  ///
  /// Só aceita caminhos dentro de `_banco_completo/`: assim um bug (ou um
  /// nome trocado) nunca consegue apagar o backup de uma empresa.
  Future<bool> removerBackupCompletoNuvem(String storagePath) async {
    try {
      if (!SupabaseService.isAvailable) return false;
      if (!storagePath.startsWith('$_pastaBackupCompletoNuvem/')) {
        debugPrint('>>> [BackupRestore] ⛔ Recusado remover caminho fora de '
            '$_pastaBackupCompletoNuvem/: $storagePath');
        return false;
      }

      await _storageAdminClient.storage.from(_bucketDumps).remove([storagePath]);
      debugPrint('>>> [BackupRestore] 🗑️ Backup completo removido da nuvem: $storagePath');
      return true;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao remover backup completo: $e');
      return false;
    }
  }

  /// Mantém apenas os [_maxBackupsCompletosNuvem] backups completos mais
  /// recentes na nuvem (cada um é o banco inteiro; guardar dezenas deles só
  /// ocuparia espaço).
  Future<void> _limparBackupsCompletosNuvemAntigos() async {
    try {
      final arquivos = await listarBackupsCompletosNuvem();
      if (arquivos.length <= _maxBackupsCompletosNuvem) return;

      final antigos = arquivos
          .sublist(_maxBackupsCompletosNuvem)
          .map((a) => a['path'] as String)
          .toList();
      if (antigos.isEmpty) return;

      await _storageAdminClient.storage.from(_bucketDumps).remove(antigos);
      debugPrint('>>> [BackupRestore] 🗑️ ${antigos.length} backup(s) completo(s) '
          'antigo(s) removido(s) da nuvem (mantidos os $_maxBackupsCompletosNuvem mais recentes)');
    } catch (e) {
      debugPrint('>>> [BackupRestore] ⚠️ Erro ao limpar backups completos antigos: $e');
    }
  }

  // ============================================================
  // RESTAURAR BACKUP COMPLETO DA NUVEM → NUVEM
  // ============================================================

  /// Baixa um backup completo da nuvem e o restaura no banco da própria
  /// nuvem (Supabase PostgreSQL via pooler).
  ///
  /// Antes e depois da restauração, conta linhas de cada tabela para gerar
  /// um relatório claro do que mudou.
  ///
  /// ⚠️ Esta operação SUBSTITUI TODOS os dados de TODAS as empresas no
  /// banco da nuvem pelo conteúdo do arquivo. Não há desfazer.
  ///
  /// Retorna (sucesso, mensagem, mapa de antes/depois por tabela).
  Future<(
    bool,
    String,
    Map<String, ({int antes, int depois, int delta})>?,
  )> restaurarBackupCompletoNaNuvem(
    String storagePath, {
    String? host,
    int? porta,
    String? usuario,
    String? senha,
    String? banco,
  }) async {
    if (kIsWeb) {
      return (false, 'Restauração na nuvem não está disponível na versão Web.', null);
    }
    if (!storagePath.startsWith('$_pastaBackupCompletoNuvem/')) {
      return (false, 'Caminho inválido — só backups completos podem ser restaurados na nuvem.', null);
    }
    if (!SupabaseService.isAvailable) {
      return (false, 'Supabase indisponível.', null);
    }

    final hostFinal = (host ?? EnvConfig.supabasePoolerHost).trim();
    final portaFinal = porta ?? EnvConfig.supabasePoolerPort;
    final usuarioFinal = usuario ?? EnvConfig.supabasePoolerUser;
    final senhaFinal = senha ?? EnvConfig.supabasePoolerPassword;
    final bancoFinal = banco ?? EnvConfig.supabaseDbNameFinal;

    if (hostFinal.isEmpty || senhaFinal.isEmpty) {
      return (
        false,
        'Conexão do banco da nuvem não configurada.\n'
        'Confira SUPABASE_POOLER_HOST e SUPABASE_POOLER_PASSWORD no .env.',
        null,
      );
    }

    // 1. Baixar o arquivo da nuvem para um temporário
    late File tempFile;
    try {
      debugPrint('>>> [BackupRestore] 📥 Baixando backup para restaurar: $storagePath');
      final bytes = await _storageAdminClient.storage
          .from(_bucketDumps)
          .download(storagePath);
      if (bytes.isEmpty) {
        return (false, 'Arquivo vazio ou não encontrado na nuvem.', null);
      }
      final tempDir = await Directory.systemTemp.createTemp('exodo_restaurar_');
      tempFile = File('${tempDir.path}${Platform.pathSeparator}${p.basename(storagePath)}');
      await tempFile.writeAsBytes(bytes, flush: true);
      final tamanhoMb = (bytes.length / 1024 / 1024).toStringAsFixed(2);
      debugPrint('>>> [BackupRestore] ✅ Arquivo baixado ($tamanhoMb MB): ${tempFile.path}');
    } catch (e) {
      return (false, 'Falha ao baixar o backup da nuvem: ${_mensagemErroStorage(e)}', null);
    }

    try {
      final psqlPath = await _findExecutable('psql');
      if (psqlPath == null) {
        return (false, 'psql não encontrado. Não é possível restaurar na nuvem.', null);
      }

      final (baseArgs, ambiente) = _conexaoPsqlNuvem(
        host: hostFinal,
        porta: portaFinal,
        usuario: usuarioFinal,
        senha: senhaFinal,
        banco: bancoFinal,
      );

      // 2. Contar linhas ANTES
      debugPrint('>>> [BackupRestore] 📊 Contando linhas antes da restauração...');
      final antes = await _contarLinhasNuvem(psqlPath, baseArgs, ambiente);
      final totalAntes = antes.values.fold<int>(0, (s, v) => s + v);
      debugPrint('>>> [BackupRestore] 📊 Total antes: $totalAntes linhas em ${antes.length} tabelas');

      // 3. Executar o .sql contra o banco da nuvem
      debugPrint('>>> [BackupRestore] 🔄 Restaurando backup completo no banco da nuvem...');
      final resultado = await _executarPsql(
        psqlPath: psqlPath,
        baseArgs: baseArgs,
        ambiente: ambiente,
        arquivo: tempFile.path,
      ).timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw TimeoutException('Restauração excedeu o tempo limite de 30 minutos'),
      );

      final stderr = (resultado.stderr as String? ?? '').trim();

      if (resultado.exitCode != 0) {
        debugPrint('>>> [BackupRestore] ❌ Erro na restauração (exitCode ${resultado.exitCode}): $stderr');
        return (
          false,
          'Erro ao restaurar no banco da nuvem: ${_mensagemErroConexaoNuvem(stderr, hostFinal, portaFinal, usuarioFinal)}',
          null,
        );
      }

      // 4. Contar linhas DEPOIS
      debugPrint('>>> [BackupRestore] 📊 Contando linhas depois da restauração...');
      final depois = await _contarLinhasNuvem(psqlPath, baseArgs, ambiente);
      final totalDepois = depois.values.fold<int>(0, (s, v) => s + v);
      debugPrint('>>> [BackupRestore] 📊 Total depois: $totalDepois linhas em ${depois.length} tabelas');

      // 5. Montar o comparativo
      final tabelasCombinadas = <String>{...antes.keys, ...depois.keys};
      final comparativo = <String, ({int antes, int depois, int delta})>{};
      for (final t in tabelasCombinadas) {
        final a = antes[t] ?? 0;
        final d = depois[t] ?? 0;
        comparativo[t] = (antes: a, depois: d, delta: d - a);
      }

      debugPrint('>>> [BackupRestore] ✅ Restauração na nuvem concluída! '
          '($totalAntes → $totalDepois linhas)');
      return (
        true,
        'Backup restaurado na nuvem com sucesso! '
            '$totalAntes linhas → $totalDepois linhas em ${tabelasCombinadas.length} tabelas.',
        comparativo,
      );
    } on TimeoutException {
      return (false, 'Restauração excedeu o tempo limite (30 min).', null);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro inesperado na restauração na nuvem: $e');
      return (false, 'Erro inesperado: $e', null);
    } finally {
      // Limpeza do arquivo temporário
      try {
        if (await tempFile.exists()) await tempFile.parent.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Conta linhas de todas as tabelas do schema public no banco conectado
  /// via psql. Devolve mapa {nome_da_tabela: contagem}.
  Future<Map<String, int>> _contarLinhasNuvem(
    String psqlPath,
    List<String> baseArgs,
    Map<String, String> ambiente,
  ) async {
    final tabelas = await _tabelasBaseDoPublico(psqlPath, baseArgs, ambiente);
    final contagens = <String, int>{};
    for (final t in tabelas) {
      try {
        final result = await _executarPsql(
          psqlPath: psqlPath,
          baseArgs: baseArgs,
          ambiente: ambiente,
          comando: 'SELECT count(*) FROM public.${_ident(t.tabela)}',
        );
        if (result.exitCode == 0) {
          contagens[t.tabela] = int.tryParse(
              (result.stdout as String).replaceAll(RegExp(r'\s'), '')) ?? 0;
        }
      } catch (e) {
        debugPrint('>>> [BackupRestore] ⚠️ Não foi possível contar ${t.tabela}: $e');
      }
    }
    return contagens;
  }
}

/// Uma coluna do esquema de um banco (lida de `pg_class`/`pg_attribute`), usada
/// para comparar o banco LOCAL com o da NUVEM e gerar o SQL que falta lá.
class _ColunaEsquema {
  final String nome;
  final String tipo;
  /// `b` = tipo base, `e` = enum, `d` = domínio, ... (pg_type.typtype)
  final String tipoKind;
  final bool obrigatoria;
  /// Expressão do DEFAULT (vazia quando a coluna não tem default).
  final String padrao;
  final bool chavePrimaria;

  const _ColunaEsquema({
    required this.nome,
    required this.tipo,
    required this.tipoKind,
    required this.obrigatoria,
    required this.padrao,
    required this.chavePrimaria,
  });
}

/// Resultado interno da comparação dos dois esquemas.
///
/// É o que os DOIS sentidos de criação e o painel da tela usam: uma única
/// fonte para "o que falta aqui" e "o que falta lá", para os números nunca
/// divergirem entre a tela de backup e o diálogo de criar tabelas.
class _ComparacaoEsquemas {
  final List<String> somenteNoLocal;
  final List<String> somenteNaNuvem;
  final List<ColunaDivergente> colunasFaltandoNoLocal;
  final List<ColunaDivergente> colunasFaltandoNaNuvem;
  final List<String> tiposDiferentes;
  final List<String> privadasDoApp;

  /// Nome que é TABELA aqui e VIEW na nuvem (e o inverso).
  final List<String> tabelaAquiEhViewNaNuvem;
  final List<String> tabelaNaNuvemEhViewAqui;

  /// Quantas tabelas DE NEGÓCIO cada lado tem (sem as privadas do app).
  final int tabelasDeNegocioLocal;
  final int tabelasDeNegocioNuvem;

  const _ComparacaoEsquemas({
    required this.somenteNoLocal,
    required this.somenteNaNuvem,
    required this.colunasFaltandoNoLocal,
    required this.colunasFaltandoNaNuvem,
    required this.tiposDiferentes,
    required this.privadasDoApp,
    required this.tabelaAquiEhViewNaNuvem,
    required this.tabelaNaNuvemEhViewAqui,
    required this.tabelasDeNegocioLocal,
    required this.tabelasDeNegocioNuvem,
  });

  /// Colunas sensíveis (senha) que faltam no local: não contam como pendência.
  List<String> get sensiveisFaltando => colunasFaltandoNoLocal
      .map((c) => c.rotulo)
      .where(BackupRestoreService.colunasSensiveis.contains)
      .toList();

  /// Colunas que faltam no local e exigem decisão (leitura da tabela mudaria).
  List<String> get decisaoFaltando => colunasFaltandoNoLocal
      .map((c) => c.rotulo)
      .where(BackupRestoreService.colunasQueExigemDecisao.contains)
      .toList();

  int get divergencias =>
      somenteNoLocal.length +
      somenteNaNuvem.length +
      colunasFaltandoNoLocal.length +
      colunasFaltandoNaNuvem.length +
      tiposDiferentes.length;

  int get divergenciasReais =>
      divergencias - sensiveisFaltando.length - decisaoFaltando.length;
}

/// Um objeto do banco (tabela, view, matview) lido direto do catálogo, com o
/// que é preciso para decidir se dá para trocar TABELA por VIEW sem risco.
class _ObjetoBanco {
  /// `relkind` do PostgreSQL: `r` tabela, `v` view, `m` matview, `p` tabela
  /// particionada, `f` tabela estrangeira.
  final String relkind;

  /// Definição da view (`pg_get_viewdef`), quando pedida.
  final String? definicao;

  /// Quantas linhas tem (só quando pedido).
  final int? linhas;

  /// Colunas da tabela local (só quando pedido) — usadas na cópia de segurança.
  final List<_ColunaEsquema> colunas;

  const _ObjetoBanco({
    required this.relkind,
    this.definicao,
    this.linhas,
    this.colunas = const [],
  });

  String get tipoLegivel => switch (relkind) {
        'r' => 'TABELA',
        'v' => 'VIEW',
        'm' => 'VIEW MATERIALIZADA',
        'p' => 'TABELA PARTICIONADA',
        'f' => 'TABELA ESTRANGEIRA',
        _ => 'objeto ($relkind)',
      };
}

/// Uma coluna que existe em um banco e não no outro (ou que existe nos dois com
/// tipos diferentes). É o detalhe fino da comparação de ESTRUTURA.
class ColunaDivergente {
  final String tabela;
  final String coluna;

  /// Tipo de cada lado (vazio quando a coluna só existe no outro).
  final String tipoLocal;
  final String tipoNuvem;

  const ColunaDivergente({
    required this.tabela,
    required this.coluna,
    this.tipoLocal = '',
    this.tipoNuvem = '',
  });

  /// Texto curto para a tela: `tabela.coluna`.
  String get rotulo => '$tabela.$coluna';

  Map<String, dynamic> toJson() => {
        'tabela': tabela,
        'coluna': coluna,
        'tipoLocal': tipoLocal,
        'tipoNuvem': tipoNuvem,
      };

  static ColunaDivergente fromJson(Map<String, dynamic> j) => ColunaDivergente(
        tabela: j['tabela']?.toString() ?? '',
        coluna: j['coluna']?.toString() ?? '',
        tipoLocal: j['tipoLocal']?.toString() ?? '',
        tipoNuvem: j['tipoNuvem']?.toString() ?? '',
      );
}

/// Retrato da ESTRUTURA dos dois bancos: quantas tabelas cada um tem, o que
/// existe só de um lado e quais colunas faltam em cada ponta.
///
/// É o que a tela de Backup e Restauração mostra para o usuário acompanhar o
/// banco local e o da nuvem (divergência de esquema é a causa de erros do tipo
/// "relation does not exist" no Supabase). As tabelas privadas do app
/// (`_exodo_sync_log`, `cache_dados`...) ficam fora da conta e aparecem em
/// [privadasDoApp], porque existem só no computador, de propósito.
class ConferenciaEsquema {
  final DateTime quando;
  final int totalLocal;
  final int totalNuvem;

  /// Tabelas que existem só em um dos lados.
  final List<String> somenteNoLocal;
  final List<String> somenteNaNuvem;

  /// Nomes que são TABELA de um lado e VIEW do outro. NÃO entram na conta de
  /// divergências: não é tabela faltando (e nem dá para criar tabela com um
  /// nome que já existe como view) — é só uma diferença de tipo de objeto.
  final List<String> objetoDiferenteNaNuvem;
  final List<String> objetoDiferenteNoLocal;

  /// Colunas que existem só em um dos lados (na direção indicada pelo nome).
  final List<ColunaDivergente> colunasFaltandoNoLocal;
  final List<ColunaDivergente> colunasFaltandoNaNuvem;

  /// Colunas que existem nos dois lados com tipos diferentes (só aviso).
  final List<String> tiposDiferentes;

  /// Tabelas privadas do app: existem só no computador e não entram na conta.
  final List<String> privadasDoApp;

  /// Motivo pelo qual um dos lados não pôde ser lido (null = leu tudo).
  final String? erroLocal;
  final String? erroNuvem;

  const ConferenciaEsquema({
    required this.quando,
    this.totalLocal = 0,
    this.totalNuvem = 0,
    this.somenteNoLocal = const [],
    this.somenteNaNuvem = const [],
    this.objetoDiferenteNaNuvem = const [],
    this.objetoDiferenteNoLocal = const [],
    this.colunasFaltandoNoLocal = const [],
    this.colunasFaltandoNaNuvem = const [],
    this.tiposDiferentes = const [],
    this.privadasDoApp = const [],
    this.erroLocal,
    this.erroNuvem,
  });

  /// Os dois lados responderam.
  bool get leuOsDois => erroLocal == null && erroNuvem == null;

  /// Quantas tabelas DE NEGÓCIO cada lado tem — o número que precisa bater nos
  /// dois lados.
  ///
  /// É exatamente o que [totalLocal]/[totalNuvem] guardam: as privadas do app
  /// (`_exodo_sync_log`, `_sync_controle`, `cache_dados`) já foram descontadas
  /// na comparação, porque existem só no computador, de propósito. Os getters
  /// existem para o nome do número ficar explícito na tela e no teste: "tabela
  /// de negócio" é o que dá para igualar com a nuvem.
  int get tabelasDeNegocioLocal => totalLocal;
  int get tabelasDeNegocioNuvem => totalNuvem;

  /// Total de divergências de estrutura (tabelas + colunas + tipos).
  int get divergencias =>
      somenteNoLocal.length +
      somenteNaNuvem.length +
      colunasFaltandoNoLocal.length +
      colunasFaltandoNaNuvem.length +
      tiposDiferentes.length;

  /// Colunas sensíveis (ex.: `usuarios.senha`) que faltam no local: o app não
  /// as cria sozinho, de propósito, então elas não contam como pendência.
  List<String> get sensiveisFaltando => colunasFaltandoNoLocal
      .map((c) => c.rotulo)
      .where(BackupRestoreService.colunasSensiveis.contains)
      .toList();

  /// Colunas que faltam no local mas exigem decisão do usuário, porque criá-las
  /// muda como o app LÊ a tabela (hoje só `empresas.empresa_id`). Também não
  /// contam como pendência automática — ver `colunasQueExigemDecisao`.
  List<String> get decisaoFaltando => colunasFaltandoNoLocal
      .map((c) => c.rotulo)
      .where(BackupRestoreService.colunasQueExigemDecisao.contains)
      .toList();

  /// Colunas que só entram com a autorização do usuário: as sensíveis (senha,
  /// login/segredo) e as que mudam como o app LÊ a tabela.
  List<String> get autorizaveisFaltando => [
        ...sensiveisFaltando,
        ...decisaoFaltando,
      ];

  /// Divergências que realmente pedem ação (sem as que dependem de autorização).
  int get divergenciasReais =>
      divergencias - sensiveisFaltando.length - decisaoFaltando.length;

  /// Estruturas equivalentes (com os dois lados lidos e nada pendente).
  bool get iguais => leuOsDois && divergenciasReais == 0;

  /// Quem está atrasado — a resposta a "onde está o problema?"
  ///
  /// Sem isso o usuário vê "101 colunas faltando" e não sabe de que lado criar.
  String get veredito {
    if (!leuOsDois) return 'Sem ler os dois bancos não dá para dizer quem está atrasado.';
    if (divergenciasReais == 0) {
      return 'Os dois bancos estão iguais na estrutura.';
    }

    final partes = <String>[];
    final colunasUteisLocal = colunasFaltandoNoLocal.length -
        sensiveisFaltando.length -
        decisaoFaltando.length;
    final faltamAqui = somenteNaNuvem.length + colunasUteisLocal;
    final faltaLa = somenteNoLocal.length + colunasFaltandoNaNuvem.length;

    if (faltamAqui > 0) {
      partes.add('o LOCAL está atrasado em ${somenteNaNuvem.length} tabela(s) e '
          '$colunasUteisLocal coluna(s) (botão "⬇️ Criar NO LOCAL")');
    }
    if (faltaLa > 0) {
      partes.add('a NUVEM está atrasada em ${somenteNoLocal.length} tabela(s) e '
          '${colunasFaltandoNaNuvem.length} coluna(s) (botão "⬆️ Criar NA NUVEM")');
    }
    if (partes.isEmpty) {
      return 'As diferenças são só de TIPO de coluna — o app não altera tipo '
          'automaticamente, para não estragar dado existente.';
    }
    return 'Quem está atrasado: ${partes.join('  |  ')}.';
  }

  /// Frase de uma linha para o topo do painel.
  String get resumo {
    if (!leuOsDois) {
      return [
        if (erroLocal != null) erroLocal!,
        if (erroNuvem != null) erroNuvem!,
      ].join(' • ');
    }
    return 'Local $totalLocal tabela(s) • Nuvem $totalNuvem tabela(s) • '
        '$divergenciasReais divergência(s)'
        '${sensiveisFaltando.isNotEmpty ? ' (+${sensiveisFaltando.length} coluna(s) sensível(is) fora da conta)' : ''}'
        '${decisaoFaltando.isNotEmpty ? ' (+${decisaoFaltando.length} coluna(s) que precisam de decisão)' : ''}';
  }

  /// Relatório em texto (salvo em [BackupRestoreService.arquivoConferenciaEsquemaTxt]).
  String get relatorioTexto {
    final b = StringBuffer()
      ..writeln('SISTEMA ÊXODO — ESTRUTURA DOS BANCOS (LOCAL × NUVEM)')
      ..writeln('Conferido em: $quando')
      ..writeln('')
      ..writeln('Banco LOCAL : $totalLocal tabela(s)')
      ..writeln('Banco NUVEM : $totalNuvem tabela(s)')
      ..writeln('');

    if (erroLocal != null) b.writeln('❌ Local : $erroLocal');
    if (erroNuvem != null) b.writeln('❌ Nuvem : $erroNuvem');
    if (erroLocal != null || erroNuvem != null) {
      b.writeln('');
      b.writeln('Sem ler os dois lados não é possível afirmar o que falta.');
      return b.toString();
    }

    b.writeln('Divergências: $divergenciasReais'
        '${sensiveisFaltando.isNotEmpty ? ' (+${sensiveisFaltando.length} coluna(s) sensível(is), fora da conta)' : ''}'
        '${decisaoFaltando.isNotEmpty ? ' (+${decisaoFaltando.length} coluna(s) que precisam de decisão)' : ''}');
    b.writeln(veredito);
    b.writeln('');

    void lista(String titulo, List<String> itens) {
      b.writeln('$titulo (${itens.length})');
      if (itens.isEmpty) {
        b.writeln('  — nenhuma');
      } else {
        for (final i in itens) {
          b.writeln('  • $i');
        }
      }
      b.writeln('');
    }

    lista('Tabelas que existem SÓ no banco local', somenteNoLocal);
    lista('Tabelas que existem SÓ na nuvem', somenteNaNuvem);
    lista('Colunas que faltam NO LOCAL',
        colunasFaltandoNoLocal.map((c) => '${c.rotulo} (nuvem: ${c.tipoNuvem})').toList());
    lista('Colunas que faltam NA NUVEM',
        colunasFaltandoNaNuvem.map((c) => '${c.rotulo} (local: ${c.tipoLocal})').toList());
    lista('Colunas com tipo diferente (não são alteradas)', tiposDiferentes);
    lista('Tabela aqui e VIEW na nuvem (nada a criar)', objetoDiferenteNaNuvem);
    lista('View aqui e TABELA na nuvem (nada a criar)', objetoDiferenteNoLocal);
    if (sensiveisFaltando.isNotEmpty) {
      b.writeln('Colunas SENSÍVEIS que faltam no local (${sensiveisFaltando.length}) '
          '— o app não cria sozinho:');
      for (final s in sensiveisFaltando) {
        b.writeln('  • $s');
      }
      b.writeln('');
    }
    if (decisaoFaltando.isNotEmpty) {
      b.writeln('Colunas que PRECISAM DE DECISÃO (${decisaoFaltando.length}) '
          '— criá-las muda como o app lê a tabela, então o app não cria sozinho:');
      for (final d in decisaoFaltando) {
        b.writeln('  • $d');
      }
      b.writeln('');
    }
    final autorizaveis = autorizaveisFaltando;
    if (autorizaveis.isNotEmpty) {
      b.writeln('Colunas que precisam da SUA AUTORIZAÇÃO (${autorizaveis.length}) '
          '— o app não cria sozinho (segredo/login ou muda como ele lê a tabela), '
          'mas cria se você marcar a opção no diálogo ou rodar o SQL salvo em disco:');
      for (final a in autorizaveis) {
        b.writeln('  • $a');
      }
      b.writeln('');
    }
    lista('Tabelas privadas do app (ficam fora da conta)', privadasDoApp);

    b.writeln('COMO IGUALAR');
    b.writeln('  • Falta na NUVEM  → Backup e Restauração → "Criar Tabelas no Supabase".');
    b.writeln('  • Falta no LOCAL  → Backup e Restauração → "Criar no Local o que falta".');
    b.writeln('  Nenhuma das duas apaga dados: só cria tabela nova (vazia) e coluna nova.');
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'quando': quando.toIso8601String(),
        'totalLocal': totalLocal,
        'totalNuvem': totalNuvem,
        'somenteNoLocal': somenteNoLocal,
        'somenteNaNuvem': somenteNaNuvem,
        'objetoDiferenteNaNuvem': objetoDiferenteNaNuvem,
        'objetoDiferenteNoLocal': objetoDiferenteNoLocal,
        'colunasFaltandoNoLocal': colunasFaltandoNoLocal.map((c) => c.toJson()).toList(),
        'colunasFaltandoNaNuvem': colunasFaltandoNaNuvem.map((c) => c.toJson()).toList(),
        'tiposDiferentes': tiposDiferentes,
        'privadasDoApp': privadasDoApp,
        'erroLocal': erroLocal,
        'erroNuvem': erroNuvem,
      };

  static List<ColunaDivergente> _colunas(dynamic lista) => (lista as List? ?? const [])
      .whereType<Map>()
      .map((m) => ColunaDivergente.fromJson(Map<String, dynamic>.from(m)))
      .toList();

  static List<String> _textos(dynamic lista) =>
      (lista as List? ?? const []).map((e) => e.toString()).toList();

  static ConferenciaEsquema fromJson(Map<String, dynamic> j) => ConferenciaEsquema(
        quando: DateTime.tryParse(j['quando']?.toString() ?? '') ?? DateTime.now(),
        totalLocal: int.tryParse(j['totalLocal']?.toString() ?? '') ?? 0,
        totalNuvem: int.tryParse(j['totalNuvem']?.toString() ?? '') ?? 0,
        somenteNoLocal: _textos(j['somenteNoLocal']),
        somenteNaNuvem: _textos(j['somenteNaNuvem']),
        objetoDiferenteNaNuvem: _textos(j['objetoDiferenteNaNuvem']),
        objetoDiferenteNoLocal: _textos(j['objetoDiferenteNoLocal']),
        colunasFaltandoNoLocal: _colunas(j['colunasFaltandoNoLocal']),
        colunasFaltandoNaNuvem: _colunas(j['colunasFaltandoNaNuvem']),
        tiposDiferentes: _textos(j['tiposDiferentes']),
        privadasDoApp: _textos(j['privadasDoApp']),
        erroLocal: j['erroLocal']?.toString(),
        erroNuvem: j['erroNuvem']?.toString(),
      );
}
