import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/ordem_servico.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/models/troca_devolucao.dart';
import 'package:sistema_exodo_novo/models/estoque_historico.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:flutter/foundation.dart';

// Re-export TipoPessoa para facilitar uso
export 'package:sistema_exodo_novo/models/cliente.dart' show TipoPessoa;

class DataService extends ChangeNotifier {
  List<EstoqueHistorico> get estoqueHistorico => _estoqueHistorico;
  // Dados locais (em memória)
  final List<Cliente> _clientes = [];
  final List<Produto> _produtos = [];
  final List<Servico> _tiposServico = [];
  final List<Pedido> _pedidos = [];
  final List<OrdemServico> _ordensServico = [];
  final List<Entrega> _entregas = [];
  final List<Motorista> _motoristas = [];
  final List<VendaBalcao> _vendasBalcao = [];
  final List<TrocaDevolucao> _trocasDevolucoes = [];
  final List<EstoqueHistorico> _estoqueHistorico = [];
  // Controle de caixa
  bool _caixaAberto = false; // Flag rápida para verificações de UI
  bool get caixaAberto => _caixaAberto;
  final List<AberturaCaixa> _aberturasCaixa = [];
  final List<FechamentoCaixa> _fechamentosCaixa = [];
  List<AberturaCaixa> get aberturasCaixa => _aberturasCaixa;
  List<FechamentoCaixa> get fechamentosCaixa => _fechamentosCaixa;

  /// Última abertura de caixa que ainda não possui fechamento
  AberturaCaixa? get aberturaCaixaAtual {
    if (_aberturasCaixa.isEmpty) return null;
    // Considerar como "aberta" a última abertura sem fechamento associado
    for (final abertura in _aberturasCaixa.reversed) {
      final temFechamento = _fechamentosCaixa.any(
        (f) => f.aberturaCaixaId == abertura.id,
      );
      if (!temFechamento) {
        return abertura;
      }
    }
    return null;
  }

  // Serviço de persistência
  final LocalStorageService _storage = LocalStorageService();
  bool _persistenciaHabilitada = true; // Flag para habilitar/desabilitar persistência

  // ID único para debug
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();
  String get instanceId => _instanceId;

  /// Método público para forçar atualização dos listeners
  void forceUpdate() {
    debugPrint(
      '>>> DataService.forceUpdate() chamado - instanceId: $_instanceId',
    );
    notifyListeners();
  }

  DataService() {
    // Não carregar dados fictícios no construtor
    // Eles serão carregados apenas se não houver dados salvos
    print('>>> DataService criado com instanceId: $_instanceId');
  }

  Future<void> iniciarSincronizacao() async {
    print('╔════════════════════════════════════════════════╗');
    print('║  INICIANDO CARREGAMENTO DE DADOS              ║');
    print('╚════════════════════════════════════════════════╝');
    
    // Primeiro, tentar carregar dados salvos
    await _carregarDadosSalvos();
    
    // Se não houver dados salvos, carregar dados fictícios
    if (_produtos.isEmpty) {
      print('>>> Nenhum produto salvo encontrado. Carregando dados fictícios...');
      _carregarProdutosFicticios();
      await _salvarTodosDados(); // Salvar dados fictícios para futuras sessões
    }
    
    if (_clientes.isEmpty) {
      print('>>> Nenhum cliente salvo encontrado. Carregando dados fictícios...');
      _carregarClientesFicticios();
      await _salvarTodosDados(); // Salvar dados fictícios para futuras sessões
    }
    
    if (_motoristas.isEmpty) {
      print('>>> Nenhum motorista salvo encontrado. Carregando dados fictícios...');
      _carregarMotoristasFicticios();
      await _salvarTodosDados(); // Salvar dados fictícios para futuras sessões
    }

    // Carregar status do caixa salvo (se existir) e ajustar com base nas aberturas/fechamentos
    _caixaAberto = await _storage.carregarStatusCaixaAberto();
    // Se as listas indicarem um estado diferente, priorizar o estado real do caixa
    if (aberturaCaixaAtual != null && !_caixaAberto) {
      _caixaAberto = true;
      await _storage.salvarStatusCaixaAberto(true);
    }
    if (aberturaCaixaAtual == null && _caixaAberto) {
      _caixaAberto = false;
      await _storage.salvarStatusCaixaAberto(false);
    }
    print('>>> Caixa atual: ${_caixaAberto ? "ABERTO" : "FECHADO"}');

    print('╔════════════════════════════════════════════════╗');
    print('║  CARREGAMENTO CONCLUÍDO                       ║');
    print('╚════════════════════════════════════════════════╝');
    print('>>> ${_produtos.length} produtos carregados');
    print('>>> ${_clientes.length} clientes carregados');
    print('>>> ${_motoristas.length} motoristas carregados');
    print('>>> ${_pedidos.length} pedidos carregados');
    print('>>> ${_vendasBalcao.length} vendas carregadas');
    print('>>> ${_trocasDevolucoes.length} trocas/devoluções carregadas');
    print('>>> Persistência: ${_persistenciaHabilitada ? "HABILITADA" : "DESABILITADA"}');
  }

  /// Gera o próximo número de caixa sequencial
  String getProximoNumeroCaixa() {
    try {
      final Set<int> numerosExistentes = {};

      // Buscar números nas aberturas de caixa
      if (_aberturasCaixa.isNotEmpty) {
        for (final abertura in _aberturasCaixa) {
          try {
            final match = RegExp(r'CAIXA-(\d+)').firstMatch(abertura.numero);
            if (match != null) {
              final numero = int.tryParse(match.group(1)!) ?? 0;
              if (numero > 0) {
                numerosExistentes.add(numero);
              }
            }
          } catch (e) {
            print('>>> Erro ao processar número de caixa: $e');
            // Continua processando outros números
          }
        }
      }

      // Encontrar o próximo número disponível
      int proximoNumero = 1;
      if (numerosExistentes.isNotEmpty) {
        try {
          proximoNumero = numerosExistentes.reduce((a, b) => a > b ? a : b) + 1;
        } catch (e) {
          print('>>> Erro ao calcular próximo número: $e');
          proximoNumero = _aberturasCaixa.length + 1;
        }
      }

      // Garantir que o número não existe (proteção extra)
      while (numerosExistentes.contains(proximoNumero)) {
        proximoNumero++;
      }

      return 'CAIXA-${proximoNumero.toString().padLeft(3, '0')}';
    } catch (e) {
      print('>>> Erro ao gerar número de caixa: $e');
      // Retorna um número baseado no timestamp como fallback
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return 'CAIXA-${(timestamp % 1000).toString().padLeft(3, '0')}';
    }
  }

  /// Abre o caixa com um valor inicial em dinheiro e persiste o status
  Future<AberturaCaixa> abrirCaixaComValor(double valorInicial,
      {String? observacao, String? responsavel}) async {
    try {
      // Se já houver um caixa aberto, apenas retorna a abertura atual
      if (caixaAberto && aberturaCaixaAtual != null) {
        return aberturaCaixaAtual!;
      }

      final numeroCaixa = getProximoNumeroCaixa();

      final abertura = AberturaCaixa(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        numero: numeroCaixa,
        dataAbertura: DateTime.now(),
        valorInicial: valorInicial,
        observacao: observacao,
        responsavel: responsavel,
      );

      _aberturasCaixa.add(abertura);
      _caixaAberto = true;
      
      try {
        await _storage.salvarStatusCaixaAberto(true);
      } catch (e) {
        print('>>> Erro ao salvar status do caixa: $e');
        // Continua mesmo se falhar ao salvar o status
      }
      
      try {
        _salvarAutomaticamente();
      } catch (e) {
        print('>>> Erro ao salvar automaticamente: $e');
        // Continua mesmo se falhar ao salvar automaticamente
      }
      
      notifyListeners();
      print('>>> Caixa ${numeroCaixa} aberto com R\$ ${valorInicial.toStringAsFixed(2)}');
      return abertura;
    } catch (e, stackTrace) {
      print('>>> ERRO ao abrir caixa: $e');
      print('>>> Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Método compatível antigo: abre o caixa com valor inicial 0
  Future<void> abrirCaixa() async {
    await abrirCaixaComValor(0);
  }

  /// Registra um fechamento de caixa com os valores esperado/real e persiste o status
  Future<FechamentoCaixa?> registrarFechamentoCaixa({
    required double valorEsperado,
    required double valorReal,
    double? diferenca,
    String? observacao,
    String? responsavel,
  }) async {
    final abertura = aberturaCaixaAtual;
    if (abertura == null) {
      debugPrint('>>> Aviso: tentar fechar caixa sem abertura atual');
      return null;
    }

    final diff = diferenca ?? (valorReal - valorEsperado);

    final fechamento = FechamentoCaixa(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      aberturaCaixaId: abertura.id,
      dataFechamento: DateTime.now(),
      valorEsperado: valorEsperado,
      valorReal: valorReal,
      diferenca: diff,
      sangrias: const [],
      observacao: observacao,
      responsavel: responsavel,
    );

    _fechamentosCaixa.add(fechamento);
    _caixaAberto = false;
    await _storage.salvarStatusCaixaAberto(false);
    _salvarAutomaticamente();
    notifyListeners();
    return fechamento;
  }

  /// Fecha o caixa e persiste o status (modo simplificado, sem valores)
  Future<void> fecharCaixa() async {
    if (!caixaAberto) return;
    await registrarFechamentoCaixa(
      valorEsperado: 0,
      valorReal: 0,
      diferenca: 0,
    );
  }

  void _carregarClientesFicticios() {
    final agora = DateTime.now();

    _clientes.addAll([
      Cliente(
        id: '1',
        nome: 'João Silva',
        tipoPessoa: TipoPessoa.fisica,
        cpfCnpj: '12345678901',
        email: 'joao.silva@email.com',
        telefone: '(11) 99999-1111',
        whatsapp: '11999991111',
        endereco: 'Rua das Flores',
        numero: '123',
        bairro: 'Centro',
        cidade: 'São Paulo',
        estado: 'SP',
        cep: '01234567',
        createdAt: agora,
        updatedAt: agora,
      ),
      Cliente(
        id: '2',
        nome: 'Maria Santos',
        tipoPessoa: TipoPessoa.fisica,
        cpfCnpj: '98765432100',
        email: 'maria.santos@email.com',
        telefone: '(11) 99999-2222',
        endereco: 'Av. Brasil',
        numero: '456',
        bairro: 'Jardim América',
        cidade: 'São Paulo',
        estado: 'SP',
        createdAt: agora,
        updatedAt: agora,
      ),
      Cliente(
        id: '3',
        nome: 'Pedro Oliveira',
        tipoPessoa: TipoPessoa.fisica,
        email: 'pedro.oliveira@email.com',
        telefone: '(11) 99999-3333',
        endereco: 'Rua do Comércio',
        numero: '789',
        bairro: 'Vila Nova',
        cidade: 'São Paulo',
        estado: 'SP',
        createdAt: agora,
        updatedAt: agora,
      ),
      Cliente(
        id: '4',
        nome: 'Ana Costa',
        tipoPessoa: TipoPessoa.fisica,
        email: 'ana.costa@email.com',
        telefone: '(11) 99999-4444',
        endereco: 'Praça da Matriz',
        numero: '50',
        bairro: 'Centro',
        cidade: 'São Paulo',
        estado: 'SP',
        limiteCredito: 5000,
        createdAt: agora,
        updatedAt: agora,
      ),
      Cliente(
        id: '5',
        nome: 'Carlos Ferreira',
        tipoPessoa: TipoPessoa.fisica,
        email: 'carlos.ferreira@email.com',
        telefone: '(11) 99999-5555',
        endereco: 'Rua Industrial',
        numero: '1000',
        bairro: 'Distrito Industrial',
        cidade: 'São Paulo',
        estado: 'SP',
        createdAt: agora,
        updatedAt: agora,
      ),
      Cliente(
        id: '6',
        nome: 'Empresa ABC Ltda',
        nomeFantasia: 'ABC Materiais',
        tipoPessoa: TipoPessoa.juridica,
        cpfCnpj: '12345678000199',
        rgIe: '123456789',
        email: 'contato@empresaabc.com.br',
        telefone: '(11) 3333-6666',
        endereco: 'Av. Empresarial',
        numero: '2000',
        bairro: 'Centro Empresarial',
        cidade: 'São Paulo',
        estado: 'SP',
        limiteCredito: 50000,
        createdAt: agora,
        updatedAt: agora,
      ),
      Cliente(
        id: '7',
        nome: 'Construtora XYZ S.A.',
        nomeFantasia: 'Construtora XYZ',
        tipoPessoa: TipoPessoa.juridica,
        cpfCnpj: '98765432000188',
        email: 'orcamento@construtoraxyz.com.br',
        telefone: '(11) 3333-7777',
        endereco: 'Rua das Obras',
        numero: '500',
        bairro: 'Bairro Novo',
        cidade: 'São Paulo',
        estado: 'SP',
        limiteCredito: 100000,
        createdAt: agora,
        updatedAt: agora,
      ),
      Cliente(
        id: '8',
        nome: 'Marcelo Almeida',
        tipoPessoa: TipoPessoa.fisica,
        email: 'marcelo.almeida@gmail.com',
        telefone: '(11) 99999-8888',
        whatsapp: '11999998888',
        endereco: 'Rua dos Pinheiros',
        numero: '321',
        bairro: 'Pinheiros',
        cidade: 'São Paulo',
        estado: 'SP',
        profissao: 'Engenheiro',
        createdAt: agora,
        updatedAt: agora,
      ),
    ]);
  }

  void _carregarProdutosFicticios() {
    final agora = DateTime.now();

    _produtos.addAll([
      Produto(
        id: '1',
        codigo: 'COD-1',
        codigoBarras: '7891234567890',
        nome: 'Parafuso Phillips 4x40mm',
        descricao: 'Parafuso cabeca Phillips aco zincado',
        unidade: 'UN',
        grupo: 'Parafusos',
        preco: 0.15,
        estoque: 500,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '2',
        codigo: 'COD-2',
        codigoBarras: '7891234567891',
        nome: 'Porca Sextavada M8',
        descricao: 'Porca sextavada aco carbono M8',
        unidade: 'UN',
        grupo: 'Porcas',
        preco: 0.25,
        estoque: 300,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '3',
        codigo: 'COD-3',
        codigoBarras: '7891234567892',
        nome: 'Arruela Lisa 8mm',
        descricao: 'Arruela lisa aco zincado 8mm',
        unidade: 'UN',
        grupo: 'Arruelas',
        preco: 0.10,
        estoque: 800,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '4',
        codigo: 'COD-4',
        codigoBarras: '7891234567893',
        nome: 'Chave de Fenda 1/4"',
        descricao: 'Chave de fenda ponta chata 1/4 polegada',
        unidade: 'UN',
        grupo: 'Ferramentas',
        preco: 12.90,
        estoque: 25,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '5',
        codigo: 'COD-5',
        codigoBarras: '7891234567894',
        nome: 'Martelo Unha 27mm',
        descricao: 'Martelo unha cabo madeira 27mm',
        unidade: 'UN',
        grupo: 'Ferramentas',
        preco: 35.00,
        estoque: 15,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '6',
        codigo: 'COD-6',
        codigoBarras: '7891234567895',
        nome: 'Fita Isolante 19mm x 10m',
        descricao: 'Fita isolante preta 19mm x 10 metros',
        unidade: 'UN',
        grupo: 'Eletrica',
        preco: 5.50,
        estoque: 100,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '7',
        codigo: 'COD-7',
        codigoBarras: '7891234567896',
        nome: 'Cabo Flexivel 2.5mm Azul',
        descricao: 'Cabo flexivel 2.5mm azul - metro',
        unidade: 'MT',
        grupo: 'Eletrica',
        preco: 3.20,
        estoque: 250,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '8',
        codigo: 'COD-8',
        codigoBarras: '7891234567897',
        nome: 'Tomada 2P+T 10A',
        descricao: 'Tomada 2 pinos + terra 10 amperes',
        unidade: 'UN',
        grupo: 'Eletrica',
        preco: 8.90,
        estoque: 45,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '9',
        codigo: 'COD-9',
        codigoBarras: '7891234567898',
        nome: 'Cano PVC 25mm 6m',
        descricao: 'Cano PVC soldavel 25mm barra 6 metros',
        unidade: 'BR',
        grupo: 'Hidraulica',
        preco: 15.80,
        estoque: 30,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '10',
        codigo: 'COD-10',
        codigoBarras: '7891234567899',
        nome: 'Joelho PVC 25mm 90',
        descricao: 'Joelho PVC soldavel 25mm 90 graus',
        unidade: 'UN',
        grupo: 'Hidraulica',
        preco: 1.50,
        estoque: 120,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '11',
        codigo: 'COD-11',
        codigoBarras: '7891234567900',
        nome: 'Tinta Latex Branco 18L',
        descricao: 'Tinta latex acrilica branco neve 18 litros',
        unidade: 'GL',
        grupo: 'Tintas',
        preco: 189.90,
        estoque: 12,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '12',
        codigo: 'COD-12',
        codigoBarras: '7891234567901',
        nome: 'Rolo de Pintura 23cm',
        descricao: 'Rolo para pintura la sintetica 23cm',
        unidade: 'UN',
        grupo: 'Tintas',
        preco: 18.50,
        estoque: 20,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '13',
        codigo: 'COD-13',
        codigoBarras: '7891234567902',
        nome: 'Lixa Madeira 120',
        descricao: 'Lixa para madeira grao 120',
        unidade: 'UN',
        grupo: 'Abrasivos',
        preco: 2.80,
        estoque: 150,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '14',
        codigo: 'COD-14',
        codigoBarras: '7891234567903',
        nome: 'Disco de Corte 4.5"',
        descricao: 'Disco de corte fino 4.5 polegadas',
        unidade: 'UN',
        grupo: 'Abrasivos',
        preco: 6.90,
        estoque: 80,
        createdAt: agora,
        updatedAt: agora,
      ),
      Produto(
        id: '15',
        codigo: 'COD-15',
        codigoBarras: '7891234567904',
        nome: 'Cadeado 40mm',
        descricao: 'Cadeado latao 40mm com 2 chaves',
        unidade: 'UN',
        grupo: 'Seguranca',
        preco: 28.00,
        estoque: 35,
        createdAt: agora,
        updatedAt: agora,
      ),
    ]);
  }

  // Getters
  List<Cliente> get clientes => _clientes;
  List<Produto> get produtos => _produtos;
  List<Servico> get tiposServico => _tiposServico;
  List<OrdemServico> get ordensServico => _ordensServico;
  List<Servico> get servicos => _tiposServico;
  List<Pedido> get pedidos => _pedidos;
  List<Entrega> get entregas => _entregas;
  List<Motorista> get motoristas => _motoristas;
  List<VendaBalcao> get vendasBalcao => _vendasBalcao;
  List<TrocaDevolucao> get trocasDevolucoes => _trocasDevolucoes;

  /// MÉTODO ESPECÍFICO para atualizar valor após troca
  /// Busca pelo número e atualiza o valorTotal diretamente
  bool atualizarValorVendaAposTroca({
    required String numeroVenda,
    required double novoValor,
    required List<ItemVendaBalcao> novosItens,
  }) {
    debugPrint('');
    debugPrint('╔════════════════════════════════════════════════╗');
    debugPrint('║  ATUALIZANDO VALOR DA VENDA APÓS TROCA         ║');
    debugPrint('╚════════════════════════════════════════════════╝');
    debugPrint('>>> Número: $numeroVenda');
    debugPrint('>>> Novo valor: R\$$novoValor');
    debugPrint('>>> Novos itens: ${novosItens.length}');
    debugPrint('>>> Total vendas: ${_vendasBalcao.length}');

    for (int i = 0; i < _vendasBalcao.length; i++) {
      if (_vendasBalcao[i].numero == numeroVenda) {
        final vendaAntiga = _vendasBalcao[i];
        debugPrint('>>> ENCONTROU no índice $i');
        debugPrint('>>> Valor antigo: R\$${vendaAntiga.valorTotal}');

        // Criar nova venda com valor atualizado
        _vendasBalcao[i] = VendaBalcao(
          id: vendaAntiga.id,
          numero: vendaAntiga.numero,
          dataVenda: vendaAntiga.dataVenda,
          clienteId: vendaAntiga.clienteId,
          clienteNome: vendaAntiga.clienteNome,
          clienteTelefone: vendaAntiga.clienteTelefone,
          itens: novosItens,
          tipoPagamento: vendaAntiga.tipoPagamento,
          valorTotal: novoValor,
          valorRecebido: novoValor,
          troco: 0,
          operador: vendaAntiga.operador,
          observacoes: vendaAntiga.observacoes,
          createdAt: vendaAntiga.createdAt,
        );

        debugPrint(
          '>>> Valor atualizado para: R\$${_vendasBalcao[i].valorTotal}',
        );
        debugPrint('>>> Chamando notifyListeners...');
        notifyListeners();
        debugPrint('>>> ✓ SUCESSO!');
        return true;
      }
    }

    debugPrint('>>> ✗ VENDA NÃO ENCONTRADA!');
    return false;
  }

  // ============ CRUD Cliente ============

  Future<void> addCliente(Cliente cliente) async {
    _clientes.add(cliente);
    notifyListeners();
    _salvarAutomaticamente();
  }

  void updateCliente(Cliente cliente) {
    final index = _clientes.indexWhere((c) => c.id == cliente.id);
    if (index != -1) {
      _clientes[index] = cliente;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteCliente(String id) {
    _clientes.removeWhere((c) => c.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  // ============ CRUD Produto ============

  Future<void> addProduto(Produto produto) async {
    _produtos.add(produto);
    notifyListeners();
    _salvarAutomaticamente();
  }

  Future<void> updateProduto(Produto produto) async {
    final index = _produtos.indexWhere((p) => p.id == produto.id);
    if (index != -1) {
      _produtos[index] = produto;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteProduto(String id) {
    _produtos.removeWhere((p) => p.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  // ============ CRUD Servico ============

  Future<void> addTipoServico(Servico servico) async {
    _tiposServico.add(servico);
    notifyListeners();
  }

  Future<void> addServico(Servico servico) async {
    await addTipoServico(servico);
  }

  void updateTipoServico(Servico servico) {
    final index = _tiposServico.indexWhere((s) => s.id == servico.id);
    if (index != -1) {
      _tiposServico[index] = servico;
      notifyListeners();
    }
  }

  void deleteTipoServico(String id) {
    _tiposServico.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  // ============ CRUD Ordem de Servico ============

  Future<void> addOrdemServico(OrdemServico os) async {
    _ordensServico.add(os);
    notifyListeners();
  }

  void updateOrdemServico(OrdemServico os) {
    final index = _ordensServico.indexWhere((o) => o.id == os.id);
    if (index != -1) {
      _ordensServico[index] = os;
      notifyListeners();
    }
  }

  void deleteOrdemServico(String id) {
    _ordensServico.removeWhere((o) => o.id == id);
    notifyListeners();
  }

  // ============ CRUD Pedido ============

  Future<void> addPedido(Pedido pedido) async {
    // Verificar se algum serviço tem valor adicional e cadastrar automaticamente
    for (final itemServico in pedido.servicos) {
      if (itemServico.valorAdicional > 0) {
        // Verificar se já existe um serviço com esse nome e preço total
        final precoTotal = itemServico.valor + itemServico.valorAdicional;
        final nomeServico = itemServico.descricaoAdicional != null && 
                           itemServico.descricaoAdicional!.isNotEmpty
            ? '${itemServico.descricao} - ${itemServico.descricaoAdicional}'
            : '${itemServico.descricao} (com adicional)';
        
        // Verificar se já existe um serviço similar
        final servicoExistente = _tiposServico.firstWhere(
          (s) => s.nome == nomeServico && s.preco == precoTotal,
          orElse: () => Servico(
            id: '',
            nome: '',
            preco: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        
        // Se não existe, cadastrar novo serviço
        if (servicoExistente.id.isEmpty) {
          final novoServico = Servico(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            nome: nomeServico,
            descricao: itemServico.descricaoAdicional ?? 
                      'Serviço com valor adicional de R\$ ${itemServico.valorAdicional.toStringAsFixed(2)}',
            preco: precoTotal,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await addTipoServico(novoServico);
        }
      }
    }
    
    _pedidos.add(pedido);
    notifyListeners();
    _salvarAutomaticamente();
  }

  void updatePedido(Pedido pedido) {
    // Verificar se algum serviço tem valor adicional e cadastrar automaticamente
    for (final itemServico in pedido.servicos) {
      if (itemServico.valorAdicional > 0) {
        // Verificar se já existe um serviço com esse nome e preço total
        final precoTotal = itemServico.valor + itemServico.valorAdicional;
        final nomeServico = itemServico.descricaoAdicional != null && 
                           itemServico.descricaoAdicional!.isNotEmpty
            ? '${itemServico.descricao} - ${itemServico.descricaoAdicional}'
            : '${itemServico.descricao} (com adicional)';
        
        // Verificar se já existe um serviço similar
        final servicoExistente = _tiposServico.firstWhere(
          (s) => s.nome == nomeServico && s.preco == precoTotal,
          orElse: () => Servico(
            id: '',
            nome: '',
            preco: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        
        // Se não existe, cadastrar novo serviço
        if (servicoExistente.id.isEmpty) {
          final novoServico = Servico(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            nome: nomeServico,
            descricao: itemServico.descricaoAdicional ?? 
                      'Serviço com valor adicional de R\$ ${itemServico.valorAdicional.toStringAsFixed(2)}',
            preco: precoTotal,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          addTipoServico(novoServico);
        }
      }
    }
    
    final index = _pedidos.indexWhere((p) => p.id == pedido.id);
    debugPrint('>>> DataService.updatePedido: id=${pedido.id}, index=$index');
    debugPrint('>>> Novo total: ${pedido.total}');
    debugPrint('>>> Novo totalRecebido: ${pedido.totalRecebido}');
    if (index != -1) {
      _pedidos[index] = pedido;
      debugPrint('>>> Pedido atualizado na posição $index');
      notifyListeners();
      debugPrint('>>> notifyListeners() chamado');
      _salvarAutomaticamente();
    } else {
      debugPrint('>>> ERRO: Pedido não encontrado para atualizar!');
    }
  }

  void deletePedido(String id) {
    _pedidos.removeWhere((p) => p.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  // ============ Metodos auxiliares ============

  List<Servico> getServicosPorCliente(String clienteId) {
    return _tiposServico;
  }

  // ============ CRUD Entrega ============

  Future<void> addEntrega(Entrega entrega) async {
    _entregas.add(entrega);
    notifyListeners();
  }

  void updateEntrega(Entrega entrega) {
    final index = _entregas.indexWhere((e) => e.id == entrega.id);
    if (index != -1) {
      _entregas[index] = entrega;
      notifyListeners();
    }
  }

  void deleteEntrega(String id) {
    _entregas.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  Entrega? getEntregaPorPedido(String pedidoId) {
    try {
      return _entregas.firstWhere((e) => e.pedidoId == pedidoId);
    } catch (_) {
      return null;
    }
  }

  // ============ CRUD Motorista ============

  Future<void> addMotorista(Motorista motorista) async {
    _motoristas.add(motorista);
    notifyListeners();
  }

  void updateMotorista(Motorista motorista) {
    final index = _motoristas.indexWhere((m) => m.id == motorista.id);
    if (index != -1) {
      _motoristas[index] = motorista;
      notifyListeners();
    }
  }

  void deleteMotorista(String id) {
    _motoristas.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  // ============ CRUD Venda Balcão ============

  Future<void> addVendaBalcao(VendaBalcao venda) async {
    _vendasBalcao.add(venda);
    print('✓ Venda ${venda.numero} salva em memória');
    notifyListeners();
    _salvarAutomaticamente();
  }

  Future<void> updateVendaBalcao(VendaBalcao venda) async {
    print(
      '>>> updateVendaBalcao chamado para: ${venda.numero} (id=${venda.id})',
    );
    print('>>> Itens da venda atualizada:');
    for (final i in venda.itens) {
      print(
        '>>>   - ${i.nome}: qtdTrocada=${i.quantidadeTrocada}, trocadoPor=${i.trocadoPor}',
      );
    }

    var index = _vendasBalcao.indexWhere((v) => v.id == venda.id);
    print('>>> Index encontrado por ID: $index');

    // Se não encontrou pelo ID, tentar pelo número
    if (index == -1) {
      index = _vendasBalcao.indexWhere((v) => v.numero == venda.numero);
      print('>>> Index encontrado por número: $index');
    }

    print('>>> Total vendas: ${_vendasBalcao.length}');

    if (index != -1) {
      _vendasBalcao[index] = venda;
      print(
        '✓ Venda ${venda.numero} atualizada em memória com valorTotal=${venda.valorTotal}',
      );
      notifyListeners();
      _salvarAutomaticamente();
    } else {
      print('!!! ERRO: Venda não encontrada para atualizar !!!');
      // Listar todas as vendas para debug
      for (var i = 0; i < _vendasBalcao.length; i++) {
        final v = _vendasBalcao[i];
        print('  [$i] id=${v.id}, numero=${v.numero}');
      }
    }
  }

  Future<void> deleteVendaBalcao(String id) async {
    _vendasBalcao.removeWhere((v) => v.id == id);
    print('✓ Venda removida da memória');
    notifyListeners();
    _salvarAutomaticamente();
  }

  /// Atualiza uma venda pelo número (mais confiável que ID)
  Future<bool> updateVendaBalcaoPorNumero(
    String numero,
    VendaBalcao vendaAtualizada,
  ) async {
    print('>>> updateVendaBalcaoPorNumero: $numero (instanceId: $_instanceId)');
    print('>>> Procurando em ${_vendasBalcao.length} vendas');

    for (var i = 0; i < _vendasBalcao.length; i++) {
      print('>>>   [$i] numero="${_vendasBalcao[i].numero}"');
    }

    final index = _vendasBalcao.indexWhere((v) => v.numero == numero);
    if (index != -1) {
      _vendasBalcao[index] = vendaAtualizada;
      print(
        '✓ Venda $numero atualizada (index=$index, novo valor=${vendaAtualizada.valorTotal})',
      );
      for (final i in vendaAtualizada.itens) {
        if (i.quantidadeTrocada > 0) {
          print(
            '  - ${i.nome}: trocada=${i.quantidadeTrocada}, por=${i.trocadoPor}',
          );
        }
      }
      print('>>> Chamando notifyListeners()...');
      notifyListeners();
      print('>>> notifyListeners() chamado!');
      _salvarAutomaticamente();
      return true;
    }
    print('!!! Venda $numero NÃO encontrada');
    return false;
  }

  // ============ CRUD Troca/Devolução ============

  Future<void> addTrocaDevolucao(TrocaDevolucao troca) async {
    _trocasDevolucoes.add(troca);
    print('✓ Troca/Devolução ${troca.id} salva em memória');
    notifyListeners();
    _salvarAutomaticamente();
  }

  Future<void> updateTrocaDevolucao(TrocaDevolucao troca) async {
    final index = _trocasDevolucoes.indexWhere((t) => t.id == troca.id);
    if (index != -1) {
      _trocasDevolucoes[index] = troca;
      print('✓ Troca/Devolução ${troca.id} atualizada em memória');
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  Future<void> deleteTrocaDevolucao(String id) async {
    _trocasDevolucoes.removeWhere((t) => t.id == id);
    print('✓ Troca/Devolução removida da memória');
    notifyListeners();
    _salvarAutomaticamente();
  }

  // Trocas/devoluções por período
  List<TrocaDevolucao> getTrocasPorPeriodo(DateTime inicio, DateTime fim) {
    return _trocasDevolucoes.where((t) {
      return t.dataOperacao.isAfter(inicio.subtract(const Duration(days: 1))) &&
          t.dataOperacao.isBefore(fim.add(const Duration(days: 1)));
    }).toList()..sort((a, b) => b.dataOperacao.compareTo(a.dataOperacao));
  }

  // Total de devoluções do dia
  double get totalDevolucoesDoDia {
    final hoje = DateTime.now();
    return _trocasDevolucoes
        .where(
          (t) =>
              t.tipo == TipoOperacao.devolucao &&
              t.dataOperacao.year == hoje.year &&
              t.dataOperacao.month == hoje.month &&
              t.dataOperacao.day == hoje.day,
        )
        .fold(0.0, (sum, t) => sum + t.valorDevolvido);
  }

  // Total de trocas do dia
  int get totalTrocasDoDia {
    final hoje = DateTime.now();
    return _trocasDevolucoes
        .where(
          (t) =>
              t.tipo == TipoOperacao.troca &&
              t.dataOperacao.year == hoje.year &&
              t.dataOperacao.month == hoje.month &&
              t.dataOperacao.day == hoje.day,
        )
        .length;
  }

  // Próximo número de venda (considera vendas balcão E pedidos para evitar duplicados)
  String getProximoNumeroVenda() {
    // Coletar todos os números existentes
    final Set<int> numerosExistentes = {};

    // Buscar números nas vendas balcão
    for (final venda in _vendasBalcao) {
      final match = RegExp(r'VND-(\d+)').firstMatch(venda.numero);
      if (match != null) {
        final numero = int.tryParse(match.group(1)!) ?? 0;
        numerosExistentes.add(numero);
      }
    }

    // Buscar números nos pedidos
    for (final pedido in _pedidos) {
      final match = RegExp(r'VND-(\d+)').firstMatch(pedido.numero);
      if (match != null) {
        final numero = int.tryParse(match.group(1)!) ?? 0;
        numerosExistentes.add(numero);
      }
    }

    // Encontrar o próximo número disponível
    int proximoNumero = 1;
    if (numerosExistentes.isNotEmpty) {
      // Pegar o maior número e adicionar 1
      proximoNumero = numerosExistentes.reduce((a, b) => a > b ? a : b) + 1;
    }

    // Garantir que o número não existe (proteção extra)
    while (numerosExistentes.contains(proximoNumero)) {
      proximoNumero++;
    }

    return 'VND-${proximoNumero.toString().padLeft(4, '0')}';
  }

  // Próximo número de serviço (SRV-0001, SRV-0002, etc)
  String getProximoNumeroServico() {
    // Coletar todos os números existentes de serviços
    final Set<int> numerosExistentes = {};

    // Buscar números nos pedidos que começam com SRV-
    for (final pedido in _pedidos) {
      final match = RegExp(r'SRV-(\d+)').firstMatch(pedido.numero);
      if (match != null) {
        final numero = int.tryParse(match.group(1)!) ?? 0;
        numerosExistentes.add(numero);
      }
    }

    // Encontrar o próximo número disponível
    int proximoNumero = 1;
    if (numerosExistentes.isNotEmpty) {
      // Pegar o maior número e adicionar 1
      proximoNumero = numerosExistentes.reduce((a, b) => a > b ? a : b) + 1;
    }

    // Garantir que o número não existe (proteção extra)
    while (numerosExistentes.contains(proximoNumero)) {
      proximoNumero++;
    }

    return 'SRV-${proximoNumero.toString().padLeft(4, '0')}';
  }

  // Migra pedidos antigos que não têm número válido
  void migrarPedidosSemNumero() {
    bool houveMudanca = false;

    for (int i = 0; i < _pedidos.length; i++) {
      final pedido = _pedidos[i];
      // Se o número está vazio ou não começa com VND-
      if (pedido.numero.isEmpty || !pedido.numero.startsWith('VND-')) {
        final novoNumero = getProximoNumeroVenda();
        _pedidos[i] = pedido.copyWith(numero: novoNumero);
        houveMudanca = true;
      }
    }

    if (houveMudanca) {
      notifyListeners();
    }
  }

  // Vendas do dia
  List<VendaBalcao> get vendasDoDia {
    final hoje = DateTime.now();
    return _vendasBalcao.where((v) {
      return v.dataVenda.year == hoje.year &&
          v.dataVenda.month == hoje.month &&
          v.dataVenda.day == hoje.day;
    }).toList()..sort((a, b) => b.dataVenda.compareTo(a.dataVenda));
  }

  // Total vendido hoje
  double get totalVendidoHoje {
    return vendasDoDia.fold(0.0, (sum, v) => sum + v.valorTotal);
  }

  // Vendas por período (considera data e horário)
  List<VendaBalcao> getVendasPorPeriodo(DateTime inicio, DateTime fim) {
    return _vendasBalcao.where((v) {
      // Comparar considerando data e horário (incluindo os limites)
      return v.dataVenda.compareTo(inicio) >= 0 && v.dataVenda.compareTo(fim) <= 0;
    }).toList()..sort((a, b) => b.dataVenda.compareTo(a.dataVenda));
  }

  /// Busca uma venda pelo número - retorna a venda atual do DataService
  VendaBalcao? getVendaPorNumero(String numero) {
    print(
      '>>> getVendaPorNumero("$numero") - buscando em ${_vendasBalcao.length} vendas',
    );
    for (final v in _vendasBalcao) {
      print(
        '>>>   Comparando "$numero" com "${v.numero}" = ${numero == v.numero}',
      );
      if (v.numero == numero) {
        print('>>> ENCONTROU! valorTotal=${v.valorTotal}');
        for (final i in v.itens) {
          if (i.quantidadeTrocada > 0) {
            print(
              '>>>   Item ${i.nome}: trocada=${i.quantidadeTrocada}, por=${i.trocadoPor}',
            );
          }
        }
        return v;
      }
    }
    print('>>> NÃO encontrou venda com numero "$numero"');
    return null;
  }

  // ============ Dados Ficticios Motoristas ============

  void _carregarMotoristasFicticios() {
    final agora = DateTime.now();

    _motoristas.addAll([
      Motorista(
        id: '1',
        nome: 'José Carlos',
        telefone: '(11) 98888-1111',
        cpf: '123.456.789-00',
        cnh: '12345678901',
        veiculoModelo: 'Fiat Fiorino',
        veiculoPlaca: 'ABC-1234',
        ativo: true,
        dataCadastro: agora,
      ),
      Motorista(
        id: '2',
        nome: 'Marcos Silva',
        telefone: '(11) 98888-2222',
        cpf: '987.654.321-00',
        cnh: '98765432101',
        veiculoModelo: 'VW Saveiro',
        veiculoPlaca: 'DEF-5678',
        ativo: true,
        dataCadastro: agora,
      ),
      Motorista(
        id: '3',
        nome: 'Roberto Santos',
        telefone: '(11) 98888-3333',
        cpf: '456.789.123-00',
        cnh: '45678912301',
        veiculoModelo: 'Renault Kangoo',
        veiculoPlaca: 'GHI-9012',
        ativo: true,
        dataCadastro: agora,
      ),
    ]);
  }

  // ============ Métodos de Persistência ============

  /// Carrega todos os dados salvos do localStorage
  Future<void> _carregarDadosSalvos() async {
    try {
      print('>>> Carregando dados salvos do localStorage...');

      // Carregar clientes
      final clientesMap = await _storage.carregarLista(LocalStorageService.keyClientes);
      if (clientesMap.isNotEmpty) {
        _clientes.clear();
        _clientes.addAll(clientesMap.map((map) => Cliente.fromMap(map)));
        print('>>> ✓ ${_clientes.length} clientes carregados');
      }

      // Carregar produtos
      final produtosMap = await _storage.carregarLista(LocalStorageService.keyProdutos);
      if (produtosMap.isNotEmpty) {
        _produtos.clear();
        _produtos.addAll(produtosMap.map((map) => Produto.fromMap(map)));
        print('>>> ✓ ${_produtos.length} produtos carregados');
      }

      // Carregar serviços
      final servicosMap = await _storage.carregarLista(LocalStorageService.keyServicos);
      if (servicosMap.isNotEmpty) {
        _tiposServico.clear();
        _tiposServico.addAll(servicosMap.map((map) => Servico.fromMap(map)));
        print('>>> ✓ ${_tiposServico.length} serviços carregados');
      }

      // Carregar pedidos
      final pedidosMap = await _storage.carregarLista(LocalStorageService.keyPedidos);
      if (pedidosMap.isNotEmpty) {
        _pedidos.clear();
        _pedidos.addAll(pedidosMap.map((map) => Pedido.fromMap(map)));
        print('>>> ✓ ${_pedidos.length} pedidos carregados');
      }

      // Carregar ordens de serviço
      final ordensMap = await _storage.carregarLista(LocalStorageService.keyOrdensServico);
      if (ordensMap.isNotEmpty) {
        _ordensServico.clear();
        _ordensServico.addAll(ordensMap.map((map) => OrdemServico.fromMap(map)));
        print('>>> ✓ ${_ordensServico.length} ordens de serviço carregadas');
      }

      // Carregar entregas
      final entregasMap = await _storage.carregarLista(LocalStorageService.keyEntregas);
      if (entregasMap.isNotEmpty) {
        _entregas.clear();
        _entregas.addAll(entregasMap.map((map) => Entrega.fromMap(map)));
        print('>>> ✓ ${_entregas.length} entregas carregadas');
      }

      // Carregar motoristas
      final motoristasMap = await _storage.carregarLista(LocalStorageService.keyMotoristas);
      if (motoristasMap.isNotEmpty) {
        _motoristas.clear();
        _motoristas.addAll(motoristasMap.map((map) => Motorista.fromMap(map)));
        print('>>> ✓ ${_motoristas.length} motoristas carregados');
      }

      // Carregar vendas balcão
      final vendasMap = await _storage.carregarLista(LocalStorageService.keyVendasBalcao);
      if (vendasMap.isNotEmpty) {
        _vendasBalcao.clear();
        _vendasBalcao.addAll(vendasMap.map((map) => VendaBalcao.fromMap(map)));
        print('>>> ✓ ${_vendasBalcao.length} vendas balcão carregadas');
      }

      // Carregar trocas/devoluções
      final trocasMap = await _storage.carregarLista(LocalStorageService.keyTrocasDevolucoes);
      if (trocasMap.isNotEmpty) {
        _trocasDevolucoes.clear();
        _trocasDevolucoes.addAll(trocasMap.map((map) => TrocaDevolucao.fromMap(map)));
        print('>>> ✓ ${_trocasDevolucoes.length} trocas/devoluções carregadas');
      }

      // Carregar histórico de estoque (se tiver método fromMap implementado)
      // final estoqueMap = await _storage.carregarLista(LocalStorageService.keyEstoqueHistorico);
      // if (estoqueMap.isNotEmpty && EstoqueHistorico tem método fromMap) {
      //   _estoqueHistorico.clear();
      //   _estoqueHistorico.addAll(estoqueMap.map((map) => EstoqueHistorico.fromMap(map)));
      //   print('>>> ✓ ${_estoqueHistorico.length} registros de histórico de estoque carregados');
      // }

      // Carregar aberturas de caixa
      final aberturasMap =
          await _storage.carregarLista(LocalStorageService.keyAberturasCaixa);
      if (aberturasMap.isNotEmpty) {
        _aberturasCaixa.clear();
        _aberturasCaixa
            .addAll(aberturasMap.map((map) => AberturaCaixa.fromMap(map)));
        print('>>> ✓ ${_aberturasCaixa.length} aberturas de caixa carregadas');
      }

      // Carregar fechamentos de caixa
      final fechamentosMap =
          await _storage.carregarLista(LocalStorageService.keyFechamentosCaixa);
      if (fechamentosMap.isNotEmpty) {
        _fechamentosCaixa.clear();
        _fechamentosCaixa
            .addAll(fechamentosMap.map((map) => FechamentoCaixa.fromMap(map)));
        print(
          '>>> ✓ ${_fechamentosCaixa.length} fechamentos de caixa carregados',
        );
      }

      print('>>> ✓ Todos os dados salvos foram carregados');
    } catch (e) {
      print('>>> ✗ Erro ao carregar dados salvos: $e');
    }
  }

  /// Salva todos os dados no localStorage
  Future<void> _salvarTodosDados() async {
    if (!_persistenciaHabilitada) return;

    try {
      await _storage.salvarLista(LocalStorageService.keyClientes, _clientes);
      await _storage.salvarLista(LocalStorageService.keyProdutos, _produtos);
      await _storage.salvarLista(LocalStorageService.keyServicos, _tiposServico);
      await _storage.salvarLista(LocalStorageService.keyPedidos, _pedidos);
      await _storage.salvarLista(LocalStorageService.keyOrdensServico, _ordensServico);
      await _storage.salvarLista(LocalStorageService.keyEntregas, _entregas);
      await _storage.salvarLista(LocalStorageService.keyMotoristas, _motoristas);
      await _storage.salvarLista(
          LocalStorageService.keyVendasBalcao, _vendasBalcao);
      await _storage.salvarLista(
          LocalStorageService.keyTrocasDevolucoes, _trocasDevolucoes);
      await _storage.salvarLista(
          LocalStorageService.keyEstoqueHistorico, _estoqueHistorico);
      await _storage.salvarLista(
          LocalStorageService.keyAberturasCaixa, _aberturasCaixa);
      await _storage.salvarLista(
          LocalStorageService.keyFechamentosCaixa, _fechamentosCaixa);
      print('>>> ✓ Todos os dados foram salvos no localStorage');
    } catch (e) {
      print('>>> ✗ Erro ao salvar dados: $e');
    }
  }

  /// Salva automaticamente os dados após uma mudança (não bloqueia)
  void _salvarAutomaticamente() {
    if (!_persistenciaHabilitada) return;
    // Salvar de forma assíncrona sem bloquear a UI
    _salvarTodosDados().catchError((e) {
      debugPrint('>>> Erro ao salvar automaticamente: $e');
    });
  }
}
