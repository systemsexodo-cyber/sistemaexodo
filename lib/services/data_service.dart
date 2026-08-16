import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/usuario.dart';

import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/ordem_servico.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/models/troca_devolucao.dart';
import 'package:sistema_exodo_novo/models/estoque_historico.dart';
import 'package:sistema_exodo_novo/models/lote_produto.dart';
import 'package:sistema_exodo_novo/models/produto_historico.dart';
import 'package:sistema_exodo_novo/models/nota_entrada.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/agendamento_servico.dart';
import 'package:sistema_exodo_novo/models/pet.dart';
import 'package:sistema_exodo_novo/models/funcionario.dart';
import 'package:sistema_exodo_novo/models/taxa_entrega.dart';
import 'package:sistema_exodo_novo/models/conta_pagar.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';
import 'package:sistema_exodo_novo/models/mesa_comanda.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/link_vendedor.dart';
import 'package:sistema_exodo_novo/models/comissao_vendedor.dart';
import 'package:sistema_exodo_novo/models/motorista.dart';
import 'package:sistema_exodo_novo/models/romaneio.dart';
import 'package:sistema_exodo_novo/models/perfil_tributario.dart';
import 'package:sistema_exodo_novo/models/departamento.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'package:sistema_exodo_novo/services/realtime_sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sistema_exodo_novo/services/sync_queue_service.dart';
import 'package:sistema_exodo_novo/services/whatsapp_service.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/services/google_drive_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/connection_logger_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:uuid/uuid.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Import condicional para Web
import '../pages/html_helper_stub.dart' if (dart.library.html) '../pages/html_helper_web.dart' as html_helper;

// Re-export TipoPessoa para facilitar uso
export 'package:sistema_exodo_novo/models/cliente.dart' show TipoPessoa;

const uuid = Uuid();

class DataService extends ChangeNotifier {
  List<EstoqueHistorico> get estoqueHistorico => _estoqueHistorico;
  List<LoteProduto> get lotesProdutos => _lotesProdutos;
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
  final List<LoteProduto> _lotesProdutos = [];
  
  // Getters públicos para acesso às listas (se não existirem)
  final List<NotaEntrada> _notasEntrada = [];
  final List<AgendamentoServico> _agendamentosServico = [];
  final List<Funcionario> _funcionarios = [];
  final List<TaxaEntrega> _taxasEntrega = [];
  final List<ContaPagar> _contasPagar = [];
  final List<NFCe> _nfces = [];
  final List<NFCe> _nfes = [];
  final List<MesaComanda> _mesasComandas = [];
  final List<LinkVendedor> _linksVendedores = [];
  final List<ComissaoVendedor> _comissoesVendedores = [];
  final List<Romaneio> _romaneios = [];
  final List<PerfilTributario> _perfisTributarios = [];
  bool _migrandoPerfisTributarios = false; // Guard contra corrida na migração do cache
  bool _persistindoPerfisTributarios = false; // Guard contra recursão na persistência
  final List<Departamento> _departamentos = [];
  bool _persistindoDepartamentos = false; // Guard contra recursão na persistência
  
  // Licenciamento
  DateTime? _ultimaValidacaoOnline;
  DateTime? _ultimaDataExecucao;
  bool _liberacaoProvisoriaAtiva = false;
  String? _responsavelAtivo;
  
  // Controle de Performance de Sincronização
  DateTime? _ultimoResetFoco;
  
  // Controle de sincronização Google Drive
  final Set<String> _notasSincronizadasDrive = {};
  bool _syncDriveEmAndamento = false;
  
  // Monitor de Bridge (NFC-e)
  List<Map<String, dynamic>> _bridgesStatus = [];
  StreamSubscription? _bridgeSubscription;
  
  // Controle de Sincronização e Snapshots
  bool _primeiraCargaAgendamentosRealizada = false;
  bool _syncMonitorInitialized = false;
  StreamSubscription? _produtosSubscription;
  StreamSubscription? _servicosSubscription;
  StreamSubscription? _agendamentosSubscription;
  
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

  // Getter que filtra apenas o que está "ATIVO" (Aberta). 
  // Isso resolve definitivamente o problema de mesas que não somem após o recebimento.
  List<MesaComanda> get mesasComandas => _mesasComandas.where((m) => m.status == 'Aberta').toList();
  
  List<MesaComanda> get mesasComandasAbertas => mesasComandas;
  List<MesaComanda> get todasMesasComandas => _mesasComandas;

  /// Exporta todos os dados operacionais da empresa em formato JSON
  Map<String, dynamic> exportarBackupCompleto() {
    return {
      'versao_schema': '1.0.0',
      'software': 'Sistema Êxodo',
      'data_exportacao': DateTime.now().toIso8601String(),
      'empresa_id': _currentEmpresaId,
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
        'romaneios': _romaneios.map((e) => e.toMap()).toList(),
      }
    };
  }

  /// Restaura dados de um backup, substituindo todos os dados atuais em memória
  /// e persistindo no PostgreSQL.
  Future<bool> importarBackup(Map<String, dynamic> backup) async {
    try {
      final colecoes = backup['colecoes'] as Map<String, dynamic>?;
      if (colecoes == null) return false;

      debugPrint('>>> [Restore] 🔄 Importando backup...');

      // Limpar dados em memória
      _clientes.clear();
      _produtos.clear();
      _tiposServico.clear();
      _pedidos.clear();
      _ordensServico.clear();
      _vendasBalcao.clear();
      _trocasDevolucoes.clear();
      _agendamentosServico.clear();
      _contasPagar.clear();
      _notasEntrada.clear();
      _funcionarios.clear();
      _nfces.clear();
      _romaneios.clear();
      _comissoesVendedores.clear();
      _linksVendedores.clear();

      // Importar cada coleção usando fromMap dos modelos
      if (colecoes['clientes'] is List) {
        for (final item in colecoes['clientes'] as List) {
          _clientes.add(Cliente.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['produtos'] is List) {
        for (final item in colecoes['produtos'] as List) {
          _produtos.add(Produto.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['servicos'] is List) {
        for (final item in colecoes['servicos'] as List) {
          _tiposServico.add(Servico.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['pedidos'] is List) {
        for (final item in colecoes['pedidos'] as List) {
          _pedidos.add(Pedido.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['vendas_balcao'] is List) {
        for (final item in colecoes['vendas_balcao'] as List) {
          _vendasBalcao.add(VendaBalcao.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['agendamentos'] is List) {
        for (final item in colecoes['agendamentos'] as List) {
          _agendamentosServico.add(AgendamentoServico.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['contas_pagar'] is List) {
        for (final item in colecoes['contas_pagar'] as List) {
          _contasPagar.add(ContaPagar.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['notas_entrada'] is List) {
        for (final item in colecoes['notas_entrada'] as List) {
          _notasEntrada.add(NotaEntrada.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['funcionarios'] is List) {
        for (final item in colecoes['funcionarios'] as List) {
          _funcionarios.add(Funcionario.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['ordens_servico'] is List) {
        for (final item in colecoes['ordens_servico'] as List) {
          _ordensServico.add(OrdemServico.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['trocas_devolucoes'] is List) {
        for (final item in colecoes['trocas_devolucoes'] as List) {
          final trocaItem = TrocaDevolucao.fromMap(item as Map<String, dynamic>);
          if (_isTrocaDevolucaoValida(trocaItem)) {
            _trocasDevolucoes.add(trocaItem);
          }
        }
      }
      if (colecoes['comissoes'] is List) {
        for (final item in colecoes['comissoes'] as List) {
          _comissoesVendedores.add(ComissaoVendedor.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['nfces'] is List) {
        for (final item in colecoes['nfces'] as List) {
          _nfces.add(NFCe.fromMap(item as Map<String, dynamic>));
        }
      }
      if (colecoes['romaneios'] is List) {
        for (final item in colecoes['romaneios'] as List) {
          _romaneios.add(Romaneio.fromMap(item as Map<String, dynamic>));
        }
      }

      // Persistir no PostgreSQL
      await _salvarTodosDados(aguardarSupabase: false, isSync: true);
      
      notifyListeners();

      debugPrint('>>> [Restore] ✅ Backup restaurado com sucesso!');
      return true;
    } catch (e, st) {
      debugPrint('>>> [Restore] ❌ Erro ao restaurar backup: $e\n$st');
      return false;
    }
  }

  /// Limpa todos os dados em memória (útil para restore/preparar importação)
  void limparDadosMemoria() {
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
    _lotesProdutos.clear();
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
    _romaneios.clear();
    _perfisTributarios.clear();
    _departamentos.clear();
  }
  
  // Controle de caixa
  bool _caixaAberto = false; // Flag rápida para verificações de UI
  bool get caixaAberto {
    // Se houver responsável ativo, o caixa "aberto" é o caixa desse usuário.
    // Cada usuário da empresa pode ter o SEU próprio caixa aberto.
    if (_responsavelAtivo != null && _responsavelAtivo!.isNotEmpty) {
      // Só considera aberto quando existe uma abertura REAL para este usuário
      // (própria ou caixa herdado sem responsável). ANTES, o fallback usava a
      // flag _caixaAberto da empresa inteira — isso fazia o operador vender
      // "no caixa de outro usuário" e os valores se misturarem.
      return aberturaCaixaAtual != null;
    }
    return _caixaAberto;
  }
  final List<AberturaCaixa> _aberturasCaixa = [];
  final List<FechamentoCaixa> _fechamentosCaixa = [];
  final List<SangriaCaixa> _sangrias = [];
  final List<SuprimentoCaixa> _suprimentos = [];
  List<AberturaCaixa> get aberturasCaixa => _aberturasCaixa;
  List<FechamentoCaixa> get fechamentosCaixa => _fechamentosCaixa;
  List<SangriaCaixa> get sangrias => _sangrias;
  List<SuprimentoCaixa> get suprimentos => _suprimentos;

  /// Todas as aberturas de caixa que ainda NÃO possuem fechamento (caixas abertos)
  List<AberturaCaixa> get aberturasCaixaAbertas {
    return _aberturasCaixa.where((abertura) {
      final temFechamento = _fechamentosCaixa.any(
        (f) => f.aberturaCaixaId == abertura.id,
      );
      return !temFechamento;
    }).toList();
  }

  /// Abertura de caixa aberta de um responsável específico (email ou nome)
  AberturaCaixa? aberturaCaixaDoResponsavel(String? responsavel) {
    if (responsavel == null || responsavel.isEmpty) return null;
    final abertas = aberturasCaixaAbertas;
    for (int i = abertas.length - 1; i >= 0; i--) {
      final ab = abertas[i];
      // Comparação tolerante: email vs nome (ex: 'carlos@gmail.com' bate com
      // 'Carlos'). ANTES era comparação exata de string, o que fazia o operador
      // não encontrar o PRÓPRIO caixa e o app "herdar" o caixa de outro usuário.
      if (_ehMesmoOperador(ab.responsavel, responsavel)) return ab;
    }
    return null;
  }

  /// Última abertura de caixa do operador (aberta OU fechada) — usada pelo
  /// filtro "Apenas Meu Caixa" do histórico. Só considera caixas DO operador
  /// informado; nunca cai no caixa de outro usuário (o comportamento antigo
  /// pegava a abertura mais recente GLOBAL, que podia ser de outra pessoa ou
  /// uma janela minúscula já fechada — as vendas sumiam do filtro).
  AberturaCaixa? ultimaAberturaDoOperador(String? operador) {
    if (operador == null || operador.trim().isEmpty) return null;
    // 1. Preferir o caixa ABERTO do operador (sessão atual). Ignora aberturas
    // já fechadas — inclusive as que foram abertas e fechadas em segundos, cuja
    // janela minúscula fazia todas as vendas sumirem do filtro "Meu Caixa".
    AberturaCaixa? aberta;
    for (final ab in aberturasCaixaAbertas) {
      if (_ehMesmoOperador(ab.responsavel, operador)) {
        if (aberta == null ||
            ab.dataAbertura.isAfter(aberta.dataAbertura)) {
          aberta = ab;
        }
      }
    }
    if (aberta != null) return aberta;
    // 2. Sem caixa aberto, usar a última sessão FECHADA do operador.
    AberturaCaixa? maisRecente;
    for (final ab in _aberturasCaixa) {
      if (_ehMesmoOperador(ab.responsavel, operador)) {
        if (maisRecente == null ||
            ab.dataAbertura.isAfter(maisRecente.dataAbertura)) {
          maisRecente = ab;
        }
      }
    }
    return maisRecente;
  }

  /// Uma venda pertence ao caixa do operador? Venda SEM operador (legada) e
  /// caixa sem responsável sempre pertencem; quando ambos existem, exige
  /// correspondência tolerante (email vs nome).
  bool vendaPertenceAoOperador(String? operadorVenda, String? responsavelCaixa) {
    if (operadorVenda == null || operadorVenda.trim().isEmpty) return true;
    if (responsavelCaixa == null || responsavelCaixa.trim().isEmpty) return true;
    return _ehMesmoOperador(operadorVenda, responsavelCaixa);
  }
  List<NotaEntrada> get notasEntrada => _notasEntrada;
  List<NFCe> get nfces => _nfces;
  List<NFCe> get nfes => _nfes;
  List<VendaBalcao> get vendasBalcao => _vendasBalcao;
  List<Pedido> get pedidos => _pedidos;
  List<TrocaDevolucao> get trocasDevolucoes => _trocasDevolucoes;

  /// Devolucoes corrompidas por sincronizacao (stubs sem venda vinculada,
  /// sem valor e sem itens - geradas pelo bug antigo do DateTime.now() no
  /// TrocaDevolucao.fromMap) sao lixo e devem ser ignoradas em todo lugar.
  bool _isTrocaDevolucaoValida(TrocaDevolucao t) {
    final temVenda =
        t.numeroPedido.isNotEmpty || t.pedidoId.isNotEmpty;
    if (temVenda) return true;
    return !(t.valorDevolvido <= 0 &&
        t.itensDevolvidos.isEmpty &&
        (t.itensNovos == null || t.itensNovos!.isEmpty));
  }

  /// Retorna as trocas e devoluções em um período específico
  List<TrocaDevolucao> getTrocasDevolucoesPorPeriodo(DateTime inicio, DateTime fim) {
    return _trocasDevolucoes.where((t) {
      return t.dataOperacao.isAfter(inicio) && t.dataOperacao.isBefore(fim);
    }).toList();
  }

  // Controle de Importação Excel
  bool _importandoExcel = false;
  bool get importandoExcel => _importandoExcel;
  void setImportandoExcel(bool valor) {
    _importandoExcel = valor;
    notifyListeners();
  }

  /// Retorna as NFC-es autorizadas em um período específico
  List<NFCe> getNfcesPorPeriodo(DateTime inicio, DateTime fim) {
    return _nfces.where((n) {
      if (n.status != 'autorizada') return false;
      return n.dataEmissao.isAfter(inicio) && n.dataEmissao.isBefore(fim);
    }).toList();
  }

  /// Última abertura de caixa que ainda não possui fechamento.
  /// Se houver responsável ativo, retorna o caixa aberto DESSE usuário — e NUNCA
  /// cai no caixa de outro usuário (antes, o fallback pegava a última abertura
  /// aberta da empresa, fazendo o caixa do carlos "herdar" o caixa da Silvia e
  /// os valores se misturarem).
  AberturaCaixa? get aberturaCaixaAtual {
    final temResponsavelAtivo = _responsavelAtivo != null && _responsavelAtivo!.isNotEmpty;

    if (temResponsavelAtivo) {
      final doResponsavel = aberturaCaixaDoResponsavel(_responsavelAtivo);
      if (doResponsavel != null) return doResponsavel;
      // Responsável ativo sem caixa próprio: NÃO herdar caixa de outro usuário.
      // Só permite herança quando o caixa aberto também não tem responsável
      // (caixa herdado/antigo aberto antes da definição de responsável).
      for (int i = _aberturasCaixa.length - 1; i >= 0; i--) {
        final abertura = _aberturasCaixa[i];
        final respAb = (abertura.responsavel ?? '').trim();
        final temFechamento = _fechamentosCaixa.any(
          (f) => f.aberturaCaixaId == abertura.id,
        );
        if (temFechamento) continue;
        if (respAb.isEmpty) return abertura;
      }
      return null;
    }

    if (_aberturasCaixa.isEmpty) return null;
    
    // OTIMIZAÇÃO: Procurar de trás para frente (mais recente primeiro)
    // a primeira abertura que não tenha um fechamento correspondente.
    for (int i = _aberturasCaixa.length - 1; i >= 0; i--) {
      final abertura = _aberturasCaixa[i];
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
  LocalStorageService get storage => _storage;
  final SupabaseService _supabaseService = SupabaseService.instance;
  final SyncQueueService _syncQueue = SyncQueueService();
  final RealtimeSyncService _realtimeSync = RealtimeSyncService.instance;

  bool _syncEmAndamento = false;

  /// Helper para realizar upsert no Supabase com empresa_id automático
  Future<void> _upsertNoSupabase(String table, Map<String, dynamic> data) async {
    if (!SupabaseService.isAvailable) {
      debugPrint('>>> [Supabase] ⏭️ Pulando upsert em $table: Supabase não disponível');
      return;
    }
    if (_currentEmpresaId == null) {
      debugPrint('>>> [Supabase] ⏭️ Pulando upsert em $table: Empresa não definida');
      return;
    }

    try {
      final map = Map<String, dynamic>.from(data);
      // SEMPRE definir empresa_id para garantir RLS funcione corretamente
      map['empresa_id'] = _currentEmpresaId;
      
      // SANITIZAÇÃO E RLS:
      // 1. Remover colunas que causam erro PGRST204 especificamente em cada tabela
      if (table == SupabaseService.tableEmpresas) {
        map.remove('observacao');
        map.remove('cor_primaria');
        map.remove('cor_secundaria');
        map.remove('telas_permitidas');
      } else if (table == SupabaseService.tableMesasComandas) {
        // 'total' é um campo calculado (getter totalCalculado). Não existe como coluna no Supabase.
        // O valor real dos itens é recalculado no modelo ao carregar.
        map.remove('total');
      } else if (table == SupabaseService.tableEntregas) {
        // enderecoEntrega ainda não existe como coluna no Supabase (PGRST204) e isso
        // fazia o sync de entregas ser descartado por completo. REMOVER após rodar
        // o SUPABASE_FIX_ALL.sql (que adiciona a coluna).
        map.remove('enderecoEntrega');
      }
      
      // 2. Injetar o ID real do usuário do Supabase apenas em tabelas que possuem a coluna usuario_id
      // Tabelas de auditoria/histórico e transações principais geralmente possuem.
      // aberturas_caixa causou erro PGRST204 (coluna não encontrada), mas fechamentos_caixa pode precisar para RLS.
      final supabaseUid = _supabaseService.client.auth.currentUser?.id;
      if (supabaseUid != null) {
        if ((table.contains('historico') && table != 'estoque_historico') || 
            table.contains('atividades') || 
            table == 'produto_historico') {
          map['usuario_id'] = supabaseUid;
        } else {
          map.remove('usuario_id'); // Garantir que não vá o "1" local
        }
      } else {
        map.remove('usuario_id');
      }

      // 3. Mapear snake_case para camelCase para tabelas de caixa (alinhamento com schema do Supabase)
      if (table == 'aberturas_caixa') {
        if (map.containsKey('data_abertura')) map['dataAbertura'] = map.remove('data_abertura');
        if (map.containsKey('valor_inicial')) map['valorInicial'] = map.remove('valor_inicial');
        if (map.containsKey('created_at')) map['createdAt'] = map.remove('created_at');
        if (map.containsKey('updated_at')) map['updatedAt'] = map.remove('updated_at');
      } else if (table == 'fechamentos_caixa') {
        if (map.containsKey('abertura_caixa_id')) map['aberturaCaixaId'] = map.remove('abertura_caixa_id');
        if (map.containsKey('data_fechamento')) map['dataFechamento'] = map.remove('data_fechamento');
        if (map.containsKey('valor_esperado')) map['valorEsperado'] = map.remove('valor_esperado');
        if (map.containsKey('valor_real')) map['valorReal'] = map.remove('valor_real');
        if (map.containsKey('created_at')) map['createdAt'] = map.remove('created_at');
        if (map.containsKey('updated_at')) map['updatedAt'] = map.remove('updated_at');
      }

      // 4. Controle de updated_at. Para estoque_historico a data é a coluna 'data'
      // (que o toMap já envia em UTC); as colunas que não existem no Supabase são
      // filtradas dinamicamente no SupabaseService (não remover aqui — senão o
      // motivo da quebra, que vai na observação, é descartado da nuvem).
      if (table == 'estoque_historico' || table == 'estoque_movimentacao') {
        map.remove('updated_at');
      } else {
        map['updated_at'] = DateTime.now().toUtc().toIso8601String();
      }
      
      debugPrint('>>> [Supabase] 📤 Enviando para $table...');
      debugPrint('>>> [Supabase]    ID: ${map['id']}');
      debugPrint('>>> [Supabase]    Empresa: $currentEmpresaId');
      
      await _supabaseService.upsert(table, map);
      debugPrint('>>> [Supabase] ✅ Upsert OK em $table: ${map['id']}');
      
      // Sincronizar status no SyncMonitor
      if (_currentEmpresaId != null && table != 'sync_logs' && table != 'sync_status') {
        SyncMonitorService.instance.atualizarStatusSucesso(
          empresaId: _currentEmpresaId!,
          filaPendente: _dirtyCollections.length,
        ).catchError((_) {});
      }
      
      // Auto-reconexão ativa: se a gravação funcionou, com certeza estamos online
      if (_isOffline) {
        _isOffline = false;
        _consecutiveConnectionFailures = 0;
        notifyListeners();
        addSyncLog("🌐 Conexão reestabelecida (operação real concluída)");
        ConnectionLoggerService.log("🌐 Conexão reestabelecida (operação real concluída)");
      }
    } catch (e) {
      final errorStr = e.toString();
      debugPrint('>>> [Supabase] ❌ Erro no upsert em $table: $e');
      
      // PROTEÇÃO CONTRA LOOP INFINITO: Se o erro for de coluna inexistente ou RLS, NÃO adicionar na fila
      // porque ele vai falhar para sempre e travar o app em um loop de retry.
      bool isIrrecuperavel = errorStr.contains('PGRST204') || 
                            errorStr.contains('PGRST205') || // tabela não existe na nuvem (ex.: lotes_produto antes de rodar o SQL)
                            errorStr.contains('42501') || 
                            errorStr.contains('column') || 
                            errorStr.contains('violates row-level security');
                            
      if (!isIrrecuperavel) {
        _adicionarSincronizacaoPendente(table: table, data: data);
      } else {
        debugPrint('>>> [Supabase] ⚠️ Erro crítico/esquema detectado em $table. Operação descartada para evitar loop.');
      }
    }
  }

  /// Helper para realizar delete no Supabase
  Future<void> _deleteNoSupabase(String table, String id) async {
    if (!SupabaseService.isAvailable || _currentEmpresaId == null) return;
    try {
      await _supabaseService.delete(table, id);
      
      // Auto-reconexão ativa: se a deleção funcionou, com certeza estamos online
      if (_isOffline) {
        _isOffline = false;
        _consecutiveConnectionFailures = 0;
        notifyListeners();
        addSyncLog("🌐 Conexão reestabelecida (operação real concluída)");
        ConnectionLoggerService.log("🌐 Conexão reestabelecida (operação real concluída)");
      }
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao deletar de $table: $e');
      _adicionarSincronizacaoPendente();
    }
  }

  /// ======================================================
  /// SINCRONIZAÇÃO BIDIRECIONAL: Envia mudanças locais para Supabase
  /// ======================================================
  Future<void> enviarMudancaParaSupabase(String tabela, Map<String, dynamic> dados, {String? evento = 'UPSERT'}) async {
    // Retorna imediatamente e delega a chamada de rede ao event loop (em background).
    // Isso evita travamentos ou esperas na UI/finalização de vendas locais.
    _processarEnvioSupabaseBackground(tabela, dados, evento);
  }

  Future<void> _processarEnvioSupabaseBackground(String tabela, Map<String, dynamic> dados, String? evento) async {
    if (!SupabaseService.isAvailable) {
      debugPrint('>>> [Sync] ⏭️ Supabase não disponível. Adicionando à fila de sync (bg).');
      _adicionarSincronizacaoPendente(table: tabela, data: dados, type: evento);
      return;
    }
    
    if (_currentEmpresaId == null) {
      debugPrint('>>> [Sync] ⏭️ Empresa não definida. Adicionando à fila de sync (bg).');
      _adicionarSincronizacaoPendente(table: tabela, data: dados, type: evento);
      return;
    }

    try {
      if (evento == 'DELETE') {
        await _deleteNoSupabase(tabela, dados['id'] as String);
      } else {
        await _upsertNoSupabase(tabela, dados);
      }
      debugPrint('>>> [Sync] ✅ Mudança enviada para Supabase em background: $tabela (${dados['id']})');
    } catch (e) {
      debugPrint('>>> [Sync] ❌ Erro ao enviar mudança para Supabase em background: $e');
      _adicionarSincronizacaoPendente(table: tabela, data: dados, type: evento);
    }
  }

  /// ======================================================
  /// REALTIME SYNC: Processa eventos recebidos via WebSocket
  /// ======================================================
  /// Chamado pelo RealtimeSyncService quando Supabase emite um evento.
  /// Atualiza a lista em memória correta e notifica a UI instantaneamente.
  void _aplicarMudancaRealtime(String tabela, String evento, Map<String, dynamic> dados) {
    try {
      final id = dados['id'] as String?;
      debugPrint('>>> [Realtime] Aplicando $evento em $tabela (id: $id)');

      switch (tabela) {
        case 'produtos':
          _aplicarEmLista<Produto>(_produtos, evento, dados, Produto.fromMap);
          break;

        case 'clientes':
          _aplicarEmLista<Cliente>(_clientes, evento, dados, Cliente.fromMap);
          break;

        case 'pedidos':
          _aplicarEmLista<Pedido>(_pedidos, evento, dados, Pedido.fromMap);
          break;

        case 'vendas_balcao':
          _aplicarEmLista<VendaBalcao>(_vendasBalcao, evento, dados, VendaBalcao.fromMap);
          break;

        case 'mesas_comandas':
          if (id != null && _idsMesaRemovidosRecentemente.contains(id) && evento != 'DELETE') {
            debugPrint('>>> [Realtime] ⚠️ Mesa $id ignorada (remoção recente protegida)');
            break;
          }
          _aplicarEmLista<MesaComanda>(_mesasComandas, evento, dados, MesaComanda.fromMap);
          break;

        case 'agendamentos_servico':
          _aplicarEmLista<AgendamentoServico>(_agendamentosServico, evento, dados, AgendamentoServico.fromMap);
          // Som de notificação para novos agendamentos recebidos de outro PC
          if (evento == 'INSERT') {
            _tocarSomNotificacao();
          }
          break;

        case 'contas_pagar':
          _aplicarEmLista<ContaPagar>(_contasPagar, evento, dados, ContaPagar.fromMap);
          break;

        case 'aberturas_caixa':
          _aplicarEmLista<AberturaCaixa>(_aberturasCaixa, evento, dados, AberturaCaixa.fromMap);
          _caixaAberto = aberturaCaixaAtual != null;
          break;

        case 'fechamentos_caixa':
          _aplicarEmLista<FechamentoCaixa>(_fechamentosCaixa, evento, dados, FechamentoCaixa.fromMap);
          _caixaAberto = aberturaCaixaAtual != null;
          break;

        case 'bridge_status':
          // Atualizar bridges sem reconstrução total
          if (id != null) {
            _bridgesStatus.removeWhere((b) => b['id'] == id);
            if (evento != 'DELETE') _bridgesStatus.add(dados);
          }
          break;

        case 'romaneios':
          _aplicarEmLista<Romaneio>(_romaneios, evento, dados, Romaneio.fromMap);
          break;
      }

      // Notifica a UI para reconstruir apenas o que mudou
      notifyListeners();
    } catch (e) {
      debugPrint('>>> [Realtime] ❌ Erro ao aplicar mudança Realtime em $tabela: $e');
    }
  }

  /// Helper genérico para aplicar INSERT/UPDATE/DELETE em qualquer lista em memória
  void _aplicarEmLista<T>(
    List<T> lista,
    String evento,
    Map<String, dynamic> dados,
    T Function(Map<String, dynamic>) fromMap,
  ) {
    final id = dados['id'] as String?;
    if (id == null) return;

    // Remover versão anterior (para UPDATE e DELETE)
    lista.removeWhere((item) => (item as dynamic).id == id);

    // Adicionar nova versão (apenas para INSERT e UPDATE)
    if (evento != 'DELETE') {
      try {
        lista.add(fromMap(dados));
      } catch (e) {
        debugPrint('>>> [Realtime] ⚠️ Erro ao parsear item de ${T.toString()}: $e');
        debugPrint('>>> [Realtime] Dados recebidos: $dados');
      }
    }
  }



  bool _persistenciaHabilitada = true; // Flag para habilitar/desabilitar persistência

  // ID único para debug
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();
  Timer? _syncTimer;
  Timer? _checkConnectivityTimer;
  int _currentSyncInterval = 10;
  DateTime _lastSyncActivityTime = DateTime.now();
  StreamSubscription? _windowFocusSubscription;
  
  // Status de Sincronização
  DateTime? _ultimaSincronizacaoSucesso;
  String? _ultimoErroSync;
  int _conflitosCount = 0;
  bool _isModoLeve = false;
  bool _isOffline = false;
  bool get isOffline => _isOffline;
  int _consecutiveConnectionFailures = 0;
  final List<String> _syncLogs = [];

  @override
  void dispose() {
    _cancelarTodasSubscriptions();
    _debounceSalvamento?.cancel();
    _syncQueue.dispose();
    _realtimeSync.parar();
    super.dispose();
  }

  /// Cancela todos os timers ativos
  void _cancelarTodasSubscriptions() {
    debugPrint('>>> [Memória] 🧹 Cancelando timers e subscriptions...');
    _syncTimer?.cancel();
    _checkConnectivityTimer?.cancel();
    _windowFocusSubscription?.cancel();
    _syncTimer = null;
    _checkConnectivityTimer = null;
    _windowFocusSubscription = null;
  }
  String get instanceId => _instanceId;
  
  // Proteção contra salvamentos excessivos (debounce otimizado)
  Timer? _debounceSalvamento;
  bool _salvandoDados = false;
  static const Duration _debounceDelay = Duration(milliseconds: 800); // Reduzido p/ 800ms: menor janela de perda ao fechar o app

  /// Grava TODAS as coleções pendentes no PostgreSQL local AGORA (flush forçado).
  /// Chamado pelo AppLifecycleListener ao fechar o app, garantindo que nenhum
  /// dado fique apenas em memória (requisito: persistência em PostgreSQL/Supabase).
  Future<void> salvarDadosAgora() async {
    if (!_persistenciaHabilitada || _dirtyCollections.isEmpty) return;

    // Cancelar debounce pendente (evita disparo duplicado após o flush).
    _debounceSalvamento?.cancel();
    _debounceSalvamento = null;

    // Evitar concorrência com um salvamento debounced em andamento: aguardar até
    // ele terminar (com timeout de segurança) antes de rodar o flush forçado.
    final prazo = DateTime.now().add(const Duration(seconds: 5));
    while (_salvandoDados && DateTime.now().isBefore(prazo)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_salvandoDados) {
      debugPrint('>>> [DataService] ⚠️ Flush forçado: timeout aguardando salvamento em andamento');
      return;
    }

    debugPrint('>>> [DataService] 🔄 Flush forçado: salvando ${_dirtyCollections.length} coleções pendentes...');
    try {
      await _salvarTodosDados(aguardarSupabase: false, forcarTodos: true);
      debugPrint('>>> [DataService] ✅ Flush forçado concluído (PostgreSQL local atualizado)');
    } catch (e) {
      debugPrint('>>> [DataService] ❌ Erro no flush forçado: $e');
    }
  }
  DateTime? _ultimaSincronizacao;
  static const Duration _intervaloSincronizacao = Duration(days: 90); // MUITO maior para economizar cotas de gravação (90 dias)
  
  // Controle de coleções modificadas (Selective Saving)
  final Set<String> _dirtyCollections = {};
  
  // Cache de IDs removidos recentemente para evitar que o Supabase os restaure 
  // durante a latência de sincronização
  final Set<String> _idsMesaRemovidosRecentemente = {};

  void _resetTimerParaAtivo() {
    _lastSyncActivityTime = DateTime.now();
    if (_currentSyncInterval != 10) {
      _currentSyncInterval = 10;
      debugPrint('>>> [Sync] ⚡ Atividade detectada localmente. Acelerando Auto-Sync para 10 segundos.');
      _programarProximoSync();
    }
  }

  void _programarProximoSync() {
    _syncTimer?.cancel();
    if (!kIsWeb) {
      _syncTimer = Timer(Duration(seconds: _currentSyncInterval), () async {
        if (!isOffline && !_syncEmAndamento) {
          debugPrint('>>> [Sync] 🔄 Pulso de sincronia automática iniciado (intervalo atual: ${_currentSyncInterval}s)...');
          try {
            await _carregarDadosDoSupabase(modoLeve: false);
            await _salvarTodosDados(aguardarSupabase: false, isSync: true);
            await atualizarConflitosCount();
            notifyListeners();
          } catch (e) {
            debugPrint('>>> [Sync] ⚠️ Erro no pulso de sincronia: $e');
          }
        }
        
        // Reavaliar intervalo de ociosidade
        final agora = DateTime.now();
        final diferencaMinutos = agora.difference(_lastSyncActivityTime).inMinutes;
        if (diferencaMinutos >= 3) {
          if (_currentSyncInterval != 45) {
            _currentSyncInterval = 45;
            debugPrint('>>> [Sync] 💤 Sem atividades locais nos últimos 3 min. Aumentando intervalo de Auto-Sync para 45 segundos.');
          }
        } else {
          if (_currentSyncInterval != 10) {
            _currentSyncInterval = 10;
            debugPrint('>>> [Sync] ⚡ Atividade recente ativa. Mantendo intervalo em 10 segundos.');
          }
        }
        
        // Agenda o próximo pulso de sincronia
        _programarProximoSync();
      });
    }
  }

  void _marcarSujo(String collectionKey) {
    if (!_dirtyCollections.contains(collectionKey)) {
      _dirtyCollections.add(collectionKey);
      _salvarAutomaticamente();
    }
    _resetTimerParaAtivo();
  }

  /// Inicia o timer de sincronização automática (Pulso Adaptativo)
  /// Essencial para manter múltiplas máquinas alinhadas sem usar Streams instáveis.
  void iniciarAutoSync() {
    _syncTimer?.cancel();
    _currentSyncInterval = 10;
    _lastSyncActivityTime = DateTime.now();
    debugPrint('>>> [Sync] ⏱️ Timer de Auto-Sync Adaptativo iniciado (10 seg inicial)');
    _programarProximoSync();
  }
  
  // Empresa atual para isolamento de dados
  String? _currentEmpresaId;
  String? get currentEmpresaId => _currentEmpresaId;

  // Informações do usuário logado (para auditoria)
  String? _usuarioAtualId;
  String? _usuarioAtualNome;
  String? _usuarioAtualEmail;

  /// Define o usuário atual para registros de auditoria
  void setUsuarioAtual(Usuario? usuario) {
    if (usuario == null) {
      _usuarioAtualId = null;
      _usuarioAtualNome = null;
      _usuarioAtualEmail = null;
    } else {
      _usuarioAtualId = usuario.id;
      _usuarioAtualNome = usuario.nome;
      _usuarioAtualEmail = usuario.email;
    }
  }

  // Getters para UI se necessário
  String get usuarioAtualNome => _usuarioAtualNome ?? 'Sistema';
  String? get usuarioAtualEmail => _usuarioAtualEmail;
  
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
      _carregarPerfisTributariosDaEmpresa();
      _carregarDepartamentosDaEmpresa();
      notifyListeners();
    }
  }

  /// Atualiza os dados da empresa no Supabase e localmente
  Future<void> atualizarDadosEmpresa(Empresa empresa) async {
    // Garantir que updatedAt está atualizado para que pulso detecte mudança
    final empresaComTimestamp = empresa.copyWith(updatedAt: DateTime.now());
    
    _empresaAtual = empresaComTimestamp;
    _carregarPerfisTributariosDaEmpresa();
    _carregarDepartamentosDaEmpresa();
    
    // PERSISTÊNCIA CRÍTICA: Salvar no PostgreSQL IMEDIATAMENTE
    if (!kIsWeb) {
      await DatabaseService().salvarEmpresaLocal(empresaComTimestamp.toMap());
    } else {
      await _storage.salvar('empresa_atual', empresaComTimestamp.toMap());
    }
    
    await _upsertNoSupabase(SupabaseService.tableEmpresas, empresaComTimestamp.toMap());
    
    notifyListeners();
  }

  
  // Estado de carregamento
  bool _isLoading = false;
  String _mensagemLoading = 'Carregando...';

  // Controle de Paginação (Infinite Scroll)
  int _paginaAtualClientes = 0;
  bool _temMaisClientes = true;
  bool _carregandoMaisClientes = false;
  
  int _paginaAtualVendas = 0;
  bool _temMaisVendas = true;
  bool _carregandoMaisVendas = false;
  bool get isLoading => _isLoading;
  bool get syncEmAndamento => _syncEmAndamento;
  DateTime? get ultimaSincronizacaoSucesso => _ultimaSincronizacaoSucesso;
  String? get ultimoErroSync => _ultimoErroSync;
  int get conflitosCount => _conflitosCount;
  String get mensagemLoading => _mensagemLoading;
  bool get isModoLeve => _isModoLeve;
  bool get firebaseHabilitado => false; // Legado: Agora usamos Supabase
  bool get supabaseHabilitado => SupabaseService.isAvailable;
  
  List<String> get syncLogs => List.unmodifiable(_syncLogs);

  void addSyncLog(String message) {
    final now = DateTime.now().toLocal();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    _syncLogs.add("[$timeStr] $message");
    debugPrint("[SyncLog] [$timeStr] $message");
    if (_syncLogs.length > 50) {
      _syncLogs.removeAt(0);
    }
    notifyListeners();
    // Persiste logs no PostgreSQL para a empresa logada
    if (_currentEmpresaId != null && _currentEmpresaId!.isNotEmpty) {
      if (!kIsWeb) {
        DatabaseService().salvarSyncLogs(_currentEmpresaId!, _syncLogs);
      } else {
        _storage.salvar('empresa_${_currentEmpresaId}_sync_logs', _syncLogs);
      }
    }
  }
  
  /// Força uma sincronização
  Future<void> forceSync() async {
    _ultimoErroSync = null;
    addSyncLog("🔄 Sincronização forçada manualmente pelo usuário.");
    notifyListeners();
    await iniciarSincronizacao();
  }

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

  /// Verifica e atualiza a quantidade de conflitos não resolvidos no PostgreSQL local
  Future<void> atualizarConflitosCount() async {
    if (kIsWeb) return;
    try {
      final conn = await DatabaseService().connection;
      final tableCheck = await conn.execute(
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'exodo_sync_conflitos')"
      );
      final exists = tableCheck.first.first as bool;
      if (exists) {
        final result = await conn.execute("SELECT COUNT(*) FROM exodo_sync_conflitos WHERE resolvido = FALSE");
        final newCount = result.first.first as int;
        if (_conflitosCount != newCount) {
          _conflitosCount = newCount;
          notifyListeners();
        }
      } else {
        if (_conflitosCount != 0) {
          _conflitosCount = 0;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao atualizar contagem de conflitos: $e');
    }
  }

  /// Marca todos os conflitos da tabela exodo_sync_conflitos como resolvidos
  Future<void> resolverTodosConflitos() async {
    if (kIsWeb) return;
    try {
      final conn = await DatabaseService().connection;
      await conn.execute("UPDATE exodo_sync_conflitos SET resolvido = TRUE WHERE resolvido = FALSE");
      await atualizarConflitosCount();
      addSyncLog("✓ Conflitos resolvidos manualmente pelo usuário.");
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao resolver conflitos: $e');
    }
  }

  /// Define a empresa atual e recarrega os dados
  /// [modoLeve]: Se true, carrega apenas dados essenciais (otimizado para loja pública)
  Future<void> definirEmpresaAtual(String? empresaId, {bool modoLeve = false}) async {
    // Se a empresa for a mesma, mas mudamos de modoLeve para modoFull, precisamos recarregar
    if (_currentEmpresaId == empresaId && empresaId != null) {
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
    print('>>> DataService: Empresa anterior: $currentEmpresaId');
    print('>>> DataService: Empresa nova: $empresaId');
    print('>>> DataService: ========================================');
    
    // Salvar dados da empresa anterior ANTES de trocar (se houver empresa anterior)
    if (_currentEmpresaId != null) {
      print('>>> DataService: Salvando dados da empresa anterior antes de trocar...');
      try {
        await _salvarTodosDados();
        print('>>> DataService: ✓ Dados da empresa anterior salvos com sucesso');
      } catch (e) {
        print('>>> DataService: ⚠️ Erro ao salvar dados da empresa anterior: $e');
        // Continua mesmo se falhar - dados já estão no localStorage
      }
    }
    
    // ISOLAMENTO: Limpar dados da empresa anterior da MEMÓRIA (não do localStorage/Supabase)
    // Isso garante que cada empresa carregue apenas seus próprios dados
    print('>>> DataService: 🧹 Limpando dados da empresa anterior da memória...');
    print('>>> DataService: ⚠️ Os dados permanecem salvos no localStorage/Supabase');
    // Resetar Paginação
    _temMaisClientes = true;
    _temMaisVendas = true;

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
    _lotesProdutos.clear();
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
    _romaneios.clear();
    _perfisTributarios.clear();
    _departamentos.clear();
    _syncLogs.clear(); // Limpar logs da empresa anterior
    print('>>> DataService: ✓ Memória limpa - pronta para carregar dados da nova empresa');
    
    // DEFINIR NOVA EMPRESA
    _currentEmpresaId = empresaId;
    _ultimaSincronizacao = null; // Resetar para que a nova empresa tenha sua própria sincronização
    _ultimaSincronizacaoSucesso = null;
    
    // Carregar logs específicos da nova empresa do PostgreSQL
    if (empresaId != null) {
      try {
        if (!kIsWeb) {
          final loadedLogs = await DatabaseService().carregarSyncLogs(empresaId);
          _syncLogs.addAll(loadedLogs);
        } else {
          final loadedLogs = await _storage.carregar('empresa_${empresaId}_sync_logs');
          if (loadedLogs != null && loadedLogs is List) {
            _syncLogs.addAll(loadedLogs.cast<String>());
          }
        }
      } catch (e) {
        debugPrint('>>> DataService: ⚠️ Erro ao carregar logs: $e');
      }
    }
    
    // Sincronizar empresa_id com DatabaseService para isolamento PostgreSQL
    if (empresaId != null) {
      DatabaseService().setEmpresaId(empresaId);
    }
    
    if (empresaId != null) {
      if (_empresaAtual?.id != empresaId) {
        _empresaAtual = null; // Limpar para evitar dados obsoletos apenas se for realmente outra empresa
      }
      
      // Recarregar dados APENAS da nova empresa (isoladamente)
      try {
        await iniciarSincronizacao(modoLeve: modoLeve).timeout(const Duration(minutes: 2));
      } catch (e) {
        print('>>> DataService: ⚠️ Erro durante iniciarSincronizacao: $e');
        // Continuamos para garantir que _isLoading = false seja chamado
      }

      // ✅ REALTIME: Ativar escuta WebSocket para sincronização multi-PC
      if (empresaId != null && !modoLeve) {
        _realtimeSync.iniciar(empresaId, callback: _aplicarMudancaRealtime).catchError((e) {
          debugPrint('>>> [Realtime] ⚠️ Erro ao iniciar Realtime (não bloqueante): $e');
        });
      }

      // ✅ SYNC MONITOR: Inicializar monitoramento de sincronizacao
      if (!_syncMonitorInitialized && !kIsWeb) {
        _syncMonitorInitialized = true;
        try {
          final pcName = Platform.localHostname;
          SyncMonitorService.instance.initialize(
            empresaId: empresaId,
            pcName: pcName,
          );
          SyncMonitorService.instance.registrarEvento(
            empresaId: empresaId,
            evento: 'inicio_sync',
            detalhes: 'Sessao iniciada no PC: $pcName',
          );
          debugPrint('>>> [SyncMonitor] ✅ Monitoramento de sync iniciado para empresa $empresaId');
        } catch (e) {
          debugPrint('>>> [SyncMonitor] ⚠️ Erro ao iniciar monitor: $e');
        }
      }
    } else {
      debugPrint('>>> [DataService] ℹ️ Aguardando login: empresa ainda não definida.');
    }
    
    // Finalizar loading
    _isLoading = false;
    notifyListeners();
    print('>>> DataService: ✓ Troca de empresa concluída - dados isolados');

    // Registrar listener de foco para Web (acordar o app se ficar em background)
    if (kIsWeb) {
      try {
        _windowFocusSubscription?.cancel();
        _windowFocusSubscription = html_helper.onWindowFocus.listen((_) {
          final agora = DateTime.now();
          if (_ultimoResetFoco != null && agora.difference(_ultimoResetFoco!).inSeconds < 30) {
            return;
          }
          _ultimoResetFoco = agora;

          debugPrint('>>> [SISTEMA] Janela focada - Verificando atualizações...');
          if (_currentEmpresaId != null) {
            _carregarDadosDoSupabase(modoLeve: true);
          }
        }, onError: (e) {
          debugPrint('>>> [SISTEMA] Erro no stream de foco: $e');
        });
      } catch (e) {
        debugPrint('>>> [SISTEMA] Erro ao registrar listener de foco: $e');
      }
    }
  }


  void _reiniciarTimerSincronizacao() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
      if (_currentEmpresaId != null && !_isLoading) {
        _sincronizarSilenciosamente();
      }
    });
  }

  Future<void> _sincronizarSilenciosamente() async {
    if (_currentEmpresaId == null) return;
    
    try {
      debugPrint('>>> [Sync] 🔄 Sincronização silenciosa em andamento...');
      await _carregarDadosDoSupabase();
      notifyListeners(); // Notificar a UI sobre novos dados
      debugPrint('>>> [Sync] ✅ Sincronização silenciosa concluída');
    } catch (e) {
      debugPrint('>>> [Sync] ⚠ Erro na sincronização silenciosa: $e');
    }
  }
  
  /// Obtém a chave de armazenamento com prefixo da empresa
  String _getChaveComEmpresa(String chaveBase) {
    if (_currentEmpresaId == null) return chaveBase;
    return 'empresa_${_currentEmpresaId}_$chaveBase';
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
    if (_currentEmpresaId == null) {
      debugPrint('>>> [DataService] ℹ️ Recarga ignorada: empresa não definida.');
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
    _initConnectivity();
    
    // Vincular o resolver da fila de sincronização para suportar persistência (Segundo Banco)
    _syncQueue.setResolver(_resolverOperacaoSync);
  }

  void _initConnectivity() {
    try {
      Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
        bool offline = true;
        for (var res in results) {
          if (res != ConnectivityResult.none) {
            offline = false;
          }
        }
        
        // Default to online if empty
        if (results.isEmpty) offline = false;

        // Verificação REAL: tentar ping no Supabase para confirmar conectividade
        if (!offline) {
          offline = !(await _verificarConexaoReal());
        }

        if (_isOffline != offline) {
          final conexaoVoltou = _isOffline && !offline;
          _isOffline = offline;
          final msg = _isOffline ? "🔌 Aparelho offline. Sincronização em nuvem pausada." : "🌐 Aparelho online.";
          addSyncLog(msg);
          ConnectionLoggerService.log(msg);
          notifyListeners();
          
          if (conexaoVoltou) {
            final reconnectMsg = "📡 Conexão restabelecida! Retomando sincronização automática...";
            addSyncLog(reconnectMsg);
            ConnectionLoggerService.log(reconnectMsg);
            Future.microtask(() async {
              try {
                await iniciarSincronizacao(modoLeve: false);
              } catch (e) {
                addSyncLog("⚠️ Erro no auto-sync pós-reconexão: $e");
                ConnectionLoggerService.log("⚠️ Erro no auto-sync pós-reconexão: $e");
              }
            });
          }
        }
      });
      
      Connectivity().checkConnectivity().then((List<ConnectivityResult> results) async {
         bool offline = true;
         for (var res in results) {
           if (res != ConnectivityResult.none) {
             offline = false;
           }
         }
         if (results.isEmpty) offline = false;
         
         // Verificação REAL: tentar ping no Supabase
         if (!offline) {
           offline = !(await _verificarConexaoReal());
         }
         
         if (_isOffline != offline) {
           _isOffline = offline;
           final msg = _isOffline ? "🔌 Conectividade alterada para Offline" : "🌐 Conectividade alterada para Online";
           ConnectionLoggerService.log(msg);
         }
         notifyListeners();
      });
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao iniciar monitoramento de conectividade: $e');
      ConnectionLoggerService.log('⚠️ Erro ao iniciar monitoramento de conectividade: $e');
      // Se falhar, assumir online para não bloquear o sistema
      _isOffline = false;
      notifyListeners();
    }
    
    // Forçar verificação inicial de conectividade
    _verificarConexaoReal().then((isOnline) {
      if (_isOffline != !isOnline) {
        _isOffline = !isOnline;
        final msg = 'Status da conexão inicial verificado: Offline = $_isOffline';
        debugPrint('>>> [DataService] $msg');
        ConnectionLoggerService.log(msg);
        notifyListeners();
      }
    });

    // Timer inteligente para verificar a internet periodicamente sem pesar o sistema.
    // Se estiver online, verifica apenas a cada 5 minutos (evita tráfego inútil e consumo de recursos).
    // Se estiver offline, verifica a cada 30 segundos para detectar a volta da rede rapidamente.
    void scheduleCheck() {
      _checkConnectivityTimer?.cancel();
      final delay = _isOffline ? const Duration(seconds: 30) : const Duration(minutes: 5);
      _checkConnectivityTimer = Timer(delay, () async {
        try {
          final isOnline = await _verificarConexaoReal();
          final offline = !isOnline;
          
          if (_isOffline != offline) {
            final conexaoVoltou = _isOffline && !offline;
            _isOffline = offline;
            final msg = _isOffline ? "🔌 Aparelho offline. Sincronização em nuvem pausada." : "🌐 Aparelho online.";
            addSyncLog(msg);
            ConnectionLoggerService.log(msg);
            notifyListeners();
            
            if (conexaoVoltou) {
              final reconnectMsg = "📡 Conexão restabelecida! Retomando sincronização automática...";
              addSyncLog(reconnectMsg);
              ConnectionLoggerService.log(reconnectMsg);
              Future.microtask(() async {
                try {
                  await iniciarSincronizacao(modoLeve: false);
                } catch (e) {
                  addSyncLog("⚠️ Erro no auto-sync pós-reconexão: $e");
                  ConnectionLoggerService.log("⚠️ Erro no auto-sync pós-reconexão: $e");
                }
              });
            }
          }
        } catch (e) {
          debugPrint('>>> [DataService] [Timer] ⚠️ Erro no timer de conectividade: $e');
        } finally {
          scheduleCheck(); // Reagenda o próximo teste baseado no novo status
        }
      });
    }
    
    // Iniciar o agendador inteligente
    scheduleCheck();
  }

  /// Verifica conectividade real fazendo um ping rápido ao Supabase com tratamento resiliente contra alarmes falsos
  Future<bool> _verificarConexaoReal() async {
    try {
      // 1. Verificar se a máquina tem internet geral (DNS lookup rápido para hosts altamente confiáveis)
      bool temInternetGeral = false;
      if (kIsWeb) {
        // Na Web, InternetAddress.lookup de dart:io não é suportado e lança erro.
        // Assumimos true para internet geral e deixamos o ping do Supabase validar a conexão real.
        temInternetGeral = true;
      } else {
        try {
          final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 2));
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            temInternetGeral = true;
          }
        } catch (_) {
          // Tentar um fallback rápido
          try {
            final result = await InternetAddress.lookup('cloudflare.com').timeout(const Duration(seconds: 2));
            if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
              temInternetGeral = true;
            }
          } catch (_) {}
        }
      }

      // Se falhar na internet geral, estamos de fato sem conexão externa
      if (!temInternetGeral) {
        _consecutiveConnectionFailures++;
        if (_consecutiveConnectionFailures >= 3) {
          return false;
        }
        // Se ainda não atingiu o limite de falhas consecutivas, assume que está online
        // para evitar falsos negativos rápidos devido a oscilações normais
        return !_isOffline; 
      }

      // 2. A internet geral está ativa. Vamos testar a API do Supabase.
      if (!SupabaseService.isAvailable) return false;
      
      // Ping simples no Supabase
      await SupabaseService.instance.client
          .from('empresas')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 4));
      
      _consecutiveConnectionFailures = 0; // Resetar contador ao obter sucesso real
      return true; // Tudo perfeito
    } catch (e) {
      // Se for erro de esquema/coluna (PGRST204), assumir online pois é erro de schema, não de conexão
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('pgrst204') || 
          errorStr.contains('column') || 
          errorStr.contains('schema')) {
        _consecutiveConnectionFailures = 0;
        return true; 
      }
      
      // Se a internet geral estava ativa e falhou apenas o ping específico do Supabase,
      // pode ser instabilidade temporária do serviço. Toleramos por até 4 tentativas consecutivas.
      _consecutiveConnectionFailures++;
      if (_consecutiveConnectionFailures >= 4) {
        debugPrint('>>> [DataService] ⚠️ Falhas consecutivas de ping no Supabase atingiram o limite: $e');
        return false;
      }
      
      debugPrint('>>> [DataService] ⚠️ Ping no Supabase falhou temporariamente (falha $_consecutiveConnectionFailures/4): $e');
      return !_isOffline; // Mantém o estado anterior para evitar alarmes falsos
    }
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
    // Isso evita que o usuário veja listas vazias enquanto o Supabase carrega
    try {
      if (_isLoading) {
        _mensagemLoading = 'Carregando cache local...';
        notifyListeners();
      }
      await _carregarDadosSalvos();
      print('>>> ✓ Cache local carregado (${_clientes.length} clientes)');
      
      // Carregar dados complementares do Supabase (Mesas/Comandas)
      if (_currentEmpresaId != null && SupabaseService.isAvailable && !_isOffline) {
         await _carregarDadosDoSupabase(modoLeve: modoLeve);
         debugPrint('>>> [Supabase] 📡 Carga de dados em nuvem concluída');
         // Migrar pedidos sem número se necessário
         migrarPedidosSemNumero();
      }
      
      notifyListeners();
    } catch (e) {
      print('>>> ⚠ Erro ao carregar cache local: $e');
    }

    // 2. Tentar atualizar/sincronizar com Supabase (MODO NÃO-BLOQUEANTE PARA STARTUP RÁPIDO)
    if (SupabaseService.isAvailable && !_isOffline) {
      print('>>> ⚡ Supabase carregando em background para startup rápido...');
      _carregarDadosDoSupabase(modoLeve: modoLeve).timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          print('>>> ⚠ Timeout ao carregar do Supabase (45s) - continuará em background');
        },
      ).then((_) {
        print('>>> ✓ Dados do Supabase sincronizados em background');
        
        // Se Supabase retornou vazio e temos dados locais, garantir que eles subam
        // Usamos uma verificação mais robusta: se não houve sucesso ainda e temos dados locais, empurra.
        if (_ultimaSincronizacaoSucesso == null && (_clientes.isNotEmpty || _produtos.isNotEmpty)) {
          debugPrint('>>> [Sync] 📡 Banco em nuvem está vazio para esta empresa. Iniciando push inicial...');
        }
        
        // PERSISTÊNCIA CRÍTICA: Sempre salvar localmente o que foi baixado do Supabase
        _salvarTodosDados(aguardarSupabase: false, isSync: true);
        atualizarConflitosCount();
        notifyListeners();
      }).catchError((e) {
        print('>>> ⚠ Erro ao carregar do Supabase em background: $e');
      });
    } else {
      // Supabase DESABILITADO ou OFFLINE - carregar apenas do localStorage
      print('>>> 🔵 Supabase DESABILITADO ou OFFLINE - Carregando apenas do localStorage...');
      if (_isLoading) {
        _mensagemLoading = 'Carregando dados locais...';
        notifyListeners();
      }
      try {
        await _carregarDadosSalvos();
        print('>>> ✅ Dados carregados do localStorage');
      } catch (e) {
        print('>>> ⚠ Erro ao carregar do localStorage: $e');
      }
    }

    // Iniciar o timer de pulso para manter máquinas sincronizadas (essencial para PDV multi-terminal)
    iniciarAutoSync();
    
    // Se não houver dados salvos (nem Supabase nem local), carregar dados fictícios
    // APENAS para a empresa padrão (ID "1"). Empresas novas começam vazias.
    final isEmpresaPadrao = _currentEmpresaId == '1' || _currentEmpresaId == null;
    
    if (isEmpresaPadrao) {
      // Apenas a empresa padrão carrega dados fictícios
      if (_produtos.isEmpty) {
        print('>>> ⚠ Nenhum produto encontrado. Carregando dados fictícios (empresa padrão)...');
        _carregarProdutosFicticios();
        // Salvar no Supabase e localStorage
        _salvarTodosDados().catchError((e) {
          print('>>> ⚠ Erro ao salvar dados fictícios: $e');
        });
      }
      
      if (_clientes.isEmpty) {
        print('>>> ⚠ Nenhum cliente encontrado. Carregando dados fictícios (empresa padrão)...');
        _carregarClientesFicticios();
        // Salvar no Supabase e localStorage
        _salvarTodosDados().catchError((e) {
          print('>>> ⚠ Erro ao salvar dados fictícios: $e');
        });
      }
      
      if (_motoristas.isEmpty) {
        print('>>> ⚠ Nenhum motorista encontrado. Carregando dados fictícios (empresa padrão)...');
        _carregarMotoristasFicticios();
        // Salvar no Supabase e localStorage
        _salvarTodosDados().catchError((e) {
          print('>>> ⚠ Erro ao salvar dados fictícios: $e');
        });
      }
    } else {
      // Empresas novas começam vazias - não carregam dados fictícios
      print('>>> Empresa nova (ID: $currentEmpresaId) - não carregando dados fictícios');
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

    // Status do caixa é calculado dinamicamente via PostgreSQL (aberturaCaixaAtual)
    if (_currentEmpresaId != null) {
      _caixaAberto = aberturaCaixaAtual != null;
      print('>>> Caixa atual: ${_caixaAberto ? "ABERTO" : "FECHADO"}');
    } else {
      debugPrint('>>> [Caixa] Status ignorado (empresa não definida no boot)');
    }

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

    print('>>> ${_agendamentosServico.length} agendamentos carregados');
    print('>>> Persistência: ${_persistenciaHabilitada ? "HABILITADA" : "DESABILITADA"}');
  }

  /// Força o download de todos os dados do Supabase para o banco local
  Future<void> baixarDadosDoSupabase() async {
    if (!SupabaseService.isAvailable) {
      throw Exception('Supabase não está disponível no momento.');
    }

    _isLoading = true;
    _mensagemLoading = 'Baixando dados do Supabase...';
    notifyListeners();

    try {
      print('>>> [Sync] ⬇️ Iniciando download forçado do Supabase...');
      
      // Chamar carregamento completo do Supabase
      await _carregarDadosDoSupabase(modoLeve: false);
      
      // Salvar tudo localmente imediatamente
      await _salvarTodosDados(aguardarSupabase: false, isSync: true);

      print('>>> [Sync] ✅ Download do Supabase concluído com sucesso!');
    } catch (e) {
      print('>>> [Sync] ❌ Erro ao baixar dados do Supabase: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
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
      // Se o usuário (responsável) já tiver um caixa aberto, retorna o dele.
      // Cada usuário da empresa pode ter o SEU próprio caixa aberto.
      // Fallback para o email do usuário logado garante que a abertura seja
      // gravada com o responsável correto (persiste após reiniciar).
      final respEfetivo = responsavel ?? _responsavelAtivo ?? _usuarioAtualEmail;
      if (respEfetivo != null && respEfetivo.isNotEmpty) {
        final caixaExistente = aberturaCaixaDoResponsavel(respEfetivo);
        if (caixaExistente != null) {
          _caixaAberto = true;
          return caixaExistente;
        }
      } else if (caixaAberto && aberturaCaixaAtual != null) {
        // Compatibilidade: sem responsável definido, mantém o caixa atual
        return aberturaCaixaAtual!;
      }

      final numeroCaixa = getProximoNumeroCaixa();

      final abertura = AberturaCaixa(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        numero: numeroCaixa,
        dataAbertura: DateTime.now(),
        valorInicial: valorInicial,
        observacao: observacao,
        responsavel: respEfetivo,
      );

      _aberturasCaixa.add(abertura);
      _caixaAberto = true;
      _marcarSujo(LocalStorageService.keyAberturasCaixa);
      

      
      // Salvar lista de aberturas imediatamente com persistência forçada
      try {
        await _salvarAberturaCaixaImediatamente();
      } catch (e) {
        print('>>> Erro ao salvar abertura do caixa: $e');
      }
      
      // Sincronizar com Supabase
      debugPrint('>>> [Caixa] ☁️ Sincronizando abertura com Supabase...');
      debugPrint('>>> [Caixa]    ID: ${abertura.id}');
      debugPrint('>>> [Caixa]    Supabase disponível: ${SupabaseService.isAvailable}');
      await _upsertNoSupabase(SupabaseService.tableAberturasCaixa, abertura.toMap());
      
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
    AberturaCaixa? abertura,
  }) async {
    print('>>> [registrarFechamentoCaixa] Iniciando...');
    print('>>> [registrarFechamentoCaixa] Valor esperado: $valorEsperado');
    print('>>> [registrarFechamentoCaixa] Valor real: $valorReal');
    print('>>> [registrarFechamentoCaixa] Responsável: $responsavel');
    
    final aberturaUsada = abertura ?? aberturaCaixaAtual;
    if (aberturaUsada == null) {
      print('>>> [registrarFechamentoCaixa] ERRO: Não há abertura de caixa!');
      debugPrint('>>> Aviso: tentar fechar caixa sem abertura');
      return null;
    }
    
    print('>>> [registrarFechamentoCaixa] Abertura encontrada: ${aberturaUsada.numero}');

    final diff = diferenca ?? (valorReal - valorEsperado);
    print('>>> [registrarFechamentoCaixa] Diferença calculada: $diff');

    // Obter sangrias e suprimentos do caixa em questão
    final sangriasCaixaAtual = getSangriasDoCaixa(aberturaUsada);
    final suprimentosCaixaAtual = getSuprimentosDoCaixa(aberturaUsada);
    
    print('>>> [registrarFechamentoCaixa] Sangrias: ${sangriasCaixaAtual.length}');
    print('>>> [registrarFechamentoCaixa] Suprimentos: ${suprimentosCaixaAtual.length}');

    final fechamento = FechamentoCaixa(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      aberturaCaixaId: aberturaUsada.id,
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
    _marcarSujo(LocalStorageService.keyFechamentosCaixa);
    
    print('>>> [registrarFechamentoCaixa] Salvando fechamento com persistência ROBUSTA...');
    // Salvar fechamento imediatamente com persistência forçada
    try {
      await _salvarFechamentoCaixaImediatamente(fechamento);
      print('>>> [registrarFechamentoCaixa] ✓ Fechamento persistido com sucesso!');
    } catch (e, stackTrace) {
      print('>>> [registrarFechamentoCaixa] ⚠️ Erro ao salvar fechamento: $e');
      print('>>> [registrarFechamentoCaixa] StackTrace: $stackTrace');
      print('>>> [registrarFechamentoCaixa] ✓ Continuando - dados já estão no localStorage');
    }
    
    notifyListeners();
    print('>>> [registrarFechamentoCaixa] ✓ Caixa fechado e salvo!');
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
      aberturaCaixaId: abertura.id,
      data: DateTime.now(),
      valor: valor,
      motivo: motivo,
      observacao: observacao,
      responsavel: responsavel ?? _responsavelAtivo,
    );

    _sangrias.add(sangria);
    _marcarSujo(LocalStorageService.keySangrias);
    
    try {
      await salvarImediatamente();
    } catch (e) {
      print('>>> Erro ao salvar sangria: $e');
    }
    
    await _upsertNoSupabase(SupabaseService.tableSangrias, sangria.toMap());
    
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
      aberturaCaixaId: abertura.id,
      data: DateTime.now(),
      valor: valor,
      motivo: motivo,
      observacao: observacao,
      responsavel: responsavel ?? _responsavelAtivo,
    );

    _suprimentos.add(suprimento);
    _marcarSujo(LocalStorageService.keySuprimentos);
    
    try {
      await salvarImediatamente();
    } catch (e) {
      print('>>> Erro ao salvar suprimento: $e');
    }
    
    await _upsertNoSupabase(SupabaseService.tableSuprimentos, suprimento.toMap());
    
    notifyListeners();
    print('>>> Suprimento registrado: R\$ ${valor.toStringAsFixed(2)} - $motivo');
    return suprimento;
  }

  /// Obtém as sangrias do caixa atual (aberto)
  List<SangriaCaixa> getSangriasCaixaAtual() {
    final abertura = aberturaCaixaAtual;
    if (abertura == null) return [];
    return getSangriasDoCaixa(abertura);
  }

  /// Obtém as sangrias de um caixa específico (por abertura)
  List<SangriaCaixa> getSangriasDoCaixa(AberturaCaixa abertura) {
    // Limite superior: fechamento do caixa (se encerrado) — evita que sangrias
    // feitas depois (de outro caixa) vazem para caixas anteriores.
    DateTime? dataFechamento;
    for (final f in _fechamentosCaixa) {
      if (f.aberturaCaixaId == abertura.id) {
        dataFechamento = f.dataFechamento;
        break;
      }
    }

    return _sangrias.where((s) {
      // Sangrias com vínculo explícito à abertura
      if (s.aberturaCaixaId != null && s.aberturaCaixaId!.isNotEmpty) {
        return s.aberturaCaixaId == abertura.id;
      }
      // Registros antigos sem vínculo: usa a janela [abertura, fechamento]
      if (s.data.isBefore(abertura.dataAbertura)) return false;
      if (dataFechamento != null && s.data.isAfter(dataFechamento)) return false;
      return true;
    }).toList();
  }

  /// Obtém os suprimentos do caixa atual (aberto)
  List<SuprimentoCaixa> getSuprimentosCaixaAtual() {
    final abertura = aberturaCaixaAtual;
    if (abertura == null) return [];
    return getSuprimentosDoCaixa(abertura);
  }

  /// Obtém os suprimentos de um caixa específico (por abertura)
  List<SuprimentoCaixa> getSuprimentosDoCaixa(AberturaCaixa abertura) {
    // Limite superior: fechamento do caixa (se encerrado).
    DateTime? dataFechamento;
    for (final f in _fechamentosCaixa) {
      if (f.aberturaCaixaId == abertura.id) {
        dataFechamento = f.dataFechamento;
        break;
      }
    }

    return _suprimentos.where((s) {
      if (s.aberturaCaixaId != null && s.aberturaCaixaId!.isNotEmpty) {
        return s.aberturaCaixaId == abertura.id;
      }
      // Registros antigos sem vínculo: usa a janela [abertura, fechamento]
      if (s.data.isBefore(abertura.dataAbertura)) return false;
      if (dataFechamento != null && s.data.isAfter(dataFechamento)) return false;
      return true;
    }).toList();
  }

  /// Compara se dois identificadores de operador/responsável se referem à
  /// mesma pessoa, tolerando diferenças de formato (email vs nome, maiúsculas,
  /// acentos, espaços). Ex.: 'carlos@gmail.com' bate com 'Carlos' ou 'carlos'.
  bool _ehMesmoOperador(String? a, String? b) {
    if (a == null || b == null) return false;
    String normalizar(String s) => s
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9@]'), '');
    final na = normalizar(a);
    final nb = normalizar(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    // Prefixo local do email: 'carlos@gmail.com' vs 'carlos'
    final localA = na.contains('@') ? na.split('@').first : na;
    final localB = nb.contains('@') ? nb.split('@').first : nb;
    return localA == localB && (localA.isNotEmpty);
  }

  /// Obtém as vendas vinculadas a um caixa específico.
  ///
  /// Filtra por DOIS critérios combinados:
  /// 1. Janela de tempo do caixa: [dataAbertura, dataFechamento]. Quando o
  ///    caixa está fechado, o limite SUPERIOR é a data do fechamento — sem isso,
  ///    vendas de caixas posteriores "vazavam" para caixas já encerrados.
  /// 2. Operador: se o caixa tem responsável E a venda tem operador, exige que
  ///    sejam a mesma pessoa (nome ou email — ver [_ehMesmoOperador]). Se a
  ///    venda não tem operador, NÃO a atribui a caixas nominados — evita que
  ///    vendas sem operador "apareçam do nada" no caixa de outro usuário.
  List<VendaBalcao> getVendasDoCaixa(AberturaCaixa abertura) {
    final responsavel = abertura.responsavel?.trim().toLowerCase();
    final temResponsavel = responsavel != null && responsavel.isNotEmpty;

    // Limite superior: fechamento do caixa (se estiver encerrado).
    DateTime? dataFechamento;
    for (final f in _fechamentosCaixa) {
      if (f.aberturaCaixaId == abertura.id) {
        dataFechamento = f.dataFechamento;
        break;
      }
    }

    return _vendasBalcao.where((v) {
      if (v.isCancelada) return false;

      // Janela inferior: venda deve ser depois da abertura do caixa.
      if (v.dataVenda.isBefore(abertura.dataAbertura)) return false;
      // Janela superior: venda deve ser antes do fechamento (se encerrado).
      if (dataFechamento != null && v.dataVenda.isAfter(dataFechamento)) return false;

      final operador = v.operador;
      final temOperador = operador != null && operador.trim().isNotEmpty;

      // Caixa nominado: só vendas do MESMO operador entram.
      if (temResponsavel && temOperador) {
        return _ehMesmoOperador(operador, responsavel);
      }
      // Caixa nominado com venda sem operador: NÃO pertence a este caixa
      // (evita misturar vendas de outro usuário no caixa do carlos).
      if (temResponsavel && !temOperador) {
        return false;
      }
      // Caixa antigo sem responsável: mantém compatibilidade (janela de tempo).
      return true;
    }).toList();
  }

  /// Calcula o saldo de um caixa específico (inicial + vendas + suprimentos - sangrias)
  double calcularSaldoDoCaixa(AberturaCaixa abertura) {
    final vendas = getVendasDoCaixa(abertura).fold(0.0, (sum, v) => sum + v.valorTotal);
    final sangrias = getSangriasDoCaixa(abertura).fold(0.0, (sum, s) => sum + s.valor);
    final suprimentos = getSuprimentosDoCaixa(abertura).fold(0.0, (sum, s) => sum + s.valor);
    return abertura.valorInicial + vendas + suprimentos - sangrias;
  }

  /// Salva a lista de aberturas de caixa imediatamente sem debounce
  /// Garante que o caixa persistirá entre reinicializações do app
  Future<void> _salvarAberturaCaixaImediatamente() async {
    try {
      print('>>> [Caixa] 💾 Salvando aberturas de caixa imediatamente...');
      
      // 1. Salvar localmente em localStorage com company scope
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyAberturasCaixa),
          _aberturasCaixa,
        );
        print('>>> [Caixa] ✅ Aberturas salvas localmente (total: ${_aberturasCaixa.length})');
      } catch (e) {
        print('>>> [Caixa] ❌ Erro ao salvar localmente: $e');
        rethrow;
      }

      // 2. Status do caixa é calculado dinamicamente via PostgreSQL (aberturaCaixaAtual)

      // 3. Salvar também as fechamentos (para manter histórico completo)
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyFechamentosCaixa),
          _fechamentosCaixa,
        );
        print('>>> [Caixa] ✅ Fechamentos salvo (total: ${_fechamentosCaixa.length})');
      } catch (e) {
        print('>>> [Caixa] ⚠️ Erro ao salvar fechamentos: $e');
        // Continuar mesmo se falhar
      }

      await _upsertNoSupabase(SupabaseService.tableAberturasCaixa, aberturaCaixaAtual!.toMap());

      print('>>> [Caixa] ✓ Salvamento completo finalizado com sucesso!');
    } catch (e, stackTrace) {
      print('>>> [Caixa] ❌ ERRO CRÍTICO ao salvar aberturas: $e');
      print('>>> [Caixa] StackTrace: $stackTrace');
      rethrow; // Re-throw para que o caller saiba que houve erro crítico
    }
  }

  /// Salva o fechamento de caixa imediatamente sem debounce
  /// Garante que o fechamento persistirá entre reinicializações do app
  Future<void> _salvarFechamentoCaixaImediatamente(FechamentoCaixa fechamento) async {
    try {
      print('>>> [Caixa] 💾 Salvando fechamento de caixa imediatamente...');
      print('>>> [Caixa]     ID: ${fechamento.id}');
      print('>>> [Caixa]     Abertura: ${fechamento.aberturaCaixaId}');
      
      // 1. Salvar localmente em localStorage com company scope
      try {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyFechamentosCaixa),
          _fechamentosCaixa,
        );
        print('>>> [Caixa] ✅ Fechamento salvo localmente (total: ${_fechamentosCaixa.length})');
      } catch (e) {
        print('>>> [Caixa] ❌ Erro ao salvar fechamento localmente: $e');
        rethrow;
      }

      // 2. Status do caixa calculado dinamicamente via PostgreSQL

      await _upsertNoSupabase(SupabaseService.tableFechamentosCaixa, fechamento.toMap());

      print('>>> [Caixa] ✓ Salvamento de fechamento concluído com sucesso!');
    } catch (e, stackTrace) {
      print('>>> [Caixa] ❌ ERRO CRÍTICO ao salvar fechamento: $e');
      print('>>> [Caixa] StackTrace: $stackTrace');
      rethrow; // Re-throw para que o caller saiba que houve erro crítico
    }
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
  List<Servico> get servicos => tiposServico;
  List<Funcionario> get funcionarios => _funcionarios;
  List<Entrega> get entregas => _entregas;
  List<Romaneio> get romaneios => _romaneios;
  List<PerfilTributario> get perfisTributarios => _perfisTributarios;

  List<Departamento> get departamentos => List.unmodifiable(_departamentos);

  /// Retorna o departamento pelo ID (ou null se não existir).
  Departamento? departamentoPorId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final d in _departamentos) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Nome legível do departamento pelo ID (fallback: o próprio id).
  String nomeDepartamento(String? id) {
    final dep = departamentoPorId(id);
    return dep?.nome ?? (id == null ? '' : id);
  }

  /// CRT atual da empresa (1=Simples, 2=Simples excesso, 3=Regime Normal)
  int get crtEmpresaAtual {
    final emp = _empresaAtual;
    if (emp == null) return 1;
    final crtConfig = emp.configuracoes?['crt'];
    final crtInt = int.tryParse(crtConfig?.toString() ?? '');
    if (crtInt != null && crtInt >= 1 && crtInt <= 3) return crtInt;
    return emp.crt ?? 1;
  }

  /// Se a empresa está em regime Simples Nacional (CRT 1 ou 2)
  bool get empresaRegimeSimples => crtEmpresaAtual == 1 || crtEmpresaAtual == 2;

  /// Perfis tributários filtrados pelo regime tributário atual da empresa.
  /// Simples Nacional (CRT 1/2) -> perfis com CSOSN. Regime Normal (CRT 3) -> perfis com CST.
  List<PerfilTributario> get perfisTributariosDoRegime {
    if (empresaRegimeSimples) {
      return _perfisTributarios
          .where((p) => p.csosn != null && p.csosn!.trim().isNotEmpty)
          .toList();
    }
    return _perfisTributarios
        .where((p) => p.icmsCst != null && p.icmsCst!.trim().isNotEmpty)
        .toList();
  }
  
  DateTime? get ultimaValidacaoOnline => _ultimaValidacaoOnline;
  DateTime? get ultimaDataExecucao => _ultimaDataExecucao;
  bool get liberacaoProvisoriaAtiva => _liberacaoProvisoriaAtiva;
  
  String? get responsavelAtivo => _responsavelAtivo;
  set responsavelAtivo(String? valor) {
    _responsavelAtivo = valor;
  }
  List<Motorista> get motoristas => _motoristas;
  List<TaxaEntrega> get taxasEntrega => _taxasEntrega;
  List<LinkVendedor> get linksVendedores => _linksVendedores;
  List<ComissaoVendedor> get comissoesVendedores => _comissoesVendedores;

  /// Busca produtos no PostgreSQL de forma otimizada para Windows
  Future<List<Produto>> buscarProdutosSQL(String termo) async {
    if (termo.isEmpty) return produtos;
    
    if (kIsWeb) {
      return _produtos.where((p) => 
        p.nome.toLowerCase().contains(termo.toLowerCase()) || 
        (p.codigo?.toLowerCase().contains(termo.toLowerCase()) ?? false)
      ).toList();
    }

    try {
      final results = await DatabaseService().buscarProdutos(termo);
      return results.map((m) => Produto.fromMap(m)).toList();
    } catch (e) {
      debugPrint('>>> [DataService] Erro ao buscar no PostgreSQL: $e');
      return [];
    }
  }
  List<ContaPagar> get contasPagar => _contasPagar;
  List<AgendamentoServico> get agendamentosServico {
    final ids = <String>{};
    return _agendamentosServico.where((a) => ids.add(a.id)).toList();
  }

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
  // 4. Salvar IMEDIATAMENTE no Supabase usando o método upsert do SupabaseService:
  //    if (SupabaseService.isAvailable && _currentEmpresaId != null) {
  //      _supabaseService.upsert(SupabaseService.table[Entidade], item.toMap()).catchError((e) {
  //        debugPrint('>>> Erro ao salvar [entidade] no Supabase: $e');
  //        _adicionarSincronizacaoPendente();
  //      });
  //    }
  // 
  // 5. Para métodos de remoção, usar delete do SupabaseService
  // 
  // IMPORTANTE: Criar o método individual no SupabaseService ANTES de usar!
  // Exemplo: salvarCliente, salvarProduto, salvarFuncionario, etc.
  // ======================================

  Cliente? getClienteById(String id) {
    try {
      return _clientes.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

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
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableClientes, cliente.toMap());
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
      
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(SupabaseService.tableClientes, cliente.toMap());
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
      
      if (agendamentosParaAtualizar.isNotEmpty) {
        for (final agendamento in agendamentosParaAtualizar) {
          _upsertNoSupabase(SupabaseService.tableAgendamentosServico, agendamento.toMap());
        }
      }
    }
  }

  void deleteCliente(String id) {
    _clientes.removeWhere((c) => c.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tableClientes, {'id': id}, evento: 'DELETE');
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
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableFuncionarios, funcionario.toMap());
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
      
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(SupabaseService.tableFuncionarios, funcionario.toMap());
    }
  }

  void deleteFuncionario(String id) {
    _funcionarios.removeWhere((f) => f.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tableFuncionarios, {'id': id}, evento: 'DELETE');
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
    
    await _upsertNoSupabase(SupabaseService.tableLinksVendedores, link.toMap());
  }

  Future<void> updateLinkVendedor(LinkVendedor link) async {
    final index = _linksVendedores.indexWhere((l) => l.id == link.id);
    if (index != -1) {
      _linksVendedores[index] = link;
      notifyListeners();
      await _salvarTodosDados();
      await _upsertNoSupabase(SupabaseService.tableLinksVendedores, link.toMap());
    }
  }

  void deleteLinkVendedor(String id) {
    _linksVendedores.removeWhere((l) => l.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover imediatamente do Supabase
    if (SupabaseService.isAvailable && _currentEmpresaId != null) {
      _supabaseService.delete(SupabaseService.tableLinksVendedores, id).catchError((e) {
        debugPrint('>>> Erro ao remover link de vendedor do Supabase: $e');
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
    
    await _upsertNoSupabase(SupabaseService.tableComissoesVendedores, comissao.toMap());
  }

  Future<void> updateComissaoVendedor(ComissaoVendedor comissao) async {
    final index = _comissoesVendedores.indexWhere((c) => c.id == comissao.id);
    if (index != -1) {
      _comissoesVendedores[index] = comissao;
      notifyListeners();
      _marcarSujo(LocalStorageService.keyComissoesVendedores);
      await _upsertNoSupabase(SupabaseService.tableComissoesVendedores, comissao.toMap());
    }
  }

  void deleteComissaoVendedor(String id) {
    _comissoesVendedores.removeWhere((c) => c.id == id);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyComissoesVendedores);
    enviarMudancaParaSupabase(SupabaseService.tableComissoesVendedores, {'id': id}, evento: 'DELETE');
  }

  // ============ CRUD ContaPagar ============

  Future<void> addContaPagar(ContaPagar conta) async {
    _contasPagar.add(conta);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyContasPagar);
    await _upsertNoSupabase(SupabaseService.tableContasPagar, conta.toMap());
  }

  Future<void> updateContaPagar(ContaPagar conta) async {
    final index = _contasPagar.indexWhere((c) => c.id == conta.id);
    if (index != -1) {
      _contasPagar[index] = conta;
      notifyListeners();
      _salvarAutomaticamente(); // Geralmente é um Future que não esperamos aqui ou aguardamos
      await _upsertNoSupabase(SupabaseService.tableContasPagar, conta.toMap());
    }
  }

  /// Busca um cliente por telefone (procura localmente e no Supabase)
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

    // 2. Se tem Supabase, buscar SEMPRE no Supabase também para garantir dados frescos (pets, endereço)
    if (SupabaseService.isAvailable && _currentEmpresaId != null) {
      debugPrint('>>> [DataService] 🔍 Buscando no Supabase por telefone: $normalizado');
      try {
        final response = await _supabaseService.client
            .from(SupabaseService.tableClientes)
            .select()
            .eq('empresa_id', _currentEmpresaId!)
            .or('telefone.eq.$normalizado,telefone2.eq.$normalizado,whatsapp.eq.$normalizado');
        
        final List<dynamic> remotosData = response;
        if (remotosData.isNotEmpty) {
          for (final map in remotosData) {
            final c = Cliente.fromMap(map as Map<String, dynamic>);
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
        debugPrint('>>> [DataService] Erro na busca remota Supabase: $e');
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
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tableContasPagar, {'id': id}, evento: 'DELETE');
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

  Future<void> addProduto(Produto produto, {bool registrarHistorico = true, String? usuarioId, String? usuarioNome, String? usuarioEmail}) async {
    // Garantir ID único e não vazio
    if (produto.id.isEmpty) {
      produto = produto.copyWith(id: uuid.v4());
    }
    final index = _produtos.indexWhere((p) => p.id == produto.id);
    final isNovo = index == -1;
    
    if (isNovo) {
      _produtos.add(produto);
    } else {
      _produtos[index] = produto;
    }
    
    notifyListeners();
    _marcarSujo(LocalStorageService.keyProdutos);
    
    // 1. Salvar imediatamente no PostgreSQL local (primeiro o upsert rápido para visibilidade imediata, depois a lista completa)
    try {
      await DatabaseService().upsertItem(LocalStorageService.keyProdutos, produto.toMap());
      DatabaseService().salvarLista(LocalStorageService.keyProdutos, 
          _produtos.map((p) => p.toMap()).toList()).catchError((e) {
        debugPrint('>>> [DataService] ⚠️ Erro ao salvar lista de produtos no PostgreSQL: $e');
      });
      debugPrint('>>> [DataService] 💾 Novo produto ${produto.nome} (preço: ${produto.preco}) salvo no PostgreSQL');
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao salvar novo produto no PostgreSQL: $e');
    }

    // 2. Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableProdutos, produto.toMap());
    
    // Registrar histórico de criação (apenas para produtos novos E alteração local)
    if (registrarHistorico && isNovo) {
      await _registrarHistoricoProduto(
        produtoAntigo: Produto(
          id: produto.id,
          nome: '',
          unidade: '',
          grupo: '',
          preco: 0,
          estoque: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        produtoNovo: produto,
        tipoOperacao: 'CREATE',
        usuarioId: usuarioId,
        usuarioNome: usuarioNome,
        usuarioEmail: usuarioEmail,
      );
    }
  }

  /// Adiciona ou atualiza múltiplos produtos em uma única operação (Batch)
  Future<void> addProdutosLote(List<Produto> novosProdutos) async {
    if (novosProdutos.isEmpty) return;
    
    // Garantir ID único e não vazio para todos os produtos
    final List<Produto> processados = [];
    for (var p in novosProdutos) {
      if (p.id.isEmpty) {
        p = p.copyWith(id: uuid.v4());
      }
      processados.add(p);
    }
    
    debugPrint('>>> [DataService] 📦 Processando lote de ${processados.length} produtos...');

    // 1. Atualizar lista local - OTIMIZADO: Usar Map para O(N) em vez de O(N^2)
    final Map<String, int> existingMap = {
      for (int i = 0; i < _produtos.length; i++) _produtos[i].id: i
    };
    
    for (final p in processados) {
      final index = existingMap[p.id];
      if (index != null) {
        _produtos[index] = p;
      } else {
        _produtos.add(p);
        existingMap[p.id] = _produtos.length - 1;
      }
    }

    // 2. Salvar no PostgreSQL (Banco Local) - PERSISTÊNCIA MANUAL
    try {
      final dataList = processados.map((p) => p.toMap()).toList();
      await DatabaseService().adicionarProdutosLote(dataList);
      debugPrint('>>> [DataService] 🏛️ Lote persistido no PostgreSQL local.');
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao persistir lote no PostgreSQL: $e');
    }

    // 3. Salvar no Supabase (Cloud)
    if (SupabaseService.isAvailable && _currentEmpresaId != null && processados.length <= 100) {
      final dataList = processados.map((p) => p.toMap()).toList();
      debugPrint('>>> [DataService] ☁️ Enviando lote para Supabase: empresa=$currentEmpresaId, itens=${dataList.length}');
      try {
        await _supabaseService.upsertLote(SupabaseService.tableProdutos, dataList)
            .timeout(const Duration(minutes: 5));
        
        debugPrint('>>> [DataService] ✅ Sincronização com Supabase concluída.');
      } catch (e) {
        debugPrint('>>> ❌ Erro ao sincronizar lote com Supabase: $e');
        _adicionarSincronizacaoPendente();
      }
    } else if (processados.length > 100) {
      debugPrint('>>> [DataService] ℹ️ Lote grande (${processados.length} itens). Sincronização com nuvem adiada conforme solicitado.');
      _adicionarSincronizacaoPendente(); // Marcar que precisa sincronizar depois
    }

    // 3. Persistir localmente e notificar UI uma única vez
    _marcarSujo(LocalStorageService.keyProdutos);
    notifyListeners();
    debugPrint('>>> [DataService] ✅ Lote concluído.');
  }

  // ============================================================
  // HISTÓRICO DE ALTERAÇÕES DE PRODUTOS (AUDITORIA)
  // ============================================================

  /// Registra uma alteração no histórico de produtos
  /// Chamado automaticamente pelo updateProduto quando há mudanças
  Future<void> _registrarHistoricoProduto({
    required Produto produtoAntigo,
    required Produto produtoNovo,
    required String tipoOperacao,
    String? usuarioId,
    String? usuarioNome,
    String? usuarioEmail,
    String? motivo,
    String? observacao,
  }) async {
    try {
      // Comparar produtos e identificar campos alterados
      final mapAntigo = produtoAntigo.toMap();
      final mapNovo = produtoNovo.toMap();
      final camposAlterados = ProdutoHistorico.compararProdutos(mapAntigo, mapNovo);

      // Se não houver campos alterados, não registrar
      if (camposAlterados.isEmpty && tipoOperacao == 'UPDATE') {
        return;
      }

      // Criar mapas apenas com campos alterados para economizar espaço
      final valoresAnteriores = <String, dynamic>{};
      final valoresNovos = <String, dynamic>{};
      
      for (final campo in camposAlterados) {
        valoresAnteriores[campo] = mapAntigo[campo];
        valoresNovos[campo] = mapNovo[campo];
      }

      if (motivo != null) {
        valoresNovos['_motivo'] = motivo;
      }
      if (observacao != null) {
        valoresNovos['_observacao'] = observacao;
      }

      // Gerar resumo das mudanças
      var resumo = ProdutoHistorico.gerarResumoMudancas(
        valoresAnteriores,
        valoresNovos,
        camposAlterados,
      );
      
      if (motivo != null || observacao != null) {
        final extras = [if (motivo != null) 'Motivo: $motivo', if (observacao != null) 'Obs: $observacao'];
        resumo = (resumo ?? '') + '\n' + extras.join(' | ');
      }

      // Criar o registro de histórico
      final historico = ProdutoHistorico(
        id: const Uuid().v4(),
        produtoId: produtoNovo.id,
        produtoNome: produtoNovo.nome,
        produtoCodigo: produtoNovo.codigo,
        usuarioId: usuarioId ?? _usuarioAtualId ?? 'sistema',
        usuarioNome: usuarioNome ?? _usuarioAtualNome ?? 'Sistema',
        usuarioEmail: usuarioEmail ?? _usuarioAtualEmail,
        tipoOperacao: tipoOperacao,
        camposAlterados: camposAlterados,
        valoresAnteriores: valoresAnteriores,
        valoresNovos: valoresNovos,
        resumoMudancas: resumo,
        dataAlteracao: DateTime.now(),
        empresaId: _currentEmpresaId ?? '',
      );

      // Salvar no PostgreSQL local (garantir empresaId definido)
      final dbService = DatabaseService();
      if (_currentEmpresaId != null && _currentEmpresaId!.isNotEmpty) {
        dbService.setEmpresaId(_currentEmpresaId!);
      }
      dbService.salvarHistoricoProduto(historico.toMap()).catchError((e) {
        debugPrint('>>> [DataService] ⚠️ Erro ao salvar histórico no PostgreSQL: $e');
      });

      // Sincronizar com Supabase em segundo plano
      final supabaseMap = historico.toSupabaseMap();
      _upsertNoSupabase('produto_historico', supabaseMap).catchError((e) {
        debugPrint('>>> [DataService] ⚠️ Erro ao sincronizar histórico: $e');
      });

      debugPrint('>>> [DataService] 📋 Histórico registrado: ${produtoNovo.nome} - ${camposAlterados.join(', ')}');
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao registrar histórico: $e');
      // Não propagar erro - histórico é opcional
    }
  }

  /// Busca o histórico de alterações de um produto específico.
  /// Tenta o banco local primeiro; se estiver vazio, busca no Supabase
  /// (garante que a entrada apareça mesmo se o banco local não tiver registros).
  Future<List<ProdutoHistorico>> buscarHistoricoProduto(String produtoId, {int limite = 50}) async {
    try {
      final dbService = DatabaseService();
      if (_currentEmpresaId != null && _currentEmpresaId!.isNotEmpty) {
        dbService.setEmpresaId(_currentEmpresaId!);
      }
      // Timeout para não travar a tela "Carregando histórico..." quando o
      // banco local está indisponível (conexão lenta/falhando).
      final resultados = await dbService
          .buscarHistoricoProduto(produtoId, limite: limite)
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () => <Map<String, dynamic>>[],
          );
      if (resultados.isNotEmpty) {
        return resultados.map((m) => ProdutoHistorico.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao buscar histórico no banco local: $e');
    }

    // Fallback: Supabase (banco local vazio/desatualizado)
    try {
      if (SupabaseService.isAvailable && _currentEmpresaId != null && _currentEmpresaId!.isNotEmpty) {
        final rows = await _supabaseService.client
            .from('produto_historico')
            .select()
            .eq('produto_id', produtoId)
            .eq('empresa_id', _currentEmpresaId!)
            .order('data_alteracao', ascending: false)
            .limit(limite);
        if (rows != null && rows.isNotEmpty) {
          return rows.map((map) => ProdutoHistorico.fromMap(map)).toList();
        }
      }
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao buscar histórico no Supabase: $e');
    }
    return [];
  }

  /// Busca todo o histórico da empresa
  Future<List<ProdutoHistorico>> buscarHistoricoGeral({int limite = 100, DateTime? dataInicio, DateTime? dataFim}) async {
    try {
      final dbService = DatabaseService();
      if (_currentEmpresaId != null && _currentEmpresaId!.isNotEmpty) {
        dbService.setEmpresaId(_currentEmpresaId!);
      }
      final resultados = await dbService.buscarHistoricoGeral(
        limite: limite,
        dataInicio: dataInicio,
        dataFim: dataFim,
      );
      return resultados.map((m) => ProdutoHistorico.fromMap(m)).toList();
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao buscar histórico geral: $e');
      return [];
    }
  }

  // ============================================================

  Future<void> updateProduto(Produto produto, {bool aguardarSincronia = true, bool registrarMovimento = true, bool notify = true, bool registrarHistorico = true, String? usuarioId, String? usuarioNome, String? usuarioEmail, String? motivoHistorico, String? observacaoHistorico}) async {
    if (produto.id.isEmpty) {
      debugPrint('>>> [DataService] ⚠️ Tentativa de atualizar produto com ID vazio abortada.');
      return;
    }
    final index = _produtos.indexWhere((p) => p.id == produto.id);
    if (index != -1) {
      // Guardar produto antigo para histórico
      final produtoAntigo = _produtos[index];

      // Registrar movimento de estoque se houver mudança na quantidade
      if (registrarMovimento && produto.estoque != produtoAntigo.estoque) {
        final diferenca = produto.estoque - produtoAntigo.estoque;
        registrarSaidaEstoque(
          produtoId: produto.id,
          quantidade: diferenca.abs(),
          motivo: diferenca < 0 ? 'saida' : 'ajuste',
          observacao: diferenca < 0 ? 'Saída via edição' : 'Ajuste via edição',
          usuario: usuarioNome ?? 'sistema',
          notify: false,
        );
      }

      // Verificar se há mudanças para registrar no histórico
      final mapAntigo = produtoAntigo.toMap();
      final mapNovo = produto.toMap();
      final camposAlterados = ProdutoHistorico.compararProdutos(mapAntigo, mapNovo);

      // Atualizar o produto na lista
      _produtos[index] = produto;
      if (notify) notifyListeners();
      _marcarSujo(LocalStorageService.keyProdutos);

      // 1. Salvar imediatamente no PostgreSQL local (apenas o registro alterado via upsert rápido)
      DatabaseService().upsertItem(LocalStorageService.keyProdutos, produto.toMap());

      // 2. Sincronizar com Supabase em segundo plano
      debugPrint('>>> [DataService] ☁️ Sincronizando produto com Supabase (segundo plano)...');
      enviarMudancaParaSupabase(SupabaseService.tableProdutos, produto.toMap());

      // 3. Registrar histórico de alterações em segundo plano
      if (registrarHistorico && camposAlterados.isNotEmpty) {
        _registrarHistoricoProduto(
          produtoAntigo: produtoAntigo,
          produtoNovo: produto,
          tipoOperacao: 'UPDATE',
          usuarioId: usuarioId,
          usuarioNome: usuarioNome,
          usuarioEmail: usuarioEmail,
          motivo: motivoHistorico,
          observacao: observacaoHistorico,
        );
      }
      
      // 4. Forçar notificação extra para garantir que todos os listeners sejam atualizados
      if (notify) {
        Future.delayed(const Duration(milliseconds: 100), () {
          notifyListeners();
        });
      }
    }
  }

  Future<void> deleteProduto(String id, {bool registrarHistorico = true, String? usuarioId, String? usuarioNome, String? usuarioEmail}) async {
    // Buscar produto antes de remover para histórico
    final produtoRemovido = _produtos.firstWhere((p) => p.id == id, orElse: () => Produto(
      id: id,
      nome: 'Produto desconhecido',
      unidade: '',
      grupo: '',
      preco: 0,
      estoque: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    
    _produtos.removeWhere((p) => p.id == id);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyProdutos);
    
    // Registrar histórico de exclusão (apenas se for alteração local)
    if (registrarHistorico) {
      await _registrarHistoricoProduto(
        produtoAntigo: produtoRemovido,
        produtoNovo: Produto(
          id: id,
          nome: produtoRemovido.nome,
          unidade: produtoRemovido.unidade,
          grupo: produtoRemovido.grupo,
          preco: produtoRemovido.preco,
          estoque: produtoRemovido.estoque,
          createdAt: produtoRemovido.createdAt,
          updatedAt: DateTime.now(),
        ),
        tipoOperacao: 'DELETE',
        usuarioId: usuarioId,
        usuarioNome: usuarioNome,
        usuarioEmail: usuarioEmail,
      );
    }
    
    if (SupabaseService.isAvailable && _currentEmpresaId != null) {
      _supabaseService.delete(SupabaseService.tableProdutos, id).catchError((e) {
        debugPrint('>>> Erro ao remover produto do Supabase: $e');
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
    
    if (_currentEmpresaId == null) {
      throw Exception('⚠️ Nenhuma empresa selecionada');
    }
    
    final empresaId = _currentEmpresaId!;
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
    
    // Deletar do Supabase primeiro se estiver habilitado
    if (SupabaseService.isAvailable) {
      try {
        await _supabaseService.deleteFiltered(SupabaseService.tableProdutos, {'empresa_id': empresaId});
        debugPrint('>>> [DataService] Todos os produtos deletados do Supabase');
      } catch (e) {
        debugPrint('>>> [DataService] ⚠️ Erro ao deletar produtos do Supabase: $e');
        _adicionarSincronizacaoPendente();
      }
    }
    
    // Limpar lista local
    _produtos.clear();
    notifyListeners();
    
    await _salvarTodosDados();
    debugPrint('>>> [DataService] Todos os produtos deletados localmente e do Supabase');
    print('>>> ✅ Operação concluída. Backup disponível em: backup_produtos_${empresaId}_*');
  }

   Produto? getProdutoById(String id) {
    try {
      return _produtos.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  // ============ Lotes de Produtos (Validade) ============

  /// Lotes de um produto específico (ordenados por validade - FEFO)
  List<LoteProduto> lotesDoProduto(String produtoId) {
    final lotes = _lotesProdutos
        .where((l) => l.produtoId == produtoId)
        .toList();
    // FEFO: primeiro os que vencem antes; lotes sem validade vão para o fim
    lotes.sort((a, b) {
      final aVal = a.dataValidade;
      final bVal = b.dataValidade;
      if (aVal == null && bVal == null) return 0;
      if (aVal == null) return 1;
      if (bVal == null) return -1;
      return aVal.compareTo(bVal);
    });
    return lotes;
  }

  /// Data de validade mais próxima (ou vencida) entre os lotes com estoque do produto
  DateTime? proximaValidade(String produtoId) {
    final lotes = lotesDoProduto(produtoId).where((l) => l.quantidade > 0).toList();
    if (lotes.isEmpty) return null;
    final comValidade = lotes.where((l) => l.dataValidade != null).toList();
    if (comValidade.isEmpty) return null;
    comValidade.sort((a, b) => a.dataValidade!.compareTo(b.dataValidade!));
    return comValidade.first.dataValidade;
  }

  /// Quantidade de produtos com lotes vencidos ou vencendo em X dias
  int contarProdutosComValidadeCritica({int dias = 30}) {
    final produtosComLote = _lotesProdutos
        .where((l) => l.quantidade > 0 && l.dataValidade != null)
        .map((l) => l.produtoId)
        .toSet();
    int count = 0;
    for (final pid in produtosComLote) {
      final val = proximaValidade(pid);
      if (val == null) continue;
      if (!val.isAfter(DateTime.now().add(Duration(days: dias)))) {
        count++;
      }
    }
    return count;
  }

  /// Adiciona ou atualiza um lote de produto
  Future<void> salvarLoteProduto(LoteProduto lote) async {
    final index = _lotesProdutos.indexWhere((l) => l.id == lote.id);
    if (index != -1) {
      _lotesProdutos[index] = lote;
    } else {
      _lotesProdutos.add(lote);
    }
    notifyListeners();
    _marcarSujo(LocalStorageService.keyLotesProdutos);

    // ⚠️ PERSISTÊNCIA IMEDIATA (não depender apenas do debounce de 5s):
    // Grava o lote no PostgreSQL local AGORA e envia para o Supabase.
    // Sem isso, se o app fechar antes do debounce, o lote fica só na memória e se perde.
    try {
      await DatabaseService().upsertItem(LocalStorageService.keyLotesProdutos, lote.toMap());
      debugPrint('>>> [DataService] 💾 Lote ${lote.id} salvo imediatamente no PostgreSQL');
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao salvar lote no PostgreSQL imediatamente: $e');
    }
    enviarMudancaParaSupabase(SupabaseService.tableLotesProdutos, lote.toMap());
  }

  /// Remove um lote de produto
  Future<void> removerLoteProduto(String loteId) async {
    _lotesProdutos.removeWhere((l) => l.id == loteId);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyLotesProdutos);

    // ⚠️ DELETE IMEDIATO no PostgreSQL local (não depender do debounce).
    try {
      await DatabaseService().removerItemPostgres(
        LocalStorageService.keyLotesProdutos,
        loteId,
        _currentEmpresaId,
      );
      debugPrint('>>> [DataService] 🗑️ Lote $loteId removido imediatamente do PostgreSQL');
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao remover lote do PostgreSQL imediatamente: $e');
    }
    enviarMudancaParaSupabase(SupabaseService.tableLotesProdutos, {'id': loteId}, evento: 'DELETE');
  }

  /// Baixa FEFO: reduz a quantidade dos lotes (primeiro os que vencem antes).
  /// Retorna a quantidade que não pôde ser abatida (estoque sem lote).
  double darBaixaEmLotes(String produtoId, double quantidade, {String? observacao}) {
    double restante = quantidade;
    final lotes = lotesDoProduto(produtoId).where((l) => l.quantidade > 0).toList();
    final atualizados = <LoteProduto>[];
    for (final lote in lotes) {
      if (restante <= 0) break;
      final abater = restante >= lote.quantidade ? lote.quantidade : restante;
      if (abater <= 0) continue;
      restante -= abater;
      final atualizado = lote.copyWith(
        quantidade: lote.quantidade - abater,
        updatedAt: DateTime.now(),
      );
      atualizados.add(atualizado);
    }
    for (final l in atualizados) {
      final idx = _lotesProdutos.indexWhere((x) => x.id == l.id);
      if (idx != -1) {
        _lotesProdutos[idx] = l;
        // ⚠️ Persistir imediatamente no PostgreSQL (não depender do debounce)
        try {
          DatabaseService().upsertItem(LocalStorageService.keyLotesProdutos, l.toMap());
        } catch (e) {
          debugPrint('>>> [DataService] ⚠️ Erro ao persistir baixa de lote: $e');
        }
        enviarMudancaParaSupabase(SupabaseService.tableLotesProdutos, l.toMap());
      }
    }
    if (atualizados.isNotEmpty) {
      _marcarSujo(LocalStorageService.keyLotesProdutos);
    }
    return restante; // quantidade sem lote correspondente
  }

  /// Entrada de estoque em lote: cria/atualiza o lote e dá entrada no estoque do produto
  Future<void> registrarEntradaEstoqueComLote({
    required String produtoId,
    required double quantidade,
    String? numeroLote,
    DateTime? dataValidade,
    DateTime? dataFabricacao,
    String? observacao,
    String? usuario,
    String? fornecedorId,
    String? fornecedorNome,
  }) async {
    await registrarEntradaEstoque(
      produtoId: produtoId,
      quantidade: quantidade,
      observacao: observacao,
      usuario: usuario,
      fornecedorId: fornecedorId,
      fornecedorNome: fornecedorNome,
    );
    if (numeroLote == null || numeroLote.trim().isEmpty) return;

    // Lote atrelado ao fornecedor: só unifica (soma) quando a entrada vem do
    // MESMO produto + MESMO fornecedor + mesmo nº de lote + mesma validade.
    // O mesmo nº de lote de fornecedores diferentes permanece em lotes
    // separados, cada um com seu estoque próprio.
    LoteProduto? existente;
    for (final l in _lotesProdutos) {
      if (l.produtoId == produtoId &&
          l.numeroLote.trim().toLowerCase() == numeroLote.trim().toLowerCase() &&
          _mesmaData(l.dataValidade, dataValidade) &&
          l.fornecedorId == fornecedorId) {
        existente = l;
        break;
      }
    }
    if (existente != null) {
      await salvarLoteProduto(existente.copyWith(
        quantidade: existente.quantidade + quantidade,
        dataFabricacao: dataFabricacao ?? existente.dataFabricacao,
        fornecedorId: fornecedorId ?? existente.fornecedorId,
        fornecedorNome: fornecedorNome ?? existente.fornecedorNome,
        updatedAt: DateTime.now(),
      ));
    } else {
      await salvarLoteProduto(LoteProduto(
        id: '${DateTime.now().microsecondsSinceEpoch}_lote_$produtoId',
        produtoId: produtoId,
        numeroLote: numeroLote.trim(),
        dataFabricacao: dataFabricacao,
        dataValidade: dataValidade,
        quantidade: quantidade,
        fornecedorId: fornecedorId,
        fornecedorNome: fornecedorNome,
      ));
    }
  }

  bool _mesmaData(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ============ Estoque Histórico ============

  /// Registra uma entrada de estoque, atualizando o produto e o histórico.
  /// Retorna `true` se o produto foi localizado e o estoque/histórico foram
  /// atualizados, ou `false` se o produto não foi encontrado (ex.: produto
  /// ainda não salvo, com ID vazio).
  Future<bool> registrarEntradaEstoque({
    required String produtoId,
    required double quantidade,
    String? observacao,
    String? usuario,
    String? fornecedorId,
    String? fornecedorNome,
  }) async {
    // 1. Localizar o produto
    final index = _produtos.indexWhere((p) => p.id == produtoId);
    if (index == -1 || produtoId.isEmpty) {
      debugPrint('>>> [DataService] registrarEntradaEstoque: Produto não encontrado ($produtoId)');
      return false;
    }

    final produto = _produtos[index];
    
    // 2. Atualizar o estoque por fornecedor
    final mapaEstoque = Map<String, double>.from(produto.estoquePorFornecedor ?? {});
    final nomeFornecedorFinal = fornecedorNome ?? 'Geral';
    mapaEstoque[nomeFornecedorFinal] = (mapaEstoque[nomeFornecedorFinal] ?? 0.0) + quantidade;

    // 3. Atualizar o produto
    final produtoAtualizado = produto.copyWith(
      estoque: produto.estoque + quantidade,
      estoquePorFornecedor: mapaEstoque,
      updatedAt: DateTime.now(),
    );

    // Salvar o produto atualizado (não aguardar Supabase para resposta instantânea).
    // A observação do histórico de alterações identifica a entrada no produto
    // (aparece na aba 'Histórico de Alterações' do formulário).
    final obsHistorico = [
      'Entrada de estoque +${quantidade.toStringAsFixed(2)}',
      if (observacao != null && observacao.isNotEmpty) observacao,
      if (fornecedorNome != null && fornecedorNome.isNotEmpty) 'Fornecedor: $fornecedorNome',
    ].join(' | ');
    await updateProduto(
      produtoAtualizado,
      aguardarSincronia: false,
      registrarMovimento: false,
      observacaoHistorico: obsHistorico,
      usuarioNome: usuario,
    );

    // 4. Registrar no histórico
    final historico = EstoqueHistorico(
      id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + produtoId,
      produtoId: produtoId,
      data: DateTime.now(),
      quantidade: quantidade,
      tipo: 'entrada',
      observacao: observacao,
      usuario: usuario,
      fornecedorId: fornecedorId,
      fornecedorNome: fornecedorNome,
    );
    _estoqueHistorico.add(historico);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyEstoqueHistorico);

    // Enviar mudança para Supabase em segundo plano de forma assíncrona (não-bloqueante)
    enviarMudancaParaSupabase(SupabaseService.tableEstoqueHistorico, historico.toMap());
    return true;
  }

  /// Zera completamente o estoque do produto para todos os fornecedores cadastrados
  Future<void> zerarEstoqueCompleto({
    required String produtoId,
    String? usuario,
  }) async {
    final index = _produtos.indexWhere((p) => p.id == produtoId);
    if (index == -1) return;

    final produto = _produtos[index];
    final mapaEstoque = Map<String, double>.from(produto.estoquePorFornecedor ?? {});
    
    // Identificar fornecedores que possuem estoque não zerado
    final fornecedoresParaZerar = mapaEstoque.entries.where((e) => e.value != 0).toList();
    
    if (fornecedoresParaZerar.isEmpty) {
      // Se já está tudo zerado ou o mapa está vazio, garante que o geral é 0
      final produtoAtualizado = produto.copyWith(
        estoque: 0.0,
        estoquePorFornecedor: {},
        updatedAt: DateTime.now(),
      );
      await updateProduto(produtoAtualizado, aguardarSincronia: false, registrarMovimento: false);
      return;
    }

    // Registrar movimentações individuais para zerar cada fornecedor
    for (final entry in fornecedoresParaZerar) {
      final fornNome = entry.key;
      final qtdAtual = entry.value;
      
      mapaEstoque[fornNome] = 0.0;

      final historico = EstoqueHistorico(
        id: DateTime.now().millisecondsSinceEpoch.toString() + '_zerar_' + fornNome + '_' + produtoId,
        produtoId: produtoId,
        data: DateTime.now(),
        quantidade: -qtdAtual,
        tipo: qtdAtual > 0 ? 'saida' : 'entrada',
        observacao: 'Zerar estoque do fornecedor "$fornNome" via botão rápido por ${usuario ?? "Sistema"}',
        usuario: usuario,
        fornecedorNome: fornNome,
      );
      
      _estoqueHistorico.add(historico);
      enviarMudancaParaSupabase(SupabaseService.tableEstoqueHistorico, historico.toMap());
    }

    final produtoAtualizado = produto.copyWith(
      estoque: 0.0,
      estoquePorFornecedor: mapaEstoque,
      updatedAt: DateTime.now(),
    );

    await updateProduto(
      produtoAtualizado, 
      aguardarSincronia: false, 
      registrarMovimento: false, 
      notify: true,
      usuarioNome: usuario,
    );
    notifyListeners();
    _marcarSujo(LocalStorageService.keyEstoqueHistorico);
  }

  /// Registra uma saída de estoque, atualizando o produto e o histórico
  Future<void> registrarSaidaEstoque({
    required String produtoId,
    required double quantidade,
    String? observacao,
    String? usuario,
    String? motivo, // 'venda', 'quebra', 'perda', 'consumo', etc.
    String? fornecedorNome, // Fornecedor específico para abater o estoque
    bool notify = true,
    bool baixaProporcionalComposicao = true, // true = usa a conversão do saco (15 kg = 1); false = baixa a quantidade inteira no ingrediente
    double? custoUnitarioOverride, // Custo unitário a registrar (padrão: preço de custo do produto)
  }) async {
    final index = _produtos.indexWhere((p) => p.id == produtoId);
    if (index == -1) return;

    final produto = _produtos[index];
    
    // Suporte a Produtos Compostos: Se for composto, baixa os ingredientes recursivamente
    if (produto.ehComposto && produto.composicao.isNotEmpty) {
      debugPrint('>>> [Estoque] 🧩 Produto COMPOSTO detectado: ${produto.nome}. Baixando ingredientes...');
      for (final itemComp in produto.composicao) {
        // Ajusta resíduo de ponto flutuante: se o valor estiver a epsilon de um inteiro (ex.: 15 kg × 0,0667 = 0,9999 → 1 saco), encaixa no inteiro;
        // senão mantém a fração real (não zera quantidades pequenas legítimas)
        // Modo direto (baixaProporcionalComposicao = false): baixa a quantidade vendida inteira APENAS
        // nos ingredientes que têm conversão definida (ex.: saco). Os demais seguem proporcionais.
        final raw = (!baixaProporcionalComposicao && itemComp.pesoTotalSaco != null)
            ? quantidade
            : quantidade * itemComp.quantidade;
        final qtdIngrediente = (raw - raw.roundToDouble()).abs() < 0.0005
            ? raw.roundToDouble()
            : raw;
        registrarSaidaEstoque(
          produtoId: itemComp.produtoId,
          quantidade: qtdIngrediente,
          motivo: motivo ?? 'venda_composicao',
          observacao: 'Baixa via composição de ${produto.nome} (${observacao ?? ""})',
          usuario: usuario,
          notify: false,
        );
      }
      // Produto composto com baixarEstoqueProprio = false (ex.: Chop controlado
      // pelo Barril em ml): a baixa acontece APENAS nos ingredientes. O estoque
      // deste produto (e seu histórico) não são alterados — ele fica "ilimitado".
      if (!produto.baixarEstoqueProprio) {
        debugPrint('>>> [Estoque] ⏭️ ${produto.nome} não baixa estoque próprio (só ingredientes).');
        return;
      }
    }
    
    // Abatimento proporcional do estoque por fornecedor
    final mapaEstoque = Map<String, double>.from(produto.estoquePorFornecedor ?? {});
    double quantidadeRestante = quantidade;

    // Se informou um fornecedor, tentar abater dele PRIMEIRO
    if (fornecedorNome != null && fornecedorNome.isNotEmpty) {
      final nomeNorm = fornecedorNome == 'Geral' ? 'Geral' : fornecedorNome;
      double estoqueDisponivel = mapaEstoque[nomeNorm] ?? 0.0;
      if (estoqueDisponivel > 0) {
        if (estoqueDisponivel >= quantidadeRestante) {
          mapaEstoque[nomeNorm] = estoqueDisponivel - quantidadeRestante;
          quantidadeRestante = 0;
        } else {
          mapaEstoque[nomeNorm] = 0.0;
          quantidadeRestante -= estoqueDisponivel;
        }
      }
    }

    // Se ainda sobrar e NÃO foi informado fornecedor no parâmetro, 
    // tentar o fornecedor principal do cadastro do produto
    if (quantidadeRestante > 0 && (fornecedorNome == null || fornecedorNome.isEmpty)) {
      if (produto.fornecedorNome != null && produto.fornecedorNome!.isNotEmpty) {
        final nomeFornPrincipal = produto.fornecedorNome!;
        double estoquePrincipal = mapaEstoque[nomeFornPrincipal] ?? 0.0;
        if (estoquePrincipal > 0) {
          if (estoquePrincipal >= quantidadeRestante) {
            mapaEstoque[nomeFornPrincipal] = estoquePrincipal - quantidadeRestante;
            quantidadeRestante = 0;
          } else {
            mapaEstoque[nomeFornPrincipal] = 0.0;
            quantidadeRestante -= estoquePrincipal;
          }
        }
      }
    }

    // Tentar abater de outros fornecedores (FIFO-ish simples) se ainda sobrar
    if (quantidadeRestante > 0) {
      final fornecedoresOrdenados = mapaEstoque.keys.toList();
      for (var forn in fornecedoresOrdenados) {
        if (quantidadeRestante <= 0) break;
        
        double estoqueDisponivel = mapaEstoque[forn] ?? 0.0;
        if (estoqueDisponivel > 0) {
          if (estoqueDisponivel >= quantidadeRestante) {
            mapaEstoque[forn] = estoqueDisponivel - quantidadeRestante;
            quantidadeRestante = 0;
          } else {
            mapaEstoque[forn] = 0.0;
            quantidadeRestante -= estoqueDisponivel;
          }
        }
      }
    }

    // Se ainda sobrar quantidade (estoque negativo), abater do primeiro fornecedor ou 'Geral'
    if (quantidadeRestante > 0) {
      final key = fornecedorNome ?? (mapaEstoque.keys.isNotEmpty ? mapaEstoque.keys.first : 'Geral');
      mapaEstoque[key] = (mapaEstoque[key] ?? 0.0) - quantidadeRestante;
    }

    final produtoAtualizado = produto.copyWith(
      estoque: produto.estoque - quantidade,
      estoquePorFornecedor: mapaEstoque,
      updatedAt: DateTime.now(),
    );

    // Salvar o produto atualizado (não aguardar Supabase para resposta instantânea)
    await updateProduto(
      produtoAtualizado, 
      aguardarSincronia: false, 
      registrarMovimento: false, 
      notify: notify, 
      motivoHistorico: motivo, 
      observacaoHistorico: observacao, 
      usuarioNome: usuario
    );

    // BAIXA FEFO NOS LOTES: se o produto possui lotes com validade, abate
    // primeiro dos lotes que vencem antes (controle de validade para ração,
    // medicamentos etc.). A quantidade abatida sai do estoque dos lotes.
    if (_lotesProdutos.any((l) => l.produtoId == produtoId && l.quantidade > 0)) {
      darBaixaEmLotes(produtoId, quantidade, observacao: observacao);
    }

    // Registrar no histórico — para quebras/perdas também registra o VALOR DE CUSTO
    // da mercadoria (preço de custo × quantidade), para o cadastro do produto e
    // relatórios mostrarem o prejuízo real de cada mercadoria quebrada.
    final custoUnit = custoUnitarioOverride ?? produto.precoCusto ?? 0.0;
    final valorCusto = motivo == 'quebra'
        ? (custoUnit * quantidade)
        : (custoUnit > 0 ? custoUnit * quantidade : null);
    final historico = EstoqueHistorico(
      id: DateTime.now().millisecondsSinceEpoch.toString() + '_saida_' + produtoId,
      produtoId: produtoId,
      data: DateTime.now(),
      quantidade: -quantidade,
      tipo: 'saida',
      observacao: (observacao ?? '') + (motivo != null ? ' (Motivo: $motivo)' : ''),
      usuario: usuario,
      fornecedorNome: fornecedorNome,
      custoUnitario: custoUnit > 0 ? custoUnit : null,
      valorCusto: valorCusto != null && valorCusto > 0 ? valorCusto : null,
      motivo: motivo,
    );
    _estoqueHistorico.add(historico);
    if (notify) notifyListeners();
    // Enviar mudança para Supabase em segundo plano de forma assíncrona (não-bloqueante)
    enviarMudancaParaSupabase(SupabaseService.tableEstoqueHistorico, historico.toMap());
  }

  // ============ INVENTÁRIO (Contagem da Loja) ============

  /// Aplica o resultado de um inventário de conferência: corrige o estoque de
  /// cada produto para a contagem real da loja e registra a diferença no
  /// histórico (motivo 'inventario'). Faltas viram saída; sobras viram entrada.
  ///
  /// [contagens] mapeia produtoId -> quantidade contada na loja.
  /// Retorna um resumo para a tela: {conferidos, faltas, sobras, itensAjustados}.
  Future<Map<String, int>> aplicarInventario(
    Map<String, double> contagens, {
    String? usuario,
  }) async {
    var conferidos = 0, faltas = 0, sobras = 0, ajustados = 0;

    for (final entry in contagens.entries) {
      final produtoId = entry.key;
      final contado = entry.value;
      final index = _produtos.indexWhere((p) => p.id == produtoId);
      if (index == -1) continue;

      final produto = _produtos[index];
      final sistema = produto.estoque;
      final diferenca = contado - sistema;
      final arredondado = (diferenca - diferenca.roundToDouble()).abs() < 0.0005
          ? diferenca.roundToDouble()
          : diferenca;

      conferidos++;
      if (arredondado.abs() < 0.0005) continue; // contagem confere — sem ajuste

      if (arredondado < 0) {
        faltas++;
        await registrarSaidaEstoque(
          produtoId: produtoId,
          quantidade: arredondado.abs(),
          motivo: 'inventario',
          observacao: 'Inventário — faltando ${arredondado.abs().toStringAsFixed(2)} (sistema: ${sistema.toStringAsFixed(2)} → contado: ${contado.toStringAsFixed(2)})',
          usuario: usuario,
          fornecedorNome: produto.fornecedorNome,
          custoUnitarioOverride: (produto.precoCusto ?? 0.0) > 0 ? produto.precoCusto : null,
        );
      } else {
        sobras++;
        await registrarEntradaEstoque(
          produtoId: produtoId,
          quantidade: arredondado,
          observacao: 'Inventário — sobra de ${arredondado.toStringAsFixed(2)} (sistema: ${sistema.toStringAsFixed(2)} → contado: ${contado.toStringAsFixed(2)})',
          usuario: usuario,
          fornecedorNome: 'Geral',
        );
      }
      ajustados++;
    }

    _marcarSujo(LocalStorageService.keyEstoqueHistorico);
    notifyListeners();
    return {'conferidos': conferidos, 'faltas': faltas, 'sobras': sobras, 'ajustados': ajustados};
  }

  // ============ CRUD NotaEntrada ============

  Future<void> addNotaEntrada(NotaEntrada nota) async {
    _notasEntrada.add(nota);
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    
    // Marcar coleções impactadas para salvamento automático seletivo
    _marcarSujo(LocalStorageService.keyNotasEntrada);
    _marcarSujo(LocalStorageService.keyProdutos); // Notas de entrada afetam estoque
    _marcarSujo(LocalStorageService.keyEstoqueHistorico); // Notas de entrada geram histórico
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableNotasEntrada, nota.toMap());
    _sincronizarNotasComDrive();
  }

  void updateNotaEntrada(NotaEntrada nota) {
    final index = _notasEntrada.indexWhere((n) => n.id == nota.id);
    if (index != -1) {
      _notasEntrada[index] = nota;
      notifyListeners();
      _salvarAutomaticamente();
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      enviarMudancaParaSupabase(SupabaseService.tableNotasEntrada, nota.toMap());
    }
  }

  void deleteNotaEntrada(String notaId) {
    _notasEntrada.removeWhere((n) => n.id == notaId);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyNotasEntrada);
    // Propagar delete para Supabase
    enviarMudancaParaSupabase(SupabaseService.tableNotasEntrada, {'id': notaId}, evento: 'DELETE');
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
          final novoEstoque = (produto.estoque - item.quantidade).clamp(0.0, double.infinity);
          
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
    _marcarSujo(LocalStorageService.keyNotasEntrada);
    // Propagar cancelâmento (exclusão) para Supabase
    await enviarMudancaParaSupabase(SupabaseService.tableNotasEntrada, {'id': notaId}, evento: 'DELETE');
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
    
    await _upsertNoSupabase(SupabaseService.tableServicos, servico.toMap());
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
      
      await _upsertNoSupabase(SupabaseService.tableServicos, servico.toMap());
    }
  }

  void deleteTipoServico(String id) {
    _tiposServico.removeWhere((s) => s.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    if (SupabaseService.isAvailable && _currentEmpresaId != null) {
      _supabaseService.delete(SupabaseService.tableServicos, id).catchError((e) {
        debugPrint('>>> Erro ao remover serviço do Supabase: $e');
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
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableOrdensServico, os.toMap());
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
      
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(SupabaseService.tableOrdensServico, os.toMap());
    }
  }
  void deleteOrdemServico(String id) {
    _ordensServico.removeWhere((o) => o.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tableOrdensServico, {'id': id}, evento: 'DELETE');
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

    if (SupabaseService.isAvailable && _currentEmpresaId != null) {
      for (final completo in novosCompletos) {
        _upsertNoSupabase(SupabaseService.tableAgendamentosServico, completo.toMap());
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
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableAgendamentosServico, agendamentoCompleto.toMap());
    
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
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableAgendamentosServico, agendamentoAtualizado.toMap());
    
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
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableAgendamentosServico, {'id': id}, evento: 'DELETE');
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

        // Salvar no Supabase
        if (SupabaseService.isAvailable && _currentEmpresaId != null) {
          await _upsertNoSupabase(SupabaseService.tableAgendamentosServico, promovido.toMap());
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
    
    await _upsertNoSupabase(SupabaseService.tableAgendamentosServico, agendamentoAtualizado.toMap());
    
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
      
      await _upsertNoSupabase(SupabaseService.tableAgendamentosServico, agendamentoAtualizado.toMap());
      
      // Notificar cliente via WhatsApp em background
      // ignore: unawaited_futures
      _enviarNotificacaoWhatsAppAgendamento(agendamentoAtualizado, isNovo: false);

      notifyListeners();
      forceUpdate();
    }
  }

  // ============ CRUD Pedido ============

  Future<void> addPedido(Pedido pedido) async {
    
    _pedidos.add(pedido);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyPedidos);
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tablePedidos, pedido.toMap());
    
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
      
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(SupabaseService.tablePedidos, pedido.toMap());

      // SINCRONIZAÇÃO BIDIRECIONAL: Pedido -> Entrega
      if (pedido.deliveryInfo != null && pedido.deliveryInfo!.status.toLowerCase() == 'entregue') {
        final entregaIndex = _entregas.indexWhere((e) => e.pedidoId == pedido.id || e.pedidoNumero == pedido.numero);
        if (entregaIndex != -1 && _entregas[entregaIndex].status != StatusEntrega.entregue) {
           _entregas[entregaIndex] = _entregas[entregaIndex].copyWith(
             status: StatusEntrega.entregue,
             dataEntrega: _entregas[entregaIndex].dataEntrega ?? DateTime.now(),
           );
           _marcarSujo(LocalStorageService.keyEntregas);
           debugPrint('>>> [Sync] ✅ Entrega sincronizada para ENTREGUE via Pedido');
        }
      }
    } else {
      debugPrint('>>> ERRO: Pedido não encontrado para atualizar!');
    }
  }

  void deletePedido(String id) {
    _pedidos.removeWhere((p) => p.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tablePedidos, {'id': id}, evento: 'DELETE');
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
      _marcarSujo(LocalStorageService.keyPedidos);
      // Sincronizar cancelamento com Supabase imediatamente
      await enviarMudancaParaSupabase(SupabaseService.tablePedidos, pedidoCancelado.toMap());
    }
  }

  // ============ Metodos auxiliares ============

  List<Servico> getServicosPorCliente(String clienteId) {
    return _tiposServico;
  }

  // ============ CRUD Entrega ============

  Future<void> addEntrega(Entrega entrega) async {
    _entregas.add(entrega);
    _marcarSujo(LocalStorageService.keyEntregas);
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    await _upsertNoSupabase(SupabaseService.tableEntregas, entrega.toMap());
  }

  Future<void> updateEntrega(Entrega entrega) async {
    final index = _entregas.indexWhere((e) => e.id == entrega.id);
    if (index != -1) {
      _entregas[index] = entrega;
      // Notificar listeners IMEDIATAMENTE para atualizar a UI
      notifyListeners();
      
      // Salvar localmente IMEDIATAMENTE (sem debounce)
      _marcarSujo(LocalStorageService.keyEntregas);
      debugPrint('>>> [Entrega] ✅ Atualizada em memória: ${entrega.id}');

      // SINCRONIZAÇÃO BIDIRECIONAL: Entrega -> Pedido
      if (entrega.status == StatusEntrega.entregue) {
        final pedidoIndex = _pedidos.indexWhere((p) => p.id == entrega.pedidoId || p.numero == entrega.pedidoNumero);
        if (pedidoIndex != -1) {
           final p = _pedidos[pedidoIndex];
           if (p.deliveryInfo != null && p.deliveryInfo!.status.toLowerCase() != 'entregue') {
              _pedidos[pedidoIndex] = p.copyWith(
                deliveryInfo: p.deliveryInfo!.copyWith(status: 'entregue'),
                status: p.status.toLowerCase() == 'pendente' ? 'Entregue' : p.status, // Opcional: atualizar status geral se estiver pendente
              );
              _marcarSujo(LocalStorageService.keyPedidos);
              debugPrint('>>> [Sync] ✅ Pedido sincronizado para ENTREGUE via Entrega');
           }
        }
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      await _upsertNoSupabase(SupabaseService.tableEntregas, entrega.toMap());
    }
  }

  void deleteEntrega(String id) {
    _entregas.removeWhere((e) => e.id == id);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyEntregas);
    enviarMudancaParaSupabase(SupabaseService.tableEntregas, {'id': id}, evento: 'DELETE');
  }

  // ROMANEIOS
  Future<void> addRomaneio(Romaneio romaneio) async {
    _romaneios.add(romaneio);
    _marcarSujo(LocalStorageService.keyRomaneios);
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase('romaneios', romaneio.toMap());
    notifyListeners();
  }

  Future<void> updateRomaneio(Romaneio romaneio) async {
    final index = _romaneios.indexWhere((r) => r.id == romaneio.id);
    if (index != -1) {
      _romaneios[index] = romaneio;
      _marcarSujo(LocalStorageService.keyRomaneios);
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase('romaneios', romaneio.toMap());
      notifyListeners();
    }
  }

  Future<void> deleteRomaneio(String id) async {
    _romaneios.removeWhere((r) => r.id == id);
    _marcarSujo(LocalStorageService.keyRomaneios);
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase('romaneios', {'id': id}, evento: 'DELETE');
    notifyListeners();
  }

  String gerarProximoNumeroRomaneio() {
    if (_romaneios.isEmpty) return 'ROM-0001';
    
    // Extrair números dos romaneios existentes
    final numeros = _romaneios.map((r) {
      final match = RegExp(r'ROM-(\d+)').firstMatch(r.numero);
      return match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
    }).toList();
    
    final proximo = (numeros.isNotEmpty ? numeros.reduce((curr, next) => curr > next ? curr : next) : 0) + 1;
    return 'ROM-${proximo.toString().padLeft(4, '0')}';
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
        _getEmpresaKey(LocalStorageService.keyTaxasEntrega), 
        _taxasEntrega
      );
      debugPrint('>>> [TaxaEntrega] ✅ Salva localmente: ${taxa.bairro} (ID: ${taxa.id})');
    } catch (e) {
      debugPrint('>>> [TaxaEntrega] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableTaxasEntrega, taxa.toMap());
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
          _getEmpresaKey(LocalStorageService.keyTaxasEntrega), 
          _taxasEntrega
        );
        debugPrint('>>> [TaxaEntrega] ✅ Atualizada localmente: ${taxa.bairro} (ID: ${taxa.id})');
      } catch (e) {
        debugPrint('>>> [TaxaEntrega] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(SupabaseService.tableTaxasEntrega, taxa.toMap());
    }
  }

  Future<void> deleteTaxaEntrega(String id) async {
    _taxasEntrega.removeWhere((t) => t.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableTaxasEntrega, {'id': id}, evento: 'DELETE');
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
        _getEmpresaKey(LocalStorageService.keyMotoristas), 
        _motoristas
      );
      debugPrint('>>> [Motorista] ✅ Salvo localmente: ${motorista.nome} (ID: ${motorista.id})');
    } catch (e) {
      debugPrint('>>> [Motorista] ❌ Erro ao salvar localmente: $e');
    }
    
    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();
    
    await _upsertNoSupabase(SupabaseService.tableMotoristas, motorista.toMap());
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
          _getEmpresaKey(LocalStorageService.keyMotoristas), 
          _motoristas
        );
        debugPrint('>>> [Motorista] ✅ Atualizado localmente: ${motorista.nome} (ID: ${motorista.id})');
      } catch (e) {
        debugPrint('>>> [Motorista] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      await _upsertNoSupabase(SupabaseService.tableMotoristas, motorista.toMap());
    }
  }

  void deleteMotorista(String id) {
    _motoristas.removeWhere((m) => m.id == id);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyMotoristas);
    enviarMudancaParaSupabase(SupabaseService.tableMotoristas, {'id': id}, evento: 'DELETE');
  }

  // ============ CRUD Venda Balcão ============

  Future<void> addVendaBalcao(VendaBalcao venda) async {
    // Garantir operador na venda: caminhos que criam VendaBalcao sem preencher
    // `operador` (ex.: pedido pago no PDV, fechamento de mesa/comanda) deixam a
    // venda "sem dono" e ela some do caixa nominado (getVendasDoCaixa exclui
    // vendas sem operador de caixas com responsável). Atribui o operador ativo.
    final temOperador = venda.operador != null && venda.operador!.trim().isNotEmpty;
    if (!temOperador) {
      final operadorPadrao = _responsavelAtivo ?? _usuarioAtualEmail;
      if (operadorPadrao != null && operadorPadrao.trim().isNotEmpty) {
        venda = venda.copyWith(operador: operadorPadrao.trim());
      }
    }
    _vendasBalcao.add(venda);
    print('✓ Venda ${venda.numero} (ID: ${venda.id}) salva em memória @ ${DateTime.now()}');
    
    // SALVAR IMEDIATAMENTE no PostgreSQL (apenas este item, sem reescrever toda a tabela)
    try {
      await DatabaseService().upsertItem(
        _getChaveComEmpresa(LocalStorageService.keyVendasBalcao),
        venda.toMap(),
      );
      print('>>> ⚡ Venda ${venda.numero} persistida via upsert rápido');
    } catch (e) {
      print('>>> ⚠️ Erro no upsert rápido da venda: $e');
    }
    
    // Baixar estoque automaticamente
    for (final item in venda.itens) {
      if (!item.isServico) {
        // Fator de baixa: usa a forma de venda escolhida no item (ex.: 1 caixa = 12 un.),
        // com fallback para o fator padrão do produto (produtos cadastrados antes das múltiplas formas).
        final produtoVendido = getProdutoById(item.id);
        final fatorBaixa = (item.quantidadeBaixa ?? 0) > 0
            ? item.quantidadeBaixa!
            : (produtoVendido?.fatorBaixaEstoque ?? 1.0);
        registrarSaidaEstoque(
          produtoId: item.id,
          quantidade: item.quantidade.toDouble() * fatorBaixa,
          motivo: 'venda',
          observacao: 'Saída via venda ${venda.numero}',
          fornecedorNome: item.fornecedorNome,
          usuario: venda.operador,
          notify: false,
          baixaProporcionalComposicao: item.baixaProporcional,
        );
        // BAIXA DAS OPÇÕES DO COMBO: cada opção selecionada no PDV
        // (ex.: sabor do milkshake) baixa o estoque do produto vinculado.
        // Produtos COMPOSTOS com exibirComposicaoPdv geram opcoesCombo a partir
        // da composição com id de prefixo 'comp_' — e o registrarSaidaEstoque já
        // baixa esses ingredientes recursivamente, então pulamos APENAS essas
        // (evita baixa dupla). Opções de perguntas (sabor, tamanho...) baixam
        // normalmente, mesmo quando o produto também é composto.
        for (final opcao in item.opcoesCombo) {
          final ehDaComposicao = opcao.id.startsWith('comp_');
          if (!ehDaComposicao && opcao.produtoId.isNotEmpty && opcao.quantidadeBaixa > 0) {
            registrarSaidaEstoque(
              produtoId: opcao.produtoId,
              quantidade: opcao.quantidadeBaixa * item.quantidade.toDouble(),
              motivo: 'venda_combo',
              observacao: 'Opção "${opcao.nome}" de ${item.nome} (venda ${venda.numero})',
              usuario: venda.operador,
              notify: false,
            );
          }
        }
      }
    }

    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    _marcarSujo(LocalStorageService.keyVendasBalcao);
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableVendasBalcao, venda.toMap());
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
          _getEmpresaKey(LocalStorageService.keyVendasBalcao), 
          _vendasBalcao
        );
        debugPrint('>>> [VendaBalcao] ✅ Atualizada localmente: ${venda.numero} (ID: ${venda.id})');
      } catch (e) {
        debugPrint('>>> [VendaBalcao] ❌ Erro ao atualizar localmente: $e');
      }
      
      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();
      
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(SupabaseService.tableVendasBalcao, venda.toMap());
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
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableVendasBalcao, {'id': id}, evento: 'DELETE');
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
      // Sincronizar cancelamento com Supabase imediatamente
      await enviarMudancaParaSupabase(SupabaseService.tableVendasBalcao, vendaCancelada.toMap());
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
    // 1. Processar devoluções ao estoque
    for (final item in troca.itensDevolvidos) {
      await registrarEntradaEstoque(
        produtoId: item.produtoId,
        quantidade: item.quantidade.toDouble(),
        observacao: 'Retorno por ${troca.tipo.name}: ${troca.numeroPedido}',
        usuario: 'Sistema',
        fornecedorNome: 'Troca/Devolução',
      );
    }

    // 2. Processar saídas de novos produtos (se for troca)
    if (troca.tipo == TipoOperacao.troca && troca.itensNovos != null) {
      for (final item in troca.itensNovos!) {
        await registrarSaidaEstoque(
          produtoId: item.produtoId,
          quantidade: item.quantidade.toDouble(),
          observacao: 'Saída por troca: ${troca.numeroPedido}',
          usuario: 'Sistema',
          motivo: 'troca',
          fornecedorNome: 'Troca/Devolução',
        );
      }
    }

    // 3. Registrar a operação
    _trocasDevolucoes.add(troca);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyTrocasDevolucoes);
    
    await _upsertNoSupabase(SupabaseService.tableTrocasDevolucoes, troca.toMap());
    
    print('>>> ✓ Troca/Devolução registrada e estoque atualizado.');
  }

  Future<void> updateTrocaDevolucao(TrocaDevolucao troca) async {
    final index = _trocasDevolucoes.indexWhere((t) => t.id == troca.id);
    if (index != -1) {
      _trocasDevolucoes[index] = troca;
      print('✓ Troca/Devolução ${troca.id} atualizada em memória');
      notifyListeners();
      _marcarSujo(LocalStorageService.keyTrocasDevolucoes);
      // Sincronizar com Supabase
      await enviarMudancaParaSupabase(SupabaseService.tableTrocasDevolucoes, troca.toMap());
    }
  }

  Future<void> deleteTrocaDevolucao(String id) async {
    _trocasDevolucoes.removeWhere((t) => t.id == id);
    print('✓ Troca/Devolução removida da memória');
    notifyListeners();
    _marcarSujo(LocalStorageService.keyTrocasDevolucoes);
    // Sincronizar exclusão com Supabase
    await enviarMudancaParaSupabase(SupabaseService.tableTrocasDevolucoes, {'id': id}, evento: 'DELETE');
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

  // Próximo número de pedido (PED-0001, PED-0002, etc)
  String getProximoNumeroPedido() {
    // Coletar todos os números existentes que começam com PED-
    final Set<int> numerosExistentes = {};

    for (final pedido in _pedidos) {
      if (pedido.numero != null && pedido.numero.startsWith('PED-')) {
        try {
          final numero = int.parse(pedido.numero.substring(4));
          numerosExistentes.add(numero);
        } catch (e) {
          // Ignorar números inválidos
        }
      }
    }

    // Encontrar o próximo número disponível
    int proximoNumero = 1;
    if (numerosExistentes.isNotEmpty) {
      proximoNumero = numerosExistentes.reduce((a, b) => a > b ? a : b) + 1;
    }

    // Garantir que o número não existe (proteção extra)
    while (numerosExistentes.contains(proximoNumero)) {
      proximoNumero++;
    }

    return 'PED-${proximoNumero.toString().padLeft(4, '0')}';
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

  /// Calcula o próximo número de NFC-e com base no maior número já emitido.
  ///
  /// A numeração é POR SÉRIE: cada série da empresa tem sua própria sequência,
  /// começando no número inicial configurado no usuário (numeroInicialNfce,
  /// padrão 1). Assim, se o usuário usa a série 2 com número inicial 5, a
  /// primeira nota será a 5 e as seguintes 6, 7, 8... sem interferir na série 1.
  int getProximoNumeroNfce({String serie = '1', int numeroInicial = 1}) {
    final serieNorm = serie.trim().isEmpty ? '1' : serie.trim();
    final Set<int> numerosExistentes = {};

    // 1. Verificar na lista de NFC-es sincronizadas (Supabase) da MESMA série
    // Considerar as que foram autorizadas, sucesso ou canceladas (o número já foi usado)
    for (final nfce in _nfces) {
      if (nfce.numero != null &&
          (nfce.status == 'autorizada' || nfce.status == 'sucesso' || nfce.status == 'cancelada')) {
        // Série da nota: NFC-e antigas podem não ter série — trata como '1'
        final serieNfce = (nfce.serie ?? '').trim().isEmpty ? '1' : nfce.serie!.trim();
        if (serieNfce != serieNorm) continue;
        final numInt = int.tryParse(nfce.numero!);
        if (numInt != null) {
          numerosExistentes.add(numInt);
        }
      }
    }

    // 2. Número inicial da série (configurado no cadastro do usuário, padrão 1)
    int proximoNumero = numeroInicial > 0 ? numeroInicial : 1;

    // 3. Se há um 'ultimo_numero_nfce' configurado na empresa e ele for maior
    //    que o número inicial da série, respeita-o (empresa pode ter vindo de
    //    outro sistema com numeração já avançada).
    //    ATENÇÃO: este contador é GLOBAL (série 1). Séries adicionais (2, 3...)
    //    têm numeração própria — começam no número inicial configurado no
    //    usuário e só são influenciadas pelas notas da MESMA série (passo 4).
    if (serieNorm == '1' && empresaAtual?.configuracoes != null) {
      final numInicial = empresaAtual!.configuracoes!['ultimo_numero_nfce'];
      if (numInicial != null) {
        final cfgNumero = (int.tryParse(numInicial.toString()) ?? 0) + 1;
        if (cfgNumero > proximoNumero) {
          proximoNumero = cfgNumero;
        }
      }
    }

    // 4. Se temos números já emitidos na série, o próximo é o maior + 1
    if (numerosExistentes.isNotEmpty) {
      final maiorDessaLista = numerosExistentes.reduce((a, b) => a > b ? a : b);
      if (maiorDessaLista >= proximoNumero) {
        proximoNumero = maiorDessaLista + 1;
      }
    }

    return proximoNumero;
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
      // Se o número está vazio ou não começa com PED- (corrigido: era VND-)
      if (pedido.numero.isEmpty || !pedido.numero.startsWith('PED-')) {
        final novoNumero = getProximoNumeroPedido();
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
    if (numero.isEmpty) return null;
    
    try {
      // Busca direta otimizada sem prints de depuração
      return _vendasBalcao.firstWhere((v) => v.numero == numero);
    } catch (_) {
      return null;
    }
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
  Future<void> _carregarDadosDoSupabase({bool modoLeve = false}) async {
    if (_currentEmpresaId == null) {
      print('>>> ⚠ _carregarDadosDoSupabase: Empresa não definida - não é possível carregar dados do Supabase');
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

    final isDeltaSync = _ultimaSincronizacaoSucesso != null;
    final lastSyncBuffer = isDeltaSync
        ? _ultimaSincronizacaoSucesso!.subtract(const Duration(minutes: 1)).toUtc()
        : null;

    debugPrint('>>> [Supabase] 🔄 Iniciando carga (Modo Leve: $finalModoLeve, SilentSync: $isSilentSync, 1aCarga=${_primeiraCargaAgendamentosRealizada}, DeltaSync: $isDeltaSync, LastSync: $lastSyncBuffer)');
    _syncEmAndamento = true;
    notifyListeners();
    addSyncLog("Iniciando sincronização (Delta: $isDeltaSync)...");
    
    try {
      print('>>> ⚡ ========================================');
      print('>>> ⚡ Carregando dados do Supabase (Modo Leve: $finalModoLeve, Delta: $isDeltaSync)');
      print('>>> ⚡ Empresa: $currentEmpresaId');
      print('>>> ⚡ ========================================');
      
      final result = await _supabaseService.carregarTudoDoSupabase(
        _currentEmpresaId!,
        lastSync: lastSyncBuffer,
        mesesRetroativos: 24, // Carregar histórico de até 2 anos
      );
      
      final Map<String, dynamic> dados = result['data'] as Map<String, dynamic>;
      
      // Verificar se há dados no Supabase - usando um critério amplo
      final temDados = dados['clientes']?.isNotEmpty == true ||
          dados['produtos']?.isNotEmpty == true ||
          dados['pedidos']?.isNotEmpty == true ||
          dados['agendamentos_servico']?.isNotEmpty == true ||
          dados['servicos']?.isNotEmpty == true ||
          dados['ordens_servico']?.isNotEmpty == true ||
          dados['funcionarios']?.isNotEmpty == true ||
          dados['taxas_entrega']?.isNotEmpty == true ||
          dados['contas_pagar']?.isNotEmpty == true ||
          dados['comissoes_vendedores']?.isNotEmpty == true ||
          dados['mesas_comandas']?.isNotEmpty == true ||
          dados['romaneios']?.isNotEmpty == true;
      
      if (!temDados) {
        debugPrint('>>> [Supabase] Nenhum dado novo/atualizado encontrado. Sincronização delta concluída.');
        _ultimaSincronizacaoSucesso = DateTime.now();
        // Persistir timestamp de sucesso
        if (_currentEmpresaId != null) {
          final keySync = _getEmpresaKey('exodo_ultima_sincronizacao_sucesso');
          await _storage.salvar(keySync, _ultimaSincronizacaoSucesso!.toIso8601String());
        }
        _ultimoErroSync = null;
        _primeiraCargaAgendamentosRealizada = true;
        addSyncLog("Concluído: Nenhum dado novo/atualizado encontrado.");
        return;
      }

      // 1. Clientes
      if (dados['clientes'] != null) {
        final novosRaw = dados['clientes'] as List;
        final novos = novosRaw.map((map) => Cliente.fromMap(map as Map<String, dynamic>)).toList();
        if (novos.isNotEmpty) {
          _mesclarSemRemover(_clientes, novos);
          _marcarSujo(LocalStorageService.keyClientes);
          print('>>> ✓ ${novos.length} clientes sincronizados do Supabase');
        }
      }

      // 2. Produtos
      if (dados['produtos'] != null && (!isSilentSync || _produtosSubscription == null)) {
        final novos = (dados['produtos'] as List).map((map) => Produto.fromMap(map as Map<String, dynamic>)).toList();
        if (novos.isNotEmpty) {
          _mesclarSemRemover(_produtos, novos);
          _marcarSujo(LocalStorageService.keyProdutos);
          print('>>> ✓ ${novos.length} produtos sincronizados do Supabase');
        }
      }

      // 3. Serviços
      if (dados['servicos'] != null && (!isSilentSync || _servicosSubscription == null)) {
        final novos = (dados['servicos'] as List).map((map) => Servico.fromMap(map as Map<String, dynamic>)).toList();
        if (novos.isNotEmpty) {
          _mesclarSemRemover(_tiposServico, novos);
          _marcarSujo(LocalStorageService.keyServicos);
          print('>>> ✓ ${novos.length} serviços carregados do Supabase');
        }
      }

      // 4. Pedidos
      if (dados['pedidos'] != null && dados['pedidos'].isNotEmpty) {
        final novosPedidos = (dados['pedidos'] as List).map((map) => Pedido.fromMap(map as Map<String, dynamic>)).toList();
        bool dirty = false;
        for (final pedido in novosPedidos) {
          final indexLocal = _pedidos.indexWhere((p) => p.id == pedido.id);
          
          if (indexLocal != -1) {
            final local = _pedidos[indexLocal];
            bool localEhMesa = local.numero.contains('MESA') || local.numero.contains('CMD') || local.clienteNome?.contains('[') == true;
            bool SupabaseEhMesa = pedido.numero.contains('MESA') || pedido.numero.contains('CMD') || pedido.clienteNome?.contains('[') == true;
            
            if (localEhMesa && !SupabaseEhMesa) {
              debugPrint('>>> [Sync] 🛡️ Preservando Identidade VIP local do Pedido: ${local.numero}');
              _pedidos[indexLocal] = pedido.copyWith(
                numero: local.numero,
                clienteNome: local.clienteNome,
                observacoes: local.observacoes
              );
              dirty = true;
              continue;
            }
            // CONFLICT RESOLUTION: Preservar versão local se for mais recente
            // Isso evita que o sync periódico sobrescreva mudanças locais (ex: cancelamentos)
            if (local.updatedAt.isAfter(pedido.updatedAt)) {
              debugPrint('>>> [Sync] 🛡️ Preservando versão LOCAL mais recente do Pedido ${local.numero} (local: ${local.updatedAt}, supabase: ${pedido.updatedAt})');
              // Não sobrescrever - manter o local. Mas marcar para re-enviar ao Supabase.
              await enviarMudancaParaSupabase(SupabaseService.tablePedidos, local.toMap());
              continue;
            }
            _pedidos[indexLocal] = pedido;
            dirty = true;
          } else {
            _pedidos.add(pedido);
            dirty = true;
          }
        }
        if (dirty) {
          _marcarSujo(LocalStorageService.keyPedidos);
        }
        print('>>> ✓ ${novosPedidos.length} pedidos carregados do Supabase');
      }

      // 5. Ordens de Serviço
      if (dados['ordens_servico'] != null && dados['ordens_servico'].isNotEmpty) {
        final novasOrdens = (dados['ordens_servico'] as List)
            .map((map) => OrdemServico.fromMap(map as Map<String, dynamic>)).toList();
        for (final ordem in novasOrdens) {
          final index = _ordensServico.indexWhere((o) => o.id == ordem.id);
          if (index >= 0) {
            _ordensServico[index] = ordem;
          } else {
            _ordensServico.add(ordem);
          }
        }
        _marcarSujo(LocalStorageService.keyOrdensServico);
        print('>>> ✓ ${novasOrdens.length} ordens de serviço carregadas do Supabase');
      }

      // 6. Entregas
      if (dados['entregas'] != null && dados['entregas'].isNotEmpty) {
        final novasEntregas = (dados['entregas'] as List).map((map) => Entrega.fromMap(map as Map<String, dynamic>)).toList();
        for (final entrega in novasEntregas) {
          final index = _entregas.indexWhere((e) => e.id == entrega.id);
          if (index >= 0) {
            _entregas[index] = entrega;
          } else {
            _entregas.add(entrega);
          }
        }
        _marcarSujo(LocalStorageService.keyEntregas);
        print('>>> ✓ ${novasEntregas.length} entregas carregadas do Supabase');
      }

      // 7. Motoristas
      if (dados['motoristas'] != null && dados['motoristas'].isNotEmpty) {
        final novosMotoristas = (dados['motoristas'] as List).map((map) => Motorista.fromMap(map as Map<String, dynamic>)).toList();
        for (final motorista in novosMotoristas) {
          final index = _motoristas.indexWhere((m) => m.id == motorista.id);
          if (index >= 0) {
            _motoristas[index] = motorista;
          } else {
            _motoristas.add(motorista);
          }
        }
        _marcarSujo(LocalStorageService.keyMotoristas);
        print('>>> ✓ ${novosMotoristas.length} motoristas carregados do Supabase');
      }

      // 8. Vendas Balcão
      if (dados['vendas_balcao'] != null && dados['vendas_balcao'].isNotEmpty) {
        final novasVendasRaw = dados['vendas_balcao'] as List;
        final novasVendas = novasVendasRaw.map((map) => VendaBalcao.fromMap(map as Map<String, dynamic>)).toList();
        bool dirty = false;
        for (final venda in novasVendas) {
          final indexLocal = _vendasBalcao.indexWhere((v) => v.id == venda.id);
          
          if (indexLocal != -1) {
            final local = _vendasBalcao[indexLocal];
            bool localEhMesa = local.numero.contains('MESA') || local.numero.contains('CMD') || local.clienteNome?.contains('[') == true;
            bool SupabaseEhMesa = venda.numero.contains('MESA') || venda.numero.contains('CMD') || venda.clienteNome?.contains('[') == true;
            
            if (localEhMesa && !SupabaseEhMesa) {
              debugPrint('>>> [Sync] 🛡️ Preservando Identidade VIP local da Venda: ${local.numero}');
              _vendasBalcao[indexLocal] = venda.copyWith(
                numero: local.numero,
                clienteNome: local.clienteNome,
                observacoes: local.observacoes
              );
              dirty = true;
              continue;
            }
            _vendasBalcao[indexLocal] = venda;
            dirty = true;
          } else {
            _vendasBalcao.add(venda);
            dirty = true;
          }
        }
        if (dirty) {
          _marcarSujo(LocalStorageService.keyVendasBalcao);
        }
        // Vendas baixadas da nuvem também podem chegar sem operador (outro
        // terminal com o bug antigo) — atribuir pelo caixa da época também aqui.
        _atribuirOperadorVendasSemDono();
        print('>>> ✓ ${novasVendas.length} vendas balcão carregadas do Supabase');
      }

      // 9. Trocas/Devoluções
      if (dados['trocas_devolucoes'] != null && dados['trocas_devolucoes'].isNotEmpty) {
        final novasTrocas = (dados['trocas_devolucoes'] as List).map((map) => TrocaDevolucao.fromMap(map as Map<String, dynamic>)).where(_isTrocaDevolucaoValida).toList();
        for (final troca in novasTrocas) {
          final index = _trocasDevolucoes.indexWhere((t) => t.id == troca.id);
          if (index >= 0) {
            _trocasDevolucoes[index] = troca;
          } else {
            _trocasDevolucoes.add(troca);
          }
        }
        _marcarSujo(LocalStorageService.keyTrocasDevolucoes);
        print('>>> ✓ ${novasTrocas.length} trocas/devoluções carregadas do Supabase');
      }

      // 10. Histórico de Estoque
      if (dados['estoque_historico'] != null && dados['estoque_historico'].isNotEmpty) {
        final novosRegistros = (dados['estoque_historico'] as List).map((map) => EstoqueHistorico.fromMap(map as Map<String, dynamic>)).toList();
        for (final registro in novosRegistros) {
          final index = _estoqueHistorico.indexWhere((e) => e.id == registro.id);
          if (index >= 0) {
            _estoqueHistorico[index] = registro;
          } else {
            _estoqueHistorico.add(registro);
          }
        }
        _marcarSujo(LocalStorageService.keyEstoqueHistorico);
        print('>>> ✓ ${novosRegistros.length} registros de estoque carregados do Supabase');
      }

      // 10b. Lotes de Produtos (validade/lote)
      if (dados['lotes_produto'] != null && dados['lotes_produto'].isNotEmpty) {
        final novosLotes = (dados['lotes_produto'] as List).map((map) => LoteProduto.fromMap(map as Map<String, dynamic>)).toList();
        for (final lote in novosLotes) {
          final index = _lotesProdutos.indexWhere((l) => l.id == lote.id);
          if (index >= 0) {
            _lotesProdutos[index] = lote;
          } else {
            _lotesProdutos.add(lote);
          }
        }
        _marcarSujo(LocalStorageService.keyLotesProdutos);
        print('>>> ✓ ${novosLotes.length} lotes de produtos carregados do Supabase');
      }

      // 11. Aberturas de Caixa
      if (dados['aberturas_caixa'] != null && dados['aberturas_caixa'].isNotEmpty) {
        final novasAberturas = (dados['aberturas_caixa'] as List).map((map) => AberturaCaixa.fromMap(map as Map<String, dynamic>)).toList();
        for (final abertura in novasAberturas) {
          final index = _aberturasCaixa.indexWhere((a) => a.id == abertura.id);
          if (index >= 0) {
            _aberturasCaixa[index] = abertura;
          } else {
            _aberturasCaixa.add(abertura);
          }
        }
        _aberturasCaixa.sort((a, b) => a.dataAbertura.compareTo(b.dataAbertura));
        _marcarSujo(LocalStorageService.keyAberturasCaixa);
        // Recalcular o status do caixa após sincronizar aberturas da nuvem
        _caixaAberto = aberturaCaixaAtual != null;
        print('>>> ✓ ${novasAberturas.length} aberturas de caixa carregadas do Supabase');
      }

      // 12. Fechamentos de Caixa
      if (dados['fechamentos_caixa'] != null && dados['fechamentos_caixa'].isNotEmpty) {
        final novosFechamentos = (dados['fechamentos_caixa'] as List).map((map) => FechamentoCaixa.fromMap(map as Map<String, dynamic>)).toList();
        for (final fechamento in novosFechamentos) {
          final index = _fechamentosCaixa.indexWhere((f) => f.id == fechamento.id);
          if (index >= 0) {
            _fechamentosCaixa[index] = fechamento;
          } else {
            _fechamentosCaixa.add(fechamento);
          }
        }
        _fechamentosCaixa.sort((a, b) => a.dataFechamento.compareTo(b.dataFechamento));
        _marcarSujo(LocalStorageService.keyFechamentosCaixa);
        print('>>> ✓ ${novosFechamentos.length} fechamentos de caixa carregadas do Supabase');
      }

      // 13. Mesas/Comandas
      if (dados['mesas_comandas'] != null && dados['mesas_comandas'].isNotEmpty) {
        final novasMesasRaw = (dados['mesas_comandas'] as List)
            .map((map) => MesaComanda.fromMap(map as Map<String, dynamic>))
            .where((m) => !_idsMesaRemovidosRecentemente.contains(m.id))
            .toList();
        _mesclarMesasComandas(novasMesasRaw, isDelta: isDeltaSync);
        _marcarSujo(LocalStorageService.keyMesasComandas);
        print('>>> ✓ ${novasMesasRaw.length} mesas/comandas carregadas do Supabase');
      }

      // 14. Romaneios
      if (dados['romaneios'] != null && dados['romaneios'].isNotEmpty) {
        final novos = (dados['romaneios'] as List).map((map) => Romaneio.fromMap(map as Map<String, dynamic>)).toList();
        for (final item in novos) {
          _romaneios.removeWhere((r) => r.id == item.id);
          _romaneios.add(item);
        }
        _marcarSujo(LocalStorageService.keyRomaneios);
        print('>>> ✓ ${novos.length} romaneios carregados do Supabase');
      }

      // 15. Funcionários
      if (dados['funcionarios'] != null && dados['funcionarios'].isNotEmpty) {
        final novos = (dados['funcionarios'] as List).map((map) => Funcionario.fromMap(map as Map<String, dynamic>)).toList();
        _mesclarSemRemover(_funcionarios, novos);
        _marcarSujo(LocalStorageService.keyFuncionarios);
        print('>>> ✓ ${novos.length} funcionários carregados do Supabase');
      }

      // 16. Taxas de Entrega
      if (dados['taxas_entrega'] != null && dados['taxas_entrega'].isNotEmpty) {
        final novos = (dados['taxas_entrega'] as List).map((map) => TaxaEntrega.fromMap(map as Map<String, dynamic>)).toList();
        _mesclarSemRemover(_taxasEntrega, novos);
        _marcarSujo(LocalStorageService.keyTaxasEntrega);
      }

      // 17. Contas a Pagar
      if (dados['contas_pagar'] != null && dados['contas_pagar'].isNotEmpty) {
        final novos = (dados['contas_pagar'] as List).map((map) => ContaPagar.fromMap(map as Map<String, dynamic>)).toList();
        _mesclarSemRemover(_contasPagar, novos);
        _marcarSujo(LocalStorageService.keyContasPagar);
      }

      // 18. NFC-es e NF-es
      if (dados['nfces'] != null && dados['nfces'].isNotEmpty) {
        final novos = (dados['nfces'] as List).map((map) => NFCe.fromMap(map as Map<String, dynamic>)).toList();
        _mesclarSemRemover(_nfces, novos);
        _marcarSujo(LocalStorageService.keyNFCes);
      }
      if (dados['nfes'] != null && dados['nfes'].isNotEmpty) {
        final novos = (dados['nfes'] as List).map((map) => NFCe.fromMap(map as Map<String, dynamic>)).toList();
        _mesclarSemRemover(_nfes, novos);
        _marcarSujo(LocalStorageService.keyNFEs);
      }

      // 19. Sangrias
      if (dados['sangrias'] != null && dados['sangrias'].isNotEmpty) {
        final novos = (dados['sangrias'] as List).map((map) => SangriaCaixa.fromMap(map as Map<String, dynamic>)).toList();
        _mesclarSemRemover(_sangrias, novos);
        _marcarSujo(LocalStorageService.keySangriasField);
      }

      // 20. Suprimentos
      if (dados['suprimentos'] != null && dados['suprimentos'].isNotEmpty) {
        final novos = (dados['suprimentos'] as List).map((map) => SuprimentoCaixa.fromMap(map as Map<String, dynamic>)).toList();
        _mesclarSemRemover(_suprimentos, novos);
        _marcarSujo(LocalStorageService.keySuprimentosField);
      }

      // 21. Links de Vendedores
      if (dados['links_vendedores'] != null && dados['links_vendedores'].isNotEmpty) {
        final novos = (dados['links_vendedores'] as List).map((map) => LinkVendedor.fromMap(map as Map<String, dynamic>)).toList();
        _mesclarSemRemover(_linksVendedores, novos);
        _marcarSujo(LocalStorageService.keyLinksVendedores);
      }

      // 22. Comissões de Vendedores
      if (dados['comissoes_vendedores'] != null && dados['comissoes_vendedores'].isNotEmpty) {
        final novos = (dados['comissoes_vendedores'] as List).map((map) => ComissaoVendedor.fromMap(map as Map<String, dynamic>)).toList();
        _mesclarSemRemover(_comissoesVendedores, novos);
        _marcarSujo(LocalStorageService.keyComissoesVendedores);
      }

      // 23. Agendamentos
      final agendamentosNoSupabase = dados['agendamentos_servico'] as List?;
      if (agendamentosNoSupabase != null && agendamentosNoSupabase.isNotEmpty) {
        if (!isSilentSync || _agendamentosSubscription == null) {
          final novosAgendamentos = agendamentosNoSupabase.map((map) {
            try {
              final agendamento = AgendamentoServico.fromMap(map as Map<String, dynamic>);
              return _vincularReferenciasAgendamento(agendamento);
            } catch (e) {
              print('>>> ❌ ERRO ao processar agendamento do Supabase: $e');
              return null;
            }
          }).where((a) => a != null).cast<AgendamentoServico>().toList();
          
          for (final agendamento in novosAgendamentos) {
            _upsertAgendamentoLocal(agendamento);
          }
          _marcarSujo(LocalStorageService.keyAgendamentosServico);
          print('>>> ✓ ${novosAgendamentos.length} agendamentos processados com sucesso');
        }
      }

      _ultimaSincronizacaoSucesso = DateTime.now();
      
      // Persistir timestamp de sucesso
      if (_currentEmpresaId != null) {
        final keySync = _getEmpresaKey('exodo_ultima_sincronizacao_sucesso');
        await _storage.salvar(keySync, _ultimaSincronizacaoSucesso!.toIso8601String());
        await _storage.remover(_getEmpresaKey('exodo_ultimo_erro_sync'));
      }

      _ultimoErroSync = null;
      _primeiraCargaAgendamentosRealizada = true;
      debugPrint('>>> [Sync] ✅ Sincronização concluída com sucesso às ${_ultimaSincronizacaoSucesso.toString()}');
      
      final List<String> summary = [];
      if (dados['clientes'] != null && (dados['clientes'] as List).isNotEmpty) summary.add('${(dados['clientes'] as List).length} clientes');
      if (dados['produtos'] != null && (dados['produtos'] as List).isNotEmpty) summary.add('${(dados['produtos'] as List).length} produtos');
      if (dados['servicos'] != null && (dados['servicos'] as List).isNotEmpty) summary.add('${(dados['servicos'] as List).length} serviços');
      if (dados['pedidos'] != null && (dados['pedidos'] as List).isNotEmpty) summary.add('${(dados['pedidos'] as List).length} pedidos');
      if (dados['ordens_servico'] != null && (dados['ordens_servico'] as List).isNotEmpty) summary.add('${(dados['ordens_servico'] as List).length} ordens serv.');
      if (dados['entregas'] != null && (dados['entregas'] as List).isNotEmpty) summary.add('${(dados['entregas'] as List).length} entregas');
      if (dados['notas_entrada'] != null && (dados['notas_entrada'] as List).isNotEmpty) summary.add('${(dados['notas_entrada'] as List).length} notas');
      if (dados['vendas'] != null && (dados['vendas'] as List).isNotEmpty) summary.add('${(dados['vendas'] as List).length} vendas');
      if (dados['trocas_devolucoes'] != null && (dados['trocas_devolucoes'] as List).isNotEmpty) summary.add('${(dados['trocas_devolucoes'] as List).length} trocas');
      if (dados['estoque_historico'] != null && (dados['estoque_historico'] as List).isNotEmpty) summary.add('${(dados['estoque_historico'] as List).length} reg. estoque');
      if (dados['aberturas_caixa'] != null && (dados['aberturas_caixa'] as List).isNotEmpty) summary.add('${(dados['aberturas_caixa'] as List).length} aberturas caixa');
      if (dados['fechamentos_caixa'] != null && (dados['fechamentos_caixa'] as List).isNotEmpty) summary.add('${(dados['fechamentos_caixa'] as List).length} fechamentos caixa');
      if (dados['mesas_comandas'] != null && (dados['mesas_comandas'] as List).isNotEmpty) summary.add('${(dados['mesas_comandas'] as List).length} mesas');
      if (dados['romaneios'] != null && (dados['romaneios'] as List).isNotEmpty) summary.add('${(dados['romaneios'] as List).length} romaneios');
      if (dados['funcionarios'] != null && (dados['funcionarios'] as List).isNotEmpty) summary.add('${(dados['funcionarios'] as List).length} funcionários');
      if (dados['taxas_entrega'] != null && (dados['taxas_entrega'] as List).isNotEmpty) summary.add('${(dados['taxas_entrega'] as List).length} taxas ent.');
      if (dados['contas_pagar'] != null && (dados['contas_pagar'] as List).isNotEmpty) summary.add('${(dados['contas_pagar'] as List).length} contas pagar');
      if (dados['nfces'] != null && (dados['nfces'] as List).isNotEmpty) summary.add('${(dados['nfces'] as List).length} NFC-es');
      if (dados['sangrias'] != null && (dados['sangrias'] as List).isNotEmpty) summary.add('${(dados['sangrias'] as List).length} sangrias');
      if (dados['suprimentos'] != null && (dados['suprimentos'] as List).isNotEmpty) summary.add('${(dados['suprimentos'] as List).length} suprimentos');
      if (dados['links_vendedores'] != null && (dados['links_vendedores'] as List).isNotEmpty) summary.add('${(dados['links_vendedores'] as List).length} links');
      if (dados['comissoes_vendedores'] != null && (dados['comissoes_vendedores'] as List).isNotEmpty) summary.add('${(dados['comissoes_vendedores'] as List).length} comissões');
      if (dados['agendamentos_servico'] != null && (dados['agendamentos_servico'] as List).isNotEmpty) summary.add('${(dados['agendamentos_servico'] as List).length} agendamentos');

      if (summary.isNotEmpty) {
        addSyncLog("✅ Recebido da nuvem: ${summary.join(', ')}.");
      } else {
        addSyncLog("✅ Sincronização concluída com sucesso.");
      }
      
      _sincronizarNotasComDrive();
      
    } catch (e, stackTrace) {
      _ultimoErroSync = e.toString();
      if (_currentEmpresaId != null) {
        _storage.salvar(_getEmpresaKey('exodo_ultimo_erro_sync'), _ultimoErroSync);
      }
      debugPrint('>>> [Sync] ❌ ERRO na sincronização: $e');
      addSyncLog("❌ ERRO na sincronização: $e");
      debugPrint('>>> StackTrace: $stackTrace');
      rethrow;
    } finally {
      _syncEmAndamento = false;
      notifyListeners();
    }
  }

  Future<void> _carregarDadosSalvos() async {
    if (_currentEmpresaId == null) {
      // debugPrint silenciado no boot para evitar spam
      return;
    }
    
    try {
      print('>>> [Performance] ⏱️ Iniciando cronômetro de carregamento local...');
      final stopwatch = Stopwatch()..start();

      // 1. Carregar do LocalStorage com chaves isoladas por empresa
      final clientesMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyClientes));
      final produtosMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyProdutos));
      final servicosMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyServicos));
      final pedidosMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyPedidos));
      final vendasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyVendasBalcao));
      final agendamentosMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyAgendamentosServico));
      final notasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyNotasEntrada));
      final funcionariosMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyFuncionarios));
      final taxasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyTaxasEntrega));
      final contasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyContasPagar));
      final nfcesMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyNFCes));
      final nfesMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyNFEs));
      final mesasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyMesasComandas));
      final sangriasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keySangriasField));
      final suprimentosMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keySuprimentosField));
      final ordensMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyOrdensServico));
      final entregasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyEntregas));
      final trocasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyTrocasDevolucoes));
      final estoqueMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyEstoqueHistorico));
      final linksVendedoresMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyLinksVendedores));
      final comissoesVendedoresMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyComissoesVendedores));
      final romaneiosMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyRomaneios));

      if (clientesMap.isNotEmpty) {
        _clientes.clear();
        _clientes.addAll(clientesMap.map((map) => Cliente.fromMap(map)));
        print('>>> ✓ ${_clientes.length} clientes carregados em ${stopwatch.elapsedMilliseconds}ms');
      }

      if (produtosMap.isNotEmpty) {
        _produtos.clear();
        _produtos.addAll(produtosMap.map((map) => Produto.fromMap(map)));
        print('>>> ✓ ${_produtos.length} produtos carregados em ${stopwatch.elapsedMilliseconds}ms');
      }

      if (servicosMap.isNotEmpty) {
        _tiposServico.clear();
        _tiposServico.addAll(servicosMap.map((map) => Servico.fromMap(map)));
        print('>>> ✓ ${_tiposServico.length} serviços carregados em ${stopwatch.elapsedMilliseconds}ms');
      }

      if (pedidosMap.isNotEmpty) {
        _pedidos.clear();
        _pedidos.addAll(pedidosMap.map((map) => Pedido.fromMap(map)));
        print('>>> ✓ ${_pedidos.length} pedidos carregados em ${stopwatch.elapsedMilliseconds}ms');
      }

      if (vendasMap.isNotEmpty) {
        _vendasBalcao.clear();
        _vendasBalcao.addAll(vendasMap.map((map) => VendaBalcao.fromMap(map)));
        print('>>> ✓ ${_vendasBalcao.length} vendas carregadas em ${stopwatch.elapsedMilliseconds}ms');
      }

      if (agendamentosMap.isNotEmpty) {
        final novos = agendamentosMap.map((map) {
          final a = AgendamentoServico.fromMap(map);
          return _vincularReferenciasAgendamento(a);
        }).toList();
        _agendamentosServico.clear();
        _agendamentosServico.addAll(novos);
        print('>>> ✓ ${_agendamentosServico.length} agendamentos carregados em ${stopwatch.elapsedMilliseconds}ms');
      }

      if (contasMap.isNotEmpty) {
        _contasPagar.clear();
        _contasPagar.addAll(contasMap.map((map) => ContaPagar.fromMap(map as Map<String, dynamic>)));
      }

      if (sangriasMap.isNotEmpty) {
        _sangrias.clear();
        _sangrias.addAll(sangriasMap.map((map) => SangriaCaixa.fromMap(map)));
      }

      if (suprimentosMap.isNotEmpty) {
        _suprimentos.clear();
        _suprimentos.addAll(suprimentosMap.map((map) => SuprimentoCaixa.fromMap(map)));
      }

      if (notasMap.isNotEmpty) {
        _notasEntrada.clear();
        _notasEntrada.addAll(notasMap.map((map) => NotaEntrada.fromMap(map)));
      }

      if (taxasMap.isNotEmpty) {
        _taxasEntrega.clear();
        _taxasEntrega.addAll(taxasMap.map((map) => TaxaEntrega.fromMap(map)));
      }

      if (ordensMap.isNotEmpty) {
        _ordensServico.clear();
        _ordensServico.addAll(ordensMap.map((map) => OrdemServico.fromMap(map)));
      }

      if (entregasMap.isNotEmpty) {
        _entregas.clear();
        _entregas.addAll(entregasMap.map((map) => Entrega.fromMap(map)));
      }

      if (trocasMap.isNotEmpty) {
        _trocasDevolucoes.clear();
        _trocasDevolucoes.addAll(trocasMap.map((map) => TrocaDevolucao.fromMap(map)).where(_isTrocaDevolucaoValida));
      }

      if (estoqueMap.isNotEmpty) {
        _estoqueHistorico.clear();
        _estoqueHistorico.addAll(estoqueMap.map((map) => EstoqueHistorico.fromMap(map)));
      }

      final lotesMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyLotesProdutos));
      if (lotesMap.isNotEmpty) {
        _lotesProdutos.clear();
        _lotesProdutos.addAll(lotesMap.map((map) => LoteProduto.fromMap(map)));
      }

      print('>>> [Carregamento] ⚙️ Carregando operacional...');
      final aberturasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyAberturasCaixa));
      if (aberturasMap.isNotEmpty) {
        _aberturasCaixa.clear();
        _aberturasCaixa.addAll(aberturasMap.map((map) => AberturaCaixa.fromMap(map)));
        _aberturasCaixa.sort((a, b) => a.dataAbertura.compareTo(b.dataAbertura));
      }

      final fechamentosMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyFechamentosCaixa));
      if (fechamentosMap.isNotEmpty) {
        _fechamentosCaixa.clear();
        _fechamentosCaixa.addAll(fechamentosMap.map((map) => FechamentoCaixa.fromMap(map)));
        _fechamentosCaixa.sort((a, b) => a.dataFechamento.compareTo(b.dataFechamento));
      }

      if (mesasMap.isNotEmpty) {
        final listasMesas = mesasMap.map((map) => MesaComanda.fromMap(map as Map<String, dynamic>)).toList();
        _mesasComandas.clear();
        _mesasComandas.addAll(listasMesas);
      }

      final motoristasMap = await _storage.carregarLista(_getEmpresaKey(LocalStorageService.keyMotoristas));
      if (motoristasMap.isNotEmpty) {
        _motoristas.clear();
        _motoristas.addAll(motoristasMap.map((map) => Motorista.fromMap(map)));
      }

      if (funcionariosMap.isNotEmpty) {
        _funcionarios.clear();
        _funcionarios.addAll(funcionariosMap.map((map) => Funcionario.fromMap(map)));
      }

      if (linksVendedoresMap.isNotEmpty) {
        _linksVendedores.clear();
        _linksVendedores.addAll(linksVendedoresMap.map((map) => LinkVendedor.fromMap(map)));
      }

      if (comissoesVendedoresMap.isNotEmpty) {
        _comissoesVendedores.clear();
        _comissoesVendedores.addAll(comissoesVendedoresMap.map((map) => ComissaoVendedor.fromMap(map)));
      }
      
      if (romaneiosMap.isNotEmpty) {
        _romaneios.clear();
        _romaneios.addAll(romaneiosMap.map((map) => Romaneio.fromMap(map)));
      }

      print('>>> [Carregamento] 🧾 Carregando fiscal...');
      if (nfcesMap.isNotEmpty) {
        _nfces.clear();
        _nfces.addAll(nfcesMap.map((map) => NFCe.fromMap(map)));
      }
      if (nfesMap.isNotEmpty) {
        _nfes.clear();
        _nfes.addAll(nfesMap.map((map) => NFCe.fromMap(map)));
      }

      print('>>> [Carregamento] 🔗 Otimizando vínculos...');
      _reVincularTodosAgendamentos(); 

      // Carregar data da última sincronização bem-sucedida
      final keySync = _getEmpresaKey('exodo_ultima_sincronizacao_sucesso');
      final syncString = await _storage.carregar(keySync);
      if (syncString is String && syncString.isNotEmpty) {
        _ultimaSincronizacaoSucesso = DateTime.tryParse(syncString);
        debugPrint('>>> [Sync] 🕒 Recuperada data de última sincronização: $_ultimaSincronizacaoSucesso');
      }
      
      // Migração: vendas legadas sem operador somem dos caixas nominados.
      // Atribui o operador pelo caixa da época (idempotente).
      _atribuirOperadorVendasSemDono();
      
      stopwatch.stop();
      print('>>> ✓ CARREGAMENTO LOCAL COMPLETO: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e, stackTrace) {
      print('>>> ✗ Erro ao carregar dados locais: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Migração de dados: vendas antigas sem `operador` (criadas antes do caixa
  /// nominado ou por caminhos que não preenchiam o campo) ficavam invisíveis
  /// nos caixas com responsável — getVendasDoCaixa exclui venda sem operador
  /// de caixa nominado. Atribui o operador pelo caixa aberto na época da venda:
  ///   - venda dentro da janela de um caixa → operador = responsável do caixa;
  ///   - caixa sem responsável → carlos@gmail.com (operador principal);
  ///   - venda fora de qualquer janela → carlos@gmail.com.
  /// Idempotente: só altera vendas SEM operador (não mexe em 'user'/silva).
  void _atribuirOperadorVendasSemDono() {
    if (_vendasBalcao.isEmpty || _aberturasCaixa.isEmpty) return;

    // Janelas de caixa: [dataAbertura, dataFechamento ou agora).
    final janelas = <({DateTime inicio, DateTime fim, String responsavel})>[];
    for (final ab in _aberturasCaixa) {
      DateTime? fim;
      for (final f in _fechamentosCaixa) {
        if (f.aberturaCaixaId == ab.id) {
          fim = f.dataFechamento;
          break;
        }
      }
      janelas.add((
        inicio: ab.dataAbertura,
        fim: fim ?? DateTime.now(),
        responsavel: (ab.responsavel ?? '').trim(),
      ));
    }
    if (janelas.isEmpty) return;

    bool mudou = false;
    for (final venda in _vendasBalcao) {
      if ((venda.operador ?? '').trim().isNotEmpty) continue;

      ({DateTime inicio, DateTime fim, String responsavel})? melhor;
      for (final j in janelas) {
        final dentro = !venda.dataVenda.isBefore(j.inicio) &&
            venda.dataVenda.isBefore(j.fim);
        if (!dentro) continue;
        if (melhor == null || j.inicio.isAfter(melhor.inicio)) melhor = j;
      }
      final resp = melhor?.responsavel;
      final novoOperador =
          (resp != null && resp.isNotEmpty) ? resp : 'carlos@gmail.com';
      final idx = _vendasBalcao.indexOf(venda);
      _vendasBalcao[idx] = venda.copyWith(operador: novoOperador);
      mudou = true;
    }

    if (mudou) {
      print('>>> [Migração] ⚙️ Vendas legadas sem operador atribuídas pelo caixa da época.');
      _marcarSujo(LocalStorageService.keyVendasBalcao);
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

  /// Método avançado para mesclar dados do Supabase com o estado local
  /// Evita o "piscar" de dados e a perda de itens recém-criados localmente
  void _mesclarListaSincronizada<T>(List<T> listaLocal, List<T> vindosDoSupabase) {
    if (vindosDoSupabase.isEmpty) {
      if (_importandoExcel) {
        debugPrint('>>> [Sync] 🛡️ Ignorando snapshot VAZIO durante importação ativa.');
        return;
      }
      
      // PROTEÇÃO: Se a lista local é MUITO grande (ex: >100) e o Supabase retornou vazio,
      // pode ser um erro de rede, delay de indexação ou snapshot parcial. Não limpar.
      if (listaLocal.length > 100) {
        debugPrint('>>> [Sync] 🛡️ Alerta: Supabase retornou vazio para lista com ${listaLocal.length} itens. Preservando dados locais.');
        return;
      }
      
      listaLocal.clear();
      return;
    }

    // PROTEÇÃO CONTRA DELAY DE INDEXAÇÃO / SNAPSHOT PARCIAL
    // Se a lista local já tem conteúdo e o Supabase retornou algo MUITO menor (menos de 10% da local)
    // Provavelmente é um snapshot inicial ou parcial. Não vamos deletar o restante ainda.
    if (listaLocal.length > 100 && vindosDoSupabase.length < (listaLocal.length * 0.1)) {
       debugPrint('>>> [Sync] 🛡️ Ignorando snapshot parcial suspeito: Local=${listaLocal.length}, Cloud=${vindosDoSupabase.length}. Preservando memória.');
       // Ainda assim, atualizamos os que vieram
       _mesclarSemRemover(listaLocal, vindosDoSupabase);
       return;
    }

    // MAPA COM INDEX PARA BUSCA O(1)
    final Map<String, int> indexMap = {
      for (int i = 0; i < listaLocal.length; i++) 
        (listaLocal[i] as dynamic).id: i
    };

    bool houveAlgumaMudanca = false;

    for (final novo in vindosDoSupabase) {
      final id = (novo as dynamic).id;
      final idx = indexMap[id];
      
      if (idx != null) {
        // ATUALIZAÇÃO SÓ SE O TIMESTAMP FOR DIFERENTE
        // Isso economiza MUITO processamento de UI em listas grandes (6k+ itens)
        final local = listaLocal[idx];
        if ((local as dynamic).updatedAt != (novo as dynamic).updatedAt) {
          listaLocal[idx] = novo;
          houveAlgumaMudanca = true;
        }
      } else {
        // Adicionar novo vindo da nuvem
        listaLocal.add(novo);
        houveAlgumaMudanca = true;
      }
    }

    // PROTEÇÃO ADICIONAL PARA REMOÇÃO (Só remove se não estiver no Supabase E passar no tempo de proteção)
    final Set<String> idsSupabase = vindosDoSupabase.map((e) => (e as dynamic).id as String).toSet();
    final agora = DateTime.now();
    
    final lenAntes = listaLocal.length;
    listaLocal.removeWhere((item) {
      final id = (item as dynamic).id;
      if (idsSupabase.contains(id)) return false;
      
      final createdAt = (item as dynamic).createdAt as DateTime?;
      if (createdAt == null) return true; 
      
      // Se é muito recente, manter (pode estar subindo pro Supabase)
      final idade = agora.difference(createdAt).inSeconds;
      if (idade < 600) { // 10 minutos de proteção
        debugPrint('>>> [Sync] 🛡️ Mantendo item local recém-criado: $id (idade: ${idade}s)');
        return false;
      }
      
      // PROTEÇÃO ADICIONAL: Se a lista vinda do Supabase é suspeitamente pequena 
      // comparada com a local (ex: menos de 10% da local) e a local é grande, 
      // não removemos itens antigos pois pode ser uma carga parcial/limitada.
      if (listaLocal.length > 1000 && vindosDoSupabase.length < (listaLocal.length * 0.5)) {
        // Se o item não está no Supabase, mas a carga parece parcial, mantemos.
        return false;
      }
      
      return true;
    });
    
    if (lenAntes != listaLocal.length) houveAlgumaMudanca = true;
  }

  /// Mescla dados vindos da nuvem sem remover os locais que não estão no snapshot
  /// Útil para snapshots parciais ou buscas limitadas. Protege edições locais mais novas usando o updatedAt.
  void _mesclarSemRemover<T>(List<T> listaLocal, List<T> vindos) {
    if (vindos.isEmpty) return;
    
    final Map<String, int> indexMap = {
      for (int i = 0; i < listaLocal.length; i++) (listaLocal[i] as dynamic).id: i
    };

    for (final novo in vindos) {
      final id = (novo as dynamic).id;
      if (indexMap.containsKey(id)) {
        final index = indexMap[id]!;
        final local = listaLocal[index];
        
        try {
          final DateTime localUpdated = (local as dynamic).updatedAt;
          final DateTime novoUpdated = (novo as dynamic).updatedAt;
          if (novoUpdated.isBefore(localUpdated)) {
            // Ignora o item da nuvem se o local for mais novo
            debugPrint('>>> [Sync] 🛡️ Ignorando item antigo da nuvem para $id. Local: $localUpdated, Cloud: $novoUpdated');
            continue;
          }
        } catch (_) {
          // Fallback se o objeto não tiver updatedAt
        }
        
        listaLocal[index] = novo;
      } else {
        listaLocal.add(novo);
      }
    }
  }

  static void _atualizarListaInPlace<T>(List<T> listaAtual, List<T> novosItens) {
    if (novosItens.isEmpty) {
      listaAtual.clear();
      return;
    }

    // BARREIRA DE SEGURANÇA: Limite aumentado para 25.000 itens para suportar catálogos massivos
    final List<T> itensSeguros = novosItens.length > 25000 
        ? novosItens.take(25000).toList() 
        : novosItens;

    if (novosItens.length > 15000) {
      debugPrint('>>> [Memória] 🛡️ Alerta: Lista com ${novosItens.length} itens. Mantendo até 25.000 para estabilidade.');
    }

    listaAtual.clear();
    listaAtual.addAll(itensSeguros);
  }

  /// Mescla mesas/comandas no estado local de forma inteligente baseada em updatedAt
  /// Mescla mesas/comandas vindas do Supabase com o estado local.
  ///
  /// [isDelta] indica se a carga veio de uma sincronização DELTA (apenas linhas
  /// atualizadas desde o último sync). Nesses casos NÃO removemos nada da lista
  /// local: remover o que não veio apagaria TODO o histórico de mesas/comandas
  /// (abertas, fechadas e deletadas). Deleções feitas em outros dispositivos são
  /// propagadas pelo Realtime (evento DELETE), então aqui apenas adicionamos/atualizamos.
  void _mesclarMesasComandas(List<MesaComanda> novos, {bool isDelta = false}) {
    if (novos.isEmpty) return;

    bool houveMudanca = false;
    for (final novo in novos) {
      final index = _mesasComandas.indexWhere((m) => m.id == novo.id);
      if (index != -1) {
        final existente = _mesasComandas[index];
        // Merge inteligente: Preferir a versão com updatedAt mais recente
        if (novo.updatedAt.isAfter(existente.updatedAt)) {
          // Verificar se tem itens novos em mesa aberta antes de atualizar
          if (novo.status == 'Aberta' && novo.itens.length > existente.itens.length) {
            _tocarSomNotificacao();
            debugPrint('>>> [Realtime] 🔔 Novo item detectado na mesa/comanda ${novo.numero}');
          }
          _mesasComandas[index] = novo;
          houveMudanca = true;
        }
      } else {
        // Nova mesa/comanda
        _mesasComandas.add(novo);
        houveMudanca = true;
      }
    }

    // ⚠️ PROTEÇÃO DO HISTÓRICO: em sincronização DELTA não removemos nada.
    if (isDelta) {
      debugPrint('>>> [Sync] 🛡️ Merge delta: mesas/comandas não presentes no snapshot foram MANTIDAS (histórico preservado).');
      if (houveMudanca) {
        notifyListeners();
      }
      return;
    }

    // Identificar itens que sumiram do Supabase mas estão no local (apenas carga completa)
    final idsNovos = novos.map((m) => m.id).toSet();
    final antesContagem = _mesasComandas.length;
    final agora = DateTime.now();

    // Proteção adicional: se a carga veio suspeitamente pequena comparada com a
    // lista local (carga parcial/limitada/erro), não removemos nada para não
    // destruir o histórico local.
    final cargaPareceParcial = _mesasComandas.length > 500 &&
        novos.length < (_mesasComandas.length * 0.5);

    _mesasComandas.removeWhere((m) {
      if (cargaPareceParcial) return false;
      if (!idsNovos.contains(m.id)) {
        // Proteção 1: Se é muito recente (criada nos últimos 10 minutos), manter!
        final idade = agora.difference(m.createdAt).inSeconds;
        if (idade < 600) {
          debugPrint('>>> [Sync] 🛡️ Mantendo Mesa/Comanda local recém-criada: ${m.numero} (idade: ${idade}s)');
          return false;
        }
        
        // Proteção 2: Se foi modificada recentemente localmente (últimos 5 minutos), manter!
        final idadeModificacao = agora.difference(m.updatedAt).inSeconds;
        if (idadeModificacao < 300) {
          debugPrint('>>> [Sync] 🛡️ Mantendo Mesa/Comanda local modificada recentemente: ${m.numero} (idade: ${idadeModificacao}s)');
          return false;
        }

        // Se sumiu da lista nova e NÃO foi removido recentemente aqui, 
        // significa que foi deletado em outro lugar.
        return !_idsMesaRemovidosRecentemente.contains(m.id);
      }
      return false;
    });
    
    if (_mesasComandas.length != antesContagem) houveMudanca = true;

    if (houveMudanca) {
      notifyListeners();
    }
  }

  /// Salva todos os dados no localStorage e Supabase
  Future<void> _salvarTodosDados({bool aguardarSupabase = true, bool forcarTodos = false, bool isSync = false}) async {
    if (!_persistenciaHabilitada) return;

    try {
      // OTIMIZAÇÃO CRÍTICA: Se a memória estiver pesada, limitar histórico
      _manterApenasRecentes(_estoqueHistorico, 300, 'Estoque');
      _manterApenasRecentes(_vendasBalcao, 10000, 'Vendas');
      _manterApenasRecentes(_ordensServico, 10000, 'Ordens de Serviço');
      _manterApenasRecentes(_pedidos, 10000, 'Pedidos');
      _manterApenasRecentes(_notasEntrada, 100, 'Notas de Entrada');
      _manterApenasRecentes(_trocasDevolucoes, 200, 'Trocas');
      _manterApenasRecentes(_agendamentosServico, 800, 'Agendamentos');
      _manterApenasRecentes(_nfces, 200, 'NFC-es');
      _manterApenasRecentes(_sangrias, 100, 'Sangrias');
      _manterApenasRecentes(_suprimentos, 100, 'Suprimentos');
      _manterApenasRecentes(_romaneios, 100, 'Romaneios');

      // Se não for para forçar todos e não temos coleções sujas, retornamos imediatamente
      if (!forcarTodos && _dirtyCollections.isEmpty) {
        return;
      }

      // Salvar no localStorage SEQUENCIALMENTE para evitar Database Lock no PostgreSQL (Windows)
      try {
        final Map<String, List<dynamic>> colecoes = {
          LocalStorageService.keyClientes: _clientes,
          LocalStorageService.keyProdutos: _produtos,
          LocalStorageService.keyServicos: _tiposServico,
          LocalStorageService.keyPedidos: _pedidos,
          LocalStorageService.keyVendasBalcao: _vendasBalcao,
          LocalStorageService.keyAgendamentosServico: _agendamentosServico,
          LocalStorageService.keyNotasEntrada: _notasEntrada,
          LocalStorageService.keyFuncionarios: _funcionarios,
          LocalStorageService.keyTaxasEntrega: _taxasEntrega,
          LocalStorageService.keyContasPagar: _contasPagar,
          LocalStorageService.keyNFCes: _nfces,
          LocalStorageService.keyNFEs: _nfes,
          LocalStorageService.keyMesasComandas: _mesasComandas,
          LocalStorageService.keySangriasField: _sangrias,
          LocalStorageService.keySuprimentosField: _suprimentos,
          LocalStorageService.keyOrdensServico: _ordensServico,
          LocalStorageService.keyEntregas: _entregas,
          LocalStorageService.keyTrocasDevolucoes: _trocasDevolucoes,
          LocalStorageService.keyEstoqueHistorico: _estoqueHistorico,
          LocalStorageService.keyLotesProdutos: _lotesProdutos,
          LocalStorageService.keyLinksVendedores: _linksVendedores,
          LocalStorageService.keyComissoesVendedores: _comissoesVendedores,
          LocalStorageService.keyRomaneios: _romaneios,
          LocalStorageService.keyMotoristas: _motoristas, // Bug Fix: motoristas estavam ausentes do mapa
        };

        int tabelasSalvasCount = 0;
        for (var entry in colecoes.entries) {
          final isDirty = _dirtyCollections.contains(entry.key);
          if (forcarTodos || isDirty) {
            await _storage.salvarLista(_getEmpresaKey(entry.key), entry.value, isSync: isSync);
            tabelasSalvasCount++;
            // Pequena pausa para o banco respirar entre tabelas
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }
        
        if (tabelasSalvasCount > 0) {
          print('>>> ✓ $tabelasSalvasCount tabelas modificadas foram salvas no localStorage');
        }
        
      } catch (e) {
        debugPrint('>>> [Memória] ❌ Erro no salvamento seletivo: $e');
      }
      
      _dirtyCollections.clear();
      
      // PROTEÇÃO: Removido re-read para validar (economiza 50% de CPU/RAM no salvamento)

      // Sincronizar com Supabase apenas se:
      // 1. Supabase está habilitado
      // 2. Tem empresa selecionada
      // 3. For uma operação manual/forçada (aguardarSupabase: true) 
      //    OU se realmente passou o intervalo (90 dias) e o app está ocioso
      final agora = DateTime.now();
      final deveSincronizarTotal = aguardarSupabase || 
        (_ultimaSincronizacaoSucesso == null && !_isOffline) || 
        agora.difference(_ultimaSincronizacao ?? agora.subtract(const Duration(days: 1))) > _intervaloSincronizacao;

      if (SupabaseService.isAvailable && _currentEmpresaId != null && deveSincronizarTotal) {
        if (aguardarSupabase) {
          // Para operações críticas (como fechar caixa), aguarda o Supabase
          try {
            await _sincronizarComSupabase();
            _ultimaSincronizacao = agora;
            print('>>> ✓ Todos os dados foram sincronizados com Supabase (aguardado)');
          } catch (e) {
            print('>>> ✗ Erro ao sincronizar com Supabase: $e');
            _adicionarSincronizacaoPendente();
          }
        } else if (_ultimaSincronizacao == null) {
          // background sync - APENAS SE FOR A PRIMEIRA VEZ para esta empresa
          // Isso garante que dados locais subam para o Supabase se ele estiver vazio
          debugPrint('>>> [Sync] 📡 Iniciando sincronização inicial em background para empresa $currentEmpresaId...');
           _sincronizarComSupabase().then((_) {
             _ultimaSincronizacao = agora;
             _ultimaSincronizacaoSucesso = agora;
             notifyListeners();
             debugPrint('>>> [Sync] ✅ Sincronização inicial em background concluída.');
           }).catchError((e) {
             debugPrint('>>> [Sync] ❌ Erro na sincronização inicial em background: $e');
             _adicionarSincronizacaoPendente();
           });
        } else {
          // background sync - APENAS SE FOR REALMENTE NECESSÁRIO (evitando picos de gravações)
          debugPrint('>>> [Sync] 📡 Ignorando sincronização TOTAL automática para poupar banda do Supabase.');
          debugPrint('>>> [Sync]    As mudanças individuais (clientes, pedidos, etc) já são salvas em tempo real.');
        }
      } else if (!deveSincronizarTotal) {
        // debugPrint('>>> [Sync] Pulando sincronização total (uso de cotas otimizado)');
      }
    } catch (e) {
      print('>>> ✗ Erro ao salvar dados: $e');
    }
  }

  /// Sincroniza todos os dados com Supabase
  /// Executa de forma assíncrona com timeout para evitar travamentos
  Future<void> _sincronizarComSupabase() async {
    if (_currentEmpresaId == null) {
      debugPrint('>>> [Sync] ⚠️ Empresa não selecionada, pulando sincronização');
      return;
    }
    
    if (!SupabaseService.isAvailable) {
      debugPrint('>>> [Sync] ⚠️ Supabase não disponível, pulando...');
      return;
    }
    
    addSyncLog("Enviando dados locais para a nuvem...");
    
    try {
      // Timeout de 60 segundos para evitar travamentos
      await _supabaseService.salvarTudoNoSupabase(
        empresaId: _currentEmpresaId!,
        clientes: _clientes,
        produtos: _produtos,
        servicos: _tiposServico,
        pedidos: _pedidos,
        ordensServico: _ordensServico,
        entregas: _entregas,
        vendasBalcao: _vendasBalcao,
        trocasDevolucoes: _trocasDevolucoes,
        estoqueHistorico: _estoqueHistorico,
        lotesProdutos: _lotesProdutos,
        aberturasCaixa: _aberturasCaixa,
        fechamentosCaixa: _fechamentosCaixa,
        motoristas: _motoristas,
        agendamentosServico: _agendamentosServico,
        notasEntrada: _notasEntrada,
        funcionarios: _funcionarios,
        romaneios: _romaneios,
        taxasEntrega: _taxasEntrega,
        contasPagar: _contasPagar,
        nfces: _nfces,
        nfes: _nfes,
        sangrias: _sangrias,
        suprimentos: _suprimentos,
        linksVendedores: _linksVendedores,
        comissoesVendedores: _comissoesVendedores,
        mesasComandas: _mesasComandas,
        empresa: _empresaAtual,
      ).timeout(
        const Duration(minutes: 10), // Aumentado para 10 minutos para grandes catálogos
        onTimeout: () {
          debugPrint('>>> [Sync] ⚠️ Timeout ao sincronizar com Supabase (10min)');
          throw TimeoutException('Timeout na sincronização com Supabase. A rede pode estar lenta ou o volume de dados é muito alto.');
        },
      );
      
      debugPrint('>>> [Sync] ✅ Sincronização com Supabase concluída com sucesso');
      _ultimaSincronizacaoSucesso = DateTime.now();
      _ultimaSincronizacao = _ultimaSincronizacaoSucesso;

      // Persistir timestamp de sucesso e remover erro anterior
      if (_currentEmpresaId != null) {
        final keySync = _getEmpresaKey('exodo_ultima_sincronizacao_sucesso');
        await _storage.salvar(keySync, _ultimaSincronizacaoSucesso!.toIso8601String());
        await _storage.remover(_getEmpresaKey('exodo_ultimo_erro_sync'));
      }
      _ultimoErroSync = null;

      addSyncLog("✅ Envio de dados concluído com sucesso.");
    } catch (e, stackTrace) {
      _ultimoErroSync = e.toString();
      if (_currentEmpresaId != null) {
        await _storage.salvar(_getEmpresaKey('exodo_ultimo_erro_sync'), _ultimoErroSync);
      }
      debugPrint('>>> [Sync] ❌ Erro ao sincronizar com Supabase: $e');
      debugPrint('>>> [Sync] StackTrace: $stackTrace');
      addSyncLog("❌ Erro ao enviar dados: $e");
      // Em caso de erro, não marcamos como sucesso para que o sistema tente novamente no próximo pulso
    } finally {
      _syncEmAndamento = false;
      notifyListeners();
    }
  }

  /// Sincronização forçada iniciada pelo usuário
  Future<void> sincronizarManualmente() async {
    _isLoading = true;
    _mensagemLoading = 'Sincronizando com nuvem...';
    notifyListeners();
    
    try {
      await _sincronizarComSupabase();
      _ultimaSincronizacao = DateTime.now();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _limparCacheLocalCompleto() {
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
    _lotesProdutos.clear();
    _notasEntrada.clear();
    _agendamentosServico.clear();
    _funcionarios.clear();
    _taxasEntrega.clear();
    _contasPagar.clear();
    _nfces.clear();
    _mesasComandas.clear();
    _linksVendedores.clear();
    _comissoesVendedores.clear();
    _romaneios.clear();
    _aberturasCaixa.clear();
    _fechamentosCaixa.clear();
    _sangrias.clear();
    _suprimentos.clear();
    _bridgesStatus.clear();
    _dirtyCollections.clear();
    _idsMesaRemovidosRecentemente.clear();

    _ultimaSincronizacao = null;
    _ultimaSincronizacaoSucesso = null;
    _ultimoErroSync = null;

    debugPrint('>>> [DataService] 🧹 Cache local completo limpo para forçar recarga da nuvem.');
  }

  /// Força a limpeza do cache local e recarregamento total do Supabase
  Future<void> recarregarTudoDoSupabase() async {
    _isLoading = true;
    _mensagemLoading = 'Baixando dados da nuvem...';
    notifyListeners();
    
    try {
      await _carregarDadosDoSupabase(modoLeve: false);
      _ultimaSincronizacao = DateTime.now();
      _ultimaSincronizacaoSucesso = _ultimaSincronizacao;
      _ultimoErroSync = null;
    } catch (e) {
      debugPrint('>>> [DataService] ❌ Erro no recarregamento total: $e');
      _ultimoErroSync = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// TESTE: Limpa apenas os dados locais (memória e PostgreSQL) sem deletar na nuvem
  Future<void> resetLocalCacheOnly() async {
    _isLoading = true;
    _mensagemLoading = 'Limpando base local para teste...';
    notifyListeners();

    try {
      // 1. Limpar listas na memória
      _clientes.clear();
      _produtos.clear();
      _pedidos.clear();
      _vendasBalcao.clear();
      _aberturasCaixa.clear();
      _fechamentosCaixa.clear();
      _entregas.clear();
      _notasEntrada.clear();
      _funcionarios.clear();
      
      // 2. Salvar estado vazio localmente (sobrescreve o PostgreSQL/Storage)
      // aguardarSupabase: false garante que NÃO DELETA na nuvem
      await _salvarTodosDados(aguardarSupabase: false);
      
      _ultimaSincronizacaoSucesso = null; // Resetar status de sync
      debugPrint('>>> [DataService] 🧹 Cache local limpo com sucesso (Nuvem intacta)');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adiciona sincronização pendente à fila
  void _adicionarSincronizacaoPendente({String? table, Map<String, dynamic>? data, String? type}) {
    if (_currentEmpresaId == null) {
      debugPrint('>>> [Sync] ⚠️ Não é possível adicionar à fila: empresa não selecionada');
      return;
    }
    
    if (table != null && data != null) {
      final operationType = type ?? 'upsert';
      debugPrint('>>> [Sync] 📋 Item específico adicionado à fila: $table (${data['id']}) - $operationType');
      _syncQueue.enqueue(SyncOperation(
        type: operationType,
        dataId: data['id']?.toString() ?? 'unknown',
        empresaId: _currentEmpresaId,
        data: {'tabela': table, 'dados': data},
        execute: () async {
          if (operationType == 'DELETE') {
            await _deleteNoSupabase(table, data['id'] as String);
          } else {
            await _upsertNoSupabase(table, data);
          }
        },
      ));
    } else {
      debugPrint('>>> [Sync] 📋 Sincronização total pendente adicionada à fila');
      _syncQueue.enqueue(SyncOperation(
        type: 'retry_sync',
        dataId: _currentEmpresaId!,
        empresaId: _currentEmpresaId,
        data: {'msg': 'Sincronização pendente forçada'},
        execute: () async {
          // Aguarda um pouco antes de tentar a sincronização total novamente para evitar loops
          await Future.delayed(const Duration(seconds: 30));
          await _sincronizarComSupabase();
        },
      ));
    }
    
    // Tentar sincronizar imediatamente se tiver conexão
    if (SupabaseService.isAvailable) {
      _syncQueue.forceSync().catchError((e) {
        debugPrint('>>> [Sync] ⚠️ Erro ao forçar sincronização: $e');
      });
    }
  }

  /// Resolve operações que foram carregadas do Banco 2 (PostgreSQL)
  Future<void> _resolverOperacaoSync(String type, String dataId, Map<String, dynamic> data) async {
    debugPrint('>>> [Sync] 🔎 Resolvendo operação persistente: $type (ID: $dataId)');
    
    if (type == 'retry_sync') {
      // Para retry_sync, simplesmente rodamos a sincronização total
      await _sincronizarComSupabase();
    } else if (type == 'upsert') {
      // Exemplo de como suportar outros tipos específicos no futuro
      final tabela = data['tabela'] as String?;
      final dados = data['dados'] as Map<String, dynamic>?;
      if (tabela != null && dados != null) {
        await _upsertNoSupabase(tabela, dados);
      }
    }
  }
  
  /// Retorna informações sobre sincronização pendente
  Map<String, dynamic> getInfoSincronizacao() {
    return _syncQueue.getQueueInfo();
  }

  bool _salvamentoAgendadoDuranteExecucao = false;

  /// Salva automaticamente os dados após uma mudança (não bloqueia)
  /// Usa debounce para evitar salvamentos excessivos que causam travamentos
  void _salvarAutomaticamente() {
    if (!_persistenciaHabilitada) return;
    
    if (_salvandoDados) {
      _salvamentoAgendadoDuranteExecucao = true;
      debugPrint('>>> [DataService] ⏳ Salvamento já em andamento. Agendando nova execução após término.');
      return;
    }
    
    // Cancelar salvamento anterior se houver
    _debounceSalvamento?.cancel();
    
    // Agendar novo salvamento com debounce
    _debounceSalvamento = Timer(_debounceDelay, () {
      _executarSalvamentoAutomatico();
    });
  }

  Future<void> _executarSalvamentoAutomatico() async {
    if (!_persistenciaHabilitada) return;
    
    _salvandoDados = true;
    _salvamentoAgendadoDuranteExecucao = false;
    
    try {
      await _salvarTodosDados(aguardarSupabase: false);
    } catch (e) {
      debugPrint('>>> [DataService] ❌ Erro ao salvar automaticamente: $e');
    } finally {
      _salvandoDados = false;
      // Se houve alguma chamada para salvar enquanto este salvamento estava em execução, executa novamente
      if (_salvamentoAgendadoDuranteExecucao) {
        _salvamentoAgendadoDuranteExecucao = false;
        _salvarAutomaticamente();
      }
    }
  }

  /// Salva imediatamente sem debounce (útil para operações críticas)
  Future<void> salvarImediatamente() async {
    debugPrint('>>> [DataService] 🏃 salvarImediatamente() chamado. Dirty: $_dirtyCollections');
    if (!_persistenciaHabilitada) {
      debugPrint('>>> [DataService] 🛑 Persistência desabilitada. Abortando salvarImediatamente.');
      return;
    }
    
    // Cancelar qualquer salvamento agendado
    _debounceSalvamento?.cancel();
    
    if (_salvandoDados) {
      debugPrint('>>> [DataService] ⏳ Já existe um salvamento em curso, aguardando...');
      // Se já está salvando, aguardar um pouco
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    _salvandoDados = true;
    try {
      // OTIMIZAÇÃO: Não forçar sincronização total do Supabase aqui. 
      // Os métodos CRUD individuais já fazem o push de seus próprios dados.
      // salvarImediatamente() agora foca em garantir a persistência LOCAL (Storage).
      await _salvarTodosDados(aguardarSupabase: false);
      debugPrint('>>> [DataService] ✅ salvarImediatamente concluído com sucesso (foco LocalStorage).');
    } catch (e) {
      debugPrint('>>> [DataService] ❌ Erro ao salvar imediatamente: $e');
      rethrow;
    } finally {
      _salvandoDados = false;
    }
  }
  
  // ============ CRUD NFC-e ============

  /// Adiciona uma NFC-e ou NF-e
  Future<void> adicionarNFCe(NFCe nfce) async {
    final isNfe = nfce.modelo == 55;
    if (isNfe) {
      _nfes.add(nfce);
    } else {
      _nfces.add(nfce);
    }

    // Atualizar o contador de último número da empresa se for maior E se a nota foi autorizada ou cancelada.
    // O contador global (ultimo_numero_nfce) representa a SÉRIE 1 — notas de
    // séries adicionais (2, 3...) têm numeração própria e NÃO devem alterá-lo,
    // senão a série 2 puxaria a numeração da série 1 (ou vice-versa).
    final asSucesso = ['autorizada', 'sucesso', 'cancelada'].contains(nfce.status?.toLowerCase());
    final serieNota = (nfce.serie ?? '').trim().isEmpty ? '1' : nfce.serie!.trim();
    if (asSucesso && serieNota == '1' && nfce.numero.isNotEmpty && empresaAtual != null) {
      final nfceNumInt = int.tryParse(nfce.numero) ?? 0;
      final configKey = isNfe ? 'ultimo_numero_nfe' : 'ultimo_numero_nfce';
      final ultimoNum = int.tryParse(empresaAtual!.configuracoes?[configKey]?.toString() ?? '0') ?? 0;
      
      if (nfceNumInt > ultimoNum) {
        final novasConfigs = Map<String, dynamic>.from(empresaAtual!.configuracoes ?? {});
        novasConfigs[configKey] = nfceNumInt.toString();
        
        final empresaAtualizada = empresaAtual!.copyWith(
          configuracoes: novasConfigs,
          updatedAt: DateTime.now(),
        );
        
        // Atualiza localmente
        setEmpresaAtual(empresaAtualizada);
        
        // Salvar no Supabase também
        await _upsertNoSupabase(SupabaseService.tableEmpresas, empresaAtualizada.toMap());
      }
    }

    notifyListeners();
    if (isNfe) {
      _marcarSujo(LocalStorageService.keyNFEs);
      await _upsertNoSupabase(SupabaseService.tableNFEs, nfce.toMap());
    } else {
      _marcarSujo(LocalStorageService.keyNFCes);
      await _upsertNoSupabase(SupabaseService.tableNFCes, nfce.toMap());
    }
    _sincronizarNotasComDrive();
  }

  /// Atualiza uma NFC-e ou NF-e existente
  Future<void> atualizarNFCe(NFCe nfce) async {
    final isNfe = nfce.modelo == 55;
    final listaTarget = isNfe ? _nfes : _nfces;
    final index = listaTarget.indexWhere((n) => n.id == nfce.id);
    
    if (index == -1) {
      // Se não encontrou no destino, procurar no outro lista para remanejar
      final listaOutra = isNfe ? _nfces : _nfes;
      final indexOutra = listaOutra.indexWhere((n) => n.id == nfce.id);
      if (indexOutra != -1) {
        listaOutra.removeAt(indexOutra);
      }
      listaTarget.add(nfce);
    } else {
      listaTarget[index] = nfce;
    }
    
    // Atualizar o contador de último número da empresa se for maior E se a nota foi autorizada ou cancelada.
    // O contador global (ultimo_numero_nfce) representa a SÉRIE 1 — notas de
    // séries adicionais (2, 3...) têm numeração própria e NÃO devem alterá-lo,
    // senão a série 2 puxaria a numeração da série 1 (ou vice-versa).
    final asSucesso = ['autorizada', 'sucesso', 'cancelada'].contains(nfce.status?.toLowerCase());
    final serieNota = (nfce.serie ?? '').trim().isEmpty ? '1' : nfce.serie!.trim();
    if (asSucesso && serieNota == '1' && nfce.numero.isNotEmpty && empresaAtual != null) {
      final nfceNumInt = int.tryParse(nfce.numero) ?? 0;
      final configKey = isNfe ? 'ultimo_numero_nfe' : 'ultimo_numero_nfce';
      final ultimoNum = int.tryParse(empresaAtual!.configuracoes?[configKey]?.toString() ?? '0') ?? 0;
      
      if (nfceNumInt > ultimoNum) {
        final novasConfigs = Map<String, dynamic>.from(empresaAtual!.configuracoes ?? {});
        novasConfigs[configKey] = nfceNumInt.toString();
        
        final empresaAtualizada = empresaAtual!.copyWith(
          configuracoes: novasConfigs,
          updatedAt: DateTime.now(),
        );
        
        // Atualiza localmente
        setEmpresaAtual(empresaAtualizada);
        
        // Salvar no Supabase também
        await _upsertNoSupabase(SupabaseService.tableEmpresas, empresaAtualizada.toMap());
      }
    }

    notifyListeners();
    _salvarAutomaticamente();
    if (isNfe) {
      await _upsertNoSupabase(SupabaseService.tableNFEs, nfce.toMap());
    } else {
      await _upsertNoSupabase(SupabaseService.tableNFCes, nfce.toMap());
    }
  }

  /// Remove uma NFC-e ou NF-e
  Future<void> removerNFCe(String id) async {
    _nfces.removeWhere((n) => n.id == id);
    _nfes.removeWhere((n) => n.id == id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover também do Supabase para não deixar registros órfãos
    try {
      if (SupabaseService.isAvailable) {
        await SupabaseService.instance.delete(SupabaseService.tableNFCes, id);
        await SupabaseService.instance.delete(SupabaseService.tableNFEs, id);
      }
    } catch (e) {
      debugPrint('>>> [NF] ⚠️ Falha ao remover nota do Supabase: $e');
    }
  }

  /// Obtém uma NFC-e ou NF-e por ID
  NFCe? obterNFCe(String id) {
    try {
      return _nfces.firstWhere((n) => n.id == id, orElse: () => _nfes.firstWhere((n) => n.id == id));
    } catch (e) {
      return null;
    }
  }

  /// Obtém NFC-e ou NF-e por chave de acesso
  NFCe? obterNFCePorChave(String chaveAcesso) {
    try {
      return _nfces.firstWhere((n) => n.chaveAcesso == chaveAcesso, orElse: () => _nfes.firstWhere((n) => n.chaveAcesso == chaveAcesso));
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
    if (_currentEmpresaId == null) return;
    
    _ultimaSincronizacao = null; // Resetar para forçar sincronização
    await _salvarTodosDados(aguardarSupabase: false);
    
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
    
    if (_currentEmpresaId == null) {
      throw Exception('⚠️ Nenhuma empresa selecionada');
    }

    final empresaId = _currentEmpresaId!;
    
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
      _lotesProdutos.clear();
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
      await _salvarTodosDados(aguardarSupabase: true);
      
      // Deletar do Supabase (apenas dados operacionais da empresa específica)
      if (SupabaseService.isAvailable) {
        try {
          final filter = {'empresa_id': empresaId};
          await _supabaseService.deleteFiltered(SupabaseService.tableProdutos, filter);
          await _supabaseService.deleteFiltered(SupabaseService.tablePedidos, filter);
          await _supabaseService.deleteFiltered(SupabaseService.tableVendasBalcao, filter);
          await _supabaseService.deleteFiltered(SupabaseService.tableServicos, filter);
          await _supabaseService.deleteFiltered(SupabaseService.tableClientes, filter);
          await _supabaseService.deleteFiltered(SupabaseService.tableAgendamentosServico, filter);
          print('>>> ✓ Dados deletados do Supabase');
        } catch (e) {
          print('>>> ⚠️ Erro ao deletar do Supabase: $e');
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
    _marcarSujo(LocalStorageService.keyMesasComandas);
    // Persistência local delegada ao _salvarAutomaticamente via _marcarSujo.

    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableMesasComandas, mesaComanda.toMap());
  }

  /// Atualiza uma mesa ou comanda existente
  Future<void> updateMesaComanda(MesaComanda mesaComanda) async {
    final index = _mesasComandas.indexWhere((m) => m.id == mesaComanda.id);
    if (index != -1) {
      _mesasComandas[index] = mesaComanda;
      notifyListeners();
      _marcarSujo(LocalStorageService.keyMesasComandas);
      // Persistência local delegada ao background para evitar stuttering.

      _salvarAutomaticamente();
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(SupabaseService.tableMesasComandas, mesaComanda.toMap());
    }
  }

  /// Remove uma mesa ou comanda
  Future<void> deleteMesaComanda(String id) async {
    debugPrint('>>> [DataService] 🗑️ Iniciando deleção da Mesa/Comanda: $id');
    debugPrint('>>> [DataService] 🔍 Estado ATUAL antes da deleção: ${_mesasComandas.length} mesas na lista.');
    
    // Adicionar ao Set de supressão recente (evita que o Supabase a restaure por latência)
    _idsMesaRemovidosRecentemente.add(id);
    // Remover do Set após 2 minutos (tempo suficiente para o Firestore propagar a deleção mundialmente)
    Future.delayed(const Duration(minutes: 2), () {
      _idsMesaRemovidosRecentemente.remove(id);
      debugPrint('>>> [DataService] 🧹 ID $id removido do Set de supressão recente');
    });

    // Primeiro marcamos como Fechada localmente para que o Getter filtre IMEDIATAMENTE
    final index = _mesasComandas.indexWhere((m) => m.id == id);
    if (index != -1) {
      _mesasComandas[index] = _mesasComandas[index].copyWith(status: 'Fechada');
    }
    notifyListeners();
    
    // Removemos da lista local (permanente)
    _mesasComandas.removeWhere((m) => m.id == id);
    
    // MARCAR COMO SUJO para garantir que o salvamento em background ocorra
    _marcarSujo(LocalStorageService.keyMesasComandas);
    // Deleção persistida via background para evitar travamentos.
    
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableMesasComandas, {'id': id}, evento: 'DELETE');
  }

  /// Marca uma mesa/comanda como DELETADA mantendo o registro no Histórico de Operações.
  /// Diferente de [deleteMesaComanda] (que remove fisicamente), aqui o registro permanece
  /// no sistema com status 'Deletada' para fins de auditoria: quem deletou e quando.
  Future<void> marcarMesaComandaDeletada(String id, {String? usuario}) async {
    final index = _mesasComandas.indexWhere((m) => m.id == id);
    if (index == -1) {
      debugPrint('>>> [DataService] 🗑️ Mesa/Comanda não encontrada para marcar como deletada: $id');
      return;
    }

    final atual = _mesasComandas[index];
    if (atual.status == 'Deletada') {
      debugPrint('>>> [DataService] ⚠️ Mesa/Comanda $id já está marcada como Deletada');
      return;
    }

    final agora = DateTime.now();
    final deletada = atual.copyWith(
      status: 'Deletada',
      dataFechamento: agora,
      usuarioModificou: usuario ?? atual.usuarioModificou,
      updatedAt: agora,
    );

    _mesasComandas[index] = deletada;
    notifyListeners();
    _marcarSujo(LocalStorageService.keyMesasComandas);
    _salvarAutomaticamente();

    debugPrint('>>> [DataService] 🗑️ Mesa/Comanda ${atual.numero} marcada como DELETADA por $usuario');

    // Sincronizar com Supabase (mantém o registro para o histórico em todos os dispositivos)
    await enviarMudancaParaSupabase(SupabaseService.tableMesasComandas, deletada.toMap());

    // Cascata: se for uma mesa, comandas vinculadas a ela também são marcadas como deletadas
    // (evita comandas órfãs apontando para uma mesa que não existe mais)
    final comandasVinculadas = _mesasComandas
        .where((m) => m.mesaId == id && m.status != 'Deletada')
        .map((m) => m.id)
        .toList();
    for (final comandaId in comandasVinculadas) {
      final cIndex = _mesasComandas.indexWhere((m) => m.id == comandaId);
      if (cIndex == -1) continue;
      final cAtual = _mesasComandas[cIndex];
      final cDeletada = cAtual.copyWith(
        status: 'Deletada',
        dataFechamento: agora,
        usuarioModificou: usuario ?? cAtual.usuarioModificou,
        updatedAt: agora,
      );
      _mesasComandas[cIndex] = cDeletada;
      debugPrint('>>> [DataService] 🗑️ Comanda vinculada ${cAtual.numero} também marcada como DELETADA');
      await enviarMudancaParaSupabase(SupabaseService.tableMesasComandas, cDeletada.toMap());
    }
    if (comandasVinculadas.isNotEmpty) {
      notifyListeners();
      _marcarSujo(LocalStorageService.keyMesasComandas);
      _salvarAutomaticamente();
    }

    // Garantir que o registro (e as comandas vinculadas) fiquem gravados de forma
    // durável no banco local imediatamente, sem depender do salvamento em background.
    await salvarImediatamente();
  }

  /// Limpa uma mesa/comanda, salvando o histórico como um pedido
  Future<void> limparMesaComanda(String id, {String? usuario}) async {
    final mesaIndex = _mesasComandas.indexWhere((m) => m.id == id);
    if (mesaIndex == -1) {
      debugPrint('>>> [LimparMesa] ❌ Mesa não encontrada: $id');
      return;
    }

    final mesa = _mesasComandas[mesaIndex];
    debugPrint('');
    debugPrint('╔════════════════════════════════════════════════╗');
    debugPrint('║  LIMPAR MESA/COMANDA - SALVANDO HISTÓRICO     ║');
    debugPrint('╚════════════════════════════════════════════════╝');
    debugPrint('>>> [LimparMesa] Tipo: ${mesa.tipo.name}');
    debugPrint('>>> [LimparMesa] Número: ${mesa.numero}');
    debugPrint('>>> [LimparMesa] Total itens: ${mesa.itens.length}');
    debugPrint('>>> [LimparMesa] Total calculado: ${mesa.totalCalculado}');
    debugPrint('>>> [LimparMesa] Pagamentos registrados: ${mesa.historicoPagamentos.length}');
    debugPrint('>>> [LimparMesa] Couvert: ${mesa.valorCouvertCalculado}');

    // Converter itens para Pedido
    final produtos = <ItemPedido>[];
    final servicos = <ItemServico>[];

    for (final item in mesa.itens) {
      if (item.status == StatusItem.cancelado) continue;

      if (item.isServico) {
        servicos.add(ItemServico(
          id: item.itemId,
          descricao: item.nome,
          valor: item.preco,
          valorAdicional: 0.0,
        ));
      } else {
        produtos.add(ItemPedido(
          id: item.itemId,
          nome: item.nome,
          quantidade: item.quantidade,
          preco: item.preco,
        ));
      }
    }

    // Criar ID ÚNICO para o histórico (será usado tanto no Pedido quanto na VendaBalcao para merge correto)
    final idHistorico = uuid.v4();
    final bool isComanda = mesa.tipo == TipoControle.comanda || 
                           mesa.numero.toUpperCase().contains('CMD') || 
                           mesa.numero.toUpperCase().contains('COMANDA');
    
    // FORÇAR PREFIXOS PADRONIZADOS PARA O HISTÓRICO
    final String prefixo = isComanda ? 'CMD' : 'MESA';
    final String labelOrigem = isComanda ? '[COMANDA]' : '[MESA]';
    
    // Observação unificada para identificação infalível no histórico
    final String tagIdentificacao = '[VIP-MC] originado de $labelOrigem ${mesa.numero}';
    
    // Se for Comanda, garantir que o número tenha o prefixo CMD (Identificação Garantida)
    // Evitar prefixo duplo se mesa.numero já contém CMD-
    final String baseLimpa = mesa.numero.toUpperCase()
        .replaceAll('CMD-', '')
        .replaceAll('MESA-', '')
        .replaceAll('COMANDA-', '')
        .trim();
        
    final String numeroHistorico = '$prefixo-$baseLimpa-${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}';

    // Nome do cliente formatado para SEMPRE ser identificado no histórico
    // Ex: "[COMANDA] 01 - João Silva" ou "[MESA] 05"
    String? clienteNomeFinal = mesa.clienteNome;
    if (clienteNomeFinal == null || clienteNomeFinal.isEmpty) {
      clienteNomeFinal = '$labelOrigem ${mesa.numero}';
    } else if (!clienteNomeFinal.toUpperCase().contains(labelOrigem)) {
      clienteNomeFinal = '$labelOrigem ${mesa.numero} - $clienteNomeFinal';
    }
    
    // Criar lista de pagamentos normalizada
    final pagamentosHistorico = mesa.historicoPagamentos.map((rp) {
        TipoPagamento tipo;
        final f = rp.formaPagamento?.toLowerCase() ?? '';
        if (f.contains('pix')) {
          tipo = TipoPagamento.pix;
        } else if (f.contains('dinheiro')) {
          tipo = TipoPagamento.dinheiro;
        } else if (f.contains('débito') || f.contains('debito')) {
          tipo = TipoPagamento.cartaoDebito;
        } else if (f.contains('crédito') || f.contains('credito') || f.contains('cart')) {
          tipo = TipoPagamento.cartaoCredito;
        } else if (f.contains('boleto')) {
          tipo = TipoPagamento.boleto;
        } else if (f.contains('crediário') || f.contains('crediario')) {
          tipo = TipoPagamento.crediario;
        } else if (f.contains('fiado')) {
          tipo = TipoPagamento.fiado;
        } else {
          tipo = TipoPagamento.outro;
        }
        
        return PagamentoPedido(
          id: rp.id,
          tipo: tipo,
          valor: rp.valor,
          recebido: true,
          dataRecebimento: rp.dataPagamento,
          observacao: rp.observacao ?? 'Migrado de ${mesa.numero}',
        );
    }).toList();

    final novoPedido = Pedido(
      id: idHistorico,
      numero: numeroHistorico,
      dataPedido: DateTime.now(),
      status: 'Finalizado (Mesa Limpa)',
      clienteId: mesa.clienteId,
      clienteNome: clienteNomeFinal, // Use o nome com tag explícita
      produtos: produtos,
      servicos: servicos,
      vendedorNome: usuario,
      pagamentos: pagamentosHistorico,
      total: mesa.totalCalculado,
      origem: 'Mesa/Comanda',
      observacoes: tagIdentificacao,
    );

    // Criar lista de itens para Pedido/VendaBalcao incluindo virtualmente o Couvert e Taxa de Serviço se existirem
    final itensHistorico = mesa.itens.where((i) => i.status != StatusItem.cancelado).map((i) => ItemVendaBalcao(
        id: i.itemId,
        nome: i.nome,
        precoUnitario: i.preco,
        quantidade: i.quantidade.toDouble(),
        isServico: i.isServico,
        adicionais: i.adicionais,
      )).toList();
      
    // Adicionar Couvert se houver valor
    if (mesa.valorCouvertCalculado > 0) {
      itensHistorico.add(ItemVendaBalcao(
        id: 'couvert-${idHistorico}',
        nome: 'Couvert Artístico (${mesa.quantidadePessoasCouvert ?? 1}x)',
        precoUnitario: mesa.valorCouvertCalculado,
        quantidade: 1.0,
        isServico: true,
      ));
    }
    
    // Adicionar Taxa de Serviço se houver valor
    if (mesa.valorTaxaServicoCalculado > 0) {
      itensHistorico.add(ItemVendaBalcao(
        id: 'taxa-servico-${idHistorico}',
        nome: 'Taxa de Serviço (Geral)',
        precoUnitario: mesa.valorTaxaServicoCalculado,
        quantidade: 1.0,
        isServico: true,
      ));
    }

    // Salvar como VendaBalcao (Venda Direta) para aparecer no histórico unificado
    final vendaHistorico = VendaBalcao(
      id: idHistorico, // MESMO ID para facilitar o merge no Histórico
      numero: novoPedido.numero,
      dataVenda: DateTime.now(),
      clienteId: mesa.clienteId,
      clienteNome: novoPedido.clienteNome,
      itens: itensHistorico,
      tipoPagamento: pagamentosHistorico.isNotEmpty ? pagamentosHistorico.first.tipo : TipoPagamento.outro,
      valorTotal: mesa.totalCalculado,
      valorRecebido: mesa.totalPago,
      operador: usuario,
      origem: 'Mesa/Comanda',
      observacoes: 'Mesa finalizada via controle. $tagIdentificacao',
    );

    // Salvar histórico (Pedido e VendaBalcao) - SEM AWAIT para garantir fluidez offline
    addPedido(novoPedido);
    addVendaBalcao(vendaHistorico);
    debugPrint('>>> [DataService] ✓ Salvo em memória e localmente!');
    
    // Deletar a mesa
    await deleteMesaComanda(id);
    
    // Forçar salvamento do histórico IMEDIATAMENTE
    await salvarImediatamente();
    
    notifyListeners();
    debugPrint('>>> [LimparMesa] ✓ Processo concluído com sucesso');
    debugPrint('');
  }
  
  /// Converte uma string de forma de pagamento para o Enum TipoPagamento
  TipoPagamento _getTipoPagamentoByString(String? forma) {
    if (forma == null || forma.isEmpty) return TipoPagamento.dinheiro;
    
    final f = forma.toLowerCase();
    if (f.contains('pix')) return TipoPagamento.pix;
    if (f.contains('dinheiro')) return TipoPagamento.dinheiro;
    if (f.contains('cartão') || f.contains('cartao')) {
      if (f.contains('deb')) return TipoPagamento.cartaoDebito;
      return TipoPagamento.cartaoCredito;
    }
    if (f.contains('boleto')) return TipoPagamento.boleto;
    if (f.contains('fiado')) return TipoPagamento.fiado;
    if (f.contains('crediario')) return TipoPagamento.crediario;
    
    return TipoPagamento.outro;
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

  Future<void> atualizarObservacaoItemMesaComanda(
    String mesaComandaId,
    String itemId,
    String observacao, {
    String? usuarioModificou,
  }) async {
    final mesaIndex = _mesasComandas.indexWhere((m) => m.id == mesaComandaId);
    if (mesaIndex == -1) throw Exception('Mesa/Comanda não encontrada');

    final mesaComanda = _mesasComandas[mesaIndex];
    final itemIndex = mesaComanda.itens.indexWhere((i) => i.id == itemId);
    
    if (itemIndex == -1) throw Exception('Item não encontrado');

    final itemAtualizado = mesaComanda.itens[itemIndex].copyWith(
      observacao: observacao,
      usuarioModificou: usuarioModificou,
      dataModificacao: DateTime.now(),
      acaoRealizada: 'Observação alterada',
    );

    final itensAtualizados = List<ItemMesaComanda>.from(mesaComanda.itens);
    itensAtualizados[itemIndex] = itemAtualizado;

    final mesaComandaAtualizada = mesaComanda.copyWith(
      itens: itensAtualizados,
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
        quantidade: 1.0, // ItemServico não tem quantidade, assume 1
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
    if (_carregandoMaisClientes || !_temMaisClientes || _currentEmpresaId == null) return;
    
    _carregandoMaisClientes = true;
    notifyListeners();
    
    try {
      debugPrint('>>> [Sync] 📥 Carregando mais clientes do Supabase...');
      final int proximaPagina = (_clientes.length / 50).floor();
      
      final result = await _supabaseService.carregarColecaoPaginada(
        _currentEmpresaId!, 
        SupabaseService.tableClientes,
        page: proximaPagina,
        pageSize: 50,
        orderBy: 'nome', 
        descending: false,
      );
      
      if (result.isEmpty) {
        _temMaisClientes = false;
        debugPrint('>>> [Sync] ✓ Fim da lista de clientes atingido no Supabase');
      } else {
        final novosClientes = result.map((map) => Cliente.fromMap(map)).toList();
        
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
        
        debugPrint('>>> [Sync] ✓ Mais $contagemNovos clientes carregados do Supabase (Total: ${_clientes.length})');
        
        if (result.length < 50) {
          _temMaisClientes = false;
        }
      }
    } catch (e) {
      debugPrint('>>> [DataService] Erro ao carregar mais clientes do Supabase: $e');
    } finally {
      _carregandoMaisClientes = false;
      notifyListeners();
    }
  }

  bool get temMaisVendas => _temMaisVendas;
  bool get carregandoMaisVendas => _carregandoMaisVendas;

  /// Carrega a próxima página de vendas (50 por vez)
  Future<void> carregarMaisVendas() async {
    if (_carregandoMaisVendas || !_temMaisVendas || _currentEmpresaId == null) return;
    
    _carregandoMaisVendas = true;
    notifyListeners();
    
    try {
      debugPrint('>>> [Sync] 📥 Carregando mais vendas do Supabase...');
      final proximaPagina = (_vendasBalcao.length / 50).floor();
      
      final result = await _supabaseService.carregarColecaoPaginada(
        _currentEmpresaId!, 
        SupabaseService.tableVendasBalcao,
        page: proximaPagina,
        pageSize: 50,
        orderBy: 'dataVenda', 
        descending: true,
      );
      
      if (result.isEmpty) {
        _temMaisVendas = false;
        debugPrint('>>> [Sync] ✓ Fim da lista de vendas atingido no Supabase');
      } else {
        final novasVendas = result.map((map) => VendaBalcao.fromMap(map)).toList();
        
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
        
        debugPrint('>>> [Sync] ✓ Mais $contagemNovas vendas carregadas do Supabase (Total: ${_vendasBalcao.length})');
        
        if (result.length < 50) {
          _temMaisVendas = false;
        }
      }
    } catch (e) {
      debugPrint('>>> [DataService] Erro ao carregar mais vendas do Supabase: $e');
    }
    finally {
      _carregandoMaisVendas = false;
      notifyListeners();
    }
  }

  void _reiniciarMonitorBridge() {
    // Monitor de bridge desativado (era baseado em Supabase)
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

  Future<void> publicarSincronizacaoTotal() async {
    _isLoading = true;
    _mensagemLoading = 'Enviando todos os dados para a nuvem...';
    notifyListeners();
    
    // Log do que vai ser sincronizado
    debugPrint('>>> [DataService] 📊 RESUMO DOS DADOS A SINCRONIZAR:');
    debugPrint('    - Produtos: ${_produtos.length}');
    debugPrint('    - Clientes: ${_clientes.length}');
    debugPrint('    - Pedidos: ${_pedidos.length}');
    debugPrint('    - Vendas Balcão: ${_vendasBalcao.length}');
    debugPrint('    - Serviços: ${_tiposServico.length}');
    debugPrint('    - Empresa ID: $currentEmpresaId');
    
    if (_currentEmpresaId == null) {
      debugPrint('>>> [DataService] ❌ ERRO: Empresa não definida!');
      _isLoading = false;
      notifyListeners();
      throw Exception('Empresa não definida. Selecione uma empresa primeiro.');
    }
    
    try {
      await _sincronizarComSupabase();
      _ultimaSincronizacao = DateTime.now();
      debugPrint('>>> [DataService] ☁️ Sincronização TOTAL concluída!');
    } catch (e) {
      debugPrint('>>> [DataService] ❌ Falha na publicação total: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adiciona ou atualiza um agendamento na lista local
  void _upsertAgendamentoLocal(AgendamentoServico agendamento, {bool prioritario = false}) {
    final index = _agendamentosServico.indexWhere((a) => a.id == agendamento.id);
    if (index != -1) {
      _agendamentosServico[index] = agendamento;
    } else {
      if (prioritario) {
        _agendamentosServico.insert(0, agendamento);
      } else {
        _agendamentosServico.add(agendamento);
      }
    }
  }

  /// Retorna uma chave única para a empresa atual no LocalStorage
  String _getEmpresaKey(String baseKey) {
    if (_currentEmpresaId == null || _currentEmpresaId!.isEmpty) return baseKey;
    return 'empresa_${_currentEmpresaId}_$baseKey';
  }

  /// 🚑 RESTAURAR: Envia os dados que estão no computador de volta para a nuvem
  /// Usar quando a nuvem foi apagada acidentalmente e o local ainda tem os dados
  Future<void> restaurarLocalParaNuvem() async {
    if (_currentEmpresaId == null) return;

    _isLoading = true;
    _mensagemLoading = 'Restaurando dados locais para a nuvem...';
    notifyListeners();

    try {
      debugPrint('>>> [Restore] 🚑 Iniciando restauração local → nuvem para empresa $currentEmpresaId');
      
      // Enviar produtos de volta para a nuvem (em lotes de 200 para não travar)
      if (_produtos.isNotEmpty) {
        debugPrint('>>> [Restore] 📦 Enviando ${_produtos.length} produtos...');
        const batchSize = 200;
        for (int i = 0; i < _produtos.length; i += batchSize) {
          final batch = _produtos.sublist(i, (i + batchSize).clamp(0, _produtos.length));
          await _supabaseService.upsertBatch(
            SupabaseService.tableProdutos,
            batch.map((p) => p.toMap()).toList(),
          );
          debugPrint('>>> [Restore] ✅ Lote ${(i ~/ batchSize) + 1}: ${batch.length} produtos enviados');
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      // Enviar clientes
      if (_clientes.isNotEmpty) {
        debugPrint('>>> [Restore] 👥 Enviando ${_clientes.length} clientes...');
        await _supabaseService.upsertBatch(
          SupabaseService.tableClientes,
          _clientes.map((c) => c.toMap()).toList(),
        );
      }

      // Enviar pedidos
      if (_pedidos.isNotEmpty) {
        debugPrint('>>> [Restore] 📝 Enviando ${_pedidos.length} pedidos...');
        await _supabaseService.upsertBatch(
          SupabaseService.tablePedidos,
          _pedidos.map((p) => p.toMap()).toList(),
        );
      }

      debugPrint('>>> [Restore] ✅ Restauração concluída! Dados locais enviados para a nuvem.');
    } catch (e) {
      debugPrint('>>> [Restore] ❌ Erro na restauração: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Limpa TODOS os dados desta empresa no SUPABASE (Cuidado!)
  Future<void> deletarTudoNoSupabaseDestaEmpresa() async {
    if (_currentEmpresaId == null) return;
    
    _isLoading = true;
    _mensagemLoading = 'Limpando dados na nuvem...';
    notifyListeners();

    try {
      final tabelas = [
        SupabaseService.tableProdutos,
        SupabaseService.tableClientes,
        SupabaseService.tablePedidos,
        SupabaseService.tableVendasBalcao,
        SupabaseService.tableAberturasCaixa,
        SupabaseService.tableFechamentosCaixa,
        SupabaseService.tableEstoqueHistorico,
      ];

      for (var tabela in tabelas) {
        debugPrint('>>> [Supabase] 🗑️ Deletando $tabela...');
        await _supabaseService.deleteByEmpresa(tabela, _currentEmpresaId!);
      }

      // Após limpar a nuvem, limpa o computador também
      _clientes.clear();
      _produtos.clear();
      _pedidos.clear();
      _vendasBalcao.clear();
      await _salvarTodosDados(aguardarSupabase: false);
      
      debugPrint('>>> [Supabase] ✅ Nuvem e Local limpos para esta empresa.');
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao limpar nuvem: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ============ MÉTODOS DE INICIALIZAÇÃO E CARREGAMENTO ============
  
  Future<void> recarregarTudoDoFirebase() async {
    return _carregarDadosDoSupabase();
  }
  
  Future<void> reativarFirebase() async {
    // Não faz nada, Firebase foi desativado
  }

  Future<void> baixarDadosDaNuvem() async {
    return _carregarDadosDoSupabase();
  }

  /// Re-vincula referências de todos os agendamentos (otimização de memória)
  void _reVincularTodosAgendamentos() {
    for (int i = 0; i < _agendamentosServico.length; i++) {
      _agendamentosServico[i] = _vincularReferenciasAgendamento(_agendamentosServico[i]);
    }
  }

  // ===========================================================================
  // LICENCIAMENTO E VALIDAÇÃO ONLINE
  // ===========================================================================

  /// Carrega o status de liberação provisória do armazenamento local
  Future<void> carregarLiberacaoProvisoria() async {
    try {
      final valor = await _storage.carregar('liberacao_provisoria_ativa');
      _liberacaoProvisoriaAtiva = valor == 'true';
      
      final ultimaValid = await _storage.carregar('ultima_validacao_online');
      if (ultimaValid != null) {
        _ultimaValidacaoOnline = DateTime.tryParse(ultimaValid.toString());
      }
      
      final ultimaExec = await _storage.carregar('ultima_data_execucao');
      if (ultimaExec != null) {
        _ultimaDataExecucao = DateTime.tryParse(ultimaExec.toString());
      }
    } catch (e) {
      debugPrint('>>> [Licenca] ⚠️ Erro ao carregar licenciamento: $e');
    }
  }

  /// Reseta as simulações de licenciamento para o estado real
  Future<void> resetarSimulacoesLicenca() async {
    _ultimaValidacaoOnline = DateTime.now();
    _ultimaDataExecucao = DateTime.now();
    _liberacaoProvisoriaAtiva = false;
    await _storage.salvar('ultima_validacao_online', _ultimaValidacaoOnline!.toIso8601String());
    await _storage.salvar('ultima_data_execucao', _ultimaDataExecucao!.toIso8601String());
    await _storage.salvar('liberacao_provisoria_ativa', 'false');
    notifyListeners();
  }

  /// Simula N dias offline para testar bloqueio de licenciamento
  Future<void> simularDiasOffline(int dias) async {
    _ultimaValidacaoOnline = DateTime.now().subtract(Duration(days: dias));
    await _storage.salvar('ultima_validacao_online', _ultimaValidacaoOnline!.toIso8601String());
    notifyListeners();
  }

  /// Simula alteração de relógio para testar bloqueio
  Future<void> simularRelogioAdulterado() async {
    _ultimaDataExecucao = DateTime.now().add(const Duration(hours: 2));
    await _storage.salvar('ultima_data_execucao', _ultimaDataExecucao!.toIso8601String());
    notifyListeners();
  }

  // ===========================================================================
  // PERFIS TRIBUTÁRIOS
  // ===========================================================================

  /// Carrega os perfis tributários a partir da configuração da empresa atual.
  ///
  /// Fonte principal: `empresa.configuracoes['perfis_tributarios']` (persistida
  /// no banco — PostgreSQL local + Supabase — onde o backend NFC-e também busca).
  /// Se a empresa ainda não tiver perfis na configuração, tenta migrar os perfis
  /// salvos apenas no cache local antes desta correção.
  void _carregarPerfisTributariosDaEmpresa() {
    if (_empresaAtual == null) return; // Sem empresa definida, não há perfis a carregar
    _perfisTributarios.clear();
    final raw = _empresaAtual?.configuracoes?['perfis_tributarios'];
    final temConfigValida = raw is List && raw.isNotEmpty;
    if (temConfigValida) {
      for (final item in raw) {
        if (item is Map) {
          _perfisTributarios.add(PerfilTributario.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }
    if (temConfigValida && _perfisTributarios.isNotEmpty) {
      // Config tem perfis válidos: garante que os padrões do sistema também
      // existam (mesclando por nome, sem duplicar) e persiste se algo foi adicionado.
      final adicionouPadrao = _criarPerfisTributariosPadrao();
      // Sempre confere o cache local (última edição do usuário) por cima da
      // configuração — assim um perfil salvo nunca some ao reiniciar, mesmo
      // que a config do banco esteja desatualizada ou vazia.
      unawaited(_migrarPerfisTributariosDoCache(forcarPersistencia: adicionouPadrao));
    } else {
      // Sem perfis válidos na config: garante os padrões IMEDIATAMENTE (síncrono)
      // para o dropdown nunca abrir vazio, e busca perfis antigos do cache em background.
      _criarPerfisTributariosPadrao();
      unawaited(_migrarPerfisTributariosDoCache(forcarPersistencia: true));
    }
  }

  /// Migra perfis tributários que estavam salvos apenas no cache local
  /// (cache_dados) para a configuração da empresa, onde são persistidos no banco.
  Future<void> _migrarPerfisTributariosDoCache({
    bool forcarPersistencia = false,
  }) async {
    if (_migrandoPerfisTributarios) return;
    _migrandoPerfisTributarios = true;
    try {
      final chave = _getChaveComEmpresa('perfis_tributarios');
      final cached = await _storage.carregarLista(chave);
      var mudou = false;
      if (cached.isNotEmpty) {
        // Restaura do cache local os perfis que NÃO existem na configuração
        // da empresa. Antes, o merge só rodava com a lista vazia — e como os
        // padrões do sistema são criados sincronamente antes, os perfis
        // personalizados eram perdidos ao reiniciar (bug: "não persiste").
        // Apenas ADICIONA (não substitui): se a config já tem o perfil, a
        // versão do banco/Supabase (que pode ter vindo de outro PC) prevalece.
        for (final m in cached) {
          final perfil = PerfilTributario.fromMap(m);
          if (!_perfisTributarios.any((p) => p.id == perfil.id)) {
            _perfisTributarios.add(perfil);
            mudou = true;
          }
        }
      }
      // Garante os padrões do sistema (dedupe por id/nome, sem duplicar)
      final adicionouPadrao = _criarPerfisTributariosPadrao();
      // Persiste apenas se algo mudou (ou se forçado) para evitar gravações
      // desnecessárias no banco a cada carregamento.
      if (mudou || adicionouPadrao || forcarPersistencia) {
        await _persistirPerfisTributariosNaEmpresa();
      }
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao migrar perfis tributários do cache: $e');
    } finally {
      _migrandoPerfisTributarios = false;
      // Notifica a UI mesmo se a persistência falhar, para o dropdown atualizar
      notifyListeners();
    }
  }

  /// Cria os perfis tributários padrão do sistema para empresas que ainda
  /// não possuem nenhum perfil cadastrado (tributado, não tributado e
  /// substituição — para Simples Nacional e Regime Normal).
  bool _criarPerfisTributariosPadrao() {
    var mudou = false;
    // ── MIGRAÇÃO DE CÓDIGOS ANTIGOS (corrige dados persistidos) ──────────────
    // Perfis criados em versões antigas podem ter o código errado de
    // "Não Tributado (Simples)" com CSOSN 500 (500 é "ICMS cobrado anteriormente
    // por ST", NÃO é não-tributado). Corrige para CSOSN 400 (não tributada pelo
    // Simples Nacional) mesmo em perfis com nome/id personalizado. O perfil
    // padrão já é corrigido pelo garantirPadrao abaixo (por id/nome exato); esta
    // regra cobre apenas perfis renomeados/personalizados e é segura: CSOSN 500
    // jamais representa "não tributado".
    for (int i = 0; i < _perfisTributarios.length; i++) {
      final p = _perfisTributarios[i];
      if (p.csosn != '500') continue;
      final nome = (p.nome ?? '').toLowerCase();
      if (!(nome.contains('não tributado') || nome.contains('nao tributado'))) {
        continue;
      }
      _perfisTributarios[i] = PerfilTributario(
        id: p.id,
        nome: p.nome,
        cfop: p.cfop,
        icmsCst: p.icmsCst,
        csosn: '400',
        aliquotaIcms: p.aliquotaIcms,
        pisCst: p.pisCst,
        aliquotaPis: p.aliquotaPis,
        cofinsCst: p.cofinsCst,
        aliquotaCofins: p.aliquotaCofins,
        cstIbs: p.cstIbs,
        aliquotaIbs: p.aliquotaIbs,
        cstCbs: p.cstCbs,
        aliquotaCbs: p.aliquotaCbs,
        ipiCst: p.ipiCst,
        aliquotaIpi: p.aliquotaIpi,
        mva: p.mva,
        reducaoBaseIcms: p.reducaoBaseIcms,
        aliquotaFcp: p.aliquotaFcp,
        aliquotaIcmsInterestadual: p.aliquotaIcmsInterestadual,
        ncm: p.ncm,
        isDefault: p.isDefault,
      );
      mudou = true;
    }
    // Adiciona o padrão se não existir OU corrige os valores se já existir
    // com o mesmo nome (ex.: CFOP errado persistido em versões anteriores).
    // A correção preserva o ID existente (para não quebrar produtos que
    // referenciam o perfil) e as customizações do usuário (alíquotas, MVA,
    // NCM etc.) — altera apenas os campos do padrão.
    void garantirPadrao(PerfilTributario padrao) {
      for (int i = 0; i < _perfisTributarios.length; i++) {
        final p = _perfisTributarios[i];
        if (p.id == padrao.id || p.nome == padrao.nome) {
          if (p.cfop != padrao.cfop ||
              p.csosn != padrao.csosn ||
              p.icmsCst != padrao.icmsCst ||
              p.isDefault != padrao.isDefault) {
            _perfisTributarios[i] = PerfilTributario(
              id: p.id, // Preserva o ID existente (vínculo com produtos)
              nome: p.nome,
              cfop: padrao.cfop,
              icmsCst: padrao.icmsCst,
              csosn: padrao.csosn,
              // Preserva customizações do usuário no perfil existente
              aliquotaIcms: p.aliquotaIcms,
              pisCst: p.pisCst,
              aliquotaPis: p.aliquotaPis,
              cofinsCst: p.cofinsCst,
              aliquotaCofins: p.aliquotaCofins,
              cstIbs: p.cstIbs,
              aliquotaIbs: p.aliquotaIbs,
              cstCbs: p.cstCbs,
              aliquotaCbs: p.aliquotaCbs,
              ipiCst: p.ipiCst,
              aliquotaIpi: p.aliquotaIpi,
              mva: p.mva,
              reducaoBaseIcms: p.reducaoBaseIcms,
              aliquotaFcp: p.aliquotaFcp,
              aliquotaIcmsInterestadual: p.aliquotaIcmsInterestadual,
              ncm: p.ncm,
              isDefault: padrao.isDefault,
            );
            mudou = true;
          }
          return;
        }
      }
      _perfisTributarios.add(padrao);
      mudou = true;
    }

    // TRIBUTADO é o perfil padrão do sistema (CFOP 5102, CSOSN 102)
    garantirPadrao(PerfilTributario(
      id: 'padrao_tributado_simples',
      nome: 'Tributado (Simples Nacional)',
      cfop: '5102',
      csosn: '102',
      isDefault: true,
    ));
    // Não Tributado: CSOSN 400 (não tributada pelo Simples Nacional).
    // ATENÇÃO: CSOSN 500 é "ICMS cobrado anteriormente por ST", NÃO é não-tributado.
    garantirPadrao(PerfilTributario(
      id: 'padrao_nao_tributado_simples',
      nome: 'Não Tributado (Simples Nacional)',
      cfop: '5102',
      csosn: '400',
    ));
    // Substituição Tributária (substituído): CFOP 5405, CSOSN 500
    garantirPadrao(PerfilTributario(
      id: 'padrao_substituicao_simples',
      nome: 'Substituição Tributária (Simples Nacional)',
      cfop: '5405',
      csosn: '500',
    ));
    garantirPadrao(PerfilTributario(
      id: 'padrao_tributado_normal',
      nome: 'Tributado (Regime Normal)',
      cfop: '5102',
      icmsCst: '00',
      isDefault: true,
    ));
    garantirPadrao(PerfilTributario(
      id: 'padrao_nao_tributado_normal',
      nome: 'Não Tributado (Regime Normal)',
      cfop: '5102',
      icmsCst: '41',
    ));
    // Substituição Tributária (substituído): CFOP 5405, CST 60
    // (ICMS cobrado anteriormente por ST - equivalente ao CSOSN 500)
    garantirPadrao(PerfilTributario(
      id: 'padrao_substituicao_normal',
      nome: 'Substituição Tributária (Regime Normal)',
      cfop: '5405',
      icmsCst: '60',
    ));
    if (mudou) {
      debugPrint('>>> [DataService] ✅ Perfis tributários padrão garantidos/corrigidos para a empresa atual');
    }
    return mudou;
  }

  /// Persiste a lista de perfis tributários na configuração da empresa atual
  /// (PostgreSQL local + Supabase), onde o backend NFC-e os busca.
  Future<void> _persistirPerfisTributariosNaEmpresa() async {
    final empresa = _empresaAtual;
    if (empresa == null) return;
    if (_persistindoPerfisTributarios) return;
    _persistindoPerfisTributarios = true;
    try {
      final novasConfigs = Map<String, dynamic>.from(empresa.configuracoes ?? {});
      novasConfigs['perfis_tributarios'] = _perfisTributarios.map((p) => p.toMap()).toList();
      await atualizarDadosEmpresa(empresa.copyWith(configuracoes: novasConfigs));
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao persistir perfis tributários na empresa: $e');
    } finally {
      _persistindoPerfisTributarios = false;
    }
  }

  /// Salva ou atualiza um perfil tributário
  Future<void> salvarPerfilTributario(PerfilTributario perfil) async {
    final index = _perfisTributarios.indexWhere((p) => p.id == perfil.id);
    if (index >= 0) {
      _perfisTributarios[index] = perfil;
    } else {
      _perfisTributarios.add(perfil);
    }
    
    if (perfil.isDefault) {
      // Existe um perfil padrão POR REGIME (Simples = CSOSN, Normal = CST).
      // Ao marcar um como padrão, desmarca apenas os padrões do MESMO regime
      // (preservando o default do regime oposto).
      final perfilTemCst = perfil.icmsCst?.trim().isNotEmpty == true;
      final perfilTemCsosn = perfil.csosn?.trim().isNotEmpty == true;
      for (int i = 0; i < _perfisTributarios.length; i++) {
        final p = _perfisTributarios[i];
        if (p.id != perfil.id && p.isDefault) {
          final mesmoRegime = (perfilTemCst && p.icmsCst?.trim().isNotEmpty == true) ||
              (perfilTemCsosn && p.csosn?.trim().isNotEmpty == true);
          if (!mesmoRegime) continue;
          _perfisTributarios[i] = PerfilTributario(
            id: p.id,
            nome: p.nome,
            cfop: p.cfop,
            icmsCst: p.icmsCst,
            csosn: p.csosn,
            aliquotaIcms: p.aliquotaIcms,
            pisCst: p.pisCst,
            aliquotaPis: p.aliquotaPis,
            cofinsCst: p.cofinsCst,
            aliquotaCofins: p.aliquotaCofins,
            cstIbs: p.cstIbs,
            aliquotaIbs: p.aliquotaIbs,
            cstCbs: p.cstCbs,
            aliquotaCbs: p.aliquotaCbs,
            ipiCst: p.ipiCst,
            aliquotaIpi: p.aliquotaIpi,
            mva: p.mva,
            reducaoBaseIcms: p.reducaoBaseIcms,
            aliquotaFcp: p.aliquotaFcp,
            aliquotaIcmsInterestadual: p.aliquotaIcmsInterestadual,
            ncm: p.ncm,
            isDefault: false,
          );
        }
      }
    }
    
    final chave = _getChaveComEmpresa('perfis_tributarios');
    await _storage.salvarLista(chave, _perfisTributarios.map((p) => p.toMap()).toList());

    // PERSISTÊNCIA NO BANCO: gravar na configuração da empresa (PostgreSQL local + Supabase)
    await _persistirPerfisTributariosNaEmpresa();
    notifyListeners();
  }

  /// Exclui um perfil tributário pelo ID
  Future<void> excluirPerfilTributario(String perfilId) async {
    _perfisTributarios.removeWhere((p) => p.id == perfilId);
    final chave = _getChaveComEmpresa('perfis_tributarios');
    await _storage.salvarLista(chave, _perfisTributarios.map((p) => p.toMap()).toList());
    await _persistirPerfisTributariosNaEmpresa();
    notifyListeners();
  }

  // ===========================================================================
  // DEPARTAMENTOS (setores de preparação: Cozinha, Bar, Sobremesas, etc.)
  // ===========================================================================

  /// Carrega os departamentos da empresa a partir de
  /// `empresa.configuracoes['departamentos']` (persistida no banco — PostgreSQL
  /// local + Supabase). Se não houver nenhum, garante os padrões (Cozinha e Bar)
  /// para o sistema funcionar sem configuração prévia.
  void _carregarDepartamentosDaEmpresa() {
    if (_empresaAtual == null) return;
    _departamentos.clear();
    final raw = _empresaAtual?.configuracoes?['departamentos'];
    if (raw is List && raw.isNotEmpty) {
      for (final item in raw) {
        if (item is Map) {
          final dep = Departamento.fromMap(Map<String, dynamic>.from(item));
          if (dep.nome.trim().isNotEmpty) {
            _departamentos.add(dep);
          }
        }
      }
    }
    // Garante os padrões (Cozinha e Bar) se a lista estiver vazia e persiste
    // apenas se algo foi adicionado (evita gravações desnecessárias no banco).
    final adicionouPadrao = _criarDepartamentosPadrao();
    if (adicionouPadrao) {
      unawaited(_persistirDepartamentosNaEmpresa());
    }
    // Sempre confere o cache local por cima (última edição do usuário não some).
    unawaited(_migrarDepartamentosDoCache());
    notifyListeners();
  }

  /// Recupera departamentos salvos apenas no cache local (compatibilidade com
  /// versões que guardavam a lista fora da configuração da empresa).
  Future<void> _migrarDepartamentosDoCache() async {
    try {
      final chave = _getChaveComEmpresa('departamentos');
      final cache = await _storage.carregarLista(chave);
      if (cache is List && cache.isNotEmpty) {
        var mudou = false;
        for (final item in cache) {
          if (item is! Map) continue;
          final dep = Departamento.fromMap(Map<String, dynamic>.from(item));
          if (dep.nome.trim().isEmpty) continue;
          if (!_departamentos.any((d) => d.id == dep.id)) {
            _departamentos.add(dep);
            mudou = true;
          }
        }
        if (mudou) {
          await _persistirDepartamentosNaEmpresa();
        }
      }
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao migrar departamentos do cache: $e');
    }
  }

  /// Garante os departamentos padrão (Cozinha e Bar) caso a empresa ainda não
  /// tenha nenhum. Retorna true se algo foi adicionado.
  bool _criarDepartamentosPadrao() {
    var mudou = false;
    void garantirPadrao(Departamento padrao) {
      for (final d in _departamentos) {
        if (d.id == padrao.id ||
            d.nome.trim().toLowerCase() == padrao.nome.trim().toLowerCase()) {
          return;
        }
      }
      _departamentos.add(padrao);
      mudou = true;
    }

    garantirPadrao(Departamento(
      id: 'dep_cozinha',
      nome: 'Cozinha',
      cor: '#FF5722',
      icone: 'restaurant',
      ordem: 0,
    ));
    garantirPadrao(Departamento(
      id: 'dep_bar',
      nome: 'Bar',
      cor: '#2196F3',
      icone: 'local_bar',
      ordem: 1,
    ));
    if (mudou) {
      debugPrint('>>> [DataService] ✅ Departamentos padrão garantidos para a empresa atual');
    }
    return mudou;
  }

  /// Persiste a lista de departamentos na configuração da empresa atual
  /// (PostgreSQL local + Supabase).
  Future<void> _persistirDepartamentosNaEmpresa() async {
    final empresa = _empresaAtual;
    if (empresa == null) return;
    if (_persistindoDepartamentos) return;
    _persistindoDepartamentos = true;
    try {
      final novasConfigs = Map<String, dynamic>.from(empresa.configuracoes ?? {});
      novasConfigs['departamentos'] = _departamentos.map((d) => d.toMap()).toList();
      await atualizarDadosEmpresa(empresa.copyWith(configuracoes: novasConfigs));
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao persistir departamentos na empresa: $e');
    } finally {
      _persistindoDepartamentos = false;
    }
  }

  /// Salva ou atualiza um departamento (cria se não existir).
  Future<void> salvarDepartamento(Departamento departamento) async {
    final index = _departamentos.indexWhere((d) => d.id == departamento.id);
    if (index >= 0) {
      _departamentos[index] = departamento;
    } else {
      _departamentos.add(departamento);
    }
    // Ordena pela ordem definida
    _departamentos.sort((a, b) => a.ordem.compareTo(b.ordem));
    // Cache local + banco
    final chave = _getChaveComEmpresa('departamentos');
    await _storage.salvarLista(chave, _departamentos.map((d) => d.toMap()).toList());
    await _persistirDepartamentosNaEmpresa();
    notifyListeners();
  }

  /// Exclui um departamento pelo ID. Produtos que apontavam para ele ficam
  /// sem departamento (campo limpo) para não quebrar o fluxo de vendas.
  Future<void> excluirDepartamento(String departamentoId) async {
    _departamentos.removeWhere((d) => d.id == departamentoId);
    // Desvincula produtos que apontavam para este departamento
    var mudouProdutos = false;
    for (int i = 0; i < _produtos.length; i++) {
      final p = _produtos[i];
      if (p.departamentoId == departamentoId) {
        _produtos[i] = p.copyWith(departamentoId: null, updatedAt: DateTime.now());
        mudouProdutos = true;
      }
    }
    if (mudouProdutos) {
      await _salvarTodosDados(aguardarSupabase: false, isSync: true);
    }
    final chave = _getChaveComEmpresa('departamentos');
    await _storage.salvarLista(chave, _departamentos.map((d) => d.toMap()).toList());
    await _persistirDepartamentosNaEmpresa();
    notifyListeners();
  }

  // ===========================================================================
  // MIGRAÇÃO DE IMPOSTOS POR REGIME TRIBUTÁRIO
  // ===========================================================================

  /// Mapeia um código CSOSN (Simples Nacional) para o CST equivalente (Regime Normal).
  static String csosnParaCst(String csosn) {
    const mapa = {
      '101': '00',
      '102': '00',
      '103': '00',
      '201': '10',
      '202': '10',
      '203': '10',
      '300': '40',
      '400': '41',
      '500': '60', // ICMS cobrado anteriormente por ST -> CST 60 (não 41!)
      '900': '90', // Outros -> CST 90
    };
    return mapa[csosn] ?? '00';
  }

  /// Mapeia um código CST (Regime Normal) para o CSOSN equivalente (Simples Nacional).
  static String cstParaCsosn(String cst) {
    const mapa = {
      '00': '102',
      '02': '102',
      '10': '201',
      '20': '103',
      '30': '203',
      '40': '300',
      '41': '400',
      '50': '400',
      '51': '400',
      '60': '500',
      '70': '202',
      '90': '900',
    };
    return mapa[cst] ?? '102';
  }

  /// ID do perfil tributário padrão equivalente no outro regime (se existir).
  static String? _perfilEquivalenteOutroRegime(String? perfilId, {required bool paraSimples}) {
    if (perfilId == null || perfilId.isEmpty) return null;
    if (paraSimples) {
      switch (perfilId) {
        case 'padrao_tributado_normal':
          return 'padrao_tributado_simples';
        case 'padrao_nao_tributado_normal':
          return 'padrao_nao_tributado_simples';
        case 'padrao_substituicao_normal':
          return 'padrao_substituicao_simples';
        default:
          return null; // Perfis personalizados: mantém o vínculo (será resolvido na emissão pelo regime)
      }
    }
    switch (perfilId) {
      case 'padrao_tributado_simples':
        return 'padrao_tributado_normal';
      case 'padrao_nao_tributado_simples':
        return 'padrao_nao_tributado_normal';
      case 'padrao_substituicao_simples':
        return 'padrao_substituicao_normal';
      default:
        return null;
    }
  }

  /// Migra os impostos de TODOS os produtos para o regime tributário informado.
  ///
  /// - `paraSimples == true`  -> CRT 1/2: cada produto passa a ter CSOSN (convertido
  ///   do CST atual, padrão 102) e limpa o CST/CFOP manual.
  /// - `paraSimples == false` -> CRT 3 (Regime Normal): cada produto passa a ter
  ///   CST (convertido do CSOSN atual, padrão 00) e limpa o CSOSN manual.
  ///
  /// Perfis tributários padrão também são trocados pelo equivalente do novo regime.
  /// Retorna a quantidade de produtos alterados.
  Future<int> migrarImpostosProdutosPorRegime({required bool paraSimples}) async {
    final produtos = List<Produto>.from(_produtos);
    var alterados = 0;

    for (final p in produtos) {
      final csosnAtual = p.csosn?.trim();
      final cstAtual = p.icmsCst?.trim();
      final temCsosn = csosnAtual != null && csosnAtual.isNotEmpty;
      final temCst = cstAtual != null && cstAtual.isNotEmpty;

      String? novoCsosn;
      String? novoCst;
      // Perfis padrão têm equivalente no outro regime (ex: padrao_tributado_simples
      // <-> padrao_tributado_normal). Perfis PERSONALIZADOS não têm equivalente:
      // desvinculamos o produto do perfil (null) para que ele não sobrescreva os
      // impostos migrados na emissão com valores do regime antigo.
      final novoPerfilId = _perfilEquivalenteOutroRegime(p.perfilTributarioId, paraSimples: paraSimples);

      if (paraSimples) {
        // Regime Normal -> Simples Nacional
        if (temCsosn) {
          novoCsosn = csosnAtual; // Já é CSOSN
        } else if (temCst) {
          novoCsosn = cstParaCsosn(cstAtual);
        } else {
          novoCsosn = '102'; // Padrão Simples: tributado sem crédito
        }
      } else {
        // Simples Nacional -> Regime Normal
        if (temCst) {
          novoCst = cstAtual; // Já é CST
        } else if (temCsosn) {
          novoCst = csosnParaCst(csosnAtual);
        } else {
          novoCst = '00'; // Padrão Regime Normal: tributada integralmente
        }
      }

      final mudou = (novoCst != p.icmsCst?.trim()) ||
          (novoCsosn != p.csosn?.trim()) ||
          (novoPerfilId != p.perfilTributarioId);
      if (!mudou) {
        continue;
      }

      // Preserva o CFOP do produto (ex: 5405 ST, 5202 devolução); só usa o
      // 5102 (venda interna) quando o produto não possui CFOP definido.
      final cfopAtual = p.cfop?.trim() ?? '';
      final novoCfop = cfopAtual.isNotEmpty ? cfopAtual : '5102';

      final migrado = p.copyWith(
        icmsCst: novoCst,
        csosn: novoCsosn,
        cfop: novoCfop,
        perfilTributarioId: novoPerfilId,
        updatedAt: DateTime.now(),
      );

      // Persiste local + Supabase (sem gerar histórico em massa)
      await updateProduto(
        migrado,
        aguardarSincronia: false,
        registrarMovimento: false,
        notify: false,
        registrarHistorico: false,
      );
      alterados++;
    }

    if (alterados > 0) {
      notifyListeners();
    }
    return alterados;
  }

  // ===========================================================================
  // CAIXA - CÁLCULOS
  // ===========================================================================

  /// Calcula o total em dinheiro no caixa atual
  double calcularDinheiroEmCaixa() {
    final abertura = aberturaCaixaAtual;
    if (abertura == null) return 0.0;
    double total = abertura.valorInicial;
    
    for (final sup in getSuprimentosDoCaixa(abertura)) {
      total += sup.valor;
    }
    for (final sang in getSangriasDoCaixa(abertura)) {
      total -= sang.valor;
    }
    for (final venda in _vendasBalcao.where((v) => !v.isCancelada)) {
      if (venda.tipoPagamento.name.toLowerCase().contains('dinheiro')) {
        total += venda.valorTotal;
      }
    }
    return total;
  }

  /// Cancela uma troca/devolução
  Future<void> cancelarTrocaDevolucao(String id) async {
    final index = _trocasDevolucoes.indexWhere((t) => t.id == id);
    if (index >= 0) {
      final troca = _trocasDevolucoes[index];
      _trocasDevolucoes[index] = troca.copyWith(
        status: 'cancelada',
      );
      notifyListeners();
    }
  }
}

