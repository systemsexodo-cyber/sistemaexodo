import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'data_service.dart';
import 'database_service.dart';
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
}
