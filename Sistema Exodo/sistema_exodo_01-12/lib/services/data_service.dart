import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/ordem_servico.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/models/troca_devolucao.dart';
import 'package:sistema_exodo_novo/models/estoque_historico.dart';
import 'package:sistema_exodo_novo/models/nota_entrada.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/agendamento_servico.dart';
import 'package:sistema_exodo_novo/models/funcionario.dart';
import 'package:sistema_exodo_novo/models/taxa_entrega.dart';
import 'package:sistema_exodo_novo/models/conta_pagar.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:sistema_exodo_novo/services/firebase_service.dart';

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
  final List<NotaEntrada> _notasEntrada = [];
  final List<AgendamentoServico> _agendamentosServico = [];
  final List<Funcionario> _funcionarios = [];
  final List<TaxaEntrega> _taxasEntrega = [];
  final List<ContaPagar> _contasPagar = [];
  final List<NFCe> _nfces = [];
  // Controle de caixa
  bool _caixaAberto = false; // Flag rápida para verificações de UI
  bool get caixaAberto => _caixaAberto;
  final List<AberturaCaixa> _aberturasCaixa = [];
  final List<FechamentoCaixa> _fechamentosCaixa = [];
  final List<SangriaCaixa> _sangrias = [];
  final List<SuprimentoCaixa> _suprimentos = [];
  List<AberturaCaixa> get aberturasCaixa => _aberturasCaixa;
  List<FechamentoCaixa> get fechamentosCaixa => _fechamentosCaixa;
  List<SangriaCaixa> get sangrias => _sangrias;
  List<SuprimentoCaixa> get suprimentos => _suprimentos;
  List<NotaEntrada> get notasEntrada => _notasEntrada;

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
  final FirebaseService _firebaseService = FirebaseService();
  bool _persistenciaHabilitada = true; // Flag para habilitar/desabilitar persistência
  bool _firebaseHabilitado = true; // Flag para habilitar/desabilitar Firebase - REATIVADO para sincronização em tempo real

  // ID único para debug
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();
  String get instanceId => _instanceId;
  
  // Proteção contra salvamentos excessivos (debounce)
  Timer? _debounceSalvamento;
  bool _salvandoDados = false;
  static const Duration _debounceDelay = Duration(seconds: 1); // Aguarda 1 segundo antes de salvar
  
  // Empresa atual para isolamento de dados
  String? _empresaIdAtual;
  String? get empresaIdAtual => _empresaIdAtual;
  
  /// Define a empresa atual e recarrega os dados
  Future<void> definirEmpresaAtual(String? empresaId) async {
    if (_empresaIdAtual == empresaId) return;
    
    _empresaIdAtual = empresaId;
    print('>>> DataService: Empresa atual definida: $empresaId');
    
    // Limpar dados atuais
    _clientes.clear();
    _produtos.clear();
    _tiposServico.clear();
    _pedidos.clear();
    _ordensServico.clear();
    _entregas.clear();
    _motoristas.clear();
    _vendasBalcao.clear();
    _trocasDevolucoes.clear();
    _estoqueHistorico.clear();
    _notasEntrada.clear();
    _agendamentosServico.clear();
    _funcionarios.clear();
    _taxasEntrega.clear();
    _contasPagar.clear();
    _aberturasCaixa.clear();
    _fechamentosCaixa.clear();
    _sangrias.clear();
    _suprimentos.clear();
    
    // Recarregar dados da nova empresa
    if (empresaId != null) {
      await iniciarSincronizacao();
    }
    
    notifyListeners();
  }
  
  /// Obtém a chave de armazenamento com prefixo da empresa
  String _getChaveComEmpresa(String chaveBase) {
    if (_empresaIdAtual == null) return chaveBase;
    return 'empresa_${_empresaIdAtual}_$chaveBase';
  }

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
    
    // Firebase é PRINCIPAL agora - tentar carregar primeiro com timeout curto
    if (_firebaseHabilitado) {
      try {
        print('>>> 🔥 Firebase é PRINCIPAL - Carregando dados do Firebase...');
        await _carregarDadosDoFirebase().timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            print('>>> ⚠ Timeout ao carregar do Firebase (8s) - usando fallback');
            throw TimeoutException('Firebase timeout');
          },
        );
        
        // Se carregou dados do Firebase, verificar se precisa carregar do local também
        if (_produtos.isEmpty && _clientes.isEmpty) {
          print('>>> ⚠ Firebase vazio. Carregando do localStorage como backup...');
          try {
            await _carregarDadosSalvos();
            // Se carregou dados do local, sincronizar com Firebase
            if (_produtos.isNotEmpty || _clientes.isNotEmpty) {
              print('>>> 🔄 Sincronizando dados locais com Firebase...');
              await _salvarTodosDados();
            }
          } catch (e2) {
            print('>>> ⚠ Erro ao carregar do localStorage: $e2');
          }
        } else {
          print('>>> ✓ Dados carregados do Firebase com sucesso!');
        }
      } catch (e, stackTrace) {
        print('>>> ⚠ Erro ao carregar do Firebase: $e');
        print('>>> StackTrace: $stackTrace');
        print('>>> Tentando carregar do localStorage como fallback...');
        try {
          await _carregarDadosSalvos();
          // Se carregou do local, tentar sincronizar com Firebase
          if (_produtos.isNotEmpty || _clientes.isNotEmpty) {
            print('>>> 🔄 Tentando sincronizar dados locais com Firebase...');
            _salvarTodosDados().catchError((e) {
              print('>>> ⚠ Erro ao sincronizar: $e');
            });
          }
        } catch (e2) {
          print('>>> ⚠ Erro ao carregar do localStorage: $e2');
          // Continua mesmo se ambos falharem - app não trava
        }
      }
    } else {
      // Se Firebase desabilitado, carregar apenas do localStorage
      try {
        await _carregarDadosSalvos();
      } catch (e) {
        print('>>> ⚠ Erro ao carregar do localStorage: $e');
        // Continua mesmo se falhar
      }
    }
    
    // Se não houver dados salvos (nem Firebase nem local), carregar dados fictícios
    // APENAS para a empresa padrão (ID "1"). Empresas novas começam vazias.
    final isEmpresaPadrao = _empresaIdAtual == '1' || _empresaIdAtual == null;
    
    if (isEmpresaPadrao) {
      // Apenas a empresa padrão carrega dados fictícios
      if (_produtos.isEmpty) {
        print('>>> ⚠ Nenhum produto encontrado. Carregando dados fictícios (empresa padrão)...');
        _carregarProdutosFicticios();
        // Salvar no Firebase e localStorage
        _salvarTodosDados().catchError((e) {
          print('>>> ⚠ Erro ao salvar dados fictícios: $e');
        });
      }
      
      if (_clientes.isEmpty) {
        print('>>> ⚠ Nenhum cliente encontrado. Carregando dados fictícios (empresa padrão)...');
        _carregarClientesFicticios();
        // Salvar no Firebase e localStorage
        _salvarTodosDados().catchError((e) {
          print('>>> ⚠ Erro ao salvar dados fictícios: $e');
        });
      }
      
      if (_motoristas.isEmpty) {
        print('>>> ⚠ Nenhum motorista encontrado. Carregando dados fictícios (empresa padrão)...');
        _carregarMotoristasFicticios();
        // Salvar no Firebase e localStorage
        _salvarTodosDados().catchError((e) {
          print('>>> ⚠ Erro ao salvar dados fictícios: $e');
        });
      }
    } else {
      // Empresas novas começam vazias - não carregam dados fictícios
      print('>>> Empresa nova (ID: $_empresaIdAtual) - não carregando dados fictícios');
      if (_produtos.isEmpty) {
        print('>>> Empresa nova: sem produtos cadastrados');
      }
      if (_clientes.isEmpty) {
        print('>>> Empresa nova: sem clientes cadastrados');
      }
      if (_motoristas.isEmpty) {
        print('>>> Empresa nova: sem motoristas cadastrados');
      }
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
    print('>>> [registrarFechamentoCaixa] Iniciando...');
    print('>>> [registrarFechamentoCaixa] Valor esperado: $valorEsperado');
    print('>>> [registrarFechamentoCaixa] Valor real: $valorReal');
    print('>>> [registrarFechamentoCaixa] Responsável: $responsavel');
    
    final abertura = aberturaCaixaAtual;
    if (abertura == null) {
      print('>>> [registrarFechamentoCaixa] ERRO: Não há abertura de caixa atual!');
      debugPrint('>>> Aviso: tentar fechar caixa sem abertura atual');
      return null;
    }
    
    print('>>> [registrarFechamentoCaixa] Abertura encontrada: ${abertura.numero}');

    final diff = diferenca ?? (valorReal - valorEsperado);
    print('>>> [registrarFechamentoCaixa] Diferença calculada: $diff');

    // Obter sangrias e suprimentos do caixa atual
    final sangriasCaixaAtual = getSangriasCaixaAtual();
    final suprimentosCaixaAtual = getSuprimentosCaixaAtual();
    
    print('>>> [registrarFechamentoCaixa] Sangrias: ${sangriasCaixaAtual.length}');
    print('>>> [registrarFechamentoCaixa] Suprimentos: ${suprimentosCaixaAtual.length}');

    final fechamento = FechamentoCaixa(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      aberturaCaixaId: abertura.id,
      dataFechamento: DateTime.now(),
      valorEsperado: valorEsperado,
      valorReal: valorReal,
      diferenca: diff,
      sangrias: sangriasCaixaAtual,
      suprimentos: suprimentosCaixaAtual,
      observacao: observacao,
      responsavel: responsavel,
    );
    
    print('>>> [registrarFechamentoCaixa] Fechamento criado: ${fechamento.id}');

    _fechamentosCaixa.add(fechamento);
    _caixaAberto = false;
    
    print('>>> [registrarFechamentoCaixa] Salvando status do caixa...');
    await _storage.salvarStatusCaixaAberto(false);
    
    print('>>> [registrarFechamentoCaixa] Salvando todos os dados no Firebase...');
    // Salvar IMEDIATAMENTE no Firebase (aguardar para garantir que foi salvo)
    try {
      await _salvarTodosDados(aguardarFirebase: true);
      print('>>> [registrarFechamentoCaixa] Dados salvos com sucesso!');
    } catch (e, stackTrace) {
      print('>>> [registrarFechamentoCaixa] ERRO ao salvar: $e');
      print('>>> [registrarFechamentoCaixa] StackTrace: $stackTrace');
      // Continua mesmo se falhar o salvamento
    }
    
    notifyListeners();
    print('>>> [registrarFechamentoCaixa] ✓ Caixa fechado e salvo no Firebase!');
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

  /// Registra uma sangria do caixa atual
  Future<SangriaCaixa> registrarSangria({
    required double valor,
    required String motivo,
    String? observacao,
    String? responsavel,
  }) async {
    final abertura = aberturaCaixaAtual;
    if (abertura == null) {
      throw Exception('Não há caixa aberto para registrar sangria');
    }

    final sangria = SangriaCaixa(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      data: DateTime.now(),
      valor: valor,
      motivo: motivo,
      observacao: observacao,
      responsavel: responsavel,
    );

    _sangrias.add(sangria);
    
    try {
      _salvarAutomaticamente();
    } catch (e) {
      print('>>> Erro ao salvar sangria: $e');
    }
    
    notifyListeners();
    print('>>> Sangria registrada: R\$ ${valor.toStringAsFixed(2)} - $motivo');
    return sangria;
  }

  /// Registra um suprimento do caixa atual
  Future<SuprimentoCaixa> registrarSuprimento({
    required double valor,
    required String motivo,
    String? observacao,
    String? responsavel,
  }) async {
    final abertura = aberturaCaixaAtual;
    if (abertura == null) {
      throw Exception('Não há caixa aberto para registrar suprimento');
    }

    final suprimento = SuprimentoCaixa(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      data: DateTime.now(),
      valor: valor,
      motivo: motivo,
      observacao: observacao,
      responsavel: responsavel,
    );

    _suprimentos.add(suprimento);
    
    try {
      _salvarAutomaticamente();
    } catch (e) {
      print('>>> Erro ao salvar suprimento: $e');
    }
    
    notifyListeners();
    print('>>> Suprimento registrado: R\$ ${valor.toStringAsFixed(2)} - $motivo');
    return suprimento;
  }

  /// Obtém as sangrias do caixa atual (aberto)
  List<SangriaCaixa> getSangriasCaixaAtual() {
    final abertura = aberturaCaixaAtual;
    if (abertura == null) return [];
    
    return _sangrias.where((s) {
      // Filtrar sangrias que pertencem ao caixa atual (após abertura)
      return s.data.isAfter(abertura.dataAbertura) ||
             s.data.isAtSameMomentAs(abertura.dataAbertura);
    }).toList();
  }

  /// Obtém os suprimentos do caixa atual (aberto)
  List<SuprimentoCaixa> getSuprimentosCaixaAtual() {
    final abertura = aberturaCaixaAtual;
    if (abertura == null) return [];
    
    return _suprimentos.where((s) {
      // Filtrar suprimentos que pertencem ao caixa atual (após abertura)
      return s.data.isAfter(abertura.dataAbertura) ||
             s.data.isAtSameMomentAs(abertura.dataAbertura);
    }).toList();
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
        precoCusto: 0.08,
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
        precoCusto: 0.12,
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
        precoCusto: 0.05,
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
        precoCusto: 8.50,
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
        precoCusto: 22.00,
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
        precoCusto: 3.20,
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
        precoCusto: 1.80,
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
        precoCusto: 5.50,
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
        precoCusto: 10.00,
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
        precoCusto: 0.80,
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
        precoCusto: 120.00,
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
        precoCusto: 11.00,
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
        precoCusto: 1.50,
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
        precoCusto: 3.80,
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
  List<Funcionario> get funcionarios => _funcionarios;
  List<Pedido> get pedidos => _pedidos;
  List<Entrega> get entregas => _entregas;
  List<Motorista> get motoristas => _motoristas;
  List<TaxaEntrega> get taxasEntrega => _taxasEntrega;
  List<ContaPagar> get contasPagar => _contasPagar;
  List<VendaBalcao> get vendasBalcao => _vendasBalcao;
  List<TrocaDevolucao> get trocasDevolucoes => _trocasDevolucoes;
  List<AgendamentoServico> get agendamentosServico => _agendamentosServico;
  List<NFCe> get nfces => _nfces;

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

  // ============ CRUD Funcionario ============

  Future<void> addFuncionario(Funcionario funcionario) async {
    _funcionarios.add(funcionario);
    notifyListeners();
    _salvarAutomaticamente();
  }

  void updateFuncionario(Funcionario funcionario) {
    final index = _funcionarios.indexWhere((f) => f.id == funcionario.id);
    if (index != -1) {
      _funcionarios[index] = funcionario;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteFuncionario(String id) {
    _funcionarios.removeWhere((f) => f.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  // ============ CRUD ContaPagar ============

  Future<void> addContaPagar(ContaPagar conta) async {
    _contasPagar.add(conta);
    notifyListeners();
    _salvarAutomaticamente();
  }

  void updateContaPagar(ContaPagar conta) {
    final index = _contasPagar.indexWhere((c) => c.id == conta.id);
    if (index != -1) {
      _contasPagar[index] = conta;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteContaPagar(String id) {
    _contasPagar.removeWhere((c) => c.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  /// Gera o próximo número de conta a pagar
  String getProximoNumeroContaPagar() {
    int ultimoNumero = 0;
    for (final conta in _contasPagar) {
      if (conta.numero != null && conta.numero!.startsWith('CP-')) {
        try {
          final numero = int.parse(conta.numero!.substring(3));
          if (numero > ultimoNumero) {
            ultimoNumero = numero;
          }
        } catch (e) {
          // Ignorar números inválidos
        }
      }
    }
    ultimoNumero++;
    return 'CP-${ultimoNumero.toString().padLeft(4, '0')}';
  }

  // ============ CRUD Produto ============

  /// Garante que existe um produto "Diversos" com código 9999
  Future<Produto> garantirProdutoDiversos() async {
    // Buscar produto com código 9999
    Produto? diversosExistente;
    try {
      diversosExistente = _produtos.firstWhere(
        (p) => p.codigo == '9999' || p.codigo == 'COD-9999',
      );
    } catch (e) {
      diversosExistente = null;
    }

    // Se já existe, retornar
    if (diversosExistente != null) {
      return diversosExistente;
    }

    // Criar produto "Diversos" com código 9999
    final agora = DateTime.now();
    final produtoDiversos = Produto(
      id: 'produto-diversos-9999',
      codigo: '9999',
      nome: 'Diversos',
      descricao: 'Produto genérico para lançamentos rápidos',
      unidade: 'UN',
      grupo: 'Diversos',
      preco: 0.0,
      estoque: 999999,
      createdAt: agora,
      updatedAt: agora,
    );

    await addProduto(produtoDiversos);
    print('>>> ✓ Produto "Diversos" (9999) criado automaticamente');
    return produtoDiversos;
  }

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

  /// Deleta todos os produtos (com confirmação necessária antes de chamar)
  Future<void> deleteAllProdutos() async {
    // Deletar do Firebase primeiro se estiver habilitado
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.deletarTodosProdutos(_empresaIdAtual!);
        debugPrint('>>> [DataService] Todos os produtos deletados do Firebase');
      } catch (e) {
        debugPrint('>>> [DataService] Erro ao deletar produtos do Firebase: $e');
        // Continua mesmo se falhar no Firebase
      }
    }
    
    // Limpar lista local
    _produtos.clear();
    notifyListeners();
    
    // Salvar lista vazia no localStorage e Firebase
    await _salvarTodosDados();
    debugPrint('>>> [DataService] Todos os produtos deletados localmente e do Firebase');
  }

  // ============ Estoque Histórico ============

  void registrarEntradaEstoque({
    required String produtoId,
    required int quantidade,
    String? observacao,
    String? usuario,
  }) {
    final historico = EstoqueHistorico(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      produtoId: produtoId,
      data: DateTime.now(),
      quantidade: quantidade,
      tipo: 'entrada',
      observacao: observacao,
      usuario: usuario,
    );
    _estoqueHistorico.add(historico);
    notifyListeners();
    _salvarAutomaticamente();
  }

  // ============ CRUD NotaEntrada ============

  Future<void> addNotaEntrada(NotaEntrada nota) async {
    _notasEntrada.add(nota);
    notifyListeners();
    _salvarAutomaticamente();
  }

  void updateNotaEntrada(NotaEntrada nota) {
    final index = _notasEntrada.indexWhere((n) => n.id == nota.id);
    if (index != -1) {
      _notasEntrada[index] = nota;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteNotaEntrada(String notaId) {
    _notasEntrada.removeWhere((n) => n.id == notaId);
    notifyListeners();
    _salvarAutomaticamente();
  }

  /// Cancela uma nota processada e desfaz todas as alterações nos produtos
  Future<void> cancelarNotaEntrada(String notaId) async {
    final nota = _notasEntrada.firstWhere((n) => n.id == notaId);
    
    if (!nota.isProcessada) {
      throw Exception('Apenas notas processadas podem ser canceladas');
    }

    print('');
    print('╔════════════════════════════════════════════════╗');
    print('║  CANCELANDO NOTA E REVERTENDO ALTERAÇÕES       ║');
    print('╚════════════════════════════════════════════════╝');
    print('>>> Nota: ${nota.numeroNota}');

    // Reverter alterações para cada item
    for (final item in nota.itens) {
      if (item.produtoId == null) continue;

      try {
        if (item.produtoNovo) {
          // Produto foi criado por esta nota - excluir
          print('>>> Excluindo produto criado: ${item.nome}');
          _produtos.removeWhere((p) => p.id == item.produtoId);
        } else {
          // Produto existia - reverter valores
          final produto = _produtos.firstWhere((p) => p.id == item.produtoId);
          
          // Reverter estoque (diminuir a quantidade que foi adicionada)
          final novoEstoque = (produto.estoque - item.quantidade.toInt()).clamp(0, double.infinity).toInt();
          
          // Reverter preços se houver valores anteriores salvos
          final precoCustoFinal = item.precoCustoAnterior ?? produto.precoCusto;
          final precoVendaFinal = item.precoVendaAnterior ?? produto.preco;
          
          print('>>> Revertendo produto: ${produto.nome}');
          print('>>>   Estoque: ${produto.estoque} → $novoEstoque');
          if (item.precoCustoAnterior != null) {
            print('>>>   Custo: ${produto.precoCusto} → $precoCustoFinal');
          }
          if (item.precoVendaAnterior != null) {
            print('>>>   Venda: ${produto.preco} → $precoVendaFinal');
          }
          
          final produtoRevertido = produto.copyWith(
            estoque: novoEstoque,
            precoCusto: precoCustoFinal,
            preco: precoVendaFinal,
            updatedAt: DateTime.now(),
          );
          
          updateProduto(produtoRevertido);
        }
      } catch (e) {
        print('>>> ERRO ao reverter item ${item.nome}: $e');
      }
    }

    // Excluir completamente a nota para permitir reprocessamento
    _notasEntrada.removeWhere((n) => n.id == notaId);
    
    print('>>> ✓ Nota excluída e alterações revertidas');
    print('>>> ✓ Nota pode ser processada novamente');
    print('');
    
    notifyListeners();
    _salvarAutomaticamente();
  }

  // ============ CRUD Servico ============

  Future<void> addTipoServico(Servico servico) async {
    // Normalizar nome para comparação (remover diferenças de separadores: -, +, etc)
    String normalizarNomeParaComparacao(String nome) {
      return nome
          .toLowerCase()
          .trim()
          .replaceAll(RegExp(r'[+\-]'), ' ') // Substituir + e - por espaço
          .replaceAll(RegExp(r'\s+'), ' ') // Normalizar espaços múltiplos
          .trim();
    }
    
    final nomeNormalizado = normalizarNomeParaComparacao(servico.nome);
    final precoTotal = servico.precoTotal;
    final precoBase = servico.preco;
    final valorAdicional = servico.valorAdicional;
    final descAdicionalNormalizada = servico.descricaoAdicional?.toLowerCase().trim() ?? '';

    // Verificar se já existe um serviço idêntico (mesmo nome normalizado, preço base, valor adicional e descrição adicional)
    final servicoIdenticoExiste = _tiposServico.any((s) {
      final nomeExistenteNormalizado = normalizarNomeParaComparacao(s.nome);
      final descAdicionalExistente = s.descricaoAdicional?.toLowerCase().trim() ?? '';
      
      return nomeExistenteNormalizado == nomeNormalizado &&
             s.preco == precoBase &&
             s.valorAdicional == valorAdicional &&
             descAdicionalExistente == descAdicionalNormalizada;
    });

    if (servicoIdenticoExiste) {
      debugPrint('>>> DataService: Serviço "${servico.nome}" já existe (idêntico), ignorando adição.');
      return;
    }

    // Verificar se existe serviço similar (mesmo nome normalizado e mesmo preço total)
    final servicoSimilarExiste = _tiposServico.any((s) {
      final nomeExistenteNormalizado = normalizarNomeParaComparacao(s.nome);
      return nomeExistenteNormalizado == nomeNormalizado && 
             s.precoTotal == precoTotal;
    });

    if (servicoSimilarExiste) {
      debugPrint('>>> DataService: Serviço similar "${servico.nome}" já existe (mesmo nome normalizado e preço total), ignorando adição.');
      return;
    }

    // Se passou todas as verificações, adicionar o serviço
    _tiposServico.add(servico);
    notifyListeners();
    _salvarAutomaticamente();
    debugPrint('>>> DataService: Serviço "${servico.nome}" adicionado com sucesso.');
  }

  Future<void> addServico(Servico servico) async {
    await addTipoServico(servico);
  }

  void updateTipoServico(Servico servico) {
    final index = _tiposServico.indexWhere((s) => s.id == servico.id);
    if (index != -1) {
      _tiposServico[index] = servico;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteTipoServico(String id) {
    _tiposServico.removeWhere((s) => s.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  // ============ CRUD Ordem de Servico ============

  Future<void> addOrdemServico(OrdemServico os) async {
    _ordensServico.add(os);
    notifyListeners();
    _salvarAutomaticamente();
  }

  void updateOrdemServico(OrdemServico os) {
    final index = _ordensServico.indexWhere((o) => o.id == os.id);
    if (index != -1) {
      _ordensServico[index] = os;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteOrdemServico(String id) {
    _ordensServico.removeWhere((o) => o.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  // ============ CRUD Agendamento Serviço ============

  /// Adiciona um novo agendamento de serviço com validação de conflitos
  Future<AgendamentoServico> addAgendamentoServico(
    AgendamentoServico agendamento,
  ) async {
    // Validar conflitos de horário
    final conflitos = _agendamentosServico.where((a) {
      return a.isAtivo && agendamento.temConflito(a);
    }).toList();

    if (conflitos.isNotEmpty) {
      throw Exception(
        'Conflito de horário! Já existe agendamento no mesmo horário:\n'
        '${conflitos.map((c) => '${c.cliente?.nome ?? "Cliente"} - ${c.servico?.nome ?? "Serviço"}').join('\n')}',
      );
    }

    // Carregar referências de serviço e cliente
    final servico = _tiposServico.firstWhere(
      (s) => s.id == agendamento.servicoId,
      orElse: () => _tiposServico.first,
    );
    final cliente = agendamento.clienteId != null
        ? _clientes.firstWhere(
            (c) => c.id == agendamento.clienteId,
            orElse: () => _clientes.first,
          )
        : null;

    final agendamentoCompleto = agendamento.copyWith(
      servico: servico,
      cliente: cliente,
    );

    _agendamentosServico.add(agendamentoCompleto);
    notifyListeners();
    _salvarAutomaticamente();
    return agendamentoCompleto;
  }

  /// Atualiza um agendamento existente com validação de conflitos
  Future<void> updateAgendamentoServico(AgendamentoServico agendamento) async {
    final index = _agendamentosServico.indexWhere((a) => a.id == agendamento.id);
    if (index == -1) {
      throw Exception('Agendamento não encontrado');
    }

    // Validar conflitos de horário (excluindo o próprio agendamento)
    final conflitos = _agendamentosServico.where((a) {
      return a.id != agendamento.id && a.isAtivo && agendamento.temConflito(a);
    }).toList();

    if (conflitos.isNotEmpty) {
      throw Exception(
        'Conflito de horário! Já existe agendamento no mesmo horário:\n'
        '${conflitos.map((c) => '${c.cliente?.nome ?? "Cliente"} - ${c.servico?.nome ?? "Serviço"}').join('\n')}',
      );
    }

    // Carregar referências atualizadas
    final servico = _tiposServico.firstWhere(
      (s) => s.id == agendamento.servicoId,
      orElse: () => _tiposServico.first,
    );
    final cliente = agendamento.clienteId != null
        ? _clientes.firstWhere(
            (c) => c.id == agendamento.clienteId,
            orElse: () => _clientes.first,
          )
        : null;

    _agendamentosServico[index] = agendamento.copyWith(
      servico: servico,
      cliente: cliente,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    _salvarAutomaticamente();
  }

  /// Remove um agendamento
  void deleteAgendamentoServico(String id) {
    _agendamentosServico.removeWhere((a) => a.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  /// Busca agendamentos por período
  List<AgendamentoServico> getAgendamentosPorPeriodo(
    DateTime inicio,
    DateTime fim,
  ) {
    return _agendamentosServico.where((a) {
      return a.dataAgendamento.compareTo(inicio) >= 0 &&
             a.dataAgendamento.compareTo(fim) <= 0;
    }).toList();
  }

  /// Busca agendamentos por cliente
  List<AgendamentoServico> getAgendamentosPorCliente(String clienteId) {
    return _agendamentosServico
        .where((a) => a.clienteId == clienteId)
        .toList();
  }

  /// Verifica se há conflito de horário para um agendamento
  bool verificarConflitoHorario(DateTime dataAgendamento, int duracaoMinutos, {String? excluirAgendamentoId}) {
    final dataTermino = dataAgendamento.add(Duration(minutes: duracaoMinutos));
    
    return _agendamentosServico.any((a) {
      if (a.id == excluirAgendamentoId) return false;
      if (!a.isAtivo) return false;
      
      return (dataAgendamento.isBefore(a.dataTermino) && 
              dataTermino.isAfter(a.dataAgendamento));
    });
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
            ? '${itemServico.descricao} + ${itemServico.descricaoAdicional}'
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
            preco: itemServico.valor, // Preço BASE (sem o adicional)
            valorAdicional: itemServico.valorAdicional, // Valor adicional separado
            descricaoAdicional: itemServico.descricaoAdicional, // Descrição do adicional
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await addTipoServico(novoServico);
        }
      }
    }
    
    _pedidos.add(pedido);
    debugPrint('>>> Pedido adicionado: ${pedido.numero} (id=${pedido.id})');
    debugPrint('>>> Total de pedidos na lista: ${_pedidos.length}');
    notifyListeners();
    // Aguardar salvamento antes de retornar
    await _salvarTodosDados();
    debugPrint('>>> Pedido salvo com sucesso: ${pedido.numero}');
  }

  void updatePedido(Pedido pedido) {
    // Verificar se algum serviço tem valor adicional e cadastrar automaticamente
    for (final itemServico in pedido.servicos) {
      if (itemServico.valorAdicional > 0) {
        // Verificar se já existe um serviço com esse nome e preço total
        final precoTotal = itemServico.valor + itemServico.valorAdicional;
        final nomeServico = itemServico.descricaoAdicional != null && 
                           itemServico.descricaoAdicional!.isNotEmpty
            ? '${itemServico.descricao} + ${itemServico.descricaoAdicional}'
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
            preco: itemServico.valor, // Preço BASE (sem o adicional)
            valorAdicional: itemServico.valorAdicional, // Valor adicional separado
            descricaoAdicional: itemServico.descricaoAdicional, // Descrição do adicional
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

  /// Cancela um pedido
  Future<void> cancelarPedido(String id, {String? motivo}) async {
    final index = _pedidos.indexWhere((p) => p.id == id);
    if (index != -1) {
      final pedido = _pedidos[index];
      
      // Devolver produtos ao estoque (serviços não têm estoque)
      for (final item in pedido.produtos) {
        try {
          // Tentar buscar pelo ID primeiro, depois pelo nome
          Produto? produto;
          try {
            produto = _produtos.firstWhere(
              (p) => p.id == item.id,
            );
          } catch (_) {
            // Se não encontrou pelo ID, tentar pelo nome
            try {
              produto = _produtos.firstWhere(
                (p) => p.nome == item.nome,
              );
            } catch (_) {
              print('>>> ⚠ Produto não encontrado para devolução: ${item.nome}');
              continue;
            }
          }
          
          final estoqueAnterior = produto.estoque;
          final novoEstoque = produto.estoque + item.quantidade;
          
          await updateProduto(
            produto.copyWith(
              estoque: novoEstoque,
              updatedAt: DateTime.now(),
            ),
          );
          
          print('>>> ✓ Estoque atualizado - Cancelamento de pedido:');
          print('>>>   Produto: ${produto.nome}');
          print('>>>   Estoque anterior: $estoqueAnterior');
          print('>>>   Quantidade devolvida: ${item.quantidade}');
          print('>>>   Novo estoque: $novoEstoque');
        } catch (e) {
          print('>>> ERRO ao devolver produto ${item.nome} ao estoque: $e');
        }
      }
      
      final pedidoCancelado = pedido.copyWith(
        status: 'Cancelado',
        observacoes: (pedido.observacoes ?? '') +
            (motivo != null && motivo.isNotEmpty
                ? '\nCancelado em ${DateTime.now().toIso8601String()} - Motivo: $motivo'
                : '\nCancelado em ${DateTime.now().toIso8601String()}'),
      );
      _pedidos[index] = pedidoCancelado;
      print('✓ Pedido ${pedido.numero} cancelado e produtos devolvidos ao estoque');
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  // ============ Metodos auxiliares ============

  List<Servico> getServicosPorCliente(String clienteId) {
    return _tiposServico;
  }

  // ============ CRUD Entrega ============

  Future<void> addEntrega(Entrega entrega) async {
    _entregas.add(entrega);
    notifyListeners();
    _salvarAutomaticamente();
  }

  void updateEntrega(Entrega entrega) {
    final index = _entregas.indexWhere((e) => e.id == entrega.id);
    if (index != -1) {
      _entregas[index] = entrega;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteEntrega(String id) {
    _entregas.removeWhere((e) => e.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  Entrega? getEntregaPorPedido(String pedidoId) {
    try {
      return _entregas.firstWhere((e) => e.pedidoId == pedidoId);
    } catch (_) {
      return null;
    }
  }

  // ============ CRUD TaxaEntrega ============

  Future<void> addTaxaEntrega(TaxaEntrega taxa) async {
    _taxasEntrega.add(taxa);
    notifyListeners();
    _salvarAutomaticamente();
  }

  void updateTaxaEntrega(TaxaEntrega taxa) {
    final index = _taxasEntrega.indexWhere((t) => t.id == taxa.id);
    if (index != -1) {
      _taxasEntrega[index] = taxa;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteTaxaEntrega(String id) {
    _taxasEntrega.removeWhere((t) => t.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  /// Busca taxa de entrega por bairro (case-insensitive)
  TaxaEntrega? getTaxaEntregaPorBairro(String bairro, {String? cidade}) {
    try {
      final bairroLower = bairro.toLowerCase().trim();
      return _taxasEntrega.firstWhere(
        (t) => t.ativo &&
            t.bairro.toLowerCase().trim() == bairroLower &&
            (cidade == null || t.cidade?.toLowerCase().trim() == cidade.toLowerCase().trim()),
      );
    } catch (_) {
      return null;
    }
  }

  // ============ CRUD Motorista ============

  Future<void> addMotorista(Motorista motorista) async {
    _motoristas.add(motorista);
    notifyListeners();
    _salvarAutomaticamente();
  }

  void updateMotorista(Motorista motorista) {
    final index = _motoristas.indexWhere((m) => m.id == motorista.id);
    if (index != -1) {
      _motoristas[index] = motorista;
      notifyListeners();
      _salvarAutomaticamente();
    }
  }

  void deleteMotorista(String id) {
    _motoristas.removeWhere((m) => m.id == id);
    notifyListeners();
    _salvarAutomaticamente();
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

  /// Cancela uma venda do balcão
  Future<void> cancelarVendaBalcao(String id) async {
    final index = _vendasBalcao.indexWhere((v) => v.id == id);
    if (index != -1) {
      final venda = _vendasBalcao[index];
      
      // Devolver itens ao estoque (apenas produtos, não serviços)
      for (final item in venda.itens) {
        // Pular serviços e itens já devolvidos/trocados
        if (item.isServico) continue;
        
        // Calcular quantidade efetiva a devolver (descontando devoluções/trocas anteriores)
        final quantidadeADevolver = item.quantidadeEfetiva;
        if (quantidadeADevolver <= 0) continue;
        
        try {
          // Tentar buscar pelo ID primeiro (mais confiável), depois pelo nome
          Produto? produto;
          try {
            produto = _produtos.firstWhere(
              (p) => p.id == item.id,
            );
          } catch (_) {
            // Se não encontrou pelo ID, tentar pelo nome
            try {
              produto = _produtos.firstWhere(
                (p) => p.nome == item.nome,
              );
            } catch (_) {
              print('>>> ⚠ Produto não encontrado para devolução: ${item.nome}');
              continue;
            }
          }
          
          final estoqueAnterior = produto.estoque;
          final novoEstoque = produto.estoque + quantidadeADevolver;
          
          await updateProduto(
            produto.copyWith(
              estoque: novoEstoque,
              updatedAt: DateTime.now(),
            ),
          );
          
          print('>>> ✓ Estoque atualizado - Cancelamento de venda:');
          print('>>>   Produto: ${produto.nome}');
          print('>>>   Estoque anterior: $estoqueAnterior');
          print('>>>   Quantidade devolvida: $quantidadeADevolver');
          print('>>>   Novo estoque: $novoEstoque');
        } catch (e) {
          print('>>> ERRO ao devolver produto ${item.nome} ao estoque: $e');
        }
      }
      
      final vendaCancelada = venda.copyWith(cancelado: true);
      _vendasBalcao[index] = vendaCancelada;
      print('✓ Venda ${venda.numero} cancelada e itens devolvidos ao estoque');
      notifyListeners();
      _salvarAutomaticamente();
    }
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

  // Vendas do dia (exclui canceladas)
  List<VendaBalcao> get vendasDoDia {
    final hoje = DateTime.now();
    return _vendasBalcao.where((v) {
      // Excluir vendas canceladas
      if (v.cancelado) return false;
      return v.dataVenda.year == hoje.year &&
          v.dataVenda.month == hoje.month &&
          v.dataVenda.day == hoje.day;
    }).toList()..sort((a, b) => b.dataVenda.compareTo(a.dataVenda));
  }

  // Total vendido hoje
  double get totalVendidoHoje {
    return vendasDoDia.fold(0.0, (sum, v) => sum + v.valorTotal);
  }

  // Vendas por período (considera data e horário) - exclui canceladas
  List<VendaBalcao> getVendasPorPeriodo(DateTime inicio, DateTime fim) {
    return _vendasBalcao.where((v) {
      // Excluir vendas canceladas
      if (v.cancelado) return false;
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
  /// Carrega dados do Firebase
  Future<void> _carregarDadosDoFirebase() async {
    if (_empresaIdAtual == null) {
      print('>>> ⚠ Empresa não definida - não é possível carregar dados do Firebase');
      return;
    }
    
    try {
      print('>>> 🔥 Carregando dados do Firebase (PRINCIPAL) para empresa: $_empresaIdAtual');
      final dados = await _firebaseService.carregarTudoDoFirebase(_empresaIdAtual!)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print('>>> ⚠ Timeout ao carregar do Firebase (8s) - usando fallback');
              throw TimeoutException('Firebase timeout');
            },
          );
      
      // Verificar se há dados no Firebase
      final temDados = dados['clientes']?.isNotEmpty == true ||
          dados['produtos']?.isNotEmpty == true ||
          dados['pedidos']?.isNotEmpty == true;
      
      if (!temDados) {
        print('>>> ⚠ Firebase está vazio. Continuando com dados locais se existirem...');
        return; // Retorna sem erro, mas sem dados
      }

      // Carregar clientes
      if (dados['clientes'] != null && dados['clientes'].isNotEmpty) {
        _clientes.clear();
        _clientes.addAll(
          (dados['clientes'] as List).map((map) => Cliente.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_clientes.length} clientes carregados do Firebase');
      }

      // Carregar produtos
      if (dados['produtos'] != null && dados['produtos'].isNotEmpty) {
        _produtos.clear();
        _produtos.addAll(
          (dados['produtos'] as List).map((map) => Produto.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_produtos.length} produtos carregados do Firebase');
      }

      // Carregar serviços
      if (dados['servicos'] != null && dados['servicos'].isNotEmpty) {
        _tiposServico.clear();
        _tiposServico.addAll(
          (dados['servicos'] as List).map((map) => Servico.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_tiposServico.length} serviços carregados do Firebase');
      }

      // Carregar pedidos
      if (dados['pedidos'] != null && dados['pedidos'].isNotEmpty) {
        _pedidos.clear();
        _pedidos.addAll(
          (dados['pedidos'] as List).map((map) => Pedido.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_pedidos.length} pedidos carregados do Firebase');
      }

      // Carregar ordens de serviço
      if (dados['ordens_servico'] != null && dados['ordens_servico'].isNotEmpty) {
        _ordensServico.clear();
        _ordensServico.addAll(
          (dados['ordens_servico'] as List)
              .map((map) => OrdemServico.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_ordensServico.length} ordens de serviço carregadas do Firebase');
      }

      // Carregar entregas
      if (dados['entregas'] != null && dados['entregas'].isNotEmpty) {
        _entregas.clear();
        _entregas.addAll(
          (dados['entregas'] as List).map((map) => Entrega.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_entregas.length} entregas carregadas do Firebase');
      }

      // Carregar motoristas
      if (dados['motoristas'] != null && dados['motoristas'].isNotEmpty) {
        _motoristas.clear();
        _motoristas.addAll(
          (dados['motoristas'] as List).map((map) => Motorista.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_motoristas.length} motoristas carregados do Firebase');
      }

      // Carregar vendas balcão
      if (dados['vendas_balcao'] != null && dados['vendas_balcao'].isNotEmpty) {
        _vendasBalcao.clear();
        _vendasBalcao.addAll(
          (dados['vendas_balcao'] as List)
              .map((map) => VendaBalcao.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_vendasBalcao.length} vendas balcão carregadas do Firebase');
      }

      // Carregar trocas/devoluções
      if (dados['trocas_devolucoes'] != null && dados['trocas_devolucoes'].isNotEmpty) {
        _trocasDevolucoes.clear();
        _trocasDevolucoes.addAll(
          (dados['trocas_devolucoes'] as List)
              .map((map) => TrocaDevolucao.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_trocasDevolucoes.length} trocas/devoluções carregadas do Firebase');
      }

      // Carregar histórico de estoque
      if (dados['estoque_historico'] != null && dados['estoque_historico'].isNotEmpty) {
        _estoqueHistorico.clear();
        _estoqueHistorico.addAll(
          (dados['estoque_historico'] as List)
              .map((map) => EstoqueHistorico.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_estoqueHistorico.length} registros de estoque carregados do Firebase');
      }

      // Carregar aberturas de caixa
      if (dados['aberturas_caixa'] != null && dados['aberturas_caixa'].isNotEmpty) {
        _aberturasCaixa.clear();
        _aberturasCaixa.addAll(
          (dados['aberturas_caixa'] as List)
              .map((map) => AberturaCaixa.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_aberturasCaixa.length} aberturas de caixa carregadas do Firebase');
      }

      // Carregar fechamentos de caixa
      if (dados['fechamentos_caixa'] != null && dados['fechamentos_caixa'].isNotEmpty) {
        _fechamentosCaixa.clear();
        _fechamentosCaixa.addAll(
          (dados['fechamentos_caixa'] as List)
              .map((map) => FechamentoCaixa.fromMap(map as Map<String, dynamic>)),
        );
        print('>>> ✓ ${_fechamentosCaixa.length} fechamentos de caixa carregados do Firebase');
      }

      // Sincronizar com localStorage após carregar do Firebase
      await _salvarTodosDados();
    } catch (e, stackTrace) {
      print('>>> ✗ Erro ao carregar dados do Firebase: $e');
      print('>>> StackTrace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _carregarDadosSalvos() async {
    try {
      print('>>> Carregando dados salvos do localStorage...');

      // Carregar clientes
      final clientesMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyClientes));
      if (clientesMap.isNotEmpty) {
        _clientes.clear();
        _clientes.addAll(clientesMap.map((map) => Cliente.fromMap(map)));
        print('>>> ✓ ${_clientes.length} clientes carregados');
      }

      // Carregar produtos
      final produtosMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyProdutos));
      if (produtosMap.isNotEmpty) {
        _produtos.clear();
        _produtos.addAll(produtosMap.map((map) => Produto.fromMap(map)));
        print('>>> ✓ ${_produtos.length} produtos carregados');
      }

      // Carregar serviços
      final servicosMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyServicos));
      if (servicosMap.isNotEmpty) {
        _tiposServico.clear();
        _tiposServico.addAll(servicosMap.map((map) => Servico.fromMap(map)));
        print('>>> ✓ ${_tiposServico.length} serviços carregados');
      }

      // Carregar pedidos
      final pedidosMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyPedidos));
      if (pedidosMap.isNotEmpty) {
        _pedidos.clear();
        _pedidos.addAll(pedidosMap.map((map) => Pedido.fromMap(map)));
        print('>>> ✓ ${_pedidos.length} pedidos carregados');
      }

      // Carregar ordens de serviço
      final ordensMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyOrdensServico));
      if (ordensMap.isNotEmpty) {
        _ordensServico.clear();
        _ordensServico.addAll(ordensMap.map((map) => OrdemServico.fromMap(map)));
        print('>>> ✓ ${_ordensServico.length} ordens de serviço carregadas');
      }

      // Carregar entregas
      final entregasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyEntregas));
      if (entregasMap.isNotEmpty) {
        _entregas.clear();
        _entregas.addAll(entregasMap.map((map) => Entrega.fromMap(map)));
        print('>>> ✓ ${_entregas.length} entregas carregadas');
      }

      // Carregar motoristas
      final motoristasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyMotoristas));
      if (motoristasMap.isNotEmpty) {
        _motoristas.clear();
        _motoristas.addAll(motoristasMap.map((map) => Motorista.fromMap(map)));
        print('>>> ✓ ${_motoristas.length} motoristas carregados');
      }

      // Carregar vendas balcão
      final vendasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyVendasBalcao));
      if (vendasMap.isNotEmpty) {
        _vendasBalcao.clear();
        _vendasBalcao.addAll(vendasMap.map((map) => VendaBalcao.fromMap(map)));
        print('>>> ✓ ${_vendasBalcao.length} vendas balcão carregadas');
      }

      // Carregar trocas/devoluções
      final trocasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyTrocasDevolucoes));
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
          await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyAberturasCaixa));
      if (aberturasMap.isNotEmpty) {
        _aberturasCaixa.clear();
        _aberturasCaixa
            .addAll(aberturasMap.map((map) => AberturaCaixa.fromMap(map)));
        print('>>> ✓ ${_aberturasCaixa.length} aberturas de caixa carregadas');
      }

      // Carregar fechamentos de caixa
      final fechamentosMap =
          await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyFechamentosCaixa));
      if (fechamentosMap.isNotEmpty) {
        _fechamentosCaixa.clear();
        _fechamentosCaixa
            .addAll(fechamentosMap.map((map) => FechamentoCaixa.fromMap(map)));
        print(
          '>>> ✓ ${_fechamentosCaixa.length} fechamentos de caixa carregados',
        );
      }

      // Carregar notas de entrada
      final notasMap =
          await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyNotasEntrada));
      if (notasMap.isNotEmpty) {
        _notasEntrada.clear();
        _notasEntrada
            .addAll(notasMap.map((map) => NotaEntrada.fromMap(map)));
        print('>>> ✓ ${_notasEntrada.length} notas de entrada carregadas');
      }

      // Carregar agendamentos de serviço
      final agendamentosMap =
          await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyAgendamentosServico));
      if (agendamentosMap.isNotEmpty) {
        _agendamentosServico.clear();
        _agendamentosServico.addAll(
          agendamentosMap.map((map) {
            final agendamento = AgendamentoServico.fromMap(map);
            // Carregar referências de serviço e cliente
            final servico = _tiposServico.firstWhere(
              (s) => s.id == agendamento.servicoId,
              orElse: () => _tiposServico.first,
            );
            final cliente = agendamento.clienteId != null
                ? _clientes.firstWhere(
                    (c) => c.id == agendamento.clienteId,
                    orElse: () => _clientes.first,
                  )
                : null;
            return agendamento.copyWith(servico: servico, cliente: cliente);
          }),
        );
        print('>>> ✓ ${_agendamentosServico.length} agendamentos carregados');
      }

      // Carregar funcionários
      final funcionariosMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyFuncionarios));
      if (funcionariosMap.isNotEmpty) {
        _funcionarios.clear();
        _funcionarios.addAll(funcionariosMap.map((map) => Funcionario.fromMap(map)));
        print('>>> ✓ ${_funcionarios.length} funcionários carregados');
      }

      // Carregar taxas de entrega
      final taxasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyTaxasEntrega));
      if (taxasMap.isNotEmpty) {
        _taxasEntrega.clear();
        _taxasEntrega.addAll(taxasMap.map((map) => TaxaEntrega.fromMap(map)));
        print('>>> ✓ ${_taxasEntrega.length} taxas de entrega carregadas');
      }

      // Carregar contas a pagar
      final contasPagarMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyContasPagar));
      if (contasPagarMap.isNotEmpty) {
        _contasPagar.clear();
        _contasPagar.addAll(contasPagarMap.map((map) => ContaPagar.fromMap(map)));
        print('>>> ✓ ${_contasPagar.length} contas a pagar carregadas');
      }

      // Carregar NFC-e
      final nfcesMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyNFCes));
      if (nfcesMap.isNotEmpty) {
        _nfces.clear();
        _nfces.addAll(nfcesMap.map((map) => NFCe.fromMap(map)));
        print('>>> ✓ ${_nfces.length} NFC-e carregadas');
      }

      print('>>> ✓ Todos os dados salvos foram carregados');
    } catch (e) {
      print('>>> ✗ Erro ao carregar dados salvos: $e');
    }
  }

  /// Salva todos os dados no localStorage e Firebase
  /// [aguardarFirebase] - se true, aguarda o Firebase salvar (para operações críticas)
  Future<void> _salvarTodosDados({bool aguardarFirebase = false}) async {
    if (!_persistenciaHabilitada) return;

    try {
      // Salvar no localStorage em paralelo para não bloquear a UI
      try {
        await Future.wait([
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyClientes), _clientes),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyProdutos), _produtos),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyServicos), _tiposServico),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyPedidos), _pedidos),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyOrdensServico), _ordensServico),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyEntregas), _entregas),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyMotoristas), _motoristas),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyVendasBalcao), _vendasBalcao),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyTrocasDevolucoes), _trocasDevolucoes),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyEstoqueHistorico), _estoqueHistorico),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyAberturasCaixa), _aberturasCaixa),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyFechamentosCaixa), _fechamentosCaixa),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyNotasEntrada), _notasEntrada),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyAgendamentosServico), _agendamentosServico),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyFuncionarios), _funcionarios),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyTaxasEntrega), _taxasEntrega),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyContasPagar), _contasPagar),
          _storage.salvarLista(_getChaveComEmpresa(LocalStorageService.keyNFCes), _nfces),
        ], eagerError: false);
      } catch (e) {
        debugPrint('>>> Erro ao salvar alguns dados: $e');
        // Continua mesmo se alguns falharem
      }
      
      print('>>> ✓ Todos os dados foram salvos no localStorage');

      // Salvar no Firebase (sincronização em nuvem)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        if (aguardarFirebase) {
          // Para operações críticas (como fechar caixa), aguarda o Firebase
          try {
            await _firebaseService.sincronizarTudo(
              empresaId: _empresaIdAtual!,
              clientes: _clientes,
              produtos: _produtos,
              servicos: _tiposServico,
              pedidos: _pedidos,
              ordensServico: _ordensServico,
              entregas: _entregas,
              vendasBalcao: _vendasBalcao,
              trocasDevolucoes: _trocasDevolucoes,
              estoqueHistorico: _estoqueHistorico,
              aberturasCaixa: _aberturasCaixa,
              fechamentosCaixa: _fechamentosCaixa,
              motoristas: _motoristas,
            );
            print('>>> ✓ Todos os dados foram sincronizados com Firebase (aguardado)');
          } catch (e) {
            print('>>> ✗ Erro ao sincronizar com Firebase: $e');
            // Continua mesmo se falhar
          }
        } else {
          // Para operações normais, executa em background para não bloquear a UI
          _firebaseService.sincronizarTudo(
            empresaId: _empresaIdAtual!,
            clientes: _clientes,
            produtos: _produtos,
            servicos: _tiposServico,
            pedidos: _pedidos,
            ordensServico: _ordensServico,
            entregas: _entregas,
            vendasBalcao: _vendasBalcao,
            trocasDevolucoes: _trocasDevolucoes,
            estoqueHistorico: _estoqueHistorico,
            aberturasCaixa: _aberturasCaixa,
            fechamentosCaixa: _fechamentosCaixa,
            motoristas: _motoristas,
          ).then((_) {
            print('>>> ✓ Todos os dados foram sincronizados com Firebase (background)');
          }).catchError((e) {
            print('>>> ✗ Erro ao sincronizar com Firebase: $e');
            // Continua mesmo se falhar o Firebase (não bloqueia a aplicação)
          });
        }
      }
    } catch (e) {
      print('>>> ✗ Erro ao salvar dados: $e');
    }
  }

  /// Salva automaticamente os dados após uma mudança (não bloqueia)
  /// Usa debounce para evitar salvamentos excessivos que causam travamentos
  void _salvarAutomaticamente() {
    if (!_persistenciaHabilitada) return;
    
    // Se já está salvando, não fazer nada (evitar salvamentos simultâneos)
    if (_salvandoDados) {
      debugPrint('>>> Salvamento já em andamento, ignorando chamada');
      return;
    }
    
    // Cancelar salvamento anterior se houver
    _debounceSalvamento?.cancel();
    
    // Agendar novo salvamento com debounce
    _debounceSalvamento = Timer(_debounceDelay, () {
      if (!_persistenciaHabilitada) return;
      
      _salvandoDados = true;
      
      // Salvar de forma assíncrona sem bloquear a UI
      _salvarTodosDados().then((_) {
        _salvandoDados = false;
      }).catchError((e) {
        debugPrint('>>> Erro ao salvar automaticamente: $e');
        _salvandoDados = false;
      });
    });
  }

  /// Salva imediatamente sem debounce (útil para operações críticas)
  Future<void> salvarImediatamente() async {
    if (!_persistenciaHabilitada) return;
    
    // Cancelar qualquer salvamento agendado
    _debounceSalvamento?.cancel();
    
    if (_salvandoDados) {
      // Se já está salvando, aguardar um pouco
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    _salvandoDados = true;
    try {
      await _salvarTodosDados();
    } catch (e) {
      debugPrint('>>> Erro ao salvar imediatamente: $e');
      rethrow;
    } finally {
      _salvandoDados = false;
    }
  }
  
  // ============ CRUD NFC-e ============

  /// Adiciona uma NFC-e
  Future<void> adicionarNFCe(NFCe nfce) async {
    _nfces.add(nfce);
    notifyListeners();
    _salvarAutomaticamente();
  }

  /// Atualiza uma NFC-e existente
  Future<void> atualizarNFCe(NFCe nfce) async {
    final index = _nfces.indexWhere((n) => n.id == nfce.id);
    if (index == -1) {
      throw Exception('NFC-e não encontrada: ${nfce.id}');
    }
    _nfces[index] = nfce;
    notifyListeners();
    _salvarAutomaticamente();
  }

  /// Remove uma NFC-e
  void removerNFCe(String id) {
    _nfces.removeWhere((n) => n.id == id);
    notifyListeners();
    _salvarAutomaticamente();
  }

  /// Obtém uma NFC-e por ID
  NFCe? obterNFCe(String id) {
    try {
      return _nfces.firstWhere((n) => n.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Obtém NFC-e por chave de acesso
  NFCe? obterNFCePorChave(String chaveAcesso) {
    try {
      return _nfces.firstWhere((n) => n.chaveAcesso == chaveAcesso);
    } catch (e) {
      return null;
    }
  }

  /// Lista NFC-e por empresa
  List<NFCe> listarNFCePorEmpresa(String empresaId) {
    return _nfces.where((n) => n.empresaId == empresaId).toList();
  }

  /// Lista NFC-e por período
  List<NFCe> listarNFCePorPeriodo(DateTime inicio, DateTime fim) {
    return _nfces.where((n) {
      return n.dataEmissao.isAfter(inicio.subtract(const Duration(days: 1))) &&
             n.dataEmissao.isBefore(fim.add(const Duration(days: 1)));
    }).toList();
  }

  /// Lista NFC-e por status
  List<NFCe> listarNFCePorStatus(String status) {
    return _nfces.where((n) => n.status == status).toList();
  }

  @override
  void dispose() {
    _debounceSalvamento?.cancel();
    super.dispose();
  }
}
