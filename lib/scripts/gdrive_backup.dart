import 'dart:convert';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

/// Script CLI para upload de backup do projeto para Google Drive
void main(List<String> args) async {
  if (args.length < 1) {
    print('Uso: dart lib/scripts/gdrive_backup.dart <arquivo_zip> [nome_amigavel] [--target-path=Caminho/Da/Pasta]');
    exit(1);
  }

  final zipFilePath = args[0];
  final friendlyName = args.length > 1 && !args[1].startsWith('--') ? args[1] : p.basename(zipFilePath);
  
  // Nova opção: --target-path="Contabilidade/Empresa/Mes"
  String? targetPathStr;
  for (var arg in args) {
    if (arg.startsWith('--target-path=')) {
      targetPathStr = arg.split('=')[1];
    }
  }
  
  // Caminhos para credenciais
  final serviceAccountPath = p.join(Directory.current.path, 'gdrive_service_account.json');
  final clientIdPath = p.join(Directory.current.path, 'gdrive_client_id.json');
  final tokenPath = p.join(Directory.current.path, 'gdrive_token.json');

  final file = File(zipFilePath);
  if (!file.existsSync()) {
    print('Erro: Arquivo não encontrado em $zipFilePath');
    exit(1);
  }

  AutoRefreshingAuthClient? client;
  final scopes = [drive.DriveApi.driveFileScope];

  // 1. Tentar Conta de Serviço
  final serviceAccountFile = File(serviceAccountPath);
  if (serviceAccountFile.existsSync()) {
    print('✅ Usando Conta de Serviço (gdrive_service_account.json)...');
    try {
      final accountJson = jsonDecode(serviceAccountFile.readAsStringSync());
      final credentials = ServiceAccountCredentials.fromJson(accountJson);
      client = await clientViaServiceAccount(credentials, scopes);
    } catch (e) {
      print('❌ Erro ao ler Conta de Serviço: $e');
    }
  }

  // 2. Se não houver Conta de Serviço, tentar OAuth2
  if (client == null) {
    final clientIdFile = File(clientIdPath);
    if (!clientIdFile.existsSync()) {
      print('Erro: Nenhuma credencial encontrada (service_account ou client_id).');
      exit(1);
    }

    print('ℹ️ Usando OAuth2 (Conta Pessoal)...');
    final clientIdJson = jsonDecode(clientIdFile.readAsStringSync());
    final clientId = ClientId(
      clientIdJson['installed']?['client_id'] ?? clientIdJson['web']?['client_id'],
      clientIdJson['installed']?['client_secret'] ?? clientIdJson['web']?['client_secret'],
    );

    final tokenFile = File(tokenPath);
    if (tokenFile.existsSync()) {
      print('Usando token de acesso salvo...');
      final credentials = AccessCredentials.fromJson(jsonDecode(tokenFile.readAsStringSync()));
      client = autoRefreshingClient(clientId, credentials, http.Client());
    } else {
      print('Iniciando primeiro login via navegador...');
      client = await clientViaUserConsent(clientId, scopes, (url) async {
        print('\n==========================================================');
        print('POR FAVOR, AUTORIZE O ACESSO NO SEU NAVEGADOR:');
        print(url);
        print('==========================================================\n');
      });
      tokenFile.writeAsStringSync(jsonEncode(client.credentials.toJson()));
    }
  }

  final driveApi = drive.DriveApi(client);

  try {
    String? currentParentId;
    
    if (targetPathStr != null && targetPathStr.isNotEmpty) {
      print('Navegando pela estrutura: $targetPathStr');
      final parts = targetPathStr.split('/').where((p) => p.isNotEmpty).toList();
      for (var folderName in parts) {
        currentParentId = await _getOrCreateFolder(driveApi, folderName, parentId: currentParentId);
      }
    } else {
      print('Localizando pasta de backup padrão...');
      currentParentId = await _getOrCreateFolder(driveApi, 'SistemaExodo_Projeto_Backups');
    }

    print('Enviando arquivo: ${p.basename(zipFilePath)} (${(file.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB)');
    
    final media = drive.Media(file.openRead(), file.lengthSync());
    final driveFile = drive.File()
      ..name = friendlyName
      ..parents = currentParentId != null ? [currentParentId] : null;

    final result = await driveApi.files.create(
      driveFile, 
      uploadMedia: media,
    );
    
    print('✅ Backup concluído com sucesso!');
    print('ID do Arquivo: ${result.id}');
  } on drive.DetailedApiRequestError catch (e) {
    print('❌ Erro da API do Google Drive:');
    print('   Status: ${e.status}');
    print('   Mensagem: ${e.message}');
    if (e.status == 403 && (e.message?.contains('storage quota') ?? false)) {
      print('\n==========================================================');
      print('⚠️ PROBLEMA DE COTA DETECTADO!');
      print('Sua Conta de Serviço (Service Account) não tem espaço próprio.');
      print('Para resolver:');
      print('1. Crie uma pasta no SEU Google Drive pessoal.');
      print('2. Compartilhe essa pasta com o email: backupprojetoexodo@natural-element-485101-c9.iam.gserviceaccount.com');
      print('3. Dê permissão de "Editor".');
      print('4. O script tentará localizar a pasta automaticamente pelo nome.');
      print('==========================================================\n');
    }
    exit(1);
  } catch (e) {
    print('❌ Erro durante o upload: $e');
    if (e.toString().contains('401') || e.toString().contains('403')) {
      print('DICA: Se o erro for de permissão, tente apagar o arquivo gdrive_token.json e rodar novamente.');
    }
    exit(1);
  } finally {
    client.close();
  }
}

Future<String?> _getOrCreateFolder(drive.DriveApi driveApi, String folderName, {String? parentId}) async {
  String query = "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
  if (parentId != null) {
    query += " and '$parentId' in parents";
  }

  final folderList = await driveApi.files.list(
    q: query,
    spaces: 'drive',
    supportsAllDrives: true,
    includeItemsFromAllDrives: true,
  );

  if (folderList.files != null && folderList.files!.isNotEmpty) {
    return folderList.files!.first.id;
  }

  print('Criando pasta "$folderName" no seu Drive...');
  final folder = drive.File()
    ..name = folderName
    ..mimeType = 'application/vnd.google-apps.folder'
    ..parents = parentId != null ? [parentId] : null;

  try {
    final createdFolder = await driveApi.files.create(folder);
    return createdFolder.id;
  } catch (e) {
    print('⚠️ Não foi possível criar a pasta "$folderName": $e');
    return null;
  }
}
