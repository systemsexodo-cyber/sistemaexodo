import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, BucketOptions;
import 'data_service.dart';
import 'database_service.dart';
import 'env_config.dart';
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
        await SupabaseService.instance.client.storage
            .from(bucketName)
            .uploadBinary(storagePath, bytes,
                fileOptions: const FileOptions(upsert: true));
      } catch (e) {
        // Se o bucket não existe, tentar criá-lo
        debugPrint('>>> [BackupRestore] ⚠️ Erro no upload, tentando criar bucket...');
        try {
          await SupabaseService.instance.client.storage.createBucket(
            bucketName,
            const BucketOptions(public: false),
          );
          await SupabaseService.instance.client.storage
              .from(bucketName)
              .uploadBinary(storagePath, bytes,
                  fileOptions: const FileOptions(upsert: true));
        } catch (e2) {
          return (false, 'Erro ao criar bucket ou fazer upload: $e2', null);
        }
      }

      debugPrint('>>> [BackupRestore] ✅ Backup enviado para nuvem: $storagePath');

      // 3. Registrar no histórico
      await _registrarNoHistorico('☁️ $fileName', bytes.length);

      return (true, 'Backup enviado para a nuvem com sucesso!', storagePath);
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao enviar backup para nuvem: $e');
      return (false, 'Erro ao enviar backup: $e', null);
    }
  }

  /// Lista backups salvos na nuvem para a empresa atual
  Future<List<Map<String, dynamic>>> listarBackupsNuvem() async {
    try {
      final empresaId = _dataService.currentEmpresaId;
      if (empresaId == null) return [];

      const bucketName = 'backups';
      final prefix = 'backups/$empresaId/';

      final files = await SupabaseService.instance.client.storage
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
      final bytes = await SupabaseService.instance.client.storage
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
      await SupabaseService.instance.client.storage
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

      final result = await Process.run(
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

      // Executar o comando com a senha via variável de ambiente
      final environment = Map<String, String>.from(Platform.environment);
      environment['PGPASSWORD'] = dbPass;

      final result = await Process.run(
        executable,
        args,
        environment: environment,
        runInShell: true,
      ).timeout(
        const Duration(minutes: 30),
        onTimeout: () {
          throw TimeoutException('Restauração excedeu o tempo limite de 30 minutos');
        },
      );

      if (result.exitCode == 0) {
        debugPrint('>>> [BackupRestore] ✅ Dump restaurado com sucesso!');
        return (true, 'Dump restaurado com sucesso! Reinicie o app para carregar os dados.');
      } else {
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

  /// Procura um executável no PATH do sistema
  Future<String?> _findExecutable(String name) async {
    try {
      final result = await Process.run(
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
    return null;
  }

  // ============================================================
  // DUMP POSTGRESQL NA NUVEM (Supabase Storage)
  // ============================================================

  /// Faz upload de um arquivo dump PostgreSQL (.dump/.sql) para o Supabase Storage
  /// Retorna (sucesso, mensagem)
  Future<(bool, String)> uploadDumpNaNuvem(File dumpFile) async {
    try {
      final empresaId = _dataService.currentEmpresaId;
      if (empresaId == null) return (false, 'Empresa não selecionada');
      if (!SupabaseService.isAvailable) return (false, 'Supabase não disponível');

      final fileName = p.basename(dumpFile.path);
      final fileBytes = await dumpFile.readAsBytes();
      final fileSize = fileBytes.length;

      debugPrint('>>> [BackupRestore] 📤 Enviando dump para nuvem: $fileName (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      // Usar bucket 'backups' existente com subpasta 'dumps'
      const bucketName = 'backups';
      final now = DateTime.now();
      final dataStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final horaStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final cleanName = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final storagePath = 'dumps/$empresaId/${cleanName.replaceAll('.dump', '')}_$dataStr$horaStr.dump';

      try {
        await SupabaseService.instance.client.storage
            .from(bucketName)
            .uploadBinary(storagePath, fileBytes,
                fileOptions: const FileOptions(upsert: true));
      } catch (e) {
        return (false, 'Erro ao enviar dump: $e');
      }

      debugPrint('>>> [BackupRestore] ✅ Dump enviado para nuvem: $storagePath');
      return (true, 'Dump enviado com sucesso! ($storagePath)');
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao enviar dump: $e');
      return (false, 'Erro ao enviar dump: $e');
    }
  }

  /// Lista dumps PostgreSQL salvos na nuvem para a empresa atual
  Future<List<Map<String, dynamic>>> listarDumpsNuvem() async {
    try {
      final empresaId = _dataService.currentEmpresaId;
      if (empresaId == null || !SupabaseService.isAvailable) return [];

      const bucketName = 'backups';
      final prefix = 'dumps/$empresaId/';

      final files = await SupabaseService.instance.client.storage
          .from(bucketName)
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

  /// Faz download de um dump da nuvem e salva localmente
  Future<(bool, String, String?)> downloadDumpDaNuvem(String storagePath) async {
    try {
      if (!SupabaseService.isAvailable) return (false, 'Supabase não disponível', null);

      debugPrint('>>> [BackupRestore] 📥 Baixando dump da nuvem: $storagePath');

      final bytes = await SupabaseService.instance.client.storage
          .from('backups')
          .download(storagePath);

      // Salvar em C:\ExodoBackups\{empresaId}\
      final empresaId = _dataService.currentEmpresaId ?? 'default';
      final backupDir = Directory('C:\\ExodoBackups\\$empresaId');
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
      await SupabaseService.instance.client.storage
          .from('backups')
          .remove([storagePath]);
      debugPrint('>>> [BackupRestore] 🗑️ Dump removido da nuvem: $storagePath');
      return true;
    } catch (e) {
      debugPrint('>>> [BackupRestore] ❌ Erro ao remover dump: $e');
      return false;
    }
  }
}
