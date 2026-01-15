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

/// Serviço para sincronizar todos os dados com Firebase Firestore
class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Coleções do Firestore
  static const String _collectionClientes = 'clientes';
  static const String _collectionProdutos = 'produtos';
  static const String _collectionServicos = 'servicos';
  static const String _collectionPedidos = 'pedidos';
  static const String _collectionOrdensServico = 'ordens_servico';
  static const String _collectionEntregas = 'entregas';
  static const String _collectionVendasBalcao = 'vendas_balcao';
  static const String _collectionTrocasDevolucoes = 'trocas_devolucoes';
  static const String _collectionEstoqueHistorico = 'estoque_historico';
  static const String _collectionAberturasCaixa = 'aberturas_caixa';
  static const String _collectionFechamentosCaixa = 'fechamentos_caixa';
  static const String _collectionMotoristas = 'motoristas';

  /// Salvar todos os dados no Firebase
  Future<void> salvarTudoNoFirebase({
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
        final docRef = _firestore.collection(_collectionClientes).doc(cliente.id);
        batch.set(docRef, cliente.toMap());
        totalOperacoes++;
      }

      // Salvar Produtos
      for (final produto in produtos) {
        final docRef = _firestore.collection(_collectionProdutos).doc(produto.id);
        batch.set(docRef, produto.toMap());
        totalOperacoes++;
      }

      // Salvar Serviços
      for (final servico in servicos) {
        final docRef = _firestore.collection(_collectionServicos).doc(servico.id);
        batch.set(docRef, servico.toMap());
        totalOperacoes++;
      }

      // Salvar Pedidos
      for (final pedido in pedidos) {
        final docRef = _firestore.collection(_collectionPedidos).doc(pedido.id);
        batch.set(docRef, pedido.toMap());
        totalOperacoes++;
      }

      // Salvar Ordens de Serviço
      for (final ordem in ordensServico) {
        final docRef = _firestore.collection(_collectionOrdensServico).doc(ordem.id);
        batch.set(docRef, ordem.toMap());
        totalOperacoes++;
      }

      // Salvar Entregas
      for (final entrega in entregas) {
        final docRef = _firestore.collection(_collectionEntregas).doc(entrega.id);
        batch.set(docRef, entrega.toMap());
        totalOperacoes++;
      }

      // Salvar Vendas Balcão
      for (final venda in vendasBalcao) {
        final docRef = _firestore.collection(_collectionVendasBalcao).doc(venda.id);
        batch.set(docRef, venda.toMap());
        totalOperacoes++;
      }

      // Salvar Trocas e Devoluções
      for (final troca in trocasDevolucoes) {
        final docRef = _firestore.collection(_collectionTrocasDevolucoes).doc(troca.id);
        batch.set(docRef, troca.toMap());
        totalOperacoes++;
      }

      // Salvar Histórico de Estoque
      for (final historico in estoqueHistorico) {
        final docRef = _firestore.collection(_collectionEstoqueHistorico).doc(historico.id);
        batch.set(docRef, historico.toMap());
        totalOperacoes++;
      }

      // Salvar Aberturas de Caixa
      for (final abertura in aberturasCaixa) {
        final docRef = _firestore.collection(_collectionAberturasCaixa).doc(abertura.id);
        batch.set(docRef, abertura.toMap());
        totalOperacoes++;
      }

      // Salvar Fechamentos de Caixa
      for (final fechamento in fechamentosCaixa) {
        final docRef = _firestore.collection(_collectionFechamentosCaixa).doc(fechamento.id);
        batch.set(docRef, fechamento.toMap());
        totalOperacoes++;
      }

      // Salvar Motoristas
      for (final motorista in motoristas) {
        final docRef = _firestore.collection(_collectionMotoristas).doc(motorista.id);
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
    await _salvarLista(clientes, _collectionClientes, (c) => c.id, (c) => c.toMap());
    await _salvarLista(produtos, _collectionProdutos, (p) => p.id, (p) => p.toMap());
    await _salvarLista(servicos, _collectionServicos, (s) => s.id, (s) => s.toMap());
    await _salvarLista(pedidos, _collectionPedidos, (p) => p.id, (p) => p.toMap());
    await _salvarLista(ordensServico, _collectionOrdensServico, (o) => o.id, (o) => o.toMap());
    await _salvarLista(entregas, _collectionEntregas, (e) => e.id, (e) => e.toMap());
    await _salvarLista(vendasBalcao, _collectionVendasBalcao, (v) => v.id, (v) => v.toMap());
    await _salvarLista(trocasDevolucoes, _collectionTrocasDevolucoes, (t) => t.id, (t) => t.toMap());
    await _salvarLista(estoqueHistorico, _collectionEstoqueHistorico, (e) => e.id, (e) => e.toMap());
    await _salvarLista(aberturasCaixa, _collectionAberturasCaixa, (a) => a.id, (a) => a.toMap());
    await _salvarLista(fechamentosCaixa, _collectionFechamentosCaixa, (f) => f.id, (f) => f.toMap());
    await _salvarLista(motoristas, _collectionMotoristas, (m) => m.id, (m) => m.toMap());
  }

  Future<void> _salvarLista<T>(
    List<T> items,
    String collection,
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
        final docRef = _firestore.collection(collection).doc(getId(item));
        batch.set(docRef, toMap(item));
      }
      
      await batch.commit();
      debugPrint('>>> [Firebase] $collection: ${end - i} documentos salvos (${i + 1}-$end de ${items.length})');
    }
  }

  /// Carregar todos os dados do Firebase
  Future<Map<String, dynamic>> carregarTudoDoFirebase() async {
    try {
      debugPrint('>>> [Firebase] Iniciando carregamento completo do Firebase...');
      
      final dados = <String, dynamic>{};

      // Carregar todas as coleções em paralelo com timeout de 8 segundos
      final results = await Future.wait([
        _firestore.collection(_collectionClientes).get(),
        _firestore.collection(_collectionProdutos).get(),
        _firestore.collection(_collectionServicos).get(),
        _firestore.collection(_collectionPedidos).get(),
        _firestore.collection(_collectionOrdensServico).get(),
        _firestore.collection(_collectionEntregas).get(),
        _firestore.collection(_collectionVendasBalcao).get(),
        _firestore.collection(_collectionTrocasDevolucoes).get(),
        _firestore.collection(_collectionEstoqueHistorico).get(),
        _firestore.collection(_collectionAberturasCaixa).get(),
        _firestore.collection(_collectionFechamentosCaixa).get(),
        _firestore.collection(_collectionMotoristas).get(),
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
}

