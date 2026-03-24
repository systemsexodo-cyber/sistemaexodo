import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

class BridgeCommand {
  final String id;
  final String comando;
  final String status;
  final String? resultado;
  final bool? sucesso;
  final DateTime? createdAt;
  final String? pcName;

  BridgeCommand({
    required this.id,
    required this.comando,
    required this.status,
    this.resultado,
    this.sucesso,
    this.createdAt,
    this.pcName,
  });

  factory BridgeCommand.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BridgeCommand(
      id: doc.id,
      comando: data['comando'] ?? '',
      status: data['status'] ?? '',
      resultado: data['resultado'],
      sucesso: data['sucesso'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      pcName: data['pc_name'],
    );
  }
}

class BridgeManagementService {
  static final BridgeManagementService instance = BridgeManagementService._();
  BridgeManagementService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Envia um comando para todos os bridges ou um específico e retorna a referência do documento
  Future<DocumentReference> enviarComando(String comando, {String? targetPc, Map<String, dynamic>? extraData}) async {
    try {
      final Map<String, dynamic> data = {
        'comando': comando,
        'status': 'pendente',
        'target_pc': targetPc, // Se null, todos os ouvintes podem tentar processar (ou o primeiro)
        'created_at': FieldValue.serverTimestamp(),
      };

      if (extraData != null) {
        data.addAll(extraData);
      }

      return await _db.collection('bridge_commands').add(data);
    } catch (e) {
      debugPrint('Erro ao enviar comando bridge: $e');
      rethrow;
    }
  }

  /// Stream de comandos recentes para monitoramento
  Stream<List<BridgeCommand>> getComandosRecentes() {
    return _db
        .collection('bridge_commands')
        .orderBy('created_at', descending: true)
        .limit(10)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => BridgeCommand.fromFirestore(doc)).toList());
  }
  
  /// Atalho para enviar update para todos
  Future<void> atualizarTodos() async {
    await enviarComando('update');
  }

  /// Atalho para reiniciar todos
  Future<void> reiniciarTodos() async {
    await enviarComando('restart');
  }
  
  /// Atalho para identificar bridges
  Future<void> identificarBridges() async {
    await enviarComando('identify');
  }

  /// Faz upload de uma nova versão do Emissor NFCe (.exe) para o Firebase Storage
  /// e atualiza o documento `bridge_config/latest` no Firestore
  Future<void> subirNovaVersaoBridge(PlatformFile file, String version, Function(double) onProgress) async {
    if (file.bytes == null) {
      throw Exception('O arquivo selecionado está vazio ou não pôde ser lido.');
    }

    try {
      final storageRef = FirebaseStorage.instance.ref().child('bridge_updates/ExodoNfceBridge_v$version.exe');
      
      final uploadTask = storageRef.putData(
        file.bytes!, 
        SettableMetadata(contentType: 'application/x-msdownload')
      );

      // Listener de progresso
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress(progress);
      });

      // Aguarda completar o upload
      await uploadTask;

      // Pegar URL Pública
      final downloadUrl = await storageRef.getDownloadURL();

      // Gravar no Firestore `bridge_config/latest`
      await FirebaseFirestore.instance.collection('bridge_config').doc('latest').set({
        'version': version,
        'download_url': downloadUrl,
        'updated_at': FieldValue.serverTimestamp(),
      });

      debugPrint('>>> [BridgeManager] Versão $version enviada com sucesso! URL: $downloadUrl');
    } catch (e) {
      debugPrint('>>> [BridgeManager] Erro no upload da nova versão: $e');
      rethrow;
    }
  }
}
