import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/servico.dart';
import '../models/pedido.dart';
import '../models/ordem_servico.dart';
import '../models/entrega.dart';
import '../models/venda_balcao.dart';
import '../models/troca_devolucao.dart';
import '../models/estoque_historico.dart';
import '../models/caixa.dart';
import '../models/entrega.dart' show Motorista;
import '../models/empresa.dart';
import '../models/usuario.dart';

/// Serviço para sincronizar todos os dados com Firebase Firestore
class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Coleções do Firestore
  static const String _collectionEmpresas = 'empresas'; // Coleção global de empresas
  static const String _collectionUsuarios = 'usuarios'; // Coleção global de usuários
  static const String _subCollectionClientes = 'clientes';
  static const String _subCollectionProdutos = 'produtos';
  static const String _subCollectionServicos = 'servicos';
  static const String _subCollectionPedidos = 'pedidos';
  static const String _subCollectionOrdensServico = 'ordens_servico';
  static const String _subCollectionEntregas = 'entregas';
  static const String _subCollectionVendasBalcao = 'vendas_balcao';
  static const String _subCollectionTrocasDevolucoes = 'trocas_devolucoes';
  static const String _subCollectionEstoqueHistorico = 'estoque_historico';
  static const String _subCollectionAberturasCaixa = 'aberturas_caixa';
  static const String _subCollectionFechamentosCaixa = 'fechamentos_caixa';
  static const String _subCollectionMotoristas = 'motoristas';
  
  /// Obtém a referência da subcoleção para uma empresa específica
  CollectionReference _getSubCollection(String empresaId, String subCollection) {
    return _firestore
        .collection(_collectionEmpresas)
        .doc(empresaId)
        .collection(subCollection);
  }

  /// Salvar todos os dados no Firebase
  Future<void> salvarTudoNoFirebase({
    required String empresaId,
    required List<Cliente> clientes,
    required List<Produto> produtos,
    required List<Servico> servicos,
    required List<Pedido> pedidos,
    required List<OrdemServico> ordensServico,
    required List<Entrega> entregas,
    required List<VendaBalcao> vendasBalcao,
    required List<TrocaDevolucao> trocasDevolucoes,
    required List<EstoqueHistorico> estoqueHistorico,
    required List<AberturaCaixa> aberturasCaixa,
    required List<FechamentoCaixa> fechamentosCaixa,
    required List<Motorista> motoristas,
  }) async {
    try {
      debugPrint('>>> [Firebase] Iniciando salvamento completo no Firebase...');
      
      // Salvar em batch para melhor performance
      final batch = _firestore.batch();
      int totalOperacoes = 0;

      // Salvar Clientes
      for (final cliente in clientes) {
        final docRef = _getSubCollection(empresaId, _subCollectionClientes).doc(cliente.id);
        batch.set(docRef, cliente.toMap());
        totalOperacoes++;
      }

      // Salvar Produtos
      for (final produto in produtos) {
        final docRef = _getSubCollection(empresaId, _subCollectionProdutos).doc(produto.id);
        batch.set(docRef, produto.toMap());
        totalOperacoes++;
      }

      // Salvar Serviços
      for (final servico in servicos) {
        final docRef = _getSubCollection(empresaId, _subCollectionServicos).doc(servico.id);
        batch.set(docRef, servico.toMap());
        totalOperacoes++;
      }

      // Salvar Pedidos
      for (final pedido in pedidos) {
        final docRef = _getSubCollection(empresaId, _subCollectionPedidos).doc(pedido.id);
        batch.set(docRef, pedido.toMap());
        totalOperacoes++;
      }

      // Salvar Ordens de Serviço
      for (final ordem in ordensServico) {
        final docRef = _getSubCollection(empresaId, _subCollectionOrdensServico).doc(ordem.id);
        batch.set(docRef, ordem.toMap());
        totalOperacoes++;
      }

      // Salvar Entregas
      for (final entrega in entregas) {
        final docRef = _getSubCollection(empresaId, _subCollectionEntregas).doc(entrega.id);
        batch.set(docRef, entrega.toMap());
        totalOperacoes++;
      }

      // Salvar Vendas Balcão
      for (final venda in vendasBalcao) {
        final docRef = _getSubCollection(empresaId, _subCollectionVendasBalcao).doc(venda.id);
        batch.set(docRef, venda.toMap());
        totalOperacoes++;
      }

      // Salvar Trocas e Devoluções
      for (final troca in trocasDevolucoes) {
        final docRef = _getSubCollection(empresaId, _subCollectionTrocasDevolucoes).doc(troca.id);
        batch.set(docRef, troca.toMap());
        totalOperacoes++;
      }

      // Salvar Histórico de Estoque
      for (final historico in estoqueHistorico) {
        final docRef = _getSubCollection(empresaId, _subCollectionEstoqueHistorico).doc(historico.id);
        batch.set(docRef, historico.toMap());
        totalOperacoes++;
      }

      // Salvar Aberturas de Caixa
      for (final abertura in aberturasCaixa) {
        final docRef = _getSubCollection(empresaId, _subCollectionAberturasCaixa).doc(abertura.id);
        batch.set(docRef, abertura.toMap());
        totalOperacoes++;
      }

      // Salvar Fechamentos de Caixa
      for (final fechamento in fechamentosCaixa) {
        final docRef = _getSubCollection(empresaId, _subCollectionFechamentosCaixa).doc(fechamento.id);
        batch.set(docRef, fechamento.toMap());
        totalOperacoes++;
      }

      // Salvar Motoristas
      for (final motorista in motoristas) {
        final docRef = _getSubCollection(empresaId, _subCollectionMotoristas).doc(motorista.id);
        batch.set(docRef, motorista.toMap());
        totalOperacoes++;
      }

      // Executar batch (limite do Firestore é 500 operações por batch)
      if (totalOperacoes > 0) {
        if (totalOperacoes <= 500) {
          await batch.commit();
          debugPrint('>>> [Firebase] $totalOperacoes documentos salvos com sucesso!');
        } else {
          // Se exceder 500, dividir em múltiplos batches
          debugPrint('>>> [Firebase] Muitos documentos ($totalOperacoes). Salvando em múltiplos batches...');
          // Por enquanto, vamos salvar em batches menores
          await _salvarEmBatches(
            empresaId: empresaId,
            clientes: clientes,
            produtos: produtos,
            servicos: servicos,
            pedidos: pedidos,
            ordensServico: ordensServico,
            entregas: entregas,
            vendasBalcao: vendasBalcao,
            trocasDevolucoes: trocasDevolucoes,
            estoqueHistorico: estoqueHistorico,
            aberturasCaixa: aberturasCaixa,
            fechamentosCaixa: fechamentosCaixa,
            motoristas: motoristas,
          );
        }
      } else {
        debugPrint('>>> [Firebase] Nenhum dado para salvar');
      }

      debugPrint('>>> [Firebase] Salvamento completo finalizado!');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar no Firebase: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salvar em múltiplos batches se necessário
  Future<void> _salvarEmBatches({
    required String empresaId,
    required List<Cliente> clientes,
    required List<Produto> produtos,
    required List<Servico> servicos,
    required List<Pedido> pedidos,
    required List<OrdemServico> ordensServico,
    required List<Entrega> entregas,
    required List<VendaBalcao> vendasBalcao,
    required List<TrocaDevolucao> trocasDevolucoes,
    required List<EstoqueHistorico> estoqueHistorico,
    required List<AberturaCaixa> aberturasCaixa,
    required List<FechamentoCaixa> fechamentosCaixa,
    required List<Motorista> motoristas,
  }) async {
    // Salvar cada coleção separadamente
    await _salvarLista(empresaId, clientes, _subCollectionClientes, (c) => c.id, (c) => c.toMap());
    await _salvarLista(empresaId, produtos, _subCollectionProdutos, (p) => p.id, (p) => p.toMap());
    await _salvarLista(empresaId, servicos, _subCollectionServicos, (s) => s.id, (s) => s.toMap());
    await _salvarLista(empresaId, pedidos, _subCollectionPedidos, (p) => p.id, (p) => p.toMap());
    await _salvarLista(empresaId, ordensServico, _subCollectionOrdensServico, (o) => o.id, (o) => o.toMap());
    await _salvarLista(empresaId, entregas, _subCollectionEntregas, (e) => e.id, (e) => e.toMap());
    await _salvarLista(empresaId, vendasBalcao, _subCollectionVendasBalcao, (v) => v.id, (v) => v.toMap());
    await _salvarLista(empresaId, trocasDevolucoes, _subCollectionTrocasDevolucoes, (t) => t.id, (t) => t.toMap());
    await _salvarLista(empresaId, estoqueHistorico, _subCollectionEstoqueHistorico, (e) => e.id, (e) => e.toMap());
    await _salvarLista(empresaId, aberturasCaixa, _subCollectionAberturasCaixa, (a) => a.id, (a) => a.toMap());
    await _salvarLista(empresaId, fechamentosCaixa, _subCollectionFechamentosCaixa, (f) => f.id, (f) => f.toMap());
    await _salvarLista(empresaId, motoristas, _subCollectionMotoristas, (m) => m.id, (m) => m.toMap());
  }

  Future<void> _salvarLista<T>(
    String empresaId,
    List<T> items,
    String subCollection,
    String Function(T) getId,
    Map<String, dynamic> Function(T) toMap,
  ) async {
    if (items.isEmpty) return;

    const batchSize = 500;
    for (int i = 0; i < items.length; i += batchSize) {
      final batch = _firestore.batch();
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      
      for (int j = i; j < end; j++) {
        final item = items[j];
        final docRef = _getSubCollection(empresaId, subCollection).doc(getId(item));
        batch.set(docRef, toMap(item));
      }
      
      await batch.commit();
      debugPrint('>>> [Firebase] $subCollection (empresa: $empresaId): ${end - i} documentos salvos (${i + 1}-$end de ${items.length})');
    }
  }

  /// Carregar todos os dados do Firebase para uma empresa específica
  Future<Map<String, dynamic>> carregarTudoDoFirebase(String empresaId) async {
    try {
      debugPrint('>>> [Firebase] Iniciando carregamento completo do Firebase para empresa: $empresaId');
      
      final dados = <String, dynamic>{};

      // Carregar todas as subcoleções da empresa em paralelo com timeout de 8 segundos
      final results = await Future.wait([
        _getSubCollection(empresaId, _subCollectionClientes).get(),
        _getSubCollection(empresaId, _subCollectionProdutos).get(),
        _getSubCollection(empresaId, _subCollectionServicos).get(),
        _getSubCollection(empresaId, _subCollectionPedidos).get(),
        _getSubCollection(empresaId, _subCollectionOrdensServico).get(),
        _getSubCollection(empresaId, _subCollectionEntregas).get(),
        _getSubCollection(empresaId, _subCollectionVendasBalcao).get(),
        _getSubCollection(empresaId, _subCollectionTrocasDevolucoes).get(),
        _getSubCollection(empresaId, _subCollectionEstoqueHistorico).get(),
        _getSubCollection(empresaId, _subCollectionAberturasCaixa).get(),
        _getSubCollection(empresaId, _subCollectionFechamentosCaixa).get(),
        _getSubCollection(empresaId, _subCollectionMotoristas).get(),
      ]).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('>>> [Firebase] ⚠ Timeout ao carregar dados (8s)');
          throw TimeoutException('Timeout ao carregar dados do Firebase');
        },
      );

      dados['clientes'] = results[0].docs.map((doc) => doc.data()).toList();
      dados['produtos'] = results[1].docs.map((doc) => doc.data()).toList();
      dados['servicos'] = results[2].docs.map((doc) => doc.data()).toList();
      dados['pedidos'] = results[3].docs.map((doc) => doc.data()).toList();
      dados['ordens_servico'] = results[4].docs.map((doc) => doc.data()).toList();
      dados['entregas'] = results[5].docs.map((doc) => doc.data()).toList();
      dados['vendas_balcao'] = results[6].docs.map((doc) => doc.data()).toList();
      dados['trocas_devolucoes'] = results[7].docs.map((doc) => doc.data()).toList();
      dados['estoque_historico'] = results[8].docs.map((doc) => doc.data()).toList();
      dados['aberturas_caixa'] = results[9].docs.map((doc) => doc.data()).toList();
      dados['fechamentos_caixa'] = results[10].docs.map((doc) => doc.data()).toList();
      dados['motoristas'] = results[11].docs.map((doc) => doc.data()).toList();

      debugPrint('>>> [Firebase] Dados carregados:');
      debugPrint('  - Clientes: ${dados['clientes'].length}');
      debugPrint('  - Produtos: ${dados['produtos'].length}');
      debugPrint('  - Serviços: ${dados['servicos'].length}');
      debugPrint('  - Pedidos: ${dados['pedidos'].length}');
      debugPrint('  - Ordens de Serviço: ${dados['ordens_servico'].length}');
      debugPrint('  - Entregas: ${dados['entregas'].length}');
      debugPrint('  - Vendas Balcão: ${dados['vendas_balcao'].length}');
      debugPrint('  - Trocas/Devoluções: ${dados['trocas_devolucoes'].length}');
      debugPrint('  - Estoque Histórico: ${dados['estoque_historico'].length}');
      debugPrint('  - Aberturas Caixa: ${dados['aberturas_caixa'].length}');
      debugPrint('  - Fechamentos Caixa: ${dados['fechamentos_caixa'].length}');
      debugPrint('  - Motoristas: ${dados['motoristas'].length}');

      return dados;
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao carregar do Firebase: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Sincronizar dados (salvar tudo)
  Future<void> sincronizarTudo({
    required String empresaId,
    required List<Cliente> clientes,
    required List<Produto> produtos,
    required List<Servico> servicos,
    required List<Pedido> pedidos,
    required List<OrdemServico> ordensServico,
    required List<Entrega> entregas,
    required List<VendaBalcao> vendasBalcao,
    required List<TrocaDevolucao> trocasDevolucoes,
    required List<EstoqueHistorico> estoqueHistorico,
    required List<AberturaCaixa> aberturasCaixa,
    required List<FechamentoCaixa> fechamentosCaixa,
    required List<Motorista> motoristas,
  }) async {
    await salvarTudoNoFirebase(
      empresaId: empresaId,
      clientes: clientes,
      produtos: produtos,
      servicos: servicos,
      pedidos: pedidos,
      ordensServico: ordensServico,
      entregas: entregas,
      vendasBalcao: vendasBalcao,
      trocasDevolucoes: trocasDevolucoes,
      estoqueHistorico: estoqueHistorico,
      aberturasCaixa: aberturasCaixa,
      fechamentosCaixa: fechamentosCaixa,
      motoristas: motoristas,
    );
  }

  // ============ MÉTODOS PARA EMPRESAS ============

  /// Salva uma empresa no Firebase
  Future<void> salvarEmpresa(Empresa empresa) async {
    try {
      final docRef = _firestore.collection(_collectionEmpresas).doc(empresa.id);
      await docRef.set(empresa.toMap());
      debugPrint('>>> [Firebase] Empresa salva: ${empresa.nomeExibicao} (ID: ${empresa.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar empresa: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Carrega todas as empresas do Firebase
  Future<List<Empresa>> carregarEmpresas() async {
    try {
      debugPrint('>>> [Firebase] Carregando empresas...');
      final snapshot = await _firestore.collection(_collectionEmpresas).get();
      final empresas = snapshot.docs
          .map((doc) => Empresa.fromMap(doc.data()))
          .toList();
      debugPrint('>>> [Firebase] ${empresas.length} empresas carregadas');
      return empresas;
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao carregar empresas: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      return [];
    }
  }

  /// Remove uma empresa do Firebase
  Future<void> removerEmpresa(String empresaId) async {
    try {
      await _firestore.collection(_collectionEmpresas).doc(empresaId).delete();
      debugPrint('>>> [Firebase] Empresa removida: $empresaId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover empresa: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  // ============ MÉTODOS PARA USUÁRIOS ============

  /// Salva um usuário no Firebase
  Future<void> salvarUsuario(Usuario usuario) async {
    try {
      final docRef = _firestore.collection(_collectionUsuarios).doc(usuario.id);
      await docRef.set(usuario.toMap());
      debugPrint('>>> [Firebase] Usuário salvo: ${usuario.nome} (ID: ${usuario.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar usuário: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Carrega todos os usuários do Firebase
  Future<List<Usuario>> carregarUsuarios() async {
    try {
      debugPrint('>>> [Firebase] Carregando usuários...');
      final snapshot = await _firestore.collection(_collectionUsuarios).get();
      final usuarios = snapshot.docs
          .map((doc) => Usuario.fromMap(doc.data()))
          .toList();
      debugPrint('>>> [Firebase] ${usuarios.length} usuários carregados');
      return usuarios;
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao carregar usuários: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      return [];
    }
  }

  /// Remove um usuário do Firebase
  Future<void> removerUsuario(String usuarioId) async {
    try {
      await _firestore.collection(_collectionUsuarios).doc(usuarioId).delete();
      debugPrint('>>> [Firebase] Usuário removido: $usuarioId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover usuário: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Deletar todos os produtos de uma empresa no Firebase
  Future<void> deletarTodosProdutos(String empresaId) async {
    try {
      debugPrint('>>> [Firebase] Deletando todos os produtos da empresa $empresaId...');
      final produtosRef = _getSubCollection(empresaId, _subCollectionProdutos);
      
      // Obter todos os documentos da subcoleção
      final snapshot = await produtosRef.get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('>>> [Firebase] Nenhum produto encontrado para deletar');
        return;
      }
      
      // Deletar em batch (máximo 500 por vez no Firestore)
      int totalDeletados = 0;
      final List<Future<void>> batches = [];
      
      for (int i = 0; i < snapshot.docs.length; i += 500) {
        final batch = _firestore.batch();
        final endIndex = (i + 500 < snapshot.docs.length) ? i + 500 : snapshot.docs.length;
        
        for (int j = i; j < endIndex; j++) {
          batch.delete(snapshot.docs[j].reference);
          totalDeletados++;
        }
        
        batches.add(batch.commit());
      }
      
      // Executar todos os batches
      await Future.wait(batches);
      
      debugPrint('>>> [Firebase] ✅ Total de $totalDeletados produtos deletados com sucesso');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ❌ Erro ao deletar todos os produtos: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }
}

