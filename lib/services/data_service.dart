import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:sistema_exodo_novo/models/pet.dart';
import 'package:sistema_exodo_novo/models/funcionario.dart';
import 'package:sistema_exodo_novo/models/taxa_entrega.dart';
import 'package:sistema_exodo_novo/models/conta_pagar.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';
import 'package:sistema_exodo_novo/models/mesa_comanda.dart';
import 'package:sistema_exodo_novo/models/link_vendedor.dart';
import 'package:sistema_exodo_novo/models/comissao_vendedor.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:sistema_exodo_novo/services/firebase_service.dart';
import 'package:sistema_exodo_novo/services/sync_queue_service.dart';
import 'package:sistema_exodo_novo/services/whatsapp_service.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/services/google_drive_service.dart';
import 'package:uuid/uuid.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

// Import condicional para Web
import '../pages/html_helper_stub.dart' if (dart.library.html) '../pages/html_helper_web.dart' as html_helper;

// Re-export TipoPessoa para facilitar uso
export 'package:sistema_exodo_novo/models/cliente.dart' show TipoPessoa;

const uuid = Uuid();

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
  
  // Getters públicos para acesso às listas (se não existirem)
  final List<NotaEntrada> _notasEntrada = [];
  final List<AgendamentoServico> _agendamentosServico = [];
  final List<Funcionario> _funcionarios = [];
  final List<TaxaEntrega> _taxasEntrega = [];
  final List<ContaPagar> _contasPagar = [];
  final List<NFCe> _nfces = [];
  final List<MesaComanda> _mesasComandas = [];
  final List<LinkVendedor> _linksVendedores = [];
  final List<ComissaoVendedor> _comissoesVendedores = [];
  
  // Controle de sincronização Google Drive
  final Set<String> _notasSincronizadasDrive = {};
  bool _syncDriveEmAndamento = false;
  
  // Monitor de Bridge (NFC-e)
  List<Map<String, dynamic>> _bridgesStatus = [];
  StreamSubscription? _bridgeSubscription;
  
  List<Map<String, dynamic>> get bridgesStatus => _bridgesStatus;
  int get bridgeOnlineCount => _bridgesStatus.where((b) => b['online'] == true && !b['id'].toString().startsWith('watchdog_')).length;

  /// Verifica se existe algum bridge online para um CNPJ específico
  bool isEmpresaBridgeOnline(String? cnpj) {
    if (cnpj == null || cnpj.isEmpty) return false;
    final cnpjLimpo = cnpj.replaceAll(RegExp(r'[^0-9]'), '');
    return _bridgesStatus.any((b) {
      final bCnpj = b['ultimo_cnpj']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      return b['online'] == true && bCnpj == cnpjLimpo;
    });
  }
  
  // Getters públicos
  List<AgendamentoServico> get agendamentos => agendamentosServico;

  List<MesaComanda> get mesasComandas => _mesasComandas;
  List<MesaComanda> get mesasComandasAbertas => 
      _mesasComandas.where((m) => m.status == 'Aberta').toList();

  /// Exporta todos os dados operacionais da empresa em formato JSON
  Map<String, dynamic> exportarBackupCompleto() {
    return {
      'versao_schema': '1.0.0',
      'software': 'Sistema Êxodo',
      'data_exportacao': DateTime.now().toIso8601String(),
      'empresa_id': _empresaIdAtual,
      'empresa_nome': _empresaAtual?.nomeExibicao,
      'colecoes': {
        'clientes': _clientes.map((e) => e.toMap()).toList(),
        'produtos': _produtos.map((e) => e.toMap()).toList(),
        'servicos': _tiposServico.map((e) => e.toMap()).toList(),
        'pedidos': _pedidos.map((e) => e.toMap()).toList(),
        'vendas_balcao': _vendasBalcao.map((e) => e.toMap()).toList(),
        'agendamentos': _agendamentosServico.map((e) => e.toMap()).toList(),
        'contas_pagar': _contasPagar.map((e) => e.toMap()).toList(),
        'notas_entrada': _notasEntrada.map((e) => e.toMap()).toList(),
        'funcionarios': _funcionarios.map((e) => e.toMap()).toList(),
        'ordens_servico': _ordensServico.map((e) => e.toMap()).toList(),
        'trocas_devolucoes': _trocasDevolucoes.map((e) => e.toMap()).toList(),
        'comissoes': _comissoesVendedores.map((e) => e.toMap()).toList(),
        'nfces': _nfces.map((e) => e.toMap()).toList(),
      }
    };
  }
  
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
  List<NFCe> get nfces => _nfces;

  /// Retorna as NFC-es autorizadas em um período específico
  List<NFCe> getNfcesPorPeriodo(DateTime inicio, DateTime fim) {
    return _nfces.where((n) {
      if (n.status != 'autorizada') return false;
      return n.dataEmissao.isAfter(inicio) && n.dataEmissao.isBefore(fim);
    }).toList();
  }

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
  final FirebaseService _firebaseService = FirebaseService.instance;
  final SyncQueueService _syncQueue = SyncQueueService();
  bool _persistenciaHabilitada = true; // Flag para habilitar/desabilitar persistência
  bool _firebaseHabilitado = true; // Flag para habilitar/desabilitar Firebase - REABILITADO

  // ID único para debug
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();
  Timer? _syncTimer;
  StreamSubscription? _agendamentosSubscription;
  StreamSubscription? _produtosSubscription;
  StreamSubscription? _servicosSubscription;
  StreamSubscription? _empresaSubscription;
  
  // Status de Sincronização
  DateTime? _ultimaSincronizacaoSucesso;
  String? _ultimoErroSync;
  bool _syncEmAndamento = false;
  bool _isModoLeve = false;
  bool _primeiraCargaAgendamentosRealizada = false;

  @override
  void dispose() {
    _cancelarTodasSubscriptions();
    _debounceSalvamento?.cancel();
    _syncQueue.dispose();
    super.dispose();
  }

  /// Cancela todas as conexões ativas com o Firebase para evitar vazamentos de memória
  void _cancelarTodasSubscriptions() {
    debugPrint('>>> [Memória] 🧹 Cancelando todas as conexões e timers...');
    _syncTimer?.cancel();
    _agendamentosSubscription?.cancel();
    _produtosSubscription?.cancel();
    _servicosSubscription?.cancel();
    _empresaSubscription?.cancel();
    _bridgeSubscription?.cancel();
    
    _syncTimer = null;
    _agendamentosSubscription = null;
    _produtosSubscription = null;
    _servicosSubscription = null;
    _empresaSubscription = null;
    _bridgeSubscription = null;
  }
  String get instanceId => _instanceId;
  bool get firebaseHabilitado => _firebaseHabilitado;
  
  // Proteção contra salvamentos excessivos (debounce otimizado)
  Timer? _debounceSalvamento;
  bool _salvandoDados = false;
  static const Duration _debounceDelay = Duration(seconds: 10); // Aumentado para 10s para estabilidade
  DateTime? _ultimaSincronizacao;
  static const Duration _intervaloSincronizacao = Duration(minutes: 30);
  
  // Controle de coleções modificadas (Selective Saving)
  final Set<String> _dirtyCollections = {};

  void _marcarSujo(String collectionKey) {
    if (!_dirtyCollections.contains(collectionKey)) {
      _dirtyCollections.add(collectionKey);
      _salvarAutomaticamente();
    }
  }
  
  // Empresa atual para isolamento de dados
  String? _empresaIdAtual;
  String? get empresaIdAtual => _empresaIdAtual;
  
  // Empresa completa (para notificações WhatsApp)
  Empresa? _empresaAtual;
  Empresa? get empresaAtual => _empresaAtual;

  // Player de Áudio para Notificações
  final AudioPlayer _audioPlayer = AudioPlayer();

  /// Toca o som de notificação quando chega um agendamento novo
  Future<void> _tocarSomNotificacao() async {
    debugPrint('>>> [Audio] 🔊 Tentando tocar som de notificação...');
    
    // NO WEB: Muitos navegadores bloqueiam som sem interação prévia.
    // O usuário DEVE ter clicado pelo menos uma vez no app.
    
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(0.8); // 80% do volume para garantir audibilidade
      
      if (kIsWeb) {
        // No Web, tentamos descobrir o caminho correto dos assets
        final origin = html_helper.getWindowOrigin();
        final url = '$origin/assets/sounds/notification.mp3';
        debugPrint('>>> [Audio] 🌐 Web: Tentando carregar via URL: $url');
        await _audioPlayer.play(UrlSource(url));
      } else {
        await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
      }
      
      debugPrint('>>> [Audio] ✅ Comando de reprodução enviado');
    } catch (e) {
      debugPrint('>>> [Audio] ❌ Erro detalhado ao tocar som: $e');
      
      // Fallback para o helper nativo do browser se o audioplayers falhar no web
      if (kIsWeb) {
        try {
          debugPrint('>>> [Audio] 🔄 Tentando fallback via HTML AudioElement...');
          html_helper.playAudio('assets/sounds/notification.mp3', volume: 0.8);
        } catch (e2) {
          debugPrint('>>> [Audio] ❌ Falha no fallback: $e2');
        }
      }
    }
  }
  
  /// Define a empresa completa (chamado pelo AuthService após selecionar empresa)
  void setEmpresaAtual(Empresa? empresa) {
    if (_empresaAtual != empresa) {
      _empresaAtual = empresa;
      notifyListeners();
    }
  }

  /// Atualiza os dados da empresa no Firebase e localmente
  Future<void> atualizarDadosEmpresa(Empresa empresa) async {
    _empresaAtual = empresa;
    if (_firebaseHabilitado) {
      await _firebaseService.salvarEmpresa(empresa);
    }
    notifyListeners();
  }

  
  // Estado de carregamento
  bool _isLoading = false;
  String _mensagemLoading = 'Carregando...';

  // Controle de Paginação (Infinite Scroll)
  DocumentSnapshot? _ultimoDocClientes;
  bool _temMaisClientes = true;
  bool _carregandoMaisClientes = false;
  
  DocumentSnapshot? _ultimoDocVendas;
  bool _temMaisVendas = true;
  bool _carregandoMaisVendas = false;

  bool get isLoading => _isLoading;
  bool get syncEmAndamento => _syncEmAndamento;
  DateTime? get ultimaSincronizacaoSucesso => _ultimaSincronizacaoSucesso;
  String? get ultimoErroSync => _ultimoErroSync;
  String get mensagemLoading => _mensagemLoading;
  bool get isModoLeve => _isModoLeve;

  /// Retorna uma mensagem amigável sobre o status da sincronização
  String get getSyncStatusText {
    if (_syncEmAndamento) return 'Sincronizando...';
    if (_ultimaSincronizacaoSucesso == null) return 'Aguardando sincronização...';
    
    final agora = DateTime.now();
    final diferenca = agora.difference(_ultimaSincronizacaoSucesso!);
    
    if (diferenca.inSeconds < 60) return 'Atualizado agora';
    if (diferenca.inMinutes < 60) return 'Atualizado há ${diferenca.inMinutes} min';
    return 'Atualizado há ${diferenca.inHours} h';
  }

  /// Define a empresa atual e recarrega os dados
  /// [modoLeve]: Se true, carrega apenas dados essenciais (otimizado para loja pública)
  Future<void> definirEmpresaAtual(String? empresaId, {bool modoLeve = false}) async {
    // Se a empresa for a mesma, mas mudamos de modoLeve para modoFull, precisamos recarregar
    if (_empresaIdAtual == empresaId && empresaId != null) {
      if (_isModoLeve && !modoLeve) {
        debugPrint('>>> [DataService] ⚡ Upgrade: modoLeve -> Full sync (empresa: $empresaId)');
        _isModoLeve = false;
        await iniciarSincronizacao(modoLeve: false);
        return;
      }
      debugPrint('>>> [DataService] ℹ️ Empresa já definida: $empresaId (Leve: $_isModoLeve)');
      _isModoLeve = modoLeve;
      return;
    }
    
    _isModoLeve = modoLeve;
    
    // Iniciar loading
    _isLoading = true;
    _mensagemLoading = 'Carregando dados da empresa...';
    notifyListeners();
    
    print('>>> DataService: ========================================');
    print('>>> DataService: TROCANDO EMPRESA');
    print('>>> DataService: Empresa anterior: $_empresaIdAtual');
    print('>>> DataService: Empresa nova: $empresaId');
    print('>>> DataService: ========================================');
    
    // Salvar dados da empresa anterior ANTES de trocar (se houver empresa anterior)
    if (_empresaIdAtual != null) {
      print('>>> DataService: Salvando dados da empresa anterior antes de trocar...');
      try {
        await _salvarTodosDados(aguardarFirebase: false);
        print('>>> DataService: ✓ Dados da empresa anterior salvos com sucesso');
      } catch (e) {
        print('>>> DataService: ⚠️ Erro ao salvar dados da empresa anterior: $e');
        // Continua mesmo se falhar - dados já estão no localStorage
      }
    }
    
    // ISOLAMENTO: Limpar dados da empresa anterior da MEMÓRIA (não do localStorage/Firebase)
    // Isso garante que cada empresa carregue apenas seus próprios dados
    print('>>> DataService: 🧹 Limpando dados da empresa anterior da memória...');
    print('>>> DataService: ⚠️ Os dados permanecem salvos no localStorage/Firebase');
    _primeiraCargaAgendamentosRealizada = false; // Resetar para a nova empresa
    
    // Resetar Paginação
    _temMaisClientes = true;
    _ultimoDocClientes = null;
    _temMaisVendas = true;
    _ultimoDocVendas = null;

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
    _nfces.clear();
    _mesasComandas.clear();
    _linksVendedores.clear();
    _comissoesVendedores.clear();
    print('>>> DataService: ✓ Memória limpa - pronta para carregar dados da nova empresa');
    
    // DEFINIR NOVA EMPRESA
    _empresaIdAtual = empresaId;
    if (empresaId != null) {
      if (_empresaAtual?.id != empresaId) {
        _empresaAtual = null; // Limpar para evitar dados obsoletos apenas se for realmente outra empresa
      }
      
      // Recarregar dados APENAS da nova empresa (isoladamente)
      await iniciarSincronizacao(modoLeve: modoLeve);
    } else {
      print('>>> DataService: ⚠ Empresa não definida - dados não serão carregados');
    }
    
    // Finalizar loading
    _isLoading = false;
    notifyListeners();
    print('>>> DataService: ✓ Troca de empresa concluída - dados isolados');

    // Registrar listener de foco para Web (acordar o app se ficar em background)
    if (kIsWeb) {
      html_helper.onWindowFocus.listen((_) {
        debugPrint('>>> [SISTEMA] Janela focada - Verificando conexões de Stream...');
        if (_empresaIdAtual != null && _firebaseHabilitado) {
          _iniciarStreamAgendamentos(); // Reiniciar para garantir dados frescos
        }
      });
    }

    // Iniciar monitor de Bridge NFC-e
    _reiniciarMonitorBridge();

    // Iniciar timer de sincronização automática
    _reiniciarTimerSincronizacao();
  }

  /// Inicia todos os streams de tempo real necessários
  void _iniciarStreamsTempoReal() {
    _agendamentosSubscription?.cancel();
    _produtosSubscription?.cancel();
    _servicosSubscription?.cancel();

    if (_empresaIdAtual == null || !_firebaseHabilitado) return;

    debugPrint('>>> [Sync] 📡 Ativando Streams de Tempo Real (Modo Leve: $_isModoLeve)');
    
    // 1. Empresa (Configurações em tempo real)
  _iniciarStreamEmpresa();
  
  // 2. Agendamentos (Sempre em tempo real)
  _iniciarStreamAgendamentos();

  // 3. Produtos e Serviços (Tempo real apenas se houver necessidade de atualização instantânea na UI)
  _iniciarStreamProdutos();
  _iniciarStreamServicos();
  }

  void _iniciarStreamProdutos() {
    if (_empresaIdAtual == null) return;
    _produtosSubscription = _firebaseService.getProdutosStream(_empresaIdAtual!).listen((novos) {
      debugPrint('>>> [Sync] 📦 Stream de Produtos: ${novos.length} itens recebidos');
      _atualizarListaInPlace(_produtos, novos);
      notifyListeners();
    });
  }

  void _iniciarStreamServicos() {
    if (_empresaIdAtual == null) return;
    _servicosSubscription = _firebaseService.getServicosStream(_empresaIdAtual!).listen((novos) {
      debugPrint('>>> [Sync] 🛠 Stream de Serviços: ${novos.length} itens recebidos');
      _atualizarListaInPlace(_tiposServico, novos);
      _reVincularTodosAgendamentos(); // Garantir que agendamentos pendentes agora achem seus serviços
      notifyListeners();
    });
  }

  /// Auxiliar para atualizar ou adicionar um agendamento na lista local com controle de versão/data
  /// Retorna true se houve mudança real na lista
  bool _upsertAgendamentoLocal(AgendamentoServico novo, {bool prioritario = false}) {
    final index = _agendamentosServico.indexWhere((a) => a.id == novo.id);
    
    // Normalizar datas para milissegundos para evitar problemas de precisão micro/mili entre Web/Firebase
    final novoMs = novo.updatedAt.millisecondsSinceEpoch;

    if (index != -1) {
      final existente = _agendamentosServico[index];
      final existenteMs = existente.updatedAt.millisecondsSinceEpoch;
      
      // Só atualizar se o novo for mais recente ou se for uma ação direta (prioritária)
      // Usamos >= para garantir que atualizações vindas do server com mesma data (mesmo ms) sejam aceitas
      if (prioritario || novoMs >= existenteMs) {
        _agendamentosServico.removeWhere((a) => a.id == novo.id);
        if (prioritario) {
          _agendamentosServico.insert(0, novo);
        } else {
          _agendamentosServico.add(novo);
        }
        return true;
      }
      return false;
    } else {
      // Novo agendamento
      if (prioritario) {
        _agendamentosServico.insert(0, novo);
      } else {
        _agendamentosServico.add(novo);
      }
      return true;
    }
  }

  /// Re-vincula referências de todos os agendamentos (útil quando serviços/clientes carregam depois)
  void _reVincularTodosAgendamentos() {
    bool houveMudanca = false;
    for (int i = 0; i < _agendamentosServico.length; i++) {
      final antes = _agendamentosServico[i];
      final depois = _vincularReferenciasAgendamento(antes);
      
      // Se alguma referência (servico, cliente, pet) foi preenchida ou mudou
      if (antes.servico != depois.servico || 
          antes.cliente != depois.cliente || 
          antes.pet != depois.pet) {
        _agendamentosServico[i] = depois;
        houveMudanca = true;
      }
    }
    if (houveMudanca) {
      notifyListeners();
    }
  }

  void _iniciarStreamEmpresa() {
    _empresaSubscription?.cancel();
    if (_empresaIdAtual == null || !_firebaseHabilitado) return;

    debugPrint('>>> [Sync] 📡 Iniciando Stream do Documento da Empresa: $_empresaIdAtual');
    
    _empresaSubscription = _firebaseService.getEmpresaStream(_empresaIdAtual!).listen((empresa) {
      if (empresa != null) {
        // Verificar se houve mudança real (especialmente em configurações de agendamento)
        final configAntes = _empresaAtual?.configuracoes?['agendamento'];
        final configDepois = empresa.configuracoes?['agendamento'];
        
        bool mudou = _empresaAtual == null || 
                    _empresaAtual!.updatedAt.isBefore(empresa.updatedAt) ||
                    configAntes.toString() != configDepois.toString();
        
        if (mudou) {
          debugPrint('>>> [Sync] 🏢 Atualização da Empresa detectada via Stream: ${empresa.id}');
          _empresaAtual = empresa;
          notifyListeners();
          
          // Salvar localmente
          _storage.salvar('empresa_atual', empresa.toMap());
        }
      }
    }, onError: (e) {
      debugPrint('>>> [Sync] ❌ ERRO no Stream da Empresa: $e');
    });
  }

  void _iniciarStreamAgendamentos() {
    _agendamentosSubscription?.cancel();
    if (_empresaIdAtual == null || !_firebaseHabilitado) return;

    final timestamp = '${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}';
    debugPrint('>>> [Sync] 📡 [$timestamp] Iniciando Stream Otimizado: agendamentos_servico');

    // Diagnóstico: Se em 5 segundos nada vier do stream e a lista ainda estiver vazia,
    // fazer um get() direto para verificar se há dados no Firebase
    Future.delayed(const Duration(seconds: 5), () async {
      if (_empresaIdAtual != null && _agendamentosServico.isEmpty) {
        debugPrint('>>> [Sync] ⚠️ DIAGNÓSTICO: Stream não entregou agendamentos em 5s. Fazendo get() direto...');
        try {
          final count = await _firebaseService.contarAgendamentosPendentes(_empresaIdAtual!);
          debugPrint('>>> [Sync] 🔎 Resultado direto do Firebase: $count agendamentos na coleção');
          if (count > 0) {
            debugPrint('>>> [Sync] ⚠️ ATENÇÃO: Há $count agendamentos no Firebase mas o Stream não os entregou!');
            debugPrint('>>> [Sync] 🔄 Tentando recarregar via get() direto...');
            // Forcá-los via carregamento leve
            await _carregarDadosDoFirebase(modoLeve: true);
          } else {
            debugPrint('>>> [Sync] ℹ️ Nenhum agendamento no Firebase para empresa $_empresaIdAtual (coleção vazia)');
          }
        } catch (e) {
          debugPrint('>>> [Sync] ❌ Erro no diagnóstico do stream: $e');
        }
      }
    });
    
    _agendamentosSubscription = _firebaseService
        .getAgendamentosStream(_empresaIdAtual!)
        .listen((novosAgendamentos) {
      debugPrint('>>> [Sync] 📥 Snapshot recebido: ${novosAgendamentos.length} agendamentos do Firebase');
      if (novosAgendamentos.isEmpty && _primeiraCargaAgendamentosRealizada) return;

      bool houveMudanca = false;
      
      // OTIMIZAÇÃO: Cache de Clientes e Serviços para busca O(1)
      final clienteMap = {for (var c in _clientes) c.id: c};
      final servicoMap = {for (var s in _tiposServico) s.id: s};

      // 1. Deleção
      final idsRemotos = novosAgendamentos.map((a) => a.id).toSet();
      _agendamentosServico.removeWhere((a) {
        if (!idsRemotos.contains(a.id)) {
          houveMudanca = true;
          return true;
        }
        return false;
      });

      // 2. Upsert
      bool temNovoAgendamento = false;
      for (final agendamento in novosAgendamentos) {
        // Vínculo otimizado
        final cliente = clienteMap[agendamento.clienteId] ?? agendamento.cliente;
        Pet? pet;
        if (agendamento.petId != null && cliente != null) {
          try {
            pet = cliente.pets.firstWhere((p) => p.id == agendamento.petId);
          } catch (_) {}
        }
        final servico = servicoMap[agendamento.servicoId] ?? agendamento.servico;

        final agendamentoCompleto = agendamento.copyWith(
          cliente: cliente,
          pet: pet ?? agendamento.pet,
          servico: servico,
        );

        if (_upsertAgendamentoLocal(agendamentoCompleto)) {
          houveMudanca = true;
          debugPrint('>>> [Sync] ✅ Agendamento Local Atualizado: ${agendamentoCompleto.numero} (${agendamentoCompleto.id})');
          
          if (_primeiraCargaAgendamentosRealizada && !idsRemotos.contains(agendamento.id)) {
             // Só toca se for novo REAL (não estava no snapshot anterior)
          }
          // Lógica simplificada de notificação para evitar flood
          if (_primeiraCargaAgendamentosRealizada && agendamento.status == 'Aguardando Confirmação') {
            temNovoAgendamento = true;
          }
        }
      }

      if (!_primeiraCargaAgendamentosRealizada) {
        _primeiraCargaAgendamentosRealizada = true;
        debugPrint('>>> [Sync] ✅ Primeira carga de agendamentos concluída via Stream. Total: ${_agendamentosServico.length}');
      }

      if (temNovoAgendamento) {
        _tocarSomNotificacao();
      }
      
      notifyListeners();
      
      if (houveMudanca) {
        debugPrint('>>> [Sync] 🔔 Notificando UI: Mudança nos agendamentos (Total: ${_agendamentosServico.length})');
        _marcarSujo(LocalStorageService.keyAgendamentosServico);
      }
    }, onError: (e) {
      debugPrint('>>> [Sync] ❌ ERRO no Stream de Agendamentos: $e');
      Future.delayed(const Duration(seconds: 15), () {
        if (_empresaIdAtual != null) _iniciarStreamAgendamentos();
      });
    });
  }

  /// Força uma sincronização completa com o Firebase
  Future<void> forceSync() async {
    debugPrint('>>> [Sync] 🔄 Forçando sincronização manual...');
    _firebaseHabilitado = true; // Tentar reabilitar se estava desativado
    await iniciarSincronizacao();
    _iniciarStreamAgendamentos();
    notifyListeners();
  }

  void _reiniciarTimerSincronizacao() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
      if (_empresaIdAtual != null && !_isLoading) {
        _sincronizarSilenciosamente();
      }
    });
  }

  Future<void> _sincronizarSilenciosamente() async {
    if (!_firebaseHabilitado || _empresaIdAtual == null) return;
    
    try {
      debugPrint('>>> [Sync] 🔄 Sincronização silenciosa em andamento...');
      await _carregarDadosDoFirebase();
      notifyListeners(); // Notificar a UI sobre novos dados
      debugPrint('>>> [Sync] ✅ Sincronização silenciosa concluída');
    } catch (e) {
      debugPrint('>>> [Sync] ⚠ Erro na sincronização silenciosa: $e');
    }
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
  
  /// Método público para recarregar dados manualmente
  /// Mostra loading durante o carregamento
  Future<void> recarregarDados({bool modoLeve = false}) async {
    if (_empresaIdAtual == null) {
      print('>>> ⚠ Não é possível recarregar: empresa não definida');
      return;
    }
    
    _isLoading = true;
    _mensagemLoading = 'Recarregando dados...';
    notifyListeners();
    
    try {
      await iniciarSincronizacao(modoLeve: modoLeve);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  DataService() {
    // Não carregar dados fictícios no construtor
    // Eles serão carregados apenas se não houver dados salvos
    print('>>> DataService criado com instanceId: $_instanceId');
  }

  Future<void> iniciarSincronizacao({bool modoLeve = false}) async {
    // Atualizar mensagem de loading
    if (_isLoading) {
      _mensagemLoading = 'Sincronizando dados...';
      notifyListeners();
    }
    
    print('╔════════════════════════════════════════════════╗');
    print('║  INICIANDO CARREGAMENTO DE DADOS              ║');
    print('╚════════════════════════════════════════════════╝');
    
    // 1. Carregar dados do localStorage IMEDIATAMENTE (rápido)
    // Isso evita que o usuário veja listas vazias enquanto o Firebase carrega
    try {
      if (_isLoading) {
        _mensagemLoading = 'Carregando cache local...';
        notifyListeners();
      }
      await _carregarDadosSalvos();
      print('>>> ✓ Cache local carregado (${_clientes.length} clientes)');
      notifyListeners();
    } catch (e) {
      print('>>> ⚠ Erro ao carregar cache local: $e');
    }

    // 2. Tentar atualizar/sincronizar com Firebase
    if (_firebaseHabilitado) {
      try {
        if (_isLoading) {
          _mensagemLoading = 'Preparando seu ambiente...';
          notifyListeners();
        }
        print('>>> 🔥 Firebase é PRINCIPAL - Carregando dados do Firebase (Modo Leve: $modoLeve)...');
        await _carregarDadosDoFirebase(modoLeve: modoLeve).timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            print('>>> ⚠ Timeout ao carregar do Firebase (60s) - usando fallback');
            throw TimeoutException('Firebase timeout');
          },
        );
        
        // Se carregou dados do Firebase, verificar se precisa carregar do local também
        if (_produtos.isEmpty && _clientes.isEmpty) {
          if (_isLoading) {
            _mensagemLoading = 'Carregando dados locais...';
            notifyListeners();
          }
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
        
        // Verificar se é erro de quota
        final errorStr = e.toString().toLowerCase();
        final isQuotaError = errorStr.contains('quota') || 
                            errorStr.contains('resource-exhausted') ||
                            errorStr.contains('quota exceeded');
        
        if (isQuotaError) {
          print('>>> ⚠️⚠️⚠️ FIREBASE COM COTA EXCEDIDA - DESABILITANDO TEMPORARIAMENTE ⚠️⚠️⚠️');
          print('>>> Usando apenas localStorage até a cota ser renovada');
          _firebaseHabilitado = false; // Desabilitar Firebase temporariamente
        }
        
        print('>>> Tentando carregar do localStorage como fallback...');
        if (_isLoading) {
          _mensagemLoading = 'Carregando dados locais...';
          notifyListeners();
        }
        try {
          await _carregarDadosSalvos();
          print('>>> ✅ Dados carregados do localStorage com sucesso!');
          print('>>> ✅ Produtos carregados: ${_produtos.length}');
          // NÃO tentar sincronizar com Firebase se está com erro de quota
          if (!isQuotaError && (_produtos.isNotEmpty || _clientes.isNotEmpty)) {
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
      // Firebase DESABILITADO - carregar apenas do localStorage
      print('>>> 🔵 Firebase DESABILITADO - Carregando apenas do localStorage...');
      if (_isLoading) {
        _mensagemLoading = 'Carregando dados locais...';
        notifyListeners();
      }
      try {
        await _carregarDadosSalvos();
        print('>>> ✅ Dados carregados do localStorage (Firebase desabilitado)');
        print('>>> ✅ Produtos carregados: ${_produtos.length}');
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
    print('>>> ${_agendamentosServico.length} agendamentos carregados');
    print('>>> Persistência: ${_persistenciaHabilitada ? "HABILITADA" : "DESABILITADA"}');

    // SEMPRE iniciar os streams após carregar dados, se houver empresa selecionada
    if (_empresaIdAtual != null) {
      debugPrint('>>> [DataService] ✅ Sincronização concluída, ativando Streams em Tempo Real...');
      _iniciarStreamAgendamentos();
      _iniciarStreamProdutos();
      _iniciarStreamServicos();
    }
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
        await _salvarTodosDados(aguardarFirebase: false);
      } catch (e) {
        print('>>> Erro ao salvar dados do caixa: $e');
      }
      
      // Salvar imediatamente no Firebase
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        _firebaseService.salvarAberturaCaixa(_empresaIdAtual!, abertura).catchError((e) {
          debugPrint('>>> Erro ao salvar abertura de caixa no Firebase: $e');
          _adicionarSincronizacaoPendente();
        });
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
    
    // Salvar fechamento imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarFechamentoCaixa(_empresaIdAtual!, fechamento).catchError((e) {
        debugPrint('>>> Erro ao salvar fechamento de caixa no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
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
      await _salvarTodosDados(aguardarFirebase: false);
    } catch (e) {
      print('>>> Erro ao salvar sangria: $e');
    }
    
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarSangriaCaixa(_empresaIdAtual!, sangria).catchError((e) {
        debugPrint('>>> Erro ao salvar sangria no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
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
      await _salvarTodosDados(aguardarFirebase: false);
    } catch (e) {
      print('>>> Erro ao salvar suprimento: $e');
    }
    
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarSuprimentoCaixa(_empresaIdAtual!, suprimento).catchError((e) {
        debugPrint('>>> Erro ao salvar suprimento no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
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
  List<Cliente> get clientes {
    final ids = <String>{};
    return _clientes.where((c) => ids.add(c.id)).toList();
  }
  List<Produto> get produtos {
    final ids = <String>{};
    return _produtos.where((p) => ids.add(p.id)).toList();
  }
  List<Servico> get tiposServico {
    final ids = <String>{};
    return _tiposServico.where((s) => ids.add(s.id)).toList();
  }
  List<OrdemServico> get ordensServico => _ordensServico;
  List<Servico> get servicos => tiposServico;
  List<Funcionario> get funcionarios => _funcionarios;
  List<Pedido> get pedidos => _pedidos;
  List<Entrega> get entregas => _entregas;
  List<Motorista> get motoristas => _motoristas;
  List<TaxaEntrega> get taxasEntrega => _taxasEntrega;
  List<ContaPagar> get contasPagar => _contasPagar;
  List<VendaBalcao> get vendasBalcao => _vendasBalcao;
  List<TrocaDevolucao> get trocasDevolucoes => _trocasDevolucoes;
  List<AgendamentoServico> get agendamentosServico {
    final ids = <String>{};
    return _agendamentosServico.where((a) => ids.add(a.id)).toList();
  }
  List<LinkVendedor> get linksVendedores => _linksVendedores;
  List<ComissaoVendedor> get comissoesVendedores => _comissoesVendedores;

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
  // 
  // PADRÃO PARA NOVOS MÉTODOS CRUD:
  // ======================================
  // Quando criar novos métodos add/update/delete, SEMPRE seguir este padrão:
  // 
  // 1. Adicionar/atualizar na lista local
  // 2. Chamar notifyListeners()
  // 3. Chamar _salvarAutomaticamente() (salva no localStorage)
  // 4. Salvar IMEDIATAMENTE no Firebase usando o método individual do FirebaseService:
  //    if (_firebaseHabilitado && _empresaIdAtual != null) {
  //      _firebaseService.salvar[Entidade](_empresaIdAtual!, item).catchError((e) {
  //        debugPrint('>>> Erro ao salvar [entidade] no Firebase: $e');
  //        _adicionarSincronizacaoPendente();
  //      });
  //    }
  // 
  // 5. Para métodos de remoção, usar remover[Entidade] do FirebaseService
  // 
  // IMPORTANTE: Criar o método individual no FirebaseService ANTES de usar!
  // Exemplo: salvarCliente, salvarProduto, salvarFuncionario, etc.
  // ======================================

  Future<void> addCliente(Cliente cliente) async {
    _clientes.add(cliente);
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce para clientes)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyClientes), 
        _clientes
      );
      debugPrint('>>> [Cliente] ✅ Salvo localmente: ${cliente.nome} (ID: ${cliente.id})');
    } catch (e) {
      debugPrint('>>> [Cliente] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarCliente(_empresaIdAtual!, cliente);
        debugPrint('>>> [Cliente] ✅✅✅ SALVO NO FIREBASE COM SUCESSO! ✅✅✅');
        debugPrint('>>> [Cliente] Nome: ${cliente.nome}');
        debugPrint('>>> [Cliente] ID: ${cliente.id}');
        debugPrint('>>> [Cliente] Empresa: $_empresaIdAtual');
      } catch (e, stackTrace) {
        debugPrint('>>> [Cliente] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [Cliente] Erro: $e');
        debugPrint('>>> [Cliente] StackTrace: $stackTrace');
        debugPrint('>>> [Cliente] ⚠️ DADOS SALVOS LOCALMENTE - serão sincronizados quando possível');
        _adicionarSincronizacaoPendente();
        // NÃO re-throw - dados já estão salvos localmente, não precisa bloquear
      }
    } else {
      debugPrint('>>> [Cliente] ⚠️⚠️⚠️ NÃO SALVOU NO FIREBASE! ⚠️⚠️⚠️');
      if (!_firebaseHabilitado) {
        debugPrint('>>> [Cliente] Motivo: Firebase NÃO está habilitado');
      }
      if (_empresaIdAtual == null) {
        debugPrint('>>> [Cliente] Motivo: Empresa NÃO está selecionada (empresaIdAtual é null)');
      }
    }
  }

  Future<void> updateCliente(Cliente cliente) async {
    final index = _clientes.indexWhere((c) => c.id == cliente.id);
    if (index != -1) {
      final clienteAntigo = _clientes[index];
      _clientes[index] = cliente;
      
      // SINCRONIZAÇÃO: Atualizar agendamentos quando pets forem alterados
      _atualizarAgendamentosComPetsAtualizados(clienteAntigo, cliente);
      
      // Notificar listeners IMEDIATAMENTE para atualizar a UI
      notifyListeners();
      
      // Marcar a lista de clientes como suja para salvamento automático
      _marcarSujo(LocalStorageService.keyClientes);
      
      // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarCliente(_empresaIdAtual!, cliente);
          debugPrint('>>> [Cliente] ✅✅✅ ATUALIZADO NO FIREBASE COM SUCESSO! ✅✅✅');
        } catch (e, stackTrace) {
          debugPrint('>>> [Cliente] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
          debugPrint('>>> [Cliente] Erro: $e');
          debugPrint('>>> [Cliente] StackTrace: $stackTrace');
          _adicionarSincronizacaoPendente();
          // NÃO re-throw - dados já estão salvos localmente
        }
      }
    }
  }
  
  /// Atualiza os agendamentos quando os dados dos pets são alterados no cadastro
  void _atualizarAgendamentosComPetsAtualizados(Cliente clienteAntigo, Cliente clienteNovo) {
    // Criar mapa de pets atualizados por ID para busca rápida
    final petsAtualizados = <String, Pet>{};
    for (final pet in clienteNovo.pets) {
      petsAtualizados[pet.id] = pet;
    }
    
    // Verificar se algum pet foi alterado
    bool temAlteracao = false;
    for (final petNovo in clienteNovo.pets) {
      final petAntigo = clienteAntigo.pets.firstWhere(
        (p) => p.id == petNovo.id,
        orElse: () => Pet(
          id: '',
          nome: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime(1970),
        ),
      );
      
      // Verificar se houve alteração comparando updatedAt
      if (petNovo.updatedAt.isAfter(petAntigo.updatedAt)) {
        temAlteracao = true;
        break;
      }
    }
    
    if (!temAlteracao && clienteAntigo.pets.length == clienteNovo.pets.length) {
      // Nenhum pet foi alterado, não precisa atualizar agendamentos
      return;
    }
    
    // Buscar todos os agendamentos deste cliente
    final agendamentosParaAtualizar = <AgendamentoServico>[];
    
    for (final agendamento in _agendamentosServico) {
      // Verificar se o agendamento pertence a este cliente
      if (agendamento.clienteId == clienteNovo.id && agendamento.petId != null) {
        // Verificar se o pet ainda existe no cliente atualizado
        final petAtualizado = petsAtualizados[agendamento.petId];
        
        if (petAtualizado != null) {
          // Pet existe e foi atualizado - atualizar referência no agendamento
          final agendamentoAtualizado = agendamento.copyWith(
            pet: petAtualizado,
            cliente: clienteNovo,
            updatedAt: DateTime.now(),
          );
          
          agendamentosParaAtualizar.add(agendamentoAtualizado);
          debugPrint('>>> [Sincronização] Atualizando agendamento ${agendamento.numero} com dados atualizados do pet ${petAtualizado.nome}');
        } else {
          // Pet foi removido do cliente - manter agendamento mas sem referência ao pet
          debugPrint('>>> [Sincronização] ⚠ Pet ${agendamento.petId} foi removido do cliente, mas agendamento ${agendamento.numero} mantido');
        }
      }
    }
    
    // Atualizar agendamentos na lista
    for (final agendamentoAtualizado in agendamentosParaAtualizar) {
      final indexAgendamento = _agendamentosServico.indexWhere((a) => a.id == agendamentoAtualizado.id);
      if (indexAgendamento != -1) {
        _agendamentosServico[indexAgendamento] = agendamentoAtualizado;
      }
    }
    
    if (agendamentosParaAtualizar.isNotEmpty) {
      debugPrint('>>> [Sincronização] ✓ ${agendamentosParaAtualizar.length} agendamento(s) atualizado(s) com dados do pet');
      
      // Salvar agendamentos atualizados
      _salvarAutomaticamente();
      
      // Salvar agendamentos no Firebase
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        for (final agendamento in agendamentosParaAtualizar) {
          _firebaseService.salvarAgendamentoServico(_empresaIdAtual!, agendamento).catchError((e) {
            debugPrint('>>> [Sincronização] Erro ao atualizar agendamento ${agendamento.numero} no Firebase: $e');
            _adicionarSincronizacaoPendente();
          });
        }
      }
    }
  }

  void deleteCliente(String id) {
    _clientes.removeWhere((c) => c.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover imediatamente do Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.removerCliente(_empresaIdAtual!, id).catchError((e) {
        debugPrint('>>> Erro ao remover cliente do Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  // ============ CRUD Funcionario ============

  Future<void> addFuncionario(Funcionario funcionario) async {
    _funcionarios.add(funcionario);
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce para funcionários)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyFuncionarios), 
        _funcionarios
      );
      debugPrint('>>> [Funcionário] ✅ Salvo localmente: ${funcionario.nome} (ID: ${funcionario.id})');
    } catch (e) {
      debugPrint('>>> [Funcionário] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarFuncionario(_empresaIdAtual!, funcionario);
        debugPrint('>>> [Funcionário] ✅✅✅ SALVO NO FIREBASE COM SUCESSO! ✅✅✅');
        debugPrint('>>> [Funcionário] Nome: ${funcionario.nome}');
        debugPrint('>>> [Funcionário] ID: ${funcionario.id}');
        debugPrint('>>> [Funcionário] Empresa: $_empresaIdAtual');
      } catch (e, stackTrace) {
        debugPrint('>>> [Funcionário] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [Funcionário] Erro: $e');
        debugPrint('>>> [Funcionário] StackTrace: $stackTrace');
        debugPrint('>>> [Funcionário] ⚠️ DADOS SALVOS LOCALMENTE - serão sincronizados quando possível');
        _adicionarSincronizacaoPendente();
      }
    } else {
      debugPrint('>>> [Funcionário] ⚠️⚠️⚠️ NÃO SALVOU NO FIREBASE! ⚠️⚠️⚠️');
      if (!_firebaseHabilitado) {
        debugPrint('>>> [Funcionário] Motivo: Firebase NÃO está habilitado');
      }
      if (_empresaIdAtual == null) {
        debugPrint('>>> [Funcionário] Motivo: Empresa NÃO está selecionada (empresaIdAtual é null)');
      }
    }
  }

  Future<void> updateFuncionario(Funcionario funcionario) async {
    final index = _funcionarios.indexWhere((f) => f.id == funcionario.id);
    if (index != -1) {
      _funcionarios[index] = funcionario;
      notifyListeners();
      
      // Salvar localmente IMEDIATAMENTE (sem debounce para funcionários)
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyFuncionarios), 
          _funcionarios
        );
        debugPrint('>>> [Funcionário] ✅ Atualizado localmente: ${funcionario.nome} (ID: ${funcionario.id})');
      } catch (e) {
        debugPrint('>>> [Funcionário] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Salvar imediatamente no Firebase
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarFuncionario(_empresaIdAtual!, funcionario);
          debugPrint('>>> [Funcionário] ✅✅✅ ATUALIZADO NO FIREBASE COM SUCESSO! ✅✅✅');
          debugPrint('>>> [Funcionário] Nome: ${funcionario.nome}');
          debugPrint('>>> [Funcionário] ID: ${funcionario.id}');
        } catch (e, stackTrace) {
          debugPrint('>>> [Funcionário] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
          debugPrint('>>> [Funcionário] Erro: $e');
          debugPrint('>>> [Funcionário] StackTrace: $stackTrace');
          debugPrint('>>> [Funcionário] ⚠️ DADOS ATUALIZADOS LOCALMENTE - serão sincronizados quando possível');
          _adicionarSincronizacaoPendente();
        }
      } else {
        debugPrint('>>> [Funcionário] ⚠️⚠️⚠️ NÃO ATUALIZOU NO FIREBASE! ⚠️⚠️⚠️');
        if (!_firebaseHabilitado) {
          debugPrint('>>> [Funcionário] Motivo: Firebase NÃO está habilitado');
        }
        if (_empresaIdAtual == null) {
          debugPrint('>>> [Funcionário] Motivo: Empresa NÃO está selecionada (empresaIdAtual é null)');
        }
      }
    }
  }

  void deleteFuncionario(String id) {
    _funcionarios.removeWhere((f) => f.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover imediatamente do Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.removerFuncionario(_empresaIdAtual!, id).catchError((e) {
        debugPrint('>>> Erro ao remover funcionário do Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  // ============ CRUD LinkVendedor ============

  Future<void> addLinkVendedor(LinkVendedor link) async {
    _linksVendedores.add(link);
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce para links de vendedores)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyLinksVendedores), 
        _linksVendedores
      );
      debugPrint('>>> [LinkVendedor] ✅ Salvo localmente: ${link.codigoLink} (ID: ${link.id})');
    } catch (e) {
      debugPrint('>>> [LinkVendedor] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarLinkVendedor(_empresaIdAtual!, link);
        debugPrint('>>> [LinkVendedor] ✅✅✅ SALVO NO FIREBASE COM SUCESSO! ✅✅✅');
        debugPrint('>>> [LinkVendedor] Código: ${link.codigoLink}');
        debugPrint('>>> [LinkVendedor] ID: ${link.id}');
      } catch (e, stackTrace) {
        debugPrint('>>> [LinkVendedor] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [LinkVendedor] Erro: $e');
        debugPrint('>>> [LinkVendedor] StackTrace: $stackTrace');
        debugPrint('>>> [LinkVendedor] ⚠️ DADOS SALVOS LOCALMENTE - serão sincronizados quando possível');
        _adicionarSincronizacaoPendente();
      }
    } else {
      debugPrint('>>> [LinkVendedor] ⚠️⚠️⚠️ NÃO SALVOU NO FIREBASE! ⚠️⚠️⚠️');
      if (!_firebaseHabilitado) {
        debugPrint('>>> [LinkVendedor] Motivo: Firebase NÃO está habilitado');
      }
      if (_empresaIdAtual == null) {
        debugPrint('>>> [LinkVendedor] Motivo: Empresa NÃO está selecionada (empresaIdAtual é null)');
      }
    }
  }

  Future<void> updateLinkVendedor(LinkVendedor link) async {
    final index = _linksVendedores.indexWhere((l) => l.id == link.id);
    if (index != -1) {
      _linksVendedores[index] = link;
      notifyListeners();
      await _salvarTodosDados();
      // Salvar imediatamente no Firebase
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        _firebaseService.salvarLinkVendedor(_empresaIdAtual!, link).catchError((e) {
          debugPrint('>>> Erro ao atualizar link de vendedor no Firebase: $e');
          _adicionarSincronizacaoPendente();
        });
      }
    }
  }

  void deleteLinkVendedor(String id) {
    _linksVendedores.removeWhere((l) => l.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover imediatamente do Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.removerLinkVendedor(_empresaIdAtual!, id).catchError((e) {
        debugPrint('>>> Erro ao remover link de vendedor do Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  // ============ CRUD ComissaoVendedor ============

  Future<void> addComissaoVendedor(ComissaoVendedor comissao) async {
    debugPrint('>>> [ComissaoVendedor] ➕ Adicionando nova comissão: ${comissao.id}');
    debugPrint('>>> [ComissaoVendedor]     Vendedor: ${comissao.funcionarioNome} (ID: ${comissao.funcionarioId})');
    debugPrint('>>> [ComissaoVendedor]     Pedido: ${comissao.pedidoNumero} (ID: ${comissao.pedidoId})');
    debugPrint('>>> [ComissaoVendedor]     Valor: R\$ ${comissao.valorComissao}');

    _comissoesVendedores.add(comissao);
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE
    try {
      final chave = _getChaveComEmpresa(LocalStorageService.keyComissoesVendedores);
      debugPrint('>>> [ComissaoVendedor] 💾 Salvando localmente na chave: $chave');
      await _storage.salvarLista(chave, _comissoesVendedores);
      debugPrint('>>> [ComissaoVendedor] ✅ Salva localmente com sucesso! Total na lista: ${_comissoesVendedores.length}');
    } catch (e) {
      debugPrint('>>> [ComissaoVendedor] ❌ ERRO ao salvar localmente: $e');
    }
    
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      debugPrint('>>> [ComissaoVendedor] 🔥 Tentando salvar no Firebase (empresa: $_empresaIdAtual)...');
      try {
        await _firebaseService.salvarComissaoVendedor(_empresaIdAtual!, comissao);
        debugPrint('>>> [ComissaoVendedor] ✅✅✅ SALVA NO FIREBASE COM SUCESSO! ✅✅✅');
      } catch (e, stackTrace) {
        debugPrint('>>> [ComissaoVendedor] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [ComissaoVendedor] Erro: $e');
        debugPrint('>>> [ComissaoVendedor] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
      }
    } else {
      if (!_firebaseHabilitado) debugPrint('>>> [ComissaoVendedor] Motivo: Firebase NÃO está habilitado');
      if (_empresaIdAtual == null) debugPrint('>>> [ComissaoVendedor] Motivo: Empresa NÃO está selecionada');
    }
  }

  Future<void> updateComissaoVendedor(ComissaoVendedor comissao) async {
    final index = _comissoesVendedores.indexWhere((c) => c.id == comissao.id);
    if (index != -1) {
      _comissoesVendedores[index] = comissao;
      notifyListeners();
      await _salvarTodosDados();
      // Atualizar imediatamente no Firebase
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        _firebaseService.atualizarComissaoVendedor(_empresaIdAtual!, comissao).catchError((e) {
          debugPrint('>>> Erro ao atualizar comissão de vendedor no Firebase: $e');
          _adicionarSincronizacaoPendente();
        });
      }
    }
  }

  void deleteComissaoVendedor(String id) {
    _comissoesVendedores.removeWhere((c) => c.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover imediatamente do Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.removerComissaoVendedor(_empresaIdAtual!, id).catchError((e) {
        debugPrint('>>> Erro ao remover comissão de vendedor do Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  // ============ CRUD ContaPagar ============

  Future<void> addContaPagar(ContaPagar conta) async {
    _contasPagar.add(conta);
    notifyListeners();
    _salvarAutomaticamente();
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarContaPagar(_empresaIdAtual!, conta).catchError((e) {
        debugPrint('>>> Erro ao salvar conta a pagar no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  void updateContaPagar(ContaPagar conta) {
    final index = _contasPagar.indexWhere((c) => c.id == conta.id);
    if (index != -1) {
      _contasPagar[index] = conta;
      notifyListeners();
      _salvarAutomaticamente();
      // Salvar imediatamente no Firebase
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        _firebaseService.salvarContaPagar(_empresaIdAtual!, conta).catchError((e) {
          debugPrint('>>> Erro ao atualizar conta a pagar no Firebase: $e');
          _adicionarSincronizacaoPendente();
        });
      }
    }
  }

  /// Busca um cliente por telefone (procura localmente e no Firebase)
  Future<List<Cliente>> buscarClientePorTelefone(String telefone) async {
    final normalizado = telefone.replaceAll(RegExp(r'\D'), '');
    if (normalizado.length < 8) return [];

    final idsVistos = <String>{};
    final resultadoFinal = <Cliente>[];

    // 1. Procurar localmente na memória (rápido)
    final candidatosLocais = _clientes.where((c) {
      final t1 = c.telefone.replaceAll(RegExp(r'\D'), '');
      final t2 = (c.telefone2 ?? '').replaceAll(RegExp(r'\D'), '');
      final w = (c.whatsapp ?? '').replaceAll(RegExp(r'\D'), '');
      
      return t1 == normalizado || t2 == normalizado || w == normalizado ||
             (normalizado.length >= 8 && (t1.endsWith(normalizado) || t2.endsWith(normalizado) || w.endsWith(normalizado))) ||
             (t1.length >= 8 && normalizado.endsWith(t1));
    }).toList();

    for (final c in candidatosLocais) {
      if (!idsVistos.contains(c.id)) {
        idsVistos.add(c.id);
        resultadoFinal.add(c);
      }
    }

    // 2. Se tem Firebase, buscar SEMPRE no Firebase também para garantir dados frescos (pets, endereço)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      debugPrint('>>> [DataService] 🔍 Buscando no Firebase por telefone: $normalizado');
      try {
        final remotos = await _firebaseService.buscarClientesPorTelefone(_empresaIdAtual!, normalizado);
        if (remotos.isNotEmpty) {
          for (final c in remotos) {
            // Se já temos o cliente localmente, substituir pelo remoto (mais fresco)
            final indexLocal = resultadoFinal.indexWhere((loc) => loc.id == c.id);
            if (indexLocal != -1) {
              resultadoFinal[indexLocal] = c;
            } else {
              resultadoFinal.add(c);
              idsVistos.add(c.id);
            }

            // Atualizar cache local
            final cacheIndex = _clientes.indexWhere((loc) => loc.id == c.id);
            if (cacheIndex != -1) {
              _clientes[cacheIndex] = c;
            } else {
              _clientes.add(c);
            }
          }
          notifyListeners();
        }
      } catch (e) {
        debugPrint('>>> [DataService] Erro na busca remota: $e');
      }
    }

    // Ordenar: Quem tem pets primeiro
    resultadoFinal.sort((a, b) {
      if (a.pets.isNotEmpty && b.pets.isEmpty) return -1;
      if (a.pets.isEmpty && b.pets.isNotEmpty) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return resultadoFinal;
  }


  void deleteContaPagar(String id) {
    _contasPagar.removeWhere((c) => c.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover imediatamente do Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.removerContaPagar(_empresaIdAtual!, id).catchError((e) {
        debugPrint('>>> Erro ao remover conta a pagar do Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
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
    // DEBUG CRÍTICO: Verificar dados antes de adicionar
    debugPrint('>>> [Produto] ========================================');
    debugPrint('>>> [Produto] ADICIONANDO NOVO PRODUTO');
    debugPrint('>>> [Produto] Nome: ${produto.nome}');
    debugPrint('>>> [Produto] ID: ${produto.id}');
    debugPrint('>>> [Produto] exibirNaLoja: ${produto.exibirNaLoja}');
    debugPrint('>>> [Produto] emDestaque: ${produto.emDestaque}');
    debugPrint('>>> [Produto] estoque: ${produto.estoque}');
    debugPrint('>>> [Produto] Verificando toMap...');
    final map = produto.toMap();
    debugPrint('>>> [Produto] toMap["exibirNaLoja"]: ${map["exibirNaLoja"]}');
    debugPrint('>>> [Produto] ========================================');
    
    _produtos.add(produto);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyProdutos);
    
    // Salvar imediatamente no Firebase (se disponível)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarProduto(_empresaIdAtual!, produto);
        debugPrint('>>> [Produto] ✅✅✅ SALVO NO FIREBASE COM SUCESSO! ✅✅✅');
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        final isQuotaError = errorStr.contains('quota') || 
                            errorStr.contains('resource-exhausted') ||
                            errorStr.contains('quota exceeded');
        
        if (isQuotaError) {
          debugPrint('>>> [Produto] ⚠️⚠️⚠️ FIREBASE COM COTA EXCEDIDA - DESABILITANDO TEMPORARIAMENTE ⚠️⚠️⚠️');
          debugPrint('>>> [Produto] Dados salvos LOCALMENTE - Firebase será desabilitado até a cota ser renovada');
          _firebaseHabilitado = false; // Desabilitar Firebase temporariamente
        } else {
          debugPrint('>>> [Produto] ❌ Erro ao salvar produto no Firebase: $e');
        }
        _adicionarSincronizacaoPendente();
        // NÃO re-throw - dados já estão salvos localmente
      }
    }
  }

  Future<void> updateProduto(Produto produto) async {
    // DEBUG CRÍTICO: Verificar dados antes de atualizar
    debugPrint('>>> [Produto] ========================================');
    debugPrint('>>> [Produto] ATUALIZANDO PRODUTO');
    debugPrint('>>> [Produto] Nome: ${produto.nome}');
    debugPrint('>>> [Produto] ID: ${produto.id}');
    debugPrint('>>> [Produto] exibirNaLoja: ${produto.exibirNaLoja}');
    debugPrint('>>> [Produto] emDestaque: ${produto.emDestaque}');
    debugPrint('>>> [Produto] estoque: ${produto.estoque}');
    final map = produto.toMap();
    debugPrint('>>> [Produto] toMap["exibirNaLoja"]: ${map["exibirNaLoja"]}');
    debugPrint('>>> [Produto] ========================================');
    
    final index = _produtos.indexWhere((p) => p.id == produto.id);
    if (index != -1) {
      _produtos[index] = produto;
      notifyListeners();
      
      // Salvar localmente IMEDIATAMENTE (sem debounce para produtos)
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyProdutos), 
          _produtos
        );
        debugPrint('>>> [Produto] ✅ Atualizado localmente: ${produto.nome} (ID: ${produto.id})');
        debugPrint('>>> [Produto] exibirNaLoja: ${produto.exibirNaLoja}, estoque: ${produto.estoque}');
        
        // Verificar se foi salvo corretamente
        final produtosSalvos = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyProdutos));
        final produtoSalvo = produtosSalvos.firstWhere(
          (p) => p['id'] == produto.id,
          orElse: () => {},
        );
        if (produtoSalvo.isNotEmpty) {
          debugPrint('>>> [Produto] ✅ Verificação pós-salvamento:');
          debugPrint('>>> [Produto]    exibirNaLoja no storage: ${produtoSalvo["exibirNaLoja"]}');
        }
      } catch (e) {
        debugPrint('>>> [Produto] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Salvar imediatamente no Firebase (se disponível)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarProduto(_empresaIdAtual!, produto);
          debugPrint('>>> [Produto] ✅✅✅ ATUALIZADO NO FIREBASE COM SUCESSO! ✅✅✅');
        } catch (e) {
          final errorStr = e.toString().toLowerCase();
          final isQuotaError = errorStr.contains('quota') || 
                              errorStr.contains('resource-exhausted') ||
                              errorStr.contains('quota exceeded');
          
          if (isQuotaError) {
            debugPrint('>>> [Produto] ⚠️⚠️⚠️ FIREBASE COM COTA EXCEDIDA - DESABILITANDO TEMPORARIAMENTE ⚠️⚠️⚠️');
            debugPrint('>>> [Produto] Dados atualizados LOCALMENTE - Firebase será desabilitado até a cota ser renovada');
            _firebaseHabilitado = false; // Desabilitar Firebase temporariamente
          } else {
            debugPrint('>>> [Produto] ❌ Erro ao atualizar produto no Firebase: $e');
          }
          _adicionarSincronizacaoPendente();
          // NÃO re-throw - dados já estão salvos localmente
        }
      }
    } else {
      debugPrint('>>> [Produto] ⚠️ Produto não encontrado para atualizar: ${produto.id}');
    }
  }

  void deleteProduto(String id) {
    _produtos.removeWhere((p) => p.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover imediatamente do Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.removerProduto(_empresaIdAtual!, id).catchError((e) {
        debugPrint('>>> Erro ao remover produto do Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  /// Deleta todos os produtos (com confirmação necessária antes de chamar)
  /// PROTEÇÃO: Cria backup automático antes de deletar
  Future<void> deleteAllProdutos({required bool confirmar}) async {
    if (!confirmar) {
      throw Exception('⚠️ PROTEÇÃO: deleteAllProdutos requer confirmação explícita (confirmar: true)');
    }
    
    if (_empresaIdAtual == null) {
      throw Exception('⚠️ Nenhuma empresa selecionada');
    }
    
    final empresaId = _empresaIdAtual!;
    final totalProdutos = _produtos.length;
    
    // PROTEÇÃO: Backup automático antes de deletar
    print('>>> 🛡️ PROTEÇÃO: Criando backup antes de deletar $totalProdutos produtos...');
    try {
      // Salvar backup completo no localStorage com timestamp
      final backupKey = 'backup_produtos_${empresaId}_${DateTime.now().millisecondsSinceEpoch}';
      final backupData = _produtos.map((p) => p.toMap()).toList();
      await _storage.salvarLista(backupKey, backupData);
      print('>>> ✅ Backup criado: $backupKey ($totalProdutos produtos)');
    } catch (e) {
      print('>>> ❌ ERRO CRÍTICO: Não foi possível criar backup! Operação cancelada.');
      print('>>> Erro: $e');
      throw Exception('⚠️ PROTEÇÃO: Não foi possível criar backup. Operação cancelada para evitar perda de dados.');
    }
    
    // Log de auditoria
    print('>>> 📋 AUDITORIA: Deletando $totalProdutos produtos da empresa $empresaId');
    print('>>> 📋 AUDITORIA: Timestamp: ${DateTime.now()}');
    
    // Deletar do Firebase primeiro se estiver habilitado
    if (_firebaseHabilitado) {
      try {
        await _firebaseService.deletarTodosProdutos(empresaId);
        debugPrint('>>> [DataService] Todos os produtos deletados do Firebase');
      } catch (e) {
        debugPrint('>>> [DataService] ⚠️ Erro ao deletar produtos do Firebase: $e');
        // NÃO CONTINUA se Firebase falhar - dados podem estar inconsistentes
        print('>>> ⚠️ PROTEÇÃO: Erro no Firebase. Verifique antes de continuar.');
      }
    }
    
    // Limpar lista local
    _produtos.clear();
    notifyListeners();
    
    // Salvar lista vazia no localStorage e Firebase
    await _salvarTodosDados();
    debugPrint('>>> [DataService] Todos os produtos deletados localmente e do Firebase');
    print('>>> ✅ Operação concluída. Backup disponível em: backup_produtos_${empresaId}_*');
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
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarEstoqueHistorico(_empresaIdAtual!, historico).catchError((e) {
        debugPrint('>>> Erro ao salvar histórico de estoque no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  // ============ CRUD NotaEntrada ============

  Future<void> addNotaEntrada(NotaEntrada nota) async {
    _notasEntrada.add(nota);
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyNotasEntrada), 
        _notasEntrada
      );
      debugPrint('>>> [NotaEntrada] ✅ Salva localmente: ${nota.id}');
    } catch (e) {
      debugPrint('>>> [NotaEntrada] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarNotaEntrada(_empresaIdAtual!, nota);
        debugPrint('>>> [NotaEntrada] ✅✅✅ SALVA NO FIREBASE COM SUCESSO! ✅✅✅');
      } catch (e, stackTrace) {
        debugPrint('>>> [NotaEntrada] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [NotaEntrada] Erro: $e');
        debugPrint('>>> [NotaEntrada] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
        // NÃO re-throw - dados já estão salvos localmente
      }
    } else {
      debugPrint('>>> [NotaEntrada] ⚠️ NÃO SALVOU NO FIREBASE!');
      if (!_firebaseHabilitado) debugPrint('>>> [NotaEntrada] Motivo: Firebase NÃO está habilitado');
      if (_empresaIdAtual == null) debugPrint('>>> [NotaEntrada] Motivo: Empresa NÃO está selecionada');
    }
  }

  void updateNotaEntrada(NotaEntrada nota) {
    final index = _notasEntrada.indexWhere((n) => n.id == nota.id);
    if (index != -1) {
      _notasEntrada[index] = nota;
      notifyListeners();
      _salvarAutomaticamente();
      // Salvar imediatamente no Firebase
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        _firebaseService.salvarNotaEntrada(_empresaIdAtual!, nota).catchError((e) {
          debugPrint('>>> Erro ao atualizar nota de entrada no Firebase: $e');
          _adicionarSincronizacaoPendente();
        });
      }
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
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyServicos), 
        _tiposServico
      );
      debugPrint('>>> [Servico] ✅ Salvo localmente: ${servico.nome} (ID: ${servico.id})');
    } catch (e) {
      debugPrint('>>> [Servico] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    debugPrint('>>> DataService: Serviço "${servico.nome}" adicionado com sucesso.');
    
    // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarServico(_empresaIdAtual!, servico);
        debugPrint('>>> [Servico] ✅✅✅ SALVO NO FIREBASE COM SUCESSO! ✅✅✅');
      } catch (e, stackTrace) {
        debugPrint('>>> [Servico] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [Servico] Erro: $e');
        debugPrint('>>> [Servico] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
        // NÃO re-throw - dados já estão salvos localmente
      }
    } else {
      debugPrint('>>> [Servico] ⚠️ NÃO SALVOU NO FIREBASE!');
      if (!_firebaseHabilitado) debugPrint('>>> [Servico] Motivo: Firebase NÃO está habilitado');
      if (_empresaIdAtual == null) debugPrint('>>> [Servico] Motivo: Empresa NÃO está selecionada');
    }
  }

  Future<void> addServico(Servico servico) async {
    await addTipoServico(servico);
  }

  Future<void> updateTipoServico(Servico servico) async {
    final index = _tiposServico.indexWhere((s) => s.id == servico.id);
    if (index != -1) {
      _tiposServico[index] = servico;
      // Notificar listeners IMEDIATAMENTE para atualizar a UI
      notifyListeners();
      
      // Salvar localmente IMEDIATAMENTE (sem debounce)
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyServicos), 
          _tiposServico
        );
        debugPrint('>>> [Servico] ✅ Atualizado localmente: ${servico.nome} (ID: ${servico.id})');
      } catch (e) {
        debugPrint('>>> [Servico] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarServico(_empresaIdAtual!, servico);
          debugPrint('>>> [Servico] ✅✅✅ ATUALIZADO NO FIREBASE COM SUCESSO! ✅✅✅');
        } catch (e, stackTrace) {
          debugPrint('>>> [Servico] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
          debugPrint('>>> [Servico] Erro: $e');
          debugPrint('>>> [Servico] StackTrace: $stackTrace');
          _adicionarSincronizacaoPendente();
          // NÃO re-throw - dados já estão salvos localmente
        }
      } else {
        debugPrint('>>> [Servico] ⚠️ NÃO ATUALIZOU NO FIREBASE!');
        if (!_firebaseHabilitado) debugPrint('>>> [Servico] Motivo: Firebase NÃO está habilitado');
        if (_empresaIdAtual == null) debugPrint('>>> [Servico] Motivo: Empresa NÃO está selecionada');
      }
    }
  }

  void deleteTipoServico(String id) {
    _tiposServico.removeWhere((s) => s.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover imediatamente do Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.removerServico(_empresaIdAtual!, id).catchError((e) {
        debugPrint('>>> Erro ao remover serviço do Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  // ============ CRUD Ordem de Servico ============

  Future<void> addOrdemServico(OrdemServico os) async {
    _ordensServico.add(os);
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyOrdensServico), 
        _ordensServico
      );
      debugPrint('>>> [OrdemServico] ✅ Salva localmente: ${os.id}');
    } catch (e) {
      debugPrint('>>> [OrdemServico] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarOrdemServico(_empresaIdAtual!, os);
        debugPrint('>>> [OrdemServico] ✅✅✅ SALVA NO FIREBASE COM SUCESSO! ✅✅✅');
      } catch (e, stackTrace) {
        debugPrint('>>> [OrdemServico] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [OrdemServico] Erro: $e');
        debugPrint('>>> [OrdemServico] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
        // NÃO re-throw - dados já estão salvos localmente
      }
    } else {
      debugPrint('>>> [OrdemServico] ⚠️ NÃO SALVOU NO FIREBASE!');
      if (!_firebaseHabilitado) debugPrint('>>> [OrdemServico] Motivo: Firebase NÃO está habilitado');
      if (_empresaIdAtual == null) debugPrint('>>> [OrdemServico] Motivo: Empresa NÃO está selecionada');
    }
  }

  Future<void> updateOrdemServico(OrdemServico os) async {
    final index = _ordensServico.indexWhere((o) => o.id == os.id);
    if (index != -1) {
      _ordensServico[index] = os;
      // Notificar listeners IMEDIATAMENTE para atualizar a UI
      notifyListeners();
      
      // Salvar localmente IMEDIATAMENTE (sem debounce)
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyOrdensServico), 
          _ordensServico
        );
        debugPrint('>>> [OrdemServico] ✅ Atualizada localmente: ${os.id}');
      } catch (e) {
        debugPrint('>>> [OrdemServico] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarOrdemServico(_empresaIdAtual!, os);
          debugPrint('>>> [OrdemServico] ✅✅✅ ATUALIZADA NO FIREBASE COM SUCESSO! ✅✅✅');
        } catch (e, stackTrace) {
          debugPrint('>>> [OrdemServico] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
          debugPrint('>>> [OrdemServico] Erro: $e');
          debugPrint('>>> [OrdemServico] StackTrace: $stackTrace');
          _adicionarSincronizacaoPendente();
          // NÃO re-throw - dados já estão salvos localmente
        }
      } else {
        debugPrint('>>> [OrdemServico] ⚠️ NÃO ATUALIZOU NO FIREBASE!');
        if (!_firebaseHabilitado) debugPrint('>>> [OrdemServico] Motivo: Firebase NÃO está habilitado');
        if (_empresaIdAtual == null) debugPrint('>>> [OrdemServico] Motivo: Empresa NÃO está selecionada');
      }
    }
  }

  void deleteOrdemServico(String id) {
    _ordensServico.removeWhere((o) => o.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Nota: Não há método de remoção individual no FirebaseService para ordem de serviço
    // A remoção será feita na próxima sincronização completa
  }

  // ============ CRUD Agendamento Serviço ============

  /// Envia notificação WhatsApp para agendamento (se configurado)
  Future<void> _enviarNotificacaoWhatsAppAgendamento(
    AgendamentoServico agendamento, {
    bool isNovo = true,
  }) async {
    // Verificar se a empresa tem WhatsApp configurado
    if (_empresaAtual == null || !_empresaAtual!.whatsappAtivo) {
      debugPrint('>>> [WhatsApp] Notificações WhatsApp não estão ativas para esta empresa');
      return;
    }

    // Verificar se as configurações estão completas
    if (_empresaAtual!.whatsappApiUrl == null ||
        _empresaAtual!.whatsappApiKey == null ||
        _empresaAtual!.whatsappInstanceName == null) {
      debugPrint('>>> [WhatsApp] Configurações de WhatsApp incompletas');
      return;
    }

    // Verificar se o cliente tem telefone
    final telefone = agendamento.cliente?.whatsapp ?? agendamento.cliente?.telefone;
    if (telefone == null || telefone.isEmpty) {
      debugPrint('>>> [WhatsApp] Cliente não tem telefone cadastrado');
      return;
    }

    try {
      final service = WhatsAppService.fromEmpresa(_empresaAtual!);
      
      if (isNovo) {
        // Notificação de novo agendamento
        debugPrint('>>> [WhatsApp] Enviando notificação de novo agendamento...');
        final sucesso = await service.notificarAgendamentoCriado(
          agendamento: agendamento,
          nomeEmpresa: _empresaAtual!.nomeExibicao,
          telefoneEmpresa: _empresaAtual!.telefone,
        );
        debugPrint('>>> [WhatsApp] Notificação enviada: ${sucesso ? "SUCESSO" : "FALHOU"}');
      } else {
        // Notificação de alteração de status
        debugPrint('>>> [WhatsApp] Enviando notificação de alteração de status...');
        final sucesso = await service.notificarStatusAlterado(
          agendamento: agendamento,
          nomeEmpresa: _empresaAtual!.nomeExibicao,
        );
        debugPrint('>>> [WhatsApp] Notificação enviada: ${sucesso ? "SUCESSO" : "FALHOU"}');
      }
    } catch (e) {
      debugPrint('>>> [WhatsApp] Erro ao enviar notificação: $e');
      // Não bloquear o fluxo principal se a notificação falhar
    }
  }

  /// Adiciona um novo agendamento de serviço com validação de conflitos
  /// Adiciona múltiplos agendamentos em lote (otimizado)
  Future<void> addAgendamentosBatch(List<AgendamentoServico> agendamentos) async {
    if (agendamentos.isEmpty) return;

    final novosCompletos = <AgendamentoServico>[];

    for (var agendamento in agendamentos) {
      AgendamentoServico agendamentoComNumero = agendamento;
      if (agendamento.numero.isEmpty || agendamento.numero == 'AGD-0000') {
        final numero = getProximoNumeroAgendamento();
        agendamentoComNumero = agendamento.copyWith(numero: numero);
      }

      final completo = _vincularReferenciasAgendamento(agendamentoComNumero);
      
      // Evitar duplicatas em memória
      _agendamentosServico.removeWhere((a) => a.id == completo.id);
      _agendamentosServico.add(completo);
      novosCompletos.add(completo);
    }

    notifyListeners();

    // Salvar localmente (UMA SÓ VEZ)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyAgendamentosServico), 
        _agendamentosServico
      );
    } catch (e) {
      debugPrint('>>> [Batch] Erro LocalStorage: $e');
    }

    _salvarAutomaticamente();

    // Salvar no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      for (final completo in novosCompletos) {
        _firebaseService.salvarAgendamentoServico(_empresaIdAtual!, completo).catchError((e) {
          debugPrint('>>> [Batch] Erro Firebase: $e');
          _adicionarSincronizacaoPendente();
        });
      }
    }

    // Notificações (opcional: pode ser pesado se forem muitos, mas geralmente são poucos pets)
    for (final completo in novosCompletos) {
      _enviarNotificacaoWhatsAppAgendamento(completo, isNovo: true);
    }
  }

  /// Helper para vincular referências de serviço, cliente e pet
  AgendamentoServico _vincularReferenciasAgendamento(AgendamentoServico agendamento) {
    Servico? servico;
    if (agendamento.servicoId != null && !agendamento.servicoId!.startsWith('vacina_')) {
      try {
        servico = _tiposServico.firstWhere((s) => s.id == agendamento.servicoId);
      } catch (_) {}
    }

    // Vincular múltiplos serviços
    List<Servico> servicosVinculados = [];
    if (agendamento.servicosIds.isNotEmpty) {
      for (final sId in agendamento.servicosIds) {
        if (sId.startsWith('vacina_')) continue;
        try {
          final s = _tiposServico.firstWhere((ts) => ts.id == sId);
          servicosVinculados.add(s);
        } catch (_) {}
      }
    }

    Cliente? cliente = agendamento.cliente;
    if (cliente == null && agendamento.clienteId != null) {
      try {
        cliente = _clientes.firstWhere((c) => c.id == agendamento.clienteId);
      } catch (_) {}
    }

    Pet? pet = agendamento.pet;
    if (pet == null && agendamento.petId != null && cliente != null) {
      try {
        pet = cliente.pets.firstWhere((p) => p.id == agendamento.petId);
      } catch (_) {}
    }

    return agendamento.copyWith(
      servico: servico,
      servicos: servicosVinculados,
      cliente: cliente,
      pet: pet,
    );
  }

  Future<AgendamentoServico> addAgendamentoServico(
    AgendamentoServico agendamento,
  ) async {
    // Gerar número de agendamento se não tiver
    AgendamentoServico agendamentoComNumero = agendamento;
    if (agendamento.numero.isEmpty || agendamento.numero == 'AGD-0000') {
      final numero = getProximoNumeroAgendamento();
      agendamentoComNumero = agendamento.copyWith(numero: numero);
    }
    
    final agendamentoCompleto = _vincularReferenciasAgendamento(agendamentoComNumero);

    // Evitar duplicatas em memória antes de adicionar
    _agendamentosServico.removeWhere((a) => a.id == agendamentoCompleto.id);
    _agendamentosServico.add(agendamentoCompleto);
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce para agendamentos)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyAgendamentosServico), 
        _agendamentosServico
      );
    } catch (e) {
      debugPrint('>>> [Agendamento] ❌ Erro ao salvar localmente: $e');
    }
    
    _salvarAutomaticamente();
    
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarAgendamentoServico(_empresaIdAtual!, agendamentoCompleto);
      } catch (e) {
        _adicionarSincronizacaoPendente();
      }
    }
    
    _enviarNotificacaoWhatsAppAgendamento(agendamentoCompleto, isNovo: true);
    
    return agendamentoCompleto;
  }

  /// Atualiza um agendamento existente com validação de conflitos
  Future<void> updateAgendamentoServico(AgendamentoServico agendamento) async {
    final index = _agendamentosServico.indexWhere((a) => a.id == agendamento.id);
    if (index == -1) {
      throw Exception('Agendamento não encontrado');
    }

    // Validação de conflito de horário REMOVIDA - permitir múltiplos agendamentos no mesmo horário
    // A duração do serviço é mantida apenas para informação, sem bloquear outros agendamentos

    final agendamentoPrevio = agendamento.copyWith(
      updatedAt: DateTime.now(),
    );

    final itemAnterior = _agendamentosServico[index];
    final agendamentoAtualizado = _vincularReferenciasAgendamento(agendamentoPrevio);
    _agendamentosServico[index] = agendamentoAtualizado;

    // Se mudou de ativo para inativo (ex: Cancelou), tentar promover alguém da espera
    if (itemAnterior.isAtivo && !agendamentoAtualizado.isAtivo) {
       _promoverAgendamentoEmEspera(itemAnterior);
    }

    notifyListeners();
    _marcarSujo(LocalStorageService.keyAgendamentosServico);
    
    // Salvar imediatamente no Firebase
    debugPrint('>>> [Agendamento] 🔍 Verificando condições para atualizar no Firebase...');
    debugPrint('>>> [Agendamento] Firebase habilitado: $_firebaseHabilitado');
    debugPrint('>>> [Agendamento] Empresa ID atual: $_empresaIdAtual');
    
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      debugPrint('>>> [Agendamento] ✅ Condições OK, tentando atualizar no Firebase...');
      try {
        await _firebaseService.salvarAgendamentoServico(_empresaIdAtual!, agendamentoAtualizado);
        debugPrint('>>> [Agendamento] ✅✅✅ ATUALIZADO NO FIREBASE COM SUCESSO! ✅✅✅');
        debugPrint('>>> [Agendamento] Número: ${agendamentoAtualizado.numero}');
        debugPrint('>>> [Agendamento] ID: ${agendamentoAtualizado.id}');
      } catch (e, stackTrace) {
        debugPrint('>>> [Agendamento] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [Agendamento] Erro: $e');
        debugPrint('>>> [Agendamento] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
        rethrow;
      }
    } else {
      debugPrint('>>> [Agendamento] ⚠️⚠️⚠️ NÃO ATUALIZOU NO FIREBASE! ⚠️⚠️⚠️');
      if (!_firebaseHabilitado) {
        debugPrint('>>> [Agendamento] Motivo: Firebase NÃO está habilitado');
      }
      if (_empresaIdAtual == null) {
        debugPrint('>>> [Agendamento] Motivo: Empresa NÃO está selecionada');
      }
    }
    
    // Enviar notificação WhatsApp se status mudou (não é novo)
    _enviarNotificacaoWhatsAppAgendamento(agendamentoAtualizado, isNovo: false);
  }

  /// Remove um agendamento
  Future<void> deleteAgendamentoServico(String id) async {
    final agendamentoRemovido = _agendamentosServico.firstWhere(
      (a) => a.id == id,
      orElse: () => throw Exception('Agendamento não encontrado'),
    );
    
    _agendamentosServico.removeWhere((a) => a.id == id);
    
    // Se o agendamento removido era ativo, tentar promover alguém da espera
    if (agendamentoRemovido.isAtivo) {
      await _promoverAgendamentoEmEspera(agendamentoRemovido);
    }

    notifyListeners();
    _marcarSujo(LocalStorageService.keyAgendamentosServico);
    
    // Remover do Firebase se habilitado
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.deletarAgendamentoServico(_empresaIdAtual!, id);
        debugPrint('>>> [Agendamento] ✅ Removido do Firebase: ${agendamentoRemovido.numero} (ID: ${agendamentoRemovido.id})');
      } catch (e, stackTrace) {
        debugPrint('>>> [Agendamento] ❌ Erro ao remover do Firebase: $e');
        debugPrint('>>> [Agendamento] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
      }
    }
  }

  /// Tenta promover um agendamento que está "Em Espera" para "Agendado"
  /// após um agendamento conflitante ser removido ou cancelado
  Future<void> _promoverAgendamentoEmEspera(AgendamentoServico agendamentoAntigo) async {
    try {
      // Procurar o primeiro agendamento em espera que conflite com o horário do que saiu
      final emEspera = _agendamentosServico.where((a) => a.isEmEspera).toList();
      
      // Ordenar por data de criação para garantir que o primeiro que entrou na fila seja o primeiro a sair
      emEspera.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      AgendamentoServico? paraPromover;
      for (var a in emEspera) {
        if (a.temSobreposicaoHorario(agendamentoAntigo)) {
          // Verificar se agora este agendamento não conflita com mais NINGUÉM que esteja ATIVO
          bool aindaTemConflito = _agendamentosServico.any((ativo) => ativo.isAtivo && ativo.temSobreposicaoHorario(a));
          if (!aindaTemConflito) {
            paraPromover = a;
            break;
          }
        }
      }

      if (paraPromover != null) {
        debugPrint('>>> [Agenda] 🚀 Promovendo agendamento ${paraPromover.numero} da espera para Agendado');
        final promovido = paraPromover.copyWith(
          status: 'Agendado',
          updatedAt: DateTime.now(),
        );
        
        // Atualizar na lista local
        final idx = _agendamentosServico.indexWhere((a) => a.id == promovido.id);
        if (idx != -1) {
          _agendamentosServico[idx] = promovido;
        }

        // Salvar no Firebase
        if (_firebaseHabilitado && _empresaIdAtual != null) {
          await _firebaseService.salvarAgendamentoServico(_empresaIdAtual!, promovido);
        }
        
        // Notificar via WhatsApp que saiu da espera (opcional, mas bom)
        _enviarNotificacaoWhatsAppAgendamento(promovido, isNovo: false);
      }
    } catch (e) {
      debugPrint('>>> [Agenda] Erro ao promover agendamento: $e');
    }
  }
  
  /// Obtém um agendamento com dados atualizados do pet e cliente
  /// Garante que os dados do pet sempre estejam sincronizados
  AgendamentoServico? getAgendamentoComDadosAtualizados(String id) {
    final agendamento = _agendamentosServico.firstWhere(
      (a) => a.id == id,
      orElse: () => throw Exception('Agendamento não encontrado'),
    );
    
    // Buscar cliente atualizado
    Cliente? clienteAtualizado;
    if (agendamento.clienteId != null) {
      try {
        clienteAtualizado = _clientes.firstWhere((c) => c.id == agendamento.clienteId);
      } catch (e) {
        debugPrint('>>> [Agendamento] ⚠ Cliente ${agendamento.clienteId} não encontrado');
      }
    }
    
    // Buscar pet atualizado do cliente
    Pet? petAtualizado;
    if (agendamento.petId != null && clienteAtualizado != null) {
      try {
        petAtualizado = clienteAtualizado.pets.firstWhere((p) => p.id == agendamento.petId);
      } catch (e) {
        debugPrint('>>> [Agendamento] ⚠ Pet ${agendamento.petId} não encontrado no cliente');
      }
    }
    
    // Retornar agendamento com dados atualizados
    return agendamento.copyWith(
      cliente: clienteAtualizado ?? agendamento.cliente,
      pet: petAtualizado ?? agendamento.pet,
    );
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

  /// Verifica disponibilidade de horário
  bool checkDisponibilidade(DateTime inicio, int duracaoMinutos, {int intervaloMinutos = 0, bool ignorarPendentes = false}) {
    final duracaoTotal = duracaoMinutos + intervaloMinutos;
    final fim = inicio.add(Duration(minutes: duracaoTotal));
    
    final isModuloPet = _empresaAtual?.moduloPet ?? false;
    
    // Verificar conflitos com agendamentos existentes
    for (final a in _agendamentosServico) {
      if (a.status == 'Cancelado' && (!a.travado || !isModuloPet)) continue;
      
      // Se ignorarPendentes for true, não bloqueamos por solicitações ainda não confirmadas
      if (ignorarPendentes && a.status == 'Aguardando Confirmação') continue;
      
      final aInicio = a.dataAgendamento;
      final aFim = a.dataTermino; // Já inclui o intervalo do agendamento existente
      
      // Lógica de sobreposição: (InicioA < FimB) && (FimA > InicioB)
      if (aInicio.isBefore(fim) && aFim.isAfter(inicio)) {
        // Conflito detectado
        return false;
      }
    }

    // Verificar conflitos com horários bloqueados (Configuração da Empresa)
    try {
      final config = _empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>?;
      
      // -- VERIFICAR HORÁRIO DE FUNCIONAMENTO --
      final hAberturaStr = config?['horarioAbertura']?.toString() ?? '08:00';
      final hFechamentoStr = config?['horarioFechamento']?.toString() ?? '18:00';
      
      final hAbertura = _timeToDouble(hAberturaStr);
      final hFechamento = _timeToDouble(hFechamentoStr);
      
      final double horaInicio = inicio.hour + (inicio.minute / 60.0);
      final double horaFim = horaInicio + (duracaoMinutos / 60.0);

      // Se começar antes de abrir ou terminar depois de fechar, está bloqueado.
      if (isModuloPet && (horaInicio < hAbertura || horaFim > hFechamento)) {
        debugPrint('>>> [DataService] Fora do horário de funcionamento: $horaInicio - $horaFim (Expediente: $hAberturaStr - $hFechamentoStr)');
        return false;
      }

      final bloqueados = config?['horariosIndisponiveis'] as List<dynamic>?;
      if (bloqueados != null && bloqueados.isNotEmpty) {
        final String dataStr = '${inicio.year}-${inicio.month.toString().padLeft(2, '0')}-${inicio.day.toString().padLeft(2, '0')}';
        final int diaSemana = inicio.weekday; // 1=Mon ... 7=Sun
        
        for (final b in bloqueados) {
          final bMap = Map<String, dynamic>.from(b);
          final String? bInicioStr = bMap['inicio'];
          final String? bFimStr = bMap['fim'];
          
          if (bInicioStr == null || bFimStr == null) continue;
          
          // Verificar se este bloqueio se aplica à data em questão
          final String tipo = bMap['tipo']?.toString() ?? 'todos';
          bool aplicaSeAData = false;
          
          switch (tipo) {
            case 'dia':
              // Dia específico
              aplicaSeAData = bMap['data'] == dataStr;
              break;
            case 'periodo':
              // Período (de-até)
              final String? dataInicioStr = bMap['dataInicio'];
              final String? dataFimStr = bMap['dataFim'];
              if (dataInicioStr != null && dataFimStr != null) {
                aplicaSeAData = dataStr.compareTo(dataInicioStr) >= 0 && dataStr.compareTo(dataFimStr) <= 0;
              }
              break;
            case 'diaSemana':
              // Dias da semana
              final diasSemana = bMap['diasSemana'];
              if (diasSemana is List) {
                aplicaSeAData = diasSemana.any((d) => d == diaSemana);
              }
              break;
            case 'todos':
            default:
              // Todos os dias (ou bloqueio antigo sem tipo)
              // Compatibilidade: se tem campo 'data' sem 'tipo', tratar como dia específico
              if (bMap['data'] != null && tipo == 'todos') {
                aplicaSeAData = bMap['data'] == dataStr;
              } else {
                aplicaSeAData = true;
              }
              break;
          }
          
          if (!aplicaSeAData) continue;
          
          final bInicioParts = bInicioStr.split(':');
          final bFimParts = bFimStr.split(':');
          
          if (bInicioParts.length != 2 || bFimParts.length != 2) continue;
          
          final double bInicio = int.parse(bInicioParts[0]) + int.parse(bInicioParts[1]) / 60.0;
          final double bFim = int.parse(bFimParts[0]) + int.parse(bFimParts[1]) / 60.0;
          
          // Sobreposição: (InicioA < FimB) && (FimA > InicioB)
          if (horaInicio < bFim && horaFim > bInicio) {
            debugPrint('>>> [DataService] Horário bloqueado detectado: $bInicioStr - $bFimStr (tipo: $tipo)');
            return false;
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [DataService] Erro ao validar horários bloqueados: $e');
    }
    
    return true;
  }

  double _timeToDouble(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length != 2) return 0.0;
      return int.parse(parts[0]) + (int.parse(parts[1]) / 60.0);
    } catch (_) {
      return 0.0;
    }
  }



  /// Aprova um agendamento (muda status de 'Aguardando Confirmação' para 'Agendado')
  Future<void> aprovarAgendamento(String agendamentoId) async {
    final index = _agendamentosServico.indexWhere((a) => a.id == agendamentoId);
    if (index != -1) {
      final agendamento = _agendamentosServico[index];
      
      // Atribuir número sequencial se ainda não tiver um válido (muito comum em agendamentos online)
    String numero = agendamento.numero;
    if (numero.isEmpty || numero == 'AGD-0000' || numero == 'TS-999') {
      numero = getProximoNumeroAgendamento();
      debugPrint('>>> [Agendamento] Gerado novo número para aprovação: $numero');
    }

    final agendamentoPrevio = agendamento.copyWith(
      numero: numero,
      status: 'Agendado',
      updatedAt: DateTime.now(),
    );
    
    // Vincular referências para garantir que o agendamento tenha os objetos (Serviço, Cliente, Pet)
    // Isso evita que ele suma da agenda caso o filtro dependa destes objetos
    final agendamentoAtualizado = _vincularReferenciasAgendamento(agendamentoPrevio);
    
    // Garantir que a lista local tem a referência mais atualizada e em destaque
    _upsertAgendamentoLocal(agendamentoAtualizado, prioritario: true);
    
    notifyListeners();
    forceUpdate(); // Forçar rebuild global para garantir que o sino e agenda atualizem
    
    // Sincronizar com Firebase IMEDIATAMENTE (sem debounce para aprovações)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarAgendamentoServico(_empresaIdAtual!, agendamentoAtualizado);
        debugPrint('>>> [Agendamento] ✅ Salvo no Firebase com sucesso');
        notifyListeners(); 
      } catch (e) {
        debugPrint('>>> [Agendamento] ❌ Erro ao aprovar no Firebase: $e');
      }
    }
    
    notifyListeners();
    _marcarSujo(LocalStorageService.keyAgendamentosServico);
    
    // Notificar cliente via WhatsApp em BACKGROUND para não travar a UI
    // ignore: unawaited_futures
    _enviarNotificacaoWhatsAppAgendamento(agendamentoAtualizado, isNovo: false);
    
    // Notificar novamente para garantir que a UI refletiu o salvamento
    notifyListeners();
    forceUpdate(); // Forçar rebuild global para garantir que o sino e agenda atualizem
    } else {
      debugPrint('>>> [Agendamento] ❌ ERRO: Agendamento $agendamentoId não encontrado para aprovação!');
    }
  }

  /// Rejeita um agendamento (muda status para 'Cancelado')
  Future<void> rejeitarAgendamento(String agendamentoId) async {
    final index = _agendamentosServico.indexWhere((a) => a.id == agendamentoId);
    if (index != -1) {
      final agendamento = _agendamentosServico[index];
      final agendamentoPrevio = agendamento.copyWith(
        status: 'Cancelado',
        updatedAt: DateTime.now(),
      );
      
      final agendamentoAtualizado = _vincularReferenciasAgendamento(agendamentoPrevio);
      
      // Atualizar a instância com prioridade
      _upsertAgendamentoLocal(agendamentoAtualizado, prioritario: true);
      
      notifyListeners();
      _salvarAutomaticamente();
      
      // Sincronizar com Firebase
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarAgendamentoServico(_empresaIdAtual!, agendamentoAtualizado);
        } catch (e) {
          debugPrint('>>> [Agendamento] Erro ao rejeitar no Firebase: $e');
        }
      }
      
      // Notificar cliente via WhatsApp em background
      // ignore: unawaited_futures
      _enviarNotificacaoWhatsAppAgendamento(agendamentoAtualizado, isNovo: false);

      notifyListeners();
      forceUpdate();
    }
  }

  /// Verifica se há conflito de horário para um agendamento

  // ============ CRUD Pedido ============

  Future<void> addPedido(Pedido pedido) async {
    
    _pedidos.add(pedido);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyPedidos);
    
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarPedido(_empresaIdAtual!, pedido);
        debugPrint('>>> [Pedido] ✅✅✅ SALVO NO FIREBASE COM SUCESSO! ✅✅✅');
        debugPrint('>>> [Pedido] Número: ${pedido.numero}');
        debugPrint('>>> [Pedido] ID: ${pedido.id}');
      } catch (e, stackTrace) {
        debugPrint('>>> [Pedido] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [Pedido] Erro: $e');
        debugPrint('>>> [Pedido] StackTrace: $stackTrace');
        debugPrint('>>> [Pedido] ⚠️ DADOS SALVOS LOCALMENTE - serão sincronizados quando possível');
        _adicionarSincronizacaoPendente();
      }
    } else {
      debugPrint('>>> [Pedido] ⚠️⚠️⚠️ NÃO SALVOU NO FIREBASE! ⚠️⚠️⚠️');
      if (!_firebaseHabilitado) {
        debugPrint('>>> [Pedido] Motivo: Firebase NÃO está habilitado');
      }
      if (_empresaIdAtual == null) {
        debugPrint('>>> [Pedido] Motivo: Empresa NÃO está selecionada (empresaIdAtual é null)');
      }
    }
    
    debugPrint('>>> Pedido salvo com sucesso: ${pedido.numero}');
  }

  Future<void> updatePedido(Pedido pedido) async {
    
    final index = _pedidos.indexWhere((p) => p.id == pedido.id);
    debugPrint('>>> DataService.updatePedido: id=${pedido.id}, index=$index');
    debugPrint('>>> Novo total: ${pedido.total}');
    debugPrint('>>> Novo totalRecebido: ${pedido.totalRecebido}');
    if (index != -1) {
      _pedidos[index] = pedido;
      notifyListeners();
      _marcarSujo(LocalStorageService.keyPedidos);
      
      // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarPedido(_empresaIdAtual!, pedido);
          debugPrint('>>> [Pedido] ✅✅✅ ATUALIZADO NO FIREBASE COM SUCESSO! ✅✅✅');
        } catch (e, stackTrace) {
          debugPrint('>>> [Pedido] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
          debugPrint('>>> [Pedido] Erro: $e');
          debugPrint('>>> [Pedido] StackTrace: $stackTrace');
          _adicionarSincronizacaoPendente();
          // NÃO re-throw - dados já estão salvos localmente
        }
      } else {
        debugPrint('>>> [Pedido] ⚠️ NÃO ATUALIZOU NO FIREBASE!');
        if (!_firebaseHabilitado) debugPrint('>>> [Pedido] Motivo: Firebase NÃO está habilitado');
        if (_empresaIdAtual == null) debugPrint('>>> [Pedido] Motivo: Empresa NÃO está selecionada');
      }
    } else {
      debugPrint('>>> ERRO: Pedido não encontrado para atualizar!');
    }
  }

  void deletePedido(String id) {
    _pedidos.removeWhere((p) => p.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Nota: Não há método de remoção individual no FirebaseService para pedido
    // A remoção será feita na próxima sincronização completa
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
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyEntregas), 
        _entregas
      );
      debugPrint('>>> [Entrega] ✅ Salva localmente: ${entrega.id}');
    } catch (e) {
      debugPrint('>>> [Entrega] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarEntrega(_empresaIdAtual!, entrega);
        debugPrint('>>> [Entrega] ✅✅✅ SALVA NO FIREBASE COM SUCESSO! ✅✅✅');
      } catch (e, stackTrace) {
        debugPrint('>>> [Entrega] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [Entrega] Erro: $e');
        debugPrint('>>> [Entrega] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
        // NÃO re-throw - dados já estão salvos localmente
      }
    } else {
      debugPrint('>>> [Entrega] ⚠️ NÃO SALVOU NO FIREBASE!');
      if (!_firebaseHabilitado) debugPrint('>>> [Entrega] Motivo: Firebase NÃO está habilitado');
      if (_empresaIdAtual == null) debugPrint('>>> [Entrega] Motivo: Empresa NÃO está selecionada');
    }
  }

  Future<void> updateEntrega(Entrega entrega) async {
    final index = _entregas.indexWhere((e) => e.id == entrega.id);
    if (index != -1) {
      _entregas[index] = entrega;
      // Notificar listeners IMEDIATAMENTE para atualizar a UI
      notifyListeners();
      
      // Salvar localmente IMEDIATAMENTE (sem debounce)
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyEntregas), 
          _entregas
        );
        debugPrint('>>> [Entrega] ✅ Atualizada localmente: ${entrega.id}');
      } catch (e) {
        debugPrint('>>> [Entrega] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarEntrega(_empresaIdAtual!, entrega);
          debugPrint('>>> [Entrega] ✅✅✅ ATUALIZADA NO FIREBASE COM SUCESSO! ✅✅✅');
        } catch (e, stackTrace) {
          debugPrint('>>> [Entrega] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
          debugPrint('>>> [Entrega] Erro: $e');
          debugPrint('>>> [Entrega] StackTrace: $stackTrace');
          _adicionarSincronizacaoPendente();
          // NÃO re-throw - dados já estão salvos localmente
        }
      } else {
        debugPrint('>>> [Entrega] ⚠️ NÃO ATUALIZOU NO FIREBASE!');
        if (!_firebaseHabilitado) debugPrint('>>> [Entrega] Motivo: Firebase NÃO está habilitado');
        if (_empresaIdAtual == null) debugPrint('>>> [Entrega] Motivo: Empresa NÃO está selecionada');
      }
    }
  }

  void deleteEntrega(String id) {
    _entregas.removeWhere((e) => e.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Nota: Não há método de remoção individual no FirebaseService para entrega
    // A remoção será feita na próxima sincronização completa
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
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyTaxasEntrega), 
        _taxasEntrega
      );
      debugPrint('>>> [TaxaEntrega] ✅ Salva localmente: ${taxa.bairro} (ID: ${taxa.id})');
    } catch (e) {
      debugPrint('>>> [TaxaEntrega] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarTaxaEntrega(_empresaIdAtual!, taxa);
        debugPrint('>>> [TaxaEntrega] ✅✅✅ SALVA NO FIREBASE COM SUCESSO! ✅✅✅');
      } catch (e, stackTrace) {
        debugPrint('>>> [TaxaEntrega] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [TaxaEntrega] Erro: $e');
        debugPrint('>>> [TaxaEntrega] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
        // NÃO re-throw - dados já estão salvos localmente
      }
    } else {
      debugPrint('>>> [TaxaEntrega] ⚠️ NÃO SALVOU NO FIREBASE!');
      if (!_firebaseHabilitado) debugPrint('>>> [TaxaEntrega] Motivo: Firebase NÃO está habilitado');
      if (_empresaIdAtual == null) debugPrint('>>> [TaxaEntrega] Motivo: Empresa NÃO está selecionada');
    }
  }

  Future<void> updateTaxaEntrega(TaxaEntrega taxa) async {
    final index = _taxasEntrega.indexWhere((t) => t.id == taxa.id);
    if (index != -1) {
      _taxasEntrega[index] = taxa;
      // Notificar listeners IMEDIATAMENTE para atualizar a UI
      notifyListeners();
      
      // Salvar localmente IMEDIATAMENTE (sem debounce)
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyTaxasEntrega), 
          _taxasEntrega
        );
        debugPrint('>>> [TaxaEntrega] ✅ Atualizada localmente: ${taxa.bairro} (ID: ${taxa.id})');
      } catch (e) {
        debugPrint('>>> [TaxaEntrega] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarTaxaEntrega(_empresaIdAtual!, taxa);
          debugPrint('>>> [TaxaEntrega] ✅✅✅ ATUALIZADA NO FIREBASE COM SUCESSO! ✅✅✅');
        } catch (e, stackTrace) {
          debugPrint('>>> [TaxaEntrega] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
          debugPrint('>>> [TaxaEntrega] Erro: $e');
          debugPrint('>>> [TaxaEntrega] StackTrace: $stackTrace');
          _adicionarSincronizacaoPendente();
          // NÃO re-throw - dados já estão salvos localmente
        }
      } else {
        debugPrint('>>> [TaxaEntrega] ⚠️ NÃO ATUALIZOU NO FIREBASE!');
        if (!_firebaseHabilitado) debugPrint('>>> [TaxaEntrega] Motivo: Firebase NÃO está habilitado');
        if (_empresaIdAtual == null) debugPrint('>>> [TaxaEntrega] Motivo: Empresa NÃO está selecionada');
      }
    }
  }

  Future<void> deleteTaxaEntrega(String id) async {
    _taxasEntrega.removeWhere((t) => t.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    
    // Remover do Firebase se habilitado
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.removerTaxaEntrega(_empresaIdAtual!, id);
        debugPrint('>>> [TaxaEntrega] ✅ Removida do Firebase com sucesso!');
      } catch (e) {
        debugPrint('>>> [TaxaEntrega] ❌ Erro ao remover do Firebase: $e');
        _adicionarSincronizacaoPendente();
      }
    }
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
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyMotoristas), 
        _motoristas
      );
      debugPrint('>>> [Motorista] ✅ Salvo localmente: ${motorista.nome} (ID: ${motorista.id})');
    } catch (e) {
      debugPrint('>>> [Motorista] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarMotorista(_empresaIdAtual!, motorista);
        debugPrint('>>> [Motorista] ✅✅✅ SALVO NO FIREBASE COM SUCESSO! ✅✅✅');
      } catch (e, stackTrace) {
        debugPrint('>>> [Motorista] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [Motorista] Erro: $e');
        debugPrint('>>> [Motorista] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
        // NÃO re-throw - dados já estão salvos localmente
      }
    } else {
      debugPrint('>>> [Motorista] ⚠️ NÃO SALVOU NO FIREBASE!');
      if (!_firebaseHabilitado) debugPrint('>>> [Motorista] Motivo: Firebase NÃO está habilitado');
      if (_empresaIdAtual == null) debugPrint('>>> [Motorista] Motivo: Empresa NÃO está selecionada');
    }
  }

  Future<void> updateMotorista(Motorista motorista) async {
    final index = _motoristas.indexWhere((m) => m.id == motorista.id);
    if (index != -1) {
      _motoristas[index] = motorista;
      // Notificar listeners IMEDIATAMENTE para atualizar a UI
      notifyListeners();
      
      // Salvar localmente IMEDIATAMENTE (sem debounce)
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyMotoristas), 
          _motoristas
        );
        debugPrint('>>> [Motorista] ✅ Atualizado localmente: ${motorista.nome} (ID: ${motorista.id})');
      } catch (e) {
        debugPrint('>>> [Motorista] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarMotorista(_empresaIdAtual!, motorista);
          debugPrint('>>> [Motorista] ✅✅✅ ATUALIZADO NO FIREBASE COM SUCESSO! ✅✅✅');
        } catch (e, stackTrace) {
          debugPrint('>>> [Motorista] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
          debugPrint('>>> [Motorista] Erro: $e');
          debugPrint('>>> [Motorista] StackTrace: $stackTrace');
          _adicionarSincronizacaoPendente();
          // NÃO re-throw - dados já estão salvos localmente
        }
      } else {
        debugPrint('>>> [Motorista] ⚠️ NÃO ATUALIZOU NO FIREBASE!');
        if (!_firebaseHabilitado) debugPrint('>>> [Motorista] Motivo: Firebase NÃO está habilitado');
        if (_empresaIdAtual == null) debugPrint('>>> [Motorista] Motivo: Empresa NÃO está selecionada');
      }
    }
  }

  void deleteMotorista(String id) {
    _motoristas.removeWhere((m) => m.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Nota: Não há método de remoção individual no FirebaseService para motorista
    // A remoção será feita na próxima sincronização completa
  }

  // ============ CRUD Venda Balcão ============

  Future<void> addVendaBalcao(VendaBalcao venda) async {
    _vendasBalcao.add(venda);
    print('✓ Venda ${venda.numero} salva em memória');
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    
    // Salvar localmente IMEDIATAMENTE (sem debounce)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyVendasBalcao), 
        _vendasBalcao
      );
      debugPrint('>>> [VendaBalcao] ✅ Salva localmente: ${venda.numero} (ID: ${venda.id})');
    } catch (e) {
      debugPrint('>>> [VendaBalcao] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      try {
        await _firebaseService.salvarVendaBalcao(_empresaIdAtual!, venda);
        debugPrint('>>> [VendaBalcao] ✅✅✅ SALVA NO FIREBASE COM SUCESSO! ✅✅✅');
      } catch (e, stackTrace) {
        debugPrint('>>> [VendaBalcao] ❌❌❌ ERRO AO SALVAR NO FIREBASE! ❌❌❌');
        debugPrint('>>> [VendaBalcao] Erro: $e');
        debugPrint('>>> [VendaBalcao] StackTrace: $stackTrace');
        _adicionarSincronizacaoPendente();
        // NÃO re-throw - dados já estão salvos localmente
      }
    } else {
      debugPrint('>>> [VendaBalcao] ⚠️ NÃO SALVOU NO FIREBASE! ⚠️⚠️⚠️');
      if (!_firebaseHabilitado) debugPrint('>>> [VendaBalcao] Motivo: Firebase NÃO está habilitado');
      if (_empresaIdAtual == null) debugPrint('>>> [VendaBalcao] Motivo: Empresa NÃO está selecionada');
    }
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
      // Notificar listeners IMEDIATAMENTE para atualizar a UI
      notifyListeners();
      print('>>> notifyListeners() chamado');
      
      // Salvar localmente IMEDIATAMENTE (sem debounce)
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyVendasBalcao), 
          _vendasBalcao
        );
        debugPrint('>>> [VendaBalcao] ✅ Atualizada localmente: ${venda.numero} (ID: ${venda.id})');
      } catch (e) {
        debugPrint('>>> [VendaBalcao] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Salvar imediatamente no Firebase (aguardando para garantir que foi salvo)
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        try {
          await _firebaseService.salvarVendaBalcao(_empresaIdAtual!, venda);
          debugPrint('>>> [VendaBalcao] ✅✅✅ ATUALIZADA NO FIREBASE COM SUCESSO! ✅✅✅');
        } catch (e, stackTrace) {
          debugPrint('>>> [VendaBalcao] ❌❌❌ ERRO AO ATUALIZAR NO FIREBASE! ❌❌❌');
          debugPrint('>>> [VendaBalcao] Erro: $e');
          debugPrint('>>> [VendaBalcao] StackTrace: $stackTrace');
          _adicionarSincronizacaoPendente();
          // NÃO re-throw - dados já estão salvos localmente
        }
      } else {
        debugPrint('>>> [VendaBalcao] ⚠️ NÃO ATUALIZOU NO FIREBASE!');
        if (!_firebaseHabilitado) debugPrint('>>> [VendaBalcao] Motivo: Firebase NÃO está habilitado');
        if (_empresaIdAtual == null) debugPrint('>>> [VendaBalcao] Motivo: Empresa NÃO está selecionada');
      }
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
      _marcarSujo(LocalStorageService.keyVendasBalcao);
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
      notifyListeners();
      _marcarSujo(LocalStorageService.keyVendasBalcao);
      return true;
    }
    print('!!! Venda $numero NÃO encontrada');
    return false;
  }

  // ============ CRUD Troca/Devolução ============

  Future<void> addTrocaDevolucao(TrocaDevolucao troca) async {
    _trocasDevolucoes.add(troca);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyTrocasDevolucoes);
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarTrocaDevolucao(_empresaIdAtual!, troca).catchError((e) {
        debugPrint('>>> Erro ao salvar troca/devolução no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
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

  String getProximoNumeroAgendamento() {
    // Coletar todos os números existentes de agendamentos
    final Set<int> numerosExistentes = {};

    // Buscar números nos agendamentos que começam com AGD-
    for (final agendamento in _agendamentosServico) {
      final match = RegExp(r'AGD-(\d+)').firstMatch(agendamento.numero);
      if (match != null) {
        final numero = int.tryParse(match.group(1)!) ?? 0;
        if (numero > 0) {
          numerosExistentes.add(numero);
        }
      }
    }

    int proximoNumero = 1;
    if (numerosExistentes.isNotEmpty) {
      proximoNumero = numerosExistentes.reduce((a, b) => a > b ? a : b) + 1;
    }

    while (numerosExistentes.contains(proximoNumero)) {
      proximoNumero++;
    }

    return 'AGD-${proximoNumero.toString().padLeft(4, '0')}';
  }

  // Migra agendamentos antigos que não têm número válido
  void migrarAgendamentosSemNumero() {
    bool houveMudanca = false;

    for (int i = 0; i < _agendamentosServico.length; i++) {
      final agendamento = _agendamentosServico[i];
      // Se o número está vazio ou não começa com AGD- ou é AGD-0000
      if (agendamento.numero.isEmpty || 
          !agendamento.numero.startsWith('AGD-') || 
          agendamento.numero == 'AGD-0000') {
        final novoNumero = getProximoNumeroAgendamento();
        _agendamentosServico[i] = agendamento.copyWith(numero: novoNumero);
        houveMudanca = true;
        print('>>> Migrado agendamento ${agendamento.id} para número $novoNumero');
      }
    }

    if (houveMudanca) {
      notifyListeners();
      _salvarAutomaticamente();
      print('>>> ✓ Migração de agendamentos sem número concluída');
    }
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

  /// [modoLeve]: Se true, carrega apenas o essencial (Produtos, Servicos, Agendamentos)
  Future<void> _carregarDadosDoFirebase({bool modoLeve = false}) async {
    if (_empresaIdAtual == null) {
      print('>>> ⚠ _carregarDadosDoFirebase: Empresa não definida - não é possível carregar dados do Firebase');
      return;
    }

    if (_syncEmAndamento) {
      debugPrint('>>> [Sync] ⏳ Sincronização já em andamento, aguardando...');
      return;
    }
    
    // Otimização: Só usar modo leve/silencioso se já fez a carga inicial completa pelo menos 1 vez
    final finalModoLeve = modoLeve || _isModoLeve;
    // isSilentSync: só é verdadeiro se o timer periódico está ativo E já foi feita a primeira carga completa
    final isSilentSync = _primeiraCargaAgendamentosRealizada &&
        _syncTimer != null &&
        _syncTimer!.isActive;

    debugPrint('>>> [Firebase] 🔄 Iniciando carga (Modo Leve: $finalModoLeve, SilentSync: $isSilentSync, 1aCarga=${_primeiraCargaAgendamentosRealizada})');
    _syncEmAndamento = true;
    notifyListeners();
    
    try {
      print('>>> 🔥 ========================================');
      print('>>> 🔥 Carregando dados do Firebase (Modo Leve: $finalModoLeve)');
      print('>>> 🔥 Empresa: $_empresaIdAtual');
      print('>>> 🔥 ========================================');
      
      final result = (finalModoLeve || isSilentSync)
          ? await _firebaseService.carregarDadosLevesDoFirebase(_empresaIdAtual!)
          : await _firebaseService.carregarTudoDoFirebase(
              _empresaIdAtual!,
              mesesRetroativos: 3,
            );
      
      final Map<String, dynamic> dados;
      if (result.containsKey('data') && result.containsKey('snapshots')) {
        dados = result['data'] as Map<String, dynamic>;
        
        // Capturar cursors iniciais para paginação
        final snapshots = result['snapshots'] as Map<String, QuerySnapshot>;
        if (snapshots['clientes'] != null && snapshots['clientes']!.docs.isNotEmpty) {
          _ultimoDocClientes = snapshots['clientes']!.docs.last;
          _temMaisClientes = snapshots['clientes']!.docs.length >= 100;
        }
        if (snapshots['vendas_balcao'] != null && snapshots['vendas_balcao']!.docs.isNotEmpty) {
          _ultimoDocVendas = snapshots['vendas_balcao']!.docs.last;
          _temMaisVendas = snapshots['vendas_balcao']!.docs.length >= 100;
        }
      } else {
        dados = result;
      }
      
      // Verificar se há dados no Firebase - usando um critério amplo
      final temDados = dados['clientes']?.isNotEmpty == true ||
          dados['produtos']?.isNotEmpty == true ||
          dados['pedidos']?.isNotEmpty == true ||
          dados['agendamentos_servico']?.isNotEmpty == true ||
          dados['servicos']?.isNotEmpty == true ||
          dados['ordens_servico']?.isNotEmpty == true ||
          dados['funcionarios']?.isNotEmpty == true ||
          dados['taxas_entrega']?.isNotEmpty == true;
      
      if (!temDados) {
        debugPrint('>>> ⚠ Firebase retornou vazio para empresa $_empresaIdAtual. Continuando com dados locais...');
        return; // Retorna sem erro, mas sem dados
      }

      // Carregar clientes - PROTEÇÃO: Não limpar se for sync silencioso/leve e a lista vier vazia
      if (dados['clientes'] != null) {
        final novosRaw = dados['clientes'] as List;
        if (novosRaw.isNotEmpty || !isSilentSync) {
          final novos = novosRaw.map((map) => Cliente.fromMap(map as Map<String, dynamic>)).toList();
          _atualizarListaInPlace(_clientes, novos);
          print('>>> ✓ ${novos.length} clientes carregados do Firebase');
        } else {
          debugPrint('>>> [Sync] Preservando lista de clientes local durante sync silencioso/leve');
        }
      }

      // Carregar produtos - Otimizado: Pular se em sync silencioso e stream ativo
      if (dados['produtos'] != null && (!isSilentSync || _produtosSubscription == null)) {
        final novos = (dados['produtos'] as List).map((map) => Produto.fromMap(map as Map<String, dynamic>)).toList();
        _atualizarListaInPlace(_produtos, novos);
        print('>>> ✓ ${novos.length} produtos carregados do Firebase');
      }

      // Carregar serviços - Otimizado: Pular se em sync silencioso e stream ativo
      if (dados['servicos'] != null && (!isSilentSync || _servicosSubscription == null)) {
        final novos = (dados['servicos'] as List).map((map) => Servico.fromMap(map as Map<String, dynamic>)).toList();
        _atualizarListaInPlace(_tiposServico, novos);
        print('>>> ✓ ${novos.length} serviços carregados do Firebase');
      }

      // Carregar pedidos - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['pedidos'] != null && dados['pedidos'].isNotEmpty) {
        final novosPedidos = (dados['pedidos'] as List).map((map) => Pedido.fromMap(map as Map<String, dynamic>)).toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        // ISOLAMENTO: Firebase já filtra por empresaId
        for (final pedido in novosPedidos) {
          _pedidos.removeWhere((p) => p.id == pedido.id);
          _pedidos.add(pedido);
        }
        print('>>> ✓ ${novosPedidos.length} pedidos carregados do Firebase para empresa $_empresaIdAtual (isolados)');
      }

      // Carregar ordens de serviço - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['ordens_servico'] != null && dados['ordens_servico'].isNotEmpty) {
        final novasOrdens = (dados['ordens_servico'] as List)
            .map((map) => OrdemServico.fromMap(map as Map<String, dynamic>)).toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        // ISOLAMENTO: Firebase já filtra por empresaId
        for (final ordem in novasOrdens) {
          _ordensServico.removeWhere((o) => o.id == ordem.id);
          _ordensServico.add(ordem);
        }
        print('>>> ✓ ${novasOrdens.length} ordens de serviço carregadas do Firebase para empresa $_empresaIdAtual (isoladas)');
      }

      // Carregar entregas - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['entregas'] != null && dados['entregas'].isNotEmpty) {
        final novasEntregas = (dados['entregas'] as List).map((map) => Entrega.fromMap(map as Map<String, dynamic>)).toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        // ISOLAMENTO: Firebase já filtra por empresaId
        for (final entrega in novasEntregas) {
          _entregas.removeWhere((e) => e.id == entrega.id);
          _entregas.add(entrega);
        }
        print('>>> ✓ ${novasEntregas.length} entregas carregadas do Firebase para empresa $_empresaIdAtual (isoladas)');
      }

      // Carregar motoristas - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['motoristas'] != null && dados['motoristas'].isNotEmpty) {
        final novosMotoristas = (dados['motoristas'] as List).map((map) => Motorista.fromMap(map as Map<String, dynamic>)).toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        for (final motorista in novosMotoristas) {
          final index = _motoristas.indexWhere((m) => m.id == motorista.id);
          if (index >= 0) {
            _motoristas[index] = motorista;
          } else {
            _motoristas.add(motorista);
          }
        }
        print('>>> ✓ ${novosMotoristas.length} motoristas carregados do Firebase para empresa $_empresaIdAtual (isolados)');
      }

      // Carregar vendas balcão - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['vendas_balcao'] != null && dados['vendas_balcao'].isNotEmpty) {
        final novasVendas = (dados['vendas_balcao'] as List)
            .map((map) => VendaBalcao.fromMap(map as Map<String, dynamic>)).toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        // ISOLAMENTO: Firebase já filtra por empresaId
        for (final venda in novasVendas) {
          _vendasBalcao.removeWhere((v) => v.id == venda.id);
          _vendasBalcao.add(venda);
        }
        print('>>> ✓ ${novasVendas.length} vendas balcão carregadas do Firebase para empresa $_empresaIdAtual (isoladas)');
      }

      // Carregar trocas/devoluções - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['trocas_devolucoes'] != null && dados['trocas_devolucoes'].isNotEmpty) {
        final novasTrocas = (dados['trocas_devolucoes'] as List)
            .map((map) => TrocaDevolucao.fromMap(map as Map<String, dynamic>)).toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        for (final troca in novasTrocas) {
          final index = _trocasDevolucoes.indexWhere((t) => t.id == troca.id);
          if (index >= 0) {
            _trocasDevolucoes[index] = troca;
          } else {
            _trocasDevolucoes.add(troca);
          }
        }
        print('>>> ✓ ${novasTrocas.length} trocas/devoluções carregadas do Firebase para empresa $_empresaIdAtual (isoladas)');
      }

      // Carregar histórico de estoque - NÃO LIMPAR, apenas adicionar/atualizar
      if (dados['estoque_historico'] != null && dados['estoque_historico'].isNotEmpty) {
        final novosRegistros = (dados['estoque_historico'] as List)
            .map((map) => EstoqueHistorico.fromMap(map as Map<String, dynamic>)).toList();
        // Atualizar ou adicionar registros (evitar duplicatas)
        for (final registro in novosRegistros) {
          final index = _estoqueHistorico.indexWhere((e) => e.id == registro.id);
          if (index >= 0) {
            _estoqueHistorico[index] = registro; // Atualizar existente
          } else {
            _estoqueHistorico.add(registro); // Adicionar novo
          }
        }
        print('>>> ✓ ${novosRegistros.length} registros de estoque carregados do Firebase (total: ${_estoqueHistorico.length})');
      }

      // Carregar aberturas de caixa - NÃO LIMPAR, apenas adicionar/atualizar
      if (dados['aberturas_caixa'] != null && dados['aberturas_caixa'].isNotEmpty) {
        final novasAberturas = (dados['aberturas_caixa'] as List)
            .map((map) => AberturaCaixa.fromMap(map as Map<String, dynamic>)).toList();
        // Atualizar ou adicionar aberturas (evitar duplicatas)
        for (final abertura in novasAberturas) {
          final index = _aberturasCaixa.indexWhere((a) => a.id == abertura.id);
          if (index >= 0) {
            _aberturasCaixa[index] = abertura; // Atualizar existente
          } else {
            _aberturasCaixa.add(abertura); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasAberturas.length} aberturas de caixa carregadas do Firebase (total: ${_aberturasCaixa.length})');
      }

      // Carregar fechamentos de caixa - NÃO LIMPAR, apenas adicionar/atualizar
      if (dados['fechamentos_caixa'] != null && dados['fechamentos_caixa'].isNotEmpty) {
        final novosFechamentos = (dados['fechamentos_caixa'] as List)
            .map((map) => FechamentoCaixa.fromMap(map as Map<String, dynamic>)).toList();
        // Atualizar ou adicionar fechamentos (evitar duplicatas)
        for (final fechamento in novosFechamentos) {
          final index = _fechamentosCaixa.indexWhere((f) => f.id == fechamento.id);
          if (index >= 0) {
            _fechamentosCaixa[index] = fechamento; // Atualizar existente
          } else {
            _fechamentosCaixa.add(fechamento); // Adicionar novo
          }
        }
        print('>>> ✓ ${novosFechamentos.length} fechamentos de caixa carregados do Firebase (total: ${_fechamentosCaixa.length})');
      }

      // Carregar mesas/comandas - NÃO LIMPAR, apenas adicionar/atualizar
      if (dados['mesas_comandas'] != null && dados['mesas_comandas'].isNotEmpty) {
        final novasMesas = (dados['mesas_comandas'] as List).map((map) => MesaComanda.fromMap(map as Map<String, dynamic>)).toList();
        // Atualizar ou adicionar mesas (evitar duplicatas)
        for (final mesa in novasMesas) {
          final index = _mesasComandas.indexWhere((m) => m.id == mesa.id);
          if (index >= 0) {
            _mesasComandas[index] = mesa; // Atualizar existente
          } else {
            _mesasComandas.add(mesa); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasMesas.length} mesas/comandas carregadas do Firebase (total: ${_mesasComandas.length})');
      }

      // Carregar funcionários - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['funcionarios'] != null) {
        final novosRaw = dados['funcionarios'] as List;
        if (novosRaw.isNotEmpty || !isSilentSync) {
          final novos = novosRaw.map((map) => Funcionario.fromMap(map as Map<String, dynamic>)).toList();
          _atualizarListaInPlace(_funcionarios, novos);
          print('>>> ✓ ${novos.length} funcionários carregados do Firebase para empresa $_empresaIdAtual (isolados)');
        }
      }

      // Carregar agendamentos de serviço - Otimizado: Pular se em sync silencioso e stream ativo
      final agendamentosNoFirebase = dados['agendamentos_servico'] as List?;
      if (agendamentosNoFirebase != null) {
        if (!isSilentSync || _agendamentosSubscription == null) {
          print('>>> [Agendamentos] 🔍 Encontrados ${agendamentosNoFirebase.length} agendamentos no Firebase');
          
          if (agendamentosNoFirebase.isNotEmpty) {
            print('>>> [Agendamentos] 🔄 Processando agendamentos do Firebase...');
            final novosAgendamentos = agendamentosNoFirebase.map((map) {
              try {
                final agendamento = AgendamentoServico.fromMap(map as Map<String, dynamic>);
                // print('>>> [Agendamentos] Processando: ${agendamento.numero} (ID: ${agendamento.id})');
                
                return _vincularReferenciasAgendamento(agendamento);
              } catch (e, stackTrace) {
                print('>>> ❌ ERRO ao processar agendamento do Firebase: $e');
                print('>>> StackTrace: $stackTrace');
                print('>>> Dados do agendamento: $map');
                return null;
              }
            }).where((a) => a != null).cast<AgendamentoServico>().toList();
          
            print('>>> [Agendamentos] ✅ ${novosAgendamentos.length} agendamentos processados com sucesso');
            
            // Atualizar ou adicionar agendamentos (evitar duplicatas e limpar duplicatas históricas)
            for (final agendamento in novosAgendamentos) {
              _upsertAgendamentoLocal(agendamento);
            }
            
            print('>>> [Agendamentos] ✅✅✅ CARREGAMENTO CONCLUÍDO! ✅✅✅');
            print('>>> [Agendamentos]   - Total na lista: ${_agendamentosServico.length}');
            
            // Migrar agendamentos sem número válido
            migrarAgendamentosSemNumero();
          } else {
            print('>>> [Agendamentos] ⚠️ Nenhum agendamento encontrado no Firebase para empresa $_empresaIdAtual');
          }
        } else {
          print('>>> [Agendamentos] ⏭️ Pulo do processamento: Stream já ativa em modo silencioso');
        }
      } else {
        print('>>> [Agendamentos] ⚠️ Campo agendamentos_servico AUSENTE no retorno do Firebase');
      }

      // Carregar taxas de entrega - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['taxas_entrega'] != null && dados['taxas_entrega'].isNotEmpty) {
        final novasTaxas = (dados['taxas_entrega'] as List)
            .map((map) => TaxaEntrega.fromMap(map as Map<String, dynamic>)).toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        for (final taxa in novasTaxas) {
          final index = _taxasEntrega.indexWhere((t) => t.id == taxa.id);
          if (index >= 0) {
            _taxasEntrega[index] = taxa;
          } else {
            _taxasEntrega.add(taxa);
          }
        }
        print('>>> ✓ ${novasTaxas.length} taxas de entrega carregadas do Firebase para empresa $_empresaIdAtual (isoladas)');
      } else {
        print('>>> ✓ Nenhuma taxa de entrega encontrada no Firebase para empresa $_empresaIdAtual');
      }

      // Carregar links de vendedores - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['links_vendedores'] != null && dados['links_vendedores'].isNotEmpty) {
        final novosLinks = (dados['links_vendedores'] as List)
            .map((map) => LinkVendedor.fromMap(map as Map<String, dynamic>))
            .toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        _linksVendedores.clear();
        _linksVendedores.addAll(novosLinks);
        print('>>> ✓ ${novosLinks.length} links de vendedores carregados do Firebase para empresa $_empresaIdAtual (isolados)');
      } else {
        print('>>> ✓ Nenhum link de vendedor encontrado no Firebase para empresa $_empresaIdAtual');
      }

      // Carregar comissões de vendedores - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['comissoes_vendedores'] != null && dados['comissoes_vendedores'].isNotEmpty) {
        final novasComissoes = (dados['comissoes_vendedores'] as List)
            .map((map) => ComissaoVendedor.fromMap(map as Map<String, dynamic>))
            .toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        _comissoesVendedores.clear();
        _comissoesVendedores.addAll(novasComissoes);
        print('>>> ✓ ${novasComissoes.length} comissões de vendedores carregadas do Firebase para empresa $_empresaIdAtual (isoladas)');
      } else {
        print('>>> ✓ Nenhuma comissão de vendedor encontrada no Firebase para empresa $_empresaIdAtual');
      }

      // Carregar NFC-es - ISOLAMENTO: Apenas dados da empresa atual do Firebase
      if (dados['nfces'] != null && dados['nfces'].isNotEmpty) {
        final novasNfces = (dados['nfces'] as List)
            .map((map) => NFCe.fromMap(map as Map<String, dynamic>))
            .toList();
        // ISOLAMENTO: Firebase já filtra por empresaId
        _nfces.clear();
        _nfces.addAll(novasNfces);
        print('>>> ✓ ${novasNfces.length} NFC-es carregadas do Firebase para empresa $_empresaIdAtual (isoladas)');
      } else {
        print('>>> ✓ Nenhuma NFC-e encontrada no Firebase para empresa $_empresaIdAtual');
      }

      // NOTA: Removido o salvamento forçado aqui para evitar loops de carregamento/salvamento
      // await _salvarTodosDados();
      _ultimaSincronizacaoSucesso = DateTime.now();
      _ultimoErroSync = null; // Limpar erro anterior em caso de sucesso
      debugPrint('>>> [Sync] ✅ Sincronização concluída com sucesso às ${_ultimaSincronizacaoSucesso.toString()}');
      
      // Iniciar sincronização silenciosa com Google Drive em background
      _sincronizarNotasComDrive();
      
    } catch (e, stackTrace) {
      _ultimoErroSync = e.toString();
      debugPrint('>>> [Sync] ❌ ERRO na sincronização: $e');
      debugPrint('>>> StackTrace: $stackTrace');
      rethrow;
    } finally {
      _syncEmAndamento = false;
      notifyListeners();
    }
  }


  Future<void> _carregarDadosSalvos() async {
    // GARANTIR que só carrega se houver empresa definida
    if (_empresaIdAtual == null) {
      print('>>> ⚠ _carregarDadosSalvos: Empresa não definida - não é possível carregar dados');
      return;
    }
    
    try {
      print('>>> Carregando dados salvos do localStorage para empresa: $_empresaIdAtual...');

      // Carregar clientes - ISOLAMENTO: Apenas dados da empresa atual
      final clientesMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyClientes));
      if (clientesMap.isNotEmpty) {
        final novosClientes = clientesMap.map((map) => Cliente.fromMap(map)).toList();
        // ISOLAMENTO: Garantir que todos os clientes pertencem à empresa atual
        final clientesFiltrados = novosClientes.where((c) {
          // Se o cliente tem empresaId, verificar se é da empresa atual
          // Se não tem, assumir que é da empresa atual (dados antigos)
          return true; // Já está isolado pela chave do localStorage
        }).toList();
        
        // Adicionar ou atualizar (evitar duplicatas)
        for (final cliente in clientesFiltrados) {
          final index = _clientes.indexWhere((c) => c.id == cliente.id);
          if (index >= 0) {
            _clientes[index] = cliente;
          } else {
            _clientes.add(cliente);
          }
        }
        print('>>> ✓ ${clientesFiltrados.length} clientes carregados da empresa $_empresaIdAtual (isolados)');
        _reVincularTodosAgendamentos(); // Re-vincular para que agendamentos achem seus clientes
      } else {
        print('>>> ✓ Nenhum cliente encontrado para empresa $_empresaIdAtual');
      }

      // Carregar produtos - ISOLAMENTO: Apenas dados da empresa atual
      final produtosMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyProdutos));
      if (produtosMap.isNotEmpty) {
        final novosProdutos = produtosMap.map((map) {
          // DEBUG: Verificar exibirNaLoja antes de converter
          if (map['nome'] != null && (map['nome'] as String).toLowerCase().contains('fanta')) {
            debugPrint('>>> [Carregamento] DEBUG FANTA no storage:');
            debugPrint('>>> [Carregamento]    nome: ${map['nome']}');
            debugPrint('>>> [Carregamento]    exibirNaLoja no map: ${map['exibirNaLoja']}');
            debugPrint('>>> [Carregamento]    tipo: ${map['exibirNaLoja'].runtimeType}');
          }
          final produto = Produto.fromMap(map);
          // DEBUG: Verificar após conversão
          if (produto.nome.toLowerCase().contains('fanta')) {
            debugPrint('>>> [Carregamento] DEBUG FANTA após fromMap:');
            debugPrint('>>> [Carregamento]    nome: ${produto.nome}');
            debugPrint('>>> [Carregamento]    exibirNaLoja: ${produto.exibirNaLoja}');
          }
          return produto;
        }).toList();
        // ISOLAMENTO: Garantir que todos os produtos pertencem à empresa atual
        // Já está isolado pela chave do localStorage (_getChaveComEmpresa)
        
        // Adicionar ou atualizar (evitar duplicatas)
        for (final produto in novosProdutos) {
          final index = _produtos.indexWhere((p) => p.id == produto.id);
          if (index >= 0) {
            _produtos[index] = produto;
          } else {
            _produtos.add(produto);
          }
        }
        print('>>> ✓ ${novosProdutos.length} produtos carregados da empresa $_empresaIdAtual (isolados)');
        
        // DEBUG: Contar produtos com exibirNaLoja = true
        final produtosComExibirNaLoja = novosProdutos.where((p) => p.exibirNaLoja).length;
        debugPrint('>>> [Carregamento] Produtos com exibirNaLoja=true: $produtosComExibirNaLoja de ${novosProdutos.length}');
        
        // DEBUG: Listar TODOS os produtos carregados com seus valores
        debugPrint('>>> [Carregamento] ========================================');
        debugPrint('>>> [Carregamento] LISTA COMPLETA DE PRODUTOS CARREGADOS:');
        for (var p in novosProdutos) {
          debugPrint('>>> [Carregamento]   "${p.nome}": exibirNaLoja=${p.exibirNaLoja}, estoque=${p.estoque}, estoqueTotal=${p.estoqueTotal}');
        }
        debugPrint('>>> [Carregamento] ========================================');
      } else {
        print('>>> ✓ Nenhum produto encontrado para empresa $_empresaIdAtual');
      }

      // Carregar serviços
      final servicosMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyServicos));
      if (servicosMap.isNotEmpty) {
        final novos = servicosMap.map((map) => Servico.fromMap(map)).toList();
        _atualizarListaInPlace(_tiposServico, novos);
        print('>>> ✓ ${novos.length} serviços carregados do localStorage');
      }

      // Carregar NFC-es
      final nfcesMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyNFCes));
      if (nfcesMap.isNotEmpty) {
        final novos = nfcesMap.map((map) => NFCe.fromMap(map)).toList();
        _atualizarListaInPlace(_nfces, novos);
        print('>>> ✓ ${novos.length} NFC-es carregadas do localStorage');
      }

      print('>>> SUCESSO: Todos os dados da empresa $_empresaIdAtual carregados do localStorage');

      // Carregar pedidos - NÃO LIMPAR, apenas adicionar/atualizar
      final pedidosMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyPedidos));
      if (pedidosMap.isNotEmpty) {
        final novosPedidos = pedidosMap.map((map) => Pedido.fromMap(map)).toList();
        // Atualizar ou adicionar pedidos (evitar duplicatas)
        for (final pedido in novosPedidos) {
          final index = _pedidos.indexWhere((p) => p.id == pedido.id);
          if (index >= 0) {
            _pedidos[index] = pedido; // Atualizar existente
          } else {
            _pedidos.add(pedido); // Adicionar novo
          }
        }
        print('>>> ✓ ${novosPedidos.length} pedidos carregados (total: ${_pedidos.length})');
      }

      // Carregar ordens de serviço - NÃO LIMPAR, apenas adicionar/atualizar
      final ordensMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyOrdensServico));
      if (ordensMap.isNotEmpty) {
        final novasOrdens = ordensMap.map((map) => OrdemServico.fromMap(map)).toList();
        // Atualizar ou adicionar ordens (evitar duplicatas)
        for (final ordem in novasOrdens) {
          final index = _ordensServico.indexWhere((o) => o.id == ordem.id);
          if (index >= 0) {
            _ordensServico[index] = ordem; // Atualizar existente
          } else {
            _ordensServico.add(ordem); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasOrdens.length} ordens de serviço carregadas (total: ${_ordensServico.length})');
      }

      // Carregar entregas - NÃO LIMPAR, apenas adicionar/atualizar
      final entregasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyEntregas));
      if (entregasMap.isNotEmpty) {
        final novasEntregas = entregasMap.map((map) => Entrega.fromMap(map)).toList();
        // Atualizar ou adicionar entregas (evitar duplicatas)
        for (final entrega in novasEntregas) {
          final index = _entregas.indexWhere((e) => e.id == entrega.id);
          if (index >= 0) {
            _entregas[index] = entrega; // Atualizar existente
          } else {
            _entregas.add(entrega); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasEntregas.length} entregas carregadas (total: ${_entregas.length})');
      }

      // Carregar motoristas - NÃO LIMPAR, apenas adicionar/atualizar
      final motoristasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyMotoristas));
      if (motoristasMap.isNotEmpty) {
        final novosMotoristas = motoristasMap.map((map) => Motorista.fromMap(map)).toList();
        // Atualizar ou adicionar motoristas (evitar duplicatas)
        for (final motorista in novosMotoristas) {
          final index = _motoristas.indexWhere((m) => m.id == motorista.id);
          if (index >= 0) {
            _motoristas[index] = motorista; // Atualizar existente
          } else {
            _motoristas.add(motorista); // Adicionar novo
          }
        }
        print('>>> ✓ ${novosMotoristas.length} motoristas carregados (total: ${_motoristas.length})');
      }

      // Carregar vendas balcão - NÃO LIMPAR, apenas adicionar/atualizar
      final vendasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyVendasBalcao));
      if (vendasMap.isNotEmpty) {
        final novasVendas = vendasMap.map((map) => VendaBalcao.fromMap(map)).toList();
        // Atualizar ou adicionar vendas (evitar duplicatas)
        for (final venda in novasVendas) {
          final index = _vendasBalcao.indexWhere((v) => v.id == venda.id);
          if (index >= 0) {
            _vendasBalcao[index] = venda; // Atualizar existente
          } else {
            _vendasBalcao.add(venda); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasVendas.length} vendas balcão carregadas (total: ${_vendasBalcao.length})');
      }

      // Carregar trocas/devoluções - NÃO LIMPAR, apenas adicionar/atualizar
      final trocasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyTrocasDevolucoes));
      if (trocasMap.isNotEmpty) {
        final novasTrocas = trocasMap.map((map) => TrocaDevolucao.fromMap(map)).toList();
        // Atualizar ou adicionar trocas (evitar duplicatas)
        for (final troca in novasTrocas) {
          final index = _trocasDevolucoes.indexWhere((t) => t.id == troca.id);
          if (index >= 0) {
            _trocasDevolucoes[index] = troca; // Atualizar existente
          } else {
            _trocasDevolucoes.add(troca); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasTrocas.length} trocas/devoluções carregadas (total: ${_trocasDevolucoes.length})');
      }

      // Carregar histórico de estoque (se tiver método fromMap implementado)
      // final estoqueMap = await _storage.carregarLista(LocalStorageService.keyEstoqueHistorico);
      // if (estoqueMap.isNotEmpty && EstoqueHistorico tem método fromMap) {
      //   _estoqueHistorico.clear();
      //   _estoqueHistorico.addAll(estoqueMap.map((map) => EstoqueHistorico.fromMap(map)));
      //   print('>>> ✓ ${_estoqueHistorico.length} registros de histórico de estoque carregados');
      // }

      // Carregar aberturas de caixa - NÃO LIMPAR, apenas adicionar/atualizar
      final aberturasMap =
          await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyAberturasCaixa));
      if (aberturasMap.isNotEmpty) {
        final novasAberturas = aberturasMap.map((map) => AberturaCaixa.fromMap(map)).toList();
        // Atualizar ou adicionar aberturas (evitar duplicatas)
        for (final abertura in novasAberturas) {
          final index = _aberturasCaixa.indexWhere((a) => a.id == abertura.id);
          if (index >= 0) {
            _aberturasCaixa[index] = abertura; // Atualizar existente
          } else {
            _aberturasCaixa.add(abertura); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasAberturas.length} aberturas de caixa carregadas (total: ${_aberturasCaixa.length})');
      }

      // Carregar fechamentos de caixa - NÃO LIMPAR, apenas adicionar/atualizar
      final fechamentosMap =
          await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyFechamentosCaixa));
      if (fechamentosMap.isNotEmpty) {
        final novosFechamentos = fechamentosMap.map((map) => FechamentoCaixa.fromMap(map)).toList();
        // Atualizar ou adicionar fechamentos (evitar duplicatas)
        for (final fechamento in novosFechamentos) {
          final index = _fechamentosCaixa.indexWhere((f) => f.id == fechamento.id);
          if (index >= 0) {
            _fechamentosCaixa[index] = fechamento; // Atualizar existente
          } else {
            _fechamentosCaixa.add(fechamento); // Adicionar novo
          }
        }
        print('>>> ✓ ${novosFechamentos.length} fechamentos de caixa carregados (total: ${_fechamentosCaixa.length})');
      }

      // Carregar sangrias - NÃO LIMPAR, apenas adicionar/atualizar
      final sangriasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keySangrias));
      if (sangriasMap.isNotEmpty) {
        final novasSangrias = sangriasMap.map((map) => SangriaCaixa.fromMap(map)).toList();
        for (final sangria in novasSangrias) {
          final index = _sangrias.indexWhere((s) => s.id == sangria.id);
          if (index >= 0) {
            _sangrias[index] = sangria;
          } else {
            _sangrias.add(sangria);
          }
        }
        print('>>> ✓ ${novasSangrias.length} sangrias carregadas (total: ${_sangrias.length})');
      }

      // Carregar suprimentos - NÃO LIMPAR, apenas adicionar/atualizar
      final suprimentosMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keySuprimentos));
      if (suprimentosMap.isNotEmpty) {
        final novosSuprimentos = suprimentosMap.map((map) => SuprimentoCaixa.fromMap(map)).toList();
        for (final suprimento in novosSuprimentos) {
          final index = _suprimentos.indexWhere((s) => s.id == suprimento.id);
          if (index >= 0) {
            _suprimentos[index] = suprimento;
          } else {
            _suprimentos.add(suprimento);
          }
        }
        print('>>> ✓ ${novosSuprimentos.length} suprimentos carregadas (total: ${_suprimentos.length})');
      }

      // Carregar mesas/comandas - NÃO LIMPAR, apenas adicionar/atualizar
      final mesasComandasMap =
          await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyMesasComandas));
      if (mesasComandasMap.isNotEmpty) {
        final novasMesas = mesasComandasMap.map((map) => MesaComanda.fromMap(map)).toList();
        // Atualizar ou adicionar mesas (evitar duplicatas)
        for (final mesa in novasMesas) {
          final index = _mesasComandas.indexWhere((m) => m.id == mesa.id);
          if (index >= 0) {
            _mesasComandas[index] = mesa; // Atualizar existente
          } else {
            _mesasComandas.add(mesa); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasMesas.length} mesas/comandas carregadas (total: ${_mesasComandas.length})');
      }

      // Carregar notas de entrada - NÃO LIMPAR, apenas adicionar/atualizar
      final notasMap =
          await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyNotasEntrada));
      if (notasMap.isNotEmpty) {
        final novasNotas = notasMap.map((map) => NotaEntrada.fromMap(map)).toList();
        // Atualizar ou adicionar notas (evitar duplicatas)
        for (final nota in novasNotas) {
          final index = _notasEntrada.indexWhere((n) => n.id == nota.id);
          if (index >= 0) {
            _notasEntrada[index] = nota; // Atualizar existente
          } else {
            _notasEntrada.add(nota); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasNotas.length} notas de entrada carregadas (total: ${_notasEntrada.length})');
      }

      // Carregar agendamentos de serviço - NÃO LIMPAR, apenas adicionar/atualizar
      final agendamentosMap =
          await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyAgendamentosServico));
      if (agendamentosMap.isNotEmpty) {
        final novosAgendamentos = agendamentosMap.map((map) {
            final agendamento = AgendamentoServico.fromMap(map);
            // Carregar referências de serviço, cliente e pet
            // Para vacinas, não há serviço cadastrado (servicoId começa com "vacina_")
            Servico? servico;
            if (agendamento.servicoId != null && !agendamento.servicoId!.startsWith('vacina_')) {
              try {
                servico = _tiposServico.firstWhere(
                  (s) => s.id == agendamento.servicoId,
                );
              } catch (e) {
                print('>>> ⚠ Serviço ${agendamento.servicoId ?? "null"} não encontrado ao carregar agendamento ${agendamento.id}');
                servico = null;
              }
            } else {
              // É uma vacina, não precisa de serviço cadastrado
              servico = null;
            }
            Cliente? cliente;
            if (agendamento.clienteId != null) {
              try {
                cliente = _clientes.firstWhere(
                  (c) => c.id == agendamento.clienteId,
                );
                // Debug: verificar se cliente tem observações
                if (cliente.observacoes != null && cliente.observacoes!.isNotEmpty) {
                  print('>>> ✓ Cliente ${cliente.nome} carregado com observações: "${cliente.observacoes}"');
                }
                if (cliente.dadosExtras != null && cliente.dadosExtras!.isNotEmpty) {
                  print('>>> ✓ Cliente ${cliente.nome} carregado com dados extras: ${cliente.dadosExtras}');
                }
              } catch (e) {
                print('>>> ⚠ Cliente ${agendamento.clienteId} não encontrado para agendamento ${agendamento.id}');
                cliente = null;
              }
            }
            
            // Carregar pet se houver
            Pet? pet;
            if (agendamento.petId != null && cliente != null) {
              try {
                pet = cliente.pets.firstWhere(
                  (p) => p.id == agendamento.petId,
                );
              } catch (e) {
                print('>>> ⚠ Pet ${agendamento.petId} não encontrado para agendamento ${agendamento.id}');
                pet = null;
              }
            }
            
            return agendamento.copyWith(servico: servico, cliente: cliente, pet: pet);
          }).toList();
        
        // Atualizar ou adicionar agendamentos (evitar duplicatas e limpar duplicatas históricas)
        for (final agendamento in novosAgendamentos) {
          _agendamentosServico.removeWhere((a) => a.id == agendamento.id);
          _agendamentosServico.add(agendamento);
        }
        
        print('>>> ✓ ${novosAgendamentos.length} agendamentos carregados (total: ${_agendamentosServico.length})');
        
        // Migrar agendamentos sem número válido
        migrarAgendamentosSemNumero();
      }

      // Carregar funcionários - NÃO LIMPAR, apenas adicionar/atualizar
      final funcionariosMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyFuncionarios));
      if (funcionariosMap.isNotEmpty) {
        final novosFuncionarios = funcionariosMap.map((map) => Funcionario.fromMap(map)).toList();
        // Atualizar ou adicionar funcionários (evitar duplicatas)
        for (final funcionario in novosFuncionarios) {
          final index = _funcionarios.indexWhere((f) => f.id == funcionario.id);
          if (index >= 0) {
            _funcionarios[index] = funcionario; // Atualizar existente
          } else {
            _funcionarios.add(funcionario); // Adicionar novo
          }
        }
        print('>>> ✓ ${novosFuncionarios.length} funcionários carregados (total: ${_funcionarios.length})');
      }

      // Carregar links de vendedores
      final linksMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyLinksVendedores));
      if (linksMap.isNotEmpty) {
        final novosLinks = linksMap.map((map) => LinkVendedor.fromMap(map)).toList();
        _linksVendedores.clear();
        _linksVendedores.addAll(novosLinks);
        print('>>> ✓ ${novosLinks.length} links de vendedores carregados');
      }

      // Carregar comissões de vendedores
      final comissoesMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyComissoesVendedores));
      if (comissoesMap.isNotEmpty) {
        final novasComissoes = comissoesMap.map((map) => ComissaoVendedor.fromMap(map)).toList();
        _comissoesVendedores.clear();
        _comissoesVendedores.addAll(novasComissoes);
        print('>>> ✓ ${novasComissoes.length} comissões de vendedores carregadas');
      }

      // Carregar taxas de entrega - NÃO LIMPAR, apenas adicionar/atualizar
      final taxasMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyTaxasEntrega));
      if (taxasMap.isNotEmpty) {
        final novasTaxas = taxasMap.map((map) => TaxaEntrega.fromMap(map)).toList();
        // Atualizar ou adicionar taxas (evitar duplicatas)
        for (final taxa in novasTaxas) {
          final index = _taxasEntrega.indexWhere((t) => t.id == taxa.id);
          if (index >= 0) {
            _taxasEntrega[index] = taxa; // Atualizar existente
          } else {
            _taxasEntrega.add(taxa); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasTaxas.length} taxas de entrega carregadas (total: ${_taxasEntrega.length})');
      }

      // Carregar contas a pagar - NÃO LIMPAR, apenas adicionar/atualizar
      final contasPagarMap = await _storage.carregarLista(_getChaveComEmpresa(LocalStorageService.keyContasPagar));
      if (contasPagarMap.isNotEmpty) {
        final novasContas = contasPagarMap.map((map) => ContaPagar.fromMap(map)).toList();
        // Atualizar ou adicionar contas (evitar duplicatas)
        for (final conta in novasContas) {
          final index = _contasPagar.indexWhere((c) => c.id == conta.id);
          if (index >= 0) {
            _contasPagar[index] = conta; // Atualizar existente
          } else {
            _contasPagar.add(conta); // Adicionar nova
          }
        }
        print('>>> ✓ ${novasContas.length} contas a pagar carregadas (total: ${_contasPagar.length})');
      }

      // NFC-es já foram carregadas no início do método _carregarDadosSalvos

      print('>>> ✓ Todos os dados salvos foram carregados');
    } catch (e) {
      print('>>> ✗ Erro ao carregar dados salvos: $e');
    }
  }

  /// Método auxiliar para atualizar listas in-place, garantindo unicidade por ID
  /// Processa uma lista para manter apenas os itens mais recentes na memória
  void _manterApenasRecentes(List lista, int limite, String nome) {
    if (lista.length > limite) {
      debugPrint('>>> [Memória] 🧹 Limpando $nome antigos (mantendo últimos $limite de ${lista.length})');
      // Tente ordenar se os modelos tiverem updatedAt
      try {
        // Ignora erros de cast se a lista for heterogênea ou sem o campo
        lista.sort((a, b) {
          try {
            return (b as dynamic).updatedAt.compareTo((a as dynamic).updatedAt);
          } catch (_) {
            return 0;
          }
        });
      } catch (_) {}
      
      lista.removeRange(limite, lista.length);
    }
  }

  static void _atualizarListaInPlace<T>(List<T> listaAtual, List<T> novosItens) {
    if (novosItens.isEmpty) {
      listaAtual.clear();
      return;
    }

    // BARREIRA DE SEGURANÇA: Limite de 5.000 itens para proteger RAM
    final List<T> itensSeguros = novosItens.length > 5000 
        ? novosItens.take(5000).toList() 
        : novosItens;

    if (novosItens.length > 5000) {
      debugPrint('>>> [Memória] 🛡️ Alerta: Lista com ${novosItens.length} itens reduzida para 5.000 para estabilidade.');
    }

    listaAtual.clear();
    listaAtual.addAll(itensSeguros);
  }

  /// Salva todos os dados no localStorage e Firebase
  /// [aguardarFirebase] - se true, aguarda o Firebase salvar (para operações críticas)
  Future<void> _salvarTodosDados({bool aguardarFirebase = false}) async {
    if (!_persistenciaHabilitada) return;

    try {
      // OTIMIZAÇÃO CRÍTICA: Se a memória estiver pesada, limitar histórico
      _manterApenasRecentes(_estoqueHistorico, 300, 'Estoque');
      _manterApenasRecentes(_vendasBalcao, 400, 'Vendas');
      _manterApenasRecentes(_ordensServico, 400, 'Ordens de Serviço');
      _manterApenasRecentes(_pedidos, 400, 'Pedidos');
      _manterApenasRecentes(_notasEntrada, 100, 'Notas de Entrada');
      _manterApenasRecentes(_trocasDevolucoes, 200, 'Trocas');
      _manterApenasRecentes(_agendamentosServico, 800, 'Agendamentos');
      _manterApenasRecentes(_nfces, 200, 'NFC-es');
      _manterApenasRecentes(_sangrias, 100, 'Sangrias');
      _manterApenasRecentes(_suprimentos, 100, 'Suprimentos');

      // Salvar no localStorage SEQUENCIALMENTE (evita picos de RAM no jsonEncode)
      try {
        final chaves = [
          LocalStorageService.keyClientes,
          LocalStorageService.keyProdutos,
          LocalStorageService.keyServicos,
          LocalStorageService.keyVendasBalcao,
          LocalStorageService.keyPedidos,
          LocalStorageService.keyOrdensServico,
          LocalStorageService.keyEntregas,
          LocalStorageService.keyMotoristas,
          LocalStorageService.keyTrocasDevolucoes,
          LocalStorageService.keyEstoqueHistorico,
          LocalStorageService.keyAberturasCaixa,
          LocalStorageService.keyFechamentosCaixa,
          LocalStorageService.keyNotasEntrada,
          LocalStorageService.keyAgendamentosServico,
          LocalStorageService.keyFuncionarios,
          LocalStorageService.keyTaxasEntrega,
          LocalStorageService.keyContasPagar,
          LocalStorageService.keyNFCes,
          LocalStorageService.keyMesasComandas,
          LocalStorageService.keyLinksVendedores,
          LocalStorageService.keyComissoesVendedores,
          LocalStorageService.keySangrias,
          LocalStorageService.keySuprimentos,
        ];

        final listas = [
          _clientes, _produtos, _tiposServico, _vendasBalcao, _pedidos,
          _ordensServico, _entregas, _motoristas, _trocasDevolucoes,
          _estoqueHistorico, _aberturasCaixa, _fechamentosCaixa, _notasEntrada,
          _agendamentosServico, _funcionarios, _taxasEntrega, _contasPagar,
          _nfces, _mesasComandas, _linksVendedores, _comissoesVendedores,
          _sangrias, _suprimentos,
        ];

        for (int i = 0; i < chaves.length; i++) {
          final chaveBase = chaves[i];
          // Só salvar se estiver na lista de sujos OU se for a primeira vez (dirty empty e force save implícito)
          if (_dirtyCollections.contains(chaveBase) || _dirtyCollections.isEmpty) {
            await _storage.salvarLista(_getChaveComEmpresa(chaveBase), listas[i]);
            _dirtyCollections.remove(chaveBase); // Limpa flag após salvar
            debugPrint('>>> [Storage] 💾 Salvo seletivo: $chaveBase');
          }
          
          // Yield para o Event Loop respirar entre operações de JSON pesado
          if (i % 3 == 0) await Future.delayed(const Duration(milliseconds: 100));
        }
        
      } catch (e) {
        debugPrint('>>> [Memória] ❌ Erro no salvamento seletivo: $e');
      }
      
      print('>>> ✓ Dados modificados foram salvos no localStorage');
      
      // PROTEÇÃO: Removido re-read para validar (economiza 50% de CPU/RAM no salvamento)

      // Sincronizar com Firebase apenas se:
      // 1. Firebase está habilitado
      // 2. Tem empresa selecionada
      // 3. Passou o intervalo de 30 minutos (ou é operação crítica)
      final agora = DateTime.now();
      final deveSincronizar = aguardarFirebase || 
        _ultimaSincronizacao == null || 
        agora.difference(_ultimaSincronizacao!) > _intervaloSincronizacao;

      if (_firebaseHabilitado && _empresaIdAtual != null && deveSincronizar) {
        if (aguardarFirebase) {
          // Para operações críticas (como fechar caixa), aguarda o Firebase
          try {
            await _sincronizarComFirebase();
            _ultimaSincronizacao = agora;
            print('>>> ✓ Todos os dados foram sincronizados com Firebase (aguardado)');
          } catch (e) {
            print('>>> ✗ Erro ao sincronizar com Firebase: $e');
            // Verificar se é erro de conexão
            final errorStr = e.toString().toLowerCase();
            final isConnectionError = errorStr.contains('network') ||
                errorStr.contains('connection') ||
                errorStr.contains('timeout') ||
                errorStr.contains('socket') ||
                errorStr.contains('internet');
            
            if (isConnectionError) {
              _syncQueue.onConnectionLost();
            }
            
            // Adicionar à fila de sincronização para tentar depois
            _adicionarSincronizacaoPendente();
          }
        } else {
          // Para operações normais, executa em background para não bloquear a UI
          _sincronizarComFirebase().then((_) {
            _ultimaSincronizacao = agora;
            print('>>> ✓ Todos os dados foram sincronizados com Firebase (background)');
          }).catchError((e) {
            print('>>> ✗ Erro ao sincronizar com Firebase: $e');
            // Adicionar à fila de sincronização para tentar depois
            _adicionarSincronizacaoPendente();
          });
        }
      } else if (!deveSincronizar) {
        debugPrint('>>> [Sync] Pulando sincronização (última foi há ${agora.difference(_ultimaSincronizacao!).inMinutes} minutos)');
      }
    } catch (e) {
      print('>>> ✗ Erro ao salvar dados: $e');
    }
  }

  /// Sincroniza todos os dados com Firebase
  /// Executa de forma assíncrona com timeout para evitar travamentos
  Future<void> _sincronizarComFirebase() async {
    if (_empresaIdAtual == null) {
      debugPrint('>>> [Sync] ⚠️ Empresa não selecionada, pulando sincronização');
      return;
    }
    
    // Verificação de cota antes de tentar
    if (!_firebaseHabilitado) {
      debugPrint('>>> [Sync] ⚠️ Firebase desabilitado (provável cota excedida), pulando...');
      return;
    }
    
    try {
      // Timeout de 60 segundos para evitar travamentos
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
        agendamentosServico: _agendamentosServico,
        notasEntrada: _notasEntrada,
        funcionarios: _funcionarios,
        taxasEntrega: _taxasEntrega,
        contasPagar: _contasPagar,
        nfces: _nfces,
        sangrias: _sangrias,
        suprimentos: _suprimentos,
        linksVendedores: _linksVendedores,
        comissoesVendedores: _comissoesVendedores,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          debugPrint('>>> [Sync] ⚠️ Timeout ao sincronizar com Firebase (60s)');
          throw TimeoutException('Timeout na sincronização com Firebase');
        },
      );
      
      debugPrint('>>> [Sync] ✅ Sincronização com Firebase concluída com sucesso');
    } catch (e, stackTrace) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('quota') || errorStr.contains('resource-exhausted')) {
        debugPrint('>>> [Sync] ⚠️⚠️⚠️ COTA EXCEDIDA NO FIREBASE! DESABILITANDO SYNC AUTOMÁTICO ⚠️⚠️⚠️');
        _firebaseHabilitado = false;
      }
      debugPrint('>>> [Sync] ❌ Erro ao sincronizar com Firebase: $e');
      debugPrint('>>> [Sync] StackTrace: $stackTrace');
      rethrow; 
    }
  }

  /// Sincronização forçada iniciada pelo usuário
  Future<void> sincronizarManualmente() async {
    _isLoading = true;
    _mensagemLoading = 'Sincronizando com nuvem...';
    notifyListeners();
    
    try {
      _firebaseHabilitado = true; // Tenta reabilitar caso tenha caído por cota
      await _sincronizarComFirebase();
      _ultimaSincronizacao = DateTime.now();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adiciona sincronização pendente à fila
  void _adicionarSincronizacaoPendente() {
    if (_empresaIdAtual == null) {
      debugPrint('>>> [Sync] ⚠️ Não é possível adicionar à fila: empresa não selecionada');
      return;
    }
    
    debugPrint('>>> [Sync] 📋 Adicionando sincronização à fila (empresa: $_empresaIdAtual)');
    _syncQueue.enqueue(SyncOperation(
      type: 'sync_all',
      dataId: _empresaIdAtual!,
      execute: _sincronizarComFirebase,
    ));
    
    // Tentar sincronizar imediatamente se tiver conexão
    if (FirebaseService.isAvailable) {
      _syncQueue.forceSync().catchError((e) {
        debugPrint('>>> [Sync] ⚠️ Erro ao forçar sincronização: $e');
      });
    }
  }
  
  /// Retorna informações sobre sincronização pendente
  Map<String, dynamic> getInfoSincronizacao() {
    return _syncQueue.getQueueInfo();
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
    _marcarSujo(LocalStorageService.keyNFCes);
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarNFCe(_empresaIdAtual!, nfce).catchError((e) {
        debugPrint('>>> Erro ao salvar NFC-e no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
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
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarNFCe(_empresaIdAtual!, nfce).catchError((e) {
        debugPrint('>>> Erro ao atualizar NFC-e no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
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

  /// Força sincronização imediata (útil quando internet volta)
  Future<void> forcarSincronizacao() async {
    if (_empresaIdAtual == null) return;
    
    _ultimaSincronizacao = null; // Resetar para forçar sincronização
    await _salvarTodosDados(aguardarFirebase: false);
    
    // Processar fila de sincronização pendente
    _syncQueue.onConnectionRestored();
  }

  /// Deleta todos os dados operacionais da empresa atual (produtos, pedidos, vendas, serviços)
  /// IMPORTANTE: Esta função NÃO deleta a empresa, apenas os dados operacionais
  /// PROTEÇÃO: Cria backup automático antes de deletar
  Future<void> deletarTodosDadosOperacionais({required bool confirmar}) async {
    if (!confirmar) {
      throw Exception('⚠️ PROTEÇÃO: deletarTodosDadosOperacionais requer confirmação explícita (confirmar: true)');
    }
    
    if (_empresaIdAtual == null) {
      throw Exception('⚠️ Nenhuma empresa selecionada');
    }

    final empresaId = _empresaIdAtual!;
    
    try {
      print('>>> 🗑️ Deletando dados operacionais da empresa: $empresaId');
      
      // Contar itens antes de deletar (para log)
      final totalProdutos = _produtos.length;
      final totalPedidos = _pedidos.length;
      final totalVendas = _vendasBalcao.length;
      final totalServicos = _tiposServico.length;
      final totalAgendamentos = _agendamentosServico.length;
      final totalOrdens = _ordensServico.length;
      final totalEntregas = _entregas.length;
      final totalClientes = _clientes.length;
      
      // PROTEÇÃO: Backup automático antes de deletar
      print('>>> 🛡️ PROTEÇÃO: Criando backup completo antes de deletar dados...');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      try {
        // Backup de todos os dados críticos
        await _storage.salvarLista('backup_produtos_${empresaId}_$timestamp', _produtos.map((p) => p.toMap()).toList());
        await _storage.salvarLista('backup_pedidos_${empresaId}_$timestamp', _pedidos.map((p) => p.toMap()).toList());
        await _storage.salvarLista('backup_vendas_${empresaId}_$timestamp', _vendasBalcao.map((v) => v.toMap()).toList());
        await _storage.salvarLista('backup_servicos_${empresaId}_$timestamp', _tiposServico.map((s) => s.toMap()).toList());
        await _storage.salvarLista('backup_ordens_${empresaId}_$timestamp', _ordensServico.map((o) => o.toMap()).toList());
        await _storage.salvarLista('backup_entregas_${empresaId}_$timestamp', _entregas.map((e) => e.toMap()).toList());
        await _storage.salvarLista('backup_agendamentos_${empresaId}_$timestamp', _agendamentosServico.map((a) => a.toMap()).toList());
        await _storage.salvarLista('backup_contas_pagar_${empresaId}_$timestamp', _contasPagar.map((c) => c.toMap()).toList());
        await _storage.salvarLista('backup_notas_entrada_${empresaId}_$timestamp', _notasEntrada.map((n) => n.toMap()).toList());
        await _storage.salvarLista('backup_clientes_${empresaId}_$timestamp', _clientes.map((c) => c.toMap()).toList());
        
        print('>>> ✅ Backup completo criado com timestamp: $timestamp');
        print('>>> ✅ Chaves de backup: backup_*_${empresaId}_$timestamp');
      } catch (e) {
        print('>>> ❌ ERRO CRÍTICO: Não foi possível criar backup! Operação cancelada.');
        print('>>> Erro: $e');
        throw Exception('⚠️ PROTEÇÃO: Não foi possível criar backup. Operação cancelada para evitar perda de dados.');
      }
      
      // Log de auditoria
      print('>>> 📋 AUDITORIA: Deletando dados operacionais da empresa $empresaId');
      print('>>> 📋 AUDITORIA: Timestamp: ${DateTime.now()}');
      print('>>> 📋 AUDITORIA: Itens a deletar:');
      print('    - $totalProdutos produto(s)');
      print('    - $totalPedidos pedido(s)');
      print('    - $totalVendas venda(s)');
      print('    - $totalServicos serviço(s)');
      print('    - $totalOrdens ordem(ns) de serviço');
      print('    - $totalEntregas entrega(s)');
      print('    - $totalAgendamentos agendamento(s)');
      print('    - $totalClientes cliente(s)');
      
      // Limpar TODAS as listas locais (apenas dados operacionais, NÃO empresas)
      _produtos.clear();
      _pedidos.clear();
      _vendasBalcao.clear();
      _tiposServico.clear();
      _clientes.clear();
      _ordensServico.clear();
      _entregas.clear();
      _trocasDevolucoes.clear();
      _estoqueHistorico.clear();
      _aberturasCaixa.clear();
      _fechamentosCaixa.clear();
      _sangrias.clear();
      _suprimentos.clear();
      _notasEntrada.clear();
      _agendamentosServico.clear();
      _contasPagar.clear();
      _nfces.clear();
      _mesasComandas.clear();
      _funcionarios.clear();
      _taxasEntrega.clear();
      _motoristas.clear();
      
      // Limpar estado do caixa
      _caixaAberto = false;
      
      // Salvar listas vazias no localStorage
      await _salvarTodosDados(aguardarFirebase: true);
      
      // Deletar do Firebase (apenas dados operacionais da empresa específica)
      if (_firebaseHabilitado) {
        try {
          await _firebaseService.deletarTodosProdutos(empresaId);
          await _firebaseService.deletarTodosPedidos(empresaId);
          await _firebaseService.deletarTodasVendasBalcao(empresaId);
          await _firebaseService.deletarTodosServicos(empresaId);
          await _firebaseService.deletarTodosClientes(empresaId); // ADICIONADO: Deletar clientes também
          await _firebaseService.deletarTodosAgendamentosServico(empresaId); // ADICIONADO: Deletar agendamentos também
          print('>>> ✓ Dados deletados do Firebase');
        } catch (e) {
          print('>>> ⚠️ Erro ao deletar do Firebase: $e');
          print('>>> ⚠️ PROTEÇÃO: Dados locais já foram limpos. Backup disponível.');
        }
      }
      
      notifyListeners();
      
      print('>>> ✅ Dados operacionais deletados:');
      print('    - $totalProdutos produto(s)');
      print('    - $totalPedidos pedido(s)');
      print('    - $totalVendas venda(s)');
      print('    - $totalServicos serviço(s)');
      print('    - $totalClientes cliente(s)');
      print('    - $totalAgendamentos agendamento(s)');
      print('>>> ⚠️ IMPORTANTE: A empresa NÃO foi deletada, apenas os dados operacionais');
    } catch (e) {
      print('>>> ❌ Erro ao deletar dados operacionais: $e');
      rethrow;
    }
  }

  // ============ CRUD Mesas e Comandas ============

  /// Adiciona uma nova mesa ou comanda
  Future<void> addMesaComanda(MesaComanda mesaComanda) async {
    _mesasComandas.add(mesaComanda);
    notifyListeners();
    _salvarAutomaticamente();
    // Salvar imediatamente no Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.salvarMesaComanda(_empresaIdAtual!, mesaComanda).catchError((e) {
        debugPrint('>>> Erro ao salvar mesa/comanda no Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  /// Atualiza uma mesa ou comanda existente
  Future<void> updateMesaComanda(MesaComanda mesaComanda) async {
    final index = _mesasComandas.indexWhere((m) => m.id == mesaComanda.id);
    if (index != -1) {
      _mesasComandas[index] = mesaComanda;
      notifyListeners();
      _salvarAutomaticamente();
      // Salvar imediatamente no Firebase
      if (_firebaseHabilitado && _empresaIdAtual != null) {
        _firebaseService.salvarMesaComanda(_empresaIdAtual!, mesaComanda).catchError((e) {
          debugPrint('>>> Erro ao atualizar mesa/comanda no Firebase: $e');
          _adicionarSincronizacaoPendente();
        });
      }
    }
  }

  /// Remove uma mesa ou comanda
  Future<void> deleteMesaComanda(String id) async {
    _mesasComandas.removeWhere((m) => m.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover do Firebase
    if (_firebaseHabilitado && _empresaIdAtual != null) {
      _firebaseService.removerMesaComanda(_empresaIdAtual!, id).catchError((e) {
        debugPrint('>>> Erro ao remover mesa/comanda do Firebase: $e');
        _adicionarSincronizacaoPendente();
      });
    }
  }

  /// Atualiza o status de um item de mesa/comanda
  Future<void> atualizarStatusItemMesaComanda(
    String mesaComandaId,
    String itemId,
    StatusItem novoStatus, {
    String? usuarioModificou,
    String? acaoRealizada,
  }) async {
    final mesaComanda = _mesasComandas.firstWhere(
      (m) => m.id == mesaComandaId,
      orElse: () => throw Exception('Mesa/Comanda não encontrada'),
    );

    final itemIndex = mesaComanda.itens.indexWhere((i) => i.id == itemId);
    if (itemIndex == -1) {
      throw Exception('Item não encontrado');
    }

    final acao = acaoRealizada ?? _getAcaoPorStatus(novoStatus);
    final itemAtualizado = mesaComanda.itens[itemIndex].copyWith(
      status: novoStatus,
      dataHoraPronto: novoStatus == StatusItem.pronto ? DateTime.now() : mesaComanda.itens[itemIndex].dataHoraPronto,
      usuarioModificou: usuarioModificou,
      dataModificacao: DateTime.now(),
      acaoRealizada: acao,
    );

    final itensAtualizados = List<ItemMesaComanda>.from(mesaComanda.itens);
    itensAtualizados[itemIndex] = itemAtualizado;

    // Usar copyWith para preservar TODOS os campos, incluindo couvert, garçom, pagamentos, etc.
    final mesaComandaAtualizada = mesaComanda.copyWith(
      itens: itensAtualizados,
      total: mesaComanda.totalCalculado,
      updatedAt: DateTime.now(),
      usuarioModificou: usuarioModificou,
    );

    await updateMesaComanda(mesaComandaAtualizada);
  }

  String _getAcaoPorStatus(StatusItem status) {
    switch (status) {
      case StatusItem.pendente:
        return 'Status alterado para Pendente';
      case StatusItem.emPreparo:
        return 'Status alterado para Em Preparo';
      case StatusItem.pronto:
        return 'Status alterado para Pronto';
      case StatusItem.entregue:
        return 'Status alterado para Entregue';
      case StatusItem.cancelado:
        return 'Item cancelado';
    }
  }

  /// Cria uma mesa/comanda a partir de um pedido
  Future<MesaComanda> criarMesaComandaDePedido(
    Pedido pedido,
    TipoControle tipo,
  ) async {
    final numero = tipo == TipoControle.mesa
        ? 'MESA-${pedido.numero.replaceAll(RegExp(r'[^\d]'), '').padLeft(3, '0')}'
        : 'CMD-${pedido.numero.replaceAll(RegExp(r'[^\d]'), '').padLeft(3, '0')}';

    final itens = <ItemMesaComanda>[];

    // Adicionar produtos do pedido
    for (final itemPedido in pedido.produtos) {
      // ItemPedido tem: id, nome, quantidade, preco
      // O id do ItemPedido é o id do produto
      final produto = _produtos.firstWhere(
        (p) => p.id == itemPedido.id,
        orElse: () => throw Exception('Produto não encontrado: ${itemPedido.id}'),
      );

      itens.add(ItemMesaComanda(
        id: uuid.v4(),
        itemId: produto.id,
        nome: produto.nome,
        quantidade: itemPedido.quantidade,
        preco: itemPedido.preco / itemPedido.quantidade, // Preço unitário
        isServico: false,
        paraCozinha: produto.paraCozinha,
        paraBar: produto.paraBar,
        status: StatusItem.pendente,
        dataHora: DateTime.now(),
      ));
    }

    // Adicionar serviços do pedido
    for (final itemServico in pedido.servicos) {
      // ItemServico tem: id, descricao, valor, valorAdicional, etc.
      // O id do ItemServico é o id do serviço
      final servico = _tiposServico.firstWhere(
        (s) => s.id == itemServico.id,
        orElse: () => throw Exception('Serviço não encontrado: ${itemServico.id}'),
      );

      itens.add(ItemMesaComanda(
        id: uuid.v4(),
        itemId: servico.id,
        nome: servico.nome,
        quantidade: 1, // ItemServico não tem quantidade, assume 1
        preco: itemServico.valor + itemServico.valorAdicional, // Preço total
        isServico: true,
        paraCozinha: false, // Serviços geralmente não são para cozinha/bar
        paraBar: false,
        status: StatusItem.pendente,
        dataHora: DateTime.now(),
      ));
    }

    final mesaComanda = MesaComanda(
      id: uuid.v4(),
      tipo: tipo,
      numero: numero,
      clienteId: pedido.clienteId,
      clienteNome: pedido.clienteNome,
      itens: itens,
      dataAbertura: pedido.dataPedido,
      status: 'Aberta',
      observacao: pedido.observacoes,
      total: pedido.total,
    );

    await addMesaComanda(mesaComanda);
    return mesaComanda;
  }

  // ===========================================================================
  // PAGINAÇÃO E INFINITE SCROLL
  // ===========================================================================

  bool get temMaisClientes => _temMaisClientes;
  bool get carregandoMaisClientes => _carregandoMaisClientes;

  /// Carrega a próxima página de clientes (50 por vez)
  Future<void> carregarMaisClientes() async {
    if (_carregandoMaisClientes || !_temMaisClientes || _empresaIdAtual == null) return;
    
    _carregandoMaisClientes = true;
    notifyListeners();
    
    try {
      debugPrint('>>> [Sync] 📥 Carregando mais clientes...');
      final snapshot = await _firebaseService.carregarColecaoPaginada(
        _empresaIdAtual!, 
        'clientes',
        startAfter: _ultimoDocClientes,
        orderBy: 'nome', 
        descending: false,
      );
      
      if (snapshot.docs.isEmpty) {
        _temMaisClientes = false;
        debugPrint('>>> [Sync] ✓ Fim da lista de clientes atingido');
      } else {
        _ultimoDocClientes = snapshot.docs.last;
        final novosClientes = snapshot.docs.map((doc) => Cliente.fromMap(doc.data() as Map<String, dynamic>)).toList();
        
        int contagemNovos = 0;
        for (var novo in novosClientes) {
          final index = _clientes.indexWhere((c) => c.id == novo.id);
          if (index == -1) {
            _clientes.add(novo);
            contagemNovos++;
          } else {
            _clientes[index] = novo; // Atualizar se já existir
          }
        }
        
        // Ordenar por nome para manter consistência na UI
        _clientes.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
        
        debugPrint('>>> [Sync] ✓ Mais $contagemNovos clientes carregados (Total: ${_clientes.length})');
        
        // Se veio menos que o limite, não há mais dados no servidor
        if (snapshot.docs.length < 50) {
          _temMaisClientes = false;
        }
      }
    } catch (e) {
      debugPrint('>>> [DataService] Erro ao carregar mais clientes: $e');
    } finally {
      _carregandoMaisClientes = false;
      notifyListeners();
    }
  }

  bool get temMaisVendas => _temMaisVendas;
  bool get carregandoMaisVendas => _carregandoMaisVendas;

  /// Carrega a próxima página de vendas (50 por vez)
  Future<void> carregarMaisVendas() async {
    if (_carregandoMaisVendas || !_temMaisVendas || _empresaIdAtual == null) return;
    
    _carregandoMaisVendas = true;
    notifyListeners();
    
    try {
      debugPrint('>>> [Sync] 📥 Carregando mais vendas...');
      final snapshot = await _firebaseService.carregarColecaoPaginada(
        _empresaIdAtual!, 
        'vendas_balcao',
        startAfter: _ultimoDocVendas,
        orderBy: 'dataVenda', 
        descending: true,
      );
      
      if (snapshot.docs.isEmpty) {
        _temMaisVendas = false;
        debugPrint('>>> [Sync] ✓ Fim da lista de vendas atingido');
      } else {
        _ultimoDocVendas = snapshot.docs.last;
        final novasVendas = snapshot.docs.map((doc) => VendaBalcao.fromMap(doc.data() as Map<String, dynamic>)).toList();
        
        int contagemNovas = 0;
        for (var nova in novasVendas) {
          final index = _vendasBalcao.indexWhere((v) => v.id == nova.id);
          if (index == -1) {
            _vendasBalcao.add(nova);
            contagemNovas++;
          } else {
            _vendasBalcao[index] = nova;
          }
        }
        
        // Ordenar por data (mais recentes primeiro)
        _vendasBalcao.sort((a, b) => b.dataVenda.compareTo(a.dataVenda));
        
        debugPrint('>>> [Sync] ✓ Mais $contagemNovas vendas carregadas (Total: ${_vendasBalcao.length})');
        
        if (snapshot.docs.length < 50) {
          _temMaisVendas = false;
        }
      }
    } catch (e) {
      debugPrint('>>> [DataService] Erro ao carregar mais vendas: $e');
    }
    finally {
      _carregandoMaisVendas = false;
      notifyListeners();
    }
  }

  void _reiniciarMonitorBridge() {
    _bridgeSubscription?.cancel();
    debugPrint('>>> [BridgeMonitor] 📡 Iniciando monitor de presença global...');
    
    _bridgeSubscription = FirebaseFirestore.instance
        .collection('bridge_status')
        .snapshots()
        .listen((snapshot) {
      _bridgesStatus = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
      
      debugPrint('>>> [BridgeMonitor] 🖥️ Status atualizado: $bridgeOnlineCount terminais online.');
      notifyListeners();
    }, onError: (e) {
      debugPrint('>>> [BridgeMonitor] ❌ Erro: $e');
    });
  }

  /// Sincroniza notas fiscais com o Google Drive de forma automática e silenciosa
  Future<void> _sincronizarNotasComDrive() async {
    if (_empresaAtual == null) return;
    
    // Evitar múltiplas execuções simultâneas
    if (_syncDriveEmAndamento) return;
    _syncDriveEmAndamento = true;

    try {
      debugPrint('>>> [SyncDrive] ☁️ Iniciando sincronização automática com Drive...');
      final driveService = GoogleDriveService.instance;
      
      // Só tenta se estiver logado ou puder logar silenciosamente
      if (driveService.driveApi == null) {
        final ok = await driveService.login(silencioso: true);
        if (!ok) {
          debugPrint('>>> [SyncDrive] ⏭️ Sincronização Drive pulada: Usuário não logado no Google');
          _syncDriveEmAndamento = false;
          return;
        }
      }

      final agora = DateTime.now();
      final trintaDiasAtras = agora.subtract(const Duration(days: 30));

      // 1. Sincronizar NFC-es Autorizadas recentes
      final nfcesExportar = _nfces.where((n) {
        return n.status == 'autorizada' && 
               n.dataEmissao.isAfter(trintaDiasAtras) &&
               !_notasSincronizadasDrive.contains(n.id);
      }).toList();

      if (nfcesExportar.isNotEmpty) {
        debugPrint('>>> [SyncDrive] 📄 Processando ${nfcesExportar.length} NFC-es para o Drive...');
        for (final nfce in nfcesExportar) {
          if (nfce.xmlEnviado != null && nfce.xmlEnviado!.isNotEmpty) {
            final ok = await driveService.salvarNotaXml(
              empresa: _empresaAtual!,
              tipoNota: 'NFCe',
              chaveAcesso: nfce.chaveAcesso ?? nfce.id,
              conteudoXml: nfce.xmlEnviado!,
              dataEmissao: nfce.dataEmissao,
            );
            if (ok) _notasSincronizadasDrive.add(nfce.id);
            // Pequeno delay para não sobrecarregar
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
      }

      // 2. Sincronizar Notas de Entrada recentes
      final entradasExportar = _notasEntrada.where((n) {
        if (n.dataEmissao == null) return false;
        return n.dataEmissao!.isAfter(trintaDiasAtras) &&
               !_notasSincronizadasDrive.contains(n.id);
      }).toList();

      if (entradasExportar.isNotEmpty) {
        debugPrint('>>> [SyncDrive] 📦 Processando ${entradasExportar.length} Notas de Entrada para o Drive...');
        for (final nota in entradasExportar) {
          if (nota.xmlOriginal != null && nota.xmlOriginal!.isNotEmpty) {
            final ok = await driveService.salvarNotaXml(
              empresa: _empresaAtual!,
              tipoNota: 'Entrada',
              chaveAcesso: nota.chaveNFe ?? nota.id,
              conteudoXml: nota.xmlOriginal!,
              dataEmissao: nota.dataEmissao,
            );
            if (ok) _notasSincronizadasDrive.add(nota.id);
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }
      }
      debugPrint('>>> [SyncDrive] ✅ Sincronização automática com Drive concluída.');
    } catch (e) {
      debugPrint('>>> [SyncDrive] ⚠️ Erro silencioso na sincronização: $e');
    } finally {
      _syncDriveEmAndamento = false;
    }
  }
}

