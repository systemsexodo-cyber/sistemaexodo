import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/usuario.dart';

import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/servico_realizado.dart';
import 'package:sistema_exodo_novo/models/orcamento.dart';
import 'package:sistema_exodo_novo/models/ordem_servico.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/models/troca_devolucao.dart';
import 'package:sistema_exodo_novo/models/estoque_historico.dart';
import 'package:sistema_exodo_novo/models/estoque.dart';
import 'package:sistema_exodo_novo/models/ajuste_estoque_lote.dart';
import 'package:sistema_exodo_novo/models/conflito_sync.dart';
import 'package:sistema_exodo_novo/services/faixa_numeracao_service.dart';
import 'package:sistema_exodo_novo/services/fila_producao_service.dart';
import 'package:sistema_exodo_novo/utils/numeracao_venda.dart';
import 'package:sistema_exodo_novo/utils/identidade_caixa.dart';
// Só os tipos usados na resolução de conflitos (as consultas nomeadas): os
// nomes do pacote não entram no arquivo inteiro para não colidir com os do app.
import 'package:postgres/postgres.dart' show Session, Sql;
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/models/lote_produto.dart';
import 'package:sistema_exodo_novo/models/produto_historico.dart';
import 'package:sistema_exodo_novo/models/nota_entrada.dart';
import 'package:sistema_exodo_novo/models/pedido_compra.dart';
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
import 'package:sistema_exodo_novo/services/cash_back_service.dart';
import 'package:sistema_exodo_novo/models/link_vendedor.dart';
import 'package:sistema_exodo_novo/models/comissao_vendedor.dart';
import 'package:sistema_exodo_novo/models/cash_back_movimento.dart';
import 'package:sistema_exodo_novo/models/motorista.dart';
import 'package:sistema_exodo_novo/models/romaneio.dart';
import 'package:sistema_exodo_novo/models/perfil_tributario.dart';
import 'package:sistema_exodo_novo/models/departamento.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'package:sistema_exodo_novo/services/realtime_sync_service.dart';
import 'package:sistema_exodo_novo/services/lan_realtime_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sistema_exodo_novo/services/sync_queue_service.dart';
import 'package:sistema_exodo_novo/services/whatsapp_service.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/services/google_drive_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/backup_restore_service.dart';
import 'package:sistema_exodo_novo/services/connection_logger_service.dart';
import 'package:sistema_exodo_novo/services/sync_monitor_service.dart';
import 'package:uuid/uuid.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Import condicional para Web
import '../pages/html_helper_stub.dart'
    if (dart.library.html) '../pages/html_helper_web.dart'
    as html_helper;

// Re-export TipoPessoa para facilitar uso
export 'package:sistema_exodo_novo/models/cliente.dart' show TipoPessoa;

const uuid = Uuid();

/// Resultado do botão **"Limpar Local"**: o que foi apagado DESTA empresa e a
/// prova de que as outras empresas continuaram intactas.
class ResultadoLimpezaLocal {
  final String empresaId;
  final String empresaNome;

  /// `tabela -> linhas apagadas` (tabelas que já estavam vazias não aparecem).
  final Map<String, int> porTabela;

  /// Linhas das OUTRAS empresas que continuaram nas mesmas tabelas depois da
  /// limpeza. É a evidência de que só a empresa alvo foi tocada.
  final int linhasDeOutrasEmpresas;

  const ResultadoLimpezaLocal({
    required this.empresaId,
    required this.empresaNome,
    required this.porTabela,
    required this.linhasDeOutrasEmpresas,
  });

  int get total => porTabela.values.fold<int>(0, (soma, qtd) => soma + qtd);
  int get tabelas => porTabela.length;
}

/// O PLANO da troca de regime: quem muda, quem já está certo e quem ficou de
/// fora — montado antes de qualquer gravação (dá para mostrar na tela e testar).
class PlanoMigracaoImpostos {
  /// Produtos da empresa alvo que serão gravados.
  final List<Produto> paraGravar;

  /// Produtos de OUTRA empresa: não são tocados (nem lidos de novo).
  final List<Produto> deOutraEmpresa;

  /// Produtos da empresa alvo sem o carimbo de empresa (registro antigo/novo).
  final List<Produto> semCarimbo;

  /// O PERFIL PADRÃO do regime novo — é ele (com o CFOP e o CSOSN/CST dele) que
  /// os produtos SEM NENHUM imposto cadastrado recebem na troca.
  final PerfilTributario perfilPadraoDoRegimeNovo;

  /// Já tinham imposto cadastrado: o que está no CADASTRO do produto é
  /// preservado (só o código muda de espécie quando o regime exige).
  final int convertidos;

  /// Não tinham NENHUM imposto cadastrado e ganham o PERFIL PADRÃO do regime novo.
  final int preenchidos;

  /// Já tinham código próprio, mas NENHUM perfil cadastrado: passam a apontar
  /// para o perfil PADRÃO que combina com o código deles (o código não muda).
  final int vinculadosAoPadrao;

  final int semMudanca; // já estavam no regime novo

  const PlanoMigracaoImpostos({
    required this.paraGravar,
    required this.deOutraEmpresa,
    required this.semCarimbo,
    required this.perfilPadraoDoRegimeNovo,
    required this.convertidos,
    required this.preenchidos,
    required this.vinculadosAoPadrao,
    required this.semMudanca,
  });
}

/// O que a troca de regime fez de fato.
class ResultadoMigracaoImpostos {
  final int gravados;
  final int convertidos;
  final int preenchidos;

  /// Sem perfil cadastrado, mas com código próprio: passaram a usar o perfil
  /// PADRÃO do mesmo imposto (o código do produto não mudou).
  final int vinculadosAoPadrao;

  final int semMudanca;

  /// Produtos de outra empresa que ficaram de fora (o número que precisa ser
  /// ZERO numa empresa sadia).
  final int deOutraEmpresa;

  /// Produtos da empresa que estavam sem carimbo de empresa.
  final int semCarimbo;

  const ResultadoMigracaoImpostos({
    required this.gravados,
    required this.convertidos,
    required this.preenchidos,
    required this.vinculadosAoPadrao,
    required this.semMudanca,
    required this.deOutraEmpresa,
    required this.semCarimbo,
  });

  /// Quantos produtos tiveram o código fiscal reescrito.
  int get alterados => convertidos + preenchidos;

  bool get tocouEmOutraEmpresa => deOutraEmpresa > 0;
}

class DataService extends ChangeNotifier {
  /// Callback opcional para manter o AuthService em sincronia quando as
  /// configurações da empresa atual mudam (perfis tributários, departamentos,
  /// estoques, etc.). Injetado no `main.dart`.
  void Function(Empresa empresa)? onEmpresaAtualizada;

  List<EstoqueHistorico> get estoqueHistorico => _estoqueHistorico;

  /// Lotes de ajuste em massa (estoque/preço) aplicados — mais recente primeiro.
  /// Servem de auditoria e permitem desfazer o ajuste inteiro depois.
  List<AjusteEstoqueLote> get ajustesEstoqueLote => _ajustesEstoqueLote;
  List<LoteProduto> get lotesProdutos => _lotesProdutos;
  // Dados locais (em memória)
  final List<Cliente> _clientes = [];
  final List<Produto> _produtos = [];
  final List<Servico> _tiposServico = [];
  final List<Pedido> _pedidos = [];
  // Serviços realizados: entidade própria (tabela `servicos_realizados`),
  // separada de `pedidos` — numeração SRV, orçamento, em aberto e recebido.
  final List<ServicoRealizado> _servicosRealizados = [];
  // Orçamentos de pedido (tela de Pedidos central): entidade própria, série
  // ORC-. Fora do PDV, dos recebíveis e dos relatórios de venda até ser
  // aprovado — a aprovação gera um Pedido (PED-).
  final List<Orcamento> _orcamentos = [];
  final List<OrdemServico> _ordensServico = [];
  final List<Entrega> _entregas = [];
  final List<Motorista> _motoristas = [];
  final List<VendaBalcao> _vendasBalcao = [];
  final List<TrocaDevolucao> _trocasDevolucoes = [];
  final List<EstoqueHistorico> _estoqueHistorico = [];
  final List<AjusteEstoqueLote> _ajustesEstoqueLote = [];
  final List<LoteProduto> _lotesProdutos = [];

  // Getters públicos para acesso às listas (se não existirem)
  final List<NotaEntrada> _notasEntrada = [];
  final List<PedidoCompra> _pedidosCompra = [];
  final List<AgendamentoServico> _agendamentosServico = [];
  final List<Funcionario> _funcionarios = [];
  final List<TaxaEntrega> _taxasEntrega = [];
  final List<ContaPagar> _contasPagar = [];
  final List<NFCe> _nfces = [];
  final List<NFCe> _nfes = [];
  final List<MesaComanda> _mesasComandas = [];
  final List<LinkVendedor> _linksVendedores = [];
  final List<ComissaoVendedor> _comissoesVendedores = [];
  final List<CashBackMovimento> _movimentosCashBack = [];
  final List<Romaneio> _romaneios = [];
  final List<PerfilTributario> _perfisTributarios = [];
  bool _migrandoPerfisTributarios =
      false; // Guard contra corrida na migração do cache
  bool _persistindoPerfisTributarios =
      false; // Guard contra recursão na persistência
  final List<Departamento> _departamentos = [];
  bool _migrandoDepartamentos =
      false; // Guard contra corrida na migração do cache
  bool _persistindoDepartamentos =
      false; // Guard contra recursão na persistência
  final List<Estoque> _estoques = [];
  bool _persistindoEstoques = false; // Guard contra recursão na persistência

  // Licenciamento
  DateTime? _ultimaValidacaoOnline;
  DateTime? _ultimaDataExecucao;
  bool _liberacaoProvisoriaAtiva = false;
  String? _responsavelAtivo;

  // Controle de Performance de Sincronização

  // Controle do pulso do portal (web). O navegador estrangula timers de abas
  // escondidas (~1×/minuto), então guardamos quando o pulso rodou por último
  // para diagnosticar atrasos e para não duplicar pulsos quando a aba volta.
  DateTime? _ultimoPulsoWeb;
  DateTime? _ultimoRetornoWeb;

  // Controle de sincronização Google Drive
  final Set<String> _notasSincronizadasDrive = {};
  bool _syncDriveEmAndamento = false;

  // Monitor de Bridge (NFC-e)
  List<Map<String, dynamic>> _bridgesStatus = [];

  // Controle de Sincronização e Snapshots
  bool _primeiraCargaAgendamentosRealizada = false;
  bool _syncMonitorInitialized = false;
  StreamSubscription? _produtosSubscription;
  StreamSubscription? _servicosSubscription;
  StreamSubscription? _agendamentosSubscription;

  List<Map<String, dynamic>> get bridgesStatus => _bridgesStatus;
  int get bridgeOnlineCount => _bridgesStatus
      .where(
        (b) =>
            b['online'] == true && !b['id'].toString().startsWith('watchdog_'),
      )
      .length;

  /// Verifica se existe algum bridge online para um CNPJ específico
  bool isEmpresaBridgeOnline(String? cnpj) {
    if (cnpj == null || cnpj.isEmpty) return false;
    final cnpjLimpo = cnpj.replaceAll(RegExp(r'[^0-9]'), '');
    return _bridgesStatus.any((b) {
      final bCnpj =
          b['ultimo_cnpj']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      return b['online'] == true && bCnpj == cnpjLimpo;
    });
  }

  // Getters públicos
  List<AgendamentoServico> get agendamentos => agendamentosServico;

  // Getter que filtra apenas o que está "ATIVO" (Aberta).
  // Isso resolve definitivamente o problema de mesas que não somem após o recebimento.
  List<MesaComanda> get mesasComandas =>
      _mesasComandas.where((m) => m.status == 'Aberta').toList();

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
        'servicos_realizados': _servicosRealizados
            .map((e) => e.toMap())
            .toList(),
        'orcamentos': _orcamentos.map((e) => e.toMap()).toList(),
        'vendas_balcao': _vendasBalcao.map((e) => e.toMap()).toList(),
        'agendamentos': _agendamentosServico.map((e) => e.toMap()).toList(),
        'contas_pagar': _contasPagar.map((e) => e.toMap()).toList(),
        'notas_entrada': _notasEntrada.map((e) => e.toMap()).toList(),
        'pedidos_compra': _pedidosCompra.map((e) => e.toMap()).toList(),
        'funcionarios': _funcionarios.map((e) => e.toMap()).toList(),
        'ordens_servico': _ordensServico.map((e) => e.toMap()).toList(),
        'trocas_devolucoes': _trocasDevolucoes.map((e) => e.toMap()).toList(),
        'comissoes': _comissoesVendedores.map((e) => e.toMap()).toList(),
        'nfces': _nfces.map((e) => e.toMap()).toList(),
        'romaneios': _romaneios.map((e) => e.toMap()).toList(),
        // Coleções que faltavam: sem elas o backup não restaurava caixa,
        // entregas, mesas/comandas, estoque, lotes, NF-e nem links de venda.
        'nfes': _nfes.map((e) => e.toMap()).toList(),
        'entregas': _entregas.map((e) => e.toMap()).toList(),
        'motoristas': _motoristas.map((e) => e.toMap()).toList(),
        'taxas_entrega': _taxasEntrega.map((e) => e.toMap()).toList(),
        'links_vendedores': _linksVendedores.map((e) => e.toMap()).toList(),
        'mesas_comandas': _mesasComandas.map((e) => e.toMap()).toList(),
        'aberturas_caixa': _aberturasCaixa.map((e) => e.toMap()).toList(),
        'fechamentos_caixa': _fechamentosCaixa.map((e) => e.toMap()).toList(),
        'sangrias': _sangrias.map((e) => e.toMap()).toList(),
        'suprimentos': _suprimentos.map((e) => e.toMap()).toList(),
        'estoque_historico': _estoqueHistorico.map((e) => e.toMap()).toList(),
        'ajustes_estoque_lote': _ajustesEstoqueLote
            .map((e) => e.toMap())
            .toList(),
        'lotes_produto': _lotesProdutos.map((e) => e.toMap()).toList(),
      },
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
      _servicosRealizados.clear();
      _orcamentos.clear();
      _ordensServico.clear();
      _vendasBalcao.clear();
      _trocasDevolucoes.clear();
      _agendamentosServico.clear();
      _contasPagar.clear();
      _notasEntrada.clear();
      _pedidosCompra.clear();
      _funcionarios.clear();
      _nfces.clear();
      _romaneios.clear();
      _comissoesVendedores.clear();
      _linksVendedores.clear();

      // Importar cada coleção usando fromMap dos modelos
      if (colecoes['clientes'] is List) {
        for (final item in colecoes['clientes'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa: cliente carimbado com OUTRA empresa no arquivo
          // fica de fora (mesma regra de produtos/serviços acima).
          if (!_registroDaEmpresaAberta(map)) continue;
          _clientes.add(Cliente.fromMap(map));
        }
      }
      if (colecoes['produtos'] is List) {
        final doBackup = (colecoes['produtos'] as List)
            .map((item) => Produto.fromMap(item as Map<String, dynamic>))
            .toList();
        // Trava de empresa: produto carimbado com OUTRA empresa no arquivo fica
        // de fora (restaurar o backup de uma empresa com a outra aberta levaria
        // o catálogo inteiro para o lugar errado).
        _produtos.addAll(
          somenteProdutosDaEmpresaAberta(doBackup, origem: 'backup'),
        );
      }
      if (colecoes['servicos'] is List) {
        for (final item in colecoes['servicos'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa: serviço carimbado com OUTRA empresa no backup não
          // entra (antes ele "aparecia em todas" ao restaurar).
          if (!_registroDaEmpresaAberta(map)) continue;
          _tiposServico.add(Servico.fromMap(map));
        }
      }
      if (colecoes['pedidos'] is List) {
        for (final item in colecoes['pedidos'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa (mesma regra dos produtos/serviços).
          if (!_registroDaEmpresaAberta(map)) continue;
          _pedidos.add(Pedido.fromMap(map));
        }
      }
      if (colecoes['servicos_realizados'] is List) {
        for (final item in colecoes['servicos_realizados'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa: serviço realizado carimbado com OUTRA empresa
          // não entra (mesma regra de produtos/serviços/agendamentos acima).
          if (!_registroDaEmpresaAberta(map)) continue;
          _servicosRealizados.add(ServicoRealizado.fromMap(map));
        }
      }
      if (colecoes['orcamentos'] is List) {
        for (final item in colecoes['orcamentos'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa: orçamento de outra empresa não entra — sem isto,
          // restaurar o backup de uma empresa com a outra aberta levava os
          // ORC- para o lugar errado (e o reenvio à nuvem re-carimbava).
          if (!_registroDaEmpresaAberta(map)) continue;
          _orcamentos.add(Orcamento.fromMap(map));
        }
      }
      if (colecoes['vendas_balcao'] is List) {
        for (final item in colecoes['vendas_balcao'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa (mesma regra dos produtos/serviços).
          if (!_registroDaEmpresaAberta(map)) continue;
          _vendasBalcao.add(VendaBalcao.fromMap(map));
        }
      }
      if (colecoes['agendamentos'] is List) {
        for (final item in colecoes['agendamentos'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _agendamentosServico.add(AgendamentoServico.fromMap(map));
        }
      }
      if (colecoes['contas_pagar'] is List) {
        for (final item in colecoes['contas_pagar'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _contasPagar.add(ContaPagar.fromMap(map));
        }
      }
      if (colecoes['notas_entrada'] is List) {
        for (final item in colecoes['notas_entrada'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa (mesma regra dos produtos/serviços).
          if (!_registroDaEmpresaAberta(map)) continue;
          _notasEntrada.add(NotaEntrada.fromMap(map));
        }
      }
      if (colecoes['pedidos_compra'] is List) {
        for (final item in colecoes['pedidos_compra'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _pedidosCompra.add(PedidoCompra.fromMap(map));
        }
      }
      if (colecoes['funcionarios'] is List) {
        for (final item in colecoes['funcionarios'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa (mesma regra dos produtos/serviços).
          if (!_registroDaEmpresaAberta(map)) continue;
          _funcionarios.add(Funcionario.fromMap(map));
        }
      }
      if (colecoes['ordens_servico'] is List) {
        for (final item in colecoes['ordens_servico'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa (mesma regra dos produtos/serviços).
          if (!_registroDaEmpresaAberta(map)) continue;
          _ordensServico.add(OrdemServico.fromMap(map));
        }
      }
      if (colecoes['trocas_devolucoes'] is List) {
        for (final item in colecoes['trocas_devolucoes'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa (mesma regra dos produtos/serviços).
          if (!_registroDaEmpresaAberta(map)) continue;
          final trocaItem = TrocaDevolucao.fromMap(map);
          if (_isTrocaDevolucaoValida(trocaItem)) {
            _trocasDevolucoes.add(trocaItem);
          }
        }
      }
      if (colecoes['comissoes'] is List) {
        for (final item in colecoes['comissoes'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa (mesma regra dos produtos/serviços).
          if (!_registroDaEmpresaAberta(map)) continue;
          _comissoesVendedores.add(ComissaoVendedor.fromMap(map));
        }
      }
      if (colecoes['nfces'] is List) {
        for (final item in colecoes['nfces'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa (mesma regra dos produtos/serviços).
          if (!_registroDaEmpresaAberta(map)) continue;
          _nfces.add(NFCe.fromMap(map));
        }
      }
      if (colecoes['romaneios'] is List) {
        for (final item in colecoes['romaneios'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          // Trava de empresa (mesma regra dos produtos/serviços).
          if (!_registroDaEmpresaAberta(map)) continue;
          _romaneios.add(Romaneio.fromMap(map));
        }
      }

      // Coleções que também faltavam no restore (mesmas do export).
      if (colecoes['nfes'] is List) {
        _nfes.clear();
        for (final item in colecoes['nfes'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _nfes.add(NFCe.fromMap(map));
        }
      }
      if (colecoes['entregas'] is List) {
        _entregas.clear();
        for (final item in colecoes['entregas'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _entregas.add(Entrega.fromMap(map));
        }
      }
      if (colecoes['motoristas'] is List) {
        _motoristas.clear();
        for (final item in colecoes['motoristas'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _motoristas.add(Motorista.fromMap(map));
        }
      }
      if (colecoes['taxas_entrega'] is List) {
        _taxasEntrega.clear();
        for (final item in colecoes['taxas_entrega'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _taxasEntrega.add(TaxaEntrega.fromMap(map));
        }
      }
      if (colecoes['links_vendedores'] is List) {
        _linksVendedores.clear();
        for (final item in colecoes['links_vendedores'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _linksVendedores.add(LinkVendedor.fromMap(map));
        }
      }
      if (colecoes['mesas_comandas'] is List) {
        _mesasComandas.clear();
        for (final item in colecoes['mesas_comandas'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _mesasComandas.add(MesaComanda.fromMap(map));
        }
      }
      if (colecoes['aberturas_caixa'] is List) {
        _aberturasCaixa.clear();
        for (final item in colecoes['aberturas_caixa'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _aberturasCaixa.add(AberturaCaixa.fromMap(map));
        }
      }
      if (colecoes['fechamentos_caixa'] is List) {
        _fechamentosCaixa.clear();
        for (final item in colecoes['fechamentos_caixa'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _fechamentosCaixa.add(FechamentoCaixa.fromMap(map));
        }
      }
      if (colecoes['sangrias'] is List) {
        _sangrias.clear();
        for (final item in colecoes['sangrias'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _sangrias.add(SangriaCaixa.fromMap(map));
        }
      }
      if (colecoes['suprimentos'] is List) {
        _suprimentos.clear();
        for (final item in colecoes['suprimentos'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _suprimentos.add(SuprimentoCaixa.fromMap(map));
        }
      }
      if (colecoes['estoque_historico'] is List) {
        _estoqueHistorico.clear();
        for (final item in colecoes['estoque_historico'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _estoqueHistorico.add(EstoqueHistorico.fromMap(map));
        }
      }
      if (colecoes['ajustes_estoque_lote'] is List) {
        _ajustesEstoqueLote.clear();
        for (final item in colecoes['ajustes_estoque_lote'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _ajustesEstoqueLote.add(AjusteEstoqueLote.fromMap(map));
        }
      }
      if (colecoes['lotes_produto'] is List) {
        _lotesProdutos.clear();
        for (final item in colecoes['lotes_produto'] as List) {
          final map = Map<String, dynamic>.from(item as Map);
          if (!_registroDaEmpresaAberta(map)) continue;
          _lotesProdutos.add(LoteProduto.fromMap(map));
        }
      }

      // Persistir no PostgreSQL. `forcarTodos` é OBRIGATÓRIO aqui: `_salvarTodosDados`
      // só grava coleções sujas, e o restore não passa por `_marcarSujo` — sem
      // forçar, o backup era "restaurado" na tela e NUNCA chegava ao banco local
      // (sumia no próximo boot).
      await _salvarTodosDados(
        aguardarSupabase: false,
        forcarTodos: true,
        isSync: true,
      );

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
    _servicosRealizados.clear();
    _orcamentos.clear();
    _ordensServico.clear();
    _entregas.clear();
    _motoristas.clear();
    _vendasBalcao.clear();
    _trocasDevolucoes.clear();
    _estoqueHistorico.clear();
    _ajustesEstoqueLote.clear();
    _lotesProdutos.clear();
    _notasEntrada.clear();
    _pedidosCompra.clear();
    _agendamentosServico.clear();
    _funcionarios.clear();
    _taxasEntrega.clear();
    _contasPagar.clear();
    _aberturasCaixa.clear();
    _fechamentosCaixa.clear();
    _sangrias.clear();
    _suprimentos.clear();
    _nfces.clear();
    _nfes.clear();
    _mesasComandas.clear();
    _linksVendedores.clear();
    _comissoesVendedores.clear();
    _romaneios.clear();
    _perfisTributarios.clear();
    _departamentos.clear();
    _estoques.clear();
  }

  // Controle de caixa
  bool _caixaAberto = false; // Espelho de `caixaAberto` (ver comentário abaixo)

  /// O caixa está aberto?
  ///
  /// O status é SEMPRE DERIVADO das listas — uma abertura sem fechamento é um
  /// caixa aberto. Nunca de um flag guardado: quando o FECHAMENTO chega do
  /// outro PC pela rede local, `_carregarCaixaLocal` recarrega as listas mas o
  /// flag continuava "aberto" de antes, e o PDV seguia liberando venda num
  /// caixa que a outra máquina já tinha fechado.
  bool get caixaAberto {
    // Com responsável ativo, o caixa é o DESSE usuário (cada usuário da
    // empresa pode ter o seu). Sem responsável, vale a abertura em aberto mais
    // recente. Os dois casos saem de `aberturaCaixaAtual`, que já aplica essa
    // regra — inclusive o fallback para caixa herdado sem responsável.
    final aberto = aberturaCaixaAtual != null;
    _caixaAberto = aberto;
    return aberto;
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

  /// Esta abertura já foi fechada (a sessão terminou)?
  bool _temFechamento(AberturaCaixa abertura) =>
      _fechamentosCaixa.any((f) => f.aberturaCaixaId == abertura.id);

  /// A abertura MAIS RECENTE de um conjunto (por `dataAbertura`).
  ///
  /// Não confia na ordem da lista: `_aberturasCaixa` chega ordenada do banco,
  /// mas recebe acréscimos em memória quando o operador abre um caixa.
  AberturaCaixa? _aberturaMaisRecente(Iterable<AberturaCaixa> candidatas) {
    AberturaCaixa? mais;
    for (final ab in candidatas) {
      if (mais == null || ab.dataAbertura.isAfter(mais.dataAbertura)) {
        mais = ab;
      }
    }
    return mais;
  }

  /// SESSÃO de caixa aberta de um responsável (email ou nome), se houver.
  ///
  /// É a abertura MAIS RECENTE desse operador — e só conta se ela ainda não tem
  /// fechamento. Aberturas antigas que ficaram sem fechamento (tentativa
  /// abortada, caixa fechado sem registrar) são lixo de histórico: contá-las
  /// como "abertas" fazia um caixa JÁ FECHADO voltar a parecer aberto, e o PDV
  /// liberava venda — era assim que o caixa fechado na outra máquina continuava
  /// aceitando venda aqui.
  AberturaCaixa? aberturaCaixaDoResponsavel(String? responsavel) {
    if (responsavel == null || responsavel.isEmpty) return null;
    // Comparação tolerante: email vs nome (ex: 'carlos@gmail.com' bate com
    // 'Carlos'). ANTES era comparação exata de string, o que fazia o operador
    // não encontrar o PRÓPRIO caixa e o app "herdar" o caixa de outro usuário.
    final sessao = _aberturaMaisRecente(
      _aberturasCaixa.where(
        (ab) => _ehMesmoOperador(ab.responsavel, responsavel),
      ),
    );
    if (sessao == null || _temFechamento(sessao)) return null;
    return sessao;
  }

  /// Última abertura de caixa do operador (aberta OU fechada) — usada pelo
  /// filtro "Apenas Meu Caixa" do histórico. É a SESSÃO mais recente DELE;
  /// nunca cai no caixa de outro usuário. Antes procurava "a primeira abertura
  /// sem fechamento do operador", e uma abertura órfã antiga tomava o lugar do
  /// caixa que ele realmente usou por último (as vendas sumiam do filtro).
  AberturaCaixa? ultimaAberturaDoOperador(String? operador) {
    if (operador == null || operador.trim().isEmpty) return null;
    return _aberturaMaisRecente(
      _aberturasCaixa.where((ab) => _ehMesmoOperador(ab.responsavel, operador)),
    );
  }

  /// Uma venda pertence ao caixa do operador? Venda SEM operador (legada) e
  /// caixa sem responsável sempre pertencem; quando ambos existem, exige
  /// correspondência tolerante (email vs nome).
  bool vendaPertenceAoOperador(
    String? operadorVenda,
    String? responsavelCaixa,
  ) {
    if (operadorVenda == null || operadorVenda.trim().isEmpty) return true;
    if (responsavelCaixa == null || responsavelCaixa.trim().isEmpty)
      return true;
    return _ehMesmoOperador(operadorVenda, responsavelCaixa);
  }

  List<NotaEntrada> get notasEntrada => _notasEntrada;
  List<PedidoCompra> get pedidosCompra => _pedidosCompra;
  List<NFCe> get nfces => _nfces;
  List<NFCe> get nfes => _nfes;
  List<VendaBalcao> get vendasBalcao => _vendasBalcao;
  List<CashBackMovimento> get movimentosCashBack => _movimentosCashBack;
  List<Pedido> get pedidos => _pedidos;
  List<ServicoRealizado> get servicosRealizados => _servicosRealizados;
  List<Orcamento> get orcamentos => _orcamentos;
  List<TrocaDevolucao> get trocasDevolucoes => _trocasDevolucoes;

  /// Devolucoes corrompidas por sincronizacao (stubs sem venda vinculada,
  /// sem valor e sem itens - geradas pelo bug antigo do DateTime.now() no
  /// TrocaDevolucao.fromMap) sao lixo e devem ser ignoradas em todo lugar.
  bool _isTrocaDevolucaoValida(TrocaDevolucao t) {
    final temVenda = t.numeroPedido.isNotEmpty || t.pedidoId.isNotEmpty;
    if (temVenda) return true;
    return !(t.valorDevolvido <= 0 &&
        t.itensDevolvidos.isEmpty &&
        (t.itensNovos == null || t.itensNovos!.isEmpty));
  }

  /// Retorna as trocas e devoluções em um período específico
  List<TrocaDevolucao> getTrocasDevolucoesPorPeriodo(
    DateTime inicio,
    DateTime fim,
  ) {
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
    final temResponsavelAtivo =
        _responsavelAtivo != null && _responsavelAtivo!.isNotEmpty;

    if (temResponsavelAtivo) {
      final doResponsavel = aberturaCaixaDoResponsavel(_responsavelAtivo);
      if (doResponsavel != null) return doResponsavel;
      // Responsável ativo sem caixa próprio: NÃO herdar caixa de outro usuário.
      // Só permite herança quando o caixa herdado também não tem responsável
      // (caixa herdado/antigo aberto antes da definição de responsável).
      final herdada = _aberturaMaisRecente(
        _aberturasCaixa.where((a) => (a.responsavel ?? '').trim().isEmpty),
      );
      if (herdada != null && !_temFechamento(herdada)) return herdada;
      return null;
    }

    // Sem responsável definido: vale a SESSÃO mais recente (a abertura mais
    // nova). Se ela já foi FECHADA, o caixa está fechado — mesmo que exista
    // alguma abertura antiga sem fechamento. Era essa abertura órfã que mantinha
    // o caixa "aberto" para sempre, liberando venda depois de fechar.
    final sessao = _aberturaMaisRecente(_aberturasCaixa);
    if (sessao != null && !_temFechamento(sessao)) return sessao;
    return null;
  }

  // Serviço de persistência
  final LocalStorageService _storage = LocalStorageService();
  LocalStorageService get storage => _storage;
  final SupabaseService _supabaseService = SupabaseService.instance;
  final SyncQueueService _syncQueue = SyncQueueService(initiallyPaused: true);
  final RealtimeSyncService _realtimeSync = RealtimeSyncService.instance;

  // ── Rede local em tempo real (LAN) ─────────────────────────────────────
  // Escuta o canal `exodo_ui_event` que o sincronizador da LAN emite quando
  // traz dados do outro PC. É o que faz a tela atualizar na hora, sem depender
  // da nuvem (funciona justamente quando a nuvem está fora).
  final LanRealtimeService _lanRealtime = LanRealtimeService.instance;
  Timer? _lanRefreshTimer;
  bool _recarregandoPelaRedeLocal = false;

  /// Um lote do sincronizador da LAN chegou no banco local: recarrega as telas.
  ///
  /// Passa por um debounce curto porque uma puxada do par vem em várias
  /// tabelas/linhas quase juntas — sem o debounce, seriam dezenas de recargas.
  void _aoMudarPelaRedeLocal(String tabela) {
    if (_descartado || _currentEmpresaId == null) return;
    _lanRefreshTimer?.cancel();
    _lanRefreshTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_recarregarPelaRedeLocal());
    });
  }

  // ── Nuvem em tempo real (Neon Realtime) ────────────────────────────────
  // A nuvem avisa QUE tabela mudou; aqui só antecipamos a sincronização que
  // já rodaria no timer de 45 s. No Windows o banco local continua sendo o
  // principal: o aviso faz a PUXADA (delta) chegar agora, e o resto do ciclo
  // (inclusive o envio da fila) segue igual.
  Timer? _nuvemRefreshTimer;
  bool _recarregandoPelaNuvem = false;

  /// Tabelas avisadas pela nuvem e ainda não puxadas.
  ///
  /// Antes, cada aviso disparava o ciclo COMPLETO (as 30 tabelas do
  /// `carregarTudoDoSupabase`). No celular, com rede móvel, essa varredura
  /// levava dezenas de segundos — o produto alterado no PC só aparecia muito
  /// depois, mesmo com o push chegando em ~1 s. Agora só a(s) tabela(s)
  /// avisada(s) é(são) baixada(s).
  final Set<String> _tabelasAvisadasPelaNuvem = <String>{};

  void _aoMudarPelaNuvem(String tabela) {
    if (_descartado || _currentEmpresaId == null || _isOffline) return;
    debugPrint('>>> [Neon-Realtime] 🔔 A nuvem avisou mudança em $tabela.');
    _tabelasAvisadasPelaNuvem.add(tabela);
    _nuvemRefreshTimer?.cancel();
    _nuvemRefreshTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_recarregarPelaNuvem());
    });
  }

  /// Puxa o delta da nuvem logo depois do aviso (com trava de reentrância:
  /// várias tabelas mudam quase juntas e não faz sentido disparar N ciclos).
  Future<void> _recarregarPelaNuvem() async {
    if (_recarregandoPelaNuvem || _descartado || _currentEmpresaId == null) {
      return;
    }
    // Ciclo completo em andamento: a puxada pontual seria descartada por
    // `_carregarDadosDoSupabase`. Mantém os avisos guardados e tenta de novo.
    if (_syncEmAndamento) {
      _nuvemRefreshTimer?.cancel();
      _nuvemRefreshTimer = Timer(const Duration(seconds: 1), () {
        unawaited(_recarregarPelaNuvem());
      });
      return;
    }
    _recarregandoPelaNuvem = true;
    // Só as tabelas que a nuvem avisou (uma consulta por tabela, em vez do
    // ciclo completo). O conjunto é limpo aqui e reabastecido se um aviso
    // chegar durante a puxada.
    final tabelas = Set<String>.from(_tabelasAvisadasPelaNuvem);
    if (tabelas.isEmpty) {
      _recarregandoPelaNuvem = false;
      return;
    }
    _tabelasAvisadasPelaNuvem.clear();
    try {
      await _sincronizarSilenciosamente(tabelas: tabelas);
    } catch (e) {
      debugPrint('>>> [Neon-Realtime] ⚠️ Falha na puxada após aviso: $e');
    } finally {
      _recarregandoPelaNuvem = false;
      if (_tabelasAvisadasPelaNuvem.isNotEmpty && !_descartado) {
        _nuvemRefreshTimer?.cancel();
        _nuvemRefreshTimer = Timer(const Duration(milliseconds: 200), () {
          unawaited(_recarregarPelaNuvem());
        });
      }
    }
  }

  Future<void> _recarregarPelaRedeLocal() async {
    if (_recarregandoPelaRedeLocal ||
        _descartado ||
        _currentEmpresaId == null) {
      return;
    }
    _recarregandoPelaRedeLocal = true;
    try {
      await _carregarDadosSalvos();
      notifyListeners();
      debugPrint(
        '>>> [LAN-Realtime] 🔄 Tela atualizada com dados recebidos pela rede local.',
      );
    } catch (e) {
      debugPrint('>>> [LAN-Realtime] ⚠️ Erro ao recarregar do banco local: $e');
    } finally {
      _recarregandoPelaRedeLocal = false;
    }
  }

  bool _syncEmAndamento = false;

  /// --------------------------------------------------------------------
  /// Trace flags: marca, em memória apenas, que um pedido/venda já foi
  /// enviado com sucesso para a nuvem NESTA sessão. Usado pelo
  /// _notificarEnvioPedidosEVendas() para evitar duplo-envio na mesma
  /// transação e para rastreamento de diagnóstico.
  /// --------------------------------------------------------------------
  final Set<String> _pedidosEnviadosEstaSessao = {};
  final Set<String> _vendasBalcaoEnviadasEstaSessao = {};

  /// Helper para realizar upsert no Supabase com empresa_id automático
  /// [empresaId] permite gravar em nome da empresa da OPERAÇÃO, e não da empresa
  /// aberta agora. Isso é essencial na fila de sincronização (persistida entre
  /// sessões): sem ele, um item pendente da Empresa A podia ser drenado depois de
  /// você trocar para a Empresa B e ia para a nuvem como sendo de B.
  Future<void> _upsertNoSupabase(
    String table,
    Map<String, dynamic> data, {
    String? empresaId,
  }) async {
    // Ordem de prioridade: (1) a empresa da operação; (2) a que já vem no
    // registro; (3) a empresa aberta agora.
    final empresaDoRegistro = data['empresa_id']?.toString();
    final empresaEfetiva = (empresaId != null && empresaId.isNotEmpty)
        ? empresaId
        : ((empresaDoRegistro != null && empresaDoRegistro.isNotEmpty)
              ? empresaDoRegistro
              : _currentEmpresaId);

    if (empresaEfetiva == null || empresaEfetiva.isEmpty) {
      debugPrint(
        '>>> [Supabase] ⏭️ Pulando upsert em $table: Empresa não definida',
      );
      return;
    }

    if (empresaEfetiva != _currentEmpresaId || !nuvemHabilitada) {
      debugPrint(
        '>>> [Supabase] ⏸️ Operação $table/${data['id']} mantida na fila da empresa $empresaEfetiva.',
      );
      _adicionarSincronizacaoPendente(
        table: table,
        data: data,
        empresaId: empresaEfetiva,
      );
      return;
    }

    if (!SupabaseService.isAvailable) {
      debugPrint(
        '>>> [Supabase] ⏭️ Pulando upsert em $table: Supabase não disponível',
      );
      return;
    }

    try {
      final map = Map<String, dynamic>.from(data);
      // empresa_id definido (e nunca sobrescrito pela empresa errada)
      map['empresa_id'] = empresaEfetiva;

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
      } else if (table == SupabaseService.tableProdutos) {
        // Colunas que existem no banco local mas NÃO existem no Supabase
        map.remove('baixar_estoque_proprio');
        map.remove('eh_composto');
        map.remove('composicao');
        map.remove('cobrar_garcom');
        // `codigos_barras_adicionais` foi adicionada só no banco LOCAL. Enviá-la
        // fazia o PostgREST recusar o produto INTEIRO com PGRST204 ("Could not
        // find the 'codigos_barras_adicionais' column") — por isso a edição
        // feita no site não chegava à nuvem nem ao app. O filtro dinâmico de
        // colunas também remove, mas aqui garantimos mesmo se ele falhar.
        map.remove('codigos_barras_adicionais');
        map.remove('codigosBarrasAdicionais');
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
        if (map.containsKey('data_abertura'))
          map['dataAbertura'] = map.remove('data_abertura');
        if (map.containsKey('valor_inicial'))
          map['valorInicial'] = map.remove('valor_inicial');
        if (map.containsKey('created_at'))
          map['createdAt'] = map.remove('created_at');
        if (map.containsKey('updated_at'))
          map['updatedAt'] = map.remove('updated_at');
      } else if (table == 'fechamentos_caixa') {
        // ⚠️ NÃO remover as chaves snake ao mapear para camel: a nuvem tem AMBAS
        // as colunas e o sincronizador local as usa no download. Antes, remover
        // abertura_caixa_id fazia a nuvem guardar só a camel; no download o
        // sincronizador convertia o ID (13 dígitos) em timestamp (coluna local
        // de tipo errado) e o vínculo fechamento→abertura se perdia — o caixa
        // ficava "sempre aberto". Enviar snake E camel mantém o dado íntegro.
        if (map.containsKey('abertura_caixa_id'))
          map['aberturaCaixaId'] = map['abertura_caixa_id'];
        if (map.containsKey('data_fechamento'))
          map['dataFechamento'] = map['data_fechamento'];
        // A nuvem só tem a versão camel dos valores numéricos — renomear.
        if (map.containsKey('valor_esperado'))
          map['valorEsperado'] = map.remove('valor_esperado');
        if (map.containsKey('valor_real'))
          map['valorReal'] = map.remove('valor_real');
        if (map.containsKey('created_at')) map['createdAt'] = map['created_at'];
        if (map.containsKey('updated_at')) map['updatedAt'] = map['updated_at'];
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

      // REGRA "LOCAL PRIMEIRO": nada sobe para a nuvem antes de estar gravado
      // no PostgreSQL local. Se o local falhar, o envio simplesmente não
      // acontece agora (a mutação fica suja/na fila e tenta de novo) — a nuvem
      // nunca fica à frente do banco local.
      await _garantirGravacaoLocalPendente();

      debugPrint('>>> [Supabase] 📤 Enviando para $table...');
      debugPrint('>>> [Supabase]    ID: ${map['id']}');
      debugPrint('>>> [Supabase]    Empresa: $currentEmpresaId');

      await _supabaseService.upsert(table, map);
      debugPrint('>>> [Supabase] ✅ Upsert OK em $table: ${map['id']}');

      // Sincronizar status no SyncMonitor
      if (_currentEmpresaId != null &&
          table != 'sync_logs' &&
          table != 'sync_status') {
        SyncMonitorService.instance
            .atualizarStatusSucesso(
              empresaId: _currentEmpresaId!,
              filaPendente: _dirtyCollections.length,
            )
            .catchError((_) {});
      }

      // Auto-reconexão ativa: se a gravação funcionou, com certeza estamos online
      if (_isOffline) {
        _isOffline = false;
        _consecutiveConnectionFailures = 0;
        notifyListeners();
        addSyncLog("🌐 Conexão reestabelecida (operação real concluída)");
        ConnectionLoggerService.log(
          "🌐 Conexão reestabelecida (operação real concluída)",
        );
      }
    } catch (e) {
      final errorStr = e.toString();
      debugPrint('>>> [Supabase] ❌ Erro no upsert em $table: $e');

      // PROTEÇÃO CONTRA LOOP INFINITO: Se o erro for de coluna inexistente ou RLS, NÃO adicionar na fila
      // porque ele vai falhar para sempre e travar o app em um loop de retry.
      bool isIrrecuperavel =
          errorStr.contains('PGRST204') ||
          errorStr.contains(
            'PGRST205',
          ) || // tabela não existe na nuvem (ex.: lotes_produto antes de rodar o SQL)
          errorStr.contains('42501') ||
          errorStr.contains('column') ||
          errorStr.contains('violates row-level security');

      if (!isIrrecuperavel) {
        _adicionarSincronizacaoPendente(table: table, data: data);
      } else {
        debugPrint(
          '>>> [Supabase] ⚠️ Erro crítico/esquema detectado em $table. Operação descartada para evitar loop.',
        );
      }
    }
  }

  /// Helper para realizar delete no Supabase
  ///
  /// [enfileirarSeOffline] fica `false` quando a chamada vem da PRÓPRIA fila
  /// (senão a exclusão se re-enfileirava a cada tentativa e a fila entrava em
  /// vaivém). Fora da fila, a exclusão feita sem internet precisa ser guardada:
  /// antes ela simplesmente sumia daqui, o registro continuava na nuvem e
  /// voltava para esta máquina no próximo download.
  Future<void> _deleteNoSupabase(
    String table,
    String id, {
    bool enfileirarSeOffline = true,
  }) async {
    if (!nuvemHabilitada) {
      debugPrint(
        '>>> [Supabase] ⏸️ Nuvem desativada; mantendo DELETE $table/$id na fila local.',
      );
      _adicionarSincronizacaoPendente(
        table: table,
        data: {'id': id},
        type: 'DELETE',
      );
      return;
    }

    if (!SupabaseService.isAvailable || _currentEmpresaId == null) {
      if (enfileirarSeOffline) {
        debugPrint(
          '>>> [Sync] ⏭️ Exclusão de $table/$id feita offline: guardada na fila.',
        );
        _adicionarSincronizacaoPendente(
          table: table,
          data: {'id': id},
          type: 'DELETE',
        );
      }
      return;
    }
    try {
      // REGRA "LOCAL PRIMEIRO": a exclusão já existe no banco local antes de
      // pedir a mesma exclusão na nuvem (mesma garantia do upsert).
      await _garantirGravacaoLocalPendente();
      await _supabaseService.delete(table, id);

      // Auto-reconexão ativa: se a deleção funcionou, com certeza estamos online
      if (_isOffline) {
        _isOffline = false;
        _consecutiveConnectionFailures = 0;
        notifyListeners();
        addSyncLog("🌐 Conexão reestabelecida (operação real concluída)");
        ConnectionLoggerService.log(
          "🌐 Conexão reestabelecida (operação real concluída)",
        );
      }
    } catch (e) {
      debugPrint('>>> [Supabase] ❌ Erro ao deletar de $table: $e');
      if (enfileirarSeOffline) {
        _adicionarSincronizacaoPendente(
          table: table,
          data: {'id': id},
          type: 'DELETE',
        );
      }
    }
  }

  /// ======================================================
  /// SINCRONIZAÇÃO BIDIRECIONAL: Envia mudanças locais para Supabase
  /// ======================================================
  Future<void> enviarMudancaParaSupabase(
    String tabela,
    Map<String, dynamic> dados, {
    String? evento = 'UPSERT',
  }) async {
    // Marca o registro como "alteração local em curso": enquanto o envio não se
    // confirma, o valor da nuvem para ele é mais antigo e não pode sobrescrever
    // o local (fecha a janela entre gravar aqui e o upsert terminar lá).
    final id = dados['id']?.toString();
    if (id != null && id.isNotEmpty && evento != 'DELETE') {
      _enviosLocaisEmCurso[id] = DateTime.now();
    }
    // Túmulo em memória: registra a deleção para que um upsert atrasado vindo
    // de outro PC (ou um pull mais antigo) não traga o registro de volta.
    if (id != null && id.isNotEmpty && evento == 'DELETE') {
      _marcarRemovidoRecentemente(id);
    }
    // Retorna imediatamente e delega a chamada de rede ao event loop (em background).
    // Isso evita travamentos ou esperas na UI/finalização de vendas locais.
    _processarEnvioSupabaseBackground(tabela, dados, evento);
  }

  Future<void> _processarEnvioSupabaseBackground(
    String tabela,
    Map<String, dynamic> dados,
    String? evento,
  ) async {
    final id = dados['id']?.toString();
    if (!nuvemHabilitada) {
      if (id != null) _enviosLocaisEmCurso.remove(id);
      _adicionarSincronizacaoPendente(table: tabela, data: dados, type: evento);
      return;
    }

    if (!SupabaseService.isAvailable) {
      debugPrint(
        '>>> [Sync] ⏭️ Supabase não disponível. Adicionando à fila de sync (bg).',
      );
      if (id != null) _enviosLocaisEmCurso.remove(id);
      _adicionarSincronizacaoPendente(table: tabela, data: dados, type: evento);
      return;
    }

    if (_currentEmpresaId == null) {
      debugPrint(
        '>>> [Sync] ⏭️ Empresa não definida. Adicionando à fila de sync (bg).',
      );
      if (id != null) _enviosLocaisEmCurso.remove(id);
      _adicionarSincronizacaoPendente(table: tabela, data: dados, type: evento);
      return;
    }

    try {
      if (evento == 'DELETE') {
        await _deleteNoSupabase(tabela, dados['id'] as String);
      } else {
        await _upsertNoSupabase(tabela, dados);
      }
      // Confirmação: a nuvem agora tem esta versão — a janela de proteção fecha
      // e o registro volta a aceitar snapshots/eventos da nuvem normalmente.
      if (id != null) _enviosLocaisEmCurso.remove(id);
      debugPrint(
        '>>> [Sync] ✅ Mudança enviada para Supabase em background: $tabela (${dados['id']})',
      );
    } catch (e) {
      debugPrint(
        '>>> [Sync] ❌ Erro ao enviar mudança para Supabase em background: $e',
      );
      if (id != null) _enviosLocaisEmCurso.remove(id);
      _adicionarSincronizacaoPendente(table: tabela, data: dados, type: evento);
    }
  }

  /// ======================================================
  /// GARANTIA DE ENVIO + CONFIRMAÇÃO (pedido / venda balcão)
  /// ======================================================
  /// Após criar/atualizar um pedido ou venda de balcão, garante que o registro
  /// chegou à nuvem (Supabase) e que o Realtime já transmitiu a mudança para
  /// os outros PCs. Reduz a janela em que uma venda feita no PC-A ainda não
  /// aparece no PC-B.
  ///
  /// Fluxo (AGORA EM SEGUNDO PLANO):
  ///   1. Upsert no Supabase, sem await (o chamador já gravou local na hora);
  ///   2. Marca o id como enviado nesta sessão (diagnóstico);
  ///   3. Espera a confirmação Realtime (o próprio broadcast volta para esta
  ///      máquina, confirmando que a escrita foi persistida e divulgada).
  ///
  /// Retorna imediatamente: é o que mantém a finalização de venda rápida no
  /// modelo híbrido — o LOCAL é o motor e a NUVEM acompanha em background, sem
  /// segurar a UI esperando upsert/rede.
  Future<void> garantirEnvioEConfirmacao({
    required String tabela,
    required Map<String, dynamic> dados,
  }) async {
    unawaited(
      _garantirEnvioEConfirmacaoBackground(tabela: tabela, dados: dados),
    );
  }

  Future<void> _garantirEnvioEConfirmacaoBackground({
    required String tabela,
    required Map<String, dynamic> dados,
  }) async {
    final id = dados['id'] as String?;

    if (!nuvemHabilitada) {
      _adicionarSincronizacaoPendente(table: tabela, data: dados);
      return;
    }

    // 1) Upsert aguardado (idempotente — o background continua como fallback)
    try {
      await _upsertNoSupabase(tabela, dados);
    } catch (e) {
      debugPrint(
        '>>> [Sync] ⚠️ garantirEnvioEConfirmacao: falha no upsert $tabela/$id: $e',
      );
      return;
    }

    // 2) Marca como enviado nesta sessão
    if (id != null) {
      if (tabela == SupabaseService.tablePedidos) {
        _pedidosEnviadosEstaSessao.add(id);
      } else if (tabela == SupabaseService.tableVendasBalcao) {
        _vendasBalcaoEnviadasEstaSessao.add(id);
      }
    }

    // 3) Confirmação Realtime (apenas se o canal estiver ativo)
    if (id != null && SupabaseService.isAvailable && _realtimeSync.ativo) {
      final confirmou = await _realtimeSync.aguardarConfirmacao(
        tabela,
        id,
        timeout: const Duration(seconds: 2),
      );
      debugPrint(
        confirmou
            ? '>>> [Sync] ✅ Realtime confirmou $tabela/$id (na nuvem e divulgado aos PCs)'
            : '>>> [Sync] ⏳ Realtime sem confirmação para $tabela/$id (segue no sync normal)',
      );
    } else {
      debugPrint(
        '>>> [Sync] ⏭️ Confirmação Realtime pulada para $tabela/$id (offline ou canal inativo)',
      );
    }
  }

  /// ======================================================
  /// REALTIME SYNC: Processa eventos recebidos via WebSocket
  /// ======================================================
  /// Chamado pelo RealtimeSyncService quando Supabase emite um evento.
  /// Atualiza a lista em memória correta e notifica a UI instantaneamente.
  void _aplicarMudancaRealtime(
    String tabela,
    String evento,
    Map<String, dynamic> dados,
  ) {
    if (!nuvemHabilitada) {
      debugPrint(
        '>>> [Realtime] ⏸️ Evento $evento em $tabela ignorado: nuvem desativada para a empresa.',
      );
      return;
    }

    try {
      final id = dados['id'] as String?;

      // TRAVA DE EMPRESA: o canal Realtime é assinado com filtro por
      // `empresa_id`, mas o evento de DELETE não leva filtro e uma assinatura
      // pode chegar com payload de outra empresa. Este é o ponto em que o dado
      // ENTRA nas listas em memória (é delas que o Fluxo de Caixa lê), então
      // descartar o que não é da empresa aberta é o que impede QUALQUER tela de
      // mostrar dados de outra empresa.
      final empresaDoEvento = (dados['empresa_id'] ?? dados['empresaId'])
          ?.toString();
      if (empresaDoEvento != null &&
          empresaDoEvento.isNotEmpty &&
          empresaDoEvento != _currentEmpresaId) {
        debugPrint(
          '>>> [Realtime] 🛡️ $evento em $tabela (id: $id) ignorado: '
          'pertence à empresa $empresaDoEvento, não a $_currentEmpresaId.',
        );
        return;
      }

      // Trava ANTI-PERDA DE ALTERAÇÃO LOCAL: se este registro tem uma mudança
      // local que ainda não subiu, o evento da nuvem é mais ANTIGO para ele e
      // não pode sobrescrevê-lo (era assim que uma baixa de estoque feita aqui
      // sumia quando o outro PC publicava o valor dele). O DELETE continua sendo
      // aplicado normalmente (deleção é sempre intencional e autoritativa).
      if (id != null &&
          evento != 'DELETE' &&
          _temEnvioLocalPendente(tabela, id)) {
        debugPrint(
          '>>> [Realtime] 🛡️ $evento em $tabela (id: $id) ignorado: há '
          'alteração local ainda não enviada.',
        );
        return;
      }

      // Trava ANTI-RESSURREIÇÃO: se este id foi apagado aqui há pouco, um
      // INSERT/UPDATE (de outro PC que ainda não sabia da deleção) NÃO pode
      // trazê-lo de volta. Reenviamos o DELETE à nuvem para convergir.
      if (id != null && evento != 'DELETE' && _foiRemovidoRecentemente(id)) {
        debugPrint(
          '>>> [Realtime] 🪦 $evento em $tabela (id: $id) ignorado: registro '
          'apagado localmente. Reenviando DELETE à nuvem.',
        );
        enviarMudancaParaSupabase(tabela, {'id': id}, evento: 'DELETE');
        return;
      }

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

        case 'pedidos_compra':
          _aplicarEmLista<PedidoCompra>(
            _pedidosCompra,
            evento,
            dados,
            PedidoCompra.fromMap,
          );
          break;

        case 'vendas_balcao':
          _aplicarEmLista<VendaBalcao>(
            _vendasBalcao,
            evento,
            dados,
            VendaBalcao.fromMap,
          );
          break;

        case 'mesas_comandas':
          if (id != null &&
              _idsMesaRemovidosRecentemente.contains(id) &&
              evento != 'DELETE') {
            debugPrint(
              '>>> [Realtime] ⚠️ Mesa $id ignorada (remoção recente protegida)',
            );
            break;
          }
          _aplicarEmLista<MesaComanda>(
            _mesasComandas,
            evento,
            dados,
            MesaComanda.fromMap,
          );
          break;

        case 'cash_back_movimentos':
          _aplicarEmLista<CashBackMovimento>(
            _movimentosCashBack,
            evento,
            dados,
            CashBackMovimento.fromMap,
          );
          break;

        case 'agendamentos_servico':
          // ⚠️ Ignorar eventos REALTIME de agendamentos criados localmente há <5s.
          // O REALTIME dispara INSERT de volta ao mesmo PC.
          if (id != null && _agendamentosCriadosLocalmente.containsKey(id)) {
            final criadoEm = _agendamentosCriadosLocalmente[id]!;
            if (DateTime.now().difference(criadoEm).inSeconds < 5) {
              debugPrint(
                '>>> [Realtime] ⏭️ Agendamento $id ignorado (criado localmente há ${DateTime.now().difference(criadoEm).inSeconds}s)',
              );
              break;
            }
            _agendamentosCriadosLocalmente.remove(id);
          }
          _aplicarEmLista<AgendamentoServico>(
            _agendamentosServico,
            evento,
            dados,
            AgendamentoServico.fromMap,
          );
          // Som de notificação para novos agendamentos recebidos de outro PC
          if (evento == 'INSERT') {
            _tocarSomNotificacao();
          }
          break;

        case 'contas_pagar':
          _aplicarEmLista<ContaPagar>(
            _contasPagar,
            evento,
            dados,
            ContaPagar.fromMap,
          );
          break;

        case 'aberturas_caixa':
          _aplicarEmLista<AberturaCaixa>(
            _aberturasCaixa,
            evento,
            dados,
            AberturaCaixa.fromMap,
          );
          _caixaAberto = aberturaCaixaAtual != null;
          break;

        case 'fechamentos_caixa':
          _aplicarEmLista<FechamentoCaixa>(
            _fechamentosCaixa,
            evento,
            dados,
            FechamentoCaixa.fromMap,
          );
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
          _aplicarEmLista<Romaneio>(
            _romaneios,
            evento,
            dados,
            Romaneio.fromMap,
          );
          break;
      }

      // Notifica a UI para reconstruir apenas o que mudou
      notifyListeners();
    } catch (e) {
      debugPrint(
        '>>> [Realtime] ❌ Erro ao aplicar mudança Realtime em $tabela: $e',
      );
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

    // ⚠️ SEGURANÇA: Parsear NOVO item ANTES de remover o antigo.
    // Se o parse falhar, o item original permanece intacto na lista.
    if (evento == 'DELETE') {
      // DELETE: remover diretamente
      lista.removeWhere((item) => (item as dynamic).id == id);
    } else {
      // INSERT/UPDATE: parsear primeiro, depois swap seguro
      T? novoItem;
      try {
        novoItem = fromMap(dados);
      } catch (e) {
        debugPrint(
          '>>> [Realtime] ⚠️ Erro ao parsear item de ${T.toString()}: $e',
        );
        debugPrint('>>> [Realtime] Dados recebidos: $dados');
        return; // NÃO remove o item existente!
      }

      if (novoItem != null) {
        // REGRA "A NUVEM NUNCA SOBRESCREVE O LOCAL": o evento que chega pelo
        // Realtime só substitui a versão local quando é mais NOVO. Empate ou
        // local mais novo → o local fica (sem isso, uma edição feita aqui era
        // revertida pelo snapshot antigo que voltava pelo canal da nuvem).
        final indexLocal = lista.indexWhere(
          (item) => (item as dynamic).id == id,
        );
        if (indexLocal >= 0 &&
            !_nuvemMaisNovaQueLocal(lista[indexLocal], novoItem)) {
          debugPrint(
            '>>> [Realtime] 🛡️ Evento da nuvem ignorado (local é igual ou mais novo): $id',
          );
          return;
        }
        // Agora é seguro remover e adicionar
        lista.removeWhere((item) => (item as dynamic).id == id);
        lista.add(novoItem);
      }
    }
  }

  bool _persistenciaHabilitada =
      true; // Flag para habilitar/desabilitar persistência

  // ID único para debug
  final String _instanceId = DateTime.now().millisecondsSinceEpoch.toString();
  Timer? _syncTimer;
  Timer? _checkConnectivityTimer;
  int _currentSyncInterval = 10;
  DateTime _lastSyncActivityTime = DateTime.now();
  StreamSubscription? _windowFocusSubscription;
  StreamSubscription? _windowVisibleSubscription;

  // Status de Sincronização
  DateTime? _ultimaSincronizacaoSucesso;
  String? _ultimoErroSync;
  int _conflitosCount = 0;

  /// Ligado sempre que uma coleção muda de verdade (ver [_marcarSujo]).
  /// Zerado no início de cada carga da nuvem e lido no fim: se continuar
  /// desligado, o pulso silencioso não mudou nada e não precisa notificar a UI
  /// (era o que fazia a árvore inteira sob `Consumer<DataService>` se
  /// reconstruir a cada ~10s sem nenhuma novidade).
  bool _mudouNestaCarga = false;
  bool _isModoLeve = false;
  bool _isOffline = false;
  bool get isOffline => _isOffline;
  int _consecutiveConnectionFailures = 0;
  final List<String> _syncLogs = [];

  /// True depois do `dispose()`. O `ChangeNotifier` estoura (em debug) se
  /// alguém chamar `notifyListeners()` depois disso — e no app isso acontece de
  /// verdade: migração de cache, persistência e sincronização terminam DEPOIS
  /// que a tela saiu. Depois de descartado não existe mais tela para avisar,
  /// então a notificação é simplesmente ignorada (era uma das fontes de erro
  /// "A DataService was used after being disposed").
  bool _descartado = false;

  @override
  void dispose() {
    _descartado = true;
    _cancelarTodasSubscriptions();
    _debounceSalvamento?.cancel();
    _syncQueue.dispose();
    _realtimeSync.parar();
    _lanRefreshTimer?.cancel();
    unawaited(_lanRealtime.parar());
    super.dispose();
  }

  /// Conta as notificações de mudança já emitidas. Os pulsos de sincronização
  /// usam isso para saber se algo REALMENTE mudou: se o contador não avançou,
  /// não há por que reconstruir a UI.
  int _versaoNotificacoes = 0;

  @override
  void notifyListeners() {
    if (_descartado) return;
    _versaoNotificacoes++;
    super.notifyListeners();
  }

  /// Cancela todos os timers ativos
  void _cancelarTodasSubscriptions() {
    debugPrint('>>> [Memória] 🧹 Cancelando timers e subscriptions...');
    _syncTimer?.cancel();
    _checkConnectivityTimer?.cancel();
    _windowFocusSubscription?.cancel();
    _windowVisibleSubscription?.cancel();
    _syncTimer = null;
    _checkConnectivityTimer = null;
    _windowFocusSubscription = null;
    _windowVisibleSubscription = null;
  }

  String get instanceId => _instanceId;

  // Proteção contra salvamentos excessivos (debounce otimizado)
  Timer? _debounceSalvamento;
  bool _salvandoDados = false;
  static const Duration _debounceDelay = Duration(
    milliseconds: 800,
  ); // Reduzido p/ 800ms: menor janela de perda ao fechar o app

  /// Grava TODAS as coleções pendentes no PostgreSQL local AGORA (flush forçado).
  /// Chamado pelo AppLifecycleListener ao fechar o app, garantindo que nenhum
  /// dado fique apenas em memória (requisito: persistência em PostgreSQL/Supabase).
  Future<void> salvarDadosAgora() async {
    if (!_persistenciaHabilitada) return;

    // Cancelar debounces pendentes (evita disparo duplicado após o flush).
    _debounceSalvamento?.cancel();
    _debounceSalvamento = null;
    _debounceLinhasLocais?.cancel();
    _debounceLinhasLocais = null;

    // Caminho rápido primeiro: grava só as linhas pendentes (caixa, vendas,
    // pedidos) antes do flush completo. Se alguma falhar, a coleção ficou suja
    // e é reescrita inteira logo abaixo.
    await _executarFlushLinhasLocais();

    if (_dirtyCollections.isEmpty) return;

    // Evitar concorrência com um salvamento debounced em andamento: aguardar até
    // ele terminar (com timeout de segurança) antes de rodar o flush forçado.
    final prazo = DateTime.now().add(const Duration(seconds: 5));
    while (_salvandoDados && DateTime.now().isBefore(prazo)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_salvandoDados) {
      debugPrint(
        '>>> [DataService] ⚠️ Flush forçado: timeout aguardando salvamento em andamento',
      );
      return;
    }

    debugPrint(
      '>>> [DataService] 🔄 Flush forçado: salvando ${_dirtyCollections.length} coleções pendentes...',
    );
    try {
      await _salvarTodosDados(aguardarSupabase: false, forcarTodos: true);
      debugPrint(
        '>>> [DataService] ✅ Flush forçado concluído (PostgreSQL local atualizado)',
      );
    } catch (e) {
      debugPrint('>>> [DataService] ❌ Erro no flush forçado: $e');
    }
  }

  /// Grava AGORA, no PostgreSQL local, o que está pendente: as linhas alteradas
  /// pelo caminho rápido (pedidos, vendas, caixa) e as coleções marcadas como
  /// sujas (entregas, motoristas…).
  ///
  /// É diferente de [salvarDadosAgora]: NÃO reescreve todas as tabelas, então
  /// serve para uma ação de tela (marcar/desmarcar entrega) confirmar a
  /// gravação antes de o usuário trocar de tela, sem o custo de um flush
  /// completo. Sem isso, a alteração ficava só na memória até o debounce — e
  /// ao reabrir a tela o dado antigo voltava do banco.
  Future<void> persistirAlteracoesPendentes() async {
    if (!_persistenciaHabilitada) return;

    _debounceLinhasLocais?.cancel();
    _debounceLinhasLocais = null;
    await _executarFlushLinhasLocais();

    if (_dirtyCollections.isEmpty) return;

    _debounceSalvamento?.cancel();
    _debounceSalvamento = null;
    try {
      await _salvarTodosDados(aguardarSupabase: false);
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Falha ao persistir alterações pendentes: $e',
      );
    }
  }

  DateTime? _ultimaSincronizacao;
  static const Duration _intervaloSincronizacao = Duration(
    days: 90,
  ); // MUITO maior para economizar cotas de gravação (90 dias)

  // Controle de coleções modificadas (Selective Saving)
  final Set<String> _dirtyCollections = {};

  /// Coleções marcadas como sujas porque receberam dados da NUVEM (e não por
  /// uma edição do usuário). O flush automático delas roda com `isSync: true`,
  /// para o trigger `set_updated_at` do PostgreSQL local NÃO trocar a data por
  /// `NOW()`: a data que veio da nuvem é a informação real de "quando mudou".
  ///
  /// Sem isso, cada pulso reescrevia a tabela inteira e carimbava
  /// `updated_at = agora` em todas as linhas; na comparação seguinte o local
  /// parecia sempre mais novo que a nuvem e TODA alteração feita no site era
  /// recusada ("Nuvem não é mais nova que o local") — o site nunca aparecia no
  /// app Windows.
  final Set<String> _colecoesSujasDaNuvem = {};

  /// Verdadeiro enquanto o bloco que aplica os dados baixados da nuvem está
  /// rodando. `_marcarSujo` consulta isto para classificar a coleção como
  /// "vinda da nuvem".
  bool _aplicandoDadosDaNuvem = false;

  // ---- GRAVAÇÃO LOCAL POR REGISTRO (caminho rápido) -------------------------
  //
  // As coleções críticas (caixa, vendas, pedidos) deixam de esperar o flush de
  // 800ms que reescrevia a TABELA INTEIRA a cada edição. Cada alteração registra
  // aqui só a LINHA mexida e é gravada por `upsertItem`/`removerItemPostgres`
  // em ~150ms. O flush completo continua existindo como REDE DE SEGURANÇA:
  // fechar o app (`salvarDadosAgora`), recargas totais, `forcarTodos` e falha
  // da gravação por registro (aí a coleção volta a ficar suja e a tabela toda
  // é reescrita).
  //   chave da coleção -> id -> linha (null = exclusão)
  final Map<String, Map<String, Map<String, dynamic>?>> _linhasLocaisPendentes =
      {};
  Timer? _debounceLinhasLocais;
  bool _salvandoLinhasLocais = false;
  bool _flushLinhasAgendado = false;
  static const Duration _debounceLinhaLocal = Duration(milliseconds: 150);

  // Cache de IDs removidos recentemente para evitar que o Supabase os restaure
  // durante a latência de sincronização
  final Set<String> _idsMesaRemovidosRecentemente =
      {}; // ⚠️ IDs de agendamentos criados localmente há <5s.
  // O REALTIME do Supabase dispara um INSERT de volta ao mesmo PC;
  // ignoramos esses eventos para não sobrescrever a versão local correta.
  final Map<String, DateTime> _agendamentosCriadosLocalmente = {};

  /// Piso entre cargas de download da nuvem no pulso automático.
  ///
  /// Com o delta ligado (`deltaCatalogo`), produtos/clientes descem só o que
  /// mudou e as demais tabelas são pequenas — então o pulso de 10s pode puxar
  /// novidades sem rebaixar o catálogo inteiro. O FULL SYNC automático do
  /// catálogo (quando as coleções estão vazias) continua limitado a 1×/6h por
  /// `_ultimaFullSyncCatalogoAutomatico`, que é o que protege a cota de egress.
  static const Duration _intervaloMinimoCargaPesada = Duration(seconds: 10);
  DateTime? _ultimaCargaPesadaNuvem;

  /// Último FULL SYNC do catálogo disparado AUTOMATICAMENTE pelo safeguard de
  /// coleções vazias (produtos/clientes/pedidos). Limitado a 1×/6h para não
  /// rebaixar ~13MB a cada pulso quando as coleções seguem vazias.
  DateTime? _ultimaFullSyncCatalogoAutomatico;

  void _resetTimerParaAtivo() {
    _lastSyncActivityTime = DateTime.now();
    if (_currentSyncInterval != 10) {
      _currentSyncInterval = 10;
      debugPrint(
        '>>> [Sync] ⚡ Atividade detectada localmente. Acelerando Auto-Sync para 10 segundos.',
      );
      _programarProximoSync();
    }
  }

  void _programarProximoSync() {
    _syncTimer?.cancel();
    if (!kIsWeb) {
      _syncTimer = Timer(Duration(seconds: _currentSyncInterval), () async {
        if (!isOffline && !_syncEmAndamento) {
          debugPrint(
            '>>> [Sync] 🔄 Pulso de sincronia automática iniciado (intervalo atual: ${_currentSyncInterval}s)...',
          );
          try {
            final versaoAntesDoPulso = _versaoNotificacoes;
            // Puxa o DELTA da nuvem a cada pulso (~10s). O catálogo só desce
            // inteiro na primeira carga ou no FULL SYNC automático (1×/6h);
            // depois disso produtos/clientes vêm por `updated_at`. É o que faz
            // a alteração feita no site aparecer no app em segundos.
            final agoraPulso = DateTime.now();
            final ultimaPesada = _ultimaCargaPesadaNuvem;
            final podeCarregarPesado =
                ultimaPesada == null ||
                agoraPulso.difference(ultimaPesada) >=
                    _intervaloMinimoCargaPesada;
            if (podeCarregarPesado) {
              _ultimaCargaPesadaNuvem = agoraPulso;
              await _carregarDadosDoSupabase(modoLeve: false);
            } else {
              final faltam =
                  _intervaloMinimoCargaPesada -
                  agoraPulso.difference(ultimaPesada!);
              debugPrint(
                '>>> [Sync] ⏭️ Download pesado adiado (piso de '
                '${_intervaloMinimoCargaPesada.inSeconds}s): libera em '
                '${faltam.inSeconds}s. Upload segue em cada pulso.',
              );
            }
            await _salvarTodosDados(aguardarSupabase: false, isSync: true);
            await atualizarConflitosCount();
            // Verificar se outra máquina enviou dados novos para a nuvem
            await _verificarAtualizacoesNuvem();
            // Só reconstrói a UI se o pulso trouxe novidade. As etapas acima já
            // chamam notifyListeners quando algo muda de verdade; antes havia um
            // notifyListeners() incondicional aqui, que a cada ~10s refazia toda
            // a árvore sob Consumer<DataService> mesmo sem nenhuma alteração.
            if (_versaoNotificacoes == versaoAntesDoPulso) {
              debugPrint(
                '>>> [Sync] 💤 Pulso sem novidades: UI não reconstruída.',
              );
            }
          } catch (e) {
            debugPrint('>>> [Sync] ⚠️ Erro no pulso de sincronia: $e');
          }
        }

        // Reavaliar intervalo de ociosidade
        final agora = DateTime.now();
        final diferencaMinutos = agora
            .difference(_lastSyncActivityTime)
            .inMinutes;
        if (diferencaMinutos >= 3) {
          if (_currentSyncInterval != 45) {
            _currentSyncInterval = 45;
            debugPrint(
              '>>> [Sync] 💤 Sem atividades locais nos últimos 3 min. Aumentando intervalo de Auto-Sync para 45 segundos.',
            );
          }
        } else {
          if (_currentSyncInterval != 10) {
            _currentSyncInterval = 10;
            debugPrint(
              '>>> [Sync] ⚡ Atividade recente ativa. Mantendo intervalo em 10 segundos.',
            );
          }
        }

        // Agenda o próximo pulso de sincronia
        _programarProximoSync();
      });
    } else {
      // WEB: o site não tem Realtime (o NEON_REALTIME_SECRET é removido do
      // bundle público antes do deploy), então busca somente o DELTA das
      // tabelas em um pulso curto. Isso mantém as alterações feitas no Windows
      // visíveis no portal em poucos segundos, sem expor credenciais nem fazer
      // uma varredura completa do catálogo no navegador.
      _syncTimer = Timer(const Duration(seconds: 10), _executarPulsoWeb);
    }
  }

  /// Pulso do portal (web): puxa o delta e reagenda.
  ///
  /// Fica separado para poder ser chamado também quando a aba volta ao foco
  /// (ver [_aoVoltarParaPaginaWeb]): assim não dependemos do timer, que o
  /// navegador estrangula para ~1×/minuto quando a página está escondida.
  Future<void> _executarPulsoWeb() async {
    final agora = DateTime.now();
    final anterior = _ultimoPulsoWeb;
    _ultimoPulsoWeb = agora;
    if (anterior != null &&
        agora.difference(anterior) > const Duration(seconds: 25)) {
      debugPrint(
        '>>> [Sync] ⏱️ Pulso web atrasou '
        '${agora.difference(anterior).inSeconds}s (aba em segundo plano?).',
      );
    }

    if (!_descartado && !isOffline && !_syncEmAndamento) {
      try {
        final versaoAntesDoPulso = _versaoNotificacoes;
        await _carregarDadosDoSupabase(modoLeve: true);
        if (_versaoNotificacoes == versaoAntesDoPulso) {
          debugPrint('>>> [Sync] 💤 Pulso web sem novidades.');
        }
      } catch (e) {
        debugPrint('>>> [Sync] ⚠️ Erro no pulso web: $e');
      }
    }
    if (!_descartado) _programarProximoSync();
  }

  /// A aba do portal voltou a ficar visível: puxa o delta NA HORA.
  ///
  /// O `window.onFocus` antigo não cobria troca de aba — e é justamente com a
  /// aba escondida que o navegador estrangula o pulso de 10 s para 1×/minuto.
  /// O resultado era a alteração feita no Windows demorar ~1 minuto para
  /// aparecer no site.
  void _aoVoltarParaPaginaWeb() {
    if (_descartado || _currentEmpresaId == null) return;
    final agora = DateTime.now();
    if (_ultimoRetornoWeb != null &&
        agora.difference(_ultimoRetornoWeb!).inSeconds < 2) {
      return; // visibilitychange + focus podem chegar juntos
    }
    _ultimoRetornoWeb = agora;
    debugPrint(
      '>>> [Sync] 👁️ Portal voltou a ficar visível — puxando novidades agora.',
    );
    // Não cancela o `_syncTimer` aqui de propósito: o pulso termina chamando
    // `_programarProximoSync()`, que já cancela/reagenda. Deixar o timer ativo
    // mantém `isSilentSync` verdadeiro e evita o "Sincronizando..." piscando na
    // tela só porque o usuário voltou para a aba.
    unawaited(_executarPulsoWeb());
  }

  void _marcarSujo(String collectionKey, {bool daNuvem = false}) {
    // Toda alteração real de coleção passa por aqui — inclusive cada bloco que
    // aplica dados da nuvem. É o sinal usado pela carga silenciosa para decidir
    // se precisa avisar a UI.
    _mudouNestaCarga = true;
    if (daNuvem || _aplicandoDadosDaNuvem) {
      // Persistência de espelho da nuvem: o flush não pode recarimbar
      // `updated_at` (ver `_colecoesSujasDaNuvem`).
      _colecoesSujasDaNuvem.add(collectionKey);
    } else {
      // Edição local: o registro precisa do carimbo `updated_at = NOW()` para
      // que os outros PCs/nuvem vejam a mudança pelo delta.
      _colecoesSujasDaNuvem.remove(collectionKey);
    }
    if (!_dirtyCollections.contains(collectionKey)) {
      _dirtyCollections.add(collectionKey);
      _salvarAutomaticamente();
    }
    _resetTimerParaAtivo();
  }

  /// Verdadeiro quando há linhas aguardando gravação pelo caminho rápido.
  bool get _temLinhasLocaisPendentes => _linhasLocaisPendentes.isNotEmpty;

  /// Grava UMA linha no banco local (upsert) SEM reescrever a tabela inteira.
  ///
  /// Cai no caminho antigo (`_marcarSujo` + flush completo) quando não há
  /// empresa selecionada, a persistência está desligada ou a coleção não tem
  /// tabela própria no PostgreSQL (ex.: `cache_dados`).
  void _persistirLinhaLocal(String collectionKey, Map<String, dynamic> row) {
    final id = row['id']?.toString();
    if (!_persistenciaHabilitada ||
        _currentEmpresaId == null ||
        id == null ||
        id.isEmpty ||
        !DatabaseService().temTabelaPara(collectionKey)) {
      _marcarSujo(collectionKey);
      return;
    }
    (_linhasLocaisPendentes[collectionKey] ??= {})[id] = row;
    _agendarFlushLinhasLocais();
  }

  /// Marca UMA linha para EXCLUSÃO no banco local (caminho rápido).
  void _removerLinhaLocal(String collectionKey, String id) {
    if (!_persistenciaHabilitada ||
        _currentEmpresaId == null ||
        !DatabaseService().temTabelaPara(collectionKey)) {
      _marcarSujo(collectionKey);
      return;
    }
    (_linhasLocaisPendentes[collectionKey] ??= {})[id] = null;
    _agendarFlushLinhasLocais();
  }

  void _agendarFlushLinhasLocais() {
    if (!_persistenciaHabilitada) return;
    if (_salvandoLinhasLocais) {
      _flushLinhasAgendado = true;
      return;
    }
    _debounceLinhasLocais?.cancel();
    _debounceLinhasLocais = Timer(_debounceLinhaLocal, () {
      _executarFlushLinhasLocais();
    });
  }

  /// Grava UMA linha no banco local e **aguarda** a gravação terminar.
  ///
  /// É o caminho usado antes de qualquer envio para a nuvem: quando este método
  /// retorna, o registro já está no PostgreSQL local (regra "local primeiro,
  /// nuvem depois"). Se a gravação não for possível pelo caminho rápido (web,
  /// tabela sem linha própria, persistência desligada), cai no flush completo
  /// — a mesma rede de segurança de sempre.
  Future<void> _salvarLinhaLocalAntesDaNuvem(
    String collectionKey,
    Map<String, dynamic> row,
  ) async {
    _persistirLinhaLocal(collectionKey, row);
    await _executarFlushLinhasLocais();
  }

  /// Igual a [_salvarLinhaLocalAntesDaNuvem], para EXCLUSÕES.
  Future<void> _removerLinhaLocalAntesDaNuvem(
    String collectionKey,
    String id,
  ) async {
    _removerLinhaLocal(collectionKey, id);
    await _executarFlushLinhasLocais();
  }

  /// Grava no PostgreSQL apenas as linhas pendentes de cada coleção.
  ///
  /// Se uma linha falhar, a coleção inteira é marcada como suja: o flush
  /// completo (tabela toda) volta a cobri-la como rede de segurança, em vez de
  /// a linha ficar em um retry apertado e infinito.
  Future<void> _executarFlushLinhasLocais() async {
    if (_linhasLocaisPendentes.isEmpty) return;
    // Quem chama com `await` precisa da GARANTIA de que a linha está no banco
    // local (regra "o local é salvo ANTES de ir para a nuvem"). Se já existe um
    // flush em andamento, espera ele terminar: o que ficou de novo entra na
    // passada seguinte e `_flushLinhasAgendado` garante que ela aconteça.
    // Limite de 5 s: se o banco local travar, o chamador não pode ficar preso.
    var esperasFlush = 0;
    while (_salvandoLinhasLocais && esperasFlush < 250) {
      _flushLinhasAgendado = true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      esperasFlush++;
      if (_linhasLocaisPendentes.isEmpty) return;
    }
    if (_salvandoLinhasLocais) {
      _flushLinhasAgendado = true;
      return;
    }
    _debounceLinhasLocais?.cancel();
    _debounceLinhasLocais = null;
    _salvandoLinhasLocais = true;
    _flushLinhasAgendado = false;

    final db = DatabaseService();
    final empresa = _currentEmpresaId;
    var gravadas = 0;
    final falhas = <String>{};

    try {
      for (final chave in List<String>.from(_linhasLocaisPendentes.keys)) {
        final linhas = _linhasLocaisPendentes[chave];
        if (linhas == null || linhas.isEmpty) {
          _linhasLocaisPendentes.remove(chave);
          continue;
        }
        for (final id in List<String>.from(linhas.keys)) {
          final row = linhas[id];
          try {
            if (row == null) {
              await db.removerItemPostgres(
                chave,
                id,
                empresa,
                lancarSeFalhar: true,
              );
            } else {
              await db.upsertItem(chave, row, lancarSeFalhar: true);
            }
            linhas.remove(id);
            gravadas++;
          } catch (e) {
            debugPrint(
              '>>> [Local] ❌ Linha $id de $chave falhou ($e). '
              'Caindo no flush completo.',
            );
            falhas.add(chave);
            _marcarSujo(chave);
            _linhasLocaisPendentes.remove(chave);
            break;
          }
        }
        if (linhas.isEmpty) _linhasLocaisPendentes.remove(chave);
      }
    } finally {
      _salvandoLinhasLocais = false;
      if (gravadas > 0) {
        debugPrint(
          '>>> [Local] ⚡ $gravadas linha(s) gravadas por registro '
          '(sem reescrever a tabela inteira).',
        );
      }
      if (_flushLinhasAgendado && _linhasLocaisPendentes.isNotEmpty) {
        _agendarFlushLinhasLocais();
      }
    }
  }

  // Dois envios para a nuvem ao mesmo tempo não podem disparar dois flush
  // completos simultâneos: o PostgreSQL local (Windows) trava com escrita
  // concorrente. Este flag faz o segundo chamado apenas esperar o primeiro.
  bool _garantiaLocalEmCurso = false;

  /// REGRA DA CASA — **gravação LOCAL primeiro, nuvem depois, para TODA entidade**.
  ///
  /// 1) descarrega as linhas do caminho rápido (gravação por registro, ~150 ms);
  /// 2) se ainda há coleções sujas (flush completo de 800 ms), força o gravar
  ///    AGORA.
  ///
  /// Chamado antes de QUALQUER requisição de rede de escrita e antes de ler o
  /// banco local: assim o dado que o usuário acabou de lançar já está no
  /// PostgreSQL local quando o envio acontece — e uma releitura do banco nunca
  /// enxerga a memória "à frente" do disco (era isso que apagava lançamento
  /// recém-feito). Nuvem em pausa, offline ou com erro (402/quota) não segura,
  /// não desfaz e não desordena nada disto: a nuvem é espelho, o local é a
  /// fonte da verdade.
  Future<void> _garantirGravacaoLocalPendente() async {
    if (!_persistenciaHabilitada) return;
    try {
      await _executarFlushLinhasLocais();
      if (_dirtyCollections.isEmpty ||
          _salvandoDados ||
          _garantiaLocalEmCurso) {
        return; // nada pendente, ou o gravador completo já está rodando
      }
      _garantiaLocalEmCurso = true;
      try {
        _debounceSalvamento?.cancel();
        await _executarSalvamentoAutomatico();
      } finally {
        _garantiaLocalEmCurso = false;
      }
    } catch (e) {
      debugPrint('>>> [Local] ⚠️ Não consegui garantir gravação local: $e');
    }
  }

  /// Inicia o timer de sincronização automática (Pulso Adaptativo)
  /// Essencial para manter múltiplas máquinas alinhadas sem usar Streams instáveis.
  void iniciarAutoSync() {
    _syncTimer?.cancel();
    _currentSyncInterval = 10;
    _lastSyncActivityTime = DateTime.now();
    debugPrint(
      '>>> [Sync] ⏱️ Timer de Auto-Sync Adaptativo iniciado (10 seg inicial)',
    );
    _programarProximoSync(); // Iniciar backup diário automático
    _iniciarBackupDiario();
  }

  Timer? _backupDiarioTimer;
  DateTime? _ultimoBackupDiario;
  bool _emProcessoBackupDiario = false;

  /// Inicia o timer de backup diário automático.
  /// Roda na abertura do app e depois verifica a cada 30 min se 24h passaram.
  /// Gera um dump PostgreSQL (.dump) e envia para o Supabase Storage.
  ///
  /// Depois de enviar, o computador e a nuvem ficam com os
  /// [BackupRestoreService.maxBackupsPorEmpresa] (5) backups mais recentes de
  /// cada tipo — os antigos saem sozinhos, dos dois lados.
  void _iniciarBackupDiario() {
    _backupDiarioTimer?.cancel();

    _carregarUltimoBackupDiario().then((_) async {
      await _carregarUltimoBackupNuvem();
      await _carregarUltimoBackupCompleto();
      // 1. Rodar backup logo na abertura do app (com pequeno delay para não travar o boot)
      Timer(const Duration(seconds: 20), () {
        _verificarBackupDiario(forcar: true);
      });
      // 1b. Backup na nuvem um pouco depois, para não competir com o dump local
      // (o backup .sql roda ~30 consultas no psql)
      Timer(const Duration(seconds: 90), () {
        _verificarBackupNuvemDiario();
        // Se algum dump de um boot anterior ficou devendo envio, tenta agora.
        reenviarDumpPendente();
      });
      // 1c. Backup COMPLETO do banco da nuvem por último: ele lê TODAS as tabelas
      // de TODAS as empresas e envia vários MB — melhor não competir com os
      // outros dois nem atrasar a abertura.
      Timer(const Duration(seconds: 150), () {
        verificarBackupCompletoNuvem(forcar: true);
      });
      // 2. Depois verificar a cada 30 min (respeitando o intervalo, 24h)
      _backupDiarioTimer = Timer.periodic(const Duration(minutes: 30), (_) {
        reenviarDumpPendente();
        _verificarBackupDiario();
        _verificarBackupNuvemDiario();
        verificarBackupCompletoNuvem();
      });
      debugPrint(
        '>>> [Backup] ⏱️ Timers de backup iniciados — dump LOCAL (20s) + '
        '.sql da EMPRESA na nuvem (90s) + banco COMPLETO da nuvem (150s); '
        'depois a cada 30 min, respeitando 24h.',
      );
    });
  }

  Future<void> _carregarUltimoBackupDiario() async {
    if (_currentEmpresaId == null) return;
    try {
      final key = _getEmpresaKey('exodo_ultimo_backup_diario');
      final valor = await _storage.carregar(key);
      if (valor != null) {
        _ultimoBackupDiario = DateTime.tryParse(valor.toString());
      }
    } catch (e) {
      debugPrint('>>> [Backup] ⚠️ Erro ao carregar último backup: $e');
    }
  }

  /// Envia o dump diário para a nuvem. Devolve `true` quando o arquivo ficou na
  /// nuvem. Só falha "de verdade" (retorna false) quando não dá para tentar ou
  /// quando o envio deu erro — nos dois casos o chamador marca o arquivo como
  /// pendente para tentar de novo.
  Future<bool> _enviarDumpDiarioParaNuvem(
    BackupRestoreService backupService,
    String dumpPath,
  ) async {
    if (!SupabaseService.isAvailable || _isOffline) {
      debugPrint(
        '>>> [Backup] ⏭️ Dump diário: upload pulado (offline/indisponível).',
      );
      return false;
    }
    try {
      final arquivo = File(dumpPath);
      if (!await arquivo.exists()) {
        debugPrint(
          '>>> [Backup] ⏭️ Dump diário: arquivo não está mais no disco.',
        );
        return true; // nada a enviar
      }
      final (ok, msg) = await backupService.uploadDumpNaNuvem(arquivo);
      if (ok) {
        debugPrint('>>> [Backup] ☁️ Dump diário enviado para nuvem: $msg');
        addSyncLog(
          '☁️ Backup diário do banco PostgreSQL enviado para a nuvem.',
        );
        return true;
      }
      debugPrint('>>> [Backup] ⚠️ Falha no upload do dump diário: $msg');
      addSyncLog('⚠️ Dump diário não subiu para a nuvem: $msg');
      return false;
    } catch (e) {
      debugPrint('>>> [Backup] ❌ Erro ao enviar dump diário para nuvem: $e');
      addSyncLog('⚠️ Erro ao enviar o dump diário para a nuvem: $e');
      return false;
    }
  }

  /// Guarda (ou limpa, com [caminho] nulo) o dump que ficou devendo envio.
  Future<void> _marcarDumpPendente(String? caminho) async {
    try {
      await _storage.salvar(
        _getEmpresaKey('exodo_dump_pendente_envio'),
        caminho ?? '',
      );
    } catch (e) {
      debugPrint('>>> [Backup] ⚠️ Erro ao marcar dump pendente: $e');
    }
  }

  /// Reenvia o dump que ficou devendo envio (chamado nas verificações de 30 min
  /// e logo após a abertura). Não gera um dump novo — só tenta subir o arquivo
  /// que já existe.
  Future<void> reenviarDumpPendente() async {
    if (_currentEmpresaId == null) return;
    if (!SupabaseService.isAvailable || _isOffline) return;

    try {
      final pendente = await _storage.carregar(
        _getEmpresaKey('exodo_dump_pendente_envio'),
      );
      final caminho = (pendente ?? '').toString();
      if (caminho.isEmpty) return;

      debugPrint('>>> [Backup] 🔁 Tentando reenviar o dump pendente: $caminho');
      final enviou = await _enviarDumpDiarioParaNuvem(
        BackupRestoreService(this),
        caminho,
      );
      if (enviou) {
        await _marcarDumpPendente(null);
        debugPrint('>>> [Backup] ✅ Dump pendente enviado — nada mais devendo.');
      }
    } catch (e) {
      debugPrint('>>> [Backup] ⚠️ Erro ao reenviar dump pendente: $e');
    }
  }

  /// Verifica se é hora de gerar o backup diário para TODAS as empresas.
  /// Roda a cada 30 minutos; para cada empresa, verifica se 24h passaram
  /// desde o último backup. O dump pg_dump é gerado UMA VEZ (banco inteiro)
  /// e copiado para a pasta de cada empresa. O backup .sql é gerado
  /// separadamente para cada empresa (cada um filtra por empresa_id).
  Future<void> _verificarBackupDiario({bool forcar = false}) async {
    if (_currentEmpresaId == null) return;
    if (_emProcessoBackupDiario) {
      debugPrint(
        '>>> [Backup] ⏳ Backup diário já em processamento, pulando...',
      );
      return;
    }

    // Listar todas as empresas do banco local
    final db = DatabaseService();
    final todasEmpresas = await db.carregarListaCompleta('empresas');
    if (todasEmpresas.isEmpty) {
      debugPrint('>>> [Backup] ⚠️ Nenhuma empresa encontrada no banco local.');
      return;
    }

    // Para cada empresa, verificar se precisa de backup
    final agora = DateTime.now();
    final empresasQuePrecisamBackup = <Map<String, dynamic>>[];
    for (final emp in todasEmpresas) {
      final empId = emp['id']?.toString();
      if (empId == null || empId.isEmpty) continue;
      final chave = 'appcfg_empresa_${empId}_exodo_ultimo_backup_diario';
      final valor = await _storage.carregar(chave);
      final ultimo = valor != null ? DateTime.tryParse(valor.toString()) : null;
      final horas = ultimo != null ? agora.difference(ultimo).inHours : 999;
      if (forcar || horas >= 24) {
        empresasQuePrecisamBackup.add(emp);
      }
    }

    if (empresasQuePrecisamBackup.isEmpty) {
      debugPrint(
        '>>> [Backup] ⏭️ Backup diário: todas as empresas foram backed up nas últimas 24h.',
      );
      return;
    }

    debugPrint(
      '>>> [Backup] 🕐 Backup diário: ${empresasQuePrecisamBackup.length} empresa(s) precisam de backup.',
    );
    _emProcessoBackupDiario = true;

    addSyncLog(
      '🗄️ Backup diário: ${empresasQuePrecisamBackup.length} empresa(s) precisam de backup...',
    );

    try {
      final backupService = BackupRestoreService(this);
      File? dumpGerado; // pg_dump UMA VEZ, copiado para cada empresa

      for (final emp in empresasQuePrecisamBackup) {
        final empId = emp['id']?.toString();
        if (empId == null || empId.isEmpty) continue;
        final nomeEmp = (emp['nome_fantasia'] ?? emp['razao_social'] ?? empId)
            .toString()
            .replaceAll(RegExp(r'[^a-zA-Z0-9À-ú]'), '_');

        debugPrint('>>> [Backup] 📦 Processando empresa $nomeEmp ($empId)...');

        // Pasta para dumps desta empresa
        final dumpsDir = Directory('C:\\ExodoBackups\\$empId\\dumps');
        if (!await dumpsDir.exists()) await dumpsDir.create(recursive: true);

        final dataStr =
            '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
        final horaStr =
            '${agora.hour.toString().padLeft(2, '0')}${agora.minute.toString().padLeft(2, '0')}';

        // 1. Gerar dump local (pg_dump -Fc) — UMA VEZ para todas as empresas
        if (dumpGerado == null) {
          final dumpPath = p.join(
            dumpsDir.path,
            '${nomeEmp}_dump_diario_${dataStr}_${horaStr}.dump',
          );
          final (sucesso, mensagem, caminho) = await backupService
              .criarBackupDumpLocal(destinoArquivo: dumpPath);
          if (!sucesso || caminho == null) {
            debugPrint('>>> [Backup] ⚠️ Falha ao gerar dump: $mensagem');
            addSyncLog('⚠️ Dump diário falhou: $mensagem');
            continue;
          }
          dumpGerado = File(caminho);
          debugPrint('>>> [Backup] 💾 Dump gerado: $caminho');
        } else {
          // Copiar dump existente para esta empresa
          final dumpPath = p.join(
            dumpsDir.path,
            '${nomeEmp}_dump_diario_${dataStr}_${horaStr}.dump',
          );
          await dumpGerado.copy(dumpPath);
          debugPrint('>>> [Backup] 📋 Dump copiado para $nomeEmp: $dumpPath');
        }

        // 2. Upload do dump para a nuvem
        final dumpPath = p.join(
          dumpsDir.path,
          '${nomeEmp}_dump_diario_${dataStr}_${horaStr}.dump',
        );
        final enviou = await _enviarDumpDiarioParaNuvem(
          backupService,
          dumpPath,
        );
        await _marcarDumpPendente(enviou ? null : dumpPath);

        // 3. Backup .sql da empresa para a nuvem (cada empresa tem seu propre sql)
        try {
          if (SupabaseService.isAvailable && !_isOffline) {
            final (okSql, msgSql, caminhoSql) = await backupService
                .criarBackupSqlDaEmpresa(empresaId: empId);
            if (okSql && caminhoSql != null) {
              // O resultado do upload é conferido: antes ele era ignorado e o
              // log dizia "enviado" mesmo quando o arquivo era recusado (foi
              // assim que o backup de uma empresa com acento no nome ficou
              // dias sem subir sem ninguém perceber).
              final (subiu, msgUpload) = await backupService.uploadDumpNaNuvem(
                File(caminhoSql),
              );
              if (subiu) {
                debugPrint(
                  '>>> [Backup] ☁️ Backup .sql de $nomeEmp enviado para nuvem.',
                );
              } else {
                debugPrint(
                  '>>> [Backup] ⚠️ Backup .sql de $nomeEmp NÃO subiu: $msgUpload',
                );
                addSyncLog(
                  '⚠️ Backup .sql de $nomeEmp não subiu para a nuvem: $msgUpload',
                );
              }
            } else {
              debugPrint(
                '>>> [Backup] ⚠️ Backup .sql de $nomeEmp falhou: $msgSql',
              );
            }
          }
        } catch (e) {
          debugPrint('>>> [Backup] ⚠️ Erro no backup .sql de $nomeEmp: $e');
        }

        // 4. Limpar os backups LOCAIS antigos desta empresa — a regra dos "5
        // últimos" vale para os .dump (que acabaram de subir) e também para os
        // .sql gerados agora; sem isso esta pasta cresceria sem limite.
        try {
          final removidos = await backupService.manterUltimosBackupsLocais(
            empId,
          );
          if (removidos > 0) {
            debugPrint(
              '>>> [Backup] 🗑️ $removidos backup(s) local(is) antigo(s) de '
              '$nomeEmp removido(s) — ficam os '
              '${BackupRestoreService.maxBackupsPorEmpresa} últimos.',
            );
          }
        } catch (e) {
          debugPrint(
            '>>> [Backup] ⚠️ Erro ao limpar backups antigos de $nomeEmp: $e',
          );
        }

        // 5. Atualizar timestamp desta empresa
        await _storage.salvar(
          'appcfg_empresa_${empId}_exodo_ultimo_backup_diario',
          agora.toIso8601String(),
        );
        debugPrint('>>> [Backup] ✅ Backup diário de $nomeEmp concluído.');
      }

      // Atualizar timestamp da empresa atual (compatibilidade)
      _ultimoBackupDiario = agora;
      debugPrint(
        '>>> [Backup] ✅ Backup diário de todas as empresas concluído.',
      );
    } catch (e) {
      debugPrint('>>> [Backup] ❌ Erro inesperado no backup diário: $e');
      addSyncLog('❌ Erro inesperado no backup diário: $e');
    } finally {
      _emProcessoBackupDiario = false;
    }
  }

  // ==========================================================================
  // BACKUP AUTOMÁTICO NA NUVEM (PostgreSQL .sql — SOMENTE a empresa atual)
  // ==========================================================================

  DateTime? _ultimoBackupNuvem;

  /// Data/hora do último backup enviado para a nuvem (empresa atual).
  DateTime? get ultimoBackupNuvem => _ultimoBackupNuvem;

  /// Carrega do armazenamento local o horário do último backup na nuvem
  /// (chave por empresa, então cada empresa tem o seu próprio controle).
  Future<void> _carregarUltimoBackupNuvem() async {
    if (_currentEmpresaId == null) return;
    try {
      final valor = await _storage.carregar(
        _getEmpresaKey('exodo_ultimo_backup_nuvem'),
      );
      if (valor != null) {
        _ultimoBackupNuvem = DateTime.tryParse(valor.toString());
      }
    } catch (e) {
      debugPrint(
        '>>> [BackupNuvem] ⚠️ Erro ao carregar último backup da nuvem: $e',
      );
    }
  }

  /// Gera e envia AGORA para a nuvem um backup PostgreSQL (.sql) com APENAS os
  /// dados da empresa atual (Supabase Storage, pasta `dumps/{empresaId}/`).
  /// Não depende do pg_dump: usa psql com `COPY ... WHERE empresa_id = '<id>'`.
  /// Retorna (sucesso, mensagem).
  Future<(bool, String)> fazerBackupNuvemAgora() async {
    if (_currentEmpresaId == null || _currentEmpresaId!.isEmpty) {
      return (false, 'Empresa não selecionada');
    }
    if (!SupabaseService.isAvailable) {
      return (false, 'Supabase indisponível — backup na nuvem não enviado');
    }

    try {
      final backupService = BackupRestoreService(this);

      // 1. Gera o backup PostgreSQL (.sql) SOMENTE desta empresa
      final (okGerou, msgGerou, caminho) = await backupService
          .criarBackupSqlDaEmpresa();
      if (!okGerou || caminho == null) {
        debugPrint('>>> [BackupNuvem] ⚠️ $msgGerou');
        addSyncLog('⚠️ Backup da empresa na nuvem NÃO foi gerado: $msgGerou');
        return (false, msgGerou);
      }

      // 2. Envia para a nuvem, na pasta da própria empresa
      final (ok, msg) = await backupService.uploadDumpNaNuvem(File(caminho));
      if (ok) {
        _ultimoBackupNuvem = DateTime.now();
        await _storage.salvar(
          _getEmpresaKey('exodo_ultimo_backup_nuvem'),
          _ultimoBackupNuvem!.toIso8601String(),
        );
        addSyncLog('☁️ Backup PostgreSQL da empresa enviado para a nuvem.');
        return (true, 'Backup da empresa enviado para a nuvem! $msgGerou');
      }
      addSyncLog('⚠️ Backup da empresa NÃO subiu para a nuvem: $msg');
      return (false, msg);
    } catch (e) {
      debugPrint('>>> [BackupNuvem] ❌ Erro ao enviar backup para a nuvem: $e');
      return (false, 'Erro ao enviar backup para a nuvem: $e');
    }
  }

  /// Timer diário do backup PostgreSQL na nuvem.
  /// NOTA: desde a refatoração, o backup .sql por empresa é feito dentro de
  /// [_verificarBackupDiario], que itera TODAS as empresas. Este método
  /// agora só serve como fallback para o caso de o dump local ter falhado
  /// mas a empresa estar online.
  Future<void> _verificarBackupNuvemDiario() async {
    // O backup .sql por empresa já é feito em _verificarBackupDiario para
    // todas as empresas. Este método fica como compatibilidade.
    debugPrint(
      '>>> [BackupNuvem] ℹ️ Backup .sql por empresa já integrado no backup diário.',
    );
  }

  // ==========================================================================
  // BACKUP COMPLETO DO BANCO DA NUVEM (TODAS as empresas) — automático
  // ==========================================================================
  //
  // Diferente dos dois acima (que são por empresa), este é a cópia COMPLETA do
  // banco do Supabase — o arquivo de recuperação de desastre —, arquivado na
  // própria nuvem em `dumps/_banco_completo/`. Como ele não pertence a nenhuma
  // empresa, o controle do último envio é uma chave GLOBAL, sem prefixo de
  // empresa (senão cada empresa teria o seu relógio e o backup sairia várias
  // vezes por dia).

  static const String _keyUltimoBackupCompleto =
      'exodo_ultimo_backup_completo_nuvem';

  DateTime? _ultimoBackupCompletoNuvem;
  bool _emProcessoBackupCompleto = false;

  /// BACKOFF: última tentativa de backup completo (sucesso OU falha).
  ///
  /// Sem isto, um backup que falha (ex.: cota do Neon estourada, `pg_dump`
  /// indisponível) era re-tentado a cada 30min para sempre — cada tentativa
  /// baixa o banco da nuvem INTEIRO (todas as empresas), ou seja, o retry
  /// infinito era uma das maiores fontes de egress.
  DateTime? _ultimaTentativaBackupCompletoNuvem;

  /// Espera mínima entre TENTATIVAS de backup completo quando a anterior
  /// falhou. Um backup bem-sucedido continua respeitando o intervalo normal
  /// (`BACKUP_COMPLETO_NUVEM_HORAS`).
  static const Duration _backoffAposFalhaBackup = Duration(hours: 6);

  /// Data/hora do último backup COMPLETO do banco da nuvem enviado.
  DateTime? get ultimoBackupCompletoNuvem => _ultimoBackupCompletoNuvem;

  Future<void> _carregarUltimoBackupCompleto() async {
    try {
      final valor = await _storage.carregar(_keyUltimoBackupCompleto);
      if (valor != null) {
        _ultimoBackupCompletoNuvem = DateTime.tryParse(valor.toString());
      }
    } catch (e) {
      debugPrint('>>> [BackupCompleto] ⚠️ Erro ao carregar o último envio: $e');
    }
  }

  /// Verifica se é hora do backup COMPLETO do banco da nuvem e, quando for,
  /// gera o arquivo (todas as tabelas, todas as empresas) e o arquiva na
  /// própria nuvem.
  ///
  /// O intervalo vem do .env (`BACKUP_COMPLETO_NUVEM_HORAS`, 24h por padrão;
  /// 0 desliga). Devolve uma linha dizendo o que aconteceu — é o mesmo texto
  /// do log, e serve para conferir o comportamento sem precisar do app aberto.
  ///
  /// [forcar] antecipa a VERIFICAÇÃO na abertura do app (em vez de esperar o
  /// timer de 30 min); a regra do intervalo continua valendo, então reabrir o
  /// app logo depois de um backup não gera um segundo arquivo.
  Future<String> verificarBackupCompletoNuvem({bool forcar = false}) async {
    if (!EnvConfig.backupCompletoNuvemAtivo) {
      return 'backup completo automático DESLIGADO (BACKUP_COMPLETO_NUVEM_HORAS=0)';
    }
    if (_emProcessoBackupCompleto) {
      return 'backup completo já em andamento — ignorado';
    }
    if (!SupabaseService.isAvailable || _isOffline) {
      return 'backup completo: sem Supabase/offline — pulado';
    }
    if (!EnvConfig.backupBancoNuvemConfigurado) {
      return 'backup completo: conexão do banco da nuvem não configurada no .env';
    }

    final intervalo = EnvConfig.backupCompletoNuvemHoras;
    final agora = DateTime.now();

    // BACKOFF: se a ÚLTIMA tentativa falhou há menos de 6h, não insiste.
    // Uma falha hoje significava retry a cada 30min para sempre, e cada
    // tentativa baixa o banco da nuvem inteiro (todas as empresas).
    // "Falhou" = tentativa mais nova que o último sucesso, OU nunca houve
    // sucesso algum (primeira máquina / backup ainda nunca completou).
    final tentativaAtual = _ultimaTentativaBackupCompletoNuvem;
    final ultimoSucesso = _ultimoBackupCompletoNuvem;
    final tentativaFalhou =
        tentativaAtual != null &&
        (ultimoSucesso == null || tentativaAtual.isAfter(ultimoSucesso));
    if (tentativaFalhou &&
        agora.difference(tentativaAtual!) < _backoffAposFalhaBackup) {
      final faltam = _backoffAposFalhaBackup - agora.difference(tentativaAtual);
      debugPrint(
        '>>> [BackupCompleto] ⏭️ Última tentativa falhou há '
        '${agora.difference(tentativaAtual).inMinutes}min — '
        'nova tentativa em ${faltam.inMinutes}min (backoff).',
      );
      return 'backup completo: tentativa anterior falhou, backoff de '
          '${faltam.inMinutes}min restante';
    }

    final horasDesdeUltimo = _ultimoBackupCompletoNuvem != null
        ? agora.difference(_ultimoBackupCompletoNuvem!).inHours
        : 9999;
    if (horasDesdeUltimo < intervalo) {
      final faltam = intervalo - horasDesdeUltimo;
      debugPrint(
        '>>> [BackupCompleto] ⏭️ Ainda não é hora: faltam ${faltam}h '
        '(intervalo ${intervalo}h).',
      );
      return 'backup completo: faltam ${faltam}h (intervalo de ${intervalo}h)';
    }

    _emProcessoBackupCompleto = true;
    // Registra a TENTATIVA antes de rodar: se o processo morrer no meio
    // (ex.: cota estourada), a próxima verificação já entra no backoff em vez
    // de disparar outro pg_dump imediatamente.
    _ultimaTentativaBackupCompletoNuvem = agora;
    debugPrint(
      '>>> [BackupCompleto] 🕐 Hora do backup COMPLETO do banco da nuvem...',
    );
    addSyncLog(
      '🗄️ Backup COMPLETO do banco da nuvem iniciado (todas as empresas)...',
    );
    try {
      final (ok, msg, _) = await BackupRestoreService(
        this,
      ).enviarBackupCompletoParaNuvem();
      if (!ok) {
        debugPrint('>>> [BackupCompleto] ⚠️ $msg');
        addSyncLog('⚠️ Backup COMPLETO da nuvem falhou: $msg');
        return 'backup completo FALHOU: $msg';
      }

      _ultimoBackupCompletoNuvem = agora;
      await _storage.salvar(_keyUltimoBackupCompleto, agora.toIso8601String());
      debugPrint('>>> [BackupCompleto] ✅ $msg');
      addSyncLog('☁️ Backup COMPLETO do banco da nuvem salvo na nuvem.');
      return 'backup completo ENVIADO: $msg';
    } catch (e) {
      debugPrint('>>> [BackupCompleto] ❌ Erro no backup completo: $e');
      addSyncLog('❌ Erro no backup COMPLETO da nuvem: $e');
      return 'backup completo ERRO: $e';
    } finally {
      _emProcessoBackupCompleto = false;
    }
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
      await _audioPlayer.setVolume(
        0.8,
      ); // 80% do volume para garantir audibilidade

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
          debugPrint(
            '>>> [Audio] 🔄 Tentando fallback via HTML AudioElement...',
          );
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
      final nuvemEstavaHabilitada = nuvemHabilitada;
      _empresaAtual = empresa;
      final nuvemEstaHabilitada = nuvemHabilitada;
      _syncQueue.setPaused(
        empresa == null ||
            _currentEmpresaId != empresa.id ||
            !nuvemEstaHabilitada,
      );

      if (!nuvemEstaHabilitada) {
        unawaited(_realtimeSync.parar());
      } else if (!nuvemEstavaHabilitada &&
          empresa != null &&
          _currentEmpresaId == empresa.id &&
          !_isModoLeve) {
        unawaited(
          _realtimeSync.iniciar(
            empresa.id,
            callback: _aplicarMudancaRealtime,
            aoMudarNaNuvem: _aoMudarPelaNuvem,
          ),
        );
      }

      _carregarPerfisTributariosDaEmpresa();
      _carregarDepartamentosDaEmpresa();
      _carregarEstoquesDaEmpresa();
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
    _carregarEstoquesDaEmpresa();

    // PERSISTÊNCIA CRÍTICA: Salvar no PostgreSQL IMEDIATAMENTE
    if (!kIsWeb) {
      await DatabaseService().salvarEmpresaLocal(empresaComTimestamp.toMap());
    } else {
      await _storage.salvar('empresa_atual', empresaComTimestamp.toMap());
    }

    unawaited(
      _upsertNoSupabase(
        SupabaseService.tableEmpresas,
        empresaComTimestamp.toMap(),
      ),
    );

    // Mantém a cópia do AuthService em sincronia (mesma empresa, mesmas
    // configurações). Sem isso, o AuthService continuava com a config antiga
    // (ex.: perfil padrão recém-alterado voltava e era reaplicado a seguir).
    onEmpresaAtualizada?.call(empresaComTimestamp);

    notifyListeners();
  }

  // Estado de carregamento
  bool _isLoading = false;
  String _mensagemLoading = 'Carregando...';

  // Carga INICIAL: enquanto true, o app mantém a tela de "carregando".
  // No desktop a tela SAI assim que o PostgreSQL local responde — a nuvem
  // é espelho e não segura a abertura. O limite abaixo só vale se o banco
  // local falhou e ainda estamos tentando a nuvem como fallback.
  bool _sincronizandoInicial = false;
  static const Duration _limiteEsperaNuvemInicial = Duration(seconds: 15);

  // Controle de Paginação (Infinite Scroll)
  bool _temMaisClientes = true;
  bool _carregandoMaisClientes = false;

  bool _temMaisVendas = true;
  bool _carregandoMaisVendas = false;
  bool get isLoading => _isLoading;

  /// Os dados que a tela de carregando lista, com a quantidade já em memória.
  ///
  /// Lê os tamanhos das coleções NA HORA (não guarda cópia): conforme a carga
  /// avança e o `notifyListeners()` chega, os números da tela sobem sozinhos
  /// — é o "mostrar os dados carregando" da abertura do sistema.
  List<({String rotulo, int quantidade})> get progressoLoading => [
    (rotulo: 'Produtos', quantidade: _produtos.length),
    (rotulo: 'Clientes', quantidade: _clientes.length),
    (rotulo: 'Pedidos', quantidade: _pedidos.length),
    (rotulo: 'Vendas (balcão)', quantidade: _vendasBalcao.length),
    (rotulo: 'Serviços', quantidade: _tiposServico.length),
    (rotulo: 'Notas de entrada', quantidade: _notasEntrada.length),
    (rotulo: 'Histórico de estoque', quantidade: _estoqueHistorico.length),
  ];

  /// Redesenha a tela de carregando para os contadores acompanharem a carga —
  /// só enquanto alguma carga está de fato acontecendo (fora disso seria
  /// rebuild à toa).
  void _notificarProgressoLoading() {
    if (_isLoading || _sincronizandoInicial) notifyListeners();
  }

  /// True enquanto os dados iniciais da nuvem estão sendo baixados na abertura.
  bool get sincronizandoInicial => _sincronizandoInicial;
  bool get syncEmAndamento => _syncEmAndamento;
  DateTime? get ultimaSincronizacaoSucesso => _ultimaSincronizacaoSucesso;
  String? get ultimoErroSync => _ultimoErroSync;
  int get conflitosCount => _conflitosCount;
  String get mensagemLoading => _mensagemLoading;
  bool get isModoLeve => _isModoLeve;
  bool get firebaseHabilitado => false; // Legado: Agora usamos Supabase
  bool get supabaseHabilitado => SupabaseService.isAvailable;
  bool get nuvemHabilitada => _empresaAtual?.nuvemAtiva ?? true;

  List<String> get syncLogs => List.unmodifiable(_syncLogs);

  void addSyncLog(String message) {
    final now = DateTime.now().toLocal();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
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

  /// O cache local (PostgreSQL) trouxe dados operacionais para a memória?
  /// Usado na ABERTURA do sistema para decidir se já dá para abrir as telas.
  ///
  /// As coleções de CAIXA entram nesta conta de propósito: sem internet o
  /// sistema precisa abrir direto no fluxo de caixa mesmo que as demais
  /// listas estejam vazias (loja que só movimenta caixa, banco recém-restaurado,
  /// etc.). Antes disto a tela ficava 60s esperando a nuvem — que não chegava.
  bool get _cacheLocalTemDados =>
      _produtos.isNotEmpty ||
      _clientes.isNotEmpty ||
      _pedidos.isNotEmpty ||
      _vendasBalcao.isNotEmpty ||
      _servicosRealizados.isNotEmpty ||
      _estoqueHistorico.isNotEmpty ||
      _aberturasCaixa.isNotEmpty ||
      _fechamentosCaixa.isNotEmpty ||
      _sangrias.isNotEmpty ||
      _suprimentos.isNotEmpty;

  /// Versão exposta para os testes de regressão do modo offline.
  @visibleForTesting
  bool get cacheLocalTemDados => _cacheLocalTemDados;

  /// O sistema pode abrir as telas SEM esperar a nuvem?
  ///
  /// Desktop: sim, se o PostgreSQL local já atendeu (mesmo vazio — empresa nova)
  /// ou se já há dados em memória. Web: só com cache, porque não há Postgres.
  @visibleForTesting
  bool get deveLiberarTelaInicialSemNuvem {
    if (_cacheLocalTemDados) return true;
    if (kIsWeb) return false;
    return DatabaseService().bancoLocalAtendeu;
  }

  /// Abre o sistema quando o banco LOCAL já atendeu — sem esperar a nuvem.
  ///
  /// A carga da nuvem continua em segundo plano. Empresa nova (listas vazias)
  /// também libera: vazio local é um estado válido, não um motivo para travar
  /// na tela "Baixando os dados da nuvem".
  void _liberarTelaInicialSeCacheLocalTemDados() {
    if (!deveLiberarTelaInicialSemNuvem) return;
    if (!_sincronizandoInicial && !_isLoading) return;
    _sincronizandoInicial = false;
    _isLoading = false;
    debugPrint(
      '>>> [Sync] ⚡ Banco local pronto — abrindo o sistema agora '
      '(produtos=${_produtos.length}, clientes=${_clientes.length}, '
      'pedidos=${_pedidos.length}, atendeu=${DatabaseService().bancoLocalAtendeu}). '
      'A nuvem segue em segundo plano.',
    );
    addSyncLog(
      _cacheLocalTemDados
          ? '⚡ Sistema aberto com os dados do banco local; '
                'a sincronização da nuvem continua em segundo plano.'
          : '🖥️ Banco local respondeu (empresa ainda sem dados). '
                'Sistema aberto — a nuvem, se existir, espelha em segundo plano.',
    );
    notifyListeners();
  }

  /// Libera a tela de carregamento inicial sem esperar a nuvem terminar
  /// (a sincronização continua rodando em segundo plano).
  void pularEsperaSincronizacaoInicial() {
    if (!_sincronizandoInicial) return;
    _sincronizandoInicial = false;
    addSyncLog(
      '⚠️ Carregamento inicial liberado pelo usuário (sem esperar a nuvem)',
    );
    notifyListeners();
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
    if (_ultimaSincronizacaoSucesso == null)
      return 'Aguardando sincronização...';

    final agora = DateTime.now();
    final diferenca = agora.difference(_ultimaSincronizacaoSucesso!);

    if (diferenca.inSeconds < 60) return 'Atualizado agora';
    if (diferenca.inMinutes < 60)
      return 'Atualizado há ${diferenca.inMinutes} min';
    return 'Atualizado há ${diferenca.inHours} h';
  }

  /// Verifica e atualiza a quantidade de conflitos não resolvidos no PostgreSQL local
  Future<void> atualizarConflitosCount() async {
    if (kIsWeb) return;
    try {
      final conn = await DatabaseService().connection;
      final tableCheck = await conn.execute(
        "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'exodo_sync_conflitos')",
      );
      final exists = tableCheck.first.first as bool;
      if (exists) {
        final result = await conn.execute(
          "SELECT COUNT(*) FROM exodo_sync_conflitos WHERE resolvido = FALSE",
        );
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
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao atualizar contagem de conflitos: $e',
      );
    }
  }

  // ─── CONFLITOS DA SINCRONIZAÇÃO (duas máquinas, banco offline) ───────────
  //
  // O sincronizador (`sincronizar_local_supabase.py`) parqueia aqui toda linha
  // alterada nas DUAS máquinas sem internet. Enquanto o conflito está aberto, o
  // download pula esse id: a versão local continua sendo a que o usuário está
  // vendo. Estas rotinas são a parte que faltava — sem elas o conflito existia,
  // mas ninguém decidia, e a edição local ficava presa para sempre.

  /// Lê os conflitos ainda abertos (mais recentes primeiro).
  ///
  /// Devolve vazio (sem estourar) quando o sincronizador nunca criou a tabela:
  /// banco novo não tem conflito nenhum.
  Future<List<ConflitoSync>> listarConflitosPendentes() async {
    if (kIsWeb) return const [];
    try {
      final conn = await DatabaseService().connection;
      final resultado = await conn.execute(
        Sql.named(
          'SELECT id, tabela, registro_id, dados_locais, dados_nuvem, criado_em '
          'FROM exodo_sync_conflitos WHERE resolvido = FALSE '
          'ORDER BY criado_em DESC NULLS LAST',
        ),
      );
      return resultado
          .map((linha) => ConflitoSync.fromMap(linha.toColumnMap()))
          .where((c) => c.tabela.isNotEmpty && c.registroId.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint(
        '>>> [Conflito] ⚠️ Não consegui listar os conflitos pendentes: $e',
      );
      return const [];
    }
  }

  /// Resolve um conflito mantendo a SUA versão (a do banco local).
  ///
  /// Carimba a linha local com a data de agora e a deixa marcada como pendente,
  /// então o próximo ciclo do sincronizador a envia para a nuvem — "o meu vale".
  /// É por isso que a marcação de tempo importa: é ela que o sincronizador
  /// compara para saber qual das duas versões é a mais nova.
  Future<bool> resolverConflitoMantendoLocal(ConflitoSync conflito) async {
    if (kIsWeb) return false;
    try {
      final conn = await DatabaseService().connection;
      final tabela = _aspasSql(conflito.tabela);

      final colunas = await _colunasLocais(conn, conflito.tabela);
      if (!colunas.contains('id')) {
        debugPrint(
          '>>> [Conflito] ⚠️ ${conflito.tabela} não tem coluna id — impossível manter a versão local.',
        );
        return false;
      }

      // Carimba a data que o sincronizador usa como referência para esta tabela
      // (mesma ordem de preferência dele: updated_at, created_at, criado_em...).
      final carimbo = const [
        'updated_at',
        'created_at',
        'criado_em',
        'data_alteracao',
        'data_venda',
        'data',
      ].firstWhere((c) => colunas.contains(c), orElse: () => '');
      final sets = <String>[];
      if (carimbo.isNotEmpty) sets.add('"$carimbo" = NOW()');
      if (colunas.contains('_sincronizado_nuvem'))
        sets.add('_sincronizado_nuvem = FALSE');

      if (sets.isNotEmpty) {
        await conn.execute(
          Sql.named('UPDATE $tabela SET ${sets.join(', ')} WHERE id = @id'),
          parameters: {'id': conflito.registroId},
        );
      }

      // Garante que a alteração entre na fila de envio. O gatilho do banco já
      // registra o UPDATE enquanto o modo de sincronização está desligado, mas
      // se a tabela não tiver o gatilho a linha ficaria pendente sem ninguém
      // para enviá-la — então confirmamos e, se faltar, inserimos na mão.
      await _garantirPendenciaDeEnvio(
        conn,
        conflito.tabela,
        conflito.registroId,
      );
      await _marcarConflitoResolvido(conn, conflito.id);
      await atualizarConflitosCount();
      addSyncLog(
        '✓ Conflito de ${conflito.tabela}/${conflito.nomeDoRegistro} resolvido MANTENDO a versão local (vai ser enviada).',
      );
      return true;
    } catch (e) {
      debugPrint('>>> [Conflito] ⚠️ Erro ao manter a versão local: $e');
      return false;
    }
  }

  /// Resolve um conflito aceitando a versão da NUVEM (a do outro PC).
  ///
  /// Grava no banco local os campos como estão na nuvem — as duas versões foram
  /// guardadas justamente para esta hora, então nada precisa ser digitado de novo.
  Future<bool> resolverConflitoUsandoNuvem(ConflitoSync conflito) async {
    if (kIsWeb) return false;
    try {
      final conn = await DatabaseService().connection;
      final colunas = await _colunasLocais(conn, conflito.tabela);
      final daNuvem = <String, dynamic>{
        for (final entrada in conflito.dadosNuvem.entries)
          if (colunas.contains(entrada.key)) entrada.key: entrada.value,
      };
      daNuvem['id'] = conflito.registroId;

      final nomes = daNuvem.keys.toList();
      final valores = nomes.map((c) => '@${_nomeDeParametro(c)}').join(', ');
      final atualizacoes = nomes
          .where((c) => c != 'id')
          .map((c) => '"$c" = EXCLUDED."$c"')
          .join(', ');

      await conn.execute(
        Sql.named(
          'INSERT INTO ${_aspasSql(conflito.tabela)} (${nomes.map((c) => '"$c"').join(', ')}) '
          'VALUES ($valores) '
          '${atualizacoes.isEmpty ? 'ON CONFLICT DO NOTHING' : 'ON CONFLICT (id) DO UPDATE SET $atualizacoes'}',
        ),
        parameters: {for (final c in nomes) _nomeDeParametro(c): daNuvem[c]},
      );

      await _marcarConflitoResolvido(conn, conflito.id);
      await atualizarConflitosCount();
      addSyncLog(
        '✓ Conflito de ${conflito.tabela}/${conflito.nomeDoRegistro} resolvido usando a versão da NUVEM.',
      );
      return true;
    } catch (e) {
      debugPrint('>>> [Conflito] ⚠️ Erro ao usar a versão da nuvem: $e');
      return false;
    }
  }

  Future<void> _marcarConflitoResolvido(Session conn, String id) async {
    await conn.execute(
      Sql.named(
        'UPDATE exodo_sync_conflitos SET resolvido = TRUE WHERE id = @id',
      ),
      parameters: {'id': id},
    );
  }

  /// Garante uma linha na fila de envio (`_exodo_sync_log`) para o registro.
  Future<void> _garantirPendenciaDeEnvio(
    Session conn,
    String tabela,
    String registroId,
  ) async {
    try {
      final existe = await conn.execute(
        Sql.named(
          "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' "
          "AND table_name = '_exodo_sync_log')",
        ),
      );
      if (existe.first.first != true) return;

      await conn.execute(
        Sql.named(
          'INSERT INTO _exodo_sync_log (table_name, record_id, operation) VALUES (@t, @r, \'UPDATE\') '
          'ON CONFLICT (table_name, record_id) DO UPDATE SET operation = \'UPDATE\', created_at = NOW()',
        ),
        parameters: {'t': tabela, 'r': registroId},
      );
    } catch (e) {
      // O gatilho do banco normalmente já fez isso; falhar aqui não invalida a
      // decisão do usuário (o envio direto do app continua valendo).
      debugPrint(
        '>>> [Conflito] ℹ️ Não consegui confirmar a fila de envio ($tabela/$registroId): $e',
      );
    }
  }

  Future<Set<String>> _colunasLocais(Session conn, String tabela) async {
    final res = await conn.execute(
      Sql.named(
        'SELECT column_name FROM information_schema.columns '
        "WHERE table_schema = 'public' AND table_name = @t",
      ),
      parameters: {'t': tabela},
    );
    return res
        .map((linha) => linha.toColumnMap()['column_name'].toString())
        .toSet();
  }

  static String _aspasSql(String nome) => '"${nome.replaceAll('"', '""')}"';

  /// Nome de parâmetro válido para o SQL nomeado (o nome da coluna pode ter
  /// ponto/acento — o driver só aceita letras, números e _).
  static String _nomeDeParametro(String coluna) =>
      'c_${coluna.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}';

  /// Marca todos os conflitos da tabela exodo_sync_conflitos como resolvidos
  Future<void> resolverTodosConflitos() async {
    if (kIsWeb) return;
    try {
      final conn = await DatabaseService().connection;
      await conn.execute(
        "UPDATE exodo_sync_conflitos SET resolvido = TRUE WHERE resolvido = FALSE",
      );
      await atualizarConflitosCount();
      addSyncLog("✓ Conflitos resolvidos manualmente pelo usuário.");
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao resolver conflitos: $e');
    }
  }

  /// Define a empresa atual e recarrega os dados
  /// [modoLeve]: Se true, carrega apenas dados essenciais (otimizado para loja pública)
  Future<void> definirEmpresaAtual(
    String? empresaId, {
    bool modoLeve = false,
  }) async {
    // Se a empresa for a mesma, mas mudamos de modoLeve para modoFull, precisamos recarregar
    if (_currentEmpresaId == empresaId && empresaId != null) {
      if (_isModoLeve && !modoLeve) {
        debugPrint(
          '>>> [DataService] ⚡ Upgrade: modoLeve -> Full sync (empresa: $empresaId)',
        );
        _isModoLeve = false;
        await iniciarSincronizacao(modoLeve: false, cargaInicial: true);
        return;
      }
      debugPrint(
        '>>> [DataService] ℹ️ Empresa já definida: $empresaId (Leve: $_isModoLeve)',
      );
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

    // Linhas pendentes do caminho rápido (gravação linha a linha) pertencem à
    // empresa que está sendo trocada: gravá-las AGORA, com `_currentEmpresaId`
    // e `DatabaseService` ainda na empresa antiga. Se sobrarem para depois da
    // troca, o carimbo de empresa (feito na hora da gravação) as adotaria pela
    // empresa nova — é assim que lançamento de uma empresa parava na outra.
    if (_currentEmpresaId != null && _temLinhasLocaisPendentes) {
      try {
        await _executarFlushLinhasLocais();
      } catch (e) {
        print(
          '>>> DataService: ⚠️ Erro ao gravar linhas pendentes da empresa anterior: $e',
        );
        // Falhou: as coleções já foram marcadas como sujas e o _salvarTodosDados
        // abaixo reescreve a tabela inteira da empresa antiga como rede de segurança.
      }
    }

    // Salvar dados da empresa anterior ANTES de trocar (se houver empresa anterior)
    if (_currentEmpresaId != null) {
      print(
        '>>> DataService: Salvando dados da empresa anterior antes de trocar...',
      );
      try {
        await _salvarTodosDados();
        print(
          '>>> DataService: ✓ Dados da empresa anterior salvos com sucesso',
        );
      } catch (e) {
        print(
          '>>> DataService: ⚠️ Erro ao salvar dados da empresa anterior: $e',
        );
        // Continua mesmo se falhar - dados já estão no localStorage
      }
    }

    // ISOLAMENTO: Limpar dados da empresa anterior da MEMÓRIA (não do localStorage/Supabase)
    // Isso garante que cada empresa carregue apenas seus próprios dados
    print(
      '>>> DataService: 🧹 Limpando dados da empresa anterior da memória...',
    );
    print(
      '>>> DataService: ⚠️ Os dados permanecem salvos no localStorage/Supabase',
    );
    // Resetar Paginação
    _temMaisClientes = true;
    _temMaisVendas = true;

    _clientes.clear();
    _produtos.clear();
    _tiposServico.clear();
    _pedidos.clear();
    // Serviços realizados (SRV-) e orçamentos (ORC-) também são POR EMPRESA:
    // sem estes dois clears, a empresa nova herdava os lançamentos da anterior
    // — o orçamento lançado na BMJ aparecia na Exodo Systems. A carga só
    // substitui a lista quando a nova empresa TEM registros (guards
    // `if (...Map.isNotEmpty)`), então empresa "vazia" mantém o que sobrou.
    _servicosRealizados.clear();
    _orcamentos.clear();
    _ordensServico.clear();
    _entregas.clear();
    _motoristas.clear();
    _vendasBalcao.clear();
    _trocasDevolucoes.clear();
    _estoqueHistorico.clear();
    _ajustesEstoqueLote.clear();
    _lotesProdutos.clear();
    _notasEntrada.clear();
    _pedidosCompra.clear();
    _agendamentosServico.clear();
    _funcionarios.clear();
    _taxasEntrega.clear();
    _contasPagar.clear();
    _aberturasCaixa.clear();
    _fechamentosCaixa.clear();
    _sangrias.clear();
    _suprimentos.clear();
    _nfces.clear();
    _nfes.clear();
    _mesasComandas.clear();
    _linksVendedores.clear();
    _comissoesVendedores.clear();
    _romaneios.clear();
    _perfisTributarios.clear();
    _departamentos.clear();
    _estoques.clear();
    _syncLogs.clear(); // Limpar logs da empresa anterior
    print(
      '>>> DataService: ✓ Memória limpa - pronta para carregar dados da nova empresa',
    );

    // DEFINIR NOVA EMPRESA
    _currentEmpresaId = empresaId;
    _syncQueue.setPaused(empresaId == null || !nuvemHabilitada);
    _ultimaSincronizacao =
        null; // Resetar para que a nova empresa tenha sua própria sincronização
    _ultimaSincronizacaoSucesso = null;

    // Controles de backup são POR EMPRESA: zerar e recarregar para a nova empresa,
    // senão ela herdaria o horário do último backup da empresa anterior e ficaria
    // até 24h sem backup automático (local e nuvem).
    _ultimoBackupDiario = null;
    _ultimoBackupNuvem = null;
    await _carregarUltimoBackupDiario();
    await _carregarUltimoBackupNuvem();

    // Os mínimos de numeração (VND/PED) também são POR EMPRESA: sem recarregar,
    // a empresa nova herdava o mínimo da anterior e a venda saía com o número da
    // outra empresa (ex.: a Exodo Systems lançou 408 porque o mínimo estava em 407).
    await carregarMinimosNumeracao();

    // Carregar logs específicos da nova empresa do PostgreSQL
    if (empresaId != null) {
      try {
        if (!kIsWeb) {
          final loadedLogs = await DatabaseService().carregarSyncLogs(
            empresaId,
          );
          _syncLogs.addAll(loadedLogs);
        } else {
          final loadedLogs = await _storage.carregar(
            'empresa_${empresaId}_sync_logs',
          );
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
        _empresaAtual =
            null; // Limpar para evitar dados obsoletos apenas se for realmente outra empresa
      }

      // Recarregar dados APENAS da nova empresa (isoladamente)
      // cargaInicial: true -> enquanto os dados não chegam, o app mantém a tela
      // de carregando (não abre as telas com o sistema vazio).
      try {
        await iniciarSincronizacao(
          modoLeve: modoLeve,
          cargaInicial: true,
        ).timeout(const Duration(minutes: 2));
      } catch (e) {
        print('>>> DataService: ⚠️ Erro durante iniciarSincronizacao: $e');
        // Continuamos para garantir que _isLoading = false seja chamado
      }

      // ✅ REALTIME: Ativar escuta WebSocket para sincronização multi-PC
      if (empresaId != null && !modoLeve && nuvemHabilitada) {
        _realtimeSync
            .iniciar(
              empresaId,
              callback: _aplicarMudancaRealtime,
              aoMudarNaNuvem: _aoMudarPelaNuvem,
            )
            .catchError((e) {
              debugPrint(
                '>>> [Realtime] ⚠️ Erro ao iniciar Realtime (não bloqueante): $e',
              );
            });
      } else if (!nuvemHabilitada) {
        unawaited(_realtimeSync.parar());
      }

      // ✅ LAN EM TEMPO REAL: independente da nuvem. O sincronizador da rede
      // local grava no PostgreSQL deste PC e avisa por pg_notify; aqui a tela
      // é recarregada na hora (é o caminho que sustenta a loja sem internet).
      if (!modoLeve && !kIsWeb) {
        _lanRealtime.iniciar(callback: _aoMudarPelaRedeLocal).catchError((e) {
          debugPrint(
            '>>> [LAN-Realtime] ⚠️ Erro ao iniciar (não bloqueante): $e',
          );
        });
      }

      // FILA DE PRODUÇÃO: as vias que não saíram na impressora do setor ficam
      // guardadas NESTA MÁQUINA (a impressora é local), então a fila é
      // carregada por empresa para o Monitor de Produção.
      try {
        FilaProducaoService.instancia.initialize(empresaId: empresaId);
      } catch (e) {
        debugPrint('>>> [FilaProducao] ⚠️ Erro ao iniciar a fila: $e');
      }

      // ✅ SYNC MONITOR: Inicializar monitoramento de sincronizacao
      // Chamado a cada troca de empresa para o heartbeat apontar sempre para a
      // empresa aberta no momento (o timer em si é criado uma única vez).
      if (!kIsWeb) {
        try {
          final pcName = Platform.localHostname;
          SyncMonitorService.instance.initialize(
            empresaId: empresaId,
            pcName: pcName,
          );
          if (!_syncMonitorInitialized) {
            _syncMonitorInitialized = true;
            SyncMonitorService.instance.registrarEvento(
              empresaId: empresaId,
              evento: 'inicio_sync',
              detalhes: 'Sessao iniciada no PC: $pcName',
            );
          }
          debugPrint(
            '>>> [SyncMonitor] ✅ Monitoramento de sync iniciado para empresa $empresaId',
          );
        } catch (e) {
          debugPrint('>>> [SyncMonitor] ⚠️ Erro ao iniciar monitor: $e');
        }
      }
    } else {
      debugPrint(
        '>>> [DataService] ℹ️ Aguardando login: empresa ainda não definida.',
      );
    }

    // Finalizar loading
    _isLoading = false;
    // Sem empresa definida (logout/saída da empresa) não há carga de nuvem
    // pendente que justifique segurar o usuário na tela de carregando.
    if (empresaId == null) {
      _sincronizandoInicial = false;
    }
    notifyListeners();
    print('>>> DataService: ✓ Troca de empresa concluída - dados isolados');

    // Web: retomar o pulso assim que a aba/janela voltar a ficar visível.
    //
    // Antes usávamos apenas `onWindowFocus`, que NÃO dispara ao trocar de aba.
    // Como o navegador estrangula timers de páginas escondidas (~1×/minuto), a
    // alteração feita no app Windows demorava até 1 minuto para aparecer no
    // portal. Agora escutamos `visibilitychange` + `pageshow` + `focus` e
    // puxamos o delta imediatamente ao voltar.
    if (kIsWeb) {
      try {
        _windowFocusSubscription?.cancel();
        _windowFocusSubscription = html_helper.onWindowFocus.listen(
          (_) => _aoVoltarParaPaginaWeb(),
          onError: (e) {
            debugPrint('>>> [SISTEMA] Erro no stream de foco: $e');
          },
        );

        _windowVisibleSubscription?.cancel();
        _windowVisibleSubscription = html_helper.onWindowVisible.listen(
          (_) => _aoVoltarParaPaginaWeb(),
          onError: (e) {
            debugPrint('>>> [SISTEMA] Erro no stream de visibilidade: $e');
          },
        );
      } catch (e) {
        debugPrint('>>> [SISTEMA] Erro ao registrar listener de foco: $e');
      }
    }
  }

  Future<void> _sincronizarSilenciosamente({Set<String>? tabelas}) async {
    if (_currentEmpresaId == null) return;

    try {
      // BANCO LOCAL PRIMEIRO — inclusive OFFLINE.
      //
      // O ciclo da nuvem sai na hora quando o aparelho está sem internet (ou
      // quando o banco local falhou na abertura), então sem esta releitura o
      // sistema NUNCA mais olhava o banco do computador depois da abertura: se
      // a primeira leitura falhou (serviço parado, timeout, senha), as telas
      // ficavam só com os dados da nuvem e o banco local só voltava no botão
      // "Recarregar dados locais" na mão — era isso que deixava o usuário
      // refém da nuvem. Com a releitura automática, assim que o PostgreSQL
      // local responde os dados dele voltam sozinhos para as telas.
      if (DatabaseService().bancoLocalFalhou || !_cacheLocalTemDados) {
        debugPrint(
          '>>> [Sync] 🔁 Banco local falhou/está vazio — relendo o '
          'banco do computador...',
        );
        await _carregarDadosSalvos();
        notifyListeners();
      }

      debugPrint(
        '>>> [Sync] 🔄 Sincronização silenciosa em andamento'
        '${tabelas == null || tabelas.isEmpty ? '' : ' (${tabelas.join(', ')})'}...',
      );
      if (SupabaseService.isAvailable && !_isOffline) {
        await _carregarDadosDoSupabase(tabelas: tabelas);
        notifyListeners();
        debugPrint('>>> [Sync] ✅ Sincronização silenciosa concluída');
      } else {
        debugPrint('>>> [Sync] 🖥️ Sem nuvem — pulso só relê o banco local.');
      }
    } catch (e) {
      debugPrint('>>> [Sync] ⚠ Erro na sincronização silenciosa: $e');
    }
  }

  /// Obtém a chave de armazenamento com prefixo da empresa
  String _getChaveComEmpresa(String chaveBase) {
    final empresaId = _currentEmpresaId;
    if (empresaId == null || empresaId.isEmpty) {
      return 'empresa_desconhecida_$chaveBase';
    }
    return 'empresa_${empresaId}_$chaveBase';
  }

  /// Método público para forçar atualização dos listeners
  void forceUpdate() {
    debugPrint(
      '>>> DataService.forceUpdate() chamado - instanceId: $_instanceId',
    );
    notifyListeners();
  }

  /// Relê o BANCO LOCAL (PostgreSQL deste computador) para a memória.
  ///
  /// É o que o botão "Recarregar dados locais" precisa fazer: com a empresa já
  /// definida, `definirEmpresaAtual` sai na hora (otimização para não recarregar
  /// a cada chamada) e o botão não recarregava NADA — parecia que o banco local
  /// estava vazio.
  ///
  /// Devolve (produtos lidos, aviso). `aviso` só vem preenchido quando o banco
  /// local NÃO respondeu, com o motivo em português — é o que a tela mostra para
  /// o usuário saber que o problema é a leitura do banco (e não "não tem dados").
  Future<(int, String?)> recarregarDoBancoLocal() async {
    if (_currentEmpresaId == null || _currentEmpresaId!.isEmpty) {
      return (0, 'Nenhuma empresa selecionada.');
    }
    DatabaseService().limparFalhaDoBancoLocal();
    _mensagemLoading = 'Lendo o banco local...';
    notifyListeners();

    await _carregarDadosSalvos();
    notifyListeners();

    final String? aviso = DatabaseService().bancoLocalFalhou
        ? DatabaseService.dicaDoErroLocal(
            DatabaseService().ultimoErroDoBancoLocal,
          )
        : null;
    addSyncLog(
      aviso == null
          ? '✅ Banco local relido: ${_produtos.length} produtos, '
                '${_clientes.length} clientes.'
          : '⚠️ Não consegui ler o banco local. $aviso',
    );
    return (_produtos.length, aviso);
  }

  /// Método público para recarregar dados manualmente
  /// Mostra loading durante o carregamento
  Future<void> recarregarDados({bool modoLeve = false}) async {
    if (_currentEmpresaId == null) {
      debugPrint(
        '>>> [DataService] ℹ️ Recarga ignorada: empresa não definida.',
      );
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
    _syncQueue.setOperationGate(
      (empresaId) =>
          empresaId != null &&
          empresaId == _currentEmpresaId &&
          nuvemHabilitada,
    );
    _syncQueue.setResolver(_resolverOperacaoSync);
  }

  void _initConnectivity() {
    try {
      Connectivity().onConnectivityChanged.listen((
        List<ConnectivityResult> results,
      ) async {
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
          final msg = _isOffline
              ? "⏸️ Nuvem pausada. Você continua trabalhando normalmente — tudo é salvo aqui e sincroniza quando a nuvem voltar."
              : "🌐 Nuvem online. Sincronização retomada.";
          addSyncLog(msg);
          ConnectionLoggerService.log(msg);
          notifyListeners();

          if (conexaoVoltou) {
            final reconnectMsg =
                "📡 Nuvem voltou! Sincronizando automaticamente o que ficou pendente...";
            addSyncLog(reconnectMsg);
            ConnectionLoggerService.log(reconnectMsg);
            // Nuvem voltou: retoma também a fila de escrita pendente.
            _syncQueue.onConnectionRestored();
            Future.microtask(() async {
              try {
                await iniciarSincronizacao(modoLeve: false);
              } catch (e) {
                addSyncLog("⚠️ Erro no auto-sync pós-reconexão: $e");
                ConnectionLoggerService.log(
                  "⚠️ Erro no auto-sync pós-reconexão: $e",
                );
              }
            });
          }
        }
      });

      Connectivity().checkConnectivity().then((
        List<ConnectivityResult> results,
      ) async {
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
          final msg = _isOffline
              ? "🔌 Conectividade alterada para Offline"
              : "🌐 Conectividade alterada para Online";
          ConnectionLoggerService.log(msg);
        }
        notifyListeners();
      });
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao iniciar monitoramento de conectividade: $e',
      );
      ConnectionLoggerService.log(
        '⚠️ Erro ao iniciar monitoramento de conectividade: $e',
      );
      // Se falhar, assumir online para não bloquear o sistema
      _isOffline = false;
      notifyListeners();
    }

    // Forçar verificação inicial de conectividade
    _verificarConexaoReal().then((isOnline) {
      if (_isOffline != !isOnline) {
        _isOffline = !isOnline;
        final msg =
            'Status da conexão inicial verificado: Offline = $_isOffline';
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
      final delay = _isOffline
          ? const Duration(seconds: 30)
          : const Duration(minutes: 5);
      _checkConnectivityTimer = Timer(delay, () async {
        try {
          final isOnline = await _verificarConexaoReal();
          final offline = !isOnline;

          if (_isOffline != offline) {
            final conexaoVoltou = _isOffline && !offline;
            _isOffline = offline;
            final msg = _isOffline
                ? "⏸️ Nuvem pausada. Você continua trabalhando normalmente — tudo é salvo aqui e sincroniza quando a nuvem voltar."
                : "🌐 Nuvem online. Sincronização retomada.";
            addSyncLog(msg);
            ConnectionLoggerService.log(msg);
            notifyListeners();

            if (conexaoVoltou) {
              final reconnectMsg =
                  "📡 Nuvem voltou! Sincronizando automaticamente o que ficou pendente...";
              addSyncLog(reconnectMsg);
              ConnectionLoggerService.log(reconnectMsg);
              // Nuvem voltou: retoma também a fila de escrita pendente.
              _syncQueue.onConnectionRestored();
              Future.microtask(() async {
                try {
                  await iniciarSincronizacao(modoLeve: false);
                } catch (e) {
                  addSyncLog("⚠️ Erro no auto-sync pós-reconexão: $e");
                  ConnectionLoggerService.log(
                    "⚠️ Erro no auto-sync pós-reconexão: $e",
                  );
                }
              });
            }
          }
        } catch (e) {
          debugPrint(
            '>>> [DataService] [Timer] ⚠️ Erro no timer de conectividade: $e',
          );
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
          final result = await InternetAddress.lookup(
            'google.com',
          ).timeout(const Duration(seconds: 2));
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            temInternetGeral = true;
          }
        } catch (_) {
          // Tentar um fallback rápido
          try {
            final result = await InternetAddress.lookup(
              'cloudflare.com',
            ).timeout(const Duration(seconds: 2));
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

      // Circuit breaker: nuvem já marcada indisponível (PGRST002/503/504).
      // Não gasta 4s no ping — assume offline até o cooldown expirar.
      if (SupabaseService.instance.servidorIndisponivel) {
        _consecutiveConnectionFailures++;
        return false;
      }

      // Ping simples no Supabase
      await SupabaseService.instance.client
          .from('empresas')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 4));

      _consecutiveConnectionFailures =
          0; // Resetar contador ao obter sucesso real
      return true; // Tudo perfeito
    } catch (e) {
      final errorStr = e.toString().toLowerCase();

      // 1) NUVEM INDISPONÍVEL (PGRST002 "schema cache" / 503 / 504 / timeouts):
      //    é o SERVIDOR fora, não um erro de dados. Antes o "schema cache" caía
      //    no ramo de erro de schema e o app se declarava ONLINE — continuando a
      //    martelar a nuvem durante a queda.
      if (SupabaseService.isErroInfraestrutura(e)) {
        _consecutiveConnectionFailures++;
        // Aciona o circuit breaker para o resto do app parar de tentar a nuvem
        // durante o cooldown (antes só a queda por PGRST002/503/504 fazia isso
        // e a cota estourada — 402 — continuava gerando uma tempestade de logs).
        SupabaseService.instance.registrarFalhaInfra(e);
        return false;
      }

      // 2) Erro de esquema/coluna de DADOS (PGRST204): não indica falta de
      //    conexão — assumir online para não pausar a sincronização.
      if (errorStr.contains('pgrst204') || errorStr.contains('column')) {
        _consecutiveConnectionFailures = 0;
        return true;
      }

      // 3) Se a internet geral estava ativa e falhou apenas o ping do Supabase,
      //    pode ser instabilidade temporária. Toleramos por até 4 tentativas.
      _consecutiveConnectionFailures++;
      if (_consecutiveConnectionFailures >= 4) {
        debugPrint(
          '>>> [DataService] ⚠️ Falhas consecutivas de ping no Supabase atingiram o limite: $e',
        );
        return false;
      }

      debugPrint(
        '>>> [DataService] ⚠️ Ping no Supabase falhou temporariamente (falha $_consecutiveConnectionFailures/4): $e',
      );
      return !_isOffline; // Mantém o estado anterior para evitar alarmes falsos
    }
  }

  /// [cargaInicial] deve ser true apenas na ABERTURA do sistema (troca/seleção
  /// de empresa). No desktop a tela de carregando SAI quando o PostgreSQL local
  /// responde — a nuvem nunca segura a abertura. O limite de segurança só vale
  /// se o banco local falhou e a nuvem ainda está sendo tentada como fallback.
  Future<void> iniciarSincronizacao({
    bool modoLeve = false,
    bool cargaInicial = false,
  }) async {
    // Atualizar mensagem de loading
    if (_isLoading) {
      _mensagemLoading = cargaInicial
          ? 'Abrindo o sistema — lendo o banco local...'
          : 'Sincronizando dados...';
      notifyListeners();
    }

    if (cargaInicial) {
      _sincronizandoInicial = true;
      _mensagemLoading = 'Abrindo o sistema — lendo o banco local...';
      notifyListeners();

      // Rede de segurança: nunca deixa o sistema preso na tela de carregando.
      Future.delayed(_limiteEsperaNuvemInicial).then((_) {
        if (_sincronizandoInicial) {
          _sincronizandoInicial = false;
          addSyncLog(
            '⚠️ Limite de espera da carga inicial atingido: '
            'abrindo o sistema com os dados locais (a nuvem continua em segundo plano)',
          );
          notifyListeners();
        }
      });
    }

    print('╔════════════════════════════════════════════════╗');
    print('║  INICIANDO CARREGAMENTO DE DADOS              ║');
    print('╚════════════════════════════════════════════════╝');

    // 1. BANCO LOCAL PRIMEIRO — é o sistema. A nuvem é espelho.
    try {
      if (_isLoading) {
        _mensagemLoading = 'Lendo o banco de dados do computador...';
        notifyListeners();
      }
      await _carregarDadosSalvos();
      print('>>> ✓ Cache local carregado (${_clientes.length} clientes)');
      _notificarProgressoLoading();

      // BANCO LOCAL QUE NÃO ATENDEU: quando a leitura do PostgreSQL local falha
      // (conexão recusada, timeout ou senha recusada) ela responde LISTA VAZIA —
      // indistinguível de "não tem dados". Aqui a leitura é repetida UMA vez
      // antes de desistir do banco local.
      if (cargaInicial &&
          !_cacheLocalTemDados &&
          DatabaseService().bancoLocalFalhou) {
        addSyncLog(
          '⚠️ Banco local não atendeu a primeira leitura. '
          '${DatabaseService.dicaDoErroLocal(DatabaseService().ultimoErroDoBancoLocal)} '
          'Tentando de novo...',
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await _carregarDadosSalvos();
        if (DatabaseService().bancoLocalAtendeu) {
          addSyncLog(
            '✅ Banco local respondeu na segunda tentativa: o sistema '
            'abre com os dados do computador (a nuvem segue em segundo plano).',
          );
        } else {
          addSyncLog(
            '⚠️ O banco local continua sem responder. '
            'Verifique o serviço PostgreSQL e o .env. '
            'A nuvem, se existir, será tentada em segundo plano.',
          );
        }
      }

      // DETECÇÃO DE BANCO INCOMPLETO: Se o banco local foi perdido (desinstalação,
      // corrupção, etc.) mas o timestamp de última sync ainda existe no exodo_config,
      // o delta sync puxaria apenas registros recentes. Forçar sync full quando
      // as coleções críticas estiverem vazias.
      if (_ultimaSincronizacaoSucesso != null) {
        final int totalLocal =
            _produtos.length + _clientes.length + _pedidos.length;
        if (totalLocal == 0) {
          debugPrint(
            '>>> [Sync] ⚠️ Banco local INCOMPLETO (produtos=0, clientes=0, pedidos=0) mas timestamp de sync antigo existe. Resetando para FULL SYNC...',
          );
          _ultimaSincronizacaoSucesso = null;
        } else if (_produtos.isEmpty || _clientes.isEmpty || _pedidos.isEmpty) {
          final int vazios =
              (_produtos.isEmpty ? 1 : 0) +
              (_clientes.isEmpty ? 1 : 0) +
              (_pedidos.isEmpty ? 1 : 0);
          debugPrint(
            '>>> [Sync] ⚠️ Coleções incompletas ($vazios vazias: produtos=${_produtos.length}, clientes=${_clientes.length}, pedidos=${_pedidos.length}). Resetando delta para FULL SYNC...',
          );
          _ultimaSincronizacaoSucesso = null;
        }
      }

      // ⚡ ABERTURA IMEDIATA: Postgres atendeu (mesmo vazio) → telas abrem.
      if (cargaInicial) {
        _liberarTelaInicialSeCacheLocalTemDados();
      }

      // ── ESPELHO DA NUVEM (nunca bloqueia a abertura) ────────────────────
      if (_currentEmpresaId != null && SupabaseService.isAvailable) {
        final nuvemDisponivel = _isOffline
            ? false
            : await _verificarConexaoReal();
        if (nuvemDisponivel) {
          debugPrint(
            '>>> [Supabase] 📡 Espelhando a nuvem em segundo plano...',
          );
          _carregarDadosDoSupabase(modoLeve: modoLeve)
              .then((_) {
                migrarPedidosSemNumero();
                debugPrint(
                  '>>> [Supabase] 📡 Carga de dados em nuvem concluída (background)',
                );
              })
              .catchError((e) {
                debugPrint('>>> [Supabase] ⚠️ Erro na carga em background: $e');
              })
              .whenComplete(() {
                if (_sincronizandoInicial) {
                  _sincronizandoInicial = false;
                  notifyListeners();
                }
              });
        } else {
          if (!_isOffline) {
            _isOffline = true;
            addSyncLog(
              '🔌 Nuvem inacessível — operando somente com banco local.',
            );
            debugPrint(
              '>>> [DataService] 🔌 Nuvem não respondeu ao ping — modo local ativo.',
            );
          }
          if (cargaInicial && _sincronizandoInicial) {
            _sincronizandoInicial = false;
            addSyncLog('🖥️ Operando com banco local (nuvem indisponível).');
            notifyListeners();
          }
        }
      }

      notifyListeners();
    } catch (e) {
      print('>>> ⚠ Erro ao carregar cache local: $e');
      if (cargaInicial && _sincronizandoInicial) {
        _sincronizandoInicial = false;
        notifyListeners();
      }
    }

    if (!SupabaseService.isAvailable || _isOffline) {
      print('>>> 🔵 Modo local: Supabase indisponível ou offline.');
      if (_sincronizandoInicial) {
        _sincronizandoInicial = false;
        addSyncLog('🖥️ Operando com banco local (sem nuvem disponível).');
        notifyListeners();
      }
    }

    // Iniciar o timer de pulso para manter máquinas sincronizadas (essencial para PDV multi-terminal)
    iniciarAutoSync();

    // Se não houver dados salvos (nem Supabase nem local), carregar dados fictícios
    // APENAS para a empresa padrão (ID "1"). Empresas novas começam vazias.
    //
    // DADOS FICTÍCIOS (demonstração): só entram se a build for feita com
    // `--dart-define=EXODO_DEMO=true`. Em build normal `isEmpresaPadrao` é
    // sempre false e nada é semeado.
    //
    // ⚠️ POR QUE ISTO FICOU BLOQUEADO: quando o app iniciava sem empresa
    // selecionada, este trecho inseria 15 produtos de demonstração de FERRAGEM
    // (ids '1'..'15', códigos COD-1..COD-15, "Parafuso Phillips 4x40mm",
    // "Martelo Unha 27mm"...) e 8 clientes fictícios em memória e chamava
    // _salvarTodosDados() — que gravava no PostgreSQL local usando o empresa_id
    // que ainda estava carregado da empresa anterior e subia para a NUVEM.
    // Foi assim que produtos de demonstração apareceram dentro da empresa BMJ,
    // colidindo com os códigos COD-1..COD-15 que o catálogo real já usava.
    // Nunca liberar isto em produção.
    const bool semearDadosDemo = bool.fromEnvironment('EXODO_DEMO');
    final isEmpresaPadrao =
        semearDadosDemo &&
        (_currentEmpresaId == '1' || _currentEmpresaId == null);

    if (isEmpresaPadrao) {
      // Apenas a empresa padrão carrega dados fictícios
      if (_produtos.isEmpty) {
        print(
          '>>> ⚠ Nenhum produto encontrado. Carregando dados fictícios (empresa padrão)...',
        );
        _carregarProdutosFicticios();
        // Salvar no Supabase e localStorage
        _salvarTodosDados().catchError((e) {
          print('>>> ⚠ Erro ao salvar dados fictícios: $e');
        });
      }

      if (_clientes.isEmpty) {
        print(
          '>>> ⚠ Nenhum cliente encontrado. Carregando dados fictícios (empresa padrão)...',
        );
        _carregarClientesFicticios();
        // Salvar no Supabase e localStorage
        _salvarTodosDados().catchError((e) {
          print('>>> ⚠ Erro ao salvar dados fictícios: $e');
        });
      }

      if (_motoristas.isEmpty) {
        print(
          '>>> ⚠ Nenhum motorista encontrado. Carregando dados fictícios (empresa padrão)...',
        );
        _carregarMotoristasFicticios();
        // Salvar no Supabase e localStorage
        _salvarTodosDados().catchError((e) {
          print('>>> ⚠ Erro ao salvar dados fictícios: $e');
        });
      }
    } else {
      // Empresas novas começam vazias - não carregam dados fictícios
      print(
        '>>> Empresa nova (ID: $currentEmpresaId) - não carregando dados fictícios',
      );
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
    print(
      '>>> Persistência: ${_persistenciaHabilitada ? "HABILITADA" : "DESABILITADA"}',
    );

    print('>>> ${_agendamentosServico.length} agendamentos carregados');
    print(
      '>>> Persistência: ${_persistenciaHabilitada ? "HABILITADA" : "DESABILITADA"}',
    );
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
  Future<AberturaCaixa> abrirCaixaComValor(
    double valorInicial, {
    String? observacao,
    String? responsavel,
  }) async {
    try {
      // Se o usuário (responsável) já tiver um caixa aberto, retorna o dele.
      // Cada usuário da empresa pode ter o SEU próprio caixa aberto.
      // Fallback para o email do usuário logado garante que a abertura seja
      // gravada com o responsável correto (persiste após reiniciar).
      final respEfetivo =
          responsavel ?? _responsavelAtivo ?? _usuarioAtualEmail;
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
      // GRAVAÇÃO LOCAL POR REGISTRO: só esta abertura vai ao PostgreSQL agora,
      // sem reescrever as tabelas de abertura/fechamento inteiras.
      _persistirLinhaLocal(
        LocalStorageService.keyAberturasCaixa,
        abertura.toMap(),
      );

      // Sincronizar com Supabase
      debugPrint('>>> [Caixa] ☁️ Sincronizando abertura com Supabase...');
      debugPrint('>>> [Caixa]    ID: ${abertura.id}');
      debugPrint(
        '>>> [Caixa]    Supabase disponível: ${SupabaseService.isAvailable}',
      );
      unawaited(
        _upsertNoSupabase(
          SupabaseService.tableAberturasCaixa,
          abertura.toMap(),
        ),
      );

      notifyListeners();
      print(
        '>>> Caixa ${numeroCaixa} aberto com R\$ ${valorInicial.toStringAsFixed(2)}',
      );
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

    print(
      '>>> [registrarFechamentoCaixa] Abertura encontrada: ${aberturaUsada.numero}',
    );

    final diff = diferenca ?? (valorReal - valorEsperado);
    print('>>> [registrarFechamentoCaixa] Diferença calculada: $diff');

    // Obter sangrias e suprimentos do caixa em questão
    final sangriasCaixaAtual = getSangriasDoCaixa(aberturaUsada);
    final suprimentosCaixaAtual = getSuprimentosDoCaixa(aberturaUsada);

    print(
      '>>> [registrarFechamentoCaixa] Sangrias: ${sangriasCaixaAtual.length}',
    );
    print(
      '>>> [registrarFechamentoCaixa] Suprimentos: ${suprimentosCaixaAtual.length}',
    );

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
    // GRAVAÇÃO LOCAL POR REGISTRO: só este fechamento vai ao PostgreSQL agora.
    _persistirLinhaLocal(
      LocalStorageService.keyFechamentosCaixa,
      fechamento.toMap(),
    );

    // Nuvem: o fechamento precisa subir (antes isso ficava dentro do método
    // que reescrevia a tabela inteira).
    unawaited(
      _upsertNoSupabase(
        SupabaseService.tableFechamentosCaixa,
        fechamento.toMap(),
      ),
    );

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
  ///
  /// [aberturaParam] permite lançar a sangria em um caixa específico (ex.: o
  /// gestor lançando no caixa de outro operador pela visão "juntar caixas");
  /// sem ele, vale o caixa aberto do usuário atual.
  Future<SangriaCaixa> registrarSangria({
    required double valor,
    required String motivo,
    String? observacao,
    String? responsavel,
    AberturaCaixa? aberturaParam,
  }) async {
    final abertura = aberturaParam ?? aberturaCaixaAtual;
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
      responsavel: responsavel ?? abertura.responsavel ?? _responsavelAtivo,
    );

    _sangrias.add(sangria);
    // GRAVAÇÃO LOCAL POR REGISTRO: só esta sangria vai ao PostgreSQL agora.
    _persistirLinhaLocal(LocalStorageService.keySangrias, sangria.toMap());

    unawaited(
      _upsertNoSupabase(SupabaseService.tableSangrias, sangria.toMap()),
    );

    notifyListeners();
    print('>>> Sangria registrada: R\$ ${valor.toStringAsFixed(2)} - $motivo');
    return sangria;
  }

  /// Registra um suprimento do caixa atual
  ///
  /// [aberturaParam] permite lançar o suprimento em um caixa específico (ex.: o
  /// gestor lançando no caixa de outro operador pela visão "juntar caixas");
  /// sem ele, vale o caixa aberto do usuário atual.
  Future<SuprimentoCaixa> registrarSuprimento({
    required double valor,
    required String motivo,
    String? observacao,
    String? responsavel,
    AberturaCaixa? aberturaParam,
  }) async {
    final abertura = aberturaParam ?? aberturaCaixaAtual;
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
      responsavel: responsavel ?? abertura.responsavel ?? _responsavelAtivo,
    );

    _suprimentos.add(suprimento);
    // GRAVAÇÃO LOCAL POR REGISTRO: só este suprimento vai ao PostgreSQL agora.
    _persistirLinhaLocal(
      LocalStorageService.keySuprimentos,
      suprimento.toMap(),
    );

    unawaited(
      _upsertNoSupabase(SupabaseService.tableSuprimentos, suprimento.toMap()),
    );

    notifyListeners();
    print(
      '>>> Suprimento registrado: R\$ ${valor.toStringAsFixed(2)} - $motivo',
    );
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
      if (dataFechamento != null && s.data.isAfter(dataFechamento))
        return false;
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
      if (dataFechamento != null && s.data.isAfter(dataFechamento))
        return false;
      return true;
    }).toList();
  }

  /// Compara se dois identificadores de operador/responsável se referem à
  /// mesma pessoa, tolerando diferenças de formato (email vs nome, maiúsculas,
  /// acentos, espaços). Ex.: 'carlos@gmail.com' bate com 'Carlos' ou 'carlos'.
  bool _ehMesmoOperador(String? a, String? b) {
    if (a == null || b == null) return false;
    String normalizar(String s) =>
        s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9@]'), '');
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
      if (dataFechamento != null && v.dataVenda.isAfter(dataFechamento))
        return false;

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
    final vendas = getVendasDoCaixa(
      abertura,
    ).fold(0.0, (sum, v) => sum + v.valorTotal);
    final sangrias = getSangriasDoCaixa(
      abertura,
    ).fold(0.0, (sum, s) => sum + s.valor);
    final suprimentos = getSuprimentosDoCaixa(
      abertura,
    ).fold(0.0, (sum, s) => sum + s.valor);
    return abertura.valorInicial + vendas + suprimentos - sangrias;
  }

  /// Resumo do valor vendido em um caixa, separado por forma de pagamento
  /// (Dinheiro, PIX, Cartão de Crédito/Débito, Ticket, Fiado, etc.).
  ///
  /// Usa [getVendasDoCaixa] como fonte — a MESMA base do saldo, do card de
  /// entradas e do PDF de fechamento —, então a soma deste resumo bate com o
  /// total de vendas exibido no caixa. Vendas com pagamento dividido (split)
  /// são detalhadas pelo campo [VendaBalcao.pagamentos]; as demais entram pela
  /// forma principal ([VendaBalcao.tipoPagamento]).
  List<ResumoFormaPagamento> calcularResumoFormaPagamentoDoCaixa(
    AberturaCaixa abertura,
  ) {
    final acumulado = <String, ResumoFormaPagamento>{};

    void acumular(TipoPagamento tipo, String? nomeForma, double valor) {
      if (valor <= 0) return;
      final rotulo = (nomeForma != null && nomeForma.trim().isNotEmpty)
          ? nomeForma.trim()
          : tipo.nome;
      final chave = '${tipo.name}|${rotulo.toLowerCase()}';
      final atual = acumulado[chave];
      acumulado[chave] = ResumoFormaPagamento(
        rotulo: rotulo,
        tipo: tipo,
        valor: (atual?.valor ?? 0.0) + valor,
        quantidade: (atual?.quantidade ?? 0) + 1,
      );
    }

    for (final venda in getVendasDoCaixa(abertura)) {
      if (venda.pagamentos.isNotEmpty) {
        for (final pag in venda.pagamentos) {
          acumular(pag.tipo, pag.nomeForma, pag.valor);
        }
      } else {
        acumular(venda.tipoPagamento, null, venda.valorTotal);
      }
    }

    final lista = acumulado.values.toList()
      ..sort((a, b) => b.valor.compareTo(a.valor));
    return lista;
  }

  /// Recebimentos de PEDIDOS (mesas/comandas/delivery) por forma de pagamento
  /// dentro da janela de um caixa.
  ///
  /// É a MESMA regra usada no diálogo de fechamento e na impressão: só pedidos
  /// do mesmo operador do caixa (`vendedorNome`), com pagamento já recebido
  /// (`recebido` + `dataRecebimento`) depois da abertura do caixa e, quando
  /// [limite] é informado (caixa já encerrado), até o horário do fechamento.
  /// Pagamentos em [TipoPagamento.outro] são ignorados, como no fluxo de caixa.
  Map<TipoPagamento, double> calcularRecebimentosDePedidosDoCaixa(
    AberturaCaixa abertura, {
    DateTime? limite,
  }) {
    final totais = <TipoPagamento, double>{};
    final respCaixa = abertura.responsavel?.trim();
    final temRespCaixa = respCaixa != null && respCaixa.isNotEmpty;
    final ate = limite?.add(const Duration(seconds: 1));

    for (final pedido in _pedidos) {
      if (temRespCaixa) {
        final operadorPedido = pedido.vendedorNome;
        if (operadorPedido == null || operadorPedido.trim().isEmpty) continue;
        if (!_ehMesmoOperador(operadorPedido, respCaixa)) continue;
      }
      for (final pag in pedido.pagamentos) {
        if (!pag.recebido || pag.dataRecebimento == null) continue;
        if (pag.tipo == TipoPagamento.outro) continue;
        if (pag.dataRecebimento!.isBefore(abertura.dataAbertura)) continue;
        if (ate != null && pag.dataRecebimento!.isAfter(ate)) continue;
        totais[pag.tipo] = (totais[pag.tipo] ?? 0.0) + pag.valor;
      }
    }
    return totais;
  }

  // Os antigos `_salvarAberturaCaixaImediatamente`/`_salvarFechamentoCaixaImediatamente`
  // gravavam a TABELA INTEIRA de aberturas/fechamentos a cada movimento. Foram
  // substituídos pela gravação por registro (`_persistirLinhaLocal`), chamada
  // direto em `abrirCaixaComValor` e `registrarFechamentoCaixa`.

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
      return _produtos
          .where(
            (p) =>
                p.nome.toLowerCase().contains(termo.toLowerCase()) ||
                (p.codigo?.toLowerCase().contains(termo.toLowerCase()) ??
                    false),
          )
          .toList();
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
        _clientes,
      );
      debugPrint(
        '>>> [Cliente] ✅ Salvo localmente: ${cliente.nome} (ID: ${cliente.id})',
      );
    } catch (e) {
      debugPrint('>>> [Cliente] ❌ Erro ao salvar localmente: $e');
    }

    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tableClientes,
      cliente.toMap(),
    );
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
      await enviarMudancaParaSupabase(
        SupabaseService.tableClientes,
        cliente.toMap(),
      );
    }
  }

  /// Atualiza os agendamentos quando os dados dos pets são alterados no cadastro
  void _atualizarAgendamentosComPetsAtualizados(
    Cliente clienteAntigo,
    Cliente clienteNovo,
  ) {
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
      if (agendamento.clienteId == clienteNovo.id &&
          agendamento.petId != null) {
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
          debugPrint(
            '>>> [Sincronização] Atualizando agendamento ${agendamento.numero} com dados atualizados do pet ${petAtualizado.nome}',
          );
        } else {
          // Pet foi removido do cliente - manter agendamento mas sem referência ao pet
          debugPrint(
            '>>> [Sincronização] ⚠ Pet ${agendamento.petId} foi removido do cliente, mas agendamento ${agendamento.numero} mantido',
          );
        }
      }
    }

    // Atualizar agendamentos na lista
    for (final agendamentoAtualizado in agendamentosParaAtualizar) {
      final indexAgendamento = _agendamentosServico.indexWhere(
        (a) => a.id == agendamentoAtualizado.id,
      );
      if (indexAgendamento != -1) {
        _agendamentosServico[indexAgendamento] = agendamentoAtualizado;
      }
    }

    if (agendamentosParaAtualizar.isNotEmpty) {
      debugPrint(
        '>>> [Sincronização] ✓ ${agendamentosParaAtualizar.length} agendamento(s) atualizado(s) com dados do pet',
      );

      // Salvar agendamentos atualizados
      _salvarAutomaticamente();

      if (agendamentosParaAtualizar.isNotEmpty) {
        for (final agendamento in agendamentosParaAtualizar) {
          _upsertNoSupabase(
            SupabaseService.tableAgendamentosServico,
            agendamento.toMap(),
          );
        }
      }
    }
  }

  void deleteCliente(String id) {
    _clientes.removeWhere((c) => c.id == id);
    // Exclusão no banco LOCAL por linha: sem isso a linha continuava viva no
    // PostgreSQL e o registro "ressuscitava" no próximo boot (o snapshot do
    // banco substitui a memória).
    _removerLinhaLocal(LocalStorageService.keyClientes, id);
    notifyListeners();
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tableClientes, {
      'id': id,
    }, evento: 'DELETE');
  }

  // ============ CRUD Funcionario ============

  Future<void> addFuncionario(Funcionario funcionario) async {
    _funcionarios.add(funcionario);
    notifyListeners();

    // Salvar localmente IMEDIATAMENTE (sem debounce para funcionários)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyFuncionarios),
        _funcionarios,
      );
      debugPrint(
        '>>> [Funcionário] ✅ Salvo localmente: ${funcionario.nome} (ID: ${funcionario.id})',
      );
    } catch (e) {
      debugPrint('>>> [Funcionário] ❌ Erro ao salvar localmente: $e');
    }

    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tableFuncionarios,
      funcionario.toMap(),
    );
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
          _funcionarios,
        );
        debugPrint(
          '>>> [Funcionário] ✅ Atualizado localmente: ${funcionario.nome} (ID: ${funcionario.id})',
        );
      } catch (e) {
        debugPrint('>>> [Funcionário] ❌ Erro ao atualizar localmente: $e');
      }

      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();

      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(
        SupabaseService.tableFuncionarios,
        funcionario.toMap(),
      );
    }
  }

  void deleteFuncionario(String id) {
    _funcionarios.removeWhere((f) => f.id == id);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyFuncionarios, id);
    notifyListeners();
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tableFuncionarios, {
      'id': id,
    }, evento: 'DELETE');
  }

  // ============ CRUD LinkVendedor ============

  Future<void> addLinkVendedor(LinkVendedor link) async {
    _linksVendedores.add(link);
    notifyListeners();

    // Salvar localmente IMEDIATAMENTE (sem debounce para links de vendedores)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyLinksVendedores),
        _linksVendedores,
      );
      debugPrint(
        '>>> [LinkVendedor] ✅ Salvo localmente: ${link.codigoLink} (ID: ${link.id})',
      );
    } catch (e) {
      debugPrint('>>> [LinkVendedor] ❌ Erro ao salvar localmente: $e');
    }

    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();

    // Nuvem em segundo plano: o link já está na memória/local.
    unawaited(
      _upsertNoSupabase(SupabaseService.tableLinksVendedores, link.toMap()),
    );
  }

  Future<void> updateLinkVendedor(LinkVendedor link) async {
    final index = _linksVendedores.indexWhere((l) => l.id == link.id);
    if (index != -1) {
      _linksVendedores[index] = link;
      notifyListeners();
      // Local por registro (não reescreve todas as tabelas) e nuvem em segundo
      // plano — mesmo padrão do fluxo de venda. Antes este caminho fazia
      // `_salvarTodosDados()` (banco inteiro) + upsert aguardado, o que segurava
      // a finalização do pedido no checkout do e-commerce.
      _persistirLinhaLocal(
        LocalStorageService.keyLinksVendedores,
        link.toMap(),
      );
      unawaited(
        _upsertNoSupabase(SupabaseService.tableLinksVendedores, link.toMap()),
      );
    }
  }

  void deleteLinkVendedor(String id) {
    _linksVendedores.removeWhere((l) => l.id == id);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyLinksVendedores, id);
    notifyListeners();
    _salvarAutomaticamente();
    // Remover imediatamente do Supabase
    if (SupabaseService.isAvailable && _currentEmpresaId != null) {
      _supabaseService
          .delete(SupabaseService.tableLinksVendedores, id)
          .catchError((e) {
            debugPrint('>>> Erro ao remover link de vendedor do Supabase: $e');
            _adicionarSincronizacaoPendente();
          });
    }
  }

  // ============ CRUD ComissaoVendedor ============

  Future<void> addComissaoVendedor(ComissaoVendedor comissao) async {
    debugPrint(
      '>>> [ComissaoVendedor] ➕ Adicionando nova comissão: ${comissao.id}',
    );
    debugPrint(
      '>>> [ComissaoVendedor]     Vendedor: ${comissao.funcionarioNome} (ID: ${comissao.funcionarioId})',
    );
    debugPrint(
      '>>> [ComissaoVendedor]     Pedido: ${comissao.pedidoNumero} (ID: ${comissao.pedidoId})',
    );
    debugPrint(
      '>>> [ComissaoVendedor]     Valor: R\$ ${comissao.valorComissao}',
    );

    _comissoesVendedores.add(comissao);
    notifyListeners();

    // Salvar localmente IMEDIATAMENTE
    try {
      final chave = _getChaveComEmpresa(
        LocalStorageService.keyComissoesVendedores,
      );
      debugPrint(
        '>>> [ComissaoVendedor] 💾 Salvando localmente na chave: $chave',
      );
      await _storage.salvarLista(chave, _comissoesVendedores);
      debugPrint(
        '>>> [ComissaoVendedor] ✅ Salva localmente com sucesso! Total na lista: ${_comissoesVendedores.length}',
      );
    } catch (e) {
      debugPrint('>>> [ComissaoVendedor] ❌ ERRO ao salvar localmente: $e');
    }

    _salvarAutomaticamente();

    // Nuvem em segundo plano: a comissão já está na memória/local.
    unawaited(
      _upsertNoSupabase(
        SupabaseService.tableComissoesVendedores,
        comissao.toMap(),
      ),
    );
  }

  Future<void> updateComissaoVendedor(ComissaoVendedor comissao) async {
    final index = _comissoesVendedores.indexWhere((c) => c.id == comissao.id);
    if (index != -1) {
      _comissoesVendedores[index] = comissao;
      notifyListeners();
      _marcarSujo(LocalStorageService.keyComissoesVendedores);
      unawaited(
        _upsertNoSupabase(
          SupabaseService.tableComissoesVendedores,
          comissao.toMap(),
        ),
      );
    }
  }

  void deleteComissaoVendedor(String id) {
    _comissoesVendedores.removeWhere((c) => c.id == id);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyComissoesVendedores, id);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyComissoesVendedores);
    enviarMudancaParaSupabase(SupabaseService.tableComissoesVendedores, {
      'id': id,
    }, evento: 'DELETE');
  }

  // ============ CRUD ContaPagar ============

  Future<void> addContaPagar(ContaPagar conta) async {
    _contasPagar.add(conta);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyContasPagar);
    unawaited(
      _upsertNoSupabase(SupabaseService.tableContasPagar, conta.toMap()),
    );
  }

  Future<void> updateContaPagar(ContaPagar conta) async {
    final index = _contasPagar.indexWhere((c) => c.id == conta.id);
    if (index != -1) {
      _contasPagar[index] = conta;
      notifyListeners();
      _salvarAutomaticamente(); // Geralmente é um Future que não esperamos aqui ou aguardamos
      unawaited(
        _upsertNoSupabase(SupabaseService.tableContasPagar, conta.toMap()),
      );
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

      return t1 == normalizado ||
          t2 == normalizado ||
          w == normalizado ||
          (normalizado.length >= 8 &&
              (t1.endsWith(normalizado) ||
                  t2.endsWith(normalizado) ||
                  w.endsWith(normalizado))) ||
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
      debugPrint(
        '>>> [DataService] 🔍 Buscando no Supabase por telefone: $normalizado',
      );
      try {
        final response = await _supabaseService.client
            .from(SupabaseService.tableClientes)
            .select()
            .eq('empresa_id', _currentEmpresaId!)
            .or(
              'telefone.eq.$normalizado,telefone2.eq.$normalizado,whatsapp.eq.$normalizado',
            );

        final List<dynamic> remotosData = response;
        if (remotosData.isNotEmpty) {
          for (final map in remotosData) {
            final c = Cliente.fromMap(map as Map<String, dynamic>);
            // Se já temos o cliente localmente, substituir pelo remoto (mais fresco)
            final indexLocal = resultadoFinal.indexWhere(
              (loc) => loc.id == c.id,
            );
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
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyContasPagar, id);
    notifyListeners();
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tableContasPagar, {
      'id': id,
    }, evento: 'DELETE');
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

  /// Produto que chega SEM perfil tributário recebe o PADRÃO do regime atual.
  ///
  /// A regra fica no serviço (e não só no formulário) para valer também para
  /// importação, clone e qualquer caminho que grave produto — o vínculo
  /// precisa chegar igual ao PostgreSQL local e à nuvem.
  Produto _comPerfilTributarioPadrao(Produto produto) {
    return produtoComPerfilTributarioPadrao(
      produto,
      _perfisTributarios,
      paraSimples: empresaRegimeSimples,
    );
  }

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
    //
    // ⚠️ O id NÃO pode ser fixo ('produto-diversos-9999'). Um id fixo é igual em
    // TODAS as empresas: ao abrir outra empresa, o upsert colidia com a linha da
    // empresa anterior e o produto "Diversos" trocava de dono (ou levava os
    // lançamentos junto). Agora o id é único por empresa.
    final agora = DateTime.now();
    final empresaAtual = (_currentEmpresaId ?? '').trim();
    final sufixoEmpresa = empresaAtual.isNotEmpty
        ? empresaAtual
        : 'sem-empresa-${agora.millisecondsSinceEpoch}';
    final produtoDiversos = Produto(
      id: 'produto-diversos-9999-$sufixoEmpresa',
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

  Future<void> addProduto(
    Produto produto, {
    bool registrarHistorico = true,
    String? usuarioId,
    String? usuarioNome,
    String? usuarioEmail,
  }) async {
    // Garantir ID único e não vazio
    if (produto.id.isEmpty) {
      produto = produto.copyWith(id: uuid.v4());
    }
    // Produto SEM perfil tributário usa o PADRÃO do regime. O vínculo vai no
    // `toMap()` e é gravado no PostgreSQL local e na nuvem junto com o item.
    produto = _comPerfilTributarioPadrao(produto);
    // ⛔ TRAVA: nunca criar/gravar produto carimbado com OUTRA empresa (a
    // gravação cruzada é o que movia itens de uma empresa para a outra).
    if (ehProdutoDeOutraEmpresa(produto.empresaId)) {
      _produtosDeOutraEmpresaRecusados++;
      debugPrint(
        '>>> [DataService] 🛡️ Cadastro RECUSADO: '
        '${_motivoRecusaDeEmpresa(produto)}. Nada foi gravado.',
      );
      return;
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
      await DatabaseService().upsertItem(
        LocalStorageService.keyProdutos,
        produto.toMap(),
      );
      DatabaseService()
          .salvarLista(
            LocalStorageService.keyProdutos,
            _produtos.map((p) => p.toMap()).toList(),
          )
          .catchError((e) {
            debugPrint(
              '>>> [DataService] ⚠️ Erro ao salvar lista de produtos no PostgreSQL: $e',
            );
          });
      debugPrint(
        '>>> [DataService] 💾 Novo produto ${produto.nome} (preço: ${produto.preco}) salvo no PostgreSQL',
      );
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao salvar novo produto no PostgreSQL: $e',
      );
    }

    // 2. Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tableProdutos,
      produto.toMap(),
    );

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
      // Lote (importação/planilha) também garante o perfil PADRÃO em quem não
      // tem: o vínculo precisa subir para o banco local e para a nuvem.
      p = _comPerfilTributarioPadrao(p);
      processados.add(p);
    }

    debugPrint(
      '>>> [DataService] 📦 Processando lote de ${processados.length} produtos...',
    );

    // 1. Atualizar lista local - OTIMIZADO: Usar Map para O(N) em vez de O(N^2)
    final Map<String, int> existingMap = {
      for (int i = 0; i < _produtos.length; i++) _produtos[i].id: i,
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
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao persistir lote no PostgreSQL: $e',
      );
    }

    // 3. Salvar no Supabase (Cloud)
    if (SupabaseService.isAvailable &&
        _currentEmpresaId != null &&
        processados.length <= 100) {
      final dataList = processados.map((p) => p.toMap()).toList();
      debugPrint(
        '>>> [DataService] ☁️ Enviando lote para Supabase: empresa=$currentEmpresaId, itens=${dataList.length}',
      );
      try {
        await _supabaseService
            .upsertLote(SupabaseService.tableProdutos, dataList)
            .timeout(const Duration(minutes: 5));

        debugPrint('>>> [DataService] ✅ Sincronização com Supabase concluída.');
      } catch (e) {
        debugPrint('>>> ❌ Erro ao sincronizar lote com Supabase: $e');
        _adicionarSincronizacaoPendente();
      }
    } else if (processados.length > 100) {
      debugPrint(
        '>>> [DataService] ℹ️ Lote grande (${processados.length} itens). Sincronização com nuvem adiada conforme solicitado.',
      );
      _adicionarSincronizacaoPendente(); // Marcar que precisa sincronizar depois
    }

    // 3. Persistir localmente e notificar UI uma única vez
    _marcarSujo(LocalStorageService.keyProdutos);
    notifyListeners();
    debugPrint('>>> [DataService] ✅ Lote concluído.');
  }

  /// Adiciona ou atualiza múltiplos CLIENTES em uma única operação (Batch).
  ///
  /// Usado pelo importador de clientes: grava o lote direto no PostgreSQL
  /// local (sem esperar o flush debounced) e replica para a nuvem, do mesmo
  /// jeito que o lote de produtos.
  Future<void> addClientesLote(List<Cliente> novosClientes) async {
    if (novosClientes.isEmpty) return;

    // Garantir ID único e não vazio para todos os clientes.
    final List<Cliente> processados = [];
    for (var c in novosClientes) {
      if (c.id.isEmpty) {
        c = c.copyWith(id: uuid.v4());
      }
      processados.add(c);
    }

    debugPrint(
      '>>> [DataService] 👥 Processando lote de ${processados.length} clientes...',
    );

    // 1. Atualizar lista local - O(N) com Map.
    final Map<String, int> existingMap = {
      for (int i = 0; i < _clientes.length; i++) _clientes[i].id: i,
    };
    for (final c in processados) {
      final index = existingMap[c.id];
      if (index != null) {
        _clientes[index] = c;
      } else {
        _clientes.add(c);
        existingMap[c.id] = _clientes.length - 1;
      }
    }

    // 2. Salvar no PostgreSQL (Banco Local) - PERSISTÊNCIA MANUAL
    try {
      final dataList = processados.map((c) => c.toMap()).toList();
      await DatabaseService().adicionarClientesLote(dataList);
      debugPrint(
        '>>> [DataService] 🏛️ Lote de clientes persistido no PostgreSQL local.',
      );
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao persistir lote de clientes no PostgreSQL: $e',
      );
    }

    // 3. Enviar para o Supabase (Cloud).
    if (SupabaseService.isAvailable &&
        _currentEmpresaId != null &&
        processados.length <= 100) {
      try {
        final dataList = processados.map((c) => c.toMap()).toList();
        await _supabaseService
            .upsertLote(SupabaseService.tableClientes, dataList)
            .timeout(const Duration(minutes: 5));
        debugPrint(
          '>>> [DataService] ✅ Lote de clientes sincronizado com Supabase.',
        );
      } catch (e) {
        debugPrint(
          '>>> ❌ Erro ao sincronizar lote de clientes com Supabase: $e',
        );
        _adicionarSincronizacaoPendente();
      }
    } else if (processados.length > 100) {
      // Lote grande: a nuvem fica para o próximo ciclo de sincronização.
      _adicionarSincronizacaoPendente();
    }

    // 4. Persistir localmente (SharedPreferences) e notificar a UI uma vez.
    _marcarSujo(LocalStorageService.keyClientes);
    notifyListeners();
    debugPrint('>>> [DataService] ✅ Lote de clientes concluído.');
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
      final camposAlterados = ProdutoHistorico.compararProdutos(
        mapAntigo,
        mapNovo,
      );

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
        final extras = [
          if (motivo != null) 'Motivo: $motivo',
          if (observacao != null) 'Obs: $observacao',
        ];
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
        debugPrint(
          '>>> [DataService] ⚠️ Erro ao salvar histórico no PostgreSQL: $e',
        );
      });

      // Sincronizar com Supabase em segundo plano (em modo lote, no fim)
      final supabaseMap = historico.toSupabaseMap();
      if (_emLoteEmMassa) {
        (_loteMudancasPendentes['produto_historico'] ??= []).add(supabaseMap);
      } else {
        _upsertNoSupabase('produto_historico', supabaseMap).catchError((e) {
          debugPrint('>>> [DataService] ⚠️ Erro ao sincronizar histórico: $e');
        });
      }

      debugPrint(
        '>>> [DataService] 📋 Histórico registrado: ${produtoNovo.nome} - ${camposAlterados.join(', ')}',
      );
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao registrar histórico: $e');
      // Não propagar erro - histórico é opcional
    }
  }

  /// Busca o histórico de alterações de um produto específico.
  /// Tenta o banco local primeiro; se estiver vazio, busca no Supabase
  /// (garante que a entrada apareça mesmo se o banco local não tiver registros).
  Future<List<ProdutoHistorico>> buscarHistoricoProduto(
    String produtoId, {
    int limite = 50,
  }) async {
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
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao buscar histórico no banco local: $e',
      );
    }

    // Fallback: Supabase (banco local vazio/desatualizado)
    try {
      if (SupabaseService.isAvailable &&
          _currentEmpresaId != null &&
          _currentEmpresaId!.isNotEmpty) {
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
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao buscar histórico no Supabase: $e',
      );
    }
    return [];
  }

  /// Busca todo o histórico da empresa
  Future<List<ProdutoHistorico>> buscarHistoricoGeral({
    int limite = 100,
    DateTime? dataInicio,
    DateTime? dataFim,
  }) async {
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

  // ───────────────────────────────────────────────────────────────────────────
  // Trava de EMPRESA do catálogo (produtos)
  //
  // O que aconteceu de verdade: um produto que entrava na memória vindo de
  // outro lugar (cache antigo sem empresa na chave, backup, sincronização) era
  // gravado com o `empresa_id` da empresa ABERTA — porque o modelo não guardava
  // a empresa e o banco carimba com a empresa da sessão. O item trocava de dono
  // em silêncio, e a troca de REGIME TRIBUTÁRIO (que reescreve todos os produtos
  // da memória em laço) denunciava isso de uma vez: "misturou todos os itens".
  //
  // Agora são três travas:
  //   1. o produto carrega a própria empresa (`Produto.empresaId`), então dá
  //      para saber de quem ele é;
  //   2. produto de OUTRA empresa não entra na memória (descartado + contado);
  //   3. produto de OUTRA empresa não é gravado (recusado + contado).
  // ───────────────────────────────────────────────────────────────────────────

  /// Produtos de outras empresas recusados na GRAVAÇÃO (sinal de alarme).
  /// Diferente de zero = algo tentou escrever no catálogo errado.
  int _produtosDeOutraEmpresaRecusados = 0;
  int get produtosDeOutraEmpresaRecusados => _produtosDeOutraEmpresaRecusados;

  /// Produtos de outras empresas DESCARTADOS ao entrar na memória.
  int _produtosDeOutraEmpresaDescartados = 0;
  int get produtosDeOutraEmpresaDescartados =>
      _produtosDeOutraEmpresaDescartados;

  /// A REGRA (pura, testável): este produto é de uma empresa diferente?
  ///
  /// `null`/vazio NÃO conta como outra empresa: é produto que ainda não foi
  /// gravado (novo) ou registro antigo sem carimbo — nos dois casos a empresa
  /// aberta é a resposta certa. Sem empresa aberta quem barra é o banco.
  @visibleForTesting
  static bool produtoDeEmpresaDiferente(
    String? empresaDoProduto,
    String? empresaAberta,
  ) {
    if (empresaAberta == null || empresaAberta.isEmpty) return false;
    if (empresaDoProduto == null || empresaDoProduto.isEmpty) return false;
    return empresaDoProduto != empresaAberta;
  }

  /// A REGRA (pura, testável): separa o que é da empresa alvo do que é de fora.
  @visibleForTesting
  static List<Produto> filtrarProdutosDaEmpresa(
    List<Produto> produtos, {
    required String? empresaAlvo,
  }) {
    if (empresaAlvo == null || empresaAlvo.isEmpty) return produtos;
    return produtos
        .where((p) => !produtoDeEmpresaDiferente(p.empresaId, empresaAlvo))
        .toList();
  }

  /// Este produto é de outra empresa (não da que está aberta)?
  bool ehProdutoDeOutraEmpresa(String? empresaDoProduto) =>
      produtoDeEmpresaDiferente(empresaDoProduto, _currentEmpresaId);

  /// Colunas que pertencem ao estoque. Quando a alteração de um produto mexe
  /// apenas nelas (é a baixa de uma venda, uma devolução, um ajuste), o app
  /// passa a gravar SÓ essas colunas — em vez de regravar a linha inteira com
  /// o objeto em memória, que pode estar com preço/nome antigos.
  static const _colunasDeEstoque = <String>{
    'estoque',
    'estoquePorFornecedor',
    'estoque_por_fornecedor',
    'estoquePorEstoque',
    'estoque_por_estoque',
    'estoquePadraoId',
    'estoque_padrao_id',
    'estoqueMinimo',
    'estoque_minimo',
    'updatedAt',
    'updated_at',
  };

  /// [coluna] é só de estoque?
  @visibleForTesting
  static bool eColunaDeEstoque(String coluna) =>
      _colunasDeEstoque.contains(coluna);

  /// Dois valores são "o mesmo dado" para efeito de gravar?
  ///
  /// Compara número com número (1 e 1.0 são o mesmo preço), e trata lista/mapa
  /// como JSON: sem isso, uma lista vazia `[]` e outra `[]` vindas de caminhos
  /// diferentes (objeto Dart x texto do banco) pareceriam alteração e fariam o
  /// app gravar a linha inteira a cada venda.
  @visibleForTesting
  static bool mesmoValorParaBanco(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    final aJson = comoJsonParaComparacao(a);
    final bJson = comoJsonParaComparacao(b);
    if (aJson != null && bJson != null) return aJson == bJson;
    return a == b;
  }

  /// Lista/mapa viram JSON ordenado; o resto devolve null.
  @visibleForTesting
  static String? comoJsonParaComparacao(Object? valor) {
    if (valor is Map || valor is List) {
      try {
        return jsonEncode(valor);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Só os produtos da empresa aberta — os de outra empresa ficam de fora e o
  /// descarte é contado (e resumido no log, sem uma linha por item).
  List<Produto> somenteProdutosDaEmpresaAberta(
    List<Produto> produtos, {
    required String origem,
  }) {
    final aceitos = filtrarProdutosDaEmpresa(
      produtos,
      empresaAlvo: _currentEmpresaId,
    );
    final descartados = produtos.length - aceitos.length;
    if (descartados > 0) {
      _produtosDeOutraEmpresaDescartados += descartados;
      final fora = produtos
          .where(
            (p) => produtoDeEmpresaDiferente(p.empresaId, _currentEmpresaId),
          )
          .map((p) => p.empresaId)
          .whereType<String>()
          .toSet();
      debugPrint(
        '>>> [DataService] 🛡️ $descartados produto(s) de OUTRA '
        'empresa descartado(s) em "$origem" (empresa(s): '
        '${fora.join(", ")}; aberta: $_currentEmpresaId).',
      );
    }
    return aceitos;
  }

  /// Mensagem única de recusa de gravação cruzada (usada no log).
  String _motivoRecusaDeEmpresa(Produto produto) {
    final aberta = _currentEmpresaId;
    return 'o produto ${produto.nome} (id=${produto.id}) é da empresa '
        '${produto.empresaId}, mas a empresa aberta é $aberta';
  }

  Future<void> updateProduto(
    Produto produto, {
    bool aguardarSincronia = true,
    bool registrarMovimento = true,
    bool notify = true,
    bool registrarHistorico = true,
    String? usuarioId,
    String? usuarioNome,
    String? usuarioEmail,
    String? motivoHistorico,
    String? observacaoHistorico,
  }) async {
    if (produto.id.isEmpty) {
      debugPrint(
        '>>> [DataService] ⚠️ Tentativa de atualizar produto com ID vazio abortada.',
      );
      return;
    }
    // Mesmo produto antigo, SEM perfil tributário, recebe o PADRÃO do regime
    // ao ser salvo — o vínculo é persistido no local e na nuvem.
    produto = _comPerfilTributarioPadrao(produto);
    // ⛔ TRAVA: produto de outra empresa não é atualizado aqui. Antes ele era
    // gravado com a empresa aberta e TROCAVA DE DONO (a empresa original perdia
    // o item). Recusar deixa o dado onde ele é.
    if (ehProdutoDeOutraEmpresa(produto.empresaId)) {
      _produtosDeOutraEmpresaRecusados++;
      debugPrint(
        '>>> [DataService] 🛡️ Atualização RECUSADA: '
        '${_motivoRecusaDeEmpresa(produto)}. Nada foi gravado.',
      );
      return;
    }
    final index = _produtos.indexWhere((p) => p.id == produto.id);
    if (index != -1) {
      // Guardar produto antigo para histórico
      final produtoAntigo = _produtos[index];

      // Registrar movimento de estoque se houver mudança na quantidade
      if (registrarMovimento && produto.estoque != produtoAntigo.estoque) {
        final diferenca = produto.estoque - produtoAntigo.estoque;
        // Saldo levado a 0 = ZERAMENTO: registra como 'zerado' para não
        // aparecer como entrada/saída nos totais do relatório de estoque.
        final ehZeramento = produto.estoque == 0;
        registrarSaidaEstoque(
          produtoId: produto.id,
          quantidade: diferenca.abs(),
          motivo: ehZeramento
              ? 'zerar_estoque'
              : (diferenca < 0 ? 'saida' : 'ajuste'),
          observacao: ehZeramento
              ? 'Estoque zerado (de ${produtoAntigo.estoque.toStringAsFixed(2)} para 0) via edição'
              : (diferenca < 0 ? 'Saída via edição' : 'Ajuste via edição'),
          usuario: usuarioNome ?? 'sistema',
          notify: false,
          tipoHistorico: ehZeramento ? 'zerado' : 'saida',
        );
      }

      // Verificar se há mudanças para registrar no histórico
      final mapAntigo = produtoAntigo.toMap();
      final mapNovo = produto.toMap();
      final camposAlterados = ProdutoHistorico.compararProdutos(
        mapAntigo,
        mapNovo,
      );

      // Quais colunas mudaram DE FATO entre o que está gravado e o que está
      // chegando. O `compararProdutos` acima só olha os campos "importantes"
      // (para o histórico); aqui é preciso o diff completo, porque a decisão de
      // gravar tudo ou só o estoque depende de TODAS as colunas.
      final colunasQueMudaram = <String, dynamic>{};
      for (final entrada in mapNovo.entries) {
        final antes = mapAntigo[entrada.key];
        if (!mesmoValorParaBanco(antes, entrada.value)) {
          colunasQueMudaram[entrada.key] = entrada.value;
        }
      }

      // Só estoque mudou (é o caso da baixa de uma venda): grava APENAS as
      // colunas de estoque. Regravar a linha inteira aqui devolvia ao banco o
      // preço que o app tinha em memória — e se a edição desse preço veio do
      // outro PC pela LAN, a venda sobrescrevia a edição nova com o valor
      // velho. Era o que mantinha um item com dois preços diferentes nos dois
      // PCs, sem convergir.
      final soEstoque =
          colunasQueMudaram.isNotEmpty &&
          colunasQueMudaram.keys.every(eColunaDeEstoque);

      // Atualizar o produto na lista
      _produtos[index] = produto;
      if (notify) notifyListeners();
      _marcarSujo(LocalStorageService.keyProdutos);

      if (_emLoteEmMassa) {
        // Modo lote (ajuste em massa): acumula para gravar e sincronizar tudo
        // de uma vez no fim — evita milhares de escritas/requisições individuais.
        _loteProdutosPendentes[produto.id] = produto.toMap();
      } else {
        // 1. Salvar imediatamente no PostgreSQL local (apenas o registro alterado via upsert rápido)
        if (soEstoque) {
          DatabaseService().atualizarColunasProduto(
            produto.id,
            colunasQueMudaram,
          );
        } else {
          DatabaseService().upsertItem(
            LocalStorageService.keyProdutos,
            produto.toMap(),
          );
        }

        // 2. Sincronizar com Supabase em segundo plano
        debugPrint(
          '>>> [DataService] ☁️ Sincronizando produto com Supabase (segundo plano)...',
        );
        // O envio leva SÓ o que mudou quando a alteração é de estoque: mandar
        // a linha inteira subiria para a nuvem o preço velho que estava em
        // memória, contaminando também o outro PC quando a nuvem voltar.
        enviarMudancaParaSupabase(
          SupabaseService.tableProdutos,
          soEstoque
              ? {'id': produto.id, ...colunasQueMudaram}
              : produto.toMap(),
        );
      }

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
      //    (em modo lote o aviso é único, no fim, para não travar com milhares de itens)
      if (notify && !_emLoteEmMassa) {
        Future.delayed(const Duration(milliseconds: 100), () {
          notifyListeners();
        });
      }
    }
  }

  Future<void> deleteProduto(
    String id, {
    bool registrarHistorico = true,
    String? usuarioId,
    String? usuarioNome,
    String? usuarioEmail,
  }) async {
    // Buscar produto antes de remover para histórico
    final produtoRemovido = _produtos.firstWhere(
      (p) => p.id == id,
      orElse: () => Produto(
        id: id,
        nome: 'Produto desconhecido',
        unidade: '',
        grupo: '',
        preco: 0,
        estoque: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    _produtos.removeWhere((p) => p.id == id);
    // Exclusão real no banco local: sem isso o produto apagado voltava no
    // próximo boot (a linha continuava no PostgreSQL local).
    _removerLinhaLocal(LocalStorageService.keyProdutos, id);
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

    unawaited(_deleteNoSupabase(SupabaseService.tableProdutos, id));
  }

  /// Deleta todos os produtos (com confirmação necessária antes de chamar)
  /// PROTEÇÃO: Cria backup automático antes de deletar
  Future<void> deleteAllProdutos({required bool confirmar}) async {
    if (!confirmar) {
      throw Exception(
        '⚠️ PROTEÇÃO: deleteAllProdutos requer confirmação explícita (confirmar: true)',
      );
    }

    if (_currentEmpresaId == null) {
      throw Exception('⚠️ Nenhuma empresa selecionada');
    }

    final empresaId = _currentEmpresaId!;
    final totalProdutos = _produtos.length;

    // PROTEÇÃO: Backup automático antes de deletar
    print(
      '>>> 🛡️ PROTEÇÃO: Criando backup antes de deletar $totalProdutos produtos...',
    );
    try {
      // Salvar backup completo no localStorage com timestamp
      final backupKey =
          'backup_produtos_${empresaId}_${DateTime.now().millisecondsSinceEpoch}';
      final backupData = _produtos.map((p) => p.toMap()).toList();
      await _storage.salvarLista(backupKey, backupData);
      print('>>> ✅ Backup criado: $backupKey ($totalProdutos produtos)');
    } catch (e) {
      print(
        '>>> ❌ ERRO CRÍTICO: Não foi possível criar backup! Operação cancelada.',
      );
      print('>>> Erro: $e');
      throw Exception(
        '⚠️ PROTEÇÃO: Não foi possível criar backup. Operação cancelada para evitar perda de dados.',
      );
    }

    // Log de auditoria
    print(
      '>>> 📋 AUDITORIA: Deletando $totalProdutos produtos da empresa $empresaId',
    );
    print('>>> 📋 AUDITORIA: Timestamp: ${DateTime.now()}');

    // Deletar do Supabase primeiro se estiver habilitado
    if (nuvemHabilitada && SupabaseService.isAvailable) {
      try {
        await _supabaseService.deleteFiltered(SupabaseService.tableProdutos, {
          'empresa_id': empresaId,
        });
        debugPrint('>>> [DataService] Todos os produtos deletados do Supabase');
      } catch (e) {
        debugPrint(
          '>>> [DataService] ⚠️ Erro ao deletar produtos do Supabase: $e',
        );
        _adicionarSincronizacaoPendente();
      }
    }

    // Limpar lista local
    _produtos.clear();
    notifyListeners();

    await _salvarTodosDados();
    debugPrint(
      '>>> [DataService] Todos os produtos deletados localmente e do Supabase',
    );
    print(
      '>>> ✅ Operação concluída. Backup disponível em: backup_produtos_${empresaId}_*',
    );
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
    final lotes = lotesDoProduto(
      produtoId,
    ).where((l) => l.quantidade > 0).toList();
    if (lotes.isEmpty) return null;
    final comValidade = lotes.where((l) => l.dataValidade != null).toList();
    if (comValidade.isEmpty) return null;
    comValidade.sort((a, b) => a.dataValidade!.compareTo(b.dataValidade!));
    return comValidade.first.dataValidade;
  }

  /// Lotes com estoque vencidos ou que vencem nos próximos [dias] dias.
  /// A comparação usa dias-calendário para não classificar como vencido um
  /// produto cuja validade é hoje apenas por causa do horário atual.
  List<LoteProduto> lotesComValidadeCritica({int dias = 30}) =>
      filtrarLotesComValidadeCritica(_lotesProdutos, dias: dias);

  @visibleForTesting
  static List<LoteProduto> filtrarLotesComValidadeCritica(
    List<LoteProduto> lotes, {
    int dias = 30,
    DateTime? hoje,
  }) {
    final agora = hoje ?? DateTime.now();
    final dataHoje = DateTime(agora.year, agora.month, agora.day);
    final limite = dataHoje.add(Duration(days: dias));
    final resultado = lotes.where((lote) {
      final validade = lote.dataValidade;
      if (lote.quantidade <= 0 || validade == null) return false;
      final diaValidade = DateTime(validade.year, validade.month, validade.day);
      return !diaValidade.isAfter(limite);
    }).toList()..sort((a, b) => a.dataValidade!.compareTo(b.dataValidade!));
    return resultado;
  }

  /// Quantidade de produtos com lotes vencidos ou vencendo em X dias
  int contarProdutosComValidadeCritica({int dias = 30}) {
    return lotesComValidadeCritica(
      dias: dias,
    ).map((lote) => lote.produtoId).toSet().length;
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
      await DatabaseService().upsertItem(
        LocalStorageService.keyLotesProdutos,
        lote.toMap(),
      );
      debugPrint(
        '>>> [DataService] 💾 Lote ${lote.id} salvo imediatamente no PostgreSQL',
      );
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao salvar lote no PostgreSQL imediatamente: $e',
      );
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
      debugPrint(
        '>>> [DataService] 🗑️ Lote $loteId removido imediatamente do PostgreSQL',
      );
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao remover lote do PostgreSQL imediatamente: $e',
      );
    }
    enviarMudancaParaSupabase(SupabaseService.tableLotesProdutos, {
      'id': loteId,
    }, evento: 'DELETE');
  }

  /// Baixa FEFO: reduz a quantidade dos lotes (primeiro os que vencem antes).
  /// Retorna a quantidade que não pôde ser abatida (estoque sem lote).
  double darBaixaEmLotes(
    String produtoId,
    double quantidade, {
    String? observacao,
  }) {
    double restante = quantidade;
    final lotes = lotesDoProduto(
      produtoId,
    ).where((l) => l.quantidade > 0).toList();
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
          DatabaseService().upsertItem(
            LocalStorageService.keyLotesProdutos,
            l.toMap(),
          );
        } catch (e) {
          debugPrint(
            '>>> [DataService] ⚠️ Erro ao persistir baixa de lote: $e',
          );
        }
        enviarMudancaParaSupabase(
          SupabaseService.tableLotesProdutos,
          l.toMap(),
        );
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
    String? estoqueId,
    double? custoUnitario,
  }) async {
    await registrarEntradaEstoque(
      produtoId: produtoId,
      quantidade: quantidade,
      observacao: observacao,
      usuario: usuario,
      fornecedorId: fornecedorId,
      fornecedorNome: fornecedorNome,
      estoqueId: estoqueId,
    );
    // Só não cria lote quando não veio NENHUM dado de lote. Antes, entrada só
    // com validade (sem nº de lote) não gerava lote nenhum — era o "lote e
    // validade não está indo": a tela chamava este método, mas ele retornava
    // aqui. Agora a validade sozinha já cria o lote, com um rótulo derivado.
    final loteTexto = (numeroLote ?? '').trim();
    final temDadoDeLote =
        loteTexto.isNotEmpty || dataValidade != null || dataFabricacao != null;
    if (!temDadoDeLote) return;
    final numeroLoteFinal = loteTexto.isNotEmpty
        ? loteTexto
        : _rotuloLoteSemNumero(dataValidade);

    // Depósito/estoque de destino do lote: é o MESMO que recebeu o produto em
    // `registrarEntradaEstoque` (o escolhido na tela ou, sem ele, o padrão do
    // produto). O lote carrega o depósito para o saldo ser separado por local.
    final produtoIndex = _produtos.indexWhere((p) => p.id == produtoId);
    final produtoDoLote = produtoIndex == -1 ? null : _produtos[produtoIndex];
    final destinoEstoque =
        estoquePorId(_estoques, estoqueId)?.id ??
        (produtoDoLote != null
            ? estoquePadraoDe(produtoDoLote)
            : estoquePrincipalAtual?.id);
    final destinoNome = nomeDoEstoque(_estoques, destinoEstoque);
    final produtoNome = produtoDoLote?.nome;

    // Lote atrelado ao fornecedor E ao depósito: só unifica (soma) quando a
    // entrada vem do MESMO produto + MESMO fornecedor + MESMO estoque + mesmo
    // nº de lote + mesma validade. O mesmo nº de lote de fornecedores ou de
    // depósitos diferentes permanece em lotes separados, cada um com seu saldo.
    LoteProduto? existente;
    for (final l in _lotesProdutos) {
      if (l.produtoId == produtoId &&
          l.numeroLote.trim().toLowerCase() == numeroLoteFinal.toLowerCase() &&
          _mesmaData(l.dataValidade, dataValidade) &&
          l.fornecedorId == fornecedorId &&
          l.estoqueId == destinoEstoque) {
        existente = l;
        break;
      }
    }
    if (existente != null) {
      await salvarLoteProduto(
        existente.copyWith(
          quantidade: existente.quantidade + quantidade,
          dataFabricacao: dataFabricacao ?? existente.dataFabricacao,
          fornecedorId: fornecedorId ?? existente.fornecedorId,
          fornecedorNome: fornecedorNome ?? existente.fornecedorNome,
          produtoNome: produtoNome ?? existente.produtoNome,
          estoqueId: destinoEstoque ?? existente.estoqueId,
          estoqueNome: destinoNome,
          custoUnitario: custoUnitario ?? existente.custoUnitario,
          updatedAt: DateTime.now(),
        ),
      );
    } else {
      await salvarLoteProduto(
        LoteProduto(
          id: '${DateTime.now().microsecondsSinceEpoch}_lote_$produtoId',
          produtoId: produtoId,
          produtoNome: produtoNome,
          numeroLote: numeroLoteFinal,
          dataFabricacao: dataFabricacao,
          dataValidade: dataValidade,
          quantidade: quantidade,
          fornecedorId: fornecedorId,
          fornecedorNome: fornecedorNome,
          estoqueId: destinoEstoque,
          estoqueNome: destinoNome,
          custoUnitario: custoUnitario,
        ),
      );
    }
  }

  /// Rótulo do lote quando o operador preenche só a validade, sem nº de lote:
  /// mantém a entrada rastreável pela data (e unifica reentradas iguais).
  String _rotuloLoteSemNumero(DateTime? validade) {
    if (validade == null) return 'S/N';
    final d = validade.day.toString().padLeft(2, '0');
    final m = validade.month.toString().padLeft(2, '0');
    return 'S/N ${d}/${m}/${validade.year}';
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
  /// Dá entrada de mercadoria no estoque.
  ///
  /// [estoqueId] é o estoque de destino (a tela pergunta no lançamento). Sem
  /// ele, entra no ESTOQUE PADRÃO do produto (o do cadastro) — e, se o produto
  /// não tiver um, no estoque principal da empresa.
  Future<bool> registrarEntradaEstoque({
    required String produtoId,
    required double quantidade,
    String? observacao,
    String? usuario,
    String? fornecedorId,
    String? fornecedorNome,
    String? estoqueId,
    bool notify = true,

    /// Tipo gravado no histórico. O padrão é 'entrada'; passa 'zerado' quando
    /// a "entrada" só existe para LEVAR O SALDO A 0 (zeramento de estoque com
    /// saldo negativo) — assim o movimento fica registrado, mas NÃO infla o
    /// total de ENTRADAS das telas de relatório.
    String tipoHistorico = 'entrada',
  }) async {
    // 1. Localizar o produto
    final index = _produtos.indexWhere((p) => p.id == produtoId);
    if (index == -1 || produtoId.isEmpty) {
      debugPrint(
        '>>> [DataService] registrarEntradaEstoque: Produto não encontrado ($produtoId)',
      );
      return false;
    }

    final produto = _produtos[index];

    // 2. Atualizar o estoque por fornecedor
    final mapaEstoque = Map<String, double>.from(
      produto.estoquePorFornecedor ?? {},
    );
    final nomeFornecedorFinal = fornecedorNome ?? 'Geral';
    mapaEstoque[nomeFornecedorFinal] =
        (mapaEstoque[nomeFornecedorFinal] ?? 0.0) + quantidade;

    // 3. Atualizar o produto — inclusive o saldo do ESTOQUE escolhido.
    //    A normalização garante o total: produto que ainda não tinha os saldos
    //    separados recebe o estoque inteiro no padrão dele + a entrada nova.
    final destinoEstoque =
        estoquePorId(_estoques, estoqueId)?.id ?? estoquePadraoDe(produto);
    final mapaEstoques = _mapaEstoquesNormalizado(produto);
    mapaEstoques[destinoEstoque] =
        (mapaEstoques[destinoEstoque] ?? 0.0) + quantidade;

    final produtoAtualizado = produto.copyWith(
      estoque: produto.estoque + quantidade,
      estoquePorFornecedor: mapaEstoque,
      estoquePorEstoque: mapaEstoques,
      updatedAt: DateTime.now(),
    );

    // Salvar o produto atualizado (não aguardar Supabase para resposta instantânea).
    // A observação do histórico de alterações identifica a entrada no produto
    // (aparece na aba 'Histórico de Alterações' do formulário).
    final obsHistorico = [
      if (tipoHistorico == 'zerado')
        'Estoque zerado (saldo 0, correção de +${quantidade.toStringAsFixed(2)})'
      else
        'Entrada de estoque +${quantidade.toStringAsFixed(2)}',
      if (observacao != null && observacao.isNotEmpty) observacao,
      if (fornecedorNome != null && fornecedorNome.isNotEmpty)
        'Fornecedor: $fornecedorNome',
      'Estoque: ${nomeDoEstoque(_estoques, destinoEstoque)}',
    ].join(' | ');
    await updateProduto(
      produtoAtualizado,
      aguardarSincronia: false,
      registrarMovimento: false,
      notify: notify,
      observacaoHistorico: obsHistorico,
      usuarioNome: usuario,
    );

    // 4. Registrar no histórico
    final historico = EstoqueHistorico(
      id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + produtoId,
      produtoId: produtoId,
      data: DateTime.now(),
      quantidade: quantidade,
      tipo: tipoHistorico,
      observacao: [
        if (observacao != null && observacao.isNotEmpty) observacao,
        if (tipoHistorico == 'zerado')
          'Estoque zerado (entrada de ${quantidade.toStringAsFixed(2)} apenas para saldo 0)'
        else
          'Entrada em ${nomeDoEstoque(_estoques, destinoEstoque)}',
      ].join(' | '),
      usuario: usuario,
      fornecedorId: fornecedorId,
      fornecedorNome: fornecedorNome,
    );
    _estoqueHistorico.add(historico);
    if (notify) notifyListeners();
    _marcarSujo(LocalStorageService.keyEstoqueHistorico);

    // Enviar mudança para Supabase em segundo plano de forma assíncrona (não-bloqueante)
    _enviarMudancaSupabase(
      SupabaseService.tableEstoqueHistorico,
      historico.toMap(),
    );
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
    final mapaEstoque = Map<String, double>.from(
      produto.estoquePorFornecedor ?? {},
    );

    // Identificar fornecedores que possuem estoque não zerado
    final fornecedoresParaZerar = mapaEstoque.entries
        .where((e) => e.value != 0)
        .toList();

    if (fornecedoresParaZerar.isEmpty) {
      // Sem saldo por fornecedor: garante que o geral é 0 — e REGISTRA o
      // zeramento, senão o saldo mudaria sem nenhum rastro no histórico.
      if (produto.estoque.abs() >= 0.0005) {
        final historico = EstoqueHistorico(
          id:
              DateTime.now().millisecondsSinceEpoch.toString() +
              '_zerar_geral_' +
              produtoId,
          produtoId: produtoId,
          data: DateTime.now(),
          quantidade: -produto.estoque, // delta assinado: 0 − saldo anterior
          tipo: 'zerado',
          observacao:
              'Estoque zerado (de ${produto.estoque.toStringAsFixed(2)} para 0) '
              'por ${usuario ?? "Sistema"}',
          usuario: usuario,
          motivo: 'zerar_estoque',
        );
        _estoqueHistorico.add(historico);
        _enviarMudancaSupabase(
          SupabaseService.tableEstoqueHistorico,
          historico.toMap(),
        );
        _marcarSujo(LocalStorageService.keyEstoqueHistorico);
      }

      final produtoAtualizado = produto.copyWith(
        estoque: 0.0,
        estoquePorFornecedor: {},
        estoquePorEstoque: {},
        updatedAt: DateTime.now(),
      );
      await updateProduto(
        produtoAtualizado,
        aguardarSincronia: false,
        registrarMovimento: false,
      );
      notifyListeners();
      return;
    }

    // Registrar movimentações individuais para zerar cada fornecedor
    for (final entry in fornecedoresParaZerar) {
      final fornNome = entry.key;
      final qtdAtual = entry.value;

      mapaEstoque[fornNome] = 0.0;

      // Zeramento: o registro fica no histórico (rastreio de quem zerou, quanto
      // existia e quando), mas como tipo 'zerado' ele NÃO vira "entrada" nem
      // "saída" nos totais — um saldo negativo levado a 0 não é mercadoria que
      // entrou, é uma conciliação de estoque.
      final historico = EstoqueHistorico(
        id:
            DateTime.now().millisecondsSinceEpoch.toString() +
            '_zerar_' +
            fornNome +
            '_' +
            produtoId,
        produtoId: produtoId,
        data: DateTime.now(),
        quantidade: -qtdAtual, // delta assinado: 0 − saldo anterior
        tipo: 'zerado',
        observacao:
            'Estoque zerado (de ${qtdAtual.toStringAsFixed(2)} para 0) — '
            'fornecedor "$fornNome" via botão rápido por ${usuario ?? "Sistema"}',
        usuario: usuario,
        fornecedorNome: fornNome,
        motivo: 'zerar_estoque',
      );

      _estoqueHistorico.add(historico);
      _enviarMudancaSupabase(
        SupabaseService.tableEstoqueHistorico,
        historico.toMap(),
      );
    }

    final produtoAtualizado = produto.copyWith(
      estoque: 0.0,
      estoquePorFornecedor: mapaEstoque,
      estoquePorEstoque: {},
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
    bool baixaProporcionalComposicao =
        true, // true = usa a conversão do saco (15 kg = 1); false = baixa a quantidade inteira no ingrediente
    bool abaterComposicao =
        true, // false = não baixa os ingredientes (usado em ajustes de estoque em massa)
    double?
    custoUnitarioOverride, // Custo unitário a registrar (padrão: preço de custo do produto)
    String? estoqueId, // de qual estoque sai (padrão: o principal da empresa)
    bool transferirParaEstoquePrincipal =
        true, // traz o que falta de outro estoque antes de baixar
    /// Tipo gravado no histórico. O padrão é 'saida'; passa 'zerado' quando a
    /// "saída" só existe para LEVAR O SALDO A 0 (zeramento de estoque): o
    /// movimento fica registrado, mas NÃO conta no total de SAÍDAS.
    String tipoHistorico = 'saida',
  }) async {
    final index = _produtos.indexWhere((p) => p.id == produtoId);
    if (index == -1) return;

    final produto = _produtos[index];

    // Suporte a Produtos Compostos: Se for composto, baixa os ingredientes recursivamente
    if (abaterComposicao &&
        produto.ehComposto &&
        produto.composicao.isNotEmpty) {
      debugPrint(
        '>>> [Estoque] 🧩 Produto COMPOSTO detectado: ${produto.nome}. Baixando ingredientes...',
      );
      for (final itemComp in produto.composicao) {
        // Ajusta resíduo de ponto flutuante: se o valor estiver a epsilon de um inteiro (ex.: 15 kg × 0,0667 = 0,9999 → 1 saco), encaixa no inteiro;
        // senão mantém a fração real (não zera quantidades pequenas legítimas)
        // Modo direto (baixaProporcionalComposicao = false): baixa a quantidade vendida inteira APENAS
        // nos ingredientes que têm conversão definida (ex.: saco). Os demais seguem proporcionais.
        final raw =
            (!baixaProporcionalComposicao && itemComp.pesoTotalSaco != null)
            ? quantidade
            : quantidade * itemComp.quantidade;
        final qtdIngrediente = (raw - raw.roundToDouble()).abs() < 0.0005
            ? raw.roundToDouble()
            : raw;
        registrarSaidaEstoque(
          produtoId: itemComp.produtoId,
          quantidade: qtdIngrediente,
          motivo: motivo ?? 'venda_composicao',
          observacao:
              'Baixa via composição de ${produto.nome} (${observacao ?? ""})',
          usuario: usuario,
          notify: false,
        );
      }
      // Produto composto com baixarEstoqueProprio = false (ex.: Chop controlado
      // pelo Barril em ml): a baixa acontece APENAS nos ingredientes. O estoque
      // deste produto (e seu histórico) não são alterados — ele fica "ilimitado".
      if (!produto.baixarEstoqueProprio) {
        debugPrint(
          '>>> [Estoque] ⏭️ ${produto.nome} não baixa estoque próprio (só ingredientes).',
        );
        return;
      }
    }

    // Abatimento proporcional do estoque por fornecedor
    final mapaEstoque = Map<String, double>.from(
      produto.estoquePorFornecedor ?? {},
    );
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
    if (quantidadeRestante > 0 &&
        (fornecedorNome == null || fornecedorNome.isEmpty)) {
      if (produto.fornecedorNome != null &&
          produto.fornecedorNome!.isNotEmpty) {
        final nomeFornPrincipal = produto.fornecedorNome!;
        double estoquePrincipal = mapaEstoque[nomeFornPrincipal] ?? 0.0;
        if (estoquePrincipal > 0) {
          if (estoquePrincipal >= quantidadeRestante) {
            mapaEstoque[nomeFornPrincipal] =
                estoquePrincipal - quantidadeRestante;
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
      final key =
          fornecedorNome ??
          (mapaEstoque.keys.isNotEmpty ? mapaEstoque.keys.first : 'Geral');
      mapaEstoque[key] = (mapaEstoque[key] ?? 0.0) - quantidadeRestante;
    }

    // ESTOQUES: a venda acontece no estoque PRINCIPAL ("o meu"). Se o saldo não
    // estiver lá, o app TRAZ o que falta dos outros estoques — uma transferência
    // de verdade, com as duas pontas no histórico — e só então baixa a venda.
    //
    // Produto que ainda não tem saldo separado por estoque (`estoquePorEstoque`
    // vazio) NÃO passa por aqui: segue exatamente como sempre, sem nenhuma
    // conversão do catálogo que já existia.
    final transferenciasDaBaixa = <EstoqueHistorico>[];
    Map<String, double>? mapaEstoques;
    // Produto que ainda não tem saldo separado NÃO passava por aqui — e segue
    // sem passar quando a operação não nomeia um estoque (venda, saída geral):
    // é o que mantém o catálogo antigo funcionando sem conversão nenhuma.
    //
    // A exceção é quando a operação nomeia um estoque (saída pelo diálogo de
    // Ajustar, ajuste em massa com Loja/Depósito escolhido): aí o saldo daquele
    // estoque precisa mexer, e o normalizador cria o mapa jogando o total no
    // estoque padrão antes da baixa — o total não muda.
    if (produto.estoquePorEstoque.isNotEmpty || estoqueId != null) {
      mapaEstoques = produto.estoquePorEstoque.isNotEmpty
          ? Map<String, double>.from(produto.estoquePorEstoque)
          : _mapaEstoquesNormalizado(produto);
      final destino =
          estoquePorId(_estoques, estoqueId)?.id ??
          estoquePrincipalAtual?.id ??
          Estoque.loja().id;
      final saldoDestino = mapaEstoques[destino] ?? 0.0;

      if (transferirParaEstoquePrincipal && saldoDestino < quantidade) {
        final plano = planejarReposicaoDeEstoque(
          saldos: mapaEstoques,
          destinoId: destino,
          faltando: quantidade - saldoDestino,
          preferidoId: produto.estoquePadraoId,
        );
        var trazido = 0.0;
        for (final passo in plano) {
          mapaEstoques[passo.estoqueId] =
              (mapaEstoques[passo.estoqueId] ?? 0.0) - passo.quantidade;
          trazido += passo.quantidade;

          final agora = DateTime.now();
          final carimbo =
              '${agora.millisecondsSinceEpoch}_transfvenda_${passo.estoqueId}';
          final texto =
              'Transferência automática (venda): '
              '${nomeDoEstoque(_estoques, passo.estoqueId)} → '
              '${nomeDoEstoque(_estoques, destino)} (${_qtdTexto(passo.quantidade)})'
              '${observacao != null && observacao.isNotEmpty ? ' | $observacao' : ''}';
          transferenciasDaBaixa.add(
            EstoqueHistorico(
              id: '${carimbo}_sai',
              produtoId: produtoId,
              data: agora,
              quantidade: -passo.quantidade,
              tipo: 'saida',
              usuario: usuario,
              motivo: 'transferencia',
              observacao: texto,
            ),
          );
          transferenciasDaBaixa.add(
            EstoqueHistorico(
              id: '${carimbo}_ent',
              produtoId: produtoId,
              data: agora,
              quantidade: passo.quantidade,
              tipo: 'entrada',
              usuario: usuario,
              motivo: 'transferencia',
              observacao: texto,
            ),
          );
        }
        if (trazido > 0) {
          mapaEstoques[destino] = saldoDestino + trazido;
          mapaEstoques.removeWhere((k, v) => v == 0 && k != destino);
          debugPrint(
            '>>> [Estoque] 🔀 Venda de ${produto.nome}: transferidos '
            '${_qtdTexto(trazido)} para ${nomeDoEstoque(_estoques, destino)}',
          );
        }
      }
      // A baixa da venda sai do estoque onde ela aconteceu — pode ficar negativa
      // quando não há mercadoria em lugar nenhum (comportamento de sempre).
      mapaEstoques[destino] = (mapaEstoques[destino] ?? 0.0) - quantidade;
    }

    final produtoAtualizado = produto.copyWith(
      estoque: produto.estoque - quantidade,
      estoquePorFornecedor: mapaEstoque,
      estoquePorEstoque: mapaEstoques ?? produto.estoquePorEstoque,
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
      usuarioNome: usuario,
    );

    // BAIXA FEFO NOS LOTES: se o produto possui lotes com validade, abate
    // primeiro dos lotes que vencem antes (controle de validade para ração,
    // medicamentos etc.). A quantidade abatida sai do estoque dos lotes.
    if (_lotesProdutos.any(
      (l) => l.produtoId == produtoId && l.quantidade > 0,
    )) {
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
      id:
          DateTime.now().millisecondsSinceEpoch.toString() +
          '_${tipoHistorico}_' +
          produtoId,
      produtoId: produtoId,
      data: DateTime.now(),
      quantidade: -quantidade,
      tipo: tipoHistorico,
      observacao:
          (observacao ?? '') + (motivo != null ? ' (Motivo: $motivo)' : ''),
      usuario: usuario,
      fornecedorNome: fornecedorNome,
      custoUnitario: custoUnit > 0 ? custoUnit : null,
      valorCusto: valorCusto != null && valorCusto > 0 ? valorCusto : null,
      motivo: motivo,
    );
    _estoqueHistorico.add(historico);

    // As transferências feitas para atender ESTA venda entram no histórico na
    // sequência (saída do outro estoque + entrada no principal), antes da baixa
    // — é o rastro que explica de onde a mercadoria veio.
    if (transferenciasDaBaixa.isNotEmpty) {
      for (final t in transferenciasDaBaixa) {
        _estoqueHistorico.add(t);
        _enviarMudancaSupabase(
          SupabaseService.tableEstoqueHistorico,
          t.toMap(),
        );
      }
      _marcarSujo(LocalStorageService.keyEstoqueHistorico);
    }

    if (notify) notifyListeners();
    // Enviar mudança para Supabase em segundo plano de forma assíncrona (não-bloqueante)
    _enviarMudancaSupabase(
      SupabaseService.tableEstoqueHistorico,
      historico.toMap(),
    );
  }

  // ============ CONSUMO INTERNO DA LOJA ============

  /// Lança uma saída de estoque como consumo interno da loja (uso próprio,
  /// descarte controlado). Diferente da venda, não gera faturamento; diferente
  /// da quebra, é um consumo operacional planejado. Cada saída vira registro
  /// no histórico com motivo 'consumo_interno' — a tela de consumo interno
  /// filtra por ele e soma o valor de custo consumido.
  Future<void> registrarConsumoInterno({
    required String produtoId,
    required double quantidade,
    String? observacao,
    String? usuario,
  }) async {
    final produtoIndex = _produtos.indexWhere((p) => p.id == produtoId);
    if (produtoIndex == -1) return;
    final produto = _produtos[produtoIndex];
    final motivoTexto = (observacao ?? '').trim();
    await registrarSaidaEstoque(
      produtoId: produtoId,
      quantidade: quantidade,
      motivo: 'consumo_interno',
      observacao: motivoTexto.isEmpty
          ? 'Consumo interno da loja'
          : 'Consumo interno: $motivoTexto',
      usuario: usuario,
      fornecedorNome: produto.fornecedorNome,
      custoUnitarioOverride:
          (produto.precoCusto ?? 0) > 0 ? produto.precoCusto : null,
    );
    debugPrint(
      '>>> [ConsumoInterno] ✓ ${produto.nome}: ${quantidade}un',
    );
  }

  /// Totais de consumo interno da loja (para o dashboard): quantidade de
  /// lançamentos, unidades consumidas e valor de custo.
  ({int lancamentos, double unidades, double custo}) totaisConsumoInterno(
    List<EstoqueHistorico> movimentos,
  ) {
    int lancamentos = 0;
    double unidades = 0;
    double custo = 0;
    for (final h in movimentos) {
      if (!h.ehConsumoInterno) continue;
      lancamentos++;
      unidades += h.quantidade.abs();
      custo += h.valorCusto ?? 0.0;
    }
    return (lancamentos: lancamentos, unidades: unidades, custo: custo);
  }

  // ============ INVENTÁRIO (Contagem da Loja) ============

  /// Aplica o resultado de um inventário de conferência: corrige o estoque de
  /// cada produto para a contagem real da loja e registra a diferença no
  /// histórico (motivo 'inventario'). Faltas viram saída; sobras viram entrada;
  /// uma contagem de **0** é ZERAMENTO (fica como 'zerado' no histórico, sem
  /// virar entrada/saída nem sobra/falta).
  ///
  /// [contagens] mapeia produtoId -> quantidade contada na loja.
  /// Retorna um resumo para a tela: {conferidos, faltas, sobras, zerados,
  /// ajustados}.
  Future<Map<String, int>> aplicarInventario(
    Map<String, double> contagens, {
    String? usuario,
  }) async {
    var conferidos = 0, faltas = 0, sobras = 0, ajustados = 0, zerados = 0;

    // Itens que realmente mudaram: viram o lote do inventário (auditoria + desfazer).
    final itens = <AjusteEstoqueLoteItem>[];

    for (final entry in contagens.entries) {
      final index = _produtos.indexWhere((p) => p.id == entry.key);
      if (index == -1) continue; // produto não encontrado
      final produto = _produtos[index];
      final estoqueAnterior = produto.estoque;

      final diferenca = await _ajustarEstoquePara(
        produtoId: entry.key,
        novoEstoque: entry.value,
        motivo: 'inventario',
        origemMovimento: 'Inventário',
        rotuloDestino: 'contado',
        abaterComposicao: true, // comportamento original do inventário
        usuario: usuario,
        // Contou 0? O saldo foi levado a 0 de propósito: registra como
        // ZERAMENTO ('zerado') em vez de sobra/falta.
        zeramento: entry.value == 0,
      );
      if (diferenca == null) continue;

      conferidos++;
      if (diferenca.abs() < 0.0005) continue; // contagem confere — sem ajuste

      if (entry.value == 0) {
        zerados++;
      } else if (diferenca < 0) {
        faltas++;
      } else {
        sobras++;
      }
      ajustados++;
      itens.add(
        AjusteEstoqueLoteItem(
          produtoId: produto.id,
          produtoNome: produto.nome,
          produtoCodigo: produto.codigo,
          estoqueAnterior: estoqueAnterior,
          estoqueNovo: entry.value,
        ),
      );
    }

    // O inventário também entra no Histórico de ajustes e pode ser desfeito.
    _registrarLoteAjuste(itens: itens, origem: 'Inventário', usuario: usuario);

    _marcarSujo(LocalStorageService.keyEstoqueHistorico);
    notifyListeners();
    return {
      'conferidos': conferidos,
      'faltas': faltas,
      'sobras': sobras,
      'zerados': zerados,
      'ajustados': ajustados,
    };
  }

  /// Ajusta o estoque de um produto para [novoEstoque], registrando a diferença
  /// no histórico de estoque (faltas viram saída, sobras viram entrada).
  ///
  /// Retorna a diferença aplicada (0 = já estava no valor desejado) ou null
  /// quando o produto não existe mais.
  /// Corrige o estoque do produto para [novoEstoque].
  ///
  /// [estoqueId] corrige o saldo de UM estoque (útil quando o produto está
  /// separado em Loja/Depósito e a contagem é de um lugar só); sem ele, o
  /// ajuste é sobre o total do produto, como sempre foi.
  Future<double?> _ajustarEstoquePara({
    required String produtoId,
    required double novoEstoque,
    required String motivo,
    required String origemMovimento,
    String rotuloDestino = 'novo',
    bool abaterComposicao = false,
    String? usuario,
    String? observacao,
    String? estoqueId,

    /// true = a diferença existe só para LEVAR O SALDO A 0 (zeramento). Grava
    /// o movimento como 'zerado' em vez de entrada/saída, para o zeramento não
    /// aparecer como "entrada" (ex.: saldo −193 → 0) nos totais das telas.
    bool zeramento = false,
  }) async {
    final index = _produtos.indexWhere((p) => p.id == produtoId);
    if (index == -1) return null;

    final produto = _produtos[index];
    final sistema = produto.estoque;
    // Numa contagem de UM estoque, a comparação é com o saldo DAQUELE estoque;
    // e o ajuste não pode trazer mercadoria de outro lugar (senão o que foi
    // contado aqui seria mascarado pelo que existe no depósito).
    // Produto ainda sem saldo separado (`estoquePorEstoque` vazio) também entra
    // aqui: o saldo do estoque escolhido é o dele (0 quando o estoque não é o
    // padrão do produto) e a entrada/saída logo abaixo cria o mapa dele.
    final porEstoque = estoqueId != null;
    final base = estoqueId != null
        ? saldoNoEstoque(produto, estoqueId)
        : sistema;
    final diferenca = novoEstoque - base;
    final arredondado = (diferenca - diferenca.roundToDouble()).abs() < 0.0005
        ? diferenca.roundToDouble()
        : diferenca;

    if (arredondado.abs() < 0.0005) return 0; // já está no valor desejado

    final detalhe = zeramento
        ? '$origemMovimento — ESTOQUE ZERADO '
              '(sistema: ${base.toStringAsFixed(2)} → saldo: 0.00)'
        : arredondado < 0
        ? '$origemMovimento — faltando ${arredondado.abs().toStringAsFixed(2)} '
              '(sistema: ${base.toStringAsFixed(2)} → $rotuloDestino: ${novoEstoque.toStringAsFixed(2)})'
        : '$origemMovimento — sobra de ${arredondado.toStringAsFixed(2)} '
              '(sistema: ${base.toStringAsFixed(2)} → $rotuloDestino: ${novoEstoque.toStringAsFixed(2)})';
    final observacaoFinal = [
      detalhe,
      if (observacao != null && observacao.trim().isNotEmpty) observacao.trim(),
    ].join(' | ');

    if (arredondado < 0) {
      await registrarSaidaEstoque(
        produtoId: produtoId,
        quantidade: arredondado.abs(),
        motivo: motivo,
        observacao: observacaoFinal,
        usuario: usuario,
        fornecedorNome: produto.fornecedorNome,
        custoUnitarioOverride: (produto.precoCusto ?? 0.0) > 0
            ? produto.precoCusto
            : null,
        abaterComposicao: abaterComposicao,
        estoqueId: estoqueId,
        transferirParaEstoquePrincipal: !porEstoque,
        tipoHistorico: zeramento ? 'zerado' : 'saida',
      );
    } else {
      await registrarEntradaEstoque(
        produtoId: produtoId,
        quantidade: arredondado,
        observacao: observacaoFinal,
        usuario: usuario,
        fornecedorNome: 'Geral',
        estoqueId: estoqueId,
        tipoHistorico: zeramento ? 'zerado' : 'entrada',
      );
    }

    return arredondado;
  }

  // ============ AJUSTE EM MASSA (ESTOQUE E PREÇO) ============

  /// Em modo lote, evita gravar/sincronizar/notificar item a item (o que
  /// travava a tela em lotes de milhares de produtos).
  bool _emLoteEmMassa = false;

  /// Produtos alterados no lote atual, aguardando gravação em bloco.
  final Map<String, Map<String, dynamic>> _loteProdutosPendentes = {};

  /// Mudanças de histórico (tabela -> registros) aguardando envio em bloco.
  final Map<String, List<Map<String, dynamic>>> _loteMudancasPendentes = {};

  /// Envia uma mudança para a nuvem. Em modo lote, apenas acumula para o envio
  /// em bloco no fim (evita milhares de requisições individuais).
  void _enviarMudancaSupabase(
    String tabela,
    Map<String, dynamic> dados, {
    String? evento,
  }) {
    if (_emLoteEmMassa) {
      (_loteMudancasPendentes[tabela] ??= []).add(dados);
      return;
    }
    enviarMudancaParaSupabase(tabela, dados, evento: evento);
  }

  /// Envia uma lista de registros para o Supabase em blocos de 100, em segundo plano.
  Future<void> _enviarBlocosParaNuvem(
    String tabela,
    List<Map<String, dynamic>> dados,
  ) async {
    if (dados.isEmpty) return;
    for (var i = 0; i < dados.length; i += 100) {
      final fim = (i + 100 < dados.length) ? i + 100 : dados.length;
      final bloco = dados.sublist(i, fim);
      try {
        await _supabaseService
            .upsertLote(tabela, bloco)
            .timeout(const Duration(minutes: 2));
      } catch (e) {
        debugPrint(
          '>>> [DataService] ⚠️ Falha ao enviar bloco de $tabela (${bloco.length} registros): $e',
        );
        _adicionarSincronizacaoPendente();
        return;
      }
    }
    debugPrint(
      '>>> [DataService] ✅ $tabela: ${dados.length} registro(s) enviados à nuvem em blocos.',
    );
  }

  /// Aplica ajustes em massa de **estoque e/ou preço** em vários produtos de
  /// uma só vez.
  ///
  /// [novosEstoques] e [novosPrecos] mapeiam produtoId -> novo valor; o que não
  /// for informado permanece como está. Cada diferença de estoque vira uma
  /// movimentação no histórico de estoque e cada mudança de preço entra no
  /// histórico de alterações do produto, mantendo a rastreabilidade.
  ///
  /// Retorna um resumo: {avaliados, estoquesAjustados, entradas, saidas,
  /// zeramentos, precosAjustados, semAlteracao}.
  Future<Map<String, int>> aplicarAjusteEmMassa({
    Map<String, double> novosEstoques = const {},
    Map<String, double> novosPrecos = const {},

    /// Estoque ajustado por esta aplicação (null = o total do produto).
    ///
    /// Passado para baixo até o histórico e para o lote, para que o DESFAZER
    /// devolva a quantidade ao mesmo lugar.
    String? estoqueId,
    String? usuario,
    String? motivo,
    String? observacao,
  }) async {
    var avaliados = 0, estoquesAjustados = 0, entradas = 0, saidas = 0;
    var precosAjustados = 0, semAlteracao = 0, zeramentos = 0;

    final ids = <String>{...novosEstoques.keys, ...novosPrecos.keys};

    // Itens que realmente mudaram — viram o registro do lote (auditoria + desfazer).
    final itensDoLote = <AjusteEstoqueLoteItem>[];

    for (final id in ids) {
      var alterou = false;
      final index = _produtos.indexWhere((p) => p.id == id);
      final produtoAntes = index == -1 ? null : _produtos[index];

      double? estoqueAnterior;
      double? estoqueNovoEfetivo;
      double? precoAnterior;
      double? precoNovoEfetivo;

      // 1. Estoque (gera movimentação no histórico de estoque)
      final novoEstoque = novosEstoques[id];
      if (novoEstoque != null) {
        estoqueAnterior = produtoAntes == null
            ? null
            : (estoqueId != null
                  ? saldoNoEstoque(produtoAntes, estoqueId)
                  : produtoAntes.estoque);
        // Levar o saldo a 0 é ZERAMENTO (inclusive no botão "ZERAR ESTOQUE"
        // da tela em massa): registra como 'zerado' e não conta como
        // entrada/saída — um saldo negativo levado a 0 não é mercadoria que
        // entrou nem saiu.
        final ehZeramento = novoEstoque == 0;
        final diferenca = await _ajustarEstoquePara(
          produtoId: id,
          novoEstoque: novoEstoque,
          motivo: motivo ?? (ehZeramento ? 'zerar_estoque' : 'ajuste'),
          origemMovimento: 'Ajuste em massa',
          estoqueId: estoqueId,
          usuario: usuario,
          observacao: observacao,
          zeramento: ehZeramento,
        );
        if (diferenca != null) {
          avaliados++;
          if (diferenca.abs() >= 0.0005) {
            if (ehZeramento) {
              zeramentos++;
            } else if (diferenca < 0) {
              saidas++;
            } else {
              entradas++;
            }
            estoquesAjustados++;
            alterou = true;
            estoqueNovoEfetivo = estoqueAnterior != null
                ? estoqueAnterior + diferenca
                : null;
          }
        }
      }

      // 2. Preço (gera registro no histórico de alterações do produto)
      final novoPreco = novosPrecos[id];
      if (novoPreco != null && produtoAntes != null) {
        if ((produtoAntes.preco - novoPreco).abs() >= 0.005) {
          precoAnterior = produtoAntes.preco;
          precoNovoEfetivo = novoPreco;
          await updateProduto(
            produtoAntes.copyWith(preco: novoPreco, updatedAt: DateTime.now()),
            aguardarSincronia: false,
            motivoHistorico: 'Ajuste em massa',
            observacaoHistorico: observacao,
            usuarioNome: usuario,
          );
          precosAjustados++;
          alterou = true;
        }
      }

      if (estoqueNovoEfetivo != null || precoNovoEfetivo != null) {
        itensDoLote.add(
          AjusteEstoqueLoteItem(
            produtoId: id,
            produtoNome: produtoAntes?.nome ?? '',
            produtoCodigo: produtoAntes?.codigo,
            estoqueAnterior: estoqueAnterior,
            estoqueNovo: estoqueNovoEfetivo,
            precoAnterior: precoAnterior,
            precoNovo: precoNovoEfetivo,
            estoqueId: estoqueId,
          ),
        );
      }

      if (!alterou) semAlteracao++;
    }

    // Registra o lote do ajuste: quem aplicou, quando, o que mudou e os valores
    // anteriores (necessários para desfazer depois).
    _registrarLoteAjuste(
      itens: itensDoLote,
      origem: 'Ajuste em massa',
      usuario: usuario,
      observacao: observacao,
    );

    _marcarSujo(LocalStorageService.keyEstoqueHistorico);
    _marcarSujo(LocalStorageService.keyProdutos);
    notifyListeners();
    return {
      'avaliados': avaliados,
      'estoquesAjustados': estoquesAjustados,
      'entradas': entradas,
      'saidas': saidas,
      'zeramentos': zeramentos,
      'precosAjustados': precosAjustados,
      'semAlteracao': semAlteracao,
    };
  }

  /// Monta e persiste o registro do ajuste em massa (auditoria + desfazer).
  /// Devolve o lote criado ou null quando nada mudou.
  AjusteEstoqueLote? _registrarLoteAjuste({
    required List<AjusteEstoqueLoteItem> itens,
    required String origem,
    String? usuario,
    String? observacao,
  }) {
    if (itens.isEmpty) return null;

    final lote = AjusteEstoqueLote(
      id: 'AJL-${DateTime.now().millisecondsSinceEpoch}',
      data: DateTime.now(),
      usuario: usuario,
      observacao: observacao,
      origem: origem,
      itens: itens,
    );
    _ajustesEstoqueLote.insert(0, lote);
    _manterApenasRecentes(
      _ajustesEstoqueLote,
      100,
      'Ajustes de Estoque em Massa',
    );
    _ultimoAjusteLoteId = lote.id;
    _marcarSujo(LocalStorageService.keyAjustesEstoqueLote);
    _enviarMudancaSupabase(
      SupabaseService.tableAjustesEstoqueLote,
      lote.toMap(),
    );
    return lote;
  }

  /// **Zera o estoque de TODOS os produtos da empresa** (catálogo inteiro,
  /// ignorando filtros de tela).
  ///
  /// Cada item vira uma saída no histórico de estoque e o conjunto entra num
  /// lote do histórico de ajustes — então a operação pode ser DESFEITA depois,
  /// devolvendo o estoque anterior de cada produto.
  ///
  /// Retorna: {avaliados, zerados, jaZerados}.
  Future<Map<String, int>> zerarTodoEstoque({
    String? usuario,
    String? observacao,
  }) async {
    var zerados = 0, jaZerados = 0;
    final itens = <AjusteEstoqueLoteItem>[];

    // Itera sobre uma cópia dos produtos: updateProduto substitui itens da lista.
    for (final produto in List<Produto>.from(_produtos)) {
      if (produto.estoque.abs() < 0.0005) {
        jaZerados++;
        continue;
      }

      final estoqueAnterior = produto.estoque;
      final diferenca = await _ajustarEstoquePara(
        produtoId: produto.id,
        novoEstoque: 0,
        motivo: 'zerar_estoque',
        origemMovimento: 'Zerar todo o estoque',
        usuario: usuario,
        observacao: observacao,
        zeramento: true,
      );

      if (diferenca == null) continue; // produto não encontrado

      zerados++;
      itens.add(
        AjusteEstoqueLoteItem(
          produtoId: produto.id,
          produtoNome: produto.nome,
          produtoCodigo: produto.codigo,
          estoqueAnterior: estoqueAnterior,
          estoqueNovo: 0,
        ),
      );
    }

    _registrarLoteAjuste(
      itens: itens,
      origem: 'Zerar todo o estoque',
      usuario: usuario,
      observacao: observacao,
    );

    _marcarSujo(LocalStorageService.keyEstoqueHistorico);
    _marcarSujo(LocalStorageService.keyProdutos);
    notifyListeners();

    return {
      'zerados': zerados,
      'jaZerados': jaZerados,
      'avaliados': zerados + jaZerados,
    };
  }

  /// Acha o produto para movimentar estoque: na memória e, se ele não estiver
  /// lá (lista ainda carregando, empresa trocada, cache parcial), no banco
  /// local — ANTES de desistir. Era isso que fazia a entrada de estoque do
  /// cadastro falhar com "produto não encontrado" num produto que existe.
  ///
  /// Devolve o índice em `_produtos` ou -1 (produto sem id, inexistente ou de
  /// outra empresa — que nunca é adotado pela empresa aberta).
  Future<int> _indiceDoProdutoParaMovimento(String produtoId) async {
    if (produtoId.isEmpty) return -1;
    final naMemoria = _produtos.indexWhere((p) => p.id == produtoId);
    if (naMemoria != -1) return naMemoria;

    try {
      final linhas = await DatabaseService().carregarLista(
        LocalStorageService.keyProdutos,
      );
      for (final linha in linhas) {
        if (linha['id']?.toString() != produtoId) continue;
        final produto = Produto.fromMap(linha);
        // Só entra na memória o produto DESTA empresa (nunca adota o de outra).
        if (ehProdutoDeOutraEmpresa(produto.empresaId)) {
          debugPrint(
            '>>> [DataService] 🛡️ Movimento recusado: o produto '
            '$produtoId é de outra empresa.',
          );
          return -1;
        }
        _produtos.add(produto);
        debugPrint(
          '>>> [DataService] 📦 Produto $produtoId carregado do banco '
          'local para movimentar o estoque.',
        );
        return _produtos.length - 1;
      }
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Não consegui buscar o produto '
        '$produtoId no banco local: $e',
      );
    }
    return -1;
  }

  /// Ajuste pontual de **um** produto (ENTRADA/SAÍDA de quantidade), usado pelo
  /// diálogo "Ajuste de Estoque" do cadastro do produto.
  ///
  /// Além da movimentação normal no histórico de estoque, registra um lote no
  /// histórico de ajustes — assim o ajuste do cadastro também pode ser desfeito.
  /// Devolve o lote criado (ou null se nada mudou).
  ///
  /// [estoqueId] é o estoque escolhido na tela: na ENTRADA é o destino (onde a
  /// mercadoria entra) e na SAÍDA é a origem (de onde ela sai). Sem ele, entra no
  /// estoque PADRÃO do produto e sai do estoque principal da empresa.
  Future<AjusteEstoqueLote?> ajustarEstoquePontual({
    required String produtoId,
    required double quantidade,
    required bool entrada,
    String? fornecedorNome,
    String? observacao,
    String? usuario,
    String? estoqueId,
  }) async {
    if (quantidade <= 0) {
      throw Exception('Informe uma quantidade maior que zero.');
    }

    final index = await _indiceDoProdutoParaMovimento(produtoId);
    if (index == -1) {
      // A tela do cadastro mostra esta mensagem: precisa dizer o que fazer, e
      // não só "produto não encontrado".
      throw Exception(
        produtoId.isEmpty
            ? 'Salve o produto antes de dar entrada ou saída no estoque.'
            : 'Este produto não está carregado no app e não achei ele no banco '
                  'desta empresa. Abra a lista de Produtos e confirme que ele aparece lá.',
      );
    }

    final produto = _produtos[index];
    final estoqueAnterior = produto.estoque;
    // Num ajuste de UM estoque (o seletor do diálogo AJUSTAR ou o da tela de
    // Ajuste Geral), o "antes/depois" do lote é o saldo DAQUELE estoque — é o
    // que o DESFAZER precisa devolver. O total só serve quando o ajuste é sobre
    // o produto inteiro.
    final estoqueAnteriorDoLote = estoqueId == null
        ? estoqueAnterior
        : saldoNoEstoque(produto, estoqueId);
    final fornecedor = (fornecedorNome == null || fornecedorNome.trim().isEmpty)
        ? 'Geral'
        : fornecedorNome.trim();

    if (entrada) {
      await registrarEntradaEstoque(
        produtoId: produtoId,
        quantidade: quantidade,
        fornecedorNome: fornecedor,
        observacao: observacao,
        usuario: usuario,
        estoqueId: estoqueId,
      );
    } else {
      await registrarSaidaEstoque(
        produtoId: produtoId,
        quantidade: quantidade,
        fornecedorNome: fornecedor,
        motivo: 'ajuste',
        observacao: observacao,
        usuario: usuario,
        estoqueId: estoqueId,
      );
    }

    final lote = _registrarLoteAjuste(
      itens: [
        AjusteEstoqueLoteItem(
          produtoId: produtoId,
          produtoNome: produto.nome,
          produtoCodigo: produto.codigo,
          estoqueAnterior: estoqueAnteriorDoLote,
          estoqueNovo:
              estoqueAnteriorDoLote + (entrada ? quantidade : -quantidade),
          estoqueId: estoqueId,
        ),
      ],
      origem: entrada ? 'Ajuste manual (entrada)' : 'Ajuste manual (saída)',
      usuario: usuario,
      observacao: observacao,
    );

    _marcarSujo(LocalStorageService.keyEstoqueHistorico);
    _marcarSujo(LocalStorageService.keyProdutos);
    notifyListeners();
    return lote;
  }

  /// Id do último lote de ajuste em massa aplicado nesta sessão.
  String? _ultimoAjusteLoteId;

  /// Último lote aplicado (usado pelo botão DESFAZER imediato da tela de ajuste).
  AjusteEstoqueLote? get ultimoAjusteLote {
    final id = _ultimoAjusteLoteId;
    if (id == null) return null;
    final index = _ajustesEstoqueLote.indexWhere((l) => l.id == id);
    return index == -1 ? null : _ajustesEstoqueLote[index];
  }

  /// Desfaz um ajuste em massa: devolve estoque e preço de cada item ao valor
  /// que tinham antes do lote e marca o registro como desfeito.
  ///
  /// A reversão NÃO apaga o histórico: cada produto recebe uma movimentação de
  /// estorno no histórico de estoque (e uma entrada no histórico de alterações
  /// para o preço), preservando a trilha de auditoria.
  ///
  /// Retorna um resumo: {estoquesRevertidos, precosRevertidos, ignorados}.
  Future<Map<String, int>> desfazerAjusteEstoqueLote(
    String loteId, {
    String? usuario,
  }) async {
    final index = _ajustesEstoqueLote.indexWhere((l) => l.id == loteId);
    if (index == -1) {
      throw Exception('Ajuste não encontrado no histórico.');
    }

    final lote = _ajustesEstoqueLote[index];
    if (lote.desfeito) {
      throw Exception('Este ajuste já foi desfeito.');
    }

    final quem = usuario ?? lote.usuario;
    var estoquesRevertidos = 0, precosRevertidos = 0, ignorados = 0;

    for (final item in lote.itens) {
      // 1. Estoque de volta ao valor anterior
      if (item.alterouEstoque) {
        final diferenca = await _ajustarEstoquePara(
          produtoId: item.produtoId,
          novoEstoque: item.estoqueAnterior!,
          motivo: 'estorno_ajuste',
          origemMovimento: 'Desfazer ajuste (${lote.origem})',
          rotuloDestino: 'estoque anterior',
          estoqueId: item.estoqueId,
          usuario: quem,
          observacao:
              'Estorno do ajuste ${lote.id}'
              '${lote.observacao != null && lote.observacao!.trim().isNotEmpty ? ' | ${lote.observacao!.trim()}' : ''}',
        );
        if (diferenca == null) {
          ignorados++; // produto não existe mais
        } else {
          estoquesRevertidos++;
        }
      }

      // 2. Preço (de venda) de volta ao valor anterior
      if (item.alterouPreco) {
        final idx = _produtos.indexWhere((p) => p.id == item.produtoId);
        if (idx == -1) {
          ignorados++;
        } else {
          await updateProduto(
            _produtos[idx].copyWith(
              preco: item.precoAnterior!,
              updatedAt: DateTime.now(),
            ),
            aguardarSincronia: false,
            motivoHistorico: 'Estorno de ajuste (${lote.origem})',
            observacaoHistorico:
                'Valor anterior restaurado (ajuste ${lote.id})',
            usuarioNome: quem,
          );
          precosRevertidos++;
        }
      }
    }

    _ajustesEstoqueLote[index] = lote.copyWith(
      desfeito: true,
      dataDesfeito: DateTime.now(),
      usuarioDesfeito: quem,
    );

    _marcarSujo(LocalStorageService.keyAjustesEstoqueLote);
    _marcarSujo(LocalStorageService.keyEstoqueHistorico);
    _marcarSujo(LocalStorageService.keyProdutos);
    _enviarMudancaSupabase(
      SupabaseService.tableAjustesEstoqueLote,
      _ajustesEstoqueLote[index].toMap(),
    );
    notifyListeners();

    return {
      'estoquesRevertidos': estoquesRevertidos,
      'precosRevertidos': precosRevertidos,
      'ignorados': ignorados,
    };
  }

  // ============ CRUD NotaEntrada ============

  Future<void> addNotaEntrada(NotaEntrada nota) async {
    _notasEntrada.add(nota);
    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();

    // Marcar coleções impactadas para salvamento automático seletivo
    _marcarSujo(LocalStorageService.keyNotasEntrada);
    _marcarSujo(
      LocalStorageService.keyProdutos,
    ); // Notas de entrada afetam estoque
    _marcarSujo(
      LocalStorageService.keyEstoqueHistorico,
    ); // Notas de entrada geram histórico

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tableNotasEntrada,
      nota.toMap(),
    );
    _sincronizarNotasComDrive();
  }

  void updateNotaEntrada(NotaEntrada nota) {
    final index = _notasEntrada.indexWhere((n) => n.id == nota.id);
    if (index != -1) {
      _notasEntrada[index] = nota;
      notifyListeners();
      _salvarAutomaticamente();
      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      enviarMudancaParaSupabase(
        SupabaseService.tableNotasEntrada,
        nota.toMap(),
      );
    }
  }

  void deleteNotaEntrada(String notaId) {
    _notasEntrada.removeWhere((n) => n.id == notaId);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyNotasEntrada, notaId);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyNotasEntrada);
    // Propagar delete para Supabase
    enviarMudancaParaSupabase(SupabaseService.tableNotasEntrada, {
      'id': notaId,
    }, evento: 'DELETE');
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
          final novoEstoque = (produto.estoque - item.quantidade).clamp(
            0.0,
            double.infinity,
          );

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
    await enviarMudancaParaSupabase(SupabaseService.tableNotasEntrada, {
      'id': notaId,
    }, evento: 'DELETE');
  }

  // ============ CRUD PedidoCompra ============

  /// Busca um pedido de compra pelo id (ou `null` se não existir mais).
  PedidoCompra? pedidoCompraPorId(String id) {
    for (final pedido in _pedidosCompra) {
      if (pedido.id == id) return pedido;
    }
    return null;
  }

  /// Próximo número da série PC-0001.
  ///
  /// A numeração é derivada dos pedidos já carregados. O id continua sendo
  /// único por timestamp, então uma numeração repetida entre dois aparelhos
  /// não faz um pedido sobrescrever o outro.
  String proximoNumeroPedidoCompra() {
    var maior = 0;
    final regex = RegExp(r'PC-(\d+)', caseSensitive: false);
    for (final pedido in _pedidosCompra) {
      final match = regex.firstMatch(pedido.numero);
      if (match == null) continue;
      final numero = int.tryParse(match.group(1) ?? '') ?? 0;
      if (numero > maior) maior = numero;
    }
    return 'PC-${(maior + 1).toString().padLeft(4, '0')}';
  }

  /// Valida os itens e garante um id único por item.
  ///
  /// O formulário cria itens novos com `id` vazio e, na edição, eles precisam
  /// receber id antes de entrar no pedido — é esse id que identifica o item no
  /// recebimento (quantidades por item) e no histórico. Ids repetidos também
  /// são trocados, porque duas linhas com o mesmo id fariam o recebimento
  /// atualizar o item errado.
  List<ItemPedidoCompra> _normalizarItensPedidoCompra(
    List<ItemPedidoCompra> itens,
  ) {
    final validos = <ItemPedidoCompra>[];
    final idsUsados = <String>{};
    final base = DateTime.now().microsecondsSinceEpoch;
    var sequencia = 0;

    for (final item in itens) {
      if (item.produtoId.isEmpty || item.quantidade <= 0) continue;
      var id = item.id.trim();
      if (id.isEmpty || idsUsados.contains(id)) {
        do {
          id = '${base}_item_${sequencia++}';
        } while (idsUsados.contains(id));
      }
      idsUsados.add(id);
      validos.add(id == item.id ? item : item.copyWith(id: id));
    }
    return validos;
  }

  /// Cria e salva um pedido de compra.
  ///
  /// [enviar] já nasce como `enviado` (o operador confirmou o pedido ao
  /// fornecedor). Sem ele o pedido fica em `rascunho` e pode ser editado.
  Future<PedidoCompra> criarPedidoCompra({
    required String fornecedorNome,
    String fornecedorId = '',
    String? fornecedorCnpj,
    String? fornecedorTelefone,
    required List<ItemPedidoCompra> itens,
    String? observacao,
    String? usuario,
    DateTime? previsaoEntrega,
    String? estoqueDestinoId,
    String? estoqueDestinoNome,
    bool enviar = false,
  }) async {
    final itensValidos = _normalizarItensPedidoCompra(itens);
    if (itensValidos.isEmpty) {
      throw ArgumentError(
        'Informe pelo menos um produto com quantidade maior que zero.',
      );
    }

    final agora = DateTime.now();
    final id = '${agora.microsecondsSinceEpoch}_pedido_compra';
    final pedido = PedidoCompra(
      id: id,
      numero: proximoNumeroPedidoCompra(),
      fornecedorId: fornecedorId,
      fornecedorNome: fornecedorNome.trim().isEmpty
          ? 'Não informado'
          : fornecedorNome.trim(),
      fornecedorCnpj: fornecedorCnpj,
      fornecedorTelefone: fornecedorTelefone,
      status: enviar ? StatusPedidoCompra.enviado : StatusPedidoCompra.rascunho,
      itens: itensValidos,
      observacao: observacao,
      usuario: usuario,
      estoqueDestinoId: estoqueDestinoId,
      estoqueDestinoNome: estoqueDestinoNome,
      dataCriacao: agora,
      dataEnvio: enviar ? agora : null,
      previsaoEntrega: previsaoEntrega,
      createdAt: agora,
      updatedAt: agora,
    );

    _pedidosCompra.add(pedido);
    _marcarSujo(LocalStorageService.keyPedidosCompra);
    notifyListeners();

    await _persistirPedidoCompraLocal(pedido);
    await _recalcularFlagsPedidoCompra(
      produtoIds: pedido.itens.map((item) => item.produtoId).toSet(),
    );
    enviarMudancaParaSupabase(
      SupabaseService.tablePedidosCompra,
      pedido.toMap(),
    );

    return pedido;
  }

  /// Cria um pedido para cada fornecedor informado.
  ///
  /// É o caminho usado pelo relatório de reposição: os itens selecionados são
  /// separados por fornecedor e cada grupo vira um pedido independente.
  Future<List<PedidoCompra>> criarPedidosCompraPorFornecedor({
    required Map<String, List<ItemPedidoCompra>> itensPorFornecedor,
    String? usuario,
    String? observacao,
    bool enviar = false,
  }) async {
    final criados = <PedidoCompra>[];
    for (final entry in itensPorFornecedor.entries) {
      if (entry.value.isEmpty) continue;
      criados.add(
        await criarPedidoCompra(
          fornecedorNome: entry.key,
          itens: entry.value,
          usuario: usuario,
          observacao: observacao,
          enviar: enviar,
        ),
      );
    }
    return criados;
  }

  /// Atualiza um pedido existente (edição de rascunho, envio etc.).
  Future<void> atualizarPedidoCompra(PedidoCompra pedido) async {
    final index = _pedidosCompra.indexWhere((p) => p.id == pedido.id);
    if (index == -1) {
      throw StateError('Pedido de compra não encontrado.');
    }
    final anterior = _pedidosCompra[index];
    final itensNormalizados = _normalizarItensPedidoCompra(pedido.itens);
    if (itensNormalizados.isEmpty) {
      throw ArgumentError(
        'Informe pelo menos um produto com quantidade maior que zero.',
      );
    }
    final produtosAfetados = <String>{
      ...anterior.itens.map((item) => item.produtoId),
      ...itensNormalizados.map((item) => item.produtoId),
    };

    final atualizado = pedido.copyWith(
      itens: itensNormalizados,
      updatedAt: DateTime.now(),
    );
    _pedidosCompra[index] = atualizado;
    _marcarSujo(LocalStorageService.keyPedidosCompra);
    notifyListeners();

    await _persistirPedidoCompraLocal(atualizado);
    await _recalcularFlagsPedidoCompra(produtoIds: produtosAfetados);
    enviarMudancaParaSupabase(
      SupabaseService.tablePedidosCompra,
      atualizado.toMap(),
    );
  }

  /// Marca o pedido como enviado ao fornecedor.
  Future<void> marcarPedidoCompraEnviado(String pedidoId) async {
    final pedido = pedidoCompraPorId(pedidoId);
    if (pedido == null) return;
    // Só rascunho vira "enviado". Um pedido parcialmente recebido continua
    // como `recebido_parcial` — voltar para `enviado` esconderia o progresso.
    if (pedido.status != StatusPedidoCompra.rascunho) return;
    await atualizarPedidoCompra(
      pedido.copyWith(
        status: StatusPedidoCompra.enviado,
        dataEnvio: pedido.dataEnvio ?? DateTime.now(),
      ),
    );
  }

  /// Cancela um pedido em aberto sem mexer no estoque.
  Future<void> cancelarPedidoCompra(
    String pedidoId, {
    String? motivo,
    String? usuario,
  }) async {
    final pedido = pedidoCompraPorId(pedidoId);
    if (pedido == null) return;
    if (pedido.recebido) {
      throw StateError(
        'Este pedido já foi recebido. Para devolver a mercadoria use uma '
        'saída/ajuste de estoque.',
      );
    }
    if (pedido.cancelado) return;

    final agora = DateTime.now();
    final cancelado = pedido.copyWith(
      status: StatusPedidoCompra.cancelado,
      dataCancelamento: agora,
      motivoCancelamento: motivo ?? pedido.motivoCancelamento,
      usuario: usuario ?? pedido.usuario,
      updatedAt: agora,
    );
    await atualizarPedidoCompra(cancelado);
  }

  /// Exclui o pedido do sistema. As entradas de estoque já lançadas ficam no
  /// histórico (excluir um pedido recebido não estorna mercadoria).
  Future<void> deletePedidoCompra(String pedidoId) async {
    final index = _pedidosCompra.indexWhere((p) => p.id == pedidoId);
    if (index == -1) return;
    final produtosAfetados = _pedidosCompra[index].itens
        .map((item) => item.produtoId)
        .toSet();
    _pedidosCompra.removeAt(index);
    _removerLinhaLocal(LocalStorageService.keyPedidosCompra, pedidoId);
    _marcarSujo(LocalStorageService.keyPedidosCompra);
    notifyListeners();
    await _recalcularFlagsPedidoCompra(produtoIds: produtosAfetados);
    enviarMudancaParaSupabase(SupabaseService.tablePedidosCompra, {
      'id': pedidoId,
    }, evento: 'DELETE');
  }

  /// Dá entrada no estoque dos itens recebidos do pedido.
  ///
  /// [quantidadesPorItem] usa o id do item do pedido como chave. Quando o mapa
  /// vem vazio (ou um item não é informado), a quantidade pendente inteira é
  /// recebida — é o atalho "receber tudo".
  ///
  /// Cada item chama [registrarEntradaEstoque], então o saldo do produto, o
  /// saldo por fornecedor, o saldo por estoque e o histórico continuam sendo
  /// atualizados pelo fluxo já existente.
  Future<ResultadoRecebimentoPedidoCompra> receberPedidoCompra({
    required String pedidoId,
    Map<String, double> quantidadesPorItem = const {},
    String? estoqueId,
    String? usuario,
    bool atualizarCusto = true,
  }) async {
    final pedido = pedidoCompraPorId(pedidoId);
    if (pedido == null) {
      throw StateError('Pedido de compra não encontrado.');
    }
    if (pedido.cancelado) {
      throw StateError('Pedido cancelado não pode ser recebido.');
    }
    if (!pedido.podeReceber) {
      throw StateError('Todos os itens deste pedido já foram recebidos.');
    }

    final receberTudo = quantidadesPorItem.isEmpty;
    final itensAtualizados = <ItemPedidoCompra>[];
    final avisos = <String>[];
    var itensRecebidos = 0;
    var quantidadeRecebida = 0.0;
    final destinoId = (estoqueId ?? pedido.estoqueDestinoId ?? '').trim();
    final destinoNome = nomeDoEstoque(
      _estoques,
      destinoId.isEmpty ? null : destinoId,
    );

    for (final item in pedido.itens) {
      final pendente = item.quantidadePendente;
      if (pendente <= 0.0001) {
        itensAtualizados.add(item);
        continue;
      }
      final solicitada = receberTudo
          ? pendente
          : (quantidadesPorItem[item.id] ?? 0);
      if (solicitada <= 0) {
        itensAtualizados.add(item);
        continue;
      }
      final quantidade = solicitada < pendente ? solicitada : pendente;
      if (quantidade <= 0) {
        itensAtualizados.add(item);
        continue;
      }

      final entradaOk = await registrarEntradaEstoque(
        produtoId: item.produtoId,
        quantidade: quantidade,
        observacao:
            'Recebimento do pedido ${pedido.numero}'
            '${pedido.fornecedorNome.isNotEmpty ? ' — ${pedido.fornecedorNome}' : ''}',
        usuario: usuario ?? pedido.usuario,
        fornecedorId: pedido.fornecedorId.isEmpty ? null : pedido.fornecedorId,
        fornecedorNome: pedido.fornecedorNome.isEmpty
            ? null
            : pedido.fornecedorNome,
        estoqueId: destinoId.isEmpty ? null : destinoId,
        notify: false,
      );

      if (!entradaOk) {
        avisos.add(
          '${item.produtoNome}: produto não encontrado; item não recebido.',
        );
        itensAtualizados.add(item);
        continue;
      }

      // Custo: o pedido guarda o custo combinado. Atualizar o cadastro é
      // opcional porque o operador pode receber com custo diferente (frete,
      // bonificação etc.).
      if (atualizarCusto && item.precoCusto > 0) {
        final produtoIndex = _produtos.indexWhere(
          (p) => p.id == item.produtoId,
        );
        if (produtoIndex != -1) {
          final produto = _produtos[produtoIndex];
          if (produto.precoCusto != item.precoCusto) {
            await updateProduto(
              produto.copyWith(
                precoCusto: item.precoCusto,
                updatedAt: DateTime.now(),
              ),
              aguardarSincronia: false,
              registrarMovimento: false,
              notify: false,
              motivoHistorico: 'Recebimento de pedido de compra',
              observacaoHistorico:
                  'Custo atualizado para R\$ ${item.precoCusto.toStringAsFixed(2)} '
                  '(pedido ${pedido.numero})',
              usuarioNome: usuario ?? pedido.usuario,
            );
          }
        }
      }

      itensAtualizados.add(
        item.copyWith(quantidadeRecebida: item.quantidadeRecebida + quantidade),
      );
      itensRecebidos++;
      quantidadeRecebida += quantidade;
    }

    if (itensRecebidos == 0) {
      if (avisos.isEmpty) {
        throw StateError(
          'Informe a quantidade recebida de pelo menos um item.',
        );
      }
      return ResultadoRecebimentoPedidoCompra(
        pedido: pedido,
        itensRecebidos: 0,
        quantidadeRecebida: 0,
        avisos: avisos,
      );
    }

    final todosRecebidos = itensAtualizados.every((item) => item.recebido);
    final algumRecebido = itensAtualizados.any(
      (item) => item.quantidadeRecebida > 0.0001,
    );
    final novoStatus = todosRecebidos
        ? StatusPedidoCompra.recebido
        : (algumRecebido ? StatusPedidoCompra.recebidoParcial : pedido.status);
    final agora = DateTime.now();
    final atualizado = pedido.copyWith(
      itens: itensAtualizados,
      status: novoStatus,
      dataRecebimento: todosRecebidos ? agora : pedido.dataRecebimento,
      estoqueDestinoId: destinoId.isEmpty ? pedido.estoqueDestinoId : destinoId,
      estoqueDestinoNome: destinoNome,
      updatedAt: agora,
    );

    final index = _pedidosCompra.indexWhere((p) => p.id == pedidoId);
    if (index != -1) {
      _pedidosCompra[index] = atualizado;
    }
    _marcarSujo(LocalStorageService.keyPedidosCompra);
    notifyListeners();

    await _persistirPedidoCompraLocal(atualizado);
    await _recalcularFlagsPedidoCompra(
      produtoIds: pedido.itens.map((item) => item.produtoId).toSet(),
    );
    enviarMudancaParaSupabase(
      SupabaseService.tablePedidosCompra,
      atualizado.toMap(),
    );

    return ResultadoRecebimentoPedidoCompra(
      pedido: atualizado,
      itensRecebidos: itensRecebidos,
      quantidadeRecebida: quantidadeRecebida,
      avisos: avisos,
    );
  }

  Future<void> _persistirPedidoCompraLocal(PedidoCompra pedido) async {
    try {
      await DatabaseService().upsertItem(
        LocalStorageService.keyPedidosCompra,
        pedido.toMap(),
      );
    } catch (e) {
      debugPrint(
        '>>> [PedidoCompra] ⚠️ Não gravei o pedido ${pedido.numero} no '
        'PostgreSQL local agora: $e',
      );
    }
  }

  /// Recalcula o selo "JÁ PEDIDO" dos produtos a partir dos pedidos ABERTOS.
  ///
  /// O campo `pedidoCompraGerado` era gravado à mão pelo relatório antigo e
  /// ficava "preso" para sempre. Agora ele é derivado: só fica marcado quando
  /// existe pedido em aberto com quantidade pendente para o produto. Ao
  /// receber/cancelar/excluir o pedido, o selo cai sozinho.
  Future<void> _recalcularFlagsPedidoCompra({Set<String>? produtoIds}) async {
    final abertos = _pedidosCompra.where((pedido) => pedido.emAberto).toList();
    final idsComPedido = <String>{};
    final ultimaDataPorProduto = <String, DateTime>{};
    for (final pedido in abertos) {
      for (final item in pedido.itens) {
        if (item.recebido) continue;
        idsComPedido.add(item.produtoId);
        final atual = ultimaDataPorProduto[item.produtoId];
        if (atual == null || pedido.dataCriacao.isAfter(atual)) {
          ultimaDataPorProduto[item.produtoId] = pedido.dataCriacao;
        }
      }
    }

    final alvos = produtoIds ?? idsComPedido;
    for (final produtoId in alvos) {
      final index = _produtos.indexWhere((p) => p.id == produtoId);
      if (index == -1) continue;
      final produto = _produtos[index];
      final deveEstarMarcado = idsComPedido.contains(produtoId);
      if (produto.pedidoCompraGerado == deveEstarMarcado) continue;
      final dataReferencia = deveEstarMarcado
          ? ultimaDataPorProduto[produtoId]
          : null;
      try {
        await updateProduto(
          produto.copyWith(
            pedidoCompraGerado: deveEstarMarcado,
            dataUltimoPedido: dataReferencia ?? produto.dataUltimoPedido,
            updatedAt: DateTime.now(),
          ),
          aguardarSincronia: false,
          registrarMovimento: false,
          notify: false,
          registrarHistorico: false,
        );
      } catch (e) {
        debugPrint(
          '>>> [PedidoCompra] ⚠️ Não atualizei o selo do produto '
          '${produto.nome}: $e',
        );
      }
    }
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
    final descAdicionalNormalizada =
        servico.descricaoAdicional?.toLowerCase().trim() ?? '';

    // Verificar se já existe um serviço idêntico (mesmo nome normalizado, preço base, valor adicional e descrição adicional)
    final servicoIdenticoExiste = _tiposServico.any((s) {
      final nomeExistenteNormalizado = normalizarNomeParaComparacao(s.nome);
      final descAdicionalExistente =
          s.descricaoAdicional?.toLowerCase().trim() ?? '';

      return nomeExistenteNormalizado == nomeNormalizado &&
          s.preco == precoBase &&
          s.valorAdicional == valorAdicional &&
          descAdicionalExistente == descAdicionalNormalizada;
    });

    if (servicoIdenticoExiste) {
      debugPrint(
        '>>> DataService: Serviço "${servico.nome}" já existe (idêntico), ignorando adição.',
      );
      return;
    }

    // Verificar se existe serviço similar (mesmo nome normalizado e mesmo preço total)
    final servicoSimilarExiste = _tiposServico.any((s) {
      final nomeExistenteNormalizado = normalizarNomeParaComparacao(s.nome);
      return nomeExistenteNormalizado == nomeNormalizado &&
          s.precoTotal == precoTotal;
    });

    if (servicoSimilarExiste) {
      debugPrint(
        '>>> DataService: Serviço similar "${servico.nome}" já existe (mesmo nome normalizado e preço total), ignorando adição.',
      );
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
        _tiposServico,
      );
      debugPrint(
        '>>> [Servico] ✅ Salvo localmente: ${servico.nome} (ID: ${servico.id})',
      );
    } catch (e) {
      debugPrint('>>> [Servico] ❌ Erro ao salvar localmente: $e');
    }

    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();

    debugPrint(
      '>>> DataService: Serviço "${servico.nome}" adicionado com sucesso.',
    );

    unawaited(
      _upsertNoSupabase(SupabaseService.tableServicos, servico.toMap()),
    );
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
          _tiposServico,
        );
        debugPrint(
          '>>> [Servico] ✅ Atualizado localmente: ${servico.nome} (ID: ${servico.id})',
        );
      } catch (e) {
        debugPrint('>>> [Servico] ❌ Erro ao atualizar localmente: $e');
      }

      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();

      unawaited(
        _upsertNoSupabase(SupabaseService.tableServicos, servico.toMap()),
      );
    }
  }

  void deleteTipoServico(String id) {
    _tiposServico.removeWhere((s) => s.id == id);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyServicos, id);
    notifyListeners();
    _salvarAutomaticamente();
    unawaited(_deleteNoSupabase(SupabaseService.tableServicos, id));
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
        _ordensServico,
      );
      debugPrint('>>> [OrdemServico] ✅ Salva localmente: ${os.id}');
    } catch (e) {
      debugPrint('>>> [OrdemServico] ❌ Erro ao salvar localmente: $e');
    }

    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tableOrdensServico,
      os.toMap(),
    );
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
          _ordensServico,
        );
        debugPrint('>>> [OrdemServico] ✅ Atualizada localmente: ${os.id}');
      } catch (e) {
        debugPrint('>>> [OrdemServico] ❌ Erro ao atualizar localmente: $e');
      }

      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();

      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(
        SupabaseService.tableOrdensServico,
        os.toMap(),
      );
    }
  }

  void deleteOrdemServico(String id) {
    _ordensServico.removeWhere((o) => o.id == id);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyOrdensServico, id);
    notifyListeners();
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tableOrdensServico, {
      'id': id,
    }, evento: 'DELETE');
  }

  // ============ CRUD Agendamento Serviço ============

  /// Envia notificação WhatsApp para agendamento (se configurado)
  Future<void> _enviarNotificacaoWhatsAppAgendamento(
    AgendamentoServico agendamento, {
    bool isNovo = true,
  }) async {
    // Verificar se a empresa tem WhatsApp configurado
    if (_empresaAtual == null || !_empresaAtual!.whatsappAtivo) {
      debugPrint(
        '>>> [WhatsApp] Notificações WhatsApp não estão ativas para esta empresa',
      );
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
    final telefone =
        agendamento.cliente?.whatsapp ?? agendamento.cliente?.telefone;
    if (telefone == null || telefone.isEmpty) {
      debugPrint('>>> [WhatsApp] Cliente não tem telefone cadastrado');
      return;
    }

    try {
      final service = WhatsAppService.fromEmpresa(_empresaAtual!);

      if (isNovo) {
        // Notificação de novo agendamento
        debugPrint(
          '>>> [WhatsApp] Enviando notificação de novo agendamento...',
        );
        final sucesso = await service.notificarAgendamentoCriado(
          agendamento: agendamento,
          nomeEmpresa: _empresaAtual!.nomeExibicao,
          telefoneEmpresa: _empresaAtual!.telefone,
        );
        debugPrint(
          '>>> [WhatsApp] Notificação enviada: ${sucesso ? "SUCESSO" : "FALHOU"}',
        );
      } else {
        // Notificação de alteração de status
        debugPrint(
          '>>> [WhatsApp] Enviando notificação de alteração de status...',
        );
        final sucesso = await service.notificarStatusAlterado(
          agendamento: agendamento,
          nomeEmpresa: _empresaAtual!.nomeExibicao,
        );
        debugPrint(
          '>>> [WhatsApp] Notificação enviada: ${sucesso ? "SUCESSO" : "FALHOU"}',
        );
      }
    } catch (e) {
      debugPrint('>>> [WhatsApp] Erro ao enviar notificação: $e');
      // Não bloquear o fluxo principal se a notificação falhar
    }
  }

  /// Adiciona um novo agendamento de serviço com validação de conflitos
  /// Adiciona múltiplos agendamentos em lote (otimizado)
  Future<void> addAgendamentosBatch(
    List<AgendamentoServico> agendamentos,
  ) async {
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

    // ⚠️ Registrar IDs como criados localmente (ignorar REALTIME por 5s)
    final agora = DateTime.now();
    for (final c in novosCompletos) {
      _agendamentosCriadosLocalmente[c.id] = agora;
    }
    _agendamentosCriadosLocalmente.removeWhere(
      (id, t) => agora.difference(t).inSeconds > 5,
    );

    debugPrint(
      '>>> [Batch] ✅ ${novosCompletos.length} agendamento(s) adicionado(s) na memória. Total: ${_agendamentosServico.length}',
    );
    for (final c in novosCompletos) {
      debugPrint(
        '>>> [Batch]   → ID=${c.id} data=${c.dataAgendamento} status=${c.status} servico=${c.servico?.nome ?? c.servicoNome}',
      );
    }
    notifyListeners();

    // Salvar localmente (UMA SÓ VEZ)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyAgendamentosServico),
        _agendamentosServico,
      );
    } catch (e) {
      debugPrint('>>> [Batch] Erro LocalStorage: $e');
    }

    _salvarAutomaticamente();

    if (SupabaseService.isAvailable && _currentEmpresaId != null) {
      for (final completo in novosCompletos) {
        _upsertNoSupabase(
          SupabaseService.tableAgendamentosServico,
          completo.toMap(),
        );
      }
    }

    // Notificações (opcional: pode ser pesado se forem muitos, mas geralmente são poucos pets)
    for (final completo in novosCompletos) {
      _enviarNotificacaoWhatsAppAgendamento(completo, isNovo: true);
    }
  }

  /// Helper para vincular referências de serviço, cliente e pet
  AgendamentoServico _vincularReferenciasAgendamento(
    AgendamentoServico agendamento,
  ) {
    Servico? servico;
    if (agendamento.servicoId != null &&
        !agendamento.servicoId!.startsWith('vacina_')) {
      try {
        servico = _tiposServico.firstWhere(
          (s) => s.id == agendamento.servicoId,
        );
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

    final agendamentoCompleto = _vincularReferenciasAgendamento(
      agendamentoComNumero,
    );

    // Evitar duplicatas em memória antes de adicionar
    _agendamentosServico.removeWhere((a) => a.id == agendamentoCompleto.id);
    _agendamentosServico.add(agendamentoCompleto);
    _agendamentosCriadosLocalmente[agendamentoCompleto.id] = DateTime.now();
    debugPrint(
      '>>> [Agendamento] ✅ Adicionado ID=${agendamentoCompleto.id} data=${agendamentoCompleto.dataAgendamento} status=${agendamentoCompleto.status} total=${_agendamentosServico.length}',
    );
    notifyListeners();

    // Salvar localmente IMEDIATAMENTE (sem debounce para agendamentos)
    try {
      await _storage.salvarLista(
        _getChaveComEmpresa(LocalStorageService.keyAgendamentosServico),
        _agendamentosServico,
      );
    } catch (e) {
      debugPrint('>>> [Agendamento] ❌ Erro ao salvar localmente: $e');
    }

    _salvarAutomaticamente();

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tableAgendamentosServico,
      agendamentoCompleto.toMap(),
    );

    _enviarNotificacaoWhatsAppAgendamento(agendamentoCompleto, isNovo: true);

    return agendamentoCompleto;
  }

  /// Atualiza um agendamento existente com validação de conflitos
  Future<void> updateAgendamentoServico(AgendamentoServico agendamento) async {
    final index = _agendamentosServico.indexWhere(
      (a) => a.id == agendamento.id,
    );
    if (index == -1) {
      throw Exception('Agendamento não encontrado');
    }

    // Validação de conflito de horário REMOVIDA - permitir múltiplos agendamentos no mesmo horário
    // A duração do serviço é mantida apenas para informação, sem bloquear outros agendamentos

    final agendamentoPrevio = agendamento.copyWith(updatedAt: DateTime.now());

    final itemAnterior = _agendamentosServico[index];
    final agendamentoAtualizado = _vincularReferenciasAgendamento(
      agendamentoPrevio,
    );
    _agendamentosServico[index] = agendamentoAtualizado;

    // Se mudou de ativo para inativo (ex: Cancelou), tentar promover alguém da espera
    if (itemAnterior.isAtivo && !agendamentoAtualizado.isAtivo) {
      _promoverAgendamentoEmEspera(itemAnterior);
    }

    notifyListeners();
    _marcarSujo(LocalStorageService.keyAgendamentosServico);

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tableAgendamentosServico,
      agendamentoAtualizado.toMap(),
    );

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
    // Exclusão real no banco local: sem isso o agendamento cancelado/apagado
    // voltava no próximo boot (a linha continuava no PostgreSQL local).
    _removerLinhaLocal(LocalStorageService.keyAgendamentosServico, id);

    // Se o agendamento removido era ativo, tentar promover alguém da espera
    if (agendamentoRemovido.isAtivo) {
      await _promoverAgendamentoEmEspera(agendamentoRemovido);
    }

    notifyListeners();
    _marcarSujo(LocalStorageService.keyAgendamentosServico);

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableAgendamentosServico, {
      'id': id,
    }, evento: 'DELETE');
  }

  /// Tenta promover um agendamento que está "Em Espera" para "Agendado"
  /// após um agendamento conflitante ser removido ou cancelado
  Future<void> _promoverAgendamentoEmEspera(
    AgendamentoServico agendamentoAntigo,
  ) async {
    try {
      // Procurar o primeiro agendamento em espera que conflite com o horário do que saiu
      final emEspera = _agendamentosServico.where((a) => a.isEmEspera).toList();

      // Ordenar por data de criação para garantir que o primeiro que entrou na fila seja o primeiro a sair
      emEspera.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      AgendamentoServico? paraPromover;
      for (var a in emEspera) {
        if (a.temSobreposicaoHorario(agendamentoAntigo)) {
          // Verificar se agora este agendamento não conflita com mais NINGUÉM que esteja ATIVO
          bool aindaTemConflito = _agendamentosServico.any(
            (ativo) => ativo.isAtivo && ativo.temSobreposicaoHorario(a),
          );
          if (!aindaTemConflito) {
            paraPromover = a;
            break;
          }
        }
      }

      if (paraPromover != null) {
        debugPrint(
          '>>> [Agenda] 🚀 Promovendo agendamento ${paraPromover.numero} da espera para Agendado',
        );
        final promovido = paraPromover.copyWith(
          status: 'Agendado',
          updatedAt: DateTime.now(),
        );

        // Atualizar na lista local
        final idx = _agendamentosServico.indexWhere(
          (a) => a.id == promovido.id,
        );
        if (idx != -1) {
          _agendamentosServico[idx] = promovido;
        }

        // Salvar no Supabase
        if (SupabaseService.isAvailable && _currentEmpresaId != null) {
          unawaited(
            _upsertNoSupabase(
              SupabaseService.tableAgendamentosServico,
              promovido.toMap(),
            ),
          );
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
        clienteAtualizado = _clientes.firstWhere(
          (c) => c.id == agendamento.clienteId,
        );
      } catch (e) {
        debugPrint(
          '>>> [Agendamento] ⚠ Cliente ${agendamento.clienteId} não encontrado',
        );
      }
    }

    // Buscar pet atualizado do cliente
    Pet? petAtualizado;
    if (agendamento.petId != null && clienteAtualizado != null) {
      try {
        petAtualizado = clienteAtualizado.pets.firstWhere(
          (p) => p.id == agendamento.petId,
        );
      } catch (e) {
        debugPrint(
          '>>> [Agendamento] ⚠ Pet ${agendamento.petId} não encontrado no cliente',
        );
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
    // Normalizar para comparar APENAS por data (ano/mes/dia), ignorando horario.
    final inicioDia = DateTime(inicio.year, inicio.month, inicio.day);
    final fimDia = DateTime(fim.year, fim.month, fim.day);
    return _agendamentosServico.where((a) {
      final dataLocal = a.dataAgendamento.toLocal();
      final aDia = DateTime(dataLocal.year, dataLocal.month, dataLocal.day);
      return !aDia.isBefore(inicioDia) && aDia.isBefore(fimDia);
    }).toList();
  }

  /// Busca agendamentos por cliente
  List<AgendamentoServico> getAgendamentosPorCliente(String clienteId) {
    return _agendamentosServico.where((a) => a.clienteId == clienteId).toList();
  }

  /// Verifica disponibilidade de horário
  bool checkDisponibilidade(
    DateTime inicio,
    int duracaoMinutos, {
    int intervaloMinutos = 0,
    bool ignorarPendentes = false,
  }) {
    final duracaoTotal = duracaoMinutos + intervaloMinutos;
    final fim = inicio.add(Duration(minutes: duracaoTotal));

    final isModuloPet = _empresaAtual?.moduloPet ?? false;

    // Verificar conflitos com agendamentos existentes
    for (final a in _agendamentosServico) {
      if (a.status == 'Cancelado' && (!a.travado || !isModuloPet)) continue;

      // Se ignorarPendentes for true, não bloqueamos por solicitações ainda não confirmadas
      if (ignorarPendentes && a.status == 'Aguardando Confirmação') continue;

      final aInicio = a.dataAgendamento;
      final aFim =
          a.dataTermino; // Já inclui o intervalo do agendamento existente

      // Lógica de sobreposição: (InicioA < FimB) && (FimA > InicioB)
      if (aInicio.isBefore(fim) && aFim.isAfter(inicio)) {
        // Conflito detectado
        return false;
      }
    }

    // Verificar conflitos com horários bloqueados (Configuração da Empresa)
    try {
      final config =
          _empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>?;

      // -- VERIFICAR HORÁRIO DE FUNCIONAMENTO --
      final hAberturaStr = config?['horarioAbertura']?.toString() ?? '08:00';
      final hFechamentoStr =
          config?['horarioFechamento']?.toString() ?? '18:00';

      final hAbertura = _timeToDouble(hAberturaStr);
      final hFechamento = _timeToDouble(hFechamentoStr);

      final double horaInicio = inicio.hour + (inicio.minute / 60.0);
      final double horaFim = horaInicio + (duracaoMinutos / 60.0);

      // Se começar antes de abrir ou terminar depois de fechar, está bloqueado.
      if (isModuloPet && (horaInicio < hAbertura || horaFim > hFechamento)) {
        debugPrint(
          '>>> [DataService] Fora do horário de funcionamento: $horaInicio - $horaFim (Expediente: $hAberturaStr - $hFechamentoStr)',
        );
        return false;
      }

      final bloqueados = config?['horariosIndisponiveis'] as List<dynamic>?;
      if (bloqueados != null && bloqueados.isNotEmpty) {
        final String dataStr =
            '${inicio.year}-${inicio.month.toString().padLeft(2, '0')}-${inicio.day.toString().padLeft(2, '0')}';
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
                aplicaSeAData =
                    dataStr.compareTo(dataInicioStr) >= 0 &&
                    dataStr.compareTo(dataFimStr) <= 0;
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

          final double bInicio =
              int.parse(bInicioParts[0]) + int.parse(bInicioParts[1]) / 60.0;
          final double bFim =
              int.parse(bFimParts[0]) + int.parse(bFimParts[1]) / 60.0;

          // Sobreposição: (InicioA < FimB) && (FimA > InicioB)
          if (horaInicio < bFim && horaFim > bInicio) {
            debugPrint(
              '>>> [DataService] Horário bloqueado detectado: $bInicioStr - $bFimStr (tipo: $tipo)',
            );
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
        debugPrint(
          '>>> [Agendamento] Gerado novo número para aprovação: $numero',
        );
      }

      final agendamentoPrevio = agendamento.copyWith(
        numero: numero,
        status: 'Agendado',
        updatedAt: DateTime.now(),
      );

      // Vincular referências para garantir que o agendamento tenha os objetos (Serviço, Cliente, Pet)
      // Isso evita que ele suma da agenda caso o filtro dependa destes objetos
      final agendamentoAtualizado = _vincularReferenciasAgendamento(
        agendamentoPrevio,
      );

      // Garantir que a lista local tem a referência mais atualizada e em destaque
      _upsertAgendamentoLocal(agendamentoAtualizado, prioritario: true);

      notifyListeners();
      forceUpdate(); // Forçar rebuild global para garantir que o sino e agenda atualizem

      unawaited(
        _upsertNoSupabase(
          SupabaseService.tableAgendamentosServico,
          agendamentoAtualizado.toMap(),
        ),
      );

      notifyListeners();
      _marcarSujo(LocalStorageService.keyAgendamentosServico);

      // Notificar cliente via WhatsApp em BACKGROUND para não travar a UI
      // ignore: unawaited_futures
      _enviarNotificacaoWhatsAppAgendamento(
        agendamentoAtualizado,
        isNovo: false,
      );

      // Notificar novamente para garantir que a UI refletiu o salvamento
      notifyListeners();
      forceUpdate(); // Forçar rebuild global para garantir que o sino e agenda atualizem
    } else {
      debugPrint(
        '>>> [Agendamento] ❌ ERRO: Agendamento $agendamentoId não encontrado para aprovação!',
      );
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

      final agendamentoAtualizado = _vincularReferenciasAgendamento(
        agendamentoPrevio,
      );

      // Atualizar a instância com prioridade
      _upsertAgendamentoLocal(agendamentoAtualizado, prioritario: true);

      notifyListeners();
      _salvarAutomaticamente();

      unawaited(
        _upsertNoSupabase(
          SupabaseService.tableAgendamentosServico,
          agendamentoAtualizado.toMap(),
        ),
      );

      // Notificar cliente via WhatsApp em background
      // ignore: unawaited_futures
      _enviarNotificacaoWhatsAppAgendamento(
        agendamentoAtualizado,
        isNovo: false,
      );

      notifyListeners();
      forceUpdate();
    }
  }

  // ============ CRUD Serviço Realizado ============
  //
  // Entidade PRÓPRIA (tabela `servicos_realizados`), separada de `pedidos`:
  // numeração SRV própria, nasce como Orçamento e não entra no PDV nem nos
  // recebíveis de pedido.

  Future<void> addServicoRealizado(ServicoRealizado servico) async {
    _servicosRealizados.add(servico);
    notifyListeners();
    // LOCAL PRIMEIRO: a linha vai para o PostgreSQL local e a gravação é
    // AGUARDADA antes de qualquer envio. Nuvem pausa/erro (402) não entra
    // nessa conta, e um reload logo em seguida não tem como apagar o
    // lançamento (o snapshot do banco já o contém).
    await _salvarLinhaLocalAntesDaNuvem(
      LocalStorageService.keyServicosRealizados,
      servico.toMap(),
    );
    await _enviarServicoRealizadoParaSupabase(servico);
    debugPrint(
      '>>> Serviço realizado salvo: ${servico.numero} (${servico.status})',
    );
  }

  Future<void> updateServicoRealizado(ServicoRealizado servico) async {
    final index = _servicosRealizados.indexWhere((s) => s.id == servico.id);
    if (index == -1) {
      await addServicoRealizado(servico);
      return;
    }
    _servicosRealizados[index] = servico;
    notifyListeners();
    // LOCAL PRIMEIRO (mesma regra do add): grava e AGUERA antes da nuvem.
    await _salvarLinhaLocalAntesDaNuvem(
      LocalStorageService.keyServicosRealizados,
      servico.toMap(),
    );
    await _enviarServicoRealizadoParaSupabase(servico);
    debugPrint(
      '>>> Serviço realizado atualizado: ${servico.numero} (${servico.status})',
    );
  }

  Future<void> removerServicoRealizado(String id) async {
    _servicosRealizados.removeWhere((s) => s.id == id);
    notifyListeners();
    // LOCAL PRIMEIRO: a exclusão sai do banco local e só depois vai pra nuvem.
    await _removerLinhaLocalAntesDaNuvem(
      LocalStorageService.keyServicosRealizados,
      id,
    );
    try {
      if (SupabaseService.isAvailable && _currentEmpresaId != null) {
        await enviarMudancaParaSupabase(
          SupabaseService.tableServicosRealizados,
          {'id': id},
          evento: 'DELETE',
        );
      }
    } catch (e) {
      debugPrint(
        '>>> ⚠️ Não foi possível excluir o serviço realizado na nuvem: $e',
      );
    }
  }

  /// Recebe uma parcela do serviço. Quando zera o pendente, o serviço passa
  /// para 'Recebido'.
  Future<ServicoRealizado?> receberPagamentoServico(
    String servicoId,
    String pagamentoId, {
    DateTime? dataRecebimento,
  }) async {
    final index = _servicosRealizados.indexWhere((s) => s.id == servicoId);
    if (index == -1) return null;

    final atual = _servicosRealizados[index];
    final recebidoEm = dataRecebimento ?? DateTime.now();
    final pagamentos = atual.pagamentos
        .map(
          (p) => p.id == pagamentoId
              ? p.copyWith(recebido: true, dataRecebimento: recebidoEm)
              : p,
        )
        .toList();

    var atualizado = atual.copyWith(
      pagamentos: pagamentos,
      updatedAt: DateTime.now(),
    );

    if (atualizado.valorPendente <= 0.009 && !atualizado.cancelado) {
      atualizado = atualizado.copyWith(
        status: ServicoRealizado.statusRecebido,
        dataConclusao: atualizado.dataConclusao ?? recebidoEm,
      );
    }

    await updateServicoRealizado(atualizado);
    return atualizado;
  }

  /// Recebe TODO o valor pendente de uma vez (quitando o serviço).
  ///
  /// Serviço lançado sem forma de pagamento recebe aqui o pagamento que faltava
  /// — senão não haveria como marcar o valor como recebido.
  Future<ServicoRealizado?> receberServicoTotal(
    String servicoId, {
    TipoPagamento? tipo,
  }) async {
    final index = _servicosRealizados.indexWhere((s) => s.id == servicoId);
    if (index == -1) return null;

    final atual = _servicosRealizados[index];
    final recebidoEm = DateTime.now();

    final List<PagamentoPedido> pagamentos;
    if (atual.pagamentos.isEmpty) {
      pagamentos = [
        PagamentoPedido(
          id: '${recebidoEm.millisecondsSinceEpoch}_pg',
          tipo: tipo ?? TipoPagamento.dinheiro,
          valor: atual.totalGeral > 0 ? atual.totalGeral : atual.totalServicos,
          recebido: true,
          dataRecebimento: recebidoEm,
        ),
      ];
    } else {
      pagamentos = atual.pagamentos
          .map(
            (p) => p.recebido
                ? p
                : p.copyWith(recebido: true, dataRecebimento: recebidoEm),
          )
          .toList();
    }

    await updateServicoRealizado(
      atual.copyWith(
        pagamentos: pagamentos,
        descontoTotal: 0,
        status: ServicoRealizado.statusRecebido,
        dataConclusao: atual.dataConclusao ?? recebidoEm,
        updatedAt: recebidoEm,
      ),
    );
    return _servicosRealizados[index];
  }

  /// Aprova um orçamento: deixa de ser proposta e passa a 'Em Aberto'
  /// (a partir daqui o valor entra como serviço a receber).
  Future<ServicoRealizado?> aprovarOrcamentoServico(String servicoId) async {
    final index = _servicosRealizados.indexWhere((s) => s.id == servicoId);
    if (index == -1) return null;

    final atual = _servicosRealizados[index];
    final atualizado = atual.copyWith(
      status: ServicoRealizado.statusEmAberto,
      dataOrcamento: atual.dataOrcamento ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await updateServicoRealizado(atualizado);
    return atualizado;
  }

  /// Cancela o serviço (não gera recebível nem orçamento válido).
  Future<ServicoRealizado?> cancelarServicoRealizado(String servicoId) async {
    final index = _servicosRealizados.indexWhere((s) => s.id == servicoId);
    if (index == -1) return null;

    final atualizado = _servicosRealizados[index].copyWith(
      status: ServicoRealizado.statusCancelado,
      updatedAt: DateTime.now(),
    );
    await updateServicoRealizado(atualizado);
    return atualizado;
  }

  // ============ CRUD Orçamento (pedidos do central) ============
  //
  // Entidade PRÓPRIA (tabela `orcamentos`, série ORC-). Não é pedido: fica fora
  // do PDV, dos recebíveis e dos relatórios de venda. Só viram pedido quando o
  // cliente aprova — e aí a série passa a ser PED-.

  Future<void> addOrcamento(Orcamento orcamento) async {
    _orcamentos.add(orcamento);
    notifyListeners();
    // LOCAL PRIMEIRO: grava no PostgreSQL local e AGUARDA antes da nuvem
    // (mesma regra dos serviços realizados e de todo o resto do sistema).
    await _salvarLinhaLocalAntesDaNuvem(
      LocalStorageService.keyOrcamentos,
      orcamento.toMap(),
    );
    await _enviarOrcamentoParaSupabase(orcamento);
    debugPrint(
      '>>> Orçamento salvo: ${orcamento.numero} (${orcamento.status})',
    );
  }

  Future<void> updateOrcamento(Orcamento orcamento) async {
    final index = _orcamentos.indexWhere((o) => o.id == orcamento.id);
    if (index == -1) {
      await addOrcamento(orcamento);
      return;
    }
    _orcamentos[index] = orcamento;
    notifyListeners();
    // LOCAL PRIMEIRO: grava e AGUARDA antes da nuvem.
    await _salvarLinhaLocalAntesDaNuvem(
      LocalStorageService.keyOrcamentos,
      orcamento.toMap(),
    );
    await _enviarOrcamentoParaSupabase(orcamento);
    debugPrint(
      '>>> Orçamento atualizado: ${orcamento.numero} (${orcamento.status})',
    );
  }

  Future<void> removerOrcamento(String id) async {
    _orcamentos.removeWhere((o) => o.id == id);
    notifyListeners();
    // LOCAL PRIMEIRO: a exclusão sai do banco local antes de ir pra nuvem.
    await _removerLinhaLocalAntesDaNuvem(LocalStorageService.keyOrcamentos, id);
    try {
      if (SupabaseService.isAvailable && _currentEmpresaId != null) {
        await enviarMudancaParaSupabase(SupabaseService.tableOrcamentos, {
          'id': id,
        }, evento: 'DELETE');
      }
    } catch (e) {
      debugPrint('>>> ⚠️ Não foi possível excluir o orçamento na nuvem: $e');
    }
  }

  /// **Aprovar** = o cliente aceitou a proposta. Só isso: o orçamento passa a
  /// 'Aprovado' e CONTINUA sendo orçamento, com o número ORC- dele.
  ///
  /// O pedido (série PED-) só nasce no [gerarPedidoDoOrcamento], depois da
  /// aprovação — as duas coisas são separadas de propósito.
  Future<Orcamento?> aprovarOrcamento(String orcamentoId) async {
    final index = _orcamentos.indexWhere((o) => o.id == orcamentoId);
    if (index == -1) return null;

    final atual = _orcamentos[index];
    if (atual.cancelado) return null;

    final aprovado = atual.copyWith(
      status: Orcamento.statusAprovado,
      dataAprovacao: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await updateOrcamento(aprovado);
    debugPrint('>>> Orçamento ${aprovado.numero} aprovado (ainda sem pedido)');
    return aprovado;
  }

  /// **Gerar pedido**: transforma um orçamento JÁ APROVADO em Pedido, com
  /// número próprio da série PED- e o número do orçamento de origem guardado
  /// nas observações do pedido.
  Future<Pedido?> gerarPedidoDoOrcamento(String orcamentoId) async {
    final index = _orcamentos.indexWhere((o) => o.id == orcamentoId);
    if (index == -1) return null;

    final orcamento = _orcamentos[index];
    // Só vira pedido depois de aprovado, e nunca duas vezes.
    if (orcamento.cancelado || !orcamento.aprovado) return null;
    if (orcamento.temPedidoGerado) return null;

    final agora = DateTime.now();
    final observacoesPedido = [
      'Orçamento ${orcamento.numero}',
      if ((orcamento.observacoes ?? '').trim().isNotEmpty)
        orcamento.observacoes!.trim(),
    ].join('\n');

    final pedido = Pedido(
      id: uuid.v4(),
      numero: getProximoNumeroPedido(),
      clienteId: orcamento.clienteId,
      clienteNome: orcamento.clienteNome,
      clienteTelefone: orcamento.clienteTelefone,
      clienteEndereco: orcamento.clienteEndereco,
      clienteCpfCnpj: orcamento.clienteCpfCnpj,
      operador: orcamento.operador,
      dataPedido: agora,
      status: 'Pendente',
      total: orcamento.totalGeral,
      descontoTotal: orcamento.descontoTotal,
      acrescimoTotal: orcamento.acrescimoTotal,
      observacoes: observacoesPedido,
      produtos: orcamento.itens,
      servicos: orcamento.servicos,
      pagamentos: const [],
      deliveryInfo: orcamento.deliveryInfo,
      createdAt: agora,
      updatedAt: agora,
    );

    await addPedido(pedido);

    await updateOrcamento(
      orcamento.copyWith(
        pedidoGeradoId: pedido.id,
        pedidoGeradoNumero: pedido.numero,
        updatedAt: agora,
      ),
    );

    debugPrint(
      '>>> Orçamento ${orcamento.numero} virou pedido ${pedido.numero}',
    );
    return pedido;
  }

  /// Reabre um orçamento recusado/cancelado (volta a ser proposta em aberto).
  Future<void> reabrirOrcamento(String orcamentoId) async {
    final index = _orcamentos.indexWhere((o) => o.id == orcamentoId);
    if (index == -1) return;
    final atual = _orcamentos[index];
    if (atual.temPedidoGerado) return; // já virou pedido: não dá para voltar
    await updateOrcamento(
      atual.copyWith(
        status: Orcamento.statusOrcamento,
        limparAprovacao: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Marca o orçamento como recusado pelo cliente.
  Future<void> recusarOrcamento(String orcamentoId) async {
    final index = _orcamentos.indexWhere((o) => o.id == orcamentoId);
    if (index == -1) return;
    await updateOrcamento(
      _orcamentos[index].copyWith(
        status: Orcamento.statusRecusado,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Cancela o orçamento (nem proposta válida, nem pedido).
  Future<void> cancelarOrcamento(String orcamentoId) async {
    final index = _orcamentos.indexWhere((o) => o.id == orcamentoId);
    if (index == -1) return;
    await updateOrcamento(
      _orcamentos[index].copyWith(
        status: Orcamento.statusCancelado,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _enviarOrcamentoParaSupabase(Orcamento orcamento) async {
    try {
      if (!SupabaseService.isAvailable || _currentEmpresaId == null) return;
      final dados = orcamento.toMap();
      dados['empresa_id'] = _currentEmpresaId;
      await enviarMudancaParaSupabase(SupabaseService.tableOrcamentos, dados);
    } catch (e) {
      // Tabela ausente na nuvem não pode impedir o salvamento local.
      debugPrint(
        '>>> ⚠️ Orçamento ${orcamento.numero} não subiu para a nuvem: $e',
      );
    }
  }

  Future<void> _enviarServicoRealizadoParaSupabase(
    ServicoRealizado servico,
  ) async {
    try {
      if (!SupabaseService.isAvailable || _currentEmpresaId == null) return;
      final dados = servico.toMap();
      dados['empresa_id'] = _currentEmpresaId;
      await enviarMudancaParaSupabase(
        SupabaseService.tableServicosRealizados,
        dados,
      );
    } catch (e) {
      // Tabela ausente na nuvem não pode impedir o salvamento local.
      debugPrint(
        '>>> ⚠️ Serviço realizado ${servico.numero} não subiu para a nuvem: $e',
      );
    }
  }

  // ============ CRUD Pedido ============

  Future<void> addPedido(Pedido pedido) async {
    _pedidos.add(pedido);
    // Trava o contador da empresa no número já emitido (ver o método).
    await _elevarMinimoNumeracaoPeloNumero(pedido.numero);
    notifyListeners();
    _persistirLinhaLocal(LocalStorageService.keyPedidos, pedido.toMap());

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tablePedidos,
      pedido.toMap(),
    );

    // GARANTIA MULTI-PC: upsert aguardado + confirmação Realtime
    await garantirEnvioEConfirmacao(
      tabela: SupabaseService.tablePedidos,
      dados: pedido.toMap(),
    );

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
      _persistirLinhaLocal(LocalStorageService.keyPedidos, pedido.toMap());

      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(
        SupabaseService.tablePedidos,
        pedido.toMap(),
      );

      // GARANTIA MULTI-PC: upsert aguardado + confirmação Realtime
      await garantirEnvioEConfirmacao(
        tabela: SupabaseService.tablePedidos,
        dados: pedido.toMap(),
      );

      // SINCRONIZAÇÃO BIDIRECIONAL: Pedido -> Entrega
      if (pedido.deliveryInfo != null &&
          pedido.deliveryInfo!.status.toLowerCase() == 'entregue') {
        final entregaIndex = _entregas.indexWhere(
          (e) => e.pedidoId == pedido.id || e.pedidoNumero == pedido.numero,
        );
        if (entregaIndex != -1 &&
            _entregas[entregaIndex].status != StatusEntrega.entregue) {
          _entregas[entregaIndex] = _entregas[entregaIndex].copyWith(
            status: StatusEntrega.entregue,
            dataEntrega: _entregas[entregaIndex].dataEntrega ?? DateTime.now(),
          );
          _marcarSujo(LocalStorageService.keyEntregas);
          debugPrint(
            '>>> [Sync] ✅ Entrega sincronizada para ENTREGUE via Pedido',
          );
        }
      }
    } else {
      debugPrint('>>> ERRO: Pedido não encontrado para atualizar!');
    }
  }

  /// Salva um pedido de forma idempotente: se já existir um pedido com o mesmo
  /// id, ATUALIZA o registro existente (mantendo o MESMO número) em vez de
  /// inserir outro registro.
  ///
  /// Isso é usado ao EDITAR um pedido salvo: antes era chamado addPedido(),
  /// que só fazia _pedidos.add(), criando dois registros com o mesmo número —
  /// e o detalhe do PDV (que busca o pedido por id) continuava exibindo o
  /// registro antigo, como se a edição não tivesse sido salva.
  Future<void> addOrUpdatePedido(Pedido pedido) async {
    final index = _pedidos.indexWhere((p) => p.id == pedido.id);
    if (index == -1) {
      await addPedido(pedido);
      return;
    }

    // Edição NUNCA renumera o pedido e também não reescreve a data de criação:
    // o número e o createdAt originais são preservados.
    final existente = _pedidos[index];
    final pedidoFinal = pedido.copyWith(
      numero: existente.numero,
      createdAt: existente.createdAt,
    );

    if (pedido.numero != existente.numero) {
      debugPrint(
        '>>> [Pedido] Numeração preservada na edição: mantido '
        '${existente.numero} (seria ${pedido.numero})',
      );
    }

    await updatePedido(pedidoFinal);
  }

  void deletePedido(String id) {
    _pedidos.removeWhere((p) => p.id == id);
    notifyListeners();
    _removerLinhaLocal(LocalStorageService.keyPedidos, id);
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    enviarMudancaParaSupabase(SupabaseService.tablePedidos, {
      'id': id,
    }, evento: 'DELETE');
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
            produto = _produtos.firstWhere((p) => p.id == item.id);
          } catch (_) {
            // Se não encontrou pelo ID, tentar pelo nome
            try {
              produto = _produtos.firstWhere((p) => p.nome == item.nome);
            } catch (_) {
              print(
                '>>> ⚠ Produto não encontrado para devolução: ${item.nome}',
              );
              continue;
            }
          }

          final estoqueAnterior = produto.estoque;
          final novoEstoque = produto.estoque + item.quantidade;

          await updateProduto(
            produto.copyWith(estoque: novoEstoque, updatedAt: DateTime.now()),
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
        observacoes:
            (pedido.observacoes ?? '') +
            (motivo != null && motivo.isNotEmpty
                ? '\nCancelado em ${DateTime.now().toIso8601String()} - Motivo: $motivo'
                : '\nCancelado em ${DateTime.now().toIso8601String()}'),
      );
      _pedidos[index] = pedidoCancelado;
      print(
        '✓ Pedido ${pedido.numero} cancelado e produtos devolvidos ao estoque',
      );
      notifyListeners();
      _persistirLinhaLocal(
        LocalStorageService.keyPedidos,
        pedidoCancelado.toMap(),
      );
      // Sincronizar cancelamento com Supabase imediatamente
      await enviarMudancaParaSupabase(
        SupabaseService.tablePedidos,
        pedidoCancelado.toMap(),
      );

      // Cancelar NFC-e associada ao pedido (se existir)
      try {
        final nfcesVinculadas = _nfces
            .where(
              (n) => n.vendaId == pedido.id || n.vendaNumero == pedido.numero,
            )
            .toList();
        for (final nfce in nfcesVinculadas) {
          if (nfce.status == 'autorizada' || nfce.status == 'sucesso') {
            final nfceCancelada = nfce.copyWith(
              status: 'cancelada',
              updatedAt: DateTime.now(),
            );
            await atualizarNFCe(nfceCancelada);
            print(
              '✓ NFC-e ${nfce.numero} vinculada ao pedido ${pedido.numero} marcada como cancelada',
            );
            // Sincronizar cancelamento da NFC-e com Supabase
            await enviarMudancaParaSupabase(
              SupabaseService.tableNFCes,
              nfceCancelada.toMap(),
            );
          }
        }
      } catch (e) {
        print('>>> ⚠ Erro ao cancelar NFC-e vinculada: $e');
      }
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

    // Nuvem em segundo plano: a entrega já está na memória/local.
    unawaited(
      _upsertNoSupabase(SupabaseService.tableEntregas, entrega.toMap()),
    );
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
        final pedidoIndex = _pedidos.indexWhere(
          (p) => p.id == entrega.pedidoId || p.numero == entrega.pedidoNumero,
        );
        if (pedidoIndex != -1) {
          final p = _pedidos[pedidoIndex];
          if (p.deliveryInfo != null &&
              p.deliveryInfo!.status.toLowerCase() != 'entregue') {
            final pedidoEntregue = p.copyWith(
              deliveryInfo: p.deliveryInfo!.copyWith(status: 'entregue'),
              status: p.status.toLowerCase() == 'pendente'
                  ? 'Entregue'
                  : p.status, // Opcional: atualizar status geral se estiver pendente
            );
            _pedidos[pedidoIndex] = pedidoEntregue;
            _persistirLinhaLocal(
              LocalStorageService.keyPedidos,
              pedidoEntregue.toMap(),
            );
            debugPrint(
              '>>> [Sync] ✅ Pedido sincronizado para ENTREGUE via Entrega',
            );
          }
        }
      }

      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();

      unawaited(
        _upsertNoSupabase(SupabaseService.tableEntregas, entrega.toMap()),
      );
    }
  }

  /// Salva a entrega vinculada a um pedido sem duplicar: se o pedido já tiver
  /// uma entrega, ATUALIZA os dados dela preservando status, histórico e
  /// rastreio. Usado ao editar pedidos de delivery (antes cada salvamento
  /// criava um registro de entrega novo, duplicando a entrega no controle).
  Future<void> addOrUpdateEntregaDoPedido(Entrega entrega) async {
    final index = _entregas.indexWhere(
      (e) =>
          e.id == entrega.id ||
          (entrega.pedidoId.isNotEmpty && e.pedidoId == entrega.pedidoId),
    );
    if (index == -1) {
      await addEntrega(entrega);
      return;
    }

    final existente = _entregas[index];
    await updateEntrega(
      existente.copyWith(
        pedidoNumero: entrega.pedidoNumero,
        clienteNome: entrega.clienteNome,
        clienteTelefone: entrega.clienteTelefone,
        enderecoEntrega: entrega.enderecoEntrega,
        bairro: entrega.bairro,
        cidade: entrega.cidade,
        cep: entrega.cep,
        motoristaId: entrega.motoristaId,
        motoristaNome: entrega.motoristaNome,
        taxaEntrega: entrega.taxaEntrega,
        observacoes: entrega.observacoes,
      ),
    );
  }

  void deleteEntrega(String id) {
    _entregas.removeWhere((e) => e.id == id);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyEntregas, id);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyEntregas);
    enviarMudancaParaSupabase(SupabaseService.tableEntregas, {
      'id': id,
    }, evento: 'DELETE');
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
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyRomaneios, id);
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

    final proximo =
        (numeros.isNotEmpty
            ? numeros.reduce((curr, next) => curr > next ? curr : next)
            : 0) +
        1;
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
        _taxasEntrega,
      );
      debugPrint(
        '>>> [TaxaEntrega] ✅ Salva localmente: ${taxa.bairro} (ID: ${taxa.id})',
      );
    } catch (e) {
      debugPrint('>>> [TaxaEntrega] ❌ Erro ao salvar localmente: $e');
    }

    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tableTaxasEntrega,
      taxa.toMap(),
    );
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
          _taxasEntrega,
        );
        debugPrint(
          '>>> [TaxaEntrega] ✅ Atualizada localmente: ${taxa.bairro} (ID: ${taxa.id})',
        );
      } catch (e) {
        debugPrint('>>> [TaxaEntrega] ❌ Erro ao atualizar localmente: $e');
      }

      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();

      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(
        SupabaseService.tableTaxasEntrega,
        taxa.toMap(),
      );
    }
  }

  Future<void> deleteTaxaEntrega(String id) async {
    _taxasEntrega.removeWhere((t) => t.id == id);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyTaxasEntrega, id);
    notifyListeners();
    _salvarAutomaticamente();

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableTaxasEntrega, {
      'id': id,
    }, evento: 'DELETE');
  }

  /// Busca taxa de entrega por bairro (case-insensitive)
  TaxaEntrega? getTaxaEntregaPorBairro(String bairro, {String? cidade}) {
    try {
      final bairroLower = bairro.toLowerCase().trim();
      return _taxasEntrega.firstWhere(
        (t) =>
            t.ativo &&
            t.bairro.toLowerCase().trim() == bairroLower &&
            (cidade == null ||
                t.cidade?.toLowerCase().trim() == cidade.toLowerCase().trim()),
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
        _motoristas,
      );
      debugPrint(
        '>>> [Motorista] ✅ Salvo localmente: ${motorista.nome} (ID: ${motorista.id})',
      );
    } catch (e) {
      debugPrint('>>> [Motorista] ❌ Erro ao salvar localmente: $e');
    }

    // Também chamar salvamento automático (para sincronizar outros dados)
    _salvarAutomaticamente();

    unawaited(
      _upsertNoSupabase(SupabaseService.tableMotoristas, motorista.toMap()),
    );
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
          _motoristas,
        );
        debugPrint(
          '>>> [Motorista] ✅ Atualizado localmente: ${motorista.nome} (ID: ${motorista.id})',
        );
      } catch (e) {
        debugPrint('>>> [Motorista] ❌ Erro ao atualizar localmente: $e');
      }

      // Também chamar salvamento automático (para sincronizar outros dados)
      _salvarAutomaticamente();

      unawaited(
        _upsertNoSupabase(SupabaseService.tableMotoristas, motorista.toMap()),
      );
    }
  }

  void deleteMotorista(String id) {
    _motoristas.removeWhere((m) => m.id == id);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyMotoristas, id);
    notifyListeners();
    _marcarSujo(LocalStorageService.keyMotoristas);
    enviarMudancaParaSupabase(SupabaseService.tableMotoristas, {
      'id': id,
    }, evento: 'DELETE');
  }

  // ============ CRUD Venda Balcão ============

  /// Vendas cujo cash back já foi computado nesta sessão (evita crédito
  /// duplicado quando uma mesma venda é regravada no fluxo).
  final Set<String> _vendasCashbackProcessadas = <String>{};

  /// Aplica as regras de cash back de uma venda finalizada:
  /// - debita do saldo do cliente o que foi pago com Cash Back;
  /// - credita o percentual sobre o valor realmente pago sem cash back.
  ///
  /// Sem cliente identificado não faz nada (cash back é fidelidade por cliente).
  /// Movimentos de cash back de um cliente (extrato).
  List<CashBackMovimento> movimentosDoCliente(String clienteId) =>
      _movimentosCashBack.where((m) => m.clienteId == clienteId).toList();

  /// Persiste movimentos de cash back: grava/atualiza na lista local, marca a
  /// coleção suja e envia cada linha para a nuvem.
  Future<void> _persistirMovimentosCashBack(
    List<CashBackMovimento> movimentos,
  ) async {
    if (movimentos.isEmpty) return;
    for (final m in movimentos) {
      final idx = _movimentosCashBack.indexWhere((x) => x.id == m.id);
      if (idx >= 0) {
        _movimentosCashBack[idx] = m;
      } else {
        _movimentosCashBack.add(m);
      }
    }
    _marcarSujo(LocalStorageService.keyCashBackMovimentos);
    notifyListeners();
    for (final m in movimentos) {
      await enviarMudancaParaSupabase(
        SupabaseService.tableCashBackMovimentos,
        m.toMap(),
      );
    }
  }

  /// Créditos do cliente com `consumido` atualizado por [consumirDosCreditos],
  /// devolvendo só as linhas que realmente mudaram (para regravar na nuvem).
  List<CashBackMovimento> _creditosConsumidos(
    List<CashBackMovimento> movimentos,
    double valorUsado,
  ) {
    final originais = {for (final m in movimentos) m.id: m};
    final atualizados =
        CashBackService.consumirDosCreditos(movimentos, valorUsado);
    return atualizados
        .where((m) => (originais[m.id]?.consumido ?? 0) != m.consumido)
        .toList();
  }

  Future<void> aplicarCashbackDaVenda(VendaBalcao venda) async {
    try {
      if (venda.cancelado || venda.valorTotal <= 0) return;
      final clienteId = venda.clienteId;
      if (clienteId == null || clienteId.isEmpty) return;
      // Trava de processamento único (evita crédito duplicado). Marcada só
      // antes do crédito efetivo — vendas puladas por falta de recebimento
      // podem ser reprocessadas quando forem pagas.
      if (_vendasCashbackProcessadas.contains(venda.id)) return;

      final index = _clientes.indexWhere((c) => c.id == clienteId);
      if (index == -1) {
        debugPrint('>>> [CashBack] ⚠️ Cliente $clienteId não encontrado — saldo não creditado');
        return;
      }

      final cliente = _clientes[index];

      // Gate por cliente: cash back desativado não acumula nem usa.
      if (!cliente.cashbackAtivo) {
        debugPrint('>>> [CashBack] ⏭️ ${cliente.nome} com cash back desativado');
        return;
      }

      final agora = DateTime.now();
      var movimentos = movimentosDoCliente(clienteId);

      // 1) Débito: quanto desta venda foi pago com o próprio cash back
      double usado = 0.0;
      for (final p in venda.pagamentos) {
        if (p.tipo == TipoPagamento.cashBack) usado += p.valor;
      }
      usado = CashBackService.maximoUsavel(
        saldo: cliente.saldoCashback,
        totalVenda: usado,
      );

      // Sem recebimento confirmado não credita: cobre a venda "restante"
      // do dividir-conta (criada ainda não paga) e vendas zeradas. O uso de
      // cash back (usado > 0) já implica que a venda tinha pagamento.
      final recebeu =
          (venda.valorRecebido ?? 0) > 0 || venda.pagamentos.isNotEmpty;
      if (usado <= 0 && !recebeu) return;

      double saldoCorrente = cliente.saldoCashback;
      final novosMovimentos = <CashBackMovimento>[];

      // 1a) Expiração: créditos vencidos saem do saldo com o motivo no extrato
      final vencido = CashBackService.saldoVencido(
        movimentos,
        clienteId: clienteId,
        agora: agora,
      );
      if (vencido > 0) {
        saldoCorrente = CashBackService.arredondar2(saldoCorrente - vencido);
        novosMovimentos.add(
          CashBackMovimento(
            id: uuid.v4(),
            clienteId: clienteId,
            tipo: CashBackMovimentoTipo.debito,
            valor: vencido,
            saldoApos: saldoCorrente,
            data: agora,
            observacao: 'Crédito expirado',
          ),
        );
        // Os créditos vencidos passam a contar como totalmente consumidos
        movimentos = movimentos
            .map((m) =>
                (m.tipo == CashBackMovimentoTipo.credito &&
                        m.expiraEm != null &&
                        !m.expiraEm!.isAfter(agora))
                    ? m.copyWith(consumido: m.valor)
                    : m)
            .toList();
      }

      // 1b) Uso: consome dos créditos (FIFO por vencimento) e registra o débito
      final creditosConsumidos = <CashBackMovimento>[];
      if (usado > 0) {
        creditosConsumidos.addAll(_creditosConsumidos(movimentos, usado));
        movimentos = CashBackService.consumirDosCreditos(movimentos, usado);
        saldoCorrente = CashBackService.arredondar2(saldoCorrente - usado);
        novosMovimentos.add(
          CashBackMovimento(
            id: uuid.v4(),
            clienteId: clienteId,
            tipo: CashBackMovimentoTipo.debito,
            valor: usado,
            saldoApos: saldoCorrente,
            vendaId: venda.id,
            vendaNumero: venda.numero,
            data: agora,
            observacao: 'Usado como pagamento na venda ${venda.numero}',
          ),
        );
      }

      // 2) Crédito: % sobre o valor pago SEM cash back (não gera cash back
      //    sobre cash back). A taxa vem da configuração da empresa.
      final valorPagoReal = venda.valorTotal - usado;
      final ganho = CashBackService.ganhoPorVenda(
        valorPagoReal,
        taxa: CashBackService.taxaParaEmpresa(_empresaAtual),
      );
      if (ganho > 0) {
        saldoCorrente = CashBackService.arredondar2(saldoCorrente + ganho);
        final pct = (CashBackService.taxaParaEmpresa(_empresaAtual) * 100)
            .toStringAsFixed(0);
        novosMovimentos.add(
          CashBackMovimento(
            id: uuid.v4(),
            clienteId: clienteId,
            tipo: CashBackMovimentoTipo.credito,
            valor: ganho,
            saldoApos: saldoCorrente,
            vendaId: venda.id,
            vendaNumero: venda.numero,
            data: agora,
            expiraEm: CashBackService.dataExpiracao(
              agora,
              validadeDias:
                  CashBackService.validadeDiasParaEmpresa(_empresaAtual),
            ),
            observacao: 'Cash back $pct% da venda ${venda.numero}',
          ),
        );
      }

      if (novosMovimentos.isEmpty) {
        _vendasCashbackProcessadas.add(venda.id);
        return;
      }

      _vendasCashbackProcessadas.add(venda.id);
      await _persistirMovimentosCashBack([
        ...creditosConsumidos,
        ...novosMovimentos,
      ]);
      await updateCliente(
        cliente.copyWith(saldoCashback: saldoCorrente < 0 ? 0.0 : saldoCorrente),
      );
      debugPrint(
        '>>> [CashBack] ✓ ${cliente.nome}: -R\$$usado (uso) +R\$$ganho (ganho) → saldo R\$$saldoCorrente (venda ${venda.numero})',
      );
    } catch (e) {
      // Cash back nunca pode derrubar a venda — erro fica só no log.
      debugPrint('>>> [CashBack] ❌ Erro ao processar venda ${venda.numero}: $e');
    }
  }

  /// Lançamento manual de cash back (crédito de bonificação ou débito de
  /// resgate/estorno) feito pelo operador na tela do cliente.
  ///
  /// Débito manual consome os créditos que vencem primeiro (mesmo FIFO da
  /// venda). Crédito manual respeita a validade configurada na empresa.
  Future<void> lancarMovimentoCashBack({
    required String clienteId,
    required CashBackMovimentoTipo tipo,
    required double valor,
    String? observacao,
  }) async {
    if (valor <= 0) return;
    final index = _clientes.indexWhere((c) => c.id == clienteId);
    if (index == -1) return;
    final cliente = _clientes[index];
    final agora = DateTime.now();

    final movimentos = movimentosDoCliente(clienteId);
    final vencido = CashBackService.saldoVencido(
      movimentos,
      clienteId: clienteId,
      agora: agora,
    );
    double saldoCorrente = CashBackService.arredondar2(
      cliente.saldoCashback - vencido,
    );

    List<CashBackMovimento> creditosConsumidos = [];
    double valorLancado = valor;
    if (tipo == CashBackMovimentoTipo.debito) {
      // Débito não pode passar do saldo válido disponível
      if (valorLancado > saldoCorrente) valorLancado = saldoCorrente;
      if (valorLancado <= 0) return;
      creditosConsumidos = _creditosConsumidos(movimentos, valorLancado);
      saldoCorrente = CashBackService.arredondar2(saldoCorrente - valorLancado);
    } else {
      saldoCorrente = CashBackService.arredondar2(saldoCorrente + valorLancado);
    }

    final movimento = CashBackMovimento(
      id: uuid.v4(),
      clienteId: clienteId,
      tipo: tipo,
      valor: valorLancado,
      saldoApos: saldoCorrente,
      data: agora,
      expiraEm: tipo == CashBackMovimentoTipo.credito
          ? CashBackService.dataExpiracao(
              agora,
              validadeDias: CashBackService.validadeDiasParaEmpresa(_empresaAtual),
            )
          : null,
      observacao: observacao ??
          (tipo == CashBackMovimentoTipo.credito
              ? 'Crédito manual'
              : 'Débito manual'),
    );

    await _persistirMovimentosCashBack([...creditosConsumidos, movimento]);
    await updateCliente(
      cliente.copyWith(saldoCashback: saldoCorrente < 0 ? 0.0 : saldoCorrente),
    );
    debugPrint(
      '>>> [CashBack] ✓ Lançamento manual ${tipo.name} R\$$valorLancado para ${cliente.nome} → saldo R\$$saldoCorrente',
    );
  }

  Future<void> addVendaBalcao(VendaBalcao venda) async {
    // Garantir operador na venda: caminhos que criam VendaBalcao sem preencher
    // `operador` (ex.: pedido pago no PDV, fechamento de mesa/comanda) deixam a
    // venda "sem dono" e ela some do caixa nominado (getVendasDoCaixa exclui
    // vendas sem operador de caixas com responsável). Atribui o operador ativo.
    final temOperador =
        venda.operador != null && venda.operador!.trim().isNotEmpty;
    if (!temOperador) {
      final operadorPadrao = _responsavelAtivo ?? _usuarioAtualEmail;
      if (operadorPadrao != null && operadorPadrao.trim().isNotEmpty) {
        venda = venda.copyWith(operador: operadorPadrao.trim());
      }
    }
    _vendasBalcao.add(venda);
    // Trava o contador da empresa no número já emitido (ver o método).
    await _elevarMinimoNumeracaoPeloNumero(venda.numero);
    print(
      '✓ Venda ${venda.numero} (ID: ${venda.id}) salva em memória @ ${DateTime.now()}',
    );

    // Cash back: credita/debita o saldo do cliente identificado.
    // Fire-and-forget: o próprio método engole erros e tem trava de
    // processamento único por venda — não atrasa a finalização da venda.
    aplicarCashbackDaVenda(venda);

    // GRAVAÇÃO LOCAL POR REGISTRO: a venda vai sozinha para o PostgreSQL, sem
    // reescrever a tabela inteira (ver _persistirLinhaLocal, mais abaixo).
    _persistirLinhaLocal(LocalStorageService.keyVendasBalcao, venda.toMap());

    // Baixar estoque automaticamente
    for (final item in venda.itens) {
      // Premiação/bônus (valor zero): o estoque já saiu no momento do
      // lançamento no PDV (motivo 'premiacao') — não baixa de novo aqui.
      if (item.isBonus) continue;
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
          if (!ehDaComposicao &&
              opcao.produtoId.isNotEmpty &&
              opcao.quantidadeBaixa > 0) {
            registrarSaidaEstoque(
              produtoId: opcao.produtoId,
              quantidade: opcao.quantidadeBaixa * item.quantidade.toDouble(),
              motivo: 'venda_combo',
              observacao:
                  'Opção "${opcao.nome}" de ${item.nome} (venda ${venda.numero})',
              usuario: venda.operador,
              notify: false,
            );
          }
        }
      }
    }

    // Notificar listeners IMEDIATAMENTE para atualizar a UI
    notifyListeners();
    _persistirLinhaLocal(LocalStorageService.keyVendasBalcao, venda.toMap());

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(
      SupabaseService.tableVendasBalcao,
      venda.toMap(),
    );

    // GARANTIA MULTI-PC: upsert aguardado + confirmação Realtime
    await garantirEnvioEConfirmacao(
      tabela: SupabaseService.tableVendasBalcao,
      dados: venda.toMap(),
    );
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

      // GRAVAÇÃO LOCAL POR REGISTRO: só a venda alterada vai ao PostgreSQL,
      // sem reescrever a tabela inteira.
      _persistirLinhaLocal(LocalStorageService.keyVendasBalcao, venda.toMap());
      debugPrint(
        '>>> [VendaBalcao] ✅ Atualizada localmente: ${venda.numero} (ID: ${venda.id})',
      );

      // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
      await enviarMudancaParaSupabase(
        SupabaseService.tableVendasBalcao,
        venda.toMap(),
      );

      // GARANTIA MULTI-PC: upsert aguardado + confirmação Realtime
      await garantirEnvioEConfirmacao(
        tabela: SupabaseService.tableVendasBalcao,
        dados: venda.toMap(),
      );
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
    _removerLinhaLocal(LocalStorageService.keyVendasBalcao, id);
    _salvarAutomaticamente();
    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableVendasBalcao, {
      'id': id,
    }, evento: 'DELETE');
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
            produto = _produtos.firstWhere((p) => p.id == item.id);
          } catch (_) {
            // Se não encontrou pelo ID, tentar pelo nome
            try {
              produto = _produtos.firstWhere((p) => p.nome == item.nome);
            } catch (_) {
              print(
                '>>> ⚠ Produto não encontrado para devolução: ${item.nome}',
              );
              continue;
            }
          }

          final estoqueAnterior = produto.estoque;
          final novoEstoque = produto.estoque + quantidadeADevolver;

          await updateProduto(
            produto.copyWith(estoque: novoEstoque, updatedAt: DateTime.now()),
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
      _persistirLinhaLocal(
        LocalStorageService.keyVendasBalcao,
        vendaCancelada.toMap(),
      );
      // Sincronizar cancelamento com Supabase imediatamente
      await enviarMudancaParaSupabase(
        SupabaseService.tableVendasBalcao,
        vendaCancelada.toMap(),
      );

      // Cancelar NFC-e associada à venda (se existir)
      try {
        final nfcesVinculadas = _nfces
            .where(
              (n) => n.vendaId == venda.id || n.vendaNumero == venda.numero,
            )
            .toList();
        for (final nfce in nfcesVinculadas) {
          if (nfce.status == 'autorizada' || nfce.status == 'sucesso') {
            final nfceCancelada = nfce.copyWith(
              status: 'cancelada',
              updatedAt: DateTime.now(),
            );
            await atualizarNFCe(nfceCancelada);
            print(
              '✓ NFC-e ${nfce.numero} vinculada à venda ${venda.numero} marcada como cancelada',
            );
            // Sincronizar cancelamento da NFC-e com Supabase
            await enviarMudancaParaSupabase(
              SupabaseService.tableNFCes,
              nfceCancelada.toMap(),
            );
          }
        }
      } catch (e) {
        print('>>> ⚠ Erro ao cancelar NFC-e vinculada à venda: $e');
      }
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
      _persistirLinhaLocal(
        LocalStorageService.keyVendasBalcao,
        vendaAtualizada.toMap(),
      );
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

    unawaited(
      _upsertNoSupabase(SupabaseService.tableTrocasDevolucoes, troca.toMap()),
    );

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
      await enviarMudancaParaSupabase(
        SupabaseService.tableTrocasDevolucoes,
        troca.toMap(),
      );
    }
  }

  Future<void> deleteTrocaDevolucao(String id) async {
    _trocasDevolucoes.removeWhere((t) => t.id == id);
    // Exclusão real no banco local (senão volta no boot).
    _removerLinhaLocal(LocalStorageService.keyTrocasDevolucoes, id);
    print('✓ Troca/Devolução removida da memória');
    notifyListeners();
    _marcarSujo(LocalStorageService.keyTrocasDevolucoes);
    // Sincronizar exclusão com Supabase
    await enviarMudancaParaSupabase(SupabaseService.tableTrocasDevolucoes, {
      'id': id,
    }, evento: 'DELETE');
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

  // Próximo número de venda (considera vendas balcão E pedidos, porque venda do
  // PDV também é gravada como pedido em alguns fluxos).
  //
  // Caixa nomeado → sequência PRÓPRIA dele ('CX1-0001'), contada só entre
  // números do mesmo prefixo: dois computadores offline nunca chegam ao mesmo
  // número. Sem nome → sequência VND- global de sempre, respeitando o mínimo
  // vindo da nuvem.
  String getProximoNumeroVenda() {
    final caixa = nomeDoCaixa;
    if (caixa.isNotEmpty) {
      return NumeracaoVenda.formatar(
        caixa,
        NumeracaoVenda.proximoNumeroLivre(
          numeros: _numerosDeVenda,
          prefixo: caixa,
          piso: _minimoCaixa ?? 0,
        ),
      );
    }

    // Coletar todos os números existentes com o prefixo legado
    final numerosExistentes = NumeracaoVenda.usadosDoPrefixo(
      _numerosDeVenda,
      NumeracaoVenda.prefixoLegado,
    );

    // Encontrar o próximo número disponível
    int proximoNumero = 1;
    if (numerosExistentes.isNotEmpty) {
      // Pegar o maior número e adicionar 1
      proximoNumero = numerosExistentes.reduce((a, b) => a > b ? a : b) + 1;
    }

    // Respeitar mínimo sincronizado com Supabase (evita numerar abaixo do que já existe na nuvem)
    final minVal = int.tryParse(_minNumeroVenda ?? '0') ?? 0;
    if (proximoNumero <= minVal) proximoNumero = minVal + 1;

    // Garantir que o número não existe (proteção extra)
    while (numerosExistentes.contains(proximoNumero)) {
      proximoNumero++;
    }

    return NumeracaoVenda.formatar(NumeracaoVenda.prefixoLegado, proximoNumero);
  }

  // Próximo número de pedido (PED-0001, PED-0002, etc)
  // Respeita o mínimo salvo via sincronizarNumeracaoComSupabase()
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

    // Respeitar mínimo sincronizado com Supabase
    final minStr = _minNumeroPedido;
    if (minStr != null) {
      final minVal = int.tryParse(minStr) ?? 0;
      if (proximoNumero <= minVal) proximoNumero = minVal + 1;
    }

    // Garantir que o número não existe (proteção extra)
    while (numerosExistentes.contains(proximoNumero)) {
      proximoNumero++;
    }

    return 'PED-${proximoNumero.toString().padLeft(4, '0')}';
  }

  // ─── Numeração SEGURA (multi-PC): consulta a nuvem antes de gerar ────────
  // Cache curto: evita consultar o Supabase a cada venda consecutiva, mas
  // mantém os mínimos frescos o suficiente para não colidir entre máquinas.
  DateTime? _ultimaConsultaNumeracaoNuvem;
  static const Duration _cacheNumeracaoNuvem = Duration(seconds: 8);

  /// Consulta o maior número VND/PED já existente na NUVEM para a empresa atual.
  /// Retorna {vnd, ped} ou null em caso de offline/erro/timeout.
  Future<Map<String, int>?> _consultarMaiorNumeroNaNuvem() async {
    if (!SupabaseService.isAvailable || _currentEmpresaId == null) return null;
    // Nuvem marcada indisponível: não consulta (evita 2×4s de timeout).
    if (SupabaseService.instance.servidorIndisponivel) return null;
    // Cache curto
    final agora = DateTime.now();
    if (_ultimaConsultaNumeracaoNuvem != null &&
        agora.difference(_ultimaConsultaNumeracaoNuvem!) <
            _cacheNumeracaoNuvem) {
      return {
        'vnd': int.tryParse(_minNumeroVenda ?? '0') ?? 0,
        'ped': int.tryParse(_minNumeroPedido ?? '0') ?? 0,
      };
    }
    try {
      final client = SupabaseService.instance.client;
      final empresaId = _currentEmpresaId!;
      int vnd = 0, ped = 0;

      // Últimos 300 por ordem descendente de numero (pega o maior)
      final resVnd = await client
          .from(SupabaseService.tableVendasBalcao)
          .select('numero')
          .eq('empresa_id', empresaId)
          .order('numero', ascending: false)
          .limit(300)
          .timeout(const Duration(seconds: 4));
      for (final row in resVnd) {
        final numero = row['numero']?.toString() ?? '';
        final m = RegExp(r'VND-(\d+)').firstMatch(numero);
        if (m != null) {
          final n = int.tryParse(m.group(1)!) ?? 0;
          if (n > vnd) vnd = n;
        }
      }

      final resPed = await client
          .from(SupabaseService.tablePedidos)
          .select('numero')
          .eq('empresa_id', empresaId)
          .order('numero', ascending: false)
          .limit(300)
          .timeout(const Duration(seconds: 4));
      for (final row in resPed) {
        final numero = row['numero']?.toString() ?? '';
        final mV = RegExp(r'VND-(\d+)').firstMatch(numero);
        if (mV != null) {
          final n = int.tryParse(mV.group(1)!) ?? 0;
          if (n > vnd) vnd = n;
        }
        if (numero.startsWith('PED-')) {
          final n = int.tryParse(numero.substring(4)) ?? 0;
          if (n > ped) ped = n;
        }
      }

      _ultimaConsultaNumeracaoNuvem = agora;
      return {'vnd': vnd, 'ped': ped};
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Falha ao consultar maior número na nuvem: $e',
      );
      return null;
    }
  }

  /// Atualiza o piso de numeração (local) a partir do maior número já existente
  /// na NUVEM — em BACKGROUND, para nunca segurar a emissão de uma venda.
  Future<void> _atualizarMinimoPelaNuvem(String tipo) async {
    try {
      final nuvem = await _consultarMaiorNumeroNaNuvem();
      if (nuvem == null) return;
      final maior = (tipo == 'venda' ? nuvem['vnd'] : nuvem['ped']) ?? 0;
      if (maior <= 0) return;
      if (tipo == 'venda') {
        if (maior > (int.tryParse(_minNumeroVenda ?? '0') ?? 0)) {
          _minNumeroVenda = maior.toString();
          await _salvarMinNumeracao('venda', maior);
          debugPrint(
            '>>> [DataService] ✅ Mínimo VND atualizado pela nuvem '
            '(empresa $_currentEmpresaId): $maior',
          );
        }
      } else {
        if (maior > (int.tryParse(_minNumeroPedido ?? '0') ?? 0)) {
          _minNumeroPedido = maior.toString();
          await _salvarMinNumeracao('pedido', maior);
          debugPrint(
            '>>> [DataService] ✅ Mínimo PED atualizado pela nuvem '
            '(empresa $_currentEmpresaId): $maior',
          );
        }
      }
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Atualização de mínimo pela nuvem falhou: $e',
      );
    }
  }

  /// Próximo número de venda SEGURO para várias máquinas.
  ///
  /// Caixa nomeado: a sequência é própria dele ('CX1-0001'), então não existe
  /// colisão possível com outro computador e nem é preciso consultar a nuvem.
  /// Sem nome: 1º o bloco reservado deste PC; 2º o comportamento anterior
  /// (maior VND da nuvem + 1). Offline, cai no local — e o sincronizador
  /// renumera o que subir repetido.
  Future<String> getProximoNumeroVendaSeguro() async {
    if (nomeDoCaixa.isNotEmpty) return getProximoNumeroVenda();

    final doBloco = await _proximoNumeroDaFaixa('venda');
    if (doBloco != null) return doBloco;

    // Nuvem FORA do caminho crítico: atualiza o mínimo em background e devolve
    // o número local na hora (a venda nunca espera rede).
    unawaited(_atualizarMinimoPelaNuvem('venda'));
    return getProximoNumeroVenda();
  }

  /// Próximo número de pedido SEGURO para várias máquinas (mesma lógica da venda).
  Future<String> getProximoNumeroPedidoSeguro() async {
    final doBloco = await _proximoNumeroDaFaixa('pedido');
    if (doBloco != null) return doBloco;

    // Nuvem FORA do caminho crítico: atualiza em background e usa o local.
    unawaited(_atualizarMinimoPelaNuvem('pedido'));
    return getProximoNumeroPedido();
  }

  // ─── Mínimos de numeração (carregados do exodo_config) ───────────────────
  String? _minNumeroVenda;
  String? _minNumeroPedido;

  // ─── Mínimos das séries que antes eram calculadas SÓ com a lista em ──────
  // ─── memória (SRV-/ORC-/AGD-). Com o piso persistido, a série nunca volta ─
  // ─── para 0001 quando a lista ainda não carregou, o app troca de empresa ou ─
  // ─── outro computador já emitiu números. ──────────────────────────────────
  String? _minNumeroServico;
  String? _minNumeroOrcamento;
  String? _minNumeroAgendamento;

  static final RegExp _rePrefixoNumero = RegExp(r'^([A-Za-z]+)-(\d+)');

  /// Sobe o piso da série correspondente a um número JÁ EMITIDO (sem gravar).
  ///
  /// Só trata SRV-/ORC-/AGD-; VND-/PED- continuam pelo caminho antigo
  /// (`_elevarMinimoNumeracaoPeloNumero`, que tem regra própria de caixa nomeado).
  void _elevarPisoEmMemoria(String? numero) {
    final match = _rePrefixoNumero.firstMatch(numero ?? '');
    if (match == null) return;
    final prefixo = match.group(1)!.toUpperCase();
    final n = int.tryParse(match.group(2)!) ?? 0;
    if (n <= 0) return;
    switch (prefixo) {
      case 'SRV':
        if (n > (int.tryParse(_minNumeroServico ?? '0') ?? 0)) {
          _minNumeroServico = n.toString();
        }
      case 'ORC':
        if (n > (int.tryParse(_minNumeroOrcamento ?? '0') ?? 0)) {
          _minNumeroOrcamento = n.toString();
        }
      case 'AGD':
        if (n > (int.tryParse(_minNumeroAgendamento ?? '0') ?? 0)) {
          _minNumeroAgendamento = n.toString();
        }
    }
  }

  /// Sobe os pisos SRV/ORC/AGD a partir do que está em memória e persiste só o
  /// que mudou. Roda depois da carga local e depois da carga da nuvem: qualquer
  /// número que exista em QUALQUER DAS DUAS fontes trava a série daí em diante.
  Future<void> _elevarEPersistirPisosSerie() async {
    final antesServico = _minNumeroServico;
    final antesOrcamento = _minNumeroOrcamento;
    final antesAgendamento = _minNumeroAgendamento;

    for (final s in _servicosRealizados) {
      _elevarPisoEmMemoria(s.numero);
    }
    for (final p in _pedidos) {
      _elevarPisoEmMemoria(p.numero);
    }
    for (final o in _orcamentos) {
      _elevarPisoEmMemoria(o.numero);
    }
    for (final a in _agendamentosServico) {
      _elevarPisoEmMemoria(a.numero);
    }

    try {
      if (antesServico != _minNumeroServico && _minNumeroServico != null) {
        await _salvarMinNumeracao('servico', int.parse(_minNumeroServico!));
      }
      if (antesOrcamento != _minNumeroOrcamento &&
          _minNumeroOrcamento != null) {
        await _salvarMinNumeracao('orcamento', int.parse(_minNumeroOrcamento!));
      }
      if (antesAgendamento != _minNumeroAgendamento &&
          _minNumeroAgendamento != null) {
        await _salvarMinNumeracao(
          'agendamento',
          int.parse(_minNumeroAgendamento!),
        );
      }
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Falha ao persistir pisos de série: $e');
    }
  }

  // ─── Identidade DESTE caixa (numeração por caixa: CX1-0001) ──────────────
  // Cada computador nomeia o próprio caixa e passa a ter a PRÓPRIA sequência.
  // É isso que impede duas máquinas sem internet de emitirem o mesmo número,
  // sem depender de consultar a nuvem a cada venda.
  String _nomeCaixa = '';
  int? _minimoCaixa;

  /// Nome do caixa deste computador ('CX1'); vazio quando ninguém nomeou ainda.
  String get nomeDoCaixa => _nomeCaixa;

  /// true quando a numeração das vendas é por caixa (não usa a sequência VND global).
  bool get numeracaoPorCaixa => _nomeCaixa.isNotEmpty;

  /// Piso de numeração do caixa atual — exposto para diagnóstico/tela.
  int get pisoDeNumeracaoDoCaixa => _minimoCaixa ?? 0;

  String _chaveNomeCaixa(String empresaId) => 'exodo_caixa_nome_$empresaId';

  String? _chaveMinimoCaixa(String prefixo, String empresaId) {
    final limpo = prefixo.trim().toLowerCase();
    if (limpo.isEmpty || empresaId.trim().isEmpty) return null;
    return 'exodo_min_numero_caixa_${limpo}_$empresaId';
  }

  /// Números dos dois lugares onde uma venda do PDV pode estar gravada.
  Iterable<String?> get _numerosDeVenda => [
    for (final venda in _vendasBalcao) venda.numero,
    for (final pedido in _pedidos) pedido.numero,
  ];

  /// Carrega o nome deste caixa e o piso de numeração dele (por empresa).
  Future<void> carregarIdentidadeDoCaixa() async {
    final empresaId = (_currentEmpresaId ?? '').trim();
    _nomeCaixa = '';
    _minimoCaixa = null;
    if (empresaId.isEmpty) return;
    try {
      final db = DatabaseService();
      final salvo = await db.carregarConfig(_chaveNomeCaixa(empresaId));
      _nomeCaixa = NumeracaoVenda.normalizarCaixa(salvo?.toString()) ?? '';
      final chavePiso = _chaveMinimoCaixa(_nomeCaixa, empresaId);
      if (chavePiso != null) {
        final piso = await db.carregarConfig(chavePiso);
        _minimoCaixa = int.tryParse(piso?.toString() ?? '');
      }
      debugPrint(
        '>>> [DataService] 🧾 Caixa deste computador: '
        '${_nomeCaixa.isEmpty ? '(sem nome - numeracao VND- global)' : _nomeCaixa} '
        '| piso de numeracao: ${_minimoCaixa ?? 0}',
      );
      // Quem mais usa este nome? Pergunta à nuvem em segundo plano (a abertura
      // do app não espera rede; o aviso aparece quando a resposta chega).
      unawaited(verificarDuplicidadeDoNomeDoCaixa());
    } catch (e) {
      debugPrint(
        '>>> [DataService] Aviso ao carregar a identidade do caixa: $e',
      );
    }
  }

  /// Define o nome deste caixa (ou limpa, com texto vazio).
  ///
  /// Devolve o nome normalizado gravado (ex.: 'CX1'), ou null quando o texto é
  /// inválido (`PED`/`VND` são reservados, e precisamos de começar com letra).
  /// Assim que o nome muda, a numeração das vendas passa a ser por caixa: o
  /// bloco antigo (VND) deixa de valer.
  Future<String?> definirNomeDoCaixa(String bruto) async {
    final empresaId = (_currentEmpresaId ?? '').trim();
    if (empresaId.isEmpty) return null;

    final texto = bruto.trim();
    final normalizado = texto.isEmpty
        ? ''
        : NumeracaoVenda.normalizarCaixa(texto);
    if (texto.isNotEmpty && normalizado == null) return null;

    _nomeCaixa = normalizado ?? '';
    try {
      await DatabaseService().salvarConfig(
        _chaveNomeCaixa(empresaId),
        _nomeCaixa,
      );
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao gravar o nome do caixa: $e');
    }

    // Piso do prefixo novo: sem ele, um app abrindo com a lista ainda vazia
    // entregaria 'CX1-0001' mesmo já existindo 'CX1-0007' na nuvem.
    _minimoCaixa = null;
    final chavePiso = _chaveMinimoCaixa(_nomeCaixa, empresaId);
    if (chavePiso != null) {
      try {
        final piso = await DatabaseService().carregarConfig(chavePiso);
        _minimoCaixa = int.tryParse(piso?.toString() ?? '');
      } catch (_) {}
    }

    _faixaVendaAtual = null;
    _ultimaConsultaNumeracaoNuvem = null;
    debugPrint(
      '>>> [DataService] 🧾 Nome do caixa definido: '
      '${_nomeCaixa.isEmpty ? '(limpo - volta para VND- global)' : _nomeCaixa}',
    );
    // O nome mudou: a lista de "outras máquinas com este nome" era do nome
    // ANTERIOR — some agora e é conferida de novo logo abaixo.
    _caixasComMesmoNome = const [];
    unawaited(verificarDuplicidadeDoNomeDoCaixa());
    notifyListeners();
    return _nomeCaixa;
  }

  Future<void> _salvarMinimoCaixa(int valor) async {
    final empresaId = (_currentEmpresaId ?? '').trim();
    final chave = _chaveMinimoCaixa(_nomeCaixa, empresaId);
    if (chave == null) return;
    try {
      await DatabaseService().salvarConfig(chave, valor.toString());
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao salvar $chave: $e');
    }
  }

  // ─── Nome de caixa REPETIDO entre as máquinas ────────────────────────────
  // O nome do caixa é configuração LOCAL (o sincronizador não a leva para a
  // nuvem), então a única forma de este PC saber que OUTRO está usando o mesmo
  // nome é publicar a própria identidade e ler a dos outros. A publicação vai em
  // `sync_logs` (evento `caixa_identificado`) porque é a tabela de monitoramento
  // que o app já grava e já lê — nenhuma tabela ou coluna nova é necessária.
  //
  // Isso é o aviso que chega ANTES: sem ele, o mesmo nome nos dois caixas só
  // aparecia depois, como número de venda repetido renumerado pelo
  // sincronizador — e aí já era venda emitida.
  List<String> _caixasComMesmoNome = const [];
  bool _verificandoDuplicidadeDoCaixa = false;

  /// 'empresa|nome|pc' já publicado nesta sessão (evita encher a nuvem de
  /// publicações iguais a cada conferência).
  String? _identidadeDoCaixaPublicada;

  /// Quantas publicações de identidade trazer da nuvem. Cada máquina publica no
  /// máximo uma vez por sessão, e só a MAIS RECENTE de cada PC interessa.
  static const int _limitePublicacoesDeIdentidade = 200;

  /// Nomes de OUTROS computadores que estão usando o mesmo nome de caixa deste.
  List<String> get caixasComMesmoNome => _caixasComMesmoNome;

  /// true quando outra máquina publicou o MESMO nome de caixa que este PC.
  bool get nomeDeCaixaDuplicado => _caixasComMesmoNome.isNotEmpty;

  /// true enquanto a conferência do nome do caixa está acontecendo na nuvem.
  bool get verificandoDuplicidadeDoCaixa => _verificandoDuplicidadeDoCaixa;

  /// Nome deste computador para as outras máquinas (o hostname).
  String? get _pcDesteComputador {
    try {
      return Platform.localHostname;
    } catch (_) {
      return null;
    }
  }

  /// Quem está usando [nome] como caixa na nuvem, SEM contar este computador.
  ///
  /// Devolve lista vazia quando não há nuvem, ninguém publicou ou o nome está
  /// livre. O aviso é uma AJUDA, não uma trava: nunca impede a operação.
  Future<List<String>> maquinasUsandoNomeDeCaixa(String nome) async {
    final empresaId = (_currentEmpresaId ?? '').trim();
    final pc = _pcDesteComputador;
    final normalizado = NumeracaoVenda.normalizarCaixa(nome);
    if (empresaId.isEmpty || pc == null || normalizado == null) return const [];
    if (!SupabaseService.isAvailable) return const [];

    try {
      final eventos = await SupabaseService.instance.select(
        'sync_logs',
        filters: {
          'empresa_id': empresaId,
          'evento': IdentidadeCaixa.eventoNaNuvem,
        },
        orderBy: 'created_at',
        descending: true,
        limit: _limitePublicacoesDeIdentidade,
      );
      return IdentidadeCaixa.maquinasUsandoNome(
        eventos: eventos,
        meuPc: pc,
        nome: normalizado,
      );
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Não foi possível conferir o nome do '
        'caixa na nuvem: $e',
      );
      return const [];
    }
  }

  /// Publica o nome deste caixa na nuvem e confere se OUTRA máquina usa o mesmo.
  ///
  /// Chamado ao definir o nome e ao abrir a empresa. A publicação acontece uma
  /// vez por sessão/empresa/nome (não é heartbeat: é histórico de identidade).
  /// Os chamadores usam em segundo plano, para a abertura do app não esperar
  /// rede — quando a resposta chega, [notifyListeners] atualiza o aviso na tela.
  Future<void> verificarDuplicidadeDoNomeDoCaixa() async {
    final empresaId = (_currentEmpresaId ?? '').trim();
    if (empresaId.isEmpty) return;

    // Sem nome não há prefixo a defender: nada a publicar nem a conferir.
    if (_nomeCaixa.isEmpty) {
      if (_caixasComMesmoNome.isNotEmpty) {
        _caixasComMesmoNome = const [];
        notifyListeners();
      }
      return;
    }

    unawaited(_publicarIdentidadeDoCaixa(empresaId));
    if (_verificandoDuplicidadeDoCaixa) return;

    _verificandoDuplicidadeDoCaixa = true;
    try {
      final outras = await maquinasUsandoNomeDeCaixa(_nomeCaixa);
      final mudou = !_mesmasMaquinas(_caixasComMesmoNome, outras);
      _caixasComMesmoNome = outras;
      if (outras.isNotEmpty) {
        debugPrint(
          '>>> [DataService] ⚠️ O nome de caixa "$_nomeCaixa" também '
          'está em uso em: ${outras.join(', ')} — risco de número de venda '
          'repetido entre caixas.',
        );
      }
      if (mudou) notifyListeners();
    } catch (e) {
      debugPrint('>>> [DataService] Aviso ao conferir o nome do caixa: $e');
    } finally {
      _verificandoDuplicidadeDoCaixa = false;
      notifyListeners();
    }
  }

  Future<void> _publicarIdentidadeDoCaixa(String empresaId) async {
    final pc = _pcDesteComputador;
    if (pc == null || _nomeCaixa.isEmpty) return;
    if (!SupabaseService.isAvailable) return;

    final assinatura = '$empresaId|$_nomeCaixa|$pc';
    if (_identidadeDoCaixaPublicada == assinatura) return;
    _identidadeDoCaixaPublicada = assinatura;
    try {
      await SyncMonitorService.instance.registrarEvento(
        empresaId: empresaId,
        evento: IdentidadeCaixa.eventoNaNuvem,
        detalhes: _nomeCaixa,
      );
    } catch (e) {
      _identidadeDoCaixaPublicada =
          null; // falhou: tenta na próxima conferência
      debugPrint(
        '>>> [DataService] ⚠️ Não foi possível publicar o nome do '
        'caixa na nuvem: $e',
      );
    }
  }

  /// As duas listas trazem as MESMAS máquinas? (evita notifyListeners de graça)
  bool _mesmasMaquinas(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (final nome in a) {
      if (!b.contains(nome)) return false;
    }
    return true;
  }

  // ─── Faixa de numeração reservada para ESTE computador ───────────────────
  // Dois PCs sem internet geravam o mesmo "VND-0003". Com bloco reservado cada
  // um tem seu pedaço da sequência e a venda offline sai sem colidir.
  final FaixaNumeracaoService _faixas = FaixaNumeracaoService();
  FaixaNumeracao? _faixaVendaAtual;
  FaixaNumeracao? _faixaPedidoAtual;

  /// Consome o próximo número do bloco deste PC (devolve já formatado: 'VND-0434').
  ///
  /// Devolve null quando não há bloco e não foi possível reservar (sem internet,
  /// sem permissão no contador ou bloco esgotado offline). Nesse caso o chamador
  /// cai na numeração antiga e o sincronizador renumera qualquer repetido que
  /// subir — nenhuma venda é perdida.
  Future<String?> _proximoNumeroDaFaixa(String tipo) async {
    final empresaId = (_currentEmpresaId ?? '').trim();
    if (empresaId.isEmpty) return null;
    try {
      var faixa = tipo == 'venda' ? _faixaVendaAtual : _faixaPedidoAtual;
      faixa ??= await _faixas.lerLocal(tipo, empresaId);

      if (faixa == null || faixa.esgotada) {
        // Nuvem indisponível: não tenta reservar bloco (5× timeout). Cai na
        // sequência local — o sincronizador renumera qualquer repetido ao subir.
        if (SupabaseService.instance.servidorIndisponivel) {
          debugPrint(
            '>>> [DataService] ⏸️ Faixa de numeração: nuvem '
            'indisponível, usando sequência local ($tipo).',
          );
          return null;
        }
        final nova = await _faixas.reservar(
          tipo: tipo,
          empresaId: empresaId,
          aPartirDe: await _baseDaReserva(tipo),
        );
        if (nova == null) return null;
        faixa = nova;
        await _faixas.salvarLocal(nova, empresaId);
        debugPrint(
          '>>> [DataService] 🔢 Faixa de numeração reservada ($tipo): '
          '${nova.inicio}..${nova.fim} — ${nova.restantes} números para vender offline',
        );
      }

      final numero = faixa.proximo;
      final avancada = faixa.avancar();
      if (tipo == 'venda') {
        _faixaVendaAtual = avancada;
      } else {
        _faixaPedidoAtual = avancada;
      }
      await _faixas.salvarLocal(avancada, empresaId);
      final prefixo = tipo == 'venda' ? 'VND' : 'PED';
      return '$prefixo-${numero.toString().padLeft(4, '0')}';
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Faixa de numeração indisponível ($tipo): $e',
      );
      return null;
    }
  }

  /// Menor número que a loja ainda pode usar (olhando local E nuvem), usado como
  /// piso na hora de reservar. Evita entregar número já emitido quando o contador
  /// da nuvem está atrasado em relação à realidade.
  Future<int> _baseDaReserva(String tipo) async {
    final texto = tipo == 'venda'
        ? getProximoNumeroVenda()
        : getProximoNumeroPedido();
    var base = int.tryParse(texto.split('-').last) ?? 1;
    final nuvem = await _consultarMaiorNumeroNaNuvem();
    if (nuvem != null) {
      final maiorNuvem = (tipo == 'venda' ? nuvem['vnd'] : nuvem['ped']) ?? 0;
      if (maiorNuvem + 1 > base) base = maiorNuvem + 1;
    }
    return base < 1 ? 1 : base;
  }

  /// Faixas de NFC-e em uso nesta sessão, por série ('1', '2'...).
  ///
  /// A série entra na chave porque cada série tem SEQUÊNCIA PRÓPIRA na SEFAZ:
  /// compartilhar um bloco entre séries entregaria número repetido.
  final Map<String, FaixaNumeracao> _faixasNfceAtual = {};

  /// Reserva atomicamente o próximo NÚMERO FISCAL da série (bloco via CAS na
  /// nuvem, mesma mecânica já usada em VND-/PED-).
  ///
  /// Por quê: o cálculo de NFC-e era "maior número que eu tenho + 1" — dois
  /// PCs emitindo offline chegavam ao MESMO número e o segundo levava
  /// rejeição 539 de duplicidade na SEFAZ (o fiscal é único, diferente de um
  /// simples número interno).
  ///
  /// Devolve null quando não dá para reservar (offline / nuvem indisponível /
  /// sem permissão): o chamador então cai no cálculo local antigo — emitir com
  /// risco de 539 é melhor do que não emitir.
  Future<int?> reservarProximoNumeroNfce({
    String serie = '1',
    int numeroInicial = 1,
  }) async {
    final serieNorm = serie.trim().isEmpty ? '1' : serie.trim();
    final empresaId = (_currentEmpresaId ?? '').trim();
    if (empresaId.isEmpty) return null;
    final tipo = 'nfce_s$serieNorm';
    try {
      // Piso: maior número desta série já registrado (lista local de notas).
      final base = getProximoNumeroNfce(
        serie: serieNorm,
        numeroInicial: numeroInicial,
      );
      final piso = base < 1 ? 1 : base;

      var faixa =
          _faixasNfceAtual[serieNorm] ??
          await _faixas.lerLocal(tipo, empresaId);

      // Faixa atrasada em relação à realidade (ex.: reemissão/contingência
      // queimou números FORA do bloco): não dá para entregar número já usado,
      // então descarta e reserva um bloco novo a partir do piso.
      if (faixa != null && !faixa.esgotada && faixa.proximo < piso) {
        debugPrint(
          '>>> [DataService] 🔢 Faixa NFC-e série $serieNorm atrasada '
          '(${faixa.proximo} < $piso) — reservando bloco novo.',
        );
        faixa = null;
      }

      if (faixa == null || faixa.esgotada) {
        // Nuvem indisponível: não tenta reservar (evita timeouts no caixa).
        if (SupabaseService.instance.servidorIndisponivel) {
          debugPrint(
            '>>> [DataService] ⏸️ Faixa NFC-e série $serieNorm: nuvem '
            'indisponível — usando sequência local.',
          );
          return null;
        }
        final nova = await _faixas.reservar(
          tipo: tipo,
          empresaId: empresaId,
          aPartirDe: piso,
          tamanho: 100,
        );
        if (nova == null) return null;
        faixa = nova;
        await _faixas.salvarLocal(nova, empresaId);
        debugPrint(
          '>>> [DataService] 🔢 Faixa NFC-e reservada (série $serieNorm): '
          '${nova.inicio}..${nova.fim} — ${nova.restantes} números para emitir offline',
        );
      }

      final numero = faixa.proximo;
      final avancada = faixa.avancar();
      _faixasNfceAtual[serieNorm] = avancada;
      await _faixas.salvarLocal(avancada, empresaId);
      return numero;
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Faixa NFC-e indisponível (série $serieNorm): $e',
      );
      return null;
    }
  }

  /// Chave de configuração dos mínimos de numeração, SEMPRE com o id da empresa.
  ///
  /// A tabela `exodo_config` é única no banco local (não tem `empresa_id`): usar a
  /// chave sem o id fazia a numeração vazar de uma empresa para a outra — a empresa
  /// nova herdava o mínimo da anterior e a venda saía com o número da outra empresa.
  String? _chaveMinNumeracao(String tipo, [String? empresaId]) {
    final id = ((empresaId ?? _currentEmpresaId) ?? '').trim();
    if (id.isEmpty) return null;
    return 'exodo_min_numero_${tipo}_$id';
  }

  /// Carrega os mínimos de numeração da EMPRESA ATUAL do banco local.
  /// Também zera o cache da consulta à nuvem, que também é por empresa.
  Future<void> carregarMinimosNumeracao() async {
    _ultimaConsultaNumeracaoNuvem = null;
    // Bloco de numeração é por empresa/Pc: ao trocar de empresa, o bloco antigo
    // não vale mais (senão a empresa nova sairia numerando na faixa da outra).
    _faixaVendaAtual = null;
    _faixaPedidoAtual = null;
    // Bloco de NFC-e também é por empresa/série: não pode vazar entre empresas.
    _faixasNfceAtual.clear();
    // Nome do caixa é por empresa: trocar de empresa pode trocar o prefixo.
    await carregarIdentidadeDoCaixa();

    final chaveVnd = _chaveMinNumeracao('venda');
    final chavePed = _chaveMinNumeracao('pedido');
    final chaveSrv = _chaveMinNumeracao('servico');
    final chaveOrc = _chaveMinNumeracao('orcamento');
    final chaveAgd = _chaveMinNumeracao('agendamento');
    if (chaveVnd == null || chavePed == null) {
      _minNumeroVenda = null;
      _minNumeroPedido = null;
      _minNumeroServico = null;
      _minNumeroOrcamento = null;
      _minNumeroAgendamento = null;
      return;
    }

    try {
      final db = DatabaseService();
      final vnd = await db.carregarConfig(chaveVnd);
      final ped = await db.carregarConfig(chavePed);
      final srv = chaveSrv == null ? null : await db.carregarConfig(chaveSrv);
      final orc = chaveOrc == null ? null : await db.carregarConfig(chaveOrc);
      final agd = chaveAgd == null ? null : await db.carregarConfig(chaveAgd);
      _minNumeroVenda = vnd?.toString();
      _minNumeroPedido = ped?.toString();
      _minNumeroServico = srv?.toString();
      _minNumeroOrcamento = orc?.toString();
      _minNumeroAgendamento = agd?.toString();
      debugPrint(
        '>>> [DataService] Mínimos carregados (empresa $_currentEmpresaId): VND=$_minNumeroVenda PED=$_minNumeroPedido SRV=$_minNumeroServico ORC=$_minNumeroOrcamento AGD=$_minNumeroAgendamento',
      );
    } catch (e) {
      debugPrint(
        '>>> [DataService] Aviso ao carregar mínimos de numeração: $e',
      );
    }
  }

  /// Grava o mínimo de numeração da empresa informada (ou da atual).
  Future<void> _salvarMinNumeracao(
    String tipo,
    int valor, [
    String? empresaId,
  ]) async {
    final chave = _chaveMinNumeracao(tipo, empresaId);
    if (chave == null) return;
    try {
      await DatabaseService().salvarConfig(chave, valor.toString());
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao salvar $chave: $e');
    }
  }

  /// Eleva o mínimo de numeração da empresa a partir de um número JÁ EMITIDO
  /// (ex.: 'VND-0408' → 408).
  ///
  /// Isso trava o contador: se em algum momento a lista em memória ainda não
  /// estiver carregada (app abrindo, troca de empresa, consulta à nuvem falhando),
  /// sem esta trava o próximo número poderia voltar para VND-0001 e duplicar
  /// uma venda que já existe.
  Future<void> _elevarMinimoNumeracaoPeloNumero(String? numero) async {
    final separado = NumeracaoVenda.separar(numero);
    if (separado == null) return; // vazio ou fora do formato: nada a elevar
    final prefixo = separado.$1;
    final n = separado.$2;

    if (prefixo == NumeracaoVenda.prefixoPedido) {
      if (n > (int.tryParse(_minNumeroPedido ?? '0') ?? 0)) {
        _minNumeroPedido = n.toString();
        await _salvarMinNumeracao('pedido', n);
      }
      return;
    }

    // Caixa nomeado: o piso é do prefixo do caixa ('CX1'), não da sequência VND.
    if (nomeDoCaixa.isNotEmpty && prefixo == nomeDoCaixa.toUpperCase()) {
      if (n > (_minimoCaixa ?? 0)) {
        _minimoCaixa = n;
        await _salvarMinimoCaixa(n);
      }
      return;
    }

    // Legado: qualquer outro prefixo (VND e o que já existe) trava a sequência global.
    if (n > (int.tryParse(_minNumeroVenda ?? '0') ?? 0)) {
      _minNumeroVenda = n.toString();
      await _salvarMinNumeracao('venda', n);
    }
  }

  /// Diagnóstico: retorna o maior número VND e PED do Supabase e do banco local
  Future<Map<String, int>> diagnosticarNumeracao(String empresaId) async {
    int localVnd = 0, localPed = 0, supabaseVnd = 0, supabasePed = 0;

    // Local
    for (final v in _vendasBalcao) {
      final m = RegExp(r'VND-(\d+)').firstMatch(v.numero);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > localVnd) localVnd = n;
      }
    }
    for (final p in _pedidos) {
      final mV = RegExp(r'VND-(\d+)').firstMatch(p.numero);
      if (mV != null) {
        final n = int.tryParse(mV.group(1)!) ?? 0;
        if (n > localVnd) localVnd = n;
      }
      if (p.numero.startsWith('PED-')) {
        final n = int.tryParse(p.numero.substring(4)) ?? 0;
        if (n > localPed) localPed = n;
      }
    }

    // Supabase
    try {
      if (SupabaseService.isAvailable && empresaId.isNotEmpty) {
        final client = SupabaseService.instance.client;

        // VND nas vendas_balcao
        final resVnd = await client
            .from('vendas_balcao')
            .select('numero')
            .eq('empresa_id', empresaId)
            .order('numero', ascending: false)
            .limit(500)
            .timeout(const Duration(seconds: 10));
        for (final row in resVnd) {
          final numero = row['numero']?.toString() ?? '';
          final m = RegExp(r'VND-(\d+)').firstMatch(numero);
          if (m != null) {
            final n = int.tryParse(m.group(1)!) ?? 0;
            if (n > supabaseVnd) supabaseVnd = n;
          }
        }

        // VND/PED nos pedidos
        final resPed = await client
            .from('pedidos')
            .select('numero')
            .eq('empresa_id', empresaId)
            .order('numero', ascending: false)
            .limit(500)
            .timeout(const Duration(seconds: 10));
        for (final row in resPed) {
          final numero = row['numero']?.toString() ?? '';
          final mV = RegExp(r'VND-(\d+)').firstMatch(numero);
          if (mV != null) {
            final n = int.tryParse(mV.group(1)!) ?? 0;
            if (n > supabaseVnd) supabaseVnd = n;
          }
          if (numero.startsWith('PED-')) {
            final n = int.tryParse(numero.substring(4)) ?? 0;
            if (n > supabasePed) supabasePed = n;
          }
        }
      }
    } catch (e) {
      debugPrint(
        '>>> [DataService] Erro ao consultar Supabase para diagnóstico: $e',
      );
    }

    return {
      'localVnd': localVnd,
      'localPed': localPed,
      'supabaseVnd': supabaseVnd,
      'supabasePed': supabasePed,
    };
  }

  /// Sincroniza a numeração local com o Supabase:
  /// Salva em exodo_config os maiores números encontrados na nuvem,
  /// garantindo que as próximas vendas/pedidos não duplicam números já existentes.
  Future<Map<String, dynamic>> sincronizarNumeracaoComSupabase(
    String empresaId,
  ) async {
    try {
      final diag = await diagnosticarNumeracao(empresaId);
      final supabaseVnd = diag['supabaseVnd']!;
      final supabasePed = diag['supabasePed']!;
      final localVnd = diag['localVnd']!;
      final localPed = diag['localPed']!;

      final db = DatabaseService();

      // Salva o máximo entre local e Supabase como mínimo garantido
      final novoMinVnd = supabaseVnd > localVnd ? supabaseVnd : localVnd;
      final novoMinPed = supabasePed > localPed ? supabasePed : localPed;

      // Grava SEMPRE por empresa: `exodo_config` é uma tabela única do banco
      // local (não tem empresa_id), então a chave precisa carregar o id.
      final chaveVnd = _chaveMinNumeracao('venda', empresaId);
      final chavePed = _chaveMinNumeracao('pedido', empresaId);
      if (chaveVnd != null && chavePed != null) {
        await db.salvarConfig(chaveVnd, novoMinVnd.toString());
        await db.salvarConfig(chavePed, novoMinPed.toString());
      }

      // Atualiza em memória APENAS se ainda for a empresa atual
      if (empresaId == _currentEmpresaId) {
        _minNumeroVenda = novoMinVnd.toString();
        _minNumeroPedido = novoMinPed.toString();
      }

      debugPrint(
        '>>> [DataService] ✅ Numeração sincronizada: VND=$novoMinVnd PED=$novoMinPed',
      );

      return {
        'sucesso': true,
        'localVnd': localVnd,
        'localPed': localPed,
        'supabaseVnd': supabaseVnd,
        'supabasePed': supabasePed,
        'novoMinVnd': novoMinVnd,
        'novoMinPed': novoMinPed,
      };
    } catch (e) {
      debugPrint('>>> [DataService] ❌ Erro ao sincronizar numeração: $e');
      return {'sucesso': false, 'erro': e.toString()};
    }
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

    // E na série própria de serviços realizados (SRV-0001, SRV-0002, ...)
    for (final servico in _servicosRealizados) {
      final match = RegExp(r'SRV-(\d+)').firstMatch(servico.numero);
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

    // Trava por piso persistido: se outro PC (ou esta máquina em sessão anterior)
    // já emitiu SRV-0100, a série NUNCA volta para 0001 mesmo com a lista em
    // memória vazia/ainda não carregada.
    final pisoServico = int.tryParse(_minNumeroServico ?? '0') ?? 0;
    if (pisoServico >= proximoNumero) proximoNumero = pisoServico + 1;

    // Garantir que o número não existe (proteção extra)
    while (numerosExistentes.contains(proximoNumero)) {
      proximoNumero++;
    }

    _elevarPisoEmMemoria('SRV-$proximoNumero');
    return 'SRV-${proximoNumero.toString().padLeft(4, '0')}';
  }

  /// Próximo número da série de ORÇAMENTOS (ORC-0001, ORC-0002, ...).
  String getProximoNumeroOrcamento() {
    final Set<int> numerosExistentes = {};

    for (final orcamento in _orcamentos) {
      final match = RegExp(r'ORC-(\d+)').firstMatch(orcamento.numero);
      if (match != null) {
        numerosExistentes.add(int.tryParse(match.group(1)!) ?? 0);
      }
    }

    int proximoNumero = 1;
    if (numerosExistentes.isNotEmpty) {
      proximoNumero = numerosExistentes.reduce((a, b) => a > b ? a : b) + 1;
    }
    // Trava por piso persistido (mesma regra do SRV-).
    final pisoOrcamento = int.tryParse(_minNumeroOrcamento ?? '0') ?? 0;
    if (pisoOrcamento >= proximoNumero) proximoNumero = pisoOrcamento + 1;
    while (numerosExistentes.contains(proximoNumero)) {
      proximoNumero++;
    }

    _elevarPisoEmMemoria('ORC-$proximoNumero');
    return 'ORC-${proximoNumero.toString().padLeft(4, '0')}';
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

    // Trava por piso persistido (mesma regra do SRV-).
    final pisoAgendamento = int.tryParse(_minNumeroAgendamento ?? '0') ?? 0;
    if (pisoAgendamento >= proximoNumero) proximoNumero = pisoAgendamento + 1;

    while (numerosExistentes.contains(proximoNumero)) {
      proximoNumero++;
    }

    _elevarPisoEmMemoria('AGD-$proximoNumero');
    return 'AGD-${proximoNumero.toString().padLeft(4, '0')}';
  }

  /// MENOR número DISPONÍVEL de NFC-e para a série informada.
  ///
  /// A numeração é POR SÉRIE: cada série da empresa tem sua própria sequência,
  /// começando no número inicial configurado no usuário (numeroInicialNfce,
  /// padrão 1). Assim, se o usuário usa a série 2 com número inicial 5, a
  /// primeira nota será a 5 e as seguintes 6, 7, 8... sem interferir na série 1.
  ///
  /// O número entregue é o MENOR que ainda não foi usado — e não "o maior + 1".
  /// A diferença aparece quando a sequência ganha um buraco: um contador
  /// envenenado (ex.: 791252835, número sorteado pelo fallback de timestamp do
  /// bridge) criava um salto e TODA venda seguinte continuava a partir dele.
  /// Com o menor livre, a numeração volta para a sequência normal; o número
  /// pulado fica queimado (nunca é reusado, porque segue contando como usado —
  /// reusar um número já transmitido é rejeição 539 de duplicidade na SEFAZ).
  int getProximoNumeroNfce({String serie = '1', int numeroInicial = 1}) {
    final serieNorm = serie.trim().isEmpty ? '1' : serie.trim();
    final Set<int> numerosExistentes = {};

    // 1. Verificar na lista de NFC-es sincronizadas (Supabase) da MESMA série.
    //    Contam como "número já usado" as autorizadas/sucesso/canceladas E as
    //    PENDENTES: uma nota rejeitada fica salva como 'pendente' aguardando
    //    reenvio com o MESMO número, então ela não pode ser reaproveitada por
    //    uma venda seguinte (senão as duas colidiriam na SEFAZ).
    //    'inutilizada' (número queimado no NFeInutilizacao4) e 'substituida'
    //    (nota pendente corrigida e reemitida com outro número) também ficam
    //    fora da sequência: reutilizar esses números geraria rejeição 539.
    for (final nfce in _nfces) {
      if (nfce.numero != null &&
          (nfce.status == 'autorizada' ||
              nfce.status == 'sucesso' ||
              nfce.status == 'cancelada' ||
              nfce.status == 'pendente' ||
              nfce.status == 'inutilizada' ||
              nfce.status == 'substituida')) {
        // Série da nota: NFC-e antigas podem não ter série — trata como '1'
        final serieNfce = (nfce.serie ?? '').trim().isEmpty
            ? '1'
            : nfce.serie!.trim();
        if (serieNfce != serieNorm) continue;
        final numInt = int.tryParse(nfce.numero!);
        if (numInt != null) {
          numerosExistentes.add(numInt);
        }
      }
    }

    // 2. Contador da empresa ('ultimo_numero_nfce', só série 1).
    //    Ele existe para a empresa que veio de outro sistema com a numeração já
    //    avançada. Só vale como piso quando NÃO há nenhuma nota guardada: com
    //    notas na mão, quem manda é a própria lista — é isso que impede um
    //    contador inflado (791252835) de puxar a próxima venda para lá.
    int? contadorEmpresa;
    if (serieNorm == '1' && empresaAtual?.configuracoes != null) {
      contadorEmpresa = int.tryParse(
        empresaAtual!.configuracoes!['ultimo_numero_nfce']?.toString() ?? '',
      );
    }

    // 3. Menor livre a partir do piso.
    return menorNumeroLivreNfce(
      numerosUsados: numerosExistentes,
      numeroInicial: numeroInicial,
      ultimoNumeroDaEmpresa: contadorEmpresa,
    );
  }

  /// Conta pura do menor número livre da série de NFC-e (sem banco, testável).
  ///
  /// [ultimoNumeroDaEmpresa] (contador `ultimo_numero_nfce`) só é usado quando
  /// [numerosUsados] está vazio — empresa recém-migrada, sem nota nenhuma no
  /// app, mas com numeração já avançada no sistema antigo.
  static int menorNumeroLivreNfce({
    required Iterable<int> numerosUsados,
    int numeroInicial = 1,
    int? ultimoNumeroDaEmpresa,
  }) {
    final usados = numerosUsados.toSet();

    var numero = numeroInicial > 0 ? numeroInicial : 1;

    // Nenhuma nota guardada: sem evidência nenhuma da sequência, o contador da
    // empresa é a única pista de onde a numeração está.
    if (usados.isEmpty) {
      if (ultimoNumeroDaEmpresa != null && ultimoNumeroDaEmpresa + 1 > numero) {
        numero = ultimoNumeroDaEmpresa + 1;
      }
      return numero;
    }

    // A sequência começa no primeiro número REGISTRADO — desde que ele não seja
    // um salto fora da janela (número sorteado, ex.: 791252835). Abaixo do
    // primeiro registro não se procura buraco: ali não há evidência nenhuma (o
    // número pode ter saído em outro sistema/PC) e reaproveitar número já
    // transmitido é rejeição 539 de duplicidade na SEFAZ.
    final menorUsado = usados.reduce((a, b) => a < b ? a : b);
    if (menorUsado > numero && menorUsado <= numero + 1000) {
      numero = menorUsado;
    }

    while (usados.contains(numero)) {
      numero++;
    }
    return numero;
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
        print(
          '>>> Migrado agendamento ${agendamento.id} para número $novoNumero',
        );
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
      return v.dataVenda.compareTo(inicio) >= 0 &&
          v.dataVenda.compareTo(fim) <= 0;
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
  Future<void> _carregarDadosDoSupabase({
    bool modoLeve = false,
    bool forcarRecarga = false,
    // Puxada PONTUAL (aviso do Realtime): baixa só estas tabelas. Não avança o
    // watermark do delta — as demais tabelas não foram consultadas, então o
    // próximo ciclo completo continua de onde parou.
    Set<String>? tabelas,
  }) async {
    if (_currentEmpresaId == null) {
      print(
        '>>> ⚠ _carregarDadosDoSupabase: Empresa não definida - não é possível carregar dados do Supabase',
      );
      return;
    }

    if (!nuvemHabilitada) {
      debugPrint(
        '>>> [Sync] ⏸️ Nuvem temporariamente desativada para a empresa $currentEmpresaId. Download bloqueado.',
      );
      addSyncLog(
        '☁️ Nuvem desativada para esta empresa. O sistema continuará em funcionamento local apenas.',
      );
      return;
    }

    // Base local limpa de propósito ("Limpar Local"): enquanto o usuário não
    // mandar "Puxar Nuvem", nenhuma recarga automática (startup, auto-sync,
    // verificação de versão) pode trazer os dados de volta — senão a limpeza
    // fica invisível, como se não tivesse funcionado.
    if (_baseLocalLimpa && !forcarRecarga) {
      debugPrint(
        '>>> [DataService] ⏸️ Recarga automática bloqueada: base local limpa, '
        'aguardando "Puxar Nuvem".',
      );
      return;
    }

    // Na recarga forçada (botão "Puxar da Nuvem") o lock já está segurando
    // `_syncEmAndamento = true` para o auto-sync periódico não entrar no meio;
    // neste caso NÃO podemos abortar aqui.
    if (_syncEmAndamento && !forcarRecarga) {
      debugPrint('>>> [Sync] ⏳ Sincronização já em andamento, aguardando...');
      return;
    }

    // Otimização: Só usar modo leve/silencioso se já fez a carga inicial completa pelo menos 1 vez
    final finalModoLeve = modoLeve || _isModoLeve;
    // isSilentSync: só é verdadeiro se o timer periódico está ativo E já foi feita a primeira carga completa
    // Na recarga forçada (botão "Puxar da Nuvem") nunca usamos modo silencioso:
    // queremos baixar TODAS as tabelas sem pular nada.
    final isSilentSync =
        !forcarRecarga &&
        _primeiraCargaAgendamentosRealizada &&
        _syncTimer != null &&
        _syncTimer!.isActive;

    final isPontual = tabelas != null && tabelas.isNotEmpty;

    var isDeltaSync = _ultimaSincronizacaoSucesso != null;
    var lastSyncBuffer = isDeltaSync
        ? _ultimaSincronizacaoSucesso!
              // Puxada pontual: margem maior (e barata — uma tabela só), para
              // cobrir relógio adiantado no aparelho que recebe o aviso.
              .subtract(Duration(minutes: isPontual ? 10 : 1))
              .toUtc()
        : null;

    // SAFEGUARD: Se o delta sync está habilitado mas a lista local de produtos
    // está vazia (banco reconstruído / desinstalação parcial), forçar full sync.
    // Sem isso, produtos antigos que não foram alterados desde o último sync
    // nunca seriam baixados do Supabase.
    //
    // THROTTLE: só é permitido 1 full sync do catálogo automático a cada 6h.
    // Se as coleções continuam vazias (ex.: empresa sem catálogo na nuvem, ou
    // nuvem devolvendo erro/sem dados), cada pulso de 10s rebaixaria ~13MB —
    // foi isso que estourou a cota de egress do Neon. O "Puxar Nuvem" manual
    // (`forcarRecarga`) e o carregamento inicial continuam livres.
    if (!isPontual &&
        isDeltaSync &&
        (_produtos.isEmpty || _clientes.isEmpty || _pedidos.isEmpty)) {
      final ultimaFull = _ultimaFullSyncCatalogoAutomatico;
      final podeFullSyncAutomatico =
          forcarRecarga ||
          ultimaFull == null ||
          DateTime.now().difference(ultimaFull) >= const Duration(hours: 6);
      if (podeFullSyncAutomatico) {
        _ultimaFullSyncCatalogoAutomatico = DateTime.now();
        debugPrint(
          '>>> [Supabase] ⚠️ Delta sync ativo mas coleção(ões) vazia(s): produtos=${_produtos.length}, clientes=${_clientes.length}, pedidos=${_pedidos.length}. Forçando FULL SYNC...',
        );
        isDeltaSync = false;
        lastSyncBuffer = null;
      } else {
        final faltam =
            const Duration(hours: 6) - DateTime.now().difference(ultimaFull);
        debugPrint(
          '>>> [Supabase] ⏭️ Coleção(ões) vazia(s) mas full sync do catálogo já '
          'rodou há pouco — próximo em ${faltam.inMinutes}min. Mantendo DELTA '
          'para não rebaixar ~13MB a cada pulso.',
        );
      }
    }

    debugPrint(
      '>>> [Supabase] 🔄 Iniciando carga (Modo Leve: $finalModoLeve, SilentSync: $isSilentSync, 1aCarga=${_primeiraCargaAgendamentosRealizada}, DeltaSync: $isDeltaSync, LastSync: $lastSyncBuffer)',
    );
    // Zerado antes de aplicar qualquer coisa: no fim da carga diz se algum dado
    // mudou de verdade (ver `_marcarSujo`).
    _mudouNestaCarga = false;
    _syncEmAndamento = true;
    // Pulso silencioso não anuncia o "Sincronizando...": evita reconstruir a
    // árvore inteira só para piscar o indicador a cada ~10s.
    if (!isSilentSync) notifyListeners();
    addSyncLog("Iniciando sincronização (Delta: $isDeltaSync)...");

    try {
      print('>>> ⚡ ========================================');
      print(
        '>>> ⚡ Carregando dados do Supabase (Modo Leve: $finalModoLeve, Delta: $isDeltaSync)',
      );
      print('>>> ⚡ Empresa: $currentEmpresaId');
      print('>>> ⚡ ========================================');

      final result = await _supabaseService.carregarTudoDoSupabase(
        _currentEmpresaId!,
        lastSync: lastSyncBuffer,
        mesesRetroativos: 24, // Carregar histórico de até 2 anos
        // EGRESS: depois da primeira carga completa, produtos/clientes vêm só
        // com o que mudou desde o último sync (o catálogo inteiro era ~5 MB a
        // cada pulso de 45 s). Se o banco local estiver vazio, `isDeltaSync`
        // já é forçado para false mais acima — aí o catálogo volta completo.
        //
        // `!forcarRecarga`: o botão "Puxar da Nuvem" promete trazer TODAS as
        // tabelas sem pular nada; com delta, o catálogo viria incompleto (só os
        // registros alterados). Na recarga forçada, portanto, delta desligado.
        deltaCatalogo: isDeltaSync && !forcarRecarga,
        tabelas: isPontual ? tabelas : null,
      );

      final Map<String, dynamic> dados = result['data'] as Map<String, dynamic>;
      // Trava ANTI-RESSURREIÇÃO: descarta do snapshot os registros apagados
      // localmente há pouco antes de mesclar (um pull mais antigo, vindo de um
      // PC que ainda não recebeu a deleção, não pode trazê-los de volta).
      _descartarDeletadosRecentes(dados);

      // FALHA TOTAL DA NUVEM: quando o Supabase está indisponível (PGRST002 /
      // 503 / 504) TODAS as tabelas falham e voltam vazias. Sem este teste o
      // fluxo abaixo trataria "tudo vazio" como "nenhum dado novo" e marcaria a
      // sincronização como SUCESSO — avançando o watermark do delta sync e
      // fazendo o cliente pular registros alterados durante a queda.
      if (DataService.falhaTotalDoSupabase(result)) {
        final servidorIndisponivel = result['servidorIndisponivel'] == true;
        final totalTabelas = (result['totalTabelas'] as int?) ?? dados.length;
        final detalhe = servidorIndisponivel
            ? 'Supabase indisponível (PGRST002/503/504).'
            : 'Não foi possível baixar nenhuma das $totalTabelas tabelas.';
        _ultimoErroSync = detalhe;
        if (_currentEmpresaId != null) {
          await _storage.salvar(
            _getEmpresaKey('exodo_ultimo_erro_sync'),
            detalhe,
          );
        }
        debugPrint(
          '>>> [Sync] ⚠️ $detalhe Nenhum dado recebido da nuvem. '
          'Sincronização NÃO marcada como sucesso — watermark preservado.',
        );
        addSyncLog(
          '⚠️ $detalhe Dados locais mantidos; nova tentativa no próximo ciclo.',
        );
        notifyListeners();
        // Não atualiza _ultimaSincronizacaoSucesso nem
        // _primeiraCargaAgendamentosRealizada: a próxima tentativa repetirá a
        // carga em vez de assumir que tudo já foi sincronizado.
        return;
      }

      // Verificar se há dados no Supabase - usando um critério amplo
      // (Inclui TODAS as tabelas baixadas para que a recarga forçada do botão
      // "Puxar da Nuvem" nunca retorne cedo com a base local vazia.)
      final temDados =
          dados['clientes']?.isNotEmpty == true ||
          dados['produtos']?.isNotEmpty == true ||
          dados['pedidos']?.isNotEmpty == true ||
          dados['servicos_realizados']?.isNotEmpty == true ||
          dados['orcamentos']?.isNotEmpty == true ||
          dados['agendamentos_servico']?.isNotEmpty == true ||
          dados['servicos']?.isNotEmpty == true ||
          dados['ordens_servico']?.isNotEmpty == true ||
          dados['funcionarios']?.isNotEmpty == true ||
          dados['taxas_entrega']?.isNotEmpty == true ||
          dados['contas_pagar']?.isNotEmpty == true ||
          dados['comissoes_vendedores']?.isNotEmpty == true ||
          dados['mesas_comandas']?.isNotEmpty == true ||
          dados['romaneios']?.isNotEmpty == true ||
          dados['vendas_balcao']?.isNotEmpty == true ||
          dados['aberturas_caixa']?.isNotEmpty == true ||
          dados['fechamentos_caixa']?.isNotEmpty == true ||
          dados['nfces']?.isNotEmpty == true ||
          dados['nfes']?.isNotEmpty == true ||
          dados['sangrias']?.isNotEmpty == true ||
          dados['suprimentos']?.isNotEmpty == true ||
          dados['entregas']?.isNotEmpty == true ||
          dados['notas_entrada']?.isNotEmpty == true ||
          dados['pedidos_compra']?.isNotEmpty == true ||
          dados['estoque_historico']?.isNotEmpty == true ||
          dados['lotes_produto']?.isNotEmpty == true ||
          dados['links_vendedores']?.isNotEmpty == true ||
          dados['motoristas']?.isNotEmpty == true;

      if (!temDados) {
        debugPrint(
          '>>> [Supabase] Nenhum dado novo/atualizado encontrado. Sincronização delta concluída.',
        );
        // Puxada pontual não mexe no watermark: as outras tabelas não foram
        // consultadas nesta rodada.
        if (!isPontual) {
          _ultimaSincronizacaoSucesso = DateTime.now();
          // Persistir timestamp de sucesso
          if (_currentEmpresaId != null) {
            final keySync = _getEmpresaKey(
              'exodo_ultima_sincronizacao_sucesso',
            );
            await _storage.salvar(
              keySync,
              _ultimaSincronizacaoSucesso!.toIso8601String(),
            );
          }
          _ultimoErroSync = null;
          _primeiraCargaAgendamentosRealizada = true;
        }
        addSyncLog("Concluído: Nenhum dado novo/atualizado encontrado.");
        return;
      }

      // A PARTIR DAQUI os dados são da NUVEM: o `_marcarSujo` das coleções
      // abaixo as classifica como "sujas por carga da nuvem". O flush grava com
      // sync_mode = 'on' e preserva o `updated_at` real do registro (ver
      // `_colecoesSujasDaNuvem`). É o que impede o local de se declarar sempre
      // mais novo e recusar as alterações feitas no site.
      _aplicandoDadosDaNuvem = true;

      // 1. Clientes
      if (dados['clientes'] != null) {
        final novos = _parseListaSegura(
          dados['clientes'] as List,
          Cliente.fromMap,
          nomeColecao: 'Clientes',
        );
        if (novos.isNotEmpty) {
          if (_mesclarSemRemover(_clientes, novos)) {
            _marcarSujo(LocalStorageService.keyClientes);
          }
          print('>>> ✓ ${novos.length} clientes sincronizados do Supabase');
        }
      }

      // 2. Produtos
      if (dados['produtos'] != null &&
          (!isSilentSync || _produtosSubscription == null)) {
        final rawProdutos = dados['produtos'] as List;
        final List<Produto> novos = [];
        int parseErros = 0;
        for (final map in rawProdutos) {
          try {
            novos.add(Produto.fromMap(map as Map<String, dynamic>));
          } catch (e) {
            parseErros++;
            debugPrint(
              '>>> [Sync] ⚠️ Produto com erro de parse ignorado: id=${(map as Map<String, dynamic>)['id']}, nome=${map['nome']}, erro=$e',
            );
          }
        }
        debugPrint(
          '>>> [Supabase] 📦 Produtos baixados: ${rawProdutos.length}, parse OK: ${novos.length}, erros: $parseErros',
        );
        // A consulta já vem filtrada por empresa; a trava aqui é a segunda linha
        // de defesa (RLS/consulta alterada, cache de outra empresa em memória).
        var aceitos = somenteProdutosDaEmpresaAberta(novos, origem: 'nuvem');
        // Trava ANTI-PERDA DE ALTERAÇÃO LOCAL: se o produto tem uma mudança
        // local ainda na fila de envio (ex.: baixa/entrada de estoque que não
        // chegou à nuvem), o snapshot da nuvem é NECESSARIAMENTE mais antigo
        // para ele e não pode sobrescrevê-lo. Sem isto, uma baixa feita aqui
        // era apagada pelo valor da nuvem quando outro PC sincronizava em
        // paralelo (o risco de "baixa perdida" entre 2 caixas). A fila reenvia
        // a versão local; só depois o produto volta a aceitar o valor da nuvem.
        final semPendenciaLocal = <Produto>[];
        var produtosPreservadosLocal = 0;
        for (final p in aceitos) {
          if (_temEnvioLocalPendente(SupabaseService.tableProdutos, p.id)) {
            produtosPreservadosLocal++;
            continue;
          }
          semPendenciaLocal.add(p);
        }
        if (produtosPreservadosLocal > 0) {
          debugPrint(
            '>>> [Sync] 🛡️ $produtosPreservadosLocal produto(s) com alteração '
            'local não enviada preservados do snapshot da nuvem '
            '(evita perda de baixa de estoque).',
          );
        }
        aceitos = semPendenciaLocal;
        // Trava de ESTOQUES: enquanto a coluna nova ainda não existir na nuvem,
        // o produto que chega de lá vem SEM os saldos por estoque. Sem esta
        // proteção, a sincronização apagaria os saldos que existem aqui (o item
        // da nuvem é mais novo e substituiria o local inteiro).
        final comEstoques = <Produto>[];
        for (final p in aceitos) {
          if (p.estoquePorEstoque.isNotEmpty) {
            comEstoques.add(p);
            continue;
          }
          final indexLocal = _produtos.indexWhere((l) => l.id == p.id);
          if (indexLocal == -1 ||
              _produtos[indexLocal].estoquePorEstoque.isEmpty) {
            comEstoques.add(p);
            continue;
          }
          final local = _produtos[indexLocal];
          comEstoques.add(
            p.copyWith(
              estoquePorEstoque: local.estoquePorEstoque,
              estoquePadraoId: local.estoquePadraoId,
            ),
          );
        }
        aceitos = comEstoques;
        if (aceitos.isNotEmpty) {
          if (_mesclarSemRemover(_produtos, aceitos)) {
            _marcarSujo(LocalStorageService.keyProdutos);
          }
          print(
            '>>> ✓ ${aceitos.length} produtos sincronizados do Supabase (${parseErros > 0 ? '$parseErros com erro de parse' : 'sem erros'})',
          );
        }
      }

      // 3. Serviços
      if (dados['servicos'] != null &&
          (!isSilentSync || _servicosSubscription == null)) {
        final novos = _parseListaSegura(
          dados['servicos'] as List,
          Servico.fromMap,
          nomeColecao: 'Serviços',
        );
        if (novos.isNotEmpty) {
          if (_mesclarSemRemover(_tiposServico, novos)) {
            _marcarSujo(LocalStorageService.keyServicos);
          }
          print('>>> ✓ ${novos.length} serviços carregados do Supabase');
        }
      }

      // 4. Pedidos
      if (dados['pedidos'] != null && dados['pedidos'].isNotEmpty) {
        final novosPedidos = _parseListaSegura(
          dados['pedidos'] as List,
          Pedido.fromMap,
          nomeColecao: 'Pedidos',
        );
        bool dirty = false;
        for (final pedido in novosPedidos) {
          final indexLocal = _pedidos.indexWhere((p) => p.id == pedido.id);

          if (indexLocal != -1) {
            final local = _pedidos[indexLocal];
            bool localEhMesa =
                local.numero.contains('MESA') ||
                local.numero.contains('CMD') ||
                local.clienteNome?.contains('[') == true;
            bool SupabaseEhMesa =
                pedido.numero.contains('MESA') ||
                pedido.numero.contains('CMD') ||
                pedido.clienteNome?.contains('[') == true;

            if (localEhMesa && !SupabaseEhMesa) {
              debugPrint(
                '>>> [Sync] 🛡️ Preservando Identidade VIP local do Pedido: ${local.numero}',
              );
              _pedidos[indexLocal] = pedido.copyWith(
                numero: local.numero,
                clienteNome: local.clienteNome,
                observacoes: local.observacoes,
              );
              dirty = true;
              continue;
            }
            // CONFLICT RESOLUTION: a nuvem só substitui o local quando é mais
            // NOVA (regra "a nuvem nunca sobrescreve o local" — empate fica o
            // local). Isso evita que o sync periódico sobrescreva mudanças locais
            // (ex.: cancelamentos feitos aqui).
            if (!_nuvemMaisNovaQueLocal(local, pedido)) {
              debugPrint(
                '>>> [Sync] 🛡️ Preservando versão LOCAL do Pedido ${local.numero} (local: ${local.updatedAt}, supabase: ${pedido.updatedAt})',
              );
              // Não sobrescrever - manter o local. Mas marcar para re-enviar ao Supabase.
              await enviarMudancaParaSupabase(
                SupabaseService.tablePedidos,
                local.toMap(),
              );
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

      // 4.1 Serviços realizados (entidade própria, série SRV)
      if (dados['servicos_realizados'] != null &&
          (dados['servicos_realizados'] as List).isNotEmpty) {
        final novosServicos = _parseListaSegura(
          dados['servicos_realizados'] as List,
          ServicoRealizado.fromMap,
          nomeColecao: 'Serviços Realizados',
        );
        bool dirty = false;
        for (final servico in novosServicos) {
          final indexLocal = _servicosRealizados.indexWhere(
            (s) => s.id == servico.id,
          );
          if (indexLocal != -1) {
            final local = _servicosRealizados[indexLocal];
            // Preserva a versão local quando ela NÃO é mais antiga que a da
            // nuvem (empate também fica local — regra "a nuvem nunca
            // sobrescreve o local"; ex.: recebimento feito aqui e ainda não
            // enviado, ou snapshot velho vindo do espelho).
            if (!_nuvemMaisNovaQueLocal(local, servico)) {
              continue;
            }
            _servicosRealizados[indexLocal] = servico;
            dirty = true;
          } else {
            _servicosRealizados.add(servico);
            dirty = true;
          }
        }
        if (dirty) {
          _marcarSujo(LocalStorageService.keyServicosRealizados);
        }
        print(
          '>>> ✓ ${novosServicos.length} serviços realizados carregados do Supabase',
        );
      }

      // 4.2 Orçamentos de pedido (entidade própria, série ORC)
      if (dados['orcamentos'] != null &&
          (dados['orcamentos'] as List).isNotEmpty) {
        final novosOrcamentos = _parseListaSegura(
          dados['orcamentos'] as List,
          Orcamento.fromMap,
          nomeColecao: 'Orçamentos',
        );
        bool dirty = false;
        for (final orcamento in novosOrcamentos) {
          final indexLocal = _orcamentos.indexWhere(
            (o) => o.id == orcamento.id,
          );
          if (indexLocal != -1) {
            final local = _orcamentos[indexLocal];
            // Empate/nuvem antiga → o local manda (nunca sobrescrever o local).
            if (!_nuvemMaisNovaQueLocal(local, orcamento)) continue;
            _orcamentos[indexLocal] = orcamento;
            dirty = true;
          } else {
            _orcamentos.add(orcamento);
            dirty = true;
          }
        }
        if (dirty) {
          _marcarSujo(LocalStorageService.keyOrcamentos);
        }
        print(
          '>>> ✓ ${novosOrcamentos.length} orçamentos carregados do Supabase',
        );
      }

      // 5. Ordens de Serviço
      if (dados['ordens_servico'] != null &&
          dados['ordens_servico'].isNotEmpty) {
        final novasOrdens = _parseListaSegura(
          dados['ordens_servico'] as List,
          OrdemServico.fromMap,
          nomeColecao: 'Ordens de Serviço',
        );
        for (final ordem in novasOrdens) {
          final index = _ordensServico.indexWhere((o) => o.id == ordem.id);
          if (index >= 0) {
            // REGRA "a nuvem nunca sobrescreve o local": só substitui se a
            // nuvem for mais nova (antes a nuvem vencia SEMPRE nesta tabela).
            if (!_nuvemMaisNovaQueLocal(_ordensServico[index], ordem)) {
              continue;
            }
            _ordensServico[index] = ordem;
          } else {
            _ordensServico.add(ordem);
          }
        }
        _marcarSujo(LocalStorageService.keyOrdensServico);
        print(
          '>>> ✓ ${novasOrdens.length} ordens de serviço carregadas do Supabase',
        );
      }

      // 6. Entregas
      if (dados['entregas'] != null && dados['entregas'].isNotEmpty) {
        final novasEntregas = _parseListaSegura(
          dados['entregas'] as List,
          Entrega.fromMap,
          nomeColecao: 'Entregas',
        );
        for (final entrega in novasEntregas) {
          final index = _entregas.indexWhere((e) => e.id == entrega.id);
          if (index >= 0) {
            // REGRA "a nuvem nunca sobrescreve o local".
            if (!_nuvemMaisNovaQueLocal(_entregas[index], entrega)) {
              continue;
            }
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
        final novosMotoristas = _parseListaSegura(
          dados['motoristas'] as List,
          Motorista.fromMap,
          nomeColecao: 'Motoristas',
        );
        for (final motorista in novosMotoristas) {
          final index = _motoristas.indexWhere((m) => m.id == motorista.id);
          if (index >= 0) {
            // REGRA "a nuvem nunca sobrescreve o local".
            if (!_nuvemMaisNovaQueLocal(_motoristas[index], motorista)) {
              continue;
            }
            _motoristas[index] = motorista;
          } else {
            _motoristas.add(motorista);
          }
        }
        _marcarSujo(LocalStorageService.keyMotoristas);
        print(
          '>>> ✓ ${novosMotoristas.length} motoristas carregados do Supabase',
        );
      }

      // 8. Vendas Balcão
      if (dados['vendas_balcao'] != null && dados['vendas_balcao'].isNotEmpty) {
        final novasVendas = _parseListaSegura(
          dados['vendas_balcao'] as List,
          VendaBalcao.fromMap,
          nomeColecao: 'Vendas Balcão',
        );
        bool dirty = false;
        for (final venda in novasVendas) {
          final indexLocal = _vendasBalcao.indexWhere((v) => v.id == venda.id);

          if (indexLocal != -1) {
            final local = _vendasBalcao[indexLocal];
            bool localEhMesa =
                local.numero.contains('MESA') ||
                local.numero.contains('CMD') ||
                local.clienteNome?.contains('[') == true;
            bool SupabaseEhMesa =
                venda.numero.contains('MESA') ||
                venda.numero.contains('CMD') ||
                venda.clienteNome?.contains('[') == true;

            if (localEhMesa && !SupabaseEhMesa) {
              debugPrint(
                '>>> [Sync] 🛡️ Preservando Identidade VIP local da Venda: ${local.numero}',
              );
              _vendasBalcao[indexLocal] = venda.copyWith(
                numero: local.numero,
                clienteNome: local.clienteNome,
                observacoes: local.observacoes,
              );
              dirty = true;
              continue;
            }
            // REGRA "a nuvem nunca sobrescreve o local": venda local igual ou
            // mais nova fica intocada (antes a nuvem vencia sempre aqui).
            if (!_nuvemMaisNovaQueLocal(local, venda)) {
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
        print(
          '>>> ✓ ${novasVendas.length} vendas balcão carregadas do Supabase',
        );
      }

      // 9. Trocas/Devoluções
      if (dados['trocas_devolucoes'] != null &&
          dados['trocas_devolucoes'].isNotEmpty) {
        final novasTrocas = _parseListaSegura(
          dados['trocas_devolucoes'] as List,
          TrocaDevolucao.fromMap,
          nomeColecao: 'Trocas/Devoluções',
        ).where(_isTrocaDevolucaoValida).toList();
        for (final troca in novasTrocas) {
          final index = _trocasDevolucoes.indexWhere((t) => t.id == troca.id);
          if (index >= 0) {
            // REGRA "a nuvem nunca sobrescreve o local".
            if (!_nuvemMaisNovaQueLocal(_trocasDevolucoes[index], troca)) {
              continue;
            }
            _trocasDevolucoes[index] = troca;
          } else {
            _trocasDevolucoes.add(troca);
          }
        }
        _marcarSujo(LocalStorageService.keyTrocasDevolucoes);
        print(
          '>>> ✓ ${novasTrocas.length} trocas/devoluções carregadas do Supabase',
        );
      }

      // 10. Histórico de Estoque
      if (dados['estoque_historico'] != null &&
          dados['estoque_historico'].isNotEmpty) {
        final novosRegistros = _parseListaSegura(
          dados['estoque_historico'] as List,
          EstoqueHistorico.fromMap,
          nomeColecao: 'Estoque Histórico',
        );
        for (final registro in novosRegistros) {
          final index = _estoqueHistorico.indexWhere(
            (e) => e.id == registro.id,
          );
          if (index >= 0) {
            // REGRA "a nuvem nunca sobrescreve o local".
            if (!_nuvemMaisNovaQueLocal(_estoqueHistorico[index], registro)) {
              continue;
            }
            _estoqueHistorico[index] = registro;
          } else {
            _estoqueHistorico.add(registro);
          }
        }
        _marcarSujo(LocalStorageService.keyEstoqueHistorico);
        print(
          '>>> ✓ ${novosRegistros.length} registros de estoque carregados do Supabase',
        );
      }

      // 10a. Lotes de ajuste em massa (auditoria/desfazer)
      if (dados['ajustes_estoque_lote'] != null &&
          dados['ajustes_estoque_lote'].isNotEmpty) {
        final novosLotes = _parseListaSegura(
          dados['ajustes_estoque_lote'] as List,
          AjusteEstoqueLote.fromMap,
          nomeColecao: 'Ajustes de Estoque em Massa',
        );
        for (final lote in novosLotes) {
          final index = _ajustesEstoqueLote.indexWhere((l) => l.id == lote.id);
          if (index >= 0) {
            // REGRA "a nuvem nunca sobrescreve o local".
            if (!_nuvemMaisNovaQueLocal(_ajustesEstoqueLote[index], lote)) {
              continue;
            }
            _ajustesEstoqueLote[index] = lote;
          } else {
            _ajustesEstoqueLote.add(lote);
          }
        }
        _ajustesEstoqueLote.sort((a, b) => b.data.compareTo(a.data));
        _marcarSujo(LocalStorageService.keyAjustesEstoqueLote);
        print(
          '>>> ✓ ${novosLotes.length} lote(s) de ajuste carregados do Supabase',
        );
      }

      // 10a.1 Pedidos de compra (pedidos feitos ao fornecedor e ainda não
      // recebidos). São documentos da empresa: mesclam por id e nunca deixam
      // uma versão mais antiga da nuvem sobrescrever o recebimento local.
      if (dados['pedidos_compra'] != null &&
          (dados['pedidos_compra'] as List).isNotEmpty) {
        final novosPedidos = _parseListaSegura(
          dados['pedidos_compra'] as List,
          PedidoCompra.fromMap,
          nomeColecao: 'Pedidos de Compra',
        );
        for (final pedido in novosPedidos) {
          final index = _pedidosCompra.indexWhere((p) => p.id == pedido.id);
          if (index >= 0) {
            if (!_nuvemMaisNovaQueLocal(_pedidosCompra[index], pedido)) {
              continue;
            }
            _pedidosCompra[index] = pedido;
          } else {
            _pedidosCompra.add(pedido);
          }
        }
        _marcarSujo(LocalStorageService.keyPedidosCompra);
        print(
          '>>> ✓ ${novosPedidos.length} pedido(s) de compra carregados do Supabase',
        );
      }

      // 10b. Lotes de Produtos (validade/lote)
      if (dados['lotes_produto'] != null && dados['lotes_produto'].isNotEmpty) {
        final novosLotes = _parseListaSegura(
          dados['lotes_produto'] as List,
          LoteProduto.fromMap,
          nomeColecao: 'Lotes de Produto',
        );
        for (final lote in novosLotes) {
          final index = _lotesProdutos.indexWhere((l) => l.id == lote.id);
          if (index >= 0) {
            // REGRA "a nuvem nunca sobrescreve o local".
            if (!_nuvemMaisNovaQueLocal(_lotesProdutos[index], lote)) {
              continue;
            }
            _lotesProdutos[index] = lote;
          } else {
            _lotesProdutos.add(lote);
          }
        }
        _marcarSujo(LocalStorageService.keyLotesProdutos);
        print(
          '>>> ✓ ${novosLotes.length} lotes de produtos carregados do Supabase',
        );
      }

      // 11. Aberturas de Caixa
      if (dados['aberturas_caixa'] != null &&
          dados['aberturas_caixa'].isNotEmpty) {
        final novasAberturas = _parseListaSegura(
          dados['aberturas_caixa'] as List,
          AberturaCaixa.fromMap,
          nomeColecao: 'Aberturas de Caixa',
        );
        for (final abertura in novasAberturas) {
          final index = _aberturasCaixa.indexWhere((a) => a.id == abertura.id);
          if (index >= 0) {
            // REGRA "a nuvem nunca sobrescreve o local".
            if (!_nuvemMaisNovaQueLocal(_aberturasCaixa[index], abertura)) {
              continue;
            }
            _aberturasCaixa[index] = abertura;
          } else {
            _aberturasCaixa.add(abertura);
          }
        }
        _aberturasCaixa.sort(
          (a, b) => a.dataAbertura.compareTo(b.dataAbertura),
        );
        _marcarSujo(LocalStorageService.keyAberturasCaixa);
        // Recalcular o status do caixa após sincronizar aberturas da nuvem
        _caixaAberto = aberturaCaixaAtual != null;
        print(
          '>>> ✓ ${novasAberturas.length} aberturas de caixa carregadas do Supabase',
        );
      }

      // 12. Fechamentos de Caixa
      if (dados['fechamentos_caixa'] != null &&
          dados['fechamentos_caixa'].isNotEmpty) {
        final novosFechamentos = _parseListaSegura(
          dados['fechamentos_caixa'] as List,
          FechamentoCaixa.fromMap,
          nomeColecao: 'Fechamentos de Caixa',
        );
        for (final fechamento in novosFechamentos) {
          final index = _fechamentosCaixa.indexWhere(
            (f) => f.id == fechamento.id,
          );
          if (index >= 0) {
            // REGRA "a nuvem nunca sobrescreve o local".
            if (!_nuvemMaisNovaQueLocal(_fechamentosCaixa[index], fechamento)) {
              continue;
            }
            _fechamentosCaixa[index] = fechamento;
          } else {
            _fechamentosCaixa.add(fechamento);
          }
        }
        _fechamentosCaixa.sort(
          (a, b) => a.dataFechamento.compareTo(b.dataFechamento),
        );
        _marcarSujo(LocalStorageService.keyFechamentosCaixa);
        print(
          '>>> ✓ ${novosFechamentos.length} fechamentos de caixa carregadas do Supabase',
        );
      }

      // 13. Mesas/Comandas
      if (dados['mesas_comandas'] != null &&
          dados['mesas_comandas'].isNotEmpty) {
        final novasMesasRaw = _parseListaSegura(
          dados['mesas_comandas'] as List,
          MesaComanda.fromMap,
          nomeColecao: 'Mesas/Comandas',
        ).where((m) => !_idsMesaRemovidosRecentemente.contains(m.id)).toList();
        _mesclarMesasComandas(novasMesasRaw, isDelta: isDeltaSync);
        _marcarSujo(LocalStorageService.keyMesasComandas);
        print(
          '>>> ✓ ${novasMesasRaw.length} mesas/comandas carregadas do Supabase',
        );
      }

      // 14. Romaneios
      if (dados['romaneios'] != null && dados['romaneios'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['romaneios'] as List,
          Romaneio.fromMap,
          nomeColecao: 'Romaneios',
        );
        for (final item in novos) {
          // REGRA "a nuvem nunca sobrescreve o local".
          final indexLocal = _romaneios.indexWhere((r) => r.id == item.id);
          if (indexLocal >= 0 &&
              !_nuvemMaisNovaQueLocal(_romaneios[indexLocal], item)) {
            continue;
          }
          _romaneios.removeWhere((r) => r.id == item.id);
          _romaneios.add(item);
        }
        _marcarSujo(LocalStorageService.keyRomaneios);
        print('>>> ✓ ${novos.length} romaneios carregados do Supabase');
      }

      // 15. Funcionários
      if (dados['funcionarios'] != null && dados['funcionarios'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['funcionarios'] as List,
          Funcionario.fromMap,
          nomeColecao: 'Funcionários',
        );
        if (_mesclarSemRemover(_funcionarios, novos)) {
          _marcarSujo(LocalStorageService.keyFuncionarios);
        }
        print('>>> ✓ ${novos.length} funcionários carregados do Supabase');
      }

      // 16. Taxas de Entrega
      if (dados['taxas_entrega'] != null && dados['taxas_entrega'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['taxas_entrega'] as List,
          TaxaEntrega.fromMap,
          nomeColecao: 'Taxas de Entrega',
        );
        if (_mesclarSemRemover(_taxasEntrega, novos)) {
          _marcarSujo(LocalStorageService.keyTaxasEntrega);
        }
      }

      // 17. Contas a Pagar
      if (dados['contas_pagar'] != null && dados['contas_pagar'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['contas_pagar'] as List,
          ContaPagar.fromMap,
          nomeColecao: 'Contas a Pagar',
        );
        if (_mesclarSemRemover(_contasPagar, novos)) {
          _marcarSujo(LocalStorageService.keyContasPagar);
        }
      }

      // 18. NFC-es e NF-es
      if (dados['nfces'] != null && dados['nfces'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['nfces'] as List,
          NFCe.fromMap,
          nomeColecao: 'NFC-es',
        );
        if (_mesclarSemRemover(_nfces, novos)) {
          _marcarSujo(LocalStorageService.keyNFCes);
        }
      }
      if (dados['nfes'] != null && dados['nfes'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['nfes'] as List,
          NFCe.fromMap,
          nomeColecao: 'NF-es',
        );
        if (_mesclarSemRemover(_nfes, novos)) {
          _marcarSujo(LocalStorageService.keyNFEs);
        }
      }

      // 19. Sangrias
      if (dados['sangrias'] != null && dados['sangrias'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['sangrias'] as List,
          SangriaCaixa.fromMap,
          nomeColecao: 'Sangrias',
        );
        if (_mesclarSemRemover(_sangrias, novos)) {
          _marcarSujo(LocalStorageService.keySangriasField);
        }
      }

      // 20. Suprimentos
      if (dados['suprimentos'] != null && dados['suprimentos'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['suprimentos'] as List,
          SuprimentoCaixa.fromMap,
          nomeColecao: 'Suprimentos',
        );
        if (_mesclarSemRemover(_suprimentos, novos)) {
          _marcarSujo(LocalStorageService.keySuprimentosField);
        }
      }

      // 21. Links de Vendedores
      if (dados['links_vendedores'] != null &&
          dados['links_vendedores'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['links_vendedores'] as List,
          LinkVendedor.fromMap,
          nomeColecao: 'Links de Vendedores',
        );
        if (_mesclarSemRemover(_linksVendedores, novos)) {
          _marcarSujo(LocalStorageService.keyLinksVendedores);
        }
      }

      // 22. Comissões de Vendedores
      if (dados['comissoes_vendedores'] != null &&
          dados['comissoes_vendedores'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['comissoes_vendedores'] as List,
          ComissaoVendedor.fromMap,
          nomeColecao: 'Comissões de Vendedores',
        );
        if (_mesclarSemRemover(_comissoesVendedores, novos)) {
          _marcarSujo(LocalStorageService.keyComissoesVendedores);
        }
      }

      // 22b. Movimentos de Cash Back (extrato de fidelidade)
      if (dados['cash_back_movimentos'] != null &&
          dados['cash_back_movimentos'].isNotEmpty) {
        final novos = _parseListaSegura(
          dados['cash_back_movimentos'] as List,
          CashBackMovimento.fromMap,
          nomeColecao: 'Movimentos de Cash Back',
        );
        if (_mesclarSemRemover(_movimentosCashBack, novos)) {
          _marcarSujo(LocalStorageService.keyCashBackMovimentos);
        }
      }

      // 23. Agendamentos
      final agendamentosNoSupabase = dados['agendamentos_servico'] as List?;
      if (agendamentosNoSupabase != null && agendamentosNoSupabase.isNotEmpty) {
        if (!isSilentSync || _agendamentosSubscription == null) {
          final novosAgendamentos = _parseListaSegura(
            agendamentosNoSupabase,
            AgendamentoServico.fromMap,
            nomeColecao: 'Agendamentos',
          ).map((a) => _vincularReferenciasAgendamento(a)).toList();

          for (final agendamento in novosAgendamentos) {
            // REGRA "a nuvem nunca sobrescreve o local".
            final indexLocal = _agendamentosServico.indexWhere(
              (a) => a.id == agendamento.id,
            );
            if (indexLocal >= 0 &&
                !_nuvemMaisNovaQueLocal(
                  _agendamentosServico[indexLocal],
                  agendamento,
                )) {
              continue;
            }
            _upsertAgendamentoLocal(agendamento);
          }
          _marcarSujo(LocalStorageService.keyAgendamentosServico);
          print(
            '>>> ✓ ${novosAgendamentos.length} agendamentos processados com sucesso',
          );
        }
      }

      // Fim da aplicação dos dados da nuvem: voltou a valer a marcação normal.
      _aplicandoDadosDaNuvem = false;

      if (!isPontual) {
        _ultimaSincronizacaoSucesso = DateTime.now();

        // Persistir timestamp de sucesso
        if (_currentEmpresaId != null) {
          final keySync = _getEmpresaKey('exodo_ultima_sincronizacao_sucesso');
          await _storage.salvar(
            keySync,
            _ultimaSincronizacaoSucesso!.toIso8601String(),
          );
          await _storage.remover(_getEmpresaKey('exodo_ultimo_erro_sync'));
        }

        _ultimoErroSync = null;
        _primeiraCargaAgendamentosRealizada = true;
      }
      debugPrint(
        '>>> [Sync] ✅ Sincronização concluída com sucesso às ${DateTime.now().toIso8601String()}'
        '${isPontual ? ' (pontual: ${tabelas!.join(', ')})' : ''}',
      );

      final List<String> summary = [];
      if (dados['clientes'] != null && (dados['clientes'] as List).isNotEmpty)
        summary.add('${(dados['clientes'] as List).length} clientes');
      if (dados['produtos'] != null && (dados['produtos'] as List).isNotEmpty)
        summary.add('${(dados['produtos'] as List).length} produtos');
      if (dados['servicos'] != null && (dados['servicos'] as List).isNotEmpty)
        summary.add('${(dados['servicos'] as List).length} serviços');
      if (dados['servicos_realizados'] != null &&
          (dados['servicos_realizados'] as List).isNotEmpty)
        summary.add(
          '${(dados['servicos_realizados'] as List).length} serviços realizados',
        );
      if (dados['orcamentos'] != null &&
          (dados['orcamentos'] as List).isNotEmpty)
        summary.add('${(dados['orcamentos'] as List).length} orçamentos');
      if (dados['pedidos'] != null && (dados['pedidos'] as List).isNotEmpty)
        summary.add('${(dados['pedidos'] as List).length} pedidos');
      if (dados['ordens_servico'] != null &&
          (dados['ordens_servico'] as List).isNotEmpty)
        summary.add('${(dados['ordens_servico'] as List).length} ordens serv.');
      if (dados['entregas'] != null && (dados['entregas'] as List).isNotEmpty)
        summary.add('${(dados['entregas'] as List).length} entregas');
      if (dados['notas_entrada'] != null &&
          (dados['notas_entrada'] as List).isNotEmpty)
        summary.add('${(dados['notas_entrada'] as List).length} notas');
      if (dados['vendas'] != null && (dados['vendas'] as List).isNotEmpty)
        summary.add('${(dados['vendas'] as List).length} vendas');
      if (dados['trocas_devolucoes'] != null &&
          (dados['trocas_devolucoes'] as List).isNotEmpty)
        summary.add('${(dados['trocas_devolucoes'] as List).length} trocas');
      if (dados['estoque_historico'] != null &&
          (dados['estoque_historico'] as List).isNotEmpty)
        summary.add(
          '${(dados['estoque_historico'] as List).length} reg. estoque',
        );
      if (dados['aberturas_caixa'] != null &&
          (dados['aberturas_caixa'] as List).isNotEmpty)
        summary.add(
          '${(dados['aberturas_caixa'] as List).length} aberturas caixa',
        );
      if (dados['fechamentos_caixa'] != null &&
          (dados['fechamentos_caixa'] as List).isNotEmpty)
        summary.add(
          '${(dados['fechamentos_caixa'] as List).length} fechamentos caixa',
        );
      if (dados['mesas_comandas'] != null &&
          (dados['mesas_comandas'] as List).isNotEmpty)
        summary.add('${(dados['mesas_comandas'] as List).length} mesas');
      if (dados['romaneios'] != null && (dados['romaneios'] as List).isNotEmpty)
        summary.add('${(dados['romaneios'] as List).length} romaneios');
      if (dados['funcionarios'] != null &&
          (dados['funcionarios'] as List).isNotEmpty)
        summary.add('${(dados['funcionarios'] as List).length} funcionários');
      if (dados['taxas_entrega'] != null &&
          (dados['taxas_entrega'] as List).isNotEmpty)
        summary.add('${(dados['taxas_entrega'] as List).length} taxas ent.');
      if (dados['contas_pagar'] != null &&
          (dados['contas_pagar'] as List).isNotEmpty)
        summary.add('${(dados['contas_pagar'] as List).length} contas pagar');
      if (dados['nfces'] != null && (dados['nfces'] as List).isNotEmpty)
        summary.add('${(dados['nfces'] as List).length} NFC-es');
      if (dados['sangrias'] != null && (dados['sangrias'] as List).isNotEmpty)
        summary.add('${(dados['sangrias'] as List).length} sangrias');
      if (dados['suprimentos'] != null &&
          (dados['suprimentos'] as List).isNotEmpty)
        summary.add('${(dados['suprimentos'] as List).length} suprimentos');
      if (dados['links_vendedores'] != null &&
          (dados['links_vendedores'] as List).isNotEmpty)
        summary.add('${(dados['links_vendedores'] as List).length} links');
      if (dados['comissoes_vendedores'] != null &&
          (dados['comissoes_vendedores'] as List).isNotEmpty)
        summary.add(
          '${(dados['comissoes_vendedores'] as List).length} comissões',
        );
      if (dados['cash_back_movimentos'] != null &&
          (dados['cash_back_movimentos'] as List).isNotEmpty)
        summary.add(
          '${(dados['cash_back_movimentos'] as List).length} cash back',
        );
      if (dados['agendamentos_servico'] != null &&
          (dados['agendamentos_servico'] as List).isNotEmpty)
        summary.add(
          '${(dados['agendamentos_servico'] as List).length} agendamentos',
        );

      if (summary.isNotEmpty) {
        addSyncLog("✅ Recebido da nuvem: ${summary.join(', ')}.");
      } else {
        addSyncLog("✅ Sincronização concluída com sucesso.");
      }

      // Tarefas de fechamento do ciclo COMPLETO. Numa puxada pontual (aviso do
      // Realtime, uma tabela) elas só custariam tempo — o Drive chega a tentar
      // login silencioso — e não têm o que fazer com o snapshot parcial.
      if (!isPontual) {
        _sincronizarNotasComDrive();

        // A nuvem pode trazer de volta rascunhos `pend-` antigos (criados antes
        // do DELETE local existir). Sem isso, a nota autorizada volta a aparecer
        // como "Pendente" depois de cada sincronização.
        await _limparRascunhosPendentesOrfaos();

        // Serviços antigos (lançados como pedido) trazidos da nuvem também
        // viram Serviço Realizado.
        await _migrarServicosRealizadosDePedidos();

        // Números SRV-/ORC-/AGD- que só existem na nuvem também travam os pisos
        // locais: sem isso, duas máquinas podiam emitir o mesmo número.
        unawaited(_elevarEPersistirPisosSerie());
      }
    } catch (e, stackTrace) {
      _ultimoErroSync = e.toString();
      if (_currentEmpresaId != null) {
        _storage.salvar(
          _getEmpresaKey('exodo_ultimo_erro_sync'),
          _ultimoErroSync,
        );
      }
      debugPrint('>>> [Sync] ❌ ERRO na sincronização: $e');
      addSyncLog("❌ ERRO na sincronização: $e");
      debugPrint('>>> StackTrace: $stackTrace');
      rethrow;
    } finally {
      _aplicandoDadosDaNuvem = false;
      _syncEmAndamento = false;
      // Notifica se a carga não é silenciosa (precisa apagar o indicador) ou se
      // algum dado mudou. Numa carga silenciosa SEM novidade nenhuma não
      // notifica: era isso que reconstruía toda a árvore sob
      // `Consumer<DataService>` a cada pulso do auto-sync.
      if (!isSilentSync || _mudouNestaCarga) {
        notifyListeners();
      } else {
        debugPrint(
          '>>> [Sync] 💤 Carga silenciosa sem novidades: UI preservada.',
        );
      }
    }
  }

  /// Lê UMA coleção do cache local de forma TOLERANTE.
  ///
  /// Regras que faltavam e faziam o fluxo de caixa sumir sem internet:
  ///  * um registro corrompido não pode derrubar a leitura inteira (antes o
  ///    `.map(FromMap)` lançava e o `catch` geral abortava TODA a carga);
  ///  * a memória só é substituída quando o banco devolveu dados — leitura
  ///    vazia/falha nunca apaga o que já está em memória.
  Future<void> _carregarColecaoLocalTolerante<T>(
    String chaveBase,
    T Function(Map<String, dynamic>) fromMap,
    List<T> destino, {
    DateTime Function(T item)? ordenarPor,
  }) async {
    try {
      final mapa = await _storage.carregarLista(_getEmpresaKey(chaveBase));
      if (mapa.isEmpty) return;

      final itens = <T>[];
      for (final registro in mapa) {
        try {
          itens.add(fromMap(registro));
        } catch (e) {
          debugPrint(
            '>>> [Cache local] ⚠️ Registro ignorado em $chaveBase '
            '(id=${registro['id']}): $e',
          );
        }
      }
      if (itens.isEmpty) return;

      destino.clear();
      destino.addAll(itens);
      if (ordenarPor != null) {
        try {
          destino.sort((a, b) => ordenarPor(a).compareTo(ordenarPor(b)));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('>>> [Cache local] ❌ Falha ao ler $chaveBase: $e');
    }
  }

  /// Aplica à memória uma coleção JÁ LIDA do cache local, tolerando registros
  /// ruins.
  ///
  /// É o par síncrono de [_carregarColecaoLocalTolerante]: recebe o mapa pronto
  /// (evita reler o banco) e roda em [_carregarDadosSalvos], onde antes um
  /// único registro corrompido fazia o `.map(FromMap)` lançar e o `catch` geral
  /// abortar TODAS as coleções seguintes — o fluxo de caixa, o estoque e os
  /// vínculos sumiam da memória sem internet.
  void _aplicarColecaoTolerante<T>(
    String chaveBase,
    List<Map<String, dynamic>> mapa,
    T Function(Map<String, dynamic>) fromMap,
    List<T> destino, {
    bool Function(T item)? filtro,
    DateTime Function(T item)? ordenarPor,
    bool ordenarDescendente = false,
  }) {
    if (mapa.isEmpty) return;

    final itens = <T>[];
    for (final registro in mapa) {
      // Trava de empresa na ENTRADA: se o registro veio carimbado com outra
      // empresa (cache antigo sem prefixo, backup, snapshot da web), ele não
      // entra na memória da empresa aberta. Modelos sem `empresaId` dependem
      // só desta checagem, por isso ela fica aqui (vale para todas as listas).
      // Lê as DUAS grafias: o banco local devolve `empresaId` (camelCase) e
      // checar só `empresa_id` deixava a trava cega em parte das origens.
      final empresaDoRegistro =
          (registro['empresa_id'] ?? registro['empresaId'])?.toString();
      if (empresaDoRegistro != null &&
          empresaDoRegistro.isNotEmpty &&
          empresaDoRegistro != _currentEmpresaId) {
        continue;
      }
      try {
        final item = fromMap(registro);
        if (filtro == null || filtro(item)) itens.add(item);
      } catch (e) {
        debugPrint(
          '>>> [Cache local] ⚠️ Registro ignorado em $chaveBase '
          '(id=${registro['id']}): $e',
        );
      }
    }
    // Leitura toda ruim NÃO apaga o que já está em memória.
    if (itens.isEmpty) return;

    // REGRA "O LOCAL MANDA": se esta coleção ainda tem gravação pendente no
    // banco local, o snapshot que acabou de ser lido está ATRASADO em relação à
    // memória. Trocar a lista inteira agora apagaria o que o usuário acabou de
    // lançar (o lançamento saía da tela e, no flush seguinte, do disco).
    // Mantém-se a memória até a gravação local concluir; na releitura seguinte
    // — já sem pendência — o snapshot volta a valer, inclusive trazendo
    // exclusões feitas por outra máquina.
    if (_dirtyCollections.contains(chaveBase) ||
        (_linhasLocaisPendentes[chaveBase]?.isNotEmpty ?? false)) {
      debugPrint(
        '>>> [Cache local] ⏳ $chaveBase com gravação local pendente: '
        'memória preservada (snapshot do banco atrasado).',
      );
      return;
    }

    destino.clear();
    destino.addAll(itens);
    if (ordenarPor != null) {
      try {
        destino.sort((a, b) {
          final cmp = ordenarPor(a).compareTo(ordenarPor(b));
          return ordenarDescendente ? -cmp : cmp;
        });
      } catch (_) {}
    }
  }

  /// Um registro carimbado com OUTRA empresa não pertence à empresa aberta.
  /// Registros sem carimbo são aceitos (dado legado), para migração.
  bool _registroDaEmpresaAberta(Map<String, dynamic> registro) {
    final empresaDoRegistro = (registro['empresa_id'] ?? registro['empresaId'])
        ?.toString();
    if (empresaDoRegistro == null || empresaDoRegistro.isEmpty) return true;
    return _currentEmpresaId != null && empresaDoRegistro == _currentEmpresaId;
  }

  /// Carrega as coleções de CAIXA do banco local.
  ///
  /// Roda PRIMEIRO em [_carregarDadosSalvos], com captura de erro própria:
  /// assim nenhum registro problemático nas demais listas (clientes, produtos,
  /// pedidos…) consegue mais impedir o carregamento do caixa — era exatamente
  /// isso que deixava o fluxo de caixa vazio quando o sistema abria sem
  /// internet.
  Future<void> _carregarCaixaLocal() async {
    await _carregarColecaoLocalTolerante<AberturaCaixa>(
      LocalStorageService.keyAberturasCaixa,
      AberturaCaixa.fromMap,
      _aberturasCaixa,
      ordenarPor: (a) => a.dataAbertura,
    );
    await _carregarColecaoLocalTolerante<FechamentoCaixa>(
      LocalStorageService.keyFechamentosCaixa,
      FechamentoCaixa.fromMap,
      _fechamentosCaixa,
      ordenarPor: (f) => f.dataFechamento,
    );
    await _carregarColecaoLocalTolerante<SangriaCaixa>(
      LocalStorageService.keySangriasField,
      SangriaCaixa.fromMap,
      _sangrias,
    );
    await _carregarColecaoLocalTolerante<SuprimentoCaixa>(
      LocalStorageService.keySuprimentosField,
      SuprimentoCaixa.fromMap,
      _suprimentos,
    );
    if (_aberturasCaixa.isNotEmpty) {
      debugPrint(
        '>>> [Cache local] 💰 Caixa carregado do banco local: '
        '${_aberturasCaixa.length} abertura(s), '
        '${_fechamentosCaixa.length} fechamento(s), '
        '${_sangrias.length} sangria(s), ${_suprimentos.length} suprimento(s).',
      );
    }
    // Reavalia o status com as listas RECÉM-CARREGADAS. É o caminho da rede
    // local: o fechamento feito no outro PC chega pelo PostgreSQL e a releitura
    // passa por aqui — sem esta linha o flag ficava velho ("aberto") e o PDV
    // continuava vendendo num caixa já fechado na outra máquina.
    _caixaAberto = aberturaCaixaAtual != null;
  }

  Future<void> _carregarDadosSalvos() async {
    if (_currentEmpresaId == null) {
      // debugPrint silenciado no boot para evitar spam
      return;
    }

    try {
      print(
        '>>> [Performance] ⏱️ Iniciando cronômetro de carregamento local...',
      );
      final stopwatch = Stopwatch()..start();

      // REGRA "LOCAL PRIMEIRO" também na LEITURA: descarrega a gravação
      // pendente ANTES de ler o banco. O snapshot lido abaixo substitui a lista
      // inteira em memória (`_aplicarColecaoTolerante`): se ele ficasse atrás
      // do que o usuário acabou de lançar, o lançamento sumia da tela e, no
      // flush seguinte, também do disco (era assim que um serviço recém-criado
      // desaparecia).
      await _garantirGravacaoLocalPendente();

      // CAIXA PRIMEIRO: o fluxo de caixa precisa abrir SEM internet mesmo que
      // alguma das demais listas falhe depois (prioridade ao banco local).
      await _carregarCaixaLocal();

      // 1. Carregar do LocalStorage com chaves isoladas por empresa
      final clientesMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyClientes),
      );
      final produtosMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyProdutos),
      );
      final servicosMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyServicos),
      );
      final pedidosMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyPedidos),
      );
      final servicosRealizadosMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyServicosRealizados),
      );
      final orcamentosMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyOrcamentos),
      );
      final vendasMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyVendasBalcao),
      );
      final agendamentosMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyAgendamentosServico),
      );
      final notasMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyNotasEntrada),
      );
      final pedidosCompraMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyPedidosCompra),
      );
      final funcionariosMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyFuncionarios),
      );
      final taxasMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyTaxasEntrega),
      );
      final contasMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyContasPagar),
      );
      final nfcesMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyNFCes),
      );
      final nfesMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyNFEs),
      );
      final mesasMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyMesasComandas),
      );
      final ordensMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyOrdensServico),
      );
      final entregasMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyEntregas),
      );
      final trocasMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyTrocasDevolucoes),
      );
      final estoqueMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyEstoqueHistorico),
      );
      final ajustesLoteMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyAjustesEstoqueLote),
      );
      final linksVendedoresMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyLinksVendedores),
      );
      final comissoesVendedoresMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyComissoesVendedores),
      );
      final romaneiosMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyRomaneios),
      );
      final movimentosCashBackMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyCashBackMovimentos),
      );

      if (clientesMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyClientes,
          clientesMap,
          Cliente.fromMap,
          _clientes,
        );
        print(
          '>>> ✓ ${_clientes.length} clientes carregados em ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      if (produtosMap.isNotEmpty) {
        // Trava de empresa na ENTRADA: o cache pode ter sido gravado com outra
        // empresa aberta (chave antiga, sem empresa) — e produto de fora que
        // ficasse em memória era carimbado com a empresa aberta na próxima
        // gravação (troca de dono silenciosa).
        final parseados = <Produto>[];
        for (final registro in produtosMap) {
          try {
            parseados.add(Produto.fromMap(registro));
          } catch (e) {
            debugPrint(
              '>>> [Cache local] ⚠️ Produto ignorado '
              '(id=${registro['id']}): $e',
            );
          }
        }
        final carregados = somenteProdutosDaEmpresaAberta(
          parseados,
          origem: 'cache local',
        );
        if (carregados.isNotEmpty) {
          _produtos.clear();
          _produtos.addAll(carregados);
        }
        print(
          '>>> ✓ ${_produtos.length} produtos carregados em ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      if (servicosMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyServicos,
          servicosMap,
          Servico.fromMap,
          _tiposServico,
        );
        print(
          '>>> ✓ ${_tiposServico.length} serviços carregados em ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      if (pedidosMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyPedidos,
          pedidosMap,
          Pedido.fromMap,
          _pedidos,
        );
        print(
          '>>> ✓ ${_pedidos.length} pedidos carregados em ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      if (servicosRealizadosMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyServicosRealizados,
          servicosRealizadosMap,
          ServicoRealizado.fromMap,
          _servicosRealizados,
        );
        print(
          '>>> ✓ ${_servicosRealizados.length} serviços realizados carregados em ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      if (orcamentosMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyOrcamentos,
          orcamentosMap,
          Orcamento.fromMap,
          _orcamentos,
        );
        print(
          '>>> ✓ ${_orcamentos.length} orçamentos carregados em ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      if (vendasMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyVendasBalcao,
          vendasMap,
          VendaBalcao.fromMap,
          _vendasBalcao,
        );
        print(
          '>>> ✓ ${_vendasBalcao.length} vendas carregadas em ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      // Deixa a tela de carregando mostrar os números que JÁ chegaram: os
      // principais ficam prontos aqui e o resto da carga continua depois.
      _notificarProgressoLoading();

      if (agendamentosMap.isNotEmpty) {
        final novos = <AgendamentoServico>[];
        for (final registro in agendamentosMap) {
          // Mesma trava de empresa das demais listas (aceita snake e camel).
          final empresaDoRegistro =
              (registro['empresa_id'] ?? registro['empresaId'])?.toString();
          if (empresaDoRegistro != null &&
              empresaDoRegistro.isNotEmpty &&
              empresaDoRegistro != _currentEmpresaId) {
            continue;
          }
          try {
            novos.add(
              _vincularReferenciasAgendamento(
                AgendamentoServico.fromMap(registro),
              ),
            );
          } catch (e) {
            debugPrint(
              '>>> [Cache local] ⚠️ Agendamento ignorado '
              '(id=${registro['id']}): $e',
            );
          }
        }
        // PROTEÇÃO: Se a memória tem mais dados que o PostgreSQL, mesclar ao invés de sobrescrever
        if (novos.length >= _agendamentosServico.length) {
          _agendamentosServico.clear();
          _agendamentosServico.addAll(novos);
        } else {
          debugPrint(
            '>>> ⚠️ PostgreSQL tem menos agendamentos (${novos.length}) que memória (${_agendamentosServico.length}). Mesclando.',
          );
          for (final n in novos) {
            if (!_agendamentosServico.any((a) => a.id == n.id)) {
              _agendamentosServico.add(n);
            }
          }
        }
        print(
          '>>> ✓ ${_agendamentosServico.length} agendamentos carregados em ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      if (contasMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyContasPagar,
          contasMap,
          ContaPagar.fromMap,
          _contasPagar,
        );
      }

      if (notasMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyNotasEntrada,
          notasMap,
          NotaEntrada.fromMap,
          _notasEntrada,
        );
      }

      if (pedidosCompraMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyPedidosCompra,
          pedidosCompraMap,
          PedidoCompra.fromMap,
          _pedidosCompra,
        );
      }

      if (taxasMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyTaxasEntrega,
          taxasMap,
          TaxaEntrega.fromMap,
          _taxasEntrega,
        );
      }

      if (ordensMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyOrdensServico,
          ordensMap,
          OrdemServico.fromMap,
          _ordensServico,
        );
      }

      if (entregasMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyEntregas,
          entregasMap,
          Entrega.fromMap,
          _entregas,
        );
      }

      if (trocasMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyTrocasDevolucoes,
          trocasMap,
          TrocaDevolucao.fromMap,
          _trocasDevolucoes,
          filtro: _isTrocaDevolucaoValida,
        );
      }

      if (estoqueMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyEstoqueHistorico,
          estoqueMap,
          EstoqueHistorico.fromMap,
          _estoqueHistorico,
        );
      }

      if (ajustesLoteMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyAjustesEstoqueLote,
          ajustesLoteMap,
          AjusteEstoqueLote.fromMap,
          _ajustesEstoqueLote,
        );
        try {
          _ajustesEstoqueLote.sort((a, b) => b.data.compareTo(a.data));
        } catch (_) {}
      }

      final lotesMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyLotesProdutos),
      );
      if (lotesMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyLotesProdutos,
          lotesMap,
          LoteProduto.fromMap,
          _lotesProdutos,
        );
      }

      print('>>> [Carregamento] ⚙️ Carregando operacional...');
      // Aberturas/fechamentos/sangrias/suprimentos já foram carregados no
      // início do método ([_carregarCaixaLocal]) — tolerantes a registro ruim.

      if (mesasMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyMesasComandas,
          mesasMap,
          MesaComanda.fromMap,
          _mesasComandas,
        );
      }

      final motoristasMap = await _storage.carregarLista(
        _getEmpresaKey(LocalStorageService.keyMotoristas),
      );
      if (motoristasMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyMotoristas,
          motoristasMap,
          Motorista.fromMap,
          _motoristas,
        );
      }

      if (funcionariosMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyFuncionarios,
          funcionariosMap,
          Funcionario.fromMap,
          _funcionarios,
        );
      }

      if (linksVendedoresMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyLinksVendedores,
          linksVendedoresMap,
          LinkVendedor.fromMap,
          _linksVendedores,
        );
      }

      if (comissoesVendedoresMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyComissoesVendedores,
          comissoesVendedoresMap,
          ComissaoVendedor.fromMap,
          _comissoesVendedores,
        );
      }

      if (romaneiosMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyRomaneios,
          romaneiosMap,
          Romaneio.fromMap,
          _romaneios,
        );
      }

      if (movimentosCashBackMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyCashBackMovimentos,
          movimentosCashBackMap,
          CashBackMovimento.fromMap,
          _movimentosCashBack,
          ordenarPor: (m) => m.data,
        );
      }

      // Última atualização dos contadores antes da parte fiscal/otimizações.
      _notificarProgressoLoading();

      print('>>> [Carregamento] 🧾 Carregando fiscal...');
      if (nfcesMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyNFCes,
          nfcesMap,
          NFCe.fromMap,
          _nfces,
        );
      }
      if (nfesMap.isNotEmpty) {
        _aplicarColecaoTolerante(
          LocalStorageService.keyNFEs,
          nfesMap,
          NFCe.fromMap,
          _nfes,
        );
      }
      await _limparRascunhosPendentesOrfaos();

      print('>>> [Carregamento] 🔗 Otimizando vínculos...');
      _reVincularTodosAgendamentos();

      // Carregar data da última sincronização bem-sucedida
      final keySync = _getEmpresaKey('exodo_ultima_sincronizacao_sucesso');
      final syncString = await _storage.carregar(keySync);
      if (syncString is String && syncString.isNotEmpty) {
        _ultimaSincronizacaoSucesso = DateTime.tryParse(syncString);
        debugPrint(
          '>>> [Sync] 🕒 Recuperada data de última sincronização: $_ultimaSincronizacaoSucesso',
        );
      }

      // Migração: vendas legadas sem operador somem dos caixas nominados.
      // Atribui o operador pelo caixa da época (idempotente).
      _atribuirOperadorVendasSemDono();

      // Migração: serviços lançados como pedido (série SRV-) passam a existir
      // na entidade própria de serviço realizado (idempotente).
      await _migrarServicosRealizadosDePedidos();

      // Carregar mínimos de numeração (VND e PED) persistidos
      await carregarMinimosNumeracao();

      // Sobe os pisos SRV/ORC/AGD a partir do que está em memória: qualquer
      // número já emitido trava a série, mesmo que a lista ainda esteja vazia.
      await _elevarEPersistirPisosSerie();

      // Túmulo persistido: registros apagados continuam barrados mesmo depois
      // de reiniciar o app (o túmulo de memória dura só 30 min).
      await carregarTombstonesPersistidos();

      stopwatch.stop();
      print(
        '>>> ✓ CARREGAMENTO LOCAL COMPLETO: ${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (e, stackTrace) {
      print('>>> ✗ Erro ao carregar dados locais: $e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Migração (idempotente): serviços que foram lançados como Pedido — série
  /// SRV- ou pedidos que só têm serviços — passam a existir também na entidade
  /// própria `servicos_realizados`.
  ///
  /// O pedido original NÃO é apagado (histórico e relatórios continuam
  /// válidos); a cópia existe para a tela de Serviços não começar vazia na
  /// separação das entidades. O vínculo pelo `id` evita migrar duas vezes.
  Future<int> _migrarServicosRealizadosDePedidos() async {
    if (_pedidos.isEmpty) return 0;

    final idsExistentes = _servicosRealizados.map((s) => s.id).toSet();
    final novos = <ServicoRealizado>[];

    for (final pedido in _pedidos) {
      if (pedido.servicos.isEmpty) continue;
      final ehSerieServico = RegExp(r'SRV-\d+').hasMatch(pedido.numero);
      final soTemServico = pedido.produtos.isEmpty;
      if (!ehSerieServico && !soTemServico) continue;
      if (idsExistentes.contains(pedido.id)) continue;

      final recebido =
          pedido.pagamentos.isNotEmpty && pedido.totalmenteRecebido;
      final cancelado = pedido.status.toLowerCase() == 'cancelado';

      novos.add(
        ServicoRealizado(
          id: pedido.id,
          numero: pedido.numero,
          clienteId: pedido.clienteId,
          clienteNome: pedido.clienteNome,
          clienteTelefone: pedido.clienteTelefone,
          clienteEndereco: pedido.clienteEndereco,
          operador: pedido.operador,
          dataServico: pedido.dataPedido,
          dataConclusao: recebido ? pedido.updatedAt : null,
          status: cancelado
              ? ServicoRealizado.statusCancelado
              : recebido
              ? ServicoRealizado.statusRecebido
              : ServicoRealizado.statusEmAberto,
          total: pedido.total,
          descontoTotal: pedido.descontoTotal,
          acrescimoTotal: pedido.acrescimoTotal,
          observacoes: pedido.observacoes,
          servicos: List.from(pedido.servicos),
          pagamentos: List.from(pedido.pagamentos),
          materiaisConsumidos: pedido.materiaisConsumidos,
          createdAt: pedido.createdAt,
          updatedAt: pedido.updatedAt,
        ),
      );
      idsExistentes.add(pedido.id);
    }

    if (novos.isEmpty) return 0;

    _servicosRealizados.addAll(novos);
    _marcarSujo(LocalStorageService.keyServicosRealizados);
    notifyListeners();
    debugPrint(
      '>>> [Migração] ${novos.length} serviço(s) lançado(s) como pedido '
      'migrado(s) para servicos_realizados',
    );
    return novos.length;
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
        final dentro =
            !venda.dataVenda.isBefore(j.inicio) &&
            venda.dataVenda.isBefore(j.fim);
        if (!dentro) continue;
        if (melhor == null || j.inicio.isAfter(melhor.inicio)) melhor = j;
      }
      final resp = melhor?.responsavel;
      final novoOperador = (resp != null && resp.isNotEmpty)
          ? resp
          : 'carlos@gmail.com';
      final idx = _vendasBalcao.indexOf(venda);
      _vendasBalcao[idx] = venda.copyWith(operador: novoOperador);
      mudou = true;
    }

    if (mudou) {
      print(
        '>>> [Migração] ⚙️ Vendas legadas sem operador atribuídas pelo caixa da época.',
      );
      _marcarSujo(LocalStorageService.keyVendasBalcao);
    }
  }

  /// Método auxiliar para atualizar listas in-place, garantindo unicidade por ID
  /// Processa uma lista para manter apenas os itens mais recentes na memória
  /// Instante de um item, para ordenar antes de aparar os mais antigos.
  ///
  /// `updatedAt` quando existe; nos modelos sem esse campo (EstoqueHistorico e
  /// AjusteEstoqueLote guardam `data`) cai para ele.
  static Object? _tempoDoItem(dynamic item) {
    try {
      final v = item.updatedAt;
      if (v != null) return v;
    } catch (_) {}
    try {
      final v = item.data;
      if (v != null) return v;
    } catch (_) {}
    try {
      final v = item.createdAt;
      if (v != null) return v;
    } catch (_) {}
    return null;
  }

  /// REGRA "A NUVEM NUNCA SOBRESCREVE O LOCAL" — decide cada merge da nuvem.
  ///
  /// Devolve `true` somente quando a versão vinda da nuvem é **estritamente mais
  /// nova** que a local. Empate, versão local mais nova ou instante que não dá
  /// para comparar → `false`: quem manda é o LOCAL (a nuvem é espelho, a fonte
  /// da verdade é o PostgreSQL local).
  ///
  /// O instante sai do [_tempoDoItem] (updatedAt → data → createdAt), então
  /// modelos sem `updatedAt` também entram na comparação. Só quando NENHUM dos
  /// dois lados tem data alguma é que a nuvem é deixada passar — sem data não
  /// há como julgar antiguidade, e travar o sync dessas entidades seria pior.
  static bool _nuvemMaisNovaQueLocal(dynamic local, dynamic nuvem) {
    final tLocal = _tempoDoItem(local);
    final tNuvem = _tempoDoItem(nuvem);
    if (tLocal is! DateTime || tNuvem is! DateTime) {
      // Nada a comparar: mantém o comportamento de sempre (nuvem aplica),
      // mas NUNCA por cima de um local que sabemos ser igual ou mais novo.
      return true;
    }
    return tNuvem.isAfter(tLocal);
  }

  /// Aparador puro dos itens antigos: mantém os [limite] mais RECENTES e joga
  /// fora os mais velhos.
  ///
  /// Precisa ordenar ANTES de cortar: sem isso o corte pegava o FIM da lista,
  /// que é o mais NOVO — porque as listas só crescem por `add` (EstoqueHistorico
  /// e AjusteEstoqueLote não têm `updatedAt`, então o sort anterior devolvia 0
  /// para todo par e nada era ordenado). O banco local guarda tudo (o gravação
  /// só faz upsert, não apaga linha); quem apar aqui é só a memória.
  static final DateTime _semTempo = DateTime.fromMillisecondsSinceEpoch(0);

  @visibleForTesting
  static void apararItensAntigos(List lista, int limite) {
    if (lista.length <= limite) return;
    // Ordenação de Schwartz: o instante de cada item é lido UMA única vez e
    // guardado junto com o item. O comparador antigo chamava `_tempoDoItem`
    // (três acessos dinâmicos dentro de try/catch) e um `compareTo` também
    // dentro de try/catch a CADA comparação — para 10k itens isso dava ~130k
    // comparações cheias de reflexão. Aqui o custo vira O(n log n) de
    // comparação simples de datas já prontas.
    try {
      final indexados = List<MapEntry<Comparable, Object?>>.generate(
        lista.length,
        (i) {
          final t = _tempoDoItem(lista[i]);
          return MapEntry<Comparable, Object?>(
            t is Comparable ? t : _semTempo,
            lista[i],
          );
        },
        growable: false,
      );
      indexados.sort((a, b) => b.key.compareTo(a.key)); // mais recente primeiro
      for (var i = 0; i < limite; i++) {
        lista[i] = indexados[i].value;
      }
      lista.removeRange(limite, lista.length);
    } catch (_) {
      // Best-effort: em qualquer imprevisto apenas corta o rabo, como antes.
      try {
        lista.removeRange(limite, lista.length);
      } catch (_) {}
    }
  }

  void _manterApenasRecentes(List lista, int limite, String nome) {
    // Apara só quando a lista passa de um limite FOLGADO (25% acima do alvo,
    // mínimo +50). Antes, assim que a lista tocava o limite exato, TODA
    // gravação (a cada ~800ms) re-ordenava a lista inteira só para cortar um ou
    // dois itens — num histórico de 10k itens eram ~130k comparações por flush.
    // Com a folga o corte vira evento esporádico, não parte de todo salvamento.
    final folga = limite ~/ 4 > 50 ? limite ~/ 4 : 50;
    if (lista.length <= limite + folga) return;
    debugPrint(
      '>>> [Memória] 🧹 Limpando $nome antigos (mantendo últimos $limite de ${lista.length})',
    );
    apararItensAntigos(lista, limite);
  }

  /// Mescla dados vindos da nuvem sem remover os locais que não estão no snapshot
  /// Útil para snapshots parciais ou buscas limitadas. Protege edições locais mais novas usando o updatedAt.
  ///
  /// Retorna `true` quando alguma linha foi realmente adicionada/substituída.
  /// Os chamadores usam isso para só marcar a coleção como suja (e reescrever a
  /// tabela) quando houve novidade — num pulso de 10s sem mudanças, o catálogo
  /// inteiro não precisa ser regravado.
  bool _mesclarSemRemover<T>(List<T> listaLocal, List<T> vindos) {
    if (vindos.isEmpty) return false;

    var mudou = false;
    final Map<String, int> indexMap = {
      for (int i = 0; i < listaLocal.length; i++)
        (listaLocal[i] as dynamic).id: i,
    };

    for (final novo in vindos) {
      final id = (novo as dynamic).id;
      if (indexMap.containsKey(id)) {
        final index = indexMap[id]!;
        final local = listaLocal[index];

        try {
          // REGRA "A NUVEM NUNCA SOBRESCREVE O LOCAL": a versão da nuvem só
          // substitui a local quando é mais NOVA. Empate (ou local mais novo)
          // → o local fica; antes, o empate deixava a nuvem vencer e a edição
          // feita aqui era revertida pelo snapshot antigo.
          if (!_nuvemMaisNovaQueLocal(local, novo)) {
            debugPrint(
              '>>> [Sync] 🛡️ Nuvem não é mais nova que o local ($id): local mantido.',
            );
            continue;
          }
        } catch (_) {
          // Fallback se o objeto não tiver updatedAt
        }

        listaLocal[index] = novo;
        mudou = true;
      } else {
        listaLocal.add(novo);
        mudou = true;
      }
    }
    return mudou;
  }

  /// Parse seguro de uma lista de registros vindos do Supabase.
  /// Se um registro falhar no parse, ele é ignorado (logado) e os demais
  /// continuam sendo processados. Retorna a lista de objetos parseados com
  /// sucesso.
  static List<T> _parseListaSegura<T>(
    List rawList,
    T Function(Map<String, dynamic>) fromMap, {
    required String nomeColecao,
  }) {
    final List<T> resultado = [];
    int erros = 0;
    for (final map in rawList) {
      try {
        resultado.add(fromMap(map as Map<String, dynamic>));
      } catch (e) {
        erros++;
        debugPrint(
          '>>> [Sync] ⚠️ $nomeColecao com erro de parse ignorado: id=${(map as Map<String, dynamic>)['id'] ?? '?'} erro=$e',
        );
      }
    }
    debugPrint(
      '>>> [Supabase] 📦 $nomeColecao: ${rawList.length} baixados, ${resultado.length} parse OK, $erros erros',
    );
    return resultado;
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
          if (novo.status == 'Aberta' &&
              novo.itens.length > existente.itens.length) {
            _tocarSomNotificacao();
            debugPrint(
              '>>> [Realtime] 🔔 Novo item detectado na mesa/comanda ${novo.numero}',
            );
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
      debugPrint(
        '>>> [Sync] 🛡️ Merge delta: mesas/comandas não presentes no snapshot foram MANTIDAS (histórico preservado).',
      );
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
    final cargaPareceParcial =
        _mesasComandas.length > 500 &&
        novos.length < (_mesasComandas.length * 0.5);

    _mesasComandas.removeWhere((m) {
      if (cargaPareceParcial) return false;
      if (!idsNovos.contains(m.id)) {
        // Proteção 1: Se é muito recente (criada nos últimos 10 minutos), manter!
        final idade = agora.difference(m.createdAt).inSeconds;
        if (idade < 600) {
          debugPrint(
            '>>> [Sync] 🛡️ Mantendo Mesa/Comanda local recém-criada: ${m.numero} (idade: ${idade}s)',
          );
          return false;
        }

        // Proteção 2: Se foi modificada recentemente localmente (últimos 5 minutos), manter!
        final idadeModificacao = agora.difference(m.updatedAt).inSeconds;
        if (idadeModificacao < 300) {
          debugPrint(
            '>>> [Sync] 🛡️ Mantendo Mesa/Comanda local modificada recentemente: ${m.numero} (idade: ${idadeModificacao}s)',
          );
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
  Future<void> _salvarTodosDados({
    bool aguardarSupabase = true,
    bool forcarTodos = false,
    bool isSync = false,
  }) async {
    if (!_persistenciaHabilitada) return;

    try {
      // OTIMIZAÇÃO CRÍTICA: Se a memória estiver pesada, limitar histórico
      _manterApenasRecentes(_estoqueHistorico, 3000, 'Estoque');
      _manterApenasRecentes(
        _ajustesEstoqueLote,
        100,
        'Ajustes de Estoque em Massa',
      );
      _manterApenasRecentes(_vendasBalcao, 10000, 'Vendas');
      _manterApenasRecentes(_ordensServico, 10000, 'Ordens de Serviço');
      _manterApenasRecentes(_pedidos, 10000, 'Pedidos');
      _manterApenasRecentes(_servicosRealizados, 10000, 'Serviços Realizados');
      _manterApenasRecentes(_orcamentos, 10000, 'Orçamentos');
      _manterApenasRecentes(_notasEntrada, 100, 'Notas de Entrada');
      _manterApenasRecentes(_pedidosCompra, 2000, 'Pedidos de Compra');
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

      // O que foi gravado de verdade e o que FALHOU nesta passada (declarados
      // antes do try para sobreviver ao catch).
      final gravadas = <String>[];
      final falhas = <String, String>{};
      // Salvar no localStorage SEQUENCIALMENTE para evitar Database Lock no PostgreSQL (Windows)
      try {
        final Map<String, List<dynamic>> colecoes = {
          LocalStorageService.keyClientes: _clientes,
          LocalStorageService.keyProdutos: _produtos,
          LocalStorageService.keyServicos: _tiposServico,
          LocalStorageService.keyPedidos: _pedidos,
          LocalStorageService.keyServicosRealizados: _servicosRealizados,
          LocalStorageService.keyOrcamentos: _orcamentos,
          LocalStorageService.keyVendasBalcao: _vendasBalcao,
          LocalStorageService.keyAgendamentosServico: _agendamentosServico,
          LocalStorageService.keyNotasEntrada: _notasEntrada,
          LocalStorageService.keyPedidosCompra: _pedidosCompra,
          LocalStorageService.keyFuncionarios: _funcionarios,
          LocalStorageService.keyTaxasEntrega: _taxasEntrega,
          LocalStorageService.keyContasPagar: _contasPagar,
          LocalStorageService.keyNFCes: _nfces,
          LocalStorageService.keyNFEs: _nfes,
          LocalStorageService.keyMesasComandas: _mesasComandas,
          LocalStorageService.keyAberturasCaixa: _aberturasCaixa,
          LocalStorageService.keyFechamentosCaixa: _fechamentosCaixa,
          LocalStorageService.keySangriasField: _sangrias,
          LocalStorageService.keySuprimentosField: _suprimentos,
          LocalStorageService.keyOrdensServico: _ordensServico,
          LocalStorageService.keyEntregas: _entregas,
          LocalStorageService.keyTrocasDevolucoes: _trocasDevolucoes,
          LocalStorageService.keyEstoqueHistorico: _estoqueHistorico,
          LocalStorageService.keyAjustesEstoqueLote: _ajustesEstoqueLote,
          LocalStorageService.keyLotesProdutos: _lotesProdutos,
          LocalStorageService.keyLinksVendedores: _linksVendedores,
          LocalStorageService.keyComissoesVendedores: _comissoesVendedores,
          LocalStorageService.keyCashBackMovimentos: _movimentosCashBack,
          LocalStorageService.keyRomaneios: _romaneios,
          LocalStorageService.keyMotoristas:
              _motoristas, // Bug Fix: motoristas estavam ausentes do mapa
        };

        int tabelasSalvasCount = 0;
        for (var entry in colecoes.entries) {
          final isDirty = _dirtyCollections.contains(entry.key);
          if (forcarTodos || isDirty) {
            // Coleção suja por carga da nuvem: grava com sync_mode = 'on' para
            // o trigger NÃO trocar updated_at por NOW() (senão o local fica
            // eternamente "mais novo" que a nuvem e o site nunca chega aqui).
            final veioDaNuvem = _colecoesSujasDaNuvem.contains(entry.key);
            try {
              await _storage.salvarLista(
                _getEmpresaKey(entry.key),
                entry.value,
                isSync: isSync || veioDaNuvem,
              );
              tabelasSalvasCount++;
              gravadas.add(entry.key);
              _colecoesSujasDaNuvem.remove(entry.key);
            } catch (e) {
              // Uma tabela que falhou NÃO pode derrubar as demais (o await
              // solto aqui abortava o loop inteiro) nem ser marcada como
              // salva: fica suja e repete no próximo flush.
              falhas[entry.key] = e.toString();
              debugPrint(
                '>>> [Memória] ❌ Não gravei ${entry.key} no banco local: $e',
              );
            }
            // Pequena pausa para o banco respirar entre tabelas
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }

        if (tabelasSalvasCount > 0) {
          print(
            '>>> ✓ $tabelasSalvasCount tabelas modificadas foram salvas no localStorage',
          );
        }
      } catch (e) {
        debugPrint('>>> [Memória] ❌ Erro no salvamento seletivo: $e');
      }

      // Aviso VÍVEL de gravação falhada: o erro até aqui só ia para o
      // debugPrint, então se o PostgreSQL local caísse a alteração ia só para
      // a nuvem e a cópia local ficava velha sem ninguém perceber.
      if (falhas.isNotEmpty) {
        final dica = DatabaseService.dicaDoErroLocal(
          DatabaseService().ultimoErroDoBancoLocal,
          acao: 'gravar',
        );
        addSyncLog(
          '⚠️ Não gravei no banco local: ${falhas.length} lista(s) '
          '(${falhas.keys.take(3).join(', ')}${falhas.length > 3 ? '…' : ''}) — $dica',
        );
        notifyListeners();
      }
      // Só desmarca o que foi GRAVADO de verdade — o resto continua sujo para
      // repetir no próximo flush. Antes tudo era limpo mesmo com falha e a
      // mudança ficava apenas em memória (sumia no fechar o app).
      _dirtyCollections.removeAll(gravadas);

      // PROTEÇÃO: Removido re-read para validar (economiza 50% de CPU/RAM no salvamento)

      // Sincronizar com Supabase apenas se:
      // 1. Supabase está habilitado
      // 2. Tem empresa selecionada
      // 3. For uma operação manual/forçada (aguardarSupabase: true)
      //    OU se realmente passou o intervalo (90 dias) e o app está ocioso
      final agora = DateTime.now();
      final deveSincronizarTotal =
          aguardarSupabase ||
          (_ultimaSincronizacaoSucesso == null && !_isOffline) ||
          agora.difference(
                _ultimaSincronizacao ?? agora.subtract(const Duration(days: 1)),
              ) >
              _intervaloSincronizacao;

      if (nuvemHabilitada &&
          SupabaseService.isAvailable &&
          _currentEmpresaId != null &&
          deveSincronizarTotal) {
        if (aguardarSupabase) {
          // Para operações críticas (como fechar caixa), aguarda o Supabase
          try {
            await _sincronizarComSupabase();
            _ultimaSincronizacao = agora;
            print(
              '>>> ✓ Todos os dados foram sincronizados com Supabase (aguardado)',
            );
          } catch (e) {
            print('>>> ✗ Erro ao sincronizar com Supabase: $e');
            _adicionarSincronizacaoPendente();
          }
        } else if (_ultimaSincronizacao == null) {
          // background sync - APENAS SE FOR A PRIMEIRA VEZ para esta empresa
          // Isso garante que dados locais subam para o Supabase se ele estiver vazio
          debugPrint(
            '>>> [Sync] 📡 Iniciando sincronização inicial em background para empresa $currentEmpresaId...',
          );
          _sincronizarComSupabase()
              .then((_) {
                _ultimaSincronizacao = agora;
                _ultimaSincronizacaoSucesso = agora;
                notifyListeners();
                debugPrint(
                  '>>> [Sync] ✅ Sincronização inicial em background concluída.',
                );
              })
              .catchError((e) {
                debugPrint(
                  '>>> [Sync] ❌ Erro na sincronização inicial em background: $e',
                );
                _adicionarSincronizacaoPendente();
              });
        } else {
          // background sync - APENAS SE FOR REALMENTE NECESSÁRIO (evitando picos de gravações)
          debugPrint(
            '>>> [Sync] 📡 Ignorando sincronização TOTAL automática para poupar banda do Supabase.',
          );
          debugPrint(
            '>>> [Sync]    As mudanças individuais (clientes, pedidos, etc) já são salvas em tempo real.',
          );
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
      debugPrint(
        '>>> [Sync] ⚠️ Empresa não selecionada, pulando sincronização',
      );
      return;
    }

    if (!nuvemHabilitada) {
      debugPrint(
        '>>> [Sync] ⏸️ Nuvem temporariamente desativada para a empresa $currentEmpresaId. Upload bloqueado.',
      );
      addSyncLog(
        '☁️ Nuvem desativada para esta empresa. Os dados continuam apenas no PostgreSQL local.',
      );
      return;
    }

    if (!SupabaseService.isAvailable) {
      debugPrint('>>> [Sync] ⚠️ Supabase não disponível, pulando...');
      return;
    }

    // PROTEÇÃO: Se TODAS as listas estiverem vazias, NÃO enviar nada para a
    // nuvem. Isso evita que uma limpeza acidental do cache local (ex.: botão
    // "Puxar Nuvem") apague todos os dados da nuvem via upsert com listas vazias.
    final todosVazios =
        _clientes.isEmpty &&
        _produtos.isEmpty &&
        _pedidos.isEmpty &&
        _vendasBalcao.isEmpty &&
        _funcionarios.isEmpty &&
        _agendamentosServico.isEmpty;
    if (todosVazios) {
      debugPrint(
        '>>> [Sync] 🛑 ABORTADO: todas as listas locais estão vazias. Enviaria dados vazios para a nuvem — isso apagaria tudo! Pulando sincronização.',
      );
      addSyncLog(
        '🛑 Sincronização abortada: dados locais vazios (proteção contra apagamento da nuvem).',
      );
      return;
    }

    addSyncLog("Enviando dados locais para a nuvem...");

    try {
      // Timeout de 60 segundos para evitar travamentos
      await _supabaseService
          .salvarTudoNoSupabase(
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
            ajustesEstoqueLote: _ajustesEstoqueLote,
            lotesProdutos: _lotesProdutos,
            aberturasCaixa: _aberturasCaixa,
            fechamentosCaixa: _fechamentosCaixa,
            motoristas: _motoristas,
            agendamentosServico: _agendamentosServico,
            notasEntrada: _notasEntrada,
            pedidosCompra: _pedidosCompra,
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
            movimentosCashBack: _movimentosCashBack,
            empresa: _empresaAtual,
          )
          .timeout(
            const Duration(
              minutes: 10,
            ), // Aumentado para 10 minutos para grandes catálogos
            onTimeout: () {
              debugPrint(
                '>>> [Sync] ⚠️ Timeout ao sincronizar com Supabase (10min)',
              );
              throw TimeoutException(
                'Timeout na sincronização com Supabase. A rede pode estar lenta ou o volume de dados é muito alto.',
              );
            },
          );

      debugPrint(
        '>>> [Sync] ✅ Sincronização com Supabase concluída com sucesso',
      );
      _ultimaSincronizacaoSucesso = DateTime.now();
      _ultimaSincronizacao = _ultimaSincronizacaoSucesso;

      // Persistir timestamp de sucesso e remover erro anterior
      if (_currentEmpresaId != null) {
        final keySync = _getEmpresaKey('exodo_ultima_sincronizacao_sucesso');
        await _storage.salvar(
          keySync,
          _ultimaSincronizacaoSucesso!.toIso8601String(),
        );
        await _storage.remover(_getEmpresaKey('exodo_ultimo_erro_sync'));
      }
      _ultimoErroSync = null;

      addSyncLog("✅ Envio de dados concluído com sucesso.");
    } catch (e, stackTrace) {
      _ultimoErroSync = e.toString();
      if (_currentEmpresaId != null) {
        await _storage.salvar(
          _getEmpresaKey('exodo_ultimo_erro_sync'),
          _ultimoErroSync,
        );
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
    if (!nuvemHabilitada) {
      addSyncLog(
        '☁️ Sincronização não iniciada: nuvem desativada para esta empresa.',
      );
      return;
    }

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

  /// Recarrega dados do PostgreSQL local e envia tudo para o Supabase.
  /// Usado após restaurar um dump PostgreSQL para que outras máquinas
  /// recebam os dados via sincronização automática.
  Future<void> enviarDadosLocaisParaNuvem() async {
    if (_currentEmpresaId == null) {
      throw Exception('Empresa não selecionada.');
    }
    if (!nuvemHabilitada) {
      throw StateError(
        'Nuvem desativada para esta empresa. Os dados continuam no PostgreSQL local.',
      );
    }
    if (!SupabaseService.isAvailable) {
      throw Exception('Supabase não está disponível.');
    }

    _isLoading = true;
    _mensagemLoading = 'Recarregando dados locais...';
    notifyListeners();

    try {
      // 1. Recarregar dados do PostgreSQL local para a memória
      debugPrint('>>> [Sync] 📥 Recarregando dados do PostgreSQL local...');
      await _carregarDadosSalvos();
      debugPrint(
        '>>> [Sync] ✅ Dados recarregados: ${_produtos.length} produtos, ${_clientes.length} clientes, ${_pedidos.length} pedidos',
      );

      if (_produtos.isEmpty && _clientes.isEmpty && _pedidos.isEmpty) {
        throw Exception(
          'Nenhum dado encontrado no PostgreSQL local. Verifique se o dump foi restaurado corretamente.',
        );
      }

      // 2. Forçar reset do timestamp para forçar upload completo
      _ultimaSincronizacao = null;
      _ultimaSincronizacaoSucesso = null;

      // 3. Backup de seguranca ANTES de deletar dados do Supabase
      _mensagemLoading = 'Criando backup de seguranca...';
      notifyListeners();
      try {
        final backupService = BackupRestoreService(this);
        final (backupOk, backupMsg, _) = await backupService
            .uploadBackupNaNuvem();
        if (backupOk) {
          debugPrint(
            '>>> [Sync] 🛡️ Backup de seguranca criado antes da limpeza: $backupMsg',
          );
          addSyncLog(
            '🛡️ Backup de seguranca criado antes de enviar dados para nuvem.',
          );
        } else {
          debugPrint('>>> [Sync] ⚠️ Backup de seguranca falhou: $backupMsg');
        }
      } catch (e) {
        debugPrint(
          '>>> [Sync] ⚠️ Erro no backup de seguranca: $e (continuando)',
        );
      }

      // 4. Enviar dados para o Supabase PRIMEIRO (upsert sobrescreve dados existentes)
      // IMPORTANTE: NÃO deletar antes do upload — se o upload falhar, dados somem!
      _mensagemLoading = 'Enviando dados para a nuvem...';
      notifyListeners();
      debugPrint('>>> [Sync] 🚀 Enviando dados locais para Supabase...');

      await _sincronizarComSupabase();

      // 5. Incrementar sync_version no Supabase para que outras máquinas detectem
      try {
        await _incrementarSyncVersion();
        // Salvar versão local para não detectar nosso próprio push
        final config = Map<String, dynamic>.from(
          _empresaAtual?.configuracoes ?? {},
        );
        final rawV = config['sync_version'];
        final newVersion = rawV is int
            ? rawV
            : int.tryParse(rawV?.toString() ?? '') ?? 1;
        await _storage.salvar(_getEmpresaKey('exodo_sync_version'), newVersion);
      } catch (e) {
        debugPrint(
          '>>> [Sync] ⚠️ Erro ao incrementar sync_version: $e (não bloqueante)',
        );
      }

      debugPrint('>>> [Sync] ✅ Dados enviados para a nuvem com sucesso!');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Verifica integridade dos dados comparando contagens locais com Supabase.
  /// Retorna (ok, mensagem, detalhes).
  Future<(bool, String, Map<String, dynamic>)> verificarIntegridade() async {
    if (_currentEmpresaId == null || !SupabaseService.isAvailable) {
      return (
        false,
        'Empresa não selecionada ou Supabase indisponível',
        <String, dynamic>{},
      );
    }

    try {
      // Contagens locais
      final local = {
        'produtos': _produtos.length,
        'clientes': _clientes.length,
        'pedidos': _pedidos.length,
        'servicos': _tiposServico.length,
        'funcionarios': _funcionarios.length,
      };

      // Contagens do Supabase
      final remoto = <String, int>{};
      final tabelas = {
        'produtos': SupabaseService.tableProdutos,
        'clientes': SupabaseService.tableClientes,
        'pedidos': SupabaseService.tablePedidos,
        'servicos': SupabaseService.tableServicos,
        'funcionarios': SupabaseService.tableFuncionarios,
      };

      for (final entry in tabelas.entries) {
        try {
          final result = await SupabaseService.instance.client
              .from(entry.value)
              .select('id')
              .eq('empresa_id', _currentEmpresaId!)
              .count();
          remoto[entry.key] = result.count;
        } catch (e) {
          remoto[entry.key] = -1; // Erro na consulta
        }
      }

      // Comparar
      final problemas = <String>[];
      for (final key in local.keys) {
        final loc = local[key] ?? 0;
        final rem = remoto[key] ?? 0;
        if (rem == -1) {
          problemas.add('$key: erro ao consultar Supabase');
        } else if (loc != rem) {
          problemas.add('$key: local=$loc, nuvem=$rem');
        }
      }

      final ok = problemas.isEmpty;
      final msg = ok
          ? '✅ Integridade OK! Todas as contagens coincidem.'
          : '⚠️ Diferenças encontradas:\n${problemas.join('\n')}';

      debugPrint('>>> [Sync] $msg');
      return (
        ok,
        msg,
        <String, dynamic>{
          'local': local,
          'remoto': remoto,
          'problemas': problemas,
        },
      );
    } catch (e) {
      return (false, 'Erro ao verificar integridade: $e', <String, dynamic>{});
    }
  }

  /// Incrementa um contador sync_version na tabela empresas do Supabase.
  /// Outras máquinas detectam a mudança e forçam full sync.
  Future<void> _incrementarSyncVersion() async {
    if (!nuvemHabilitada || _currentEmpresaId == null || _empresaAtual == null)
      return;
    try {
      final config = Map<String, dynamic>.from(
        _empresaAtual!.configuracoes ?? {},
      );
      final rawCV = config['sync_version'];
      final currentVersion = rawCV is int
          ? rawCV
          : int.tryParse(rawCV?.toString() ?? '') ?? 0;
      config['sync_version'] = currentVersion + 1;
      config['last_cloud_push'] = DateTime.now().toUtc().toIso8601String();
      await _supabaseService.upsert(SupabaseService.tableEmpresas, {
        'id': _currentEmpresaId!,
        'configuracoes': config,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint(
        '>>> [Sync] 🔄 sync_version incrementada para ${currentVersion + 1}',
      );
    } catch (e) {
      debugPrint('>>> [Sync] ⚠️ Erro ao incrementar sync_version: $e');
    }
  }

  /// Verifica se o Supabase tem dados mais recentes que o local.
  /// Chamado periodicamente pelo auto-sync para detectar uploads de outras máquinas.
  Future<void> _verificarAtualizacoesNuvem() async {
    if (!nuvemHabilitada ||
        _currentEmpresaId == null ||
        !SupabaseService.isAvailable ||
        _isOffline)
      return;
    if (_syncEmAndamento) return;

    try {
      // Buscar sync_version remoto
      final result = await _supabaseService.client
          .from(SupabaseService.tableEmpresas)
          .select('configuracoes')
          .eq('id', _currentEmpresaId!)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (result == null) return;

      final config = result['configuracoes'] as Map<String, dynamic>?;
      if (config == null) return;

      // sync_version pode vir como int OU String do Supabase
      final rawRemote = config['sync_version'];
      final remoteVersion = rawRemote is int
          ? rawRemote
          : int.tryParse(rawRemote?.toString() ?? '') ?? 0;
      final rawLocal = await _storage.carregar(
        _getEmpresaKey('exodo_sync_version'),
      );
      final localVersion = rawLocal is int
          ? rawLocal
          : int.tryParse(rawLocal?.toString() ?? '') ?? 0;

      if (remoteVersion > localVersion) {
        debugPrint(
          '>>> [Sync] 🔄 Nova versão detectada! Remoto: $remoteVersion, Local: $localVersion. Forçando FULL SYNC...',
        );

        // Salvar nova versão local
        await _storage.salvar(
          _getEmpresaKey('exodo_sync_version'),
          remoteVersion,
        );

        // Forçar full sync resetando o timestamp
        _ultimaSincronizacaoSucesso = null;
        _ultimaSincronizacao = null;

        // Trigger download
        _syncEmAndamento = true;
        try {
          await _carregarDadosDoSupabase(modoLeve: false);
          await _salvarTodosDados(aguardarSupabase: false, isSync: true);
          _ultimaSincronizacaoSucesso = DateTime.now();
          _ultimaSincronizacao = _ultimaSincronizacaoSucesso;
          notifyListeners();
          debugPrint(
            '>>> [Sync] ✅ Full sync concluído após detectar atualização da nuvem',
          );
        } finally {
          _syncEmAndamento = false;
        }
      }
    } catch (e) {
      debugPrint('>>> [Sync] ⚠️ Erro ao verificar atualizações da nuvem: $e');
    }
  }

  /// Tabelas LOCAIS (PostgreSQL) que guardam dados POR EMPRESA.
  ///
  /// Usadas para limpar a base local de uma empresa sem tocar nas outras e sem
  /// tocar na nuvem ("Limpar Local" e "Puxar Nuvem"). Aceita tanto as chaves do
  /// [LocalStorageService] quanto o nome real da tabela — `DatabaseService`
  /// resolve as duas formas.
  ///
  /// Ficam DE FORA de propósito:
  ///  - `sync_logs`, `sync_status`, `exodo_sync_conflitos`: telemetria de
  ///    sincronização, não dados da empresa;
  ///  - `empresas` e `usuarios`: cadastro/autenticação — apagar derrubaria o app.
  /// (usamos `final` e não `const` porque as chaves do [LocalStorageService]
  /// são getters, não constantes de compilação)
  static final List<String> tabelasLocaisDaEmpresa = [
    LocalStorageService.keyProdutos,
    LocalStorageService.keyClientes,
    LocalStorageService.keyServicos,
    LocalStorageService.keyPedidos,
    LocalStorageService.keyServicosRealizados,
    LocalStorageService.keyOrcamentos,
    LocalStorageService.keyVendasBalcao,
    LocalStorageService.keyAgendamentosServico,
    LocalStorageService.keyNotasEntrada,
    LocalStorageService.keyPedidosCompra,
    LocalStorageService.keyFuncionarios,
    LocalStorageService.keyTaxasEntrega,
    LocalStorageService.keyContasPagar,
    LocalStorageService.keyNFCes,
    LocalStorageService.keyNFEs,
    LocalStorageService.keyMesasComandas,
    LocalStorageService.keySangriasField,
    LocalStorageService.keySuprimentosField,
    LocalStorageService.keyOrdensServico,
    LocalStorageService.keyEntregas,
    LocalStorageService.keyTrocasDevolucoes,
    LocalStorageService.keyEstoqueHistorico,
    LocalStorageService.keyAjustesEstoqueLote,
    LocalStorageService.keyLotesProdutos,
    LocalStorageService.keyLinksVendedores,
    LocalStorageService.keyComissoesVendedores,
    LocalStorageService.keyRomaneios,
    LocalStorageService.keyMotoristas,
    LocalStorageService.keyAberturasCaixa,
    LocalStorageService.keyFechamentosCaixa,
    'produto_historico', // histórico de alterações do produto (sem chave de storage)
    'imagens', // imagens/fotos dos produtos
  ];

  /// Verifica se um mapa de dados contém alguma lista não vazia — ou seja,
  /// há pelo menos uma tabela com registros para sincronizar.
  ///
  /// É usado pelo teste de regressão e pode ser útil em qualquer ponto que
  /// precise saber, de forma genérica, se um dicionário de coleções tem
  /// conteúdo.
  static bool possuiDadosParaSincronizacao(Map<String, dynamic> dados) {
    for (final valor in dados.values) {
      if (valor is List && valor.isNotEmpty) return true;
    }
    return false;
  }

  /// `true` quando a carga do Supabase falhou POR COMPLETO — o servidor está
  /// indisponível (PGRST002/503/504) ou nenhuma das tabelas respondeu.
  ///
  /// Nesse caso a sincronização NÃO pode ser marcada como sucesso: sem este
  /// teste, todas as listas voltando vazias eram tratadas como "nenhum dado
  /// novo", o watermark do delta sync avançava e o cliente passava a pular os
  /// registros alterados durante a queda do Supabase.
  static bool falhaTotalDoSupabase(Map<String, dynamic> resultado) {
    if (resultado['servidorIndisponivel'] == true) return true;
    final total = (resultado['totalTabelas'] as int?) ?? 0;
    final falhas = (resultado['falhas'] as int?) ?? 0;
    return total > 0 && falhas >= total;
  }

  /// `true` depois do botão **"Limpar Local"**: a base local está vazia DE
  /// PROPÓSITO e nenhuma recarga automática pode repovoá-la — só o botão
  /// "Puxar Nuvem" (que chama `_carregarDadosDoSupabase` com
  /// `forcarRecarga: true`). Sem esta trava, o auto-sync baixava tudo de novo
  /// poucos segundos depois da limpeza e o botão parecia não ter feito nada.
  bool _baseLocalLimpa = false;

  /// A base local foi limpa e está aguardando "Puxar Nuvem"?
  bool get baseLocalLimpa => _baseLocalLimpa;

  void _limparCacheLocalCompleto() {
    _clientes.clear();
    _produtos.clear();
    _tiposServico.clear();
    _pedidos.clear();
    _servicosRealizados.clear();
    _orcamentos.clear();
    _ordensServico.clear();
    _entregas.clear();
    _motoristas.clear();
    _vendasBalcao.clear();
    _trocasDevolucoes.clear();
    _estoqueHistorico.clear();
    _ajustesEstoqueLote.clear();
    _lotesProdutos.clear();
    _notasEntrada.clear();
    _pedidosCompra.clear();
    _agendamentosServico.clear();
    _funcionarios.clear();
    _taxasEntrega.clear();
    _contasPagar.clear();
    _nfces.clear();
    _nfes.clear();
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
    // As linhas do caminho rápido são descartadas: a base local foi/ será
    // limpa e uma linha pendente antiga não pode ressuscitar um registro
    // apagado na recarga completa da nuvem.
    _linhasLocaisPendentes.clear();
    _debounceLinhasLocais?.cancel();
    _debounceLinhasLocais = null;
    _idsMesaRemovidosRecentemente.clear();

    _ultimaSincronizacao = null;
    _ultimaSincronizacaoSucesso = null;
    _ultimoErroSync = null;

    debugPrint(
      '>>> [DataService] 🧹 Cache local completo limpo para forçar recarga da nuvem.',
    );
  }

  /// Força a limpeza completa da base local e recarregamento total do Supabase.
  /// Ao final, a base local fica IDÊNTICA à nuvem: tudo que existia só localmente
  /// (clientes, vendas, pedidos, etc.) é apagado e substituído pelos dados do Supabase.
  Future<void> recarregarTudoDoSupabase() async {
    _isLoading = true;
    _mensagemLoading = 'Limpando base local e baixando dados da nuvem...';
    notifyListeners();

    // Sem empresa selecionada não há como puxar (evita limpar chaves compartilhadas)
    if (_currentEmpresaId == null || _currentEmpresaId!.isEmpty) {
      _isLoading = false;
      notifyListeners();
      throw Exception(
        'Nenhuma empresa selecionada. Selecione uma empresa primeiro.',
      );
    }

    // Se já estiver offline, nem começar: evita limpar o local e ficar sem dados
    if (_isOffline || !SupabaseService.isAvailable) {
      _isLoading = false;
      notifyListeners();
      throw Exception(
        'Sem conexão com a nuvem (Supabase offline). Nada foi alterado.',
      );
    }

    // Evita conflito com o auto-sync periódico que possa estar rodando agora
    final prazo = DateTime.now().add(const Duration(seconds: 15));
    while (_syncEmAndamento && DateTime.now().isBefore(prazo)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_syncEmAndamento) {
      _isLoading = false;
      notifyListeners();
      throw Exception(
        'Sincronização já em andamento. Tente novamente em instantes.',
      );
    }

    // "Puxar Nuvem" é o ÚNICO caminho que pode repovoar uma base limpa.
    _baseLocalLimpa = false;

    // �o. PRÉ-CHECAGEM OBRIGATÓRIA — baixa da nuvem ANTES de apagar qualquer
    // coisa aqui. Enquanto a ordem era "apaga local → baixa", uma falha da
    // nuvem (offline, cota 402, 503/504) deixava o computador ZERADO sem ter de
    // onde repor: o usuário ficava refém da nuvem. Agora, se a nuvem não
    // responder ou não tiver dados, ABORTA e o banco local fica intacto.
    try {
      final pre = await _supabaseService.carregarTudoDoSupabase(
        _currentEmpresaId!,
        lastSync: null,
        mesesRetroativos: 24,
      );
      final dadosPre = (pre['data'] as Map<String, dynamic>?) ?? {};
      if (DataService.falhaTotalDoSupabase(pre)) {
        throw Exception(
          'A nuvem não respondeu (indisponível ou cota excedida). '
          'Nada foi apagado no seu computador — os dados locais continuam aqui.',
        );
      }
      if (!DataService.possuiDadosParaSincronizacao(dadosPre)) {
        throw Exception(
          'A nuvem não devolveu dados desta empresa. Para não esvaziar o seu '
          'computador, nada foi apagado — tente novamente quando a nuvem '
          'estiver respondendo normalmente.',
        );
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint(
        '>>> [DataService] ⛔ Puxar Nuvem abortado na pré-checagem: $e',
      );
      rethrow;
    }

    // Segura o lock de sincronização durante TODA a operação para o auto-sync
    // periódico não interromper no meio (senão ele sobrescreveria o estado vazio
    // ou se misturaria com a recarga). _carregarDadosDoSupabase(forcarRecarga)
    // não aborta por causa dele e o próprio finally dele libera o lock.
    _syncEmAndamento = true;

    try {
      // ORDEM SEGURA: limpar a MEMÓRIA → BAIXAR da nuvem → só então apagar o
      // banco local e gravar o que veio. Assim o DELETE do banco local só
      // acontece depois de o download ter dado certo.

      // 1. Limpar a MEMÓRIA (não toca no banco local ainda). Resetar o
      //    timestamp força FULL SYNC (sem delta).
      _limparCacheLocalCompleto();

      // Mantém _ultimaSincronizacao preenchido para que _salvarTodosDados NÃO
      // interprete como "primeira sincronização" e tente enviar o estado vazio
      // para a nuvem (isso apagaria a nuvem!). O upload só acontece quando o
      // _ultimaSincronizacao está nulo.
      _ultimaSincronizacao = DateTime.now();

      // 2. Baixar TUDO do Supabase para a memória (full sync).
      await _carregarDadosDoSupabase(modoLeve: false, forcarRecarga: true);

      // 3. Só AGORA que a nuvem respondeu e a memória tem os dados, esvaziar o
      //    PostgreSQL local. _upsertRows só insere/atualiza (nunca remove), por
      //    isso o DELETE explícito — mas ele vem DEPOIS do download, então uma
      //    falha de nuvem não deixa o computador sem dados.
      if (!kIsWeb) {
        // Cópia de segurança do estado local ANTES de apagar (best-effort: se
        // falhar, o download da nuvem já garantiu os dados para repor, então a
        // operação segue — mas a cópia é sempre tentada).
        try {
          await BackupRestoreService(
            this,
          ).criarBackupSqlDaEmpresa(empresaId: _currentEmpresaId);
        } catch (e) {
          debugPrint(
            '>>> [DataService] ⚠️ Cópia antes do Puxar Nuvem falhou: $e',
          );
        }

        final db = DatabaseService();
        if (_currentEmpresaId != null) {
          db.setEmpresaId(_currentEmpresaId!); // Garante isolamento por empresa
        }
        final removidas = await db.limparTabelasDaEmpresa(
          tabelasLocaisDaEmpresa,
        );
        final totalRemovidas = removidas.values.fold<int>(
          0,
          (soma, qtd) => soma + qtd,
        );
        debugPrint(
          '>>> [DataService] 🗑️ Base local (PostgreSQL) limpa: $totalRemovidas linha(s) '
          'em ${removidas.length} tabela(s) da empresa $_currentEmpresaId.',
        );
      }

      // 4. Persistir localmente exatamente o que veio da nuvem (sobrescreve tudo).
      await _salvarTodosDados(
        aguardarSupabase: false,
        forcarTodos: true,
        isSync: true,
      );

      // Aberturas/fechamentos de caixa são persistidos fora do mapa de _salvarTodosDados;
      // gravar explicitamente para a base local refletir exatamente a nuvem.
      if (_currentEmpresaId != null) {
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyAberturasCaixa),
          _aberturasCaixa,
        );
        await _storage.salvarLista(
          _getChaveComEmpresa(LocalStorageService.keyFechamentosCaixa),
          _fechamentosCaixa,
        );
      }

      _ultimaSincronizacao = DateTime.now();
      _ultimaSincronizacaoSucesso = _ultimaSincronizacao;
      _ultimoErroSync = null;

      debugPrint(
        '>>> [DataService] ✅ Base local recarregada da nuvem (local == nuvem).',
      );
    } catch (e) {
      debugPrint('>>> [DataService] ❌ Erro no recarregamento total: $e');
      _ultimoErroSync = e.toString();
      rethrow;
    } finally {
      // Libera o lock de sincronização mesmo em caso de erro (o finally interno
      // de _carregarDadosDoSupabase já libera, mas garantimos por segurança)
      _syncEmAndamento = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// **LIMPAR LOCAL**: apaga os dados DESTA empresa no computador — memória,
  /// PostgreSQL local e cache — deixando a NUVEM intacta.
  ///
  /// É o passo que faltava no fluxo "Limpar Local → Puxar Nuvem". A versão
  /// anterior só esvaziava as listas em memória e chamava `_salvarTodosDados`,
  /// que faz UPSERT (nunca DELETE): as tabelas do PostgreSQL continuavam cheias,
  /// então a recarga trazia de volta exatamente o que já estava local — e o que
  /// não existisse na nuvem nunca desaparecia.
  ///
  /// Segurança da nuvem: `DatabaseService.limparTabela` roda com
  /// `exodo.sync_mode = 'on'`, então o trigger `log_sync_event` não registra os
  /// DELETEs e o sincronizador de bandeja não os propaga para o Supabase.
  ///
  /// Retorna `tabela -> linhas apagadas` (tabelas vazias não aparecem).
  Future<ResultadoLimpezaLocal> resetLocalCacheOnly({
    String? empresaId,
    String? empresaNome,
  }) async {
    final aberta = _currentEmpresaId;
    final alvo = (empresaId != null && empresaId.isNotEmpty)
        ? empresaId
        : aberta;

    if (alvo == null || alvo.isEmpty) {
      throw Exception(
        'Nenhuma empresa selecionada. Selecione uma empresa primeiro.',
      );
    }

    // A empresa ABERTA NA TELA manda: se o serviço estiver com outra empresa
    // carregada, aborta sem apagar NADA. Sem esta conferência, o botão poderia
    // limpar a base local de uma empresa que não é a que o usuário está vendo.
    if (aberta != null && aberta.isNotEmpty && aberta != alvo) {
      throw Exception(
        'A empresa aberta na tela não é a mesma carregada no '
        'sistema. Nada foi apagado — abra a empresa de novo e tente outra vez.',
      );
    }

    final nome = empresaNome ?? _empresaAtual?.nomeExibicao ?? alvo;

    _isLoading = true;
    _mensagemLoading = 'Limpando a base local desta empresa...';
    notifyListeners();

    // 🛡️ REDE DE SEGURANÇA OBRIGATÓRIA: tira uma foto do banco local desta
    // empresa ANTES de apagar. Se a cópia de segurança NÃO puder ser criada,
    // a limpeza é ABORTADA — os dados locais são sagrados e nunca podem ser
    // apagados sem uma cópia recuperável em C:\ExodoBackups.
    try {
      final (okBackup, msgBackup, caminhoBackup) = await BackupRestoreService(
        this,
      ).criarBackupSqlDaEmpresa(empresaId: alvo);
      if (okBackup) {
        debugPrint(
          '>>> [DataService] 🛡️ Cópia automática antes de limpar: $caminhoBackup',
        );
      } else {
        _isLoading = false;
        notifyListeners();
        throw Exception(
          'Limpeza ABORTADA: não foi possível criar a cópia de segurança antes '
          'de apagar ($msgBackup). Por segurança, nada foi removido.',
        );
      }
    } catch (e) {
      // Se o próprio backup lançou, aborta a limpeza.
      if (e is! Exception || !e.toString().contains('Limpeza ABORTADA')) {
        _isLoading = false;
        notifyListeners();
        throw Exception(
          'Limpeza ABORTADA: falha ao criar a cópia de segurança antes de '
          'apagar ($e). Por segurança, nada foi removido.',
        );
      }
      rethrow;
    }

    // Impede o auto-sync de gravar no meio da limpeza.
    _syncEmAndamento = true;
    try {
      // 1. Listas em memória
      _limparCacheLocalCompleto();

      // 2. PostgreSQL local: DELETE das linhas DESTA empresa, tabela por tabela
      final removidas = <String, int>{};
      var linhasDeOutrasEmpresas = 0;
      if (!kIsWeb) {
        final db = DatabaseService();
        db.setEmpresaId(alvo); // garante o isolamento por empresa
        removidas.addAll(
          await db.limparTabelasDaEmpresa(tabelasLocaisDaEmpresa),
        );
        // Prova pós-limpeza: quanto sobrou das OUTRAS empresas nas mesmas tabelas.
        linhasDeOutrasEmpresas = await db.contarLinhasDeOutrasEmpresas(
          tabelasLocaisDaEmpresa,
        );
      }

      // 3. _limparCacheLocalCompleto zerou _ultimaSincronizacao. Se ficasse nulo,
      //    o próximo salvamento entenderia "primeira sincronização" e enviaria o
      //    estado VAZIO para a nuvem (apagando-a). Marcamos como sincronizado
      //    agora; deixar _ultimaSincronizacaoSucesso nulo força o próximo
      //    download a ser completo, sem delta.
      _ultimaSincronizacao = DateTime.now();
      _ultimaSincronizacaoSucesso = null;
      _ultimoErroSync = null;

      // Trava as recargas automáticas até o usuário mandar "Puxar Nuvem":
      // assim a tela realmente fica vazia (prova de que a limpeza ocorreu) em
      // vez de se repovoar sozinha em segundos.
      _baseLocalLimpa = true;

      final resultado = ResultadoLimpezaLocal(
        empresaId: alvo,
        empresaNome: nome,
        porTabela: removidas,
        linhasDeOutrasEmpresas: linhasDeOutrasEmpresas,
      );
      debugPrint(
        '>>> [DataService] 🧹 Base local de "$nome" ($alvo) limpa: '
        '${resultado.total} linha(s) em ${resultado.tabelas} tabela(s). '
        'Outras empresas intactas: $linhasDeOutrasEmpresas linha(s). '
        'Nuvem intacta. Recargas automáticas bloqueadas até "Puxar Nuvem".',
      );
      return resultado;
    } finally {
      _syncEmAndamento = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adiciona sincronização pendente à fila
  void _adicionarSincronizacaoPendente({
    String? table,
    Map<String, dynamic>? data,
    String? type,
    String? empresaId,
  }) {
    final empresaNoRegistro = data?['empresa_id']?.toString();
    final empresaDaOperacao = (empresaId != null && empresaId.isNotEmpty)
        ? empresaId
        : ((empresaNoRegistro != null && empresaNoRegistro.isNotEmpty)
              ? empresaNoRegistro
              : _currentEmpresaId);
    if (empresaDaOperacao == null || empresaDaOperacao.isEmpty) {
      debugPrint(
        '>>> [Sync] ⚠️ Não é possível adicionar à fila: empresa não selecionada',
      );
      return;
    }

    if (table != null && data != null) {
      final operationType = type ?? 'upsert';
      // Captura a empresa AQUI (no enfileiramento). A fila é persistida e pode ser
      // drenada depois de trocar de empresa; se o execute() lesse
      // _currentEmpresaId, o item desta empresa seria gravado como sendo da outra.
      debugPrint(
        '>>> [Sync] 📋 Item específico adicionado à fila: $table (${data['id']}) - $operationType (empresa: $empresaDaOperacao)',
      );
      _syncQueue.enqueue(
        SyncOperation(
          type: operationType,
          dataId: data['id']?.toString() ?? 'unknown',
          empresaId: empresaDaOperacao,
          data: {'tabela': table, 'dados': data},
          execute: () async {
            if (operationType == 'DELETE') {
              // Veio da fila: quem cuida das tentativas é a própria fila.
              await _deleteNoSupabase(
                table,
                data['id'] as String,
                enfileirarSeOffline: false,
              );
            } else {
              await _upsertNoSupabase(
                table,
                data,
                empresaId: empresaDaOperacao,
              );
            }
          },
        ),
      );
    } else {
      debugPrint(
        '>>> [Sync] 📋 Sincronização total pendente adicionada à fila',
      );
      _syncQueue.enqueue(
        SyncOperation(
          type: 'retry_sync',
          dataId: empresaDaOperacao,
          empresaId: empresaDaOperacao,
          data: {'msg': 'Sincronização pendente forçada'},
          execute: () async {
            // Aguarda um pouco antes de tentar a sincronização total novamente para evitar loops
            await Future.delayed(const Duration(seconds: 30));
            await _sincronizarComSupabase();
          },
        ),
      );
    }

    // Tentar sincronizar imediatamente se tiver conexão — e a nuvem não
    // estiver marcada como indisponível (evita churn durante a queda).
    if (nuvemHabilitada &&
        SupabaseService.isAvailable &&
        !SupabaseService.instance.servidorIndisponivel) {
      _syncQueue.forceSync().catchError((e) {
        debugPrint('>>> [Sync] ⚠️ Erro ao forçar sincronização: $e');
      });
    }
  }

  /// True se este registro tem uma alteração LOCAL ainda não enviada à nuvem
  /// (operação pendente na fila de sincronização). Enquanto isso, o valor da
  /// nuvem é necessariamente mais antigo para o registro e NÃO pode
  /// sobrescrevê-lo — é o que impede que uma baixa de estoque (ou um DELETE)
  /// feita em um caixa seja apagada/resuscitada por outro PC sincronizando em
  /// paralelo. A própria fila reenvia a versão local; só depois o registro volta
  /// a aceitar o valor da nuvem.
  bool _temEnvioLocalPendente(String tabela, String id) {
    if (id.isEmpty) return false;
    // (1) Envio em curso (janela curta entre gravar local e o upsert terminar).
    final marcadoEm = _enviosLocaisEmCurso[id];
    if (marcadoEm != null) {
      if (DateTime.now().difference(marcadoEm) < _janelaProtecaoEnvioLocal) {
        return true;
      }
      _enviosLocaisEmCurso.remove(id);
    }
    // (2) Envio falhou e ficou na fila persistida.
    return _syncQueue.temPendencia('UPSERT', id) ||
        _syncQueue.temPendencia('INSERT', id) ||
        _syncQueue.temPendencia('UPDATE', id) ||
        _syncQueue.temPendencia('DELETE', id);
  }

  /// Registros com alteração local em curso de envio (id -> quando começou).
  /// Complementa a fila (que só existe depois de uma falha): cobre a janela em
  /// que o upsert ainda está no ar e o valor da nuvem é mais antigo.
  final Map<String, DateTime> _enviosLocaisEmCurso = {};
  static const Duration _janelaProtecaoEnvioLocal = Duration(seconds: 120);

  /// IDs apagados LOCALMENTE há pouco (id -> quando). Serve de "túmulo" em
  /// memória: impede que um snapshot/pull MAIS ANTIGO da nuvem ressuscite o
  /// registro (o upsert atrasado de outro PC que ainda o tinha). Um DELETE
  /// sempre vence o upsert.
  final Map<String, DateTime> _idsRemovidosRecentemente = {};
  static const Duration _janelaTombstone = Duration(minutes: 30);

  /// Túmulo PERSISTIDO na tabela `_exodo_deletados` (alimentada pelo trigger
  /// de DELETE do banco local), carregado no boot/troca de empresa.
  ///
  /// É a correção da lacuna do túmulo "só de memória": ele expirava em 30 min
  /// e morria junto com o app — depois de reiniciar, um upsert atrasado de
  /// outro PC ressuscitava o registro apagado. Este sobrevive ao reinício e só
  /// expira depois de [_janelaTombstonePersistido].
  final Map<String, DateTime> _tombstonesPersistidos = {};
  static const Duration _janelaTombstonePersistido = Duration(days: 90);

  /// Carrega os túmulos da empresa atual do banco local (janela de 90 dias).
  Future<void> carregarTombstonesPersistidos() async {
    if (_currentEmpresaId == null) return;
    try {
      final linhas = await DatabaseService().carregarTombstones(
        _currentEmpresaId!,
        desde: DateTime.now().subtract(_janelaTombstonePersistido),
      );
      _tombstonesPersistidos.clear();
      for (final linha in linhas) {
        final id = linha['registro_id']?.toString();
        if (id == null || id.isEmpty) continue;
        final bruto = linha['deletado_em'];
        final quando = bruto is DateTime
            ? bruto
            : DateTime.tryParse(bruto?.toString() ?? '') ?? DateTime.now();
        _tombstonesPersistidos[id] = quando;
      }
      debugPrint(
        '>>> [DataService] 🪦 ${_tombstonesPersistidos.length} túmulos '
        'carregados (empresa $_currentEmpresaId).',
      );
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Falha ao carregar túmulos: $e');
    }
  }

  bool _foiRemovidoRecentemente(String id) {
    final quando = _idsRemovidosRecentemente[id];
    if (quando != null) {
      if (DateTime.now().difference(quando) > _janelaTombstone) {
        _idsRemovidosRecentemente.remove(id);
      } else {
        return true;
      }
    }
    // Túmulo persistido: vale mesmo depois de reiniciar o app.
    final persistido = _tombstonesPersistidos[id];
    if (persistido == null) return false;
    if (DateTime.now().difference(persistido) > _janelaTombstonePersistido) {
      _tombstonesPersistidos.remove(id);
      return false;
    }
    return true;
  }

  void _marcarRemovidoRecentemente(String id) {
    if (id.isEmpty) return;
    final agora = DateTime.now();
    _idsRemovidosRecentemente[id] = agora;
    // Vale imediatamente mesmo se o app fechar antes do próximo boot (o
    // trigger grava a linha no banco, e esta cópia cobre a janela até lá).
    _tombstonesPersistidos[id] = agora;
    // Limite de memória: descarta os túmulos mais antigos se passar de 5000.
    if (_idsRemovidosRecentemente.length > 5000) {
      final antigos = _idsRemovidosRecentemente.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final excedente = _idsRemovidosRecentemente.length - 5000;
      for (var i = 0; i < excedente; i++) {
        _idsRemovidosRecentemente.remove(antigos[i].key);
      }
    }
    if (_tombstonesPersistidos.length > 5000) {
      final antigos = _tombstonesPersistidos.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final excedente = _tombstonesPersistidos.length - 5000;
      for (var i = 0; i < excedente; i++) {
        _tombstonesPersistidos.remove(antigos[i].key);
      }
    }
  }

  /// Remove de um snapshot da nuvem os registros cujo id foi apagado aqui há
  /// pouco — impede que um pull mais antigo os ressuscite.
  void _descartarDeletadosRecentes(Map<String, dynamic> dados) {
    if (_idsRemovidosRecentemente.isEmpty && _tombstonesPersistidos.isEmpty) {
      return;
    }
    for (final chave in dados.keys.toList()) {
      final lista = dados[chave];
      if (lista is! List) continue;
      final filtrada = lista.where((item) {
        if (item is! Map) return true;
        final id = item['id']?.toString();
        return id == null || !_foiRemovidoRecentemente(id);
      }).toList();
      if (filtrada.length != lista.length) {
        debugPrint(
          '>>> [Sync] 🪦 ${lista.length - filtrada.length} registro(s) de '
          '$chave ignorados no pull: apagados localmente.',
        );
        dados[chave] = filtrada;
      }
    }
  }

  /// Resolve operações que foram carregadas do Banco 2 (PostgreSQL)
  Future<void> _resolverOperacaoSync(
    String type,
    String dataId,
    Map<String, dynamic> data,
  ) async {
    debugPrint(
      '>>> [Sync] 🔎 Resolvendo operação persistente: $type (ID: $dataId)',
    );

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
      debugPrint(
        '>>> [DataService] ⏳ Salvamento já em andamento. Agendando nova execução após término.',
      );
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
    debugPrint(
      '>>> [DataService] 🏃 salvarImediatamente() chamado. Dirty: $_dirtyCollections',
    );
    if (!_persistenciaHabilitada) {
      debugPrint(
        '>>> [DataService] 🛑 Persistência desabilitada. Abortando salvarImediatamente.',
      );
      return;
    }

    // Cancelar qualquer salvamento agendado
    _debounceSalvamento?.cancel();

    if (_salvandoDados) {
      debugPrint(
        '>>> [DataService] ⏳ Já existe um salvamento em curso, aguardando...',
      );
      // Se já está salvando, aguardar um pouco
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _salvandoDados = true;
    try {
      // OTIMIZAÇÃO: Não forçar sincronização total do Supabase aqui.
      // Os métodos CRUD individuais já fazem o push de seus próprios dados.
      // salvarImediatamente() agora foca em garantir a persistência LOCAL (Storage).
      await _salvarTodosDados(aguardarSupabase: false);
      debugPrint(
        '>>> [DataService] ✅ salvarImediatamente concluído com sucesso (foco LocalStorage).',
      );
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
    // `ehNFe` (e não `modelo == 55`) porque o modelo também é lido da chave de
    // acesso: quem chama sem preencher `modelo` gravava DANFE na lista e na
    // tabela de NFC-e, e ela aparecia no histórico de NFC-e.
    final isNfe = nfce.ehNFe;
    if (isNfe) {
      _nfes.add(nfce);
    } else {
      _nfces.add(nfce);
    }

    // Atualizar o contador de último número da empresa se for maior E se a nota foi autorizada ou cancelada.
    // O contador global (ultimo_numero_nfce) representa a SÉRIE 1 — notas de
    // séries adicionais (2, 3...) têm numeração própria e NÃO devem alterá-lo,
    // senão a série 2 puxaria a numeração da série 1 (ou vice-versa).
    final asSucesso = [
      'autorizada',
      'sucesso',
      'cancelada',
    ].contains(nfce.status?.toLowerCase());
    final serieNota = (nfce.serie ?? '').trim().isEmpty
        ? '1'
        : nfce.serie!.trim();
    if (asSucesso &&
        serieNota == '1' &&
        nfce.numero.isNotEmpty &&
        empresaAtual != null) {
      final nfceNumInt = int.tryParse(nfce.numero) ?? 0;
      final configKey = isNfe ? 'ultimo_numero_nfe' : 'ultimo_numero_nfce';
      final ultimoNum =
          int.tryParse(
            empresaAtual!.configuracoes?[configKey]?.toString() ?? '0',
          ) ??
          0;

      if (nfceNumInt > ultimoNum) {
        final novasConfigs = Map<String, dynamic>.from(
          empresaAtual!.configuracoes ?? {},
        );
        novasConfigs[configKey] = nfceNumInt.toString();

        final empresaAtualizada = empresaAtual!.copyWith(
          configuracoes: novasConfigs,
          updatedAt: DateTime.now(),
        );

        // Atualiza localmente
        setEmpresaAtual(empresaAtualizada);

        // Salvar no Supabase também
        await _upsertNoSupabase(
          SupabaseService.tableEmpresas,
          empresaAtualizada.toMap(),
        );
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
    final isNfe = nfce.ehNFe;
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
    final asSucesso = [
      'autorizada',
      'sucesso',
      'cancelada',
    ].contains(nfce.status?.toLowerCase());
    final serieNota = (nfce.serie ?? '').trim().isEmpty
        ? '1'
        : nfce.serie!.trim();
    if (asSucesso &&
        serieNota == '1' &&
        nfce.numero.isNotEmpty &&
        empresaAtual != null) {
      final nfceNumInt = int.tryParse(nfce.numero) ?? 0;
      final configKey = isNfe ? 'ultimo_numero_nfe' : 'ultimo_numero_nfce';
      final ultimoNum =
          int.tryParse(
            empresaAtual!.configuracoes?[configKey]?.toString() ?? '0',
          ) ??
          0;

      if (nfceNumInt > ultimoNum) {
        final novasConfigs = Map<String, dynamic>.from(
          empresaAtual!.configuracoes ?? {},
        );
        novasConfigs[configKey] = nfceNumInt.toString();

        final empresaAtualizada = empresaAtual!.copyWith(
          configuracoes: novasConfigs,
          updatedAt: DateTime.now(),
        );

        // Atualiza localmente
        setEmpresaAtual(empresaAtualizada);

        // Salvar no Supabase também
        await _upsertNoSupabase(
          SupabaseService.tableEmpresas,
          empresaAtualizada.toMap(),
        );
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
      await _deleteNoSupabase(SupabaseService.tableNFCes, id);
      await _deleteNoSupabase(SupabaseService.tableNFEs, id);
    } catch (e) {
      debugPrint('>>> [NF] ⚠️ Falha ao remover nota do Supabase: $e');
    }
    // Remover também do PostgreSQL local.
    //
    // `_salvarTodosDados` só faz UPSERT nas tabelas locais: o registro saía da
    // lista em memória, mas continuava na tabela. No próximo carregamento o
    // rascunho voltava para a lista — por isso a nota emitida (autorizada)
    // reaparecia como "Pendente" depois de um tempo.
    if (!kIsWeb) {
      try {
        await DatabaseService().removerItemPostgres(
          LocalStorageService.keyNFCes,
          id,
          _currentEmpresaId,
        );
        await DatabaseService().removerItemPostgres(
          LocalStorageService.keyNFEs,
          id,
          _currentEmpresaId,
        );
      } catch (e) {
        debugPrint('>>> [NF] ⚠️ Falha ao remover nota do PostgreSQL local: $e');
      }
    }
  }

  /// Descarta os rascunhos `pend-<millis>` que já viraram nota emitida.
  ///
  /// O fluxo de emissão grava um rascunho (`id` começando com `pend-`) antes de
  /// falar com a SEFAZ e o apaga quando a nota é autorizada. Como o `DELETE`
  /// nunca chegava ao PostgreSQL local, o rascunho voltava para a lista a cada
  /// carregamento/sincronização: a mesma nota aparecia duas vezes, uma
  /// autorizada e outra "Pendente".
  ///
  /// Só descarta o rascunho quando existe outra nota com o MESMO número e série
  /// já autorizada/cancelada — numeração fiscal não se repete, então isso nunca
  /// remove um rascunho legítimo (os rascunhos salvos por "Gravar Nota" não usam
  /// o prefixo `pend-`).
  Future<void> _limparRascunhosPendentesOrfaos() async {
    const statusEmitidos = ['autorizada', 'sucesso', 'cancelada'];
    final orfaos = <NFCe>[];

    for (final rascunho in [..._nfces, ..._nfes]) {
      if (!rascunho.id.startsWith('pend-')) continue;
      final statusRascunho = rascunho.status?.toLowerCase() ?? '';
      if (statusRascunho != 'pendente' && statusRascunho != 'rejeitada')
        continue;

      final jaEmitida = [..._nfces, ..._nfes].any(
        (outra) =>
            outra.id != rascunho.id &&
            outra.numero == rascunho.numero &&
            (outra.serie ?? '') == (rascunho.serie ?? '') &&
            statusEmitidos.contains(outra.status?.toLowerCase()),
      );

      if (jaEmitida) orfaos.add(rascunho);
    }

    if (orfaos.isEmpty) return;

    debugPrint(
      '>>> [NF] 🧹 Removendo ${orfaos.length} rascunho(s) pendente(s) já emitido(s): ' +
          orfaos.map((o) => '${o.id}(Nº ${o.numero})').join(', '),
    );
    for (final orfao in orfaos) {
      await removerNFCe(orfao.id);
    }
  }

  /// Obtém uma NFC-e ou NF-e por ID
  NFCe? obterNFCe(String id) {
    try {
      return _nfces.firstWhere(
        (n) => n.id == id,
        orElse: () => _nfes.firstWhere((n) => n.id == id),
      );
    } catch (e) {
      return null;
    }
  }

  /// Obtém NFC-e ou NF-e por chave de acesso
  NFCe? obterNFCePorChave(String chaveAcesso) {
    try {
      return _nfces.firstWhere(
        (n) => n.chaveAcesso == chaveAcesso,
        orElse: () => _nfes.firstWhere((n) => n.chaveAcesso == chaveAcesso),
      );
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
      throw Exception(
        '⚠️ PROTEÇÃO: deletarTodosDadosOperacionais requer confirmação explícita (confirmar: true)',
      );
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
      print(
        '>>> 🛡️ PROTEÇÃO: Criando backup completo antes de deletar dados...',
      );
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      try {
        // Backup de todos os dados críticos
        await _storage.salvarLista(
          'backup_produtos_${empresaId}_$timestamp',
          _produtos.map((p) => p.toMap()).toList(),
        );
        await _storage.salvarLista(
          'backup_pedidos_${empresaId}_$timestamp',
          _pedidos.map((p) => p.toMap()).toList(),
        );
        await _storage.salvarLista(
          'backup_vendas_${empresaId}_$timestamp',
          _vendasBalcao.map((v) => v.toMap()).toList(),
        );
        await _storage.salvarLista(
          'backup_servicos_${empresaId}_$timestamp',
          _tiposServico.map((s) => s.toMap()).toList(),
        );
        await _storage.salvarLista(
          'backup_ordens_${empresaId}_$timestamp',
          _ordensServico.map((o) => o.toMap()).toList(),
        );
        await _storage.salvarLista(
          'backup_entregas_${empresaId}_$timestamp',
          _entregas.map((e) => e.toMap()).toList(),
        );
        await _storage.salvarLista(
          'backup_agendamentos_${empresaId}_$timestamp',
          _agendamentosServico.map((a) => a.toMap()).toList(),
        );
        await _storage.salvarLista(
          'backup_contas_pagar_${empresaId}_$timestamp',
          _contasPagar.map((c) => c.toMap()).toList(),
        );
        await _storage.salvarLista(
          'backup_notas_entrada_${empresaId}_$timestamp',
          _notasEntrada.map((n) => n.toMap()).toList(),
        );
        await _storage.salvarLista(
          'backup_clientes_${empresaId}_$timestamp',
          _clientes.map((c) => c.toMap()).toList(),
        );

        print('>>> ✅ Backup completo criado com timestamp: $timestamp');
        print('>>> ✅ Chaves de backup: backup_*_${empresaId}_$timestamp');
      } catch (e) {
        print(
          '>>> ❌ ERRO CRÍTICO: Não foi possível criar backup! Operação cancelada.',
        );
        print('>>> Erro: $e');
        throw Exception(
          '⚠️ PROTEÇÃO: Não foi possível criar backup. Operação cancelada para evitar perda de dados.',
        );
      }

      // Log de auditoria
      print(
        '>>> 📋 AUDITORIA: Deletando dados operacionais da empresa $empresaId',
      );
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
      _ajustesEstoqueLote.clear();
      _lotesProdutos.clear();
      _aberturasCaixa.clear();
      _fechamentosCaixa.clear();
      _sangrias.clear();
      _suprimentos.clear();
      _notasEntrada.clear();
      _pedidosCompra.clear();
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
      if (nuvemHabilitada && SupabaseService.isAvailable) {
        try {
          final filter = {'empresa_id': empresaId};
          await _supabaseService.deleteFiltered(
            SupabaseService.tableProdutos,
            filter,
          );
          await _supabaseService.deleteFiltered(
            SupabaseService.tablePedidos,
            filter,
          );
          await _supabaseService.deleteFiltered(
            SupabaseService.tableVendasBalcao,
            filter,
          );
          await _supabaseService.deleteFiltered(
            SupabaseService.tableServicos,
            filter,
          );
          await _supabaseService.deleteFiltered(
            SupabaseService.tableClientes,
            filter,
          );
          await _supabaseService.deleteFiltered(
            SupabaseService.tableAgendamentosServico,
            filter,
          );
          await _supabaseService.deleteFiltered(
            SupabaseService.tableNFCes,
            filter,
          );
          await _supabaseService.deleteFiltered(
            SupabaseService.tableNFEs,
            filter,
          );
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
      print(
        '>>> ⚠️ IMPORTANTE: A empresa NÃO foi deletada, apenas os dados operacionais',
      );
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
    await enviarMudancaParaSupabase(
      SupabaseService.tableMesasComandas,
      mesaComanda.toMap(),
    );
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
      await enviarMudancaParaSupabase(
        SupabaseService.tableMesasComandas,
        mesaComanda.toMap(),
      );
    }
  }

  /// Remove uma mesa ou comanda
  Future<void> deleteMesaComanda(String id) async {
    debugPrint('>>> [DataService] 🗑️ Iniciando deleção da Mesa/Comanda: $id');
    debugPrint(
      '>>> [DataService] 🔍 Estado ATUAL antes da deleção: ${_mesasComandas.length} mesas na lista.',
    );

    // Adicionar ao Set de supressão recente (evita que o Supabase a restaure por latência)
    _idsMesaRemovidosRecentemente.add(id);
    // Remover do Set após 2 minutos (tempo suficiente para o Firestore propagar a deleção mundialmente)
    Future.delayed(const Duration(minutes: 2), () {
      _idsMesaRemovidosRecentemente.remove(id);
      debugPrint(
        '>>> [DataService] 🧹 ID $id removido do Set de supressão recente',
      );
    });

    // Primeiro marcamos como Fechada localmente para que o Getter filtre IMEDIATAMENTE
    final index = _mesasComandas.indexWhere((m) => m.id == id);
    if (index != -1) {
      _mesasComandas[index] = _mesasComandas[index].copyWith(status: 'Fechada');
    }
    notifyListeners();

    // Removemos da lista local (permanente)
    _mesasComandas.removeWhere((m) => m.id == id);

    // Exclusão REAL no banco local: sem isso a mesa/comanda apagada voltava
    // no próximo boot (a linha continuava no PostgreSQL local e o snapshot do
    // banco substituía a memória).
    _removerLinhaLocal(LocalStorageService.keyMesasComandas, id);

    // MARCAR COMO SUJO para garantir que o salvamento em background ocorra
    _marcarSujo(LocalStorageService.keyMesasComandas);
    // Deleção persistida via background para evitar travamentos.

    // Enviar mudança para Supabase automaticamente (sincronização bidirecional)
    await enviarMudancaParaSupabase(SupabaseService.tableMesasComandas, {
      'id': id,
    }, evento: 'DELETE');
  }

  /// Marca uma mesa/comanda como DELETADA mantendo o registro no Histórico de Operações.
  /// Diferente de [deleteMesaComanda] (que remove fisicamente), aqui o registro permanece
  /// no sistema com status 'Deletada' para fins de auditoria: quem deletou e quando.
  Future<void> marcarMesaComandaDeletada(String id, {String? usuario}) async {
    final index = _mesasComandas.indexWhere((m) => m.id == id);
    if (index == -1) {
      debugPrint(
        '>>> [DataService] 🗑️ Mesa/Comanda não encontrada para marcar como deletada: $id',
      );
      return;
    }

    final atual = _mesasComandas[index];
    if (atual.status == 'Deletada') {
      debugPrint(
        '>>> [DataService] ⚠️ Mesa/Comanda $id já está marcada como Deletada',
      );
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

    debugPrint(
      '>>> [DataService] 🗑️ Mesa/Comanda ${atual.numero} marcada como DELETADA por $usuario',
    );

    // Sincronizar com Supabase (mantém o registro para o histórico em todos os dispositivos)
    await enviarMudancaParaSupabase(
      SupabaseService.tableMesasComandas,
      deletada.toMap(),
    );

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
      debugPrint(
        '>>> [DataService] 🗑️ Comanda vinculada ${cAtual.numero} também marcada como DELETADA',
      );
      await enviarMudancaParaSupabase(
        SupabaseService.tableMesasComandas,
        cDeletada.toMap(),
      );
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
    debugPrint(
      '>>> [LimparMesa] Pagamentos registrados: ${mesa.historicoPagamentos.length}',
    );
    debugPrint('>>> [LimparMesa] Couvert: ${mesa.valorCouvertCalculado}');

    // Converter itens para Pedido
    final produtos = <ItemPedido>[];
    final servicos = <ItemServico>[];

    for (final item in mesa.itens) {
      if (item.status == StatusItem.cancelado) continue;

      if (item.isServico) {
        servicos.add(
          ItemServico(
            id: item.itemId,
            descricao: item.nome,
            valor: item.preco,
            valorAdicional: 0.0,
          ),
        );
      } else {
        produtos.add(
          ItemPedido(
            id: item.itemId,
            nome: item.nome,
            quantidade: item.quantidade,
            preco: item.preco,
          ),
        );
      }
    }

    // Criar ID ÚNICO para o histórico (será usado tanto no Pedido quanto na VendaBalcao para merge correto)
    final idHistorico = uuid.v4();
    final bool isComanda =
        mesa.tipo == TipoControle.comanda ||
        mesa.numero.toUpperCase().contains('CMD') ||
        mesa.numero.toUpperCase().contains('COMANDA');

    // FORÇAR PREFIXOS PADRONIZADOS PARA O HISTÓRICO
    final String prefixo = isComanda ? 'CMD' : 'MESA';
    final String labelOrigem = isComanda ? '[COMANDA]' : '[MESA]';

    // Observação unificada para identificação infalível no histórico
    final String tagIdentificacao =
        '[VIP-MC] originado de $labelOrigem ${mesa.numero}';

    // Se for Comanda, garantir que o número tenha o prefixo CMD (Identificação Garantida)
    // Evitar prefixo duplo se mesa.numero já contém CMD-
    final String baseLimpa = mesa.numero
        .toUpperCase()
        .replaceAll('CMD-', '')
        .replaceAll('MESA-', '')
        .replaceAll('COMANDA-', '')
        .trim();

    final String numeroHistorico =
        '$prefixo-$baseLimpa-${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}';

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
      } else if (f.contains('crédito') ||
          f.contains('credito') ||
          f.contains('cart')) {
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
    final itensHistorico = mesa.itens
        .where((i) => i.status != StatusItem.cancelado)
        .map(
          (i) => ItemVendaBalcao(
            id: i.itemId,
            nome: i.nome,
            precoUnitario: i.preco,
            quantidade: i.quantidade.toDouble(),
            isServico: i.isServico,
            adicionais: i.adicionais,
          ),
        )
        .toList();

    // Adicionar Couvert se houver valor
    if (mesa.valorCouvertCalculado > 0) {
      itensHistorico.add(
        ItemVendaBalcao(
          id: 'couvert-${idHistorico}',
          nome: 'Couvert Artístico (${mesa.quantidadePessoasCouvert ?? 1}x)',
          precoUnitario: mesa.valorCouvertCalculado,
          quantidade: 1.0,
          isServico: true,
        ),
      );
    }

    // Adicionar Taxa de Serviço se houver valor
    if (mesa.valorTaxaServicoCalculado > 0) {
      itensHistorico.add(
        ItemVendaBalcao(
          id: 'taxa-servico-${idHistorico}',
          nome: 'Taxa de Serviço (Geral)',
          precoUnitario: mesa.valorTaxaServicoCalculado,
          quantidade: 1.0,
          isServico: true,
        ),
      );
    }

    // Salvar como VendaBalcao (Venda Direta) para aparecer no histórico unificado
    final vendaHistorico = VendaBalcao(
      id: idHistorico, // MESMO ID para facilitar o merge no Histórico
      numero: novoPedido.numero,
      dataVenda: DateTime.now(),
      clienteId: mesa.clienteId,
      clienteNome: novoPedido.clienteNome,
      itens: itensHistorico,
      tipoPagamento: pagamentosHistorico.isNotEmpty
          ? pagamentosHistorico.first.tipo
          : TipoPagamento.outro,
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

  /// Atualiza o status de um item de mesa/comanda
  Future<void> atualizarStatusItemMesaComanda(
    String mesaComandaId,
    String itemId,
    StatusItem novoStatus, {
    String? usuarioModificou,
    String? acaoRealizada,
  }) async {
    debugPrint('>>> [DataService] atualizarStatusItemMesaComanda: mesa=$mesaComandaId item=$itemId novoStatus=$novoStatus');
    final mesaComanda = _mesasComandas.firstWhere(
      (m) => m.id == mesaComandaId,
      orElse: () => throw Exception('Mesa/Comanda não encontrada: $mesaComandaId (total: ${_mesasComandas.length})'),
    );
    debugPrint('>>> [DataService] Mesa encontrada: ${mesaComanda.numero}, itens: ${mesaComanda.itens.length}');

    final itemIndex = mesaComanda.itens.indexWhere((i) => i.id == itemId);
    if (itemIndex == -1) {
      debugPrint('>>> [DataService] Itens na mesa: ${mesaComanda.itens.map((i) => '${i.nome}(${i.id})').join(', ')}');
      throw Exception('Item não encontrado: $itemId na mesa ${mesaComanda.numero} (${mesaComanda.itens.length} itens)');
    }
    debugPrint('>>> [DataService] Item encontrado no índice $itemIndex: ${mesaComanda.itens[itemIndex].nome}');

    final acao = acaoRealizada ?? _getAcaoPorStatus(novoStatus);
    final itemAtualizado = mesaComanda.itens[itemIndex].copyWith(
      status: novoStatus,
      dataHoraPronto: novoStatus == StatusItem.pronto
          ? DateTime.now()
          : mesaComanda.itens[itemIndex].dataHoraPronto,
      usuarioModificou: usuarioModificou,
      dataModificacao: DateTime.now(),
      acaoRealizada: acao,
    );

    final itensAtualizados = List<ItemMesaComanda>.from(mesaComanda.itens);
    itensAtualizados[itemIndex] = itemAtualizado;

    // Usar copyWith para preservar TODOS os campos, incluindo couvert, garçom, pagamentos, etc.
    // Recalcular total com base nos itens atualizados
    final mesaComTemp = mesaComanda.copyWith(
      itens: itensAtualizados,
    );
    final mesaComandaAtualizada = mesaComanda.copyWith(
      itens: itensAtualizados,
      total: mesaComTemp.totalCalculado,
      updatedAt: DateTime.now(),
      usuarioModificou: usuarioModificou,
    );

    debugPrint('>>> [DataService] Atualizando mesa ${mesaComanda.numero} com item ${mesaComanda.itens[itemIndex].nome} -> status $novoStatus');
    await updateMesaComanda(mesaComandaAtualizada);
    debugPrint('>>> [DataService] Mesa atualizada com sucesso');
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
        orElse: () =>
            throw Exception('Produto não encontrado: ${itemPedido.id}'),
      );

      itens.add(
        ItemMesaComanda(
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
        ),
      );
    }

    // Adicionar serviços do pedido
    for (final itemServico in pedido.servicos) {
      // ItemServico tem: id, descricao, valor, valorAdicional, etc.
      // O id do ItemServico é o id do serviço
      final servico = _tiposServico.firstWhere(
        (s) => s.id == itemServico.id,
        orElse: () =>
            throw Exception('Serviço não encontrado: ${itemServico.id}'),
      );

      itens.add(
        ItemMesaComanda(
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
        ),
      );
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
    if (_carregandoMaisClientes ||
        !_temMaisClientes ||
        _currentEmpresaId == null)
      return;

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
        debugPrint(
          '>>> [Sync] ✓ Fim da lista de clientes atingido no Supabase',
        );
      } else {
        final novosClientes = result
            .map((map) => Cliente.fromMap(map))
            .toList();

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
        _clientes.sort(
          (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
        );

        debugPrint(
          '>>> [Sync] ✓ Mais $contagemNovos clientes carregados do Supabase (Total: ${_clientes.length})',
        );

        if (result.length < 50) {
          _temMaisClientes = false;
        }
      }
    } catch (e) {
      debugPrint(
        '>>> [DataService] Erro ao carregar mais clientes do Supabase: $e',
      );
    } finally {
      _carregandoMaisClientes = false;
      notifyListeners();
    }
  }

  bool get temMaisVendas => _temMaisVendas;
  bool get carregandoMaisVendas => _carregandoMaisVendas;

  /// Carrega a próxima página de vendas (50 por vez)
  Future<void> carregarMaisVendas() async {
    if (_carregandoMaisVendas || !_temMaisVendas || _currentEmpresaId == null)
      return;

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
        final novasVendas = result
            .map((map) => VendaBalcao.fromMap(map))
            .toList();

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

        debugPrint(
          '>>> [Sync] ✓ Mais $contagemNovas vendas carregadas do Supabase (Total: ${_vendasBalcao.length})',
        );

        if (result.length < 50) {
          _temMaisVendas = false;
        }
      }
    } catch (e) {
      debugPrint(
        '>>> [DataService] Erro ao carregar mais vendas do Supabase: $e',
      );
    } finally {
      _carregandoMaisVendas = false;
      notifyListeners();
    }
  }

  /// Sincroniza notas fiscais com o Google Drive de forma automática e silenciosa
  Future<void> _sincronizarNotasComDrive() async {
    if (_empresaAtual == null) return;

    // Evitar múltiplas execuções simultâneas
    if (_syncDriveEmAndamento) return;
    _syncDriveEmAndamento = true;

    try {
      debugPrint(
        '>>> [SyncDrive] ☁️ Iniciando sincronização automática com Drive...',
      );
      final driveService = GoogleDriveService.instance;

      // Só tenta se estiver logado ou puder logar silenciosamente
      if (driveService.driveApi == null) {
        final ok = await driveService.login(silencioso: true);
        if (!ok) {
          debugPrint(
            '>>> [SyncDrive] ⏭️ Sincronização Drive pulada: Usuário não logado no Google',
          );
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
        debugPrint(
          '>>> [SyncDrive] 📄 Processando ${nfcesExportar.length} NFC-es para o Drive...',
        );
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
        debugPrint(
          '>>> [SyncDrive] 📦 Processando ${entradasExportar.length} Notas de Entrada para o Drive...',
        );
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
      debugPrint(
        '>>> [SyncDrive] ✅ Sincronização automática com Drive concluída.',
      );
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
  void _upsertAgendamentoLocal(
    AgendamentoServico agendamento, {
    bool prioritario = false,
  }) {
    // ⚠️ Ignorar upsert de agendamentos criados localmente há <10s.
    // O REALTIME pode disparar INSERT de volta ao mesmo PC antes da UI atualizar.
    if (_agendamentosCriadosLocalmente.containsKey(agendamento.id)) {
      final criadoEm = _agendamentosCriadosLocalmente[agendamento.id]!;
      if (DateTime.now().difference(criadoEm).inSeconds < 10) {
        return; // Não sobrescrever versão local
      }
      _agendamentosCriadosLocalmente.remove(agendamento.id);
    }

    final index = _agendamentosServico.indexWhere(
      (a) => a.id == agendamento.id,
    );
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
    final empresaId = _currentEmpresaId;
    if (empresaId == null || empresaId.isEmpty) {
      return 'empresa_desconhecida_$baseKey';
    }
    return 'empresa_${empresaId}_$baseKey';
  }

  /// Helper: sanitiza dados de produto para o schema do Supabase
  /// Remove todas as colunas que existem local mas NÃO existem na nuvem.
  static Map<String, dynamic> _sanitizeProdutoForSupabase(
    Map<String, dynamic> map,
  ) {
    // Colunas são filtradas automaticamente no upsertBatch via OpenAPI
    // (colunas que não existem no Supabase são descartadas, e as que existem
    // — inclusive formas_venda, promocoes, variacoes, adicionais, icms_aliquota
    // etc. — são PRESERVADAS, ao contrário das listas hardcoded antigas que
    // apagavam dados reais).
    return map;
  }

  /// Helper: sanitiza dados de pedido para o schema do Supabase
  static Map<String, dynamic> _sanitizePedidoForSupabase(
    Map<String, dynamic> map,
  ) {
    // Filtragem automática via OpenAPI no upsertBatch (preserva colunas reais
    // como numero, cliente_telefone, pagamentos, produtos, delivery_info etc.).
    return map;
  }

  /// Helper: sanitiza dados de venda_balcao para o schema do Supabase
  static Map<String, dynamic> _sanitizeVendaBalcaoForSupabase(
    Map<String, dynamic> map,
  ) {
    // Filtragem automática via OpenAPI no upsertBatch. numero e numero_venda
    // são preservados (a unique constraint exige numero_venda).
    return map;
  }

  /// Helper: sanitiza dados de mesa_comanda para o schema do Supabase
  static Map<String, dynamic> _sanitizeMesaComandaForSupabase(
    Map<String, dynamic> map,
  ) {
    // Filtragem automática via OpenAPI no upsertBatch.
    return map;
  }

  /// Helper: sanitiza dados de empresa para o schema do Supabase
  static Map<String, dynamic> _sanitizeEmpresaForSupabase(
    Map<String, dynamic> map,
  ) {
    // Filtragem automática via OpenAPI no upsertBatch.
    return map;
  }

  /// Helper: sanitiza dados de entrega para o schema do Supabase
  static Map<String, dynamic> _sanitizeEntregaForSupabase(
    Map<String, dynamic> map,
  ) {
    // Filtragem automática via OpenAPI no upsertBatch.
    return map;
  }

  /// Mapeia snake_case → camelCase para tabelas de caixa (compatibilidade com schema Supabase)
  static Map<String, dynamic> _sanitizeCaixaForSupabase(
    String table,
    Map<String, dynamic> map,
  ) {
    if (table == 'aberturas_caixa') {
      if (map.containsKey('data_abertura'))
        map['dataAbertura'] = map.remove('data_abertura');
      if (map.containsKey('valor_inicial'))
        map['valorInicial'] = map.remove('valor_inicial');
      if (map.containsKey('created_at'))
        map['createdAt'] = map.remove('created_at');
      if (map.containsKey('updated_at'))
        map['updatedAt'] = map.remove('updated_at');
    } else if (table == 'fechamentos_caixa') {
      if (map.containsKey('abertura_caixa_id'))
        map['aberturaCaixaId'] = map['abertura_caixa_id'];
      if (map.containsKey('data_fechamento'))
        map['dataFechamento'] = map['data_fechamento'];
      if (map.containsKey('valor_esperado'))
        map['valorEsperado'] = map.remove('valor_esperado');
      if (map.containsKey('valor_real'))
        map['valorReal'] = map.remove('valor_real');
      if (map.containsKey('created_at')) map['createdAt'] = map['created_at'];
      if (map.containsKey('updated_at')) map['updatedAt'] = map['updated_at'];
    }
    return map;
  }

  /// Sanitiza um mapa de dados de acordo com a tabela de destino no Supabase.
  /// Retorna o mapa sanitizado (mutável) — não modifica o objeto original.
  static Map<String, dynamic> _sanitizeForSupabase(
    String table,
    Map<String, dynamic> map,
  ) {
    final m = Map<String, dynamic>.from(map);
    m['empresa_id'] = map['empresa_id']; // Preservar empresa_id

    // REMOÇÃO GLOBAL: colunas internas do app que NÃO existem no Supabase
    // (adicionadas pelo sincronizador local/outbox em TODAS as tabelas)
    m.remove('sync');
    m.remove('sync_status');
    m.remove('sync_data');
    m.remove('sync_erro');
    m.remove('sync_tentativas');
    m.remove('exodo_sync');

    // Colunas específicas que não existem no Supabase são tratadas
    // AUTOMATICAMENTE no upsertBatch (OpenAPI): chaves ausentes são
    // descartadas e versões camelCase/snake_case equivalentes são renomeadas
    // preservando o dado (ex: tem_acesso -> temAcesso). As listas hardcoded
    // antigas foram removidas porque apagavam colunas que EXISTEM no Supabase
    // (data_emissao, vendedor_id, pagamentos, formas_venda, etc.).

    switch (table) {
      case 'produtos':
        return _sanitizeProdutoForSupabase(m);
      case 'pedidos':
        return _sanitizePedidoForSupabase(m);
      case 'vendas_balcao':
        return _sanitizeVendaBalcaoForSupabase(m);
      case 'mesas_comandas':
        return _sanitizeMesaComandaForSupabase(m);
      case 'empresas':
        return _sanitizeEmpresaForSupabase(m);
      case 'entregas':
        return _sanitizeEntregaForSupabase(m);
      case 'aberturas_caixa':
      case 'fechamentos_caixa':
        return _sanitizeCaixaForSupabase(table, m);
      default:
        return m;
    }
  }

  /// ================================================================
  /// MIGRAÇÃO COMPLETA: Local → Nuvem (backup de todos os dados)
  /// ================================================================
  /// Envia TODAS as tabelas do banco local para o Supabase.
  /// Use quando:
  ///  - A nuvem foi apagada/acidentalmente limpa
  ///  - Você quer forçar o sync completo para a nuvem
  ///  - Troubleshooting de dados inconsistentes entre máquinas
  ///
  /// Retornos: (sucesso, tabelaComErro, mensagemErro)
  Future<(bool, String?, String?)> migrarTabelasLocalParaNuvem() async {
    if (_currentEmpresaId == null) {
      return (false, null, 'Empresa não definida');
    }
    if (!nuvemHabilitada) {
      return (false, null, 'Nuvem desativada para esta empresa.');
    }

    _isLoading = true;
    _mensagemLoading = 'Migrando dados locais para a nuvem...';
    notifyListeners();

    final tabelaErro = ValueNotifier<String?>(null);
    final msgErro = ValueNotifier<String?>(null);

    try {
      debugPrint(
        '>>> [Migrate] 📤 Iniciando migração Local → Nuvem para empresa $_currentEmpresaId',
      );
      addSyncLog('📤 Iniciando migração completa Local → Nuvem...');

      // PASSO 1: Verificar e criar tabelas ausentes na NUVEM automaticamente (OPCIONAL)
      // A nuvem é o Neon (Data API); o Supabase fica como segunda opção. Se
      // nenhum dos dois estiver configurado, a criação automática é pulada —
      // a migração continua e pula tabelas que não existem.
      debugPrint(
        '>>> [Migrate] 🔍 Verificando tabelas na nuvem antes da migração...',
      );
      addSyncLog('🔍 Verificando tabelas na nuvem (Neon)...');
      try {
        if (EnvConfig.neonDisponivel || EnvConfig.supabaseDbAvailable) {
          final (ok, logs) = await _supabaseService.criarTabelasNoSupabase();
          if (ok) {
            debugPrint('>>> [Migrate] ✅ Verificação de tabelas concluída');
            for (final log in logs) {
              debugPrint('>>> [Migrate]    $log');
            }
          } else {
            debugPrint(
              '>>> [Migrate] ⚠️ Não foi possível verificar tabelas automaticamente: ${logs.join(', ')}',
            );
          }
        } else {
          debugPrint(
            '>>> [Migrate] ℹ️ Nuvem não configurada — criação automática de tabelas desabilitada',
          );
          addSyncLog(
            'ℹ️ Criação automática de tabelas desabilitada (preencha o .env.neon; o Supabase, reserva, usa SUPABASE_DB_HOST/PASSWORD)',
          );
        }
      } catch (e) {
        debugPrint(
          '>>> [Migrate] ⚠️ Erro ao verificar tabelas: $e (continuando migração...)',
        );
      }

      // Função auxiliar: envia uma lista para uma tabela, sanitizada
      Future<bool> enviarTabela(
        String tabela,
        List<Map<String, dynamic>> dados,
      ) async {
        if (dados.isEmpty) return true;
        debugPrint(
          '>>> [Migrate] 📦 Enviando ${dados.length} registros para $tabela...',
        );

        // Conjunto de colunas problemáticas para esta tabela (será populado em caso de erro)
        final Set<String> colunasProblematicas = {};

        const batchSize = 200;
        for (int i = 0; i < dados.length; i += batchSize) {
          final batch = dados.sublist(
            i,
            (i + batchSize).clamp(0, dados.length),
          );

          // Função local para sanitizar removendo colunas problemáticas conhecidas
          Map<String, dynamic> sanitizar(Map<String, dynamic> d) {
            d['empresa_id'] = _currentEmpresaId;
            d['updated_at'] = DateTime.now().toUtc().toIso8601String();
            final sanitizado = _sanitizeForSupabase(tabela, d);
            // Remover colunas que já sabemos que causam erro
            for (final col in colunasProblematicas) {
              sanitizado.remove(col);
            }
            return sanitizado;
          }

          final sanitizados = batch.map(sanitizar).toList();
          try {
            await _supabaseService.upsertBatch(tabela, sanitizados);
            debugPrint(
              '>>> [Migrate] ✅ $tabela: lote ${(i ~/ batchSize) + 1} OK (${batch.length} registros)',
            );
          } catch (e) {
            final errStr = e.toString();
            debugPrint(
              '>>> [Migrate] ❌ Erro ao enviar $tabela (lote ${(i ~/ batchSize) + 1}): $e',
            );

            // Tentar extrair nome da coluna problemática do erro
            String? colunaProblematica;
            final RegExp regColuna = RegExp(
              r"column '([^']+)' doesn't exist",
              caseSensitive: false,
            );
            final matchColuna = regColuna.firstMatch(errStr);
            if (matchColuna != null) {
              colunaProblematica = matchColuna.group(1);
            } else if (errStr.contains("Could not find the column '")) {
              // Extrair entre aspas simples após "column "
              final idxStart =
                  errStr.indexOf("Could not find the column '") + 26;
              final idxEnd = errStr.indexOf("'", idxStart);
              if (idxEnd > idxStart) {
                colunaProblematica = errStr.substring(idxStart, idxEnd);
              }
            }

            // Erros recuperáveis: tabela não existe, coluna inexistente, RLS, etc.
            bool isTabelaInexistente =
                errStr.contains('does not exist') ||
                errStr.contains('PGRST205') ||
                errStr.contains('Could not find the table') ||
                (errStr.contains('relation') &&
                    errStr.contains('does not exist'));
            bool isColunaInexistente =
                errStr.contains('PGRST204') ||
                (errStr.contains('column') &&
                    errStr.contains('does not exist')) ||
                errStr.contains('Could not find the') ||
                colunaProblematica != null;
            bool isErroRLS =
                errStr.contains('42501') ||
                errStr.contains('row-level security') ||
                errStr.contains('permission denied');
            bool isErroSchema =
                errStr.contains('schema cache') ||
                errStr.contains('Bad Request');

            if (isTabelaInexistente || isErroRLS || isErroSchema) {
              debugPrint(
                '>>> [Migrate] ⚠️ Tabela "$tabela" não pode ser sincronizada — pulando automaticamente.',
              );
              debugPrint(
                '>>> [Migrate]    Motivo: ${isTabelaInexistente ? "tabela não existe" : (isErroRLS ? "erro de permissão" : "erro de schema")}',
              );
              // Se a tabela não existe, pular TODOS os lotes dela
              break;
            }

            if (isColunaInexistente && colunaProblematica != null) {
              // Coluna não existe: adicionar à lista de problemáticas e RETENTAR este lote
              colunasProblematicas.add(colunaProblematica);
              debugPrint(
                '>>> [Migrate] 🔧 Coluna "$colunaProblematica" não existe em $tabela — removendo e retentando...',
              );
              // RETENTAR este mesmo lote (não incrementar i)
              i -= batchSize;
              continue;
            }

            tabelaErro.value = tabela;
            msgErro.value = errStr;
            return false;
          }
          await Future.delayed(const Duration(milliseconds: 200));
        }
        return true;
      }

      // Enviar cada tabela na ordem de dependência
      final tabelas = <(String, List<Map<String, dynamic>>)>[
        ('produtos', _produtos.map((p) => p.toMap()).toList()),
        ('clientes', _clientes.map((c) => c.toMap()).toList()),
        ('servicos', _tiposServico.map((s) => s.toMap()).toList()),
        ('pedidos', _pedidos.map((p) => p.toMap()).toList()),
        (
          'servicos_realizados',
          _servicosRealizados.map((s) => s.toMap()).toList(),
        ),
        ('orcamentos', _orcamentos.map((o) => o.toMap()).toList()),
        ('vendas_balcao', _vendasBalcao.map((v) => v.toMap()).toList()),
        (
          'agendamentos_servico',
          _agendamentosServico.map((a) => a.toMap()).toList(),
        ),
        ('notas_entrada', _notasEntrada.map((n) => n.toMap()).toList()),
        ('funcionarios', _funcionarios.map((f) => f.toMap()).toList()),
        ('ordens_servico', _ordensServico.map((o) => o.toMap()).toList()),
        ('trocas_devolucoes', _trocasDevolucoes.map((t) => t.toMap()).toList()),
        (
          'comissoes_vendedores',
          _comissoesVendedores.map((c) => c.toMap()).toList(),
        ),
        (
          'cash_back_movimentos',
          _movimentosCashBack.map((m) => m.toMap()).toList(),
        ),
        ('contas_pagar', _contasPagar.map((cp) => cp.toMap()).toList()),
        ('romaneios', _romaneios.map((r) => r.toMap()).toList()),
        ('aberturas_caixa', _aberturasCaixa.map((a) => a.toMap()).toList()),
        ('fechamentos_caixa', _fechamentosCaixa.map((f) => f.toMap()).toList()),
        ('sangrias_caixa', _sangrias.map((s) => s.toMap()).toList()),
        ('suprimentos_caixa', _suprimentos.map((s) => s.toMap()).toList()),
        ('nfces', _nfces.map((n) => n.toMap()).toList()),
        ('mesas_comandas', _mesasComandas.map((m) => m.toMap()).toList()),
        ('taxas_entrega', _taxasEntrega.map((t) => t.toMap()).toList()),
        ('links_vendedores', _linksVendedores.map((l) => l.toMap()).toList()),
        (
          'perfis_tributarios',
          _perfisTributarios.map((p) => p.toMap()).toList(),
        ),
        ('departamentos', _departamentos.map((d) => d.toMap()).toList()),
      ];

      int tabelasEnviadas = 0;
      int tabelasPuladas = 0;
      final Set<String> tabelasNaoExistemNoSupabase = {};
      for (final (tabela, dados) in tabelas) {
        // Pular tabelas que já sabemos que não existem no Supabase
        if (tabelasNaoExistemNoSupabase.contains(tabela)) {
          continue;
        }
        if (dados.isEmpty) {
          debugPrint('>>> [Migrate] ⏭️ $tabela: vazia, pulando');
          continue;
        }
        final ok = await enviarTabela(tabela, dados);
        if (!ok) {
          // Se a tabela que deu erro não existe no Supabase, marcar para não tentar de novo
          final erroTabela = tabelaErro.value;
          if (erroTabela != null) {
            debugPrint(
              '>>> [Migrate] ⚠️ Tabela "$erroTabela" será pulada nas próximas tentativas.',
            );
            tabelasNaoExistemNoSupabase.add(erroTabela);
            tabelasPuladas++;
            // Resetar erro para continuar com as próximas tabelas
            tabelaErro.value = null;
            msgErro.value = null;
            continue;
          }
          break;
        }
        tabelasEnviadas++;
      }

      String msg =
          'Migração Local → Nuvem concluída: $tabelasEnviadas tabelas enviadas';
      if (tabelasPuladas > 0) {
        msg +=
            ', $tabelasPuladas tabela(s) pulada(s) (não existem no Supabase)';
      }
      debugPrint('>>> [Migrate] ✅ $msg');
      addSyncLog('✅ $msg');
      return (tabelaErro.value == null, tabelaErro.value, msgErro.value ?? msg);
    } catch (e, st) {
      debugPrint('>>> [Migrate] ❌ Erro na migração Local → Nuvem: $e\n$st');
      addSyncLog('❌ Erro na migração Local → Nuvem: $e');
      return (false, null, e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ================================================================
  /// MIGRAÇÃO COMPLETA: Nuvem → Local (restore de todos os dados)
  /// ================================================================
  /// Baixa TODAS as tabelas do Supabase e popula o banco local.
  /// Use quando:
  ///  - Você quer igualar o banco local com a nuvem
  ///  - Troubleshooting de dados inconsistentes entre máquinas
  ///
  /// ⚠️ ATENÇÃO: Isso SUBSTITUI todos os dados locais!
  Future<(bool, String?, String?)> migrarTabelasNuvemParaLocal() async {
    if (_currentEmpresaId == null) {
      return (false, null, 'Empresa não definida');
    }

    _isLoading = true;
    _mensagemLoading = 'Baixando dados da nuvem para o local...';
    notifyListeners();

    try {
      debugPrint(
        '>>> [Migrate] 📥 Iniciando migração Nuvem → Local para empresa $_currentEmpresaId',
      );
      addSyncLog('📥 Iniciando migração completa Nuvem → Local...');

      // Limpar cache em memória primeiro
      limparDadosMemoria();

      // Carregar todos os dados da nuvem (mesmo método usado no sync normal)
      await _carregarDadosDoSupabase(modoLeve: false);

      // Salvar no banco local
      await _salvarTodosDados(aguardarSupabase: false, isSync: true);

      notifyListeners();

      final msg =
          'Migração Nuvem → Local concluída! '
          '${_produtos.length} produtos, ${_clientes.length} clientes, '
          '${_pedidos.length} pedidos, ${_vendasBalcao.length} vendas.';
      debugPrint('>>> [Migrate] ✅ $msg');
      addSyncLog('✅ $msg');
      return (true, null, msg);
    } catch (e, st) {
      debugPrint('>>> [Migrate] ❌ Erro na migração Nuvem → Local: $e\n$st');
      addSyncLog('❌ Erro na migração Nuvem → Local: $e');
      return (false, null, e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ================================================================
  /// SINCRONIZAÇÃO BIDIRECIONAL COMPLETA (merge inteligente)
  /// ================================================================
  /// Baixa dados da nuvem, merge com o que existe localmente,
  /// e envia de volta. Garante que os dois bancos fiquem idênticos.
  ///
  /// Fluxo:
  ///  1. Baixa dados da nuvem
  ///  2. Merge: mantém o que é mais recente (por updated_at)
  ///  3. Salva local
  ///  4. Envia de volta para a nuvem
  Future<(bool, String?)> sincronizacaoBidirecionalCompleta() async {
    if (_currentEmpresaId == null) {
      return (false, 'Empresa não definida');
    }

    _isLoading = true;
    _mensagemLoading = 'Sincronizando dados entre local e nuvem...';
    notifyListeners();

    try {
      debugPrint(
        '>>> [Sync] 🔄 Iniciando sincronização bidirecional completa...',
      );
      addSyncLog('🔄 Iniciando sincronização bidirecional completa...');

      // 1. Enviar os dados do PostgreSQL local para a nuvem PRIMEIRO.
      // ⚠️ ORDEM IMPORTANTE: a nuvem pode estar quase vazia (ex: máquina nova).
      // Se baixarmos primeiro, a memória seria sobrescrita com os dados quase
      // vazios e o envio seguinte mandaria quase nada. Enviando primeiro, os
      // 5600 produtos locais sobem e depois baixamos só o que falta (ex:
      // registros criados por OUTRAS máquinas).
      debugPrint(
        '>>> [Sync] 📤 Passo 1/4: Enviando dados locais (PostgreSQL) para a nuvem...',
      );
      addSyncLog('📤 Enviando dados locais para a nuvem...');
      final (okEnvio, msgEnvio) = await enviarDadosLocalParaNuvem();
      if (!okEnvio) {
        final msg =
            'Sincronização parcial: problema ao enviar dados para a nuvem. $msgEnvio';
        debugPrint('>>> [Sync] ⚠️ $msg');
        addSyncLog('⚠️ $msg');
        return (false, msg);
      }
      debugPrint('>>> [Sync] ✅ Passo 1/4 concluído: $msgEnvio');
      addSyncLog('✅ $msgEnvio');

      // 2. Baixar da nuvem o que outras máquinas criaram (merge)
      debugPrint(
        '>>> [Sync] 📥 Passo 2/4: Baixando dados da nuvem (de outras máquinas)...',
      );
      await _carregarDadosDoSupabase(modoLeve: false);

      // 3. Salvar localmente (merge)
      debugPrint('>>> [Sync] 💾 Passo 3/4: Salvando dados localmente...');
      await _salvarTodosDados(aguardarSupabase: false, isSync: true);
      notifyListeners();

      // 4. Verificar consistência final
      debugPrint('>>> [Sync] 🔍 Passo 4/4: Verificando consistência...');
      debugPrint(
        '>>> [Sync] ✅ Local: ${_produtos.length} produtos, ${_clientes.length} clientes, '
        '${_pedidos.length} pedidos, ${_vendasBalcao.length} vendas',
      );

      final msg =
          'Sincronização completa! Dados locais enviados para a nuvem e dados da nuvem baixados. Os bancos estão unificados.';
      debugPrint('>>> [Sync] ✅ $msg');
      addSyncLog('✅ $msg');
      return (true, msg);
    } catch (e, st) {
      debugPrint('>>> [Sync] ❌ Erro na sincronização bidirecional: $e\n$st');
      addSyncLog('❌ Erro na sincronização bidirecional: $e');
      return (false, e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Envia dados locais para a nuvem de forma simples e direta
  /// Lê os dados DIRETO do PostgreSQL local (DatabaseService) — não das listas
  /// em memória, que podem estar vazias ou vir do Supabase.
  Future<(bool, String)> enviarDadosLocalParaNuvem() async {
    debugPrint('>>>> [EnvirLocalNuvem] Iniciando envio local -> nuvem');

    if (_currentEmpresaId == null) {
      debugPrint('>>>> [EnvirLocalNuvem] ERRO: Empresa nao definida');
      return (false, 'Empresa não definida');
    }
    if (!nuvemHabilitada) {
      return (
        false,
        'Nuvem desativada para esta empresa. Dados mantidos localmente.',
      );
    }
    debugPrint('>>>> [EnvirLocalNuvem] Empresa: ' + _currentEmpresaId!);

    if (!SupabaseService.isAvailable) {
      debugPrint('>>>> [EnvirLocalNuvem] ERRO: Supabase nao conectado');
      return (false, 'Supabase não está conectado');
    }
    debugPrint('>>>> [EnvirLocalNuvem] Supabase conectado');

    // Garantir que o DatabaseService está apontando para a empresa atual
    DatabaseService().setEmpresaId(_currentEmpresaId!);

    int tabelasEnviadas = 0;
    int tabelasComErro = 0;
    int totalRegistros = 0;
    final List<String> erros = [];
    final List<String> tabelasOk = [];

    // Tabela -> chave usada pelo DatabaseService (PostgreSQL local)
    final tabelas = <String, String>{
      'produtos': LocalStorageService.keyProdutos,
      'clientes': LocalStorageService.keyClientes,
      'pedidos': LocalStorageService.keyPedidos,
      'servicos_realizados': LocalStorageService.keyServicosRealizados,
      'orcamentos': LocalStorageService.keyOrcamentos,
      'vendas_balcao': LocalStorageService.keyVendasBalcao,
      'mesas_comandas': LocalStorageService.keyMesasComandas,
      'servicos': LocalStorageService.keyServicos,
      'ordens_servico': LocalStorageService.keyOrdensServico,
      'notas_entrada': LocalStorageService.keyNotasEntrada,
      'pedidos_compra': LocalStorageService.keyPedidosCompra,
      'funcionarios': LocalStorageService.keyFuncionarios,
      'agendamentos_servico': LocalStorageService.keyAgendamentosServico,
      'trocas_devolucoes': LocalStorageService.keyTrocasDevolucoes,
      'comissoes_vendedores': LocalStorageService.keyComissoesVendedores,
      'cash_back_movimentos': LocalStorageService.keyCashBackMovimentos,
      'contas_pagar': LocalStorageService.keyContasPagar,
      'romaneios': LocalStorageService.keyRomaneios,
      'aberturas_caixa': LocalStorageService.keyAberturasCaixa,
      'fechamentos_caixa': LocalStorageService.keyFechamentosCaixa,
      'sangrias_caixa': LocalStorageService.keySangriasField,
      'suprimentos_caixa': LocalStorageService.keySuprimentosField,
      'nfces': LocalStorageService.keyNFCes,
      'taxas_entrega': LocalStorageService.keyTaxasEntrega,
      'links_vendedores': LocalStorageService.keyLinksVendedores,
      'estoque_historico': LocalStorageService.keyEstoqueHistorico,
      'ajustes_estoque_lote': LocalStorageService.keyAjustesEstoqueLote,
    };

    for (final entry in tabelas.entries) {
      final tabela = entry.key;
      final chave = entry.value;

      // SEMPRE filtrar por empresa_id — NUNCA carregar tudo sem filtro,
      // senão dados de outras empresas são misturados e enviados com a
      // empresa_id errada. carregarLista já aplica WHERE empresa_id = X.
      List<Map<String, dynamic>> dados = [];
      try {
        dados = await DatabaseService().carregarLista(chave);
        debugPrint(
          '>>>> [EnvirLocalNuvem] PostgreSQL (empresa ' +
              _currentEmpresaId! +
              ') - ' +
              tabela +
              ': ' +
              dados.length.toString() +
              ' registros',
        );
      } catch (e) {
        debugPrint(
          '>>>> [EnvirLocalNuvem] ⚠️ Falha ao ler ' +
              tabela +
              ': ' +
              e.toString(),
        );
      }

      if (dados.isEmpty) {
        debugPrint('>>>> [EnvirLocalNuvem] SKIP ' + tabela + ': vazia');
        continue;
      }

      // Deduplicação: vendas_balcao pode ter vendas duplicadas (duas máquinas
      // criaram a mesma venda com ids diferentes, mesmo numero). Mantém apenas
      // uma cópia por numero para evitar 23505 (unique constraint).
      if (tabela == 'vendas_balcao' && dados.length > 1) {
        final Map<String, Map<String, dynamic>> porNumero = {};
        for (final d in dados) {
          final numero = d['numero']?.toString() ?? '';
          if (numero.isNotEmpty && porNumero.containsKey(numero)) continue;
          porNumero[numero.isNotEmpty ? numero : d['id']?.toString() ?? ''] = d;
        }
        if (porNumero.length < dados.length) {
          debugPrint(
            '>>>> [EnvirLocalNuvem] Dedup vendas_balcao: ${dados.length} -> ${porNumero.length} (removidos ${dados.length - porNumero.length} duplicados)',
          );
          dados = porNumero.values.toList();
        }
      }

      debugPrint(
        '>>>> [EnvirLocalNuvem] Enviando ' +
            dados.length.toString() +
            ' para ' +
            tabela +
            '...',
      );

      // Conjunto de colunas problemáticas para esta tabela (removidas e retentadas)
      final Set<String> colunasRemovidas = {};

      Future<void> enviarLote(
        String tabelaAtual,
        List<Map<String, dynamic>> lote,
      ) async {
        // Sanitização dos dados (datas→string; colunas são filtradas
        // automaticamente pelo upsertBatch via OpenAPI)
        List<Map<String, dynamic>> preparar(List<Map<String, dynamic>> origem) {
          return origem.map((d) {
            var copia = _converterValoresParaJson(Map<String, dynamic>.from(d));
            copia['empresa_id'] = _currentEmpresaId;
            copia['updated_at'] = DateTime.now().toUtc().toIso8601String();
            // numero_venda é derivado dentro do SupabaseService._prepararVendaBalcao
            var sanitizado = _sanitizeForSupabase(tabelaAtual, copia);
            for (final col in colunasRemovidas) {
              sanitizado.remove(col);
            }
            return sanitizado;
          }).toList();
        }

        var dadosLote = preparar(lote);
        const batchSize = 500;
        for (int i = 0; i < dadosLote.length; i += batchSize) {
          final batch = dadosLote.sublist(
            i,
            (i + batchSize).clamp(0, dadosLote.length),
          );
          try {
            await _supabaseService.upsertBatch(tabelaAtual, batch);
          } catch (e2) {
            final err2 = e2.toString();
            debugPrint(
              '>>>> [EnvirLocalNuvem] ⚠️ ERRO no lote de ' +
                  tabelaAtual +
                  ': ' +
                  err2,
            );
            // Tratar erro de constraint (23505 = duplicate key) para vendas_balcao:
            // quando duas máquinas criaram vendas com mesmo numero, o 2º registro
            // colide. Retry registro-a-registro e pula os que já existem.
            if (tabelaAtual == 'vendas_balcao' &&
                (err2.contains('23505') || err2.contains('duplicate key'))) {
              debugPrint(
                '>>>> [EnvirLocalNuvem] ⚠️ 23505 em vendas_balcao — retry registro-a-registro...',
              );
              for (final registro in batch) {
                try {
                  await _supabaseService.upsertBatch(tabelaAtual, [registro]);
                } catch (eReg) {
                  final errReg = eReg.toString();
                  if (errReg.contains('23505') ||
                      errReg.contains('duplicate key')) {
                    debugPrint(
                      '>>>> [EnvirLocalNuvem] ⏭️ Venda duplicada pulada: ${registro['id']} (numero: ${registro['numero']})',
                    );
                  } else {
                    debugPrint(
                      '>>>> [EnvirLocalNuvem] ❌ Erro na venda ${registro['id']}: $errReg',
                    );
                  }
                }
              }
              continue;
            }
            // Extrair coluna problemática do erro PGRST204 e REMOVER de todos os lotes
            final coluna = _extrairColunaDoErro(err2);
            if (coluna != null && !colunasRemovidas.contains(coluna)) {
              colunasRemovidas.add(coluna);
              debugPrint(
                '>>>> [EnvirLocalNuvem] 🔧 Coluna "$coluna" não existe no Supabase — removendo de TODOS os lotes e retentando...',
              );
              dadosLote = preparar(lote);
              i -= batchSize;
              continue;
            }
            rethrow;
          }
        }
      }

      try {
        await enviarLote(tabela, dados);
        tabelasEnviadas++;
        totalRegistros += dados.length;
        tabelasOk.add(
          tabela +
              '(' +
              dados.length.toString() +
              ')' +
              (colunasRemovidas.isNotEmpty
                  ? ' [sem ${colunasRemovidas.join(',')}]'
                  : ''),
        );
        debugPrint(
          '>>>> [EnvirLocalNuvem] OK ' +
              tabela +
              ': ' +
              dados.length.toString() +
              ' registros' +
              (colunasRemovidas.isNotEmpty
                  ? ' (colunas removidas: ${colunasRemovidas.join(', ')})'
                  : ''),
        );
      } catch (e) {
        final errStr = e.toString();
        debugPrint('>>>> [EnvirLocalNuvem] ERRO em ' + tabela + ': ' + errStr);

        // Tabela realmente não existe no Supabase -> pular
        if (errStr.contains('PGRST205') ||
            (errStr.contains('relation') &&
                errStr.contains('does not exist'))) {
          debugPrint(
            '>>>> [EnvirLocalNuvem] SKIP ' +
                tabela +
                ': nao existe no Supabase',
          );
          continue;
        }
        tabelasComErro++;
        final shortErr = errStr.length > 150
            ? errStr.substring(0, 150)
            : errStr;
        erros.add(tabela + ': ' + shortErr);
      }
    }

    // Perfis tributários e departamentos existem apenas em memória
    final extras = <String, List<Map<String, dynamic>>>{
      'perfis_tributarios': _perfisTributarios.map((p) => p.toMap()).toList(),
      'departamentos': _departamentos.map((d) => d.toMap()).toList(),
    };
    for (final entry in extras.entries) {
      final tabela = entry.key;
      final dados = entry.value;
      if (dados.isEmpty) {
        debugPrint('>>>> [EnvirLocalNuvem] SKIP ' + tabela + ': vazia');
        continue;
      }
      debugPrint(
        '>>>> [EnvirLocalNuvem] Enviando ' +
            dados.length.toString() +
            ' para ' +
            tabela +
            '...',
      );
      try {
        final dadosSanitizados = dados.map((d) {
          final copia = Map<String, dynamic>.from(d);
          copia['empresa_id'] = _currentEmpresaId;
          copia['updated_at'] = DateTime.now().toUtc().toIso8601String();
          return _sanitizeForSupabase(tabela, copia);
        }).toList();
        const batchSize = 500;
        for (int i = 0; i < dadosSanitizados.length; i += batchSize) {
          final batch = dadosSanitizados.sublist(
            i,
            (i + batchSize).clamp(0, dadosSanitizados.length),
          );
          await _supabaseService.upsertBatch(tabela, batch);
        }
        tabelasEnviadas++;
        totalRegistros += dados.length;
        tabelasOk.add(tabela + '(' + dados.length.toString() + ')');
        debugPrint(
          '>>>> [EnvirLocalNuvem] OK ' +
              tabela +
              ': ' +
              dados.length.toString() +
              ' registros',
        );
      } catch (e) {
        final errStr = e.toString();
        debugPrint('>>>> [EnvirLocalNuvem] ERRO em ' + tabela + ': ' + errStr);
        if (errStr.contains('does not exist') ||
            errStr.contains('PGRST205') ||
            errStr.contains('PGRST204')) {
          debugPrint(
            '>>>> [EnvirLocalNuvem] SKIP ' +
                tabela +
                ': nao existe no Supabase',
          );
          continue;
        }
        tabelasComErro++;
        final shortErr = errStr.length > 100
            ? errStr.substring(0, 100)
            : errStr;
        erros.add(tabela + ': ' + shortErr);
      }
    }

    String msg =
        'Enviados ' +
        tabelasEnviadas.toString() +
        ' tabelas / ' +
        totalRegistros.toString() +
        ' registros para a nuvem';
    if (tabelasOk.isNotEmpty) {
      msg += ': ' + tabelasOk.join(', ');
    }
    if (tabelasComErro > 0) {
      msg +=
          '\n' + tabelasComErro.toString() + ' com erro: ' + erros.join('; ');
    }
    debugPrint('>>>> [EnvirLocalNuvem] RESULTADO: ' + msg);

    // VERIFICAÇÃO: contar no Supabase o que realmente existe agora
    try {
      final verificacao = <String>[];
      for (final tabela in [
        'produtos',
        'clientes',
        'pedidos',
        'vendas_balcao',
        'servicos',
        'mesas_comandas',
      ]) {
        final count = await _supabaseService.contarRegistrosNaNuvem(
          tabela,
          _currentEmpresaId!,
        );
        debugPrint(
          '>>>> [EnvirLocalNuvem] 📊 VERIFICAÇÃO $tabela no Supabase: $count registros',
        );
        if (count >= 0) verificacao.add(tabela + '=' + count.toString());
      }
      msg +=
          '\n📊 No Supabase agora: ' +
          (verificacao.isEmpty ? 'sem dados' : verificacao.join(', '));
    } catch (e) {
      debugPrint('>>>> [EnvirLocalNuvem] ⚠️ Falha na verificação: $e');
    }

    return (tabelasComErro == 0, msg);
  }

  /// 🚀 Após restaurar um dump no PostgreSQL local, recarrega TODOS os dados
  /// do banco local para a memória do app e envia tudo para o Supabase.
  /// Assim a nuvem fica igual ao banco local restaurado — e as outras máquinas
  /// puxam esses dados na próxima sincronização.
  /// Recarrega as listas em memória a partir do banco LOCAL — e **só** disso.
  ///
  /// É o par do "restaurar sem mexer na nuvem": a tela aplica o backup no
  /// PostgreSQL local e usa este método para refletir o resultado na interface,
  /// sem disparar nenhum envio para o Supabase. Enviar para a nuvem vira uma
  /// decisão separada e explícita do usuário (
  /// [restaurarBancoLocalESincronizarNuvem] / [enviarDadosLocalParaNuvem]).
  Future<void> recarregarSomenteBancoLocal() async {
    if (_currentEmpresaId == null) {
      debugPrint(
        '>>> [DataService] ℹ️ Recarga local ignorada: empresa não definida.',
      );
      return;
    }
    await _carregarDadosSalvos();
    debugPrint(
      '>>> [DataService] ✅ Memória recarregada só do banco local: '
      '${_produtos.length} produtos, ${_clientes.length} clientes, ${_pedidos.length} pedidos',
    );
    notifyListeners();
  }

  Future<(bool, String)> restaurarBancoLocalESincronizarNuvem() async {
    if (_currentEmpresaId == null) {
      return (false, 'Empresa não definida');
    }

    try {
      debugPrint(
        '>>> [Restaurar] 🔄 Recarregando dados do banco local (PostgreSQL)...',
      );

      // 1. Recarregar todas as listas em memória a partir do PostgreSQL local
      await _carregarDadosSalvos();
      debugPrint(
        '>>> [Restaurar] ✅ Memória recarregada: ${_produtos.length} produtos, ${_clientes.length} clientes, ${_pedidos.length} pedidos',
      );

      // 2. Enviar tudo para o Supabase
      if (!SupabaseService.isAvailable) {
        return (
          true,
          'Dump restaurado e carregado localmente. Supabase indisponível — os dados serão enviados quando houver conexão.',
        );
      }

      debugPrint(
        '>>> [Restaurar] ☁️ Enviando dados do banco local para o Supabase...',
      );
      final (ok, msg) = await enviarDadosLocalParaNuvem();
      if (ok) {
        return (true, 'Dump restaurado e enviado para a nuvem! $msg');
      }
      return (
        true,
        'Dump restaurado localmente, mas com avisos na nuvem: $msg',
      );
    } catch (e, st) {
      debugPrint('>>> [Restaurar] ❌ Erro: $e\n$st');
      return (false, 'Erro ao recarregar/enviar dados: $e');
    }
  }

  /// Converte SOMENTE os VALORES do PostgreSQL (DateTime, etc.) em formatos
  /// JSON serializáveis, MANTENDO as chaves exatamente como estão no banco
  /// local. IMPORTANTE: o banco local e o Supabase usam os MESMOS nomes de
  /// colunas (inclusive camelCase em tabelas legadas como temAcesso,
  /// tipoComissao, linkVendedorId, entregaIds, vendaId). Converter as chaves
  /// para snake_case criava colunas que NÃO existem no Supabase e derrubava a
  /// tabela inteira com PGRST204.
  static Map<String, dynamic> _converterValoresParaJson(
    Map<String, dynamic> map,
  ) {
    final resultado = <String, dynamic>{};
    map.forEach((chave, valor) {
      resultado[chave] = _converterValorParaJson(valor);
    });
    return resultado;
  }

  /// Converte valores do PostgreSQL (DateTime, etc.) em formatos JSON serializáveis
  /// (string ISO 8601 para datas) — necessário porque a API do Supabase rejeita
  /// objetos DateTime: "Converting object to an encodable object failed".
  /// As chaves internas de Map/JSONB são preservadas (sem conversão).
  static dynamic _converterValorParaJson(dynamic valor) {
    if (valor == null) return null;
    if (valor is DateTime) {
      return valor.toIso8601String();
    }
    if (valor is Map) {
      final resultado = <String, dynamic>{};
      valor.forEach((k, v) {
        resultado[k.toString()] = _converterValorParaJson(v);
      });
      return resultado;
    }
    if (valor is List) {
      return valor.map(_converterValorParaJson).toList();
    }
    return valor;
  }

  /// Extrai o nome da coluna problemática de uma mensagem de erro do Supabase.
  /// Ex.: 'column "xxx" of relation "produtos" does not exist' -> 'xxx'
  static String? _extrairColunaDoErro(String errStr) {
    final match = RegExp(r'column "?([a-zA-Z0-9_]+)"?').firstMatch(errStr);
    if (match != null) {
      return match.group(1);
    }
    // PGRST204: 'Could not find the column "xxx"'
    final match2 = RegExp(r'column "([a-zA-Z0-9_]+)"').firstMatch(errStr);
    if (match2 != null) {
      return match2.group(1);
    }
    // "Could not find the 'xxx' column"
    final match3 = RegExp(
      r"Could not find the '([a-zA-Z0-9_]+)'",
    ).firstMatch(errStr);
    if (match3 != null) {
      return match3.group(1);
    }
    return null;
  }

  /// 🚑 RESTAURAR: Envia os dados que estão no computador de volta para a nuvem
  /// Usar quando a nuvem foi apagada acidentalmente e o local ainda tem os dados
  Future<void> restaurarLocalParaNuvem() async {
    if (_currentEmpresaId == null) return;
    if (!nuvemHabilitada) {
      addSyncLog(
        '☁️ Restauração para nuvem bloqueada: nuvem desativada para esta empresa.',
      );
      return;
    }

    _isLoading = true;
    _mensagemLoading = 'Restaurando dados locais para a nuvem...';
    notifyListeners();

    try {
      debugPrint(
        '>>> [Restore] 🚑 Iniciando restauração local → nuvem para empresa $currentEmpresaId',
      );

      // Enviar produtos de volta para a nuvem (em lotes de 200 para não travar)
      if (_produtos.isNotEmpty) {
        debugPrint('>>> [Restore] 📦 Enviando ${_produtos.length} produtos...');
        const batchSize = 200;
        for (int i = 0; i < _produtos.length; i += batchSize) {
          final batch = _produtos.sublist(
            i,
            (i + batchSize).clamp(0, _produtos.length),
          );
          // Sanitizar: remover colunas que não existem no Supabase (PGRST204)
          final dadosSanitizados = batch.map((p) {
            final map = p.toMap();
            map.remove('baixar_estoque_proprio');
            map.remove('eh_composto');
            map.remove('composicao');
            map.remove('cobrar_garcom');
            return map;
          }).toList();
          await _supabaseService.upsertBatch(
            SupabaseService.tableProdutos,
            dadosSanitizados,
          );
          debugPrint(
            '>>> [Restore] ✅ Lote ${(i ~/ batchSize) + 1}: ${batch.length} produtos enviados',
          );
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

      debugPrint(
        '>>> [Restore] ✅ Restauração concluída! Dados locais enviados para a nuvem.',
      );
    } catch (e) {
      debugPrint('>>> [Restore] ❌ Erro na restauração: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Tabelas operacionais incluídas no "Zerar Nuvem" (todas têm coluna empresa_id)
  static const List<String> _tabelasParaZerarNuvem = [
    SupabaseService.tableProdutos,
    SupabaseService.tableClientes,
    SupabaseService.tablePedidos,
    SupabaseService.tableVendasBalcao,
    SupabaseService.tableAberturasCaixa,
    SupabaseService.tableFechamentosCaixa,
    SupabaseService.tableEstoqueHistorico,
  ];

  /// Conta quantos registros existem na nuvem para a empresa atual (por tabela).
  /// Usado no diálogo de confirmação do "Zerar Nuvem" para mostrar o que será apagado.
  Future<Map<String, int>> contarDadosDaEmpresa() async {
    final resultado = <String, int>{};
    final empresaId = _currentEmpresaId;
    if (!nuvemHabilitada || empresaId == null || empresaId.isEmpty) {
      return resultado;
    }
    for (final tabela in _tabelasParaZerarNuvem) {
      try {
        resultado[tabela] = await _supabaseService.contarRegistrosNaNuvem(
          tabela,
          empresaId,
        );
      } catch (e) {
        debugPrint('>>> [Supabase] ⚠️ Erro ao contar $tabela: $e');
      }
    }
    return resultado;
  }

  /// Limpa TODOS os dados desta empresa no SUPABASE (Cuidado!)
  ///
  /// PROTEÇÕES:
  ///  - Exige empresa selecionada (nunca apaga com id vazio);
  ///  - BLOQUEIA o id '1' (empresa padrão legada que, neste banco, concentra
  ///    os dados de TODAS as empresas — apagar por esse id apagaria tudo);
  ///  - Conta os registros ANTES de apagar e só apaga os da empresa atual;
  ///  - Retorna um resumo (tabela -> qtd removida) para exibição na UI.
  Future<Map<String, int>> deletarTudoNoSupabaseDestaEmpresa() async {
    final empresaId = _currentEmpresaId;
    if (empresaId == null || empresaId.isEmpty) {
      throw Exception('⚠️ Nenhuma empresa selecionada. Operação cancelada.');
    }
    if (!nuvemHabilitada) {
      throw StateError(
        'Nuvem desativada para esta empresa. Nenhum dado foi apagado.',
      );
    }
    // PROTEÇÃO CRÍTICA: o id "1" é a empresa padrão e, no banco atual, TODAS
    // as empresas legadas estão gravadas sob esse id. Apagar por ele apagaria
    // os dados de todas as empresas de uma vez.
    if (empresaId == '1') {
      throw Exception(
        '⚠️ Segurança: a empresa padrão (ID "1") concentra dados de várias empresas no banco. '
        'Apagar por esse ID apagaria tudo. Migre/renomeie a empresa antes de zerar.',
      );
    }

    _isLoading = true;
    _mensagemLoading = 'Limpando dados na nuvem...';
    notifyListeners();

    try {
      final removidosPorTabela = <String, int>{};
      for (var tabela in _tabelasParaZerarNuvem) {
        debugPrint('>>> [Supabase] 🗑️ Deletando $tabela...');
        final removidos = await _supabaseService.deleteByEmpresa(
          tabela,
          empresaId,
        );
        if (removidos > 0) {
          removidosPorTabela[tabela] = removidos;
        }
      }

      // Após limpar a nuvem, limpa o computador também (apenas listas da empresa atual)
      _clientes.clear();
      _produtos.clear();
      _pedidos.clear();
      _vendasBalcao.clear();
      await _salvarTodosDados(aguardarSupabase: false);

      debugPrint(
        '>>> [Supabase] ✅ Nuvem e Local limpos para a empresa $empresaId: $removidosPorTabela',
      );
      return removidosPorTabela;
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
      _agendamentosServico[i] = _vincularReferenciasAgendamento(
        _agendamentosServico[i],
      );
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
    await _storage.salvar(
      'ultima_validacao_online',
      _ultimaValidacaoOnline!.toIso8601String(),
    );
    await _storage.salvar(
      'ultima_data_execucao',
      _ultimaDataExecucao!.toIso8601String(),
    );
    await _storage.salvar('liberacao_provisoria_ativa', 'false');
    notifyListeners();
  }

  /// Simula N dias offline para testar bloqueio de licenciamento
  Future<void> simularDiasOffline(int dias) async {
    _ultimaValidacaoOnline = DateTime.now().subtract(Duration(days: dias));
    await _storage.salvar(
      'ultima_validacao_online',
      _ultimaValidacaoOnline!.toIso8601String(),
    );
    notifyListeners();
  }

  /// Simula alteração de relógio para testar bloqueio
  Future<void> simularRelogioAdulterado() async {
    _ultimaDataExecucao = DateTime.now().add(const Duration(hours: 2));
    await _storage.salvar(
      'ultima_data_execucao',
      _ultimaDataExecucao!.toIso8601String(),
    );
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
    if (_empresaAtual == null)
      return; // Sem empresa definida, não há perfis a carregar
    _perfisTributarios.clear();
    final raw = _empresaAtual?.configuracoes?['perfis_tributarios'];
    final temConfigValida = raw is List && raw.isNotEmpty;
    if (temConfigValida) {
      for (final item in raw) {
        if (item is Map) {
          _perfisTributarios.add(
            PerfilTributario.fromMap(Map<String, dynamic>.from(item)),
          );
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
      unawaited(
        _migrarPerfisTributariosDoCache(forcarPersistencia: adicionouPadrao),
      );
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
    // Sem empresa definida, o cache cairia num namespace compartilhado e
    // misturaria perfis de empresas diferentes. Melhor não migrar agora.
    final empresaAlvo = _currentEmpresaId;
    if (empresaAlvo == null || empresaAlvo.isEmpty) return;
    if (_empresaAtual == null) return;
    _migrandoPerfisTributarios = true;
    try {
      // A LEITURA é assíncrona e a empresa pode ser TROCADA no meio dela:
      // `setEmpresaAtual` chama esta rotina com a empresa AINDA ANTERIOR (o
      // `definirEmpresaAtual` só depois atualiza `_currentEmpresaId`). Fixamos
      // a empresa NA ENTRADA: sem isso, os perfis da empresa anterior eram
      // mesclados na lista da empresa nova e — pior — GRAVADOS nela (bug:
      // "mudei o perfil numa empresa e mudou também na outra").
      final chave = 'empresa_${empresaAlvo}_perfis_tributarios';
      final cached = await _storage.carregarLista(chave);
      // A empresa mudou enquanto líamos o cache? O conteúdo é da anterior —
      // descarta para não contaminar a empresa aberta agora.
      if (_currentEmpresaId != empresaAlvo ||
          _empresaAtual?.id != empresaAlvo) {
        debugPrint(
          '>>> [Perfis] Migração do cache descartada: a empresa aberta mudou '
          '($empresaAlvo -> $_currentEmpresaId) durante a leitura.',
        );
        return;
      }
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
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao migrar perfis tributários do cache: $e',
      );
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
          // Corrige apenas os CÓDIGOS do padrão (CFOP/CSOSN/CST persistidos
          // errados em versões antigas). `isDefault` NÃO é tocado aqui: quem
          // escolhe o perfil PADRÃO é o usuário, no switch "Definir como
          // Perfil Padrão". Antes esta rotina forçava isDefault=true no
          // Tributado em TODO carregamento — a escolha do usuário voltava
          // para o Tributado ao reabrir a tela (o selo PADRÃO "não mudava") e
          // o regime ficava com dois padrões ao mesmo tempo.
          if (p.cfop != padrao.cfop ||
              p.csosn != padrao.csosn ||
              p.icmsCst != padrao.icmsCst) {
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
              isDefault: p.isDefault,
            );
            mudou = true;
          }
          return;
        }
      }
      // O padrão do sistema ainda não existe nesta empresa: cria agora. Se ele
      // nascer marcado como PADRÃO num regime que já tem um, o ajuste de
      // `padroesUnicosPorRegime` logo abaixo mantém a escolha do usuário.
      _perfisTributarios.add(padrao);
      mudou = true;
    }

    // TRIBUTADO é o perfil padrão do sistema (CFOP 5102, CSOSN 102)
    garantirPadrao(
      PerfilTributario(
        id: 'padrao_tributado_simples',
        nome: 'Tributado (Simples Nacional)',
        cfop: '5102',
        csosn: '102',
        isDefault: true,
      ),
    );
    // Não Tributado: CSOSN 400 (não tributada pelo Simples Nacional).
    // ATENÇÃO: CSOSN 500 é "ICMS cobrado anteriormente por ST", NÃO é não-tributado.
    garantirPadrao(
      PerfilTributario(
        id: 'padrao_nao_tributado_simples',
        nome: 'Não Tributado (Simples Nacional)',
        cfop: '5102',
        csosn: '400',
      ),
    );
    // Substituição Tributária (substituído): CFOP 5405, CSOSN 500
    garantirPadrao(
      PerfilTributario(
        id: 'padrao_substituicao_simples',
        nome: 'Substituição Tributária (Simples Nacional)',
        cfop: '5405',
        csosn: '500',
      ),
    );
    garantirPadrao(
      PerfilTributario(
        id: 'padrao_tributado_normal',
        nome: 'Tributado (Regime Normal)',
        cfop: '5102',
        icmsCst: '00',
        isDefault: true,
      ),
    );
    garantirPadrao(
      PerfilTributario(
        id: 'padrao_nao_tributado_normal',
        nome: 'Não Tributado (Regime Normal)',
        cfop: '5102',
        icmsCst: '41',
      ),
    );
    // Substituição Tributária (substituído): CFOP 5405, CST 60
    // (ICMS cobrado anteriormente por ST - equivalente ao CSOSN 500)
    garantirPadrao(
      PerfilTributario(
        id: 'padrao_substituicao_normal',
        nome: 'Substituição Tributária (Regime Normal)',
        cfop: '5405',
        icmsCst: '60',
      ),
    );
    // Invariante: UM perfil PADRÃO por regime (ver padroesUnicosPorRegime).
    final padroesAntes = _perfisTributarios.where((p) => p.isDefault).length;
    final normalizados = padroesUnicosPorRegime(_perfisTributarios);
    if (normalizados.where((p) => p.isDefault).length != padroesAntes) {
      _perfisTributarios
        ..clear()
        ..addAll(normalizados);
      mudou = true;
    }

    if (mudou) {
      debugPrint(
        '>>> [DataService] ✅ Perfis tributários padrão garantidos/corrigidos para a empresa atual',
      );
    }
    return mudou;
  }

  /// Persiste a lista de perfis tributários na configuração da empresa atual
  /// (PostgreSQL local + Supabase), onde o backend NFC-e os busca.
  Future<void> _persistirPerfisTributariosNaEmpresa() async {
    final empresa = _empresaAtual;
    if (empresa == null) return;
    // Trava de isolamento: nunca gravar os perfis na empresa "errada" (ex.:
    // _empresaAtual desatualizada em relação à empresa realmente aberta).
    if (_currentEmpresaId == null || empresa.id != _currentEmpresaId) {
      debugPrint(
        '>>> [Perfis] Persistência ignorada: empresa aberta ($_currentEmpresaId) '
        'difere da empresa em memória (${empresa.id}).',
      );
      return;
    }
    if (_persistindoPerfisTributarios) return;
    _persistindoPerfisTributarios = true;
    try {
      final novasConfigs = Map<String, dynamic>.from(
        empresa.configuracoes ?? {},
      );
      novasConfigs['perfis_tributarios'] = _perfisTributarios
          .map((p) => p.toMap())
          .toList();
      await atualizarDadosEmpresa(
        empresa.copyWith(configuracoes: novasConfigs),
      );
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao persistir perfis tributários na empresa: $e',
      );
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
          final mesmoRegime =
              (perfilTemCst && p.icmsCst?.trim().isNotEmpty == true) ||
              (perfilTemCsosn && p.csosn?.trim().isNotEmpty == true);
          if (!mesmoRegime) continue;
          _perfisTributarios[i] = p.copyWith(isDefault: false);
        }
      }
    }

    final chave = _getChaveComEmpresa('perfis_tributarios');
    await _storage.salvarLista(
      chave,
      _perfisTributarios.map((p) => p.toMap()).toList(),
    );

    // PERSISTÊNCIA NO BANCO: gravar na configuração da empresa (PostgreSQL local + Supabase)
    await _persistirPerfisTributariosNaEmpresa();
    notifyListeners();
  }

  /// Exclui um perfil tributário pelo ID
  Future<void> excluirPerfilTributario(String perfilId) async {
    _perfisTributarios.removeWhere((p) => p.id == perfilId);
    final chave = _getChaveComEmpresa('perfis_tributarios');
    await _storage.salvarLista(
      chave,
      _perfisTributarios.map((p) => p.toMap()).toList(),
    );
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
    // Dados antigos chegaram a gravar o MESMO departamento duas vezes na
    // configuração da empresa (cache local mesclado em paralelo). A lista
    // duplicada derrubava o DropdownButton do cadastro de produtos, então a
    // limpeza acontece já na leitura e o resultado é regravado.
    final removeuDuplicatas = _normalizarDepartamentos();
    if (adicionouPadrao || removeuDuplicatas) {
      unawaited(_persistirDepartamentosNaEmpresa());
    }
    // Sempre confere o cache local por cima (última edição do usuário não some).
    unawaited(_migrarDepartamentosDoCache());
    notifyListeners();
  }

  /// Recupera departamentos salvos apenas no cache local (compatibilidade com
  /// versões que guardavam a lista fora da configuração da empresa).
  Future<void> _migrarDepartamentosDoCache() async {
    // Duas migrações ao mesmo tempo (setEmpresaAtual + atualizarDadosEmpresa)
    // liam o mesmo cache e as duas adicionavam o departamento: a lista ficava
    // com o id repetido. Uma migração por vez resolve na origem.
    if (_migrandoDepartamentos) return;
    // A empresa é fixada NA ENTRADA: trocar de empresa no meio da leitura
    // mesclaria os departamentos da empresa anterior na nova (mesmo defeito dos
    // perfis tributários).
    final empresaAlvo = _currentEmpresaId;
    if (empresaAlvo == null || empresaAlvo.isEmpty) return;
    _migrandoDepartamentos = true;
    try {
      final chave = 'empresa_${empresaAlvo}_departamentos';
      final cache = await _storage.carregarLista(chave);
      if (_currentEmpresaId != empresaAlvo ||
          _empresaAtual?.id != empresaAlvo) {
        debugPrint(
          '>>> [Departamentos] Migração do cache descartada: a empresa aberta '
          'mudou ($empresaAlvo -> $_currentEmpresaId) durante a leitura.',
        );
        return;
      }
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
        if (_normalizarDepartamentos()) mudou = true;
        if (mudou) {
          await _persistirDepartamentosNaEmpresa();
        }
      }
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao migrar departamentos do cache: $e',
      );
    } finally {
      _migrandoDepartamentos = false;
      // Notifica a UI mesmo se a persistência falhar, para o dropdown atualizar.
      notifyListeners();
    }
  }

  /// Remove da lista os departamentos sem nome e os IDs repetidos, gerando um
  /// id estável para registros antigos que foram salvos sem id.
  ///
  /// A lista é montada por três caminhos (configuração da empresa, cache local
  /// e departamentos padrão) e a duplicata de ID quebrava o `DropdownButton` do
  /// cadastro de produtos com "There should be exactly one item with
  /// [DropdownButton]'s value". Retorna true se a lista foi alterada.
  bool _normalizarDepartamentos() {
    final normalizados = <Departamento>[];
    final idsVistos = <String>{};
    var mudou = false;
    for (final dep in _departamentos) {
      final nome = dep.nome.trim();
      if (nome.isEmpty) {
        mudou = true;
        continue;
      }
      var id = dep.id.trim();
      if (id.isEmpty) {
        id = 'dep_${nome.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
      }
      if (!idsVistos.add(id)) {
        mudou = true;
        continue;
      }
      if (id != dep.id || nome != dep.nome) {
        mudou = true;
        normalizados.add(dep.copyWith(id: id, nome: nome));
      } else {
        normalizados.add(dep);
      }
    }
    if (mudou) {
      _departamentos
        ..clear()
        ..addAll(normalizados);
    }
    return mudou;
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

    garantirPadrao(
      Departamento(
        id: 'dep_cozinha',
        nome: 'Cozinha',
        cor: '#FF5722',
        icone: 'restaurant',
        ordem: 0,
      ),
    );
    garantirPadrao(
      Departamento(
        id: 'dep_bar',
        nome: 'Bar',
        cor: '#2196F3',
        icone: 'local_bar',
        ordem: 1,
      ),
    );
    if (mudou) {
      debugPrint(
        '>>> [DataService] ✅ Departamentos padrão garantidos para a empresa atual',
      );
    }
    return mudou;
  }

  /// Persiste a lista de departamentos na configuração da empresa atual
  /// (PostgreSQL local + Supabase).
  Future<void> _persistirDepartamentosNaEmpresa() async {
    final empresa = _empresaAtual;
    if (empresa == null) return;
    // Trava de isolamento: nunca gravar na empresa "errada" (ex.: `_empresaAtual`
    // desatualizada em relação à empresa realmente aberta).
    if (_currentEmpresaId == null || empresa.id != _currentEmpresaId) {
      debugPrint(
        '>>> [Departamentos] Persistência ignorada: empresa aberta '
        '($_currentEmpresaId) difere da empresa em memória (${empresa.id}).',
      );
      return;
    }
    if (_persistindoDepartamentos) return;
    _persistindoDepartamentos = true;
    try {
      final novasConfigs = Map<String, dynamic>.from(
        empresa.configuracoes ?? {},
      );
      novasConfigs['departamentos'] = _departamentos
          .map((d) => d.toMap())
          .toList();
      await atualizarDadosEmpresa(
        empresa.copyWith(configuracoes: novasConfigs),
      );
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao persistir departamentos na empresa: $e',
      );
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
    await _storage.salvarLista(
      chave,
      _departamentos.map((d) => d.toMap()).toList(),
    );
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
        _produtos[i] = p.copyWith(
          departamentoId: null,
          updatedAt: DateTime.now(),
        );
        mudouProdutos = true;
      }
    }
    if (mudouProdutos) {
      await _salvarTodosDados(aguardarSupabase: false, isSync: true);
    }
    final chave = _getChaveComEmpresa('departamentos');
    await _storage.salvarLista(
      chave,
      _departamentos.map((d) => d.toMap()).toList(),
    );
    await _persistirDepartamentosNaEmpresa();
    notifyListeners();
  }

  // ===========================================================================
  // ESTOQUES (Loja, Depósito… — onde a mercadoria fica)
  // ===========================================================================
  //
  // Cada produto tem um saldo POR ESTOQUE (`estoquePorEstoque`) e um estoque
  // PADRÃO (onde ele mora). A soma dos saldos é o `estoque` total — e é o total
  // que a venda baixa, como sempre. A diferença é DE ONDE sai: se o saldo não
  // estiver no estoque principal ("o meu", onde a venda acontece), o app traz o
  // que falta dos outros estoques com uma TRANSFERÊNCIA de verdade (saída na
  // origem + entrada no destino, as duas no histórico) e só depois baixa.
  //
  // A lista de estoques vive em `empresa.configuracoes['estoques']`, igual aos
  // perfis tributários e aos departamentos: vale para todos os computadores sem
  // mexer no banco.

  List<Estoque> get estoques => List.unmodifiable(_estoques);

  /// O estoque principal ("o meu"): onde a venda acontece e para onde a
  /// mercadoria é trazida quando sai de outro estoque.
  Estoque? get estoquePrincipalAtual => estoquePrincipal(_estoques);

  /// Id do estoque padrão de um produto: o que o cadastro definiu; se ele não
  /// definiu (ou o estoque foi excluído), cai no principal da empresa.
  String estoquePadraoDe(Produto produto) {
    final escolhido = estoquePorId(_estoques, produto.estoquePadraoId);
    if (escolhido != null) return escolhido.id;
    return estoquePrincipalAtual?.id ?? Estoque.loja().id;
  }

  /// Saldo de UM produto em UM estoque.
  ///
  /// Produto que ainda não foi separado por estoque (`estoquePorEstoque` vazio)
  /// tem todo o estoque no padrão dele — é o que mantém o catálogo que já
  /// existia funcionando sem nenhuma conversão.
  double saldoNoEstoque(Produto produto, String estoqueId) {
    final mapa = produto.estoquePorEstoque;
    if (mapa.isEmpty) {
      return estoquePadraoDe(produto) == estoqueId ? produto.estoque : 0.0;
    }
    return mapa[estoqueId] ?? 0.0;
  }

  /// Saldos do produto em cada estoque da empresa, com o padrão primeiro.
  List<({Estoque estoque, double saldo})> saldosDoProduto(Produto produto) {
    final padrao = estoquePadraoDe(produto);
    final ordenados = [..._estoques]
      ..sort((a, b) {
        if (a.id == padrao && b.id != padrao) return -1;
        if (b.id == padrao && a.id != padrao) return 1;
        return a.ordem.compareTo(b.ordem);
      });
    return [
      for (final e in ordenados)
        (estoque: e, saldo: saldoNoEstoque(produto, e.id)),
    ];
  }

  /// Mapa de saldos NORMALIZADO: produto sem o mapa ganha um com todo o estoque
  /// no estoque padrão dele (o total não muda em nenhum caso).
  Map<String, double> _mapaEstoquesNormalizado(Produto produto) {
    final mapa = Map<String, double>.from(produto.estoquePorEstoque);
    if (mapa.isEmpty && produto.estoque != 0) {
      mapa[estoquePadraoDe(produto)] = produto.estoque;
    }
    return mapa;
  }

  // ── RESERVA DE ESTOQUE EM PEDIDOS DE VENDA ──────────────────────────────
  //
  // Com a configuração `empresa.configuracoes['reservar_estoque_pedidos']`
  // ligada, todo pedido SALVO que ainda esteja em aberto (Pendente / Em
  // Andamento / Parcialmente Pago) segura a quantidade dos seus produtos: a
  // unidade prometida não fica mais disponível para outro pedido. Quando o
  // pedido é Pago/Concluído a baixa real acontece (fluxo normal) e a reserva
  // some sozinha; se for Cancelado, a reserva também some. Por isso a reserva é
  // CALCULADA a partir dos pedidos em aberto — nunca fica presa nem duplicada
  // no saldo do produto.

  /// A configuração de reserva de estoque por pedidos está ligada?
  bool get reservarEstoquePedidosAtivo =>
      reservaAtivaNaConfig(_empresaAtual?.configuracoes);

  /// Leitura PURA da configuração (exposta para teste direto).
  @visibleForTesting
  static bool reservaAtivaNaConfig(Map<String, dynamic>? configuracoes) =>
      configuracoes?['reservar_estoque_pedidos'] == true;

  /// Status de pedido que ainda SEGURA estoque reservado (não pago nem
  /// cancelado). Pago/Concluído já deu baixa real; Cancelado não vale mais.
  static bool _statusReservaEstoque(String status) {
    final s = status.trim().toLowerCase();
    return s != 'pago' &&
        s != 'concluído' &&
        s != 'concluido' &&
        s != 'cancelado';
  }

  /// Núcleo PURO da reserva: soma a baixa dos itens de [produtoId] em todos os
  /// pedidos em aberto (mesma conta do débito real: forma de venda ×
  /// quantidade). Exposto para teste direto — não depende de storage/rede.
  @visibleForTesting
  static double calcularEstoqueReservado({
    required String produtoId,
    required List<Pedido> pedidos,
    required Produto? Function(String id) produtoPorId,
  }) {
    var total = 0.0;
    for (final pedido in pedidos) {
      if (!_statusReservaEstoque(pedido.status)) continue;
      for (final item in pedido.produtos) {
        if (item.id != produtoId) continue;
        final produto = produtoPorId(item.id);
        final fator = (item.quantidadeBaixa ?? 0) > 0
            ? item.quantidadeBaixa!
            : (produto?.fatorBaixaEstoque ?? 1.0);
        total += item.quantidade * fator;
      }
    }
    return total;
  }

  /// Quanto do produto está RESERVADO por pedidos de venda em aberto.
  /// Sem a configuração ligada, sempre 0 (nada muda no comportamento atual).
  double estoqueReservadoDe(String produtoId) {
    if (!reservarEstoquePedidosAtivo) return 0.0;
    return calcularEstoqueReservado(
      produtoId: produtoId,
      pedidos: _pedidos,
      produtoPorId: getProdutoById,
    );
  }

  /// Estoque DISPONÍVEL para venda: o saldo total menos o reservado por pedidos
  /// em aberto. É o número que as telas de venda devem validar/exibir.
  double estoqueDisponivelDe(Produto produto) =>
      produto.estoque - estoqueReservadoDe(produto.id);

  /// Mensagem de falta de estoque disponível para [quantidade] do produto, ou
  /// `null` quando pode vender. Só vale para produtos que controlam o próprio
  /// estoque — compostos baixam os ingredientes e produtos com
  /// `baixarEstoqueProprio = false` não entram.
  String? validarEstoqueDisponivel(Produto produto, {double quantidade = 1.0}) {
    if (!reservarEstoquePedidosAtivo) return null;
    if (!produto.baixarEstoqueProprio) return null;
    if (produto.ehComposto && produto.composicao.isNotEmpty) return null;
    final disponivel = estoqueDisponivelDe(produto);
    if (disponivel >= quantidade - 0.0001) return null;
    final reservado = estoqueReservadoDe(produto.id);
    return 'Estoque insuficiente: disponível ${_qtdTexto(disponivel)} '
        '(estoque ${_qtdTexto(produto.estoque)} − reservado '
        '${_qtdTexto(reservado)}).';
  }

  /// Liga/desliga a reserva de estoque por pedidos na configuração da empresa.
  Future<void> definirReservarEstoquePedidos(bool ativo) async {
    final empresa = _empresaAtual;
    if (empresa == null) return;
    final novasConfigs = Map<String, dynamic>.from(empresa.configuracoes ?? {});
    novasConfigs['reservar_estoque_pedidos'] = ativo;
    await atualizarDadosEmpresa(empresa.copyWith(configuracoes: novasConfigs));
    notifyListeners();
  }

  /// Planeja de ONDE tirar o que falta para o estoque de destino.
  ///
  /// Puro de propósito (não mexe em produto nem em disco) para poder ser
  /// testado direto: primeiro o estoque PADRÃO do produto, depois quem tem mais
  /// saldo. Só entram estoques com saldo positivo — nunca fica negativo daqui.
  @visibleForTesting
  static List<({String estoqueId, double quantidade})>
  planejarReposicaoDeEstoque({
    required Map<String, double> saldos,
    required String destinoId,
    required double faltando,
    String? preferidoId,
  }) {
    final plano = <({String estoqueId, double quantidade})>[];
    var resta = faltando;
    if (resta <= 0) return plano;

    final candidatos =
        saldos.entries.where((e) => e.key != destinoId && e.value > 0).toList()
          ..sort((a, b) {
            if (preferidoId != null && a.key != b.key) {
              if (a.key == preferidoId) return -1;
              if (b.key == preferidoId) return 1;
            }
            return b.value.compareTo(a.value); // quem tem mais, primeiro
          });

    for (final c in candidatos) {
      if (resta <= 0) break;
      final tira = c.value >= resta ? resta : c.value;
      plano.add((estoqueId: c.key, quantidade: tira));
      resta -= tira;
    }
    return plano;
  }

  /// Texto curto de quantidade para mensagem (1 em vez de 1,00).
  static String _qtdTexto(double v) => (v - v.roundToDouble()).abs() < 0.0005
      ? v.round().toString()
      : v.toStringAsFixed(2);

  /// Carrega os estoques da empresa a partir de
  /// `empresa.configuracoes['estoques']`. Sem nada configurado, cria Loja
  /// (principal) e Depósito para o recurso já funcionar.
  void _carregarEstoquesDaEmpresa() {
    if (_empresaAtual == null) return;
    _estoques.clear();
    final raw = _empresaAtual?.configuracoes?['estoques'];
    if (raw is List && raw.isNotEmpty) {
      for (final item in raw) {
        if (item is Map) {
          final e = Estoque.fromMap(Map<String, dynamic>.from(item));
          if (e.id.isNotEmpty && e.nome.trim().isNotEmpty) _estoques.add(e);
        }
      }
    }
    _estoques.sort((a, b) => a.ordem.compareTo(b.ordem));
    final adicionouPadrao = _criarEstoquesPadrao();
    if (adicionouPadrao) unawaited(_persistirEstoquesNaEmpresa());
    // Sempre confere o cache local por cima (última edição do usuário não some).
    unawaited(_migrarEstoquesDoCache());
    notifyListeners();
  }

  /// Recupera estoques salvos apenas no cache local (compatibilidade).
  Future<void> _migrarEstoquesDoCache() async {
    // Mesma trava dos perfis/departamentos: a empresa é fixada na entrada.
    final empresaAlvo = _currentEmpresaId;
    if (empresaAlvo == null || empresaAlvo.isEmpty) return;
    try {
      final chave = 'empresa_${empresaAlvo}_estoques';
      final cache = await _storage.carregarLista(chave);
      if (_currentEmpresaId != empresaAlvo ||
          _empresaAtual?.id != empresaAlvo) {
        debugPrint(
          '>>> [Estoques] Migração do cache descartada: a empresa aberta mudou '
          '($empresaAlvo -> $_currentEmpresaId) durante a leitura.',
        );
        return;
      }
      if (cache is List && cache.isNotEmpty) {
        var mudou = false;
        for (final item in cache) {
          if (item is! Map) continue;
          final e = Estoque.fromMap(Map<String, dynamic>.from(item));
          if (e.id.isEmpty || e.nome.trim().isEmpty) continue;
          if (!_estoques.any((x) => x.id == e.id)) {
            _estoques.add(e);
            mudou = true;
          }
        }
        if (mudou) {
          _estoques.sort((a, b) => a.ordem.compareTo(b.ordem));
          await _persistirEstoquesNaEmpresa();
        }
      }
    } catch (e) {
      debugPrint('>>> [DataService] ⚠️ Erro ao migrar estoques do cache: $e');
    }
  }

  /// Garante Loja (principal) e Depósito. Retorna true se algo foi adicionado.
  bool _criarEstoquesPadrao() {
    var mudou = false;
    void garantir(Estoque padrao) {
      if (_estoques.any(
        (e) =>
            e.id == padrao.id ||
            e.nome.trim().toLowerCase() == padrao.nome.trim().toLowerCase(),
      )) {
        return;
      }
      _estoques.add(padrao);
      mudou = true;
    }

    if (_estoques.isEmpty) garantir(Estoque.loja());
    if (!_estoques.any((e) => e.principal) && _estoques.isNotEmpty) {
      // Nunca ficar sem principal: o primeiro assume.
      _estoques[0] = _estoques[0].copyWith(principal: true);
      mudou = true;
    }
    garantir(Estoque.deposito());
    _estoques.sort((a, b) => a.ordem.compareTo(b.ordem));
    if (mudou) {
      debugPrint(
        '>>> [DataService] ✅ Estoques padrão garantidos: '
        '${_estoques.map((e) => e.nome).join(', ')}',
      );
    }
    return mudou;
  }

  /// Persiste a lista de estoques na configuração da empresa atual
  /// (PostgreSQL local + Supabase).
  Future<void> _persistirEstoquesNaEmpresa() async {
    final empresa = _empresaAtual;
    if (empresa == null) return;
    // Trava de isolamento: nunca gravar na empresa "errada".
    if (_currentEmpresaId == null || empresa.id != _currentEmpresaId) {
      debugPrint(
        '>>> [Estoques] Persistência ignorada: empresa aberta '
        '($_currentEmpresaId) difere da empresa em memória (${empresa.id}).',
      );
      return;
    }
    if (_persistindoEstoques) return;
    _persistindoEstoques = true;
    try {
      final novasConfigs = Map<String, dynamic>.from(
        empresa.configuracoes ?? {},
      );
      novasConfigs['estoques'] = _estoques.map((e) => e.toMap()).toList();
      await atualizarDadosEmpresa(
        empresa.copyWith(configuracoes: novasConfigs),
      );
    } catch (e) {
      debugPrint(
        '>>> [DataService] ⚠️ Erro ao persistir estoques na empresa: $e',
      );
    } finally {
      _persistindoEstoques = false;
    }
  }

  /// Salva (cria ou atualiza) um estoque. Só UM fica como principal.
  Future<void> salvarEstoque(Estoque estoque) async {
    final index = _estoques.indexWhere((e) => e.id == estoque.id);
    if (index >= 0) {
      _estoques[index] = estoque;
    } else {
      _estoques.add(
        estoque.copyWith(
          ordem: estoque.ordem == 0 ? _estoques.length : estoque.ordem,
        ),
      );
    }
    if (estoque.principal) {
      for (int i = 0; i < _estoques.length; i++) {
        if (_estoques[i].id != estoque.id && _estoques[i].principal) {
          _estoques[i] = _estoques[i].copyWith(principal: false);
        }
      }
    }
    _estoques.sort((a, b) => a.ordem.compareTo(b.ordem));
    final chave = _getChaveComEmpresa('estoques');
    await _storage.salvarLista(chave, _estoques.map((e) => e.toMap()).toList());
    await _persistirEstoquesNaEmpresa();
    notifyListeners();
  }

  /// Define qual estoque é o principal ("o meu").
  Future<void> definirEstoquePrincipal(String estoqueId) async {
    for (int i = 0; i < _estoques.length; i++) {
      _estoques[i] = _estoques[i].copyWith(
        principal: _estoques[i].id == estoqueId,
      );
    }
    final chave = _getChaveComEmpresa('estoques');
    await _storage.salvarLista(chave, _estoques.map((e) => e.toMap()).toList());
    await _persistirEstoquesNaEmpresa();
    notifyListeners();
  }

  /// Exclui um estoque. O que estava nele é transferido para o principal (senão
  /// o saldo do produto desapareceria) e os produtos que o tinham como padrão
  /// passam a usar o principal.
  Future<void> excluirEstoque(String estoqueId) async {
    final principal = estoquePrincipalAtual?.id;
    if (principal == null || principal == estoqueId) {
      debugPrint(
        '>>> [DataService] ⚠️ Não dá para excluir o estoque principal.',
      );
      return;
    }
    _estoques.removeWhere((e) => e.id == estoqueId);

    var mudouProdutos = false;
    for (int i = 0; i < _produtos.length; i++) {
      final p = _produtos[i];
      final saldo = p.estoquePorEstoque[estoqueId];
      final padraoEraEle = p.estoquePadraoId == estoqueId;
      if (saldo == null && !padraoEraEle) continue;

      final mapa = Map<String, double>.from(p.estoquePorEstoque)
        ..remove(estoqueId);
      if (saldo != null && saldo != 0) {
        mapa[principal] = (mapa[principal] ?? 0.0) + saldo;
      }
      _produtos[i] = p.copyWith(
        estoquePorEstoque: mapa,
        estoquePadraoId: padraoEraEle ? principal : p.estoquePadraoId,
        updatedAt: DateTime.now(),
      );
      mudouProdutos = true;
    }
    if (mudouProdutos) {
      await _salvarTodosDados(aguardarSupabase: false, isSync: true);
    }
    final chave = _getChaveComEmpresa('estoques');
    await _storage.salvarLista(chave, _estoques.map((e) => e.toMap()).toList());
    await _persistirEstoquesNaEmpresa();
    notifyListeners();
  }

  /// TRANSFERÊNCIA DE ESTOQUE: move [quantidade] de um estoque para outro do
  /// MESMO produto. O total não muda — só o lugar onde a mercadoria está.
  ///
  /// Registra as DUAS pontas no histórico (saída na origem + entrada no
  /// destino) com motivo 'transferencia', para o relatório mostrar o caminho e
  /// para a ação poder ser conferida depois.
  ///
  /// Retorna (deu certo, mensagem para a tela).
  Future<(bool, String)> transferirEstoque({
    required String produtoId,
    required String deEstoqueId,
    required String paraEstoqueId,
    required double quantidade,
    String? usuario,
    String? observacao,
    bool definirComoPadrao = false,
    bool notify = true,
  }) async {
    final index = _produtos.indexWhere((p) => p.id == produtoId);
    if (index == -1) return (false, 'Produto não encontrado');
    if (quantidade <= 0)
      return (false, 'Informe uma quantidade maior que zero');
    if (deEstoqueId == paraEstoqueId)
      return (false, 'Escolha estoques diferentes');

    final produto = _produtos[index];
    final nomeDe = nomeDoEstoque(_estoques, deEstoqueId);
    final nomePara = nomeDoEstoque(_estoques, paraEstoqueId);
    final mapa = _mapaEstoquesNormalizado(produto);
    final disponivel = mapa[deEstoqueId] ?? 0.0;

    if (disponivel <= 0) {
      return (
        false,
        'Não há nada em $nomeDe (saldo ${_qtdTexto(disponivel)}).',
      );
    }
    if (quantidade > disponivel) {
      return (
        false,
        '$nomeDe tem apenas ${_qtdTexto(disponivel)} — não dá para transferir ${_qtdTexto(quantidade)}.',
      );
    }

    mapa[deEstoqueId] = disponivel - quantidade;
    mapa[paraEstoqueId] = (mapa[paraEstoqueId] ?? 0.0) + quantidade;
    mapa.removeWhere(
      (k, v) => v == 0 && k != deEstoqueId && k != paraEstoqueId,
    );

    final agora = DateTime.now();
    final carimbo = '${agora.millisecondsSinceEpoch}_transf_$produtoId';
    final complemento = (observacao != null && observacao.trim().isNotEmpty)
        ? ' | ${observacao.trim()}'
        : '';
    final texto =
        'Transferência: $nomeDe → $nomePara (${_qtdTexto(quantidade)})$complemento';

    final saida = EstoqueHistorico(
      id: '${carimbo}_sai',
      produtoId: produtoId,
      data: agora,
      quantidade: -quantidade,
      tipo: 'saida',
      usuario: usuario,
      motivo: 'transferencia',
      observacao: texto,
    );
    final entrada = EstoqueHistorico(
      id: '${carimbo}_ent',
      produtoId: produtoId,
      data: agora,
      quantidade: quantidade,
      tipo: 'entrada',
      usuario: usuario,
      motivo: 'transferencia',
      observacao: texto,
    );

    await updateProduto(
      produto.copyWith(
        estoquePorEstoque: mapa,
        estoquePadraoId: definirComoPadrao
            ? paraEstoqueId
            : produto.estoquePadraoId,
        updatedAt: agora,
      ),
      aguardarSincronia: false,
      registrarMovimento: false,
      notify: false,
      motivoHistorico: 'transferencia',
      observacaoHistorico: texto,
      usuarioNome: usuario,
    );

    _estoqueHistorico.add(saida);
    _estoqueHistorico.add(entrada);
    _enviarMudancaSupabase(
      SupabaseService.tableEstoqueHistorico,
      saida.toMap(),
    );
    _enviarMudancaSupabase(
      SupabaseService.tableEstoqueHistorico,
      entrada.toMap(),
    );
    _marcarSujo(LocalStorageService.keyEstoqueHistorico);
    if (notify) notifyListeners();

    return (
      true,
      '${_qtdTexto(quantidade)} transferido(s) de $nomeDe para $nomePara — total do produto não mudou.',
    );
  }

  /// As transferências mais recentes (motivo 'transferencia'), mais novas antes.
  List<EstoqueHistorico> transferenciasRecentes({int limite = 20}) {
    final lista =
        _estoqueHistorico
            .where((h) => h.motivo == 'transferencia' && h.quantidade < 0)
            .toList()
          ..sort((a, b) => b.data.compareTo(a.data));
    return lista.take(limite).toList();
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

  /// Mantém a invariante "UM perfil PADRÃO por regime" na lista de perfis.
  ///
  /// Dado legado pode trazer dois PADRÃO no mesmo regime: versões anteriores
  /// forçavam `isDefault = true` no Tributado do sistema a cada carregamento,
  /// por cima do perfil que o usuário já tinha escolhido. No empate fica a
  /// escolha do usuário — o que NÃO é o Tributado do sistema —, senão o selo
  /// PADRÃO apareceria em dois cartões e o perfil aplicado aos produtos
  /// dependeria da ordem da lista.
  ///
  /// Devolve uma lista na mesma ordem; os perfis que já estavam corretos são os
  /// mesmos objetos (a comparação por identidade não é usada, mas evita
  /// reconstruir a lista à toa).
  @visibleForTesting
  static List<PerfilTributario> padroesUnicosPorRegime(
    List<PerfilTributario> perfis,
  ) {
    final resultado = List<PerfilTributario>.from(perfis);
    for (final paraSimples in const [true, false]) {
      final indicesPadrao = <int>[];
      for (int i = 0; i < resultado.length; i++) {
        final p = resultado[i];
        final temCodigoDoRegime = paraSimples
            ? (p.csosn?.trim().isNotEmpty ?? false)
            : (p.icmsCst?.trim().isNotEmpty ?? false);
        if (p.isDefault && temCodigoDoRegime) indicesPadrao.add(i);
      }
      if (indicesPadrao.length <= 1) continue;
      final idDoSistema = paraSimples
          ? 'padrao_tributado_simples'
          : 'padrao_tributado_normal';
      var manter = indicesPadrao.first;
      for (final i in indicesPadrao) {
        if (resultado[i].id != idDoSistema) {
          manter = i;
          break;
        }
      }
      for (final i in indicesPadrao) {
        if (i == manter) continue;
        resultado[i] = resultado[i].copyWith(isDefault: false);
      }
    }
    return resultado;
  }

  /// O perfil PADRÃO de um regime — é ele que os produtos SEM NENHUM imposto
  /// cadastrado recebem quando a empresa troca de regime.
  ///
  /// Prefere o perfil marcado como padrão (`isDefault` — o que aparece com o
  /// selo PADRÃO na tela de Perfis Tributários) que tenha código do regime
  /// pedido; se nenhum estiver marcado, usa o padrão do sistema pelo id.
  /// `null` quando a empresa ainda não tem o perfil padrão desse regime (aí o
  /// plano usa o padrão de fábrica, igual ao que `_criarPerfisTributariosPadrao`
  /// cria: CFOP 5102 com CSOSN 102 no Simples, CST 00 no Normal).
  @visibleForTesting
  static PerfilTributario? perfilPadraoDoRegime(
    Iterable<PerfilTributario> perfis, {
    required bool paraSimples,
  }) {
    bool temCodigoDoRegime(PerfilTributario p) => paraSimples
        ? (p.csosn?.trim().isNotEmpty ?? false)
        : (p.icmsCst?.trim().isNotEmpty ?? false);
    for (final p in perfis) {
      if (p.isDefault && temCodigoDoRegime(p)) return p;
    }
    final idPadrao = paraSimples
        ? 'padrao_tributado_simples'
        : 'padrao_tributado_normal';
    for (final p in perfis) {
      if (p.id == idPadrao) return p;
    }
    return null;
  }

  /// Padrão de fábrica do regime — espelho do perfil que
  /// `_criarPerfisTributariosPadrao` garante existir na empresa. Só é usado
  /// quando a empresa não tem nenhum perfil padrão daquele regime cadastrado.
  static PerfilTributario _perfilPadraoDeFabrica({required bool paraSimples}) {
    return paraSimples
        ? PerfilTributario(
            id: 'padrao_tributado_simples',
            nome: 'Tributado (Simples Nacional)',
            cfop: '5102',
            csosn: '102',
            isDefault: true,
          )
        : PerfilTributario(
            id: 'padrao_tributado_normal',
            nome: 'Tributado (Regime Normal)',
            cfop: '5102',
            icmsCst: '00',
            isDefault: true,
          );
  }

  /// Código fiscal preenchido ou `null` (registro antigo guarda `''`, que aqui
  /// conta como "não tem código").
  static String? _codigoOuNulo(String? valor) {
    final t = valor?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// IDs dos perfis padrão do sistema (os que aparecem com o selo PADRÃO).
  static const Set<String> _idsDosPerfisPadrao = {
    'padrao_tributado_simples',
    'padrao_nao_tributado_simples',
    'padrao_substituicao_simples',
    'padrao_tributado_normal',
    'padrao_nao_tributado_normal',
    'padrao_substituicao_normal',
  };

  /// Perfil PADRÃO que combina com um código fiscal do regime — 102/00
  /// (tributado), 400/41 (não tributado) e 500/60 (substituição).
  /// `null` quando o código não tem padrão equivalente (ex.: CSOSN 900).
  static String? _idDoPerfilPadraoParaCodigo(
    String codigo, {
    required bool paraSimples,
  }) {
    final c = codigo.trim();
    if (paraSimples) {
      switch (c) {
        case '102':
          return 'padrao_tributado_simples';
        case '400':
          return 'padrao_nao_tributado_simples';
        case '500':
          return 'padrao_substituicao_simples';
      }
      return null;
    }
    switch (c) {
      case '00':
        return 'padrao_tributado_normal';
      case '41':
        return 'padrao_nao_tributado_normal';
      case '60':
        return 'padrao_substituicao_normal';
    }
    return null;
  }

  /// O perfil PADRÃO que o produto deve passar a usar quando ele NÃO tem perfil
  /// cadastrado — escolhido pelo CÓDIGO que o produto já tem, para o perfil não
  /// reescrever o imposto do cadastro na emissão (o perfil manda mais que o
  /// código do produto).
  ///
  /// Primeiro procura um perfil padrão com exatamente esse código (cobre o
  /// padrão que o usuário customizou — ex.: tributado com CSOSN 103); depois o
  /// padrão do grupo daquele código (102/00, 400/41, 500/60).
  ///
  /// `null` quando nenhum padrão da empresa combina com o código: aí o produto
  /// fica como está (vincular um perfil que manda outro código seria reescrever
  /// o imposto que está no cadastro dele).
  @visibleForTesting
  static PerfilTributario? perfilPadraoParaCodigo(
    Iterable<PerfilTributario> perfis, {
    required bool paraSimples,
    String? csosn,
    String? cst,
  }) {
    final codigo = paraSimples ? _codigoOuNulo(csosn) : _codigoOuNulo(cst);
    if (codigo == null) return null;

    final padroes = perfis
        .where((p) => p.isDefault || _idsDosPerfisPadrao.contains(p.id))
        .toList();

    // 1. Um perfil padrão cujo próprio código é o código do produto.
    for (final p in padroes) {
      final codigoDoPerfil = paraSimples
          ? _codigoOuNulo(p.csosn)
          : _codigoOuNulo(p.icmsCst);
      if (codigoDoPerfil == codigo) return p;
    }

    // 2. O padrão do grupo daquele código, se ele existir na empresa.
    final idPadrao = _idDoPerfilPadraoParaCodigo(
      codigo,
      paraSimples: paraSimples,
    );
    if (idPadrao == null) return null;
    for (final p in perfis) {
      if (p.id == idPadrao) return p;
    }
    return null;
  }

  /// Perfil que um produto SEM perfil cadastrado deve usar.
  ///
  /// Primeiro tenta o PADRÃO que combina com o código que o produto já tem
  /// (para o vínculo não reescrever o imposto do cadastro na emissão); se o
  /// produto não tem código nenhum, usa o PADRÃO do regime. Código sem padrão
  /// equivalente (ex.: CSOSN 900) devolve `null`: melhor continuar manual do
  /// que vinculá-lo a um perfil que manda outro código.
  static PerfilTributario? perfilPadraoParaProduto(
    Iterable<PerfilTributario> perfis, {
    required bool paraSimples,
    String? csosn,
    String? cst,
  }) {
    final padraoDoCodigo = perfilPadraoParaCodigo(
      perfis,
      paraSimples: paraSimples,
      csosn: csosn,
      cst: cst,
    );
    if (padraoDoCodigo != null) return padraoDoCodigo;

    final temCodigo =
        _codigoOuNulo(csosn) != null || _codigoOuNulo(cst) != null;
    if (temCodigo) return null;

    return perfilPadraoDoRegime(perfis, paraSimples: paraSimples);
  }

  /// Devolve o produto já com o perfil PADRÃO quando ele NÃO tem perfil.
  ///
  /// Produto que já tem perfil (inclusive personalizado ou de outro regime)
  /// não é tocado: o vínculo existente manda. Produto sem código fiscal
  /// nenhum recebe também o CFOP e o CSOSN/CST do perfil; produto que já tem
  /// código recebe só o vínculo, preservando o imposto do cadastro.
  @visibleForTesting
  static Produto produtoComPerfilTributarioPadrao(
    Produto produto,
    Iterable<PerfilTributario> perfis, {
    required bool paraSimples,
  }) {
    if ((produto.perfilTributarioId ?? '').trim().isNotEmpty) return produto;

    final perfil = perfilPadraoParaProduto(
      perfis,
      paraSimples: paraSimples,
      csosn: produto.csosn,
      cst: produto.icmsCst,
    );
    if (perfil == null) return produto;

    final temCodigo =
        _codigoOuNulo(produto.csosn) != null ||
        _codigoOuNulo(produto.icmsCst) != null;
    if (temCodigo) {
      return produto.copyWith(perfilTributarioId: perfil.id);
    }

    return produto.copyWith(
      perfilTributarioId: perfil.id,
      cfop: _codigoOuNulo(produto.cfop) ??
          _codigoOuNulo(perfil.cfop) ??
          '5102',
      csosn: paraSimples
          ? (_codigoOuNulo(perfil.csosn) ?? '102')
          : produto.csosn,
      icmsCst: paraSimples
          ? produto.icmsCst
          : (_codigoOuNulo(perfil.icmsCst) ?? '00'),
    );
  }

  /// ID do perfil tributário padrão equivalente no outro regime (se existir).
  ///
  /// Só os perfis PADRÃO do sistema têm equivalente (ex.: padrao_tributado_simples
  /// <-> padrao_tributado_normal). Perfil personalizado devolve `null` de
  /// propósito: ele NÃO é desvinculado do produto — o cadastro do produto manda.
  static String? _perfilEquivalenteOutroRegime(
    String? perfilId, {
    required bool paraSimples,
  }) {
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

  /// Planeja a migração de impostos SEM gravar nada.
  ///
  /// Só entram produtos DA EMPRESA [empresaId]: a troca de regime é uma
  /// operação da empresa que está sendo editada, nunca "tudo que estiver na
  /// memória". Era exatamente aí que itens de outra empresa tinham os impostos
  /// reescritos junto (e, pior, eram gravados com a empresa aberta).
  ///
  /// Produto sem empresa carimbada (`null`) é de registro antigo/novo: entra,
  /// porque não pertence a OUTRA empresa — e o próprio banco carimba com a
  /// empresa aberta ao gravar.
  ///
  /// Devolve o plano completo, com o que ficou de fora e por quê, para a tela
  /// poder dizer exatamente o que aconteceu.
  ///
  /// REGRA DO IMPOSTO (o que a troca faz com cada produto da empresa):
  ///   1. produto que JÁ TEM imposto no cadastro (CSOSN/CST e/ou perfil) ->
  ///      o cadastro é RESPEITADO: o código continua o dele (só troca de
  ///      espécie quando o regime exige CSOSN ↔ CST) e o perfil personalizado
  ///      fica vinculado como estava (antes ele era desvinculado e o produto
  ///      perdia o imposto configurado);
  ///   2. perfil PADRÃO do regime antigo -> equivalente do regime novo;
  ///   3. produto SEM perfil cadastrado -> passa a apontar para o perfil
  ///      PADRÃO que combina com o código dele (o código do cadastro não
  ///      muda); sem código nenhum, recebe o PERFIL PADRÃO do regime novo
  ///      (vínculo + CFOP + CSOSN/CST dele). Era esta a parte que "não mudava":
  ///      o produto ganhava um código solto (102/00) sem perfil nenhum.
  ///
  /// [perfis] são os perfis da empresa (usados para ler o código do perfil que
  /// o produto referencia) e [perfilPadraoDoRegimeNovo] é o padrão do regime de
  /// destino. Sem ele, procura em [perfis]; sem nenhum, usa o padrão de fábrica.
  @visibleForTesting
  static PlanoMigracaoImpostos planejarMigracaoDeImpostos(
    Iterable<Produto> produtos, {
    required bool paraSimples,
    required String empresaId,
    Iterable<PerfilTributario> perfis = const [],
    PerfilTributario? perfilPadraoDoRegimeNovo,
  }) {
    final paraGravar = <Produto>[];
    final deOutraEmpresa = <Produto>[];
    final semCarimbo = <Produto>[];
    var convertidos = 0;
    var preenchidos = 0;
    var vinculadosAoPadrao = 0;
    var semMudanca = 0;

    final perfisDaEmpresa = perfis.toList();
    final perfilPorId = <String, PerfilTributario>{
      for (final perfil in perfisDaEmpresa)
        if (perfil.id.trim().isNotEmpty) perfil.id: perfil,
    };
    // PERFIL PADRÃO do regime NOVO: é ele que os produtos sem nenhum imposto
    // cadastrado recebem (vínculo + CFOP + CSOSN/CST do próprio perfil).
    final padrao =
        perfilPadraoDoRegimeNovo ??
        perfilPadraoDoRegime(perfisDaEmpresa, paraSimples: paraSimples) ??
        _perfilPadraoDeFabrica(paraSimples: paraSimples);
    final cfopPadrao = _codigoOuNulo(padrao.cfop) ?? '5102';

    for (final p in produtos) {
      if (produtoDeEmpresaDiferente(p.empresaId, empresaId)) {
        deOutraEmpresa.add(p);
        continue;
      }
      if ((p.empresaId ?? '').trim().isEmpty) semCarimbo.add(p);

      final perfilAtualId = (p.perfilTributarioId ?? '').trim();
      final temPerfil = perfilAtualId.isNotEmpty;
      final perfilAtual = temPerfil ? perfilPorId[perfilAtualId] : null;

      // Código fiscal que o CADASTRO do produto tem hoje: o dele ou, quando ele
      // não tem nenhum, o do perfil vinculado (o cadastro manda).
      var csosnAtual = _codigoOuNulo(p.csosn);
      var cstAtual = _codigoOuNulo(p.icmsCst);
      if (csosnAtual == null && cstAtual == null && perfilAtual != null) {
        csosnAtual = _codigoOuNulo(perfilAtual.csosn);
        cstAtual = _codigoOuNulo(perfilAtual.icmsCst);
      }
      final temCodigo = csosnAtual != null || cstAtual != null;

      // ── Código fiscal de destino ─────────────────────────────────────────
      // O Simples usa CSOSN e o Regime Normal usa CST (nunca os dois juntos).
      // O código do cadastro é PRESERVADO — ele só muda de "espécie" quando a
      // empresa troca de regime, porque o código do outro regime não existe no
      // novo (CSOSN ↔ CST).
      String? csosnDestino;
      String? cstDestino;
      if (temCodigo) {
        if (paraSimples) {
          csosnDestino = csosnAtual ?? cstParaCsosn(cstAtual!);
        } else {
          cstDestino = cstAtual ?? csosnParaCst(csosnAtual!);
        }
      }

      // ── Perfil tributário de destino ─────────────────────────────────────
      // O cadastro do produto é respeitado. As trocas de perfil são:
      //   1. perfil PADRÃO do regime antigo -> equivalente no regime novo;
      //   2. produto SEM NENHUM imposto cadastrado -> ganha o PERFIL PADRÃO do
      //      regime novo (com o CFOP e o código dele);
      //   3. produto sem PERFIL, mas com código próprio -> passa a usar o perfil
      //      PADRÃO que combina com o código dele (o código não se altera).
      // Perfil PERSONALIZADO permanece vinculado exatamente como estava.
      final semNenhumImposto = !temPerfil && !temCodigo;
      final semPerfilComCodigo = !temPerfil && temCodigo;
      String? perfilDestinoId;
      if (semNenhumImposto) {
        perfilDestinoId = padrao.id;
        if (paraSimples) {
          csosnDestino = _codigoOuNulo(padrao.csosn) ?? '102';
        } else {
          cstDestino = _codigoOuNulo(padrao.icmsCst) ?? '00';
        }
      } else if (semPerfilComCodigo) {
        // Sem perfil cadastrado: o produto passa a usar o perfil PADRÃO do
        // código que ele tem (nunca um padrão que manda outro código — isso
        // reescreveria o imposto do cadastro na emissão).
        perfilDestinoId = perfilPadraoParaCodigo(
          perfisDaEmpresa,
          paraSimples: paraSimples,
          csosn: csosnDestino,
          cst: cstDestino,
        )?.id;
      } else {
        perfilDestinoId =
            _perfilEquivalenteOutroRegime(
              perfilAtualId,
              paraSimples: paraSimples,
            ) ??
            perfilAtualId;
      }

      final mudou =
          cstDestino != _codigoOuNulo(p.icmsCst) ||
          csosnDestino != _codigoOuNulo(p.csosn) ||
          (perfilDestinoId ?? '') != perfilAtualId;
      if (!mudou) {
        semMudanca++;
        continue;
      }

      // Preserva o CFOP do produto (ex: 5405 ST, 5202 devolução); sem CFOP
      // próprio, usa o do perfil de destino (o padrão é 5102, venda interna).
      final perfilDestino = perfilDestinoId == null
          ? null
          : perfilPorId[perfilDestinoId];
      final cfopDestino =
          _codigoOuNulo(p.cfop) ??
          _codigoOuNulo(perfilDestino?.cfop) ??
          cfopPadrao;

      if (semNenhumImposto) {
        preenchidos++; // sem imposto nenhum: ganha o PERFIL PADRÃO do regime novo
      } else {
        convertidos++; // tinha imposto: o cadastro é preservado (e convertido se preciso)
        if (semPerfilComCodigo && perfilDestinoId != null) {
          vinculadosAoPadrao++; // não tinha perfil: passa a usar o padrão do código
        }
      }

      // ATENÇÃO ao `limpar...`: o produto tem que sair com UM código só. O
      // código do regime antigo precisa ser APAGADO (o `null` num `copyWith`
      // comum significa "não mexer", então a troca de regime deixava o produto
      // com CSOSN e CST ao mesmo tempo — foi o que apareceu no catálogo).
      paraGravar.add(
        p.copyWith(
          icmsCst: cstDestino,
          csosn: csosnDestino,
          limparIcmsCst: cstDestino == null,
          limparCsosn: csosnDestino == null,
          cfop: cfopDestino,
          perfilTributarioId: perfilDestinoId,
          updatedAt: DateTime.now(),
        ),
      );
    }

    return PlanoMigracaoImpostos(
      paraGravar: paraGravar,
      deOutraEmpresa: deOutraEmpresa,
      semCarimbo: semCarimbo,
      perfilPadraoDoRegimeNovo: padrao,
      convertidos: convertidos,
      preenchidos: preenchidos,
      vinculadosAoPadrao: vinculadosAoPadrao,
      semMudanca: semMudanca,
    );
  }

  /// Planeja a troca de regime a partir do estado ATUAL da empresa — mesmos
  /// produtos e mesmos perfis que a gravação vai usar.
  ///
  /// A tela mostra este plano e [migrarImpostosProdutosPorRegime] executa ESTE
  /// mesmo plano: o que o usuário confirma é exatamente o que é gravado.
  PlanoMigracaoImpostos planejarTrocaDeRegime({
    required bool paraSimples,
    required String empresaId,
  }) {
    final perfis = List<PerfilTributario>.from(_perfisTributarios);
    return planejarMigracaoDeImpostos(
      List<Produto>.from(_produtos),
      paraSimples: paraSimples,
      empresaId: empresaId,
      perfis: perfis,
      perfilPadraoDoRegimeNovo: perfilPadraoDoRegime(
        perfis,
        paraSimples: paraSimples,
      ),
    );
  }

  /// Migra os impostos dos produtos DA EMPRESA [empresaId] para o regime novo.
  ///
  /// - `paraSimples == true`  -> CRT 1/2: cada produto passa a ter CSOSN (o do
  ///   cadastro, ou o equivalente do CST, ou o do perfil padrão).
  /// - `paraSimples == false` -> CRT 3 (Regime Normal): cada produto passa a ter
  ///   CST (o do cadastro, ou o equivalente do CSOSN, ou o do perfil padrão).
  ///
  /// O perfil do produto é RESPEITADO (personalizado continua vinculado); só o
  /// perfil PADRÃO do regime antigo é trocado pelo equivalente no novo. Produto
  /// SEM nenhum imposto cadastrado recebe o PERFIL PADRÃO do regime novo.
  /// NUNCA toca em produto de outra empresa (isso já aconteceu: a troca de regime
  /// reescreveu o catálogo inteiro que estava em memória, de qualquer empresa).
  Future<ResultadoMigracaoImpostos> migrarImpostosProdutosPorRegime({
    required bool paraSimples,
    required String empresaId,
  }) async {
    final plano = planejarTrocaDeRegime(
      paraSimples: paraSimples,
      empresaId: empresaId,
    );

    var gravados = 0;
    if (plano.paraGravar.isNotEmpty) {
      // 1. Memória: aplica os produtos migrados de uma vez (a tela já reflete
      //    o resultado assim que o aviso aparece).
      final mapas = <Map<String, dynamic>>[];
      for (final migrado in plano.paraGravar) {
        mapas.add(migrado.toMap());
        final index = _produtos.indexWhere((p) => p.id == migrado.id);
        if (index != -1) {
          _produtos[index] = migrado;
        } else {
          _produtos.add(migrado);
        }
        gravados++;
      }

      // 2. PostgreSQL local: UM lote para o catálogo todo. Antes era um
      //    `updateProduto` por produto (milhares de idas ao banco num catálogo
      //    grande): o processo arrastava por minutos e, se a tela recarregasse
      //    no meio, parecia que nada tinha mudado. A empresa do produto vai
      //    junto no mapa, então a trava do banco continua recusando qualquer
      //    gravação cruzada em vez de carimbar a empresa aberta.
      try {
        await DatabaseService().adicionarProdutosLote(mapas);
        debugPrint(
          '>>> [DataService] 💾 Migração de imposto gravada em bloco: '
          '${mapas.length} produto(s).',
        );
      } catch (e) {
        debugPrint('>>> [DataService] ❌ Erro ao gravar o lote da migração: $e');
        rethrow;
      }

      // 3. Nuvem: em BLOCOS de 100, em segundo plano. Um upsert por produto
      //    (como era antes) significava milhares de requisições seguidas num
      //    catálogo grande.
      if (SupabaseService.isAvailable) {
        unawaited(_enviarBlocosParaNuvem(SupabaseService.tableProdutos, mapas));
      }

      notifyListeners();
    }
    return ResultadoMigracaoImpostos(
      gravados: gravados,
      convertidos: plano.convertidos,
      preenchidos: plano.preenchidos,
      vinculadosAoPadrao: plano.vinculadosAoPadrao,
      semMudanca: plano.semMudanca,
      deOutraEmpresa: plano.deOutraEmpresa.length,
      semCarimbo: plano.semCarimbo.length,
    );
  }

  /// Aplica AGORA o imposto do regime ATUAL em todos os produtos da empresa.
  ///
  /// Mesma regra da troca de regime, mas sem trocar de regime: serve para
  /// consertar o catálogo de quem já mudou de regime antes desta regra existir
  /// (produto sem perfil ficava sem imposto nenhum e o perfil padrão nunca
  /// aparecia). Produto sem perfil passa a usar o perfil PADRÃO do regime pelo
  /// código que ele tem; produto sem imposto nenhum ganha o perfil padrão.
  Future<ResultadoMigracaoImpostos> corrigirImpostosDosProdutos({
    required String empresaId,
  }) {
    return migrarImpostosProdutosPorRegime(
      paraSimples: empresaRegimeSimples,
      empresaId: empresaId,
    );
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
      _trocasDevolucoes[index] = troca.copyWith(status: 'cancelada');
      notifyListeners();
    }
  }
}
