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
import '../models/agendamento_servico.dart';
import '../models/nota_entrada.dart';
import '../models/funcionario.dart';
import '../models/taxa_entrega.dart';
import '../models/conta_pagar.dart';
import '../models/nfce.dart';
import '../models/mesa_comanda.dart';
import '../models/link_vendedor.dart';
import '../models/comissao_vendedor.dart';

/// Serviço para sincronizar todos os dados com Firebase Firestore
class FirebaseService {
  FirebaseService._(); // Construtor privado para singleton
  
  static final FirebaseService instance = FirebaseService._();
  
  // Lazy getter para Firestore - só acessa quando necessário
  static FirebaseFirestore get _firestore {
    try {
      return FirebaseFirestore.instance;
    } catch (e) {
      debugPrint('>>> [Firebase] ⚠️ Erro ao acessar Firestore: $e');
      // Se houver erro, tentar verificar se Firebase está inicializado
      throw Exception('Firebase não está inicializado. Erro: $e');
    }
  }
  
  /// Verifica se o Firebase está disponível
  static bool get isAvailable {
    try {
      FirebaseFirestore.instance; // Tenta acessar a instância
      return true;
    } catch (e) {
      return false;
    }
  }
  
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
  static const String _subCollectionAgendamentosServico = 'agendamentos_servico';
  static const String _subCollectionNotasEntrada = 'notas_entrada';
  static const String _subCollectionFuncionarios = 'funcionarios';
  static const String _subCollectionTaxasEntrega = 'taxas_entrega';
  static const String _subCollectionContasPagar = 'contas_pagar';
  static const String _subCollectionNFCes = 'nfces';
  static const String _subCollectionSangrias = 'sangrias_caixa';
  static const String _subCollectionSuprimentos = 'suprimentos_caixa';
  static const String _subCollectionMesasComandas = 'mesas_comandas';
  static const String _subCollectionLinksVendedores = 'links_vendedores';
  static const String _subCollectionComissoesVendedores = 'comissoes_vendedores';
  
  /// Obtém a referência da subcoleção para uma empresa específica
  /// IMPORTANTE: Este método garante que os dados são filtrados por empresaId
  /// A estrutura no Firebase é: empresas/{empresaId}/{subCollection}/{documentos}
  CollectionReference _getSubCollection(String empresaId, String subCollection) {
    if (empresaId.isEmpty) {
      throw ArgumentError('empresaId não pode ser vazio ao acessar subcoleção: $subCollection');
    }
    // Esta estrutura garante que só acessamos dados da empresa especificada
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
    required List<AgendamentoServico> agendamentosServico,
    required List<NotaEntrada> notasEntrada,
    required List<Funcionario> funcionarios,
    required List<TaxaEntrega> taxasEntrega,
    required List<ContaPagar> contasPagar,
    required List<NFCe> nfces,
    required List<SangriaCaixa> sangrias,
    required List<SuprimentoCaixa> suprimentos,
    List<LinkVendedor>? linksVendedores,
    List<ComissaoVendedor>? comissoesVendedores,
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

      // Salvar Agendamentos de Serviço
      for (final agendamento in agendamentosServico) {
        final docRef = _getSubCollection(empresaId, _subCollectionAgendamentosServico).doc(agendamento.id);
        batch.set(docRef, agendamento.toMap());
        totalOperacoes++;
      }

      // Salvar Notas de Entrada
      for (final nota in notasEntrada) {
        final docRef = _getSubCollection(empresaId, _subCollectionNotasEntrada).doc(nota.id);
        batch.set(docRef, nota.toMap());
        totalOperacoes++;
      }

      // Salvar Funcionários
      for (final funcionario in funcionarios) {
        final docRef = _getSubCollection(empresaId, _subCollectionFuncionarios).doc(funcionario.id);
        batch.set(docRef, funcionario.toMap());
        totalOperacoes++;
      }

      // Salvar Taxas de Entrega
      for (final taxa in taxasEntrega) {
        final docRef = _getSubCollection(empresaId, _subCollectionTaxasEntrega).doc(taxa.id);
        batch.set(docRef, taxa.toMap());
        totalOperacoes++;
      }

      // Salvar Contas a Pagar
      for (final conta in contasPagar) {
        final docRef = _getSubCollection(empresaId, _subCollectionContasPagar).doc(conta.id);
        batch.set(docRef, conta.toMap());
        totalOperacoes++;
      }

      // Salvar NFC-es
      for (final nfce in nfces) {
        final docRef = _getSubCollection(empresaId, _subCollectionNFCes).doc(nfce.id);
        batch.set(docRef, nfce.toMap());
        totalOperacoes++;
      }

      // Salvar Sangrias de Caixa
      for (final sangria in sangrias) {
        final docRef = _getSubCollection(empresaId, _subCollectionSangrias).doc(sangria.id);
        batch.set(docRef, sangria.toMap());
        totalOperacoes++;
      }

      // Salvar Suprimentos de Caixa
      for (final suprimento in suprimentos) {
        final docRef = _getSubCollection(empresaId, _subCollectionSuprimentos).doc(suprimento.id);
        batch.set(docRef, suprimento.toMap());
        totalOperacoes++;
      }

      // NOTA: Mesas/Comandas são salvas individualmente via salvarMesaComanda()
      // quando são criadas/atualizadas, não precisam estar aqui no batch completo
      // pois são operações frequentes e devem ser salvas imediatamente

      // Salvar Links de Vendedores
      if (linksVendedores != null) {
        for (final link in linksVendedores) {
          final docRef = _getSubCollection(empresaId, _subCollectionLinksVendedores).doc(link.id);
          batch.set(docRef, link.toMap());
          totalOperacoes++;
        }
      }

      // Salvar Comissões de Vendedores
      if (comissoesVendedores != null) {
        for (final comissao in comissoesVendedores) {
          final docRef = _getSubCollection(empresaId, _subCollectionComissoesVendedores).doc(comissao.id);
          batch.set(docRef, comissao.toMap());
          totalOperacoes++;
        }
      }

      // Executar batch (limite do Firestore é 500 operações por batch)
      if (totalOperacoes > 0) {
        if (totalOperacoes <= 500) {
          // Aumentado para 45 segundos para lidar com conexões lentas ou batches grandes
          await batch.commit().timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              debugPrint('>>> [Firebase] ⚠️ Timeout ao salvar batch (45s)');
              throw TimeoutException('Timeout ao salvar batch no Firebase');
            },
          );
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
            agendamentosServico: agendamentosServico,
            notasEntrada: notasEntrada,
            funcionarios: funcionarios,
            taxasEntrega: taxasEntrega,
            contasPagar: contasPagar,
            nfces: nfces,
            sangrias: sangrias,
            suprimentos: suprimentos,
            linksVendedores: linksVendedores ?? [],
            comissoesVendedores: comissoesVendedores ?? [],
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
    required List<AgendamentoServico> agendamentosServico,
    required List<NotaEntrada> notasEntrada,
    required List<Funcionario> funcionarios,
    required List<TaxaEntrega> taxasEntrega,
    required List<ContaPagar> contasPagar,
    required List<NFCe> nfces,
    required List<SangriaCaixa> sangrias,
    required List<SuprimentoCaixa> suprimentos,
    List<LinkVendedor>? linksVendedores,
    List<ComissaoVendedor>? comissoesVendedores,
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
    await _salvarLista(empresaId, agendamentosServico, _subCollectionAgendamentosServico, (a) => a.id, (a) => a.toMap());
    await _salvarLista(empresaId, notasEntrada, _subCollectionNotasEntrada, (n) => n.id, (n) => n.toMap());
    await _salvarLista(empresaId, funcionarios, _subCollectionFuncionarios, (f) => f.id, (f) => f.toMap());
    await _salvarLista(empresaId, taxasEntrega, _subCollectionTaxasEntrega, (t) => t.id, (t) => t.toMap());
    await _salvarLista(empresaId, contasPagar, _subCollectionContasPagar, (c) => c.id, (c) => c.toMap());
    await _salvarLista(empresaId, nfces, _subCollectionNFCes, (n) => n.id, (n) => n.toMap());
    await _salvarLista(empresaId, sangrias, _subCollectionSangrias, (s) => s.id, (s) => s.toMap());
    await _salvarLista(empresaId, suprimentos, _subCollectionSuprimentos, (s) => s.id, (s) => s.toMap());
    if (linksVendedores != null) {
      await _salvarLista(empresaId, linksVendedores, _subCollectionLinksVendedores, (l) => l.id, (l) => l.toMap());
    }
    if (comissoesVendedores != null) {
      await _salvarLista(empresaId, comissoesVendedores, _subCollectionComissoesVendedores, (c) => c.id, (c) => c.toMap());
    }
  }

  Future<void> _salvarLista<T>(
    String empresaId,
    List<T> items,
    String subCollection,
    String Function(T) getId,
    Map<String, dynamic> Function(T) toMap,
  ) async {
    if (items.isEmpty) return;

    debugPrint('>>> [Firebase] Sincronizando $subCollection (${items.length} itens)...');
    
    // Salvar item por item em vez de batch para maior granularidade e evitar timeouts de lotes grandes
    int sucessos = 0;
    int falhas = 0;

    for (var item in items) {
      try {
        final id = getId(item);
        final docRef = _getSubCollection(empresaId, subCollection).doc(id);
        
        // Timeout individual de 15s por item
        await docRef.set(toMap(item)).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('Timeout no item $id'),
        );
        sucessos++;
      } catch (e) {
        falhas++;
        // Se for erro de cota, interrompemos a lista para não piorar
        if (e.toString().toLowerCase().contains('quota')) {
          debugPrint('>>> [Firebase] ⚠️ Cota excedida durante sync de $subCollection. Interrompendo...');
          break;
        }
      }
      
      // Pequeno delay para não "metralhar" o Firestore
      await Future.delayed(const Duration(milliseconds: 10));
    }
    
    debugPrint('>>> [Firebase] Finalizado $subCollection: $sucessos sucessos, $falhas falhas.');
  }

  /// Carrega todos os dados do Firebase para uma empresa específica
  /// [lastSync]: Se fornecido, busca apenas documentos atualizados após esta data
  Future<Map<String, dynamic>> carregarTudoDoFirebase(String empresaId, {DateTime? lastSync}) async {
    try {
      if (!isAvailable) throw Exception('Firebase não está disponível');
      if (empresaId.isEmpty) throw ArgumentError('empresaId não pode ser vazio');
      
      debugPrint('>>> [Firebase] 🔥 CARREGANDO TUDO DO FIREBASE - LastSync: $lastSync');
      
      final dados = <String, dynamic>{};

      Query _applyFilter(Query query) {
        if (lastSync == null) return query;
        return query.where('updatedAt', isGreaterThan: lastSync.toIso8601String());
      }
      
      // Carregar todas as subcoleções em paralelo
      final results = await Future.wait([
        _applyFilter(_getSubCollection(empresaId, _subCollectionClientes)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionProdutos)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionServicos)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionPedidos)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionOrdensServico)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionEntregas)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionVendasBalcao)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionTrocasDevolucoes)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionEstoqueHistorico)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionAberturasCaixa)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionFechamentosCaixa)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionMotoristas)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionAgendamentosServico)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionNotasEntrada)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionFuncionarios)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionTaxasEntrega)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionContasPagar)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionNFCes)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionSangrias)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionSuprimentos)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionMesasComandas)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionLinksVendedores)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionComissoesVendedores)).get(),
      ]).timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          debugPrint('>>> [Firebase] ⚠ Timeout ao carregar dados (45s)');
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
      dados['agendamentos_servico'] = results[12].docs.map((doc) => doc.data()).toList();
      dados['notas_entrada'] = results[13].docs.map((doc) => doc.data()).toList();
      dados['funcionarios'] = results[14].docs.map((doc) => doc.data()).toList();
      dados['taxas_entrega'] = results[15].docs.map((doc) => doc.data()).toList();
      dados['contas_pagar'] = results[16].docs.map((doc) => doc.data()).toList();
      dados['nfces'] = results[17].docs.map((doc) => doc.data()).toList();
      dados['sangrias'] = results[18].docs.map((doc) => doc.data()).toList();
      dados['suprimentos'] = results[19].docs.map((doc) => doc.data()).toList();
      dados['mesas_comandas'] = results[20].docs.map((doc) => doc.data()).toList();
      dados['links_vendedores'] = results[21].docs.map((doc) => doc.data()).toList();
      dados['comissoes_vendedores'] = results[22].docs.map((doc) => doc.data()).toList();

      debugPrint('>>> [Firebase] Carga concluída:');
      debugPrint('  - Clientes: ${dados['clientes'].length}');
      debugPrint('  - Produtos: ${dados['produtos'].length}');
      debugPrint('  - Pedidos: ${dados['pedidos'].length}');
      debugPrint('  - Agendamentos: ${dados['agendamentos_servico'].length}');
      debugPrint('  - Comissões Vendedores: ${dados['comissoes_vendedores'].length}');

      return dados;
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao carregar do Firebase: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Carrega APENAS os dados essenciais para o funcionamento da loja pública/agendamento

  /// Isso evita carregar milhares de documentos irrelevantes (estoque_historico, nfces, etc)
  /// e previne erros de Out of Memory (OOM)
  /// [lastSync]: Se fornecido, busca apenas documentos atualizados após esta data
  Future<Map<String, dynamic>> carregarDadosLevesDoFirebase(String empresaId, {DateTime? lastSync}) async {
    try {
      if (!isAvailable) throw Exception('Firebase não está disponível');
      if (empresaId.isEmpty) throw ArgumentError('empresaId não pode ser vazio');
      
      debugPrint('>>> [Firebase] ⚡ CARREGANDO DADOS LEVES (Modo Leve) - LastSync: $lastSync');
      
      final dados = <String, dynamic>{};

      Query _applyFilter(Query query) {
        if (lastSync == null) return query;
        return query.where('updatedAt', isGreaterThan: lastSync.toIso8601String());
      }

      // Carregar apenas o necessário: Produtos, Serviços, Agendamentos and Taxas de Entrega
      final results = await Future.wait([
        _applyFilter(_getSubCollection(empresaId, _subCollectionProdutos)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionServicos)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionAgendamentosServico)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionTaxasEntrega)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionFuncionarios)).get(),
        _applyFilter(_getSubCollection(empresaId, _subCollectionLinksVendedores)).get(),
      ]).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('>>> [Firebase] ⚠ Timeout ao carregar dados leves (30s)');
          throw TimeoutException('Timeout ao carregar dados essenciais do Firebase');
        },
      );

      dados['produtos'] = results[0].docs.map((doc) => doc.data()).toList();
      dados['servicos'] = results[1].docs.map((doc) => doc.data()).toList();
      dados['agendamentos_servico'] = results[2].docs.map((doc) => doc.data()).toList();
      dados['taxas_entrega'] = results[3].docs.map((doc) => doc.data()).toList();
      dados['funcionarios'] = results[4].docs.map((doc) => doc.data()).toList();
      dados['links_vendedores'] = results[5].docs.map((doc) => doc.data()).toList();

      // Inicializar listas vazias para os dados não carregados
      dados['clientes'] = [];
      dados['pedidos'] = [];
      dados['ordens_servico'] = [];
      dados['entregas'] = [];
      dados['vendas_balcao'] = [];
      dados['trocas_devolucoes'] = [];
      dados['estoque_historico'] = [];
      dados['aberturas_caixa'] = [];
      dados['fechamentos_caixa'] = [];
      dados['motoristas'] = [];
      dados['notas_entrada'] = [];
      dados['contas_pagar'] = [];
      dados['nfces'] = [];
      dados['sangrias'] = [];
      dados['suprimentos'] = [];
      dados['mesas_comandas'] = [];
      dados['comissoes_vendedores'] = [];

      debugPrint('>>> [Firebase] ⚡ Carga leve concluída para empresa: $empresaId');
      return dados;
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO na carga leve: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }


  /// Sincronizar dados (salvar tudo)
  /// Executa com timeout para evitar travamentos
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
    required List<AgendamentoServico> agendamentosServico,
    required List<NotaEntrada> notasEntrada,
    required List<Funcionario> funcionarios,
    required List<TaxaEntrega> taxasEntrega,
    required List<ContaPagar> contasPagar,
    required List<NFCe> nfces,
    required List<SangriaCaixa> sangrias,
    required List<SuprimentoCaixa> suprimentos,
    List<LinkVendedor>? linksVendedores,
    List<ComissaoVendedor>? comissoesVendedores,
  }) async {
    try {
      // Timeout de 30 segundos para evitar travamentos
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
        agendamentosServico: agendamentosServico,
        notasEntrada: notasEntrada,
        funcionarios: funcionarios,
        taxasEntrega: taxasEntrega,
        contasPagar: contasPagar,
        nfces: nfces,
        sangrias: sangrias,
        suprimentos: suprimentos,
        linksVendedores: linksVendedores,
        comissoesVendedores: comissoesVendedores,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('>>> [Firebase] ⚠️ Timeout ao sincronizar tudo (30s)');
          throw TimeoutException('Timeout ao sincronizar dados com Firebase');
        },
      );
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ❌ Erro ao sincronizar tudo: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
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


  /// Busca uma empresa específica pelo slug no Firebase (otimizado)
  Future<Empresa?> buscarEmpresaPorSlug(String slug) async {
    try {
      final slugLower = slug.toLowerCase().trim();
      debugPrint('>>> [Firebase] 🔍 Buscando empresa por slug: $slugLower');
      
      // Tentar buscar por slug
      final snapshotSlug = await _firestore.collection(_collectionEmpresas)
          .where('slug', isEqualTo: slugLower)
          .get();
          
      if (snapshotSlug.docs.isNotEmpty) {
        return Empresa.fromMap(snapshotSlug.docs.first.data());
      }
      
      // Tentar buscar por ID (caso o slug passado seja o ID)
      final docId = await _firestore.collection(_collectionEmpresas).doc(slugLower).get();
      if (docId.exists) {
        return Empresa.fromMap(docId.data()!);
      }
      
      debugPrint('>>> [Firebase] ❌ Empresa não encontrada para slug/ID: $slugLower');
      return null;
    } catch (e) {
      debugPrint('>>> [Firebase] ERRO ao buscar empresa por slug: $e');
      return null;
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

  // ============ MÉTODOS INDIVIDUAIS DE SALVAMENTO ============
  // 
  // PADRÃO PARA NOVOS MÉTODOS DE SALVAMENTO:
  // =========================================
  // Quando criar novos tipos de dados, SEMPRE criar métodos individuais aqui:
  // 
  // 1. Criar método salvar[Entidade](String empresaId, [Entidade] item)
  // 2. Criar método remover[Entidade](String empresaId, String itemId) se necessário
  // 3. Usar _getSubCollection(empresaId, _subCollection[Nome]) para obter a referência
  // 4. Adicionar a constante _subCollection[Nome] no topo da classe
  // 5. Adicionar no método salvarTudoNoFirebase e _salvarEmBatches
  // 6. Adicionar no método carregarTudoDoFirebase
  // 
  // Exemplo de estrutura:
  // static const String _subCollectionNovaEntidade = 'nova_entidade';
  // 
  // Future<void> salvarNovaEntidade(String empresaId, NovaEntidade item) async {
  //   try {
  //     final docRef = _getSubCollection(empresaId, _subCollectionNovaEntidade).doc(item.id);
  //     await docRef.set(item.toMap());
  //     debugPrint('>>> [Firebase] Nova entidade salva: ${item.nome} (ID: ${item.id})');
  //   } catch (e, stackTrace) {
  //     debugPrint('>>> [Firebase] ERRO ao salvar nova entidade: $e');
  //     debugPrint('>>> [Firebase] StackTrace: $stackTrace');
  //     rethrow;
  //   }
  // }
  // =========================================
  
  /// Salva um cliente individual no Firebase
  /// Com timeout para evitar travamentos
  Future<void> salvarCliente(String empresaId, Cliente cliente) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionClientes).doc(cliente.id);
      await docRef.set(cliente.toMap()).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('>>> [Firebase] ⚠️ Timeout ao salvar cliente (10s)');
          throw TimeoutException('Timeout ao salvar cliente no Firebase');
        },
      );
      debugPrint('>>> [Firebase] Cliente salvo: ${cliente.nome} (ID: ${cliente.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar cliente: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove um cliente do Firebase
  /// Com timeout para evitar travamentos
  Future<void> removerCliente(String empresaId, String clienteId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionClientes).doc(clienteId).delete().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('>>> [Firebase] ⚠️ Timeout ao remover cliente (10s)');
          throw TimeoutException('Timeout ao remover cliente do Firebase');
        },
      );
      debugPrint('>>> [Firebase] Cliente removido: $clienteId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover cliente: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Busca clientes por telefone no Firebase (para evitar carregar todos os clientes)
  Future<List<Cliente>> buscarClientesPorTelefone(String empresaId, String telefone) async {
    try {
      final normalizado = telefone.replaceAll(RegExp(r'\D'), '');
      if (normalizado.isEmpty) return [];

      debugPrint('>>> [Firebase] 🔍 Buscando cliente por telefone: $normalizado');
      
      // Tentar buscar por telefone e whatsapp
      final querySnapshotTelefone = await _getSubCollection(empresaId, _subCollectionClientes)
          .where('telefone', isEqualTo: normalizado)
          .get();
          
      final querySnapshotWhatsapp = await _getSubCollection(empresaId, _subCollectionClientes)
          .where('whatsapp', isEqualTo: normalizado)
          .get();

      // Combinar os resultados
      final docs = [...querySnapshotTelefone.docs, ...querySnapshotWhatsapp.docs];
      
      // Remover duplicados (pelo ID)
      final idsVistos = <String>{};
      final clientes = <Cliente>[];
      
      for (final doc in docs) {
        if (!idsVistos.contains(doc.id)) {
          idsVistos.add(doc.id);
          clientes.add(Cliente.fromMap(doc.data() as Map<String, dynamic>));
        }
      }
      
      debugPrint('>>> [Firebase] Found ${clientes.length} candidates for phone $normalizado');
      return clientes;
    } catch (e) {
      debugPrint('>>> [Firebase] Erro ao buscar cliente por telefone: $e');
      return [];
    }
  }


  /// Salva um produto individual no Firebase
  /// Com timeout para evitar travamentos
  Future<void> salvarProduto(String empresaId, Produto produto) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionProdutos).doc(produto.id);
      await docRef.set(produto.toMap()).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('>>> [Firebase] ⚠️ Timeout ao salvar produto (10s)');
          throw TimeoutException('Timeout ao salvar produto no Firebase');
        },
      );
      debugPrint('>>> [Firebase] Produto salvo: ${produto.nome} (ID: ${produto.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar produto: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove um produto do Firebase
  Future<void> removerProduto(String empresaId, String produtoId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionProdutos).doc(produtoId).delete();
      debugPrint('>>> [Firebase] Produto removido: $produtoId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover produto: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva um serviço individual no Firebase
  Future<void> salvarServico(String empresaId, Servico servico) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionServicos).doc(servico.id);
      await docRef.set(servico.toMap());
      debugPrint('>>> [Firebase] Serviço salvo: ${servico.nome} (ID: ${servico.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar serviço: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove um serviço do Firebase
  Future<void> removerServico(String empresaId, String servicoId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionServicos).doc(servicoId).delete();
      debugPrint('>>> [Firebase] Serviço removido: $servicoId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover serviço: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove um pedido do Firebase
  Future<void> removerPedido(String empresaId, String pedidoId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionPedidos).doc(pedidoId).delete();
      debugPrint('>>> [Firebase] Pedido removido: $pedidoId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover pedido: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove uma venda balcão do Firebase
  Future<void> removerVendaBalcao(String empresaId, String vendaId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionVendasBalcao).doc(vendaId).delete();
      debugPrint('>>> [Firebase] Venda balcão removida: $vendaId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover venda balcão: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva um pedido individual no Firebase
  Future<void> salvarPedido(String empresaId, Pedido pedido) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionPedidos).doc(pedido.id);
      await docRef.set(pedido.toMap());
      debugPrint('>>> [Firebase] Pedido salvo: ${pedido.numero} (ID: ${pedido.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar pedido: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma ordem de serviço individual no Firebase
  Future<void> salvarOrdemServico(String empresaId, OrdemServico ordem) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionOrdensServico).doc(ordem.id);
      await docRef.set(ordem.toMap());
      debugPrint('>>> [Firebase] Ordem de serviço salva: ${ordem.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar ordem de serviço: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma entrega individual no Firebase
  Future<void> salvarEntrega(String empresaId, Entrega entrega) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionEntregas).doc(entrega.id);
      await docRef.set(entrega.toMap());
      debugPrint('>>> [Firebase] Entrega salva: ${entrega.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar entrega: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma venda balcão individual no Firebase
  Future<void> salvarVendaBalcao(String empresaId, VendaBalcao venda) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionVendasBalcao).doc(venda.id);
      await docRef.set(venda.toMap());
      debugPrint('>>> [Firebase] Venda balcão salva: ${venda.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar venda balcão: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma troca/devolução individual no Firebase
  Future<void> salvarTrocaDevolucao(String empresaId, TrocaDevolucao troca) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionTrocasDevolucoes).doc(troca.id);
      await docRef.set(troca.toMap());
      debugPrint('>>> [Firebase] Troca/Devolução salva: ${troca.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar troca/devolução: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva um histórico de estoque individual no Firebase
  Future<void> salvarEstoqueHistorico(String empresaId, EstoqueHistorico historico) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionEstoqueHistorico).doc(historico.id);
      await docRef.set(historico.toMap());
      debugPrint('>>> [Firebase] Histórico de estoque salvo: ${historico.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar histórico de estoque: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma abertura de caixa individual no Firebase
  Future<void> salvarAberturaCaixa(String empresaId, AberturaCaixa abertura) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionAberturasCaixa).doc(abertura.id);
      await docRef.set(abertura.toMap());
      debugPrint('>>> [Firebase] Abertura de caixa salva: ${abertura.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar abertura de caixa: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva um fechamento de caixa individual no Firebase
  Future<void> salvarFechamentoCaixa(String empresaId, FechamentoCaixa fechamento) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionFechamentosCaixa).doc(fechamento.id);
      await docRef.set(fechamento.toMap());
      debugPrint('>>> [Firebase] Fechamento de caixa salvo: ${fechamento.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar fechamento de caixa: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva um motorista individual no Firebase
  Future<void> salvarMotorista(String empresaId, Motorista motorista) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionMotoristas).doc(motorista.id);
      await docRef.set(motorista.toMap());
      debugPrint('>>> [Firebase] Motorista salvo: ${motorista.nome} (ID: ${motorista.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar motorista: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva um agendamento de serviço individual no Firebase
  /// Com timeout para evitar travamentos
  Future<void> salvarAgendamentoServico(String empresaId, AgendamentoServico agendamento) async {
    try {
      debugPrint('>>> [Firebase] 🔥 INICIANDO salvamento de agendamento...');
      debugPrint('>>> [Firebase] Empresa ID: $empresaId');
      debugPrint('>>> [Firebase] Agendamento ID: ${agendamento.id}');
      debugPrint('>>> [Firebase] Número: ${agendamento.numero}');
      debugPrint('>>> [Firebase] Coleção: $_subCollectionAgendamentosServico');
      
      final docRef = _getSubCollection(empresaId, _subCollectionAgendamentosServico).doc(agendamento.id);
      debugPrint('>>> [Firebase] Referência do documento criada: ${docRef.path}');
      
      final dados = agendamento.toMap();
      debugPrint('>>> [Firebase] Dados convertidos para Map (${dados.length} campos)');
      debugPrint('>>> [Firebase] Campos principais: id=${dados['id']}, numero=${dados['numero']}, clienteId=${dados['clienteId']}');
      
      // Timeout aumentado para 30 segundos
    await docRef.set(dados).timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('>>> [Firebase] ⚠️ Timeout ao salvar agendamento (30s)');
        throw TimeoutException('Timeout ao salvar agendamento no Firebase');
      },
    );
      debugPrint('>>> [Firebase] ✅✅✅ DOCUMENTO SALVO NO FIRESTORE! ✅✅✅');
      debugPrint('>>> [Firebase] Caminho completo: ${docRef.path}');
      debugPrint('>>> [Firebase] ✅✅✅ AGENDAMENTO PERSISTIDO COM SUCESSO! ✅✅✅');
      debugPrint('>>> [Firebase] Este agendamento estará disponível mesmo em modo anônimo!');
      
      // Verificar se foi salvo corretamente (com timeout também)
      try {
        final docSnapshot = await docRef.get().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('>>> [Firebase] ⚠️ Timeout ao verificar agendamento (5s)');
            throw TimeoutException('Timeout ao verificar agendamento');
          },
        );
        if (docSnapshot.exists) {
          debugPrint('>>> [Firebase] ✅ Verificação: Documento existe no Firestore');
          final dadosVerificados = docSnapshot.data() as Map<String, dynamic>?;
          debugPrint('>>> [Firebase] Dados verificados: ${dadosVerificados?['numero'] ?? 'N/A'}');
        } else {
          debugPrint('>>> [Firebase] ⚠️ AVISO: Documento não encontrado após salvar!');
        }
      } catch (e) {
        debugPrint('>>> [Firebase] ⚠️ Erro ao verificar documento (mas foi salvo): $e');
        // Não re-throw - o documento já foi salvo, só a verificação falhou
      }
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ❌❌❌ ERRO CRÍTICO AO SALVAR AGENDAMENTO! ❌❌❌');
      debugPrint('>>> [Firebase] Tipo do erro: ${e.runtimeType}');
      debugPrint('>>> [Firebase] Mensagem: $e');
      debugPrint('>>> [Firebase] StackTrace completo:');
      debugPrint('>>> [Firebase] $stackTrace');
      rethrow;
    }
  }
  /// Obtém um stream de agendamentos de uma empresa para tempo real
  Stream<List<AgendamentoServico>> getAgendamentosStream(String empresaId) {
    debugPrint('>>> [Firebase] 📣 Criando novo Stream em: empresas/$empresaId/agendamentos_servico');
    return _getSubCollection(empresaId, _subCollectionAgendamentosServico)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        try {
          return AgendamentoServico.fromMap(doc.data() as Map<String, dynamic>);
        } catch (e) {
          debugPrint('>>> [Firebase] Erro ao converter agendamento do stream: $e');
          return null;
        }
      }).where((a) => a != null).cast<AgendamentoServico>().toList();
    });
  }

  /// Obtém um stream de produtos para tempo real
  Stream<List<Produto>> getProdutosStream(String empresaId) {
    debugPrint('>>> [Firebase] 📣 Criando novo Stream em: empresas/$empresaId/produtos');
    return _getSubCollection(empresaId, _subCollectionProdutos)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        try {
          return Produto.fromMap(doc.data() as Map<String, dynamic>);
        } catch (e) {
          debugPrint('>>> [Firebase] Erro ao converter produto do stream: $e');
          return null;
        }
      }).where((p) => p != null).cast<Produto>().toList();
    });
  }

  /// Obtém um stream de serviços para tempo real
  Stream<List<Servico>> getServicosStream(String empresaId) {
    debugPrint('>>> [Firebase] 📣 Criando novo Stream em: empresas/$empresaId/servicos');
    return _getSubCollection(empresaId, _subCollectionServicos)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        try {
          return Servico.fromMap(doc.data() as Map<String, dynamic>);
        } catch (e) {
          debugPrint('>>> [Firebase] Erro ao converter serviço do stream: $e');
          return null;
        }
      }).where((s) => s != null).cast<Servico>().toList();
    });
  }


  /// [DIAGNÓSTICO] Conta todos os documentos para verificar se existem no Firebase
  Future<int> contarAgendamentosPendentes(String empresaId) async {
    try {
      final snapshot = await _getSubCollection(empresaId, _subCollectionAgendamentosServico).get();
      return snapshot.size;
    } catch (e) {
      debugPrint('>>> [Firebase] Erro ao contar agendamentos: $e');
      return -1;
    }
  }


  /// Deleta um agendamento de serviço do Firebase
  Future<void> deletarAgendamentoServico(String empresaId, String agendamentoId) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionAgendamentosServico).doc(agendamentoId);
      
      await docRef.delete();
      debugPrint('>>> [Firebase] Agendamento deletado: $agendamentoId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao deletar agendamento: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma nota de entrada individual no Firebase
  Future<void> salvarNotaEntrada(String empresaId, NotaEntrada nota) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionNotasEntrada).doc(nota.id);
      await docRef.set(nota.toMap());
      debugPrint('>>> [Firebase] Nota de entrada salva: ${nota.numeroNota} (ID: ${nota.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar nota de entrada: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva um funcionário individual no Firebase
  Future<void> salvarFuncionario(String empresaId, Funcionario funcionario) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionFuncionarios).doc(funcionario.id);
      await docRef.set(funcionario.toMap());
      debugPrint('>>> [Firebase] Funcionário salvo: ${funcionario.nome} (ID: ${funcionario.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar funcionário: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove um funcionário do Firebase
  Future<void> removerFuncionario(String empresaId, String funcionarioId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionFuncionarios).doc(funcionarioId).delete();
      debugPrint('>>> [Firebase] Funcionário removido: $funcionarioId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover funcionário: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  // ============ CRUD LinkVendedor ============

  /// Salva um link de vendedor no Firebase
  Future<void> salvarLinkVendedor(String empresaId, LinkVendedor link) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionLinksVendedores).doc(link.id);
      await docRef.set(link.toMap());
      debugPrint('>>> [Firebase] Link de vendedor salvo: ${link.codigoLink} (ID: ${link.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar link de vendedor: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove um link de vendedor do Firebase
  Future<void> removerLinkVendedor(String empresaId, String linkId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionLinksVendedores).doc(linkId).delete();
      debugPrint('>>> [Firebase] Link de vendedor removido: $linkId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover link de vendedor: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  // ============ CRUD ComissaoVendedor ============

  /// Salva uma comissão de vendedor no Firebase
  Future<void> salvarComissaoVendedor(String empresaId, ComissaoVendedor comissao) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionComissoesVendedores).doc(comissao.id);
      await docRef.set(comissao.toMap());
      debugPrint('>>> [Firebase] Comissão de vendedor salva: ${comissao.pedidoNumero} (ID: ${comissao.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar comissão de vendedor: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Atualiza uma comissão de vendedor no Firebase
  Future<void> atualizarComissaoVendedor(String empresaId, ComissaoVendedor comissao) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionComissoesVendedores).doc(comissao.id);
      await docRef.update(comissao.toMap());
      debugPrint('>>> [Firebase] Comissão de vendedor atualizada: ${comissao.pedidoNumero} (ID: ${comissao.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao atualizar comissão de vendedor: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove uma comissão de vendedor do Firebase
  Future<void> removerComissaoVendedor(String empresaId, String comissaoId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionComissoesVendedores).doc(comissaoId).delete();
      debugPrint('>>> [Firebase] Comissão de vendedor removida: $comissaoId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover comissão de vendedor: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma taxa de entrega individual no Firebase
  Future<void> salvarTaxaEntrega(String empresaId, TaxaEntrega taxa) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionTaxasEntrega).doc(taxa.id);
      await docRef.set(taxa.toMap());
      debugPrint('>>> [Firebase] Taxa de entrega salva: ${taxa.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar taxa de entrega: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove uma taxa de entrega do Firebase
  Future<void> removerTaxaEntrega(String empresaId, String taxaId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionTaxasEntrega).doc(taxaId).delete();
      debugPrint('>>> [Firebase] Taxa de entrega removida: $taxaId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover taxa de entrega: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Deleta todas as taxas de entrega de uma empresa no Firebase
  Future<void> deletarTodasTaxasEntrega(String empresaId) async {
    try {
      final taxasRef = _getSubCollection(empresaId, _subCollectionTaxasEntrega);
      final snapshot = await taxasRef.get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('>>> [Firebase] Nenhuma taxa de entrega para deletar');
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
      
      debugPrint('>>> [Firebase] ✅ Total de $totalDeletados taxas de entrega deletadas com sucesso');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ❌ Erro ao deletar todas as taxas de entrega: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma conta a pagar individual no Firebase
  Future<void> salvarContaPagar(String empresaId, ContaPagar conta) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionContasPagar).doc(conta.id);
      await docRef.set(conta.toMap());
      debugPrint('>>> [Firebase] Conta a pagar salva: ${conta.numero ?? conta.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar conta a pagar: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove uma conta a pagar do Firebase
  Future<void> removerContaPagar(String empresaId, String contaId) async {
    try {
      await _getSubCollection(empresaId, _subCollectionContasPagar).doc(contaId).delete();
      debugPrint('>>> [Firebase] Conta a pagar removida: $contaId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover conta a pagar: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma NFC-e individual no Firebase
  Future<void> salvarNFCe(String empresaId, NFCe nfce) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionNFCes).doc(nfce.id);
      await docRef.set(nfce.toMap());
      debugPrint('>>> [Firebase] NFC-e salva: ${nfce.chaveAcesso}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar NFC-e: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma sangria de caixa individual no Firebase
  Future<void> salvarSangriaCaixa(String empresaId, SangriaCaixa sangria) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionSangrias).doc(sangria.id);
      await docRef.set(sangria.toMap());
      debugPrint('>>> [Firebase] Sangria de caixa salva: ${sangria.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar sangria de caixa: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva um suprimento de caixa individual no Firebase
  Future<void> salvarSuprimentoCaixa(String empresaId, SuprimentoCaixa suprimento) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionSuprimentos).doc(suprimento.id);
      await docRef.set(suprimento.toMap());
      debugPrint('>>> [Firebase] Suprimento de caixa salvo: ${suprimento.id}');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar suprimento de caixa: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva uma mesa/comanda no Firebase
  Future<void> salvarMesaComanda(String empresaId, MesaComanda mesaComanda) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionMesasComandas).doc(mesaComanda.id);
      await docRef.set(mesaComanda.toMap());
      debugPrint('>>> [Firebase] Mesa/Comanda salva: ${mesaComanda.numero} (ID: ${mesaComanda.id})');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao salvar mesa/comanda: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Remove uma mesa/comanda do Firebase
  Future<void> removerMesaComanda(String empresaId, String mesaComandaId) async {
    try {
      final docRef = _getSubCollection(empresaId, _subCollectionMesasComandas).doc(mesaComandaId);
      await docRef.delete();
      debugPrint('>>> [Firebase] Mesa/Comanda removida: $mesaComandaId');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ERRO ao remover mesa/comanda: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Deleta todos os produtos de uma empresa no Firebase
  Future<void> deletarTodosProdutos(String empresaId) async {
    try {
      final produtosRef = _getSubCollection(empresaId, _subCollectionProdutos);
      final snapshot = await produtosRef.get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('>>> [Firebase] Nenhum produto para deletar');
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

  /// Deleta todos os pedidos de uma empresa no Firebase
  Future<void> deletarTodosPedidos(String empresaId) async {
    try {
      final pedidosRef = _getSubCollection(empresaId, _subCollectionPedidos);
      final snapshot = await pedidosRef.get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('>>> [Firebase] Nenhum pedido para deletar');
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
      
      debugPrint('>>> [Firebase] ✅ Total de $totalDeletados pedidos deletados com sucesso');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ❌ Erro ao deletar todos os pedidos: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Deleta todas as vendas de balcão de uma empresa no Firebase
  Future<void> deletarTodasVendasBalcao(String empresaId) async {
    try {
      final vendasRef = _getSubCollection(empresaId, _subCollectionVendasBalcao);
      final snapshot = await vendasRef.get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('>>> [Firebase] Nenhuma venda para deletar');
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
      
      debugPrint('>>> [Firebase] ✅ Total de $totalDeletados vendas deletadas com sucesso');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ❌ Erro ao deletar todas as vendas: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Deleta todos os serviços de uma empresa no Firebase
  Future<void> deletarTodosServicos(String empresaId) async {
    try {
      final servicosRef = _getSubCollection(empresaId, _subCollectionServicos);
      final snapshot = await servicosRef.get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('>>> [Firebase] Nenhum serviço para deletar');
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
      
      debugPrint('>>> [Firebase] ✅ Total de $totalDeletados serviços deletados com sucesso');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ❌ Erro ao deletar todos os serviços: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Deleta todos os clientes de uma empresa no Firebase
  Future<void> deletarTodosClientes(String empresaId) async {
    try {
      final clientesRef = _getSubCollection(empresaId, _subCollectionClientes);
      final snapshot = await clientesRef.get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('>>> [Firebase] Nenhum cliente para deletar');
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
      
      debugPrint('>>> [Firebase] ✅ Total de $totalDeletados clientes deletados com sucesso');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ❌ Erro ao deletar todos os clientes: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Deleta todos os agendamentos de serviço de uma empresa no Firebase
  Future<void> deletarTodosAgendamentosServico(String empresaId) async {
    try {
      final agendamentosRef = _getSubCollection(empresaId, _subCollectionAgendamentosServico);
      final snapshot = await agendamentosRef.get();
      
      if (snapshot.docs.isEmpty) {
        debugPrint('>>> [Firebase] Nenhum agendamento para deletar');
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
      
      debugPrint('>>> [Firebase] ✅ Total de $totalDeletados agendamentos deletados com sucesso');
    } catch (e, stackTrace) {
      debugPrint('>>> [Firebase] ❌ Erro ao deletar todos os agendamentos: $e');
      debugPrint('>>> [Firebase] StackTrace: $stackTrace');
      rethrow;
    }
  }
}

