import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'data_service.dart';
import 'database_service.dart';
import 'env_config.dart';
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
}
