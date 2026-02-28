import 'dart:convert';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Script CLI para upload de backup do projeto para Google Drive via OAuth2 (Conta Pessoal)
void main(List<String> args) async {
  if (args.length < 2) {
    print('Uso: dart lib/scripts/gdrive_backup.dart <arquivo_zip> <client_id_json>');
    exit(1);
  }

  final zipFilePath = args[0];
  final clientIdPath = args[1];
  final tokenPath = p.join(p.dirname(clientIdPath), 'gdrive_token.json');

  final file = File(zipFilePath);
  if (!file.existsSync()) {
    print('Erro: Arquivo ZIP não encontrado em $zipFilePath');
    exit(1);
  }

  final clientIdFile = File(clientIdPath);
  if (!clientIdFile.existsSync()) {
    print('Erro: Arquivo gdrive_client_id.json não encontrado.');
    print('Crie um ID de Cliente OAuth para "App de Desktop" no Google Cloud Console.');
    exit(1);
  }

  final clientIdJson = jsonDecode(clientIdFile.readAsStringSync());
  final clientId = ClientId(
    clientIdJson['installed']['client_id'],
    clientIdJson['installed']['client_secret'],
  );

  final scopes = [drive.DriveApi.driveFileScope];

  AutoRefreshingAuthClient client;

  final tokenFile = File(tokenPath);
  if (tokenFile.existsSync()) {
    print('Usando token de acesso salvo...');
    final credentials = AccessCredentials.fromJson(jsonDecode(tokenFile.readAsStringSync()));
    client = autoRefreshingClient(clientId, credentials, HttpClient());
  } else {
    print('Iniciando primeiro login via navegador...');
    client = await clientViaUserConsent(clientId, scopes, (url) async {
      print('\n==========================================================');
      print('POR FAVOR, AUTORIZE O ACESSO NO SEU NAVEGADOR:');
      print(url);
      print('==========================================================\n');
      
      // Tenta abrir o navegador automaticamente
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      }
    });
    
    // Salva as credenciais para a próxima vez
    tokenFile.writeAsStringSync(jsonEncode(client.credentials.toJson()));
    print('✅ Login realizado e token salvo com sucesso!');
  }

  final driveApi = drive.DriveApi(client);

  try {
    print('Localizando pasta de backup "SistemaExodo_Projeto_Backups"...');
    String? folderId = await _getOrCreateFolder(driveApi, 'SistemaExodo_Projeto_Backups');

    print('Enviando arquivo: ${p.basename(zipFilePath)} (${(file.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB)');
    
    final media = drive.Media(file.openRead(), file.lengthSync());
    final driveFile = drive.File()
      ..name = p.basename(zipFilePath)
      ..parents = folderId != null ? [folderId] : null;

    final result = await driveApi.files.create(
      driveFile, 
      uploadMedia: media,
      uploadOptions: drive.UploadOptions.resumable,
    );
    
    print('✅ Backup concluído com sucesso!');
    print('Dono do arquivo: ${client.credentials.accessToken}');
    print('ID do Arquivo: ${result.id}');
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

Future<String?> _getOrCreateFolder(drive.DriveApi driveApi, String folderName) async {
  final folderList = await driveApi.files.list(
    q: "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
    spaces: 'drive',
  );

  if (folderList.files != null && folderList.files!.isNotEmpty) {
    return folderList.files!.first.id;
  }

  print('Criando pasta "$folderName" no seu Drive...');
  final folder = drive.File()
    ..name = folderName
    ..mimeType = 'application/vnd.google-apps.folder';

  final createdFolder = await driveApi.files.create(folder);
  return createdFolder.id;
}
