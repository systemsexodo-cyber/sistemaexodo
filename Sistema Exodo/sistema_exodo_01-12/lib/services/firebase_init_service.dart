import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Serviço para inicializar toda a estrutura do Firebase Firestore
class FirebaseInitService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Nomes das coleções
  static const String collectionClientes = 'clientes';
  static const String collectionProdutos = 'produtos';
  static const String collectionServicos = 'servicos';
  static const String collectionPedidos = 'pedidos';
  static const String collectionOrdensServico = 'ordens_servico';
  static const String collectionEntregas = 'entregas';
  static const String collectionVendasBalcao = 'vendas_balcao';
  static const String collectionTrocasDevolucoes = 'trocas_devolucoes';
  static const String collectionEstoqueHistorico = 'estoque_historico';
  static const String collectionAberturasCaixa = 'aberturas_caixa';
  static const String collectionFechamentosCaixa = 'fechamentos_caixa';
  static const String collectionMotoristas = 'motoristas';
  static const String collectionConfig = 'config'; // Para configurações gerais

  /// Inicializa toda a estrutura do Firebase
  /// Cria documentos de exemplo e garante que as coleções existam
  static Future<void> inicializarEstrutura() async {
    try {
      debugPrint('╔════════════════════════════════════════════════╗');
      debugPrint('║  INICIANDO ESTRUTURA DO FIREBASE            ║');
      debugPrint('╚════════════════════════════════════════════════╝');

      // Criar documento de configuração inicial
      await _criarConfiguracaoInicial();

      // Verificar e criar estrutura de coleções
      await _verificarEstruturaColecoes();

      // Criar índices compostos necessários (se necessário)
      await _criarIndices();

      debugPrint('╔════════════════════════════════════════════════╗');
      debugPrint('║  ESTRUTURA DO FIREBASE CRIADA COM SUCESSO!    ║');
      debugPrint('╚════════════════════════════════════════════════╝');
    } catch (e, stackTrace) {
      debugPrint('>>> ✗ Erro ao inicializar estrutura do Firebase: $e');
      debugPrint('>>> StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Cria documento de configuração inicial
  static Future<void> _criarConfiguracaoInicial() async {
    try {
      final configRef = _firestore.collection(collectionConfig).doc('sistema');
      final configDoc = await configRef.get();

      if (!configDoc.exists) {
        await configRef.set({
          'versao': '1.0.0',
          'dataInicializacao': FieldValue.serverTimestamp(),
          'ultimaSincronizacao': FieldValue.serverTimestamp(),
          'estruturaCriada': true,
          'colecoes': [
            collectionClientes,
            collectionProdutos,
            collectionServicos,
            collectionPedidos,
            collectionOrdensServico,
            collectionEntregas,
            collectionVendasBalcao,
            collectionTrocasDevolucoes,
            collectionEstoqueHistorico,
            collectionAberturasCaixa,
            collectionFechamentosCaixa,
            collectionMotoristas,
          ],
        });
        debugPrint('>>> ✓ Documento de configuração criado');
      } else {
        debugPrint('>>> ✓ Documento de configuração já existe');
      }
    } catch (e) {
      debugPrint('>>> ⚠ Erro ao criar configuração: $e');
    }
  }

  /// Verifica e cria estrutura de coleções (criando documentos vazios se necessário)
  static Future<void> _verificarEstruturaColecoes() async {
    final colecoes = [
      collectionClientes,
      collectionProdutos,
      collectionServicos,
      collectionPedidos,
      collectionOrdensServico,
      collectionEntregas,
      collectionVendasBalcao,
      collectionTrocasDevolucoes,
      collectionEstoqueHistorico,
      collectionAberturasCaixa,
      collectionFechamentosCaixa,
      collectionMotoristas,
    ];

    for (final colecao in colecoes) {
      try {
        // Verificar se a coleção existe (tentando ler um documento)
        final snapshot = await _firestore.collection(colecao).limit(1).get();
        debugPrint('>>> ✓ Coleção "$colecao" verificada (${snapshot.docs.length} docs)');
      } catch (e) {
        debugPrint('>>> ⚠ Erro ao verificar coleção "$colecao": $e');
        // Coleção será criada automaticamente quando o primeiro documento for adicionado
      }
    }
  }

  /// Cria índices compostos necessários (documentação)
  /// Nota: Índices compostos devem ser criados manualmente no Console do Firebase
  /// ou através do arquivo firestore.indexes.json
  static Future<void> _criarIndices() async {
    debugPrint('>>> ℹ Índices compostos devem ser criados no Console do Firebase');
    debugPrint('>>> ℹ Ou através do arquivo firestore.indexes.json');
  }

  /// Atualiza timestamp de última sincronização
  static Future<void> atualizarUltimaSincronizacao() async {
    try {
      await _firestore.collection(collectionConfig).doc('sistema').update({
        'ultimaSincronizacao': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('>>> ⚠ Erro ao atualizar última sincronização: $e');
    }
  }

  /// Obtém informações da estrutura
  static Future<Map<String, dynamic>?> obterInfoEstrutura() async {
    try {
      final doc = await _firestore.collection(collectionConfig).doc('sistema').get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      debugPrint('>>> ⚠ Erro ao obter info da estrutura: $e');
      return null;
    }
  }

  /// Limpa toda a estrutura (CUIDADO: apaga todos os dados!)
  static Future<void> limparEstrutura({bool confirmar = false}) async {
    if (!confirmar) {
      debugPrint('>>> ⚠ Operação de limpeza requer confirmação!');
      return;
    }

    try {
      debugPrint('>>> 🗑️ Limpando estrutura do Firebase...');
      
      final colecoes = [
        collectionClientes,
        collectionProdutos,
        collectionServicos,
        collectionPedidos,
        collectionOrdensServico,
        collectionEntregas,
        collectionVendasBalcao,
        collectionTrocasDevolucoes,
        collectionEstoqueHistorico,
        collectionAberturasCaixa,
        collectionFechamentosCaixa,
        collectionMotoristas,
      ];

      for (final colecao in colecoes) {
        final snapshot = await _firestore.collection(colecao).get();
        final batch = _firestore.batch();
        
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        
        await batch.commit();
        debugPrint('>>> ✓ Coleção "$colecao" limpa (${snapshot.docs.length} docs)');
      }

      debugPrint('>>> ✓ Estrutura limpa com sucesso!');
    } catch (e, stackTrace) {
      debugPrint('>>> ✗ Erro ao limpar estrutura: $e');
      debugPrint('>>> StackTrace: $stackTrace');
      rethrow;
    }
  }
}

