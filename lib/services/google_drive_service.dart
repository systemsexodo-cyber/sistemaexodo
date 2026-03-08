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

import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._();
  GoogleDriveService._();

  static const String _keyUltimoBackup = 'google_drive_ultimo_backup';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '767835275358-ar47lvn9uboh1b12s2tvqli7epq8ttu0.apps.googleusercontent.com',
    scopes: [
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveMetadataReadonlyScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  bool _isServiceAccount = false;

  bool get isServiceAccount => _isServiceAccount;

  Future<bool> login({bool silencioso = false}) async {
    try {
      // 1. Tentar Conta de Serviço primeiro (para login "fixo")
      if (await _tentarLoginServiceAccount()) {
        debugPrint('>>> [GoogleDrive] ✅ Autenticado via Conta de Serviço (Fixo)');
        return true;
      }

      // 2. Se falhar ou não existir, tentar login do usuário (OAuth2)
      if (silencioso) {
        _currentUser = await _googleSignIn.signInSilently();
      } else {
        _currentUser = await _googleSignIn.signIn();
      }
      
      if (_currentUser == null) return false;

      final authHeaders = await _currentUser!.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      _driveApi = drive.DriveApi(authenticateClient);
      _isServiceAccount = false;
      
      return true;
    } catch (e) {
      debugPrint('>>> [GoogleDrive] Erro no login (${silencioso ? 'silencioso' : 'manual'}): $e');
      return false;
    }
  }

  Future<bool> _tentarLoginServiceAccount() async {
    if (kIsWeb) return false;

    try {
      // Procurar arquivo na raiz do projeto ou junto ao executável
      final baseDir = Directory.current.path;
      final paths = [
        p.join(baseDir, 'gdrive_service_account.json'),
        p.join(baseDir, 'firebase-credentials.json'),
        p.join(baseDir, 'backend_nfce', 'firebase-credentials.json'),
        'gdrive_service_account.json',
        'firebase-credentials.json',
      ];

      File? file;
      for (final path in paths) {
        final f = File(path);
        if (f.existsSync()) {
          file = f;
          break;
        }
      }

      if (file == null) return false;

      final jsonContent = await file.readAsString();
      final accountJson = jsonDecode(jsonContent);
      final credentials = auth.ServiceAccountCredentials.fromJson(accountJson);
      
      final scopes = [drive.DriveApi.driveFileScope];
      final client = await auth.clientViaServiceAccount(credentials, scopes);
      
      _driveApi = drive.DriveApi(client);
      _isServiceAccount = true;
      _currentUser = null; // Limpa usuário OAuth se estiver usando Service Account
      
      return true;
    } catch (e) {
      debugPrint('>>> [GoogleDrive] Falha ao carregar Conta de Serviço: $e');
      return false;
    }
  }

  Future<void> logout() async {
    if (!_isServiceAccount) {
      await _googleSignIn.signOut();
    }
    _currentUser = null;
    _driveApi = null;
    _isServiceAccount = false;
  }

  bool get isLoggedIn => _currentUser != null || _isServiceAccount;
  String? get userEmail => _isServiceAccount ? 'Conta de Serviço (Fixo)' : _currentUser?.email;

  /// Verifica se é necessário realizar um backup automático (intervalo de 24h)
  Future<void> verificarERealizarBackupAutomatico() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ultimoBackupStr = prefs.getString(_keyUltimoBackup);
      
      if (ultimoBackupStr != null) {
        final ultimoBackup = DateTime.parse(ultimoBackupStr);
        final agora = DateTime.now();
        final diferenca = agora.difference(ultimoBackup);
        
        // Se o último backup foi há menos de 24 horas, não faz nada
        if (diferenca.inHours < 24) {
          debugPrint('>>> [GoogleDrive] Backup automático ignorado (Último backup há ${diferenca.inHours}h)');
          return;
        }
      }

      debugPrint('>>> [GoogleDrive] Iniciando backup automático (24h passadas)...');
      
      // Tenta login silencioso primeiro
      if (_googleSignIn.currentUser == null) {
        try {
          // Tenta silent login apenas UMA VEZ.
          final user = await _googleSignIn.signInSilently().timeout(const Duration(seconds: 5));
          if (user != null) {
            final authHeaders = await user.authHeaders;
            final authenticateClient = GoogleAuthClient(authHeaders);
            _driveApi = drive.DriveApi(authenticateClient);
            _currentUser = user;
          } else {
             debugPrint('>>> [GoogleDrive] Silent login não retornou usuário.');
             return; // Aborta backup automático se não logou
          }
        } catch (e) {
          debugPrint('>>> [GoogleDrive] Silent login falhou (possível erro de rede/sessão): $e');
          return; // Aborta backup automático em caso de erro
        }
      }

      // Se chegamos aqui e temos _driveApi, prossegue
      if (_driveApi != null) {
        final resultado = await realizarBackupTodasEmpresas();
        if (resultado['sucesso'] == true) {
          debugPrint('>>> [GoogleDrive] Backup automático concluído com sucesso!');
        }
      } else {
         debugPrint('>>> [GoogleDrive] Backup automático cancelado: Necessário login manual.');
      }
    } catch (e) {
      debugPrint('>>> [GoogleDrive] Erro no backup automático: $e');
    }
  }

  /// Cria ou recupera uma pasta específica no Google Drive seguindo um caminho (ex: "Contabilidade/CNPJ/Mes")
  Future<String?> _getOrCreateFolderPath(String path, {String? parentId}) async {
    if (_driveApi == null) return null;

    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    String? currentParentId = parentId;

    for (var folderName in parts) {
      try {
        String query = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
        if (currentParentId != null) {
          query += " and '$currentParentId' in parents";
        }

        final folderList = await _driveApi!.files.list(
          q: query,
          spaces: 'drive',
        );

        if (folderList.files != null && folderList.files!.isNotEmpty) {
          currentParentId = folderList.files!.first.id;
        } else {
          // Criar nova pasta
          final folder = drive.File()
            ..name = folderName
            ..mimeType = 'application/vnd.google-apps.folder'
            ..parents = currentParentId != null ? [currentParentId] : null;

          final createdFolder = await _driveApi!.files.create(folder);
          currentParentId = createdFolder.id;
        }
      } catch (e) {
        debugPrint('>>> [GoogleDrive] Erro ao navegar/criar pasta $folderName: $e');
        return null;
      }
    }
    return currentParentId;
  }

  /// Salva um conteúdo (XML ou Texto) no Google Drive em uma pasta específica
  Future<bool> salvarArquivo({
    required String nomeArquivo,
    required String conteudo,
    required String caminhoPasta,
    String mimeType = 'text/plain',
  }) async {
    // Tenta login silencioso se não estiver logado
    if (_driveApi == null) {
      final ok = await login(silencioso: true);
      if (!ok) {
        debugPrint('>>> [GoogleDrive] Login silencioso falhou ao tentar salvar arquivo.');
        return false;
      }
    }

    try {
      // 1. Garantir pasta principal do sistema
      final rootFolderId = await _getOrCreateBackupFolder();
      if (rootFolderId == null) return false;

      // 2. Garantir sub-caminho solicitado
      final folderId = await _getOrCreateFolderPath(caminhoPasta, parentId: rootFolderId);
      if (folderId == null) return false;

      // 3. Preparar mídia
      final bytes = utf8.encode(conteudo);
      final stream = Stream.value(bytes);
      final media = drive.Media(stream, bytes.length);

      // 4. Verificar se arquivo já existe para atualizar ou criar novo
      final fileList = await _driveApi!.files.list(
        q: "name = '$nomeArquivo' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );

      final fileMetadata = drive.File()
        ..name = nomeArquivo
        ..parents = (fileList.files == null || fileList.files!.isEmpty) ? [folderId] : null;

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        // Atualizar existente
        await _driveApi!.files.update(fileMetadata, fileList.files!.first.id!, uploadMedia: media);
        debugPrint('>>> [GoogleDrive] Arquivo atualizado: $nomeArquivo');
      } else {
        // Criar novo
        await _driveApi!.files.create(fileMetadata, uploadMedia: media);
        debugPrint('>>> [GoogleDrive] Novo arquivo criado: $nomeArquivo');
      }

      return true;
    } catch (e) {
      debugPrint('>>> [GoogleDrive] Erro ao salvar arquivo no Drive: $e');
      return false;
    }
  }

  /// Cria ou recupera a pasta de backup no Google Drive
  Future<String?> _getOrCreateBackupFolder() async {
    if (_driveApi == null) return null;

    // ID da pasta fornecido pelo usuário via Drive Link
    const String folderIdFixa = '1tGm8ZxMuTWFfHaJyrx3VveYzYF_jpZcQ';
    const String folderNameDefault = 'SistemaExodo_Backups';
    
    try {
      // 1. Tentar primeiro o ID fixo que o usuário compartilhou
      try {
         final fixa = await _driveApi!.files.get(folderIdFixa) as drive.File;
         if (fixa.id != null) {
           debugPrint('>>> [GoogleDrive] ✅ Usando pasta raiz fixa: ${fixa.name}');
           return fixa.id;
         }
      } catch (e) {
         debugPrint('>>> [GoogleDrive] Pasta fixa não encontrada ou sem acesso, buscando por nome...');
      }

      // 2. Fallback: Buscar por nome
      final folderList = await _driveApi!.files.list(
        q: "name = '$folderNameDefault' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
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

      // Salvar timestamp do backup bem-sucedido
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUltimoBackup, DateTime.now().toIso8601String());

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
