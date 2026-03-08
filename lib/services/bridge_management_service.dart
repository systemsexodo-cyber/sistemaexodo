import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

  /// Envia um comando para todos os bridges ou um específico
  Future<void> enviarComando(String comando, {String? targetPc, Map<String, dynamic>? extraData}) async {
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

      await _db.collection('bridge_commands').add(data);
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
}
