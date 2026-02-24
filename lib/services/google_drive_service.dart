import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'firebase_service.dart';
import '../models/empresa.dart';
import 'data_service.dart';

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._();
  GoogleDriveService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveMetadataReadonlyScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;

  Future<bool> login() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser == null) return false;

      final authHeaders = await _currentUser!.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      _driveApi = drive.DriveApi(authenticateClient);
      
      return true;
    } catch (e) {
      debugPrint('>>> [GoogleDrive] Erro no login: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _driveApi = null;
  }

  bool get isLoggedIn => _currentUser != null;
  String? get userEmail => _currentUser?.email;

  /// Cria ou recupera a pasta de backup no Google Drive
  Future<String?> _getOrCreateBackupFolder() async {
    if (_driveApi == null) return null;

    const folderName = 'SistemaExodo_Backups';
    
    try {
      final folderList = await _driveApi!.files.list(
        q: "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
      );

      if (folderList.files != null && folderList.files!.isNotEmpty) {
        return folderList.files!.first.id;
      }

      // Criar nova pasta
      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final createdFolder = await _driveApi!.files.create(folder);
      return createdFolder.id;
    } catch (e) {
      debugPrint('>>> [GoogleDrive] Erro ao obter/criar pasta: $e');
      return null;
    }
  }

  /// Realiza o backup de todas as empresas
  Future<Map<String, dynamic>> realizarBackupTodasEmpresas() async {
    if (_driveApi == null) {
      final ok = await login();
      if (!ok) return {'sucesso': false, 'mensagem': 'Login falhou'};
    }

    try {
      final parentFolderId = await _getOrCreateBackupFolder();
      if (parentFolderId == null) return {'sucesso': false, 'mensagem': 'Não foi possível acessar a pasta de backup'};

      // 1. Obter todas as empresas
      final empresas = await FirebaseService.instance.carregarEmpresas();
      if (empresas.isEmpty) return {'sucesso': false, 'mensagem': 'Nenhuma empresa encontrada'};

      // 2. Pasta para o backup atual (por data)
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final dailyFolderName = 'Backup_$timestamp';
      
      final dailyFolder = drive.File()
        ..name = dailyFolderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentFolderId];

      final createdDailyFolder = await _driveApi!.files.create(dailyFolder);
      final dailyFolderId = createdDailyFolder.id!;

      int empresasSucesso = 0;
      int empresasFalha = 0;

      // 3. Iterar e exportar cada empresa
      for (final empresa in empresas) {
        try {
          debugPrint('>>> [GoogleDrive] Exportando dados da empresa: ${empresa.nomeExibicao} (${empresa.id})');
          
          // Carregar todos os dados do Firebase para esta empresa
          final dados = await FirebaseService.instance.carregarTudoDoFirebase(empresa.id);
          
          final jsonString = jsonEncode({
            'empresa': empresa.toMap(),
            'dados': dados,
            'data_backup': DateTime.now().toIso8601String(),
          });

          final fileName = 'Backup_${empresa.slug}_$timestamp.json';
          final bytes = utf8.encode(jsonString);
          final stream = Stream.value(bytes);
          final media = drive.Media(stream, bytes.length);

          final fileToUpload = drive.File()
            ..name = fileName
            ..parents = [dailyFolderId];

          await _driveApi!.files.create(fileToUpload, uploadMedia: media);
          empresasSucesso++;
        } catch (e) {
          debugPrint('>>> [GoogleDrive] Erro no backup da empresa ${empresa.id}: $e');
          empresasFalha++;
        }
      }

      return {
        'sucesso': true,
        'mensagem': 'Backup concluído!',
        'detalhes': {
          'total': empresas.length,
          'sucesso': empresasSucesso,
          'falha': empresasFalha,
          'pasta': dailyFolderName,
        }
      };
    } catch (e) {
      debugPrint('>>> [GoogleDrive] Erro geral no backup: $e');
      return {'sucesso': false, 'mensagem': 'Erro inesperado: $e'};
    }
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}
